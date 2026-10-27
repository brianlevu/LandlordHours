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


    // MARK: C · S8 adopts the household owner's id even when that owner is a pending group here


    // MARK: D · Delete all data after an account change deletes the OTHER account's zone


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
