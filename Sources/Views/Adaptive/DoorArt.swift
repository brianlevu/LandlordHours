import SwiftUI

// MARK: - DoorArt: the two-pane art constants (§1.27 asset contract; DU10, DU11, DU14)
//
// The one file in `Views/Adaptive/` allowed hex literals [grep]: art constants, like
// `HouseTokens`. Colours a person reads (text, edges a card needs) are tokens elsewhere; these are
// light: the hall behind the door, its lamp, the warm pool, the veil the pane lights through.

enum DoorArt {
    // The hall behind the door. Dusk: a dim interior whose luma stays below the facade (v6: 52 vs 66),
    // with a lamp glow. Night: the brightest thing on the house.
    static let hallDuskTop = Color(hex: "2A1C12")
    static let hallDuskBottom = Color(hex: "4A3220")
    static let warmDusk = Color(hex: "F2B872")
    static let warmNight = Color(hex: "FFC877")
    /// The door's light on the wall by day (screen-blended).
    static let glowDusk = Color(hex: "FFE6C2")

    /// The right pane's veil before the door opens (the unfold wipes it away from the fold).
    static let veilDusk = Color(hex: "2A1A0A")
    static let veilNight = Color(hex: "05081A")

    /// The night pool's strength: the card edge token is locked (DU11), so the pool gives way.
    static let nightGlow: Double = 0.09
    static let duskGlow: Double = 0.55

    /// The selected shelf pill's edge: ≥ 3:1 on the shelf wall (dusk #7A6F58, night #5D6AA0).
    static func shelfPillEdge(dark: Bool) -> Color { Color(hex: dark ? "5D6AA0" : "7A6F58") }

    static func warm(dark: Bool) -> Color { dark ? warmNight : warmDusk }
    static func glow(dark: Bool) -> Color { (dark ? warmNight : glowDusk).opacity(dark ? nightGlow : duskGlow) }

    /// The door leaf in the 1206px still, measured from the installed sculpt renders (2026-10-25,
    /// navy leaf bounds on `craft_half` light: x 628–674, y 558–707, plus the 1px outline).
    /// `complete`: the porch post and railing stand in front of the leaf (x 640–665 of 627–676), so
    /// a masked leaf would swing the post with it. Until the art lane renders the leaf as its own
    /// layer, `complete` plays the pane light only, as the framing stages do (open item for Brian).
    static func doorRect(stage: CraftStage) -> CGRect? {
        switch stage {
        case .half: return CGRect(x: 627, y: 557, width: 49, height: 151)
        case .complete, .started, .frame70, .framing: return nil
        }
    }

    /// The still's side in pixels the rect is measured in.
    static let stillSide: CGFloat = 1206

    /// The door's wall recedes up and to the right: its horizontal edges rise 0.28px per px (the lit
    /// door panes on `craft_half` light, y 578 → 568 over x 629 → 665). The opening is drawn as that
    /// parallelogram, never an upright box (gate J 1.2: "a slab pasted on the wall").
    static let facadeSlope: CGFloat = -0.28
}

/// `duoDoor` (§B.2): a 0.80 s door clock t 0 → 1 (`.linear(duration: 0.80)`), 0.50 s back on fold,
/// a 0.20 s crossfade under Reduce Motion. Lives here until package A folds it into `AppAnimation`.
enum DoorMotion {
    static let open = Animation.linear(duration: 0.80)
    static let close = Animation.linear(duration: 0.50)
    static let reduced = Animation.easeOut(duration: 0.20)

    /// Ease-out cubic of `t` over its own window [a, b] (every door layer is a pure function of t).
    static func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = min(max((t - a) / (b - a), 0), 1)
        return 1 - pow(1 - u, 3)
    }
}

/// The door clock: 0 = door shut and the work pane dark; 1 = open and lit (at rest everywhere).
@MainActor
final class DoorClock: ObservableObject {
    @Published var t: Double = 1
    /// The running ramp (`run(to:duration:)` in HingeObserver.swift).
    var runner: Task<Void, Never>?

    init(t: Double = 1) { self.t = t }
}
