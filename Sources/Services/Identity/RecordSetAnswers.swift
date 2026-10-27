import Foundation

// MARK: - The person's answers: two sets, spouse, aside, put back, bulk, zone gone, account
//
// Every answer is recorded in groups.json before any merge write (§3.3), and every one can be
// walked back: combine → the backup; spouse → Undo for 30 days; aside → "Add to my records";
// removed → Put back.

enum TwoSetsAnswer: String, Codable {
    case combine
    case spouse
    case aside
}

enum BulkAnswer: String { case keep, remove }
enum ZoneGoneAnswer: String { case keepAndRestore, deleteHere }
enum AccountChangedAnswer: String { case keepWithThisICloud, useThisICloud, later }

extension RecordSetMigration {

    private func updateGroup(_ id: String, _ change: (inout GroupRecord) -> Void) {
        var file = GroupsFile.load(root: root) ?? GroupsFile(createdAt: now(), primaryId: storageId, groups: [])
        var record = file.group(id) ?? GroupRecord(id: id, status: .pending, source: .device, entryCount: 0, propertyCount: 0, hours: 0, lastEntryDate: nil)
        change(&record)
        file.upsert(record)
        try? file.save(root: root)
    }

    /// P4: the answer for one held group.
    func answer(_ answer: TwoSetsAnswer, group id: String) {
        earlier.reload()
        guard let live, let group = earlier.group(id) else { return }
        let at = now()
        // The answer is written first; a crash after this re-applies the same merge.
        updateGroup(id) { r in
            r.answeredAt = at
            switch answer {
            case .combine: r.status = .combine; r.undoUntil = nil
            case .spouse: r.status = .spouse; r.undoUntil = at.addingTimeInterval(EarlierRecordsStore.spouseUndoWindow)
            case .aside: r.status = .aside; r.undoUntil = nil
            }
        }
        Analytics.mergeQuestionAnswered(answer.rawValue)
        switch answer {
        case .aside:
            try? earlier.setStatus(.aside, for: id)
        case .combine, .spouse:
            let liveIds = Set(live.liveEntries.map(\.id))
            let incoming = answer == .spouse
                ? group.entries.flatMap { e in liveIds.contains(e.id) ? MergeRules.swapParticipants([e]) : MergeRules.swapParticipants([e], editedAt: at) }
                : group.entries
            let e = MergeRules.unionReporting(live.liveEntries, incoming)
            let p = MergeRules.unionReporting(live.liveProperties, group.properties)
            let c = MergeRules.unionReporting(live.liveCategories, group.categories)
            let deduped = MergeRules.dedupeBySourceKey(e.merged)
            writeLosers(e.losers.map(\.ledgerVersion) + p.losers.map(\.ledgerVersion) + c.losers.map(\.ledgerVersion)
                        + deduped.losers.map(\.ledgerVersion), tag: "answer-\(id)")
            live.replaceLive(entries: deduped.merged, properties: p.merged, categories: c.merged)
            // The set's capture inbox, pending deletes and queued "Log it" taps join the live ones (U33/U34/U36).
            Self.mergeCaptureFiles(from: [id], into: storageId, root: root)
            if let contents = Self.trackerContents(id, root: root), let deletes = contents.pendingDeletes, !deletes.isEmpty {
                tracker.addTombstones(deletes)
            }
            Self.rekeyQueuedActions(from: [id], to: storageId, defaults: defaults)
            if answer == .spouse {
                // Kept for Undo (P17); the group's own settings are discarded (R9).
                try? earlier.setStatus(.spouse, for: id)
                var tax = live.taxProfile
                tax.spouseTracking = true
                live.applyRemoteSettings(goal: nil, tax: tax)
                defaults.set(true, forKey: IdentityKeys.taxDirty)
            } else {
                earlier.removeGroup(id)
            }
            // The combined records have no baseline under the unified id: the next push sends them.
        }
        onChange?()
    }

    /// P17 "Undo": the spouse group's entries leave the live set and wait for an answer again.
    /// Nothing is deleted, here or in iCloud: the hours go back to the group as they are now
    /// (edits made since the answer included, participants swapped back), and their iCloud
    /// copies go back under the group's own tag on the next push (`pushRetags`), so every other
    /// device and a new phone still hold them.
    func undoSpouse(group id: String) {
        earlier.reload()
        guard let live, var group = earlier.group(id), group.status == .spouse else { return }
        let names = Set(group.entries.map { $0.id.uuidString })
        let current = live.liveEntries.filter { names.contains($0.id.uuidString) }
        group.entries = MergeRules.union(group.entries, MergeRules.swapParticipants(current))
        group.status = .pending
        group.retagPending = (group.retagPending ?? []).union(Set(current.map { $0.id.uuidString }))
        do {
            try earlier.save(group)
        } catch {
            // The archive copy couldn't be written: keep them live rather than risk them.
            return
        }
        live.replaceLive(entries: live.liveEntries.filter { !names.contains($0.id.uuidString) },
                         properties: live.liveProperties, categories: live.liveCategories)
        // Not live any more: no baseline, and never a tombstone.
        tracker.forget(recordNames: Array(names))
        updateGroup(id) { $0.status = .pending; $0.undoUntil = nil; $0.answeredAt = nil }
        onChange?()
    }

    /// "Add to my records" for an aside group: it goes back to the question (R10).
    func reconsider(group id: String) {
        try? earlier.setStatus(.pending, for: id)
        updateGroup(id) { $0.status = .pending }
        onChange?()
    }

    /// P19: delete one earlier group from iCloud and this iPhone. Can't be undone.
    func deleteGroup(_ id: String) async {
        guard let group = earlier.group(id) else { return }
        let names = group.entries.map { $0.id.uuidString } + group.properties.map { $0.id.uuidString }
            + group.categories.map { $0.id.uuidString } + group.unparsedRecords.map(\.recordName)
        if !names.isEmpty, await source.accountState() == .available, await confirmAccount() == .same {
            _ = await source.push([], deletes: names)
        }
        earlier.removeGroup(id)
        updateGroup(id) { $0.status = .notNeeded; $0.entryCount = 0; $0.propertyCount = 0; $0.hours = 0 }
        onChange?()
    }

    /// P18 "Put back": the records return to the live set and are pushed as new. Putting back is
    /// an edit made now: the copies are stamped now, so the devices that saw the delete take them
    /// back (R11 ignores only copies older than the delete).
    func putBack(_ names: Set<String>) {
        guard let live else { return }
        let taken = earlier.takeRemoved(names)
        guard !taken.isEmpty else { return }
        let at = now()
        func stamped<T: IdentityRecord>(_ records: [T], _ stamp: (inout T) -> Void) -> [T] {
            records.map { var r = $0; stamp(&r); return r }
        }
        let entries = stamped(taken.compactMap(\.entry)) { $0.modifiedAt = max($0.modifiedAt, at) }
        let properties = stamped(taken.compactMap(\.property)) { $0.modifiedAt = max($0.modifiedAt, at) }
        let categories = stamped(taken.compactMap(\.category)) { $0.modifiedAt = max($0.modifiedAt, at) }
        live.replaceLive(entries: MergeRules.union(live.liveEntries, entries),
                         properties: MergeRules.union(live.liveProperties, properties),
                         categories: MergeRules.union(live.liveCategories, categories))
        var map = (defaults.dictionary(forKey: IdentityKeys.deletedRecordNames) as? [String: Date]) ?? [:]
        for name in names { map[name] = nil }
        defaults.set(map, forKey: IdentityKeys.deletedRecordNames)
        tracker.forget(recordNames: Array(names))
        tracker.cancelTombstones(for: names)
        onChange?()
    }

    /// P28: keep (push as new) or remove (Recently removed, kept until the person acts).
    func answerBulk(_ answer: BulkAnswer) {
        guard let live, let hold = earlier.bulkHold else { return }
        switch answer {
        case .keep:
            tracker.forget(recordNames: Array(hold.names))
            Analytics.bulkAnswered(kept: true, count: hold.names.count)
        case .remove:
            let at = now()
            let entries = live.liveEntries, properties = live.liveProperties, categories = live.liveCategories
            let removed = entries.filter { hold.names.contains($0.id.uuidString) }.map { RemovedRecord(name: $0.id.uuidString, reason: .bulkRemoved, removedAt: at, keepUntil: nil, entry: $0) }
                + properties.filter { hold.names.contains($0.id.uuidString) }.map { RemovedRecord(name: $0.id.uuidString, reason: .bulkRemoved, removedAt: at, keepUntil: nil, property: $0) }
                + categories.filter { hold.names.contains($0.id.uuidString) }.map { RemovedRecord(name: $0.id.uuidString, reason: .bulkRemoved, removedAt: at, keepUntil: nil, category: $0) }
            earlier.remove(removed)
            live.replaceLive(entries: entries.filter { !hold.names.contains($0.id.uuidString) },
                             properties: properties.filter { !hold.names.contains($0.id.uuidString) },
                             categories: categories.filter { !hold.names.contains($0.id.uuidString) })
            if hold.fromPulledDeletes { noteDeleted(hold.names) }
            tracker.forget(recordNames: Array(hold.names))
            Analytics.bulkAnswered(kept: false, count: hold.names.count)
        }
        earlier.setBulkHold(nil)
        onChange?()
    }

    /// P31: the zone was deleted on another device.
    func answerZoneGone(_ answer: ZoneGoneAnswer) async -> Bool {
        Analytics.zoneGoneAnswered(answer.rawValue)
        switch answer {
        case .keepAndRestore:
            // Restore only into the account this phone's set came from.
            guard await confirmAccount() == .same else { onChange?(); return false }
            defaults.removeObject(forKey: IdentityKeys.zoneGone)
            IdentityKeys.forgetZone(defaults)
            // The person chose to put this iPhone’s copy back: the zone is created for that, here.
            do { try await source.ensureZone() } catch { onChange?(); return false }
            defaults.set(true, forKey: IdentityKeys.zoneSeen)
            tracker.resetBaselines()
            let report = await pushLive()
            onChange?()
            return !report.zoneGone && report.failedTypes.isEmpty
        case .deleteHere:
            defaults.removeObject(forKey: IdentityKeys.zoneGone)
            onChange?()
            return true
        }
    }

    /// P13: this iPhone is signed in to a different iCloud account now.
    func answerAccountChanged(_ answer: AccountChangedAnswer) async -> CloudOutcome {
        guard answer != .later else { return .accountChanged }
        let newUser = await source.userRecordName()
        defaults.removeObject(forKey: IdentityKeys.accountChanged)
        if let newUser { defaults.set(newUser, forKey: IdentityKeys.icloudUserRecordName) }
        tracker.resetBaselines()
        IdentityKeys.forgetZone(defaults)   // another account's zone: this device never saw it
        defaults.removeObject(forKey: IdentityKeys.unifiedIdDecided)
        defaults.removeObject(forKey: IdentityKeys.householdForeign)
        accountMayHaveChanged()
        if answer == .keepWithThisICloud {
            // Whatever is already in this iCloud is asked about, never merged by its tag (§1.4).
            defaults.set(true, forKey: IdentityKeys.accountSwitchKeep)
        } else {
            defaults.removeObject(forKey: IdentityKeys.accountSwitchKeep)
        }
        if answer == .useThisICloud, let live {
            // This iPhone's set goes to Earlier records (nothing deleted); the new account's records come in.
            let id = "this-iphone-" + ISO8601DateFormatter().string(from: now()).prefix(10)
            try? earlier.save(ArchivedGroup(id: String(id), status: .aside, source: .device, entries: live.liveEntries,
                                            properties: live.liveProperties, categories: live.liveCategories, createdAt: now()))
            updateGroup(String(id)) { $0.status = .aside; $0.source = .device; $0.entryCount = live.liveEntries.count
                $0.propertyCount = live.liveProperties.count; $0.hours = live.liveEntries.reduce(0) { $0 + $1.hours } }
            live.replaceLive(entries: [], properties: [], categories: [])
        }
        try? FileManager.default.removeItem(at: ZoneSnapshot.url(root: root))
        Self.setStep(.deviceMerged, defaults)
        onChange?()
        return await runCloudPhase()
    }

    /// Onboarding finished (or was left).
    func finishOnboarding() {}

    static func trackerContents(_ id: String, root: URL) -> SyncChangeTracker.Contents? {
        let url = SuggestionStore.directory(forUserId: id, baseDirectory: root.appendingPathComponent("Sync", isDirectory: true))
            .appendingPathComponent("pushed-fingerprints.json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SyncChangeTracker.Contents.self, from: $0) }
    }

    private func writeLosers(_ versions: [RecordVersion], tag: String) {
        guard !versions.isEmpty else { return }
        let url = MigrationFiles.migrationDirectory(root: root).appendingPathComponent("\(tag)-losers.json")
        try? MigrationFiles.writeDurably(JSONEncoder.identity.encode(versions), to: url)
    }
}
