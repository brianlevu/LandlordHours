import Foundation
import os.log

private let earlierLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "EarlierRecords")

// MARK: - Earlier records: archive groups, Recently removed, undo
//
// The safety net (§1.1). Nothing the merge could not place is ever deleted: a second set of
// records the app is not sure is yours (pending / aside), records removed on another device, and
// records the app inferred were removed all live here, on the device under
// `Application Support/archive/`, until the person acts. Archive groups are also pushed to iCloud
// under `aside-<id>` so they survive the device (R10).

struct ArchivedGroup: Codable, Equatable, Identifiable {
    var id: String
    var status: GroupStatus
    var source: GroupSource
    var entries: [TimeEntry]
    var properties: [RentalProperty]
    var categories: [CustomCategory]
    /// Raw zone records for this group that could not be parsed (kept, never deleted).
    var unparsedRecords: [ZoneRecord] = []
    var createdAt: Date
    /// Records of this group already pushed under `aside-<id>` (device-only ones).
    var pushedAsideNames: Set<String> = []
    /// Only settings records were found in iCloud for this owner.
    var settingsOnly = false

    var hours: Double { entries.reduce(0) { $0 + $1.hours } }
    var lastEntryDate: Date? { entries.map(\.date).max() }
    var isEmpty: Bool { entries.isEmpty && properties.isEmpty && unparsedRecords.isEmpty }

    static func == (lhs: ArchivedGroup, rhs: ArchivedGroup) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.entries.map(\.id) == rhs.entries.map(\.id)
            && lhs.properties.map(\.id) == rhs.properties.map(\.id) && lhs.pushedAsideNames == rhs.pushedAsideNames
    }
}

enum RemovalReason: String, Codable {
    /// A delete the person made on another device (R5b / steady-state pulled delete): 30 days.
    case deletedElsewhere
    /// The app inferred it (R5 synced-then-absent): kept until the person acts.
    case inferredAbsent
    /// The person answered "Remove them" to the bulk question (P28): kept until they act.
    case bulkRemoved
    /// The person deleted it on this device before the update (R3 tombstone): 30 days.
    case deletedHere
    /// An edit made on this iPhone and not yet in iCloud, beaten by a newer edit from another
    /// device (last writer wins): the older version is kept 30 days, with Put back.
    case replacedByNewer

    var isInferred: Bool { self == .inferredAbsent || self == .bulkRemoved }
}

struct RemovedRecord: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var reason: RemovalReason
    var removedAt: Date
    /// nil = kept until the person acts (inferred removals, §2.4).
    var keepUntil: Date?
    var entry: TimeEntry?
    var property: RentalProperty?
    var category: CustomCategory?
    /// The legacy group it came from (for analytics counts and "Put back").
    var groupId: String?

    static func == (lhs: RemovedRecord, rhs: RemovedRecord) -> Bool {
        lhs.name == rhs.name && lhs.reason == rhs.reason && lhs.keepUntil == rhs.keepUntil
    }

    var version: RecordVersion? {
        if let entry { return RecordLedger.version(entry) }
        if let property { return RecordLedger.version(property) }
        if let category { return RecordLedger.version(category) }
        return nil
    }

    var hours: Double { entry?.hours ?? 0 }
}

/// Records held because one pull or read would have removed more than half the live set (R5c,
/// P28). Visible, not pushed, until the person answers.
struct BulkHold: Codable, Equatable {
    var names: Set<String>
    var totalLive: Int
    var heldHours: Double
    var totalHours: Double
    var createdAt: Date
    /// The hold came from pulled deletes (steady state) rather than an absence at S5/S7.
    var fromPulledDeletes: Bool
}

@MainActor
final class EarlierRecordsStore: ObservableObject {
    static let userDeleteRetention: TimeInterval = 30 * 86_400

    let root: URL
    @Published private(set) var groups: [ArchivedGroup] = []
    @Published private(set) var removed: [RemovedRecord] = []
    @Published private(set) var bulkHold: BulkHold?

    init(root: URL = MigrationFiles.defaultRoot) {
        self.root = root
        reload()
    }

    private var directory: URL { MigrationFiles.archiveDirectory(root: root) }
    private var removedURL: URL { directory.appendingPathComponent("recently-removed.json") }
    private var bulkURL: URL { directory.appendingPathComponent("bulk-hold.json") }
    private func groupURL(_ id: String) -> URL {
        SuggestionStore.directory(forUserId: id, baseDirectory: directory).appendingPathExtension("json")
    }

    func reload() {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        groups = items.filter { $0.pathExtension == "json" && $0.lastPathComponent != "recently-removed.json" && $0.lastPathComponent != "bulk-hold.json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? JSONDecoder().decode(ArchivedGroup.self, from: $0) } }
            .sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.id < $1.id }
        removed = (try? Data(contentsOf: removedURL)).flatMap { try? JSONDecoder().decode([RemovedRecord].self, from: $0) } ?? []
        bulkHold = (try? Data(contentsOf: bulkURL)).flatMap { try? JSONDecoder().decode(BulkHold.self, from: $0) }
    }

    // MARK: Groups

    func group(_ id: String) -> ArchivedGroup? { groups.first { $0.id == id } }

    /// Adds or replaces an archive group. Records already in it are kept (union by UUID, newer wins).
    func save(_ group: ArchivedGroup) throws {
        var merged = group
        if let existing = self.group(group.id) {
            merged.entries = MergeRules.union(existing.entries, group.entries)
            merged.properties = MergeRules.union(existing.properties, group.properties)
            merged.categories = MergeRules.union(existing.categories, group.categories)
            merged.pushedAsideNames.formUnion(existing.pushedAsideNames)
            merged.createdAt = min(existing.createdAt, group.createdAt)
            let raw = Dictionary((existing.unparsedRecords + group.unparsedRecords).map { ($0.recordName, $0) }, uniquingKeysWith: { _, b in b })
            merged.unparsedRecords = raw.values.sorted { $0.recordName < $1.recordName }
        }
        try MigrationFiles.writeDurably(JSONEncoder().encode(merged), to: groupURL(merged.id))
        reload()
    }

    func setStatus(_ status: GroupStatus, for id: String) throws {
        guard var group = self.group(id) else { return }
        group.status = status
        try MigrationFiles.writeDurably(JSONEncoder().encode(group), to: groupURL(id))
        reload()
    }

    func markPushedAside(_ names: Set<String>, group id: String) {
        guard var group = self.group(id), !names.isSubset(of: group.pushedAsideNames) else { return }
        group.pushedAsideNames.formUnion(names)
        try? MigrationFiles.writeDurably(JSONEncoder().encode(group), to: groupURL(id))
        reload()
    }

    /// The group was combined into the live set or deleted: its archive copy goes.
    func removeGroup(_ id: String) {
        try? FileManager.default.removeItem(at: groupURL(id))
        reload()
    }

    /// Adds records to an existing group (pull routing R10: a record for an archived owner).
    func route(entries: [TimeEntry] = [], properties: [RentalProperty] = [], categories: [CustomCategory] = [],
               unparsed: [ZoneRecord] = [], to id: String, status: GroupStatus, source: GroupSource, now: Date = Date()) {
        let group = ArchivedGroup(id: id, status: status, source: source, entries: entries, properties: properties,
                                  categories: categories, unparsedRecords: unparsed, createdAt: now)
        do { try save(group) } catch {
            earlierLogger.error("Archive write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The group that holds `name`, if any (R20 membership).
    func groupId(containing name: String) -> String? {
        groups.first { g in
            g.entries.contains { $0.id.uuidString == name } || g.properties.contains { $0.id.uuidString == name }
                || g.categories.contains { $0.id.uuidString == name } || g.unparsedRecords.contains { $0.recordName == name }
        }?.id
    }

    var pendingGroups: [ArchivedGroup] { groups.filter { $0.status == .pending && !$0.isEmpty } }

    // MARK: Recently removed

    func remove(_ records: [RemovedRecord]) {
        guard !records.isEmpty else { return }
        var byName = Dictionary(removed.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for record in records { byName[record.name] = record }
        writeRemoved(RemovedRecord.newestFirst(Array(byName.values)))
    }

    /// Takes records out of Recently removed (Put back, or the person acted).
    @discardableResult
    func takeRemoved(_ names: Set<String>) -> [RemovedRecord] {
        let taken = removed.filter { names.contains($0.name) }
        guard !taken.isEmpty else { return [] }
        writeRemoved(removed.filter { !names.contains($0.name) })
        return taken
    }

    /// User deletes past their 30 days go; inferred removals never auto-purge in 2.2 (§2.4).
    func purgeExpired(now: Date = Date()) {
        let keep = removed.filter { item in
            guard let until = item.keepUntil else { return true }
            return until > now
        }
        if keep.count != removed.count { writeRemoved(keep) }
    }

    func containsRemoved(_ name: String) -> Bool { removed.contains { $0.name == name } }

    private func writeRemoved(_ list: [RemovedRecord]) {
        do {
            try MigrationFiles.writeDurably(JSONEncoder().encode(list), to: removedURL)
            removed = list
        } catch {
            earlierLogger.error("Recently removed write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Bulk hold (P28)

    func setBulkHold(_ hold: BulkHold?) {
        if let hold {
            try? MigrationFiles.writeDurably(JSONEncoder().encode(hold), to: bulkURL)
        } else {
            try? FileManager.default.removeItem(at: bulkURL)
        }
        bulkHold = hold
    }

    // MARK: Delete all data

    func deleteEverything() {
        try? FileManager.default.removeItem(at: directory)
        reload()
    }

    /// Every version this store holds, for the ledger.
    var archivedVersions: Set<RecordVersion> {
        Set(groups.flatMap { g in g.entries.map(RecordLedger.version) + g.properties.map(RecordLedger.version) + g.categories.map(RecordLedger.version) })
    }
    var removedVersions: Set<RecordVersion> { Set(removed.compactMap(\.version)) }
    var unparsedNames: Set<String> { Set(groups.flatMap { $0.unparsedRecords.map(\.recordName) }) }
}

extension RemovedRecord {
    /// Newest first; records removed in the same moment (a bulk removal) keep one stable order by name,
    /// so the list never reshuffles between launches.
    static func newestFirst(_ records: [RemovedRecord]) -> [RemovedRecord] {
        records.sorted { a, b in
            if a.removedAt != b.removedAt { return a.removedAt > b.removedAt }
            let da = a.entry?.date ?? .distantPast, db = b.entry?.date ?? .distantPast
            if da != db { return da > db }
            let la = a.property?.name ?? a.category?.name ?? "", lb = b.property?.name ?? b.category?.name ?? ""
            if la != lb { return la < lb }
            return a.name < b.name
        }
    }
}
