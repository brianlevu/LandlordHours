import XCTest
import CloudKit
@testable import LandlordHours

// Package A acceptance 11: the free-rental pick syncs through iCloud. Later `chosenAt` wins on
// iPhone and iPad (the month clock follows it), a defaulted pick never beats a picked one, the
// local pick holds offline, and a write that races another device merges instead of overwriting.

private final class FakeCloud: FreeRentalCloudStore {
    var record: FreeRentalSelection?
    var offline = false
    /// A write from another device lands between our fetch and our save, once.
    var racingWrite: FreeRentalSelection?
    var saves = 0
    private var fetchedVersion: FreeRentalSelection??

    func fetch() async throws -> FreeRentalSelection? {
        if offline { throw FreeRentalCloudError.unavailable }
        fetchedVersion = .some(record)
        return record
    }

    func save(_ selection: FreeRentalSelection) async throws {
        if offline { throw FreeRentalCloudError.unavailable }
        if let racing = racingWrite {
            racingWrite = nil
            record = racing
        }
        guard case .some(let seen) = fetchedVersion, seen == record else {
            throw FreeRentalCloudError.conflict(record)
        }
        record = selection
        saves += 1
    }
}

private final class SlowCloud: FreeRentalCloudStore {
    var record: FreeRentalSelection?
    var duringSave: () -> Void = {}
    func fetch() async throws -> FreeRentalSelection? { record }
    func save(_ selection: FreeRentalSelection) async throws { duringSave(); record = selection }
}

private final class FakeLocal: FreeRentalLocalStore {
    var selection: FreeRentalSelection?
    var isDirty = false
    func adopt(_ selection: FreeRentalSelection) { self.selection = selection }
}

@MainActor
final class FreeRentalSyncTests: XCTestCase {
    private let pine = UUID(), oak = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private func picked(_ id: UUID, _ days: Double) -> FreeRentalSelection {
        FreeRentalSelection(rentalID: id, chosenAt: t0.addingTimeInterval(days * 86_400), source: .picked)
    }
    private func defaulted(_ id: UUID, _ days: Double) -> FreeRentalSelection {
        FreeRentalSelection(rentalID: id, chosenAt: t0.addingTimeInterval(days * 86_400), source: .defaulted)
    }

    // MARK: Rules

    func testTheLaterPickWins() {
        XCTAssertEqual(FreeRentalSync.merge(local: picked(pine, 0), remote: picked(oak, 3)), picked(oak, 3))
        XCTAssertEqual(FreeRentalSync.merge(local: picked(pine, 5), remote: picked(oak, 3)), picked(pine, 5))
        XCTAssertEqual(FreeRentalSync.merge(local: defaulted(pine, 0), remote: defaulted(oak, 1)), defaulted(oak, 1))
    }

    func testADefaultedPickNeverOverwritesAPickedOne() {
        XCTAssertEqual(FreeRentalSync.merge(local: defaulted(oak, 30), remote: picked(pine, 0)), picked(pine, 0))
        XCTAssertEqual(FreeRentalSync.merge(local: picked(pine, 0), remote: defaulted(oak, 30)), picked(pine, 0))
    }

    func testNothingOnOneSideTakesTheOther() {
        XCTAssertEqual(FreeRentalSync.merge(local: nil, remote: picked(oak, 1)), picked(oak, 1))
        XCTAssertEqual(FreeRentalSync.merge(local: picked(pine, 1), remote: nil), picked(pine, 1))
        XCTAssertNil(FreeRentalSync.merge(local: nil, remote: nil))
    }

    func testAPickWhoseRentalIsGoneNeverWins() {
        // The iPad's pick was deleted here; this device's newer default at a real rental stays.
        XCTAssertEqual(FreeRentalSync.merge(local: defaulted(oak, 5), remote: picked(pine, 9), known: [oak]), defaulted(oak, 5))
        XCTAssertEqual(FreeRentalSync.merge(local: picked(pine, 1), remote: picked(oak, 0), known: [pine, oak]), picked(pine, 1),
                       "with both rentals known, the usual rules")
    }

    func testAPickMadeDuringTheSaveStaysDirty() async {
        let cloud = SlowCloud()
        let phone = FakeLocal(); phone.selection = picked(pine, 6)
        let sync = FreeRentalSync(local: phone, cloud: cloud)
        cloud.duringSave = { phone.selection = self.picked(self.oak, 7); phone.isDirty = true }
        sync.localPickChanged()
        await sync.syncNow()
        XCTAssertTrue(phone.isDirty, "the newer pick is still to send")
    }

    func testATieLandsTheSameOnBothDevices() {
        let a = picked(pine, 2), b = picked(oak, 2)
        XCTAssertEqual(FreeRentalSync.merge(local: a, remote: b), FreeRentalSync.merge(local: b, remote: a))
    }

    func testTheMonthClockFollowsTheWinner() {
        let winner = FreeRentalSync.merge(local: picked(pine, 0), remote: picked(oak, 10))
        let calendar = Calendar(identifier: .gregorian)
        XCTAssertEqual(FreeRentalPolicy.nextSwitchDate(selection: winner, calendar: calendar),
                       calendar.date(byAdding: .month, value: 1, to: t0.addingTimeInterval(10 * 86_400)))
    }

    // MARK: Sync against a fake cloud

    func testIPadAdoptsTheIPhonesNewerPick() async {
        let cloud = FakeCloud(); cloud.record = picked(oak, 4)
        let ipad = FakeLocal(); ipad.selection = picked(pine, 1)
        let sync = FreeRentalSync(local: ipad, cloud: cloud)
        await sync.syncNow()
        XCTAssertEqual(ipad.selection, picked(oak, 4))
        XCTAssertEqual(cloud.saves, 0, "nothing to send: the cloud already holds the winner")
    }

    func testALocalPickReachesTheCloud() async {
        let cloud = FakeCloud(); cloud.record = picked(oak, 1)
        let phone = FakeLocal(); phone.selection = picked(pine, 6)
        let sync = FreeRentalSync(local: phone, cloud: cloud)
        sync.localPickChanged()
        await sync.syncNow()
        XCTAssertEqual(cloud.record, picked(pine, 6))
        XCTAssertFalse(phone.isDirty)
    }

    func testOfflineTheLocalPickHoldsAndIsSentLater() async {
        let cloud = FakeCloud(); cloud.offline = true; cloud.record = picked(oak, 1)
        let phone = FakeLocal(); phone.selection = picked(pine, 6)
        let sync = FreeRentalSync(local: phone, cloud: cloud)
        sync.localPickChanged()
        await sync.syncNow()
        XCTAssertEqual(phone.selection, picked(pine, 6), "the local pick holds")
        XCTAssertTrue(phone.isDirty, "still to send")
        cloud.offline = false
        await sync.syncNow()
        XCTAssertEqual(cloud.record, picked(pine, 6))
        XCTAssertFalse(phone.isDirty)
    }

    func testASwipeDownDefaultNeverReplacesAPickMadeOnTheOtherDevice() async {
        let cloud = FakeCloud(); cloud.record = picked(pine, 0)
        let ipad = FakeLocal(); ipad.selection = defaulted(oak, 20)
        let sync = FreeRentalSync(local: ipad, cloud: cloud)
        sync.localPickChanged()
        await sync.syncNow()
        XCTAssertEqual(ipad.selection, picked(pine, 0))
        XCTAssertEqual(cloud.record, picked(pine, 0))
    }

    func testARacingWriteIsMergedNotOverwritten() async {
        let cloud = FakeCloud(); cloud.record = picked(oak, 1)
        cloud.racingWrite = picked(oak, 9)       // the iPad switched a moment ago
        let phone = FakeLocal(); phone.selection = picked(pine, 5)
        let sync = FreeRentalSync(local: phone, cloud: cloud)
        sync.localPickChanged()
        await sync.syncNow()
        XCTAssertEqual(cloud.record, picked(oak, 9), "the later pick (the iPad's) wins")
        XCTAssertEqual(phone.selection, picked(oak, 9))
    }

    func testWithoutICloudNothingHappensAndThePickStaysDirty() async {
        let phone = FakeLocal(); phone.selection = picked(pine, 1)
        let sync = FreeRentalSync(local: phone, cloud: nil)
        sync.localPickChanged()
        await sync.syncNow()
        XCTAssertTrue(phone.isDirty)
        XCTAssertEqual(phone.selection, picked(pine, 1))
    }

    // MARK: The record

    func testTheRecordRoundTripsAndNamesItsFields() {
        let zone = CKRecordZone.ID(zoneName: "LandlordHoursZone", ownerName: CKCurrentUserDefaultName)
        let record = CloudKitFreeRentalStore.record(for: picked(oak, 3), owner: "household", zoneID: zone)
        XCTAssertEqual(record.recordType, "FreeRental")
        XCTAssertEqual(record.recordID.recordName, "FreeRental-household")
        XCTAssertEqual(Set(record.allKeys()), ["appUserId", "rentalId", "chosenAt", "source"])
        XCTAssertEqual(CloudKitFreeRentalStore.selection(from: record), picked(oak, 3))
    }

    /// The expected schema lists exactly the fields the record writes (check_cloudkit_schema.py
    /// compares that file with Production before a release).
    func testTheSchemaManifestListsTheRecord() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/qa/cloudkit_schema_expected.json")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("manifest not readable from this destination") }
        let file = try JSONDecoder().decode([String: [String: String]].self, from: data)
        XCTAssertEqual(file["FreeRental"], ["appUserId": "STRING", "rentalId": "STRING", "chosenAt": "TIMESTAMP", "source": "STRING"])
    }

    func testTheLocalStoreUsesEntitlementStoresKeyAndEncoding() {
        let defaults = UserDefaults(suiteName: "FreeRentalLocal-\(UUID().uuidString)")!
        let local = EntitlementFreeRentalLocal(defaults: defaults, key: { "p.\($0)" }, changed: {})
        let store = EntitlementStore(defaults: defaults, key: { "p.\($0)" })
        local.adopt(picked(oak, 2))
        XCTAssertEqual(store.freeRentalSelection, picked(oak, 2), "EntitlementStore reads what sync adopted")
        local.isDirty = true
        XCTAssertTrue(local.isDirty)
    }
}
