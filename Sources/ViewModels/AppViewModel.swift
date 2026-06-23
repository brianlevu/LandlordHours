import Foundation
import SwiftUI
import AuthenticationServices
import WidgetKit
import ActivityKit

// MARK: - Per-User Key Scoping

/// Scopes UserDefaults keys to the current signed-in user.
/// Auth keys (appleUserId, emailUserId, etc.) remain unscoped.
enum UserScope {
    /// Current userId, read directly from UserDefaults auth keys
    static var userId: String? {
        UserDefaults.standard.string(forKey: "appleUserId")
        ?? UserDefaults.standard.string(forKey: "emailUserId")
    }

    /// Returns a user-scoped key. Falls back to unscoped if no user signed in.
    static func key(_ base: String) -> String {
        guard let id = userId else { return base }
        return "u.\(id).\(base)"
    }

    /// Returns the scoped key for a known userId. Used during account deletion
    /// after capturing the account id but before clearing auth keys.
    static func key(_ base: String, userId: String?) -> String {
        guard let userId else { return base }
        return "u.\(userId).\(base)"
    }
}

@MainActor
class AppViewModel: ObservableObject {
    @Published var properties: [RentalProperty] = []
    @Published var timeEntries: [TimeEntry] = []
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @Published var isInitializing = true
    @Published var isSignedIn = false
    @Published var userName: String = ""

    // CloudKit sync service
    let syncService = CloudKitSyncService()
    var iCloudSynced: Bool { syncService.accountAvailable }
    var lastSyncDate: Date? { syncService.lastSyncDate }

    // Celebration state
    @Published var activeCelebration: CelebrationType?
    var suppressCelebrations = false

    // Timer state
    @Published var isTimerRunning = false
    @Published var timerStartTime: Date?
    @Published var timerPropertyId: UUID?
    @Published var timerCategory: ActivityCategory = .repairs
    @Published var staleTimerRecovery: StaleTimerRecovery?

    // Data persistence (user-scoped)
    private var propertiesKey: String { UserScope.key("LandlordHours.properties") }
    private var entriesKey: String { UserScope.key("LandlordHours.entries") }
    private var timerKey: String { UserScope.key("LandlordHours.timer") }
    private var staleTimerRecoveryKey: String { UserScope.key("LandlordHours.staleTimerRecovery") }

    init() {
        checkSignInState()
#if DEBUG
        applyLaunchMockScenarioIfNeeded()
#endif
        if UserScope.userId != nil {
            migrateUnscopedLegacyData()
            loadData()
            loadTimerState()
            refreshWidgetSnapshot()
        }
        syncService.delegate = self

        // Trigger cloud sync when tax profile or goals change
        TaxProfileManager.shared.onDidChange = { [weak self] in
            self?.syncService.schedulePush()
        }
        GoalManager.shared.onDidChange = { [weak self] in
            self?.refreshWidgetSnapshot()
            self?.syncService.schedulePush()
        }
        // Show branded splash screen for 1.5s, then animate into the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.4)) {
                self.isInitializing = false
            }
        }
        // Start CloudKit sync after splash if signed in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.isSignedIn {
                Task { await self.syncService.start() }
            }
        }
    }
    
    func checkSignInState() {
        if UserDefaults.standard.string(forKey: "appleUserId") != nil {
            isSignedIn = true
            userName = UserDefaults.standard.string(forKey: "appleUserName") ?? "User"
        } else if UserDefaults.standard.string(forKey: "emailUserId") != nil {
            isSignedIn = true
            userName = UserDefaults.standard.string(forKey: "emailUserName") ?? "User"
        }
    }

    func signIn() {
        isSignedIn = true
        // Clear in-memory state from any previous user before loading new user's data.
        // This prevents stale data from leaking if a CloudKit sync fires during the transition.
        properties = []
        timeEntries = []
        // Migrate legacy unscoped data to this user's scoped keys (one-time)
        migrateUnscopedLegacyData()
        // Load user-scoped data (UserScope.userId is now set via auth keys)
        loadData()
        loadTimerState()
        // Reload all singleton managers for this user
        SubscriptionManager.shared.reload()
        GoalManager.shared.loadGoals()
        CategoryManager.shared.loadCategories()
        TaxProfileManager.shared.reload()
        MilestoneTracker.shared.reload()

        if let name = UserDefaults.standard.string(forKey: "appleUserName"), !name.isEmpty {
            userName = name
        } else if let name = UserDefaults.standard.string(forKey: "emailUserName"), !name.isEmpty {
            userName = name
        } else {
            userName = "User"
        }

        // Start CloudKit sync
        Task { await syncService.start() }
    }

    /// Call when a new account is created (not for returning sign-in).
    func signUp() {
        // New user — delete any stale unscoped data so it doesn't leak
        Self.clearUnscopedLegacyData()
        // Clear onboarding flag so new user sees onboarding flow
        UserDefaults.standard.removeObject(forKey: UserScope.key("hasCompletedOnboarding"))
        signIn()
    }

    func signOut() {
        // Stop CloudKit sync
        syncService.stop()

        // Clear auth keys (unscoped — shared on device)
        UserDefaults.standard.removeObject(forKey: "appleUserId")
        UserDefaults.standard.removeObject(forKey: "appleUserName")
        UserDefaults.standard.removeObject(forKey: "appleUserEmail")
        UserDefaults.standard.removeObject(forKey: "emailUserId")
        UserDefaults.standard.removeObject(forKey: "emailUserName")
        UserDefaults.standard.removeObject(forKey: "emailUserEmail")
        UserDefaults.standard.removeObject(forKey: "loginType")
        // Clear any stale unscoped legacy data to prevent leaking to next user
        Self.clearUnscopedLegacyData()
        // Note: per-user data stays in UserDefaults under scoped keys (u.<userId>.*)

        // Cancel any running timer and clear persisted timer state
        endTimerLiveActivity(propertyId: timerPropertyId, category: timerCategory, startDate: timerStartTime, needsReview: false)
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        saveTimerState()

        // Reset in-memory state
        properties = []
        timeEntries = []
        activeCelebration = nil
        isSignedIn = false
        userName = ""
        EngagementWidgetSnapshotStore.save(.empty)
        WidgetCenter.shared.reloadTimelines(ofKind: EngagementWidgetSnapshotStore.widgetKind)

        // Reset singleton managers in memory
        SubscriptionManager.shared.resetForSignOut()
        GoalManager.shared.resetForSignOut()
        CategoryManager.shared.resetForSignOut()
        TaxProfileManager.shared.resetForSignOut()
        MilestoneTracker.shared.reload()
    }

    func deleteAccountAndData() async throws {
        guard let userId = UserScope.userId else {
            signOut()
            return
        }

        syncService.stop()
        if syncService.accountAvailable {
            try await syncService.deleteCurrentUserRecords(
                properties: properties,
                entries: timeEntries,
                categories: CategoryManager.shared.customCategories,
                userId: userId
            )
        } else {
            await syncService.checkAccountStatus()
            if syncService.accountAvailable {
                try await syncService.deleteCurrentUserRecords(
                    properties: properties,
                    entries: timeEntries,
                    categories: CategoryManager.shared.customCategories,
                    userId: userId
                )
            }
        }

        Self.clearScopedAccountData(for: userId)

        properties = []
        timeEntries = []
        activeCelebration = nil
        endTimerLiveActivity(propertyId: timerPropertyId, category: timerCategory, startDate: timerStartTime, needsReview: false)
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil

        signOut()
    }

    func resetCurrentUserLocalData() {
        syncService.stop()

        properties = []
        timeEntries = []
        activeCelebration = nil
        endTimerLiveActivity(propertyId: timerPropertyId, category: timerCategory, startDate: timerStartTime, needsReview: false)
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        timerCategory = .repairs
        staleTimerRecovery = nil
        EngagementWidgetSnapshotStore.save(.empty)
        WidgetCenter.shared.reloadTimelines(ofKind: EngagementWidgetSnapshotStore.widgetKind)

        saveTimerState()
        clearStaleTimerRecovery()

        let defaults = UserDefaults.standard
        let localDataKeys = [
            "LandlordHours.properties",
            "LandlordHours.entries",
            "LandlordHours.timer",
            "timerStartTime",
            "timerPropertyId",
            "timerCategory",
            "LandlordHours.staleTimerRecovery",
            "LandlordHours.stoppedTimerDraft",
            "LandlordHours.celebratedMilestones",
            "hasCompletedOnboarding",
            GuidedOnboardingStore.completedKey,
            GuidedOnboardingStore.skippedKey,
            "globalGoalType",
            "propertyGoals",
            "customCategories",
            "selectedTaxYear",
            "lastLogDate",
            "smartRemindersEnabled",
            "iCloudBackupEnabled",
            "cloudkit.changeToken",
            "cloudkit.zoneChangeToken",
            "cloudkit.zoneCreated",
            "cloudkit.subscriptionCreated",
            "cloudkit.migrationDone",
            "LandlordHours.taxProfile.filingStatus",
            "LandlordHours.taxProfile.spouseTracking",
            "LandlordHours.taxProfile.taxYear",
            "LandlordHours.taxProfile.groupingElection",
            "LandlordHours.taxProfile.nonREWorkHours"
        ]

        for key in Set(localDataKeys) {
            defaults.removeObject(forKey: UserScope.key(key))
        }

        GoalManager.shared.resetForDataReset()
        CategoryManager.shared.resetForDataReset()
        TaxProfileManager.shared.resetForDataReset()
        MilestoneTracker.shared.reload()
        SubscriptionManager.shared.reload()
        defaults.synchronize()

        Task { await syncService.start() }
    }

    // MARK: - Legacy Data Migration

    /// Unscoped keys from before the UserScope system was added.
    /// These must be migrated once, then deleted.
    private static let unscopedLegacyKeys = [
        "LandlordHours.properties",
        "LandlordHours.entries",
        "LandlordHours.timer",
        "LandlordHours.celebratedMilestones",
        "hasCompletedOnboarding",
        "isProUser",
        "hasPurchasedPro",
        "trialStartDate",
        "globalGoalType",
        "propertyGoals",
        "iCloudBackupEnabled",
        "profileImageData",
        GuidedOnboardingStore.completedKey,
        GuidedOnboardingStore.skippedKey,
        "LandlordHours.taxProfile.filingStatus",
        "LandlordHours.taxProfile.spouseTracking",
        "LandlordHours.taxProfile.taxYear",
        "LandlordHours.taxProfile.groupingElection",
        "LandlordHours.taxProfile.nonREWorkHours",
    ]

    /// One-time migration: copies unscoped data into the current user's scoped keys,
    /// then deletes the unscoped keys so they can't leak to other users.
    private func migrateUnscopedLegacyData() {
        let migrationKey = UserScope.key("legacyDataMigrated")
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        guard UserScope.userId != nil else { return }

        let defaults = UserDefaults.standard
        for baseKey in Self.unscopedLegacyKeys {
            let scopedKey = UserScope.key(baseKey)
            // Only migrate if unscoped data exists AND scoped version doesn't
            if defaults.object(forKey: baseKey) != nil && defaults.object(forKey: scopedKey) == nil {
                defaults.set(defaults.object(forKey: baseKey), forKey: scopedKey)
            }
        }

        // Mark migration as done for this user
        defaults.set(true, forKey: migrationKey)

        // Delete all unscoped legacy keys
        Self.clearUnscopedLegacyData()
    }

    /// Delete all unscoped legacy data keys. Safe to call multiple times.
    static func clearUnscopedLegacyData() {
        let defaults = UserDefaults.standard
        for key in unscopedLegacyKeys {
            defaults.removeObject(forKey: key)
        }
    }

    static func clearScopedAccountData(for userId: String) {
        let defaults = UserDefaults.standard
        let taxProfileFields = [
            "filingStatus",
            "spouseTracking",
            "taxYear",
            "groupingElection",
            "nonREWorkHours"
        ]
        let baseKeys = unscopedLegacyKeys + [
            "legacyDataMigrated",
            "timerStartTime",
            "timerPropertyId",
            "timerCategory",
            "LandlordHours.staleTimerRecovery",
            "LandlordHours.stoppedTimerDraft",
            "customCategories",
            "selectedTaxYear",
            "lastLogDate",
            "smartRemindersEnabled",
            "cloudkit.changeToken",
            "cloudkit.zoneChangeToken",
            "cloudkit.zoneCreated",
            "cloudkit.subscriptionCreated",
            "cloudkit.migrationDone",
            GuidedOnboardingStore.completedKey,
            GuidedOnboardingStore.skippedKey
        ] + taxProfileFields.map { "LandlordHours.taxProfile.\($0)" }

        for key in Set(baseKeys) {
            defaults.removeObject(forKey: UserScope.key(key, userId: userId))
        }
    }
    
    // MARK: - Sync Now (manual trigger for Settings)
    func syncNow() {
        Task {
            await syncService.pushAll()
            await syncService.pullChanges()
        }
    }

    // MARK: - Subscription Features
    func canAddProperty() -> Bool {
        if SubscriptionManager.shared.isPro { return true }
        return properties.count < 1
    }
    
    func canAddTimeEntry() -> Bool {
        return true // Open for all users
    }

    func canAttachPhotos() -> Bool {
        return true // Open for all users
    }
    
    func canExportPDF() -> Bool {
        return SubscriptionManager.shared.isPro
    }
    
    func getUpgradeMessage() -> String {
        if !canAddProperty() {
            return "Upgrade to Pro to add unlimited properties"
        }
        if !canAddTimeEntry() {
            return "Upgrade to Pro for unlimited time entries"
        }
        return "Upgrade to Pro for unlimited access"
    }
    
    // MARK: - Property Management
    func addProperty(name: String, address: String, type: PropertyType) {
        let property = RentalProperty(name: name, address: address, propertyType: type)
        properties.append(property)
        saveData()
        triggerCelebration(.propertyAdded)
    }
    
    func updateProperty(_ property: RentalProperty) {
        if let index = properties.firstIndex(where: { $0.id == property.id }) {
            var updated = property
            updated.modifiedAt = Date()
            properties[index] = updated
            saveData()
        }
    }

    func deleteProperty(_ property: RentalProperty) {
        // Stop timer if it's running for this property
        if isTimerRunning && timerPropertyId == property.id {
            cancelTimer()
        }
        properties.removeAll { $0.id == property.id }
        timeEntries.removeAll { $0.propertyId == property.id }
        saveData()
        Task { await syncService.deletePropertyFromCloud(property) }
    }
    
    // MARK: - Time Entry Management
    func addTimeEntry(
        propertyId: UUID,
        participant: Participant,
        category: ActivityCategory,
        hours: Double,
        date: Date,
        notes: String,
        attachments: [TimeAttachment] = []
    ) {
        let entry = TimeEntry(
            propertyId: propertyId,
            participant: participant,
            category: category,
            hours: hours,
            date: date,
            notes: notes,
            attachments: attachments
        )
        timeEntries.append(entry)
        saveData()
        checkHourMilestones()
    }
    
    func updateTimeEntry(_ entry: TimeEntry) {
        if let index = timeEntries.firstIndex(where: { $0.id == entry.id }) {
            timeEntries[index] = entry
            saveData()
        }
    }

    func deleteTimeEntry(_ entry: TimeEntry) {
        timeEntries.removeAll { $0.id == entry.id }
        saveData()
        Task { await syncService.deleteEntryFromCloud(entry) }
    }

    // MARK: - Calendar Import
    func importCalendarEntries(_ detectedEntries: [DetectedCalendarEntry]) -> Int {
        guard !properties.isEmpty else { return 0 }
        let validPropertyIds = Set(properties.map(\.id))
        let selected = detectedEntries.filter { $0.isSelected }
        var importedCount = 0
        for detected in selected {
            guard let propertyId = detected.propertyId,
                  validPropertyIds.contains(propertyId) else {
                continue
            }
            if let externalId = detected.sourceExternalId,
               timeEntries.contains(where: { $0.importSource == "calendar" && $0.importExternalId == externalId }) {
                continue
            }
            if timeEntries.contains(where: { isDuplicateCalendarEntry($0, detected: detected, propertyId: propertyId) }) {
                continue
            }
            let entry = TimeEntry(
                propertyId: propertyId,
                participant: .selfParticipant,
                category: detected.category,
                hours: detected.hours,
                date: detected.eventDate,
                notes: detected.eventTitle,
                importSource: "calendar",
                importExternalId: detected.sourceExternalId,
                importCalendarId: detected.sourceCalendarId
            )
            timeEntries.append(entry)
            importedCount += 1
        }
        if importedCount > 0 {
            saveData()
            checkHourMilestones()
        }
        return importedCount
    }

    private func isDuplicateCalendarEntry(
        _ entry: TimeEntry,
        detected: DetectedCalendarEntry,
        propertyId: UUID
    ) -> Bool {
        guard entry.importSource == "calendar",
              entry.propertyId == propertyId,
              entry.category == detected.category,
              abs(entry.hours - detected.hours) < 0.01,
              abs(entry.date.timeIntervalSince(detected.eventDate)) < 60 else {
            return false
        }

        if let calendarId = detected.sourceCalendarId,
           let entryCalendarId = entry.importCalendarId,
           calendarId != entryCalendarId {
            return false
        }

        return entry.notes
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(detected.eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    // MARK: - Timer Functions
    func startTimer(propertyId: UUID, category: ActivityCategory) {
        guard !isTimerRunning else { return }
        guard properties.contains(where: { $0.id == propertyId }) else { return }
        isTimerRunning = true
        timerStartTime = Date()
        timerPropertyId = propertyId
        timerCategory = category
        saveTimerState()
        startOrUpdateTimerLiveActivity()
    }
    
    /// Set to true when `stopTimer` caps the entry at 24 hours, so the UI can warn the user.
    @Published var timerWasCapped = false

    func stopTimer(participant: Participant, notes: String = "") {
        guard isTimerRunning,
              let startTime = timerStartTime,
              let propertyId = timerPropertyId else { return }

        let rawHours = Date().timeIntervalSince(startTime) / 3600.0
        let maxHours: Double = 24
        let wasCapped = rawHours > maxHours
        let hours = min(rawHours, maxHours)

        addTimeEntry(
            propertyId: propertyId,
            participant: participant,
            category: timerCategory,
            hours: hours,
            date: startTime,
            notes: notes
        )

        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        timerWasCapped = wasCapped
        endTimerLiveActivity(propertyId: propertyId, category: timerCategory, startDate: startTime, needsReview: true)
        saveTimerState()
    }
    
    func cancelTimer() {
        let endingPropertyId = timerPropertyId
        let endingCategory = timerCategory
        let endingStartDate = timerStartTime
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        endTimerLiveActivity(propertyId: endingPropertyId, category: endingCategory, startDate: endingStartDate, needsReview: false)
        saveTimerState()
    }

    func saveRecoveredStaleTimer(hours: Double? = nil, notes: String = "Recovered from a timer that was left running.") {
        guard let recovery = staleTimerRecovery else { return }
        let cappedHours = min(max(hours ?? recovery.suggestedHours, 0.25), 24)
        addTimeEntry(
            propertyId: recovery.propertyId,
            participant: .selfParticipant,
            category: recovery.category,
            hours: cappedHours,
            date: recovery.startTime,
            notes: notes
        )
        staleTimerRecovery = nil
        clearStaleTimerRecovery()
    }

    func discardRecoveredStaleTimer() {
        staleTimerRecovery = nil
        clearStaleTimerRecovery()
    }
    
    var timerElapsedTime: TimeInterval {
        guard let startTime = timerStartTime else { return 0 }
        let elapsed = Date().timeIntervalSince(startTime)
        // Cap at 24 hours to prevent inflated entries from stale timers
        return min(elapsed, 24 * 3600)
    }
    
    // MARK: - Milestone Celebrations

    func triggerCelebration(_ type: CelebrationType) {
        guard !suppressCelebrations else { return }

        // Property added always celebrates (every new property is an achievement)
        if case .propertyAdded = type {
            activeCelebration = type
            return
        }

        let year = Calendar.current.component(.year, from: Date())
        let tracker = MilestoneTracker.shared
        guard tracker.shouldCelebrate(type, year: year) else { return }
        tracker.markCelebrated(type, year: year)
        activeCelebration = type
    }

    private func checkHourMilestones() {
        let year = Calendar.current.component(.year, from: Date())
        let goalType = GoalManager.shared.globalGoalType
        let status: (hours: Double, isMet: Bool)

        switch goalType {
        case .reps, .both:
            let reps = repsStatus(participant: .selfParticipant, year: year)
            status = (reps.realEstateHours, reps.isQualified)
        case .str:
            let material = materialParticipationOverview(year: year)
            status = (material.ownerAndSpouseHours, material.isMateriallyParticipating)
        }

        // Check goal met first (highest priority)
        if status.isMet {
            triggerCelebration(.goalMet)
            return
        }

        // Check hour milestones: 10, 50, 100, 250, 500
        let milestones: [Int] = [500, 250, 100, 50, 10]
        for milestone in milestones {
            if status.hours >= Double(milestone) {
                triggerCelebration(.hoursLogged(milestone: milestone))
                return
            }
        }
    }

    // MARK: - REPS Calculations
    func entriesForYear(_ year: Int) -> [TimeEntry] {
        let calendar = Calendar.current
        return timeEntries.filter { calendar.component(.year, from: $0.date) == year }
    }
    
    func totalHoursForParticipant(_ participant: Participant, year: Int) -> Double {
        entriesForYear(year)
            .filter { $0.participant == participant && $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
    }
    
    func totalHoursAllParticipants(year: Int) -> Double {
        entriesForYear(year)
            .filter { $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
    }
    
    func totalHoursForProperty(_ propertyId: UUID) -> Double {
        timeEntries
            .filter { $0.propertyId == propertyId && $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
    }
    
    func hoursForProperty(_ property: RentalProperty, year: Int) -> Double {
        entriesForYear(year)
            .filter { $0.propertyId == property.id && $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
    }
    
    func progressTo750Hours(participant: Participant, year: Int) -> Double {
        let hours = TaxQualificationEngine.qualifyingRealEstateHours(
            entries: timeEntries,
            participant: participant,
            year: year
        )
        return min(hours / REPSRequirements.annualHourThreshold, 1.0)
    }
    
    func meets50PercentRule(year: Int) -> Bool {
        repsStatus(participant: .selfParticipant, year: year).meetsMoreThanHalfPersonalServicesTest
    }

    func repsStatus(participant: Participant, year: Int) -> TaxQualificationEngine.REPSResult {
        TaxQualificationEngine.repsStatus(
            entries: timeEntries,
            participant: participant,
            year: year,
            nonRealEstateHours: TaxProfileManager.shared.nonREWorkHours
        )
    }

    func materialParticipationStatus(
        year: Int,
        propertyId: UUID? = nil
    ) -> TaxQualificationEngine.MaterialParticipationResult {
        TaxQualificationEngine.materialParticipationStatus(
            entries: timeEntries,
            year: year,
            propertyId: propertyId,
            groupingElection: TaxProfileManager.shared.groupingElection
        )
    }

    func materialParticipationOverview(year: Int) -> TaxQualificationEngine.MaterialParticipationResult {
        if TaxProfileManager.shared.groupingElection {
            return materialParticipationStatus(year: year)
        }

        return properties
            .map { materialParticipationStatus(year: year, propertyId: $0.id) }
            .max { $0.ownerAndSpouseHours < $1.ownerAndSpouseHours }
            ?? materialParticipationStatus(year: year, propertyId: nil)
    }
    
    // MARK: - Persistence
    private func saveData() {
        if let propertiesData = try? JSONEncoder().encode(properties) {
            UserDefaults.standard.set(propertiesData, forKey: propertiesKey)
        }
        if let entriesData = try? JSONEncoder().encode(timeEntries) {
            UserDefaults.standard.set(entriesData, forKey: entriesKey)
        }
        refreshWidgetSnapshot()
        // Trigger debounced cloud push
        syncService.schedulePush()
    }
    
    private func loadData() {
        // Always reset before loading — prevents stale data from leaking across user scopes
        properties = []
        timeEntries = []

        if let propertiesData = UserDefaults.standard.data(forKey: propertiesKey),
           let decoded = try? JSONDecoder().decode([RentalProperty].self, from: propertiesData) {
            properties = decoded
        }
        if let entriesData = UserDefaults.standard.data(forKey: entriesKey),
           let decoded = try? JSONDecoder().decode([TimeEntry].self, from: entriesData) {
            timeEntries = decoded
        }
        refreshWidgetSnapshot()
    }

    private func refreshWidgetSnapshot() {
        let now = Date()
        let taxYear = Calendar.current.component(.year, from: now)
        let widgetGoal = widgetGoalContext()
        let context = EngagementContext(
            now: now,
            taxYear: taxYear,
            properties: properties,
            timeEntries: timeEntries,
            calendarDraftCount: 0,
            isTimerRunning: isTimerRunning,
            timerStartTime: timerStartTime,
            notificationPermission: .notDetermined,
            recentDismissals: [],
            isProUser: SubscriptionManager.shared.isPro,
            targetHours: widgetGoal.targetHours
        )
        let snapshot = EngagementIntelligenceService.shared.snapshot(for: context)
        let recommendation = EngagementIntelligenceService.shared.recommendation(for: context)
        EngagementWidgetSnapshotStore.save(
            EngagementWidgetSnapshot(
                updatedAt: now,
                taxYear: taxYear,
                propertyCount: properties.count,
                yearHours: snapshot.yearHours,
                targetHours: widgetGoal.targetHours,
                targetLabel: widgetGoal.label,
                targetShortLabel: widgetGoal.shortLabel,
                requiredHoursToDate: snapshot.requiredHoursToDate,
                daysRemainingInYear: snapshot.daysRemainingInYear,
                lastLogDate: snapshot.lastLogDate,
                isTimerRunning: isTimerRunning,
                timerStartTime: timerStartTime,
                recommendationSurface: recommendation.surface,
                recommendationReason: recommendation.reason,
                recommendationDestination: recommendation.destination,
                recommendationTitle: recommendation.title,
                recommendationMessage: recommendation.message
            )
        )
        WidgetCenter.shared.reloadTimelines(ofKind: EngagementWidgetSnapshotStore.widgetKind)
    }

    private func widgetGoalContext() -> (targetHours: Double, label: String, shortLabel: String) {
        switch GoalManager.shared.globalGoalType {
        case .reps:
            return (750, "750h REPS", "750h")
        case .str:
            return (100, "100h STR", "100h")
        case .both:
            return (750, "750h REPS + STR", "750h")
        }
    }
    
    private func saveTimerState() {
        let defaults = UserDefaults.standard
        let startTimeKey = UserScope.key("timerStartTime")
        let propertyIdKey = UserScope.key("timerPropertyId")
        let categoryKey = UserScope.key("timerCategory")

        defaults.set(isTimerRunning, forKey: timerKey)

        if let startTime = timerStartTime {
            defaults.set(startTime, forKey: startTimeKey)
        } else {
            defaults.removeObject(forKey: startTimeKey)
        }

        if let propertyId = timerPropertyId {
            defaults.set(propertyId.uuidString, forKey: propertyIdKey)
        } else {
            defaults.removeObject(forKey: propertyIdKey)
        }

        if isTimerRunning {
            defaults.set(timerCategory.rawValue, forKey: categoryKey)
        } else {
            defaults.removeObject(forKey: categoryKey)
        }

        refreshWidgetSnapshot()
    }

    private func saveStaleTimerRecovery(_ recovery: StaleTimerRecovery) {
        if let data = try? JSONEncoder().encode(recovery) {
            UserDefaults.standard.set(data, forKey: staleTimerRecoveryKey)
        }
    }

    private func loadStaleTimerRecovery() {
        guard let data = UserDefaults.standard.data(forKey: staleTimerRecoveryKey),
              let recovery = try? JSONDecoder().decode(StaleTimerRecovery.self, from: data),
              properties.contains(where: { $0.id == recovery.propertyId }) else {
            clearStaleTimerRecovery()
            return
        }
        staleTimerRecovery = recovery
    }

    private func clearStaleTimerRecovery() {
        UserDefaults.standard.removeObject(forKey: staleTimerRecoveryKey)
    }

    private func loadTimerState() {
        loadStaleTimerRecovery()
        isTimerRunning = UserDefaults.standard.bool(forKey: timerKey)
        if let startTime = UserDefaults.standard.object(forKey: UserScope.key("timerStartTime")) as? Date {
            timerStartTime = startTime
        }
        if let propertyIdStr = UserDefaults.standard.string(forKey: UserScope.key("timerPropertyId")),
           let propertyId = UUID(uuidString: propertyIdStr) {
            timerPropertyId = propertyId
        }
        if let categoryRaw = UserDefaults.standard.string(forKey: UserScope.key("timerCategory")),
           let category = ActivityCategory(rawValue: categoryRaw) {
            timerCategory = category
        }
        // Auto-cancel stale timers (running for >24 hours = forgotten)
        if isTimerRunning, let start = timerStartTime,
           Date().timeIntervalSince(start) > 24 * 3600 {
            let stalePropertyId = timerPropertyId
            if let propertyId = timerPropertyId,
               properties.contains(where: { $0.id == propertyId }) {
                staleTimerRecovery = StaleTimerRecovery(
                    startTime: start,
                    propertyId: propertyId,
                    category: timerCategory,
                    elapsedHours: Date().timeIntervalSince(start) / 3600.0
                )
                if let staleTimerRecovery {
                    saveStaleTimerRecovery(staleTimerRecovery)
                }
            }
            isTimerRunning = false
            timerStartTime = nil
            timerPropertyId = nil
            endTimerLiveActivity(propertyId: stalePropertyId, category: timerCategory, startDate: start, needsReview: true)
            saveTimerState()
        } else if isTimerRunning {
            startOrUpdateTimerLiveActivity()
        }
    }

    private func startOrUpdateTimerLiveActivity() {
        guard isTimerRunning,
              let timerStartTime,
              let timerPropertyId,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = timerLiveActivityState(
            propertyId: timerPropertyId,
            category: timerCategory,
            startDate: timerStartTime,
            needsReview: false
        )

        Task {
            if let existing = Activity<LandlordHoursTimerAttributes>.activities.first {
                await existing.update(ActivityContent(state: state, staleDate: nil))
                return
            }

            do {
                _ = try Activity.request(
                    attributes: LandlordHoursTimerAttributes(timerId: timerPropertyId.uuidString),
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                #if DEBUG
                print("[LiveActivity] Could not start timer activity: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func endTimerLiveActivity(
        propertyId: UUID?,
        category: ActivityCategory,
        startDate: Date?,
        needsReview: Bool
    ) {
        guard !Activity<LandlordHoursTimerAttributes>.activities.isEmpty else { return }

        let fallbackPropertyId = propertyId ?? properties.first?.id ?? UUID()
        let state = timerLiveActivityState(
            propertyId: fallbackPropertyId,
            category: category,
            startDate: startDate ?? Date(),
            needsReview: needsReview
        )

        Task {
            for activity in Activity<LandlordHoursTimerAttributes>.activities {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
    }

    private func timerLiveActivityState(
        propertyId: UUID,
        category: ActivityCategory,
        startDate: Date,
        needsReview: Bool
    ) -> LandlordHoursTimerAttributes.ContentState {
        LandlordHoursTimerAttributes.ContentState(
            propertyName: properties.first(where: { $0.id == propertyId })?.name ?? "Rental property",
            categoryName: category.chipLabel,
            startDate: startDate,
            isReviewNeeded: needsReview
        )
    }
}

struct StaleTimerRecovery: Codable, Equatable {
    let startTime: Date
    let propertyId: UUID
    let category: ActivityCategory
    let elapsedHours: Double

    var suggestedHours: Double {
        min(max(elapsedHours, 0.25), 24)
    }
}

// MARK: - CloudKit Sync Delegate

extension AppViewModel: CloudKitSyncDelegate {

    func syncDidReceiveProperties(_ remoteProperties: [RentalProperty]) {
        for remote in remoteProperties {
            if let idx = properties.firstIndex(where: { $0.id == remote.id }) {
                // Last-write-wins: replace if remote is newer
                if remote.modifiedAt > properties[idx].modifiedAt {
                    properties[idx] = remote
                }
            } else {
                properties.append(remote)
            }
        }
        saveDataLocal()
    }

    func syncDidReceiveEntries(_ remoteEntries: [TimeEntry]) {
        for remote in remoteEntries {
            if let idx = timeEntries.firstIndex(where: { $0.id == remote.id }) {
                if remote.modifiedAt > timeEntries[idx].modifiedAt {
                    timeEntries[idx] = remote
                }
            } else {
                timeEntries.append(remote)
            }
        }
        saveDataLocal()
    }

    func syncDidDeletePropertyIds(_ ids: Set<UUID>) {
        properties.removeAll { ids.contains($0.id) }
        timeEntries.removeAll { ids.contains($0.propertyId) }
        saveDataLocal()
    }

    func syncDidDeleteEntryIds(_ ids: Set<UUID>) {
        timeEntries.removeAll { ids.contains($0.id) }
        saveDataLocal()
    }

    func syncDidReceiveCategories(_ remoteCategories: [CustomCategory]) {
        let mgr = CategoryManager.shared
        for remote in remoteCategories {
            if let idx = mgr.customCategories.firstIndex(where: { $0.id == remote.id }) {
                if remote.modifiedAt > mgr.customCategories[idx].modifiedAt {
                    mgr.customCategories[idx] = remote
                }
            } else {
                mgr.customCategories.append(remote)
            }
        }
        mgr.saveCategories()
    }

    func syncDidReceiveGoalSettings(globalGoalType: HourGoalType, propertyGoals: [PropertyGoal]) {
        let mgr = GoalManager.shared
        mgr.globalGoalType = globalGoalType
        mgr.propertyGoals = propertyGoals
        mgr.saveGoals()
    }

    func syncDidReceiveTaxProfile(_ fields: TaxProfileFields) {
        let mgr = TaxProfileManager.shared
        if let status = FilingStatus(rawValue: fields.filingStatus) {
            mgr.filingStatus = status
        }
        mgr.spouseTracking = fields.spouseTracking
        mgr.taxYear = fields.taxYear
        mgr.groupingElection = fields.groupingElection
        mgr.nonREWorkHours = fields.nonREWorkHours
    }

    /// Save to UserDefaults only (no cloud push — avoids loop when merging remote data)
    private func saveDataLocal() {
        if let propertiesData = try? JSONEncoder().encode(properties) {
            UserDefaults.standard.set(propertiesData, forKey: propertiesKey)
        }
        if let entriesData = try? JSONEncoder().encode(timeEntries) {
            UserDefaults.standard.set(entriesData, forKey: entriesKey)
        }
    }

#if DEBUG
    enum MockDataScenario: String, CaseIterable, Identifiable {
        case firstTime
        case emptyMainTabs
        case occasional
        case frequent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .firstTime: return "First-time user"
            case .emptyMainTabs: return "Empty main tabs"
            case .occasional: return "Occasional user"
            case .frequent: return "Frequent user"
            }
        }

        var subtitle: String {
            switch self {
            case .firstTime: return "Signed in, no onboarding or records"
            case .emptyMainTabs: return "Signed in, onboarding complete, no records"
            case .occasional: return "One LTR, light monthly logging"
            case .frequent: return "Three properties, spouse, calendar imports"
            }
        }

        var userName: String {
            switch self {
            case .firstTime: return "New Owner"
            case .emptyMainTabs: return "New Owner"
            case .occasional: return "Maya Chen"
            case .frequent: return "Jordan Rivera"
            }
        }
    }

    private func applyLaunchMockScenarioIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHMockScenario"),
              args.indices.contains(index + 1),
              let scenario = MockDataScenario(rawValue: args[index + 1]) else {
            return
        }
        applyMockScenario(scenario)
    }

    func applyMockScenario(_ scenario: MockDataScenario) {
        syncService.stop()
        suppressCelebrations = true

        let userId = "debug-\(scenario.rawValue)"
        Self.clearScopedAccountData(for: userId)

        let defaults = UserDefaults.standard
        defaults.set(userId, forKey: "emailUserId")
        defaults.set(Self.launchMockEmail(defaultValue: "brianlevu@gmail.com"), forKey: "emailUserEmail")
        defaults.set(Self.launchMockName(defaultValue: scenario.userName), forKey: "emailUserName")
        defaults.set(LoginType.email.rawValue, forKey: "loginType")

        isSignedIn = true
        userName = Self.launchMockName(defaultValue: scenario.userName)
        properties = []
        timeEntries = []
        activeCelebration = nil
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        staleTimerRecovery = nil

        defaults.removeObject(forKey: UserScope.key("hasCompletedOnboarding"))
        defaults.removeObject(forKey: UserScope.key("isProUser"))
        defaults.removeObject(forKey: UserScope.key("hasPurchasedPro"))
        clearStaleTimerRecovery()

        let taxProfile = TaxProfileManager.shared
        taxProfile.filingStatus = .marriedJoint
        taxProfile.spouseTracking = scenario == .frequent
        taxProfile.taxYear = Calendar.current.component(.year, from: Date())
        taxProfile.groupingElection = scenario == .frequent
        taxProfile.nonREWorkHours = scenario == .frequent ? 620 : 0

        let goalManager = GoalManager.shared
        goalManager.propertyGoals = []
        goalManager.globalGoalType = scenario == .occasional ? .str : .reps

        switch scenario {
        case .firstTime:
            break
        case .emptyMainTabs:
            defaults.set(true, forKey: UserScope.key("hasCompletedOnboarding"))
            GuidedOnboardingStore.skip()
        case .occasional:
            defaults.set(true, forKey: UserScope.key("hasCompletedOnboarding"))
            properties = Self.mockPropertiesOccasional()
            timeEntries = Self.mockEntriesOccasional(properties: properties)
        case .frequent:
            defaults.set(true, forKey: UserScope.key("hasCompletedOnboarding"))
            defaults.set(true, forKey: UserScope.key("isProUser"))
            defaults.set(true, forKey: UserScope.key("hasPurchasedPro"))
            properties = Self.mockPropertiesFrequent()
            timeEntries = Self.mockEntriesFrequent(properties: properties)
            goalManager.propertyGoals = properties.map { property in
                PropertyGoal(propertyId: property.id, goalType: property.propertyType == .str ? .str : .reps)
            }
        }

        saveDataLocal()
        goalManager.saveGoals()
        SubscriptionManager.shared.reload()
        CategoryManager.shared.loadCategories()
        MilestoneTracker.shared.reload()
        defaults.synchronize()

        suppressCelebrations = false
    }

    private static func launchMockEmail(defaultValue: String) -> String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHMockEmail"),
              args.indices.contains(index + 1),
              !args[index + 1].isEmpty else {
            return defaultValue
        }
        return args[index + 1]
    }

    private static func launchMockName(defaultValue: String) -> String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHMockName"),
              args.indices.contains(index + 1),
              !args[index + 1].isEmpty else {
            return defaultValue
        }
        return args[index + 1]
    }

    private static func mockPropertiesOccasional() -> [RentalProperty] {
        [
            mockProperty(
                id: "0D776174-6B40-4550-97D3-A45D4E0D54F8",
                name: "Oak Street Duplex",
                address: "214 Oak Street, Sacramento, CA",
                type: .ltr,
                createdDaysAgo: 220
            )
        ]
    }

    private static func mockPropertiesFrequent() -> [RentalProperty] {
        [
            mockProperty(id: "4C529168-E861-40EF-A093-8605A0C545B6", name: "Oak Street Duplex", address: "214 Oak Street, Sacramento, CA", type: .ltr, createdDaysAgo: 640),
            mockProperty(id: "3858434C-2475-4F34-BE31-89DE9154E663", name: "Lakeview Cottage", address: "78 Pine Shore Road, South Lake Tahoe, CA", type: .str, createdDaysAgo: 410),
            mockProperty(id: "E4A83DC6-3EB1-4AE0-A695-36B80492450C", name: "Mission Studio", address: "901 Valencia Street, San Francisco, CA", type: .ltr, createdDaysAgo: 130)
        ]
    }

    private static func mockProperty(id: String, name: String, address: String, type: PropertyType, createdDaysAgo: Int) -> RentalProperty {
        let createdAt = date(daysAgo: createdDaysAgo, hour: 9)
        var property = RentalProperty(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            address: address,
            propertyType: type
        )
        property.createdAt = createdAt
        property.modifiedAt = date(daysAgo: min(createdDaysAgo, 4), hour: 11)
        return property
    }

    private static func mockEntriesOccasional(properties: [RentalProperty]) -> [TimeEntry] {
        guard let property = properties.first else { return [] }
        let raw: [(Int, Double, ActivityCategory, String)] = [
            (3, 1.0, .management, "Called tenant about dishwasher issue and coordinated repair window."),
            (9, 1.5, .bookkeeping, "Reviewed rent ledger, receipts, and mileage notes."),
            (16, 2.0, .repairs, "Met handyman at the duplex and inspected the garbage disposal repair."),
            (24, 0.75, .leasing, "Answered prospective tenant questions about lease renewal options."),
            (32, 1.25, .insurance, "Reviewed policy renewal and uploaded documents for CPA records."),
            (47, 2.5, .repairs, "Replaced smoke detector batteries and checked hallway lighting."),
            (61, 1.0, .management, "Followed up on rent payment timing and vendor invoice."),
            (74, 1.5, .travel, "Drove to Oak Street for exterior inspection after storm."),
            (92, 2.0, .bookkeeping, "Prepared quarterly expense summary."),
            (118, 1.0, .legal, "Reviewed local rental ordinance update.")
        ]
        return raw.map { day, hours, category, notes in
            TimeEntry(
                propertyId: property.id,
                participant: .selfParticipant,
                category: category,
                hours: hours,
                date: date(daysAgo: day, hour: 10 + (day % 7)),
                notes: notes,
                importSource: day % 3 == 0 ? "calendar" : nil
            )
        }
    }

    private static func mockEntriesFrequent(properties: [RentalProperty]) -> [TimeEntry] {
        guard properties.count >= 3 else { return [] }
        let templates: [(ActivityCategory, Double, String)] = [
            (.management, 1.0, "Tenant messages, vendor scheduling, and owner follow-up."),
            (.repairs, 2.25, "On-site repair coordination and completion photos."),
            (.bookkeeping, 1.5, "Categorized expenses and reconciled receipts."),
            (.leasing, 1.75, "Screened applicant questions and updated listing details."),
            (.travel, 1.25, "Travel to property for inspection and lockbox check."),
            (.renovations, 3.0, "Reviewed contractor scope, materials, and punch list."),
            (.insurance, 1.0, "Prepared claim documentation and policy notes."),
            (.legal, 0.75, "Reviewed lease language and compliance notes.")
        ]

        var entries: [TimeEntry] = []
        for i in 0..<96 {
            let property = properties[i % properties.count]
            let template = templates[i % templates.count]
            let isSpouse = i % 9 == 0
            let hours = template.1 + Double((i % 4)) * 0.25
            entries.append(
                TimeEntry(
                    propertyId: property.id,
                    participant: isSpouse ? .spouse : .selfParticipant,
                    category: template.0,
                    hours: hours,
                    date: date(daysAgo: 1 + (i * 3) % 178, hour: 8 + (i % 9)),
                    notes: "\(property.name): \(template.2)",
                    importSource: i % 5 == 0 ? "calendar" : nil
                )
            )
        }

        entries.append(
            TimeEntry(
                propertyId: properties[1].id,
                participant: .selfParticipant,
                category: .investing,
                hours: 2.0,
                date: date(daysAgo: 12, hour: 14),
                notes: "Compared possible acquisition returns. Marked non-REPS so reports can verify excluded hours."
            )
        )
        return entries.sorted { $0.date > $1.date }
    }

    private static func date(daysAgo: Int, hour: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 15
        let base = Calendar.current.date(from: components) ?? Date()
        return Calendar.current.date(byAdding: .day, value: -daysAgo, to: base) ?? Date()
    }
#endif
}
