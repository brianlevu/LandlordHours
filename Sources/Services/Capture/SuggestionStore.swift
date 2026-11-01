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
            // Editing a series for "all events" moves every occurrence's original start, so its
            // keys change. An entry confirmed from the same series on a day this occurrence
            // touches is the same work under the old key.
            if let externalId = suggestion.externalId, let key = entry.sourceKey,
               key != suggestion.sourceKey,
               key == "cal:\(externalId)" || key.hasPrefix("cal:\(externalId):"),
               entry.date >= firstDay, entry.date < daysEnd {
                return true
            }
            // Records of other confirmed suggestions are separate detected events.
            guard entry.sourceKey == nil else { return false }
            let entryEnd = entry.date.addingTimeInterval(entry.hours * 3600)
            let overlaps = entry.date < windowEnd && entryEnd > windowStart
            let onTouchedDay = entry.date >= firstDay && entry.date < daysEnd
            guard overlaps || onTouchedDay else { return false }
            // The logged hours must be this event's length, give or take 15 minutes. A rental with
            // any other entry that day (a long day of repairs) is not this event, and flagging it
            // took the row's single tag away from "Not sure".
            guard let hours = suggestion.proposedHours ?? suggestion.end.map({ $0.timeIntervalSince(windowStart) / 3600 }),
                  hours > 0, abs(entry.hours - hours) <= hoursMatchTolerance else { return false }
            if let propertyId = suggestion.proposedPropertyId {
                return entry.propertyId == propertyId
            }
            return true
        }
    }

    /// Fifteen minutes: logged hours this close to the event's length look like the same work.
    static let hoursMatchTolerance = 0.25

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
        /// The 2.2 one-time re-check of pending calendar items has run on this install.
        /// Optional so files written before it still decode.
        var pendingCleanupDone: Bool?
        /// 2.3 F: the second one-time re-check (the positive-signal gate) has run on this install.
        var pendingCleanupV2Done: Bool?
        /// 2.3 F: repeating series the user called "Not rental work" (series id → when). No
        /// occurrence of these is suggested again. Optional so older files still decode.
        var dismissedSeries: [String: Date]?
        /// 2.3 F: what one "Not rental work" took with it: the series and the other pending
        /// occurrences it dismissed, by the key the user acted on. Undo reads it.
        var seriesDismissals: [String: SeriesDismissal]?
        /// 2.3 F: per calendar (container id), the user's own verdicts. On this device only.
        var calendarFeedback: [String: CalendarFeedback]?
    }

    struct SeriesDismissal: Codable, Equatable {
        var seriesId: String
        var siblingKeys: [String]
    }

    /// How the user has answered for one calendar's events.
    struct CalendarFeedback: Codable, Equatable {
        /// "Not rental work" taps (a series counts once).
        var notRental = 0
        /// Events confirmed as rental work.
        var confirmed = 0
        /// The one-time "Stop checking this calendar?" prompt was shown (answered either way).
        var prompted = false
    }

    /// "Not rental work" answers that make a calendar worth asking about (2.3 F).
    static let quietPromptDismissals = 3

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

    var hasRunPendingCleanup: Bool { contents.pendingCleanupDone == true }
    var hasRunPendingCleanupV2: Bool { contents.pendingCleanupV2Done == true }

    /// Marks both one-time cleanups done (V2 supersedes V1: it runs the same pass under the 2.3 rules).
    func markPendingCleanupV2Done() {
        guard contents.pendingCleanupV2Done != true || contents.pendingCleanupDone != true else { return }
        contents.pendingCleanupV2Done = true
        contents.pendingCleanupDone = true
        save()
    }

    // MARK: Series and calendar feedback (2.3 F)

    func isSeriesDismissed(_ seriesId: String) -> Bool { contents.dismissedSeries?[seriesId] != nil }

    /// The dismissed series `key` belongs to, if any.
    private func dismissedSeries(containing key: String) -> String? {
        contents.dismissedSeries?.keys.first { Suggestion.key(key, isIn: $0) }
    }

    func feedback(forCalendar containerId: String) -> CalendarFeedback {
        contents.calendarFeedback?[containerId] ?? CalendarFeedback()
    }

    private func updateFeedback(_ containerId: String?, _ change: (inout CalendarFeedback) -> Void) {
        guard let containerId, !containerId.isEmpty else { return }
        var all = contents.calendarFeedback ?? [:]
        var entry = all[containerId] ?? CalendarFeedback()
        change(&entry)
        all[containerId] = entry
        contents.calendarFeedback = all
    }

    /// Calendars to offer the one-time "Stop checking this calendar?" prompt for: 3 or more "Not
    /// rental work" answers, no confirms, never asked, and still checked (`excluded` holds the
    /// calendars the user already turned off). Most dismissed first.
    func calendarsToOfferQuieting(excluded: Set<String>) -> [String] {
        (contents.calendarFeedback ?? [:])
            .filter { id, f in f.notRental >= Self.quietPromptDismissals && f.confirmed == 0 && !f.prompted && !excluded.contains(id) }
            .sorted { $0.value.notRental != $1.value.notRental ? $0.value.notRental > $1.value.notRental : $0.key < $1.key }
            .map(\.key)
    }

    func markQuietPromptShown(calendar containerId: String) {
        updateFeedback(containerId) { $0.prompted = true }
        save()
    }

    #if DEBUG
    /// `-LHInboxQuietPrompt` (frames, UI tests): a calendar with `count` "Not rental work" answers
    /// and no confirms, so the Inbox's one-time prompt shows.
    func debugSeedQuietPrompt(calendar containerId: String, count: Int) {
        updateFeedback(containerId) { $0 = CalendarFeedback(notRental: count, confirmed: 0, prompted: false) }
        save()
    }
    #endif

    /// Takes every pending item of a calendar the user stopped checking out of the Inbox. The
    /// system's call: nothing is remembered as dismissed, so turning the calendar back on brings
    /// them back on the next scan. Returns how many.
    @discardableResult
    func removePending(inCalendars containerIds: Set<String>) -> Int {
        let keys = Set(contents.suggestions.filter { $0.isPending && containerIds.contains($0.containerId ?? "") }.map(\.sourceKey))
        return removeHiddenBySystem(keys: keys)
    }

    func markPendingCleanupDone() {
        guard contents.pendingCleanupDone != true else { return }
        contents.pendingCleanupDone = true
        save()
    }

    /// Takes pending items out because the classifier now says they are not rental work. This is
    /// the system's call, not the user's: nothing is added to the dismissed keys, so it never
    /// reads as a "not rental work" signal. Only pending items are removed. Returns how many.
    @discardableResult
    func removeHiddenBySystem(keys: Set<String>) -> Int {
        let before = contents.suggestions.count
        contents.suggestions.removeAll { keys.contains($0.sourceKey) && $0.isPending }
        let removed = before - contents.suggestions.count
        if removed > 0 { save() }
        return removed
    }

    /// Gives a pending item its new, lower confidence, tier and evidence. Property, category and
    /// hours are the user's to change and stay as they were.
    func lowerConfidence(forKey key: String, to classification: CaptureClassification) {
        guard let index = contents.suggestions.firstIndex(where: { $0.sourceKey == key && $0.isPending }),
              classification.confidence < contents.suggestions[index].confidence else { return }
        contents.suggestions[index].confidence = classification.confidence
        contents.suggestions[index].tier = classification.tier
        contents.suggestions[index].evidence = classification.evidence
        save()
    }

    func isDismissed(_ key: String) -> Bool { contents.dismissedKeys[key] != nil }

    /// False when `ingest` would ignore this key anyway: dismissed, or already confirmed. A scan
    /// skips classifying these (no model call for an event that is settled).
    func wouldIngest(sourceKey: String) -> Bool {
        if isDismissed(sourceKey) { return false }
        if dismissedSeries(containing: sourceKey) != nil { return false }
        if let existing = contents.suggestions.first(where: { $0.sourceKey == sourceKey }) { return existing.isPending }
        return true
    }

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
            // 2.3 F: one "Not rental work" hides the whole repeating series.
            if let series = candidate.seriesId, isSeriesDismissed(series) { continue }

            if let index = contents.suggestions.firstIndex(where: { $0.sourceKey == candidate.sourceKey }) {
                guard contents.suggestions[index].isPending else { continue }
                candidate.id = contents.suggestions[index].id
                candidate.detectedAt = min(contents.suggestions[index].detectedAt, candidate.detectedAt)
                // A re-scan that can't place the event keeps the property it was given since.
                if candidate.proposedPropertyId == nil {
                    candidate.proposedPropertyId = contents.suggestions[index].proposedPropertyId
                }
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

    /// Puts `propertyId` on every pending suggestion that has no property. Onboarding calls it
    /// when the owner's first and only property is saved, since the look-back may have found
    /// events before there was a property to attach them to. Returns how many changed.
    @discardableResult
    func attachPropertyToUnplaced(_ propertyId: UUID) -> Int {
        var changed = 0
        for index in contents.suggestions.indices
        where contents.suggestions[index].isPending && contents.suggestions[index].proposedPropertyId == nil {
            contents.suggestions[index].proposedPropertyId = propertyId
            changed += 1
        }
        if changed > 0 { save() }
        return changed
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
        if contents.suggestions[index].isPending, contents.suggestions[index].kind == .calendar {
            updateFeedback(contents.suggestions[index].containerId) { $0.confirmed += 1 }
        }
        contents.suggestions[index].state = .confirmed(entryId: entryId)
        contents.suggestions[index].mightAlreadyBeLogged = false
        save()
    }

    /// Dismisses a suggestion and remembers its key so it never comes back. Safe to repeat.
    ///
    /// 2.3 F: "Not rental work" on a calendar item also counts against its calendar, and on one
    /// occurrence of a repeating event it hides the whole series (the other pending occurrences
    /// and every future one). Undo (`restorePending`) reverses both.
    func dismiss(key: String, reason: Suggestion.DismissReason, now: Date = Date()) {
        if let index = contents.suggestions.firstIndex(where: { $0.sourceKey == key }),
           contents.suggestions[index].isPending {
            let item = contents.suggestions[index]
            contents.suggestions[index].state = .dismissed(reason: reason)
            if reason == .notLandlordWork, item.kind == .calendar {
                updateFeedback(item.containerId) { $0.notRental += 1 }
                if let series = item.seriesId { dismissSeries(series, from: key, now: now) }
            }
        }
        if contents.dismissedKeys[key] == nil { contents.dismissedKeys[key] = now }
        save()
    }

    private func dismissSeries(_ series: String, from key: String, now: Date) {
        var siblings: [String] = []
        for index in contents.suggestions.indices
        where contents.suggestions[index].isPending && contents.suggestions[index].seriesId == series {
            contents.suggestions[index].state = .dismissed(reason: .notLandlordWork)
            let sibling = contents.suggestions[index].sourceKey
            if contents.dismissedKeys[sibling] == nil { contents.dismissedKeys[sibling] = now }
            siblings.append(sibling)
        }
        var all = contents.dismissedSeries ?? [:]
        all[series] = all[series] ?? now
        contents.dismissedSeries = all
        var undo = contents.seriesDismissals ?? [:]
        undo[key] = SeriesDismissal(seriesId: series, siblingKeys: siblings)
        contents.seriesDismissals = undo
    }

    /// Undo: puts these suggestions back in the inbox as pending and forgets their dismissed
    /// keys. The caller removes any entry or mute rule the undone action created.
    func restorePending(keys: Set<String>) {
        guard !keys.isEmpty else { return }
        var keys = keys
        // 2.3 F: undo what each answer counted, and bring back a series it hid.
        for index in contents.suggestions.indices where keys.contains(contents.suggestions[index].sourceKey) {
            let item = contents.suggestions[index]
            guard item.kind == .calendar else { continue }
            switch item.state {
            case .dismissed(reason: .notLandlordWork):
                updateFeedback(item.containerId) { $0.notRental = max(0, $0.notRental - 1) }
            case .confirmed:
                updateFeedback(item.containerId) { $0.confirmed = max(0, $0.confirmed - 1) }
            default:
                break
            }
        }
        for key in keys {
            guard let undo = contents.seriesDismissals?[key] else { continue }
            contents.dismissedSeries?[undo.seriesId] = nil
            contents.seriesDismissals?[key] = nil
            keys.formUnion(undo.siblingKeys)
        }
        for index in contents.suggestions.indices where keys.contains(contents.suggestions[index].sourceKey) {
            contents.suggestions[index].state = .pending
        }
        for key in keys { contents.dismissedKeys[key] = nil }
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
