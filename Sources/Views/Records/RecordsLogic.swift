import Foundation

// MARK: - Records: pure logic (grouping, totals, source badges, filters)
//
// Kept out of the view so it can be unit-tested without a simulator.

/// Where a record came from, as the Records list labels it.
enum RecordSourceBadge: String, CaseIterable, Equatable {
    case manual
    case timer
    case voice
    case calendarImport
    case suggested
    case other

    init(entry: TimeEntry) {
        // A confirmed 2.0 suggestion is "Suggested" whatever detector found it.
        if entry.confirmedAt != nil {
            self = .suggested
            return
        }
        switch entry.source {
        case .manual: self = .manual
        case .timer: self = .timer
        case .voice: self = .voice
        case .calendar: self = .calendarImport
        default: self = .other
        }
    }

    var title: String {
        switch self {
        case .manual: return "Manual"
        case .timer: return "Timer"
        case .voice: return "Voice"
        case .calendarImport: return "Calendar import"
        case .suggested: return "Suggested"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .manual: return "pencil"
        case .timer: return "timer"
        case .voice: return "waveform"
        case .calendarImport: return "calendar"
        case .suggested: return "tray.and.arrow.down"
        case .other: return "questionmark.circle"
        }
    }

    /// The filter menu lists the sources that can occur, in this order.
    static let filterOrder: [RecordSourceBadge] = [.manual, .timer, .voice, .calendarImport, .suggested, .other]
}

struct RecordsMonthSection: Identifiable, Equatable {
    /// First day of the month.
    let month: Date
    let entries: [TimeEntry]

    var id: Date { month }
    var totalHours: Double { entries.reduce(0) { $0 + $1.hours } }

    static func == (lhs: RecordsMonthSection, rhs: RecordsMonthSection) -> Bool {
        lhs.month == rhs.month && lhs.entries.map(\.id) == rhs.entries.map(\.id)
    }
}

struct RecordsFilter: Equatable {
    var year: Int
    var propertyId: UUID?
    var source: RecordSourceBadge?
    var participant: Participant?
    var searchText: String = ""

    var isNarrowed: Bool {
        propertyId != nil || source != nil || participant != nil
            || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum RecordsLogic {
    /// The one sentence under the total, so "All logged hours" (which includes a spouse's
    /// entries and non-countable tasks) is never read as the qualification number on Today.
    static func totalLabel(goal: HouseGoal, tracksSpouseJointly: Bool) -> String {
        switch goal {
        case .reps750:
            return "All logged hours. The 750h test counts your hours only."
        case .mp500, .mp100:
            let target = Int(goal.targetHours)
            return tracksSpouseJointly
                ? "All logged hours. The \(target)h test counts you and your spouse."
                : "All logged hours. The \(target)h test counts your hours only."
        }
    }

    /// Row title: the note's first line, or the category when there is no note.
    static func title(for entry: TimeEntry) -> String {
        let firstLine = entry.notes
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return firstLine.isEmpty ? entry.category.inboxLabel : firstLine
    }

    static func filtered(
        _ entries: [TimeEntry],
        filter: RecordsFilter,
        propertyName: (UUID) -> String?,
        calendar: Calendar = .current
    ) -> [TimeEntry] {
        let query = filter.searchText.trimmingCharacters(in: .whitespaces)
        return entries
            .filter { calendar.component(.year, from: $0.date) == filter.year }
            .filter { filter.propertyId == nil || $0.propertyId == filter.propertyId }
            .filter { filter.participant == nil || $0.participant == filter.participant }
            .filter { filter.source == nil || RecordSourceBadge(entry: $0) == filter.source }
            .filter { entry in
                guard !query.isEmpty else { return true }
                let haystack = [entry.notes, entry.category.inboxLabel, entry.category.rawValue, propertyName(entry.propertyId) ?? ""]
                return haystack.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
            .sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.createdAt > rhs.createdAt : lhs.date > rhs.date
            }
    }

    /// Newest month first; entries newest first inside each month.
    static func monthSections(_ entries: [TimeEntry], calendar: Calendar = .current) -> [RecordsMonthSection] {
        let grouped = Dictionary(grouping: entries) { entry -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date)) ?? entry.date
        }
        return grouped.keys.sorted(by: >).map { month in
            RecordsMonthSection(
                month: month,
                entries: (grouped[month] ?? []).sorted { $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date }
            )
        }
    }

    /// Years the picker offers: every year with records, plus the current year.
    static func availableYears(_ entries: [TimeEntry], now: Date = Date(), calendar: Calendar = .current) -> [Int] {
        var years = Set(entries.map { calendar.component(.year, from: $0.date) })
        years.insert(calendar.component(.year, from: now))
        return years.sorted(by: >)
    }
}
