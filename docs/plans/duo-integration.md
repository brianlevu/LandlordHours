# Duo door: integration note (feat/duo-door, phase 1)

_2026-11-01. Lane: the iPhone Duo's own parts of the locked "door" design (v8, 2026-10-24). The shared two-pane layout (house left, work right, the bar at the right pane's foot) is package J's (`origin/v2/j`, 575cfa0), and the iPad lane (`feat/ipad-adaptive`) owns porting it, root navigation and `Sources/Views/Adaptive/*`. This branch edits none of those and not `ContentView`._

## What this branch adds

| File | What it is | v8 / standard element |
|---|---|---|
| `Sources/Models/Unfold/FoldPosture.swift` | Pure. `FoldPosture.resolve(division:in:)`: `.flat` (no fold: every iPhone, every iPad window, the closed Duo), `.open` (vertical fold, landscape 951×669), `.propped` (fold across, 669×951). `workPaneFoldEdge` (`.leading` / `.top`), `hostsDoor`. `HingeStatus` mirrors `DeviceHinge.Status`. Agrees with J's `PaneDivision.isVertical` (height ≥ width). | v8 `DuoGeo.open` / `.propped`, §1.27 "The model", §1.27 "The door" |
| `Sources/Models/Unfold/UnfoldDoor.swift` | Pure. `UnfoldDoor.move(from:to:reduceMotion:current:)` (the hinge rules), `touch`, `isStranded`; `UnfoldMove` (the linear clock); `DoorPose(t:style:hasDoor:)`, every door layer's value. | v8 `DuoDoorClock`, `duoEase` windows; §B.2 `duoDoor`, §B.3 `duoUnfold` incl. its Reduce Motion column |
| `Sources/Views/Unfold/UnfoldClock.swift` | `UnfoldClock` (ObservableObject; `t`, `style`, `pose`) run on a `CADisplayLink`; `.unfoldDoor(_:posture:)` = `onHingeChange` (iOS 27.1, behind `#available`) + touch-to-finish + the stranded-door guard. | v8 "onHingeChange starts the door", must-prove 2, 3, 7, 9, 10 |
| `Sources/Views/Unfold/UnfoldLight.swift` | `UnfoldLight(pose:edge:veil:)` and `UnfoldLightOverlay(clock:edge:veil:)`: the work pane's veil wiping away from the fold's edge, leading when open and top when propped; a fade (no wipe) under Reduce Motion. Keeps no hex: the caller passes J's `DoorArt.veilDusk/veilNight`. | v8 `DuoInsideLight` |
| `Sources/Views/Debug/UnfoldCaptureBoard.swift` | DEBUG. `-LHSurfaceBoard unfold-door` renders door instants off-screen at 951×669 and 669×951 @3x; `UnfoldCapture.composition` lets the real shell register itself. | v8 `DuoV2Snapshotter` motion mode |
| `Tests/FoldPostureTests.swift`, `Tests/UnfoldDoorTests.swift`, `Tests/UnfoldClockTests.swift` | 10 + 18 + 8 tests. | |
| `scripts/duo/adaptive-unfold.patch` | The exact change to J's `Views/Adaptive/` files that plugs the above in (see below). Made and built against `origin/v2/j` 575cfa0 with J's four `scripts/adaptive/*.patch` applied. | |

## Where it hooks in once feat/ipad-adaptive lands

Apply `scripts/duo/adaptive-unfold.patch` to the ported files (or make the same edits by hand if the port renamed things). In words:

1. **`DoorArt.swift`**: delete `DoorMotion` and the `DoorClock` class; add `typealias DoorClock = UnfoldClock` (or rename the uses). The rules and windows now live in `UnfoldDoor` / `DoorPose`.
2. **`HingeObserver.swift`**: delete. `.unfoldDoor(clock, posture:)` replaces `.duoUnfold(clock, isEnabled:)` and `DoorClock.run/finish`.
3. **`TwoPaneLayout.swift`**:
   - `@StateObject private var clock = DoorClock()` → `@State private var clock = DoorClock()` (held, not observed).
   - `private var posture: FoldPosture { FoldPosture.resolve(division: split.isDivision ? split.gap : nil, in: split.size) }`.
   - `.duoUnfold(clock, isEnabled: split.isDivision)` and the `simultaneousGesture(... clock.finish() ...)` → `.unfoldDoor(clock, posture: posture)`.
   - `.overlay { if split.isDivision { InsideLight(clock: clock) } }` → `.overlay { if let edge = posture.workPaneFoldEdge { UnfoldLightOverlay(clock: clock, edge: edge, veil: dark ? DoorArt.veilNight.opacity(0.78) : DoorArt.veilDusk.opacity(0.70)) } }`.
   - `HousePane(showsDoor: split.isDivision, …)` → `showsDoor: posture.hostsDoor`.
   - DEBUG only: `AdaptiveDebug.captureClock ?? clock` so door captures can hold the clock.
4. **`FrontDoor.swift`**: read `clock.pose` (`leafTurn`, `doorLight`, `leafAngleDegrees`, `leafDarken`, `leafShadow`) instead of easing `t` itself, and add `.opacity(pose.doorLayerOpacity)` on the door's `ZStack` (the Reduce Motion crossfade).
5. **`HousePane.swift`**: `@ObservedObject var clock` → `let clock` (only `FrontDoor` observes it).
6. **`InteriorWall.swift`**: delete `InsideLight` (replaced by `UnfoldLight`).
7. **`AdaptiveDebug.swift`** (DEBUG): `static var captureClock: UnfoldClock?` and `-LHAdaptiveRender door`, which holds the clock at each instant on the real shell (open 3 rentals L/XXL, open All rentals, propped L/XXL; dusk and night).

Nothing touches `ContentView` or the tab structure; `xcodegen generate` picks up the new files.

## Requests to the iPad lane (API changes in `Views/Adaptive/`, which this lane does not edit)

| # | Request | Why | Observed / inferred |
|---|---|---|---|
| R1 | Keep the hinge listener on whenever a hinge exists (`.unfoldDoor` does), not only while `split.isDivision`. | J's `.duoUnfold(clock, isEnabled: split.isDivision)` is off while the window is compact, i.e. exactly while folded. The open event can arrive before the window becomes two-pane; if it is dropped, t stays 0 after the earlier fold and the work pane stays veiled. `.unfoldDoor` also settles a door left short of open after 1 s on a fold (`UnfoldDoor.isStranded`). | Observed in code; the device order is must-prove 3 (inferred until a device run) |
| R2 | Light the work pane from its **top** edge when propped. | J's `InsideLight` always wipes leading → trailing, so the propped work pane (below the fold) would light from its side, not from the fold. | Observed in code |
| R3 | Reduce Motion = a 0.20 s crossfade with no leaf turn and no wipe (§B.3). | J sets `t = 1` at once under Reduce Motion: no crossfade. `DoorPose(style: .crossfade)` + `.opacity(pose.doorLayerOpacity)` gives it. | Observed in code |
| R4 | Do not observe the door clock in `TwoPaneLayout` or `HousePane`. | `@StateObject`/`@ObservedObject` re-evaluate the whole layout and house pane on each of ~48 clock ticks; only the leaf and the veil need to redraw (must-prove 10: 0 hitches with 8 rentals). | Observed in code; the hitch cost is inferred until Instruments on a device |
| R5 | Drive the clock per display frame. | J's clock sleeps 16 ms in a `Task` loop, which drifts against the display; `UnfoldClock` uses `CADisplayLink`. | Inferred |
| R6 | (Art lane, not code) a separate leaf layer for `craft_complete`. | `DoorArt.doorRect(.complete)` is nil because the porch post stands in front of the leaf; §B.3 says the leaf turns on `half` **and** `complete`. Until then `complete` plays the pane light only. | Observed (J's own open item) |

## Still unproven (needs a Duo on iOS 27.1)

Unchanged from §1.27 must-prove 1–11, 14, 15. In particular: the real fold band (1), that `onHingeChange` never fires on a resize or a cold launch (2), the unfold order and first frame (3), touch at 0.1 s (7), fold reverse and the outer display (8), Reduce Motion on device (9), Instruments (10), Brian's gut check of the door (14). Simulators cannot unfold; every Duo frame here is an off-screen `drawHierarchy` render.

## Captures

See the hand-off for paths: `~/AgentScratch/landlordhours/2026-11-01/duo-door/`.
