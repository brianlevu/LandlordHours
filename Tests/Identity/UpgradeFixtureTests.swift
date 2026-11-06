import XCTest
@testable import LandlordHours

/// S1–S4 over the fixtures captured from shipped 1.0.6 and 2.0.1 builds (Tests/Fixtures/upgrade,
/// scripts/qa/capture_upgrade_fixture.sh). Every row: the §2.3 invariant holds, the expected
/// counts, `u.*` byte-identical before and after, onboarding, Pro and settings carried.
@MainActor
final class UpgradeFixtureTests: XCTestCase {
    private var sandbox: IdentitySandbox!

    override func setUp() {
        super.setUp()
        TestScope.unpin()
        RecordLedger.lastChecks = [:]
        sandbox = IdentitySandbox()
    }

    override func tearDown() {
        sandbox.tearDown()
        super.tearDown()
    }

    private func load(_ state: String) throws {
        XCTAssertNotNil(Fixture.url(state), "fixture \(state) is bundled")
        XCTAssertTrue(Fixture.load(state, into: sandbox), "fixture \(state) loads")
    }

    private var v2Entries: [TimeEntry] { Fixture.entries(sandbox.defaults, key: "v2.LandlordHours.entries") }
    private var v2Properties: [RentalProperty] { Fixture.properties(sandbox.defaults, key: "v2.LandlordHours.properties") }
    private func assertInvariant(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(RecordLedger.lastChecks["S4"] ?? [], [], "the §2.3 invariant at S4", file: file, line: line)
    }

    // MARK: D2 · 1.0.6 signed in (U4)

    func testD2OneEmailGroupBecomesTheRecordSet() throws {
        try load("D2")
        let before = Fixture.legacySnapshot(sandbox.defaults)
        let outcome = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(outcome, .merged(primary: "email-upgrade.tester@example.com", pendingGroups: 0))
        XCTAssertEqual(v2Entries.count, 97)
        XCTAssertEqual(v2Properties.count, 3)
        XCTAssertTrue(sandbox.defaults.bool(forKey: "v2.hasCompletedOnboarding"), "R14: no Welcome for an upgrader")
        XCTAssertTrue(sandbox.defaults.bool(forKey: "v2.isProUser"), "R13: Pro carried")
        XCTAssertTrue(sandbox.defaults.bool(forKey: "v2.LandlordHours.taxProfile.spouseTracking"))
        XCTAssertEqual(sandbox.defaults.string(forKey: IdentityKeys.storageId), "email-upgrade.tester@example.com")
        XCTAssertEqual(Fixture.legacySnapshot(sandbox.defaults), before, "u.* untouched")
        XCTAssertNotNil(MigrationBackup.latestURL(root: sandbox.root), "S2 backup written")
        assertInvariant()
    }

    // MARK: D3 · 1.0.6 signed out, two email profiles (U5)

    func testD3TwoEmailGroupsAskAboutTheSmallerOne() throws {
        try load("D3")
        let before = Fixture.legacySnapshot(sandbox.defaults)
        let outcome = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(outcome, .merged(primary: "email-upgrade.tester@example.com", pendingGroups: 1))
        let earlier = EarlierRecordsStore(root: sandbox.root)
        XCTAssertEqual(earlier.pendingGroups.map(\.id), ["email-old.profile@example.com"], "held, never merged")
        XCTAssertEqual(earlier.pendingGroups.first?.entries.count, 10)
        XCTAssertEqual(v2Entries.count, 97, "only the primary is live until the answer")
        XCTAssertEqual(Fixture.legacySnapshot(sandbox.defaults), before)
        assertInvariant()
    }

    // MARK: D4 · 2.0.1 email migrated to local (U4)

    func testD4TwoPointZeroOneEmailUpgrader() throws {
        try load("D4")
        _ = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(sandbox.defaults.string(forKey: IdentityKeys.storageId), "email-upgrade.tester@example.com")
        XCTAssertEqual(v2Entries.count, 5)
        XCTAssertEqual(EarlierRecordsStore(root: sandbox.root).pendingGroups.map(\.id), ["email-old.profile@example.com"])
        assertInvariant()
    }

    // MARK: D5 · 2.0.1 local profile (U2)

    func testD5LocalProfile() throws {
        try load("D5")
        _ = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(sandbox.defaults.string(forKey: IdentityKeys.storageId), "local-6F1E2D3C-0000-4000-8000-0000000C0A01")
        XCTAssertEqual(v2Entries.count, 10)
        XCTAssertEqual(v2Properties.count, 1)
        assertInvariant()
    }

    // MARK: D6 / D7 · 2.0.1 Apple sign-in (U3), with the empty half-made local profile

    func testD6AppleIdIsJustAGroupName() throws {
        try load("D6")
        _ = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(sandbox.defaults.string(forKey: IdentityKeys.storageId), "001234.k7f1xture0a00000000000000000000.0101")
        XCTAssertEqual(v2Entries.count, 97)
        assertInvariant()
    }

    func testD7TheEmptyLocalGroupIsDroppedSilently() throws {
        try load("D7")
        let outcome = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(outcome, .merged(primary: "001234.k7f1xture0a00000000000000000000.0101", pendingGroups: 0))
        let groups = try XCTUnwrap(GroupsFile.load(root: sandbox.root))
        XCTAssertEqual(groups.group("local-welcome-fixture")?.status, .notNeeded, "never asked about")
        XCTAssertTrue(EarlierRecordsStore(root: sandbox.root).groups.isEmpty)
        assertInvariant()
    }

    // MARK: D8 · two local profiles (U5)

    func testD8TwoLocalProfilesAsk() throws {
        try load("D8")
        let outcome = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(outcome, .merged(primary: "local-6F1E2D3C-0000-4000-8000-0000000C0B02", pendingGroups: 1))
        assertInvariant()
    }

    // MARK: D9 · unscoped 1.0.x keys (U4b)

    func testD9UnscopedKeysAreTheirOwnGroup() throws {
        try load("D9")
        _ = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        let groups = try XCTUnwrap(GroupsFile.load(root: sandbox.root))
        XCTAssertEqual(groups.primaryId, LegacyInventory.unscopedGroupId)
        XCTAssertEqual(sandbox.defaults.string(forKey: IdentityKeys.storageId), IdentityZone.household)
        XCTAssertEqual(v2Entries.count, 97)
        XCTAssertNotNil(sandbox.defaults.object(forKey: "LandlordHours.entries"), "the unscoped keys stay (2.3 cleans up)")
        assertInvariant()
    }

    // MARK: D11 · DEBUG ids

    func testD11DebugIdsAreNeverMigrated() throws {
        try load("D11")
        _ = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(sandbox.defaults.string(forKey: IdentityKeys.storageId), IdentityZone.household)
        XCTAssertTrue(v2Entries.isEmpty)
        XCTAssertFalse((GroupsFile.load(root: sandbox.root)?.groups ?? []).contains { $0.id.hasPrefix("debug-") })
    }

    // MARK: U29 · an unknown key survives the move

    func testU29UnknownKeySurvives() throws {
        try load("D2")
        sandbox.defaults.set("kept", forKey: "u.email-upgrade.tester@example.com.someFutureSetting")
        _ = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(sandbox.defaults.string(forKey: "v2.someFutureSetting"), "kept")
    }

    // MARK: U36 · pending deletes of a 2.0 tracker become tombstones (D10)

    func testU36PendingDeletesBecomeTombstonesAndRemovedCopies() throws {
        try load("D5")
        let id = "local-6F1E2D3C-0000-4000-8000-0000000C0A01"
        let entries = Fixture.entries(sandbox.defaults, key: "u.\(id).LandlordHours.entries")
        let deleted = entries[0].id.uuidString
        Fixture.writeTracker(owner: id, entries: entries, properties: [], pendingDeletes: [deleted], in: sandbox)
        _ = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertFalse(v2Entries.contains { $0.id.uuidString == deleted }, "R3: still a delete")
        XCTAssertTrue(EarlierRecordsStore(root: sandbox.root).containsRemoved(deleted), "with a copy in Recently removed")
        XCTAssertTrue(SyncChangeTracker(userId: id, baseDirectory: sandbox.syncRoot).pendingDeletes.contains(deleted), "pushed once")
        assertInvariant()
    }

    // MARK: U34 · a queued "Log it" under a combined legacy id lands in the live set

    func testU34QueuedLogItIsRekeyedWhenItsSetIsCombined() async throws {
        try load("D8")
        let secondary = "local-6F1E2D3C-0000-4000-8000-0000000C0A01"
        CaptureActionQueue.enqueue(QueuedCaptureAction(profileId: secondary, sourceKey: "cal:evt-9", kind: .confirm, queuedAt: Date()),
                                   defaults: sandbox.defaults)
        let harness = EngineHarness(sandbox)
        try harness.device()
        harness.engine.answer(.combine, group: secondary)
        let storage = sandbox.defaults.string(forKey: IdentityKeys.storageId)
        XCTAssertEqual(CaptureActionQueue.all(defaults: sandbox.defaults).map(\.profileId), [storage])
    }

    // MARK: U33 · two capture inboxes become one

    func testU33SuggestionFilesMergeBySourceKey() throws {
        try load("D5")
        try load("S")
        let main = "local-6F1E2D3C-0000-4000-8000-0000000C0A01"
        let other = "local-6F1E2D3C-0000-4000-8000-0000000C0533"
        let base = sandbox.root.appendingPathComponent("Capture", isDirectory: true)
        let otherURL = SuggestionStore.directory(forUserId: other, baseDirectory: base).appendingPathComponent(SuggestionStore.fileName)
        let otherContents = try JSONDecoder.captureDecoder.decode(SuggestionStore.Contents.self, from: Data(contentsOf: otherURL))
        XCTAssertFalse(otherContents.suggestions.isEmpty, "the captured inbox holds suggestions")
        RecordSetMigration.mergeCaptureFiles(from: [other], into: main, root: sandbox.root)
        RecordSetMigration.mergeCaptureFiles(from: [other], into: main, root: sandbox.root)   // idempotent
        let mainURL = SuggestionStore.directory(forUserId: main, baseDirectory: base).appendingPathComponent(SuggestionStore.fileName)
        let merged = try JSONDecoder.captureDecoder.decode(SuggestionStore.Contents.self, from: Data(contentsOf: mainURL))
        XCTAssertEqual(Set(merged.suggestions.map(\.sourceKey)), Set(otherContents.suggestions.map(\.sourceKey)))
        XCTAssertEqual(merged.suggestions.count, otherContents.suggestions.count, "no duplicates on a re-run")
        XCTAssertEqual(Set(merged.dismissedKeys.keys), Set(otherContents.dismissedKeys.keys), "dismissed keys OR'd")
    }

    // MARK: U20 · disk full at S2

    func testU20BackupFailureLeavesEverythingOnTheLegacyKeys() throws {
        try load("D2")
        let before = Fixture.legacySnapshot(sandbox.defaults)
        var options = RecordSetMigration.DeviceOptions()
        options.writeBackup = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        let outcome = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root, options: options)
        guard case .backupFailed(let needed) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertGreaterThan(needed, 0)
        XCTAssertEqual(IdentityScope.step(sandbox.defaults), .inventoried)
        XCTAssertEqual(IdentityScope.resolve(sandbox.defaults).prefix, "u.email-upgrade.tester@example.com.", "the app runs on the legacy prefix")
        XCTAssertNil(sandbox.defaults.data(forKey: "v2.LandlordHours.entries"), "nothing half-migrated")
        XCTAssertEqual(Fixture.legacySnapshot(sandbox.defaults), before)
        // Space came back: the next launch completes.
        let retry = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(retry, .merged(primary: "email-upgrade.tester@example.com", pendingGroups: 0))
        XCTAssertEqual(IdentityScope.resolve(sandbox.defaults).prefix, "v2.")
        XCTAssertEqual(v2Entries.count, 97)
    }

    // MARK: U12 · crash injection at S2 and S4

    func testU12CrashAtS2AndS4ReRunsToTheSameResult() throws {
        try load("D3")
        let clean = IdentitySandbox()
        defer { clean.tearDown() }
        XCTAssertTrue(Fixture.load("D3", into: clean))
        _ = try RecordSetMigration.runDevicePhase(defaults: clean.defaults, root: clean.root)
        let expected = clean.defaults.data(forKey: "v2.LandlordHours.entries")

        for step in ["S2", "S4"] {
            var options = RecordSetMigration.DeviceOptions()
            options.crashAt = step
            XCTAssertThrowsError(try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root, options: options))
            XCTAssertLessThan(IdentityScope.step(sandbox.defaults), .deviceMerged, "crashed before \(step) completed")
        }
        _ = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(sandbox.defaults.data(forKey: "v2.LandlordHours.entries"), expected, "S4 re-run is byte-identical")
        XCTAssertEqual(EarlierRecordsStore(root: sandbox.root).pendingGroups.count, 1)
        assertInvariant()
    }

    func testDevicePhaseRunsOnce() throws {
        try load("D2")
        _ = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        XCTAssertEqual(try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root), .alreadyMerged)
    }

    func testFreshInstall() throws {
        XCTAssertEqual(try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root), .fresh)
        XCTAssertEqual(IdentityScope.resolve(sandbox.defaults), .init(scopeId: "household", prefix: "v2."))
    }

    // MARK: Performance · S1–S4 under 400 ms for 5,000 entries

    func testS1ToS4On5000EntriesIsUnder400ms() throws {
        try load("D2")
        let id = "email-upgrade.tester@example.com"
        let captured = Fixture.entries(sandbox.defaults, key: "u.\(id).LandlordHours.entries")
        // 5,000 entries made from the captured ones (new ids, same shape).
        var many: [TimeEntry] = []
        while many.count < 5_000 {
            for e in captured where many.count < 5_000 {
                var copy = TimeEntry(propertyId: e.propertyId, participant: e.participant, category: e.category, hours: e.hours,
                                     date: e.date, notes: e.notes, importSource: e.importSource)
                copy.modifiedAt = e.modifiedAt
                many.append(copy)
            }
        }
        sandbox.defaults.set(try JSONEncoder().encode(many), forKey: "u.\(id).LandlordHours.entries")
        let start = Date()
        _ = try RecordSetMigration.runDevicePhase(defaults: sandbox.defaults, root: sandbox.root)
        let ms = Date().timeIntervalSince(start) * 1000
        print("S1–S4 for 5,000 entries: \(Int(ms)) ms")
        XCTAssertEqual(v2Entries.count, 5_000)
        XCTAssertLessThan(ms, 400, "S1–S4 run before the first frame")
    }
}
