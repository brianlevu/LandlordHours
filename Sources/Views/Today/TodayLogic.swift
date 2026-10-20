import Foundation

// MARK: - Today, below the house: the rules (pure, unit-tested)
//
// redesign-specs.md §2. Everything that decides WHAT Today shows under the hero lives here, so
// the count source, the caught-up states, the week maths and the spouse rule are tested without
// views. The views in TodayComponents.swift only draw what these return.

/// The "To confirm" block. Its items and its count come from the Inbox's own list
/// (`InboxViewModel.visible`), so the capsule, "Review all N" and the Inbox tab badge are one
/// number and can never drift apart.
enum TodayConfirm {
    /// Rows shown in the card before "Review all N".
    static let rowLimit = 3

    enum State: Equatable {
        /// No property yet: the hero's empty lot carries the one action, so the block is hidden.
        case hidden
        /// One or more items waiting (rows, most likely first).
        case rows
        /// The look-back is still scanning and nothing has turned up yet.
        case loading
        /// Nothing pending. `captureOn == false` offers to turn suggestions on.
        case caughtUp(captureOn: Bool)
    }

    static func state(hasProperties: Bool, pendingCount: Int, backfillScanning: Bool, captureOn: Bool) -> State {
        guard hasProperties else { return .hidden }
        if pendingCount > 0 { return .rows }
        if backfillScanning { return .loading }
        return .caughtUp(captureOn: captureOn)
    }

    /// The badge number: every visible pending item (the Inbox's `badgeCount`).
    static func count(visible: [Suggestion]) -> Int { visible.count }

    /// The rows Today shows: most likely first (the Inbox's backfill ranking), at most three.
    static func rows(visible: [Suggestion]) -> [Suggestion] {
        Array(InboxLogic.ranked(visible).prefix(rowLimit))
    }

    /// "Review all 8" shows only when there is more than the card holds.
    static func showsReviewAll(count: Int) -> Bool { count > rowLimit }
}

// MARK: - This week

/// One column of the week strip.
struct TodayWeekDay: Equatable, Identifiable {
    /// Start of the day in the calendar's time zone.
    let date: Date
    /// Countable confirmed hours; nil for a day that hasn't happened yet.
    let hours: Double?
    let isToday: Bool
    /// "M", "T" … (the strip) and "Mon" … (the XXL list and VoiceOver).
    let letter: String
    let shortName: String
    let fullName: String

    var id: Date { date }
    var isFuture: Bool { hours == nil }
}

enum TodayWeek {
    /// The week starts on Monday (the approved strip reads M T W T F S S), whatever the locale.
    static func mondayCalendar(_ base: Calendar) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        return calendar
    }

    static func startOfWeek(containing date: Date, calendar base: Calendar) -> Date {
        let calendar = mondayCalendar(base)
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Whether an entry counts toward the goal the house measures, with the house's own spouse
    /// rule: REPS counts your own hours only (the IRS tests each spouse alone; spouse hours never
    /// combine). Material participation adds spouse hours only when the household tracks them
    /// jointly. Investor-only tasks (investing, financing, negotiation) never count.
    static func counts(_ entry: TimeEntry, goal: HouseGoal, includeSpouse: Bool) -> Bool {
        guard entry.countsForREPS else { return false }
        switch entry.participant {
        case .selfParticipant: return true
        case .spouse: return goal != .reps750 && includeSpouse
        }
    }

    /// Monday to Sunday of the week containing `now`. Days are walked with the calendar (never
    /// 24h steps), so a daylight-saving change can't shift an entry into the wrong day.
    static func days(
        entries: [TimeEntry],
        goal: HouseGoal,
        includeSpouse: Bool,
        now: Date,
        calendar base: Calendar = .current
    ) -> [TodayWeekDay] {
        let calendar = mondayCalendar(base)
        let start = startOfWeek(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let counted = entries.filter { counts($0, goal: goal, includeSpouse: includeSpouse) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let dayStart = calendar.startOfDay(for: day)
            let future = dayStart > today
            let hours = future ? nil : counted
                .filter { calendar.isDate($0.date, inSameDayAs: dayStart) }
                .reduce(0) { $0 + $1.hours }
            formatter.dateFormat = "EEE"
            let short = formatter.string(from: dayStart)
            formatter.dateFormat = "EEEE"
            let full = formatter.string(from: dayStart)
            return TodayWeekDay(date: dayStart, hours: hours, isToday: dayStart == today,
                                letter: String(short.prefix(1)), shortName: short, fullName: full)
        }
    }

    static func total(_ days: [TodayWeekDay]) -> Double {
        days.compactMap(\.hours).reduce(0, +)
    }

    /// The one bar that carries its value: the tallest, earliest on a tie; none when all are 0.
    static func labelledIndex(_ days: [TodayWeekDay]) -> Int? {
        let peak = days.compactMap(\.hours).max() ?? 0
        guard peak > 0 else { return nil }
        return days.firstIndex { $0.hours == peak }
    }

    /// Bar height for the 56pt strip (a 10pt floor, so a short day still reads as a capsule).
    static func barHeight(hours: Double, peak: Double, maxHeight: Double = 56, minHeight: Double = 10) -> Double {
        guard hours > 0, peak > 0 else { return 0 }
        return max(minHeight, maxHeight * min(hours / peak, 1))
    }

    /// "Monday, 2 hours", "Thursday, no hours", "Saturday, not yet" for VoiceOver.
    static func spoken(_ day: TodayWeekDay) -> String {
        guard let hours = day.hours else { return "\(day.fullName), not yet" }
        let words = hours > 0 ? InboxFormat.spokenHours(hours) : "no hours"
        return "\(day.fullName)\(day.isToday ? ", today" : ""), \(words)"
    }
}

// MARK: - Pace cards

/// The two cards under the week: the 50% rule (REPS) or days left (material participation), and
/// the hours a week still needed. Caution colour only when behind.
struct TodayPaceCardModel: Equatable {
    enum Tone: Equatable { case neutral, caution, positive }
    let label: String
    let value: String
    let status: String?
    let tone: Tone
}

enum TodayPaceCards {
    static func weeksLeft(now: Date, calendar: Calendar = .current) -> Double {
        let year = calendar.component(.year, from: now)
        guard let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { return 1 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0
        return max(Double(max(days, 1)) / 7, 1)
    }

    static func finish(hours: Double, goal: HouseGoal, pace: TodayPace, now: Date, calendar: Calendar = .current) -> TodayPaceCardModel {
        if HouseProgress(hours: hours, goal: goal).isGoalMet {
            return TodayPaceCardModel(label: "Goal hours", value: "Reached", status: "Keep logging for your record", tone: .positive)
        }
        let remaining = max(goal.targetHours - hours, 0.01)
        let perWeek = Int((remaining / weeksLeft(now: now, calendar: calendar)).rounded(.up))
        let behind = pace.tone == .caution
        return TodayPaceCardModel(
            label: "To finish by Dec 31",
            value: "\(perWeek)h a week",
            status: behind ? "Behind pace" : (pace.tone == .positive ? "On pace" : nil),
            tone: behind ? .caution : .neutral
        )
    }
}
