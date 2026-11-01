import SwiftUI

// MARK: - The Duo lane's hooks (owner: branch feat/duo-door; docs/plans/two-pane-api.md)
//
// Plugs the fold and the door into `TwoPaneLayout`:
//   · division     the active `.division` region (iOS 27.1 `reservedRegions`); nil on iPad.
//   · arrangement  `ArrangementView` along the fold when the division is the system's.
//   · heroOverlay  the door leaf over the house (`half`; framing stages and the skyline get none).
//   · workOverlay  the light that wipes in from the fold: leading when open, top when propped.
//   · root         `DuoDoorRoot`: the hinge listener and the door clock, shared through the environment.
// On iPad every one of these resolves to nothing: no division, so no posture, no door and no light.

extension TwoPaneHooks {
    /// The hooks the app's root installs (`TwoPaneHooks.installed`).
    @MainActor static var duo: TwoPaneHooks {
        var hooks = TwoPaneHooks()
        hooks.division = { DuoHooks.division($0) }
        hooks.arrangement = { split, house, work in DuoHooks.arrangement(split, house: house, work: work) }
        hooks.heroOverlay = { AnyView(DuoDoorOverlay(context: $0)) }
        hooks.workOverlay = { AnyView(DuoPaneLightOverlay(split: $0)) }
        hooks.root = { content, split in AnyView(DuoDoorRoot(content: content, split: split)) }
        return hooks
    }
}
