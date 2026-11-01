# Two-pane layout: the API the Duo lane codes against

Owner: branch `feat/ipad-adaptive` (iPad and the shared two-pane layout). Consumer: branch `feat/duo-door` (Duo posture detection and the door).
Law: DESIGN-STANDARD §1.27, "Adaptive layout: one model for iPhone, iPad and the iPhone Duo" (int/2.3).
Status: 2026-11-01, first cut. The names below are stable; anything not listed here is internal and may change.

## Who owns what

| Path | Owner | Note |
|---|---|---|
| `Sources/Views/ContentView.swift` (root navigation) | iPad lane | The root is `TwoPaneLayout { mainContent }.twoPaneHooks(TwoPaneHooks.installed)` |
| `Sources/Views/Adaptive/*.swift` | iPad lane | Layout, panes, house pane, work pane, bar bridge, Today work pane |
| `Sources/Views/Adaptive/Duo/TwoPaneHooks+Duo.swift` | **Duo lane** | The one file the Duo lane replaces to install its hooks. Today a stub that returns `.none` |
| `Sources/Views/Adaptive/Duo/*` (new files) | **Duo lane** | Hinge observer, door leaf, door clock, inside light, the `reservedRegions` reader, `ArrangementView` |

The Duo lane does not edit any other file in `Views/Adaptive/` or `ContentView.swift`. If it needs a new seam, it asks the iPad lane, which adds it to `TwoPaneHooks`.

## The mode function

```swift
enum LayoutMode { case compact, twoPane, stacked; var isSplit: Bool }

struct PaneDivision { let rect: CGRect; var isVertical: Bool }   // the fold, margins included, in the root's space

struct LayoutSplit {
    let mode: LayoutMode
    let size: CGSize        // the scene, safe areas included
    let gap: CGRect         // iPad: the 24pt page gap; Duo: the division rect
    let isDivision: Bool    // true only when the gap is a physical fold
    var first: CGRect       // house pane: leading (two-pane) or top (stacked)
    var second: CGRect      // work pane: trailing or bottom
}

LayoutMode.resolve(previous: LayoutMode?, size: CGSize, division: PaneDivision?, live: Bool) -> LayoutSplit
```

- The only place the mode is computed (§1.27 [grep]). It is pure and unit-tested in `Tests/AdaptiveLayoutTests.swift`.
- A vertical division gives two-pane split at the fold if each pane is at least 380 wide; a horizontal one gives stacked if each half is at least 380 tall; otherwise compact.
- With no division: two-pane iff `W ≥ 800` and `H ≥ 645`. While a resize is live, hysteresis is +8 (808 / 653). After 0.3 s still, and at scene connect, the mode is re-resolved with `previous: nil`.
- Constants: `LayoutMode.paneGap` (24, iPad only), `minPane` 380, `minWidth` 800, `minHeight` 645, `hysteresis` 8, `settleDelay` 0.3.
- Sizes inside a pane: `PaneMetrics.heroSide(paneWidth:paneHeight:accessibility:)`, `numeral(...)`, `gutter(paneWidth:onDuo:)` (pass `onDuo: split.isDivision`), `shelfModel(paneWidth:)`, `contentCap` 600, `barClearance` 84.

## The root view

```swift
TwoPaneLayout { /* the shell: the root TabView and its modifiers */ }
    .twoPaneHooks(TwoPaneHooks.installed)
```

- Measures the scene with `onGeometryChange` on a sibling probe (never the screen, idiom or orientation) and calls `hooks.division(proxy)` in that same transform to read the fold.
- Sets `\.layoutMode` for everything below it.
- Compact on a compact size class: the shell as it is (the phone). Compact on a regular size class (a narrow iPad window): the shell in `WorkPane`, so the bar is the same bottom bar.
- Two-pane: `HousePane` | the gap | `WorkPane`, over one page (`LHPage` + `FoldWash`, then `InteriorWall`). If `split.isDivision`, the division came from the system, and `hooks.arrangement` is set, the Duo lane's container lays out the two panes instead of the `HStack`.
- Stacked: `HousePane` over `WorkPane`, with the fold between them, over `StackedWall`.

## The hooks (`Sources/Views/Adaptive/TwoPaneHooks.swift`)

```swift
struct TwoPaneHeroContext { let stage: CraftStage?; let side: CGFloat; let split: LayoutSplit }

struct TwoPaneHooks {
    var division: (GeometryProxy) -> PaneDivision?                                  // default: always nil
    var arrangement: (@MainActor (LayoutSplit, AnyView /*house*/, AnyView /*work*/) -> AnyView)?
    var heroOverlay: (@MainActor (TwoPaneHeroContext) -> AnyView)?                 // over the house diorama
    var workOverlay: (@MainActor (LayoutSplit) -> AnyView)?                         // over the work pane
    var root: (@MainActor (AnyView, LayoutSplit) -> AnyView)?                       // wraps the whole layout once
    static let none: TwoPaneHooks
    @MainActor static var installed: TwoPaneHooks { duo }                           // `duo` lives in Duo/TwoPaneHooks+Duo.swift
}
extension EnvironmentValues { var twoPaneHooks: TwoPaneHooks }
extension View { func twoPaneHooks(_: TwoPaneHooks) -> some View }
```

How the door fits these seams (the Duo lane's design, sketched so the seams are sufficient):
- `root` wraps the layout in the hinge observer (`onHingeChange`, iOS 27.1) and injects the door clock with `.environmentObject(clock)`. The clock must be owned by a view the Duo lane writes (for example a small `DuoDoorRoot` view holding `@StateObject var clock`), because the hook closures cannot hold state.
- `heroOverlay` returns the door leaf view, which reads the clock with `@EnvironmentObject`. It is applied inside `HousePane`, below `root`, so the environment reaches it.
- `workOverlay` returns the inside-light veil. It is applied to the work pane from outside the pane's hosting controller, so the environment reaches it too. **Nothing inside the work pane's hosting controller inherits SwiftUI environment from above**; see `WorkPaneEnvironment`.
- `division` reads `proxy.reservedRegions(kind: .division)` behind `#available(iOS 27.1, *)` and returns the active region's frame plus margins. It runs in the geometry transform, so it must be cheap and side-effect free.
- `arrangement` returns `ArrangementView { house } secondary: { work }` with the split style. Must-prove 15 (which side the primary renders on) is the Duo lane's.
- Rule kept from §1.27: the door plays only on a hinge event, never on a size, arrangement or scene change. `TwoPaneLayout` never animates the mode change itself.

## Environment the panes publish

| Key | Type | Set by | Meaning |
|---|---|---|---|
| `\.layoutMode` | `LayoutMode` | `TwoPaneLayout` | compact, two-pane or stacked |
| `\.paneContext` | `PaneContext` (`.sheet` / `.pane`) | `TwoPaneLayout` | Do details and Log time open as sheets, or in the right pane? Screens read this, never widths |
| `\.paneGutter` | `CGFloat` | `TwoPaneLayout` | 16 on the Duo and in panes under 440, else 24 |
| `\.paneFoldInset` | `CGFloat` | `TwoPaneLayout` | Half the gap or fold, so a wall drawn in the pane lines up with the house pane's light |
| `\.paneWindowHeight` | `CGFloat` | `TwoPaneLayout` | The window height (0 in compact), for `PaneReach` |
| `\.paneLogRental` | `UUID?` | `TwoPaneLayout` | The rental the house pane shows; Log time in the pane starts on it |
| `AdaptiveSelection` (environment object) | class | `TwoPaneLayout` | The shelf's selection (`selectedID`, `selectedRentalID`, `isAllRentals`) and the work pane's in-place route |

## The work pane and the bar (must-prove 12)

- `WorkPane { content }` hosts the shell's `TabView` in one child `UIHostingController` with `traitOverrides.horizontalSizeClass = .compact` (the only such line in shipping code). The system then draws its compact bottom bar at the pane's foot. `.toolbarVerticalBehavior(.disabled)` (iOS 27.1) keeps the Duo from turning it into a side rail.
- `WorkPane.usesCompactBridge` is true on iPadOS 26 and later only (`bridgeProven(osMajor:)`). iPadOS 18 to 25 is UNPROVEN on this Mac (no 18 runtime or device, 2026-11-01), so it gets §1.27's fallback, the system's own iPad bar over the right pane. DEBUG flags: `-LHPaneSystemBar` forces the fallback; `-LHPaneCompactBridge` forces the bridge.
- `.paneAwareLogTime(route:background:onDismiss:sheet:)` is the one Log time presentation site: a `.large` sheet in compact, the card in the work pane otherwise. While it is up in the pane, `PaneHostBridge` hides the tab's content under it at the UIKit level; the bar stays.

## What the Duo lane must not do

- Compute a mode anywhere but `LayoutMode.resolve`, or read `userInterfaceIdiom`, `UIDevice.orientation` or a device name.
- Name a view `*Duo*`, `*Pad*` or `*iPad*` outside `Views/Adaptive/` (§1.27 [grep]).
- Add a second `traitOverrides.horizontalSizeClass` or any `.environment(\.horizontalSizeClass, …)`.
- Hard-code 951, 669 or 24 in shipping layout code; the fold comes from the division.
