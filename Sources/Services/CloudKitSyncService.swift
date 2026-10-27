import Foundation
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.openclaw.landlordhours", category: "CloudKit")

// MARK: - Sync Delegate

@MainActor
protocol CloudKitSyncDelegate: AnyObject {
    func syncDidReceiveProperties(_ properties: [RentalProperty])
    func syncDidReceiveEntries(_ entries: [TimeEntry])
    func syncDidDeletePropertyIds(_ ids: Set<UUID>)
    func syncDidDeleteEntryIds(_ ids: Set<UUID>)
    func syncDidReceiveCategories(_ categories: [CustomCategory])
    func syncDidReceiveGoalSettings(globalGoalType: HourGoalType, propertyGoals: [PropertyGoal], materialParticipationTarget: Int?)
    func syncDidReceiveTaxProfile(_ fields: TaxProfileFields)
}

/// Lightweight struct for passing tax profile data from CloudKit
struct TaxProfileFields {
    var filingStatus: String
    var spouseTracking: Bool
    var taxYear: Int
    var groupingElection: Bool
    var nonREWorkHours: Double
    var modifiedAt: Date
}

// MARK: - CloudKit Sync Service
//
// 2.2 (package K): one record set per iCloud account. There is no owner filter on the pull any
// more: every change goes through `RecordSetMigration.applyPull`, which routes it by membership
// (R20), by owner (R10/R12) and by `sourceKey` (R19), sends pulled deletes to Recently removed
// and asks before applying a bulk delete (P28). Pushes go per record type, non-atomic, so one
// missing type in the Production schema can never block every other record (the 1.x failure).
// A zone deleted on another device is never recreated on its own (P31).

@MainActor
final class CloudKitSyncService: ObservableObject {

    // MARK: Public state
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var accountAvailable = false
    /// The last account status, in package K's words (status row, P8/P9, `.restricted`).
    @Published private(set) var accountState: ICloudAccountState = .couldNotDetermine

    weak var delegate: CloudKitSyncDelegate?
    /// The record-set engine (owned by `IdentityCoordinator`). Pulls and pushes go through it.
    weak var engine: RecordSetMigration?
    /// Called after a pull or push changed what the identity surfaces show.
    var onIdentityChange: (() -> Void)?
    /// Called with the scope id once its initial pull has finished and the push gate opened.
    var onInitialSyncCompleted: ((String) -> Void)?
    /// Called with the scope id whenever its initial pull succeeds, by any path (launch, Sync
    /// Now, iCloud coming back, a notification action's retry).
    var onInitialPullSucceeded: ((String) -> Void)?
    /// False when this build has no CloudKit (simulator, missing entitlement).
    var isCloudKitAvailable: Bool { container != nil }

    // MARK: Private
    private let container: CKContainer?
    private var database: CKDatabase? { container?.privateCloudDatabase }
    /// DEBUG device tests run against a throwaway zone in the Development container, never the
    /// person's `LandlordHoursZone` (DevelopmentContainerSyncTests).
    var zoneIDOverride: CKRecordZone.ID?
    private var zoneID: CKRecordZone.ID { zoneIDOverride ?? IdentityZone.zoneID }
    /// The scope the push gate and the baselines are keyed by (`UserScope.userId`).
    private var appUserId: String? { UserScope.userId }
    /// The owner tag every pushed record carries: the unified id (§4.6).
    private var ownerTag: String? { IdentityScope.unifiedId() }

    private var zoneTokenKey: String { UserScope.key("cloudkit.zoneChangeToken") }
    private var subscriptionCreatedKey: String { UserScope.key("cloudkit.subscriptionCreated") }

    private var pushDebounceTask: Task<Void, Never>?

    /// Scope whose initial sync (the cloud phase, or a first pull) has finished. Pushes for any
    /// other scope are held until it has, so default local state never overwrites iCloud.
    private(set) var initialSyncCompletedFor: String?
    /// A push requested while the initial sync was running; flushed once it completes.
    private(set) var hasHeldPush = false
    /// Instrumentation for tests: push requests received / held by the gate.
    private(set) var pushRequestCount = 0
    private(set) var heldPushRequestCount = 0
    /// Counter-based guard to prevent push loops when merging remote changes.
    private var remoteUpdateDepth = 0

    /// Maximum retry attempts for transient CloudKit errors.
    private let maxRetries = 3

    // MARK: - Lifecycle

    init() {
        if Self.hasCloudKitEntitlement {
            container = CKContainer(identifier: "iCloud.com.openclaw.landlordhours")
        } else {
            container = nil
            accountState = .unsupported
            logger.warning("CloudKit disabled: missing iCloud CloudKit entitlement")
        }
        accountChangeObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleAccountChanged() }
        }
    }

    /// The steps `start()` runs. Production uses CloudKit and the engine; tests inject fakes.
    struct InitialSyncOperations {
        var accountAvailable: () async -> Bool
        var prepare: () async -> Void
        var push: () async -> Void
        /// Returns true when the pull (or the cloud phase) reached iCloud and merged.
        var pull: () async -> Bool
    }

    /// Test seam: when set, `start()` uses these instead of CloudKit.
    var operationsOverride: InitialSyncOperations?
    @Published private(set) var isRunningInitialSync = false
    private(set) var accountStatusCheckCount = 0
    /// The last account check couldn't tell (network error, temporarily unavailable).
    private(set) var accountStatusUnknown = false
    private var accountChangeObserver: NSObjectProtocol?
    private(set) var flushedHeldPushCount = 0

    static let heldChangesMessage = "Couldn’t reach iCloud. Your changes are safe on this iPhone and will sync when iCloud is back."

    /// The engine's own zone source when a DEBUG fake replaces iCloud; otherwise `self`.
    weak var zoneSourceOverride: IdentityZoneSource?
    private var zoneSource: IdentityZoneSource { zoneSourceOverride ?? self }

    private var liveOperations: InitialSyncOperations {
        InitialSyncOperations(
            accountAvailable: { [weak self] in
                guard let self else { return false }
                if let fake = self.zoneSourceOverride {
                    let state = await fake.accountState()
                    self.accountState = state
                    self.accountAvailable = state == .available
                    self.accountStatusCheckCount += 1
                    return self.accountAvailable
                }
                guard self.container != nil else { return false }
                // A DEBUG mock scope (captures, mock scenarios) never meets the real zone.
                guard !IdentityScope.isDebugScope() else { return false }
                await self.checkAccountStatus()
                return self.accountAvailable
            },
            prepare: { [weak self] in
                guard let self, self.zoneSourceOverride == nil else { return }
                await self.ensureSubscriptionExists()
            },
            push: { [weak self] in await self?.performPushAll() },
            pull: { [weak self] in
                guard let self else { return false }
                // Until the migration is done, the cloud phase IS the initial pull (S5–S10).
                if let engine = self.engine, engine.step < .done {
                    let outcome = await engine.runCloudPhase()
                    self.onIdentityChange?()
                    switch outcome {
                    case .done:
                        self.lastSyncDate = Date()
                        return true
                    case .zoneGone, .accountChanged:
                        self.syncError = nil
                        return false
                    case .incomplete(let problem), .pushFailed(let problem):
                        self.syncError = problem
                        return false
                    case .iCloudOff, .notReady:
                        return false
                    }
                }
                return await self.pullChanges()
            }
        )
    }

    /// Initial sync for the active scope, then opens the push gate and flushes any held push.
    func start() async {
        if !isDeletingAccount { pushesBlocked = false }
        if let running = initialSyncTask {
            rerunRequested = true
            await running.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRunningInitialSync = true
            defer {
                self.isRunningInitialSync = false
                self.initialSyncTask = nil
                self.onIdentityChange?()   // "Syncing…" ends: the status row says what happened
            }
            repeat {
                self.rerunRequested = false
                await self.runInitialSyncOnce()
            } while self.rerunRequested
        }
        initialSyncTask = task
        await task.value
    }

    private var rerunRequested = false
    private var initialSyncTask: Task<Void, Never>?

    private func runInitialSyncOnce() async {
        let startingFor = appUserId
        if initialSyncCompletedFor != startingFor { initialSyncCompletedFor = nil }
        let ops = operationsOverride ?? liveOperations
        guard await ops.accountAvailable() else {
            accountAvailable = false
            onIdentityChange?()   // the status row and Today's P10 learn that iCloud is off
            return
        }
        accountAvailable = true
        await ops.prepare()
        var pullSucceeded = false
        // 2.2: always pull (or run the cloud phase) before any push; the engine pushes the merged
        // set itself at S9. Empty local state never overwrites iCloud.
        await Self.runInitialSync(defaults: .standard, pullFirst: true, migrationDoneKey: UserScope.key("cloudkit.migrationDone"),
                                  hasLocalData: false, push: { await ops.push() }, pull: { pullSucceeded = await ops.pull() })
        guard appUserId == startingFor, startingFor != nil else { return }
        guard pullSucceeded else {
            if hasHeldPush { syncError = Self.heldChangesMessage }
            return
        }
        initialSyncCompletedFor = startingFor
        if hasHeldPush {
            hasHeldPush = false
            flushedHeldPushCount += 1
            await ops.push()
        } else if !(changeTracker?.pendingDeletes.isEmpty ?? true) || operationsOverride == nil {
            await ops.push()
        }
        if let startingFor {
            onInitialPullSucceeded?(startingFor)
            onInitialSyncCompleted?(startingFor)
        }
    }

    /// Manual "Sync now": runs the initial sync first when the gate isn't open yet, then pushes
    /// and pulls. Never holds silently.
    func syncNow() async {
        if isRunningInitialSync {
            syncError = nil
            return
        }
        if !isPushAllowed {
            await start()
        }
        guard isPushAllowed else {
            if !accountAvailable {
                syncError = String(localized: "iCloud is off. Turn on iCloud for LandlordHours in Settings to sync.", table: "Identity")
            } else if syncError == nil {
                syncError = Self.heldChangesMessage
            }
            return
        }
        await pushAll()
        _ = await pullChanges()
    }

    static func isPushAllowed(initialSyncCompletedFor: String?, appUserId: String?) -> Bool {
        guard let appUserId else { return false }
        return initialSyncCompletedFor == appUserId
    }

    private var isPushAllowed: Bool {
        Self.isPushAllowed(initialSyncCompletedFor: initialSyncCompletedFor, appUserId: appUserId)
    }

    /// Initial-sync ordering, extracted so tests can drive it with fakes.
    static func runInitialSync(
        defaults: UserDefaults,
        pullFirst: Bool = false,
        migrationDoneKey: String,
        hasLocalData: Bool,
        push: () async -> Void,
        pull: () async -> Void
    ) async {
        if pullFirst {
            await pull()
            return
        }
        let migrationDone = defaults.bool(forKey: migrationDoneKey)
        if !migrationDone && hasLocalData {
            await push()
            defaults.set(true, forKey: migrationDoneKey)
            await pull()
            return
        }
        await pull()
        if !migrationDone {
            defaults.set(true, forKey: migrationDoneKey)
        }
    }

    func stop() {
        pushDebounceTask?.cancel()
        pushDebounceTask = nil
        initialSyncCompletedFor = nil
        hasHeldPush = false
    }

    // MARK: - Account Status

    func checkAccountStatus() async {
        accountStatusCheckCount += 1
        if let fake = zoneSourceOverride {
            accountState = await fake.accountState()
            accountAvailable = accountState == .available
            return
        }
        guard let container else {
            accountAvailable = false
            accountState = .unsupported
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHFakeICloudHang") {
            try? await Task.sleep(for: .seconds(3600))
            return
        }
        #endif
        do {
            let status = try await container.accountStatus()
            let wasAvailable = accountAvailable
            accountAvailable = (status == .available)
            accountState = Self.state(status)
            accountStatusUnknown = status == .couldNotDetermine || status == .temporarilyUnavailable
            if accountAvailable, !wasAvailable, !isRunningInitialSync,
               appUserId != nil, initialSyncCompletedFor != appUserId {
                Task { await self.start() }
            }
        } catch {
            accountAvailable = false
            accountStatusUnknown = true
            accountState = .couldNotDetermine
            logger.error("Account status error: \(error.localizedDescription)")
        }
    }

    nonisolated static func state(_ status: CKAccountStatus) -> ICloudAccountState {
        switch status {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .temporarilyUnavailable: return .temporarilyUnavailable
        case .couldNotDetermine: return .couldNotDetermine
        @unknown default: return .couldNotDetermine
        }
    }

    // MARK: - Zone Setup

    /// Creates the zone. Only ever called before this device first synced, or when the person
    /// answered "Keep this iPhone's copy" to P31: a zone deleted elsewhere is never recreated on
    /// our own.
    func createZone() async throws {
        guard let database else { throw CloudKitSyncUnavailableError() }
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
    }

    // MARK: - Subscription

    private func ensureSubscriptionExists() async {
        guard let database else { return }
        guard !UserDefaults.standard.bool(forKey: subscriptionCreatedKey) else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: "private-db-changes")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await database.save(subscription)
            UserDefaults.standard.set(true, forKey: subscriptionCreatedKey)
        } catch {
            if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                UserDefaults.standard.set(true, forKey: subscriptionCreatedKey)
            } else {
                logger.error("Subscription error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Push (Local → Cloud)

    /// Debounced push — waits 2 seconds after last call before actually pushing.
    func schedulePush() {
        pushRequestCount += 1
        guard remoteUpdateDepth == 0 else { return }
        guard !pushesBlocked else { return }
        guard isPushAllowed else {
            heldPushRequestCount += 1
            hasHeldPush = true
            return
        }
        guard container != nil || zoneSourceOverride != nil else { return }
        pushDebounceTask?.cancel()
        pushDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await pushAll()
        }
    }

    /// Push changed local data to CloudKit (manual "Sync now" and debounced edits).
    func pushAll() async {
        guard isPushAllowed else {
            hasHeldPush = true
            return
        }
        await performPushAll()
    }

    private func performPushAll() async {
        guard accountAvailable, !pushesBlocked else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
        if let engine {
            // Never push into an iCloud account the set wasn't read from (P13).
            guard await engine.confirmAccount() == .same else { onIdentityChange?(); return }
            guard !pushesBlocked else { return }
            let task = Task { @MainActor in await engine.pushLive() }
            enginePushTask = task
            let report = await task.value
            if report.zoneGone {
                _ = engine.handleZoneGone()
                onIdentityChange?()
                return
            }
            if !report.failedTypes.isEmpty {
                syncError = report.quotaExceeded
                    ? String(localized: "iCloud is full. Your records are safe on this iPhone; free up iCloud space to keep syncing.", table: "Identity")
                    : String(localized: "Some records couldn’t be saved to iCloud. They’ll be tried again.", table: "Identity")
            } else {
                lastSyncDate = Date()
            }
            onIdentityChange?()
            return
        }
        do {
            try await pushChangedRecords(
                save: { records in try await self.withRetry { [records] in try await self.batchSaveLegacy(records) } },
                delete: { ids in try await self.withRetry { [ids] in try await self.batchDelete(ids) } }
            )
            lastSyncDate = Date()
        } catch {
            syncError = error.localizedDescription
            logger.error("Push error: \(error.localizedDescription)")
        }
    }

    // MARK: - Push changed records only (no engine: unit tests)

    /// Test seam: where the per-scope push baselines live.
    var changeTrackerBaseDirectory: URL = SyncChangeTracker.defaultBaseDirectory
    private var cachedChangeTracker: SyncChangeTracker?

    /// The active scope's push baselines.
    var changeTracker: SyncChangeTracker? {
        guard let appUserId else { return nil }
        if let cachedChangeTracker, cachedChangeTracker.userId == appUserId,
           cachedChangeTracker.fileURL.path.hasPrefix(changeTrackerBaseDirectory.path) {
            return cachedChangeTracker
        }
        let tracker = SyncChangeTracker(userId: appUserId, baseDirectory: changeTrackerBaseDirectory)
        cachedChangeTracker = tracker
        return tracker
    }

    /// Every local record under the owner tag.
    func allLocalRecords() -> [CKRecord] {
        if let engine { return engine.liveZoneRecords().map { $0.ckRecord(zoneID: zoneID) } }
        var records: [CKRecord] = []
        let viewModel = getViewModel()
        for property in viewModel?.properties ?? [] { records.append(Self.record(for: property, zoneID: zoneID, appUserId: ownerTag)) }
        for entry in viewModel?.timeEntries ?? [] { records.append(Self.record(for: entry, zoneID: zoneID, appUserId: ownerTag)) }
        for category in CategoryManager.shared.customCategories { records.append(Self.record(for: category, zoneID: zoneID, appUserId: ownerTag)) }
        return records
    }

    /// Sends pending deletes, then only the records that differ from the server baseline.
    @discardableResult
    func pushChangedRecords(
        save: @escaping ([CKRecord]) async throws -> Void,
        delete: @escaping ([CKRecord.ID]) async throws -> Void
    ) async throws -> [CKRecord] {
        let previous = pushChain
        let task = Task { @MainActor () throws -> [CKRecord] in
            await previous?.value
            guard !self.pushesBlocked else { return [] }
            return try await self.pushChangedRecordsNow(save: save, delete: delete)
        }
        pushChain = Task { _ = try? await task.value }
        return try await task.value
    }

    private var pushChain: Task<Void, Never>?
    /// Set while everything is being deleted: no push may run or start.
    private(set) var pushesBlocked = false
    private var isDeletingAccount = false

    /// Stops all pushing before Delete all data, and waits for any push already in flight.
    func quiescePushes() async {
        pushesBlocked = true
        pushDebounceTask?.cancel()
        pushDebounceTask = nil
        initialSyncCompletedFor = nil
        hasHeldPush = false
        await pushChain?.value
        // The engine's pushes and the cloud phase push too: wait for both.
        await enginePushTask?.value
        await initialSyncTask?.value
    }

    /// The engine push in flight (`performPushAll`), awaited by `quiescePushes`.
    private var enginePushTask: Task<ZonePushReport, Never>?

    private func pushChangedRecordsNow(
        save: ([CKRecord]) async throws -> Void,
        delete: ([CKRecord.ID]) async throws -> Void
    ) async throws -> [CKRecord] {
        let tracker = changeTracker
        tracker?.cancelTombstones(for: Set(allLocalRecords().map(\.recordID.recordName)))
        if let tombstones = tracker?.pendingDeletes, !tombstones.isEmpty {
            try await delete(tombstones.map { CKRecord.ID(recordName: $0, zoneID: zoneID) })
            tracker?.clearTombstones(tombstones)
        }
        let all = allLocalRecords()
        let changed = tracker?.changedRecords(all) ?? all
        guard !changed.isEmpty else { return [] }
        try await save(changed)
        tracker?.recordServerState(changed)
        return changed
    }

    private func batchDelete(_ ids: [CKRecord.ID]) async throws {
        guard let database else { throw CloudKitSyncUnavailableError() }
        for offset in stride(from: 0, to: ids.count, by: 400) {
            let batch = Array(ids[offset..<min(offset + 400, ids.count)])
            let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)
            op.qualityOfService = .userInitiated
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error):
                        if Self.isDeleteMissingRecordsOnly(error) { continuation.resume(); return }
                        continuation.resume(throwing: error)
                    }
                }
                database.add(op)
            }
        }
    }

    private func batchSaveLegacy(_ records: [CKRecord]) async throws {
        let report = await saveRecordsPerType(records)
        if !report.failedTypes.isEmpty { throw CKError(CKError.Code(rawValue: report.failedTypes.values.first ?? 1) ?? .internalError) }
    }

    /// The zone was deleted ("Delete all data" elsewhere, a reset) or never existed.
    nonisolated static func isZoneGone(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        let gone: (CKError.Code) -> Bool = { $0 == .zoneNotFound || $0 == .userDeletedZone }
        if gone(ckError.code) { return true }
        if ckError.code == .partialFailure {
            let codes = ckError.partialErrorsByItemID?.values.compactMap { ($0 as? CKError)?.code } ?? []
            return !codes.isEmpty && codes.allSatisfy(gone)
        }
        return false
    }

    /// Forgets what this device believed the server holds (every local record is re-uploaded).
    func resetSyncBaselines() {
        changeTracker?.resetBaselines()
    }

    /// A different (or no) iCloud account. Steady state: compare the iCloud user; a different
    /// one pauses sync and asks (P13). Never pushes into the new account on its own.
    func handleAccountChanged() async {
        initialSyncCompletedFor = nil
        engine?.accountMayHaveChanged()
        await checkAccountStatus()
        guard accountAvailable else { return }
        if let stored = UserDefaults.standard.string(forKey: IdentityKeys.icloudUserRecordName),
           let current = await userRecordName(), stored != current {
            UserDefaults.standard.set(true, forKey: IdentityKeys.accountChanged)
            onIdentityChange?()
            return
        }
        if !isRunningInitialSync, appUserId != nil { await start() }
    }

    /// No engine (unit tests of the push path): the pulled copies become the baseline.
    func recordPulledBaselines(properties: [RentalProperty], entries: [TimeEntry], categories: [CustomCategory],
                               deletedRecordNames: [String], goalSettingsPulled: Bool, taxProfilePulled: Bool) {
        guard let tracker = changeTracker else { return }
        var records = properties.map { Self.record(for: $0, zoneID: zoneID, appUserId: ownerTag) }
        records += entries.map { Self.record(for: $0, zoneID: zoneID, appUserId: ownerTag) }
        records += categories.map { Self.record(for: $0, zoneID: zoneID, appUserId: ownerTag) }
        tracker.recordServerState(records)
        tracker.forget(recordNames: deletedRecordNames)
    }

    // MARK: - Pull (Cloud → Local)

    @discardableResult
    func pullChanges() async -> Bool {
        guard accountAvailable else { return false }
        guard !UserDefaults.standard.bool(forKey: IdentityKeys.zoneGone), !UserDefaults.standard.bool(forKey: IdentityKeys.accountChanged) else { return false }
        // Never pull another iCloud account's records into this set (P13). This runs before every
        // pull, so it also covers start() racing handleAccountChanged and a switch made while the
        // app was closed.
        if let engine, await engine.confirmAccount() != .same {
            onIdentityChange?()
            return false
        }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
        do {
            let token = loadZoneToken()
            let delta: ZoneDelta
            do {
                delta = try await zoneSource.deltaPull(from: token)
            } catch ZoneSourceError.tokenExpired {
                // v3 §4.10: drop the token, read the whole zone, find deletes with R5's guards.
                return await recoverFromExpiredToken()
            }
            remoteUpdateDepth += 1
            defer { remoteUpdateDepth -= 1 }
            if let engine {
                engine.applyPull(delta)
                onIdentityChange?()
            }
            // The token moves only after the changes are applied (a crash in between re-pulls
            // them; applying a delta twice changes nothing), and only past a complete delta: a
            // record CloudKit couldn't hand over comes again on the next pull.
            if delta.incomplete {
                logger.error("Pull incomplete: keeping the change token to fetch the missed records again")
            } else {
                saveZoneToken(delta.tokenData)
            }
            lastSyncDate = Date()
            UserDefaults.standard.set(true, forKey: IdentityKeys.hasSynced)
            return true
        } catch ZoneSourceError.zoneGone {
            if let engine { _ = engine.handleZoneGone(); onIdentityChange?() }
            return false
        } catch {
            syncError = error.localizedDescription
            logger.error("Pull error: \(error.localizedDescription)")
            return false
        }
    }

    private func recoverFromExpiredToken() async -> Bool {
        saveZoneToken(nil)
        let snapshot = await zoneSource.readWholeZone()
        guard !snapshot.incomplete else {
            syncError = snapshot.problem
            return false
        }
        guard snapshot.zoneExists else {
            if let engine { _ = engine.handleZoneGone(); onIdentityChange?() }
            return false
        }
        guard let engine else { saveZoneToken(snapshot.tokenData); return true }
        // Everything present is a change; synced-and-absent live records are deletes (R5 guards).
        let tracker = engine.tracker
        let liveNames = engine.routingContext().liveNames
        let absent = Set(tracker.contents.fingerprints.keys).intersection(liveNames).subtracting(snapshot.presentNames)
        let guards = MergeRules.AbsenceGuards(readComplete: true, zoneExists: true, sameAccount: true)
        var deleted: [String: String] = [:]
        switch MergeRules.absence(fingerprinted: Set(tracker.contents.fingerprints.keys).intersection(liveNames),
                                  onDevice: liveNames, present: snapshot.presentNames, guards: guards) {
        case .removed(let names), .paused(let names):
            for name in names { deleted[name] = "TimeEntry" }
        default:
            break
        }
        _ = absent
        remoteUpdateDepth += 1
        defer { remoteUpdateDepth -= 1 }
        engine.applyPull(ZoneDelta(changed: snapshot.records, deleted: deleted, tokenData: snapshot.tokenData, incomplete: false),
                         deleteReason: .inferredAbsent)
        saveZoneToken(snapshot.tokenData)   // after the read is applied, never before
        onIdentityChange?()
        lastSyncDate = Date()
        return true
    }

    // MARK: - Delete from Cloud

    /// Records a local property delete (its entries too). Every delete goes through the
    /// serialized push (tombstone → push → clear).
    func deletePropertyFromCloud(_ property: RentalProperty, cascadedEntryIds: [UUID] = []) {
        recordLocalDeletes([property.id.uuidString] + cascadedEntryIds.map(\.uuidString))
    }

    func deleteEntryFromCloud(_ entry: TimeEntry) {
        recordLocalDeletes([entry.id.uuidString])
    }

    private func recordLocalDeletes(_ names: [String]) {
        guard let tracker = changeTracker else {
            logger.error("Delete of \(names.count) record(s) not queued for iCloud: no record set yet")
            return
        }
        tracker.forget(recordNames: names)
        tracker.addTombstones(names)
        engine?.noteDeleted(Set(names))
        schedulePush()
    }

    /// The delete could not reach iCloud. Nothing was deleted, here or there.
    struct AccountDeleteICloudUnreachableError: LocalizedError, Equatable {
        var errorDescription: String? {
            String(localized: "Couldn’t reach iCloud. Your data hasn’t been deleted. Try again when you’re online.", table: "Identity")
        }
    }

    /// The phone is signed in to a different iCloud account than the record set came from:
    /// Delete all data never deletes that account's zone (only this iPhone's copy, if asked).
    struct OtherICloudAccountError: LocalizedError, Equatable {
        var errorDescription: String? {
            String(localized: "This iPhone is signed in to a different iCloud account. Nothing in that iCloud was deleted.", table: "Identity")
        }
    }

    /// Test seam for `deleteEverythingInICloud`.
    var zoneDeleteOverride: (() async throws -> Void)?

    /// Delete all data, iCloud side: the whole zone, one atomic operation (§1.4). Throws before
    /// anything local is touched when iCloud can't be reached.
    func deleteEverythingInICloud() async throws {
        // Only the zone of the account the record set came from (P13 pauses everything else).
        if UserDefaults.standard.bool(forKey: IdentityKeys.accountChanged) { throw OtherICloudAccountError() }
        if let engine {
            switch await engine.confirmAccount() {
            case .same: break
            case .changed: throw OtherICloudAccountError()
            case .unknown:
                // Can't tell who is signed in: refuse only when there is an account to compare.
                if engine.defaults.string(forKey: IdentityKeys.icloudUserRecordName) != nil { throw AccountDeleteICloudUnreachableError() }
            }
        }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        await quiescePushes()
        do {
            if let zoneDeleteOverride {
                try await zoneDeleteOverride()
            } else {
                try await zoneSource.deleteZone()
            }
        } catch {
            pushesBlocked = false
            throw error
        }
        saveZoneToken(nil)
        changeTracker?.reset()
        cachedChangeTracker = nil
        lastSyncDate = Date()
    }

    // MARK: - Record Mapping: Property

    /// 2.0 classifier fields on the Property record type. Additive and never written as nil,
    /// so pushes from 1.1 (which never set them) leave the server values alone under
    /// `.changedKeys`. Add each to the DEVELOPMENT schema, then deploy to Production before any
    /// 2.0 build reaches users.
    enum PropertyField {
        static let aliases = "aliases"                  // String (list); always written, may be empty
        static let aliasCount = "aliasCount"            // Int64; always written (0 = cleared)
        static let isOwnerOccupied = "isOwnerOccupied"  // Int64 0/1; always written
        static let all = [aliases, aliasCount, isOwnerOccupied]
    }

    /// RentalProperty → CKRecord. The 2.0 fields are ALWAYS written (never nil), so clearing
    /// every alias or turning "I live here" off syncs to other devices. An empty list may come
    /// back from the server as missing; `aliasCount` 0 is what marks it cleared. Requires the
    /// Production schema deploy (a release gate) before any 2.0 build ships.
    nonisolated static func record(for property: RentalProperty, zoneID: CKRecordZone.ID, appUserId: String?) -> CKRecord {
        let recordID = CKRecord.ID(recordName: property.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "Property", recordID: recordID)
        record["name"] = property.name
        record["address"] = property.address
        record["propertyType"] = property.propertyType.rawValue
        record["createdAt"] = property.createdAt
        record["modifiedAt"] = property.modifiedAt
        let aliases = RentalProperty.cleanedAliases(property.aliases)
        record[PropertyField.aliases] = aliases
        record[PropertyField.aliasCount] = Int64(aliases.count)
        record[PropertyField.isOwnerOccupied] = Int64(property.isOwnerOccupied ? 1 : 0)
        if let appUserId { record["appUserId"] = appUserId }
        return record
    }

    /// CKRecord → RentalProperty. Records written by 1.1 lack the 2.0 fields: no aliases,
    /// not owner-occupied.
    nonisolated static func property(from record: CKRecord) -> RentalProperty? {
        guard let name = record["name"] as? String,
              let address = record["address"] as? String,
              let typeRaw = record["propertyType"] as? String,
              let type = PropertyType(rawValue: typeRaw),
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }

        var property = RentalProperty(id: id, name: name, address: address, propertyType: type)
        property.createdAt = record["createdAt"] as? Date ?? Date()
        property.modifiedAt = record["modifiedAt"] as? Date ?? property.createdAt
        let count = (record[PropertyField.aliasCount] as? Int64) ?? (record[PropertyField.aliasCount] as? NSNumber)?.int64Value
        if count == 0 {
            property.aliases = []
        } else {
            property.aliases = RentalProperty.cleanedAliases(record[PropertyField.aliases] as? [String] ?? [])
        }
        let occupied = (record[PropertyField.isOwnerOccupied] as? Int64) ?? (record[PropertyField.isOwnerOccupied] as? NSNumber)?.int64Value
        property.isOwnerOccupied = (occupied ?? 0) != 0
        return property
    }

    // MARK: - Record Mapping: TimeEntry

    /// 2.0 capture fields on the TimeEntry record type. Additive: written only when non-nil, so
    /// a push never sends a nil for them, and pushes from 1.1 (which never set them) leave the
    /// server values alone under `.changedKeys`. Add each to the DEVELOPMENT schema, then
    /// deploy to Production before any 2.0 build reaches users.
    enum CaptureEntryField {
        static let detectedAt = "detectedAt"        // Date/Time
        static let confirmedAt = "confirmedAt"      // Date/Time
        static let sourceDetail = "sourceDetail"    // String
        static let sourceKey = "sourceKey"          // String
        static let recordDescription = "recordDescription"  // String (Log time description)
        static let all = [detectedAt, confirmedAt, sourceDetail, sourceKey, recordDescription]
    }

    /// TimeEntry → CKRecord. The record name is the entry id; for confirmed suggestions that id
    /// is derived from the source key, so two devices confirming one event write one record.
    nonisolated static func record(for entry: TimeEntry, zoneID: CKRecordZone.ID, appUserId: String?) -> CKRecord {
        let recordID = CKRecord.ID(recordName: entry.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "TimeEntry", recordID: recordID)
        record["propertyId"] = entry.propertyId.uuidString
        record["participant"] = entry.participant.rawValue
        record["category"] = entry.category.rawValue
        record["hours"] = entry.hours
        record["date"] = entry.date
        record["notes"] = entry.notes
        record["createdAt"] = entry.createdAt
        record["modifiedAt"] = entry.modifiedAt
        // Optional fields: never write nil (a nil under .changedKeys would clear the server value).
        if let importSource = entry.importSource { record["importSource"] = importSource }
        if let importExternalId = entry.importExternalId { record["importExternalId"] = importExternalId }
        if let importCalendarId = entry.importCalendarId { record["importCalendarId"] = importCalendarId }
        if let detectedAt = entry.detectedAt { record[CaptureEntryField.detectedAt] = detectedAt }
        if let confirmedAt = entry.confirmedAt { record[CaptureEntryField.confirmedAt] = confirmedAt }
        if let sourceDetail = entry.sourceDetail { record[CaptureEntryField.sourceDetail] = sourceDetail }
        if let sourceKey = entry.sourceKey { record[CaptureEntryField.sourceKey] = sourceKey }
        if let recordDescription = entry.recordDescription { record[CaptureEntryField.recordDescription] = recordDescription }
        if let appUserId { record["appUserId"] = appUserId }
        return record
    }

    /// CKRecord → TimeEntry. Records written by 1.1 simply lack the capture fields.
    nonisolated static func entry(from record: CKRecord) -> TimeEntry? {
        guard let propertyIdStr = record["propertyId"] as? String,
              let propertyId = UUID(uuidString: propertyIdStr),
              let participantRaw = record["participant"] as? String,
              let participant = Participant(rawValue: participantRaw),
              let categoryRaw = record["category"] as? String,
              let category = ActivityCategory(rawValue: categoryRaw),
              let hours = record["hours"] as? Double,
              let date = record["date"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }

        var entry = TimeEntry(
            id: id,
            propertyId: propertyId,
            participant: participant,
            category: category,
            hours: hours,
            date: date,
            notes: record["notes"] as? String ?? "",
            importSource: record["importSource"] as? String,
            importExternalId: record["importExternalId"] as? String,
            importCalendarId: record["importCalendarId"] as? String,
            detectedAt: record[CaptureEntryField.detectedAt] as? Date,
            confirmedAt: record[CaptureEntryField.confirmedAt] as? Date,
            sourceDetail: record[CaptureEntryField.sourceDetail] as? String,
            sourceKey: record[CaptureEntryField.sourceKey] as? String,
            recordDescription: record[CaptureEntryField.recordDescription] as? String
        )
        entry.createdAt = record["createdAt"] as? Date ?? Date()
        entry.modifiedAt = record["modifiedAt"] as? Date ?? entry.createdAt
        return entry
    }

    // MARK: - Record Mapping: CustomCategory

    nonisolated static func record(for cat: CustomCategory, zoneID: CKRecordZone.ID, appUserId: String?) -> CKRecord {
        let recordID = CKRecord.ID(recordName: cat.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "CustomCategory", recordID: recordID)
        record["name"] = cat.name
        record["iconName"] = cat.iconName
        record["colorHex"] = cat.colorHex
        record["countsForREPS"] = cat.countsForREPS ? 1 : 0
        record["modifiedAt"] = cat.modifiedAt
        if let appUserId { record["appUserId"] = appUserId }
        return record
    }

    nonisolated static func customCategory(from record: CKRecord) -> CustomCategory? {
        guard let name = record["name"] as? String,
              let iconName = record["iconName"] as? String,
              let colorHex = record["colorHex"] as? String,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        let countsForREPS = ((record["countsForREPS"] as? NSNumber)?.int64Value ?? 1) != 0
        var cat = CustomCategory(id: id, name: name, iconName: iconName, colorHex: colorHex, countsForREPS: countsForREPS)
        cat.modifiedAt = record["modifiedAt"] as? Date ?? Date()
        return cat
    }

    // MARK: - Change Token Persistence

    /// The zone token, kept archived (`CKServerChangeToken`) so the engine stays CloudKit-free.
    /// The engine's record set owns the token (the migration hands its S8b token over at S10).
    private func loadZoneToken() -> Data? {
        if let engine { return engine.steadyToken }
        return UserDefaults.standard.data(forKey: zoneTokenKey)
    }

    private func saveZoneToken(_ data: Data?) {
        if let engine { engine.steadyToken = data; return }
        if let data { UserDefaults.standard.set(data, forKey: zoneTokenKey) } else { UserDefaults.standard.removeObject(forKey: zoneTokenKey) }
    }

    nonisolated static func archive(_ token: CKServerChangeToken?) -> Data? {
        token.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
    }

    nonisolated static func unarchive(_ data: Data?) -> CKServerChangeToken? {
        data.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
    }

    // MARK: - ViewModel Access Helper

    @MainActor
    private func getViewModel() -> AppViewModel? {
        // Access via delegate — AppViewModel is the delegate
        return delegate as? AppViewModel
    }

    // MARK: - Retry Helper

    /// Returns true if the CKError is transient and worth retrying.
    func isTransientError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .serverResponseLost:
            return true
        default:
            return false
        }
    }

    /// Returns the retry delay from a CKError's retryAfterSeconds, or a default exponential backoff.
    private func retryDelay(for error: Error, attempt: Int) -> TimeInterval {
        if let ckError = error as? CKError,
           let retryAfter = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            return retryAfter
        }
        // Exponential backoff: 1s, 2s, 4s
        return pow(2.0, Double(attempt - 1))
    }

    /// Executes `operation` with retry logic for transient CloudKit errors.
    private func withRetry(_ operation: @escaping () async throws -> Void) async throws {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                try await operation()
                return
            } catch {
                lastError = error
                guard isTransientError(error), attempt < maxRetries - 1 else {
                    throw error
                }
                let delay = retryDelay(for: error, attempt: attempt + 1)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        if let lastError { throw lastError }
    }

    private static var hasCloudKitEntitlement: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    private static func isDeleteMissingRecordsOnly(_ error: Error) -> Bool {
        guard let ckError = error as? CKError, ckError.code == .partialFailure else {
            return false
        }
        let errors = ckError.partialErrorsByItemID?.values.compactMap { $0 as? CKError } ?? []
        return !errors.isEmpty && errors.allSatisfy { $0.code == .unknownItem }
    }
}

private struct CloudKitSyncUnavailableError: LocalizedError {
    var errorDescription: String? {
        "iCloud sync is unavailable in this build."
    }
}

// MARK: - IdentityZoneSource (live CloudKit)

extension CloudKitSyncService: IdentityZoneSource {
    func accountState() async -> ICloudAccountState {
        guard container != nil else { return .unsupported }
        await checkAccountStatus()
        return accountState
    }

    func userRecordName() async -> String? {
        guard let container else { return nil }
        return try? await container.userRecordID().recordName
    }

    /// S5: the whole zone with no token. Names are collected before parsing; any failure marks
    /// the read incomplete (v3 finding 1).
    func readWholeZone() async -> ZoneSnapshot {
        guard let database else {
            var s = ZoneSnapshot.empty(zoneExists: false)
            s.incomplete = true
            s.problem = String(localized: "iCloud sync is unavailable in this build.", table: "Identity")
            return s
        }
        var snapshot = ZoneSnapshot.empty(zoneExists: true)
        do {
            let result = try await fetchZone(database: database, token: nil)
            snapshot.presentNames = result.names
            snapshot.records = result.records
            snapshot.incomplete = result.incomplete
            snapshot.tokenData = result.token
            if result.incomplete { snapshot.problem = String(localized: "iCloud didn’t answer for every record.", table: "Identity") }
        } catch let error as CKError where Self.isZoneGone(error) {
            return ZoneSnapshot.empty(zoneExists: false)
        } catch {
            snapshot.incomplete = true
            snapshot.problem = Self.plainProblem(error)
        }
        return snapshot
    }

    func deltaPull(from token: Data?) async throws -> ZoneDelta {
        guard let database else { throw ZoneSourceError.unavailable("no CloudKit") }
        do {
            let result = try await withRetryReturning { try await self.fetchZone(database: database, token: Self.unarchive(token)) }
            return ZoneDelta(changed: result.records, deleted: result.deleted, tokenData: result.token, incomplete: result.incomplete)
        } catch let error as CKError where error.code == .changeTokenExpired {
            throw ZoneSourceError.tokenExpired
        } catch let error as CKError where Self.isZoneGone(error) {
            throw ZoneSourceError.zoneGone
        }
    }

    private struct ZoneFetch {
        var names: Set<String> = []
        var records: [ZoneRecord] = []
        var deleted: [String: String] = [:]
        var token: Data?
        var incomplete = false
    }

    private func fetchZone(database: CKDatabase, token: CKServerChangeToken?) async throws -> ZoneFetch {
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = token
        let zoneID = self.zoneID
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ZoneFetch, Error>) in
            var fetch = ZoneFetch()
            var zoneError: Error?
            let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: config])
            op.recordWasChangedBlock = { recordID, result in
                // Present before parsing: a record that fails here is still present.
                fetch.names.insert(recordID.recordName)
                switch result {
                case .success(let record): fetch.records.append(ZoneRecord(record))
                case .failure(let error):
                    fetch.incomplete = true
                    logger.error("Record change error: \(error.localizedDescription)")
                }
            }
            op.recordWithIDWasDeletedBlock = { recordID, recordType in
                fetch.deleted[recordID.recordName] = recordType
            }
            op.recordZoneChangeTokensUpdatedBlock = { _, changeToken, _ in
                fetch.token = Self.archive(changeToken)
            }
            op.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .success(let (serverToken, _, _)): fetch.token = Self.archive(serverToken)
                case .failure(let error):
                    zoneError = error
                    fetch.incomplete = true
                }
            }
            op.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    if let zoneError = zoneError as? CKError, Self.isZoneGone(zoneError) || zoneError.code == .changeTokenExpired {
                        continuation.resume(throwing: zoneError)
                    } else {
                        continuation.resume(returning: fetch)
                    }
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            op.qualityOfService = .userInitiated
            database.add(op)
        }
    }

    /// Creates the zone on a fresh install or after Delete all data. A zone this device knew
    /// (`IdentityKeys.knowsZone`) that is gone is never recreated here: P31 asks.
    func ensureZone() async throws {
        guard let database else { throw ZoneSourceError.unavailable("no CloudKit") }
        do {
            _ = try await database.recordZone(for: zoneID)
        } catch let error as CKError where Self.isZoneGone(error) {
            if IdentityKeys.knowsZone(.standard) { throw ZoneSourceError.zoneGone }
            try await createZone()
        }
    }

    /// S8: the household pair. Measured on the Development container (iPad mini 5, 2026-10-25):
    /// `.ifServerRecordUnchanged` on a freshly built record does not refuse to overwrite one that
    /// exists, so the first writer is found by reading. Read: a pair exists → adopt its
    /// `appUserId`. Else save, then read back: another device that saved in the same moment wins
    /// if its copy is the one on the server, and this one adopts it (the loser never pushes
    /// under its own id; both converge on the server's copy).
    func saveHousehold(goal: ZoneRecord, tax: ZoneRecord) async throws -> HouseholdSaveResult {
        guard let database else { throw ZoneSourceError.unavailable("no CloudKit") }
        let goalID = CKRecord.ID(recordName: goal.recordName, zoneID: zoneID)
        if let existing = try await fetchOptional(goalID, database: database), let owner = existing["appUserId"] as? String {
            return owner == goal.appUserId ? .saved : .adopted(owner)
        }
        let records = [goal.ckRecord(zoneID: zoneID), tax.ckRecord(zoneID: zoneID)]
        do {
            try await modify(database: database, save: records, policy: .ifServerRecordUnchanged, atomic: false)
        } catch let error as CKError {
            if let owner = Self.serverRecords(in: error).compactMap({ $0["appUserId"] as? String }).first { return .adopted(owner) }
            guard Self.isZoneGone(error) else { throw error }
            // Only the cloud phase creates the zone (`ensureZone`, before S8): gone now means
            // deleted meanwhile. Ask (P31), never recreate.
            throw ZoneSourceError.zoneGone
        }
        if let after = try await fetchOptional(goalID, database: database), let owner = after["appUserId"] as? String, owner != goal.appUserId {
            return .adopted(owner)
        }
        return .saved
    }

    private func fetchOptional(_ id: CKRecord.ID, database: CKDatabase) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem || Self.isZoneGone(error) {
            return nil
        }
    }

    nonisolated private static func serverRecords(in error: CKError) -> [CKRecord] {
        var found: [CKRecord] = []
        if let record = error.serverRecord { found.append(record) }
        if let partial = error.partialErrorsByItemID {
            for item in partial.values {
                if let record = (item as? CKError)?.serverRecord { found.append(record) }
            }
        }
        return found
    }

    /// S9 and every steady-state push: deletes, then saves per record type, non-atomic.
    func push(_ records: [ZoneRecord], deletes: [String]) async -> ZonePushReport {
        var report = ZonePushReport()
        guard database != nil else { report.failedTypes["all"] = CKError.Code.notAuthenticated.rawValue; return report }
        if !deletes.isEmpty {
            do {
                try await withRetry { try await self.batchDelete(deletes.map { CKRecord.ID(recordName: $0, zoneID: self.zoneID) }) }
                report.deletedNames = Set(deletes)
            } catch {
                if Self.isZoneGone(error) {
                    if IdentityKeys.knowsZone(.standard) { report.zoneGone = true; return report }
                    // A zone this device never saw holds nothing to delete.
                    report.deletedNames = Set(deletes)
                } else {
                    logger.error("Delete push failed: \(error.localizedDescription)")
                }
            }
        }
        let saved = await saveRecordsPerType(records.map { $0.ckRecord(zoneID: zoneID) })
        report.savedNames = saved.savedNames
        report.failedTypes = saved.failedTypes
        report.quotaExceeded = saved.quotaExceeded
        // A push never creates the zone, whatever it knows: only the cloud phase does
        // (`ensureZone`), so a push in flight when Delete all data runs can't bring it back.
        if saved.zoneGone { report.zoneGone = true }
        if !report.savedNames.isEmpty { UserDefaults.standard.set(true, forKey: IdentityKeys.hasSynced) }
        return report
    }

    struct TypeSaveReport {
        var savedNames: Set<String> = []
        var failedTypes: [String: Int] = [:]
        var quotaExceeded = false
        var zoneGone = false
    }

    /// One operation per record type, `isAtomic = false`, batches of 400: a type missing from the
    /// Production schema fails alone (diagnosis §7.3), and every record that saved is reported.
    func saveRecordsPerType(_ records: [CKRecord]) async -> TypeSaveReport {
        var report = TypeSaveReport()
        guard let database else { return report }
        let byType = Dictionary(grouping: records, by: \.recordType)
        for (type, typeRecords) in byType.sorted(by: { $0.key < $1.key }) {
            for offset in stride(from: 0, to: typeRecords.count, by: 400) {
                let batch = Array(typeRecords[offset..<min(offset + 400, typeRecords.count)])
                do {
                    let saved = try await withRetryReturning {
                        try await self.modifyReporting(database: database, save: batch, policy: .changedKeys)
                    }
                    report.savedNames.formUnion(saved.saved)
                    if !saved.failures.isEmpty {
                        report.failedTypes[type] = saved.failures.values.first?.rawValue ?? -1
                        if saved.failures.values.contains(.quotaExceeded) { report.quotaExceeded = true }
                        if saved.failures.values.allSatisfy({ $0 == .zoneNotFound || $0 == .userDeletedZone }) { report.zoneGone = true }
                    }
                } catch {
                    let code = (error as? CKError)?.code
                    report.failedTypes[type] = code?.rawValue ?? -1
                    if code == .quotaExceeded { report.quotaExceeded = true }
                    if Self.isZoneGone(error) { report.zoneGone = true }
                    logger.error("Push of \(type, privacy: .public) failed: \(error.localizedDescription)")
                }
            }
        }
        return report
    }

    private func modifyReporting(database: CKDatabase, save: [CKRecord], policy: CKModifyRecordsOperation.RecordSavePolicy)
        async throws -> (saved: Set<String>, failures: [String: CKError.Code]) {
        try await withCheckedThrowingContinuation { continuation in
            var saved = Set<String>()
            var failures: [String: CKError.Code] = [:]
            let op = CKModifyRecordsOperation(recordsToSave: save, recordIDsToDelete: nil)
            op.savePolicy = policy
            op.isAtomic = false
            op.qualityOfService = .userInitiated
            op.perRecordSaveBlock = { recordID, result in
                switch result {
                case .success: saved.insert(recordID.recordName)
                case .failure(let error): failures[recordID.recordName] = (error as? CKError)?.code ?? .internalError
                }
            }
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: (saved, failures))
                case .failure(let error):
                    // Non-atomic: a partial failure still saved the rest; report both.
                    if let ck = error as? CKError, ck.code == .partialFailure {
                        continuation.resume(returning: (saved, failures))
                    } else if Self.isTransient(error) {
                        continuation.resume(throwing: error)
                    } else {
                        for record in save where !saved.contains(record.recordID.recordName) {
                            failures[record.recordID.recordName] = (error as? CKError)?.code ?? .internalError
                        }
                        continuation.resume(returning: (saved, failures))
                    }
                }
            }
            database.add(op)
        }
    }

    private func modify(database: CKDatabase, save: [CKRecord], policy: CKModifyRecordsOperation.RecordSavePolicy, atomic: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: save, recordIDsToDelete: nil)
            op.savePolicy = policy
            op.isAtomic = atomic
            op.qualityOfService = .userInitiated
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            database.add(op)
        }
    }

    /// Delete all data: the whole zone, one operation. Already gone counts as done.
    func deleteZone() async throws {
        guard let database else { throw ZoneSourceError.unavailable("no CloudKit") }
        guard await accountState() == .available else { throw AccountDeleteICloudUnreachableError() }
        // Never another account's zone: the user this set was read from must still be signed in.
        if let stored = UserDefaults.standard.string(forKey: IdentityKeys.icloudUserRecordName) {
            guard let current = await userRecordName() else { throw AccountDeleteICloudUnreachableError() }
            guard current == stored else { throw OtherICloudAccountError() }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: [zoneID])
            op.qualityOfService = .userInitiated
            op.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error):
                    if Self.isZoneGone(error) { continuation.resume() } else { continuation.resume(throwing: error) }
                }
            }
            database.add(op)
        }
    }

    nonisolated static func isTransient(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .serverResponseLost:
            return true
        default:
            return false
        }
    }

    /// One plain line for the status row (never a stack trace).
    nonisolated static func plainProblem(_ error: Error) -> String {
        guard let ck = error as? CKError else { return String(localized: "iCloud didn’t answer.", table: "Identity") }
        switch ck.code {
        case .networkUnavailable, .networkFailure: return String(localized: "iCloud didn’t answer (network).", table: "Identity")
        case .notAuthenticated: return String(localized: "This iPhone isn’t signed in to iCloud.", table: "Identity")
        case .quotaExceeded: return String(localized: "iCloud is full.", table: "Identity")
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return String(localized: "iCloud is busy. We’ll try again.", table: "Identity")
        default: return String(localized: "iCloud didn’t answer.", table: "Identity")
        }
    }

    private func withRetryReturning<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<3 {
            do { return try await operation() } catch {
                lastError = error
                guard Self.isTransient(error), attempt < 2 else { throw error }
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            }
        }
        throw lastError ?? CloudKitSyncUnavailableError()
    }
}
