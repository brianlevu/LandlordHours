import Foundation
import SwiftUI

// MARK: - Today, below the house: the rules (pure, unit-tested)
//
// redesign-specs.md §2. Everything that decides WHAT Today shows under the hero lives here, so
// the count source, the caught-up states, the week maths and the spouse rule are tested without
// views. The views in TodayComponents.swift only draw what these return.

/// The "To confirm" block. Its items and its count come from the Inbox's own list
/// (`InboxViewModel.visible`), so the count, "See all N" and the Inbox tab badge are one number
/// and can never drift apart. v2 (§H.8): at most two rows on Today (one under 700pt of window
/// height or at XXL), then a "See all N" foot.
enum TodayConfirm {
    /// Rows shown on Today at the default size (§H.8).
    static let rowLimit = 2

    enum State: Equatable {
        /// No property yet: the hero's own action carries the screen, so the block is hidden.
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

    /// The items Today counts for the page shown: every visible item on "All rentals" (rentalID nil),
    /// only that rental's items on a single-rental page.
    static func scoped(_ visible: [Suggestion], rentalID: UUID?) -> [Suggestion] {
        guard let rentalID else { return visible }
        return visible.filter { $0.proposedPropertyId == rentalID }
    }

    /// The count in the header: the visible pending items for the page shown.
    static func count(visible: [Suggestion], rentalID: UUID? = nil) -> Int { scoped(visible, rentalID: rentalID).count }

    /// The rows Today shows: most likely first (the Inbox's backfill ranking), at most `limit`.
    static func rows(visible: [Suggestion], rentalID: UUID? = nil, limit: Int = rowLimit) -> [Suggestion] {
        Array(InboxLogic.ranked(scoped(visible, rentalID: rentalID)).prefix(max(0, limit)))
    }

    /// The "See all N" foot shows when more are waiting than the rows hold.
    static func showsReviewAll(count: Int, limit: Int = rowLimit) -> Bool { count > max(0, limit) }

    /// §H.8 / D3b: 2 rows at default; 1 when the window is under 700pt tall or the text is at XXL
    /// or XXXL (the AX sizes scroll, so they keep 2).
    static func rowLimit(windowHeight: CGFloat, typeSize: DynamicTypeSize) -> Int {
        if typeSize.isAccessibilitySize { return rowLimit }
        if windowHeight > 0 && windowHeight < 700 { return 1 }
        if typeSize >= .xxLarge { return 1 }
        return rowLimit
    }
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
    /// `repsParticipant` is whose own count the 750 follows (the spouse's when the spouse is the
    /// real estate professional); every other goal counts the owner, plus the spouse when joint.
    static func counts(_ entry: TimeEntry, goal: HouseGoal, includeSpouse: Bool, repsParticipant: Participant = .selfParticipant) -> Bool {
        guard entry.countsForREPS else { return false }
        if goal == .reps750 { return entry.participant == repsParticipant }
        switch entry.participant {
        case .selfParticipant: return true
        case .spouse: return includeSpouse
        }
    }

    /// Monday to Sunday of the week containing `now`. Days are walked with the calendar (never
    /// 24h steps), so a daylight-saving change can't shift an entry into the wrong day.
    static func days(
        entries: [TimeEntry],
        goal: HouseGoal,
        includeSpouse: Bool,
        repsParticipant: Participant = .selfParticipant,
        now: Date,
        calendar base: Calendar = .current
    ) -> [TodayWeekDay] {
        let calendar = mondayCalendar(base)
        let start = startOfWeek(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let counted = entries.filter { counts($0, goal: goal, includeSpouse: includeSpouse, repsParticipant: repsParticipant) }
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

    static func finish(hours: Double, goal: HouseGoal, pace: TodayPace, now: Date, calendar: Calendar = .current, paceReady: Bool = true) -> TodayPaceCardModel {
        if HouseProgress(hours: hours, goal: goal).isGoalMet {
            return TodayPaceCardModel(label: "Goal hours", value: "Reached", status: "Keep logging for your record", tone: .positive)
        }
        if !paceReady {
            // After one hour, "74h a week" is noise: the number waits for enough hours.
            return TodayPaceCardModel(label: String(localized: "To finish by Dec 31"), value: String(localized: "Not yet"),
                                      status: String(localized: "Needs a few weeks of hours"), tone: .neutral)
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


// MARK: - The hero's words: the target, whose count it is, and where you stand

/// What the Today hero says (goal-first messaging, 2.0). One pure type so every state is tested:
/// the eyebrow names the target, the caption says how far along you are against Dec 31, and the
/// 750 and 100-hour tests add what makes them different (whose count, and "more than anyone
/// else"). The 100-hour test is never shown as reached until the owner confirms no one did more.
struct TodayHeroCopy: Equatable {
    /// "2026 · 500-hour target", or "2026 · Tahoe cabin · 100-hour target" when the count is one rental's
    /// (the view sets it in mono capitals).
    let eyebrow: String
    /// The pieces of the eyebrow, so a long rental name can shorten with an ellipsis and the rest never wraps.
    let eyebrowYear: String
    let eyebrowTarget: String
    let propertyName: String?
    /// The target in hours; nil for "just keep a record".
    let targetHours: Int?
    /// "your own count", "spouse’s own count" or "more than anyone else"; nil for 500 hours.
    let qualifier: String?
    /// "of 500 hours".
    let caption: String
    /// What follows the caption, lower case: "on pace for Dec 31", "9h a week to finish by Dec 31".
    let phrase: String?
    let tone: HouseStatusTone
    /// The 100-hour test is over 100 hours and waiting on "did anyone do more?": the hero opens that question.
    let needsConfirmation: Bool
    /// The hours target is reached AND nothing about it is still open (the half test, the 100-hour question).
    let claimsReached: Bool

    /// The status line as a sentence: "On pace for Dec 31".
    var status: String? { phrase.map(Self.sentenceCased) }

    /// One line for VoiceOver and tests: "of 500 hours · on pace for Dec 31".
    var spoken: String {
        guard let phrase else { return caption }
        return String(localized: "\(caption) · \(phrase)")
    }

    /// The empty lot's line, with the person's own target when one is set.
    static func emptyLotLine(target: Int?) -> String {
        target.map { String(localized: "Add a rental. Hours you confirm count toward your \($0).") }
            ?? String(localized: "Add a rental. Hours you confirm count toward your goal.")
    }

    static func sentenceCased(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    struct Input {
        var goal: HouseGoal
        /// "Just keep a record": no target, no pace.
        var isRecord = false
        var hours: Double
        var year: Int
        var now: Date
        var calendar: Calendar = .current
        /// Whose own count the 750 follows.
        var repsParticipant: Participant = .selfParticipant
        /// The half test for that person: only meaningful for the 750.
        var halfTest: TaxQualificationEngine.MoreThanHalfStatus = .notEntered
        /// This year's "did anyone else do more?" answer (nil = unanswered).
        var noOneParticipatedMore: Bool?
        /// The rental the count belongs to (100 and 500 hour tests are counted per rental); nil when
        /// the count covers every rental (a grouping election, the 750, a record).
        var propertyName: String?
        /// Days since the first hour this year was logged; the pace waits for enough of them.
        var daysOfData: Int = .max
        /// Something is waiting in the Inbox to confirm.
        var hasPendingToConfirm = false
    }

    /// Pace needs two weeks of hours or ten confirmed hours, whichever comes first.
    static let paceMinDays = 14
    static let paceMinHours = 10.0

    static func paceIsReady(hours: Double, daysOfData: Int) -> Bool {
        hours >= paceMinHours || daysOfData >= paceMinDays
    }

    /// The line under the Today title: "212h toward 750 this year." (no ".0"), or for a record "212 hours logged this year."
    static func headerLine(hours: Double, target: Int, isRecord: Bool, year: Int) -> String {
        isRecord
            ? String(localized: "\(OnbFormat.hoursInWords(hours)) logged in \(String(year)).")
            : String(localized: "\(OnbFormat.hours(hours)) toward \(target) this year.")
    }

    static func make(_ i: Input) -> TodayHeroCopy {
        let target = Int(i.goal.targetHours)
        let yearText = String(i.year)
        if i.isRecord {
            return TodayHeroCopy(
                eyebrow: String(localized: "\(yearText) · Your record"),
                eyebrowYear: yearText, eyebrowTarget: String(localized: "Your record"), propertyName: nil, targetHours: nil,
                qualifier: nil,
                caption: String(localized: "hours logged in \(yearText)"),
                phrase: nil, tone: .neutral, needsConfirmation: false, claimsReached: false)
        }
        let targetText = String(localized: "\(target)-hour target")
        let name = i.propertyName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let eyebrow = name.map { String(localized: "\(yearText) · \($0) · \(targetText)") } ?? String(localized: "\(yearText) · \(targetText)")
        let caption = String(localized: "of \(target) hours")
        let qualifier: String?
        switch i.goal {
        case .reps750:
            qualifier = i.repsParticipant == .spouse ? String(localized: "spouse’s own count") : String(localized: "your own count")
        case .mp100: qualifier = String(localized: "more than anyone else")
        case .mp500: qualifier = nil
        }
        func result(_ phrase: String?, _ tone: HouseStatusTone, confirm: Bool = false, reached: Bool = false) -> TodayHeroCopy {
            TodayHeroCopy(eyebrow: eyebrow, eyebrowYear: yearText, eyebrowTarget: targetText, propertyName: name, targetHours: target,
                          qualifier: qualifier, caption: caption, phrase: phrase, tone: tone,
                          needsConfirmation: confirm, claimsReached: reached)
        }

        if HouseProgress(hours: i.hours, goal: i.goal).isGoalMet {
            switch i.goal {
            case .reps750:
                switch i.halfTest {
                case .met: return result(String(localized: "reached, based on your records"), .positive, reached: true)
                case .notEntered: return result(String(localized: "750 reached. Add your other work hours to check the half rule."), .caution)
                case .notMet: return result(String(localized: "750 reached. The half rule isn’t met yet."), .caution)
                }
            case .mp500:
                return result(String(localized: "reached, based on your records"), .positive, reached: true)
            case .mp100:
                switch i.noOneParticipatedMore {
                case true?: return result(String(localized: "reached · no one did more, based on your records"), .positive, reached: true)
                case false?: return result(String(localized: "someone else did more"), .caution)
                case nil: return result(String(localized: "confirm no one did more"), .caution, confirm: true)
                }
            }
        }

        // Pace waits for two weeks of hours or ten confirmed hours: after one hour "74h a week" is noise.
        if !paceIsReady(hours: i.hours, daysOfData: i.daysOfData) {
            return result(i.hasPendingToConfirm ? String(localized: "Confirm your found hours to see your pace.")
                                                : String(localized: "Log a few weeks to see your pace."), .neutral)
        }
        let weeks = TodayPaceCards.weeksLeft(now: i.now, calendar: i.calendar)
        let perWeek = Int((max(i.goal.targetHours - i.hours, 0.01) / weeks).rounded(.up))
        let finishLine = String(localized: "\(perWeek)h a week to finish by Dec 31")
        let day = Double(i.calendar.ordinality(of: .day, in: .year, for: i.now) ?? 1)
        let daysInYear = Double(i.calendar.range(of: .day, in: .year, for: i.now)?.count ?? 365)
        let expected = i.goal.targetHours * day / daysInYear
        return i.hours >= expected
            ? result(String(localized: "on pace for Dec 31"), .positive)
            : result(finishLine, .caution)
    }
}

// MARK: - v2: the crafted hero's focus, figures and pace sentence (standard §H.1 H10, §H.8)

/// How a status line reads: met/on pace, behind, or nothing to judge yet. (Moved here from the
/// retired `HouseHeroView`; `TodayHeroCopy` still speaks it.)
enum HouseStatusTone: Equatable, Sendable {
    case positive, caution, neutral
}

/// A save the hero should show: hours moved from `oldHours` to `newHours`. (Moved here from the
/// retired `ConfirmBuildAnimation`; `TodayHouseEvents` queues it.)
struct HouseConfirmEvent: Equatable {
    let id = UUID()
    let oldHours: Double
    let newHours: Double
}

/// One page of the rental switcher: one rental, or "All rentals" (H10).
struct TodayFocus: Identifiable, Equatable, Sendable {
    /// nil = All rentals.
    let rentalID: UUID?
    let name: String
    /// Confirmed, countable hours this tax year.
    let hours: Double
    /// The goal the house measures against.
    let goal: Double

    /// Stable id: the rental's UUID string, or "all" (the drop ledger's key).
    var id: String { CraftDropLedger.focus(rentalID: rentalID) }
    var totals: CraftHeroTotals { CraftHeroTotals(hours: hours, goal: goal) }
    /// The one stage function, through `CraftHeroTotals`.
    var stage: CraftStage { totals.stage }
    /// The rentals whose entries light the windows (nil = all of them).
    var rentalIDs: Set<UUID>? { rentalID.map { [$0] } }
    var isAllRentals: Bool { rentalID == nil }
}

enum TodayFocusList {
    struct Rental: Equatable, Sendable {
        let id: UUID
        let name: String
        let hours: Double
    }

    /// One page per rental; with two or more rentals, "All rentals" leads as the first page (H10):
    /// the sum of their hours against the largest goal, through the same stage function.
    static func make(rentals: [Rental], goal: Double, allRentalsName: String) -> [TodayFocus] {
        let singles = rentals.map { TodayFocus(rentalID: $0.id, name: $0.name, hours: $0.hours, goal: goal) }
        guard singles.count > 1 else { return singles }
        let all = CraftHeroTotals.allRentals(singles.map(\.totals))
        return [TodayFocus(rentalID: nil, name: allRentalsName, hours: all.hours, goal: all.goal)] + singles
    }

    /// Which page Today opens on: the remembered one if it still exists, else the rental the goal is
    /// counted on (`todayFocusProperty`), else the first page.
    static func initialFocusID(_ focuses: [TodayFocus], remembered: String?, countedRental: UUID?) -> String? {
        if let remembered, focuses.contains(where: { $0.id == remembered }) { return remembered }
        if let countedRental, let match = focuses.first(where: { $0.rentalID == countedRental }) { return match.id }
        return focuses.first?.id
    }

    /// The page `step` away from `current`, wrapping (swipe on the house, VoiceOver adjust).
    static func step(_ focuses: [TodayFocus], from current: String?, by step: Int) -> String? {
        guard !focuses.isEmpty else { return nil }
        let i = focuses.firstIndex { $0.id == current } ?? 0
        let n = focuses.count
        return focuses[((i + step) % n + n) % n].id
    }
}

/// The plain pace line under the number (§H.8): "Behind by 14h. 9h a week gets you to 100."
/// The lead is `behind` or `positiveOnPage` semibold (neutral leads use `textPrimary`); the rest
/// is `textSecondary`. Never says qualify, never rounds in the user's favour.
struct TodayPaceSentence: Equatable {
    enum Tone: Equatable { case behind, positive, neutral }

    let lead: String?
    let rest: String
    let tone: Tone

    /// One line for VoiceOver.
    var spoken: String { [lead, rest].compactMap { $0 }.joined(separator: " ") }

    struct Input {
        var hours: Double
        var goal: Double
        var year: Int
        var now: Date
        var calendar: Calendar = .current
        /// "Just keep a record": no target, no pace.
        var isRecord = false
        /// Two weeks of data or ten hours (`TodayHeroCopy.paceIsReady`).
        var paceReady = true
        var hasPendingToConfirm = false
        /// The goal is reached but something is still open (the 750's half rule, the 100-hour
        /// "did anyone do more?"): said instead of "Done".
        var reachedCaveat: String? = nil
    }

    /// Every pace line ends with a full stop, like "Behind by 14h. 9h a week gets you to 100."
    static func sentence(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let last = t.last, !".!?".contains(last) else { return t }
        return t + "."
    }

    static func make(_ i: Input) -> TodayPaceSentence {
        let goal = Int(i.goal.rounded())
        if i.isRecord || i.goal <= 0 {
            return TodayPaceSentence(lead: nil, rest: String(localized: "today.pace.record", defaultValue: "Hours on your \(String(i.year)) record.", table: "Today"), tone: .neutral)
        }
        if i.hours >= i.goal {
            if let caveat = i.reachedCaveat {
                // The hours are reached, so the lead is `positiveOnPage` (§H.4); the caveat says what is open.
                return TodayPaceSentence(lead: String(localized: "today.pace.reached", defaultValue: "\(goal) reached.", table: "Today"),
                                         rest: sentence(caveat), tone: .positive)
            }
            return TodayPaceSentence(lead: String(localized: "today.pace.done", defaultValue: "Done for \(String(i.year)).", table: "Today"),
                                     rest: String(localized: "today.pace.doneRest", defaultValue: "\(goal) hours on the record.", table: "Today"),
                                     tone: .positive)
        }
        if i.hours <= 0 {
            return TodayPaceSentence(lead: nil, rest: String(localized: "today.pace.none", defaultValue: "No hours yet. Log your first one while it’s fresh.", table: "Today"), tone: .neutral)
        }
        if !i.paceReady {
            return TodayPaceSentence(lead: nil, rest: i.hasPendingToConfirm
                ? String(localized: "today.pace.confirmFirst", defaultValue: "Confirm your found hours to see your pace.", table: "Today")
                : String(localized: "today.pace.notReady", defaultValue: "Log a few weeks to see your pace.", table: "Today"),
                tone: .neutral)
        }
        let day = Double(i.calendar.ordinality(of: .day, in: .year, for: i.now) ?? 1)
        let daysInYear = Double(i.calendar.range(of: .day, in: .year, for: i.now)?.count ?? 365)
        let expected = i.goal * day / daysInYear
        let weeks = TodayPaceCards.weeksLeft(now: i.now, calendar: i.calendar)
        let weekly = max(1, Int((max(i.goal - i.hours, 0) / weeks).rounded(.up)))
        let rest = String(localized: "today.pace.weekly", defaultValue: "\(weekly)h a week gets you to \(goal).", table: "Today")
        let behind = Int((expected - i.hours).rounded())
        if behind >= 1 {
            return TodayPaceSentence(lead: String(localized: "today.pace.behind", defaultValue: "Behind by \(behind)h.", table: "Today"),
                                     rest: rest, tone: .behind)
        }
        return TodayPaceSentence(lead: String(localized: "today.pace.onPace", defaultValue: "On pace.", table: "Today"), rest: rest, tone: .positive)
    }
}


/// The rental chip's name when it does not fit: whole words only, then "…" (§2 no mid-word break).
enum TodayChipName {
    /// The full name first, then the name with one word fewer each time ("The Arroyo Seco…"), so
    /// `ViewThatFits` picks the longest that fits. The last candidate is the first word, which the
    /// chip may still shorten when even it is too wide.
    static func candidates(_ name: String) -> [String] {
        let words = name.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 1 else { return [name] }
        var out = [name]
        for n in stride(from: words.count - 1, through: 1, by: -1) {
            var head = words.prefix(n).joined(separator: " ")
            while let last = head.last, ",;:-·".contains(last) { head.removeLast() }
            let candidate = head + "…"
            if !out.contains(candidate) { out.append(candidate) }
        }
        return out
    }
}
