import CloudKit
import XCTest
@testable import LandlordHours

/// The record types and fields this build writes, kept in `scripts/qa/cloudkit_schema_expected.json`
/// so `scripts/qa/check_cloudkit_schema.py` can compare them with the Production schema before a
/// release (diagnosis §7.4: 1.x pushes failed because CustomCategory was missing in Production).
/// The test fails when the code writes a field the manifest doesn't list, so the manifest can't drift.
@MainActor
final class CloudKitSchemaManifestTests: XCTestCase {
    static func manifestFromCode() -> [String: [String: String]] {
        let zone = IdentityZone.zoneID
        var property = RentalProperty(name: "n", address: "a", propertyType: .ltr, aliases: ["x"], isOwnerOccupied: true)
        property.modifiedAt = Date()
        let entry = TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: 1, notes: "n",
                              importSource: "calendar", importExternalId: "e", importCalendarId: "c", detectedAt: Date(),
                              confirmedAt: Date(), sourceDetail: "d", sourceKey: "k", recordDescription: "r")
        let category = CustomCategory(name: "c", iconName: "i", colorHex: "000000", countsForREPS: true)
        let goal = GoalSettingsValues(globalGoalType: "REPS", materialParticipationTarget: 500, propertyGoalsJSON: "[]")
            .record(name: "GoalSettings-household", owner: "household").ckRecord()
        let tax = TaxProfileValues(filingStatus: "Single", spouseTracking: true, taxYear: 2026, groupingElection: false,
                                   nonREWorkHours: 1.5, displayName: "Sam").record(name: "TaxProfile-household", owner: "household").ckRecord()
        let records = [CloudKitSyncService.record(for: property, zoneID: zone, appUserId: "household"),
                       CloudKitSyncService.record(for: entry, zoneID: zone, appUserId: "household"),
                       CloudKitSyncService.record(for: category, zoneID: zone, appUserId: "household"), goal, tax]
        var out: [String: [String: String]] = [:]
        for record in records {
            var fields: [String: String] = [:]
            for key in record.allKeys() {
                switch record[key] {
                case is String: fields[key] = "STRING"
                case is Date: fields[key] = "TIMESTAMP"
                case is [String]: fields[key] = "LIST<STRING>"
                case let n as NSNumber: fields[key] = CFNumberIsFloatType(n) ? "DOUBLE" : "INT64"
                default: fields[key] = "UNKNOWN"
                }
            }
            out[record.recordType] = fields
        }
        return out
    }

    func testTheManifestMatchesWhatTheCodeWrites() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/qa/cloudkit_schema_expected.json")
        let code = Self.manifestFromCode()
        guard let data = try? Data(contentsOf: url) else {
            // Not reachable from a device run; the simulator run checks it.
            throw XCTSkip("manifest not readable from this destination: \(url.path)")
        }
        let file = try JSONDecoder().decode([String: [String: String]].self, from: data)
        XCTAssertEqual(file, code, "update scripts/qa/cloudkit_schema_expected.json and deploy the new fields to Production first")
    }
}
