import XCTest
@testable import LandlordHours

/// Unit tests share the host app's `UserDefaults.standard`. This snapshots every key package K's
/// scope depends on (the legacy sign-in keys, every `v2.` identity key, the DEBUG scope) and the
/// in-memory scope override, so a test can pin its own scope and leave the host as it found it.
struct AuthStateSnapshot {
    static var keys: [String] {
        ProfileKeys.signOutKeys + [ProfileKeys.previousProfileId, IdentityScope.debugScopeKey,
                                   IdentityKeys.state, IdentityKeys.storageId, IdentityKeys.unifiedId,
                                   IdentityKeys.unifiedIdDecided, IdentityKeys.legacyPrefixId]
    }
    private var values: [String: Any] = [:]
    private var override: String?

    static func capture(_ defaults: UserDefaults = .standard) -> AuthStateSnapshot {
        var snapshot = AuthStateSnapshot()
        for key in keys { if let value = defaults.object(forKey: key) { snapshot.values[key] = value } }
        snapshot.override = IdentityScope.debugOverride
        return snapshot
    }

    /// Clears the sign-in keys and any pinned scope (the identity state of the host stays).
    static func clearAll(_ defaults: UserDefaults = .standard) {
        for key in ProfileKeys.signOutKeys + [ProfileKeys.previousProfileId, IdentityScope.debugScopeKey] {
            defaults.removeObject(forKey: key)
        }
        IdentityScope.debugOverride = nil
    }

    func restore(_ defaults: UserDefaults = .standard) {
        for key in Self.keys {
            if let value = values[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        IdentityScope.debugOverride = override
    }
}

/// Pins the record-set scope to an isolated legacy-shaped scope (`u.<id>.`) for a test.
enum TestScope {
    static func pin(_ id: String) { IdentityScope.debugOverride = id }
    static func unpin() { IdentityScope.debugOverride = nil }
}

/// A fresh `UserDefaults` suite and a temp Application Support root for engine tests.
struct IdentitySandbox {
    let defaults: UserDefaults
    let suiteName: String
    let root: URL

    init(_ name: String = #function) {
        suiteName = "IdentityTests.\(name).\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        root = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    var syncRoot: URL { root.appendingPathComponent("Sync", isDirectory: true) }
}

/// Loads a captured upgrade fixture (Tests/Fixtures/upgrade) into a sandbox.
@MainActor
enum Fixture {
    static func url(_ state: String) -> URL? {
        Bundle(for: FixtureBundleToken.self).url(forResource: IdentityFixtures.fixtureName(for: state), withExtension: "plist")
    }

    @discardableResult
    static func load(_ state: String, into sandbox: IdentitySandbox) -> Bool {
        guard let url = url(state) else { return false }
        return IdentityFixtures.loadUpgradeFixture(state, into: sandbox.defaults, root: sandbox.root, bundleURL: url)
    }

    /// Every `u.*` key and value, for "u.* byte-identical before and after".
    static func legacySnapshot(_ defaults: UserDefaults) -> [String: Data] {
        var out: [String: Data] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("u.") {
            out[key] = try? PropertyListSerialization.data(fromPropertyList: ["v": value], format: .binary, options: 0)
        }
        return out
    }

    /// The tracker 2.0 would have written after pushing `records` for `owner` (D10): built with the
    /// shipped `SyncChangeTracker` API from the captured records, never typed by hand.
    static func writeTracker(owner: String, entries: [TimeEntry], properties: [RentalProperty], pendingDeletes: [String] = [],
                             in sandbox: IdentitySandbox) {
        let tracker = SyncChangeTracker(userId: owner, baseDirectory: sandbox.syncRoot)
        let records = properties.map { CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: owner) }
            + entries.map { CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: owner) }
        tracker.recordServerState(records)
        if !pendingDeletes.isEmpty { tracker.addTombstones(pendingDeletes) }
    }

    static func entries(_ defaults: UserDefaults, key: String) -> [TimeEntry] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([TimeEntry].self, from: $0) } ?? []
    }

    static func properties(_ defaults: UserDefaults, key: String) -> [RentalProperty] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([RentalProperty].self, from: $0) } ?? []
    }

    /// The zone records a group's device data would be in iCloud (tagged `owner`).
    static func zoneRecords(entries: [TimeEntry], properties: [RentalProperty], owner: String?) -> [ZoneRecord] {
        properties.map { ZoneRecord(CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: owner)) }
            + entries.map { ZoneRecord(CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: owner)) }
    }
}

private final class FixtureBundleToken {}

/// The engine wired to a sandbox and a fake zone.
@MainActor
final class EngineHarness {
    let sandbox: IdentitySandbox
    let zone: FakeZoneSource
    let live: DefaultsLiveRecordSet
    let earlier: EarlierRecordsStore
    let engine: RecordSetMigration

    init(_ sandbox: IdentitySandbox, zone: FakeZoneSource? = nil) {
        self.sandbox = sandbox
        let zone = zone ?? FakeZoneSource()
        self.zone = zone
        live = DefaultsLiveRecordSet(defaults: sandbox.defaults)
        earlier = EarlierRecordsStore(root: sandbox.root)
        engine = RecordSetMigration(defaults: sandbox.defaults, root: sandbox.root, source: zone, live: live, earlier: earlier)
    }

    @discardableResult
    func device(_ options: RecordSetMigration.DeviceOptions = .init()) throws -> RecordSetMigration.DeviceOutcome {
        try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root, options: options)
    }

    func cloud() async -> RecordSetMigration.CloudOutcome {
        let outcome = await engine.runCloudPhase()
        earlier.reload()
        return outcome
    }

    var step: MigrationStep { IdentityScope.step(sandbox.defaults) }
    var entries: [TimeEntry] { live.liveEntries }
    var properties: [RentalProperty] { live.liveProperties }
    var groups: GroupsFile? { GroupsFile.load(root: sandbox.root) }
    var pushedNames: Set<String> { Set(zone.pushesFlat.map(\.recordName)) }
}

extension FakeZoneSource {
    var pushesFlat: [ZoneRecord] { pushesForTests.flatMap { $0 } }
}
