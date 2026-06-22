# LandlordHours Design Improvement Backlog

Last updated: 2026-06-22
Design skill: `impeccable` 3.7.1
Latest scan: `/Users/brian/Projects/LandlordHours/docs/e2e-visual-runs/2026-06-21_22-48-07-impeccable-screen-scan/contact-sheet.jpg`

## Goal

Reach and maintain a 20 / 20 product UI standard across the full app. The bar is not novelty; it is a calm, premium, trustworthy iOS utility where the daily landlord workflow is obvious, fast, and visually coherent.

## Operating Loop

For each milestone:

1. Audit the current screenshots and code for the target surface.
2. Improve the smallest coherent slice that can materially raise quality.
3. Build and run the app on the configured iPhone simulator.
4. Capture changed-screen screenshots with the e2e visual script.
5. Inspect the screenshot, fix visible issues, and repeat when needed.
6. Run static design scans from `docs/design-audit-playbook.md`.
7. Run the test suite before calling the milestone done.
8. Record evidence, remaining issues, and the next target here.

## Ranked Backlog

### P0 - Track Time

Status: Milestone 1 complete; timer/detail refinements remain open
Files: `Sources/Views/TimeLogView.swift`
Evidence:
- `08-occasional-track.png`
- `13-frequent-track-pro.png`

Problems:
- Core daily flow still reads like the older app compared with Home, Reports, Settings, and Paywall.
- The first viewport is dominated by an oversized blank note field and repeated AI copy.
- Manual details feel like a secondary accordion instead of a confident review step.
- Timer mode shares the same old card language and needs stronger hierarchy after Log mode is improved.

Acceptance criteria:
- First viewport communicates one clear action: describe work, review detected evidence, then log.
- AI assistance feels integrated and premium, with no duplicate instructional copy.
- Manual fields feel like an audit-ready evidence review, not a hidden fallback.
- CTA and disabled states remain obvious and truthful.
- Light mode, dark mode, and large Dynamic Type do not clip primary controls.

Completed in milestone 1:
- Reframed the Log card as a focused evidence composer with a compact header.
- Removed duplicate empty-state AI instruction.
- Added an evidence draft preview for property, category, and hours before the manual review step.
- Tightened the note field height so the first viewport has a clearer path forward.
- Preserved the existing AI auto-fill, manual details, attachment, timer, and save behavior.

Verification:
- Build/run: passed with no warnings via XcodeBuildMCP.
- Visual evidence:
  - `/Users/brian/Projects/LandlordHours/docs/e2e-visual-runs/2026-06-21_23-01-07-track-impeccable-milestone/08-occasional-track.png`
  - `/Users/brian/Projects/LandlordHours/docs/e2e-visual-runs/2026-06-21_23-01-07-track-impeccable-milestone/13-frequent-track-pro.png`
- Static design scans: no new Track-specific critical hits.
- Tests: 67 passed, 0 failed, 0 skipped.

Remaining Track follow-up:
- Inspect expanded manual details at large Dynamic Type.
- Give Timer mode the same level of composition after Properties is started or if timer usage becomes the next priority.

### P1 - Properties

Status: Milestone 2 complete; dark mode and large Dynamic Type validation remain open
Files: `Sources/Views/PropertiesView.swift`
Evidence:
- `07-occasional-properties.png`
- `12-frequent-properties-pro.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/add-property.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/property-detail.png`

Problems:
- Property cards feel utilitarian and list-like rather than like a premium rental portfolio.
- Add-property entry point is visually heavy and generic.
- Multi-property state needs better hierarchy for progress, type, and next action.

Acceptance criteria:
- Each property card communicates identity, tax-relevant status, and next action at a glance.
- Empty and multi-property states share the same component quality as Home and Reports.
- Add-property remains discoverable without overpowering the list.

Completed in milestone 1:
- Added a portfolio evidence summary with property count, LTR/STR split, and total logged hours.
- Reworked property cards around identity, address, tax-relevant evidence label, annual progress, total hours, and log count.
- Replaced always-visible destructive trash buttons with a quieter overflow action menu.
- Added a more useful empty-state setup card and a clearer add-property row.
- Adopted the iOS 26+/27 native glass effect for the portfolio summary with a non-glass fallback for earlier iOS versions.

Completed in milestone 2:
- Reframed Add Property as creating an evidence container, with live readiness pills for name, address, and rental type.
- Reworked the Add Property type selector into an evidence-profile section instead of a generic form control.
- Reworked Property Detail around evidence first, then editable property identity and location.
- Removed the duplicate Property Detail edit sheet path so there is one clear editing model.
- Consolidated duplicated property statistics into the evidence overview.
- Added DEBUG-only visual QA launch flags for deterministic Properties screenshots:
  - `-LHOpenAddProperty`
  - `-LHOpenFirstPropertyDetail`
- Corrected XcodeBuildMCP's active profile to the dedicated LandlordHours iOS 27 simulator.

Verification:
- Build: passed through the dedicated Xcode 27 lane.
- Visual evidence:
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-check-20260622030528/occasional-properties.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-check-20260622030528/frequent-properties.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/add-property.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/property-detail.png`
- Static design scans: no new Properties-specific critical hits.

Remaining Properties follow-up:
- Validate large Dynamic Type and dark mode on the redesigned cards.
- First-time main-tab capture is still partially blocked by onboarding/splash state; resolve under the First-Time / Onboarding Capture backlog item.

### P1 - First-Time / Onboarding Capture

Status: Milestone 1 complete; onboarding substep capture remains open
Files: `Sources/Views/OnboardingView.swift`, `Sources/ViewModels/AppViewModel.swift`, `Sources/Views/SettingsView.swift`, visual capture scripts
Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/01-onboarding-goal.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/02-empty-home.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/03-empty-properties.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/04-empty-track.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/05-empty-reports.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/06-empty-settings.png`

Problems:
- Current first-time visual matrix is blocked by the same onboarding goal screen across tab labels.
- This prevents a truthful first-time audit of main-tab states.

Acceptance criteria:
- Visual capture can distinguish onboarding screens from first-time main-tab states.
- Onboarding feels helpful and premium without over-explaining tax rules.

Completed in milestone 1:
- Added a DEBUG-only `emptyMainTabs` scenario so signed-in empty app states can be captured separately from true onboarding.
- Updated the e2e visual capture script to capture one onboarding screen, five empty main-tab states, occasional user states, frequent Pro states, and non-admin Settings.
- Fixed Settings debug scenario styling for the new empty-main-tabs scenario.
- Corrected the generated review checklist so non-admin debug visibility is checked against screenshot 17.

Verification:
- Build: `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Visual capture: `SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh` passed with 17 screenshots and `review.md`.
- Screenshot inspection: confirmed `01-onboarding-goal.png` is true onboarding, while `02-empty-home.png` through `06-empty-settings.png` are signed-in main app tabs with no properties or entries.

Remaining First-Time follow-up:
- Add deterministic launch hooks or UI automation for deeper onboarding substeps beyond the first goal screen.
- Run the full first-time activation flow once semantic UI automation is stable on Xcode 27 beta.

### P2 - Reports Bottom Inset

Status: Completed
Files: `Sources/Views/ReportsView.swift`
Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-48-03/10-occasional-reports.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-48-03/15-frequent-reports-pro.png`

Problems:
- Reports is visually strong, but lower content can compete with the floating tab bar.

Acceptance criteria:
- Bottom content clears the tab bar in every goal mode.
- No regression to the reports ring, goal switcher, or export entry points.

Completed:
- Added Reports-local bottom scroll clearance so the lower breakdown content has more room above the floating tab bar without changing other tabs.
- Kept the existing Reports hierarchy, ring, goal switcher, export lock/share affordance, and goal-specific palettes intact.

Verification:
- Build: `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Visual capture: `SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh` passed with 17 screenshots.
- Screenshot inspection: `10-occasional-reports.png` and `15-frequent-reports-pro.png` show no regression to the ring, goal pills, export affordance, or tab bar.
- Unit tests: `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh unit` passed, 65 / 65.
- Static design scans: reviewed, no new Reports-specific critical hits.

### P2 - Home Activation / Learning Entry

Status: Completed; dark mode and large Dynamic Type validation remain open
Files: `Sources/Views/DashboardView.swift`
Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_04-18-40/02-empty-home.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_04-18-40/07-occasional-home.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_04-18-40/12-frequent-home-pro.png`

Problems:
- Learning was reachable but felt like a quiet card below the primary Home work.
- Empty Home did not give users a meaningful setup path that connected property setup, first log, learning, and reports.
- A first vertical checklist attempt was too tall and collided with the floating tab bar in the initial empty-state viewport.

References:
- Airbnb profile completion flow: activation checklist pattern for setup progress.
- Revolut home dashboard: current state first, next actions second, supporting education lower.
- Apple Fitness summary: modular status/action cards that keep progress glanceable.

Completed:
- Added an empty-state Home activation module under the primary Home actions.
- Connected four meaningful entry points: Property, First hour, Learn, and Report.
- Preserved the existing `Learn what counts` card for populated Home states.
- Kept completion state focused on property setup and first logged hour, shown as `0/2`, `1/2`, or `2/2`.
- Reworked the first pass from a tall list into a compact 2x2 tile grid after screenshot review showed tab-bar overlap.

Verification:
- Build: `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Visual capture: `SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh` passed, 17 screenshots captured.
- Screenshot inspection: empty Home shows the activation grid without tab-bar collision; occasional and frequent Home keep the learning shortcut.
- Unit tests: `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh unit` passed, 65 / 65.
- Static design scans: reviewed, no new Home-specific critical hits.

Remaining Home follow-up:
- Validate the activation grid in dark mode and larger Dynamic Type.
- Consider semantic UI tests for the four activation entry points once Xcode 27 UI automation is stable.

### P2 - Settings / Home Maintenance

Status: Watch
Files: `Sources/Views/SettingsView.swift`, `Sources/Views/DashboardView.swift`

Notes:
- Recent Settings, Paywall, navigation, and Home Learning changes are directionally strong.
- Future work should be incremental: bottom inset, copy tightening, accessibility, and dark-mode checks.

## Milestone Log

### 2026-06-21 - Full App Impeccable Screen Scan

Outcome:
- Ranked Track as the next highest-value redesign target.
- Confirmed Properties as the next major surface after Track.
- Confirmed Reports/Home/Settings/Paywall are currently lower-risk.

Evidence:
- `/Users/brian/Projects/LandlordHours/docs/e2e-visual-runs/2026-06-21_22-48-07-impeccable-screen-scan/contact-sheet.jpg`

Next:
- Execute P0 Track Time redesign, then run the visual/test loop.

### 2026-06-21 - Track Time Milestone 1

Outcome:
- Improved the default Log mode first viewport from a form-heavy composition into an evidence-first composer.
- Preserved existing behavior while making the next action clearer.
- Verified both occasional and frequent seeded states.

Evidence:
- `/Users/brian/Projects/LandlordHours/docs/e2e-visual-runs/2026-06-21_23-01-07-track-impeccable-milestone/08-occasional-track.png`
- `/Users/brian/Projects/LandlordHours/docs/e2e-visual-runs/2026-06-21_23-01-07-track-impeccable-milestone/13-frequent-track-pro.png`

Verification:
- `build_run_sim`: passed, no warnings.
- `capture_iphone_e2e_visuals.sh`: passed, 16 screenshots captured.
- Static design scans: reviewed, no new Track-specific critical hits.
- `test_sim(progress: false)`: passed, 67 / 67.

Next:
- Move to P1 Properties list and add-property entry point.

### 2026-06-22 - Properties Milestone 1

Outcome:
- Improved the Properties tab from a utilitarian list into a portfolio evidence surface.
- Added tax-relevant progress directly to each property card.
- Reduced destructive-action noise by moving delete into an overflow menu.
- Used native iOS 26+/27 Liquid Glass treatment for the summary card while preserving fallback behavior for iOS 17+.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-check-20260622030528/occasional-properties.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-check-20260622030528/frequent-properties.png`

Verification:
- `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Static design scans: reviewed, no new Properties-specific critical hits.

Next:
- Continue with Add Property and Property Detail refinements, then resolve first-time capture so empty/main-tab states can be audited truthfully.

### 2026-06-22 - Properties Milestone 2

Outcome:
- Improved Add Property and Property Detail so they now match the portfolio-evidence direction from the redesigned Properties tab.
- Added a clearer evidence-container summary to Add Property and a tax-progress evidence overview to Property Detail.
- Removed the duplicate detail edit sheet and kept inline editing as the single interaction model.
- Added DEBUG-only launch flags for repeatable visual QA of Add Property and Property Detail.
- Fixed the XcodeBuildMCP active defaults profile so automation uses `LandlordHours iPhone iOS 27` instead of a shared simulator.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/add-property.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/property-detail.png`

Verification:
- `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `mcp__xcodebuildmcp.session_set_defaults(... persist: true)`: active profile now points at `C8B22181-D398-477F-91D3-ED67F1B8851C`.
- Static design scans: reviewed, no new Properties-specific critical hits.

Notes:
- XcodeBuildMCP accessibility snapshots currently fail against the Xcode 27 beta because the tool looks for a removed `SimulatorKit.framework` path. Screenshots still work via `simctl`.
- XcodeBuildMCP runtime logs are still being written under `/Users/brian/Library/Developer/XcodeBuildMCP/...`; DerivedData and result bundles are on SSD as expected.

Next:
- Validate Properties in dark mode and large Dynamic Type.
- Resolve first-time main-tab visual capture so onboarding and empty tab states can be audited separately.

### 2026-06-22 - First-Time / Onboarding Capture Milestone 1

Outcome:
- Separated true onboarding capture from signed-in empty main-tab capture.
- Added a DEBUG-only `emptyMainTabs` scenario for visual QA without triggering onboarding or guided setup overlays.
- Updated the e2e visual matrix to cover onboarding, empty tabs, occasional users, frequent Pro users, and non-admin Settings in one run.
- Fixed the generated non-admin debug-control checklist reference.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/01-onboarding-goal.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/02-empty-home.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/03-empty-properties.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/04-empty-track.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/05-empty-reports.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/06-empty-settings.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/review.md`

Verification:
- `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh`: passed, 17 screenshots captured.
- Manual screenshot inspection: first onboarding and five empty main-tab states are correctly separated.

Next:
- Add deterministic capture for deeper onboarding steps.
- Resume P2 Reports bottom inset or dark mode and large Dynamic Type validation for Properties.

### 2026-06-22 - Reports Bottom Inset

Outcome:
- Increased Reports-only bottom scroll clearance so lower breakdown rows have more breathing room around the floating tab bar.
- Preserved the existing Reports hero, goal switcher, progress ring, pace indicator, stat chips, and export affordance.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-48-03/10-occasional-reports.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-48-03/15-frequent-reports-pro.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-48-03/review.md`

Verification:
- `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh`: passed, 17 screenshots captured.
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 65 / 65.
- Static design scans: reviewed, no new Reports-specific critical hits.

Next:
- Validate Properties in dark mode and large Dynamic Type.

### 2026-06-22 - Home Activation / Learning Entry

Outcome:
- Added a more meaningful empty-state Home entry point inspired by best-in-class activation and home-dashboard patterns.
- Moved setup/learning/report guidance into a compact mid-page module under the primary Home actions.
- Preserved the existing lower `Learn what counts` card for users who already have property and time-entry data.
- Iterated after screenshot review: the first checklist version was too tall, so it became a 2x2 action grid and moved above the annual target card for the empty state.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_04-18-40/02-empty-home.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_04-18-40/07-occasional-home.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_04-18-40/12-frequent-home-pro.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_04-18-40/review.md`

Verification:
- `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh`: passed, 17 screenshots captured.
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 65 / 65.
- Static design scans: reviewed, no new Home-specific critical hits.

Next:
- Continue with dark mode and large Dynamic Type checks across Properties and Home.
- Consider adding UI automation for activation-card actions when Xcode 27 beta accessibility tooling stabilizes.

### 2026-06-22 - Dark Mode / Dynamic Type / Track Robustness

Outcome:
- Added deterministic visual-QA controls for appearance and Dynamic Type in `ci_scripts/capture_iphone_e2e_visuals.sh`.
- Added a DEBUG launch override for `-LHColorScheme light|dark` so screenshots are not dependent on simulator appearance drift.
- Improved Track details for accessibility-large text: quick summary chips scroll instead of compressing, evidence draft uses a stable two-row layout, and Date/Person controls stack vertically instead of competing for width.
- Replaced remaining Track hardcoded light surfaces with adaptive colors for dark mode.
- Fixed local time-entry parsing for partial property-name phrases, e.g. "Oak Street leak" now resolves to "Oak Street Duplex" and keeps "1 hour" as 1.0h.
- Updated the UI typing regression to assert the redesigned "Evidence draft" state.

Mobbin reference check:
- Settings/account organization and premium module: [Opal settings screen](https://mobbin.com/screens/5097c3fe-ae25-40af-bd42-c5bba3d92215), plus adjacent premium-account patterns from [Tinder](https://mobbin.com/screens/3611a9af-6466-44eb-9917-aaf8c95b8be4) and [Manus](https://mobbin.com/screens/fc3ef8e5-b4e4-4504-8f6a-00fcd97db718).
- Time-entry form structure: [Toggl Track time entry](https://mobbin.com/screens/0ddd6c94-6458-4b1a-807c-a36adf93eab1) and [Jobber work-entry pattern](https://mobbin.com/screens/c705b35b-93d8-4aa1-a37f-2aa174ff6003).

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_roadmap-dark-a11y-final2/02-empty-home.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_roadmap-dark-a11y-final2/14-frequent-track-pro.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_roadmap-dark-a11y-final2/15-frequent-reports-pro.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_roadmap-dark-a11y-final2/16-frequent-settings-pro.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_roadmap-dark-a11y-final2/review.md`

Verification:
- `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, confirmed from xcresult as 66 / 66.
- Direct UI run with Xcode 27 beta: emitted pass summary, 5 / 5 UI tests passed. Xcode 27 beta kept the shell process attached after the pass summary, so the process was stopped manually after the success output was written to `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs/direct-ui-test-202606220455.log`.
- `APPEARANCE=dark CONTENT_SIZE=accessibility-large SETTLE_SECONDS=5 OUT_DIR=/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_roadmap-dark-a11y-final2 ./ci_scripts/capture_iphone_e2e_visuals.sh`: passed, 17 screenshots captured.

Notes:
- Xcode 27 beta still logs an Apple simulator accessibility warning about duplicate WebCore/WebKit accessibility classes during UI tests. It did not fail the tests.
- The Track placeholder example text is not parsed until the user actually types; parser behavior is covered by unit test.

Next:
- Add deterministic capture for deeper onboarding steps.
- Add UI automation for Home activation-card actions.
- Continue reducing remaining static-scan cleanup items after the current branch is reviewed.
