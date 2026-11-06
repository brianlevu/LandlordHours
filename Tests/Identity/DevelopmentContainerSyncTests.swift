import CloudKit
import XCTest
@testable import LandlordHours

/// Package K against real CloudKit (§5.2): the live source on a device, Debug-signed, so the
/// Development environment of `iCloud.com.openclaw.landlordhours`. Every test works in its own
/// throwaway zone (`LHZone-ktest-<id>`), never the person's `LandlordHoursZone`, and deletes it.
/// Skipped on the simulator (no CloudKit) and on a device with no iCloud account.
@MainActor
final class DevelopmentContainerSyncTests: XCTestCase {
    private var service: CloudKitSyncService!
    private var zoneID: CKRecordZone.ID!

    override func setUp() async throws {
        try await super.setUp()
        service = CloudKitSyncService()
        guard service.isCloudKitAvailable else { throw XCTSkip("no CloudKit in this build (simulator)") }
        zoneID = CKRecordZone.ID(zoneName: "LHZone-ktest-\(UUID().uuidString.prefix(8))", ownerName: CKCurrentUserDefaultName)
        service.zoneIDOverride = zoneID
        let state = await service.accountState()
        guard state == .available else { throw XCTSkip("iCloud account on this device: \(state)") }
        try await service.createZone()
    }

    override func tearDown() async throws {
        if service?.isCloudKitAvailable == true, zoneID != nil { try? await service.deleteZone() }
        service = nil
        try await super.tearDown()
    }

    private func entries(_ n: Int, owner: String) -> [ZoneRecord] {
        let property = RentalProperty(name: "Dev Oak", address: "1 Dev St", propertyType: .ltr)
        var out = [ZoneRecord(CloudKitSyncService.record(for: property, zoneID: zoneID, appUserId: owner))]
        for i in 0..<n {
            var e = TimeEntry(propertyId: property.id, participant: .selfParticipant, category: .repairs, hours: Double(i + 1), notes: "dev \(i)")
            e.modifiedAt = Date(timeIntervalSince1970: 1_790_000_000 + Double(i))
            out.append(ZoneRecord(CloudKitSyncService.record(for: e, zoneID: zoneID, appUserId: owner)))
        }
        return out
    }

    /// S5 / S8b / S9: per-type push, a complete whole-zone read with raw names, a delta pull
    /// that sees changes and deletes from the S5 token.
    func testPushReadAndDeltaAgainstTheDevelopmentContainer() async throws {
        let records = entries(5, owner: "k-test") + [ZoneRecord(CloudKitSyncService.record(
            for: CustomCategory(name: "Dev", iconName: "hammer", colorHex: "60A5FA", countsForREPS: true), zoneID: zoneID, appUserId: "k-test"))]
        let report = await service.push(records, deletes: [])
        XCTAssertEqual(report.failedTypes, [:], "every type saves (CustomCategory included)")
        XCTAssertEqual(report.savedNames, Set(records.map(\.recordName)))

        let snapshot = await service.readWholeZone()
        XCTAssertFalse(snapshot.incomplete, snapshot.problem ?? "")
        XCTAssertTrue(snapshot.zoneExists)
        XCTAssertTrue(Set(records.map(\.recordName)).isSubset(of: snapshot.presentNames), "names collected before parsing")
        XCTAssertNotNil(snapshot.tokenData)
        let parsed = snapshot.records.filter { $0.recordType == "TimeEntry" }.compactMap(\.entry)
        XCTAssertEqual(parsed.count, 5)
        XCTAssertEqual(Set(parsed.map(\.notes)), Set((0..<5).map { "dev \($0)" }))

        // A change and a delete made "on another device" after S5.
        var changed = records[1]
        changed.fields["notes"] = .string("dev changed")
        changed.fields["modifiedAt"] = .date(Date())
        _ = await service.push([changed], deletes: [records[2].recordName])
        let delta = try await service.deltaPull(from: snapshot.tokenData)
        XCTAssertTrue(delta.changed.contains { $0.recordName == changed.recordName && $0.entry?.notes == "dev changed" })
        XCTAssertEqual(delta.deleted[records[2].recordName], "TimeEntry")
    }

    /// U17 on real CloudKit: the second household save loses `.ifServerRecordUnchanged` and adopts.
    func testHouseholdSaveConflictAdoptsTheFirstWriter() async throws {
        let goal = GoalSettingsValues.defaults.record(name: IdentityZone.goalSettingsName(IdentityZone.household), owner: "device-A")
        let tax = TaxProfileValues(filingStatus: FilingStatus.single.rawValue, spouseTracking: false, taxYear: 2026, groupingElection: false,
                                   nonREWorkHours: 0, displayName: "Dev").record(name: IdentityZone.taxProfileName(IdentityZone.household), owner: "device-A")
        let first = try await service.saveHousehold(goal: goal, tax: tax)
        XCTAssertEqual(first, .saved)
        let second = try await service.saveHousehold(goal: goal.retagged("device-B"), tax: tax.retagged("device-B"))
        XCTAssertEqual(second, .adopted("device-A"), "the loser adopts; nothing is written under its id")
        let snapshot = await service.readWholeZone()
        XCTAssertEqual(snapshot.records.first { $0.recordName == IdentityZone.goalSettingsName(IdentityZone.household) }?.appUserId, "device-A")
        XCTAssertEqual(TaxProfileValues(record: snapshot.records.first { $0.recordName == IdentityZone.taxProfileName(IdentityZone.household) }!).displayName,
                       "Dev", "TaxProfile.displayName exists in the Development schema")
    }

    /// Delete all data: one operation removes the whole zone; a read then reports it gone.
    func testDeleteZoneRemovesEverything() async throws {
        _ = await service.push(entries(2, owner: "k-test"), deletes: [])
        try await service.deleteZone()
        let snapshot = await service.readWholeZone()
        XCTAssertFalse(snapshot.zoneExists, "the zone is gone")
        XCTAssertTrue(snapshot.records.isEmpty)
    }
}
