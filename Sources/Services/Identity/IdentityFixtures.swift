#if DEBUG
import Foundation

// MARK: - Fakes and launch fixtures for the identity journeys (DEBUG only)
//
// `-LHUpgradeFixture <state>`  writes a captured upgrade fixture before the device phase runs
//                              (D2–D9). The UI test passes the captured plist itself in the
//                              environment (`LH_UPGRADE_FIXTURE_B64`, base64), so the same run works
//                              on a simulator and on an iPad; unit tests load it from their bundle.
// `-LHFakeZone <case>`         replaces iCloud with an in-memory zone: empty, noZone (no zone yet:
//                              a fresh install or after Delete all data), email (the D2 group
//                              in iCloud), cloudOnly (a new phone), twoSets, bulk, slow, fail,
//                              zoneGone, accountChanged, quota, restricted, off.
// `-LHCrashAt <step>`          stops the migration after a step (S2, S4, S5, S7, S8, S8b, S9).
// `-LHResetIdentity`           clears every identity key, `u.*`, `v2.*` and the migration files
//                              first (a fresh device).

/// An in-memory zone with failure injection.
@MainActor
final class FakeZoneSource: IdentityZoneSource {
    var records: [String: ZoneRecord] = [:]
    var account: ICloudAccountState = .available
    var userName: String? = "_fakeUser"
    var zoneExists = true
    /// Fail the whole-zone read (U6-fail), or mark it incomplete for one record (U15a).
    var failRead = false
    var incompleteRead = false
    var readDelay: Duration = .zero
    var tokenExpiredOnDelta = 0
    var quotaExceeded = false
    var failTypes: Set<String> = []
    /// Changes and deletes made "on another device" after the last read.
    var pendingChanged: [ZoneRecord] = []
    var pendingDeleted: [String: String] = [:]
    /// Another device already wrote the household pair (S8 race): its `appUserId`.
    var raceHouseholdOwner: String?
    /// Where "has this device synced before" lives (the live source reads the same key).
    var defaults: UserDefaults = .standard
    private(set) var pushes: [[ZoneRecord]] = []
    var pushesForTests: [[ZoneRecord]] { pushes }
    private(set) var deletes: [String] = []
    private(set) var zoneDeleted = false
    private(set) var readCount = 0
    private(set) var zonesCreated = 0
    private(set) var deltaPullCount = 0
    /// The last delta pull had no token, so it fetched the whole zone.
    private(set) var lastDeltaWasWholeZone = false
    /// Records a delta pull fails to fetch once (CloudKit's per-record `recordWasChangedBlock` failure).
    var failOnceInDelta: Set<String> = []
    /// The zone's change log: a token is the last sequence it covers, so a pull from an older token
    /// sees a change again and a pull from a newer one never does (as CloudKit).
    private struct LoggedChange { var sequence: Int; var record: ZoneRecord?; var deletedName: String?; var deletedType: String? }
    private var changeLog: [LoggedChange] = []
    private(set) var sequence = 0

    init(records: [ZoneRecord] = []) {
        for r in records { self.records[r.recordName] = r }
    }

    func accountState() async -> ICloudAccountState { account }
    func userRecordName() async -> String? { userName }

    func readWholeZone() async -> ZoneSnapshot {
        readCount += 1
        if readDelay > .zero { try? await Task.sleep(for: readDelay) }
        if failRead {
            var s = ZoneSnapshot.empty(zoneExists: true)
            s.incomplete = true
            s.problem = String(localized: "iCloud didn’t answer (network).", table: "Identity")
            return s
        }
        guard zoneExists else { return ZoneSnapshot.empty(zoneExists: false) }
        absorbPending()
        let all = Array(records.values)
        var snapshot = ZoneSnapshot(readAt: Date(), presentNames: Set(all.map(\.recordName)), records: all.sorted { $0.recordName < $1.recordName },
                                    incomplete: incompleteRead, zoneExists: true, tokenData: Self.token(sequence))
        if incompleteRead { snapshot.problem = String(localized: "iCloud didn’t answer for 1 record.", table: "Identity") }
        return snapshot
    }

    func deltaPull(from token: Data?) async throws -> ZoneDelta {
        if tokenExpiredOnDelta > 0 { tokenExpiredOnDelta -= 1; throw ZoneSourceError.tokenExpired }
        guard zoneExists else { throw ZoneSourceError.zoneGone }
        absorbPending()
        var changed: [String: ZoneRecord] = [:]
        var deleted: [String: String] = [:]
        if let since = Self.sequence(of: token) {
            // Like CloudKit: everything after the token, latest change per record.
            for change in changeLog where change.sequence > since {
                if let record = change.record {
                    changed[record.recordName] = record; deleted[record.recordName] = nil
                } else if let name = change.deletedName {
                    deleted[name] = change.deletedType ?? "TimeEntry"; changed[name] = nil
                }
            }
        } else {
            // No token: the whole zone, no deletes.
            changed = records
        }
        var incomplete = false
        for name in failOnceInDelta where changed[name] != nil {
            // recordWasChangedBlock failed for it: left out, the delta is incomplete, the token still moves.
            changed[name] = nil
            failOnceInDelta.remove(name)
            incomplete = true
        }
        deltaPullCount += 1
        lastDeltaWasWholeZone = Self.sequence(of: token) == nil
        return ZoneDelta(changed: changed.values.sorted { $0.recordName < $1.recordName }, deleted: deleted,
                         tokenData: Self.token(sequence), incomplete: incomplete)
    }

    /// Moves "another device" changes into the zone and the change log.
    private func absorbPending() {
        for r in pendingChanged {
            sequence += 1
            changeLog.append(LoggedChange(sequence: sequence, record: r, deletedName: nil, deletedType: nil))
            records[r.recordName] = r
        }
        for (name, type) in pendingDeleted.sorted(by: { $0.key < $1.key }) {
            sequence += 1
            changeLog.append(LoggedChange(sequence: sequence, record: nil, deletedName: name, deletedType: type))
            records[name] = nil
        }
        pendingChanged = []; pendingDeleted = [:]
    }

    static func token(_ sequence: Int) -> Data { Data("s\(sequence)".utf8) }
    static func sequence(of token: Data?) -> Int? {
        guard let token, let text = String(data: token, encoding: .utf8), text.hasPrefix("s") else { return nil }
        return Int(text.dropFirst())
    }

    func ensureZone() async throws {
        guard !zoneExists else { return }
        if IdentityKeys.knowsZone(defaults) { throw ZoneSourceError.zoneGone }
        zoneExists = true
        zonesCreated += 1
    }

    func saveHousehold(goal: ZoneRecord, tax: ZoneRecord) async throws -> HouseholdSaveResult {
        // Like the live source: a save into a missing zone creates it, unless this device knew
        // the zone (deleted elsewhere: asked, never recreated).
        if !zoneExists {
            if IdentityKeys.knowsZone(defaults) { throw ZoneSourceError.zoneGone }
            zoneExists = true
        }
        if let raceHouseholdOwner, records[goal.recordName] == nil {
            records[goal.recordName] = goal.retagged(raceHouseholdOwner)
            records[tax.recordName] = tax.retagged(raceHouseholdOwner)
        }
        if let existing = records[goal.recordName], let owner = existing.appUserId, owner != goal.appUserId {
            return .adopted(owner)
        }
        records[goal.recordName] = goal
        records[tax.recordName] = tax
        return .saved
    }

    func push(_ batch: [ZoneRecord], deletes names: [String]) async -> ZonePushReport {
        var report = ZonePushReport()
        if !zoneExists {
            // Like the live source: a device that knew the zone never recreates it; a zone it
            // never saw has nothing to delete, and the first save creates it.
            if IdentityKeys.knowsZone(defaults) { report.zoneGone = true; return report }
            report.deletedNames = Set(names)
            guard !batch.isEmpty else { return report }
            zoneExists = true
        }
        if quotaExceeded {
            report.quotaExceeded = true
            for type in Set(batch.map(\.recordType)) { report.failedTypes[type] = 25 }
            return report
        }
        for name in names { records[name] = nil; report.deletedNames.insert(name) }
        deletes += names
        for record in batch {
            if failTypes.contains(record.recordType) { report.failedTypes[record.recordType] = 12; continue }
            var stored = record
            stored.modificationDate = Date()
            records[record.recordName] = stored
            report.savedNames.insert(record.recordName)
        }
        pushes.append(batch)
        return report
    }

    func deleteZone() async throws {
        records = [:]
        zoneExists = false
        zoneDeleted = true
    }

    /// Another device deleted the zone (U37).
    func simulateZoneDeletedElsewhere() { records = [:]; zoneExists = false }
}

enum IdentityFixtures {
    static var args: [String] { ProcessInfo.processInfo.arguments }

    static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    static var crashAt: String? { value(after: "-LHCrashAt") }

    /// Runs before the device phase (AppViewModel.init).
    @MainActor
    static func applyLaunchArguments(defaults: UserDefaults = .standard, root: URL = MigrationFiles.defaultRoot) {
        if args.contains("-LHResetIdentity") || value(after: "-LHUpgradeFixture") != nil {
            resetIdentity(defaults: defaults, root: root)
        }
        if value(after: "-LHUpgradeFixture") != nil {
            let env = ProcessInfo.processInfo.environment
            if let b64 = env["LH_UPGRADE_FIXTURE_B64"], let data = Data(base64Encoded: b64) {
                load(plistData: data, into: defaults)
            }
            if let b64 = env["LH_UPGRADE_SUGGESTIONS_B64"], let data = Data(base64Encoded: b64), let id = env["LH_UPGRADE_SUGGESTIONS_ID"] {
                writeSuggestions(data, id: id, root: root)
            }
        }
    }

    /// Clears every identity key and file (a fresh device). DEBUG only.
    static func resetIdentity(defaults: UserDefaults, root: URL) {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("u.") || key.hasPrefix(IdentityKeys.prefix) || ProfileKeys.signOutKeys.contains(key)
            || key == ProfileKeys.previousProfileId || key == IdentityScope.debugScopeKey || LegacyInventory.unscopedBaseKeys.contains(key)
            || key == CaptureActionQueue.key {
            defaults.removeObject(forKey: key)
        }
        for folder in IdentityFolder.allCases where folder != .attachments {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(folder.rawValue, isDirectory: true))
        }
    }

    /// Bundle directory holding the captured fixtures (copied into DEBUG app builds).
    static func fixtureURL(_ name: String, ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }

    /// Writes one captured fixture's defaults (and capture inbox file) into `defaults`/`root`.
    @discardableResult
    static func loadUpgradeFixture(_ state: String, into defaults: UserDefaults, root: URL, bundleURL: URL? = nil) -> Bool {
        let name = fixtureName(for: state)
        guard let url = bundleURL ?? fixtureURL(name, ext: "plist"), let data = try? Data(contentsOf: url),
              load(plistData: data, into: defaults) else { return false }
        // Capture inbox files ride beside the plist: `<state>.<id>.suggestions.json`.
        let dir = url.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(name + ".") && file.lastPathComponent.hasSuffix(".suggestions.json") {
            let id = String(file.lastPathComponent.dropFirst(name.count + 1).dropLast(".suggestions.json".count))
            if let data = try? Data(contentsOf: file) { writeSuggestions(data, id: id, root: root) }
        }
        return true
    }

    @discardableResult
    static func load(plistData data: Data, into defaults: UserDefaults) -> Bool {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
        for (key, value) in plist where !isSystemKey(key) { defaults.set(value, forKey: key) }
        return true
    }

    static func writeSuggestions(_ data: Data, id: String, root: URL) {
        let target = SuggestionStore.directory(forUserId: id, baseDirectory: root.appendingPathComponent("Capture", isDirectory: true))
            .appendingPathComponent(SuggestionStore.fileName)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: target, options: .atomic)
    }

    static let fixtureNames: [String: String] = [
        "D2": "D2-106-signed-in", "D3": "D3-106-signed-out-two", "D4": "D4-201-email-migrated", "D5": "D5-201-local",
        "D6": "D6-201-apple", "D7": "D7-201-apple-plus-empty-local", "D8": "D8-201-two-local", "D9": "D9-unscoped",
        "D11": "D11-debug", "S": "S-201-suggestions"
    ]

    static func fixtureName(for state: String) -> String { fixtureNames[state] ?? state }

    static func isSystemKey(_ key: String) -> Bool {
        key.hasPrefix("Apple") || key.hasPrefix("NS") || key.hasPrefix("AK") || key.hasPrefix("SK") || key.hasPrefix("com.apple")
            || key.hasPrefix("PK") || key.hasPrefix("WebKit") || key.hasPrefix("INNext")
    }

    // MARK: Fake zones

    /// The zone source a DEBUG launch asked for, if any.
    @MainActor
    static func fakeZoneIfRequested(defaults: UserDefaults = .standard) -> FakeZoneSource? {
        guard let name = value(after: "-LHFakeZone") else { return nil }
        return fakeZone(name, defaults: defaults)
    }

    @MainActor
    static func fakeZone(_ name: String, defaults: UserDefaults = .standard) -> FakeZoneSource {
        let source = FakeZoneSource()
        switch name {
        case "off": source.account = .noAccount
        case "noZone":
            // A fresh install, or a phone after Delete all data: iCloud is on, the zone doesn't exist.
            source.zoneExists = false
        case "restricted": source.account = .restricted
        case "fail": source.failRead = true
        case "slow":
            source.readDelay = .seconds(3)
            source.records = Dictionary(uniqueKeysWithValues: sampleGroup(owner: "email-upgrade.tester@example.com", entries: 14, seed: 0x51).map { ($0.recordName, $0) })
        case "cloudOnly", "email":
            source.records = Dictionary(uniqueKeysWithValues: sampleGroup(owner: "email-upgrade.tester@example.com", entries: 14, seed: 0x51).map { ($0.recordName, $0) })
        case "twoSets":
            let a = sampleGroup(owner: "email-upgrade.tester@example.com", entries: 12, seed: 0x52)
            let b = sampleGroup(owner: "001234.k7f1xture0a00000000000000000000.0202", entries: 4, seed: 0x53)
            source.records = Dictionary(uniqueKeysWithValues: (a + b).map { ($0.recordName, $0) })
        case "quota": source.quotaExceeded = true
        case "accountChanged":
            // This device last read iCloud as "_fakeUser"; the phone now reports another account.
            defaults.set("_fakeUser", forKey: IdentityKeys.icloudUserRecordName)
            source.userName = "_otherUser"
        case "zoneGone":
            // Synced before; the zone was then deleted on another device (U37).
            defaults.set(true, forKey: IdentityKeys.hasSynced)
            RecordSetMigration.setStep(.done, defaults)
            source.zoneExists = false
        case "bulk":
            // U23: this device synced every record; iCloud now holds only 3 of them.
            let live = DefaultsLiveRecordSet(defaults: defaults)
            let storage = defaults.string(forKey: IdentityKeys.storageId) ?? IdentityZone.household
            let tracker = SyncChangeTracker(userId: storage, baseDirectory: MigrationFiles.defaultRoot.appendingPathComponent("Sync", isDirectory: true))
            let all = live.liveProperties.map { CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: storage) }
                + live.liveEntries.map { CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: storage) }
            tracker.recordServerState(all)
            let kept = live.liveProperties.map { ZoneRecord(CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: storage)) }
                + live.liveEntries.prefix(3).map { ZoneRecord(CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: storage)) }
            source.records = Dictionary(uniqueKeysWithValues: kept.map { ($0.recordName, $0) })
        default: break
        }
        return source
    }

    /// A small, fixed group of zone records (entries 2 h each, one property), deterministic ids.
    static func sampleGroup(owner: String?, entries count: Int, seed: UInt8, now: Date = Date()) -> [ZoneRecord] {
        func uuid(_ n: Int) -> UUID {
            UUID(uuidString: String(format: "7A11%02X00-0000-4000-8000-%012X", seed, n)) ?? UUID()
        }
        let property = RentalProperty(id: uuid(0), name: "Maple Court", address: "12 Maple Ct", propertyType: .ltr)
        var records = [ZoneRecord(CloudKitSyncService.record(for: property, zoneID: IdentityZone.zoneID, appUserId: owner))]
        for i in 1...max(count, 1) {
            var entry = TimeEntry(id: uuid(i), propertyId: property.id, participant: .selfParticipant, category: .management, hours: 2,
                                  date: now.addingTimeInterval(-Double(i) * 86_400 * 3), notes: "")
            entry.modifiedAt = now.addingTimeInterval(-Double(i) * 86_400 * 3)
            records.append(ZoneRecord(CloudKitSyncService.record(for: entry, zoneID: IdentityZone.zoneID, appUserId: owner)))
        }
        return records
    }
}
#endif
