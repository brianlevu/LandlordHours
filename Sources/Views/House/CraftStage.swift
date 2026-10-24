import CoreGraphics
import Foundation

// MARK: - The crafted house: stage and placement (pure; plan package 0)
//
// Standard §H.3: there is ONE answer to "what stage is this rental", `CraftStage.stage(hours:goal:)`.
// Stage thresholds are a share of the goal the house measures against (100, 500 or 750):
//   started < 0.20 · frame70 < 0.47 · framing < 0.60 · half < 1.0 · complete ≥ 1.0
// The v1 `HouseProgress.stage` forwards here, so Today, Onboarding, Reports, the widget and
// `TodayHouse` all read the same stage. "All rentals" (§H.1 H10) is the same function over the
// summed hours and the largest goal (`CraftHeroTotals` in `ViewModels/TodayHouse.swift`).
//
// Also here: the H1 placement table (per-stage scale about the ground line and lift at a 390pt
// frame) and the hero frame sizes (H1, H3, H7, the medium size of §H.5, the thumbnails). The view
// that draws them is `House/CraftHouseView.swift` (package A); it reads these numbers and never
// keeps a second copy.

/// The five rendered stages of the crafted house. Raw values are the asset names (§H.3).
enum CraftStage: String, CaseIterable, Comparable, Sendable {
    /// Framing, first storey (just started).
    case started = "craft_started"
    /// Framing, most of it.
    case frame70 = "craft_frame70"
    /// Framing only, complete.
    case framing = "craft_framing"
    /// Roof on, siding about half.
    case half = "craft_half"
    /// Finished.
    case complete = "craft_complete"

    // MARK: The one stage function

    /// Upper bounds (exclusive) of each stage as a share of the goal. `complete` has none.
    static let shareThresholds: [(stage: CraftStage, below: Double)] = [
        (.started, 0.20), (.frame70, 0.47), (.framing, 0.60), (.half, 1.0),
    ]

    /// The stage for `hours` measured against `goal` hours. Bad input (negative or non-finite
    /// hours) draws the first stage; a goal that is not a positive number has nothing to measure
    /// against and also draws the first stage.
    static func stage(hours: Double, goal: Double) -> CraftStage {
        let h = hours.isFinite ? max(0, hours) : 0
        guard goal.isFinite, goal > 0 else { return .started }
        let share = h / goal
        return shareThresholds.first { share < $0.below }?.stage ?? .complete
    }

    // MARK: Assets (§H.3)

    /// The lit still: `craft_<stage>`.
    var assetName: String { rawValue }

    /// The still for a window state: the base asset is lit; `-unlit` is the dark-glass twin.
    func assetName(lit: Bool) -> String { lit ? rawValue : rawValue + "-unlit" }

    /// The house-only thumbnail (lit only): `craft_thumb_<stage>`.
    var thumbnailName: String { "craft_thumb_" + rawValue.dropFirst("craft_".count) }

    /// True for the stages with no windows yet, where the slab work lamp plays the lit role.
    var isFraming: Bool { self == .started || self == .frame70 || self == .framing }

    // MARK: Placement (§H.1, the stage placement table)

    /// The frame side the lift is written against.
    static let referenceSide: CGFloat = 390

    /// Scale about the ground line (bottom centre, y = 0.92 of the frame). The early stages are
    /// short and sit low, so they are scaled up to fill the hero slot; the art is clipped to the frame.
    var stageScale: CGFloat {
        switch self {
        case .started: return 1.18
        case .frame70: return 1.08
        case .framing, .half, .complete: return 1.0
        }
    }

    /// Lift in points at a 390pt frame (closes the dead space under the rental chip).
    var stageLiftAtReference: CGFloat {
        switch self {
        case .started: return 30
        case .frame70: return 12
        case .framing, .half, .complete: return 0
        }
    }

    /// The lift for a frame of `side` points: scales with `side / 390`.
    func stageLift(side: CGFloat) -> CGFloat {
        guard side.isFinite, side > 0 else { return 0 }
        return stageLiftAtReference * side / Self.referenceSide
    }

    /// Where the lot's ground line sits in the still (the scale anchor).
    static let groundLine: CGFloat = 0.92

    // MARK: Words

    /// The stage in words, for VoiceOver and meta lines ("Frame going up").
    var spokenName: String {
        switch self {
        case .started: return String(localized: "stage.started", defaultValue: "Framing started", table: "Shared")
        case .frame70: return String(localized: "stage.frame70", defaultValue: "Frame going up", table: "Shared")
        case .framing: return String(localized: "stage.framing", defaultValue: "Frame finished", table: "Shared")
        case .half: return String(localized: "stage.half", defaultValue: "Roof on, siding going up", table: "Shared")
        case .complete: return String(localized: "stage.complete", defaultValue: "House finished", table: "Shared")
        }
    }

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: CraftStage, rhs: CraftStage) -> Bool { lhs.order < rhs.order }
}

// MARK: - Hero sizes (§H.1 H1, H3, H7; §H.5)

/// The sizes the crafted house is drawn at. Pure arithmetic over the window size; the view applies
/// the band rules of §1.27 and the hysteresis of H8.
enum CraftHeroSize {
    /// Band B and C: the hero frame is fixed at this side, centred in the ≤ 600 column (H6).
    static let wideBandSide: CGFloat = 390
    /// The diorama (with its lot) is never drawn under this side (§H.5, thumbnail minimum).
    static let minimumDioramaSide: CGFloat = 220
    /// House-only thumbnail sizes: rows (44), picker grids and sheet headers (56), the onboarding
    /// step, sidebar header and widgets (120). Never under 44.
    static let thumbnailRow: CGFloat = 44
    static let thumbnailHeader: CGFloat = 56
    static let thumbnailLarge: CGFloat = 120

    /// Today's hero frame side in band A: `min(W − 12, round(0.446 × H))` at default to XXL, and
    /// `min(W − 12, round(0.337 × H))` at accessibility sizes (H3). 402×874 → 390 (AX 295);
    /// 375×667 → 297; Duo closed 382×644 → 287.
    static func hero(windowWidth: CGFloat, windowHeight: CGFloat, accessibility: Bool) -> CGFloat {
        side(windowWidth: windowWidth, windowHeight: windowHeight, share: accessibility ? 0.337 : 0.446)
    }

    /// The rental page's medium frame: `min(W − 12, round(0.343 × H))` (402×874 → 300), and
    /// 220 at accessibility sizes (§H.5).
    static func medium(windowWidth: CGFloat, windowHeight: CGFloat, accessibility: Bool) -> CGFloat {
        if accessibility { return min(minimumDioramaSide, max(0, windowWidth - 12)) }
        return side(windowWidth: windowWidth, windowHeight: windowHeight, share: 0.343)
    }

    /// The numeral cap: 64pt when the window is under 700pt tall (H7), 54pt at accessibility sizes (H3).
    static func numeralCap(windowHeight: CGFloat, accessibility: Bool) -> CGFloat? {
        if accessibility { return 54 }
        return windowHeight < 700 ? 64 : nil
    }

    private static func side(windowWidth: CGFloat, windowHeight: CGFloat, share: CGFloat) -> CGFloat {
        guard windowWidth.isFinite, windowHeight.isFinite, windowWidth > 0, windowHeight > 0 else { return 0 }
        return max(0, min(windowWidth - 12, (share * windowHeight).rounded()))
    }
}
