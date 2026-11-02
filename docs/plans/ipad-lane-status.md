# iPad lane status (paused 2026-11-01 20:45 PST)

Branch `feat/ipad-adaptive` (worktree `/Users/brian/tmp/worktrees/lh-ipad`), based on int/2.3 at f7018fc. Paused by Brian so the Mac is free for the 2.3 release. Nothing is booted, claimed or running for this lane.

Law: DESIGN-STANDARD §1.27 on int/2.3 (two-pane: house left, workstation right; no sidebar, no `NavigationSplitView`, no `Table`/`.inspector`). The 2026-10-23 spec (bands A/B/C, sidebar) is history only. API for the Duo lane: `docs/plans/two-pane-api.md`.

## Done (committed and pushed; all checks self-run, no gate yet)

| Commit | What |
|---|---|
| 635b1f5 | Package J (origin/v2/j 575cfa0) ported: `Sources/Views/Adaptive/*` (LayoutMode, TwoPaneLayout, WorkPane with the one compact-trait bridge, HousePane + shelf, TodayWorkPane, OnTheRecordCard, InteriorWall, DoorArt light constants, AdaptiveDebug renderer), `Adaptive.xcstrings`, assets, `two_pane_check.py`. Root wired in `ContentView`: `TwoPaneLayout { mainContent }`; Log time through `.paneAwareLogTime` (a `.large` sheet in compact, the card in the pane, using LogTimeSheet's own `.pane` placement and `rentalShown`); Today root is `AdaptiveToday`. Door, hinge, `reservedRegions` and `ArrangementView` code removed and replaced by `TwoPaneHooks` seams (Duo lane). Bridge on iPadOS 26+ only (`WorkPane.bridgeProven`); iPadOS 18-25 gets the system iPad bar (§1.27 fallback; 18 is UNPROVEN, Brian declined the runtime download). `standard_lint.py` gained `SANCTIONED` exact-line exceptions the standard names (DoorArt hex, the off-screen measure, in-pane back links). |
| 73e466e | `docs/plans/two-pane-api.md`; `Adaptive/Duo/TwoPaneHooks+Duo.swift` stub (the Duo lane's one file). |
| 00aeace | 2.3 kept inside the panes. Today pane: identity notice + timer above To confirm; Learn, This season (care), Your record under it; arrival on the rental just changed (package E); milestones and the Day-1 reveal. Rentals in a pane: the shelf's rental as the page body (hero hidden, it is in the house pane); All rentals = the list, a row picks on the shelf. Inbox confirm pushes in the pane (`PaneDetail`, back link "To confirm"). New unit tests in `Tests/AdaptiveLayoutTests.swift` (Split View tiles, Slide Over, rotation, Stage Manager sizes, the 799/800 boundary from both sides, degenerate sizes, bridge OS gate, empty hooks). |
| 68155ad | `IPadColumnUITests` skips two-pane windows (IP1-IP4 are compact band B only now). New `UITests/AdaptiveScreensCaptureUITests.swift` (every top-level screen x light/dark x L/XXL; frames named by the mode the app chose). |
| bebec89 | ⌘⇧N opens Log time on the timer (string `shell.key.timer`, table Adaptive). |
| 6812752 | `UITests/AdaptiveWindowUITests.swift`: drags the window grip to 900/800/799/700/799/800/375/1000, asserts the settled mode and that the tab survives (must-prove 12 resize, 16). |

Self-checks run: `xcodebuild build-for-testing` green on iOS Simulator SDK 27.2 (log `/Users/brian/tmp/lh-ipad-lane/bft7.log`); `python3 scripts/qa/standard_lint.py` → 0 new; §1.27 greps: 0 `NavigationSplitView`, `.inspector(`, `TabSection(`, `sidebarAdaptable`, `tabViewSidebarHeader`, `.environment(\.horizontalSizeClass`; one `traitOverrides.horizontalSizeClass`. Two pre-existing `userInterfaceIdiom` uses in `Sources/Services/Capture/Notifications/` (not layout; from int/2.3) are left alone.

## Left (in order)

1. **Must-prove 12 on iPadOS 27 and 26** (sims; the iPads too if released): `AdaptiveUITests/testRightPaneBarTwoPane`, plus `AdaptiveWindowUITests`.
2. **Unit suite** on an iPad and an iPhone sim (StoreKit tests need iOS 27, see lessons file).
3. **Full UI suite on iPhone** (no regression) and **on a two-pane iPad**. Expect Today UI tests that look for phone ids (`today.hero`, the rental chip) to fail on two-pane: give each a `pane.house` skip or a pane assertion; never weaken an assertion.
4. **Captures**: `AdaptiveScreensCaptureUITests` on iPad (A16) 27.0 portrait + landscape (two-pane), iPad mini (A17 Pro) portrait (compact band B), and iPhone 17 Pro on both this branch and the base worktree, then pixel-diff the iPhone pairs (proves no iPhone change). Also `AdaptiveUITests/testCapturePortrait|Landscape` (gate frames incl. AX3). Then `python3 scripts/qa/frame_check.py density <frames>` and `scripts/adaptive/two_pane_check.py` numbers into the hand-off.
5. **Gates**: a fresh `visual-gate` (opus) on the frames (first review of a new surface: two independent looks), then a fresh `verifier` (opus). Fix, re-gate, push. Do not merge.
6. Not built (open, report them): §1.27 "Rules kept" items with no code anywhere yet: drop destinations, per-scene `SceneState` + draft restore + "Open in New Window", widgets `systemExtraLarge`, ⌘F, Space/⌫ on a focused row, the R12 window-controls inset check in a compact iPad window.

## Exact next commands

Wait for the flag first: `test -f /Users/brian/AgentScratch/landlordhours/2026-11-01/release-lanes-done` (or the coordinator's go). Check `memory_pressure | tail -1` and `/Users/brian/.local/share/simboot/simboot.sh status`. One sim at a time; release it when its run ends.

```bash
cd /Users/brian/tmp/worktrees/lh-ipad && git pull --ff-only
xcodegen generate
xcodebuild build-for-testing -scheme LandlordHours -destination 'generic/platform=iOS Simulator' -derivedDataPath /Users/brian/tmp/DerivedData/landlordhours-ipad
/Users/brian/.local/share/simboot/simboot.sh boot lh-ipad-a16-27 com.apple.CoreSimulator.SimDeviceType.iPad-A16 com.apple.CoreSimulator.SimRuntime.iOS-27-0 --owner lh-ipad-lane
```

Then, with the UDID simboot prints in place of `UDID` below:

```bash
xcodebuild test-without-building -scheme LandlordHours -derivedDataPath /Users/brian/tmp/DerivedData/landlordhours-ipad -destination 'id=UDID' -only-testing:LandlordHoursUITests/AdaptiveUITests/testRightPaneBarTwoPane -only-testing:LandlordHoursUITests/AdaptiveWindowUITests -resultBundlePath /Users/brian/tmp/lh-ipad-lane/mp12-ipados27.xcresult
xcrun xcresulttool export attachments --path /Users/brian/tmp/lh-ipad-lane/mp12-ipados27.xcresult --output-path /Users/brian/tmp/lh-ipad-lane/mp12-ipados27-att
/Users/brian/.local/share/simboot/simboot.sh release UDID --owner lh-ipad-lane
```

Repeat with `com.apple.CoreSimulator.SimRuntime.iOS-26-5` for iPadOS 26. Check the UI-test target name with `xcodebuild -list` before the first run; for captures, set `TEST_RUNNER_LH_ORIENT=landscape` in the environment of the landscape run.

## Gotchas

- The iPhone base for the no-change diff is a detached worktree at f7018fc: `/Users/brian/tmp/worktrees/lh-ipad-base`, with `UITests/AdaptiveScreensCaptureUITests.swift` copied in (untracked) and its project regenerated; DerivedData `/Users/brian/tmp/DerivedData/landlordhours-ipad-base`. It is this lane's scratch: remove it with `git worktree remove --force` when the diff is done.
- The work pane's `UIHostingController` does not inherit SwiftUI environment: anything the shell's screens read must be passed in `WorkPaneEnvironment` (`TwoPaneLayout.swift` / `WorkPane.swift`).
- Package J's notes: iPadOS 26.5 draws the Inbox badge but exposes nothing to accessibility (recorded, not asserted, on 26); the shelf scrolls by frame, not `isHittable`.
- `IPadColumnUITests` only runs on compact windows now (iPad mini portrait).
- The 2.2 interim's floating top bar on compact iPad windows is gone: compact iPad windows also go through the bridge, so the bar is the bottom bar in every mode (§1.27), on iPadOS 26+.
- Never use `mcp__Claude_Code_iOS_Simulator__control`; simctl + XCUITest only. Never BLV-Phone, Dina's iPhone or the iPad Air. Claim the iPad 10th gen / mini 5 in `/Users/brian/.local/share/device-claims/claims.tsv` before use.
