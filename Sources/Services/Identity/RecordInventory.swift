import Foundation

// MARK: - S1 · inventory of every legacy group on the device
//
// A group is the records sharing one legacy owner id: `email-<address>` (1.0.6), `local-<UUID>`
// (2.0 "Get started"), an Apple user id (2.0 Sign in with Apple), or `legacy-unscoped` (keys
// written before per-user scoping, D9). The inventory is key-driven (§2.2.1): every
// `u.<id>.<suffix>` key is assigned to its id, so an unknown key survives the move to `v2.`.

/// How 1.x / 2.0 stored who was signed in. Read-only in 2.2 (Sign in with Apple is removed).
enum LoginType: String, Codable {
    case apple
    case email
    case local
}

enum LegacyGroupKind: String, Codable {
    case email, local, apple, unscoped

    static func of(_ id: String) -> LegacyGroupKind {
        if id == LegacyInventory.unscopedGroupId { return .unscoped }
        if id.hasPrefix(ProfileKeys.emailProfilePrefix) { return .email }
        if id.hasPrefix(ProfileKeys.localProfilePrefix) { return .local }
        return .apple
    }
}

/// One legacy group as S1 found it on this device.
struct LegacyGroup: Equatable {
    var id: String
    var kind: LegacyGroupKind { LegacyGroupKind.of(id) }
    /// Every key that belongs to the group, by suffix (`LandlordHours.entries`, `isProUser`, …).
    var values: [String: Any]
    var entries: [TimeEntry]
    var properties: [RentalProperty]
    var categories: [CustomCategory]
    /// A blob was present but could not be decoded: the group is never treated as empty.
    var unreadableSuffixes: [String]
    /// `Sync/<id>/pushed-fingerprints.json`, if this group ever pushed (D10).
    var tracker: SyncChangeTracker.Contents?
    /// Was the active id at launch (`resolveUserId`).
    var wasActive: Bool

    var isEmpty: Bool { entries.isEmpty && properties.isEmpty && unreadableSuffixes.isEmpty }
    var totalHours: Double { entries.reduce(0) { $0 + $1.hours } }
    var lastEntryDate: Date? { entries.map(\.date).max() }
    var completedOnboarding: Bool { (values["hasCompletedOnboarding"] as? Bool) ?? false }
    var isPro: Bool { (values["isProUser"] as? Bool) == true || (values["hasPurchasedPro"] as? Bool) == true }

    static func == (lhs: LegacyGroup, rhs: LegacyGroup) -> Bool {
        lhs.id == rhs.id && lhs.entries.map(\.id) == rhs.entries.map(\.id)
            && lhs.properties.map(\.id) == rhs.properties.map(\.id) && lhs.unreadableSuffixes == rhs.unreadableSuffixes
    }
}

struct LegacyInventory {
    static let unscopedGroupId = "legacy-unscoped"
    static let entriesSuffix = "LandlordHours.entries"
    static let propertiesSuffix = "LandlordHours.properties"
    static let categoriesSuffix = "customCategories"

    /// Suffixes that prove an id is a profile even when nothing else names it.
    static let anchorSuffixes = [entriesSuffix, propertiesSuffix, "hasCompletedOnboarding", "legacyDataMigrated",
                                 "isProUser", "hasPurchasedPro", "globalGoalType", categoriesSuffix,
                                 "cloudkit.migrationDone", "LandlordHours.timer", "profile.name"]

    /// Base keys 1.0.x wrote before per-user scoping (D9). Mirrors `AppViewModel.unscopedLegacyKeys`.
    static let unscopedBaseKeys = [
        "LandlordHours.properties", "LandlordHours.entries", "LandlordHours.timer", "LandlordHours.celebratedMilestones",
        "hasCompletedOnboarding", "isProUser", "hasPurchasedPro", "trialStartDate", "globalGoalType",
        "materialParticipationTarget", "propertyGoals", "iCloudBackupEnabled", "profileImageData",
        "profile.name", "profile.email", "profile.userEdited", "hasCompletedGuidedOnboarding", "hasSkippedGuidedOnboarding",
        "LandlordHours.taxProfile.filingStatus", "LandlordHours.taxProfile.spouseTracking", "LandlordHours.taxProfile.taxYear",
        "LandlordHours.taxProfile.groupingElection", "LandlordHours.taxProfile.nonREWorkHours", "customCategories"
    ]

    var groups: [LegacyGroup]
    /// The id `resolveUserId` named at launch, if any.
    var activeId: String?
    /// `u.*` keys that matched no id (kept in the backup only).
    var orphanKeys: [String]

    var nonEmpty: [LegacyGroup] { groups.filter { !$0.isEmpty } }

    /// Primary (v3 §2): most entries → latest entry → most properties → the active id. An empty
    /// group is never primary.
    var primary: LegacyGroup? { Self.primary(of: groups, activeId: activeId) }

    static func primary(of groups: [LegacyGroup], activeId: String?) -> LegacyGroup? {
        groups.filter { !$0.isEmpty }.sorted { a, b in
            if a.entries.count != b.entries.count { return a.entries.count > b.entries.count }
            let la = a.lastEntryDate ?? .distantPast, lb = b.lastEntryDate ?? .distantPast
            if la != lb { return la > lb }
            if a.properties.count != b.properties.count { return a.properties.count > b.properties.count }
            if (a.id == activeId) != (b.id == activeId) { return a.id == activeId }
            return a.id < b.id
        }.first
    }

    /// Ids DEBUG builds use for mock scenarios (D11): never offered, never migrated.
    static func isIgnoredId(_ id: String) -> Bool { id.isEmpty || id.hasPrefix("debug-") }

    /// Reads every legacy group. Pure over `defaults` and the `Sync/` folder under `root`.
    static func scan(defaults: UserDefaults, root: URL) -> LegacyInventory {
        let all = defaults.dictionaryRepresentation()
        let activeId = ProfileKeys.resolveUserId(defaults)

        // 1. Candidate ids: auth keys plus any id carrying an anchor suffix.
        var ids = Set<String>()
        for key in [ProfileKeys.appleUserId, ProfileKeys.localProfileId, ProfileKeys.emailUserId, ProfileKeys.previousProfileId] {
            if let id = defaults.string(forKey: key), !id.isEmpty { ids.insert(id) }
        }
        for key in all.keys where key.hasPrefix("u.") {
            for suffix in anchorSuffixes where key.hasSuffix("." + suffix) {
                let start = key.index(key.startIndex, offsetBy: 2)
                let end = key.index(key.endIndex, offsetBy: -(suffix.count + 1))
                if start < end { ids.insert(String(key[start..<end])) }
            }
        }
        ids = ids.filter { !isIgnoredId($0) }

        // 2. Assign every u.* key to the longest id it starts with (ids may contain dots).
        let ordered = ids.sorted { $0.count > $1.count }
        var valuesById: [String: [String: Any]] = [:]
        var orphans: [String] = []
        for (key, value) in all where key.hasPrefix("u.") {
            guard let id = ordered.first(where: { key.hasPrefix("u.\($0).") }) else {
                let rest = key.dropFirst(2)
                if !rest.hasPrefix("debug-") { orphans.append(key) }
                continue
            }
            let suffix = String(key.dropFirst(2 + id.count + 1))
            valuesById[id, default: [:]][suffix] = value
        }

        var groups: [LegacyGroup] = []
        for id in ids {
            groups.append(makeGroup(id: id, values: valuesById[id] ?? [:], active: id == activeId, root: root))
        }
        // 3. D9: unscoped 1.0.x keys form their own group when they hold anything.
        var unscoped: [String: Any] = [:]
        for key in unscopedBaseKeys { if let v = all[key] { unscoped[key] = v } }
        if unscoped[entriesSuffix] != nil || unscoped[propertiesSuffix] != nil {
            groups.append(makeGroup(id: unscopedGroupId, values: unscoped, active: false, root: root))
        }
        groups.sort { $0.id < $1.id }
        return LegacyInventory(groups: groups, activeId: activeId, orphanKeys: orphans.sorted())
    }

    static func makeGroup(id: String, values: [String: Any], active: Bool, root: URL) -> LegacyGroup {
        var unreadable: [String] = []
        func decode<T: Decodable>(_ suffix: String, as type: [T].Type) -> [T] {
            guard let data = values[suffix] as? Data else { return [] }
            do { return try JSONDecoder().decode(type, from: data) } catch { unreadable.append(suffix); return [] }
        }
        let entries = decode(entriesSuffix, as: [TimeEntry].self)
        let properties = decode(propertiesSuffix, as: [RentalProperty].self)
        let categories = decode(categoriesSuffix, as: [CustomCategory].self)
        let trackerURL = SuggestionStore.directory(forUserId: id, baseDirectory: root.appendingPathComponent("Sync", isDirectory: true))
            .appendingPathComponent("pushed-fingerprints.json")
        let tracker = (try? Data(contentsOf: trackerURL)).flatMap { try? JSONDecoder().decode(SyncChangeTracker.Contents.self, from: $0) }
        return LegacyGroup(id: id, values: values, entries: entries, properties: properties, categories: categories,
                           unreadableSuffixes: unreadable.sorted(), tracker: tracker, wasActive: active)
    }
}

// MARK: - groups.json (S3 / S6)

enum GroupStatus: String, Codable {
    /// The group the live set is built from.
    case primary
    /// Empty: dropped silently, never asked about.
    case notNeeded
    /// Waiting for the two-sets answer (held: on device, in iCloud, never merged, never deleted).
    case pending
    case combine
    case spouse
    case aside

    var isLive: Bool { self == .primary || self == .combine || self == .spouse }
}

enum GroupSource: String, Codable { case device, iCloud, both }

struct GroupRecord: Codable, Equatable, Identifiable {
    var id: String
    var status: GroupStatus
    var source: GroupSource
    var entryCount: Int
    var propertyCount: Int
    var hours: Double
    var lastEntryDate: Date?
    /// Only settings records in iCloud (no entries or properties): listed, never asked about.
    var settingsOnly: Bool = false
    /// R2b: same owner id on device and in iCloud, both non-empty, zero UUID overlap.
    var splitFromDevice: Bool = false
    var answeredAt: Date?
    /// Spouse undo window ends (30 days after the answer).
    var undoUntil: Date?
}

struct GroupsFile: Codable, Equatable {
    var version = 1
    var createdAt: Date
    var primaryId: String?
    var groups: [GroupRecord]

    func group(_ id: String) -> GroupRecord? { groups.first { $0.id == id } }
    mutating func upsert(_ record: GroupRecord) {
        if let i = groups.firstIndex(where: { $0.id == record.id }) { groups[i] = record } else { groups.append(record) }
    }
    var pending: [GroupRecord] {
        groups.filter { $0.status == .pending }.sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.id < $1.id }
    }

    static func load(root: URL) -> GroupsFile? {
        guard let data = try? Data(contentsOf: MigrationFiles.groupsURL(root: root)) else { return nil }
        return try? JSONDecoder.identity.decode(GroupsFile.self, from: data)
    }

    func save(root: URL) throws {
        try MigrationFiles.writeDurably(try JSONEncoder.identity.encode(self), to: MigrationFiles.groupsURL(root: root))
    }
}

extension JSONEncoder {
    static var identity: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var identity: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
