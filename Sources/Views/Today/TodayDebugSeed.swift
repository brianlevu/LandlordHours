#if DEBUG
import SwiftUI

// MARK: - DEBUG launch hooks for Today (UI tests and frame captures; compiled out of Release)
//
// Real data through the real Today: these hooks only write rentals, entries and suggestions,
// then Today draws them with its own logic (the windows come from `TodayWindowState`).
//
//   -LHCraftSeed craft|one|eight|goal750
//        craft:   Santa Ray Ave 46h (frame70), Delaney Ct 4h (started), Pine Cabin 62h (half); 100h test
//        one:     Pine Cabin 46h (one rental: no chip menu, no dots, no All rentals)
//        eight:   eight rentals on the 100h test (All rentals leads)
//        goal750: three rentals summing to 750 on the 750h test (All rentals finished)
//   -LHCraftFocus <n>        open on page n (0 = All rentals when there are two or more)
//   -LHCraftWindows lit|dark lit: the opened rental (the first, for All) logged 1.5h today;
//                            dark: nothing logged today anywhere
//   -LHCraftFirstHour        same as dark (the next log is the first of the day: `windowsOn`)
//   -LHCraftScroll           scroll to the end of Today after launch (AX row captures)
// Run with `-LHMockScenario emptyMainTabs`; `-LHSeedSuggestions inbox` adds the To confirm rows.
//
// Older hooks kept for the UI tests:
//   -LHTodayConfirmLimit <n>  keep the n most likely pending suggestions; the rest are dismissed.
//   -LHTodayScanning          start a look-back that finds nothing and holds (the loading state).
@MainActor
enum TodayDebugSeed {
    private static var didApply = false

    static func value(_ flag: String) -> String? { InboxDebugSeed.value(after: flag) }
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    static var scrollsToEnd: Bool { args.contains("-LHCraftScroll") }
    static var focusIndex: Int? { value("-LHCraftFocus").flatMap(Int.init) }
    private static var windowsLit: Bool {
        if args.contains("-LHCraftFirstHour") { return false }
        return value("-LHCraftWindows")?.lowercased() != "dark"
    }

    static func applyIfNeeded(app: AppViewModel) {
        guard !didApply else { return }
        didApply = true
        if let seed = value("-LHCraftSeed") { applyCraftSeed(seed.lowercased(), app: app) }
        InboxDebugSeed.applyIfNeeded(app: app)

        if let raw = value("-LHTodayConfirmLimit"), let limit = Int(raw),
           let store = AppModelHost.shared.suggestionStore {
            let visible = InboxLogic.visible(store.suggestions, now: InboxClock.now())
            let keep = Set(InboxLogic.ranked(visible).prefix(max(0, limit)).map(\.sourceKey))
            for suggestion in visible where !keep.contains(suggestion.sourceKey) {
                store.dismiss(key: suggestion.sourceKey, reason: .notLandlordWork)
            }
            NotificationCenter.default.post(name: .captureSuggestionsDidChange, object: nil)
        }

        if args.contains("-LHTodayScanning") {
            BackfillJob.shared.start(HoldingScanner())
        }
    }

    // MARK: Craft seeds

    private static func applyCraftSeed(_ seed: String, app: AppViewModel) {
        let plan: [(String, Double)]
        let goal: GoalChoice
        switch seed {
        case "one": plan = [("Pine Cabin", 46)]; goal = .mp100
        case "eight":
            plan = [("Santa Ray Ave", 46), ("Delaney Ct", 4), ("Pine Cabin", 62), ("Oak Street Duplex", 12),
                    ("Harbor View Loft", 30), ("Maple Row", 88), ("Cedar Court", 20), ("The Arroyo Seco Schoolhouse Lofts", 8)]
            goal = .mp100
        case "goal750": plan = [("Santa Ray Ave", 300), ("Delaney Ct", 200), ("Pine Cabin", 250)]; goal = .reps750
        default: plan = [("Santa Ray Ave", 46), ("Delaney Ct", 4), ("Pine Cabin", 62)]; goal = .mp100
        }
        if value("-LHGoalChoice") == nil { GoalManager.shared.setGoalChoice(goal) }

        let wasSuppressed = app.suppressCelebrations
        app.suppressCelebrations = true
        defer { app.suppressCelebrations = wasSuppressed }

        // Keep the ids of rentals another DEBUG seed already made (the Inbox seed's suggestions
        // point at them): a name match first, then any leftover id, so every row names a rental.
        var spare = app.properties.filter { p in !plan.contains { $0.0 == p.name } }.map(\.id)
        let rentals = plan.map { item -> RentalProperty in
            let id = app.properties.first { $0.name == item.0 }?.id ?? (spare.isEmpty ? UUID() : spare.removeFirst())
            return RentalProperty(id: id, name: item.0, address: "", propertyType: .ltr)
        }
        app.properties = rentals
        app.timeEntries = []

        // Which rental logged today: the opened page's (the first rental for All rentals).
        let index = focusIndex ?? (rentals.count > 1 ? 1 : 0)
        let litRental = rentals.count > 1 ? max(0, index - 1) : 0
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let year = calendar.component(.year, from: startOfToday)
        let categories: [ActivityCategory] = [.repairs, .management, .leasing, .bookkeeping]
        for (i, rental) in rentals.enumerated() {
            var remaining = plan[i].1
            if windowsLit && i == litRental && remaining >= 1.5,
               let at = calendar.date(byAdding: .hour, value: 9, to: startOfToday) {
                app.timeEntries.append(TimeEntry(propertyId: rental.id, participant: .selfParticipant, category: .repairs,
                                                 hours: 1.5, date: at, notes: ""))
                remaining -= 1.5
            }
            var daysBack = 2   // never yesterday or today: only the lit rental logged today
            while remaining > 0.0001 {
                let hours = min(8, remaining)
                guard let day = calendar.date(byAdding: .day, value: -daysBack, to: startOfToday),
                      calendar.component(.year, from: day) == year,
                      let at = calendar.date(byAdding: .hour, value: 10, to: day) else { break }
                app.timeEntries.append(TimeEntry(propertyId: rental.id, participant: .selfParticipant,
                                                 category: categories[daysBack % categories.count], hours: hours,
                                                 date: at, notes: ""))
                remaining -= hours
                daysBack += 1
            }
        }
        app.saveData()
    }

    /// A look-back that has found nothing yet and keeps going (cancelled with the job).
    private struct HoldingScanner: BackfillScanning {
        @MainActor func scan(
            progress: @escaping @MainActor (ClassifierBatchProgress) -> Void,
            found: @escaping @MainActor ([Suggestion]) -> Void
        ) async -> BackfillScanOutcome {
            progress(ClassifierBatchProgress(completed: 0, total: 40))
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            return BackfillScanOutcome(access: .fullAccess, foundCount: 0, cancelled: Task.isCancelled)
        }
    }
}
#endif
