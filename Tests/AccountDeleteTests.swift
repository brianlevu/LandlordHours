import CloudKit
import XCTest
@testable import LandlordHours

/// Delete all data (App Review 5.1.1(v)), package K: the whole iCloud zone in one operation, then
/// every `v2.*` and `u.*` key, the archive, the backup and attachments. Never a local wipe while
/// iCloud still holds a copy, unless the person chose "Delete from this iPhone anyway".
@MainActor
final class AccountDeleteTests: CaptureTestCase {

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
        let service = viewModel.syncService
        service.accountAvailable = true
        service.zoneDeleteOverride = { throw CloudKitSyncService.AccountDeleteICloudUnreachableError() }
        do {
            try await viewModel.deleteAllData()
            XCTFail("The delete must fail, not report success")
        } catch {
            XCTAssertTrue(error is CloudKitSyncService.AccountDeleteICloudUnreachableError, "\(error)")
        }
        XCTAssertEqual(viewModel.properties.count, 1, "Nothing is wiped locally while iCloud still has a copy")
        XCTAssertEqual(viewModel.timeEntries.count, 1)
        XCTAssertFalse(service.pushesBlocked, "Syncing can resume")
    }

    func testICloudOffAsksBeforeDeletingFromThisIPhoneOnly() async throws {
        let (viewModel, _) = makeViewModel()
        let service = viewModel.syncService
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
    }

    func testTheUnreachableMessageIsPlain() {
        XCTAssertEqual(CloudKitSyncService.AccountDeleteICloudUnreachableError().localizedDescription,
                       "Couldn’t reach iCloud. Your data hasn’t been deleted. Try again when you’re online.")
    }
}
