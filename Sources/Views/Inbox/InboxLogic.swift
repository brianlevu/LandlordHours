import Foundation

/// The inbox's notion of "now". DEBUG captures pin it (`-LHFixedNow`) so frames do not depend
/// on the time of day they were taken.
enum InboxClock {
    nonisolated(unsafe) static var now: () -> Date = { Date() }
}

// MARK: - Inbox rules (pure, unit-tested)
//
// Everything that decides WHAT the inbox shows lives here, so grouping, ranking, badges and the
// swipe-to-log rule are tested without views.

/// One day of the Inbox list: a day header (standard §1.15a) over that day's rows.
struct InboxSection: Identifiable, Equatable {
    /// The start of the day the work happened.
    var day: Date
    var items: [Suggestion]
    var id: Date { day }
}

enum InboxLogic {
    /// Items the inbox shows now: pending, and the event is over (an upcoming event's
    /// suggestion becomes visible at its `detectedAt`, which is the event end).
    static func visible(_ suggestions: [Suggestion], now: Date) -> [Suggestion] {
        suggestions.filter { $0.isPending && $0.detectedAt <= now }
    }

    /// One section per day, newest day first; inside a day, by start time (§1.15a). Days with
    /// nothing in them are left out.
    static func sections(_ suggestions: [Suggestion], now: Date, calendar: Calendar = .current) -> [InboxSection] {
        let byDay = Dictionary(grouping: visible(suggestions, now: now)) { calendar.startOfDay(for: $0.start) }
        return byDay.keys.sorted(by: >).map { day in
            InboxSection(day: day, items: (byDay[day] ?? []).sorted { $0.start < $1.start })
        }
    }

    /// The rows "Confirm N likely" logs: nothing needs a decision (`canQuickLog`) and the
    /// classifier is sure (not "Not sure"). §1.3 Batch.
    static func likely(_ suggestions: [Suggestion], propertyIds: Set<UUID>) -> [Suggestion] {
        suggestions.filter { canQuickLog($0, propertyIds: propertyIds) && !badges(for: $0).notSure }
    }

    /// The foot / bar shows from two rows up (§1.3 Batch).
    static let batchMinimum = 2

    /// Backfill order: most confident first; at equal confidence, items that are NOT flagged
    /// "might already be logged" first, then newest.
    static func ranked(_ suggestions: [Suggestion]) -> [Suggestion] {
        suggestions.sorted { a, b in
            if a.confidence != b.confidence { return a.confidence > b.confidence }
            if a.mightAlreadyBeLogged != b.mightAlreadyBeLogged { return !a.mightAlreadyBeLogged }
            return a.start > b.start
        }
    }

    /// How many the backfill intro shows before "Show more".
    static let backfillPreviewLimit = 15

    static func badges(for suggestion: Suggestion) -> SuggestionBadges {
        SuggestionBadges(
            notSure: suggestion.confidence < ClassifierThresholds.likely,
            mightAlreadyBeLogged: suggestion.mightAlreadyBeLogged,
            needsHours: suggestion.hoursBasis == .none || (suggestion.proposedHours ?? 0) <= 0
        )
    }

    /// A swipe logs straight away only when nothing needs a decision: the hours come from the
    /// calendar schedule, the proposal is complete, and nothing looks already logged.
    /// Anything else opens the confirm sheet instead.
    static func canQuickLog(_ suggestion: Suggestion, propertyIds: Set<UUID>) -> Bool {
        guard suggestion.isPending, suggestion.hoursBasis == .scheduled else { return false }
        guard let hours = suggestion.proposedHours, hours > 0 else { return false }
        guard let property = suggestion.proposedPropertyId, propertyIds.contains(property) else { return false }
        guard suggestion.proposedCategory != nil else { return false }
        return !suggestion.mightAlreadyBeLogged
    }

    /// The mute rule offered by "Don't suggest events like this".
    static func muteRule(forTitleOf suggestion: Suggestion) -> CaptureMuteRule? {
        let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return CaptureMuteRule(match: .titleContains, value: title)
    }

    static func muteRule(forCalendarOf suggestion: Suggestion) -> CaptureMuteRule? {
        guard let container = suggestion.containerId, !container.isEmpty else { return nil }
        return CaptureMuteRule(match: .containerId, value: container)
    }
}

struct SuggestionBadges: Equatable {
    /// Below the "likely" line: shown as "Not sure", never hidden.
    var notSure: Bool
    /// Hours already logged look like this item. Never pre-selected or swipe-logged.
    var mightAlreadyBeLogged: Bool
    /// No hours to propose (receipts, unknown length): the sheet asks.
    var needsHours: Bool
}

// MARK: - Formatting

enum InboxFormat {
    /// One `DateFormatter` per (pattern, calendar, locale): the list formats a date per row per layout
    /// pass, and building a formatter each time dominated a scroll.
    private static let formatters = NSCache<NSString, DateFormatter>()

    private static func formatter(_ pattern: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let key = "\(pattern)|\(calendar.identifier)|\(calendar.timeZone.identifier)|\(locale.identifier)" as NSString
        if let cached = formatters.object(forKey: key) { return cached }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = pattern
        formatters.setObject(formatter, forKey: key)
        return formatter
    }

    /// "2h", "1h 30m", "45m".
    static func hours(_ value: Double) -> String {
        let totalMinutes = Int((value * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        switch (h, m) {
        case (0, _): return "\(m)m"
        case (_, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }

    /// The day header over a day's rows (§1.15a), the one source: "Today", "Yesterday", weekday and
    /// date for the days before that in the last week ("Mon Oct 19"), then "Oct 12", and
    /// "Oct 12, 2025" in another year. The patterns are localizable.
    static func dayHeader(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let startOfDate = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 99
        if days == 0 { return String(localized: "inbox.day.today", defaultValue: "Today", table: "Inbox") }
        if days == 1 { return String(localized: "inbox.day.yesterday", defaultValue: "Yesterday", table: "Inbox") }
        let pattern: String
        if (2...6).contains(days) {
            pattern = String(localized: "inbox.day.weekPattern", defaultValue: "EEE MMM d", table: "Inbox",
                             comment: "Date pattern for a day in the last week, e.g. Mon Oct 19")
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            pattern = String(localized: "inbox.day.datePattern", defaultValue: "MMM d", table: "Inbox",
                             comment: "Date pattern for an older day this year, e.g. Oct 12")
        } else {
            pattern = String(localized: "inbox.day.yearPattern", defaultValue: "MMM d, yyyy", table: "Inbox",
                             comment: "Date pattern for a day in another year, e.g. Oct 12, 2025")
        }
        // A calendar without a real locale (the root locale) formats months as "M10": use the user's.
        let calendarLocale = calendar.locale
        let locale = (calendarLocale?.identifier.isEmpty ?? true) ? Locale.current : (calendarLocale ?? .current)
        return formatter(pattern, calendar: calendar, locale: locale).string(from: date)
    }

    /// "Plumber at Pine Cabin" (§1.3): the one function for a decision row's title and the confirm
    /// sheet's.
    static func rowTitle(_ suggestion: Suggestion, propertyName: String?) -> String {
        guard let propertyName, !propertyName.isEmpty else { return suggestion.title }
        return String(localized: "inbox.row.title", defaultValue: "\(suggestion.title) at \(propertyName)", table: "Inbox",
                      comment: "A suggestion's title at a rental, e.g. Plumber at Pine Cabin")
    }

    /// The meta line's time range, "12–2" (§1.3: the glyph names the source and the day header the
    /// date). A receipt has no time, so it says "Receipt". Word joiners keep "9–10:30" on one line.
    static func rowMeta(_ suggestion: Suggestion, calendar: Calendar = .current) -> String {
        if suggestion.kind == .receipt { return kindLabel(suggestion.kind) }
        return timeRange(start: suggestion.start, end: suggestion.end, calendar: calendar)
            .replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")
    }

    /// "2 hours", "1 hour 30 minutes" for VoiceOver.
    static func spokenHours(_ value: Double) -> String {
        let totalMinutes = Int((value * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        return parts.isEmpty ? "0 minutes" : parts.joined(separator: " ")
    }

    static func kindLabel(_ kind: Suggestion.Kind) -> String {
        switch kind {
        case .calendar: return String(localized: "inbox.kind.calendar", defaultValue: "Calendar", table: "Inbox")
        case .receipt: return String(localized: "inbox.kind.receipt", defaultValue: "Receipt", table: "Inbox")
        case .location: return String(localized: "inbox.kind.location", defaultValue: "Location", table: "Inbox")
        case .gmail: return String(localized: "inbox.kind.email", defaultValue: "Email", table: "Inbox")
        }
    }

    static func kindSymbol(_ kind: Suggestion.Kind) -> String {
        switch kind {
        case .calendar: return "calendar"
        case .receipt: return "doc.text"
        case .location: return "location.fill"
        case .gmail: return "envelope"
        }
    }

    /// "Today", "Yesterday", "Tue" (this week), "Oct 3".
    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        return formatter((0..<7).contains(days) ? "EEE" : "MMM d", calendar: calendar, locale: Locale(identifier: "en_US")).string(from: date)
    }

    /// "9–11", "5:30–6:30", "11:30–1".
    static func timeRange(start: Date, end: Date?, calendar: Calendar = .current) -> String {
        func clock(_ date: Date) -> String {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            let hour12 = ((c.hour ?? 0) + 11) % 12 + 1
            return (c.minute ?? 0) == 0 ? "\(hour12)" : String(format: "%d:%02d", hour12, c.minute ?? 0)
        }
        guard let end, end > start else { return clock(start) }
        return "\(clock(start))–\(clock(end))"
    }

    /// "Calendar · Tue 9–11".
    static func sourceLine(_ suggestion: Suggestion, now: Date, calendar: Calendar = .current) -> String {
        let when = day(suggestion.start, now: now, calendar: calendar)
        if suggestion.kind == .receipt { return "\(kindLabel(suggestion.kind)) · \(when)" }
        return "\(kindLabel(suggestion.kind)) · \(when) \(timeRange(start: suggestion.start, end: suggestion.end, calendar: calendar))"
    }

    /// "TUE, OCT 14" for the sheet eyebrow.
    static func longDay(_ date: Date, calendar: Calendar = .current) -> String {
        return formatter("EEE, MMM d", calendar: calendar, locale: Locale(identifier: "en_US")).string(from: date)
    }

    static func clockTime(_ date: Date, calendar: Calendar = .current) -> String {
        return formatter("h:mm", calendar: calendar, locale: Locale(identifier: "en_US")).string(from: date)
    }
}
