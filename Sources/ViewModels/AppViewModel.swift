import Foundation
import SwiftUI
import AuthenticationServices
import WidgetKit
import ActivityKit
import UIKit
import os.log

// MARK: - Per-User Key Scoping

/// Scopes UserDefaults keys to the current signed-in user.
/// Auth keys (appleUserId, localProfileId, legacy emailUserId, etc.) remain unscoped.
enum UserScope {
    /// Current userId: `appleUserId ?? localProfileId ?? emailUserId` (legacy fallback).
    static var userId: String? {
        ProfileKeys.resolveUserId(.standard)
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

    init() {
#if DEBUG
        seedLegacyEmailFixtureIfNeeded()
#endif
        // 1.1: turn a ≤1.0.6 email "account" into a local profile with the SAME ID.
        // Must run before anything reads auth keys or migrates unscoped legacy data.
        ProfileMigration.migrateEmailProfile(defaults: .standard)
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
        // Any successful pull for the active profile (including retries that call start()
        // directly) clears the export sheet's "Couldn't reach iCloud" note.
        syncService.onInitialPullSucceeded = { [weak self] profileId in
            guard let self, profileId == UserScope.userId else { return }
            self.initialPullFailed = false
        }

        // Trigger cloud sync when tax profile or goals change
        TaxProfileManager.shared.onDidChange = { [weak self] in
            // Spouse hours / grouping change what the widget counts.
            self?.refreshWidgetSnapshot()
            self?.syncService.schedulePush()
        }
        GoalManager.shared.onDidChange = { [weak self] in
            self?.refreshWidgetSnapshot()
            self?.syncService.schedulePush()
        }
        // WP-L: no launch splash. Today renders at once from local data; the first pull runs
        // behind it and only the hours wait on it.
        if Self.isUnitTestHost {
            // Unit tests build many view models; keep their sync start where it always was
            // (after 2 s, no placeholder) so no test races a pull it didn't ask for.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.isSignedIn { Task { await self.syncService.start() } }
            }
        } else if isSignedIn {
            #if DEBUG
            // Capture hook: a forced pull state replaces the real sync start.
            if Self.simulatedPullState == nil { startInitialSync(showsPlaceholder: !Self.isMockLaunch) }
            #else
            startInitialSync(showsPlaceholder: !Self.isMockLaunch)
            #endif
        }
#if DEBUG
        applySimulatedPendingPullIfNeeded()
#endif
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
    
    func checkSignInState() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: ProfileKeys.appleUserId) != nil {
            isSignedIn = true
            userName = defaults.string(forKey: ProfileKeys.appleUserName) ?? "User"
        } else if defaults.string(forKey: ProfileKeys.localProfileId) != nil {
            isSignedIn = true
            userName = defaults.string(forKey: ProfileKeys.localProfileName) ?? "User"
        } else if defaults.string(forKey: ProfileKeys.emailUserId) != nil {
            isSignedIn = true
            userName = defaults.string(forKey: ProfileKeys.emailUserName) ?? "User"
        }
    }

    /// Name shown for the active profile, from whichever identity is active.
    static func resolvedProfileName(_ defaults: UserDefaults = .standard) -> String {
        let candidate: String?
        if defaults.string(forKey: ProfileKeys.appleUserId) != nil {
            candidate = defaults.string(forKey: ProfileKeys.appleUserName)
        } else if defaults.string(forKey: ProfileKeys.localProfileId) != nil {
            candidate = defaults.string(forKey: ProfileKeys.localProfileName)
        } else {
            candidate = defaults.string(forKey: ProfileKeys.emailUserName)
        }
        guard let candidate, !candidate.isEmpty else { return "User" }
        return candidate
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
        // Pro belongs to this device's App Store account, not to a profile: carry the
        // cached flag from the previous profile, then reload() re-checks StoreKit
        // (Transaction.currentEntitlements) for the new profile.
        ProEntitlementCarryOver.carryFromPreviousProfile(defaults: .standard)
        // Reload all singleton managers for this user
        SubscriptionManager.shared.reload()
        GoalManager.shared.loadGoals()
        CategoryManager.shared.loadCategories()
        TaxProfileManager.shared.reload()
        MilestoneTracker.shared.reload()

        userName = Self.resolvedProfileName(.standard)
        AppleSignInManager.shared.checkExistingSignIn()

        // Start CloudKit sync; a restored profile's hours settle in when the pull lands.
        BackfillJob.shared.reset()
        startInitialSync()
    }

    /// "Continue without an account": creates a `local-<UUID>` profile.
    ///
    /// Deliberately does NOT call `signUp()`, which would wipe unscoped legacy data.
    /// Unscoped legacy data is migrated into the new profile instead.
    func continueWithoutAccount() {
        let defaults = UserDefaults.standard
        let id = ProfileKeys.newLocalProfileId()
        defaults.set(id, forKey: ProfileKeys.localProfileId)
        defaults.removeObject(forKey: ProfileKeys.localProfileName)
        defaults.removeObject(forKey: ProfileKeys.localProfileEmail)
        defaults.set(LoginType.local.rawValue, forKey: ProfileKeys.loginType)
        migrateUnscopedLegacyData()
        defaults.removeObject(forKey: UserScope.key("hasCompletedOnboarding"))
        signIn()
        Analytics.profileCreated(kind: .local)
    }

    /// Restores an earlier profile found on this device or in iCloud and makes it active.
    /// The currently active profile's data stays on this device.
    func switchToProfile(_ profile: DiscoveredProfile) {
        if isSignedIn || UserScope.userId != nil {
            signOut()
        }
        ProfileRestore.activate(profile, defaults: .standard)
        signIn()
    }

    /// Inactive earlier profiles found on this device and (when reachable) in iCloud.
    func discoverRestorableProfiles(cloudSource: CloudProfileRecordSource? = nil) async -> [DiscoveredProfile] {
        let activeId = UserScope.userId
        let device = ProfileDiscovery.deviceProfiles(defaults: .standard, excluding: activeId)
        let source: CloudProfileRecordSource = cloudSource ?? syncService
        let cloud: [DiscoveredProfile]
        do {
            cloud = ProfileDiscovery.cloudProfiles(
                from: try await source.fetchProfileRecordSummaries(),
                excluding: activeId
            )
        } catch {
            cloud = []
        }
        return ProfileDiscovery.merge(device: device, cloud: cloud)
    }

    /// Call when a new account is created (not for returning sign-in).
    func signUp() {
        // New user — delete any stale unscoped data so it doesn't leak
        Self.clearUnscopedLegacyData()
        // Clear onboarding flag so new user sees onboarding flow
        UserDefaults.standard.removeObject(forKey: UserScope.key("hasCompletedOnboarding"))
        signIn()
        // signUp() is only called for a brand-new Sign in with Apple profile.
        Analytics.profileCreated(kind: .apple)
    }

    /// Signs out / switches away from the active profile. Per-profile data stays on the
    /// device under `u.<id>.*`.
    ///
    /// - Parameter keepProfileState: false only when the profile's data was just deleted,
    ///   so nothing is written back into the deleted scope.
    func signOut(keepProfileState: Bool = true) {
        // Stop CloudKit sync
        syncService.stop()
        endAwaitingInitialPull()
        // Background work belongs to the outgoing profile: stop it, never finish it into the next.
        BackfillJob.shared.reset()
        ExportJob.shared.reset()
        let defaults = UserDefaults.standard
        let outgoingId = UserScope.userId

        // Timer: stop the visible timer and save its state to THIS profile while its ID
        // is still set. (Before 1.1 this ran after the ID was cleared and wrote unscoped
        // `LandlordHours.timer*` keys.) A running timer resumes — or is offered for
        // recovery if stale — when the profile comes back.
        if keepProfileState, let outgoingId {
            // Pause a running timer at switch time: record the elapsed time as a recovery
            // draft for this profile (offered when the profile comes back) instead of
            // leaving the timer counting while another profile is active.
            if isTimerRunning, let start = timerStartTime, let propertyId = timerPropertyId {
                saveStaleTimerRecovery(StaleTimerRecovery(
                    startTime: start,
                    propertyId: propertyId,
                    category: timerCategory,
                    elapsedHours: max(Date().timeIntervalSince(start), 0) / 3600.0,
                    reason: .pausedAtSwitch,
                    pausedAt: Date()
                ))
                endTimerLiveActivity(propertyId: propertyId, category: timerCategory, startDate: start, needsReview: true)
                isTimerRunning = false
                timerStartTime = nil
                timerPropertyId = nil
            }
            saveTimerState()
            if defaults.string(forKey: ProfileKeys.localProfileId) == outgoingId,
               let name = defaults.string(forKey: ProfileKeys.localProfileName), !name.isEmpty {
                defaults.set(name, forKey: UserScope.key(ProfileRestore.profileNameKey, userId: outgoingId))
            }
            defaults.set(outgoingId, forKey: ProfileKeys.previousProfileId)
        }
        endTimerLiveActivity(propertyId: timerPropertyId, category: timerCategory, startDate: timerStartTime, needsReview: false)

        // Clear auth keys (unscoped — shared on device)
        for key in ProfileKeys.signOutKeys {
            defaults.removeObject(forKey: key)
        }
        // Clear any stale unscoped legacy data to prevent leaking to next user
        Self.clearUnscopedLegacyData()
        // Note: per-user data stays in UserDefaults under scoped keys (u.<userId>.*)

        // Reset in-memory timer state only; never persist it after the ID is gone.
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil
        timerCategory = .repairs
        staleTimerRecovery = nil

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
        AppleSignInManager.shared.signOut()
    }

    enum ProfileDeletionError: LocalizedError, Equatable {
        /// iCloud is off/unreachable, so copies saved there can't be removed now.
        case iCloudUnavailable

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return "iCloud is off, so copies saved there can't be removed now. Delete from this iPhone anyway, or turn on iCloud and retry?"
            }
        }
    }

    /// Deletes the active profile's data (Apple: "Delete Account and Data"; local:
    /// "Delete All Data"): iCloud records, scoped keys, attachment files and
    /// notification keys, then signs out.
    ///
    /// - Parameter allowLocalOnly: when iCloud is unavailable the call throws
    ///   `ProfileDeletionError.iCloudUnavailable` BEFORE deleting anything, unless the
    ///   user explicitly chose "Delete from this iPhone anyway".
    func deleteAccountAndData(allowLocalOnly: Bool = false) async throws {
        guard let userId = UserScope.userId else {
            signOut()
            return
        }

        syncService.stop()
        if !syncService.accountAvailable {
            await syncService.checkAccountStatus()
        }
        if syncService.accountAvailable {
            try await syncService.deleteCurrentUserRecords(
                properties: properties,
                entries: timeEntries,
                categories: CategoryManager.shared.customCategories,
                userId: userId
            )
        } else if !allowLocalOnly {
            throw ProfileDeletionError.iCloudUnavailable
        }

        // Photo files are not keyed by user; delete the ones this profile references.
        deleteAttachmentFiles(for: timeEntries)
        Self.clearScopedAccountData(for: userId)

        properties = []
        timeEntries = []
        activeCelebration = nil
        endTimerLiveActivity(propertyId: timerPropertyId, category: timerCategory, startDate: timerStartTime, needsReview: false)
        isTimerRunning = false
        timerStartTime = nil
        timerPropertyId = nil

        signOut(keepProfileState: false)
        let defaults = UserDefaults.standard
        if defaults.string(forKey: ProfileKeys.previousProfileId) == userId {
            defaults.removeObject(forKey: ProfileKeys.previousProfileId)
        }
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
            ProfileRestore.profileNameKey,
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
        triggerCelebration(.propertyAdded)
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

    private static let saveFailureMessage =
        "Couldn't save your latest changes — free up space and try again."
    private static let loadFailureMessage =
        "Couldn't open your saved records. They're still on your device — reopen the app, and contact support if this keeps happening."

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
            targetHours: goal.hoursRequired,
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
        WidgetCenter.shared.reloadTimelines(ofKind: EngagementWidgetSnapshotStore.widgetKind)
    }

    private func widgetGoalContext() -> (targetHours: Double, label: String, shortLabel: String) {
        let goal = GoalManager.shared.globalGoalType
        let hours = goal.hoursRequired
        let short = "\(Int(hours))h"
        switch goal {
        case .reps: return (hours, "\(short) REPS", short)
        case .str: return (hours, "\(short) STR", short)
        case .both: return (hours, "\(short) REPS + STR", short)
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
        defaults.removeObject(forKey: ProfileKeys.emailUserId)
        defaults.removeObject(forKey: ProfileKeys.emailUserName)
        defaults.removeObject(forKey: ProfileKeys.emailUserEmail)
        defaults.set(userId, forKey: ProfileKeys.localProfileId)
        defaults.set(Self.launchMockEmail(defaultValue: "brianlevu@gmail.com"), forKey: ProfileKeys.localProfileEmail)
        defaults.set(Self.launchMockName(defaultValue: scenario.userName), forKey: ProfileKeys.localProfileName)
        defaults.set(LoginType.local.rawValue, forKey: ProfileKeys.loginType)

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
