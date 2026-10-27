import XCTest
@testable import LandlordHours

/// Adversarial review of d3bb9e2 (fix/k-engine). Each test is a loss or silent-change path the
/// reviewer expects to FAIL on this commit; a pass means the path is closed.
@MainActor
final class AdversarialReviewTests: XCTestCase {
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

    private func legacy(_ id: String, _ box: IdentitySandbox? = nil) -> (entries: [TimeEntry], properties: [RentalProperty]) {
        let d = (box ?? sandbox).defaults
        return (Fixture.entries(d, key: "u.\(id).LandlordHours.entries"), Fixture.properties(d, key: "u.\(id).LandlordHours.properties"))
    }

    // MARK: A · Undo spouse never reaches a second 2.2 phone that already holds the hours live

    func testUndoSpouseLeavesTheHoursLiveAsSpouseOnASecondPhone() async throws {
        XCTAssertTrue(Fixture.load("D8", into: sandbox))
        let zone = FakeZoneSource()
        let a = EngineHarness(sandbox, zone: zone)
        try a.device()
        let doneA = await a.cloud()
        XCTAssertEqual(doneA, .done)
        let group = try XCTUnwrap(a.earlier.group(local))
        let names = Set(group.entries.map(\.id.uuidString))
        a.engine.answer(.spouse, group: local)
        await a.engine.pushLive()

        // Phone B, same iCloud, migrates after the answer: the hours arrive live, as the spouse's.
        let boxB = IdentitySandbox("undo-second-phone")
        defer { boxB.tearDown() }
        let b = EngineHarness(boxB, zone: zone)
        try b.device()
        let doneB = await b.cloud()
        XCTAssertEqual(doneB, .done)
        XCTAssertTrue(names.isSubset(of: Set(b.entries.map(\.id.uuidString))), "B holds them live")

        // A undoes; the retagged copies reach B.
        a.engine.undoSpouse(group: local)
        await a.engine.pushLive()
        let retagged = names.compactMap { zone.records[$0] }
        XCTAssertEqual(retagged.count, names.count)
        XCTAssertFalse(Set(retagged.compactMap(\.appUserId)).contains(a.engine.unifiedId), "A retagged them away from the live set")
        b.engine.applyPull(ZoneDelta(changed: retagged, deleted: [:], tokenData: nil, incomplete: false))

        let stillLive = b.entries.filter { names.contains($0.id.uuidString) }
        XCTAssertTrue(stillLive.isEmpty, "after Undo on A the hours must not stay live on B (\(stillLive.count) still live)")
        XCTAssertTrue(stillLive.allSatisfy { $0.participant == .selfParticipant } || stillLive.isEmpty,
                      "and if they do stay, they are still counted as the spouse's on B")
    }

    // MARK: B · a 2.0.x upgrader that synced before recreates a zone deleted on another phone

    func testAnUpgraderThatSyncedIn20RecreatesAZoneDeletedElsewhere() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let device = legacy(local)
        // This phone pushed in 2.0 (D10: a tracker with baselines exists).
        Fixture.writeTracker(owner: local, entries: device.entries, properties: device.properties, in: sandbox)
        sandbox.defaults.set(true, forKey: "u.\(local).cloudkit.migrationDone")
        sandbox.defaults.set(Data("old-token".utf8), forKey: "u.\(local).cloudkit.zoneChangeToken")
        // Meanwhile the other phone (already on 2.2) ran Delete all data: the zone is gone.
        let zone = FakeZoneSource()
        zone.zoneExists = false
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let outcome = await h.cloud()
        XCTAssertEqual(outcome, .zoneGone, "a phone that synced in 2.0 knew the zone: P31 asks, never recreates")
        XCTAssertFalse(zone.zoneExists, "the deleted zone must stay deleted")
        XCTAssertTrue(zone.records.isEmpty, "nothing re-uploaded (\(zone.records.count) records came back)")
    }

    // MARK: C · S8 adopts the household owner's id even when that owner is a pending group here

    func testAPendingGroupsIdBecomesTheUnifiedIdAndANewPhoneGetsOneSetWithNoQuestion() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))   // this phone: local-…, 10 entries
        let other = "email-other.person@example.com"       // phone A migrated first under its own id
        var records = IdentityFixtures.sampleGroup(owner: other, entries: 20, seed: 0x81)
        records.append(GoalSettingsValues.defaults.record(name: IdentityZone.goalSettingsName(IdentityZone.household), owner: other))
        records.append(TaxProfileValues(filingStatus: FilingStatus.marriedJoint.rawValue, spouseTracking: true, taxYear: 2026,
                                        groupingElection: false, nonREWorkHours: 0, displayName: nil)
            .record(name: IdentityZone.taxProfileName(IdentityZone.household), owner: other))
        let zone = FakeZoneSource(records: records)
        let b = EngineHarness(sandbox, zone: zone)
        try b.device()
        let outcome = await b.cloud()
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(b.earlier.pendingGroups.map(\.id), [other], "the other set is asked about on this phone")
        let mine = Set(legacy(local).entries.map(\.id.uuidString))
        let tags = Set(mine.compactMap { zone.records[$0]?.appUserId })
        XCTAssertFalse(tags.contains(other), "this phone's hours were stored under the set it has not been asked about (unified id \(b.engine.unifiedId))")

        // The person answers "Not mine, keep them aside" here. A new phone on the same iCloud:
        b.engine.answer(.aside, group: other)
        await b.engine.pushLive()   // the app pushes after every answer (AppViewModel.answerTwoSets → schedulePush)
        let boxC = IdentitySandbox("new-phone-c")
        defer { boxC.tearDown() }
        let c = EngineHarness(boxC, zone: zone)
        try c.device()
        let doneC = await c.cloud()
        XCTAssertEqual(doneC, .done)
        XCTAssertFalse(c.earlier.pendingGroups.isEmpty, "the new phone must still be asked; it got \(c.entries.count) entries live with no question")
        XCTAssertEqual(c.entries.count, 10, "only this person's hours live on the new phone")
    }

    // MARK: D · Delete all data after an account change deletes the OTHER account's zone

    func testDeleteAllDataWhileTheAccountChangedDeletesTheOtherAccountsZone() async throws {
        let zoneA = FakeZoneSource()
        zoneA.userName = "_accountA"
        let a = EngineHarness(sandbox, zone: zoneA)
        XCTAssertEqual(try a.device(), .fresh)
        let property = RentalProperty(name: "Elm", address: "1 Elm St", propertyType: .ltr)
        let mine = TimeEntry(propertyId: property.id, participant: .selfParticipant, category: .management, hours: 3, date: Date(), notes: "")
        a.live.replaceLive(entries: [mine], properties: [property], categories: [])
        let doneA = await a.cloud()
        XCTAssertEqual(doneA, .done)

        // The phone is now signed in to someone else's iCloud (their own LandlordHours set lives there).
        let theirs = IdentityFixtures.sampleGroup(owner: IdentityZone.household, entries: 5, seed: 0x91)
        let zoneB = FakeZoneSource(records: theirs)
        zoneB.userName = "_accountB"
        let relaunched = EngineHarness(sandbox, zone: zoneB)
        let outcome = await relaunched.cloud()
        XCTAssertEqual(outcome, .accountChanged, "P13 is showing")

        let keys = [IdentityKeys.zoneGone, IdentityKeys.accountChanged, IdentityKeys.hasSynced, IdentityKeys.icloudUserRecordName,
                    UserScope.key("cloudkit.zoneChangeToken")]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) } }
        UserDefaults.standard.set("_accountA", forKey: IdentityKeys.icloudUserRecordName)
        UserDefaults.standard.set(true, forKey: IdentityKeys.accountChanged)
        let service = CloudKitSyncService()
        service.zoneSourceOverride = zoneB
        service.engine = relaunched.engine
        service.accountAvailable = true
        do {
            try await service.deleteEverythingInICloud()
            XCTFail("Delete all data must refuse to delete a zone that belongs to another iCloud account")
        } catch {
            // expected
        }
        XCTAssertFalse(zoneB.zoneDeleted, "the other account's \(theirs.count) records were deleted from their iCloud")
    }

    // MARK: E · a remote edit drops the live entry's photos

    func testARemoteEditOfAnEntryDropsItsPhotos() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let h = EngineHarness(sandbox, zone: FakeZoneSource())
        try h.device()
        let done = await h.cloud()
        XCTAssertEqual(done, .done)
        var live = h.entries
        live[0].attachments = [TimeAttachment(filename: "receipt.jpg", data: Data([1, 2, 3]), mimeType: "image/jpeg")]
        h.live.replaceLive(entries: live, properties: h.properties, categories: h.live.liveCategories)
        XCTAssertEqual(h.entries[0].attachments.count, 1)
        var theirs = live[0]
        theirs.attachments = []
        theirs.hours += 1
        theirs.modifiedAt = live[0].modifiedAt.addingTimeInterval(60)
        let record = ZoneRecord(CloudKitSyncService.record(for: theirs, zoneID: IdentityZone.zoneID, appUserId: h.engine.unifiedId))
        h.engine.applyPull(ZoneDelta(changed: [record], deleted: [:], tokenData: nil, incomplete: false))
        let after = try XCTUnwrap(h.entries.first { $0.id == live[0].id })
        XCTAssertEqual(after.hours, theirs.hours, "the edit arrives")
        XCTAssertEqual(after.attachments.count, 1, "photos stay on this iPhone (they are never synced, so the pulled copy has none)")
    }

    // MARK: F · Put back on a phone whose clock is behind the deleting phone is ignored there

    func testPutBackFromAPhoneWithASlowerClockIsIgnoredByTheDeletingPhone() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let device = legacy(local)
        let zone = FakeZoneSource(records: Fixture.zoneRecords(entries: device.entries, properties: device.properties, owner: local))
        let a = EngineHarness(sandbox, zone: zone)
        try a.device()
        let doneA = await a.cloud()
        XCTAssertEqual(doneA, .done)
        let boxB = IdentitySandbox("clock-phone-b")
        defer { boxB.tearDown() }
        let b = EngineHarness(boxB, zone: zone)
        try b.device()
        let doneB = await b.cloud()
        XCTAssertEqual(doneB, .done)
        let target = try XCTUnwrap(b.entries.first)
        let name = target.id.uuidString
        // Phone B's clock runs 10 minutes ahead of phone A's.
        let realNow = Date()
        b.engine.now = { realNow.addingTimeInterval(600) }
        a.engine.now = { realNow }
        b.live.replaceLive(entries: b.entries.filter { $0.id != target.id }, properties: b.properties, categories: b.live.liveCategories)
        b.engine.tracker.forget(recordNames: [name])
        b.engine.tracker.addTombstones([name])
        b.engine.noteDeleted([name])
        await b.engine.pushLive()
        a.engine.applyPull(ZoneDelta(changed: [], deleted: [name: "TimeEntry"], tokenData: nil, incomplete: false))
        XCTAssertFalse(a.entries.contains { $0.id == target.id })
        a.engine.putBack([name])
        await a.engine.pushLive()
        let restored = try XCTUnwrap(zone.records[name])
        b.engine.applyPull(ZoneDelta(changed: [restored], deleted: [:], tokenData: nil, incomplete: false))
        XCTAssertTrue(b.entries.contains { $0.id == target.id }, "Put back on A never reaches B when A's clock is behind B's")
    }

    // MARK: - Added by the fix lane (each one red on d3bb9e2 before its fix)

    /// What `AppViewModel.wipeEverythingLocal` leaves behind.
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

    // H3 · a push already in flight when Delete all data runs never recreates the zone
    func testAPushInFlightDuringDeleteAllDataNeverRecreatesTheZone() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let zone = FakeZoneSource()
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        let done = await h.cloud()
        XCTAssertEqual(done, .done)
        var live = h.entries
        live[0].hours += 1
        live[0].modifiedAt = Date().addingTimeInterval(5)
        h.live.replaceLive(entries: live, properties: h.properties, categories: h.live.liveCategories)
        zone.pushDelay = .milliseconds(300)
        let inFlight = Task { await h.engine.pushLive() }
        try await Task.sleep(for: .milliseconds(50))
        try await zone.deleteZone()          // Delete all data: the zone…
        wipeLikeDeleteAll(h)                 // …then everything on the phone
        _ = await inFlight.value
        XCTAssertFalse(zone.zoneExists, "the push that was in flight must not bring the deleted zone back")
        XCTAssertTrue(zone.records.isEmpty, "nothing re-uploaded")
    }

    // Open item · "Get started" during the iCloud check never overwrites the household
    func testOnboardingAnswersAfterTheCloudPhaseLandsNeverOverwriteTheHousehold() async throws {
        let zone = IdentityFixtures.fakeZone("cloudOnly", defaults: sandbox.defaults)
        let householdTax = TaxProfileValues(filingStatus: FilingStatus.marriedJoint.rawValue, spouseTracking: true, taxYear: 2026,
                                            groupingElection: true, nonREWorkHours: 0, displayName: nil)
        zone.records[IdentityZone.taxProfileName(IdentityZone.household)] = householdTax.record(
            name: IdentityZone.taxProfileName(IdentityZone.household), owner: "email-upgrade.tester@example.com")
        zone.records[IdentityZone.goalSettingsName(IdentityZone.household)] = GoalSettingsValues.defaults.record(
            name: IdentityZone.goalSettingsName(IdentityZone.household), owner: "email-upgrade.tester@example.com")
        let h = EngineHarness(sandbox, zone: zone)
        XCTAssertEqual(try h.device(), .fresh)
        // The person taps Get started on an empty phone while iCloud is being checked.
        IdentityKeys.beginOnboarding(liveIsEmpty: true, defaults: sandbox.defaults)
        let done = await h.cloud()                          // the cloud phase lands mid-onboarding
        XCTAssertEqual(done, .done)
        XCTAssertTrue(h.live.taxProfile.spouseTracking)
        // A later onboarding step: "Just me".
        var tax = h.live.taxProfile
        tax.spouseTracking = false
        h.live.applyRemoteSettings(goal: nil, tax: tax)
        IdentityKeys.markSettingsDirty(tax: true, liveIsEmpty: h.entries.isEmpty, defaults: sandbox.defaults)
        await h.engine.pushLive()
        let stored = try XCTUnwrap(zone.records[IdentityZone.taxProfileName(IdentityZone.household)])
        XCTAssertEqual(TaxProfileValues(record: stored).spouseTracking, true, "the household's tax profile is not overwritten on every device")
        h.engine.finishOnboarding()
        XCTAssertTrue(h.live.taxProfile.spouseTracking, "this phone follows the household")
        XCTAssertNotNil(sandbox.defaults.data(forKey: IdentityKeys.discardedOnboardingAnswers), "the answer is kept in Advanced (P29)")
    }

    // M4 · a spouse group's id is never this phone's unified id
    func testASpouseGroupIsNeverTheUnifiedId() async throws {
        XCTAssertTrue(Fixture.load("D8", into: sandbox))
        // The spouse's 2.0.x phone pushed more hours than this phone holds.
        let zone = FakeZoneSource(records: IdentityFixtures.sampleGroup(owner: local, entries: 60, seed: 0xA1))
        zone.account = .noAccount
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        _ = await h.cloud()                                  // iCloud off: no cloud phase yet
        h.engine.answer(.spouse, group: local)               // answered on the device
        zone.account = .available
        let done = await h.cloud()
        XCTAssertEqual(done, .done)
        XCTAssertNotEqual(h.engine.unifiedId, local, "this phone's hours would be tagged as the spouse's and swapped on every other phone")
    }

    // M5 · two tracker instances on one file never lose each other's writes
    func testTwoTrackerInstancesOnOneFileKeepEachOthersWrites() {
        let a = SyncChangeTracker(userId: "household", baseDirectory: sandbox.syncRoot)
        let b = SyncChangeTracker(userId: "household", baseDirectory: sandbox.syncRoot)
        let property = RentalProperty(name: "Elm", address: "1 Elm St", propertyType: .ltr)
        a.recordServerState([CloudKitSyncService.record(for: property, zoneID: IdentityZone.zoneID, appUserId: "household")])
        b.addTombstones(["deleted-entry"])
        let fresh = SyncChangeTracker(userId: "household", baseDirectory: sandbox.syncRoot)
        XCTAssertTrue(fresh.hasBaseline(for: property.id.uuidString), "the other instance's stale copy overwrote the baseline")
        XCTAssertEqual(fresh.pendingDeletes, ["deleted-entry"])
        a.recordServerState([])
        a.forget(recordNames: ["nothing"])
        XCTAssertEqual(SyncChangeTracker(userId: "household", baseDirectory: sandbox.syncRoot).pendingDeletes, ["deleted-entry"],
                       "a stale instance never writes a tombstone away")
    }

    // M3 · an unpushed local edit that a newer remote edit beats is kept in Recently removed
    func testAnUnpushedLocalEditBeatenByANewerRemoteEditIsKept() async throws {
        XCTAssertTrue(Fixture.load("D5", into: sandbox))
        let h = EngineHarness(sandbox, zone: FakeZoneSource())
        try h.device()
        _ = await h.cloud()
        var live = h.entries
        let original = live[0]
        live[0].notes = "local edit, not pushed yet"
        live[0].modifiedAt = original.modifiedAt.addingTimeInterval(30)
        h.live.replaceLive(entries: live, properties: h.properties, categories: h.live.liveCategories)
        var theirs = original
        theirs.hours += 2
        theirs.modifiedAt = original.modifiedAt.addingTimeInterval(60)
        let record = ZoneRecord(CloudKitSyncService.record(for: theirs, zoneID: IdentityZone.zoneID, appUserId: h.engine.unifiedId))
        h.engine.applyPull(ZoneDelta(changed: [record], deleted: [:], tokenData: nil, incomplete: false))
        XCTAssertEqual(h.entries.first { $0.id == original.id }?.hours, theirs.hours, "the newer edit wins")
        XCTAssertTrue(h.earlier.removed.contains { $0.entry?.notes == "local edit, not pushed yet" }, "the losing local edit is kept")
    }

    // Low · an offline group delete still reaches iCloud
    func testADeleteOfAnEarlierGroupMadeOfflineReachesICloudLater() async throws {
        XCTAssertTrue(Fixture.load("D3", into: sandbox))
        let old = "email-old.profile@example.com"
        let zone = FakeZoneSource()
        let h = EngineHarness(sandbox, zone: zone)
        try h.device()
        _ = await h.cloud()
        let names = Set(try XCTUnwrap(h.earlier.group(old)).entries.map(\.id.uuidString))
        XCTAssertTrue(names.isSubset(of: Set(zone.records.keys)), "the aside copies are in iCloud")
        zone.account = .noAccount
        await h.engine.deleteGroup(old)
        zone.account = .available
        await h.engine.pushLive()
        XCTAssertTrue(names.isDisjoint(with: Set(zone.records.keys)), "the delete reaches iCloud once it is back")
    }

    // Low · unified id rule 2 skips an excluded owner to the next candidate
    func testUnifiedIdRule2FallsToTheNextAllowedOwner() {
        let id = MergeRules.unifiedId(householdOwner: nil, zoneEntryCounts: ["email-pending": 20, "email-mine": 5],
                                      devicePrimary: "local-x", excluded: ["email-pending"])
        XCTAssertEqual(id, "email-mine")
    }
}
