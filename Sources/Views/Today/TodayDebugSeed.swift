#if DEBUG
import SwiftUI

// MARK: - DEBUG launch hooks for Today's below-the-house states (UI tests and frame captures)
//
// Run after the Inbox seed (`-LHSeedSuggestions …`), which this applies first so the order is fixed.
//   -LHTodayConfirmLimit <n>     keep the n most likely pending suggestions; the rest are removed
//                                from the inbox (store-level dismiss), so To confirm shows n.
//   -LHTodayWeekSample <h,h,…>   replace this week's entries (Monday first, up to today, using the
//                                pinned inbox clock) with your own countable hours per day.
//   -LHTodayScanning             start a look-back that finds nothing and holds (the loading state).
//   -LHTodayScrollTo <id>        scroll Today so a section leads: draft | confirm | week | record.
//   -LHTodaySwipePreview <dx>    draw the first To confirm row slid by dx points (the swipe frame).
//   -LHNoSwipePeek               no one-time swipe peek (deterministic frames).
// Compiled out of Release.
@MainActor
enum TodayDebugSeed {
    private static var didApply = false

    static func value(_ flag: String) -> String? { InboxDebugSeed.value(after: flag) }

    static var scrollTarget: String? { value("-LHTodayScrollTo") }

    static var swipePreviewOffset: CGFloat? {
        value("-LHTodaySwipePreview").flatMap(Double.init).map { CGFloat($0) }
    }

    static func applyIfNeeded(app: AppViewModel) {
        guard !didApply else { return }
        didApply = true
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

        if let raw = value("-LHTodayWeekSample") {
            seedWeek(raw.split(separator: ",").compactMap { Double($0) }, app: app)
        }

        if ProcessInfo.processInfo.arguments.contains("-LHTodayScanning") {
            BackfillJob.shared.start(HoldingScanner())
        }
    }

    private static func seedWeek(_ hours: [Double], app: AppViewModel) {
        guard let property = app.properties.first else { return }
        let calendar = Calendar.current
        let now = InboxClock.now()
        let start = TodayWeek.startOfWeek(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let wasSuppressed = app.suppressCelebrations
        app.suppressCelebrations = true
        defer { app.suppressCelebrations = wasSuppressed }
        app.timeEntries.removeAll { $0.date >= start && $0.date < (calendar.date(byAdding: .day, value: 7, to: start) ?? start) }
        let categories: [ActivityCategory] = [.repairs, .leasing, .management, .bookkeeping]
        for (offset, value) in hours.prefix(7).enumerated() where value > 0 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start), day <= today,
                  let at = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) else { continue }
            app.timeEntries.append(TimeEntry(propertyId: property.id, participant: .selfParticipant,
                                             category: categories[offset % categories.count], hours: value,
                                             date: at, notes: ""))
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
