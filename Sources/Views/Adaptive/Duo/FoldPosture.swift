import CoreGraphics

// MARK: - FoldPosture: which way the fold lies (standard §1.27 the Duo poses; §B.3 `duoUnfold`)
//
// Pure. The input is the active `.division` region the system reports (iOS 27.1
// `GeometryProxy.reservedRegions(kind: .division)`, frame plus margins, in the root's space) and the
// window size. Never the screen, the idiom, a device name, the orientation or a hard-coded 951/669/24:
//
//   · no division           → `.flat`    every iPhone, every iPad window, the closed Duo's outer display
//   · a vertical division   → `.open`    the Duo held open (landscape 951×669): house left, work right
//   · a horizontal division → `.propped` the Duo propped up (669×951): house above, work below
//
// It agrees with package J's `PaneDivision.isVertical` (height ≥ width is vertical), so the door's
// light and the panes never disagree about which way the fold runs. The layout mode itself (and the
// 380pt pane floor) stays `LayoutMode.resolve`'s; the posture only says where the door can play and
// which edge of the work pane the light comes from.

/// The hinge's state, mirrored from SwiftUI's `DeviceHinge.Status` (iOS 27.1) so the door logic is
/// testable on every OS the app supports.
enum HingeStatus: Equatable, Sendable {
    case closed
    case partiallyOpen
    case fullyOpen

    var isOpen: Bool { self != .closed }
}

/// The edge of the work pane that meets the fold: the door's light enters there.
enum FoldEdge: Equatable, Sendable {
    case leading
    case top
}

enum FoldPosture: Equatable, Sendable {
    /// No fold in the window.
    case flat
    /// The fold runs top to bottom: two panes side by side.
    case open
    /// The fold runs across: two halves, one above the other.
    case propped

    /// The posture for an active division in a window of `size`. A division that is empty, not
    /// finite, or wholly outside the window is no fold; one partly outside is read by the part inside.
    static func resolve(division: CGRect?, in size: CGSize) -> FoldPosture {
        guard let division,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              division.origin.x.isFinite, division.origin.y.isFinite,
              division.width.isFinite, division.height.isFinite,
              division.width > 0, division.height > 0 else { return .flat }
        let inside = division.intersection(CGRect(origin: .zero, size: size))
        guard !inside.isNull, inside.width > 0, inside.height > 0 else { return .flat }
        return inside.height >= inside.width ? .open : .propped
    }

    /// Where the work pane meets the fold (nil when there is no fold).
    var workPaneFoldEdge: FoldEdge? {
        switch self {
        case .flat: return nil
        case .open: return .leading
        case .propped: return .top
        }
    }

    /// Only a physical fold hosts the door. An iPad two-pane window is lit at rest (§1.27 "The door").
    var hostsDoor: Bool { self != .flat }
}
