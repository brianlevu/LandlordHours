import Foundation
import CloudKit
import os.log

private let migrationLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "RecordSetMigration")

// MARK: - The live record set, as the engine sees it

/// Where the live set lives while the app runs. `AppViewModel` in the app; `DefaultsLiveRecordSet`
/// in tests and before the view model exists.
@MainActor
protocol LiveRecordSet: AnyObject {
    var liveEntries: [TimeEntry] { get }
    var liveProperties: [RentalProperty] { get }
    var liveCategories: [CustomCategory] { get }
    /// Persists the new live set (no push; the engine pushes).
    func replaceLive(entries: [TimeEntry], properties: [RentalProperty], categories: [CustomCategory])
    var goalSettings: GoalSettingsValues { get }
    var taxProfile: TaxProfileValues { get }
    /// Applies settings that came from iCloud (never marks them dirty).
    func applyRemoteSettings(goal: GoalSettingsValues?, tax: TaxProfileValues?)
}

/// The live set read and written straight from `v2.` keys.
@MainActor
final class DefaultsLiveRecordSet: LiveRecordSet {
    let defaults: UserDefaults
    let prefix: String
    init(defaults: UserDefaults, prefix: String = IdentityKeys.prefix) { self.defaults = defaults; self.prefix = prefix }

    private func decode<T: Decodable>(_ suffix: String, _ type: [T].Type) -> [T] {
        (defaults.data(forKey: prefix + suffix)).flatMap { try? JSONDecoder().decode(type, from: $0) } ?? []
    }
    var liveEntries: [TimeEntry] { decode(LegacyInventory.entriesSuffix, [TimeEntry].self) }
    var liveProperties: [RentalProperty] { decode(LegacyInventory.propertiesSuffix, [RentalProperty].self) }
    var liveCategories: [CustomCategory] { decode(LegacyInventory.categoriesSuffix, [CustomCategory].self) }
    func replaceLive(entries: [TimeEntry], properties: [RentalProperty], categories: [CustomCategory]) {
        // Sorted keys: an S4 re-run after a crash writes byte-identical blobs (§3.3).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try? encoder.encode(entries), forKey: prefix + LegacyInventory.entriesSuffix)
        defaults.set(try? encoder.encode(properties), forKey: prefix + LegacyInventory.propertiesSuffix)
        defaults.set(try? encoder.encode(categories), forKey: prefix + LegacyInventory.categoriesSuffix)
    }
    var goalSettings: GoalSettingsValues { GoalSettingsValues(defaults: defaults, prefix: prefix) }
    var taxProfile: TaxProfileValues { TaxProfileValues(defaults: defaults, prefix: prefix) }
    func applyRemoteSettings(goal: GoalSettingsValues?, tax: TaxProfileValues?) {
        if let goal {
            defaults.set(goal.globalGoalType, forKey: prefix + "globalGoalType")
            defaults.set(Data(goal.propertyGoalsJSON.utf8), forKey: prefix + "propertyGoals")
            if let mp = goal.materialParticipationTarget, mp > 0 { defaults.set(mp, forKey: prefix + "materialParticipationTarget") }
        }
        if let tax {
            let p = prefix + "LandlordHours.taxProfile."
            defaults.set(tax.filingStatus, forKey: p + "filingStatus")
            defaults.set(tax.spouseTracking, forKey: p + "spouseTracking")
            defaults.set(tax.taxYear, forKey: p + "taxYear")
            defaults.set(tax.groupingElection, forKey: p + "groupingElection")
            defaults.set(tax.nonREWorkHours, forKey: p + "nonREWorkHours")
            if let name = tax.displayName { defaults.set(name, forKey: IdentityKeys.displayName) }
        }
    }
}

// MARK: - The migration

/// S1–S10 (§3.1). The device phase runs before the first frame; the cloud phase runs in the
/// background whenever iCloud is reachable, and is re-entrant from its last completed step.
@MainActor
final class RecordSetMigration {

    // MARK: Device phase (S1–S4)

    enum DeviceOutcome: Equatable {
        case alreadyMerged
        /// Nothing on the device: a fresh start under "household".
        case fresh
        case merged(primary: String?, pendingGroups: Int)
        /// The backup couldn't be written (disk full): the app runs on `u.<id>.` (§3.4, P25).
        case backupFailed(neededBytes: Int)
    }

    /// Test seam: crash injection (`-LHCrashAt <step>` in DEBUG, `crashAt` in tests).
    struct CrashInjected: Error, Equatable { var step: String }

    struct DeviceOptions {
        var now = Date()
        var writeBackup: ((Data, URL) throws -> Void)? = nil
        var crashAt: String? = nil
    }

    static func runDevicePhase(defaults: UserDefaults, root: URL, options: DeviceOptions = DeviceOptions()) throws -> DeviceOutcome {
        let start = Date()
        defer {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            migrationLogger.info("Device phase took \(ms) ms")
        }
        if IdentityScope.step(defaults) >= .deviceMerged { return .alreadyMerged }

        // S1 — inventory (memory only).
        let inventory = LegacyInventory.scan(defaults: defaults, root: root)
        setStep(.inventoried, defaults)
        // A 1.x/2.0 profile that synced (baselines, a zone token, or its first push done) knew the
        // zone: if it is gone now it was deleted on another phone, and P31 asks (never recreated).
        if inventory.groups.contains(where: Self.syncedBefore) { defaults.set(true, forKey: IdentityKeys.zoneSeen) }

        let backupKeys = MigrationBackup.backedUpKeys(in: defaults.dictionaryRepresentation())
        if inventory.groups.isEmpty && backupKeys.isEmpty {
            // Fresh install: nothing to protect, nothing to back up.
            adoptIds(storage: IdentityZone.household, unified: IdentityZone.household, defaults: defaults)
            setStep(.deviceMerged, defaults)
            return .fresh
        }

        // S2 — backup, or nothing.
        let backup = MigrationBackup.make(defaults: defaults, root: root, now: options.now)
        do {
            if let writer = options.writeBackup {
                try backup.write(root: root, now: options.now, write: writer)
            } else {
                try backup.write(root: root, now: options.now)
            }
        } catch {
            let needed = (try? JSONEncoder.identity.encode(backup).count) ?? 0
            migrationLogger.error("Backup failed; staying on legacy keys: \(error.localizedDescription, privacy: .public)")
            // The app keeps running on the active profile's legacy prefix until S2 succeeds.
            let legacy = inventory.activeId.flatMap { LegacyInventory.isIgnoredId($0) ? nil : $0 } ?? inventory.primary?.id
            if let legacy, legacy != LegacyInventory.unscopedGroupId { defaults.set(legacy, forKey: IdentityKeys.legacyPrefixId) }
            defaults.set(needed, forKey: IdentityKeys.backupNeededBytes)
            return .backupFailed(neededBytes: needed)
        }
        defaults.removeObject(forKey: IdentityKeys.legacyPrefixId)
        defaults.removeObject(forKey: IdentityKeys.backupNeededBytes)
        setStep(.backedUp, defaults)
        if options.crashAt == "S2" { throw CrashInjected(step: "S2") }

        // S3 — groups (answers already recorded survive a re-run).
        let previous = GroupsFile.load(root: root)
        let primary = inventory.primary
        var groupsFile = GroupsFile(createdAt: previous?.createdAt ?? options.now, primaryId: primary?.id, groups: previous?.groups ?? [])
        for group in inventory.groups {
            let status: GroupStatus
            if group.id == primary?.id {
                status = .primary
            } else if group.isEmpty {
                status = .notNeeded
            } else if let answered = previous?.group(group.id)?.status, answered != .primary, answered != .notNeeded {
                status = answered
            } else {
                status = .pending
            }
            groupsFile.upsert(GroupRecord(id: group.id, status: status, source: .device, entryCount: group.entries.count,
                                          propertyCount: group.properties.count, hours: group.totalHours,
                                          lastEntryDate: group.lastEntryDate,
                                          answeredAt: previous?.group(group.id)?.answeredAt))
        }
        try groupsFile.save(root: root)
        setStep(.groupsResolved, defaults)

        // S4 — the live set under `v2.`, archive copies, ids.
        let storage = (primary?.id).flatMap { $0 == LegacyInventory.unscopedGroupId ? nil : $0 } ?? IdentityZone.household
        let live = inventory.groups.filter { groupsFile.group($0.id)?.status.isLive == true }
        let earlier = EarlierRecordsStore(root: root)

        if let primary { copyKeys(of: primary, defaults: defaults) }

        var entries: [TimeEntry] = []
        var properties: [RentalProperty] = []
        var categories: [CustomCategory] = []
        var losers: [RecordVersion] = []
        let ordered = live.sorted { ($0.id == primary?.id ? 0 : 1, $0.id) < ($1.id == primary?.id ? 0 : 1, $1.id) }
        for group in ordered {
            let e = MergeRules.unionReporting(entries, group.entries)
            let p = MergeRules.unionReporting(properties, group.properties)
            let c = MergeRules.unionReporting(categories, group.categories)
            entries = e.merged; properties = p.merged; categories = c.merged
            losers += e.losers.map(\.ledgerVersion) + p.losers.map(\.ledgerVersion) + c.losers.map(\.ledgerVersion)
        }
        // R3: every live group's pending deletes stay deletes.
        let tombstones = Set(live.flatMap { $0.tracker?.pendingDeletes ?? [] })
        let te = MergeRules.applyTombstones(entries, names: tombstones)
        let tp = MergeRules.applyTombstones(properties, names: tombstones)
        let tc = MergeRules.applyTombstones(categories, names: tombstones)
        entries = te.kept; properties = tp.kept; categories = tc.kept
        let removedHere = te.removed.map { RemovedRecord(name: $0.id.uuidString, reason: .deletedHere, removedAt: options.now,
                                                         keepUntil: options.now.addingTimeInterval(EarlierRecordsStore.userDeleteRetention), entry: $0) }
            + tp.removed.map { RemovedRecord(name: $0.id.uuidString, reason: .deletedHere, removedAt: options.now,
                                             keepUntil: options.now.addingTimeInterval(EarlierRecordsStore.userDeleteRetention), property: $0) }
            + tc.removed.map { RemovedRecord(name: $0.id.uuidString, reason: .deletedHere, removedAt: options.now,
                                             keepUntil: options.now.addingTimeInterval(EarlierRecordsStore.userDeleteRetention), category: $0) }
        earlier.remove(removedHere)
        // R19: one calendar event confirmed in two groups is one entry.
        let deduped = MergeRules.dedupeBySourceKey(entries)
        entries = deduped.merged
        losers += deduped.losers.map(\.ledgerVersion)
        if !deduped.losers.isEmpty { defaults.set(deduped.losers.count, forKey: "v2.migration.captureDedupe") }

        let liveSet = DefaultsLiveRecordSet(defaults: defaults)
        liveSet.replaceLive(entries: entries, properties: properties, categories: categories)
        if options.crashAt == "S4" { throw CrashInjected(step: "S4") }

        // R13 Pro OR, R14 onboarding, R15/R16 drafts and opt-ins.
        let pro = MergeRules.proFlags(inventory.groups)
        if pro.isProUser { defaults.set(true, forKey: "v2.isProUser") }
        if pro.hasPurchasedPro { defaults.set(true, forKey: "v2.hasPurchasedPro") }
        if MergeRules.completedOnboarding(inventory.groups.filter { !$0.isEmpty || $0.id == primary?.id },
                                          liveIsEmpty: entries.isEmpty && properties.isEmpty) {
            defaults.set(true, forKey: "v2.hasCompletedOnboarding")
        }
        mergeSecondaryValues(live.filter { $0.id != primary?.id }, defaults: defaults, now: options.now)
        mergeCaptureFiles(from: live.map(\.id).filter { $0 != storage }, into: storage, root: root)
        mergeTrackers(live, into: storage, root: root)
        rekeyQueuedActions(from: Set(live.map(\.id)), to: storage, defaults: defaults)

        // R10: pending / aside groups are copied to Earlier records (and pushed under aside- at S9).
        for group in inventory.groups where !group.isEmpty {
            guard let status = groupsFile.group(group.id)?.status, status == .pending || status == .aside else { continue }
            try earlier.save(ArchivedGroup(id: group.id, status: status, source: .device, entries: group.entries,
                                           properties: group.properties, categories: group.categories, createdAt: options.now))
        }

        adoptIds(storage: storage, unified: primary.flatMap { $0.id == LegacyInventory.unscopedGroupId ? nil : $0.id } ?? IdentityZone.household,
                 defaults: defaults)

        // The invariant, device side. Each inventory version is hashed once; a live entry reuses
        // its source's hash unless its id had more than one version.
        var versionsById: [UUID: [RecordVersion]] = [:]
        var before = Set<RecordVersion>()
        for g in inventory.groups {
            for e in g.entries {
                let v = e.ledgerVersion
                before.insert(v)
                if versionsById[e.id]?.contains(v) != true { versionsById[e.id, default: []].append(v) }
            }
            before.formUnion(g.properties.map(\.ledgerVersion) + g.categories.map(\.ledgerVersion))
        }
        var places = RecordLedger.Places()
        places.live = Set(entries.map { e -> RecordVersion in
            if let known = versionsById[e.id], known.count == 1 { return known[0] }
            return e.ledgerVersion
        }).union(RecordLedger.versions(entries: [], properties: properties, categories: categories))
        places.archived = earlier.archivedVersions
        places.removed = earlier.removedVersions
        places.backup = Set(losers)
        places.tombstoned = tombstones
        RecordLedger.enforce(RecordLedger.check(before: before, places: places), step: "S4")
        LedgerSnapshot(step: "S4", takenAt: options.now, live: places.live.sorted { $0.name < $1.name },
                       archived: places.archived.sorted { $0.name < $1.name }, removed: places.removed.sorted { $0.name < $1.name },
                       tombstoned: tombstones.sorted()).save("v2-after-device.json", root: root)

        setStep(.deviceMerged, defaults)
        return .merged(primary: primary?.id, pendingGroups: groupsFile.pending.count)
    }

    /// Copies every `u.<primary>.<suffix>` key to `v2.<suffix>` (key-driven, §2.2.1), except the
    /// per-profile CloudKit tokens (the cloud phase reads the zone whole).
    static func copyKeys(of group: LegacyGroup, defaults: UserDefaults) {
        for (suffix, value) in group.values {
            if suffix.hasPrefix("cloudkit.") { continue }
            defaults.set(value, forKey: IdentityKeys.prefix + suffix)
        }
    }

    /// R15 / R16 for combined groups: their timers become drafts, their drafts and opt-ins join.
    static func mergeSecondaryValues(_ groups: [LegacyGroup], defaults: UserDefaults, now: Date) {
        guard !groups.isEmpty else { return }
        let draftsKey = IdentityKeys.prefix + "LandlordHours.staleTimerRecoveries"
        var drafts = (defaults.data(forKey: draftsKey)).flatMap { try? JSONDecoder().decode([StaleTimerRecovery].self, from: $0) } ?? []
        for group in groups {
            if let data = group.values["LandlordHours.staleTimerRecoveries"] as? Data,
               let list = try? JSONDecoder().decode([StaleTimerRecovery].self, from: data) {
                for draft in list where !drafts.contains(where: { $0.id == draft.id }) { drafts.append(draft) }
            }
            if (group.values["LandlordHours.timer"] as? Bool) == true, let start = group.values["timerStartTime"] as? Date,
               let rawProperty = group.values["timerPropertyId"] as? String, let propertyId = UUID(uuidString: rawProperty) {
                let category = (group.values["timerCategory"] as? String).flatMap(ActivityCategory.init(rawValue:)) ?? .repairs
                drafts.append(StaleTimerRecovery(startTime: start, propertyId: propertyId, category: category,
                                                 elapsedHours: max(now.timeIntervalSince(start), 0) / 3600, reason: .pausedAtSwitch, pausedAt: now))
            }
            for key in CaptureOptIn.allBaseKeys + [CapturePromptConsent.baseKey]
            where (group.values[key] as? Bool) == true {
                defaults.set(true, forKey: IdentityKeys.prefix + key)
            }
        }
        if !drafts.isEmpty { defaults.set(try? JSONEncoder().encode(drafts.sorted { $0.startTime < $1.startTime }), forKey: draftsKey) }
    }

    /// A set this phone holds apart from its own: still asked about, or kept aside.
    static func heldApart(_ status: GroupStatus?) -> Bool { status == .pending || status == .aside }

    static func syncedBefore(_ group: LegacyGroup) -> Bool {
        !(group.tracker?.fingerprints.isEmpty ?? true) || group.values["cloudkit.zoneChangeToken"] != nil
            || (group.values["cloudkit.migrationDone"] as? Bool) == true
    }

    /// U33: suggestion files of combined groups merge into the live one by `sourceKey`; dismissed
    /// keys and mute rules are OR'd.
    static func mergeCaptureFiles(from ids: [String], into storage: String, root: URL) {
        let base = root.appendingPathComponent("Capture", isDirectory: true)
        let targetURL = SuggestionStore.directory(forUserId: storage, baseDirectory: base).appendingPathComponent(SuggestionStore.fileName)
        var target = (try? Data(contentsOf: targetURL)).flatMap { try? JSONDecoder.captureDecoder.decode(SuggestionStore.Contents.self, from: $0) }
            ?? SuggestionStore.Contents()
        var changed = false
        for id in ids {
            let url = SuggestionStore.directory(forUserId: id, baseDirectory: base).appendingPathComponent(SuggestionStore.fileName)
            guard let data = try? Data(contentsOf: url),
                  let contents = try? JSONDecoder.captureDecoder.decode(SuggestionStore.Contents.self, from: data) else { continue }
            for suggestion in contents.suggestions where !target.suggestions.contains(where: { $0.sourceKey == suggestion.sourceKey }) {
                target.suggestions.append(suggestion)
                changed = true
            }
            for (key, date) in contents.dismissedKeys where target.dismissedKeys[key] == nil {
                target.dismissedKeys[key] = date
                changed = true
            }
            for rule in contents.muteRules where !target.muteRules.contains(rule) {
                target.muteRules.append(rule)
                changed = true
            }
        }
        guard changed, let data = try? JSONEncoder.captureEncoder.encode(target) else { return }
        try? MigrationFiles.writeDurably(data, to: targetURL)
    }

    /// U36: every live group's pending deletes become the live tracker's tombstones.
    static func mergeTrackers(_ groups: [LegacyGroup], into storage: String, root: URL) {
        let tombstones = groups.filter { $0.id != storage }.flatMap { $0.tracker?.pendingDeletes ?? [] }
        guard !tombstones.isEmpty else { return }
        SyncChangeTracker(userId: storage, baseDirectory: root.appendingPathComponent("Sync", isDirectory: true)).addTombstones(tombstones)
    }

    /// U34: a "Log it" queued under a legacy id before the update lands under the live id.
    static func rekeyQueuedActions(from ids: Set<String>, to storage: String, defaults: UserDefaults) {
        let items = CaptureActionQueue.all(defaults: defaults)
        guard items.contains(where: { ids.contains($0.profileId) && $0.profileId != storage }) else { return }
        var seen = Set<String>()
        let rekeyed = items.map { item -> QueuedCaptureAction in
            var copy = item
            if ids.contains(item.profileId) { copy.profileId = storage }
            return copy
        }.filter { seen.insert("\($0.profileId)|\($0.sourceKey)").inserted }
        CaptureActionQueue.save(rekeyed, defaults: defaults)
    }

    static func adoptIds(storage: String, unified: String, defaults: UserDefaults) {
        defaults.set(storage, forKey: IdentityKeys.storageId)
        if defaults.string(forKey: IdentityKeys.captureProfileId) == nil { defaults.set(storage, forKey: IdentityKeys.captureProfileId) }
        if !defaults.bool(forKey: IdentityKeys.unifiedIdDecided) { defaults.set(unified, forKey: IdentityKeys.unifiedId) }
    }

    static func setStep(_ step: MigrationStep, _ defaults: UserDefaults) {
        defaults.set(step.rawValue, forKey: IdentityKeys.state)
    }

    // MARK: Instance (cloud phase, pulls, answers)

    let defaults: UserDefaults
    let root: URL
    let source: IdentityZoneSource
    weak var live: LiveRecordSet?
    let earlier: EarlierRecordsStore
    var now: () -> Date = { Date() }
    /// Called whenever something the UI shows changed (groups, holds, notices, status).
    var onChange: (() -> Void)?
    /// Test seam: crash injection inside the cloud phase.
    var crashAt: String?

    init(defaults: UserDefaults, root: URL, source: IdentityZoneSource, live: LiveRecordSet, earlier: EarlierRecordsStore) {
        self.defaults = defaults
        self.root = root
        self.source = source
        self.live = live
        self.earlier = earlier
    }

    var step: MigrationStep { IdentityScope.step(defaults) }

    // MARK: Account guard (P13)

    enum AccountCheck: Equatable { case same, changed, unknown }

    /// Set once this run of the app confirmed iCloud is still the account the set was read from.
    /// Cleared on `CKAccountChanged` (`accountMayHaveChanged`); a relaunch starts unconfirmed.
    private(set) var accountConfirmed = false

    /// Every pull and push asks this first: iCloud must still be the account the set was read
    /// from. A different one pauses sync and asks (P13); one we can't learn right now touches
    /// nothing this round.
    func confirmAccount() async -> AccountCheck {
        if defaults.bool(forKey: IdentityKeys.accountChanged) { return .changed }
        if accountConfirmed { return .same }
        guard let current = await source.userRecordName() else { return .unknown }
        if let stored = defaults.string(forKey: IdentityKeys.icloudUserRecordName) {
            guard stored == current else {
                defaults.set(true, forKey: IdentityKeys.accountChanged)
                onChange?()
                return .changed
            }
        } else if step >= .cloudInventoried {
            // S5 couldn't learn the account; learn it now.
            defaults.set(current, forKey: IdentityKeys.icloudUserRecordName)
        }
        accountConfirmed = true
        return .same
    }

    func accountMayHaveChanged() { accountConfirmed = false }

    // MARK: The steady-state change token

    /// Where the steady-state pull keeps its zone change token (the live record set's scope).
    var steadyTokenKey: String { IdentityScope.resolve(defaults).prefix + "cloudkit.zoneChangeToken" }
    var steadyToken: Data? {
        get { defaults.data(forKey: steadyTokenKey) }
        set { if let newValue { defaults.set(newValue, forKey: steadyTokenKey) } else { defaults.removeObject(forKey: steadyTokenKey) } }
    }
    /// The same scope the rest of the app runs on (a DEBUG scope wins, so a mock never meets the
    /// real record set's baselines).
    var storageId: String { IdentityScope.resolve(defaults).scopeId ?? defaults.string(forKey: IdentityKeys.storageId) ?? IdentityZone.household }
    var unifiedId: String { IdentityScope.unifiedId(defaults) ?? storageId }
    var syncRoot: URL { root.appendingPathComponent("Sync", isDirectory: true) }
    private var sharedTracker: SyncChangeTracker?
    /// The record set's push baselines and tombstones: one instance, shared with the sync service.
    var tracker: SyncChangeTracker {
        if let sharedTracker, sharedTracker.userId == storageId,
           sharedTracker.fileURL.path.hasPrefix(syncRoot.path) { return sharedTracker }
        let made = SyncChangeTracker(userId: storageId, baseDirectory: syncRoot)
        sharedTracker = made
        return made
    }

    enum CloudOutcome: Equatable {
        case done
        case notReady
        case iCloudOff(ICloudAccountState)
        /// The whole-zone read failed or was partial: stay at deviceMerged, card P11, retry.
        case incomplete(String)
        case accountChanged
        case zoneGone
        /// The push could not finish; S9 retries on the next start.
        case pushFailed(String)
    }

    struct CloudStats: Equatable {
        var stale = 0, unparsed = 0, untaggedAdopted = 0, r5Removed = 0, bulkHeld = 0, captureDedupe = 0, deltaAbandoned = false
    }
    private(set) var lastStats = CloudStats()

    /// S5–S10. Safe to call again at any time; resumes from the last completed step.
    func runCloudPhase() async -> CloudOutcome {
        earlier.reload()
        guard step >= .deviceMerged, defaults.string(forKey: IdentityKeys.legacyPrefixId) == nil else { return .notReady }
        if step == .done { return await confirmAccount() == .changed ? .accountChanged : .done }
        if defaults.bool(forKey: IdentityKeys.zoneGone) { return .zoneGone }
        if defaults.bool(forKey: IdentityKeys.accountChanged) { return .accountChanged }
        let account = await source.accountState()
        guard account == .available else {
            if account == .noAccount || account == .restricted || account == .unsupported {
                defaults.set(true, forKey: IdentityKeys.noticeCloudWaiting)
            }
            return .iCloudOff(account)
        }
        // A resumed migration (step ≥ cloudInventoried) skips S5's read, so the account is checked
        // here on every run, not only when S5 reads.
        switch await confirmAccount() {
        case .changed: return .accountChanged
        case .unknown where defaults.string(forKey: IdentityKeys.icloudUserRecordName) != nil: return .iCloudOff(.couldNotDetermine)
        default: break
        }
        var stats = CloudStats()

        // S5 — a complete whole-zone read, the token, and whose iCloud this is.
        var snapshot: ZoneSnapshot
        if step >= .cloudInventoried, let saved = ZoneSnapshot.load(root: root) {
            snapshot = saved
        } else {
            let userName = await source.userRecordName()
            if let stored = defaults.string(forKey: IdentityKeys.icloudUserRecordName), let userName, stored != userName {
                defaults.set(true, forKey: IdentityKeys.accountChanged)
                onChange?()
                return .accountChanged
            }
            snapshot = await source.readWholeZone()
            if snapshot.incomplete {
                defaults.set(snapshot.problem ?? String(localized: "iCloud didn’t answer.", table: "Identity"), forKey: IdentityKeys.lastSyncProblem)
                defaults.set(true, forKey: IdentityKeys.noticeCloudWaiting)
                Analytics.identityReadIncomplete()
                onChange?()
                return .incomplete(snapshot.problem ?? "incomplete")
            }
            snapshot.userRecordName = userName
            try? snapshot.save(root: root)
            if snapshot.zoneExists { defaults.set(true, forKey: IdentityKeys.zoneSeen) }
            if let userName { defaults.set(userName, forKey: IdentityKeys.icloudUserRecordName) }
            defaults.set(snapshot.tokenData, forKey: IdentityKeys.migrationZoneToken)
            defaults.removeObject(forKey: IdentityKeys.lastSyncProblem)
            defaults.removeObject(forKey: IdentityKeys.noticeCloudWaiting)
            Self.setStep(.cloudInventoried, defaults)
        }
        if crashAt == "S5" { return .notReady }

        // S6 / S7 — cloud groups, then the merge.
        if step < .cloudMerged {
            stats = resolveAndMergeCloud(snapshot)
            if crashAt == "S7" { return .notReady }
            Self.setStep(.cloudMerged, defaults)
        }

        // The zone didn't exist at S5: a fresh install or a phone after Delete all data creates it
        // now, so S8b can pull and S9 can push. A zone this device knew is never recreated (P31).
        if step < .deltaPulled, !snapshot.zoneExists {
            do {
                try await source.ensureZone()
            } catch ZoneSourceError.zoneGone {
                return handleZoneGone()
            } catch {
                return .pushFailed(String(describing: error))
            }
            defaults.set(true, forKey: IdentityKeys.zoneSeen)
        }

        // S8 — the unified id and the household pair.
        if step < .householdWritten {
            do {
                try await writeHousehold(snapshot)
            } catch ZoneSourceError.zoneGone {
                return handleZoneGone()
            } catch {
                return .pushFailed(String(describing: error))
            }
            if crashAt == "S8" { return .notReady }
            Self.setStep(.householdWritten, defaults)
        }

        // S8b — every change since S5, before anything is pushed.
        if step < .deltaPulled {
            do {
                var delta = try await source.deltaPull(from: defaults.data(forKey: IdentityKeys.migrationZoneToken))
                holdUnseenSet(&delta)
                _ = applyPull(delta)
                // Applied first; the token moves only past a complete delta, so a record CloudKit
                // couldn't hand over comes again on the next pull.
                if !delta.incomplete { defaults.set(delta.tokenData, forKey: IdentityKeys.migrationZoneToken) }
            } catch ZoneSourceError.tokenExpired {
                let loops = defaults.integer(forKey: IdentityKeys.deltaLoops)
                if loops < 3 {
                    defaults.set(loops + 1, forKey: IdentityKeys.deltaLoops)
                    try? FileManager.default.removeItem(at: ZoneSnapshot.url(root: root))
                    Self.setStep(.deviceMerged, defaults)
                    // Back to S5 with a fresh read; answers and merges already made stay.
                    return await runCloudPhase()
                }
                stats.deltaAbandoned = true
                Analytics.identityDeltaAbandoned()
            } catch ZoneSourceError.zoneGone {
                // The zone S5 read (or S8 created) was deleted on another device meanwhile.
                return handleZoneGone()
            } catch {
                return .pushFailed(String(describing: error))
            }
            if crashAt == "S8b" { return .notReady }
            Self.setStep(.deltaPulled, defaults)
        }

        // S9 — push the live set under the unified id; archives under aside-.
        if step < .pushed {
            let report = await pushLive()
            if report.zoneGone { return handleZoneGone() }
            if !report.failedTypes.isEmpty && report.savedNames.isEmpty && !liveIsEmpty {
                return .pushFailed("push failed for \(report.failedTypes.keys.sorted())")
            }
            await pushArchives(snapshot)
            if crashAt == "S9" { return .notReady }
            Self.setStep(.pushed, defaults)
        }

        // S10 — done.
        Self.setStep(.done, defaults)
        // The steady-state pull goes on from where S8b stopped, not from a whole-zone refetch.
        if let token = defaults.data(forKey: IdentityKeys.migrationZoneToken) { steadyToken = token }
        defaults.set(true, forKey: IdentityKeys.hasSynced)
        defaults.removeObject(forKey: IdentityKeys.accountSwitchKeep)
        defaults.removeObject(forKey: IdentityKeys.deltaLoops)
        if defaults.object(forKey: IdentityKeys.noticeDone) == nil, IdentityRecordsSummary.wasUpgrade(root: root) {
            defaults.set(false, forKey: IdentityKeys.noticeDone)
        }
        lastStats = stats
        Analytics.recordsUnified(stats: stats, groups: GroupsFile.load(root: root))
        onChange?()
        return .done
    }

    private var liveIsEmpty: Bool { (live?.liveEntries.isEmpty ?? true) && (live?.liveProperties.isEmpty ?? true) }

    // MARK: S6 / S7

    private func resolveAndMergeCloud(_ snapshot: ZoneSnapshot) -> CloudStats {
        var stats = CloudStats()
        guard let live else { return stats }
        var groups = GroupsFile.load(root: root) ?? GroupsFile(createdAt: now(), primaryId: nil, groups: [])
        let deviceNames = Set(live.liveEntries.map { $0.id.uuidString } + live.liveProperties.map { $0.id.uuidString } + live.liveCategories.map { $0.id.uuidString })
        let inventory = deviceTrackers()

        // Owners of user records in the zone (nil → the unscoped 1.x group, Z4).
        var byOwner: [String: [ZoneRecord]] = [:]
        var settingsOwners = Set<String>()
        for record in snapshot.records {
            let owner = record.appUserId ?? LegacyInventory.unscopedGroupId
            if record.isUserRecord { byOwner[owner, default: []].append(record) } else if record.isSettings { settingsOwners.insert(owner) }
        }
        if let untagged = byOwner[LegacyInventory.unscopedGroupId] { stats.untaggedAdopted = untagged.count }
        // P13 "Keep with this iCloud": the new account's zone holds someone else's set (or nothing).
        // No owner there is this phone's by its tag, even "household" or a legacy id it shares.
        let switching = defaults.bool(forKey: IdentityKeys.accountSwitchKeep)
        let liveOwners = switching ? Set<String>() : Set([unifiedId, storageId] + groups.groups.filter { $0.status.isLive }.map(\.id))

        // Which cloud owner becomes primary when the device set is empty (U6, new phone).
        var cloudPrimary: String?
        if deviceNames.isEmpty {
            cloudPrimary = byOwner.filter { owner, records in
                !owner.hasPrefix(IdentityZone.asidePrefix) && !LegacyInventory.isIgnoredId(owner)
                    && groups.group(owner).map { $0.status != .aside && $0.status != .pending } != false
                    && records.contains { $0.recordType == "TimeEntry" || $0.recordType == "Property" }
            }.sorted { a, b in
                let ea = a.value.filter { $0.recordType == "TimeEntry" }.count, eb = b.value.filter { $0.recordType == "TimeEntry" }.count
                return ea != eb ? ea > eb : a.key < b.key
            }.first?.key
            // An earlier 2.2 device already unified the zone: its owner is the live one.
            if let household = snapshot.records.first(where: { $0.recordName == IdentityZone.goalSettingsName(IdentityZone.household) })?.appUserId,
               byOwner[household] != nil {
                cloudPrimary = household
            }
        }

        var entries = live.liveEntries, properties = live.liveProperties, categories = live.liveCategories
        var losers: [RecordVersion] = []
        let tombstones = Set(tracker.pendingDeletes)
        let deleted = deletedNames()

        func absorb(_ records: [ZoneRecord]) {
            let parsedEntries = records.compactMap(\.entry).filter { !tombstones.contains($0.id.uuidString) && !deleted.contains($0.id.uuidString) }
            let pulled = MergeRules.keepingLocalAttachments(parsedEntries, from: entries)
            let e = MergeRules.unionReporting(entries, pulled)
            let p = MergeRules.unionReporting(properties, records.compactMap(\.property).filter { !tombstones.contains($0.id.uuidString) && !deleted.contains($0.id.uuidString) })
            let c = MergeRules.unionReporting(categories, records.compactMap(\.category).filter { !tombstones.contains($0.id.uuidString) && !deleted.contains($0.id.uuidString) })
            entries = e.merged; properties = p.merged; categories = c.merged
            losers += e.losers.map(\.ledgerVersion) + p.losers.map(\.ledgerVersion) + c.losers.map(\.ledgerVersion)
        }

        for (owner, records) in byOwner.sorted(by: { $0.key < $1.key }) {
            let entryCount = records.filter { $0.recordType == "TimeEntry" }.count
            let propertyCount = records.filter { $0.recordType == "Property" }.count
            let hours = records.compactMap(\.entry).reduce(0) { $0 + $1.hours }
            let last = records.compactMap(\.entry).map(\.date).max()
            let unparsed = records.filter { !$0.isParseable }
            stats.unparsed += unparsed.count
            let names = Set(records.map(\.recordName))
            func record(_ status: GroupStatus, split: Bool = false) -> GroupRecord {
                var r = groups.group(owner) ?? GroupRecord(id: owner, status: status, source: .iCloud, entryCount: entryCount,
                                                            propertyCount: propertyCount, hours: hours, lastEntryDate: last)
                r.status = status
                r.source = (r.source == .device || r.source == .both) ? .both : .iCloud
                r.entryCount = max(r.entryCount, entryCount); r.propertyCount = max(r.propertyCount, propertyCount)
                r.hours = max(r.hours, hours); r.lastEntryDate = [r.lastEntryDate, last].compactMap { $0 }.max()
                r.splitFromDevice = split
                return r
            }

            if owner.hasPrefix(IdentityZone.asidePrefix) {
                // Another 2.2 device kept this aside: it stays aside here too.
                let id = String(owner.dropFirst(IdentityZone.asidePrefix.count))
                earlier.route(entries: records.compactMap(\.entry), properties: records.compactMap(\.property),
                              categories: records.compactMap(\.category), unparsed: unparsed, to: id,
                              status: groups.group(id)?.status == .pending ? .pending : .aside, source: .iCloud, now: now())
                if groups.group(id) == nil { groups.upsert(record(.aside)) }
                continue
            }
            if LegacyInventory.isIgnoredId(owner) { continue }

            let existing = groups.group(owner)?.status
            // After an account switch, an answer given for the old account's owner says nothing here.
            let answered = switching ? nil : existing
            if liveOwners.contains(owner) || owner == cloudPrimary || answered == .combine || answered == .primary {
                // R2b: same owner id, both non-empty, zero UUID overlap → two groups, asked.
                let deviceOfOwner = deviceNames.intersection(inventory[owner]?.names ?? [])
                let ownerDevice = (owner == storageId) ? deviceNames : deviceOfOwner
                if owner == storageId, existing == .primary, MergeRules.isSplit(deviceNames: ownerDevice, cloudNames: names),
                   inventory[owner]?.fingerprints.isDisjoint(with: names) ?? true {
                    var r = record(.pending, split: true)
                    r.id = owner
                    groups.upsert(r)
                    earlier.route(entries: records.compactMap(\.entry), properties: records.compactMap(\.property),
                                  categories: records.compactMap(\.category), unparsed: unparsed, to: owner, status: .pending,
                                  source: .iCloud, now: now())
                    continue
                }
                absorb(records)
                if !unparsed.isEmpty {
                    earlier.route(unparsed: unparsed, to: owner, status: .combine, source: .iCloud, now: now())
                }
                groups.upsert(record(owner == cloudPrimary || existing == .primary ? .primary : (existing ?? .combine)))
                if owner == cloudPrimary { groups.primaryId = groups.primaryId ?? owner }
                continue
            }
            if existing == .aside || existing == .pending {
                earlier.route(entries: records.compactMap(\.entry), properties: records.compactMap(\.property),
                              categories: records.compactMap(\.category), unparsed: unparsed, to: owner, status: existing!,
                              source: .iCloud, now: now())
                groups.upsert(record(existing!))
                continue
            }
            if entryCount == 0 && propertyCount == 0 {
                // Only categories (or unparseable records): listed, never asked about, never merged.
                earlier.route(categories: records.compactMap(\.category), unparsed: unparsed, to: owner, status: .notNeeded,
                              source: .iCloud, now: now())
                groups.upsert(record(.notNeeded))
                continue
            }
            // A second set of records: held, visible, asked about (no size threshold).
            earlier.route(entries: records.compactMap(\.entry), properties: records.compactMap(\.property),
                          categories: records.compactMap(\.category), unparsed: unparsed, to: owner, status: .pending,
                          source: .iCloud, now: now())
            groups.upsert(record(.pending))
        }
        // Settings-only owners (diagnosis §7.2): the cloud knew them; listed as "found, no entries".
        for owner in settingsOwners where byOwner[owner] == nil && !LegacyInventory.isIgnoredId(owner)
            && owner != IdentityZone.household && !owner.hasPrefix(IdentityZone.asidePrefix) && groups.group(owner) == nil
            && owner != unifiedId && owner != storageId {
            groups.upsert(GroupRecord(id: owner, status: .notNeeded, source: .iCloud, entryCount: 0, propertyCount: 0, hours: 0,
                                      lastEntryDate: nil, settingsOnly: true))
        }

        // R19 across the merged set.
        let deduped = MergeRules.dedupeBySourceKey(entries)
        entries = deduped.merged
        losers += deduped.losers.map(\.ledgerVersion)
        stats.captureDedupe = deduped.losers.count

        // R5 / R5c per live legacy profile with baselines.
        // Baselines from the old account say nothing about the new one's zone (R5 never removes).
        let guards = MergeRules.AbsenceGuards(readComplete: !snapshot.incomplete, zoneExists: snapshot.zoneExists, sameAccount: !switching)
        var inferred: [RemovedRecord] = []
        var held = Set<String>()
        for (owner, info) in inventory where groups.group(owner)?.status.isLive == true || owner == storageId {
            let onDevice = info.names.intersection(Set(entries.map { $0.id.uuidString } + properties.map { $0.id.uuidString } + categories.map { $0.id.uuidString }))
            switch MergeRules.absence(fingerprinted: info.fingerprints, onDevice: onDevice, present: snapshot.presentNames, guards: guards) {
            case .removed(let names):
                inferred += removedCopies(names, entries: entries, properties: properties, categories: categories,
                                          reason: .inferredAbsent, group: owner)
            case .paused(let names):
                held.formUnion(names)
            case .staleBaselines:
                stats.stale += info.fingerprints.count
                if owner == storageId { tracker.resetBaselines() }
            case .skipped:
                break
            }
        }
        if !inferred.isEmpty {
            let names = Set(inferred.map(\.name))
            earlier.remove(inferred)
            entries.removeAll { names.contains($0.id.uuidString) }
            properties.removeAll { names.contains($0.id.uuidString) }
            categories.removeAll { names.contains($0.id.uuidString) }
            stats.r5Removed = names.count
        }
        if !held.isEmpty {
            let heldHours = entries.filter { held.contains($0.id.uuidString) }.reduce(0) { $0 + $1.hours }
            earlier.setBulkHold(BulkHold(names: held, totalLive: entries.count + properties.count, heldHours: heldHours,
                                         totalHours: entries.reduce(0) { $0 + $1.hours }, createdAt: now(), fromPulledDeletes: false))
            stats.bulkHeld = held.count
            Analytics.bulkPromptShown(count: held.count)
        }
        live.replaceLive(entries: entries, properties: properties, categories: categories)
        try? groups.save(root: root)
        defaults.set(stats.unparsed, forKey: IdentityKeys.unparsedCount)

        applySettingsAtMigration(snapshot, groups: groups)

        // The invariant, cloud side: every device and zone version has a place.
        let zoneVersions = Set(snapshot.records.filter { $0.isUserRecord && $0.isParseable }.map { RecordVersion(name: $0.recordName, hash: $0.contentHash) })
        let deviceBefore = (LedgerSnapshot.load("v2-after-device.json", root: root)?.live).map(Set.init) ?? []
        var places = RecordLedger.Places()
        places.live = RecordLedger.versions(entries: entries, properties: properties, categories: categories)
        places.archived = earlier.archivedVersions
        places.removed = earlier.removedVersions
        // cloud-snapshot.json keeps every zone version, as the S2 backup keeps every device one.
        places.backup = Set(losers).union(deviceBefore).union(zoneVersions)
        places.tombstoned = tombstones.union(deleted)
        places.unparsed = Set(snapshot.unparsed.map(\.recordName))
        // Zone records under ignored (debug-*) owners are not ours to place.
        let ignoredNames = Set(snapshot.records.filter { $0.appUserId.map(LegacyInventory.isIgnoredId) == true }.map(\.recordName))
        let before = zoneVersions.filter { !ignoredNames.contains($0.name) }.union(deviceBefore)
        RecordLedger.enforce(RecordLedger.check(before: before, places: places), step: "S7")
        LedgerSnapshot(step: "S7", takenAt: now(), live: places.live.sorted { $0.name < $1.name },
                       archived: places.archived.sorted { $0.name < $1.name }, removed: places.removed.sorted { $0.name < $1.name },
                       tombstoned: places.tombstoned.sorted()).save("v2-after-cloud.json", root: root)
        try? earlier.removedSnapshot().write(to: MigrationFiles.migrationDirectory(root: root).appendingPathComponent("removed.json"))
        onChange?()
        return stats
    }

    /// Trackers of every legacy id on the device (fingerprinted names and owned names).
    private func deviceTrackers() -> [String: (fingerprints: Set<String>, names: Set<String>)] {
        var result: [String: (Set<String>, Set<String>)] = [:]
        let groups = GroupsFile.load(root: root)?.groups ?? []
        for group in groups where group.source != .iCloud {
            let url = SuggestionStore.directory(forUserId: group.id, baseDirectory: syncRoot).appendingPathComponent("pushed-fingerprints.json")
            guard let data = try? Data(contentsOf: url), let contents = try? JSONDecoder().decode(SyncChangeTracker.Contents.self, from: data) else { continue }
            let fingerprinted = Set(contents.fingerprints.keys.filter { !$0.hasPrefix("GoalSettings-") && !$0.hasPrefix("TaxProfile-") })
            result[group.id] = (fingerprinted, fingerprinted)
        }
        return result.mapValues { (fingerprints: $0.0, names: $0.1) }
    }

    private func removedCopies(_ names: Set<String>, entries: [TimeEntry], properties: [RentalProperty], categories: [CustomCategory],
                               reason: RemovalReason, group: String?) -> [RemovedRecord] {
        let at = now()
        let keep: Date? = reason.isInferred ? nil : at.addingTimeInterval(EarlierRecordsStore.userDeleteRetention)
        return entries.filter { names.contains($0.id.uuidString) }.map { RemovedRecord(name: $0.id.uuidString, reason: reason, removedAt: at, keepUntil: keep, entry: $0, groupId: group) }
            + properties.filter { names.contains($0.id.uuidString) }.map { RemovedRecord(name: $0.id.uuidString, reason: reason, removedAt: at, keepUntil: keep, property: $0, groupId: group) }
            + categories.filter { names.contains($0.id.uuidString) }.map { RemovedRecord(name: $0.id.uuidString, reason: reason, removedAt: at, keepUntil: keep, category: $0, groupId: group) }
    }

    // MARK: Settings at migration (v4 §3.3)

    private func applySettingsAtMigration(_ snapshot: ZoneSnapshot, groups: GroupsFile) {
        guard let live else { return }
        func find(_ name: String) -> ZoneRecord? { snapshot.records.first { $0.recordName == name } }
        var householdGoal = find(IdentityZone.goalSettingsName(IdentityZone.household))
        var householdTax = find(IdentityZone.taxProfileName(IdentityZone.household))
        if let owner = (householdGoal ?? householdTax)?.appUserId, Self.heldApart(groups.group(owner)?.status) {
            // Another set's settings (this phone is asking about it, or keeps it aside): never applied.
            householdGoal = nil; householdTax = nil
        }
        // No household pair: the primary group's own pair (Z6: `-default` only when the unscoped
        // group is primary).
        let primary = groups.primaryId ?? storageId
        let groupOwner = primary == LegacyInventory.unscopedGroupId ? "default" : primary
        let groupGoal = find(IdentityZone.goalSettingsName(groupOwner))
        let groupTax = find(IdentityZone.taxProfileName(groupOwner))
        let empty = live.liveEntries.isEmpty && live.liveProperties.isEmpty
        let winner = MergeRules.settingsWinner(
            householdExists: householdGoal != nil || householdTax != nil,
            localDirty: defaults.bool(forKey: IdentityKeys.goalDirty) || defaults.bool(forKey: IdentityKeys.taxDirty),
            dirtyWhileEmpty: defaults.bool(forKey: IdentityKeys.goalDirtyWhileEmpty) || defaults.bool(forKey: IdentityKeys.taxDirtyWhileEmpty),
            liveIsEmpty: empty,
            groupSettingsExist: groupGoal != nil || groupTax != nil)
        switch winner {
        case .household, .householdDiscardingLocal, .group:
            let goal = (householdGoal ?? groupGoal).map(GoalSettingsValues.init(record:))
            var tax = (householdTax ?? groupTax).map(TaxProfileValues.init(record:))
            if tax?.displayName == nil { tax?.displayName = live.taxProfile.displayName }
            if winner == .householdDiscardingLocal || (winner == .group && dirtyWhileEmpty) {
                // The answers made before the cloud read landed go to Advanced (P29), never lost.
                let report = DiscardedSettings(goal: live.goalSettings, tax: live.taxProfile, at: now())
                defaults.set(try? JSONEncoder().encode(report), forKey: IdentityKeys.discardedOnboardingAnswers)
                defaults.set(true, forKey: IdentityKeys.noticeSettingsKept)
                Analytics.settingsEmptyEditDiscarded()
            }
            live.applyRemoteSettings(goal: goal, tax: tax)
            clearDirty()
            if householdGoal != nil || householdTax != nil {
                defaults.set(true, forKey: IdentityKeys.householdFromCloud)
                rememberHousehold(goal: goal, tax: tax)
            }
        case .local, .nothing:
            break
        }
    }

    struct HouseholdCache: Codable { var goal: GoalSettingsValues?; var tax: TaxProfileValues? }

    /// Two sets migrating at once: the id S8 adopted belongs to records this phone doesn't hold.
    /// Those records become a held set (asked about), this phone keeps its own id, and nothing
    /// of the live set is pushed until the question is answered (as with a pending household).
    private func holdUnseenSet(_ delta: inout ZoneDelta) {
        guard let owner = defaults.string(forKey: IdentityKeys.adoptedUnseen) else { return }
        defaults.removeObject(forKey: IdentityKeys.adoptedUnseen)
        let own = defaults.string(forKey: IdentityKeys.adoptedFrom) ?? storageId
        defaults.removeObject(forKey: IdentityKeys.adoptedFrom)
        guard let live else { return }
        let liveNames = Set(live.liveEntries.map { $0.id.uuidString } + live.liveProperties.map { $0.id.uuidString }
                            + live.liveCategories.map { $0.id.uuidString })
        let theirs = delta.changed.filter { $0.isUserRecord && $0.appUserId == owner && !liveNames.contains($0.recordName) }
        guard theirs.contains(where: { $0.recordType == "TimeEntry" || $0.recordType == "Property" }) else { return }
        defaults.set(own, forKey: IdentityKeys.unifiedId)
        defaults.set(owner, forKey: IdentityKeys.householdHeldFor)
        holdHousehold(from: delta.changed.filter { $0.appUserId == owner })
        var groups = GroupsFile.load(root: root) ?? GroupsFile(createdAt: now(), primaryId: storageId, groups: [])
        earlier.route(entries: theirs.compactMap(\.entry), properties: theirs.compactMap(\.property),
                      categories: theirs.compactMap(\.category), unparsed: theirs.filter { !$0.isParseable },
                      to: owner, status: .pending, source: .iCloud, now: now())
        let entries = theirs.compactMap(\.entry)
        groups.upsert(GroupRecord(id: owner, status: .pending, source: .iCloud, entryCount: entries.count,
                                  propertyCount: theirs.compactMap(\.property).count, hours: entries.reduce(0) { $0 + $1.hours },
                                  lastEntryDate: entries.map(\.date).max()))
        try? groups.save(root: root)
        let held = Set(theirs.map(\.recordName))
        delta.changed.removeAll { held.contains($0.recordName) }
    }

    /// Keeps the held household pair's values (from a read or a delta) for when the hold ends.
    func holdHousehold(from records: [ZoneRecord]) {
        let goal = records.first { $0.recordName == IdentityZone.goalSettingsName(IdentityZone.household) }.map(GoalSettingsValues.init(record:))
        let tax = records.first { $0.recordName == IdentityZone.taxProfileName(IdentityZone.household) }.map(TaxProfileValues.init(record:))
        guard goal != nil || tax != nil else { return }
        defaults.set(try? JSONEncoder().encode(HouseholdCache(goal: goal, tax: tax)), forKey: IdentityKeys.heldHouseholdCache)
    }

    /// The hold ends (the set that owns the household pair was answered). Before anything is
    /// pushed, the usual settings precedence (v4 §3.3) runs against that pair: clean local
    /// settings take the household's, so the next push never writes this phone's over it.
    func releaseHousehold() {
        defaults.removeObject(forKey: IdentityKeys.householdHeldFor)
        defer { defaults.removeObject(forKey: IdentityKeys.heldHouseholdCache) }
        guard let live, let data = defaults.data(forKey: IdentityKeys.heldHouseholdCache),
              let held = try? JSONDecoder().decode(HouseholdCache.self, from: data) else { return }
        let winner = MergeRules.settingsWinner(
            householdExists: true,
            localDirty: defaults.bool(forKey: IdentityKeys.goalDirty) || defaults.bool(forKey: IdentityKeys.taxDirty),
            dirtyWhileEmpty: dirtyWhileEmpty,
            liveIsEmpty: live.liveEntries.isEmpty && live.liveProperties.isEmpty,
            groupSettingsExist: false)
        switch winner {
        case .household, .householdDiscardingLocal, .group:
            if winner == .householdDiscardingLocal {
                let report = DiscardedSettings(goal: live.goalSettings, tax: live.taxProfile, at: now())
                defaults.set(try? JSONEncoder().encode(report), forKey: IdentityKeys.discardedOnboardingAnswers)
                defaults.set(true, forKey: IdentityKeys.noticeSettingsKept)
            }
            var tax = held.tax
            if tax?.displayName == nil { tax?.displayName = live.taxProfile.displayName }
            live.applyRemoteSettings(goal: held.goal, tax: tax)
            clearDirty()
        case .local, .nothing:
            break
        }
    }

    private func rememberHousehold(goal: GoalSettingsValues?, tax: TaxProfileValues?) {
        defaults.set(try? JSONEncoder().encode(HouseholdCache(goal: goal, tax: tax)), forKey: IdentityKeys.householdCache)
    }

    private func loadHouseholdCache() -> HouseholdCache? {
        defaults.data(forKey: IdentityKeys.householdCache).flatMap { try? JSONDecoder().decode(HouseholdCache.self, from: $0) }
    }

    /// Onboarding finished (or was left). Answers it made after the cloud phase brought another
    /// device's household in lose to that household, as answers made before it would have (P29):
    /// the household goes back on this phone and the answers are kept in Advanced.
    func finishOnboarding() {
        let pinned = defaults.bool(forKey: IdentityKeys.onboardingStartedEmpty)
        defaults.removeObject(forKey: IdentityKeys.onboardingStartedEmpty)
        guard pinned, dirtyWhileEmpty, defaults.bool(forKey: IdentityKeys.householdFromCloud),
              let live, let cache = loadHouseholdCache() else { return }
        let report = DiscardedSettings(goal: live.goalSettings, tax: live.taxProfile, at: now())
        defaults.set(try? JSONEncoder().encode(report), forKey: IdentityKeys.discardedOnboardingAnswers)
        defaults.set(true, forKey: IdentityKeys.noticeSettingsKept)
        var tax = cache.tax
        if tax?.displayName == nil { tax?.displayName = live.taxProfile.displayName }
        live.applyRemoteSettings(goal: cache.goal, tax: tax)
        clearDirty()
        Analytics.settingsEmptyEditDiscarded()
        onChange?()
    }

    private var dirtyWhileEmpty: Bool {
        defaults.bool(forKey: IdentityKeys.goalDirtyWhileEmpty) || defaults.bool(forKey: IdentityKeys.taxDirtyWhileEmpty)
    }

    private func clearDirty() {
        for key in [IdentityKeys.goalDirty, IdentityKeys.goalDirtyWhileEmpty, IdentityKeys.taxDirty, IdentityKeys.taxDirtyWhileEmpty] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: S8

    private func writeHousehold(_ snapshot: ZoneSnapshot) async throws {
        guard let live else { return }
        let groups = GroupsFile.load(root: root)
        let householdOwner = snapshot.records.first { $0.recordName == IdentityZone.goalSettingsName(IdentityZone.household) }?.appUserId
        if defaults.bool(forKey: IdentityKeys.accountSwitchKeep) {
            try await writeHouseholdAfterAccountSwitch(snapshot, householdOwner: householdOwner, groups: groups)
            return
        }
        var zoneCounts: [String: Int] = [:]
        for record in snapshot.records where record.recordType == "TimeEntry" {
            let owner = record.appUserId ?? LegacyInventory.unscopedGroupId
            if groups?.group(owner)?.status.isLive ?? true { zoneCounts[owner, default: 0] += 1 }
        }
        zoneCounts[LegacyInventory.unscopedGroupId] = nil
        var excluded = Set((groups?.groups ?? []).filter { $0.status == .aside || $0.status == .pending || $0.splitFromDevice }.map(\.id))
        if groups?.groups.contains(where: { $0.splitFromDevice && $0.id == storageId }) == true { excluded.insert(storageId) }
        var chosen = MergeRules.unifiedId(householdOwner: householdOwner, zoneEntryCounts: zoneCounts,
                                          devicePrimary: groups?.primaryId ?? storageId, excluded: excluded)
        if chosen == LegacyInventory.unscopedGroupId { chosen = IdentityZone.household }
        if let householdOwner, excluded.contains(householdOwner) {
            // The household pair is a set this phone holds apart. Never adopt its id or overwrite
            // its pair; while it is still a question, push nothing of the live set (S9 holds).
            if groups?.group(householdOwner)?.status == .pending {
                defaults.set(householdOwner, forKey: IdentityKeys.householdHeldFor)
                holdHousehold(from: snapshot.records)
            }
            defaults.set(chosen, forKey: IdentityKeys.unifiedId)
            defaults.set(true, forKey: IdentityKeys.unifiedIdDecided)
            return
        }
        let empty = live.liveEntries.isEmpty && live.liveProperties.isEmpty
        if householdOwner == nil && empty && !defaults.bool(forKey: IdentityKeys.goalDirty) && !defaults.bool(forKey: IdentityKeys.taxDirty) {
            // Empty never dictates: nothing written, the next pull brings whatever another device writes.
            defaults.set(chosen, forKey: IdentityKeys.unifiedId)
            defaults.set(true, forKey: IdentityKeys.unifiedIdDecided)
            return
        }
        let goal = live.goalSettings.record(name: IdentityZone.goalSettingsName(IdentityZone.household), owner: chosen)
        let tax = live.taxProfile.record(name: IdentityZone.taxProfileName(IdentityZone.household), owner: chosen)
        switch try await source.saveHousehold(goal: goal, tax: tax) {
        case .saved:
            // This phone's own pair: its echo in the next delta is not "from another device".
            tracker.recordServerState([goal.ckRecord(), tax.ckRecord()])
        case .adopted(let server):
            if excluded.contains(server) {
                // Raced by a set this phone holds apart: keep this phone's id and ask first.
                if groups?.group(server)?.status == .pending { defaults.set(server, forKey: IdentityKeys.householdHeldFor) }
            } else {
                // The loser adopts the winner's id before pushing anything (U17). If S5 never saw
                // that owner and this phone has records, it may be another set that migrated in
                // the same minute: S8b looks at what it brings before anything merges.
                let seen = Set(snapshot.records.compactMap(\.appUserId))
                if !seen.contains(server), !empty {
                    defaults.set(server, forKey: IdentityKeys.adoptedUnseen)
                    defaults.set(chosen, forKey: IdentityKeys.adoptedFrom)
                }
                chosen = server
            }
            Analytics.identitySettingsConflict(adopted: true)
        }
        defaults.set(chosen, forKey: IdentityKeys.unifiedId)
        defaults.set(true, forKey: IdentityKeys.unifiedIdDecided)
    }

    /// S8 after P13 "Keep with this iCloud". This phone's set keeps its own id, unless an owner in
    /// the new zone already uses it (a fresh set is "household" on every account): then it takes
    /// a new one, so the other set's phones see these records as a set to ask about, never as their
    /// own. A household pair already there is the other set's: never adopted, never overwritten.
    private func writeHouseholdAfterAccountSwitch(_ snapshot: ZoneSnapshot, householdOwner: String?, groups: GroupsFile?) async throws {
        guard let live else { return }
        var chosen = unifiedId
        let zoneOwners = Set(snapshot.records.compactMap(\.appUserId))
        if zoneOwners.contains(chosen) || householdOwner == chosen {
            chosen = IdentityZone.household + "-" + UUID().uuidString.prefix(8).lowercased()
        }
        if householdOwner != nil {
            defaults.set(true, forKey: IdentityKeys.householdForeign)
        } else {
            defaults.removeObject(forKey: IdentityKeys.householdForeign)
            let empty = live.liveEntries.isEmpty && live.liveProperties.isEmpty
            if !empty || defaults.bool(forKey: IdentityKeys.goalDirty) || defaults.bool(forKey: IdentityKeys.taxDirty) {
                let goal = live.goalSettings.record(name: IdentityZone.goalSettingsName(IdentityZone.household), owner: chosen)
                let tax = live.taxProfile.record(name: IdentityZone.taxProfileName(IdentityZone.household), owner: chosen)
                if case .adopted = try await source.saveHousehold(goal: goal, tax: tax) {
                    // Another phone of this account wrote it first: it is that set's.
                    defaults.set(true, forKey: IdentityKeys.householdForeign)
                }
            }
        }
        defaults.set(chosen, forKey: IdentityKeys.unifiedId)
        defaults.set(true, forKey: IdentityKeys.unifiedIdDecided)
    }

    // MARK: Pull routing (S8b and every steady-state pull)

    struct PullOutcome: Equatable {
        var liveChanged = 0
        var archived = 0
        var newGroups: [String] = []
        var removed = 0
        var bulkHeld = 0
        var settingsApplied = false
        var dedupedByKey = 0
        var unparsed = 0
    }

    func routingContext() -> MergeRules.RoutingContext {
        var membership: [String: String] = [:]
        for g in earlier.groups {
            for e in g.entries { membership[e.id.uuidString] = g.id }
            for p in g.properties { membership[p.id.uuidString] = g.id }
            for c in g.categories { membership[c.id.uuidString] = g.id }
        }
        let liveNames = Set((live?.liveEntries.map { $0.id.uuidString } ?? []) + (live?.liveProperties.map { $0.id.uuidString } ?? [])
                            + (live?.liveCategories.map { $0.id.uuidString } ?? []))
        let hashes = (defaults.dictionary(forKey: IdentityKeys.deletedRecordHashes) as? [String: String]) ?? [:]
        let deletedMap = (defaults.dictionary(forKey: IdentityKeys.deletedRecordNames) as? [String: Date]) ?? [:]
        let deleted = deletedNames()
        return MergeRules.RoutingContext(liveNames: liveNames, archiveMembership: membership, unifiedId: unifiedId,
                                         groups: GroupsFile.load(root: root), deletedNames: deleted,
                                         tombstones: Set(tracker.pendingDeletes), deletedHashes: hashes.filter { deleted.contains($0.key) },
                                         deletedAt: deletedMap.filter { deleted.contains($0.key) })
    }

    /// `deleteReason`: `.deletedElsewhere` for delete callbacks (30 days); `.inferredAbsent` for
    /// the absences a whole-zone read found after `changeTokenExpired` (kept until the person acts).
    @discardableResult
    func applyPull(_ delta: ZoneDelta, deleteReason: RemovalReason = .deletedElsewhere) -> PullOutcome {
        var outcome = PullOutcome()
        guard let live else { return outcome }
        let context = routingContext()
        var entries = live.liveEntries, properties = live.liveProperties, categories = live.liveCategories
        var groups = GroupsFile.load(root: root) ?? GroupsFile(createdAt: now(), primaryId: nil, groups: [])
        var pulledForBaseline: [ZoneRecord] = []
        var household: (goal: ZoneRecord?, tax: ZoneRecord?) = (nil, nil)
        var mirror: (goal: ZoneRecord?, tax: ZoneRecord?) = (nil, nil)
        var putBackElsewhere = Set<String>()
        // Last writer wins, but an edit made here and never pushed is not dropped (Recently removed).
        var replaced: [RemovedRecord] = []
        let baselineTracker = tracker
        func isUnpushed(_ record: CKRecord) -> Bool { !baselineTracker.changedRecords([record]).isEmpty }

        for record in delta.changed {
            if record.isSettings {
                if record.recordName == IdentityZone.goalSettingsName(IdentityZone.household) { household.goal = record }
                if record.recordName == IdentityZone.taxProfileName(IdentityZone.household) { household.tax = record }
                if unifiedId != IdentityZone.household {
                    if record.recordName == IdentityZone.goalSettingsName(unifiedId) { mirror.goal = record }
                    if record.recordName == IdentityZone.taxProfileName(unifiedId) { mirror.tax = record }
                }
                continue
            }
            guard record.isUserRecord else { continue }
            switch MergeRules.route(record, context: context) {
            case .ignore:
                continue
            case .live:
                guard record.isParseable else {
                    earlier.route(unparsed: [record], to: record.appUserId ?? unifiedId, status: .combine, source: .iCloud, now: now())
                    outcome.unparsed += 1
                    continue
                }
                if var entry = record.entry {
                    entry = MergeRules.keepingLocalAttachments([entry], from: entries)[0]
                    if let match = MergeRules.liveMatch(forPulled: entry, in: entries) {
                        // R19: the same calendar event under another id; never a second entry. A
                        // newer edit made there lands on the live entry instead of being dropped.
                        outcome.dedupedByKey += 1
                        if entry.modifiedAt > match.modifiedAt, let i = entries.firstIndex(where: { $0.id == match.id }),
                           let adopted = MergeRules.adoptEdit(entry, into: match) {
                            if isUnpushed(CloudKitSyncService.record(for: match, zoneID: IdentityZone.zoneID, appUserId: unifiedId)) {
                                replaced.append(RemovedRecord(name: match.id.uuidString, reason: .replacedByNewer, removedAt: now(),
                                                              keepUntil: now().addingTimeInterval(EarlierRecordsStore.userDeleteRetention), entry: match))
                            }
                            entries[i] = adopted
                            outcome.liveChanged += 1
                        }
                        continue
                    }
                    if let local = entries.first(where: { $0.id == entry.id }), entry.modifiedAt > local.modifiedAt,
                       local.ledgerVersion != entry.ledgerVersion,
                       isUnpushed(CloudKitSyncService.record(for: local, zoneID: IdentityZone.zoneID, appUserId: unifiedId)) {
                        replaced.append(RemovedRecord(name: local.id.uuidString, reason: .replacedByNewer, removedAt: now(),
                                                      keepUntil: now().addingTimeInterval(EarlierRecordsStore.userDeleteRetention), entry: local))
                    }
                    entries = MergeRules.union(entries, [entry])
                } else if let property = record.property {
                    if let local = properties.first(where: { $0.id == property.id }), property.modifiedAt > local.modifiedAt,
                       local.ledgerVersion != property.ledgerVersion,
                       isUnpushed(CloudKitSyncService.record(for: local, zoneID: IdentityZone.zoneID, appUserId: unifiedId)) {
                        replaced.append(RemovedRecord(name: local.id.uuidString, reason: .replacedByNewer, removedAt: now(),
                                                      keepUntil: now().addingTimeInterval(EarlierRecordsStore.userDeleteRetention), property: local))
                    }
                    properties = MergeRules.union(properties, [property])
                } else if let category = record.category {
                    if let local = categories.first(where: { $0.id == category.id }), category.modifiedAt > local.modifiedAt,
                       local.ledgerVersion != category.ledgerVersion,
                       isUnpushed(CloudKitSyncService.record(for: local, zoneID: IdentityZone.zoneID, appUserId: unifiedId)) {
                        replaced.append(RemovedRecord(name: local.id.uuidString, reason: .replacedByNewer, removedAt: now(),
                                                      keepUntil: now().addingTimeInterval(EarlierRecordsStore.userDeleteRetention), category: local))
                    }
                    categories = MergeRules.union(categories, [category])
                }
                pulledForBaseline.append(record)
                outcome.liveChanged += 1
                if context.deletedNames.contains(record.recordName) { putBackElsewhere.insert(record.recordName) }
            case .archive(let id):
                let held = earlier.group(id)?.status ?? groups.group(id)?.status
                earlier.route(entries: record.entry.map { [$0] } ?? [], properties: record.property.map { [$0] } ?? [],
                              categories: record.category.map { [$0] } ?? [], unparsed: record.isParseable ? [] : [record],
                              to: id, status: held == .pending ? .pending : .aside, source: .iCloud, now: now())
                outcome.archived += 1
            case .newGroup(let owner):
                guard !LegacyInventory.isIgnoredId(owner) else { continue }
                earlier.route(entries: record.entry.map { [$0] } ?? [], properties: record.property.map { [$0] } ?? [],
                              categories: record.category.map { [$0] } ?? [], unparsed: record.isParseable ? [] : [record],
                              to: owner, status: .pending, source: .iCloud, now: now())
                if groups.group(owner) == nil || groups.group(owner)?.status == .notNeeded {
                    groups.upsert(GroupRecord(id: owner, status: .pending, source: .iCloud, entryCount: 0, propertyCount: 0, hours: 0, lastEntryDate: nil))
                    outcome.newGroups.append(owner)
                }
            }
        }

        // Deletes: never straight to the bin (v4 3c). More than half the live set → ask first.
        let liveNames = Set(entries.map { $0.id.uuidString } + properties.map { $0.id.uuidString } + categories.map { $0.id.uuidString })
        let liveDeletes = Set(delta.deleted.keys).intersection(liveNames)
        if MergeRules.isBulkDelete(deleting: liveDeletes.count, liveCount: liveNames.count) {
            let heldHours = entries.filter { liveDeletes.contains($0.id.uuidString) }.reduce(0) { $0 + $1.hours }
            earlier.setBulkHold(BulkHold(names: liveDeletes, totalLive: liveNames.count, heldHours: heldHours,
                                         totalHours: entries.reduce(0) { $0 + $1.hours }, createdAt: now(), fromPulledDeletes: true))
            outcome.bulkHeld = liveDeletes.count
            Analytics.bulkPromptShown(count: liveDeletes.count)
        } else if !liveDeletes.isEmpty {
            earlier.remove(removedCopies(liveDeletes, entries: entries, properties: properties, categories: categories,
                                         reason: deleteReason, group: nil))
            entries.removeAll { liveDeletes.contains($0.id.uuidString) }
            // A deleted property takes its entries with it on every device; keep them in Recently removed too.
            let deletedProperties = Set(properties.filter { liveDeletes.contains($0.id.uuidString) }.map(\.id))
            if !deletedProperties.isEmpty {
                let orphans = Set(entries.filter { deletedProperties.contains($0.propertyId) }.map { $0.id.uuidString })
                earlier.remove(removedCopies(orphans, entries: entries, properties: [], categories: [], reason: .deletedElsewhere, group: nil))
                entries.removeAll { orphans.contains($0.id.uuidString) }
            }
            properties.removeAll { liveDeletes.contains($0.id.uuidString) }
            categories.removeAll { liveDeletes.contains($0.id.uuidString) }
            noteDeleted(liveDeletes)
            outcome.removed = liveDeletes.count
        }
        // Deletes of archived records: out of the archive, into Recently removed.
        for (name, _) in delta.deleted where !liveNames.contains(name) {
            guard let groupId = earlier.groupId(containing: name), let group = earlier.group(groupId) else { continue }
            var g = group
            let removed = removedCopies([name], entries: g.entries, properties: g.properties, categories: g.categories, reason: .deletedElsewhere, group: groupId)
            earlier.remove(removed)
            g.entries.removeAll { $0.id.uuidString == name }
            g.properties.removeAll { $0.id.uuidString == name }
            g.categories.removeAll { $0.id.uuidString == name }
            earlier.removeGroup(groupId)
            if !g.isEmpty { try? earlier.save(g) }
        }

        if outcome.liveChanged > 0 || outcome.removed > 0 {
            live.replaceLive(entries: entries, properties: properties, categories: categories)
        }
        if !replaced.isEmpty { earlier.remove(replaced) }
        if !putBackElsewhere.isEmpty {
            // Put back on another device: live here again, so it leaves Recently removed and R11.
            earlier.takeRemoved(putBackElsewhere)
            forgetDeleted(putBackElsewhere)
        }
        try? groups.save(root: root)

        // Settings: only the household pair and the 2.0 mirror (§3.3). Another set's pair (kept with
        // this iCloud after an account change) is never applied.
        if defaults.bool(forKey: IdentityKeys.householdForeign) { household = (nil, nil) }
        if let owner = (household.goal ?? household.tax)?.appUserId, owner != unifiedId, Self.heldApart(groups.group(owner)?.status) {
            household = (nil, nil)
        }
        if household.goal != nil || household.tax != nil {
            let cached = loadHouseholdCache()
            rememberHousehold(goal: household.goal.map(GoalSettingsValues.init(record:)) ?? cached?.goal,
                              tax: household.tax.map(TaxProfileValues.init(record:)) ?? cached?.tax)
            // The set's own pair, written by another device (not this phone's last push, which is
            // the baseline): onboarding answers made while empty never overwrite it.
            let fromAnotherDevice = [household.goal, household.tax].compactMap { $0 }
                .contains { $0.appUserId == unifiedId && !tracker.changedRecords([$0.ckRecord()]).isEmpty }
            if fromAnotherDevice { defaults.set(true, forKey: IdentityKeys.householdFromCloud) }
        }
        var goalRecord = household.goal, taxRecord = household.tax
        if MergeRules.mirrorBeatsHousehold(mirror: mirror.goal?.modificationDate, household: household.goal?.modificationDate), mirror.goal != nil {
            goalRecord = mirror.goal
        }
        if MergeRules.mirrorBeatsHousehold(mirror: mirror.tax?.modificationDate, household: household.tax?.modificationDate), mirror.tax != nil {
            taxRecord = mirror.tax
        }
        let goalDirty = defaults.bool(forKey: IdentityKeys.goalDirty)
        let taxDirty = defaults.bool(forKey: IdentityKeys.taxDirty)
        let applyGoal = goalRecord.flatMap { goalDirty ? nil : GoalSettingsValues(record: $0) }
        var applyTax = taxRecord.flatMap { taxDirty ? nil : TaxProfileValues(record: $0) }
        if applyTax?.displayName == nil { applyTax?.displayName = live.taxProfile.displayName }
        if applyGoal != nil || applyTax != nil {
            live.applyRemoteSettings(goal: applyGoal, tax: applyTax)
            outcome.settingsApplied = true
        }

        // The server's copy becomes the baseline (records the merge kept newer still differ and push).
        let t = tracker
        var baselines = pulledForBaseline.map { $0.ckRecord() }
        if applyGoal != nil, let goalRecord { baselines.append(live.goalSettings.record(name: goalRecord.recordName, owner: goalRecord.appUserId).ckRecord()) }
        if applyTax != nil, let taxRecord { baselines.append(live.taxProfile.record(name: taxRecord.recordName, owner: taxRecord.appUserId).ckRecord()) }
        t.recordServerState(baselines)
        t.forget(recordNames: Array(liveDeletes))
        if !outcome.newGroups.isEmpty || outcome.bulkHeld > 0 || outcome.archived > 0 || outcome.removed > 0 { onChange?() }
        return outcome
    }

    // MARK: S9 / steady-state push

    /// The live set as zone records under the unified id, plus the household pair (+ mirror).
    func liveZoneRecords() -> [ZoneRecord] {
        guard let live else { return [] }
        let owner = unifiedId
        var records = live.liveProperties.map { ZoneRecord(CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: owner)) }
        records += live.liveEntries.map { ZoneRecord(CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: owner)) }
        records += live.liveCategories.map { ZoneRecord(CloudKitSyncService.record(for: $0, zoneID: IdentityZone.zoneID, appUserId: owner)) }
        let empty = live.liveEntries.isEmpty && live.liveProperties.isEmpty
        let dirty = defaults.bool(forKey: IdentityKeys.goalDirty) || defaults.bool(forKey: IdentityKeys.taxDirty)
        // Answers from an onboarding that started empty never overwrite a household another device
        // wrote (`finishOnboarding` puts the household back and keeps the answers for P29).
        let heldOnboarding = dirtyWhileEmpty && defaults.bool(forKey: IdentityKeys.householdFromCloud)
        if (!empty || dirty || defaults.bool(forKey: IdentityKeys.hasSynced)) && !heldOnboarding {
            if !defaults.bool(forKey: IdentityKeys.householdForeign) {
                records.append(live.goalSettings.record(name: IdentityZone.goalSettingsName(IdentityZone.household), owner: owner))
                records.append(live.taxProfile.record(name: IdentityZone.taxProfileName(IdentityZone.household), owner: owner))
            }
            if owner != IdentityZone.household {
                // 2.0.x devices on this id follow the household through the mirror (§3.2).
                records.append(live.goalSettings.record(name: IdentityZone.goalSettingsName(owner), owner: owner))
                records.append(live.taxProfile.record(name: IdentityZone.taxProfileName(owner), owner: owner))
            }
        }
        return records
    }

    /// Pushes tombstones, then only what changed (per record type; one failing type never blocks
    /// the others). Held (bulk) records are not pushed until answered.
    @discardableResult
    func pushLive() async -> ZonePushReport {
        if let held = defaults.string(forKey: IdentityKeys.householdHeldFor) {
            if GroupsFile.load(root: root)?.group(held)?.status == .pending { return ZonePushReport() }
            defaults.removeObject(forKey: IdentityKeys.householdHeldFor)
        }
        let t = tracker
        let held = earlier.bulkHold?.names ?? []
        let all = liveZoneRecords().filter { !held.contains($0.recordName) }
        t.cancelTombstones(for: Set(all.map(\.recordName)))
        let deletes = t.pendingDeletes
        let changed = t.changedRecords(all.map { $0.ckRecord() }).map(ZoneRecord.init)
        guard !changed.isEmpty || !deletes.isEmpty else { return ZonePushReport() }
        let report = await source.push(changed, deletes: deletes)
        t.clearTombstones(Array(report.deletedNames))
        t.recordServerState(changed.filter { report.savedNames.contains($0.recordName) }.map { $0.ckRecord() })
        if report.savedNames.contains(IdentityZone.goalSettingsName(IdentityZone.household)) {
            defaults.removeObject(forKey: IdentityKeys.goalDirty); defaults.removeObject(forKey: IdentityKeys.goalDirtyWhileEmpty)
        }
        if report.savedNames.contains(IdentityZone.taxProfileName(IdentityZone.household)) {
            defaults.removeObject(forKey: IdentityKeys.taxDirty); defaults.removeObject(forKey: IdentityKeys.taxDirtyWhileEmpty)
        }
        for (type, code) in report.failedTypes { Analytics.syncPushFailed(recordType: type, code: code) }
        if report.quotaExceeded {
            defaults.set(String(localized: "iCloud is full. Your records are safe on this iPhone; free up iCloud space to keep syncing.", table: "Identity"),
                         forKey: IdentityKeys.lastSyncProblem)
        } else if report.failedTypes.isEmpty {
            defaults.removeObject(forKey: IdentityKeys.lastSyncProblem)
        }
        return report
    }

    /// Device-only records of archive groups go to iCloud once, under `aside-<id>` (R10).
    func pushArchives(_ snapshot: ZoneSnapshot?) async {
        let present = snapshot?.presentNames ?? []
        for group in earlier.groups where group.status == .pending || group.status == .aside {
            var records: [ZoneRecord] = []
            let owner = IdentityZone.asidePrefix + group.id
            for p in group.properties where !present.contains(p.id.uuidString) && !group.pushedAsideNames.contains(p.id.uuidString) {
                records.append(ZoneRecord(CloudKitSyncService.record(for: p, zoneID: IdentityZone.zoneID, appUserId: owner)))
            }
            for e in group.entries where !present.contains(e.id.uuidString) && !group.pushedAsideNames.contains(e.id.uuidString) {
                records.append(ZoneRecord(CloudKitSyncService.record(for: e, zoneID: IdentityZone.zoneID, appUserId: owner)))
            }
            for c in group.categories where !present.contains(c.id.uuidString) && !group.pushedAsideNames.contains(c.id.uuidString) {
                records.append(ZoneRecord(CloudKitSyncService.record(for: c, zoneID: IdentityZone.zoneID, appUserId: owner)))
            }
            guard !records.isEmpty else { continue }
            let report = await source.push(records, deletes: [])
            earlier.markPushedAside(report.savedNames, group: group.id)
        }
    }

    // MARK: Deleted names (R11)

    func deletedNames() -> Set<String> {
        let map = (defaults.dictionary(forKey: IdentityKeys.deletedRecordNames) as? [String: Date]) ?? [:]
        let cutoff = now().addingTimeInterval(-90 * 86_400)
        return Set(map.filter { $0.value > cutoff }.keys)
    }

    /// R11: these names were deleted. `hashes` names the deleted versions; any not given are
    /// looked up in the live set and Recently removed (the deleted copy is in one of them).
    func noteDeleted(_ names: Set<String>, hashes given: [String: String] = [:]) {
        var map = (defaults.dictionary(forKey: IdentityKeys.deletedRecordNames) as? [String: Date]) ?? [:]
        let cutoff = now().addingTimeInterval(-90 * 86_400)
        map = map.filter { $0.value > cutoff }
        for name in names { map[name] = now() }
        defaults.set(map, forKey: IdentityKeys.deletedRecordNames)
        var known: [String: String] = [:]
        if let live {
            for e in live.liveEntries where names.contains(e.id.uuidString) { known[e.id.uuidString] = RecordLedger.version(e).hash }
            for p in live.liveProperties where names.contains(p.id.uuidString) { known[p.id.uuidString] = RecordLedger.version(p).hash }
            for c in live.liveCategories where names.contains(c.id.uuidString) { known[c.id.uuidString] = RecordLedger.version(c).hash }
        }
        for r in earlier.removed where names.contains(r.name) { if let v = r.version { known[r.name] = v.hash } }
        // Last resort: the version this phone held at its last merge (the ledger's after-cloud copy).
        for v in LedgerSnapshot.load("v2-after-cloud.json", root: root)?.live ?? [] where names.contains(v.name) && known[v.name] == nil {
            known[v.name] = v.hash
        }
        known.merge(given) { _, new in new }
        var stored = (defaults.dictionary(forKey: IdentityKeys.deletedRecordHashes) as? [String: String]) ?? [:]
        stored = stored.filter { map[$0.key] != nil }
        for name in names { stored[name] = known[name] }
        defaults.set(stored, forKey: IdentityKeys.deletedRecordHashes)
    }

    /// Put back here or on another device: no longer deleted (R11).
    func forgetDeleted(_ names: Set<String>) {
        var map = (defaults.dictionary(forKey: IdentityKeys.deletedRecordNames) as? [String: Date]) ?? [:]
        var hashes = (defaults.dictionary(forKey: IdentityKeys.deletedRecordHashes) as? [String: String]) ?? [:]
        for name in names { map[name] = nil; hashes[name] = nil }
        defaults.set(map, forKey: IdentityKeys.deletedRecordNames)
        defaults.set(hashes, forKey: IdentityKeys.deletedRecordHashes)
    }

    // MARK: Zone gone (P31) — never recreate on our own

    func handleZoneGone() -> CloudOutcome {
        if IdentityKeys.knowsZone(defaults) {
            defaults.set(true, forKey: IdentityKeys.zoneGone)
            Analytics.zoneGonePromptShown()
            onChange?()
            return .zoneGone
        }
        // Never seen: the zone simply doesn't exist yet. The source creates it on the next push.
        return .pushFailed("zone_missing")
    }
}

/// The onboarding answers that lost to the household pair (P29, Settings › Advanced).
struct DiscardedSettings: Codable, Equatable {
    var goal: GoalSettingsValues
    var tax: TaxProfileValues
    var at: Date
}

extension LedgerSnapshot {
    static func load(_ name: String, root: URL) -> LedgerSnapshot? {
        (try? Data(contentsOf: url(name, root: root))).flatMap { try? JSONDecoder.identity.decode(LedgerSnapshot.self, from: $0) }
    }
}

extension EarlierRecordsStore {
    func removedSnapshot() throws -> Data { try JSONEncoder.identity.encode(removed.map { [$0.name, $0.reason.rawValue] }) }
}
