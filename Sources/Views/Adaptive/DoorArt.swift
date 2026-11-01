import SwiftUI

// MARK: - DoorArt: the two-pane wall-light constants (§1.27 asset contract; DU10, DU11)
//
// The door leaf, hall and veil constants are the Duo lane's (feat/duo-door); this file keeps only
// the light both devices share: the wash at the gap and the shelf pill edge.
//
// The one file in `Views/Adaptive/` allowed hex literals [grep]: art constants, like
// `HouseTokens`. Colours a person reads (text, edges a card needs) are tokens elsewhere; these are
// light: the hall behind the door, its lamp, the warm pool, the veil the pane lights through.

enum DoorArt {
    /// The door's light on the wall by day (screen-blended).
    static let glowDusk = Color(hex: "FFE6C2")
    static let warmNight = Color(hex: "FFC877")

    /// The night pool's strength: the card edge token is locked (DU11), so the pool gives way.
    static let nightGlow: Double = 0.09
    static let duskGlow: Double = 0.55

    /// The selected shelf pill's edge: ≥ 3:1 on the shelf wall (dusk #7A6F58, night #5D6AA0).
    static func shelfPillEdge(dark: Bool) -> Color { Color(hex: dark ? "5D6AA0" : "7A6F58") }

    static func glow(dark: Bool) -> Color { (dark ? warmNight : glowDusk).opacity(dark ? nightGlow : duskGlow) }
}
