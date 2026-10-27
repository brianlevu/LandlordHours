import Foundation
import SwiftUI
import Combine
import WidgetKit
import ActivityKit
import UIKit
import os.log

// MARK: - Record-set key scoping

/// Scopes UserDefaults keys to the record set. 2.2 (package K): one record set per iCloud
/// account under the fixed `v2.` prefix once the device merge has run (`IdentityScope`); the
/// `u.<id>.` keys of 1.x / 2.0 profiles stay untouched (2.3 removes them).
enum UserScope {
    /// The scope id: the frozen storage id (`v2.storageId`), used for folder names, capture ids
    /// and notification ids. Nil only before the first 2.2 launch finished its device merge.
    static var userId: String? {
        IdentityScope.resolve(.standard).scopeId
    }

    /// A key in the live record set (`v2.<base>`).
    static func key(_ base: String) -> String {
        IdentityScope.resolve(.standard).prefix + base
    }

    /// The key for a known scope id: the live prefix for the active scope id, otherwise the
    /// legacy `u.<id>.` key (the inventory, DEBUG fixtures, tests).
    static func key(_ base: String, userId: String?) -> String {
        guard let userId else { return base }
        let resolved = IdentityScope.resolve(.standard)
        if userId == resolved.scopeId { return resolved.prefix + base }
        return "u.\(userId).\(base)"
    }
}

@MainActor
class AppViewModel: ObservableObject {
    @Published var properties: [RentalProperty] = []
    @Published var timeEntries: [TimeEntry] = [] {
        didSet { lastEntriesChangeOrigin = isApplyingRemoteChanges ? .remote : .local }
    }
    /// Where the latest change to `timeEntries` came from. Today mutes the house build (no
    /// "+Nh" beam, no haptic) only for iCloud merges, never for the user's own saves.
    enum EntriesChangeOrigin: Equatable { case local, remote }
    @Published private(set) var lastEntriesChangeOrigin: EntriesChangeOrigin = .local
    private var isApplyingRemoteChanges = false
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())
    /// WP-L: the active profile's first iCloud pull of this launch is still running, so the hours
    /// on Today may not be final. Today shows the drafting loader in the house slot and a
    /// placeholder for the number; everything else is usable. Never blocks: it ends when the
    /// initial sync ends (any outcome) or after `initialPullPlaceholderTimeout`.
    @Published private(set) var isAwaitingInitialPull = false
    /// The initial sync is still running (true past the placeholder cap). Export waits on it:
    /// a report made now could miss hours from other devices. False once it lands or fails.
    @Published private(set) var isInitialPullRunning = false
    /// The last initial sync reached iCloud's account but its pull failed. Export still works,
    /// with a note that the report may miss hours from other devices.
    @Published private(set) var initialPullFailed = false
    private var initialSyncsInFlight = 0
    static let initialPullPlaceholderTimeout: TimeInterval = 6
    private var initialPullWaitToken = UUID()
    @Published var isSignedIn = false
    @Published var userName: String = ""

    // CloudKit sync service
    let syncService = CloudKitSyncService()
    var iCloudSynced: Bool { syncService.accountAvailable }
    var lastSyncDate: Date? { syncService.lastSyncDate }

    // Celebration state
    @Published var activeCelebration: CelebrationType?
    var suppressCelebrations = false
    /// True while no scene is on screen (a notification action or intent running in the
    /// background). Milestones crossed then are queued, not lost; `AppModelHost` turns this
    /// off and presents the queue when a scene becomes active.
    var queuesCelebrations = false

    // Timer state
    @Published var isTimerRunning = false
    @Published var timerStartTime: Date?
    @Published var timerPropertyId: UUID?
    @Published var timerCategory: ActivityCategory = .repairs
    /// Timer drafts waiting for review (forgotten >24 h timers, timers paused at a profile
    /// switch). Oldest first; the Track card shows the first one, then the next.
    @Published var staleTimerRecoveries: [StaleTimerRecovery] = []
    var staleTimerRecovery: StaleTimerRecovery? {
        get { staleTimerRecoveries.first }
        set { staleTimerRecoveries = newValue.map { [$0] } ?? [] }
    }

    // Data persistence (user-scoped)
    private var propertiesKey: String { UserScope.key("LandlordHours.properties") }
    private var entriesKey: String { UserScope.key("LandlordHours.entries") }
    private var timerKey: String { UserScope.key("LandlordHours.timer") }
    /// Legacy single-draft key (≤1.1 builds before the list); migrated into the list on load.
    private var staleTimerRecoveryKey: String { UserScope.key("LandlordHours.staleTimerRecovery") }
    private var staleTimerRecoveriesKey: String { UserScope.key("LandlordHours.staleTimerRecoveries") }

    /// Package K: the identity surfaces (iCloud status, Earlier records, the two-sets question,
    /// the Welcome footer, the Today notice) and the record-set engine behind them.
    let identity = IdentityCoordinator()
    private var identityObservation: AnyCancellable?

    init() {
#if DEBUG
        // Captured upgrade fixtures and fresh-device resets are written before the merge reads them.
        IdentityFixtures.applyLaunchArguments()
        seedLegacyEmailFixtureIfNeeded()
#endif
        // 2.2: every 1.x / 2.0 state becomes one record set under `v2.` (S1–S4, before the
        // first frame). Nothing is deleted; `u.*` stays as it is.
        // The managers re-read their keys only when this launch moved the record set.
        if Self.runDeviceMerge() { reloadManagersForRecordSet() }
        checkSignInState()
#if DEBUG
        applyLaunchMockScenarioIfNeeded()
#endif
        if UserScope.userId != nil {
            loadData()
            loadTimerState()
            refreshWidgetSnapshot()
        }
        syncService.delegate = self
        var zoneSource: IdentityZoneSource = syncService
#if DEBUG
        if let fake = IdentityFixtures.fakeZoneIfRequested() { zoneSource = fake; Self.debugFakeZone = fake }
#endif
        identity.attach(source: zoneSource, live: self, sync: syncService)
        identity.hasSavedEntry = !timeEntries.isEmpty
        // Views that read `viewModel.identity` (Welcome, Today, Settings) re-render with it.
        identityObservation = identity.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        // Any successful pull clears the export sheet's "Couldn't reach iCloud" note.
        syncService.onInitialPullSucceeded = { [weak self] profileId in
            guard let self, profileId == UserScope.userId else { return }
            self.initialPullFailed = false
        }
        syncService.onIdentityChange = { [weak self] in
            guard let self else { return }
            self.reloadAfterIdentityChange()
        }

        // Settings edits made by a person are "dirty" until pushed (v4 §3.3); edits made while the
        // record set is empty are "dirty while empty" and never beat the household's settings.
        TaxProfileManager.shared.onDidChange = { [weak self] in
            guard let self else { return }
            self.markSettingsDirty(tax: true)
            self.refreshWidgetSnapshot()
            self.syncService.schedulePush()
        }
        GoalManager.shared.onDidChange = { [weak self] in
            guard let self else { return }
            self.markSettingsDirty(tax: false)
            self.refreshWidgetSnapshot()
            self.syncService.schedulePush()
        }
        if Self.isUnitTestHost {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.isSignedIn { Task { await self.syncService.start() } }
            }
        } else if isSignedIn {
            #if DEBUG
            if Self.simulatedPullState == nil { startInitialSync(showsPlaceholder: !Self.isMockLaunch) }
            #else
            startInitialSync(showsPlaceholder: !Self.isMockLaunch)
            #endif
        }
#if DEBUG
        applySimulatedPendingPullIfNeeded()
#endif
    }

#if DEBUG
    /// The in-memory zone a `-LHFakeZone` launch uses (UI tests drive "another device" through it).
    static var debugFakeZone: FakeZoneSource?
#endif

    /// S1–S4 over the standard defaults and Application Support. True when this launch merged.
    @discardableResult
    static func runDeviceMerge() -> Bool {
        var options = RecordSetMigration.DeviceOptions()
#if DEBUG
        options.crashAt = IdentityFixtures.crashAt
        if ProcessInfo.processInfo.arguments.contains("-LHBackupFails") {
            options.writeBackup = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        }
#endif
        do {
            return try RecordSetMigration.runDevicePhase(defaults: .standard, root: MigrationFiles.defaultRoot, options: options) != .alreadyMerged
        } catch {
            Self.persistenceLogger.error("Device merge stopped: \(String(describing: error), privacy: .public)")
            return true
        }
    }

    /// Every manager re-reads its keys from the record set's prefix.
    func reloadManagersForRecordSet() {
        SubscriptionManager.shared.reload()
        GoalManager.shared.loadGoals()
        CategoryManager.shared.loadCategories()
        TaxProfileManager.shared.reload()
        MilestoneTracker.shared.reload()
    }

    /// Pulls, answers and archive moves change the live set: reload what Today shows.
    func reloadAfterIdentityChange() {
        identity.hasSavedEntry = !timeEntries.isEmpty
        if rootState == .welcome { identity.noteLiveHours(timeEntries.reduce(0) { $0 + $1.hours }) }
        identity.refresh(sync: syncService)
        objectWillChange.send()
    }

    private var isApplyingRemoteSettings = false

    /// New-user onboarding began: on an empty phone its answers count as made "while empty" to
    /// the end, so a household another device wrote is never overwritten by them (package K).
    func beginOnboardingAnswers() {
        IdentityKeys.beginOnboarding(liveIsEmpty: properties.isEmpty && timeEntries.isEmpty, defaults: .standard)
    }

    /// Onboarding finished or was left: settle its answers against the household.
    func endOnboardingAnswers() {
        identity.engine?.finishOnboarding()
        identity.refresh(sync: syncService)
    }

    private func markSettingsDirty(tax: Bool) {
        guard !isApplyingRemoteSettings else { return }
        IdentityKeys.markSettingsDirty(tax: tax, liveIsEmpty: properties.isEmpty && timeEntries.isEmpty, defaults: .standard)
    }

    /// Starts the profile's initial iCloud sync. With `showsPlaceholder`, Today treats the hours
    /// as not final until the first pull ends (any outcome) or the timeout passes.
    @discardableResult
    func startInitialSync(showsPlaceholder: Bool = true) -> Task<Void, Never> {
        let token = showsPlaceholder && syncService.isCloudKitAvailable ? beginAwaitingInitialPull() : nil
        initialSyncsInFlight += 1
        isInitialPullRunning = true
        return Task { [weak self] in
            guard let self else { return }
            // Returns only after a pull for the profile active now has run (a call made while
            // another profile's pull is in flight waits for the re-run).
            await self.syncService.start()
            self.initialSyncsInFlight -= 1
            if self.initialSyncsInFlight == 0 {
                self.isInitialPullRunning = false
                self.initialPullFailed = Self.initialPullFailed(
                    accountAvailable: self.syncService.accountAvailable,
                    completedFor: self.syncService.initialSyncCompletedFor,
                    activeProfile: UserScope.userId
                )
            }
            // Ends only the wait this sync began (a newer wait belongs to a newer start).
            if let token { self.endAwaitingInitialPull(token: token) }
        }
    }

    /// Failed = iCloud was reachable as an account but this profile's pull didn't complete.
    /// No account (or no CloudKit) is not a failure: export works normally without a note.
    static func initialPullFailed(accountAvailable: Bool, completedFor: String?, activeProfile: String?) -> Bool {
        guard accountAvailable, let activeProfile else { return false }
        return completedFor != activeProfile
    }

    @discardableResult
    func beginAwaitingInitialPull(timeout: TimeInterval = AppViewModel.initialPullPlaceholderTimeout) -> UUID {
        let token = UUID()
        initialPullWaitToken = token
        isAwaitingInitialPull = true
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.endAwaitingInitialPull(token: token)
        }
        return token
    }

    /// Ends the wait `token` started; nil ends any wait (sign-out).
    func endAwaitingInitialPull(token: UUID? = nil) {
        if let token, token != initialPullWaitToken { return }
        initialPullWaitToken = UUID()
        isAwaitingInitialPull = false
    }

    /// Running inside the unit-test host (XCTest injects this variable).
    static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// UI tests, captures and screenshot runs drive the app from DEBUG fixtures, not iCloud.
    static var isMockLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-LHMockScenario")
    }

#if DEBUG
    /// `-LHSimulatePendingPull <seconds>`: Today shows the first-pull loading state for that long,
    /// then settles (captures and the "Today stays usable while loading" UI test).
    /// `-LHSimulatePullState waiting|syncing|failed`: holds the export gate in that state
    /// (captures of the export sheet). waiting = hours placeholder showing; syncing = past the
    /// cap with the pull still running; failed = the pull failed (gate open with the note).
    static var simulatedPullState: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHSimulatePullState"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    private func applySimulatedPullStateIfNeeded() {
        switch Self.simulatedPullState {
        case "waiting":
            isInitialPullRunning = true
            beginAwaitingInitialPull(timeout: 3600)
        case "syncing":
            isInitialPullRunning = true
        case "failed":
            isInitialPullRunning = false
            initialPullFailed = true
        default:
            break
        }
    }

    private func applySimulatedPendingPullIfNeeded() {
        applySimulatedPullStateIfNeeded()
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHSimulatePendingPull"),
              args.indices.contains(index + 1),
              let seconds = Double(args[index + 1]) else { return }
        beginAwaitingInitialPull(timeout: seconds)
    }
#endif
    
    /// There is no sign-in in 2.2: the record set exists once the device merge has run. The
    /// name kept for compatibility: true whenever there is a record set to show.
    func checkSignInState() {
        isSignedIn = UserScope.userId != nil
        userName = Self.resolvedProfileName(.standard)
    }

    /// "Your name" (optional), shown as "Prepared for" on reports. Device copy of
    /// `TaxProfile.displayName`, which syncs.
    static func resolvedProfileName(_ defaults: UserDefaults = .standard) -> String {
        #if DEBUG
        if let scope = defaults.string(forKey: IdentityScope.debugScopeKey) ?? IdentityScope.debugOverride,
           let name = defaults.string(forKey: "u.\(scope).profile.name"), !name.isEmpty { return name }
        #endif
        if let name = defaults.string(forKey: IdentityKeys.displayName), !name.isEmpty { return name }
        return ""
    }

    /// Saves "Your name" (device copy + the synced TaxProfile field).
    func setDisplayName(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaults = UserDefaults.standard
        if clean.isEmpty { defaults.removeObject(forKey: IdentityKeys.displayName) } else { defaults.set(clean, forKey: IdentityKeys.displayName) }
        userName = clean
        markSettingsDirty(tax: true)
        syncService.schedulePush()
    }

    /// Whether the record set has finished onboarding. False before the device merge.
    var activeProfileCompletedOnboarding: Bool {
        guard UserScope.userId != nil else { return false }
        return UserDefaults.standard.bool(forKey: UserScope.key("hasCompletedOnboarding"))
    }

    /// What the root shows (ContentView): Welcome, the onboarding steps, or the app.
    enum RootState: Equatable { case welcome, onboarding, app }

    var rootState: RootState {
        guard isSignedIn else { return .welcome }
        return activeProfileCompletedOnboarding ? .app : .welcome
    }

    /// Welcome's primary button: "Continue" when earlier records are already here (P2).
    var welcomePrimaryTitle: String {
        if case .found = identity.welcome {
            return String(localized: "Continue", table: "Identity")
        }
        return String(localized: "Get started", table: "ConversionPath")
    }

    /// The one Today card K fills (C's slot under the hero).
    var todayNotice: TodayIdentityNotice? { identity.todayNotice }

    enum ProfileDeletionError: LocalizedError, Equatable {
        /// iCloud is off/unreachable, so copies saved there can't be removed now.
        case iCloudUnavailable
        /// The phone is signed in to a different iCloud account: its zone is never deleted.
        case otherICloudAccount

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return String(localized: "iCloud is off, so copies saved there can’t be removed now. Delete from this iPhone anyway, or turn on iCloud and retry?", table: "Identity")
            case .otherICloudAccount:
                return String(localized: "This iPhone is signed in to a different iCloud account. Nothing there will be deleted. Delete from this iPhone only?", table: "Identity")
            }
        }
    }

    /// Delete all data (§1.4): the whole iCloud zone (one operation), then every `v2.*` and
    /// `u.*` key, the archive, the backup, attachments, notification keys and the widget
    /// snapshot. Afterwards the app is a new install: Welcome.
    ///
    /// - Parameter allowLocalOnly: with iCloud unavailable it throws `.iCloudUnavailable` BEFORE
    ///   deleting anything, unless the person chose "Delete from this iPhone anyway".
    func deleteAllData(allowLocalOnly: Bool = false) async throws {
        syncService.stop()
        if !syncService.accountAvailable { await syncService.checkAccountStatus() }
        var deletedInICloud = false
        if syncService.accountAvailable {
            do {
                try await syncService.deleteEverythingInICloud()
                deletedInICloud = true
            } catch is CloudKitSyncService.OtherICloudAccountError {
                // Another account's iCloud is never touched; this iPhone's copy only when asked.
                guard allowLocalOnly else { throw ProfileDeletionError.otherICloudAccount }
            }
        } else if !allowLocalOnly {
            throw ProfileDeletionError.iCloudUnavailable
        }
        Analytics.deleteAllData(iCloud: deletedInICloud)
        wipeEverythingLocal()
    }

    /// The local half of Delete all data (also P31 "Delete here too").
    func wipeEverythingLocal() {
        endTimerLiveActivity(propertyId: timerPropertyId, category: timerCategory, startDate: timerStartTime, needsReview: false)
        deleteAttachmentFiles(for: timeEntries)
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("u.") || key.hasPrefix(IdentityKeys.prefix) || ProfileKeys.signOutKeys.contains(key)
            || key == ProfileKeys.previousProfileId || Self.unscopedLegacyKeys.contains(key) || key == CaptureActionQueue.key {
            defaults.removeObject(forKey: key)
        }
        let root = MigrationFiles.defaultRoot
        // Photos are not keyed by record set: the whole folder goes.
        for folder in IdentityFolder.allCases {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(folder.rawValue, isDirectory: true))
        }
        identity.earlier.deleteEverything()
        // A new install's record set.
        RecordSetMigration.adoptIds(storage: IdentityZone.household, unified: IdentityZone.household, defaults: defaults)
        RecordSetMigration.setStep(.deviceMerged, defaults)

        properties = []
        timeEntries = []
        activeCelebration = nil
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        timerCategory = .repairs
        staleTimerRecovery = nil
        EngagementWidgetSnapshotStore.save(.empty)
        WidgetSurfaceStore.save(.empty)
        WidgetCenter.shared.reloadTimelines(ofKind: EngagementWidgetSnapshotStore.widgetKind)
        reloadManagersForRecordSet()
        checkSignInState()
        identity.refresh(sync: syncService)
        objectWillChange.send()
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
        WidgetSurfaceStore.save(.empty)
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
            "LandlordHours.staleTimerRecoveries",
            "LandlordHours.stoppedTimerDraft",
            "LandlordHours.celebratedMilestones",
            "hasCompletedOnboarding",
            GuidedOnboardingStore.completedKey,
            GuidedOnboardingStore.skippedKey,
            "globalGoalType",
            "materialParticipationTarget",
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

        for key in Set(localDataKeys + CaptureOptIn.allBaseKeys) {
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
        "materialParticipationTarget",
        "propertyGoals",
        "iCloudBackupEnabled",
        "profileImageData",
        "profile.name",
        "profile.email",
        "profile.userEdited",
        GuidedOnboardingStore.completedKey,
        GuidedOnboardingStore.skippedKey,
        "LandlordHours.taxProfile.filingStatus",
        "LandlordHours.taxProfile.spouseTracking",
        "LandlordHours.taxProfile.taxYear",
        "LandlordHours.taxProfile.groupingElection",
        "LandlordHours.taxProfile.nonREWorkHours",
    ]

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
            "nonREWorkHours",
            "noOneParticipatedMore"
        ]
        let baseKeys = unscopedLegacyKeys + [
            "legacyDataMigrated",
            "timerStartTime",
            "timerPropertyId",
            "timerCategory",
            "LandlordHours.staleTimerRecovery",
            "LandlordHours.staleTimerRecoveries",
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
            GuidedOnboardingStore.skippedKey,
            "LandlordHours.timer",
            PendingCelebrationQueue.baseKey,
            HouseCelebrationLedger.celebratedBaseKey,
            HouseCelebrationLedger.pendingBaseKey,
            HouseCelebrationLedger.backfillShownBaseKey,
            "profile.displayName",
            CapturePromptConsent.baseKey
        ] + taxProfileFields.map { "LandlordHours.taxProfile.\($0)" } + CaptureOptIn.allBaseKeys

        for key in Set(baseKeys) {
            defaults.removeObject(forKey: UserScope.key(key, userId: userId))
        }

        // Notification cooldown keys (`LandlordHours.notification.lastScheduled.<reason>`).
        // Match the full `u.<id>.LandlordHours.notification.` prefix so a profile whose ID
        // merely starts with this one (e.g. `email-a@x.com.au`) is never touched.
        let notificationPrefix = UserScope.key("LandlordHours.notification.", userId: userId)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(notificationPrefix) {
            defaults.removeObject(forKey: key)
        }

        // 2.0 capture inbox (local only): the profile's suggestions, dismissed keys, mute rules.
        SuggestionStore.removeAll(forUserId: userId)
        // Sync push baselines and delete tombstones (local-only and iCloud deletes alike).
        SyncChangeTracker.removeAll(forUserId: userId)
    }

    // MARK: - Event-ended prompts (opt-in, per profile)

    /// Whether this profile opted in to end-of-event notifications. Off by default, including
    /// for profiles upgraded from 1.x. The inbox opt-in screens set it; changing it rebuilds
    /// (or clears) the schedule right away.
    var eventPromptsEnabled: Bool {
        get {
            guard let userId = UserScope.userId else { return false }
            return CapturePromptConsent.isEnabled(profileId: userId)
        }
        set {
            guard let userId = UserScope.userId else { return }
            CapturePromptConsent.set(newValue, profileId: userId)
            objectWillChange.send()
            Task { @MainActor in
                await CaptureNotificationRefresher.shared.refresh(reason: newValue ? "opt-in" : "opt-out")
            }
        }
    }

    // MARK: - Sync Now (manual trigger for Settings)
    func syncNow() {
        Task { await syncService.syncNow() }
    }

    // MARK: - Subscription Features
    func canAddProperty() -> Bool {
        ProGate.canAddProperty(isPro: SubscriptionManager.shared.isPro, propertyCount: properties.count)
    }
    
    func canAddTimeEntry() -> Bool {
        return true // Open for all users
    }

    func canAttachPhotos() -> Bool {
        return true // Open for all users
    }
    
    func canExportPDF() -> Bool {
        !ProGate.isExportLocked(isPro: SubscriptionManager.shared.isPro)
    }

    /// Called after the user actually shares an export (the share sheet reported completion).
    /// Records `export_shared` and offers Apple's rating prompt on the first shared export.
    var onExportShared: ((ExportFormat) -> Void)?

    func exportShared(format: ExportFormat) {
        Analytics.exportShared(format: format)
        RatingPromptCoordinator.shared.consider(.exportShared, entryCount: timeEntries.count)
        onExportShared?(format)
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
        // 2.0: a toast, not the 1.x full-screen confetti (CelebrationType.propertyAdded is retired).
        if !suppressCelebrations && persistenceError == nil {
            LHToastCenter.shared.show(.success, "Added \(property.name)")
        }
        Analytics.propertyAdded()
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
        let removedEntries = timeEntries.filter { $0.propertyId == property.id }
        deleteAttachmentFiles(for: removedEntries)
        timeEntries.removeAll { $0.propertyId == property.id }
        saveData()
        // Tombstones the property AND its entries; the next push sends the deletes.
        syncService.deletePropertyFromCloud(property, cascadedEntryIds: removedEntries.map(\.id))
    }
    
    // MARK: - Time Entry Management
    func addTimeEntry(
        propertyId: UUID,
        participant: Participant,
        category: ActivityCategory,
        hours: Double,
        date: Date,
        notes: String,
        attachments: [TimeAttachment] = [],
        source: EntrySource = .manual
    ) {
        let houseHoursBefore = houseCountableHours()
        let entry = TimeEntry(
            propertyId: propertyId,
            participant: participant,
            category: category,
            hours: hours,
            date: date,
            notes: notes,
            attachments: attachments,
            importSource: source.storedValue
        )
        timeEntries.append(entry)
        saveData()
        reportHouseSave(previousHours: houseHoursBefore)
        Analytics.sessionLogged(category: category, participant: participant)
        Analytics.entryLogged(source: source)
        RatingPromptCoordinator.shared.consider(.entriesMilestone, entryCount: timeEntries.count)
    }
    
    /// The Log time sheet's save. Unlike `addTimeEntry`, it reports a failed write: the entry is
    /// taken back out (nothing half-saved), `persistenceError` is set, and the sheet stays open
    /// with the reason. On success it runs the same house, analytics and iCloud path.
    @discardableResult
    func logTimeEntry(
        propertyId: UUID,
        participant: Participant,
        category: ActivityCategory,
        hours: Double,
        date: Date,
        notes: String,
        attachments: [TimeAttachment] = [],
        source: EntrySource = .manual,
        recordDescription: String? = nil
    ) -> LogSaveResult {
        guard properties.contains(where: { $0.id == propertyId }) else {
            return .failed(LogSaveResult.missingPropertyMessage)
        }
        guard hours > 0 else { return .failed(LogSaveResult.missingHoursMessage) }
        let houseHoursBefore = houseCountableHours()
        let entry = TimeEntry(
            propertyId: propertyId,
            participant: participant,
            category: category,
            hours: min(hours, 24),
            date: date,
            notes: notes,
            attachments: attachments,
            importSource: source.storedValue,
            recordDescription: recordDescription
        )
        timeEntries.append(entry)
        guard writePersistentStore() else {
            timeEntries.removeAll { $0.id == entry.id }
            return .failed(LogSaveResult.writeFailedMessage)
        }
        refreshWidgetSnapshot()
        syncService.schedulePush()
        reportHouseSave(previousHours: houseHoursBefore)
        Analytics.sessionLogged(category: category, participant: participant)
        Analytics.entryLogged(source: source)
        RatingPromptCoordinator.shared.consider(.entriesMilestone, entryCount: timeEntries.count)
        return .saved(entry.id)
    }

#if DEBUG
    /// DEBUG: the next persistent write fails (unit tests and the `-LHFailNextSave` capture).
    static var debugFailNextWrite = false
#endif

    func updateTimeEntry(_ entry: TimeEntry) {
        if let index = timeEntries.firstIndex(where: { $0.id == entry.id }) {
            timeEntries[index] = entry
            saveData()
        }
    }

    func deleteTimeEntry(_ entry: TimeEntry) {
        deleteAttachmentFiles(for: [entry])
        timeEntries.removeAll { $0.id == entry.id }
        saveData()
        syncService.deleteEntryFromCloud(entry)
    }

    /// Remove the on-disk attachment files backing the given entries. Safe to call
    /// for entries with no attachments; missing files are ignored.
    private func deleteAttachmentFiles(for entries: [TimeEntry]) {
        for entry in entries {
            for attachment in entry.attachments {
                AttachmentStore.shared.delete(attachment)
            }
        }
    }

    // MARK: - Calendar Import (1.x)
    /// The 1.x bulk calendar import, unchanged. 2.0 has no UI that calls it (calendar work is
    /// confirmed one suggestion at a time in the Inbox); it stays because 1.1 devices still run
    /// this exact code, and the 1.1-compatibility tests (CaptureFlowTests, CalendarDetectorTests)
    /// replay it to prove a 2.0 confirm is skipped by a 1.1 import.
    func importCalendarEntries(_ detectedEntries: [DetectedCalendarEntry]) -> Int {
        guard !properties.isEmpty else { return 0 }
        let validPropertyIds = Set(properties.map(\.id))
        let selected = detectedEntries.filter { $0.isSelected }
        let houseHoursBefore = houseCountableHours()
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
            reportHouseSave(previousHours: houseHoursBefore)
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
            notes: notes,
            source: .timer
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

    /// Puts a discarded running timer back exactly as it was (the "Timer discarded · Undo" toast).
    func restoreTimer(propertyId: UUID, category: ActivityCategory, startTime: Date) {
        guard !isTimerRunning, properties.contains(where: { $0.id == propertyId }) else { return }
        isTimerRunning = true
        timerStartTime = startTime
        timerPropertyId = propertyId
        timerCategory = category
        saveTimerState()
        startOrUpdateTimerLiveActivity()
    }

    /// Saves ONE timer draft as an entry. Pass the id of the draft the user is looking at:
    /// if it was already saved/discarded (a double tap), nothing happens — the next draft is
    /// never saved unseen.
    ///
    /// - Parameter propertyId: required when the draft's property was deleted; the user
    ///   picks where the hours go.
    /// - Returns: true if an entry was added.
    @discardableResult
    func saveRecoveredStaleTimer(id: UUID? = nil, hours: Double? = nil, propertyId: UUID? = nil, notes: String? = nil) -> Bool {
        guard let recovery = id.map({ id in staleTimerRecoveries.first { $0.id == id } }) ?? staleTimerRecovery else {
            return false
        }
        let targetProperty = propertyId ?? recovery.propertyId
        guard properties.contains(where: { $0.id == targetProperty }) else { return false }
        // Tax honesty: a draft capped at 24 h needs reviewed hours, never a one-tap save.
        if recovery.requiresReview && hours == nil { return false }
        // Same rule as stopTimer: exact elapsed time, capped at 24 h, never rounded up.
        let cappedHours = min(max(hours ?? recovery.suggestedHours, 0), 24)
        addTimeEntry(
            propertyId: targetProperty,
            participant: .selfParticipant,
            category: recovery.category,
            hours: cappedHours,
            date: recovery.startTime,
            notes: notes ?? recovery.entryNote,
            source: .timer
        )
        removeStaleTimerRecovery(id: recovery.id)
        return true
    }

    func discardRecoveredStaleTimer(id: UUID? = nil) {
        guard let target = id ?? staleTimerRecovery?.id else { return }
        removeStaleTimerRecovery(id: target)
    }

    /// True when the draft's property no longer exists (it was deleted after the timer).
    func staleTimerRecoveryNeedsProperty(_ recovery: StaleTimerRecovery) -> Bool {
        !properties.contains { $0.id == recovery.propertyId }
    }

    private func removeStaleTimerRecovery(id: UUID) {
        guard staleTimerRecoveries.contains(where: { $0.id == id }) else { return }
        staleTimerRecoveries.removeAll { $0.id == id }
        writeStaleTimerRecoveries(staleTimerRecoveries)
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
        if queuesCelebrations {
            PendingCelebrationQueue.enqueue(type)
        } else {
            activeCelebration = type
        }
    }

    /// Shows the oldest queued celebration (crossed while in the background), if nothing else
    /// is showing. Called when a scene becomes active.
    func presentPendingCelebrationIfAny() {
        guard activeCelebration == nil, !suppressCelebrations else { return }
        if let next = PendingCelebrationQueue.dequeue() {
            activeCelebration = next
        }
    }

    // 2.0: saving hours no longer triggers the 1.x confetti overlay (hoursLogged / goalMet).
    // The Blueprint house is the only reward on a save: the confirm build on Today and, at
    // 100 / 500 / 750 / the goal, MilestoneCelebrationView once (TodayHouseEvents).

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
    
    /// True only when other work hours are entered and real estate is more than half.
    func meets50PercentRule(year: Int) -> Bool {
        repsStatus(participant: .selfParticipant, year: year).moreThanHalfStatus == .met
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
        propertyId: UUID? = nil,
        includeSpouse: Bool = true
    ) -> TaxQualificationEngine.MaterialParticipationResult {
        TaxQualificationEngine.materialParticipationStatus(
            entries: includeSpouse ? timeEntries : timeEntries.filter { $0.participant == .selfParticipant },
            year: year,
            propertyId: propertyId,
            groupingElection: TaxProfileManager.shared.groupingElection,
            noOneParticipatedMore: TaxProfileManager.shared.noOneParticipatedMore(forYear: year)
        )
    }

    /// `includeSpouse: false` leaves spouse entries out (the house when spouse hours are not
    /// tracked jointly); every other caller keeps the owner + spouse total.
    func materialParticipationOverview(year: Int, includeSpouse: Bool = true) -> TaxQualificationEngine.MaterialParticipationResult {
        TaxQualificationEngine.materialParticipationOverview(
            entries: includeSpouse ? timeEntries : timeEntries.filter { $0.participant == .selfParticipant },
            properties: properties,
            year: year,
            groupingElection: TaxProfileManager.shared.groupingElection,
            noOneParticipatedMore: TaxProfileManager.shared.noOneParticipatedMore(forYear: year)
        )
    }
    
    // MARK: - Persistence

    /// Non-blocking, user-facing persistence error surfaced as a banner. `nil` when healthy.
    @Published var persistenceError: String? {
        didSet { if persistenceError != nil { RatingPromptCoordinator.shared.noteError() } }
    }

    private static let persistenceLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "Persistence")

    /// Shown in the one toast with "Retry" (copy sheet §6).
    static let saveFailureMessage = "Couldn’t save your last change. Your iPhone may be out of space."
    /// Shown in the one toast with "Help" (opens Get help).
    static let loadFailureMessage = "Couldn’t open your records. They’re still safe on this iPhone."

    /// The toast's "Retry": writes everything again (clears the error on success).
    func retrySave() {
        saveData()
    }

    func saveData() {
        writePersistentStore()
        refreshWidgetSnapshot()
        // Trigger debounced cloud push
        syncService.schedulePush()
    }

    /// Flushes any pending attachment bytes to disk, then encodes and writes
    /// properties + entries. Sets `persistenceError` on failure instead of
    /// swallowing it. Returns `true` on a fully successful write.
    @discardableResult
    private func writePersistentStore() -> Bool {
        do {
#if DEBUG
            if Self.debugFailNextWrite {
                Self.debugFailNextWrite = false
                throw CocoaError(.fileWriteOutOfSpace)
            }
#endif
            // Write attachment files first so the encoded blob never carries photo
            // bytes and files are verified before any inline copy is dropped.
            try persistPendingAttachments()
            let propertiesData = try JSONEncoder().encode(properties)
            let entriesData = try JSONEncoder().encode(timeEntries)
            UserDefaults.standard.set(propertiesData, forKey: propertiesKey)
            UserDefaults.standard.set(entriesData, forKey: entriesKey)
            persistenceError = nil
            return true
        } catch {
            Self.persistenceLogger.error("Save failed: \(error.localizedDescription, privacy: .public)")
            persistenceError = Self.saveFailureMessage
            return false
        }
    }

    /// Writes every attachment's still-in-memory bytes (freshly picked photos, or
    /// legacy inline blobs) out to a verified file, then drops the in-memory copy.
    /// Idempotent: attachments with no pending bytes are skipped. On a thrown
    /// error, already-flushed attachments stay safely on disk and the persisted
    /// blob (untouched by this method) still holds every inline copy, so a later
    /// attempt re-runs without data loss.
    private func persistPendingAttachments() throws {
        for entryIndex in timeEntries.indices {
            for attachmentIndex in timeEntries[entryIndex].attachments.indices {
                let attachment = timeEntries[entryIndex].attachments[attachmentIndex]
                guard let bytes = attachment.pendingBytes else { continue }
                try AttachmentStore.shared.write(bytes, for: attachment)
                timeEntries[entryIndex].attachments[attachmentIndex].clearPendingData()
            }
        }
    }

    private func loadData() {
        // Always reset before loading — prevents stale data from leaking across user scopes
        properties = []
        timeEntries = []
        persistenceError = nil

        // A present-but-undecodable blob is corruption: surface it rather than
        // silently presenting an empty dataset as if it were the real records.
        if let propertiesData = UserDefaults.standard.data(forKey: propertiesKey) {
            do {
                properties = try JSONDecoder().decode([RentalProperty].self, from: propertiesData)
            } catch {
                Self.persistenceLogger.error("Property load failed (corrupt store): \(error.localizedDescription, privacy: .public)")
                persistenceError = Self.loadFailureMessage
            }
        }
        if let entriesData = UserDefaults.standard.data(forKey: entriesKey) {
            do {
                timeEntries = try JSONDecoder().decode([TimeEntry].self, from: entriesData)
            } catch {
                Self.persistenceLogger.error("Entry load failed (corrupt store): \(error.localizedDescription, privacy: .public)")
                persistenceError = Self.loadFailureMessage
            }
        }

        migrateInlineAttachmentsIfNeeded()
        refreshWidgetSnapshot()
    }

    /// One-time migration of legacy inline attachment bytes to file storage.
    ///
    /// Detection is data-driven — it runs only when a just-decoded entry still
    /// carries inline bytes — which makes it inherently idempotent: after a
    /// successful flush the persisted blob has no inline bytes, so a re-run finds
    /// nothing to migrate. It is crash-safe: if the process dies before the
    /// re-save, the persisted blob still holds the inline bytes and the next
    /// launch migrates again. Bytes are never dropped before their file write is
    /// verified (see `persistPendingAttachments`).
    private func migrateInlineAttachmentsIfNeeded() {
        let hasLegacyInlineBytes = timeEntries.contains { entry in
            entry.attachments.contains { $0.hasPendingData }
        }
        guard hasLegacyInlineBytes else { return }

        do {
            try persistPendingAttachments()
            let entriesData = try JSONEncoder().encode(timeEntries)
            UserDefaults.standard.set(entriesData, forKey: entriesKey)
            Self.persistenceLogger.info("Migrated legacy inline attachments to file storage.")
        } catch {
            // Leave the persisted blob untouched (it still holds the inline bytes)
            // so a later launch retries. No data is lost; log for diagnostics.
            Self.persistenceLogger.error("Attachment migration deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The one engagement context the widget and Siri read. Same counting rules as Today's
    /// house: REPS is your hours alone; material participation adds a spouse only when Tax
    /// Profile "Spouse hours" is on.
    func engagementContext(
        now: Date = Date(),
        taxYear: Int? = nil,
        isTimerRunning timerRunning: Bool? = nil,
        timerStartTime timerStart: Date? = nil
    ) -> EngagementContext {
        let goal = GoalManager.shared.globalGoalType
        let choice = GoalManager.shared.goalChoice
        return EngagementContext(
            now: now,
            taxYear: taxYear ?? Calendar.current.component(.year, from: now),
            properties: properties,
            timeEntries: timeEntries,
            calendarDraftCount: 0,
            isTimerRunning: timerRunning ?? isTimerRunning,
            timerStartTime: timerRunning == nil ? timerStartTime : timerStart,
            notificationPermission: .notDetermined,
            recentDismissals: [],
            isProUser: SubscriptionManager.shared.isPro,
            // MP 500 measures against 500 (its HourGoalType stays `.str` for 1.x compatibility).
            targetHours: choice.targetHours,
            goalType: goal,
            groupingElection: TaxProfileManager.shared.groupingElection,
            includeSpouse: tracksSpouseJointly
        )
    }

    private func refreshWidgetSnapshot() {
        let now = Date()
        let taxYear = Calendar.current.component(.year, from: now)
        let widgetGoal = widgetGoalContext()
        let context = engagementContext(now: now, taxYear: taxYear)
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
        // 2.0 surfaces: the widget draws WidgetSurfaceSnapshot (and reloads the same kind).
        refreshWidgetSurface(now: now)
    }

    private func widgetGoalContext() -> (targetHours: Double, label: String, shortLabel: String) {
        let choice = GoalManager.shared.goalChoice
        let labels = choice.widgetLabels
        return (choice.targetHours, labels.0, labels.1)
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

    /// Appends a draft to this profile's list. Never replaces one awaiting review.
    private func saveStaleTimerRecovery(_ recovery: StaleTimerRecovery) {
        var list = persistedStaleTimerRecoveries()
        if !list.contains(recovery) { list.append(recovery) }
        writeStaleTimerRecoveries(list)
    }

    private func persistedStaleTimerRecoveries() -> [StaleTimerRecovery] {
        let defaults = UserDefaults.standard
        var list: [StaleTimerRecovery] = []
        if let data = defaults.data(forKey: staleTimerRecoveriesKey),
           let decoded = try? JSONDecoder().decode([StaleTimerRecovery].self, from: data) {
            list = decoded
        }
        // Migrate the legacy single-draft key into the list (never drop it).
        if let data = defaults.data(forKey: staleTimerRecoveryKey),
           let legacy = try? JSONDecoder().decode(StaleTimerRecovery.self, from: data),
           !list.contains(legacy) {
            list.insert(legacy, at: 0)
        }
        return list
    }

    private func writeStaleTimerRecoveries(_ list: [StaleTimerRecovery]) {
        let defaults = UserDefaults.standard
        if list.isEmpty {
            defaults.removeObject(forKey: staleTimerRecoveriesKey)
        } else if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: staleTimerRecoveriesKey)
        }
        defaults.removeObject(forKey: staleTimerRecoveryKey)
    }

    private func loadStaleTimerRecovery() {
        // Keep every draft, including ones whose property was deleted: the card asks the
        // user to pick a property (or discard) instead of dropping recorded time silently.
        let list = persistedStaleTimerRecoveries()
        staleTimerRecoveries = list
        writeStaleTimerRecoveries(list)
    }

    private func clearStaleTimerRecovery() {
        UserDefaults.standard.removeObject(forKey: staleTimerRecoveryKey)
        UserDefaults.standard.removeObject(forKey: staleTimerRecoveriesKey)
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
                let forgotten = StaleTimerRecovery(
                    startTime: start,
                    propertyId: propertyId,
                    category: timerCategory,
                    elapsedHours: Date().timeIntervalSince(start) / 3600.0
                )
                saveStaleTimerRecovery(forgotten)
                staleTimerRecoveries = persistedStaleTimerRecoveries()
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

    /// The widget extension (and its Live Activity UI) is not in the 1.1 build, so no Live Activity
    /// is requested. Flip back on in 2.0 when the extension returns.
    static let liveActivitiesEnabled = false

    private func startOrUpdateTimerLiveActivity() {
        guard Self.liveActivitiesEnabled,
              isTimerRunning,
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

struct StaleTimerRecovery: Codable, Equatable, Identifiable {
    enum Reason: String, Codable {
        /// Left running for more than 24 hours.
        case forgotten
        /// Paused when the user switched profiles.
        case pausedAtSwitch
    }

    var id = UUID()
    let startTime: Date
    let propertyId: UUID
    let category: ActivityCategory
    let elapsedHours: Double
    var reason: Reason = .forgotten
    var pausedAt: Date? = nil

    init(startTime: Date, propertyId: UUID, category: ActivityCategory, elapsedHours: Double,
         reason: Reason = .forgotten, pausedAt: Date? = nil) {
        self.id = UUID()
        self.startTime = startTime
        self.propertyId = propertyId
        self.category = category
        self.elapsedHours = elapsedHours
        self.reason = reason
        self.pausedAt = pausedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, propertyId, category, elapsedHours, reason, pausedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startTime = try c.decode(Date.self, forKey: .startTime)
        propertyId = try c.decode(UUID.self, forKey: .propertyId)
        category = try c.decode(ActivityCategory.self, forKey: .category)
        elapsedHours = try c.decode(Double.self, forKey: .elapsedHours)
        reason = try c.decodeIfPresent(Reason.self, forKey: .reason) ?? .forgotten
        pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
    }

    /// Exact elapsed time capped at 24 h — the same rule as `stopTimer`. Never rounded
    /// up: a 2-minute timer suggests 2 minutes, not 15, so tax hours are never inflated.
    var suggestedHours: Double {
        min(max(elapsedHours, 0), 24)
    }

    var wasCapped: Bool { elapsedHours > 24 }

    /// The note saved on the entry. It goes into the audit export, so it must say what
    /// actually happened.
    var entryNote: String {
        switch reason {
        case .forgotten: return "Recovered from a timer that was left running."
        case .pausedAtSwitch: return "Timer paused when switching profiles."
        }
    }

    /// "2 min" under an hour (a 2-minute draft must not read "0.0h"), else "1.5h".
    var durationLabel: String {
        let hours = suggestedHours
        guard hours < 1 else { return AppFormat.hours(hours) }
        let minutes = Int((hours * 60).rounded())
        return minutes < 1 ? "under 1 min" : "\(minutes) min"
    }

    /// The card's headline. A capped draft says both facts in one line, so the run time and
    /// the 24 h cap never read as a contradiction.
    var cardHeadline: String {
        guard wasCapped else { return ranLabel }
        return "\(ranLabel). We stopped counting at 24h \u{2014} check it before saving."
    }

    /// Copy for the Track recovery card, per draft reason. Kept here so it is unit-tested.
    func cardMessage(propertyName: String?, hasAnyProperty: Bool) -> String {
        let start = startTime.formatted(date: .abbreviated, time: .shortened)
        guard let propertyName else {
            let pick = hasAnyProperty
                ? "Choose a property below to save it to."
                : "Add a property to save it."
            return "Started \(start). The property for this timer was deleted. \(pick)"
        }
        switch reason {
        case .pausedAtSwitch:
            let paused = (pausedAt ?? startTime).formatted(date: .abbreviated, time: .shortened)
            let action = wasCapped ? "" : " Save the time it ran, or discard it."
            return "Started \(start) for \(propertyName). We paused it when you switched profiles at \(paused).\(action)"
        case .forgotten:
            let note = wasCapped ? "" : " Review it before saving so the record stays accurate."
            return "Started \(start) for \(propertyName).\(note)"
        }
    }

    /// The real elapsed time, always shown on the card ("Ran 45 min", "Ran 30.0h").
    var ranLabel: String {
        let hours = max(elapsedHours, 0)
        if hours < 1 {
            let minutes = Int((hours * 60).rounded())
            return minutes < 1 ? "Ran under 1 min" : "Ran \(minutes) min"
        }
        return "Ran \(AppFormat.hours(hours))"
    }

    /// Capped drafts (over 24 h) must be reviewed in the editor; no one-tap save.
    var requiresReview: Bool { wasCapped }

    /// The review editor's Save is enabled only once the user has changed the hours, or
    /// explicitly confirmed the suggested figure. One tap can never commit the 24 h cap.
    func canSaveReview(hours: Double, confirmed: Bool) -> Bool {
        guard hours > 0 else { return false }
        return confirmed || abs(hours - suggestedHours) > 0.0001
    }

    var accessibilityTitle: String {
        switch reason {
        case .forgotten: return "Timer left running."
        case .pausedAtSwitch: return "Timer paused when you switched profiles."
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
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }
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
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }
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

    func syncDidReceiveGoalSettings(globalGoalType: HourGoalType, propertyGoals: [PropertyGoal], materialParticipationTarget: Int?) {
        let mgr = GoalManager.shared
        mgr.globalGoalType = globalGoalType
        // nil: a record from a device before 2.0 says nothing about the target; keep ours.
        if let materialParticipationTarget { mgr.applyMaterialParticipationTarget(materialParticipationTarget) }
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
        writePersistentStore()
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
        // An isolated DEBUG scope (`u.debug-<scenario>.`), never the person's `v2.` record set.
        defaults.set(userId, forKey: IdentityScope.debugScopeKey)
        defaults.set(Self.launchMockName(defaultValue: scenario.userName), forKey: "u.\(userId).profile.name")
        reloadManagersForRecordSet()

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
        // Capture hook: `-LHOtherWorkHours 0` shows the "add your other work hours" state.
        let launchArgs = ProcessInfo.processInfo.arguments
        if let index = launchArgs.firstIndex(of: "-LHOtherWorkHours"),
           launchArgs.indices.contains(index + 1),
           let hours = Double(launchArgs[index + 1]) {
            taxProfile.nonREWorkHours = hours
        }

        let goalManager = GoalManager.shared
        goalManager.propertyGoals = []
        goalManager.globalGoalType = scenario == .occasional ? .str : .reps
        goalManager.setGoalSetup(rental: nil, pro: nil)          // a mock launch starts with no onboarding answers
        TaxProfileManager.shared.setNoOneParticipatedMore(nil, forYear: Calendar.current.component(.year, from: Date()))

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

        // Journey-test hook: attach a real, file-backed photo to the most-recent
        // seeded entry so the persistence/relaunch path can be exercised end-to-end
        // without driving the system photo picker. DEBUG-only, opt-in via launch arg.
        if ProcessInfo.processInfo.arguments.contains("-LHSeedAttachment"), !timeEntries.isEmpty {
            let bytes = Self.debugSeedAttachmentData()
            if !bytes.isEmpty {
                timeEntries[0].date = Date()
                timeEntries[0].attachments = [
                    TimeAttachment(filename: "seed_receipt.png", data: bytes, mimeType: "image/png")
                ]
            }
        }

        saveDataLocal()
        goalManager.saveGoals()
        SubscriptionManager.shared.reload()
        CategoryManager.shared.loadCategories()
        MilestoneTracker.shared.reload()
        defaults.synchronize()

        suppressCelebrations = false
        TodayHouseEvents.shared.resetInMemoryState()
        #if DEBUG
        applyTodayHoursSeedIfNeeded()
        applyPropertiesSeedIfNeeded()
        #endif
    }

    /// A small solid image used only by the `-LHSeedAttachment` journey hook.
    private static func debugSeedAttachmentData() -> Data {
        let size = CGSize(width: 160, height: 160)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(red: 0.49, green: 0.44, blue: 0.97, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 30, y: 62, width: 100, height: 36))
        }
        return image.pngData() ?? Data()
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

// MARK: - The live record set (package K's engine reads and writes through here)

extension AppViewModel: LiveRecordSet {
    var liveEntries: [TimeEntry] { timeEntries }
    var liveProperties: [RentalProperty] { properties }
    var liveCategories: [CustomCategory] { CategoryManager.shared.customCategories }

    func replaceLive(entries: [TimeEntry], properties newProperties: [RentalProperty], categories: [CustomCategory]) {
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }
        properties = newProperties
        timeEntries = entries
        writePersistentStore()
        let manager = CategoryManager.shared
        if manager.customCategories.map(\.id) != categories.map(\.id) || manager.customCategories.map(\.modifiedAt) != categories.map(\.modifiedAt) {
            manager.customCategories = categories
            manager.saveCategories()
        }
        refreshWidgetSnapshot()
        identity.hasSavedEntry = !timeEntries.isEmpty
    }

    var goalSettings: GoalSettingsValues {
        let gm = GoalManager.shared
        let json = (try? JSONEncoder().encode(gm.propertyGoals)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let mp = gm.materialParticipationTarget
        return GoalSettingsValues(globalGoalType: gm.globalGoalType.rawValue, materialParticipationTarget: mp == 0 ? nil : mp, propertyGoalsJSON: json)
    }

    var taxProfile: TaxProfileValues {
        let tp = TaxProfileManager.shared
        return TaxProfileValues(filingStatus: tp.filingStatus.rawValue, spouseTracking: tp.spouseTracking, taxYear: tp.taxYear,
                                groupingElection: tp.groupingElection, nonREWorkHours: tp.nonREWorkHours,
                                displayName: UserDefaults.standard.string(forKey: IdentityKeys.displayName))
    }

    func applyRemoteSettings(goal: GoalSettingsValues?, tax: TaxProfileValues?) {
        isApplyingRemoteSettings = true
        defer { isApplyingRemoteSettings = false }
        if let goal {
            let gm = GoalManager.shared
            gm.globalGoalType = HourGoalType(rawValue: goal.globalGoalType) ?? .reps
            if let mp = goal.materialParticipationTarget { gm.applyMaterialParticipationTarget(mp) }
            gm.propertyGoals = goal.propertyGoals
            gm.saveGoals()
        }
        if let tax {
            let tp = TaxProfileManager.shared
            if let status = FilingStatus(rawValue: tax.filingStatus) { tp.filingStatus = status }
            tp.spouseTracking = tax.spouseTracking
            tp.taxYear = tax.taxYear
            tp.groupingElection = tax.groupingElection
            tp.nonREWorkHours = tax.nonREWorkHours
            if let name = tax.displayName, !name.isEmpty {
                UserDefaults.standard.set(name, forKey: IdentityKeys.displayName)
                userName = name
            }
        }
    }
}

// MARK: - The person's answers (package K); each one pushes what changed

extension AppViewModel {
    func answerTwoSets(_ answer: TwoSetsAnswer, group id: String) {
        identity.answer(answer, group: id)
        syncService.schedulePush()
        reloadAfterIdentityChange()
    }

    func undoSpouse(group id: String) {
        identity.undoSpouse(group: id)
        syncService.schedulePush()
        reloadAfterIdentityChange()
    }

    func putBack(_ names: Set<String>) {
        identity.putBack(names)
        syncService.schedulePush()
        reloadAfterIdentityChange()
    }

    func answerBulk(_ answer: BulkAnswer) {
        identity.answerBulk(answer)
        syncService.schedulePush()
        reloadAfterIdentityChange()
    }

    func answerZoneGone(_ answer: ZoneGoneAnswer) async {
        guard let engine = identity.engine else { return }
        _ = await engine.answerZoneGone(answer)
        if answer == .deleteHere { wipeEverythingLocal() }
        reloadAfterIdentityChange()
    }

    func answerAccountChanged(_ answer: AccountChangedAnswer) async {
        guard let engine = identity.engine else { return }
        _ = await engine.answerAccountChanged(answer)
        identity.accountChangedDeferred = false
        reloadAfterIdentityChange()
        if answer != .later { await syncService.start() }
    }
}

extension AppViewModel {
    /// Welcome's "Continue" (P2): the records arrived from an earlier version, so setup is done.
    func completeOnboardingWithEarlierRecords() {
        UserDefaults.standard.set(true, forKey: UserScope.key("hasCompletedOnboarding"))
        CaptureOptIn.markWhatsNewSeen()
        objectWillChange.send()
    }
}
