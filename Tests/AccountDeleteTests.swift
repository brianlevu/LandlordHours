import CloudKit
import XCTest
@testable import LandlordHours

/// Delete all data (App Review 5.1.1(v)), package K: the whole iCloud zone in one operation, then
/// every `v2.*` and `u.*` key, the archive, the backup and attachments. Never a local wipe while
/// iCloud still holds a copy, unless the person chose "Delete from this iPhone anyway".
@MainActor
final class AccountDeleteTests: CaptureTestCase {

    /// The iCloud account the delete confirms, pinned per test. Without it the engine asks the
    /// real container (no account on a simulator, so "unknown") and reads `v2.icloudUserRecordName`
    /// from whatever the host app last left in `UserDefaults.standard`: an identity UI test's
    /// `-LHFakeZone` launch leaves `_fakeUser` there, and the next run's delete is refused as
    /// "iCloud unreachable". The fake must outlive the test (`zoneSourceOverride` is weak).
    private var account: FakeZoneSource!

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: IdentityKeys.icloudUserRecordName)
        UserDefaults.standard.removeObject(forKey: IdentityKeys.accountChanged)
        account = nil
        try await super.tearDown()
    }

    /// Points the delete at a fake iCloud signed in as `current`, with `stored` as the account
    /// this record set was read from (nil: never learned).
    private func pinICloud(_ viewModel: AppViewModel, current: String?, stored: String?) {
        let zone = FakeZoneSource()
        zone.userName = current
        account = zone
        UserDefaults.standard.removeObject(forKey: IdentityKeys.accountChanged)
        if let stored {
            UserDefaults.standard.set(stored, forKey: IdentityKeys.icloudUserRecordName)
        } else {
            UserDefaults.standard.removeObject(forKey: IdentityKeys.icloudUserRecordName)
        }
        viewModel.identity.attach(source: zone, live: viewModel, sync: viewModel.syncService)
    }

    private func seedLegacyGroup() -> String {
        let legacy = "email-old-\(UUID().uuidString.prefix(6))@example.com"
        UserDefaults.standard.set(Data("[]".utf8), forKey: "u.\(legacy).LandlordHours.entries")
        return legacy
    }

    func testDeleteAllDataDeletesTheZoneThenEveryLocalKey() async throws {
        let (viewModel, property) = makeViewModel()
        viewModel.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs,
                               hours: 2, date: Date(), notes: "Fix sink")
        let legacy = seedLegacyGroup()
        pinICloud(viewModel, current: "_accountA", stored: "_accountA")
        var zoneDeletes = 0
        let service = viewModel.syncService
        service.accountAvailable = true
        service.zoneDeleteOverride = { zoneDeletes += 1 }

        try await viewModel.deleteAllData()

        XCTAssertEqual(zoneDeletes, 1, "One operation deletes the whole zone")
        XCTAssertTrue(viewModel.properties.isEmpty)
        XCTAssertTrue(viewModel.timeEntries.isEmpty)
        XCTAssertNil(UserDefaults.standard.object(forKey: "u.\(legacy).LandlordHours.entries"), "Legacy u.* keys go too")
        let leftovers = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("u.") }
        XCTAssertTrue(leftovers.isEmpty, "No u.* key survives: \(leftovers.prefix(3))")
        XCTAssertEqual(IdentityScope.step(), .deviceMerged, "A new install's record set")
        XCTAssertEqual(UserDefaults.standard.string(forKey: IdentityKeys.storageId), IdentityZone.household)
        XCTAssertFalse(viewModel.activeProfileCompletedOnboarding, "Welcome shows next")
    }

    func testLosingICloudMidDeleteKeepsEveryLocalRecord() async {
        let (viewModel, property) = makeViewModel()
        viewModel.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs,
                               hours: 2, date: Date(), notes: "Fix sink")
        pinICloud(viewModel, current: "_accountA", stored: "_accountA")
        let service = viewModel.syncService
        service.accountAvailable = true
        var zoneDeleteAttempts = 0
        service.zoneDeleteOverride = {
            zoneDeleteAttempts += 1
            throw CloudKitSyncService.AccountDeleteICloudUnreachableError()
        }
        do {
            try await viewModel.deleteAllData()
            XCTFail("The delete must fail, not report success")
        } catch {
            XCTAssertTrue(error is CloudKitSyncService.AccountDeleteICloudUnreachableError, "\(error)")
        }
        XCTAssertEqual(zoneDeleteAttempts, 1, "iCloud was lost during the zone delete, not before it")
        XCTAssertEqual(viewModel.properties.count, 1, "Nothing is wiped locally while iCloud still has a copy")
        XCTAssertEqual(viewModel.timeEntries.count, 1)
        XCTAssertFalse(service.pushesBlocked, "Syncing can resume")
    }

    /// The record set knows whose iCloud it came from, but the phone can't say who is signed in
    /// now (offline, CloudKit busy). The delete refuses before touching the zone or this iPhone.
    func testAnUnconfirmedICloudAccountRefusesTheDelete() async {
        let (viewModel, property) = makeViewModel()
        viewModel.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs,
                               hours: 2, date: Date(), notes: "Fix sink")
        pinICloud(viewModel, current: nil, stored: "_accountA")
        let service = viewModel.syncService
        service.accountAvailable = true
        var zoneDeletes = 0
        service.zoneDeleteOverride = { zoneDeletes += 1 }
        do {
            try await viewModel.deleteAllData()
            XCTFail("An account that can't be confirmed must not be deleted")
        } catch {
            XCTAssertTrue(error is CloudKitSyncService.AccountDeleteICloudUnreachableError, "\(error)")
        }
        XCTAssertEqual(zoneDeletes, 0, "The zone is never touched")
        XCTAssertEqual(viewModel.properties.count, 1, "Nothing is wiped locally")
        XCTAssertEqual(viewModel.timeEntries.count, 1)
    }

    func testICloudOffAsksBeforeDeletingFromThisIPhoneOnly() async throws {
        let (viewModel, _) = makeViewModel()
        let service = viewModel.syncService
        // No iCloud account (the same on a simulator and on a signed-in iPad).
        let off = IdentityFixtures.fakeZone("off")
        service.zoneSourceOverride = off
        service.accountAvailable = false
        var zoneDeletes = 0
        service.zoneDeleteOverride = { zoneDeletes += 1 }
        do {
            try await viewModel.deleteAllData()
            XCTFail("With iCloud off the person is asked first")
        } catch AppViewModel.ProfileDeletionError.iCloudUnavailable {
        }
        XCTAssertEqual(viewModel.properties.count, 1, "Nothing deleted before the answer")
        try await viewModel.deleteAllData(allowLocalOnly: true)
        XCTAssertEqual(zoneDeletes, 0, "iCloud is not touched")
        XCTAssertTrue(viewModel.properties.isEmpty)
        withExtendedLifetime(off) {}
    }

    func testTheUnreachableMessageIsPlain() {
        XCTAssertEqual(CloudKitSyncService.AccountDeleteICloudUnreachableError().localizedDescription,
                       "Couldn’t reach iCloud. Your data hasn’t been deleted. Try again when you’re online.")
    }
}
