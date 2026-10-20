import Foundation

// MARK: - Log time (2.0): the form's rules, kept out of the view so they are unit-tested.
//
// Spec: AgentScratch redesign-specs.md §3 (approved sandbox `sandbox-screens` fc0cf6b, S2Log.swift).
// Smart-layer slots (smart-layer/design-implications.md): the fill source is a parameter, not the
// string "your note"; a pre-fill strip and a "Description for your record" row exist as hidden
// slots; the timer draft card is the generic draft card.

/// The outcome of the Log time sheet's save (`AppViewModel.logTimeEntry`).
enum LogSaveResult: Equatable {
    case saved(UUID)
    /// Nothing was saved; the message says why, in plain words.
    case failed(String)

    static let writeFailedMessage = "Couldn't save this. Free up some space on your iPhone and try again."
    static let missingPropertyMessage = "Pick a property to log this."
    static let missingHoursMessage = "Add how long it took to log this."

    var entryId: UUID? {
        if case .saved(let id) = self { return id }
        return nil
    }
}

/// A field the note (or, later, a receipt or a visit) can fill.
enum LogField: Hashable, CaseIterable {
    case property, category, hours, participant
}

/// Where a fill came from. Today only the note and voice fill; the rest are smart-layer slots.
enum LogFillSource: Equatable {
    case note
    case voice
    case receipt
    case visit(String)

    /// "Filled from {phrase}".
    var phrase: String {
        switch self {
        case .note: return "your note"
        case .voice: return "what you said"
        case .receipt: return "a receipt"
        case .visit(let name): return name
        }
    }

    /// No trailing middot: "Undo" is its own button, so the caption never ends in a dangling "·".
    var caption: String { "Filled from \(phrase)" }
}

/// The Log time form. Values the user set by hand are never overwritten by a fill.
struct LogForm: Equatable {
    struct Snapshot: Equatable {
        var propertyId: UUID?
        var category: ActivityCategory?
        var hours: Double
        var participant: Participant
    }

    var note = ""
    var propertyId: UUID?
    var category: ActivityCategory?
    var hours: Double = 0
    var participant: Participant = .selfParticipant
    var date = Date()
    /// Fields the user touched. A fill skips them.
    private(set) var userSet: Set<LogField> = []
    /// Fields the last fill wrote (they flash once, and Undo puts them back).
    private(set) var filled: Set<LogField> = []
    private(set) var fillSource: LogFillSource?
    private(set) var beforeFill: Snapshot?
    /// The category came from "last used", not from the user or a fill.
    private(set) var categoryIsRemembered = false

    static let step = 0.25
    static let maxHours = 24.0

    /// Defaults that keep "2h at my only rental" to a few taps: the only property, the last
    /// category used, 1 hour. None of them count as user-set, so a fill can replace them.
    static func starting(properties: [RentalProperty], entries: [TimeEntry], now: Date = Date()) -> LogForm {
        var form = LogForm()
        form.date = now
        form.hours = 1
        if properties.count == 1 { form.propertyId = properties[0].id }
        if let last = entries.max(by: { $0.date < $1.date })?.category {
            form.category = last
            form.categoryIsRemembered = true
        }
        return form
    }

    // MARK: User edits

    mutating func setProperty(_ id: UUID?) {
        propertyId = id
        userSet.insert(.property)
        filled.remove(.property)
    }

    mutating func setCategory(_ value: ActivityCategory) {
        category = value
        categoryIsRemembered = false
        userSet.insert(.category)
        filled.remove(.category)
    }

    mutating func setHours(_ value: Double) {
        hours = Self.clampHours(value)
        userSet.insert(.hours)
        filled.remove(.hours)
    }

    mutating func stepHours(up: Bool) {
        setHours(hours + (up ? Self.step : -Self.step))
    }

    mutating func setParticipant(_ value: Participant) {
        participant = value
        userSet.insert(.participant)
        filled.remove(.participant)
    }

    static func clampHours(_ value: Double) -> Double {
        min(max(0, (value / step).rounded() * step), maxHours)
    }

    // MARK: Fill

    /// Fills from a parsed note. Only values the parser is sure of are used: a matched property,
    /// a matched category, hours the note said out loud, and "spouse" only when spouse hours are
    /// tracked. Returns the fields it wrote.
    @discardableResult
    mutating func apply(_ parsed: ParsedTimeEntry, source: LogFillSource, spouseTracking: Bool) -> Set<LogField> {
        let snapshot = Snapshot(propertyId: propertyId, category: category, hours: hours, participant: participant)
        var wrote = Set<LogField>()
        if let property = parsed.property, !userSet.contains(.property), propertyId != property.id {
            propertyId = property.id
            wrote.insert(.property)
        }
        if parsed.categoryMatched, !userSet.contains(.category), category != parsed.category || categoryIsRemembered {
            category = parsed.category
            categoryIsRemembered = false
            wrote.insert(.category)
        }
        if parsed.hoursAreExplicit, !userSet.contains(.hours), parsed.hours > 0 {
            let value = Self.clampHours(parsed.hours)
            if value != hours { hours = value; wrote.insert(.hours) }
        }
        let who = LogParticipantRule.resolve(parsed.participant, spouseTracking: spouseTracking)
        if !userSet.contains(.participant), who != participant {
            participant = who
            wrote.insert(.participant)
        }
        guard !wrote.isEmpty else { return [] }
        beforeFill = snapshot
        filled = wrote
        fillSource = source
        return wrote
    }

    var canUndoFill: Bool { beforeFill != nil && fillSource != nil }

    /// "Filled from your note · Undo": puts back exactly what was there before the fill.
    mutating func undoFill() {
        guard let before = beforeFill else { return }
        if filled.contains(.property) { propertyId = before.propertyId }
        if filled.contains(.category) { category = before.category }
        if filled.contains(.hours) { hours = before.hours }
        if filled.contains(.participant) { participant = before.participant }
        filled = []
        fillSource = nil
        beforeFill = nil
    }

    /// A new note starts a new fill; the old caption goes away.
    mutating func clearFillCaption() {
        filled = []
        fillSource = nil
        beforeFill = nil
    }

    // MARK: Validation

    /// The one line under the button saying what's missing, or nil when it can be logged.
    func missingMessage(properties: [RentalProperty]) -> String? {
        if propertyId == nil || !properties.contains(where: { $0.id == propertyId }) {
            return properties.isEmpty ? "Add a property to log this." : LogSaveResult.missingPropertyMessage
        }
        if hours <= 0 { return LogSaveResult.missingHoursMessage }
        if category == nil { return "Pick the kind of work to log this." }
        return nil
    }

    func canLog(properties: [RentalProperty]) -> Bool { missingMessage(properties: properties) == nil }

    /// Investing, Financing and Negotiation are logged for the record but never count.
    var countsTowardHours: Bool { category?.countsForREPS ?? true }

    func participantToSave(spouseTracking: Bool) -> Participant {
        LogParticipantRule.resolve(participant, spouseTracking: spouseTracking)
    }

    var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Who an entry belongs to. Without spouse tracking every entry is the owner's own, whatever the
/// note says ("my wife and I…"), so spouse hours never sneak into a household that doesn't
/// track them. With tracking, "Spouse" is a real choice. (REPS still counts only the owner's own
/// hours — TodayHouse.houseCountableHours — so a spouse entry never fills YOUR 750.)
enum LogParticipantRule {
    static func resolve(_ participant: Participant, spouseTracking: Bool) -> Participant {
        spouseTracking ? participant : .selfParticipant
    }

    static func showsPicker(spouseTracking: Bool) -> Bool { spouseTracking }
}

// MARK: - Formatting

enum LogTimeFormat {
    /// " · " that never ends a line: the middot is glued to the word after it (no dangling "·").
    static let dot = " \u{00B7}\u{00A0}"

    /// "1h 30m", "45m", "2h".
    static func hours(_ value: Double) -> String { InboxFormat.hours(value) }

    /// "Log 1h 30m"; "Log time" with nothing to log.
    static func logButton(_ hours: Double) -> String { hours > 0 ? "Log \(Self.hours(hours))" : "Log time" }

    /// "Logged 1h 30m at Pine Cabin".
    static func loggedToast(hours: Double, propertyName: String?) -> String {
        guard let propertyName else { return "Logged \(Self.hours(hours))" }
        return "Logged \(Self.hours(hours)) at \(propertyName)"
    }

    /// "TODAY · SUN, OCT 19" (uppercased by the view) or "TUE, OCT 14".
    static func eyebrow(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day = InboxFormat.longDay(date, calendar: calendar)
        return calendar.isDate(date, inSameDayAs: now) ? "Today\(dot)\(day)" : day
    }

    /// The Date row: "Today, Oct 19", "Yesterday, Oct 18", "Tue, Oct 14".
    static func dateRow(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        let short = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "Today, \(short)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday, \(short)"
        }
        return InboxFormat.longDay(date, calendar: calendar)
    }

    /// "1:14:07" or "4:07".
    static func clock(_ elapsed: TimeInterval) -> String {
        let s = max(0, Int(elapsed))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Timer

enum TimerReviewMath {
    /// Under a minute is not worth a record; the review says so instead of logging "0m".
    static let minimumSavable: TimeInterval = 60
    static let cap: TimeInterval = 24 * 3600

    /// The review's hours: the run time to the nearest 5 minutes, at least 5 minutes, capped at 24h.
    static func reviewHours(elapsed: TimeInterval) -> Double {
        let capped = min(max(elapsed, 0), cap)
        guard capped >= minimumSavable else { return 0 }
        let fiveMinuteBlocks = max(1, (capped / 300).rounded())
        return fiveMinuteBlocks * 300 / 3600
    }

    /// "Timer ran 1h 14m" (whole minutes, never rounded up).
    static func ranCaption(elapsed: TimeInterval) -> String {
        let minutes = Int(min(max(elapsed, 0), cap) / 60)
        guard minutes > 0 else { return "Timer ran under a minute" }
        return "Timer ran \(InboxFormat.hours(Double(minutes) / 60))"
    }

    static func wasCapped(elapsed: TimeInterval) -> Bool { elapsed > cap }
}

/// A stopped timer waiting to be logged. Survives closing the sheet and relaunching (it's what
/// the Today draft card shows). Same storage key as 1.x, so a 1.x draft still comes back.
struct StoppedTimerDraft: Codable, Equatable {
    let elapsed: TimeInterval
    let propertyId: UUID
    let category: ActivityCategory
    let startDate: Date
    var participant: Participant
    var notes: String

    var reviewHours: Double { TimerReviewMath.reviewHours(elapsed: elapsed) }
}

enum StoppedTimerDraftStore {
    static var key: String { UserScope.key("LandlordHours.stoppedTimerDraft") }

    static func load(defaults: UserDefaults = .standard) -> StoppedTimerDraft? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StoppedTimerDraft.self, from: data)
    }

    static func save(_ draft: StoppedTimerDraft, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: key) }
        NotificationCenter.default.post(name: .stoppedTimerDraftDidChange, object: nil)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        NotificationCenter.default.post(name: .stoppedTimerDraftDidChange, object: nil)
    }
}

extension Notification.Name {
    static let stoppedTimerDraftDidChange = Notification.Name("stoppedTimerDraftDidChange")
    /// Opens the Log time sheet from anywhere (object: `LogSheetRoute`).
    static let openLogSheet = Notification.Name("openLogSheet")
}

/// What the "+" sheet opens on.
enum LogSheetRoute: Identifiable, Equatable {
    case log
    case timer
    /// A stopped timer waiting for its note.
    case timerReview
    /// A timer draft left from a forgotten timer or a profile switch.
    case recovery(UUID)

    var id: String {
        switch self {
        case .log: return "log"
        case .timer: return "timer"
        case .timerReview: return "timerReview"
        case .recovery(let id): return "recovery-\(id.uuidString)"
        }
    }
}

// MARK: - Category groups (the picker)

enum LogCategoryGroups {
    /// The grid: the kinds of work that count toward hours.
    static let counted: [ActivityCategory] = [.repairs, .renovations, .management, .leasing, .bookkeeping, .legal, .travel, .insurance]
    /// "Doesn't count toward hours": logged for the record, never counted.
    static let notCounted: [ActivityCategory] = ActivityCategory.allCases.filter { !$0.countsForREPS }
}

// MARK: - Smart-layer slots (no features yet)

/// One pre-fill chip ("Home Depot · 9:40"). The strip above the note hides when there are none.
struct LogPrefill: Identifiable, Equatable {
    let id: UUID
    let title: String
    let source: LogFillSource
}
