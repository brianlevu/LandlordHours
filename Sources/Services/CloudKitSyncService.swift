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
    func syncDidReceiveGoalSettings(globalGoalType: HourGoalType, propertyGoals: [PropertyGoal])
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

@MainActor
final class CloudKitSyncService: ObservableObject, CloudProfileRecordSource {

    // MARK: Public state
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var accountAvailable = false

    weak var delegate: CloudKitSyncDelegate?

    // MARK: Private
    private let container: CKContainer?
    private var database: CKDatabase? { container?.privateCloudDatabase }
    private let zoneID = CKRecordZone.ID(zoneName: "LandlordHoursZone", ownerName: CKCurrentUserDefaultName)
    /// The current app-level userId, used to tag CloudKit records so they don't leak across app users sharing the same iCloud account.
    private var appUserId: String? { UserScope.userId }

    private var changeTokenKey: String { UserScope.key("cloudkit.changeToken") }
    private var zoneTokenKey: String { UserScope.key("cloudkit.zoneChangeToken") }
    private var zoneCreatedKey: String { UserScope.key("cloudkit.zoneCreated") }
    private var subscriptionCreatedKey: String { UserScope.key("cloudkit.subscriptionCreated") }
    private var migrationDoneKey: String { UserScope.key("cloudkit.migrationDone") }

    private var pushDebounceTask: Task<Void, Never>?

    /// Profile whose initial sync (optional first push, then the first pull) has finished.
    /// Pushes for any other profile are held until it has, so default local state can never
    /// overwrite iCloud copies (TaxProfile-<id>, GoalSettings-<id>) on a restore/reinstall.
    private(set) var initialSyncCompletedFor: String?
    /// A push requested while the initial sync was running; flushed once it completes.
    private(set) var hasHeldPush = false
    /// Instrumentation for tests: push requests received / held by the gate.
    private(set) var pushRequestCount = 0
    private(set) var heldPushRequestCount = 0
    /// Counter-based guard to prevent push loops when merging remote changes.
    /// Incremented before delegate callbacks, decremented after. Using a counter
    /// instead of a boolean is safer if delegate callbacks trigger nested paths.
    private var remoteUpdateDepth = 0

    /// Maximum retry attempts for transient CloudKit errors.
    private let maxRetries = 3

    // MARK: - Lifecycle

    init() {
        if Self.hasCloudKitEntitlement {
            container = CKContainer(identifier: "iCloud.com.openclaw.landlordhours")
        } else {
            container = nil
            syncError = "iCloud sync is unavailable in this build."
            logger.warning("CloudKit disabled: missing iCloud CloudKit entitlement")
        }
    }

    /// The steps `start()` runs. Production uses CloudKit; tests inject fakes to drive
    /// `start()` end to end (account check → prepare → initial push/pull → gate → flush).
    struct InitialSyncOperations {
        var accountAvailable: () async -> Bool
        var prepare: () async -> Void
        var push: () async -> Void
        /// Returns true when the pull reached iCloud and merged.
        var pull: () async -> Bool
    }

    /// Test seam: when set, `start()` uses these instead of CloudKit.
    var operationsOverride: InitialSyncOperations?
    private(set) var isRunningInitialSync = false
    /// Instrumentation for tests: held pushes flushed after a successful initial pull.
    private(set) var flushedHeldPushCount = 0

    static let heldChangesMessage = "Couldn't reach iCloud. Your changes are safe on this iPhone and will sync when iCloud is back."

    private var liveOperations: InitialSyncOperations {
        InitialSyncOperations(
            accountAvailable: { [weak self] in
                guard let self, self.container != nil else { return false }
                await self.checkAccountStatus()
                return self.accountAvailable
            },
            prepare: { [weak self] in
                await self?.ensureZoneExists()
                await self?.ensureSubscriptionExists()
            },
            push: { [weak self] in await self?.performPushAll() },
            pull: { [weak self] in await self?.pullChanges() ?? false }
        )
    }

    /// Initial sync for the active profile, then opens the push gate and flushes any held
    /// push. Safe to call again (Sync Now, iCloud becoming available): a failed pull keeps
    /// the gate closed and says so instead of holding silently.
    func start() async {
        // One initial sync at a time; a request that arrives meanwhile (profile switch,
        // iCloud coming back, Sync Now) re-runs it afterwards instead of being dropped.
        if isRunningInitialSync {
            rerunRequested = true
            return
        }
        isRunningInitialSync = true
        defer { isRunningInitialSync = false }
        repeat {
            rerunRequested = false
            await runInitialSyncOnce()
        } while rerunRequested
    }

    private var rerunRequested = false

    private func runInitialSyncOnce() async {
        let startingFor = appUserId
        if initialSyncCompletedFor != startingFor { initialSyncCompletedFor = nil }
        let ops = operationsOverride ?? liveOperations
        guard await ops.accountAvailable() else {
            accountAvailable = false
            return
        }
        accountAvailable = true
        await ops.prepare()
        // Initial sync: push local then pull remote — but never push an empty local
        // state before the first pull (it would overwrite iCloud copies of
        // GoalSettings-<id> / TaxProfile-<id> with defaults on a reinstall/restore).
        let viewModel = getViewModel()
        let hasLocalData = !(viewModel?.properties.isEmpty ?? true)
            || !(viewModel?.timeEntries.isEmpty ?? true)
            || !CategoryManager.shared.customCategories.isEmpty
        var pullSucceeded = false
        await Self.runInitialSync(
            defaults: .standard,
            migrationDoneKey: migrationDoneKey,
            hasLocalData: hasLocalData,
            push: { await ops.push() },
            pull: { pullSucceeded = await ops.pull() }
        )
        // Only open the gate if the active profile didn't change while we were syncing.
        guard appUserId == startingFor, startingFor != nil else { return }
        guard pullSucceeded else {
            // Keep the gate closed (pushing now could overwrite iCloud with defaults), but
            // never hold silently: say so. Sync Now or iCloud returning retries start().
            if hasHeldPush { syncError = Self.heldChangesMessage }
            return
        }
        initialSyncCompletedFor = startingFor
        if hasHeldPush {
            hasHeldPush = false
            flushedHeldPushCount += 1
            await ops.push()
        }
    }

    /// Manual "Sync Now": runs the initial sync first when the gate isn't open yet, then
    /// pushes and pulls. Never holds silently: if iCloud is off or unreachable, `syncError`
    /// says so.
    func syncNow() async {
        if !isPushAllowed {
            await start()
        }
        guard isPushAllowed else {
            if !accountAvailable {
                syncError = "iCloud is off. Turn on iCloud for LandlordHours in Settings to sync."
            } else if syncError == nil {
                syncError = Self.heldChangesMessage
            }
            return
        }
        await pushAll()
        _ = await pullChanges()
    }

    /// Whether a push for `appUserId` may run now: only after that profile's initial sync.
    static func isPushAllowed(initialSyncCompletedFor: String?, appUserId: String?) -> Bool {
        guard let appUserId else { return false }
        return initialSyncCompletedFor == appUserId
    }

    private var isPushAllowed: Bool {
        Self.isPushAllowed(initialSyncCompletedFor: initialSyncCompletedFor, appUserId: appUserId)
    }

    /// Initial-sync ordering, extracted so tests can drive it with fakes.
    ///
    /// - Push first only when the one-time initial push hasn't run AND there is local
    ///   data to protect. Restored iCloud-only profiles arrive with `migrationDone`
    ///   already set (see `ProfileRestore.activate`), so they always pull first.
    /// - When the push is skipped for empty state, the initial push is marked done
    ///   after the pull; later edits push through `schedulePush()` as usual.
    static func runInitialSync(
        defaults: UserDefaults,
        migrationDoneKey: String,
        hasLocalData: Bool,
        push: () async -> Void,
        pull: () async -> Void
    ) async {
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
        guard let container else {
            accountAvailable = false
            syncError = "iCloud sync is unavailable in this build."
            return
        }
        do {
            let status = try await container.accountStatus()
            let wasAvailable = accountAvailable
            accountAvailable = (status == .available)
            // iCloud came back (it was off at launch, or signed in later): run the initial
            // pull for the active profile so the push gate can open.
            if accountAvailable, !wasAvailable, !isRunningInitialSync,
               appUserId != nil, initialSyncCompletedFor != appUserId {
                Task { await self.start() }
            }
        } catch {
            accountAvailable = false
            logger.error("Account status error: \(error.localizedDescription)")
        }
    }

    // MARK: - Zone Setup

    private func ensureZoneExists() async {
        guard let database else { return }
        guard !UserDefaults.standard.bool(forKey: zoneCreatedKey) else { return }
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await database.save(zone)
            UserDefaults.standard.set(true, forKey: zoneCreatedKey)
        } catch {
            // Zone may already exist
            if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                UserDefaults.standard.set(true, forKey: zoneCreatedKey)
            } else {
                logger.error("Zone creation error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Subscription

    private func ensureSubscriptionExists() async {
        guard let database else { return }
        guard !UserDefaults.standard.bool(forKey: subscriptionCreatedKey) else { return }
        let subscriptionID = "private-db-changes"
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
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
        guard isPushAllowed else {
            // Hold, don't drop: the edit is pushed once the initial pull has finished.
            heldPushRequestCount += 1
            hasHeldPush = true
            return
        }
        guard container != nil else { return }
        pushDebounceTask?.cancel()
        pushDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await pushAll()
        }
    }

    /// Push all local data to CloudKit (manual "Sync Now" and debounced edits). Held until
    /// the active profile's initial sync has completed.
    func pushAll() async {
        guard isPushAllowed else {
            hasHeldPush = true
            return
        }
        await performPushAll()
    }

    private func performPushAll() async {
        guard accountAvailable else { return }
        isSyncing = true
        syncError = nil

        do {
            // Gather all records to push
            var records: [CKRecord] = []

            // Properties
            let viewModel = getViewModel()
            for property in viewModel?.properties ?? [] {
                records.append(propertyToRecord(property))
            }

            // Time entries (without attachments — those are too large for inline push)
            for entry in viewModel?.timeEntries ?? [] {
                records.append(entryToRecord(entry))
            }

            // Custom categories
            for category in CategoryManager.shared.customCategories {
                records.append(customCategoryToRecord(category))
            }

            // Goal settings (single record)
            records.append(goalSettingsToRecord())

            // Tax profile (single record)
            records.append(taxProfileToRecord())

            // Batch save with retry for transient errors
            try await withRetry { [records] in
                try await self.batchSave(records)
            }
            lastSyncDate = Date()
        } catch {
            syncError = error.localizedDescription
            logger.error("Push error: \(error.localizedDescription)")
        }

        isSyncing = false
    }

    private func batchSave(_ records: [CKRecord]) async throws {
        guard let database else { throw CloudKitSyncUnavailableError() }
        let batchSize = 400
        for offset in stride(from: 0, to: records.count, by: batchSize) {
            let batch = Array(records[offset..<min(offset + batchSize, records.count)])
            let op = CKModifyRecordsOperation(recordsToSave: batch, recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.qualityOfService = .userInitiated

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        if Self.isDeleteMissingRecordsOnly(error) {
                            continuation.resume()
                            return
                        }
                        continuation.resume(throwing: error)
                    }
                }
                database.add(op)
            }
        }
    }

    // MARK: - Pull (Cloud → Local)

    @discardableResult
    func pullChanges() async -> Bool {
        guard accountAvailable else { return false }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            try await withRetry {
                try await self.fetchZoneChanges()
            }
            lastSyncDate = Date()
            return true
        } catch {
            syncError = error.localizedDescription
            logger.error("Pull error: \(error.localizedDescription)")
            return false
        }
    }

    private func fetchZoneChanges() async throws {
        guard let database else { throw CloudKitSyncUnavailableError() }
        let token = loadZoneToken()

        var updatedProperties: [RentalProperty] = []
        var updatedEntries: [TimeEntry] = []
        var updatedCategories: [CustomCategory] = []
        var deletedPropertyIDs: Set<UUID> = []
        var deletedEntryIDs: Set<UUID> = []
        var goalRecord: CKRecord?
        var taxProfileRecord: CKRecord?
        var newToken: CKServerChangeToken?

        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = token

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )

            op.recordWasChangedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    // Filter by appUserId — skip records that belong to a different app user
                    let recordOwner = record["appUserId"] as? String
                    let currentUser = self.appUserId
                    if let owner = recordOwner, let current = currentUser, owner != current {
                        // Record belongs to a different app user — skip it
                        return
                    }
                    if recordOwner == nil && currentUser != nil {
                        // Legacy record with no appUserId — skip for safety
                        // (original user's data is already migrated to their local scoped keys)
                        return
                    }

                    switch record.recordType {
                    case "Property":
                        if let property = self.recordToProperty(record) {
                            updatedProperties.append(property)
                        }
                    case "TimeEntry":
                        if let entry = self.recordToEntry(record) {
                            updatedEntries.append(entry)
                        }
                    case "CustomCategory":
                        if let cat = self.recordToCustomCategory(record) {
                            updatedCategories.append(cat)
                        }
                    case "GoalSettings":
                        goalRecord = record
                    case "TaxProfile":
                        taxProfileRecord = record
                    default:
                        break
                    }
                case .failure(let error):
                    logger.error("Record change error: \(error.localizedDescription)")
                }
            }

            op.recordWithIDWasDeletedBlock = { recordID, recordType in
                // Note: CK delete callbacks don't include record fields, so we can't filter
                // by appUserId here. Only process deletes for records that exist locally
                // (which are already scoped to the current user).
                if let uuid = UUID(uuidString: recordID.recordName) {
                    switch recordType {
                    case "Property":
                        deletedPropertyIDs.insert(uuid)
                    case "TimeEntry":
                        deletedEntryIDs.insert(uuid)
                    default:
                        break
                    }
                }
            }

            op.recordZoneChangeTokensUpdatedBlock = { zoneID, changeToken, _ in
                newToken = changeToken
            }

            op.recordZoneFetchResultBlock = { zoneID, result in
                switch result {
                case .success(let (serverToken, _, _)):
                    newToken = serverToken
                case .failure(let error):
                    logger.error("Zone fetch error: \(error.localizedDescription)")
                }
            }

            op.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            op.qualityOfService = .userInitiated
            database.add(op)
        }

        // Save the new zone change token
        if let token = newToken {
            saveZoneToken(token)
        }

        // Notify delegate with changes on MainActor.
        // Increment depth guard so delegate-triggered saves don't push back to CloudKit.
        remoteUpdateDepth += 1
        defer { remoteUpdateDepth -= 1 }

        if !updatedProperties.isEmpty {
            delegate?.syncDidReceiveProperties(updatedProperties)
        }
        if !updatedEntries.isEmpty {
            delegate?.syncDidReceiveEntries(updatedEntries)
        }
        if !deletedPropertyIDs.isEmpty {
            delegate?.syncDidDeletePropertyIds(deletedPropertyIDs)
        }
        if !deletedEntryIDs.isEmpty {
            delegate?.syncDidDeleteEntryIds(deletedEntryIDs)
        }
        if !updatedCategories.isEmpty {
            delegate?.syncDidReceiveCategories(updatedCategories)
        }
        if let record = goalRecord {
            let rawGoalType = record["globalGoalType"] as? String
            let goalType = rawGoalType.flatMap(HourGoalType.init(rawValue:)) ?? .reps
            if rawGoalType == nil {
                logger.warning("GoalSettings record missing globalGoalType, defaulting to .reps")
            }
            let goalsJSON = record["propertyGoalsJSON"] as? String ?? "[]"
            let goals = (try? JSONDecoder().decode([PropertyGoal].self, from: Data(goalsJSON.utf8))) ?? []
            if goals.isEmpty && record["propertyGoalsJSON"] != nil {
                logger.warning("GoalSettings record has malformed propertyGoalsJSON, defaulting to empty")
            }
            delegate?.syncDidReceiveGoalSettings(globalGoalType: goalType, propertyGoals: goals)
        }
        if let record = taxProfileRecord {
            if record["filingStatus"] == nil {
                logger.warning("TaxProfile record missing filingStatus, defaulting to marriedJoint")
            }
            let fields = TaxProfileFields(
                filingStatus: record["filingStatus"] as? String ?? "marriedJoint",
                spouseTracking: (record["spouseTracking"] as? Int64 ?? 1) != 0,
                taxYear: Int(record["taxYear"] as? Int64 ?? Int64(Calendar.current.component(.year, from: Date()))),
                groupingElection: (record["groupingElection"] as? Int64 ?? 0) != 0,
                nonREWorkHours: record["nonREWorkHours"] as? Double ?? 0,
                modifiedAt: record["modifiedAt"] as? Date ?? Date()
            )
            delegate?.syncDidReceiveTaxProfile(fields)
        }
    }

    // MARK: - Profile Discovery (iCloud)

    /// Discovery-only fetch of the whole zone (no change token) that reduces each record
    /// to its owner, type and date. Unlike `pullChanges()` it does NOT drop other app
    /// users' records — that is the point — and it never touches local state.
    /// Returns `[]` when iCloud is unavailable, so offline discovery is device-only.
    func fetchProfileRecordSummaries() async throws -> [CloudRecordSummary] {
        guard container != nil, let database else { return [] }
        await checkAccountStatus()
        guard accountAvailable else { return [] }

        var summaries: [CloudRecordSummary] = []
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = nil
        config.desiredKeys = ["appUserId", "date"]

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let op = CKFetchRecordZoneChangesOperation(
                    recordZoneIDs: [zoneID],
                    configurationsByRecordZoneID: [zoneID: config]
                )
                op.recordWasChangedBlock = { _, result in
                    if case .success(let record) = result {
                        summaries.append(CloudRecordSummary(
                            appUserId: record["appUserId"] as? String,
                            recordType: record.recordType,
                            date: record["date"] as? Date
                        ))
                    }
                }
                op.fetchRecordZoneChangesResultBlock = { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                op.qualityOfService = .userInitiated
                database.add(op)
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return []
        } catch let error as CKError where error.code == .partialFailure {
            let codes = error.partialErrorsByItemID?.values.compactMap { ($0 as? CKError)?.code } ?? []
            if codes.allSatisfy({ $0 == .zoneNotFound || $0 == .userDeletedZone }) { return [] }
            throw error
        }
        return summaries
    }

    // MARK: - Delete from Cloud

    func deletePropertyFromCloud(_ property: RentalProperty) async {
        guard accountAvailable else { return }
        guard let database else { return }
        let recordID = CKRecord.ID(recordName: property.id.uuidString, zoneID: zoneID)
        do {
            try await database.deleteRecord(withID: recordID)
        } catch {
            logger.error("Delete property error: \(error.localizedDescription)")
        }
    }

    func deleteEntryFromCloud(_ entry: TimeEntry) async {
        guard accountAvailable else { return }
        guard let database else { return }
        let recordID = CKRecord.ID(recordName: entry.id.uuidString, zoneID: zoneID)
        do {
            try await database.deleteRecord(withID: recordID)
        } catch {
            logger.error("Delete entry error: \(error.localizedDescription)")
        }
    }

    func deleteCurrentUserRecords(
        properties: [RentalProperty],
        entries: [TimeEntry],
        categories: [CustomCategory],
        userId: String
    ) async throws {
        guard let database else { throw CloudKitSyncUnavailableError() }

        await checkAccountStatus()
        guard accountAvailable else { return }
        await ensureZoneExists()

        var recordIDs = properties.map { CKRecord.ID(recordName: $0.id.uuidString, zoneID: zoneID) }
        recordIDs.append(contentsOf: entries.map { CKRecord.ID(recordName: $0.id.uuidString, zoneID: zoneID) })
        recordIDs.append(contentsOf: categories.map { CKRecord.ID(recordName: $0.id.uuidString, zoneID: zoneID) })
        for recordType in ["Property", "TimeEntry", "CustomCategory"] {
            recordIDs.append(contentsOf: try await fetchRecordIDs(recordType: recordType, userId: userId))
        }
        recordIDs.append(CKRecord.ID(recordName: "GoalSettings-\(userId)", zoneID: zoneID))
        recordIDs.append(CKRecord.ID(recordName: "TaxProfile-\(userId)", zoneID: zoneID))

        let uniqueRecordIDs = Array(Dictionary(uniqueKeysWithValues: recordIDs.map { ($0.recordName, $0) }).values)
        let batchSize = 400
        for offset in stride(from: 0, to: uniqueRecordIDs.count, by: batchSize) {
            let batch = Array(uniqueRecordIDs[offset..<min(offset + batchSize, uniqueRecordIDs.count)])
            let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)
            op.qualityOfService = .userInitiated

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        if Self.isDeleteMissingRecordsOnly(error) {
                            continuation.resume()
                            return
                        }
                        continuation.resume(throwing: error)
                    }
                }
                database.add(op)
            }
        }

        UserDefaults.standard.removeObject(forKey: changeTokenKey)
        UserDefaults.standard.removeObject(forKey: zoneTokenKey)
        lastSyncDate = Date()
    }

    private func fetchRecordIDs(recordType: String, userId: String) async throws -> [CKRecord.ID] {
        guard let database else { return [] }
        let predicate = NSPredicate(format: "appUserId == %@", userId)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        var recordIDs: [CKRecord.ID] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                operation = CKQueryOperation(query: query)
                operation.zoneID = zoneID
            }
            operation.desiredKeys = []
            operation.resultsLimit = 400

            cursor = try await withCheckedThrowingContinuation { continuation in
                operation.recordMatchedBlock = { recordID, result in
                    if case .success = result {
                        recordIDs.append(recordID)
                    }
                }
                operation.queryResultBlock = { result in
                    switch result {
                    case .success(let nextCursor):
                        continuation.resume(returning: nextCursor)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
        } while cursor != nil

        return recordIDs
    }

    // MARK: - Record Mapping: Property

    private func propertyToRecord(_ property: RentalProperty) -> CKRecord {
        let recordID = CKRecord.ID(recordName: property.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "Property", recordID: recordID)
        record["name"] = property.name
        record["address"] = property.address
        record["propertyType"] = property.propertyType.rawValue
        record["createdAt"] = property.createdAt
        record["modifiedAt"] = property.modifiedAt
        record["appUserId"] = appUserId
        return record
    }

    private func recordToProperty(_ record: CKRecord) -> RentalProperty? {
        guard let name = record["name"] as? String,
              let address = record["address"] as? String,
              let typeRaw = record["propertyType"] as? String,
              let type = PropertyType(rawValue: typeRaw),
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }

        var property = RentalProperty(id: id, name: name, address: address, propertyType: type)
        property.createdAt = record["createdAt"] as? Date ?? Date()
        property.modifiedAt = record["modifiedAt"] as? Date ?? property.createdAt
        return property
    }

    // MARK: - Record Mapping: TimeEntry

    private func entryToRecord(_ entry: TimeEntry) -> CKRecord {
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
        record["importSource"] = entry.importSource
        record["importExternalId"] = entry.importExternalId
        record["importCalendarId"] = entry.importCalendarId
        record["appUserId"] = appUserId
        return record
    }

    private func recordToEntry(_ record: CKRecord) -> TimeEntry? {
        guard let propertyIdStr = record["propertyId"] as? String,
              let propertyId = UUID(uuidString: propertyIdStr),
              let participantRaw = record["participant"] as? String,
              let participant = Participant(rawValue: participantRaw),
              let categoryRaw = record["category"] as? String,
              let category = ActivityCategory(rawValue: categoryRaw),
              let hours = record["hours"] as? Double,
              let date = record["date"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }

        let notes = record["notes"] as? String ?? ""
        let importSource = record["importSource"] as? String
        let importExternalId = record["importExternalId"] as? String
        let importCalendarId = record["importCalendarId"] as? String
        var entry = TimeEntry(
            id: id,
            propertyId: propertyId,
            participant: participant,
            category: category,
            hours: hours,
            date: date,
            notes: notes,
            importSource: importSource,
            importExternalId: importExternalId,
            importCalendarId: importCalendarId
        )
        entry.createdAt = record["createdAt"] as? Date ?? Date()
        entry.modifiedAt = record["modifiedAt"] as? Date ?? entry.createdAt
        return entry
    }

    // MARK: - Record Mapping: CustomCategory

    private func customCategoryToRecord(_ cat: CustomCategory) -> CKRecord {
        let recordID = CKRecord.ID(recordName: cat.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "CustomCategory", recordID: recordID)
        record["name"] = cat.name
        record["iconName"] = cat.iconName
        record["colorHex"] = cat.colorHex
        record["countsForREPS"] = cat.countsForREPS ? 1 : 0
        record["modifiedAt"] = cat.modifiedAt
        record["appUserId"] = appUserId
        return record
    }

    private func recordToCustomCategory(_ record: CKRecord) -> CustomCategory? {
        guard let name = record["name"] as? String,
              let iconName = record["iconName"] as? String,
              let colorHex = record["colorHex"] as? String,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }

        let countsForREPS = (record["countsForREPS"] as? Int64 ?? 1) != 0
        var cat = CustomCategory(id: id, name: name, iconName: iconName, colorHex: colorHex, countsForREPS: countsForREPS)
        cat.modifiedAt = record["modifiedAt"] as? Date ?? Date()
        return cat
    }

    // MARK: - Record Mapping: GoalSettings (single record)

    private func goalSettingsToRecord() -> CKRecord {
        // Scope record name by app user so multiple users don't overwrite each other
        let recordName = "GoalSettings-\(appUserId ?? "default")"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: "GoalSettings", recordID: recordID)
        let gm = GoalManager.shared
        record["globalGoalType"] = gm.globalGoalType.rawValue
        if let json = try? JSONEncoder().encode(gm.propertyGoals),
           let str = String(data: json, encoding: .utf8) {
            record["propertyGoalsJSON"] = str
        }
        record["modifiedAt"] = Date() as CKRecordValue
        record["appUserId"] = appUserId
        return record
    }

    // MARK: - Record Mapping: TaxProfile (single record)

    private func taxProfileToRecord() -> CKRecord {
        let recordName = "TaxProfile-\(appUserId ?? "default")"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: "TaxProfile", recordID: recordID)
        let tp = TaxProfileManager.shared
        record["filingStatus"] = tp.filingStatus.rawValue
        record["spouseTracking"] = tp.spouseTracking ? 1 : 0
        record["taxYear"] = Int64(tp.taxYear)
        record["groupingElection"] = tp.groupingElection ? 1 : 0
        record["nonREWorkHours"] = tp.nonREWorkHours
        record["modifiedAt"] = Date() as CKRecordValue
        record["appUserId"] = appUserId
        return record
    }

    // MARK: - Change Token Persistence

    private func loadChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: changeTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveChangeToken(_ token: CKServerChangeToken?) {
        guard let token = token else {
            UserDefaults.standard.removeObject(forKey: changeTokenKey)
            return
        }
        let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: changeTokenKey)
    }

    private func loadZoneToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: zoneTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveZoneToken(_ token: CKServerChangeToken?) {
        guard let token = token else {
            UserDefaults.standard.removeObject(forKey: zoneTokenKey)
            return
        }
        let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: zoneTokenKey)
    }

    // MARK: - ViewModel Access Helper

    @MainActor
    private func getViewModel() -> AppViewModel? {
        // Access via delegate — AppViewModel is the delegate
        return delegate as? AppViewModel
    }

    // MARK: - Retry Helper

    /// Returns true if the CKError is transient and worth retrying.
    private func isTransientError(_ error: Error) -> Bool {
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
