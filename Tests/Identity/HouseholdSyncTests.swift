import XCTest
@testable import LandlordHours

/// S5–S10 and the steady-state pull against the fake zone (U-rows of §5.1). The device-side
/// data comes from the captured fixtures; the zone holds what those builds would have pushed.
@MainActor
final class HouseholdSyncTests: XCTestCase {
    private var sandbox: IdentitySandbox!
    private let email = "email-upgrade.tester@example.com"
    private let local = "local-6F1E2D3C-0000-4000-8000-0000000C0A01"

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

    private func legacy(_ id: String) -> (entries: [TimeEntry], properties: [RentalProperty]) {
        (Fixture.entries(sandbox.defaults, key: "u.\(id).LandlordHours.entries"),
         Fixture.properties(sandbox.defaults, key: "u.\(id).LandlordHours.properties"))
    }

    private func assertNoViolations(file: StaticString = #filePath, line: UInt = #line) {
        for (step, violations) in RecordLedger.lastChecks {
            XCTAssertEqual(violations, [], "invariant at \(step)", file: file, line: line)
        }
    }

    // MARK: U4 · a 1.x upgrader whose records are already in iCloud

    func testU4SameGroupOnDeviceAndInICloudBecomesOneSet() async throws {
        XCTAssertTrue(Fixture.load("D2", into: sandbox))
        let device = legacy(email)
        Fixture.writeTracker(owner: email, entries: device.entries, properties: device.properties, in: sandbox)
        let zone = FakeZoneSource(records: Fixture.zoneRecords(entries: device.entries, properties: device.properties, owner: email))
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome = await h.cloud()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(h.entries.count, 97)
        XCTAssertEqual(sandbox.defaults.string(forKey: IdentityKeys.unifiedId), email, "the legacy id: 2.0.x devices keep seeing it")
        XCTAssertEqual(zone.records[IdentityZone.goalSettingsName(IdentityZone.household)]?.appUserId, email)
        XCTAssertNotNil(zone.records[IdentityZone.goalSettingsName(email)], "the mirror pair for 2.0.x devices")
        XCTAssertTrue(h.earlier.pendingGroups.isEmpty, "no question")
        XCTAssertEqual(h.step, .done)
        assertNoViolations()
    }

    // MARK: U6 · a new phone, same iCloud: records arrive with no tap

    func testU6NewPhoneGetsTheICloudGroupAutomatically() async throws {
        let zone = IdentityFixtures.fakeZone("cloudOnly")
        let h = EngineHarness(sandbox, zone: zone)
        XCTAssertEqual(try h.device(), .fresh)
        let outcome1 = await h.cloud()
        XCTAssertEqual(outcome1, .done)
        XCTAssertEqual(h.entries.count, 14)
        XCTAssertEqual(h.properties.count, 1)
        XCTAssertTrue(h.earlier.pendingGroups.isEmpty, "a single non-empty group is never asked about")
        XCTAssertEqual(sandbox.defaults.string(forKey: IdentityKeys.unifiedId), "email-upgrade.tester@example.com")
        assertNoViolations()
    }

    func testU6FailTheReadFailsShowsItAndRetries() async throws {
        let zone = IdentityFixtures.fakeZone("cloudOnly")
        zone.failRead = true
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome24 = await h.cloud()
        guard case .incomplete = outcome24 else { return XCTFail("an incomplete read is not 'nothing found'") }
        XCTAssertEqual(h.step, .deviceMerged)
        XCTAssertNotNil(sandbox.defaults.string(forKey: IdentityKeys.lastSyncProblem), "the status row says it failed")
        XCTAssertTrue(sandbox.defaults.bool(forKey: IdentityKeys.noticeCloudWaiting), "Today card P11")
        XCTAssertTrue(h.entries.isEmpty)
        zone.failRead = false
        let outcome2 = await h.cloud()
        XCTAssertEqual(outcome2, .done)
        XCTAssertEqual(h.entries.count, 14)
    }

    // MARK: U15a / U15b · partial read, unparseable records

    func testU15aAPartialReadRemovesNothing() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let device = legacy(local)
        Fixture.writeTracker(owner: local, entries: device.entries, properties: device.properties, in: sandbox)
        let zone = FakeZoneSource(records: Array(Fixture.zoneRecords(entries: device.entries, properties: device.properties, owner: local).prefix(2)))
        zone.incompleteRead = true
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome25 = await h.cloud()
        guard case .incomplete = outcome25 else { return XCTFail() }
        XCTAssertEqual(h.entries.count, 10, "0 removed")
        XCTAssertTrue(h.earlier.removed.isEmpty)
    }

    func testU15bUnparseableRecordsAreKeptCountedAndNeverAbsent() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let device = legacy(local)
        Fixture.writeTracker(owner: local, entries: device.entries, properties: device.properties, in: sandbox)
        var records = Fixture.zoneRecords(entries: device.entries, properties: device.properties, owner: local)
        for i in records.indices where records[i].recordType == "TimeEntry" && i < 4 { records[i].fields["participant"] = .string("Partner") }
        let zone = FakeZoneSource(records: records)
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome3 = await h.cloud()
        XCTAssertEqual(outcome3, .done)
        XCTAssertEqual(h.entries.count, 10, "the device copies stay; nothing is inferred absent")
        XCTAssertTrue(h.earlier.removed.isEmpty)
        XCTAssertEqual(sandbox.defaults.integer(forKey: IdentityKeys.unparsedCount), 3, "P26 counts them")
        XCTAssertEqual(h.earlier.unparsedNames.count, 3, "kept raw")
    }

    // MARK: U16 · account switched before the upgrade

    func testU16ZeroOverlapDiscardsBaselinesAndAsks() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let device = legacy(local)
        Fixture.writeTracker(owner: local, entries: device.entries, properties: device.properties, in: sandbox)
        let zone = FakeZoneSource(records: IdentityFixtures.sampleGroup(owner: "local-B", entries: 5, seed: 0x61))
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome4 = await h.cloud()
        XCTAssertEqual(outcome4, .done)
        XCTAssertEqual(h.entries.count, 10, "0 archived from the device")
        XCTAssertEqual(h.earlier.pendingGroups.map(\.id), ["local-B"], "the zone's group is asked about")
        XCTAssertTrue(h.earlier.removed.isEmpty)
        assertNoViolations()
    }

    // MARK: U17 · two devices migrate at once

    func testU17TheLoserAdoptsTheWinnersId() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let zone = FakeZoneSource()
        zone.raceHouseholdOwner = "local-A-other-device"
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome5 = await h.cloud()
        XCTAssertEqual(outcome5, .done)
        XCTAssertEqual(sandbox.defaults.string(forKey: IdentityKeys.unifiedId), "local-A-other-device")
        let tags = Set(h.zone.pushesFlat.filter(\.isUserRecord).compactMap(\.appUserId))
        XCTAssertEqual(tags, ["local-A-other-device"], "nothing is pushed under the losing id")
    }

    // MARK: U18 · a delete on a 2.0 device between S5 and the push

    func testU18AWindowDeleteArrivesThroughTheDelta() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let device = legacy(local)
        let zone = FakeZoneSource(records: Fixture.zoneRecords(entries: device.entries, properties: device.properties, owner: local))
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        h.engine.crashAt = "S8"
        _ = await h.cloud()
        let gone = device.entries[0].id.uuidString
        zone.pendingDeleted = [gone: "TimeEntry"]
        h.engine.crashAt = nil
        let outcome6 = await h.cloud()
        XCTAssertEqual(outcome6, .done)
        XCTAssertFalse(h.entries.contains { $0.id.uuidString == gone })
        let removed = try XCTUnwrap(h.earlier.removed.first { $0.name == gone })
        XCTAssertEqual(removed.reason, .deletedElsewhere)
        XCTAssertNotNil(removed.keepUntil, "a delete the person made elsewhere: 30 days")
        XCTAssertFalse(h.pushedNames.contains(gone), "never pushed back")
    }

    // MARK: U21 · same owner id, zero overlap

    func testU21SameIdDisjointRecordsAreTwoSets() async throws {
        XCTAssertTrue(Fixture.load("D2", into: sandbox))
        let zone = FakeZoneSource(records: IdentityFixtures.sampleGroup(owner: email, entries: 4, seed: 0x62))
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome7 = await h.cloud()
        XCTAssertEqual(outcome7, .done)
        XCTAssertEqual(h.entries.count, 97, "no silent union")
        let group = try XCTUnwrap(h.earlier.pendingGroups.first)
        XCTAssertEqual(group.entries.count, 4)
        XCTAssertEqual(h.groups?.group(email)?.splitFromDevice, true)
        XCTAssertEqual(sandbox.defaults.string(forKey: IdentityKeys.unifiedId), IdentityZone.household, "U27: a split id is excluded")
    }

    // MARK: U22 · changeTokenExpired

    func testU22TokenExpiredLoopsBackToAWholeRead() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let zone = FakeZoneSource()
        zone.tokenExpiredOnDelta = 2
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome8 = await h.cloud()
        XCTAssertEqual(outcome8, .done)
        XCTAssertEqual(zone.readCount, 3, "S5 again after each expired token")
        XCTAssertEqual(h.entries.count, 10)
    }

    func testU22AfterThreeLoopsTheMigrationProceeds() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let zone = FakeZoneSource()
        zone.tokenExpiredOnDelta = 10
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome9 = await h.cloud()
        XCTAssertEqual(outcome9, .done)
        XCTAssertEqual(h.engine.lastStats.deltaAbandoned, true)
        XCTAssertEqual(h.entries.count, 10, "no record lost")
    }

    // MARK: U23 / U23b · bulk absence

    private func bulkSetup(present: Int) throws -> EngineHarness {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let device = legacy(local)
        Fixture.writeTracker(owner: local, entries: device.entries, properties: device.properties, in: sandbox)
        let records = Fixture.zoneRecords(entries: Array(device.entries.prefix(present)), properties: device.properties, owner: local)
        return EngineHarness(sandbox, zone: FakeZoneSource(records: records))
    }

    func testU23MostRecordsAbsentPausesAndAsks() async throws {
        let h = try bulkSetup(present: 3)
        try h.device()
        let outcome10 = await h.cloud()
        XCTAssertEqual(outcome10, .done)
        let hold = try XCTUnwrap(h.earlier.bulkHold, "P28")
        XCTAssertEqual(hold.names.count, 7)
        XCTAssertEqual(h.entries.count, 10, "all visible")
        XCTAssertTrue(hold.names.isDisjoint(with: h.pushedNames), "held records are not pushed")
        h.engine.answerBulk(.keep)
        await h.engine.pushLive()
        XCTAssertTrue(hold.names.isSubset(of: h.pushedNames), "Keep → pushed as new")
        XCTAssertEqual(h.entries.count, 10)
    }

    func testU23RemoveSendsThemToRecentlyRemovedUntilTheyAct() async throws {
        let h = try bulkSetup(present: 3)
        try h.device()
        _ = await h.cloud()
        h.engine.answerBulk(.remove)
        XCTAssertEqual(h.entries.count, 3)
        XCTAssertEqual(h.earlier.removed.count, 7)
        XCTAssertTrue(h.earlier.removed.allSatisfy { $0.keepUntil == nil }, "kept until the person acts")
        h.engine.putBack(Set(h.earlier.removed.map(\.name)))
        XCTAssertEqual(h.entries.count, 10, "Put back")
    }

    func testU23bBelowHalfIsRemovedWithPutBack() async throws {
        let h = try bulkSetup(present: 7)
        try h.device()
        let outcome11 = await h.cloud()
        XCTAssertEqual(outcome11, .done)
        XCTAssertNil(h.earlier.bulkHold)
        XCTAssertEqual(h.entries.count, 7)
        XCTAssertEqual(h.earlier.removed.count, 3)
        XCTAssertTrue(h.earlier.removed.allSatisfy { $0.reason == .inferredAbsent && $0.keepUntil == nil })
        assertNoViolations()
    }

    // MARK: U24 / U24c · onboarding before the cloud read

    func testU24DirtyWhileEmptyNeverBeatsTheHousehold() async throws {
        let zone = FakeZoneSource(records: IdentityFixtures.sampleGroup(owner: email, entries: 3, seed: 0x63))
        let household = GoalSettingsValues(globalGoalType: HourGoalType.reps.rawValue, materialParticipationTarget: nil,
                                           propertyGoalsJSON: "[{\"id\":\"6F1E2D3C-0000-4000-8000-00000000F001\",\"propertyId\":\"7A116300-0000-4000-8000-000000000000\",\"goalType\":\"REPS\"}]")
        zone.records[IdentityZone.goalSettingsName(IdentityZone.household)] = household.record(name: IdentityZone.goalSettingsName(IdentityZone.household), owner: email)
        zone.records[IdentityZone.taxProfileName(IdentityZone.household)] = TaxProfileValues(filingStatus: FilingStatus.marriedJoint.rawValue, spouseTracking: true, taxYear: 2026, groupingElection: true, nonREWorkHours: 0, displayName: "Sam").record(name: IdentityZone.taxProfileName(IdentityZone.household), owner: email)
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        // Onboarding answers on the fresh phone, before iCloud answered.
        sandbox.defaults.set("STR", forKey: "v2.globalGoalType")
        sandbox.defaults.set(false, forKey: "v2.LandlordHours.taxProfile.spouseTracking")
        for key in [IdentityKeys.goalDirty, IdentityKeys.goalDirtyWhileEmpty, IdentityKeys.taxDirty, IdentityKeys.taxDirtyWhileEmpty] {
            sandbox.defaults.set(true, forKey: key)
        }
        let outcome12 = await h.cloud()
        XCTAssertEqual(outcome12, .done)
        XCTAssertEqual(h.live.goalSettings.globalGoalType, HourGoalType.reps.rawValue, "the household wins")
        XCTAssertEqual(h.live.goalSettings.propertyGoals.count, 1, "propertyGoals intact")
        XCTAssertTrue(h.live.taxProfile.spouseTracking)
        XCTAssertEqual(h.live.taxProfile.displayName, "Sam", "Your name travels in TaxProfile.displayName")
        XCTAssertTrue(sandbox.defaults.bool(forKey: IdentityKeys.noticeSettingsKept), "P29")
        XCTAssertNotNil(sandbox.defaults.data(forKey: IdentityKeys.discardedOnboardingAnswers), "kept in Advanced, never lost")
    }

    func testU24cAnEmptyZoneTakesTheOnboardingAnswers() async throws {
        let zone = FakeZoneSource()
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        sandbox.defaults.set("STR", forKey: "v2.globalGoalType")
        sandbox.defaults.set(true, forKey: IdentityKeys.goalDirty)
        sandbox.defaults.set(true, forKey: IdentityKeys.goalDirtyWhileEmpty)
        let outcome13 = await h.cloud()
        XCTAssertEqual(outcome13, .done)
        let saved = try XCTUnwrap(zone.records[IdentityZone.goalSettingsName(IdentityZone.household)])
        XCTAssertEqual(GoalSettingsValues(record: saved).globalGoalType, "STR")
    }

    // MARK: U26 / U26b · steady-state pulled deletes

    private func doneHarness() async throws -> (EngineHarness, [TimeEntry]) {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let device = legacy(local)
        let zone = FakeZoneSource(records: Fixture.zoneRecords(entries: device.entries, properties: device.properties, owner: local))
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome14 = await h.cloud()
        XCTAssertEqual(outcome14, .done)
        return (h, device.entries)
    }

    func testU26ADeleteAccountOnA20DeviceBecomesAQuestion() async throws {
        let (h, entries) = try await doneHarness()
        var deleted = Dictionary(uniqueKeysWithValues: entries.map { ($0.id.uuidString, "TimeEntry") })
        for p in h.properties { deleted[p.id.uuidString] = "Property" }
        let outcome = h.engine.applyPull(ZoneDelta(changed: [], deleted: deleted, tokenData: nil, incomplete: false))
        XCTAssertEqual(outcome.removed, 0, "nothing removed until answered")
        XCTAssertNotNil(h.earlier.bulkHold)
        XCTAssertEqual(h.entries.count, 10)
    }

    func testU26bSingleDeletesGoToRecentlyRemovedFor30Days() async throws {
        let (h, entries) = try await doneHarness()
        let outcome = h.engine.applyPull(ZoneDelta(changed: [], deleted: [entries[0].id.uuidString: "TimeEntry", entries[1].id.uuidString: "TimeEntry"],
                                                   tokenData: nil, incomplete: false))
        XCTAssertEqual(outcome.removed, 2)
        XCTAssertEqual(h.entries.count, 8)
        XCTAssertEqual(h.earlier.removed.count, 2)
        XCTAssertTrue(h.earlier.removed.allSatisfy { $0.keepUntil != nil && $0.reason == .deletedElsewhere })
        XCTAssertTrue(h.engine.deletedNames().contains(entries[0].id.uuidString), "R11: a 1.1 device can't resurrect it")
    }

    // MARK: U28 / U30 · unscoped 1.x users (D9 + Z6 + Z4)

    func testU28AndU30UnscopedRecordsAndTheDefaultSettingsPair() async throws {
        XCTAssertTrue(Fixture.load("D9", into: sandbox))
        let entries = Fixture.entries(sandbox.defaults, key: "LandlordHours.entries")
        let properties = Fixture.properties(sandbox.defaults, key: "LandlordHours.properties")
        var records = Fixture.zoneRecords(entries: entries, properties: properties, owner: nil)   // Z4: no appUserId
        let extra = IdentityFixtures.sampleGroup(owner: nil, entries: 2, seed: 0x64)                  // pushed by another unscoped device
        records += extra
        records.append(TaxProfileValues(filingStatus: FilingStatus.single.rawValue, spouseTracking: false, taxYear: 2025, groupingElection: false,
                                        nonREWorkHours: 12, displayName: nil).record(name: IdentityZone.taxProfileName("default"), owner: nil))
        let h = EngineHarness(sandbox, zone: FakeZoneSource(records: records))
        try h.device()
        let outcome15 = await h.cloud()
        XCTAssertEqual(outcome15, .done)
        XCTAssertEqual(h.entries.count, 97 + 2, "zero ownerless records dropped")
        XCTAssertEqual(h.engine.lastStats.untaggedAdopted, entries.count + properties.count + extra.count)
        XCTAssertEqual(h.live.taxProfile.filingStatus, FilingStatus.single.rawValue, "Z6: the -default pair is the unscoped group's")
        assertNoViolations()
    }

    // MARK: U31 · ping-pong: membership beats the incoming tag

    func testU31AnArchivedRecordRePushedUnderItsLegacyIdStaysArchived() async throws {
        XCTAssertTrue(Fixture.load("D3", into: sandbox))
        let old = "email-old.profile@example.com"
        let h = EngineHarness(sandbox, zone: FakeZoneSource())
        try h.device()
        let outcome16 = await h.cloud()
        XCTAssertEqual(outcome16, .done)
        h.engine.answer(.aside, group: old)
        var edited = try XCTUnwrap(h.earlier.group(old)?.entries.first)
        for _ in 0..<3 {
            edited.notes += "!"
            edited.modifiedAt = edited.modifiedAt.addingTimeInterval(60)
            let record = ZoneRecord(CloudKitSyncService.record(for: edited, zoneID: IdentityZone.zoneID, appUserId: email))
            h.engine.applyPull(ZoneDelta(changed: [record], deleted: [:], tokenData: nil, incomplete: false))
        }
        XCTAssertFalse(h.entries.contains { $0.id == edited.id }, "membership unchanged over three pulls")
        XCTAssertTrue(h.earlier.group(old)?.entries.contains { $0.id == edited.id } ?? false)
    }

    // MARK: U32 · one calendar event confirmed in two sets

    func testU32CombineNeverDoublesCapturedHours() async throws {
        XCTAssertTrue(Fixture.load("D8", into: sandbox))
        let primary = "local-6F1E2D3C-0000-4000-8000-0000000C0B02"
        let secondary = local
        var a = Fixture.entries(sandbox.defaults, key: "u.\(primary).LandlordHours.entries")
        var b = Fixture.entries(sandbox.defaults, key: "u.\(secondary).LandlordHours.entries")
        a[0].sourceKey = "cal:shared-event"
        b[0].sourceKey = "cal:shared-event"
        b[0].modifiedAt = a[0].modifiedAt.addingTimeInterval(-60)
        sandbox.defaults.set(try JSONEncoder().encode(a), forKey: "u.\(primary).LandlordHours.entries")
        sandbox.defaults.set(try JSONEncoder().encode(b), forKey: "u.\(secondary).LandlordHours.entries")
        let h = EngineHarness(sandbox, zone: FakeZoneSource())
        try h.device()
        _ = await h.cloud()
        let before = h.entries.count
        h.engine.answer(.combine, group: secondary)
        XCTAssertEqual(h.entries.filter { $0.sourceKey == "cal:shared-event" }.count, 1, "hours not doubled")
        XCTAssertEqual(h.entries.count, before + b.count - 1)
        let losers = sandbox.root.appendingPathComponent("migration/answer-\(secondary)-losers.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: losers.path), "the loser is recorded with the backup")
    }

    // MARK: Spouse and aside answers (P5 / P6 / P17)

    func testSpouseAnswerSwapsParticipantsAndUndoWalksItBack() async throws {
        XCTAssertTrue(Fixture.load("D8", into: sandbox))
        let h = EngineHarness(sandbox, zone: FakeZoneSource())
        try h.device()
        _ = await h.cloud()
        let before = h.entries.count
        let group = try XCTUnwrap(h.earlier.group(local))
        h.engine.answer(.spouse, group: local)
        XCTAssertEqual(h.entries.count, before + group.entries.count)
        let moved = h.entries.filter { e in group.entries.contains { $0.id == e.id } }
        XCTAssertTrue(zip(moved.sorted { $0.id.uuidString < $1.id.uuidString }, group.entries.sorted { $0.id.uuidString < $1.id.uuidString })
            .allSatisfy { $0.participant != $1.participant }, "Self↔Spouse")
        XCTAssertTrue(h.live.taxProfile.spouseTracking)
        XCTAssertNotNil(h.groups?.group(local)?.undoUntil)
        h.engine.undoSpouse(group: local)
        XCTAssertEqual(h.entries.count, before)
        XCTAssertEqual(h.earlier.pendingGroups.map(\.id), [local], "waiting for an answer again")
    }

    func testAsideIsPushedUnderAsidePrefixNeverTheUnifiedId() async throws {
        XCTAssertTrue(Fixture.load("D3", into: sandbox))
        let old = "email-old.profile@example.com"
        let zone = FakeZoneSource()
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome17 = await h.cloud()
        XCTAssertEqual(outcome17, .done)
        let group = try XCTUnwrap(h.earlier.group(old))
        let asideTags = Set(zone.records.values.filter { r in group.entries.contains { $0.id.uuidString == r.recordName } }.compactMap(\.appUserId))
        XCTAssertEqual(asideTags, ["aside-\(old)"], "R10: held sets survive the device, under aside-")
    }

    // MARK: U35 · a notification under a merged legacy id is accepted

    func testU35MergedLegacyIdsAreLive() async throws {
        XCTAssertTrue(Fixture.load("D8", into: sandbox))
        let h = EngineHarness(sandbox, zone: FakeZoneSource())
        try h.device()
        h.engine.answer(.combine, group: local)
        XCTAssertTrue(MigrationFiles.liveLegacyIds(root: sandbox.root).contains(local))
        XCTAssertTrue(MigrationFiles.liveLegacyIds(root: sandbox.root).contains("local-6F1E2D3C-0000-4000-8000-0000000C0B02"))
    }

    // MARK: U37 · zone deleted on another device

    func testU37ZoneGoneAsksAndReUploadsNothing() async throws {
        let (h, _) = try await doneHarness()
        h.zone.simulateZoneDeletedElsewhere()
        let pushesBefore = h.zone.pushesForTests.count
        try? await Task.sleep(nanoseconds: 1)
        h.engine.tracker.resetBaselines()   // anything at all to push
        let report = await h.engine.pushLive()
        XCTAssertTrue(report.zoneGone)
        XCTAssertEqual(h.engine.handleZoneGone(), .zoneGone)
        XCTAssertTrue(sandbox.defaults.bool(forKey: IdentityKeys.zoneGone), "P31")
        XCTAssertEqual(h.zone.pushesForTests.count, pushesBefore, "nothing re-uploaded")
        XCTAssertTrue(h.zone.records.isEmpty)
        let outcome18 = await h.engine.runCloudPhase()
        XCTAssertEqual(outcome18, .done, "the migration was done; the question pauses sync")
        let ok = await h.engine.answerZoneGone(.keepAndRestore)
        XCTAssertTrue(ok, "Keep: this iPhone's copy goes back to iCloud, only because the person chose it")
        XCTAssertEqual(h.zone.records.values.filter { $0.recordType == "TimeEntry" }.count, 10)
        XCTAssertFalse(sandbox.defaults.bool(forKey: IdentityKeys.zoneGone))
    }

    // MARK: U38 · iCloud full, restricted

    func testU38QuotaKeepsRecordsAndSaysSo() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let zone = FakeZoneSource()
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        _ = await h.cloud()
        zone.quotaExceeded = true
        var entry = h.entries[0]
        entry.hours += 1
        entry.modifiedAt = Date()
        h.live.replaceLive(entries: [entry] + h.entries.dropFirst(), properties: h.properties, categories: [])
        let report = await h.engine.pushLive()
        XCTAssertTrue(report.quotaExceeded)
        XCTAssertNotNil(sandbox.defaults.string(forKey: IdentityKeys.lastSyncProblem))
        XCTAssertTrue(h.engine.tracker.changedRecords([ZoneRecord(CloudKitSyncService.record(for: entry, zoneID: IdentityZone.zoneID,
                                                                                                 appUserId: h.engine.unifiedId)).ckRecord()]).count == 1,
                      "still pending, tried again later")
    }

    func testU38RestrictedReadsAsOff() async throws {
        let zone = IdentityFixtures.fakeZone("restricted")
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome19 = await h.cloud()
        XCTAssertEqual(outcome19, .iCloudOff(.restricted))
    }

    // MARK: U8 · the iCloud account changed

    func testU8AccountChangedPausesAndAsks() async throws {
        let (h, _) = try await doneHarness()
        // A migration run after an account change compares the stored user (steady state does too).
        RecordSetMigration.setStep(.deviceMerged, sandbox.defaults)
        try? FileManager.default.removeItem(at: ZoneSnapshot.url(root: sandbox.root))
        h.zone.userName = "_otherUser"
        let outcome20 = await h.cloud()
        XCTAssertEqual(outcome20, .accountChanged)
        XCTAssertTrue(sandbox.defaults.bool(forKey: IdentityKeys.accountChanged))
        h.zone.records = [:]   // the other account's zone holds nothing of this iPhone's
        let outcome21 = await h.engine.answerAccountChanged(.useThisICloud)
        XCTAssertEqual(outcome21, .done)
        XCTAssertTrue(h.entries.isEmpty, "this iPhone's set went to Earlier records")
        XCTAssertEqual(h.earlier.groups.filter { $0.id.hasPrefix("this-iphone-") }.first?.entries.count, 10, "nothing deleted")
    }

    // MARK: Delete all data deletes the whole zone

    func testDeleteZoneRemovesEverythingInICloud() async throws {
        let (h, _) = try await doneHarness()
        try await h.zone.deleteZone()
        XCTAssertTrue(h.zone.zoneDeleted)
        XCTAssertTrue(h.zone.records.isEmpty)
    }

    // MARK: Settings-only owners are listed (diagnosis §7.2)

    func testAnOwnerWithOnlySettingsRecordsIsListedNotAsked() async throws {
        let settingsOnly = "001234.only-settings.0303"
        let zone = FakeZoneSource(records: [
            GoalSettingsValues.defaults.record(name: IdentityZone.goalSettingsName(settingsOnly), owner: settingsOnly),
            TaxProfileValues(filingStatus: FilingStatus.single.rawValue, spouseTracking: false, taxYear: 2025, groupingElection: false,
                             nonREWorkHours: 0, displayName: nil).record(name: IdentityZone.taxProfileName(settingsOnly), owner: settingsOnly)
        ])
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome = await h.cloud()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(h.groups?.group(settingsOnly)?.settingsOnly, true, "the cloud knew them: found, no hours")
        XCTAssertTrue(h.earlier.pendingGroups.isEmpty, "never asked about")
    }

    // MARK: Per-type push (diagnosis §7.3)

    func testOneFailingRecordTypeNeverBlocksTheOthers() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let zone = FakeZoneSource()
        zone.failTypes = ["CustomCategory"]
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        h.live.replaceLive(entries: h.entries, properties: h.properties,
                           categories: [CustomCategory(name: "Snow", iconName: "snowflake", colorHex: "60A5FA", countsForREPS: true)])
        let outcome22 = await h.cloud()
        XCTAssertEqual(outcome22, .done)
        XCTAssertEqual(h.zone.records.values.filter { $0.recordType == "TimeEntry" }.count, 10, "entries saved")
        XCTAssertTrue(h.zone.records.values.filter { $0.recordType == "CustomCategory" }.isEmpty)
        let category = try XCTUnwrap(h.live.liveCategories.first)
        XCTAssertFalse(h.engine.tracker.hasBaseline(for: category.id.uuidString), "the failed type stays pending")
    }

    // MARK: Crash injection inside the cloud phase (U12)

    func testU12CloudCrashPointsResumeToTheSameResult() async throws {
        for point in ["S5", "S7", "S8", "S8b", "S9"] {
            let box = IdentitySandbox("crash-\(point)")
            defer { box.tearDown() }
            XCTAssertTrue(Fixture.load("D5", into: box))
            let device = (Fixture.entries(box.defaults, key: "u.\(local).LandlordHours.entries"),
                          Fixture.properties(box.defaults, key: "u.\(local).LandlordHours.properties"))
            let zone = FakeZoneSource(records: Fixture.zoneRecords(entries: device.0, properties: device.1, owner: local)
                                      + IdentityFixtures.sampleGroup(owner: local, entries: 2, seed: 0x65))
            let h = EngineHarness(box, zone: zone)
            try h.device()
            h.engine.crashAt = point
            _ = await h.cloud()
            h.engine.crashAt = nil
            let outcome23 = await h.cloud()
            XCTAssertEqual(outcome23, .done, "resume after \(point)")
            XCTAssertEqual(h.entries.count, 12, "\(point): every record once")
            XCTAssertEqual(Set(h.entries.map(\.id)).count, 12)
        }
    }
}

// MARK: - Record-loss regressions (adversarial reviews of v2/k at dc864f1 and ff35d00)
//
// Each test reproduces one path by which a tax hour could be lost or silently changed, through
// the same fake zone the engine uses, with the fake behaving like CloudKit where it matters: a
// zone that doesn't exist yet, a change token that only covers what it covers, and a record the
// delta fails to fetch.

@MainActor
final class RecordLossRegressionTests: XCTestCase {
    private var sandbox: IdentitySandbox!
    private let local = "local-6F1E2D3C-0000-4000-8000-0000000C0A01"

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

    private func newEntry(hours: Double = 3, property: RentalProperty) -> TimeEntry {
        TimeEntry(propertyId: property.id, participant: .selfParticipant, category: .management, hours: hours,
                  date: Date(), notes: "")
    }

    /// What `AppViewModel.wipeEverythingLocal` leaves behind (Delete all data, P31 "Delete here too").
    private func wipeLikeDeleteAll(_ h: EngineHarness) {
        for key in sandbox.defaults.dictionaryRepresentation().keys where key.hasPrefix("u.") || key.hasPrefix(IdentityKeys.prefix) {
            sandbox.defaults.removeObject(forKey: key)
        }
        for folder in IdentityFolder.allCases {
            try? FileManager.default.removeItem(at: sandbox.root.appendingPathComponent(folder.rawValue, isDirectory: true))
        }
        h.earlier.deleteEverything()
        RecordSetMigration.adoptIds(storage: IdentityZone.household, unified: IdentityZone.household, defaults: sandbox.defaults)
        RecordSetMigration.setStep(.deviceMerged, sandbox.defaults)
    }

    // MARK: 1 · a fresh install, or a phone after Delete all data, syncs

    func testAFreshInstallWithNoZoneCreatesItOnTheFirstSyncAndSyncs() async throws {
        let zone = IdentityFixtures.fakeZone("noZone", defaults: sandbox.defaults)
        let h = EngineHarness(sandbox, zone: zone)
        XCTAssertEqual(try h.device(), .fresh)
        let outcome = await h.cloud()
        XCTAssertEqual(outcome, .done, "the cloud phase finishes on an account with no zone yet")
        XCTAssertTrue(zone.zoneExists, "the first sync creates the zone")
        XCTAssertFalse(sandbox.defaults.bool(forKey: IdentityKeys.zoneGone), "never 'deleted on another device'")

        // The first entry after onboarding reaches iCloud, and the next pull works.
        let property = RentalProperty(name: "Elm", address: "1 Elm St", propertyType: .ltr)
        let entry = newEntry(property: property)
        h.live.replaceLive(entries: [entry], properties: [property], categories: [])
        let report = await h.engine.pushLive()
        XCTAssertFalse(report.zoneGone)
        XCTAssertNotNil(zone.records[entry.id.uuidString], "the hour is in iCloud")
        _ = try await zone.deltaPull(from: nil)
        XCTAssertFalse(sandbox.defaults.bool(forKey: IdentityKeys.zoneGone))
    }

    func testAPhoneAfterDeleteAllDataSyncsAgain() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let zone = FakeZoneSource()
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let first = await h.cloud()
        XCTAssertEqual(first, .done)
        // Delete all data: the whole zone, then everything on the phone.
        try await zone.deleteZone()
        wipeLikeDeleteAll(h)
        let again = await h.cloud()
        XCTAssertEqual(again, .done, "a new start syncs like a new install")
        XCTAssertTrue(zone.zoneExists)
        let property = RentalProperty(name: "Oak", address: "2 Oak St", propertyType: .ltr)
        let entry = newEntry(property: property)
        h.live.replaceLive(entries: [entry], properties: [property], categories: [])
        let report = await h.engine.pushLive()
        XCTAssertFalse(report.zoneGone)
        XCTAssertNotNil(zone.records[entry.id.uuidString])
    }

    func testAZoneThisPhoneReadThenDeletedElsewhereIsAskedAboutNeverRecreated() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let device = (Fixture.entries(sandbox.defaults, key: "u.\(local).LandlordHours.entries"),
                      Fixture.properties(sandbox.defaults, key: "u.\(local).LandlordHours.properties"))
        let zone = FakeZoneSource(records: Fixture.zoneRecords(entries: device.0, properties: device.1, owner: local))
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        h.engine.crashAt = "S7"
        _ = await h.cloud()                          // S5 read the zone
        zone.simulateZoneDeletedElsewhere()          // Delete all data on another phone
        h.engine.crashAt = nil
        let outcome = await h.cloud()
        XCTAssertEqual(outcome, .zoneGone, "P31: asked, not recreated")
        XCTAssertFalse(zone.zoneExists, "the deleted zone stays deleted")
        XCTAssertTrue(zone.records.isEmpty, "nothing re-uploaded")
        XCTAssertEqual(h.entries.count, 10, "this phone's copy is kept")
    }

    // MARK: 2 · Undo spouse deletes nothing from iCloud

    func testUndoSpouseKeepsEveryHourInICloudAndRestoresThePriorState() async throws {
        XCTAssertTrue(Fixture.load("D8", into: sandbox))
        let zone = FakeZoneSource()
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let done = await h.cloud()
        XCTAssertEqual(done, .done)
        let group = try XCTUnwrap(h.earlier.group(local))
        let names = Set(group.entries.map(\.id.uuidString))
        XCTAssertFalse(names.isEmpty)
        h.engine.answer(.spouse, group: local)
        await h.engine.pushLive()                    // the spouse's hours reach iCloud as the household's
        XCTAssertTrue(names.isSubset(of: Set(zone.records.keys)))

        h.engine.undoSpouse(group: local)
        await h.engine.pushLive()
        XCTAssertTrue(Set(zone.deletes).isDisjoint(with: names), "Undo deletes nothing in iCloud")
        XCTAssertTrue(names.isSubset(of: Set(zone.records.keys)), "every spouse hour is still in iCloud")
        let tags = Set(names.compactMap { zone.records[$0]?.appUserId })
        XCTAssertFalse(tags.contains(h.engine.unifiedId), "no longer live under the household's id")
        for original in group.entries {
            XCTAssertEqual(zone.records[original.id.uuidString]?.entry?.participant, original.participant, "participants as before")
        }
        XCTAssertEqual(h.earlier.pendingGroups.map(\.id), [local], "waiting for an answer again")
        XCTAssertEqual(Set(try XCTUnwrap(h.earlier.group(local)).entries.map(\.id.uuidString)), names)

        // A new phone on the same iCloud gets every hour back, held, not merged.
        let box = IdentitySandbox("undo-new-phone")
        defer { box.tearDown() }
        let phone = EngineHarness(box, zone: zone)
        try phone.device()
        let outcome = await phone.cloud()
        XCTAssertEqual(outcome, .done)
        XCTAssertTrue(Set(phone.entries.map(\.id.uuidString)).isDisjoint(with: names), "not live on the new phone")
        let held = Set(phone.earlier.groups.flatMap { $0.entries.map(\.id.uuidString) })
        XCTAssertTrue(names.isSubset(of: held), "every hour is in Earlier records on the new phone")
    }

    func testUndoSpouseKeepsAnEditMadeAfterTheAnswer() async throws {
        XCTAssertTrue(Fixture.load("D8", into: sandbox))
        let h = EngineHarness(sandbox, zone: FakeZoneSource())
        try h.device()
        _ = await h.cloud()
        let group = try XCTUnwrap(h.earlier.group(local))
        h.engine.answer(.spouse, group: local)
        let target = try XCTUnwrap(group.entries.first)
        var live = h.entries
        let i = try XCTUnwrap(live.firstIndex { $0.id == target.id })
        live[i].hours += 1.5
        live[i].modifiedAt = Date().addingTimeInterval(60)
        h.live.replaceLive(entries: live, properties: h.properties, categories: h.live.liveCategories)
        h.engine.undoSpouse(group: local)
        let back = try XCTUnwrap(h.earlier.group(local)?.entries.first { $0.id == target.id })
        XCTAssertEqual(back.hours, target.hours + 1.5, "the edit made while it was the spouse's survives Undo")
        XCTAssertEqual(back.participant, target.participant)
    }
}
