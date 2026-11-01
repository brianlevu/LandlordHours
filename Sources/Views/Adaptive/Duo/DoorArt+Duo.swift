import SwiftUI

// MARK: - DoorArt, the door's constants (§1.27 asset contract; DU14; ported from package J)
//
// The Duo's half of `DoorArt` (the art constants §1.27 allows hex in [grep]): the hall behind the
// door, its lamp, the veil the work pane lights through, and where the door sits in the still.
// Colours a person reads are tokens elsewhere; these are light.

extension DoorArt {
    // The hall behind the door. Dusk: a dim interior whose luma stays below the facade (v6: 52 vs 66),
    // with a lamp glow. Night: the brightest thing on the house (`warmNight`).
    static let hallDuskTop = Color(hex: "2A1C12")
    static let hallDuskBottom = Color(hex: "4A3220")
    static let warmDusk = Color(hex: "F2B872")

    /// The work pane's veil before the door opens (the unfold wipes it away from the fold), at full
    /// strength: dusk 0.70, night 0.78.
    static let veilDusk = Color(hex: "2A1A0A").opacity(0.70)
    static let veilNight = Color(hex: "05081A").opacity(0.78)

    static func warm(dark: Bool) -> Color { dark ? warmNight : warmDusk }
    static func veil(dark: Bool) -> Color { dark ? veilNight : veilDusk }

    /// The door leaf in the 1206px still, measured from the installed sculpt renders (2026-10-25,
    /// navy leaf bounds on `craft_half` light: x 628–674, y 558–707, plus the 1px outline).
    /// `complete`: the porch post and railing stand in front of the leaf (x 640–665 of 627–676), so a
    /// masked leaf would swing the post with it. Until the art lane renders the leaf as its own layer,
    /// `complete` plays the pane light only, as the framing stages do (open item for Brian).
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
