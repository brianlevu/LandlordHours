import Foundation

// MARK: - Pace and care nudges: the rules (2.3 package D)
//
// Pure: settings + facts about the person's data + what was already sent in, a list of
// notifications out. No clock, no UNUserNotificationCenter, no UserDefaults, so every rule is a
// unit test.
//
// The rules:
//  - Nothing at all unless the person turned a kind on. Each kind is its own switch.
//  - One notification a day at most, and a few a month at most (`monthlyCap`).
//  - Never during quiet hours: a time inside the window moves to the moment it ends.
//  - Pace and care are never in one notification. They are separate requests on separate days.
//  - Every nudge is built from the person's own data (hours, a care item). No data, no nudge.
//  - Care goes one item at a time, and the same item is not nudged again for `careRepeatDays`.

struct NudgeRental: Equatable, Sendable {
    let id: UUID
    let name: String
}

struct NudgeFacts {
    var now: Date
    var calendar: Calendar
    var rentals: [NudgeRental]
    var yearHours: Double
    var targetHours: Double
    var careItems: [CareDueItem]
    /// Care is a Pro feature (`ProFeature.carePlan`): no plan, no care nudge.
    var carePlanUnlocked: Bool
}

struct NudgePlan: Equatable, Sendable {
    let id: String
    let kind: NudgeKind
    let fireDate: Date
    let title: String
    let body: String
    /// The rental a care nudge is about. Pace nudges are about the whole year.
    let rentalID: UUID?
    let itemID: String
}

struct NudgeOutput: Equatable {
    var plans: [NudgePlan]
    /// What to keep: the sent history (past nudges) plus the plans just made.
    var ledger: [NudgeLedgerEntry]
}

enum NudgePolicy {
    static let horizonDays = 14
    static let monthlyCap = 6
    static let careRepeatDays = 30
    /// "Behind" means this many weeks of the pace the goal needs.
    static let behindWeeks = 2.0
    /// Too early in the year for a pace to mean anything.
    static let minDaysIntoYear = 60

    static let idPrefix = "nudge."

    // The hour each kind goes out, local time, before quiet hours move it.
    static let weeklyHour = 18
    static let morningHour = 10

    static func plan(settings: NudgeSettings, facts: NudgeFacts, ledger: [NudgeLedgerEntry]) -> NudgeOutput {
        let cal = facts.calendar
        let now = facts.now

        // Past nudges only: anything in the future was a plan the last rebuild made, and this
        // rebuild remakes it.
        var sent = ledger.filter { $0.fireDate <= now }
        let keepFrom = cal.date(byAdding: .day, value: -400, to: now) ?? now
        sent.removeAll { $0.fireDate < keepFrom }

        // "Behind" fires once per time behind. Catching up clears it.
        let behind = isBehind(facts)
        if !behind { sent.removeAll { $0.kind == .behindPace } }

        guard settings.anyKindOn else { return NudgeOutput(plans: [], ledger: sent) }

        struct Candidate {
            let priority: Int
            let kind: NudgeKind
            let itemID: String
            let preferred: Date
            let title: String
            let body: String
            let rentalID: UUID?
            /// Care may take a later free day; the others keep their date or are dropped.
            let movable: Bool
        }
        var candidates: [Candidate] = []
        let hasData = facts.yearHours > 0 && !facts.rentals.isEmpty

        if settings.yearEnd, hasData {
            let year = cal.component(.year, from: now)
            for day in [1, 20] {
                guard let date = cal.date(from: DateComponents(year: year, month: 12, day: day)),
                      let fire = at(hour: morningHour, on: date, cal),
                      fire > now, withinHorizon(fire, now, cal) else { continue }
                let text = NudgeCopy.yearEnd(year: year, hours: wholeHours(facts.yearHours))
                candidates.append(Candidate(priority: 0, kind: .yearEnd, itemID: dayKey(date, cal), preferred: fire,
                                            title: text.title, body: text.body, rentalID: nil, movable: false))
            }
        }

        if settings.behindPace, behind, !sent.contains(where: { $0.kind == .behindPace }) {
            let today = cal.startOfDay(for: now)
            var fire = at(hour: morningHour, on: today, cal) ?? now
            if fire <= now { fire = at(hour: morningHour, on: cal.date(byAdding: .day, value: 1, to: today) ?? today, cal) ?? fire }
            let text = NudgeCopy.behind(hoursBehind: Int(gap(facts).rounded(.up)), target: wholeHours(facts.targetHours))
            candidates.append(Candidate(priority: 1, kind: .behindPace, itemID: dayKey(fire, cal), preferred: fire,
                                        title: text.title, body: text.body, rentalID: nil, movable: false))
        }

        if settings.weeklyPace, hasData {
            let today = cal.startOfDay(for: now)
            for offset in 0..<horizonDays {
                guard let day = cal.date(byAdding: .day, value: offset, to: today),
                      cal.component(.weekday, from: day) == 1,   // Sunday
                      let fire = at(hour: weeklyHour, on: day, cal), fire > now else { continue }
                let text = NudgeCopy.weekly(hours: wholeHours(facts.yearHours), target: wholeHours(facts.targetHours),
                                            perWeek: hoursPerWeek(facts))
                candidates.append(Candidate(priority: 2, kind: .weeklyPace, itemID: dayKey(day, cal), preferred: fire,
                                            title: text.title, body: text.body, rentalID: nil, movable: false))
            }
        }

        if settings.carePlan, facts.carePlanUnlocked,
           let item = nextCareItem(facts, sent: sent),
           let rental = facts.rentals.first(where: { $0.id == item.rentalID }) {
            let today = cal.startOfDay(for: now)
            let text = NudgeCopy.care(rental: rental.name, item: item.title)
            candidates.append(Candidate(priority: 3, kind: .carePlan, itemID: careKey(item), preferred: at(hour: morningHour, on: today, cal) ?? now,
                                        title: text.title, body: text.body, rentalID: item.rentalID, movable: true))
        }

        // Take them in priority order, one a day, under the monthly cap.
        var takenDays = Set(sent.map { cal.startOfDay(for: $0.fireDate) })
        var monthCounts: [String: Int] = [:]
        for entry in sent { monthCounts[monthKey(entry.fireDate, cal), default: 0] += 1 }

        var plans: [NudgePlan] = []
        for candidate in candidates.sorted(by: { ($0.priority, $0.preferred) < ($1.priority, $1.preferred) }) {
            var fire = settings.moveOutOfQuietHours(candidate.preferred, calendar: cal)
            var attempts = candidate.movable ? horizonDays : 1
            var placed = false
            while attempts > 0 {
                attempts -= 1
                let day = cal.startOfDay(for: fire)
                if fire > now, withinHorizon(fire, now, cal),
                   !takenDays.contains(day), monthCounts[monthKey(fire, cal), default: 0] < monthlyCap {
                    takenDays.insert(day)
                    monthCounts[monthKey(fire, cal), default: 0] += 1
                    placed = true
                    break
                }
                guard candidate.movable,
                      let nextDay = cal.date(byAdding: .day, value: 1, to: day),
                      let next = at(hour: morningHour, on: nextDay, cal) else { break }
                fire = settings.moveOutOfQuietHours(next, calendar: cal)
            }
            guard placed else { continue }
            plans.append(NudgePlan(id: requestID(candidate.kind, candidate.itemID, cal, fire), kind: candidate.kind, fireDate: fire,
                                   title: candidate.title, body: candidate.body, rentalID: candidate.rentalID, itemID: candidate.itemID))
        }
        plans.sort { $0.fireDate < $1.fireDate }

        let made = plans.map { NudgeLedgerEntry(kind: $0.kind, itemID: $0.itemID, fireDate: $0.fireDate) }
        return NudgeOutput(plans: plans, ledger: sent + made)
    }

    // MARK: Pace arithmetic

    static func daysInYear(_ facts: NudgeFacts) -> Int {
        facts.calendar.range(of: .day, in: .year, for: facts.now)?.count ?? 365
    }

    static func dayOfYear(_ facts: NudgeFacts) -> Int {
        facts.calendar.ordinality(of: .day, in: .year, for: facts.now) ?? 1
    }

    /// Hours the goal needs by today, minus the hours logged. Negative when ahead.
    static func gap(_ facts: NudgeFacts) -> Double {
        let target = max(facts.targetHours, 1)
        let required = target * Double(dayOfYear(facts)) / Double(daysInYear(facts))
        return required - facts.yearHours
    }

    static func isBehind(_ facts: NudgeFacts) -> Bool {
        guard facts.yearHours > 0, dayOfYear(facts) >= minDaysIntoYear else { return false }
        let weeklyNeed = max(facts.targetHours, 1) * 7 / Double(daysInYear(facts))
        return gap(facts) >= behindWeeks * weeklyNeed
    }

    /// Hours a week to still reach the goal by Dec 31, rounded up. 0 when the goal is met.
    static func hoursPerWeek(_ facts: NudgeFacts) -> Int {
        let remaining = max(0, facts.targetHours - facts.yearHours)
        guard remaining > 0 else { return 0 }
        let daysLeft = max(1, daysInYear(facts) - dayOfYear(facts))
        let weeksLeft = max(1, Int((Double(daysLeft) / 7).rounded(.up)))
        return Int((remaining / Double(weeksLeft)).rounded(.up))
    }

    // MARK: Care

    static func careKey(_ item: CareDueItem) -> String { "\(item.rentalID.uuidString).\(item.id)" }

    private static func nextCareItem(_ facts: NudgeFacts, sent: [NudgeLedgerEntry]) -> CareDueItem? {
        let recent = facts.calendar.date(byAdding: .day, value: -careRepeatDays, to: facts.now) ?? facts.now
        let already = Set(sent.filter { $0.kind == .carePlan && $0.fireDate >= recent }.map(\.itemID))
        return facts.careItems
            .filter { !already.contains(careKey($0)) }
            .min { ($0.due, $0.id) < ($1.due, $1.id) }
    }

    // MARK: Helpers

    static func wholeHours(_ hours: Double) -> Int { Int(hours.rounded(.down)) }

    private static func at(hour: Int, on day: Date, _ cal: Calendar) -> Date? {
        cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    private static func withinHorizon(_ date: Date, _ now: Date, _ cal: Calendar) -> Bool {
        guard let end = cal.date(byAdding: .day, value: horizonDays, to: cal.startOfDay(for: now)) else { return false }
        return date < end
    }

    private static func dayKey(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func monthKey(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    /// One id per kind per day: adding the same nudge twice replaces it, never doubles it.
    private static func requestID(_ kind: NudgeKind, _ itemID: String, _ cal: Calendar, _ fire: Date) -> String {
        "\(idPrefix)\(kind.rawValue).\(dayKey(fire, cal))"
    }
}

extension NudgeSettings {
    /// A time inside quiet hours moves to the moment they end; any other time is unchanged.
    func moveOutOfQuietHours(_ date: Date, calendar: Calendar) -> Date {
        guard isQuiet(date, calendar: calendar) else { return date }
        let end = calendar.date(bySettingHour: quietEndHour, minute: 0, second: 0, of: date) ?? date
        if end > date { return end }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return calendar.date(bySettingHour: quietEndHour, minute: 0, second: 0, of: nextDay) ?? date
    }
}
