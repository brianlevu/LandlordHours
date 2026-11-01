import SwiftUI

// MARK: - TwoPaneHooks: the seams the Duo lane fills (§1.27; docs/plans/two-pane-api.md)
//
// `TwoPaneLayout` owns the layout for every device: the mode (`LayoutMode.resolve`), the panes, the
// gap, the house pane, the work pane and its compact bar bridge. It knows nothing about hinges,
// postures or the door. The Duo lane (branch feat/duo-door) plugs those in here, and only here:
//
//   · `division`    reads the active fold from the root's geometry (`reservedRegions(kind: .division)`
//                   on iOS 27.1). nil everywhere else, so an iPad never has a division.
//   · `arrangement` lays out the two panes when the division is real (`ArrangementView`); nil keeps
//                   the `HStack` / `VStack` with the gap, which is what the iPad uses.
//   · `heroOverlay` draws over the house pane's diorama (the door leaf), given the stage and side.
//   · `workOverlay` draws over the work pane (the light that wipes in from the fold).
//   · `root`        wraps the whole layout once (the hinge observer and the door clock it shares
//                   with the overlays through the environment).
//
// Every hook defaults to "nothing", so the iPad build has no Duo code path at all. The hooks are
// installed with `.twoPaneHooks(_:)` above `TwoPaneLayout`; `TwoPaneHooks.installed` is the value
// the root uses; it returns `TwoPaneHooks.duo`, defined in `Duo/TwoPaneHooks+Duo.swift`, the one
// file in this folder the Duo lane owns.

struct TwoPaneHeroContext {
    /// The house shown (nil on "All rentals" and on an empty lot).
    let stage: CraftStage?
    /// The diorama's side in points.
    let side: CGFloat
    /// The window's split (the division, if any, is `split.gap` with `split.isDivision`).
    let split: LayoutSplit
}

struct TwoPaneHooks {
    var division: (GeometryProxy) -> PaneDivision? = { _ in nil }
    var arrangement: (@MainActor (_ split: LayoutSplit, _ house: AnyView, _ work: AnyView) -> AnyView)?
    var heroOverlay: (@MainActor (TwoPaneHeroContext) -> AnyView)?
    var workOverlay: (@MainActor (LayoutSplit) -> AnyView)?
    var root: (@MainActor (_ content: AnyView, _ split: LayoutSplit) -> AnyView)?

    /// No hooks: the iPad, and every device until the Duo lane installs its own.
    static let none = TwoPaneHooks()

    /// The hooks the app's root installs: the Duo lane's, from `Duo/TwoPaneHooks+Duo.swift` (the one
    /// file it owns here); `.none` until it fills that file.
    @MainActor static var installed: TwoPaneHooks { duo }
}

private struct TwoPaneHooksKey: EnvironmentKey {
    static let defaultValue = TwoPaneHooks.none
}

extension EnvironmentValues {
    /// The Duo lane's seams into `TwoPaneLayout` (none on iPad).
    var twoPaneHooks: TwoPaneHooks {
        get { self[TwoPaneHooksKey.self] }
        set { self[TwoPaneHooksKey.self] = newValue }
    }
}

extension View {
    /// Installs the Duo lane's seams for the `TwoPaneLayout` below.
    func twoPaneHooks(_ hooks: TwoPaneHooks) -> some View {
        environment(\.twoPaneHooks, hooks)
    }
}
