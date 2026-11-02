# Duo lane status (paused 2026-11-01 for the 2.3 release)

Branch `feat/duo-door`, head 4643fc2 before this note, pushed. Worktree `/Users/brian/tmp/worktrees/lh-duo`. No simulator was booted by this lane; no processes are left running.

## Done (committed and pushed)

- All Duo code is in `Sources/Views/Adaptive/Duo/` and plugs in through `TwoPaneHooks` only (`TwoPaneHooks+Duo.swift`): `division` (the `reservedRegions` reader), `arrangement` (`ArrangementView`), `heroOverlay` (the door leaf, `DuoFrontDoor`), `workOverlay` (the posture-aware pane light, `UnfoldLight`), `root` (`DuoDoorRoot`: the hinge listener and the door clock, shared by `\.unfoldClock`). Nothing else in `Views/Adaptive/` or `ContentView` is edited.
- Pure, tested logic: `FoldPosture` (flat / open / propped from the division), `UnfoldDoor` (the `duoUnfold` rules: hinge-only, 0.80 / 0.50 s, Reduce Motion 0.20 s crossfade, touch finishes, stranded door settles lit, folded door rests shut), `DoorPose` (each layer as a function of t, §B.3 windows).
- Tests: `Tests/FoldPostureTests.swift` (10), `Tests/UnfoldDoorTests.swift` (19), `Tests/UnfoldClockTests.swift` (13). The 29 pure tests in the first two files pass on macOS through `~/AgentScratch/landlordhours/2026-11-01/duo-door/harness/run.sh /Users/brian/tmp/worktrees/lh-duo` (observed, 29/29). The XCTest run on a simulator has NOT been done.
- `xcodebuild build-for-testing` succeeds (observed, merged with feat/ipad-adaptive at 6812752). `python3 scripts/qa/standard_lint.py`: 0 new violations (observed). `standard_lint.py` gained five `SANCTIONED` lines for the door's art hexes in `Duo/DoorArt+Duo.swift`.
- A fresh-context code review (opus code-reviewer) found no blockers; its three MAJOR findings were fixed in 4643fc2 (stranded check re-runs at rest and on scene active; the root holds the clock in `@State`; `complete` has no door yet, recorded as an art request). `docs/plans/duo-integration.md` lists every difference from package J's door and the requests.

## Left (acceptance criteria not yet met)

1. Run the unit suite on one simulator: the three new test classes plus the existing suite (no new failures).
2. Captures: `-LHAdaptiveRender duo` (rest frames, the iPad lane's renderer) and `-LHDuoDoorRender` (door instants, this lane) on one sim, then side-by-side sheets against v8 (`~/AgentScratch/landlordhours/2026-10-24/duo-concept-v8/frames/`) with `~/AgentScratch/landlordhours/2026-11-01/duo-door/tools/sbs.py`.
3. A fresh `visual-gate` (opus) on the sheets and strips; apply fixes and re-gate.
4. A fresh `verifier` (opus) on the branch.
5. Push; do not merge.

## Exact next steps (after `~/AgentScratch/landlordhours/2026-11-01/release-lanes-done` exists, or Brian frees the Mac)

```bash
cd /Users/brian/tmp/worktrees/lh-duo
git fetch origin && git merge --no-edit origin/feat/ipad-adaptive    # then: xcodegen generate; amend the merge message with the Co-Authored-By line
memory_pressure | tail -1
/Users/brian/.local/share/simboot/simboot.sh boot lh-duo-door "iPhone Duo" com.apple.CoreSimulator.SimRuntime.iOS-27-1 --owner duo-door
```

Then, with the UDID simboot prints (record it; release it when done with `simboot.sh release <udid> --owner duo-door` and delete it):

```bash
xcodebuild -project LandlordHours.xcodeproj -scheme LandlordHours -derivedDataPath /Users/brian/tmp/DerivedData/landlordhours-duo-door \
  -destination "id=<udid>" test-without-building -only-testing:LandlordHoursTests
xcrun simctl install <udid> /Users/brian/tmp/DerivedData/landlordhours-duo-door/Build/Products/Debug-iphonesimulator/LandlordHours.app
xcrun simctl launch <udid> com.openclaw.landlordhours -LHMockScenario emptyMainTabs -LHSeedSuggestions inbox -LHCraftSeed craft \
  -LHCraftWindows lit -LHDuoDoorRender -LHAdaptiveRender duo -AppleLanguages "(en)" -AppleLocale en_US
# wait for Documents/adaptive/DONE and Documents/duodoor/DONE in the app's data container, copy both out, then:
python3 ~/AgentScratch/landlordhours/2026-11-01/duo-door/tools/sbs.py <adaptive-dir> <duodoor-dir> ~/AgentScratch/landlordhours/2026-11-01/duo-door/sheets
```

(The `<udid>` and the two directories are only known after the boot and the copy; fill them in then.) Both renderers can run in one launch, but if they fight over `AdaptiveSnapshotter.duoShot`, run them in two launches.

## Dependency on feat/ipad-adaptive

- This branch is built on it (merged twice, last at 6812752; it has since moved to 84a1a6f). It needs `TwoPaneHooks`, `LayoutSplit`, `PaneDivision`, `TwoPaneHeroContext`, `HousePane`'s hero overlay call, `TwoPaneLayout`'s work overlay and root calls, `DoorArt.warmNight`, and the DEBUG `AdaptiveSnapshotter.duoShot` / `duoOpen` / `duoPropped` / `AdaptiveSnapshotSelection.args`.
- Merge order: feat/ipad-adaptive first, then feat/duo-door. If the hooks' signatures change, only `TwoPaneHooks+Duo.swift` and `DuoDoorRoot.swift` should need edits.

## Gotchas

- `.simultaneousGesture(g, including: .none)` disables every gesture below it, not just `g`; the door uses `.subviews` at rest. Package J's original had `.none`.
- `standard_lint` flags any `DragGesture` (custom-swipe) and any `Color(hex:)` outside token files; art hexes go in `SANCTIONED`, one exact line each.
- A `@StateObject` clock re-renders its owner on every tick; the root holds it in `@State` and only the leaf, the veil and the hinge modifier observe it.
- `restsShut` resets t to 0 only with the hinge known closed, so a cold launch already open stays lit (no light-up on appear).
- `craft_complete` has no door leaf (the porch post covers it): pane light only until the art lane renders the leaf separately (request R1 in duo-integration.md).
- The simulator cannot unfold: every Duo frame is an off-screen render with a stand-in 24pt division. §1.27 must-prove 1–11, 14, 15 still need a Duo on iOS 27.1.
- `/Volumes/Home` does not exist on this Mac; DerivedData lives in `~/tmp/DerivedData/landlordhours-duo-door`.
- zsh: `git show $B:path` applies a history modifier; quote it as `"${B}:path"`.
