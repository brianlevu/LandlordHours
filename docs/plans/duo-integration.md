# Duo door: integration note (feat/duo-door, phase 1)

_2026-11-01. Lane: the iPhone Duo's own parts of the locked "door" design (v8, 2026-10-24). The shared two-pane layout is the iPad lane's (`feat/ipad-adaptive`, ported from package J). This branch is built on it and plugs in only through `TwoPaneHooks` (`docs/plans/two-pane-api.md`). It edits nothing in `Sources/Views/Adaptive/` outside `Duo/`, and not `ContentView`._

## How it hooks in

`TwoPaneHooks.installed` returns `TwoPaneHooks.duo` (`Duo/TwoPaneHooks+Duo.swift`), which fills every seam:

| Hook | Duo code | What it does |
|---|---|---|
| `division` | `DuoHooks.division` | Reads `proxy.reservedRegions(kind: .division)` (iOS 27.1), the active region's frame plus margins. nil below 27.1 and on every device with no fold. |
| `arrangement` | `DuoHooks.arrangement` | `ArrangementView { house } secondary: { work }`, `.split.axes(.horizontal)`, ratio 0.5. Used only when the division is the system's (`TwoPaneLayout` checks). |
| `heroOverlay` | `DuoDoorOverlay` → `DuoFrontDoor` | The door leaf, hall and step light over the house, on a fold only and on `half` only (`DoorArt.doorRect`). |
| `workOverlay` | `DuoPaneLightOverlay` → `UnfoldLightOverlay` | The veil that wipes in from the fold: from the work pane's leading edge when open, its top edge when propped. |
| `root` | `DuoDoorRoot` | Owns the `UnfoldClock`, listens to the hinge (`.unfoldDoor`), shares the clock through `\.unfoldClock`. The overlays draw nothing without it. |

When the two-pane layout merges to a release branch, this branch merges after it. No other wiring is needed.

## Files (all in `Sources/Views/Adaptive/Duo/`)

| File | What it is | v8 / standard element |
|---|---|---|
| `FoldPosture.swift` | Pure. `FoldPosture.resolve(division:in:)`: `.flat`, `.open` (vertical fold), `.propped` (fold across). `workPaneFoldEdge`, `hostsDoor`. `HingeStatus`. Agrees with `PaneDivision.isVertical`. | v8 `DuoGeo.open`/`.propped`; §1.27 "The door" |
| `UnfoldDoor.swift` | Pure. The `duoUnfold` rules: `move(from:to:reduceMotion:current:)`, `touch`, `isStranded`; `UnfoldMove`; `DoorPose` (every layer as a function of t). | v8 `DuoDoorClock`, `duoEase`; §B.2 `duoDoor`, §B.3 incl. Reduce Motion |
| `UnfoldClock.swift` | The clock on a `CADisplayLink`; `.unfoldDoor(_:posture:)` = `onHingeChange` + touch-to-finish + the stranded-door guard. | must-prove 2, 3, 7, 9, 10 |
| `UnfoldLight.swift` | `UnfoldLight`, `UnfoldLightOverlay`: the posture-aware veil. | v8 `DuoInsideLight` |
| `DuoFrontDoor.swift` | The leaf, hall and step pool, reading `DoorPose`; fades in under Reduce Motion. Ported from J's `FrontDoor`. | v8 `DuoFrontDoor`, DU14 |
| `DoorArt+Duo.swift` | The door's art constants (hall, lamp, veil, door rect, facade slope), ported from J's `DoorArt`. Sanctioned in `standard_lint.py` like the shared `DoorArt` lines. | §1.27 asset contract |
| `DuoDoorRoot.swift` | `DuoDoorRoot`, `DuoHooks` (division, arrangement, posture), the overlays and `\.unfoldClock`. | v8 "onHingeChange starts the door" |
| `TwoPaneHooks+Duo.swift` | The installed hooks. | |
| `DuoDoorCapture.swift` | DEBUG. `-LHDuoDoorRender` renders the real shell at Duo sizes with the clock held at each instant. | v8 `DuoV2Snapshotter` motion mode |

Tests: `Tests/FoldPostureTests.swift` (10), `Tests/UnfoldDoorTests.swift` (19), `Tests/UnfoldClockTests.swift` (13).

## Differences from package J's door, on purpose

| # | J | Here | Why |
|---|---|---|---|
| 1 | The hinge listener was on only while the window was two-pane. | On wherever a hinge exists, plus a guard that settles a door left shut on a fold after 1 s. | The open event can land while the window is still compact; dropped, the work pane would stay veiled (must-prove 3). Observed in J's code; the device order is still unproven. |
| 2 | The veil always wiped leading to trailing. | From the fold's edge: leading when open, top when propped. | Propped, the work pane is below the fold. |
| 5 | A touch was a tap (fires on lift; a scroll never finished the door). | A touch-down press finishes it; the gesture is masked to `.subviews` at rest so every other control keeps its taps. | §B.3 "a touch sets t = 1". |
| 6 | No re-check after a fold that stayed on the inner display, or on returning from the background. | The stranded check re-runs whenever the door comes to rest short of open and when the scene becomes active; folded onto the outer display with the hinge closed, the door rests shut so the next unfold plays. | Fresh-context code review, 2026-11-01. |
| 3 | Reduce Motion set t = 1 at once. | A 0.20 s crossfade, no leaf turn, no wipe. | §B.3's Reduce Motion column. |
| 4 | A `Task` slept 16 ms per step; the layout and house pane observed the clock. | `CADisplayLink`; the root holds the clock in `@State` (not observed); only the leaf, the veil and the hinge modifier follow it. | Must-prove 10 (no hitches); fewer views redraw per frame. Hitch cost is inferred until Instruments on a device. |

## Requests

| # | To | Request |
|---|---|---|
| R1 | Art lane | A separate leaf layer for `craft_complete`. Today `doorRect(.complete)` is nil (the porch post stands in front of the leaf), so `complete` plays the pane light only. §B.3 says the leaf turns on `half` and `complete`. |
| R2 | iPad lane | None needed for phase 1: the hooks were sufficient. `scripts/qa/standard_lint.py` gained five `SANCTIONED` lines for `DoorArt+Duo.swift`, the same pattern as the shared `DoorArt` lines. |

## Still unproven (needs a Duo on iOS 27.1)

§1.27 must-prove 1–11, 14, 15 are unchanged. Simulators cannot unfold; every Duo frame here is an off-screen `drawHierarchy` render with a stand-in 24pt division.
