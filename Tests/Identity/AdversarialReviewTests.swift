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


    // MARK: F · Put back on a phone whose clock is behind the deleting phone is ignored there


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






}
