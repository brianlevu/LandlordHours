import Foundation
import SwiftUI
import AuthenticationServices

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

    // Data persistence (user-scoped)
    private var propertiesKey: String { UserScope.key("LandlordHours.properties") }
    private var entriesKey: String { UserScope.key("LandlordHours.entries") }
    private var timerKey: String { UserScope.key("LandlordHours.timer") }

    init() {
        loadData()
        loadTimerState()
        checkSignInState()
        syncService.delegate = self
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
        // Note: per-user data stays in UserDefaults under scoped keys (u.<userId>.*)

        // Reset in-memory state
        properties = []
        timeEntries = []
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        activeCelebration = nil
        isSignedIn = false
        userName = ""

        // Reset singleton managers in memory
        SubscriptionManager.shared.resetForSignOut()
        GoalManager.shared.resetForSignOut()
        CategoryManager.shared.resetForSignOut()
        TaxProfileManager.shared.resetForSignOut()
        MilestoneTracker.shared.reload()
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
    
    func deleteTimeEntry(_ entry: TimeEntry) {
        timeEntries.removeAll { $0.id == entry.id }
        saveData()
        Task { await syncService.deleteEntryFromCloud(entry) }
    }
    
    // MARK: - Timer Functions
    func startTimer(propertyId: UUID, category: ActivityCategory) {
        isTimerRunning = true
        timerStartTime = Date()
        timerPropertyId = propertyId
        timerCategory = category
        saveTimerState()
    }
    
    func stopTimer(participant: Participant, notes: String = "") {
        guard isTimerRunning,
              let startTime = timerStartTime,
              let propertyId = timerPropertyId else { return }
        
        let hours = Date().timeIntervalSince(startTime) / 3600.0
        
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
        saveTimerState()
    }
    
    func cancelTimer() {
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        saveTimerState()
    }
    
    var timerElapsedTime: TimeInterval {
        guard let startTime = timerStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // MARK: - Milestone Celebrations

    func triggerCelebration(_ type: CelebrationType) {
        guard !suppressCelebrations else { return }
        let year = Calendar.current.component(.year, from: Date())
        let tracker = MilestoneTracker.shared
        guard tracker.shouldCelebrate(type, year: year) else { return }
        tracker.markCelebrated(type, year: year)
        activeCelebration = type
    }

    private func checkHourMilestones() {
        let year = Calendar.current.component(.year, from: Date())
        let total = totalHoursAllParticipants(year: year)
        let goalType = GoalManager.shared.globalGoalType
        let target = goalType.hoursRequired

        // Check goal met first (highest priority)
        if total >= target {
            triggerCelebration(.goalMet)
            return
        }

        // Check hour milestones: 10, 50, 100, 250, 500
        let milestones: [Int] = [500, 250, 100, 50, 10]
        for milestone in milestones {
            if total >= Double(milestone) {
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
        let hours = totalHoursForParticipant(participant, year: year)
        return min(hours / REPSRequirements.annualHourThreshold, 1.0)
    }
    
    func meets50PercentRule(year: Int) -> Bool {
        let selfHours = totalHoursForParticipant(.selfParticipant, year: year)
        let spouseHours = totalHoursForParticipant(.spouse, year: year)
        let totalHours = selfHours + spouseHours
        
        guard totalHours > 0 else { return false }
        
        let selfPercentage = selfHours / totalHours
        let spousePercentage = spouseHours / totalHours
        
        return selfPercentage <= REPSRequirements.workingTimePercentage || 
               spousePercentage <= REPSRequirements.workingTimePercentage
    }
    
    // MARK: - Persistence
    private func saveData() {
        if let propertiesData = try? JSONEncoder().encode(properties) {
            UserDefaults.standard.set(propertiesData, forKey: propertiesKey)
        }
        if let entriesData = try? JSONEncoder().encode(timeEntries) {
            UserDefaults.standard.set(entriesData, forKey: entriesKey)
        }
        // Trigger debounced cloud push
        syncService.schedulePush()
    }
    
    private func loadData() {
        if let propertiesData = UserDefaults.standard.data(forKey: propertiesKey),
           let decoded = try? JSONDecoder().decode([RentalProperty].self, from: propertiesData) {
            properties = decoded
        }
        if let entriesData = UserDefaults.standard.data(forKey: entriesKey),
           let decoded = try? JSONDecoder().decode([TimeEntry].self, from: entriesData) {
            timeEntries = decoded
        }
    }
    
    private func saveTimerState() {
        if let startTime = timerStartTime {
            UserDefaults.standard.set(startTime, forKey: UserScope.key("timerStartTime"))
        }
        UserDefaults.standard.set(isTimerRunning, forKey: timerKey)
        if let propertyId = timerPropertyId {
            UserDefaults.standard.set(propertyId.uuidString, forKey: UserScope.key("timerPropertyId"))
        }
    }

    private func loadTimerState() {
        isTimerRunning = UserDefaults.standard.bool(forKey: timerKey)
        if let startTime = UserDefaults.standard.object(forKey: UserScope.key("timerStartTime")) as? Date {
            timerStartTime = startTime
        }
        if let propertyIdStr = UserDefaults.standard.string(forKey: UserScope.key("timerPropertyId")),
           let propertyId = UUID(uuidString: propertyIdStr) {
            timerPropertyId = propertyId
        }
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
}
