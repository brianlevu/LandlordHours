import Foundation
import CloudKit

// MARK: - S5 · what the zone holds, read whole and kept raw
//
// `presentNames` is every `recordID.recordName` seen, collected BEFORE parsing, so a record that
// fails to decode is present, not absent (v3 finding 1). Any failure in the per-record, per-zone or
// whole-operation callback marks the read `incomplete`, and R5 is then skipped. The snapshot is
// CloudKit-free (`ZoneRecord`) so the merge rules are pure and testable, and it is written to
// `migration/cloud-snapshot.json` as the S5 record of what iCloud held.

enum ZoneFieldValue: Codable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case date(Date)
    case strings([String])
    case bytes(Data)

    var ckValue: CKRecordValue {
        switch self {
        case .string(let s): return s as CKRecordValue
        case .int(let i): return NSNumber(value: i)
        case .double(let d): return NSNumber(value: d)
        case .date(let d): return d as CKRecordValue
        case .strings(let a): return a as CKRecordValue
        case .bytes(let b): return b as CKRecordValue
        }
    }

    init?(_ value: CKRecordValue?) {
        switch value {
        case let s as String: self = .string(s)
        case let d as Date: self = .date(d)
        case let a as [String]: self = .strings(a)
        case let b as Data: self = .bytes(b)
        case let n as NSNumber:
            // CloudKit hands back Int64 and Double fields as NSNumber; keep which one it was.
            if CFNumberIsFloatType(n) { self = .double(n.doubleValue) } else { self = .int(n.int64Value) }
        default: return nil
        }
    }
}

struct ZoneRecord: Codable, Equatable {
    var recordName: String
    var recordType: String
    var fields: [String: ZoneFieldValue]
    /// Server-set modification date (mirror-vs-household settings precedence only).
    var modificationDate: Date?

    var appUserId: String? {
        if case .string(let s)? = fields["appUserId"] { return s }
        return nil
    }

    init(recordName: String, recordType: String, fields: [String: ZoneFieldValue], modificationDate: Date? = nil) {
        self.recordName = recordName
        self.recordType = recordType
        self.fields = fields
        self.modificationDate = modificationDate
    }

    init(_ record: CKRecord) {
        recordName = record.recordID.recordName
        recordType = record.recordType
        var f: [String: ZoneFieldValue] = [:]
        for key in record.allKeys() { if let v = ZoneFieldValue(record[key]) { f[key] = v } }
        fields = f
        modificationDate = record.modificationDate
    }

    func ckRecord(zoneID: CKRecordZone.ID = IdentityZone.zoneID) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        for (key, value) in fields { record[key] = value.ckValue }
        return record
    }

    func retagged(_ owner: String?) -> ZoneRecord {
        var copy = self
        if let owner { copy.fields["appUserId"] = .string(owner) } else { copy.fields["appUserId"] = nil }
        return copy
    }

    /// The content hash of the §2.3 invariant: the sync fingerprint without the owner tag.
    var contentHash: String { RecordLedger.contentHash(ckRecord()) }

    /// Parsed through the same mappers the sync uses. nil = unparseable (R6b).
    var entry: TimeEntry? { recordType == "TimeEntry" ? CloudKitSyncService.entry(from: ckRecord()) : nil }
    var property: RentalProperty? { recordType == "Property" ? CloudKitSyncService.property(from: ckRecord()) : nil }
    var category: CustomCategory? { recordType == "CustomCategory" ? CloudKitSyncService.customCategory(from: ckRecord()) : nil }
    /// The record's own `modifiedAt` (entries, properties, categories).
    var modifiedAt: Date? { entry?.modifiedAt ?? property?.modifiedAt ?? category?.modifiedAt }
    var isSettings: Bool { recordType == "GoalSettings" || recordType == "TaxProfile" }
    var isUserRecord: Bool { ["TimeEntry", "Property", "CustomCategory"].contains(recordType) }
    var isParseable: Bool {
        switch recordType {
        case "TimeEntry": return entry != nil
        case "Property": return property != nil
        case "CustomCategory": return category != nil
        default: return true
        }
    }
}

/// Fixed names in the record set (data values, never shown on screen).
enum IdentityName: String {
    /// The unified id of a fresh set, and the suffix of the settings pair's record names.
    case household
}

/// Application Support folders the record set uses.
enum IdentityFolder: String, CaseIterable {
    case migration
    case archive
    case sync = "Sync"
    case capture = "Capture"
    case attachments = "Attachments"
}

enum IdentityZone {
    static let zoneName = "LandlordHoursZone"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    static let household = IdentityName.household.rawValue
    static let asidePrefix = "aside-"
    static func goalSettingsName(_ owner: String) -> String { "GoalSettings-\(owner)" }
    static func taxProfileName(_ owner: String) -> String { "TaxProfile-\(owner)" }
}

struct ZoneSnapshot: Codable, Equatable {
    var version = 1
    var readAt: Date
    /// Every record name the read saw, before any parsing.
    var presentNames: Set<String>
    var records: [ZoneRecord]
    var incomplete: Bool
    /// False when the zone does not exist (deleted, or never created).
    var zoneExists: Bool
    /// The server change token at the end of the read (archived `CKServerChangeToken`).
    var tokenData: Data?
    var userRecordName: String?
    /// Plain words for the status row when the read failed or was incomplete.
    var problem: String?

    var unparsed: [ZoneRecord] { records.filter { $0.isUserRecord && !$0.isParseable } }

    func records(owner: String?) -> [ZoneRecord] { records.filter { $0.appUserId == owner } }

    /// Owner ids of user records (entries, properties, categories) and settings-only owners.
    var owners: Set<String?> { Set(records.map(\.appUserId)) }

    static func empty(zoneExists: Bool, now: Date = Date()) -> ZoneSnapshot {
        ZoneSnapshot(readAt: now, presentNames: [], records: [], incomplete: false, zoneExists: zoneExists)
    }

    static func url(root: URL) -> URL { MigrationFiles.migrationDirectory(root: root).appendingPathComponent("cloud-snapshot.json") }
    func save(root: URL) throws { try MigrationFiles.writeDurably(JSONEncoder().encode(self), to: Self.url(root: root)) }
    static func load(root: URL) -> ZoneSnapshot? {
        (try? Data(contentsOf: url(root: root))).flatMap { try? JSONDecoder().decode(ZoneSnapshot.self, from: $0) }
    }
}

/// Changes since a token (S8b, steady-state pull).
struct ZoneDelta: Equatable {
    var changed: [ZoneRecord]
    /// Deleted record names with their record type.
    var deleted: [String: String]
    var tokenData: Data?
    var incomplete: Bool
}

enum ICloudAccountState: String, Codable, Equatable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    /// This build has no CloudKit (simulator without a fake zone, missing entitlement).
    case unsupported
}

enum HouseholdSaveResult: Equatable {
    case saved
    /// Another device wrote the household pair first: adopt its `appUserId` (S8 race).
    case adopted(String)
}

struct ZonePushReport: Equatable {
    var savedNames: Set<String> = []
    /// recordType → CKError code (raw) for types whose save failed; their records stay pending.
    var failedTypes: [String: Int] = [:]
    var deletedNames: Set<String> = []
    var quotaExceeded = false
    var zoneGone = false
    /// Nothing was pushed: the live set waits for an answer (`IdentityKeys.householdHeldFor`).
    var held = false
}

enum ZoneSourceError: Error, Equatable {
    case tokenExpired
    case zoneGone
    case unavailable(String)
}

/// Everything the cloud phase needs from iCloud. Live: `CloudKitSyncService`. Tests and DEBUG
/// launches (`-LHFakeZone`): `FakeZoneSource`.
@MainActor
protocol IdentityZoneSource: AnyObject {
    func accountState() async -> ICloudAccountState
    func userRecordName() async -> String?
    func readWholeZone() async -> ZoneSnapshot
    func deltaPull(from token: Data?) async throws -> ZoneDelta
    /// Creates the zone when this device never saw it (a fresh install, a phone after Delete all
    /// data). Throws `ZoneSourceError.zoneGone` when a zone it knew is gone: never recreated on
    /// its own (P31). No-op when the zone exists.
    func ensureZone() async throws
    /// Saves the household pair with `.ifServerRecordUnchanged`.
    func saveHousehold(goal: ZoneRecord, tax: ZoneRecord) async throws -> HouseholdSaveResult
    /// Saves per record type (one failing type never blocks the others) and deletes.
    func push(_ records: [ZoneRecord], deletes: [String]) async -> ZonePushReport
    /// Delete all data: the whole zone, one operation.
    func deleteZone() async throws
}
