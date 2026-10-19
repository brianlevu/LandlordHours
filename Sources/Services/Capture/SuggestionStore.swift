import Foundation
import os.log

private let storeLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "SuggestionStore")

// MARK: - Reconciliation (pure)
//
// Decides how a detected item relates to records the user already has. Pure functions so the
// rules that stop double-counted tax hours are unit-tested without any store or view model.
enum CaptureReconciler {
    /// Hours tolerance when comparing a suggestion with an existing entry.
    static let hoursTolerance = 0.01

    /// The entry that already records this exact suggestion (confirmed here or on another
    /// device): same `sourceKey`, or the deterministic id derived from it for `profileId`.
    /// `entries` are the profile's own entries.
    static func confirmedEntry(for suggestion: Suggestion, profileId: String, in entries: [TimeEntry]) -> TimeEntry? {
        let derivedId = suggestion.entryId(profileId: profileId)
        return entries.first { $0.id == derivedId || ($0.sourceKey != nil && $0.sourceKey == suggestion.sourceKey) }
    }

    /// How far a 1.x import's start may differ from the suggestion's start. Matches 1.x's own
    /// duplicate check (`isDuplicateCalendarEntry`, < 60 s).
    static let legacyStartTolerance: TimeInterval = 60

    /// A 1.x calendar bulk import covering this calendar suggestion.
    ///
    /// 1.x stored the device-local `eventIdentifier`, which is shared by every repeat of a
    /// recurring event, so its keys can never equal a 2.0 `cal:` key. Matching is therefore
    /// fuzzy, and strict so real hours are never hidden: same start time (within 60 s), same
    /// hours, same title (1.x wrote the event title into `notes`), and the same property
    /// whenever the suggestion proposes one. Each old import covers at most one suggestion:
    /// entries in `claimed` already cover another suggestion and are skipped; when several
    /// imports qualify the one closest in start time wins.
    static func legacyImportMatch(
        for suggestion: Suggestion,
        in entries: [TimeEntry],
        calendar: Calendar = .current,
        excluding claimed: Set<UUID> = []
    ) -> TimeEntry? {
        guard suggestion.kind == .calendar, let hours = suggestion.proposedHours else { return nil }
        let title = normalizedTitle(suggestion.title)
        guard !title.isEmpty else { return nil }
        let matches = entries.filter { entry in
            guard entry.isLegacyCalendarImport, !claimed.contains(entry.id) else { return false }
            if let propertyId = suggestion.proposedPropertyId, entry.propertyId != propertyId { return false }
            guard abs(entry.date.timeIntervalSince(suggestion.start)) <= legacyStartTolerance else { return false }
            guard abs(entry.hours - hours) < hoursTolerance else { return false }
            return normalizedTitle(entry.notes) == title
        }
        return matches.min {
            abs($0.date.timeIntervalSince(suggestion.start)) < abs($1.date.timeIntervalSince(suggestion.start))
        }
    }

    /// True when hours already recorded look like this item. The item is still shown, marked
    /// "might already be logged", and never pre-selected: the user decides.
    ///
    /// Two signals, both in absolute time:
    /// - A calendar-sourced entry (a 1.x import) with the same title and a start within 60 s,
    ///   whatever its property: the property may have been edited or derived differently.
    /// - A hand-logged entry (no `sourceKey`) on the same property whose own window
    ///   (`date` ... `date + hours`) overlaps the item's window, or whose `date` falls on a
    ///   calendar day the item touches (people log "2 h on Tuesday" without a time). Events
    ///   crossing midnight touch both days. Without a proposed property, only when hours line up.
    static func mightAlreadyBeLogged(
        _ suggestion: Suggestion,
        in entries: [TimeEntry],
        calendar: Calendar = .current
    ) -> Bool {
        let title = normalizedTitle(suggestion.title)
        let windowStart = suggestion.start
        let windowEnd = max(
            suggestion.end ?? windowStart.addingTimeInterval((suggestion.proposedHours ?? 0) * 3600),
            windowStart
        )
        let firstDay = calendar.startOfDay(for: windowStart)
        let lastDay = calendar.startOfDay(for: max(windowStart, windowEnd.addingTimeInterval(-1)))
        let daysEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(86_400)

        return entries.contains { entry in
            if entry.source == .calendar, entry.sourceKey != suggestion.sourceKey, !title.isEmpty,
               abs(entry.date.timeIntervalSince(suggestion.start)) <= legacyStartTolerance,
               normalizedTitle(entry.notes) == title {
                return true
            }
            // Records of other confirmed suggestions are separate detected events.
            guard entry.sourceKey == nil else { return false }
            let entryEnd = entry.date.addingTimeInterval(entry.hours * 3600)
            let overlaps = entry.date < windowEnd && entryEnd > windowStart
            let onTouchedDay = entry.date >= firstDay && entry.date < daysEnd
            guard overlaps || onTouchedDay else { return false }
            if let propertyId = suggestion.proposedPropertyId {
                return entry.propertyId == propertyId
            }
            guard let hours = suggestion.proposedHours else { return false }
            return abs(entry.hours - hours) <= 0.25
        }
    }

    static func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

// MARK: - Suggestion store
//
// The inbox. One JSON file per profile at
// Application Support/Capture/<userScope>/suggestions.json, written atomically with the
// default file-protection class. Local only: never synced, never in the App Group.
// Holds pending/confirmed/dismissed suggestions, the dismissed-key memory (so a dismissed
// event never comes back), and mute rules. Deleting a profile removes its folder.
@MainActor
final class SuggestionStore {
    struct Contents: Codable, Equatable {
        var version: Int = 1
        var suggestions: [Suggestion] = []
        /// Dedupe keys the user dismissed, with when. Pruned after a tax year.
        var dismissedKeys: [String: Date] = [:]
        var muteRules: [CaptureMuteRule] = []
    }

    static let fileName = "suggestions.json"

    let userId: String
    let fileURL: URL
    private(set) var contents: Contents
    /// Last write error, for diagnostics. Nil when the last save succeeded.
    private(set) var lastSaveError: Error?

    nonisolated static var defaultBaseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Capture", isDirectory: true)
    }

    /// Folder for one profile. The user id is made path-safe; it is never empty.
    nonisolated static func directory(forUserId userId: String, baseDirectory: URL = defaultBaseDirectory) -> URL {
        let safe = userId.map { ch -> Character in
            ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "." ? ch : "_"
        }
        let name = safe.isEmpty || String(safe).allSatisfy({ $0 == "." }) ? "_" : String(safe)
        return baseDirectory.appendingPathComponent(name, isDirectory: true)
    }

    /// Removes a profile's capture folder (profile delete / reset).
    nonisolated static func removeAll(forUserId userId: String, baseDirectory: URL = defaultBaseDirectory) {
        let dir = directory(forUserId: userId, baseDirectory: baseDirectory)
        try? FileManager.default.removeItem(at: dir)
    }

    init(userId: String, baseDirectory: URL = SuggestionStore.defaultBaseDirectory) {
        self.userId = userId
        self.fileURL = Self.directory(forUserId: userId, baseDirectory: baseDirectory)
            .appendingPathComponent(Self.fileName)
        self.contents = Self.load(from: fileURL)
    }

    private static func load(from url: URL) -> Contents {
        guard let data = try? Data(contentsOf: url) else { return Contents() }
        do {
            return try JSONDecoder.captureDecoder.decode(Contents.self, from: data)
        } catch {
            // Suggestions are regenerable; keep the bad file for support and start clean.
            storeLogger.error("Suggestion store unreadable: \(error.localizedDescription, privacy: .public)")
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("suggestions.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return Contents()
        }
    }

    // MARK: Reads

    var suggestions: [Suggestion] { contents.suggestions }
    var pending: [Suggestion] { contents.suggestions.filter(\.isPending) }
    var muteRules: [CaptureMuteRule] { contents.muteRules }

    func suggestion(forKey key: String) -> Suggestion? {
        contents.suggestions.first { $0.sourceKey == key }
    }

    /// Entry ids that already cover a stored suggestion other than `key`. A 1.x import may
    /// cover only one suggestion.
    func claimedEntryIds(excludingKey key: String) -> Set<UUID> {
        Set(contents.suggestions.compactMap { suggestion -> UUID? in
            guard suggestion.sourceKey != key, case .confirmed(let id) = suggestion.state else { return nil }
            return id
        })
    }

    func isDismissed(_ key: String) -> Bool { contents.dismissedKeys[key] != nil }

    func isMuted(_ suggestion: Suggestion) -> Bool {
        contents.muteRules.contains { $0.mutes(suggestion) }
    }

    // MARK: Writes

    /// Adds newly detected items, deduped by key. Returns the suggestions that were newly added
    /// as pending (what a notifier may announce).
    ///
    /// - A key the user dismissed never comes back.
    /// - A muted item is skipped.
    /// - A key already stored updates the pending copy (event moved/renamed) and keeps its id.
    /// - An item already recorded (same key, derived id, or a matching 1.x import) is stored as
    ///   confirmed so it never shows in the inbox.
    /// - Anything that looks like hours already logged by hand is flagged, never pre-selected.
    @discardableResult
    func ingest(_ candidates: [Suggestion], existingEntries: [TimeEntry], calendar: Calendar = .current) -> [Suggestion] {
        var added: [Suggestion] = []
        var seenKeys = Set<String>()
        for var candidate in candidates {
            guard seenKeys.insert(candidate.sourceKey).inserted else { continue }
            guard !isDismissed(candidate.sourceKey), !isMuted(candidate) else { continue }

            if let index = contents.suggestions.firstIndex(where: { $0.sourceKey == candidate.sourceKey }) {
                guard contents.suggestions[index].isPending else { continue }
                candidate.id = contents.suggestions[index].id
                candidate.detectedAt = min(contents.suggestions[index].detectedAt, candidate.detectedAt)
                candidate.state = .pending
                contents.suggestions[index] = resolved(candidate, entries: existingEntries, calendar: calendar)
                continue
            }

            let resolvedCandidate = resolved(candidate, entries: existingEntries, calendar: calendar)
            contents.suggestions.append(resolvedCandidate)
            if resolvedCandidate.isPending { added.append(resolvedCandidate) }
        }
        save()
        return added
    }

    /// Re-checks every pending suggestion against current entries (after a sync pull, a manual
    /// log, or a confirm on another device).
    func reconcile(with entries: [TimeEntry], calendar: Calendar = .current) {
        var changed = false
        for index in contents.suggestions.indices where contents.suggestions[index].isPending {
            let updated = resolved(contents.suggestions[index], entries: entries, calendar: calendar)
            if updated != contents.suggestions[index] {
                contents.suggestions[index] = updated
                changed = true
            }
        }
        if changed { save() }
    }

    private func resolved(_ suggestion: Suggestion, entries: [TimeEntry], calendar: Calendar) -> Suggestion {
        var result = suggestion
        if let existing = CaptureReconciler.confirmedEntry(for: suggestion, profileId: userId, in: entries) {
            result.state = .confirmed(entryId: existing.id)
            result.mightAlreadyBeLogged = false
        } else if let legacy = CaptureReconciler.legacyImportMatch(
            for: suggestion, in: entries, calendar: calendar,
            excluding: claimedEntryIds(excludingKey: suggestion.sourceKey)
        ) {
            result.state = .confirmed(entryId: legacy.id)
            result.mightAlreadyBeLogged = false
        } else {
            result.mightAlreadyBeLogged = CaptureReconciler.mightAlreadyBeLogged(suggestion, in: entries, calendar: calendar)
        }
        return result
    }

    /// Marks a suggestion confirmed. Safe to repeat.
    func markConfirmed(key: String, entryId: UUID) {
        guard let index = contents.suggestions.firstIndex(where: { $0.sourceKey == key }) else { return }
        guard contents.suggestions[index].state != .confirmed(entryId: entryId) else { return }
        contents.suggestions[index].state = .confirmed(entryId: entryId)
        contents.suggestions[index].mightAlreadyBeLogged = false
        save()
    }

    /// Dismisses a suggestion and remembers its key so it never comes back. Safe to repeat.
    func dismiss(key: String, reason: Suggestion.DismissReason, now: Date = Date()) {
        if let index = contents.suggestions.firstIndex(where: { $0.sourceKey == key }),
           contents.suggestions[index].isPending {
            contents.suggestions[index].state = .dismissed(reason: reason)
        }
        if contents.dismissedKeys[key] == nil { contents.dismissedKeys[key] = now }
        save()
    }

    func addMuteRule(_ rule: CaptureMuteRule) {
        guard !contents.muteRules.contains(where: { $0.match == rule.match && $0.value == rule.value }) else { return }
        contents.muteRules.append(rule)
        for index in contents.suggestions.indices
        where contents.suggestions[index].isPending && rule.mutes(contents.suggestions[index]) {
            contents.suggestions[index].state = .dismissed(reason: .muted)
        }
        save()
    }

    func removeMuteRule(id: UUID) {
        contents.muteRules.removeAll { $0.id == id }
        save()
    }

    /// Forgets dismissed keys (and their resolved suggestions) older than `cutoff`. Run once a
    /// tax year has closed so the file does not grow forever.
    func pruneResolved(olderThan cutoff: Date) {
        contents.dismissedKeys = contents.dismissedKeys.filter { $0.value >= cutoff }
        contents.suggestions.removeAll { !$0.isPending && $0.start < cutoff }
        save()
    }

    /// Atomic write, default file protection (complete until first user authentication).
    func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder.captureEncoder.encode(contents)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastSaveError = nil
        } catch {
            lastSaveError = error
            storeLogger.error("Suggestion store save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension JSONEncoder {
    static var captureEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var captureDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
