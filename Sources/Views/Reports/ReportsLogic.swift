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
        case .you: return "You"
        case .spouse: return "Spouse"
        case .household: return "You and your spouse"
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
            if met { return ("Goal hours met", .positive) }
            let short = max(1, Int((goal.targetHours - hours).rounded(.up)))
            return ("Year ended \(short)h short", .caution)
        }
        if year > currentYear { return ("Not started", .neutral) }
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
                detail: "50% rule not tracked for your spouse. REPS is met by one spouse alone, so these hours never add to yours."
            )
        }
        if rep.isQualified {
            return ReportStanding(
                person: person, goal: .reps750, hours: hours, target: 750,
                status: "Both tests met", tone: .positive,
                detail: "More than 750 hours, and more than half your working time."
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
        case .met: rule = "50% rule: met, \(Int((rep.realEstateWorkPercentage * 100).rounded(.down)))% of your working time."
        case .notMet: rule = "50% rule: not met yet, \(Int((rep.realEstateWorkPercentage * 100).rounded(.down)))% of your working time."
        case .notEntered: rule = "50% rule: " + TaxQualificationEngine.MoreThanHalfStatus.notEnteredPrompt.lowercased() + "."
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
                status: "Goal met", tone: .positive,
                detail: goal == .mp100 ? "More than 100 hours, and no one else did more." : "More than 500 hours on this activity."
            )
        }
        // Over 500 hours the 500-hour test is met, so who else spent more time doesn't matter.
        // The card says so instead of asking a question the Reports screen has no row for.
        if goal == .mp100, result.meets500HourTest {
            return ReportStanding(
                person: person, goal: goal, hours: hours, target: goal.targetHours,
                status: "Over 500 hours", tone: .positive,
                detail: "The 500-hour test is met, so the 100-hour question doesn't apply."
            )
        }
        if goal == .mp100, result.ownerAndSpouseHours > 100 {
            switch result.noOneParticipatedMore {
            case .none:
                return ReportStanding(
                    person: person, goal: goal, hours: hours, target: goal.targetHours,
                    status: "100 hours reached", tone: .caution,
                    detail: "Confirm no one else spent more time on it to pass this test."
                )
            case .some(false):
                return ReportStanding(
                    person: person, goal: goal, hours: hours, target: goal.targetHours,
                    status: "Someone else did more", tone: .caution,
                    detail: "The 100-hour test isn't met. The 500-hour test still counts."
                )
            case .some(true):
                break
            }
        }
        let pace = paceStatus(hours: hours, goal: goal, year: year, now: now, calendar: calendar)
        return ReportStanding(
            person: person, goal: goal, hours: hours, target: goal.targetHours,
            status: pace.text, tone: pace.tone,
            detail: includesSpouse ? "Your hours and your spouse's count together for this test." : "Your hours only. Turn on spouse hours in Tax profile to count both."
        )
    }

    /// Bars: label + hours, largest first, at most `limit` rows with the rest folded into "Other".
    static func ranked(_ pairs: [(String, Double)], limit: Int = 6) -> [(label: String, hours: Double)] {
        let sorted = pairs.filter { $0.1 > 0 }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        guard sorted.count > limit else { return sorted.map { ($0.0, $0.1) } }
        let head = sorted.prefix(limit - 1).map { ($0.0, $0.1) }
        let rest = sorted.dropFirst(limit - 1).reduce(0) { $0 + $1.1 }
        return head + [("Other", rest)]
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
