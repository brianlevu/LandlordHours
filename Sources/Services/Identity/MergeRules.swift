import Foundation

// MARK: - The merge rules (v3 §4.4 R1–R18, v4 amendments, K's R19–R20), as pure functions
//
// Every function here is deterministic over its inputs and touches no store, so each rule is
// unit-tested on its own (MigrationRulesTests) and the migration composes them.

protocol IdentityRecord {
    var id: UUID { get }
    var modifiedAt: Date { get }
    var ledgerVersion: RecordVersion { get }
}

extension TimeEntry: IdentityRecord { var ledgerVersion: RecordVersion { RecordLedger.version(self) } }
extension RentalProperty: IdentityRecord { var ledgerVersion: RecordVersion { RecordLedger.version(self) } }
extension CustomCategory: IdentityRecord { var ledgerVersion: RecordVersion { RecordLedger.version(self) } }

enum MergeRules {
    // MARK: R1 / R2 — union by UUID

    struct UnionResult<T> {
        var merged: [T]
        /// Versions that lost (older `modifiedAt`, or R2's equal-time other copy). Backup-bound.
        var losers: [T]
    }

    /// R1: same UUID → newer `modifiedAt` wins. R2: equal `modifiedAt`, different content → the
    /// first argument (the device copy) wins. Never dedupes by content. Order: `base` first, then
    /// new ids from `incoming` in their order.
    static func unionReporting<T: IdentityRecord>(_ base: [T], _ incoming: [T]) -> UnionResult<T> {
        var merged = base
        var index = Dictionary(base.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        var losers: [T] = []
        for item in incoming {
            if let i = index[item.id] {
                let current = merged[i]
                if item.modifiedAt > current.modifiedAt {
                    if current.ledgerVersion != item.ledgerVersion { losers.append(current) }
                    merged[i] = item
                } else if current.ledgerVersion != item.ledgerVersion {
                    losers.append(item)
                }
            } else {
                index[item.id] = merged.count
                merged.append(item)
            }
        }
        return UnionResult(merged: merged, losers: losers)
    }

    static func union<T: IdentityRecord>(_ base: [T], _ incoming: [T]) -> [T] { unionReporting(base, incoming).merged }

    // MARK: R19 — one calendar event, one entry

    /// Entries sharing a `sourceKey` are one entry: the newer `modifiedAt` wins; the loser goes to
    /// the backup and is counted `capture_dedupe`.
    static func dedupeBySourceKey(_ entries: [TimeEntry]) -> UnionResult<TimeEntry> {
        var winners: [String: TimeEntry] = [:]
        var losers: [TimeEntry] = []
        for entry in entries {
            guard let key = entry.sourceKey, !key.isEmpty else { continue }
            if let current = winners[key] {
                if current.id == entry.id { continue }
                if entry.modifiedAt > current.modifiedAt { losers.append(current); winners[key] = entry } else { losers.append(entry) }
            } else {
                winners[key] = entry
            }
        }
        let loserIds = Set(losers.map(\.id))
        return UnionResult(merged: entries.filter { !loserIds.contains($0.id) }, losers: losers)
    }

    /// R19 on pull: a pulled entry whose `sourceKey` matches a different live entry is that entry
    /// (a 2.0.x device still deriving capture ids from its legacy id can't add a duplicate).
    static func liveMatch(forPulled entry: TimeEntry, in live: [TimeEntry]) -> TimeEntry? {
        guard let key = entry.sourceKey, !key.isEmpty else { return nil }
        return live.first { $0.id != entry.id && $0.sourceKey == key }
    }

    /// R19 on pull, newer side: the live entry takes the pulled edit's content and keeps its own
    /// id and its photos (attachments never sync), so a newer edit made on the other device is
    /// never dropped.
    static func adoptEdit(_ pulled: TimeEntry, into live: TimeEntry) -> TimeEntry? {
        guard let data = try? JSONEncoder().encode(pulled),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        object["id"] = live.id.uuidString
        guard let rewritten = try? JSONSerialization.data(withJSONObject: object),
              var adopted = try? JSONDecoder().decode(TimeEntry.self, from: rewritten), adopted.id == live.id else { return nil }
        adopted.attachments = live.attachments
        return adopted
    }

    // MARK: R3 — tombstones

    static func applyTombstones<T: IdentityRecord>(_ records: [T], names: Set<String>) -> (kept: [T], removed: [T]) {
        var kept: [T] = [], removed: [T] = []
        for r in records { if names.contains(r.id.uuidString) { removed.append(r) } else { kept.append(r) } }
        return (kept, removed)
    }

    // MARK: R9 / R12 — spouse

    static func swapParticipants(_ entries: [TimeEntry]) -> [TimeEntry] {
        entries.map { entry in
            var e = entry
            e.participant = entry.participant == .selfParticipant ? .spouse : .selfParticipant
            return e
        }
    }

    /// The spouse answer is an edit the person made: the swapped copies are stamped `at`, so they
    /// beat the pre-answer copy another device still holds (equal times would keep each device's
    /// own copy and push it back forever).
    static func swapParticipants(_ entries: [TimeEntry], editedAt at: Date) -> [TimeEntry] {
        swapParticipants(entries).map { entry in
            var e = entry
            e.modifiedAt = max(entry.modifiedAt, at)
            return e
        }
    }

    // MARK: R5 / R5c — synced, then absent from a complete read

    enum AbsenceOutcome: Equatable {
        /// A guard failed: nothing removed. `reason` is for logs and analytics.
        case skipped(String)
        /// Zero overlap: this profile's baselines came from another account or a recreated zone.
        /// Fingerprints are discarded; its records take the R4 "new" path.
        case staleBaselines
        /// These names were synced and are now absent: Recently removed (inferred).
        case removed(Set<String>)
        /// More than half absent: paused, held on the device, not pushed, the person is asked (P28).
        case paused(Set<String>)
    }

    struct AbsenceGuards: Equatable {
        var readComplete: Bool
        var zoneExists: Bool
        var sameAccount: Bool
    }

    /// R5 for one legacy profile: `fingerprinted` are the names its tracker says the server held,
    /// `onDevice` the names of its records now on the device, `present` the raw names of the read.
    static func absence(fingerprinted: Set<String>, onDevice: Set<String>, present: Set<String>,
                        guards: AbsenceGuards, bulkThreshold: Double = 0.5) -> AbsenceOutcome {
        guard guards.readComplete else { return .skipped("incomplete_read") }
        guard guards.zoneExists else { return .skipped("zone_absent") }
        guard guards.sameAccount else { return .skipped("account_changed") }
        guard !fingerprinted.isEmpty else { return .skipped("no_baselines") }
        guard !fingerprinted.isDisjoint(with: present) else { return .staleBaselines }
        let absent = fingerprinted.subtracting(present).intersection(onDevice)
        guard !absent.isEmpty else { return .removed([]) }
        if Double(fingerprinted.subtracting(present).count) / Double(fingerprinted.count) > bulkThreshold {
            return .paused(absent)
        }
        return .removed(absent)
    }

    /// Steady state (v4 3c): a pull whose deletes exceed half the live set asks first.
    static func isBulkDelete(deleting: Int, liveCount: Int, threshold: Double = 0.5) -> Bool {
        guard liveCount > 0, deleting > 0 else { return false }
        return Double(deleting) / Double(liveCount) > threshold
    }

    // MARK: R2b — same owner id, zero overlap

    static func isSplit(deviceNames: Set<String>, cloudNames: Set<String>) -> Bool {
        !deviceNames.isEmpty && !cloudNames.isEmpty && deviceNames.isDisjoint(with: cloudNames)
    }

    // MARK: R13 / R14 — Pro and onboarding

    static func proFlags(_ groups: [LegacyGroup]) -> (isProUser: Bool, hasPurchasedPro: Bool) {
        (groups.contains { ($0.values["isProUser"] as? Bool) == true },
         groups.contains { ($0.values["hasPurchasedPro"] as? Bool) == true })
    }

    static func completedOnboarding(_ groups: [LegacyGroup], liveIsEmpty: Bool) -> Bool {
        groups.contains { $0.completedOnboarding } || !liveIsEmpty
    }

    // MARK: §4.6 — the unified id

    /// 1. household pair in the zone → its `appUserId`; 2. else the zone owner with the most
    /// entries (ties → lexicographically smallest) unless excluded; 3. else the device primary's
    /// legacy id unless excluded; 4. else "household". Excluded: R2b-split ids, aside/pending ids,
    /// anything starting with `aside-` (v4 change 3a).
    static func unifiedId(householdOwner: String?, zoneEntryCounts: [String: Int], devicePrimary: String?,
                          excluded: Set<String>) -> String {
        func allowed(_ id: String) -> Bool {
            !excluded.contains(id) && !id.hasPrefix(IdentityZone.asidePrefix) && !LegacyInventory.isIgnoredId(id)
        }
        // Rule 1 too respects `excluded`: a pending/aside set's id is never this phone's.
        if let householdOwner, !householdOwner.isEmpty, allowed(householdOwner) { return householdOwner }
        let ranked = zoneEntryCounts.filter { $0.value > 0 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        if let top = ranked.first {
            return allowed(top.key) ? top.key : IdentityZone.household
        }
        if let devicePrimary, devicePrimary != LegacyInventory.unscopedGroupId {
            return allowed(devicePrimary) ? devicePrimary : IdentityZone.household
        }
        return IdentityZone.household
    }

    // MARK: §4.5 / v4 §3.3 — settings precedence (no client clocks)

    enum SettingsWinner: Equatable {
        case household
        case local
        /// Local was dirty while the set was empty: household wins; local answers → merge report (P29).
        case householdDiscardingLocal
        /// No household pair; local is clean and the set is empty: write nothing, pull.
        case nothing
        /// No household pair: the primary group's own settings (cloud) apply.
        case group
    }

    static func settingsWinner(householdExists: Bool, localDirty: Bool, dirtyWhileEmpty: Bool,
                               liveIsEmpty: Bool, groupSettingsExist: Bool) -> SettingsWinner {
        if householdExists {
            if !localDirty { return .household }
            return dirtyWhileEmpty ? .householdDiscardingLocal : .local
        }
        if localDirty && !dirtyWhileEmpty { return .local }
        if groupSettingsExist { return dirtyWhileEmpty ? .householdDiscardingLocal : .group }
        if localDirty { return .local }
        return liveIsEmpty ? .nothing : .local
    }

    /// Mirror (`-<unifiedId>`, written by 2.0.x devices) vs household: newer server date wins.
    static func mirrorBeatsHousehold(mirror: Date?, household: Date?) -> Bool {
        guard let mirror else { return false }
        guard let household else { return true }
        return mirror > household
    }

    // MARK: R20 / R10 / R12 — where a pulled record goes

    enum Route: Equatable {
        case live
        /// Spouse group (R12): re-tag participants on arrival, then live.
        case liveAsSpouse
        case archive(String)
        /// An owner the device never saw: a new group, held and asked about.
        case newGroup(String)
        /// R11: deleted after migration; ignore.
        case ignore
    }

    struct RoutingContext {
        var liveNames: Set<String>
        var archiveMembership: [String: String]
        var unifiedId: String?
        var groups: GroupsFile?
        var deletedNames: Set<String>
        var tombstones: Set<String>
        /// When each of `deletedNames` was deleted. A copy edited after that (Put back on another
        /// device) is not the deleted record coming back from a 1.1 device: it routes normally.
        var deletedAt: [String: Date] = [:]
    }

    static func route(_ record: ZoneRecord, context: RoutingContext) -> Route {
        let name = record.recordName
        if context.tombstones.contains(name) { return .ignore }
        if context.deletedNames.contains(name) {
            guard let at = context.deletedAt[name], let edited = record.modifiedAt, edited > at else { return .ignore }
        }
        let owner = record.appUserId ?? LegacyInventory.unscopedGroupId
        // R12 before R20: a copy tagged with a spouse group's own id comes from the spouse's 2.0.x
        // device, written from their side (participant Self). It is swapped on arrival even when the
        // record is already live here, or the spouse's hours silently turn back into the owner's.
        if owner != context.unifiedId, context.groups?.group(owner)?.status == .spouse,
           context.liveNames.contains(name) || (context.archiveMembership[name] ?? owner) == owner {
            return .liveAsSpouse
        }
        // R20: membership by UUID beats the incoming tag.
        if context.liveNames.contains(name) { return .live }
        if let group = context.archiveMembership[name] { return .archive(group) }
        if owner == context.unifiedId { return .live }
        if owner.hasPrefix(IdentityZone.asidePrefix) { return .archive(String(owner.dropFirst(IdentityZone.asidePrefix.count))) }
        if let group = context.groups?.group(owner) {
            switch group.status {
            case .primary, .combine: return .live
            case .spouse: return .liveAsSpouse
            case .aside, .pending: return .archive(owner)
            case .notNeeded: return .newGroup(owner)
            }
        }
        return .newGroup(owner)
    }
}
