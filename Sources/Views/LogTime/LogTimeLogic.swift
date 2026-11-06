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

    static var writeFailedMessage: String { lt("Couldn’t save this. Free up some space on your iPhone and try again.") }
    static var missingPropertyMessage: String { lt("Pick a rental to log this.") }
    static var missingHoursMessage: String { lt("Add how long it took to log this.") }
    static var missingKindMessage: String { lt("Pick the kind of work to log this.") }
    static var missingNameMessage: String { lt("Name your rental to log this.") }

    var entryId: UUID? {
        if case .saved(let id) = self { return id }
        return nil
    }
}

/// A field the note (or, later, a receipt or a visit) can fill.
enum LogField: Hashable, CaseIterable {
    case property, category, hours, participant, date, description
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
        case .note: return lt("your note")
        case .voice: return lt("what you said")
        case .receipt: return lt("a receipt")
        case .visit(let name): return name
        }
    }

    /// "Filled from your note" (the model's wording; the rules alone say "Matched from your words").
    var caption: String { caption(tier: .model) }

    /// No trailing middot: "Undo" is its own button, so the caption never ends in a dangling "·".
    /// The note's model answered: "Filled from your note". Rules alone: "Matched from your words".
    func caption(tier: LogFillTier) -> String {
        switch tier {
        case .rules: return lt("Matched from your words")
        case .model:
            switch self {
            case .note: return lt("Filled from your note")
            case .voice: return lt("Filled from what you said")
            case .receipt: return lt("Filled from a receipt")
            case .visit(let name): return lt("Filled from \(name)")
            }
        }
    }
}

/// Who wrote a fill. The rules always run (even with "Read my notes with Apple's model" off);
/// the model only refines. A model answer may replace what the rules wrote, never what the user set.
enum LogFillTier: Equatable { case rules, model }

/// Where a field's current value came from.
enum LogProvenance: Equatable { case defaultValue, remembered, rules, model, user }

/// A value the model replaced after the user had already seen the rules' answer, so the row
/// can offer its own Undo.
enum LogUpdatedValue: Equatable {
    case property(UUID?)
    case category(ActivityCategory?)
    case hours(Double, wasDefault: Bool)
    case date(Date)
    case participant(Participant)
}

/// What the Log button says it still needs, in the order the user would fix it.
enum LogGap: Equatable { case name, rental, kind, hours }

/// The Log time form. Values the user set by hand are never overwritten by a fill.
struct LogForm: Equatable {
    struct Snapshot: Equatable {
        var propertyId: UUID?
        var category: ActivityCategory?
        var categoryIsRemembered = false
        var hours: Double
        var hoursIsDefault = false
        var participant: Participant
        var date = Date()
        var recordDescription: String?
    }

    var note = ""
    var propertyId: UUID?
    var category: ActivityCategory?
    var hours: Double = 0
    var participant: Participant = .selfParticipant
    var date = Date()
    /// "Description for your record": the model's sentence (fact-checked), editable. Nil hides
    /// the row. The note stays the user's own words.
    private(set) var recordDescription: String?
    /// "Your note mentions 2 rentals. Log each one separately." Shown under Property while the
    /// property is empty because the note named several.
    private(set) var propertyHint: String?
    /// Fields the user touched. A fill skips them.
    private(set) var userSet: Set<LogField> = []
    /// Fields the last fill wrote (they flash once, and Undo puts them back).
    private(set) var filled: Set<LogField> = []
    private(set) var fillSource: LogFillSource?
    private(set) var beforeFill: Snapshot?
    /// The category came from "last used", not from the user or a fill.
    private(set) var categoryIsRemembered = false
    /// The 1h is the app's number, not the user's and not the note's. A fill or a hand edit clears it.
    private(set) var hoursIsDefault = false
    /// Who wrote each filled field (rules or the model).
    private(set) var filledBy: [LogField: LogFillTier] = [:]
    /// Rows the model changed after the rules' answer had been on screen: field → the value it had.
    private(set) var updatedAfterSeen: [LogField: LogUpdatedValue] = [:]
    /// The tier of the latest fill (drives the caption).
    private(set) var fillTier: LogFillTier = .rules
    /// A note was read and never named the kind of work, so the remembered "last used" kind was
    /// taken off rather than logged silently. Undo puts it back.
    private(set) var droppedRemembered = false

    static let step = 0.25
    static let maxHours = 24.0

    /// Defaults that keep "2h at my only rental" to a few taps: the only property, the last
    /// category used, 1 hour. None of them count as user-set, so a fill can replace them.
    ///
    /// `rentalShown` is the rental the shell is showing (the shelf or the chip; nil on "All
    /// rentals"): with several rentals Log time starts on it, as a default and not a user choice.
    static func starting(properties: [RentalProperty], entries: [TimeEntry], rentalShown: UUID? = nil,
                         now: Date = Date()) -> LogForm {
        var form = LogForm()
        form.date = now
        form.hours = 1
        form.hoursIsDefault = true
        if properties.count == 1 {
            form.propertyId = properties[0].id
        } else if let shown = rentalShown, properties.contains(where: { $0.id == shown }) {
            form.propertyId = shown
        }
        if let last = entries.max(by: { $0.date < $1.date })?.category {
            form.category = last
            form.categoryIsRemembered = true
        }
        return form
    }

    // MARK: User edits

    mutating func setProperty(_ id: UUID?) {
        propertyId = id
        propertyHint = nil
        userSet.insert(.property)
        markUser(.property)
    }

    mutating func setCategory(_ value: ActivityCategory) {
        category = value
        categoryIsRemembered = false
        userSet.insert(.category)
        markUser(.category)
    }

    mutating func setHours(_ value: Double) {
        hours = Self.clampHours(value)
        hoursIsDefault = false
        userSet.insert(.hours)
        markUser(.hours)
    }

    mutating func stepHours(up: Bool) {
        setHours(hours + (up ? Self.step : -Self.step))
    }

    mutating func setParticipant(_ value: Participant) {
        participant = value
        userSet.insert(.participant)
        markUser(.participant)
    }

    mutating func setDate(_ value: Date) {
        date = value
        userSet.insert(.date)
        markUser(.date)
    }

    mutating func setDescription(_ value: String) {
        recordDescription = value
        userSet.insert(.description)
        markUser(.description)
    }

    /// A hand edit makes the value the user's: no mark, no per-row Undo, and no later fill touches it.
    private mutating func markUser(_ field: LogField) {
        filled.remove(field)
        filledBy[field] = nil
        updatedAfterSeen[field] = nil
    }

    /// Where `field`'s value came from.
    func provenance(_ field: LogField) -> LogProvenance {
        if userSet.contains(field) { return .user }
        if let tier = filledBy[field], filled.contains(field) { return tier == .model ? .model : .rules }
        if field == .category, categoryIsRemembered { return .remembered }
        return .defaultValue
    }

    /// A recent chip: rental, kind and hours in one tap. They are the user's own values (no mark).
    mutating func applyRecent(_ recent: LogRecent) {
        clearFillCaption()
        setProperty(recent.propertyId)
        setCategory(recent.category)
        setHours(recent.hours)
    }

    /// The description to save: trimmed, nil when empty.
    var descriptionToSave: String? {
        let trimmed = recordDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func clampHours(_ value: Double) -> Double {
        min(max(0, (value / step).rounded() * step), maxHours)
    }

    // MARK: Fill

    private var snapshot: Snapshot {
        Snapshot(propertyId: propertyId, category: category, categoryIsRemembered: categoryIsRemembered, hours: hours,
                 hoursIsDefault: hoursIsDefault, participant: participant, date: date, recordDescription: recordDescription)
    }

    /// The 1.x keyword parser's result as a reading: only what it is sure of (a matched
    /// property, a matched category, hours said out loud, a spouse).
    @discardableResult
    mutating func apply(_ parsed: ParsedTimeEntry, source: LogFillSource, spouseTracking: Bool) -> Set<LogField> {
        var reading = NoteReading()
        reading.propertyId = parsed.property?.id
        reading.category = parsed.categoryMatched ? parsed.category : nil
        reading.hours = parsed.hoursAreExplicit && parsed.hours > 0 ? parsed.hours : nil
        reading.participant = parsed.participant == .spouse ? .spouse : nil
        return apply(reading, source: source, spouseTracking: spouseTracking)
    }

    /// Fills from a note reading. Never touches a field the user set. A fill on top of a fill
    /// (the rules first, then Apple's model; or a longer note) is ONE fill: Undo goes back to
    /// what was there before the first one, and a field a later reading no longer fills goes
    /// back too. Returns the fields whose value changed in this call (they flash).
    ///
    /// `tier` says who wrote this reading. A model reading may replace what the rules wrote; when
    /// `late` (the rules' answer had been on screen a moment) the replaced value is kept in
    /// `updatedAfterSeen` so that row can offer its own Undo. `rulesBaseline` is the rules'
    /// reading of the same note: a model value equal to it is still the rules' word.
    @discardableResult
    mutating func apply(_ reading: NoteReading, source: LogFillSource, spouseTracking: Bool,
                        tier: LogFillTier = .rules, late: Bool = false, rulesBaseline: NoteReading? = nil,
                        calendar: Calendar = .current) -> Set<LogField> {
        let current = snapshot
        let before = beforeFill ?? current
        let priorTiers = filledBy
        var next = self
        if next.canUndoFill { next.restoreBefore() }

        if let id = reading.propertyId, !userSet.contains(.property) {
            next.propertyId = id
        }
        if let value = reading.category, !userSet.contains(.category) {
            next.category = value
            next.categoryIsRemembered = false
        }
        if let value = reading.hours, value > 0, !userSet.contains(.hours) {
            next.hours = Self.clampHours(value)
            next.hoursIsDefault = false
        }
        if let day = reading.date, !userSet.contains(.date) {
            // The note picks the day; the time of day stays.
            let time = calendar.dateComponents([.hour, .minute, .second], from: date)
            next.date = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0,
                                      of: calendar.startOfDay(for: day)) ?? day
        }
        if let who = reading.participant, !userSet.contains(.participant) {
            next.participant = LogParticipantRule.resolve(who, spouseTracking: spouseTracking)
        }
        if let text = reading.description, !userSet.contains(.description) {
            next.recordDescription = text
        }
        if !userSet.contains(.property) {
            next.propertyHint = Self.propertyHint(count: reading.mentionedPropertyCount)
        }

        let after = next.snapshot
        let differs = Self.differing(before, after, calendar: calendar).subtracting(userSet)
        next.droppedRemembered = false
        if reading.category == nil, next.categoryIsRemembered, !userSet.contains(.category) {
            next.category = nil
            next.categoryIsRemembered = false
            next.droppedRemembered = true
        }
        next.filled = differs
        next.filledBy = [:]
        for field in differs {
            next.filledBy[field] = Self.fieldTier(field, tier: tier, reading: reading, baseline: rulesBaseline, prior: priorTiers[field])
        }
        if differs.isEmpty {
            next.beforeFill = nil
            next.fillSource = nil
        } else {
            next.beforeFill = before
            next.fillSource = source
            next.fillTier = tier
        }
        let changed = Self.differing(current, after, calendar: calendar).subtracting(userSet)
        if tier == .model, late {
            for field in changed where priorTiers[field] == .rules {
                switch field {
                case .property: next.updatedAfterSeen[.property] = .property(current.propertyId)
                case .category: next.updatedAfterSeen[.category] = .category(current.category)
                case .hours: next.updatedAfterSeen[.hours] = .hours(current.hours, wasDefault: current.hoursIsDefault)
                case .date: next.updatedAfterSeen[.date] = .date(current.date)
                case .participant: next.updatedAfterSeen[.participant] = .participant(current.participant)
                case .description: break
                }
            }
        }
        next.updatedAfterSeen = next.updatedAfterSeen.filter { !userSet.contains($0.key) && differs.contains($0.key) }
        self = next
        return changed
    }

    /// A model value equal to the rules' own is still the rules' word; anything the model alone
    /// wrote (a different value, the description) is the model's.
    private static func fieldTier(_ field: LogField, tier: LogFillTier, reading: NoteReading,
                                  baseline: NoteReading?, prior: LogFillTier?) -> LogFillTier {
        guard tier == .model else { return .rules }
        guard let baseline else { return .model }
        let same: Bool
        switch field {
        case .property: same = reading.propertyId == baseline.propertyId
        case .category: same = reading.category == baseline.category
        case .hours: same = reading.hours == baseline.hours
        case .date: same = reading.date == baseline.date
        case .participant: same = reading.participant == baseline.participant
        case .description: same = false
        }
        return same && prior != .model ? .rules : .model
    }

    private static func differing(_ a: Snapshot, _ b: Snapshot, calendar: Calendar) -> Set<LogField> {
        var out = Set<LogField>()
        if a.propertyId != b.propertyId { out.insert(.property) }
        if a.category != b.category || a.categoryIsRemembered != b.categoryIsRemembered { out.insert(.category) }
        if a.hours != b.hours || a.hoursIsDefault != b.hoursIsDefault { out.insert(.hours) }
        if a.participant != b.participant { out.insert(.participant) }
        if !calendar.isDate(a.date, inSameDayAs: b.date) { out.insert(.date) }
        if a.recordDescription != b.recordDescription { out.insert(.description) }
        return out
    }

    static func propertyHint(count: Int) -> String? {
        count >= 2 ? lt("Your note mentions \(count) rentals. Log each one on its own.") : nil
    }

    var canUndoFill: Bool { beforeFill != nil && fillSource != nil }

    /// "Filled from your note · Undo": puts back exactly what was there before the fill.
    mutating func undoFill() {
        guard beforeFill != nil else { return }
        restoreBefore()
        updatedAfterSeen = [:]
    }

    private mutating func restoreBefore() {
        guard let before = beforeFill else { return }
        if filled.contains(.property) { propertyId = before.propertyId }
        if filled.contains(.category) {
            category = before.category
            categoryIsRemembered = before.categoryIsRemembered
        }
        if filled.contains(.hours) {
            hours = before.hours
            hoursIsDefault = before.hoursIsDefault
        }
        if filled.contains(.participant) { participant = before.participant }
        if filled.contains(.date) { date = before.date }
        if filled.contains(.description) { recordDescription = before.recordDescription }
        if droppedRemembered {
            category = before.category
            categoryIsRemembered = before.categoryIsRemembered
            droppedRemembered = false
        }
        propertyHint = nil
        filled = []
        filledBy = [:]
        fillSource = nil
        beforeFill = nil
    }

    /// A new note starts a new fill; the old caption goes away.
    mutating func clearFillCaption() {
        filled = []
        filledBy = [:]
        updatedAfterSeen = [:]
        fillSource = nil
        beforeFill = nil
    }

    /// Puts back what the model replaced on one row, and makes that value the user's.
    mutating func undoUpdate(_ field: LogField) {
        guard let old = updatedAfterSeen[field] else { return }
        switch old {
        case .property(let id): setProperty(id)
        case .category(let value):
            if let value { setCategory(value) }
        case .hours(let value, _): setHours(value)
        case .date(let value): setDate(value)
        case .participant(let value): setParticipant(value)
        }
        updatedAfterSeen[field] = nil
    }

    /// The row's "Updated" note timed out; the value stays.
    mutating func dismissUpdate(_ field: LogField) { updatedAfterSeen[field] = nil }

    // MARK: Validation

    /// The first thing the Log button still needs, or nil when it can log. With no rentals yet
    /// (`firstRunName` non-nil) the rental is the name typed on the sheet.
    func gap(properties: [RentalProperty], firstRunName: String? = nil) -> LogGap? {
        if properties.isEmpty {
            if (firstRunName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .name }
        } else if propertyId == nil || !properties.contains(where: { $0.id == propertyId }) {
            return .rental
        }
        if category == nil { return .kind }
        if hours <= 0 { return .hours }
        return nil
    }

    /// The one line under the button saying what's missing, or nil when it can be logged.
    func missingMessage(properties: [RentalProperty], firstRunName: String? = nil) -> String? {
        switch gap(properties: properties, firstRunName: firstRunName) {
        case .name?: return LogSaveResult.missingNameMessage
        case .rental?: return LogSaveResult.missingPropertyMessage
        case .kind?: return LogSaveResult.missingKindMessage
        case .hours?: return LogSaveResult.missingHoursMessage
        case nil: return nil
        }
    }

    func canLog(properties: [RentalProperty], firstRunName: String? = nil) -> Bool {
        gap(properties: properties, firstRunName: firstRunName) == nil
    }

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

    /// "Tue, Oct 14".
    static func longDay(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    /// "9:41" (no am / pm: the timer card says "started 9:41").
    static func clockTime(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }

    /// "1h 30m", "45m", "2h".
    static func hours(_ value: Double) -> String { LHFormat.hours(value) }

    /// "Log 1h 30m"; "Log time" with nothing to log.
    static func logButton(_ hours: Double) -> String {
        hours > 0 ? lt("Log \(Self.hours(hours))") : lt("Log time")
    }

    /// "Logged 1h 30m at Pine Cabin".
    static func loggedToast(hours: Double, propertyName: String?) -> String {
        guard let propertyName else { return lt("Logged \(Self.hours(hours))") }
        return lt("Logged \(Self.hours(hours)) at \(propertyName)")
    }

    /// "Pine Cabin added · Logged 1h".
    static func addedAndLoggedToast(hours: Double, propertyName: String) -> String {
        lt("\(propertyName) added · Logged \(Self.hours(hours))")
    }

    /// The header's day, worded exactly like the Date row and the details line: "Today · Sun, Oct 19",
    /// "Yesterday · Sat, Oct 18", else "Tue, Oct 14". One line, the date once, the word always agreeing
    /// with the selected day (it used to print yesterday's bare date above a "Yesterday" row).
    static func eyebrow(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day = LogTimeFormat.longDay(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return lt("Today \u{00B7}\u{00A0}\(day)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return lt("Yesterday \u{00B7}\u{00A0}\(day)")
        }
        return day
    }

    /// "Timer · Tue, Oct 14": the header of a stopped or recovered timer.
    static func timerEyebrow(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        lt("Timer \u{00B7}\u{00A0}\(eyebrow(date, now: now, calendar: calendar))")
    }

    /// "Today", "Yesterday", or the weekday ("Tue").
    static func dayWord(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return lt("Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return lt("Yesterday")
        }
        return date.formatted(Date.FormatStyle(calendar: calendar).weekday(.abbreviated))
    }

    /// The Date row: "Today, Oct 19", "Yesterday, Oct 18", "Tue, Oct 14".
    static func dateRow(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        let short = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return lt("Today, \(short)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return lt("Yesterday, \(short)")
        }
        return LogTimeFormat.longDay(date, calendar: calendar)
    }

    /// What the Log button says it will do: hours and rental (plus the day when it isn't today),
    /// or the first thing still missing. The button is never dead; tapping a gap opens that editor.
    /// Spaces inside each phrase are non-breaking, so a wrapped label breaks before "at", never
    /// inside "Pine Cabin". At AX sizes the day is left off (the Date row says it).
    static func buttonTitle(form: LogForm, properties: [RentalProperty], firstRunName: String? = nil,
                            now: Date = Date(), calendar: Calendar = .current, ax: Bool = false) -> String {
        switch form.gap(properties: properties, firstRunName: firstRunName) {
        case .name?: return lt("Name your rental")
        case .rental?: return lt("Pick a rental")
        case .kind?: return lt("Pick the kind of work")
        case .hours?: return lt("Add how long it took")
        case nil:
            func nb(_ text: String) -> String { text.replacingOccurrences(of: " ", with: "\u{00A0}") }
            let hoursText = hours(form.hours)
            var text: String
            if let name = firstRunName?.trimmingCharacters(in: .whitespacesAndNewlines), properties.isEmpty {
                text = nb(lt("Add \(name) and log \(hoursText)"))
            } else {
                let name = properties.first { $0.id == form.propertyId }?.name ?? ""
                text = nb(lt("Log \(hoursText)")) + " " + nb(lt("at \(name)"))
            }
            // At accessibility sizes the day stays on the Date row: the button keeps to two lines.
            if !ax, !calendar.isDate(form.date, inSameDayAs: now) {
                text += "\u{00A0}\u{00B7} " + dayWord(form.date, now: now, calendar: calendar)
            }
            return text
        }
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
        guard minutes > 0 else { return lt("Timer ran under a minute") }
        return lt("Timer ran \(LHFormat.hours(Double(minutes) / 60))")
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

    /// The "+" route (tab 2: Review timer notification or widget, intents, 1.x posts): a running
    /// timer opens its card, a stopped timer waiting for its note opens that review, else a new log.
    static func forPlusRoute(isTimerRunning: Bool, stoppedDraft: StoppedTimerDraft?) -> LogSheetRoute {
        if isTimerRunning { return .timer }
        if stoppedDraft != nil { return .timerReview }
        return .log
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
