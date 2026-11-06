import Foundation

// MARK: - Confirm-first capture
//
// The ONLY path from a suggestion to a tax record. Idempotent on the suggestion's sourceKey:
// the entry id is derived from the profile id + key (`CaptureIdentity`), so a double tap, a repeated
// notification action, or the same event confirmed on iPhone and iPad all produce one entry
// (and one CloudKit record).

enum CaptureConfirmResult: Equatable {
    /// A new entry was saved.
    case created(entryId: UUID)
    /// The suggestion was already recorded (earlier confirm, another device, or a matching
    /// 1.x import). Nothing new was saved.
    case alreadyRecorded(entryId: UUID)
    /// Required values are missing; the confirm sheet must ask for them.
    case needsInput(missing: Set<CaptureConfirmField>)

    var entryId: UUID? {
        switch self {
        case .created(let id): return id
        case .alreadyRecorded(let id): return id
        case .needsInput: return nil
        }
    }
}

enum CaptureConfirmField: String, Hashable, CaseIterable {
    /// No active profile to record into.
    case profile
    case property
    case category
    case hours
    /// The plan does not allow another entry (`canAddTimeEntry()`; WP-P owns the free-tier rules).
    case plan
}

extension AppViewModel {
    /// Turns a suggestion into a TimeEntry. Safe to call any number of times.
    ///
    /// Write order: the entry is saved first, then the suggestion is marked. If the process
    /// dies between the two, the next call finds the entry by its derived id and only marks
    /// the suggestion — it never saves a second entry.
    @discardableResult
    func confirm(
        _ suggestion: Suggestion,
        edits: SuggestionEdits = SuggestionEdits(),
        store: SuggestionStore? = nil,
        profileId: String? = nil,
        now: Date = Date()
    ) -> CaptureConfirmResult {
        guard let profileId = profileId ?? store?.userId ?? UserScope.userId else {
            return .needsInput(missing: [.profile])
        }
        let entryId = suggestion.entryId(profileId: profileId)

        if let existing = CaptureReconciler.confirmedEntry(for: suggestion, profileId: profileId, in: timeEntries)
            ?? CaptureReconciler.legacyImportMatch(
                for: suggestion, in: timeEntries,
                excluding: store?.claimedEntryIds(excludingKey: suggestion.sourceKey) ?? []
            ) {
            store?.markConfirmed(key: suggestion.sourceKey, entryId: existing.id)
            return .alreadyRecorded(entryId: existing.id)
        }

        // Free-tier limits hook in here (WP-P writes the rules in canAddTimeEntry()).
        guard canAddTimeEntry() else { return .needsInput(missing: [.plan]) }

        let propertyId = edits.propertyId ?? suggestion.proposedPropertyId
        let category = edits.category ?? suggestion.proposedCategory
        let hours = edits.hours ?? suggestion.proposedHours

        var missing = Set<CaptureConfirmField>()
        if propertyId == nil || !properties.contains(where: { $0.id == propertyId }) { missing.insert(.property) }
        if category == nil { missing.insert(.category) }
        if (hours ?? 0) <= 0 { missing.insert(.hours) }
        guard missing.isEmpty, let propertyId, let category, let hours else {
            return .needsInput(missing: missing)
        }

        let houseHoursBefore = houseCountableHours()
        let source = suggestion.kind.entrySource
        let isCalendar = suggestion.kind == .calendar
        let entry = TimeEntry(
            id: entryId,
            propertyId: propertyId,
            participant: edits.participant ?? .selfParticipant,
            category: category,
            hours: hours,
            date: edits.date ?? suggestion.start,
            // 1.1 compatibility: a 1.1 device's calendar import skips an event when an entry
            // with importSource "calendar" has importExternalId == the event's eventIdentifier,
            // OR has the same property, category, hours (±0.01), start (±60 s) and notes equal
            // to the event title (case-insensitive), with no conflicting importCalendarId
            // (AppViewModel.importCalendarEntries / isDuplicateCalendarEntry). So calendar
            // importExternalId trade-off: 1.x only knows the series-wide eventIdentifier (no
            // per-occurrence id exists), so after one occurrence of a series is confirmed a 1.1
            // device skips the rest of that series. We keep writing it, exactly as 1.x would,
            // because the safe error for tax hours is a missed suggestion (the user can log it
            // by hand), not a double count. Dropping it would leave only the fuzzy match, which
            // a differing category or property on the 1.1 device defeats.
            // Calendar confirms keep the title in notes unless the user edits it, store the
            // eventIdentifier in importExternalId, and leave importCalendarId nil (calendar ids
            // are device-local and a mismatch would defeat the title check on another device).
            notes: edits.notes ?? (isCalendar ? suggestion.title : ""),
            importSource: source.storedValue,
            importExternalId: isCalendar ? (suggestion.legacyEventIdentifier ?? suggestion.externalId) : nil,
            importCalendarId: nil,
            detectedAt: suggestion.detectedAt,
            confirmedAt: now,
            sourceDetail: suggestion.isBackfill ? "backfill" : nil,
            sourceKey: suggestion.sourceKey
        )
        timeEntries.append(entry)
        saveData()
        store?.markConfirmed(key: suggestion.sourceKey, entryId: entry.id)
        reportHouseSave(previousHours: houseHoursBefore)
        Analytics.entryLogged(source: source)
        return .created(entryId: entry.id)
    }

    /// Dismisses a suggestion ("Not rental work"). Never touches entries. Safe to repeat.
    func dismiss(_ suggestion: Suggestion, reason: Suggestion.DismissReason = .notLandlordWork, store: SuggestionStore) {
        store.dismiss(key: suggestion.sourceKey, reason: reason)
    }
}

// MARK: - Pending celebrations
//
// A milestone crossed while no scene is on screen (a background "Log it") is marked
// celebrated by MilestoneTracker, so without this queue it would never be seen.
enum PendingCelebrationQueue {
    static let baseKey = "LandlordHours.pendingCelebrations"

    private static var key: String { UserScope.key(baseKey) }

    static func enqueue(_ type: CelebrationType, defaults: UserDefaults = .standard) {
        var ids = defaults.stringArray(forKey: key) ?? []
        guard !ids.contains(type.id) else { return }
        ids.append(type.id)
        defaults.set(ids, forKey: key)
    }

    static func dequeue(defaults: UserDefaults = .standard) -> CelebrationType? {
        var ids = defaults.stringArray(forKey: key) ?? []
        while !ids.isEmpty {
            let id = ids.removeFirst()
            defaults.set(ids.isEmpty ? nil : ids, forKey: key)
            if let type = CelebrationType(persistedId: id) { return type }
        }
        return nil
    }

    static func pending(defaults: UserDefaults = .standard) -> [CelebrationType] {
        (defaults.stringArray(forKey: key) ?? []).compactMap(CelebrationType.init(persistedId:))
    }
}

extension CelebrationType {
    /// Inverse of `id`, for the pending queue.
    init?(persistedId id: String) {
        switch id {
        case "propertyAdded": self = .propertyAdded
        case "goalMet": self = .goalMet
        case "greatWork": self = .greatWork
        case "weeklyStreak": self = .weeklyStreak
        default:
            let prefix = "hoursLogged_"
            guard id.hasPrefix(prefix), let milestone = Int(id.dropFirst(prefix.count)) else { return nil }
            self = .hoursLogged(milestone: milestone)
        }
    }
}
