import XCTest
import CloudKit
@testable import LandlordHours

// MARK: - Frozen 1.1 TimeEntry
//
// An exact copy of TimeEntry as shipped in 1.1 (fields, synthesized keys and encoding, custom
// decoder). Never edit it: it stands in for a 1.1 device reading data a 2.0 device wrote.
private struct TimeEntryV11: Codable {
    let id: UUID
    var propertyId: UUID
    var participant: Participant
    var category: ActivityCategory
    var hours: Double
    var date: Date
    var notes: String
    var attachments: [TimeAttachment]
    var createdAt: Date
    var modifiedAt: Date
    var importSource: String?
    var importExternalId: String?
    var importCalendarId: String?

    init(id: UUID, propertyId: UUID, participant: Participant, category: ActivityCategory, hours: Double,
         date: Date, notes: String, importSource: String?, importExternalId: String?, importCalendarId: String?,
         createdAt: Date, modifiedAt: Date) {
        self.id = id
        self.propertyId = propertyId
        self.participant = participant
        self.category = category
        self.hours = hours
        self.date = date
        self.notes = notes
        self.attachments = []
        self.importSource = importSource
        self.importExternalId = importExternalId
        self.importCalendarId = importCalendarId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        propertyId = try c.decode(UUID.self, forKey: .propertyId)
        participant = try c.decode(Participant.self, forKey: .participant)
        category = try c.decode(ActivityCategory.self, forKey: .category)
        hours = try c.decode(Double.self, forKey: .hours)
        date = try c.decode(Date.self, forKey: .date)
        notes = try c.decode(String.self, forKey: .notes)
        attachments = try c.decodeIfPresent([TimeAttachment].self, forKey: .attachments) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        importSource = try c.decodeIfPresent(String.self, forKey: .importSource)
        importExternalId = try c.decodeIfPresent(String.self, forKey: .importExternalId)
        importCalendarId = try c.decodeIfPresent(String.self, forKey: .importCalendarId)
    }
}

private func jsonObject(_ data: Data) throws -> NSDictionary {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

private func jsonArray(_ data: Data) throws -> NSArray {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSArray)
}

// MARK: - Migration safety

final class TimeEntryMigrationTests: XCTestCase {
    /// A 1.1 store blob exactly as 1.1 writes it (default JSONEncoder, dates as reference-date
    /// seconds): one manual entry with an attachment, one timer entry, one calendar import.
    static let v11StoreJSON = """
    [
      {"id":"11111111-1111-1111-1111-111111111111","propertyId":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
       "participant":"Self","category":"Repairs & Maintenance","hours":2.5,"date":794000000,
       "notes":"Fixed the sink","attachments":[{"id":"99999999-9999-9999-9999-999999999999",
       "filename":"receipt.jpg","mimeType":"image/jpeg","createdAt":794000100,"modifiedAt":794000100}],
       "createdAt":794000200,"modifiedAt":794000300},
      {"id":"22222222-2222-2222-2222-222222222222","propertyId":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
       "participant":"Spouse","category":"Property Management","hours":1,"date":794100000,
       "notes":"","attachments":[],"createdAt":794100000,"modifiedAt":794100000,"importSource":"timer"},
      {"id":"33333333-3333-3333-3333-333333333333","propertyId":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
       "participant":"Self","category":"Leasing & Tenant Relations","hours":1.5,"date":794200000,
       "notes":"Showing - Oak St","attachments":[],"createdAt":794200000,"modifiedAt":794200000,
       "importSource":"calendar","importExternalId":"EVT-1","importCalendarId":"CAL-1"}
    ]
    """

    func testV11StoreRoundTripsThrough20WithNoFieldLoss() throws {
        let original = Data(Self.v11StoreJSON.utf8)
        let entries = try JSONDecoder().decode([TimeEntry].self, from: original)
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.allSatisfy { $0.detectedAt == nil && $0.confirmedAt == nil && $0.sourceDetail == nil && $0.sourceKey == nil })
        let reencoded = try JSONEncoder().encode(entries)
        XCTAssertEqual(try jsonArray(reencoded), try jsonArray(original),
                       "A 1.1 store saved by 2.0 must be byte-for-byte equivalent JSON: no field lost, none added")
    }

    func testV11EncodedEntriesRoundTripThrough20() throws {
        let v11 = TimeEntryV11(
            id: UUID(), propertyId: UUID(), participant: .spouse, category: .bookkeeping, hours: 0.75,
            date: Date(timeIntervalSinceReferenceDate: 800_000_000), notes: "Ledger",
            importSource: "voice", importExternalId: nil, importCalendarId: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_001),
            modifiedAt: Date(timeIntervalSinceReferenceDate: 800_000_002)
        )
        let v11Data = try JSONEncoder().encode([v11])
        let current = try JSONDecoder().decode([TimeEntry].self, from: v11Data)
        XCTAssertEqual(try jsonArray(try JSONEncoder().encode(current)), try jsonArray(v11Data))
    }

    func testFrozenV11Decodes20JSON() throws {
        var entry = TimeEntry(
            id: UUID(), propertyId: UUID(), participant: .selfParticipant, category: .leasing, hours: 2,
            date: Date(timeIntervalSinceReferenceDate: 801_000_000), notes: "",
            importSource: "calendar", importExternalId: "EXT", importCalendarId: "CAL",
            detectedAt: Date(timeIntervalSinceReferenceDate: 801_000_100),
            confirmedAt: Date(timeIntervalSinceReferenceDate: 801_000_200),
            sourceDetail: "backfill", sourceKey: "cal:EXT:2026-05-20T15:00:00Z"
        )
        entry.modifiedAt = Date(timeIntervalSinceReferenceDate: 801_000_300)
        let data = try JSONEncoder().encode([entry])
        let json = try jsonArray(data)
        let dict = try XCTUnwrap(json.firstObject as? NSDictionary)
        XCTAssertNotNil(dict["confirmedAt"], "2.0 writes the new fields")

        let old = try JSONDecoder().decode([TimeEntryV11].self, from: data)
        XCTAssertEqual(old.count, 1)
        XCTAssertEqual(old[0].id, entry.id)
        XCTAssertEqual(old[0].hours, 2)
        XCTAssertEqual(old[0].importSource, "calendar", "1.1 still reads a confirmed calendar entry as a calendar import")
        XCTAssertEqual(old[0].modifiedAt, entry.modifiedAt)
    }

    func testManual20EntryEncodesNoNewKeys() throws {
        let entry = TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: 1)
        let dict = try jsonObject(try JSONEncoder().encode(entry))
        for key in ["detectedAt", "confirmedAt", "sourceDetail", "sourceKey"] {
            XCTAssertNil(dict[key], "\(key) must be omitted when nil")
        }
    }
}

// MARK: - EntrySource

final class EntrySourceTests: XCTestCase {
    func testStoredValuesAndUnknownMapToOther() {
        XCTAssertEqual(EntrySource(importSource: nil), .manual)
        XCTAssertEqual(EntrySource(importSource: "calendar"), .calendar)
        XCTAssertEqual(EntrySource(importSource: "receipt"), .receipt)
        XCTAssertEqual(EntrySource(importSource: "location"), .location)
        XCTAssertEqual(EntrySource(importSource: "shortcut"), .shortcut)
        XCTAssertEqual(EntrySource(importSource: "gmail"), .gmail)
        XCTAssertEqual(EntrySource(importSource: "hologram-3000"), .other, "Unknown future values are Other, never Manual")
        XCTAssertEqual(EntrySource(importSource: "manual"), .other, "Manual is stored as nil; a literal is unknown data")
        XCTAssertEqual(EntrySource.other.displayName, "Other")
        XCTAssertNil(EntrySource.manual.storedValue)
        XCTAssertEqual(EntrySource.calendar.storedValue, "calendar")
    }

    func testConfirmedCalendarEntryKeepsCalendarImportLabel() {
        let confirmed = TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .leasing, hours: 1,
                                  importSource: Suggestion.Kind.calendar.entrySource.storedValue,
                                  confirmedAt: Date())
        XCTAssertEqual(confirmed.importSource, "calendar")
        XCTAssertEqual(confirmed.source.displayName, "Calendar import")
        XCTAssertTrue(confirmed.isConfirmedSuggestion)
        XCTAssertFalse(confirmed.isLegacyCalendarImport)
    }
}

// MARK: - CloudKit mapping

final class CloudKitCaptureMappingTests: XCTestCase {
    private let zone = CKRecordZone.ID(zoneName: "LandlordHoursZone", ownerName: CKCurrentUserDefaultName)

    private func assertNoNils(_ record: CKRecord, file: StaticString = #filePath, line: UInt = #line) {
        for key in record.allKeys() {
            XCTAssertNotNil(record[key], "\(key) written as nil", file: file, line: line)
        }
        for key in record.changedKeys() {
            XCTAssertNotNil(record[key], "\(key) changed to nil", file: file, line: line)
        }
    }

    func testManualEntryWritesNoCaptureFieldsAndNoNils() {
        let entry = TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: 1)
        let record = CloudKitSyncService.record(for: entry, zoneID: zone, appUserId: "local-x")
        assertNoNils(record)
        let keys = Set(record.allKeys())
        for field in CloudKitSyncService.CaptureEntryField.all {
            XCTAssertFalse(keys.contains(field), "\(field) must not be sent for an entry without it")
        }
        XCTAssertFalse(keys.contains("importSource"))
        XCTAssertEqual(record["appUserId"] as? String, "local-x")
    }

    func testCaptureFieldsRoundTrip() throws {
        let detected = Date(timeIntervalSince1970: 1_780_000_000)
        let confirmed = Date(timeIntervalSince1970: 1_780_000_600)
        let entry = TimeEntry(
            id: CaptureIdentity.entryId(forSourceKey: "cal:E:2026-05-28T10:00:00Z"),
            propertyId: UUID(), participant: .selfParticipant, category: .leasing, hours: 1.5,
            importSource: "calendar", importExternalId: "E", importCalendarId: "C",
            detectedAt: detected, confirmedAt: confirmed, sourceDetail: "backfill",
            sourceKey: "cal:E:2026-05-28T10:00:00Z"
        )
        let record = CloudKitSyncService.record(for: entry, zoneID: zone, appUserId: nil)
        assertNoNils(record)
        XCTAssertNil(record["appUserId"])
        XCTAssertEqual(record["confirmedAt"] as? Date, confirmed)
        let back = try XCTUnwrap(CloudKitSyncService.entry(from: record))
        XCTAssertEqual(back.id, entry.id)
        XCTAssertEqual(back.detectedAt, detected)
        XCTAssertEqual(back.confirmedAt, confirmed)
        XCTAssertEqual(back.sourceDetail, "backfill")
        XCTAssertEqual(back.sourceKey, entry.sourceKey)
        XCTAssertEqual(back.importSource, "calendar")
    }

    func testRecordWrittenBy11DecodesWithNilCaptureFields() throws {
        let record = CKRecord(recordType: "TimeEntry", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        record["propertyId"] = UUID().uuidString
        record["participant"] = "Self"
        record["category"] = ActivityCategory.repairs.rawValue
        record["hours"] = 2.0
        record["date"] = Date()
        record["notes"] = "n"
        record["createdAt"] = Date()
        record["modifiedAt"] = Date()
        let entry = try XCTUnwrap(CloudKitSyncService.entry(from: record))
        XCTAssertNil(entry.confirmedAt)
        XCTAssertNil(entry.sourceKey)
        XCTAssertEqual(entry.source, .manual)
    }

    func testSameSourceKeyGivesSameRecordNameOnTwoDevices() {
        let key = SuggestionKey.calendar(externalId: "EXT-9", occurrence: Date(timeIntervalSince1970: 1_780_000_000))
        let a = TimeEntry(id: CaptureIdentity.entryId(forSourceKey: key), propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: 1)
        let b = TimeEntry(id: CaptureIdentity.entryId(forSourceKey: key), propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: 2)
        XCTAssertEqual(CloudKitSyncService.record(for: a, zoneID: zone, appUserId: "u").recordID,
                       CloudKitSyncService.record(for: b, zoneID: zone, appUserId: "u").recordID)
    }
}

// MARK: - Identity and keys

final class CaptureIdentityTests: XCTestCase {
    func testEntryIdIsRFC4122Version5AndStable() {
        // Cross-checked with Python: uuid.uuid5(UUID('6C1B6E2A-...'), 'cal:ABC-123:2026-03-02T15:00:00Z')
        let id = CaptureIdentity.entryId(forSourceKey: "cal:ABC-123:2026-03-02T15:00:00Z")
        XCTAssertEqual(id.uuidString, "85A08703-3E8B-5E78-928A-2B9114DB91D8")
        XCTAssertEqual(CaptureIdentity.entryId(forSourceKey: "cal:ABC-123:2026-03-02T15:00:00Z"), id)
        XCTAssertNotEqual(CaptureIdentity.entryId(forSourceKey: "cal:ABC-123:2026-03-09T15:00:00Z"), id,
                          "Each occurrence of a recurring event is its own record")
    }

    func testKeysAreStableAndUTC() {
        let date = Date(timeIntervalSince1970: 1_772_463_600) // 2026-03-02T15:00:00Z
        XCTAssertEqual(SuggestionKey.calendar(externalId: "ABC-123", occurrence: date), "cal:ABC-123:2026-03-02T15:00:00Z")
        let pid = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        XCTAssertEqual(SuggestionKey.geo(propertyId: pid, arrival: date), "geo:AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA:2026-03-02T15:00:00Z")
        XCTAssertEqual(SuggestionKey.receipt(data: Data("abc".utf8)),
                       "rcpt:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testReceiptsNeverGuessHours() {
        let s = Suggestion(sourceKey: "rcpt:x", kind: .receipt, detectedAt: Date(), start: Date(), title: "Home Depot",
                           proposedPropertyId: UUID(), proposedHours: 3, hoursBasis: .scheduled)
        XCTAssertNil(s.proposedHours)
        XCTAssertEqual(s.hoursBasis, .none)
        XCTAssertFalse(s.isPreselectable)
    }
}

// MARK: - App destinations

final class AppDestinationTests: XCTestCase {
    func testLegacyRawValuesStillResolve() {
        XCTAssertEqual(AppDestination(rawValue: "home"), .today)
        XCTAssertEqual(AppDestination(rawValue: "reports"), .records)
        XCTAssertEqual(AppDestination(rawValue: "track"), .logTime)
        XCTAssertEqual(AppDestination(rawValue: "properties"), .properties)
        XCTAssertEqual(AppDestination(rawValue: "settings"), .settings)
        for legacy in [LandlordHoursIntentDestination.home, .properties, .track, .reports, .settings] {
            XCTAssertEqual(AppDestination(legacy: legacy).rawValue, legacy.rawValue)
        }
    }

    func testFourTabs() {
        XCTAssertEqual(AppTab.allCases, [.today, .inbox, .records, .properties])
        XCTAssertEqual(AppDestination.settings.tab, .today)
        XCTAssertEqual(AppDestination.confirmSuggestion.tab, .inbox)
        XCTAssertEqual(AppDestination(engagement: .calendarReview), .inbox)
    }
}

// MARK: - App Group drop box and BGTask ids

final class AppGroupDropBoxTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("dropbox-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testOneFilePerItemConsumedOldestFirstAndRetriedOnFailure() throws {
        let box = AppGroupDropBox(directory: dir)
        try box.drop("first", profileId: "p", now: Date(timeIntervalSince1970: 100))
        try box.drop("second", profileId: "p", now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(box.pendingFiles().count, 2)

        var seen: [String] = []
        let consumed = box.consume(String.self) { item in
            seen.append(item.payload)
            return item.payload == "first" // second "fails"
        }
        XCTAssertEqual(seen, ["first", "second"])
        XCTAssertEqual(consumed, 1)
        XCTAssertEqual(box.pendingFiles().count, 1, "A failed item stays for the next consume")
    }

    func testBackgroundTaskIdentifiersAreDeclaredInInfoPlist() throws {
        let declared = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])
        XCTAssertEqual(Set(declared), Set(BackgroundTaskIdentifiers.all))
    }
}

// MARK: - Capture flags

final class CaptureFlagsTests: XCTestCase {
    private final class FakeRemote: CaptureFlagRemoteSource {
        var values: [CaptureFlag: Bool] = [:]
        func value(for flag: CaptureFlag) -> Bool? { values[flag] }
    }

    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "CaptureFlagsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testLiveValueWinsAndIsCached() {
        let remote = FakeRemote()
        remote.values[.autoCapture] = false
        let flags = CaptureFlags(remote: remote, defaults: defaults, currentBuild: 10)
        XCTAssertFalse(flags.isEnabled(.autoCapture), "Kill switch honoured")
        remote.values = [:] // analytics opted out / offline
        XCTAssertFalse(flags.isEnabled(.autoCapture), "Cached kill switch survives losing PostHog")
    }

    func testMinimumBuildGateThenDefault() {
        let remote = FakeRemote()
        let old = CaptureFlags(remote: remote, defaults: defaults, currentBuild: 5, minimumBuilds: [.autoCapture: 10])
        XCTAssertFalse(old.isEnabled(.autoCapture))
        let new = CaptureFlags(remote: remote, defaults: defaults, currentBuild: 10, minimumBuilds: [.autoCapture: 10])
        XCTAssertTrue(new.isEnabled(.autoCapture))
        XCTAssertFalse(new.isEnabled(.gmailReader), "Gmail ships dark by default")
        XCTAssertFalse(new.isEnabled(.locationBeta))
    }

    func testPostHogSourceSilentWhenAnalyticsOff() {
        // Unit tests never configure analytics, so the PostHog source must return nil.
        XCTAssertNil(PostHogCaptureFlagSource().value(for: .autoCapture))
    }
}
