import CloudKit
import XCTest
@testable import LandlordHours

/// Delete all data against iCloud (App Review 5.1.1(v)): every record type, no crash on ids that
/// are both local and in iCloud, and an honest failure when iCloud can't be reached.
@MainActor
final class AccountDeleteTests: CaptureTestCase {
    private let zone = CKRecordZone.ID(zoneName: "LandlordHoursZone", ownerName: CKCurrentUserDefaultName)
    private func ids(_ names: [String]) -> [CKRecord.ID] { names.map { CKRecord.ID(recordName: $0, zoneID: zone) } }

    private final class Recorder {
        var batches: [[String]] = []
        var fetched: [String] = []
        var deleted: [String] { batches.flatMap { $0 } }
    }

    private func operations(_ recorder: Recorder, available: Bool = true,
                            server: [String: Result<[String], Error>]) -> CloudKitSyncService.AccountDeleteOperations {
        .init(
            accountAvailable: { available },
            fetchRecordIDs: { [zone] type in
                recorder.fetched.append(type)
                switch server[type] ?? .success([]) {
                case .success(let names): return names.map { CKRecord.ID(recordName: $0, zoneID: zone) }
                case .failure(let error): throw error
                }
            },
            deleteBatch: { batch in recorder.batches.append(batch.map(\.recordName)) }
        )
    }

    func testAMissingRecordTypeIsSkippedAndTheOtherTypesAreStillDeleted() async throws {
        let recorder = Recorder()
        let ops = operations(recorder, server: [
            "Property": .success(["p1"]),
            "TimeEntry": .success(["e1", "e2"]),
            "CustomCategory": .failure(CKError(.unknownItem)),   // "Did not find record type"
        ])
        try await CloudKitSyncService.runAccountDelete(localIDs: [], fixedIDs: ids(["GoalSettings-u"]), operations: ops)
        XCTAssertEqual(recorder.fetched, ["Property", "TimeEntry", "CustomCategory"], "Every type is tried")
        XCTAssertEqual(Set(recorder.deleted), ["p1", "e1", "e2", "GoalSettings-u"])
    }

    func testOtherFetchErrorsStillFailTheDelete() async {
        let recorder = Recorder()
        let ops = operations(recorder, server: ["TimeEntry": .failure(CKError(.networkUnavailable))])
        do {
            try await CloudKitSyncService.runAccountDelete(localIDs: ids(["p1"]), fixedIDs: [], operations: ops)
            XCTFail("A network error must not be read as 'nothing to delete'")
        } catch {}
        XCTAssertTrue(recorder.deleted.isEmpty, "Nothing is deleted when the id list is incomplete")
    }

    func testIdsThatAreBothLocalAndInICloudAreDeletedOnceWithoutATrap() async throws {
        // Before the fix, Dictionary(uniqueKeysWithValues:) trapped here (exit 133).
        let recorder = Recorder()
        let shared = (0..<450).map { "e\($0)" }
        let ops = operations(recorder, server: ["TimeEntry": .success(shared + ["cloud-only"]),
                                                "Property": .success(["p1"])])
        try await CloudKitSyncService.runAccountDelete(localIDs: ids(["p1"] + shared + ["e1"]), fixedIDs: ids(["TaxProfile-u"]),
                                                      operations: ops)
        XCTAssertEqual(recorder.deleted.count, Set(recorder.deleted).count, "Each record is deleted once")
        XCTAssertEqual(Set(recorder.deleted), Set(["p1", "cloud-only", "TaxProfile-u"] + shared))
        XCTAssertEqual(recorder.batches.map(\.count), [400, 53], "Batches of at most 400")
    }

    func testUnreachableICloudThrowsBeforeDeletingAnything() async {
        let recorder = Recorder()
        let ops = operations(recorder, available: false, server: ["Property": .success(["p1"])])
        do {
            try await CloudKitSyncService.runAccountDelete(localIDs: ids(["p1"]), fixedIDs: [], operations: ops)
            XCTFail("Expected an explicit failure")
        } catch let error as CloudKitSyncService.AccountDeleteICloudUnreachableError {
            XCTAssertEqual(error.localizedDescription,
                           "Couldn’t reach iCloud. Your data hasn’t been deleted. Try again when you’re online.")
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertTrue(recorder.fetched.isEmpty)
        XCTAssertTrue(recorder.deleted.isEmpty)
    }

    func testLosingICloudMidDeleteKeepsEveryLocalRecord() async {
        let (viewModel, property) = makeViewModel()
        viewModel.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs,
                               hours: 2, date: Date(), notes: "Fix sink")
        let service = viewModel.syncService
        service.accountAvailable = true          // iCloud looked available when the delete started…
        service.accountDeleteOverride = .init(accountAvailable: { false },   // …and was gone by the time it ran
                                              fetchRecordIDs: { _ in [] }, deleteBatch: { _ in })
        do {
            try await viewModel.deleteAccountAndData()
            XCTFail("The delete must fail, not report success")
        } catch {
            XCTAssertTrue(error is CloudKitSyncService.AccountDeleteICloudUnreachableError, "\(error)")
        }
        XCTAssertEqual(viewModel.properties.count, 1, "Nothing is wiped locally while iCloud still has a copy")
        XCTAssertEqual(viewModel.timeEntries.count, 1)
        XCTAssertNotNil(UserScope.userId, "Still signed in to the same profile")
        XCTAssertFalse(service.pushesBlocked, "Syncing can resume")
    }

    func testAFullDeleteThroughTheViewModelRemovesEverything() async throws {
        let (viewModel, property) = makeViewModel()
        viewModel.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs,
                               hours: 2, date: Date(), notes: "Fix sink")
        let entryId = viewModel.timeEntries[0].id.uuidString
        let recorder = Recorder()
        let service = viewModel.syncService
        service.accountAvailable = true
        service.accountDeleteOverride = operations(recorder, server: [
            "Property": .success([property.uuidString]),               // also local: a duplicate
            "TimeEntry": .success([entryId]),
            "CustomCategory": .failure(CKError(.unknownItem)),
        ])
        try await viewModel.deleteAccountAndData()
        XCTAssertEqual(Set(recorder.deleted).isSuperset(of: [property.uuidString, entryId]), true)
        XCTAssertEqual(recorder.deleted.count, Set(recorder.deleted).count)
        XCTAssertTrue(viewModel.properties.isEmpty)
        XCTAssertTrue(viewModel.timeEntries.isEmpty)
    }
}
