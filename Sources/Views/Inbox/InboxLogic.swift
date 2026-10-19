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

enum InboxGroup: String, CaseIterable, Identifiable {
    case today
    case thisWeek
    case earlier

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This week"
        case .earlier: return "Earlier"
        }
    }
}

struct InboxSection: Identifiable, Equatable {
    var group: InboxGroup
    var items: [Suggestion]
    var id: String { group.id }
}

enum InboxLogic {
    /// Items the inbox shows now: pending, and the event is over (an upcoming event's
    /// suggestion becomes visible at its `detectedAt`, which is the event end).
    static func visible(_ suggestions: [Suggestion], now: Date) -> [Suggestion] {
        suggestions.filter { $0.isPending && $0.detectedAt <= now }
    }

    /// Today / This week (the 6 days before today) / Earlier, by when the work happened.
    /// Newest first inside each group; empty groups are left out.
    static func sections(_ suggestions: [Suggestion], now: Date, calendar: Calendar = .current) -> [InboxSection] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        var buckets: [InboxGroup: [Suggestion]] = [:]
        for suggestion in visible(suggestions, now: now) {
            let group: InboxGroup
            if suggestion.start >= startOfToday {
                group = .today
            } else if suggestion.start >= startOfWeek {
                group = .thisWeek
            } else {
                group = .earlier
            }
            buckets[group, default: []].append(suggestion)
        }
        return InboxGroup.allCases.compactMap { group in
            guard let items = buckets[group], !items.isEmpty else { return nil }
            return InboxSection(group: group, items: items.sorted { $0.start > $1.start })
        }
    }

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
        case .calendar: return "Calendar"
        case .receipt: return "Receipt"
        case .location: return "Location"
        case .gmail: return "Email"
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
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = (0..<7).contains(days) ? "EEE" : "MMM d"
        return formatter.string(from: date)
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
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    static func clockTime(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }
}
