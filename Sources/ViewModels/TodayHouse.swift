import Foundation

// MARK: - Today's house: what it counts, and the events that build it
//
// The Today hero is the Blueprint house (WP-H). This file holds the Today-only glue:
//   - which hours the house counts (the goal's countable hours, from the existing tax engine),
//   - the honest pace line ("Behind by 12h" / "On pace, 18h ahead"),
//   - the event hub every save path reports to, so Today plays the confirm build on its next
//     appear (or live), presents each milestone celebration once, and shows the Day-1 backfill
//     reveal once.
//
// Countable hours (docs/2.0-auto-capture-plan.md, "the house counts the goal's countable hours"):
//   - REPS: your own real-estate hours, exactly `repsStatus(.selfParticipant).realEstateHours`.
//     Investor-only tasks never count. Spouse hours never count toward YOUR 750 (the IRS tests
//     REPS for each spouse separately, as the audit export already says), so the REPS house
//     never includes them, joint tracking or not.
//   - Material participation: `materialParticipationOverview` (owner + spouse, best property or
//     the grouped activity), with spouse hours only when the household tracks them jointly
//     (Tax Profile "Spouse hours" on). Investor-only tasks never count.

extension AppViewModel {
    /// The goal the house measures against, from the 1.x goal setting.
    var houseGoal: HouseGoal { HouseGoal(GoalManager.shared.globalGoalType) }

    /// Whether spouse hours are tracked jointly (Tax Profile "Spouse hours").
    var tracksSpouseJointly: Bool { TaxProfileManager.shared.spouseTracking }

    /// The goal's countable hours for `year`. Reuses the tax engine; never re-derives the rules.
    func houseCountableHours(
        goal: HouseGoal? = nil,
        year: Int = Calendar.current.component(.year, from: Date()),
        includeSpouse: Bool? = nil
    ) -> Double {
        switch goal ?? houseGoal {
        case .reps750:
            return repsStatus(participant: .selfParticipant, year: year).realEstateHours
        case .mp500, .mp100:
            return materialParticipationOverview(year: year, includeSpouse: includeSpouse ?? tracksSpouseJointly)
                .ownerAndSpouseHours
        }
    }

    /// Reports a save to Today's house. Call with the countable hours read BEFORE the save.
    func reportHouseSave(previousHours: Double) {
        guard !suppressCelebrations else { return }
        let year = Calendar.current.component(.year, from: Date())
        TodayHouseEvents.shared.entrySaved(
            from: previousHours,
            to: houseCountableHours(year: year),
            goal: houseGoal,
            year: year
        )
    }
}

// MARK: - Pace

/// The honest status line on the hero. Linear pace: the share of the goal the calendar says
/// you should have by today. Never rounds in the user's favour.
struct TodayPace: Equatable {
    enum Tone: Equatable { case positive, caution, neutral }

    let text: String
    let tone: Tone

    static func resolve(hours: Double, goal: HouseGoal, date: Date = Date(), calendar: Calendar = .current) -> TodayPace {
        if HouseProgress(hours: hours, goal: goal).isGoalMet {
            return TodayPace(text: "Goal hours met", tone: .positive)
        }
        if hours <= 0 {
            return TodayPace(text: "No hours logged yet", tone: .neutral)
        }
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let daysInYear = Double(calendar.range(of: .day, in: .year, for: date)?.count ?? 365)
        let expected = goal.targetHours * day / daysInYear
        if hours >= expected {
            let ahead = Int((hours - expected).rounded(.down))
            return TodayPace(text: ahead >= 1 ? "On pace, \(ahead)h ahead" : "On pace", tone: .positive)
        }
        let behind = max(1, Int((expected - hours).rounded(.up)))
        return TodayPace(text: "Behind by \(behind)h", tone: .caution)
    }
}

// MARK: - Celebrate-once ledger

/// Remembers which house celebrations a profile has seen, per tax year and milestone, so a
/// celebration never repeats (deleting and re-adding hours, a relaunch, another device's sync).
struct HouseCelebrationLedger {
    static let celebratedBaseKey = "LandlordHours.house.celebrated"
    static let pendingBaseKey = "LandlordHours.house.pendingCelebrations"
    static let backfillShownBaseKey = "LandlordHours.house.backfillShown"

    var defaults: UserDefaults = .standard
    /// The profile; nil = the active one.
    var userId: String? = UserScope.userId

    private func key(_ base: String) -> String { UserScope.key(base, userId: userId) }

    static func token(_ celebration: HouseCelebration, year: Int) -> String { "\(year)_\(celebration.id)" }

    func isCelebrated(_ celebration: HouseCelebration, year: Int) -> Bool {
        (defaults.stringArray(forKey: key(Self.celebratedBaseKey)) ?? []).contains(Self.token(celebration, year: year))
    }

    func markCelebrated(_ celebration: HouseCelebration, year: Int) {
        var list = defaults.stringArray(forKey: key(Self.celebratedBaseKey)) ?? []
        let token = Self.token(celebration, year: year)
        guard !list.contains(token) else { return }
        list.append(token)
        defaults.set(list, forKey: key(Self.celebratedBaseKey))
    }

    /// Queued celebrations (crossed while Today was not on screen), as `year_id` tokens.
    var pendingTokens: [String] {
        get { defaults.stringArray(forKey: key(Self.pendingBaseKey)) ?? [] }
        nonmutating set { defaults.set(newValue.isEmpty ? nil : newValue, forKey: key(Self.pendingBaseKey)) }
    }

    var backfillShown: Bool {
        get { defaults.bool(forKey: key(Self.backfillShownBaseKey)) }
        nonmutating set { defaults.set(newValue, forKey: key(Self.backfillShownBaseKey)) }
    }

    static func parse(token: String) -> (year: Int, celebration: HouseCelebration)? {
        let parts = token.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2, let year = Int(parts[0]) else { return nil }
        let id = parts[1]
        if id.hasPrefix("stage-"), let raw = Int(id.dropFirst(6)), let m = HouseMilestone(rawValue: raw) {
            return (year, .stage(m))
        }
        if id.hasPrefix("goal-"), let goal = HouseGoal(rawValue: String(id.dropFirst(5))) {
            return (year, .goalMet(goal))
        }
        return nil
    }
}

// MARK: - Milestone queue seam (WP4)

/// Anything that can queue a house celebration. WP4's background milestone queue feeds Today
/// through this (a "Log it" notification action crosses 500h with no scene on screen; Today
/// presents it once on next appear). Queuing an already-celebrated milestone is a no-op.
@MainActor
protocol HouseMilestoneQueue: AnyObject {
    func enqueue(_ celebration: HouseCelebration, year: Int)
}

/// The Day-1 backfill result Today reveals once.
struct HouseBackfillReveal: Identifiable, Equatable {
    let id = UUID()
    let foundHours: Double
    let suggestionCount: Int
}

// MARK: - Event hub

/// Every save path reports here (manual log via "+", timer stop, inbox confirm). Today reads it
/// on appear and while visible. Celebrations and the backfill flag persist per profile; the
/// pending confirm build is in memory (a relaunch just shows the house at its new height).
@MainActor
final class TodayHouseEvents: ObservableObject, HouseMilestoneQueue {
    static let shared = TodayHouseEvents()

    /// The confirm build Today has not played yet (merged across saves: oldest from, newest to).
    @Published private(set) var pendingConfirm: HouseConfirmEvent?
    /// Bumped whenever a celebration is queued, so a visible Today can present it.
    @Published private(set) var celebrationTick = 0
    /// The Day-1 reveal, once, until Today shows it.
    @Published private(set) var pendingBackfill: HouseBackfillReveal?

    private let ledgerProvider: () -> HouseCelebrationLedger

    init(ledger: @escaping () -> HouseCelebrationLedger = { HouseCelebrationLedger() }) {
        self.ledgerProvider = ledger
    }

    private var ledger: HouseCelebrationLedger { ledgerProvider() }

    // MARK: Saves

    /// A save moved the goal's countable hours from `old` to `new`.
    func entrySaved(from old: Double, to new: Double, goal: HouseGoal, year: Int) {
        guard new > old else { return }
        if let existing = pendingConfirm {
            pendingConfirm = HouseConfirmEvent(oldHours: min(existing.oldHours, old), newHours: new)
        } else {
            pendingConfirm = HouseConfirmEvent(oldHours: old, newHours: new)
        }
        for celebration in HouseProgress.celebrations(from: old, to: new, goal: goal) {
            enqueue(celebration, year: year)
        }
    }

    /// Today takes the confirm it is about to play (or that it just played live).
    @discardableResult
    func takeConfirm() -> HouseConfirmEvent? {
        defer { pendingConfirm = nil }
        return pendingConfirm
    }

    // MARK: Celebrations

    func enqueue(_ celebration: HouseCelebration, year: Int) {
        let ledger = ledger
        guard !ledger.isCelebrated(celebration, year: year) else { return }
        let token = HouseCelebrationLedger.token(celebration, year: year)
        var pending = ledger.pendingTokens
        guard !pending.contains(token) else { return }
        pending.append(token)
        ledger.pendingTokens = pending
        celebrationTick += 1
    }

    /// The celebration to present next: the highest one queued (the hero shows only the last of
    /// a multi-threshold jump, as WP-H designed). nil when nothing is waiting.
    var nextCelebration: (celebration: HouseCelebration, year: Int)? {
        let ledger = ledger
        return ledger.pendingTokens
            .compactMap(HouseCelebrationLedger.parse(token:))
            .filter { !ledger.isCelebrated($0.celebration, year: $0.year) }
            .max { ($0.year, $0.celebration.thresholdHours) < ($1.year, $1.celebration.thresholdHours) }
    }

    /// Marks `celebration` and every lower queued one of that year as celebrated and clears
    /// them, so none of them ever shows again. Call when the screen is presented.
    func markPresented(_ celebration: HouseCelebration, year: Int) {
        let ledger = ledger
        ledger.markCelebrated(celebration, year: year)
        var remaining: [String] = []
        for token in ledger.pendingTokens {
            guard let parsed = HouseCelebrationLedger.parse(token: token) else { continue }
            if parsed.year == year && parsed.celebration.thresholdHours <= celebration.thresholdHours {
                ledger.markCelebrated(parsed.celebration, year: parsed.year)
            } else if !ledger.isCelebrated(parsed.celebration, year: parsed.year) {
                remaining.append(token)
            }
        }
        ledger.pendingTokens = remaining
    }

    // MARK: Day-1 backfill (WP3 calls this)

    /// The Day-1 backfill finished: `foundHours` of suggestions (not records) in
    /// `suggestionCount` items. Today shows the reveal once per profile.
    func backfillFinished(foundHours: Double, suggestionCount: Int) {
        guard suggestionCount > 0, foundHours > 0, !ledger.backfillShown else { return }
        pendingBackfill = HouseBackfillReveal(foundHours: foundHours, suggestionCount: suggestionCount)
    }

    /// Today presented the reveal; it never shows again for this profile.
    func markBackfillShown() {
        ledger.backfillShown = true
        pendingBackfill = nil
    }

    /// Profile switch / data reset: drop in-memory state (persisted state is per profile).
    func resetInMemoryState() {
        pendingConfirm = nil
        pendingBackfill = nil
    }
}

#if DEBUG
// MARK: - DEBUG seeding for Today captures and UI tests
//
//   -LHTodayHours <h>          after -LHMockScenario: replace this year's entries with your own
//                              countable hours totalling h (8h days, before today)
//   -LHTodayConfirmHours <h>   then log h more hours through addTimeEntry (the real save path),
//                              so Today plays the confirm build and any milestone on appear
//   -LHTodayBackfill <h> <n>   then report a finished Day-1 backfill (h hours in n suggestions)
// Compiled out of Release.
extension AppViewModel {
    func applyTodayHoursSeedIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        func value(_ flag: String, offset: Int = 1) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + offset) else { return nil }
            return arguments[i + offset]
        }
        if let raw = value("-LHTodayHours"), let total = Double(raw) {
            seedTodayHours(total)
        }
        if let raw = value("-LHTodayConfirmHours"), let hours = Double(raw), hours > 0,
           let property = properties.first {
            addTimeEntry(
                propertyId: property.id,
                participant: .selfParticipant,
                category: .repairs,
                hours: hours,
                date: Date(),
                notes: "Fixed the porch steps"
            )
        }
        if let rawHours = value("-LHTodayBackfill"), let hours = Double(rawHours),
           let rawCount = value("-LHTodayBackfill", offset: 2), let count = Int(rawCount) {
            TodayHouseEvents.shared.backfillFinished(foundHours: hours, suggestionCount: count)
        }
    }

    private func seedTodayHours(_ total: Double) {
        let wasSuppressed = suppressCelebrations
        suppressCelebrations = true
        defer { suppressCelebrations = wasSuppressed }
        if properties.isEmpty {
            addProperty(name: "Pine Cabin", address: "12 Pine Rd", type: .ltr)
        }
        guard let property = properties.first else { return }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let startOfToday = calendar.startOfDay(for: Date())
        timeEntries.removeAll { calendar.component(.year, from: $0.date) == year }
        var remaining = max(0, total)
        var daysBack = 1
        let categories: [ActivityCategory] = [.repairs, .management, .leasing, .bookkeeping]
        while remaining > 0.0001 {
            let hours = min(8, remaining)
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: startOfToday),
                  calendar.component(.year, from: day) == year,
                  let date = calendar.date(byAdding: .hour, value: 9, to: day) else { break }
            timeEntries.append(TimeEntry(
                propertyId: property.id,
                participant: .selfParticipant,
                category: categories[daysBack % categories.count],
                hours: hours,
                date: date,
                notes: ""
            ))
            remaining -= hours
            daysBack += 1
        }
        saveData()
    }
}
#endif
