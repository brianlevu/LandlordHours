import XCTest
@testable import LandlordHours

/// The merge rules one by one (v3 §4.4, v4, package K §2.2): pure functions, no store.
@MainActor
final class MigrationRulesTests: XCTestCase {
    private let oak = UUID(uuidString: "6F1E2D3C-0000-4000-8000-0000000AAA01")!

    private func entry(_ id: String, hours: Double = 2, modified: TimeInterval = 0, sourceKey: String? = nil,
                       participant: Participant = .selfParticipant) -> TimeEntry {
        var e = TimeEntry(id: UUID(uuidString: id)!, propertyId: oak, participant: participant, category: .repairs, hours: hours,
                          date: Date(timeIntervalSince1970: 1_790_000_000), notes: "", sourceKey: sourceKey)
        e.createdAt = Date(timeIntervalSince1970: 1_790_000_000)
        e.modifiedAt = Date(timeIntervalSince1970: 1_790_000_000 + modified)
        return e
    }

    private let idA = "00000000-0000-4000-8000-00000000000A"
    private let idB = "00000000-0000-4000-8000-00000000000B"
    private let idC = "00000000-0000-4000-8000-00000000000C"

    // MARK: R1 / R2

    func testR1NewerModifiedAtWinsAndTheOlderVersionIsReported() {
        let device = [entry(idA, hours: 2, modified: 0)]
        let cloud = [entry(idA, hours: 3, modified: 60), entry(idB)]
        let result = MergeRules.unionReporting(device, cloud)
        XCTAssertEqual(result.merged.map(\.hours), [3, 2])
        XCTAssertEqual(result.losers.map(\.hours), [2], "the older version goes to the backup")
    }

    func testR2EqualTimeDifferentContentDeviceWins() {
        let result = MergeRules.unionReporting([entry(idA, hours: 2)], [entry(idA, hours: 5)])
        XCTAssertEqual(result.merged.map(\.hours), [2])
        XCTAssertEqual(result.losers.map(\.hours), [5])
    }

    func testUnionNeverDedupesByContent() {
        let result = MergeRules.unionReporting([entry(idA)], [entry(idB)])
        XCTAssertEqual(result.merged.count, 2, "two entries with the same content are two entries")
    }

    // MARK: R19

    func testR19OneCalendarEventIsOneEntry() {
        let a = entry(idA, modified: 10, sourceKey: "cal:evt-1")
        let b = entry(idB, modified: 20, sourceKey: "cal:evt-1")
        let c = entry(idC)
        let result = MergeRules.dedupeBySourceKey([a, b, c])
        XCTAssertEqual(Set(result.merged.map(\.id.uuidString)), [idB, idC], "the newer copy wins")
        XCTAssertEqual(result.losers.map(\.id.uuidString), [idA])
    }

    func testR19OnPullMatchesALiveEntryWithTheSameSourceKey() {
        let live = [entry(idA, sourceKey: "cal:evt-1")]
        XCTAssertNotNil(MergeRules.liveMatch(forPulled: entry(idB, sourceKey: "cal:evt-1"), in: live))
        XCTAssertNil(MergeRules.liveMatch(forPulled: entry(idA, sourceKey: "cal:evt-1"), in: live), "the same entry is not a duplicate")
        XCTAssertNil(MergeRules.liveMatch(forPulled: entry(idB), in: live))
    }

    // MARK: R3

    func testR3TombstonesStayDeletes() {
        let split = MergeRules.applyTombstones([entry(idA), entry(idB)], names: [idA])
        XCTAssertEqual(split.kept.map(\.id.uuidString), [idB])
        XCTAssertEqual(split.removed.map(\.id.uuidString), [idA])
    }

    // MARK: R5 / R5c (U15, U16, U23, U23b)

    private func names(_ n: Int, prefix: String = "r") -> Set<String> { Set((0..<n).map { "\(prefix)\($0)" }) }
    private let ok = MergeRules.AbsenceGuards(readComplete: true, zoneExists: true, sameAccount: true)

    func testR5IsSkippedOnAnIncompleteRead() {
        let outcome = MergeRules.absence(fingerprinted: names(10), onDevice: names(10), present: names(3),
                                         guards: .init(readComplete: false, zoneExists: true, sameAccount: true))
        XCTAssertEqual(outcome, .skipped("incomplete_read"))
    }

    func testR5IsSkippedWhenTheZoneIsAbsent() {
        let outcome = MergeRules.absence(fingerprinted: names(10), onDevice: names(10), present: [],
                                         guards: .init(readComplete: true, zoneExists: false, sameAccount: true))
        XCTAssertEqual(outcome, .skipped("zone_absent"))
    }

    func testU16ZeroOverlapMeansStaleBaselinesNotDeletes() {
        let outcome = MergeRules.absence(fingerprinted: names(120), onDevice: names(120), present: names(50, prefix: "other"), guards: ok)
        XCTAssertEqual(outcome, .staleBaselines)
    }

    func testU23bBelowHalfAbsentIsRemovedToRecentlyRemoved() {
        let present = names(80)
        let outcome = MergeRules.absence(fingerprinted: names(120), onDevice: names(120), present: present, guards: ok)
        XCTAssertEqual(outcome, .removed(names(120).subtracting(present)))
    }

    func testU23MoreThanHalfAbsentPausesAndAsks() {
        let present = names(37)
        let outcome = MergeRules.absence(fingerprinted: names(120), onDevice: names(120), present: present, guards: ok)
        XCTAssertEqual(outcome, .paused(names(120).subtracting(present)))
    }

    func testU15bAnUnparseableRecordIsPresentSoNeverAbsent() {
        // presentNames is collected before parsing: r0…r9 all present even if 3 fail to decode.
        let outcome = MergeRules.absence(fingerprinted: names(10), onDevice: names(10), present: names(10), guards: ok)
        XCTAssertEqual(outcome, .removed([]))
    }

    func testBulkDeleteThresholdIsHalfTheLiveSet() {
        XCTAssertTrue(MergeRules.isBulkDelete(deleting: 200, liveCount: 200))
        XCTAssertTrue(MergeRules.isBulkDelete(deleting: 6, liveCount: 10))
        XCTAssertFalse(MergeRules.isBulkDelete(deleting: 5, liveCount: 10))
        XCTAssertFalse(MergeRules.isBulkDelete(deleting: 0, liveCount: 0))
    }

    // MARK: R2b

    func testR2bSameOwnerZeroOverlapIsTwoGroups() {
        XCTAssertTrue(MergeRules.isSplit(deviceNames: ["a"], cloudNames: ["b"]))
        XCTAssertFalse(MergeRules.isSplit(deviceNames: ["a", "b"], cloudNames: ["b"]))
        XCTAssertFalse(MergeRules.isSplit(deviceNames: [], cloudNames: ["b"]))
    }

    // MARK: §4.6 unified id (U17, U27)

    func testUnifiedIdPrefersTheHouseholdPair() {
        XCTAssertEqual(MergeRules.unifiedId(householdOwner: "local-A", zoneEntryCounts: ["email-x": 99], devicePrimary: "email-x", excluded: []), "local-A")
    }

    func testUnifiedIdIsTheZoneMajorityTiesLexicographic() {
        XCTAssertEqual(MergeRules.unifiedId(householdOwner: nil, zoneEntryCounts: ["local-C": 180, "local-A": 200], devicePrimary: "local-C", excluded: []), "local-A")
        XCTAssertEqual(MergeRules.unifiedId(householdOwner: nil, zoneEntryCounts: ["local-B": 5, "local-A": 5], devicePrimary: nil, excluded: []), "local-A")
    }

    func testU27AnExcludedIdBecomesHousehold() {
        XCTAssertEqual(MergeRules.unifiedId(householdOwner: nil, zoneEntryCounts: ["email-x": 40], devicePrimary: "email-x", excluded: ["email-x"]), "household")
        XCTAssertEqual(MergeRules.unifiedId(householdOwner: nil, zoneEntryCounts: ["aside-email-x": 40], devicePrimary: nil, excluded: []), "household")
    }

    func testUnifiedIdFallsBackToTheDevicePrimaryThenHousehold() {
        XCTAssertEqual(MergeRules.unifiedId(householdOwner: nil, zoneEntryCounts: [:], devicePrimary: "email-x", excluded: []), "email-x")
        XCTAssertEqual(MergeRules.unifiedId(householdOwner: nil, zoneEntryCounts: [:], devicePrimary: nil, excluded: []), "household")
    }

    // MARK: v4 §3.3 settings precedence (U24, U24b, U24c)

    func testSettingsPrecedenceTable() {
        typealias W = MergeRules.SettingsWinner
        func win(_ household: Bool, dirty: Bool, empty: Bool, setEmpty: Bool, group: Bool) -> W {
            MergeRules.settingsWinner(householdExists: household, localDirty: dirty, dirtyWhileEmpty: empty, liveIsEmpty: setEmpty, groupSettingsExist: group)
        }
        XCTAssertEqual(win(true, dirty: false, empty: false, setEmpty: false, group: false), .household)
        XCTAssertEqual(win(true, dirty: true, empty: false, setEmpty: false, group: false), .local)
        XCTAssertEqual(win(true, dirty: true, empty: true, setEmpty: true, group: false), .householdDiscardingLocal, "U24")
        XCTAssertEqual(win(false, dirty: true, empty: true, setEmpty: true, group: true), .householdDiscardingLocal, "U24b: the group, never defaults")
        XCTAssertEqual(win(false, dirty: true, empty: true, setEmpty: true, group: false), .local, "U24c: nothing in the zone")
        XCTAssertEqual(win(false, dirty: false, empty: false, setEmpty: true, group: false), .nothing, "empty never dictates")
    }

    func testMirrorVsHouseholdUsesServerDates() {
        let now = Date()
        XCTAssertTrue(MergeRules.mirrorBeatsHousehold(mirror: now, household: now.addingTimeInterval(-10)))
        XCTAssertFalse(MergeRules.mirrorBeatsHousehold(mirror: now.addingTimeInterval(-10), household: now))
        XCTAssertFalse(MergeRules.mirrorBeatsHousehold(mirror: nil, household: now))
    }

    // MARK: R20 / R10 / R12 / R11 routing (U31)

    func testRoutingMembershipBeatsTheIncomingTag() {
        var groups = GroupsFile(createdAt: Date(), primaryId: "email-x", groups: [])
        groups.upsert(GroupRecord(id: "local-old", status: .aside, source: .device, entryCount: 1, propertyCount: 0, hours: 1, lastEntryDate: nil))
        groups.upsert(GroupRecord(id: "local-sp", status: .spouse, source: .device, entryCount: 1, propertyCount: 0, hours: 1, lastEntryDate: nil))
        let context = MergeRules.RoutingContext(liveNames: ["live-1"], archiveMembership: ["arch-1": "local-old"], unifiedId: "email-x",
                                                groups: groups, deletedNames: ["gone-1"], tombstones: ["tomb-1"])
        func rec(_ name: String, _ owner: String?) -> ZoneRecord {
            ZoneRecord(recordName: name, recordType: "TimeEntry", fields: owner.map { ["appUserId": .string($0)] } ?? [:])
        }
        XCTAssertEqual(MergeRules.route(rec("live-1", "local-old"), context: context), .live, "U31: a live record stays live")
        XCTAssertEqual(MergeRules.route(rec("arch-1", "email-x"), context: context), .archive("local-old"), "an archived record stays archived")
        XCTAssertEqual(MergeRules.route(rec("n1", "email-x"), context: context), .live)
        XCTAssertEqual(MergeRules.route(rec("n2", "aside-local-old"), context: context), .archive("local-old"))
        XCTAssertEqual(MergeRules.route(rec("n3", "local-old"), context: context), .archive("local-old"))
        XCTAssertEqual(MergeRules.route(rec("n4", "local-sp"), context: context), .liveAsSpouse)
        XCTAssertEqual(MergeRules.route(rec("n5", "001234.new"), context: context), .newGroup("001234.new"))
        XCTAssertEqual(MergeRules.route(rec("gone-1", "email-x"), context: context), .ignore, "R11")
        XCTAssertEqual(MergeRules.route(rec("tomb-1", "email-x"), context: context), .ignore)
    }

    // MARK: R9 / R13 / R14

    func testR9SpouseSwapsBothWays() {
        let swapped = MergeRules.swapParticipants([entry(idA), entry(idB, participant: .spouse)])
        XCTAssertEqual(swapped.map(\.participant), [.spouse, .selfParticipant])
    }

    func testIgnoredDebugIdsAreNeverGroups() {
        XCTAssertTrue(LegacyInventory.isIgnoredId("debug-frequent"))
        XCTAssertFalse(LegacyInventory.isIgnoredId("email-a@b.co"))
        XCTAssertEqual(LegacyGroupKind.of("email-a@b.co"), .email)
        XCTAssertEqual(LegacyGroupKind.of("local-1"), .local)
        XCTAssertEqual(LegacyGroupKind.of("001234.abc.0101"), .apple)
        XCTAssertEqual(LegacyGroupKind.of(LegacyInventory.unscopedGroupId), .unscoped)
    }
}

/// The §2.3 invariant over (UUID, content hash).
@MainActor
final class RecordLedgerTests: XCTestCase {
    private func version(_ name: String, _ hash: String) -> RecordVersion { RecordVersion(name: name, hash: hash) }

    func testAPlacedVersionPasses() {
        var places = RecordLedger.Places()
        places.live = [version("a", "1")]
        places.archived = [version("b", "1")]
        places.removed = [version("c", "1")]
        XCTAssertTrue(RecordLedger.check(before: [version("a", "1"), version("b", "1"), version("c", "1")], places: places).isEmpty)
    }

    func testADisappearedRecordFails() {
        let violations = RecordLedger.check(before: [version("a", "1")], places: RecordLedger.Places())
        XCTAssertEqual(violations.map(\.name), ["a"])
    }

    func testALastWriterLoserNeedsABackupCopy() {
        var places = RecordLedger.Places()
        places.live = [version("a", "2")]
        XCTAssertEqual(RecordLedger.check(before: [version("a", "1"), version("a", "2")], places: places).count, 1)
        places.backup = [version("a", "1")]
        XCTAssertTrue(RecordLedger.check(before: [version("a", "1"), version("a", "2")], places: places).isEmpty)
    }

    func testATombstoneNeedsACopy() {
        var places = RecordLedger.Places()
        places.tombstoned = ["a"]
        XCTAssertEqual(RecordLedger.check(before: [version("a", "1")], places: places).count, 1)
        places.removed = [version("a", "1")]
        XCTAssertTrue(RecordLedger.check(before: [version("a", "1")], places: places).isEmpty)
    }

    func testLiveAndArchivedAtOnceFails() {
        var places = RecordLedger.Places()
        places.live = [version("a", "1")]
        places.archived = [version("a", "1")]
        XCTAssertFalse(RecordLedger.check(before: [version("a", "1")], places: places).isEmpty)
    }

    func testTheContentHashIgnoresTheOwnerTag() {
        var entry = TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: 2, notes: "x")
        entry.modifiedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let a = CloudKitSyncService.record(for: entry, zoneID: IdentityZone.zoneID, appUserId: "email-x")
        let b = CloudKitSyncService.record(for: entry, zoneID: IdentityZone.zoneID, appUserId: "household")
        XCTAssertEqual(RecordLedger.contentHash(a), RecordLedger.contentHash(b))
        XCTAssertNotEqual(SyncChangeTracker.fingerprint(a), SyncChangeTracker.fingerprint(b), "the sync fingerprint still sees the re-tag")
        entry.hours = 3
        XCTAssertNotEqual(RecordLedger.contentHash(a), RecordLedger.contentHash(CloudKitSyncService.record(for: entry, zoneID: IdentityZone.zoneID, appUserId: nil)))
    }

    func testFastEntryHashMatchesTheRecordPath() throws {
        let sandbox = IdentitySandbox()
        defer { sandbox.tearDown() }
        XCTAssertTrue(Fixture.load("D2", into: sandbox))
        var entries = Fixture.entries(sandbox.defaults, key: "u.email-upgrade.tester@example.com.LandlordHours.entries")
        var capture = TimeEntry(propertyId: UUID(), participant: .spouse, category: .management, hours: 1.25, notes: "a\u{1F}b",
                                importSource: "calendar", importExternalId: "x", importCalendarId: "c", detectedAt: Date(),
                                confirmedAt: Date(), sourceDetail: "backfill", sourceKey: "cal:1", recordDescription: "Fixed it")
        capture.modifiedAt = Date(timeIntervalSince1970: 1_790_000_000.5)
        entries.append(capture)
        XCTAssertGreaterThan(entries.count, 90)
        for entry in entries {
            let slow = RecordLedger.contentHash(CloudKitSyncService.record(for: entry, zoneID: IdentityZone.zoneID, appUserId: "email-x"))
            XCTAssertEqual(RecordLedger.entryHash(entry), slow)
        }
    }

    func testZoneRecordRoundTripKeepsTheHash() {
        var entry = TimeEntry(propertyId: UUID(), participant: .spouse, category: .management, hours: 1.5, notes: "n", sourceKey: "cal:1")
        entry.modifiedAt = Date(timeIntervalSince1970: 1_790_000_123.456)
        let record = CloudKitSyncService.record(for: entry, zoneID: IdentityZone.zoneID, appUserId: "email-x")
        let zone = ZoneRecord(record)
        XCTAssertEqual(zone.contentHash, RecordLedger.contentHash(record))
        XCTAssertEqual(zone.entry?.hours, 1.5)
        XCTAssertEqual(zone.entry?.sourceKey, "cal:1")
        let data = try? JSONEncoder().encode(zone)
        let decoded = data.flatMap { try? JSONDecoder().decode(ZoneRecord.self, from: $0) }
        XCTAssertEqual(decoded?.contentHash, zone.contentHash, "the snapshot file keeps the exact version")
    }
}
