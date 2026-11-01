import Foundation

// MARK: - Inbox quiet (2.3 package F)
//
// "Not sure" items leave the main list. They sit behind one collapsed "Not sure" row under the
// To confirm card, are not counted in "To confirm · N" (Inbox, Today, the tab badge, widgets),
// and are never notified. `InboxViewModel.visible` reads the main list through `mainList`
// (package A's seam line); `InboxLogic.visible` applies the same filter, so every caller agrees.
//
// Synthetic office set (200 office events, 60 rental): main-list noise 42 → 0–1 of 200, rental
// still reachable (main list or Not sure) 60 of 60. See the package F hand-off.
extension InboxLogic {
    /// A "Not sure" item: below the likely line. It goes behind the collapsed row.
    static func isMaybe(_ suggestion: Suggestion) -> Bool {
        suggestion.confidence < ClassifierThresholds.likely
    }

    /// The main list: everything that is not "Not sure". Idempotent.
    static func mainList(_ suggestions: [Suggestion]) -> [Suggestion] {
        suggestions.filter { !isMaybe($0) }
    }

    /// The items behind the collapsed "Not sure" row: pending, over, and below the likely line.
    /// Newest first, like the main list's days.
    static func maybeList(_ suggestions: [Suggestion], now: Date) -> [Suggestion] {
        due(suggestions, now: now).filter(isMaybe).sorted { $0.start > $1.start }
    }
}
