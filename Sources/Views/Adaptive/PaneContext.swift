import SwiftUI

// MARK: - PaneContext: does a detail open as a sheet or in the right pane? (§1.27; plan J1)
//
// The contract every screen reads instead of checking widths. In compact, a screen's detail and
// Log time open as system sheets; in two-pane and stacked they open inside the right pane, over
// the interior wall, with a back link. Screens never look at the window size themselves.

enum PaneContext: Equatable, Sendable {
    /// Compact: details and Log time are sheets.
    case sheet
    /// Two-pane or stacked: details and Log time open in the right pane.
    case pane
}

private struct PaneContextKey: EnvironmentKey {
    static let defaultValue: PaneContext = .sheet
}

extension EnvironmentValues {
    /// Set by `TwoPaneLayout`: `.pane` inside the work pane of a two-pane or stacked window.
    var paneContext: PaneContext {
        get { self[PaneContextKey.self] }
        set { self[PaneContextKey.self] = newValue }
    }
}

private struct PaneFoldInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Half the gap or fold band: how far outside the work pane's leading edge the fold's midline
    /// lies, so a wall drawn inside the pane shares the house pane's light profile (DU9).
    var paneFoldInset: CGFloat {
        get { self[PaneFoldInsetKey.self] }
        set { self[PaneFoldInsetKey.self] = newValue }
    }
}

private struct PaneLogRentalKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// The rental the house pane shows, inside a two-pane or stacked work pane (nil in compact and
    /// on "All rentals"). Log time in the pane starts on it, so it names the rental shown (§1.27).
    /// `LogTimeSheet` reads it (package E; `scripts/adaptive/logtime-pane-rental.patch`).
    var paneLogRental: UUID? {
        get { self[PaneLogRentalKey.self] }
        set { self[PaneLogRentalKey.self] = newValue }
    }
}

private struct PaneGutterKey: EnvironmentKey {
    static let defaultValue: CGFloat = 16
}

extension EnvironmentValues {
    /// The gutter inside the work pane (§1.27 density addendum): 16 on the Duo and in iPad panes
    /// under 440, else 24. Set by `TwoPaneLayout` from `PaneMetrics.gutter`.
    var paneGutter: CGFloat {
        get { self[PaneGutterKey.self] }
        set { self[PaneGutterKey.self] = newValue }
    }
}

// MARK: - What the right pane shows over its tab's root

/// The right pane's own stack: the tab's root, or a detail / Log time opened over it in place.
enum WorkPaneRoute: Equatable, Identifiable {
    /// A To confirm item, opened from Today's work pane (back link "To confirm").
    case suggestion(String)
    /// Log time, in the pane, naming the rental shown.
    case logTime(LogSheetRoute)

    var id: String {
        switch self {
        case .suggestion(let key): return "suggestion-\(key)"
        case .logTime(let route): return "log-\(route.id)"
        }
    }
}

/// The selection the house pane's shelf drives (§1.27 "What the shelf selects"): the hero, the
/// number block, Today's To confirm filter, and which rental page the Rentals tab shows. Nothing
/// else; Inbox and Records are never filtered by it (AD19).
@MainActor
final class AdaptiveSelection: ObservableObject {
    /// The shelf item: `HouseShelf.allID` or a rental's UUID string.
    @Published var selectedID: String
    /// The right pane's route over the current tab's root (nil = the root).
    @Published var route: WorkPaneRoute?

    init(selectedID: String = HouseShelf.allID) {
        self.selectedID = selectedID
    }

    var selectedRentalID: UUID? { UUID(uuidString: selectedID) }
    var isAllRentals: Bool { selectedRentalID == nil }

    func select(_ id: String) {
        guard id != selectedID else { return }
        selectedID = id
    }

    func open(_ route: WorkPaneRoute) { self.route = route }
    func close() { route = nil }
}
