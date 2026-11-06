import Foundation

// MARK: - Reports: where each person stands
//
// Reports leads with the same numbers Today shows. Nothing here re-derives a tax rule: the
// hours come from `AppViewModel.houseCountableHours` (Today's house) and `repsStatus`, the pace
// line from `TodayPace`, and the met/not-met answers from the engine results.

struct ReportStanding: Identifiable, Equatable {
    enum Person: String, Equatable { case you, spouse, household }
    enum Tone: Equatable { case positive, caution, neutral }

    let person: Person
    let goal: HouseGoal
    let hours: Double
    let target: Double
    /// Short status, e.g. "Behind by 12h", "Both tests met".
    let status: String
    let tone: Tone
    /// One plain line under the status (the 50% rule, the spouse rule, the 100h question).
    let detail: String?

    var id: String { person.rawValue }

    var name: String {
        switch person {
        case .you: return RR.t("reports.person.you", "You")
        case .spouse: return RR.t("reports.person.spouse", "Spouse")
        case .household: return RR.t("reports.person.together", "You and your spouse")
        }
    }

    var progress: Double { target > 0 ? min(hours / target, 1) : 0 }
}

enum ReportsLogic {
    /// Status for a goal's hours in `year`. The current year uses Today's pace line; a closed
    /// year says whether it ended met or short; a future year has nothing to measure yet.
    static func paceStatus(
        hours: Double,
        goal: HouseGoal,
        year: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (text: String, tone: ReportStanding.Tone) {
        let currentYear = calendar.component(.year, from: now)
        let met = HouseProgress(hours: hours, goal: goal).isGoalMet
        if year < currentYear {
            if met { return (RR.t("reports.pace.met", "Goal hours met"), .positive) }
            let short = max(1, Int((goal.targetHours - hours).rounded(.up)))
            return (RR.t("reports.pace.short", "Year ended \(short)h short"), .caution)
        }
        if year > currentYear { return (RR.t("reports.pace.notStarted", "Not started"), .neutral) }
        let pace = TodayPace.resolve(hours: hours, goal: goal, date: now, calendar: calendar)
        switch pace.tone {
        case .positive: return (pace.text, .positive)
        case .caution: return (pace.text, .caution)
        case .neutral: return (pace.text, .neutral)
        }
    }

    /// The REPS card for one person. `rep` is `repsStatus(participant:year:)`.
    static func repsStanding(
        person: ReportStanding.Person,
        rep: TaxQualificationEngine.REPSResult,
        year: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReportStanding {
        let hours = rep.realEstateHours
        if person == .spouse {
            let pace = paceStatus(hours: hours, goal: .reps750, year: year, now: now, calendar: calendar)
            // Hours alone never show a spouse as qualified: the 50% rule isn't tracked for them,
            // so this card is never green.
            return ReportStanding(
                person: .spouse, goal: .reps750, hours: hours, target: 750,
                status: pace.text, tone: pace.tone == .caution ? .caution : .neutral,
                detail: RR.t("reports.spouse.detail", "50% rule not tracked for your spouse. The 750 is met by one of you alone, so these hours never add to yours.")
            )
        }
        if rep.isQualified {
            return ReportStanding(
                person: person, goal: .reps750, hours: hours, target: 750,
                status: RR.t("reports.rule.bothMarks", "Past both marks"), tone: .positive,
                detail: RR.t("reports.rule.bothMarks.detail", "More than 750 hours, and more than half your working time.")
            )
        }
        if let open = TaxQualificationEngine.hoursMetRuleOpenStatus(rep) {
            return ReportStanding(
                person: person, goal: .reps750, hours: hours, target: 750,
                status: open.label, tone: .caution, detail: open.detail
            )
        }
        let pace = paceStatus(hours: hours, goal: .reps750, year: year, now: now, calendar: calendar)
        let rule: String
        switch rep.moreThanHalfStatus {
        case .met:
            let percent = Int((rep.realEstateWorkPercentage * 100).rounded(.down))
            rule = RR.t("reports.rule.met", "50% rule: met, \(percent)% of your working time.")
        case .notMet:
            let percent = Int((rep.realEstateWorkPercentage * 100).rounded(.down))
            rule = RR.t("reports.rule.notMet", "50% rule: not met yet, \(percent)% of your working time.")
        case .notEntered:
            let prompt = TaxQualificationEngine.MoreThanHalfStatus.notEnteredPrompt.lowercased()
            rule = RR.t("reports.rule.notEntered", "50% rule: \(prompt).")
        }
        return ReportStanding(
            person: person, goal: .reps750, hours: hours, target: 750,
            status: pace.text, tone: pace.tone, detail: rule
        )
    }

    /// The material participation card. `hours` is Today's countable hours for the goal and
    /// `result` the engine overview with the same spouse setting.
    static func mpStanding(
        goal: HouseGoal,
        hours: Double,
        result: TaxQualificationEngine.MaterialParticipationResult,
        includesSpouse: Bool,
        year: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReportStanding {
        let person: ReportStanding.Person = includesSpouse ? .household : .you
        let met = goal == .mp500 ? result.meets500HourTest : result.meets100HourTest
        if met {
            return ReportStanding(
                person: person, goal: goal, hours: hours, target: goal.targetHours,
                status: RR.t("reports.mp.met", "Goal met"), tone: .positive,
                detail: goal == .mp100
                    ? RR.t("reports.mp.met.100", "More than 100 hours, and no one else did more.")
                    : RR.t("reports.mp.met.500", "More than 500 hours on this activity.")
            )
        }
        // Over 500 hours the 500-hour test is met, so who else spent more time doesn't matter.
        // The card says so instead of asking a question the Reports screen has no row for.
        if goal == .mp100, result.meets500HourTest {
            return ReportStanding(
                person: person, goal: goal, hours: hours, target: goal.targetHours,
                status: RR.t("reports.mp.over500", "Over 500 hours"), tone: .positive,
                detail: RR.t("reports.mp.over500.detail", "You\u{2019}re past 500 hours, so who else did more doesn\u{2019}t come up.")
            )
        }
        if goal == .mp100, result.ownerAndSpouseHours > 100 {
            switch result.noOneParticipatedMore {
            case .none:
                return ReportStanding(
                    person: person, goal: goal, hours: hours, target: goal.targetHours,
                    status: RR.t("reports.mp.reached100", "100 hours reached"), tone: .positive,
                    detail: RR.t("reports.mp.reached100.detail", "Confirm no one else spent more time on it.")
                )
            case .some(false):
                return ReportStanding(
                    person: person, goal: goal, hours: hours, target: goal.targetHours,
                    status: RR.t("reports.mp.someoneMore", "Someone else did more"), tone: .caution,
                    detail: RR.t("reports.mp.someoneMore.detail", "Someone else did more, so the 100-hour route is out. The 500-hour route is still open.")
                )
            case .some(true):
                break
            }
        }
        let pace = paceStatus(hours: hours, goal: goal, year: year, now: now, calendar: calendar)
        return ReportStanding(
            person: person, goal: goal, hours: hours, target: goal.targetHours,
            status: pace.text, tone: pace.tone,
            detail: includesSpouse
                ? RR.t("reports.mp.together", "Your hours and your spouse\u{2019}s count together for this test.")
                : RR.t("reports.mp.solo", "Your hours only. Turn on spouse hours in Settings to count both.")
        )
    }

    /// Bars: label + hours, largest first, at most `limit` rows with the rest folded into "Other".
    static func ranked(_ pairs: [(String, Double)], limit: Int = 6) -> [(label: String, hours: Double)] {
        let sorted = pairs.filter { $0.1 > 0 }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        guard sorted.count > limit else { return sorted.map { ($0.0, $0.1) } }
        let head = sorted.prefix(limit - 1).map { ($0.0, $0.1) }
        let rest = sorted.dropFirst(limit - 1).reduce(0) { $0 + $1.1 }
        return head + [(RR.t("reports.other", "Other"), rest)]
    }

    /// Hours per month for `year` (12 values, January first).
    static func monthlyHours(_ entries: [TimeEntry], year: Int, calendar: Calendar = .current) -> [Double] {
        var months = Array(repeating: 0.0, count: 12)
        for entry in entries where calendar.component(.year, from: entry.date) == year {
            let month = calendar.component(.month, from: entry.date)
            months[month - 1] += entry.hours
        }
        return months
    }
}

// MARK: - Pace tiles and rental rows (moved here from Today, standard §1.11, §H.5)

/// One pace tile: a value and its label (`LHTile.Stat`).
struct ReportsTile: Equatable {
    let value: String
    let label: String
}

/// One rental in "By rental": its own house stage against the chosen goal, lit when hours were
/// logged there today, and its share of the year's hours.
struct ReportsRentalRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let hours: Double
    /// 0...1 of all rental hours in the year.
    let share: Double
    let stage: CraftStage
    let loggedToday: Bool
}

extension ReportsLogic {
    /// Hours a week still needed and the second tile (the 50% rule for the 750, days left for the
    /// other tests). Only the current year has a pace; a closed or future year shows none.
    static func paceTiles(
        standing: ReportStanding,
        rep: TaxQualificationEngine.REPSResult?,
        year: Int,
        paceReady: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ReportsTile] {
        guard calendar.component(.year, from: now) == year else { return [] }
        let pace = TodayPace.resolve(hours: standing.hours, goal: standing.goal, date: now, calendar: calendar)
        let finish = TodayPaceCards.finish(hours: standing.hours, goal: standing.goal, pace: pace, now: now,
                                           calendar: calendar, paceReady: paceReady)
        var tiles = [ReportsTile(value: finish.value, label: finish.label)]
        if standing.goal == .reps750, let rep {
            switch rep.moreThanHalfStatus {
            case .notEntered:
                tiles.append(ReportsTile(value: RR.t("reports.tile.rule.notChecked", "Not checked"),
                                         label: RR.t("reports.tile.rule.label", "Your 50% rule")))
            case .met, .notMet:
                let percent = Int((rep.realEstateWorkPercentage * 100).rounded(.down))
                tiles.append(ReportsTile(value: RR.t("reports.tile.rule.value", "\(percent)%"),
                                         label: RR.t("reports.tile.rule.workTime", "Of your working time")))
            }
        } else {
            let days = daysLeft(now: now, calendar: calendar)
            tiles.append(ReportsTile(
                value: days == 1 ? RR.t("reports.tile.days.one", "1 day") : RR.t("reports.tile.days.many", "\(days) days"),
                label: RR.t("reports.tile.days.label", "Left in \(String(year))")))
        }
        return tiles
    }

    static func daysLeft(now: Date, calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: now)
        guard let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { return 0 }
        return max(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0, 0)
    }

    /// "By rental": every rental with hours in the year, largest first, each with its own stage.
    static func rentalRows(
        rentals: [(id: UUID, name: String, hours: Double, loggedToday: Bool)],
        goalHours: Double
    ) -> [ReportsRentalRow] {
        let active = rentals.filter { $0.hours > 0 }
        let total = active.reduce(0) { $0 + $1.hours }
        return active
            .sorted { $0.hours == $1.hours ? $0.name < $1.name : $0.hours > $1.hours }
            .map { rental in
                ReportsRentalRow(
                    id: rental.id, name: rental.name, hours: rental.hours,
                    share: total > 0 ? rental.hours / total : 0,
                    stage: CraftStage.stage(hours: rental.hours, goal: goalHours),
                    loggedToday: rental.loggedToday
                )
            }
    }

    /// "34% of your hours" for a rental row's meta line.
    static func shareLine(_ share: Double) -> String {
        let percent = Int((share * 100).rounded())
        return RR.t("reports.rental.share", "\(percent)% of your hours")
    }
}

extension AppViewModel {
    /// Reports' lead cards, from the same engine values Today uses.
    func reportStandings(goal: HouseGoal, year: Int, now: Date = Date()) -> [ReportStanding] {
        switch goal {
        case .reps750:
            var cards = [ReportsLogic.repsStanding(person: .you, rep: repsStatus(participant: .selfParticipant, year: year), year: year, now: now)]
            let spouse = repsStatus(participant: .spouse, year: year)
            if tracksSpouseJointly || spouse.realEstateHours > 0 {
                cards.append(ReportsLogic.repsStanding(person: .spouse, rep: spouse, year: year, now: now))
            }
            return cards
        case .mp500, .mp100:
            let includeSpouse = tracksSpouseJointly
            return [ReportsLogic.mpStanding(
                goal: goal,
                hours: houseCountableHours(goal: goal, year: year, includeSpouse: includeSpouse),
                result: materialParticipationOverview(year: year, includeSpouse: includeSpouse),
                includesSpouse: includeSpouse,
                year: year,
                now: now
            )]
        }
    }
}
