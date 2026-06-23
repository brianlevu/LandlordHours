# LandlordHours Design Improvement Backlog

Last updated: 2026-06-23 00:41 America/Los_Angeles
Design skill: `impeccable` 3.7.1
Latest scan: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/full-matrix-light-current-20260622193508/contact-sheet.jpg`

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

### P0 - Release Readiness / Xcode 27 Ship Gate

Status: Automated build, test, device build, archive, and export gates passed; manual system-surface QA remains open
Files: `Sources/App/PrivacyInfo.xcprivacy`, `UITests/LandlordHoursUITests.swift`, `fastlane/Fastfile`, `LandlordHours.xcodeproj/project.pbxproj`

Outcome:
- Added the required app privacy manifest and packaged it into the app target.
- Declared UserDefaults as the required accessed API category with reason `CA92.1`.
- Hardened UI-test launch behavior by terminating stale app processes before relaunch.
- Updated the first-time activation UI test to match the current Track flow: resolved parsed drafts can log directly; incomplete drafts still expose review/evidence.
- Verified the widget extension, Live Activity support, App Intents metadata, App Group entitlement, and privacy manifest are present in Xcode 27 builds.
- Verified the app builds on the paired iOS 27 physical device.
- Verified Release archive creation to the SSD-backed archive lane.
- Verified an App Store Connect export dry run from the archive without uploading or submitting anything.
- Moved Fastlane build output off shared `/tmp` and into the LandlordHours SSD-backed Xcode 27 lane.

Evidence:
- Build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622214920.xcresult`
- Unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622214112.xcresult`
- UI result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-full-patched-20260622214920.xcresult`
- Device build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-20260622215713.xcresult`
- Release archive: `/Volumes/Home/XcodeStorage/Archives/LandlordHours-20260622215945.xcarchive`
- App Store Connect export: `/Volumes/Home/XcodeStorage/Archives/LandlordHours-20260622215945-export/LandlordHours.ipa`
- Export log: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs/lane-export-app-store-connect-20260622220323.log`

Verification:
- `LANE_TIMEOUT_SECONDS=900 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `LANE_TIMEOUT_SECONDS=900 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 82 / 82.
- Full UI run on `LandlordHours iPhone 17 Pro Max iOS 27`: passed, 10 / 10.
- `plutil -lint Sources/App/PrivacyInfo.xcprivacy Sources/App/Info.plist Sources/Widget/Info.plist LandlordHours.entitlements LandlordHoursWidget.entitlements`: passed.
- Physical-device build against `BLV-Phone` on iOS 27: passed.
- `xcodebuild archive` with Release configuration and SSD archive path: passed.
- `xcodebuild -exportArchive` with `method=app-store-connect`: passed and produced a 22 MB IPA.

Remaining:
- Do not upload to TestFlight or submit for review without Brian's explicit approval.
- Real-device manual QA is still required for Siri phrases, Shortcuts donation/discovery, notification tap routing under Focus modes, widget glanceability, Lock Screen Live Activity, Dynamic Island states, and voice logging.
- TestFlight purchase behavior and App Store Connect product lookup still need a sandbox/TestFlight install path.
- The final UI result still contains two non-fatal SwiftUI `Invalid frame dimension (negative or non-finite)` runtime warnings. No visible regression was found in the passing UI suite, but it should remain on the polish/debug list.

### P0 - Full App Visual Matrix

Status: Milestone 1 complete; real-device and verified Dynamic Type QA remain open
Files: `ci_scripts/capture_iphone_e2e_visuals.sh`, `Sources/Views/TimeLogView.swift`

Completed in milestone 1:
- Ran the full 21-screen iPhone 17 Pro Max iOS 27 light matrix across onboarding, empty tabs, occasional user, frequent Pro user, and non-admin settings states.
- Ran the full 21-screen dark matrix and generated a contact sheet for contrast/hierarchy review.
- Patched `ci_scripts/capture_iphone_e2e_visuals.sh` so Simulator screenshots write to `/tmp` first, then copy into the SSD-backed lane folder. This avoids `simctl io screenshot` permission failures against the external-volume symlink.
- Fixed the Track empty-no-property state. It no longer centers a small message in a mostly blank screen; it now uses the same task-first hierarchy as Home/Properties with a focused setup card, direct Add Property action, and a short evidence checklist.
- Re-ran the current light matrix after the Track fix so the primary evidence reflects the latest UI.
- Ran static design scans from `docs/design-audit-playbook.md`; remaining hits are expected category customization colors, token definitions, and normal acronyms such as PDF/REPS/STR.

Evidence:
- Current light contact sheet: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/full-matrix-light-current-20260622193508/contact-sheet.jpg`
- Current light screenshots: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/full-matrix-light-current-20260622193508`
- Dark contact sheet: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/full-matrix-dark-20260622192604/contact-sheet.jpg`
- Dark screenshots: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/full-matrix-dark-20260622192604`
- Track fixed screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/full-matrix-fixes-20260622192534/08-empty-track-fixed.png`

Verification:
- `git diff --check`: passed.
- `LANE_TIMEOUT_SECONDS=600 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622192452.xcresult`
- `LANE_TIMEOUT_SECONDS=600 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 82 / 82.
- Unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622193806.xcresult`

Remaining:
- Simulator Dynamic Type automation printed `Invalid argument` during the first full accessibility pass, and the targeted main-tab pass still visually matched normal text size. Treat automated Dynamic Type verification as blocked until the content-size setter is made reliable or validated manually in Simulator Settings / real device.
- Real-device system-surface QA is still needed for widgets, Live Activities / Dynamic Island, notification tap routing, Siri / Shortcuts phrasing, and voice logging.

### P0 - Engagement Intelligence Layer

Status: Milestone 11 complete; real-device system-surface QA remains open
Files: `Sources/Services/EngagementIntelligenceService.swift`, `Sources/Services/EngagementNotificationScheduler.swift`, `Sources/Services/EngagementWidgetSnapshotStore.swift`, `Sources/Services/LandlordHoursTimerAttributes.swift`, `Sources/App/LandlordHoursAppIntents.swift`, `Sources/Widget/LandlordHoursWidget.swift`, `Sources/Views/EngagementLabView.swift`, `Sources/Views/SettingsView.swift`, `Sources/Views/ContentView.swift`, `Tests/LandlordHoursTests.swift`

Product thesis:
- LandlordHours has low-frequency but high-importance usage. The user may do real property work only occasionally, then forget to log it.
- Siri, Shortcuts, widgets, notifications, and Live Activities should not be treated as separate feature checkboxes. They should be outputs of one contextual intelligence layer that decides when to help, when to stay quiet, and where to send the user.
- The selling point is not "more reminders." The selling point is that LandlordHours quietly helps users avoid missing audit evidence.

Problems:
- Engagement features can easily become noisy, generic, or annoying.
- The best experiences are silent most of the time, which makes them hard to judge through ordinary UI screenshots.
- Different users have very different contexts: no properties, one property, many properties, inactive users, timer users, calendar-import users, users behind pace, users near year-end, and users who dismiss reminders.
- If Siri/Shortcuts, notifications, widgets, and Live Activities each make separate decisions, the app will feel inconsistent.

Acceptance criteria:
- One testable rules layer produces recommendations such as `doNothing`, `showHomeNudge`, `scheduleNotification`, `updateWidget`, `suggestShortcut`, `startLiveActivity`, or `openReviewFlow`.
- Silence is a first-class passing outcome. The app must prove it can suppress prompts after recent activity, dismissal, weak evidence, missing setup, or cooldown periods.
- Every engagement touch has a clear reason, destination, and cooldown.
- Copy stays calm and evidence-focused. It should never sound needy, gamified, or alarmist.
- The user can act in one tap or one sentence when the prompt is useful.
- The same semantic layer powers Siri/Shortcuts, widgets, notifications, Home nudges, and later AI summaries.
- The feature is good enough to market only after scenario fixtures show high relevance and low annoyance across inactive, active, and year-end user states.

Measurement model:
- Primary quality metric: relevant saves created from contextual prompts, not raw notification opens.
- Secondary metrics: calendar draft review rate, Siri/Shortcut successful log rate, widget quick-action use, weekly summary open-to-save rate, timer-abandonment recovery, and export-readiness improvement.
- Guardrail metrics: notification dismissal rate, disabled-notification rate, repeated ignored prompts, prompt shown with no viable next action, and duplicate prompt surfaces within the cooldown window.
- Silent-success metric: cases where the engine correctly chooses `doNothing`.

Scenario fixtures to build before shipping:
- New user with no property and no logs: show setup path, do not send REPS pace reminders.
- One property, no logs after 7 days: quiet reminder to log recent property work.
- User logged yesterday: do nothing.
- User dismissed reminder twice: suppress similar reminders for a cooldown period.
- Active timer running too long: timer safety prompt or Live Activity action.
- Calendar event ended with likely property work: invite review, not automatic save.
- Behind REPS pace in October: weekly summary can mention pace gap with a direct Track/Reports path.
- Near year-end with export-ready records: prompt export/report review.
- No calendar candidates: do nothing.
- Pro user with multiple properties: widget summarizes status and offers review/log action.

Surface strategy:
- Siri/Shortcuts: semantic capture and summary layer. First intents should be Log Time, Start Timer, Stop Timer, Get Year Summary, Open Reports, and Review Calendar Drafts.
- Widgets: persistent memory layer. Show progress, last logged date, pace status, and quick actions. Best for bringing users back without interruption.
- Notifications: contextual recovery layer. Use for weekly pace, inactivity, timer safety, calendar-review candidates, and year-end export prompts. Avoid generic daily reminders.
- Live Activities: bounded active-work layer only. Use for a running timer or active property-work session, not annual REPS progress.
- Home nudges: in-app explanation layer for why the app is asking for action.

Marketing threshold:
- Do not market this as "AI reminders" or "smart notifications" until the scenario simulator proves the app is more often quiet than noisy.
- If confidence is high, position it as: "Quietly catches missing landlord work before tax time."
- If confidence is medium, keep it mostly silent in the product experience and let users discover it through widgets, Siri, and contextual prompts.
- If confidence is low, ship only manual Siri/Shortcuts and widgets first, with notifications limited to timer safety and weekly summaries.

Implementation order:
1. Add `EngagementContext` and `EngagementRecommendation` models. Completed in milestone 1.
2. Add `EngagementIntelligenceService` with pure, unit-tested rules and cooldown handling. Completed in milestone 1.
3. Add scenario fixture tests for the cases above. Initial fixture suite completed in milestone 1.
4. Add a DEBUG-only Engagement Lab to preview recommendations, notification copy, widget states, Siri summary responses, and Live Activity states. Completed in milestone 2.
5. Add App Intents and App Shortcuts on top of the same semantic model. Completed in milestone 3.
6. Add widget timeline/state rendering. Completed in milestone 5.
7. Add local notification scheduler with permission-aware behavior. Completed in milestone 4.
8. Add Live Activity only for active timer/property-work sessions. Completed in milestone 6.
9. Harden Lock Screen widgets, Dynamic Island actions, notification action categories, and system-surface QA entry points. Completed in milestone 8.
10. Polish system-surface design and copy after build-ios audit. Completed in milestone 9.
11. Apply iOS 26+/27 Liquid Glass and reduce wasted space in widget/system-surface previews. Completed in milestone 10.
12. Validate and repair actual Home Screen widget and Dynamic Island layouts after simulator Home Screen review. Completed in milestone 11.

Completed in milestone 1:
- Added `EngagementSurface`, `EngagementDestination`, `EngagementReason`, `EngagementRecommendation`, `EngagementDismissal`, `EngagementContext`, and `EngagementSnapshot`.
- Added `EngagementIntelligenceService` as a pure decision layer that can recommend setup nudges, inactivity notifications, calendar-review prompts, behind-pace widget states, year-end export prompts, long-timer Live Activity review, portfolio summary widgets, or `doNothing`.
- Added suppression for repeated dismissals within a 14-day window.
- Added deterministic unit fixtures for new users, recent active users, inactive users, repeated dismissals, calendar drafts, long-running timers, behind-pace users, year-end export, and no-calendar-candidate silence.
- Wired the new service into the app target.

Completed in milestone 2:
- Added a DEBUG-only Engagement Lab behind Settings > Developer Tools, with launch support via `-LHOpenEngagementLab`.
- Added scenario previews for setup, recently active, inactive, dismissed, calendar candidates, long timer, behind pace, and year-end export states.
- Added surface previews for notification, widget, Live Activity, and Siri/Shortcut copy so the silent/engagement experience can be reviewed before shipping real system integrations.
- Hid the custom app tab bar inside the lab and refined selected scenario cards so the previews read as focused QA surfaces.
- Captured light and dark iPhone 17 Pro Max iOS 27 screenshots for visual review.

Completed in milestone 3:
- Added `LandlordHoursAppIntents.swift` with App Intents and App Shortcuts for Log Time, Open Reports, Year Summary, and Next Action.
- Connected Siri/Shortcuts to the engagement intelligence layer for year summary and next-action responses instead of writing separate reminder logic.
- Added a pending destination bridge so intent-triggered app opens land on the correct tab through `ContentView`.
- Kept the first intent release conservative: it opens destinations and summarizes local data, but does not silently create tax records from voice input yet.
- Verified Xcode 27 App Intents metadata extraction writes `Metadata.appintents`.
- Moved generated `tmp/xcode27` logs/screenshots behind an SSD-backed symlink after the internal drive hit `No space left on device`.

Completed in milestone 4:
- Added `EngagementNotificationScheduler` to convert only notification-surface recommendations into local notification plans.
- Added permission-aware planning: denied permission schedules nothing, and silent/widget/live-activity recommendations do not become notifications.
- Added notification payload metadata with engagement reason and destination for future tap routing.
- Kept interruption level restrained: ordinary engagement prompts use active notifications; timer safety is the only time-sensitive class.
- Added unit coverage for calendar-review notifications, year-end export notifications, denied-permission suppression, silent scenarios, and widget-only scenarios.

Completed in milestone 5:
- Added a WidgetKit extension target, `LandlordHoursWidgetExtension`, embedded in the app target.
- Added `EngagementWidgetSnapshotStore` using the shared App Group `group.com.openclaw.landlordhours` so the app can publish the current engagement state to widgets.
- Added small and medium widget layouts that show the logo mark, pace/progress, quiet next action, and contextual detail without turning the widget into a dense mini app.
- Wired `AppViewModel` saves, loads, timer changes, sign-out, and local reset to refresh the widget snapshot and reload timelines.
- Added app/widget App Group entitlements and `landlordhours://open?destination=...` deep-link routing from the widget into the main tabs.
- Kept the widget conservative and evidence-focused: it points to setup, track, reports, calendar review, export, or timer review based on the same engagement model used by Siri/Shortcuts and notifications.
- Real-device/TestFlight signing will require the App Group capability to be enabled for both the app and widget bundle IDs in Apple Developer.

Completed in milestone 6:
- Added ActivityKit support for the existing timer flow through `LandlordHoursTimerAttributes`.
- Enabled Live Activities in the app plist with `NSSupportsLiveActivities`.
- Added a timer Live Activity to the widget extension with Lock Screen/live banner, compact Dynamic Island, expanded Dynamic Island, and minimal island states.
- Wired `AppViewModel` timer lifecycle to start/update the Live Activity when a timer starts or is restored, and end it when the timer is stopped, canceled, reset, signed out, or recovered as stale.
- Kept the Live Activity bounded to active work only. Annual REPS progress remains in widgets/reports, not on the Lock Screen.
- Copy is intentionally quiet: property, category, elapsed timer, and the next calm action to stop/review in app.

Completed in milestone 7:
- Added `UNUserNotificationCenterDelegate` handling in the app delegate.
- Routed engagement notification taps through the same pending-destination bridge used by App Intents, so notifications, widgets, and Siri/App Shortcuts resolve to consistent app tabs.
- Mapped engagement destinations to product tabs: add property to Properties, track/timer review to Track, reports/calendar/export to Reports, and none to Home.
- Enabled foreground presentation for development and QA so local engagement reminders are visible while testing the app.

Completed in milestone 8:
- Added Lock Screen widget families: accessory circular, accessory rectangular, and accessory inline.
- Added a Dynamic Island expanded-region action link that opens the timer/review path instead of leaving the island as read-only status.
- Added notification categories and action buttons for track, review calendar drafts, prepare export, open reports, add property, and timer review.
- Added direct DEBUG launch routing for Engagement Lab surfaces through `-LHEngagementSurface widget|liveActivity|siri`, so CI can validate each quiet system surface without brittle segmented-control taps.
- Added a Dynamic Island preview inside Engagement Lab with compact and expanded states, so its UI/UX can be reviewed before real-device Dynamic Island QA.
- Added unit coverage for setup, behind-pace, and running-timer widget snapshot semantics.
- Added a targeted UI test that launches and screenshots the widget, Live Activity / Dynamic Island, and Siri / Shortcut Engagement Lab surfaces.

Completed in milestone 9:
- Made widget snapshots goal-aware with `targetHours`, `targetLabel`, and `targetShortLabel`, so STR/material participation users no longer see hardcoded `750h` widget copy.
- Made the engagement pace engine use the configured target hours instead of a fixed REPS target.
- Tightened widget headlines/actions: behind-pace states now show the gap and use `Review pace`; stale widgets show a `Refresh` path; running timers keep `Review timer` priority.
- Added stale-widget fallback copy so old snapshot data does not look falsely current.
- Rewrote notification and Live Activity copy to be calmer and more literal: no "noisy evidence" phrasing, no direct-stop promise from the Dynamic Island when the real action opens the app.
- Added real notification cooldown persistence so repeated app launches do not reschedule the same engagement notification inside its cooldown window.
- Reduced foreground notification interruption: DEBUG shows banner/list without sound; production lists quietly while the user is already in the app.
- Refreshed the widget snapshot when the user changes goal settings.

Completed in milestone 10:
- Reworked the small widget from a sparse centered ring into a denser glanceable status card with headline, supporting detail, target summary, and a compact action chip.
- Tightened the medium widget layout so the ring, status copy, logged-hours stat, days-left stat, and action chip fit with less dead space.
- Added iOS 26+/27 `glassEffect` treatment to widget chips and Engagement Lab system-surface previews, with iOS 17+ fallbacks kept in place.
- Updated Engagement Lab widget, Live Activity, Dynamic Island, and Siri preview cards to use Liquid Glass panels instead of flat white cards.
- Made the lab progress dial respect the configured engagement target hours instead of hardcoding the REPS target.
- Preserved the principle that Live Activities stay bounded to active timers; annual qualification status belongs in widgets/reports, not persistent Lock Screen surfaces.

Completed in milestone 11:
- Rejected the preview-only approval after real Simulator Home Screen review showed clipped widget text, weak hierarchy, and empty system-surface layouts.
- Made timer-running widgets use timer-specific copy and hierarchy instead of competing with annual `750h` progress.
- Simplified Dynamic Island expanded content to property, category, elapsed time, and one action; removed the clipped eyebrow label and duplicated explanatory row.
- Replaced fragile small-widget progress text with a compact progress bar to avoid truncation in the actual iOS Home Screen widget slot.
- Reworked the medium widget lower area into a progress bar plus logged/days-left detail so the space reads intentional.
- Shortened system-surface copy: `Timer active`, `Review before saving.`, and `Review`.

Verification plan:
- Unit tests for every scenario fixture and suppression/cooldown rule.
- UI tests for App Intent destinations where possible.
- Widget snapshot checks for small, medium, and Lock Screen accessory sizes in light/dark/accessibility-large.
- Real-device testing for notification feel, Siri phrasing, Focus mode behavior, widget glanceability, and Live Activity behavior.
- Backlog milestone is not complete until at least one real-device pass confirms the experience feels useful and restrained.

Verification:
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 78 / 78.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622164539.xcresult`
- Build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622164606.xcresult`
- Milestone 2 build: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Milestone 2 unit: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 78 / 78.
- Milestone 2 build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622165619.xcresult`
- Milestone 2 unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622165639.xcresult`
- Milestone 2 screenshots:
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/engagement-lab-202606221657/01-engagement-lab-dark.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/engagement-lab-202606221657/02-engagement-lab-light.png`
- Milestone 3 build: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Milestone 3 unit: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 78 / 78.
- Milestone 3 build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622170244.xcresult`
- Milestone 3 unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622170449.xcresult`
- App Intents metadata: `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27/Build/Products/Debug-iphonesimulator/LandlordHours.app/Metadata.appintents`
- Milestone 4 build: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Milestone 4 unit: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 82 / 82.
- Milestone 4 build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622170844.xcresult`
- Milestone 4 unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622170908.xcresult`
- Milestone 5 project parse: `DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer xcodebuild -list -project LandlordHours.xcodeproj`: passed; project lists `LandlordHoursWidgetExtension`.
- Milestone 5 plist/entitlement lint: `plutil -lint Sources/App/Info.plist Sources/Widget/Info.plist LandlordHours.entitlements LandlordHoursWidget.entitlements`: passed.
- Milestone 5 build: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Milestone 5 unit: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 82 / 82.
- Milestone 5 build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622172910.xcresult`
- Milestone 5 unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622172942.xcresult`
- Milestone 6 project parse: `DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer xcodebuild -list -project LandlordHours.xcodeproj`: passed.
- Milestone 6 plist lint: `plutil -lint Sources/App/Info.plist Sources/Widget/Info.plist`: passed.
- Milestone 6 build: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Milestone 6 unit: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 82 / 82.
- Milestone 6 build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622173410.xcresult`
- Milestone 6 unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622173436.xcresult`
- Milestone 7 build: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Milestone 7 unit: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 82 / 82.
- Milestone 7 build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622173637.xcresult`
- Milestone 7 unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622173718.xcresult`
- Milestone 8 build: `LANE_TIMEOUT_SECONDS=900 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Milestone 8 unit: `LANE_TIMEOUT_SECONDS=900 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 85 / 85.
- Milestone 8 targeted UI: `testEngagementLabSurfacesStayReviewable`: passed, 1 / 1.
- Milestone 8 build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622224343.xcresult`
- Milestone 8 unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622224511.xcresult`
- Milestone 8 UI result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-engagement-lab-r3-20260622225608.xcresult`
- Milestone 9 build: `LANE_TIMEOUT_SECONDS=600 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Milestone 9 full unit: direct `test-without-building -only-testing:LandlordHoursTests`: passed, 87 / 87.
- Milestone 9 targeted engagement unit: direct `test-without-building -only-testing:LandlordHoursTests/EngagementIntelligenceServiceTests`: passed, 18 / 18.
- Milestone 9 build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622231728.xcresult`
- Milestone 9 full unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-all-without-building-20260622231831.xcresult`
- Milestone 9 engagement unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-engagement-20260622231756.xcresult`
- Milestone 10 build: `LANE_TIMEOUT_SECONDS=600 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Milestone 10 targeted UI: rebuilt `testEngagementLabSurfacesStayReviewable`: passed, 1 / 1.
- Milestone 10 build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622232853.xcresult`
- Milestone 10 UI result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-engagement-glass-final-20260622234129.xcresult`
- Milestone 10 UI screenshots: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/engagement-glass-final-20260622234129/`
- Milestone 11 build: `LANE_TIMEOUT_SECONDS=600 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Milestone 11 build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260623000948.xcresult`
- Milestone 11 final Home Screen screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/home-system-surfaces-after-widget-final.png`
- Milestone 11 unit runner note: single-test and full-unit commands compiled the targets but stalled during Xcode 27 simulator test handoff; the hung `xcodebuild` processes were terminated. Re-run unit tests after simulator/Xcode runner state is clean.
- Real-device signing probe: `DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer xcodebuild -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj -scheme LandlordHours -destination 'platform=iOS,id=00008140-001C682C0E7B001C' -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27 -resultBundlePath /Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-altai-20260622174951.xcresult build`: failed at provisioning, not Swift/build logic.
- Real-device continuity signing: restored the existing App Store Connect namespace and verified managed provisioning succeeds for `com.openclaw.landlordhours` and `com.openclaw.landlordhours.widget`.

Next:
- Enable App Groups in Apple Developer for both app identifiers:
  - `com.openclaw.landlordhours`
  - `com.openclaw.landlordhours.widget`
- Add/enable App Group:
  - `group.com.openclaw.landlordhours`
- Add/enable iCloud container:
  - `iCloud.com.openclaw.landlordhours`
- Enable Sign in with Apple for the app identifier.
- Run real-device widget QA by adding the small, medium, accessory circular, accessory rectangular, and accessory inline widgets, then tapping each deep link.
- Run real-device Live Activity and Dynamic Island QA by starting a timer, locking the phone, checking the Lock Screen activity, expanding Dynamic Island, tapping the review action, and stopping the timer.
- Run real-device notification QA under normal mode and Focus mode to confirm action buttons and tap routing feel helpful instead of noisy.
- Real-device build against `BLV-Phone` passed with managed development profiles.
- Continuity result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-openclaw-managed-20260622182805.xcresult`
- Add widget snapshot/real-device visual QA for small and medium widgets in light, dark, and larger text.
- Add real-device Lock Screen and Dynamic Island QA for timer Live Activities.
- Add real-device notification feel QA.
- Add real-device Siri/Shortcut phrase QA before marketing or release claims.

### P0 - Track Time

Status: Milestone 4 complete; real-device voice QA remains open
Files: `Sources/Views/TimeLogView.swift`, `Sources/Services/VoiceEntryService.swift`, `Sources/Services/AITimeEntryService.swift`
Evidence:
- `08-occasional-track.png`
- `13-frequent-track-pro.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/voice-logging-202606220657/track-voice-light.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/voice-logging-202606220657/track-voice-dark.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-20260622072543/timer-idle.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-20260622072543/timer-running.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-20260622072543/timer-review.png`

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

Completed in milestone 2:
- Added Apple-native voice entry to the Log composer through `VoiceEntryService`.
- Kept voice local-first: Apple speech creates a transcript, then the existing local parser fills property, category, participant, and hours.
- Added microphone and speech-recognition privacy strings.
- Added contextual speech phrases for property names, addresses, categories, and tax terms.
- Improved local parsing for dictated durations such as "one and a half hours", "thirty minutes", and "1 hour and 30 minutes".

Completed in milestone 3:
- Reworked Timer mode into the same evidence-first flow as Log mode: setup evidence, live evidence, then review entry.
- Moved primary timer actions above the clock so Start, Stop & Review, and Save are visible before secondary timer decoration.
- Tightened the clock ring and review hierarchy so the tab bar does not hide the main action.
- Added DEBUG-only launch hooks for deterministic Timer idle/running/review visual QA.
- Added accessibility identifiers for timer start, stop, save, and discard controls.

Completed in milestone 4:
- Added DEBUG-only expanded-log visual QA hooks for deterministic large Dynamic Type inspection:
  - `-LHExpandLogDetails`
  - `-LHScrollLogDetailsLower`
- Added expanded-form bottom scroll runway so Date, Person, attachment, and property controls can clear the floating tab bar at accessibility-large text.
- Replaced remaining fixed muted colors in lower Track controls with adaptive text/action colors.
- Validated the expanded manual details screen in forced dark appearance with accessibility-large Dynamic Type.

Verification:
- Build/run: passed with no warnings via XcodeBuildMCP.
- Visual evidence:
  - `/Users/brian/Projects/LandlordHours/docs/e2e-visual-runs/2026-06-21_23-01-07-track-impeccable-milestone/08-occasional-track.png`
  - `/Users/brian/Projects/LandlordHours/docs/e2e-visual-runs/2026-06-21_23-01-07-track-impeccable-milestone/13-frequent-track-pro.png`
- Voice visual evidence:
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/voice-logging-202606220657/track-voice-light.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/voice-logging-202606220657/track-voice-dark.png`
- Timer visual evidence:
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-20260622072543/timer-idle.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-20260622072543/timer-running.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-20260622072543/timer-review.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-dark-20260622072714/timer-running-dark.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/track-expanded-dark-a11y-202606221017/01-track-expanded-details-top-dark-a11y.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/track-expanded-dark-a11y-202606221017/02-track-expanded-details-lower-dark-a11y.png`
- Static design scans: no new Track-specific critical hits.
- Tests: 69 passed, 0 failed, 0 skipped.

Remaining Track follow-up:
- Real-device voice QA is still needed because Simulator microphone/speech permission behavior is not a full production signal.

### P1 - Properties

Status: Milestone 3 complete; first-time tap-through automation verified under First-Time / Onboarding Capture
Files: `Sources/Views/PropertiesView.swift`
Evidence:
- `07-occasional-properties.png`
- `12-frequent-properties-pro.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/add-property.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/property-detail.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-dark-a11y-202606220942/add-property-empty-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-dark-a11y-202606220942/property-detail-dark-a11y.png`

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

Completed in milestone 3:
- Validated empty, occasional, and frequent Pro Properties tab states in forced dark appearance with accessibility-large Dynamic Type.
- Captured Add Property directly from the empty main-tab state and confirmed the evidence-container hierarchy remains readable at large text.
- Captured Property Detail directly from the frequent Pro scenario and confirmed the evidence overview, identity fields, and location card remain usable in dark/accessibility-large.
- Confirmed the Add Property footer remains visible and the form scrolls; no primary copy or action is clipped in the inspected first viewport.

Verification:
- Build: passed through the dedicated Xcode 27 lane.
- Visual evidence:
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-check-20260622030528/occasional-properties.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-check-20260622030528/frequent-properties.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/add-property.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/property-detail.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-dark-a11y/07-empty-properties.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-dark-a11y/12-occasional-properties.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-dark-a11y/17-frequent-properties-pro.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-dark-a11y-202606220942/add-property-empty-dark-a11y.png`
  - `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-dark-a11y-202606220942/property-detail-dark-a11y.png`
- Static design scans: no new Properties-specific critical hits.

Remaining Properties follow-up:
- Continue monitoring Add Property form behavior in real-device keyboard and address-entry conditions.

### P1 - First-Time / Onboarding Capture

Status: Milestone 5 complete; first-time activation flow verified
Files: `Sources/Views/OnboardingView.swift`, `Sources/ViewModels/AppViewModel.swift`, `Sources/Views/SettingsView.swift`, `Sources/Views/DashboardView.swift`, `Sources/Views/ContentView.swift`, `Sources/Views/PropertiesView.swift`, `Sources/Views/TimeLogView.swift`, `UITests/LandlordHoursUITests.swift`, visual capture scripts
Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/01-onboarding-goal.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/02-empty-home.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/03-empty-properties.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/04-empty-track.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/05-empty-reports.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_03-37-24/06-empty-settings.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/01-onboarding-goal.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/02-onboarding-property.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/03-onboarding-paywall.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/04-onboarding-notifications.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/05-onboarding-calendar.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/onboarding-contact-sheet.jpg`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-depth-fix-202606220910/02-onboarding-property-fixed.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-polish-202606220930/04-onboarding-notifications-polished.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-polish-202606220930/05-onboarding-calendar-polished.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-polish-202606220933/03-onboarding-paywall-polished-final.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-dark-a11y/review.md`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-dark-a11y-fix-202606220937/01-onboarding-goal-dark-a11y-fixed.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-dark-a11y-fix-202606220937/02-onboarding-property-dark-a11y-fixed.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-dark-a11y-fix-202606220937/03-onboarding-paywall-dark-a11y-fixed.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-dark-a11y-fix-202606220937/04-onboarding-notifications-dark-a11y-fixed.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-dark-a11y-fix-202606220937/05-onboarding-calendar-dark-a11y-fixed.png`

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

Completed in milestone 2:
- Added a deterministic `-LHOnboardingStep` launch argument for onboarding goal, property, Pro/paywall, notifications, and calendar steps.
- Expanded the e2e visual capture matrix from 17 to 21 screenshots so onboarding substeps are audited separately from signed-in main tabs.
- Updated the generated review checklist to match the 21-shot matrix and distinguish onboarding, empty main tabs, occasional user, frequent Pro user, and non-admin Settings.
- Captured and inspected an onboarding contact sheet covering all five onboarding steps.
- Tightened the property onboarding screen after screenshot review showed the CTA too close to the bottom safe area.

Completed in milestone 3:
- Reworked the Pro/paywall step from a price-heavy generic upgrade screen into a clearer Pro value card with export, unlimited properties, and review-before-save benefits.
- Removed fake star-rating social proof from the onboarding paywall.
- Replaced the notifications phone mockup with a concrete reminder plan that explains visit reminders, weekly pace summaries, and user control.
- Replaced the calendar mockup with an import preview and a simple Scan -> Review -> Save flow.
- Made Calendar visibly optional with the shared `Skip for now` CTA pattern.
- Added shared onboarding header, mini-badge, benefit-card, detection-row, and flow-step helpers so the remaining permission screens use one component vocabulary.
- Fixed screenshot-detected text truncation in Pro and Calendar.

Completed in milestone 4:
- Captured the full 21-screen visual matrix in forced dark appearance and accessibility-large Dynamic Type.
- Fixed the shared onboarding primary CTA color so dark-mode buttons use the app action color instead of low-contrast charcoal.
- Fixed the selected property-type chip so it no longer turns into a near-white block in dark mode.
- Re-captured all five onboarding steps in dark/accessibility-large after the component fixes.

Verification:
- Build: `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Visual capture: `SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh` passed with 17 screenshots and `review.md`.
- Screenshot inspection: confirmed `01-onboarding-goal.png` is true onboarding, while `02-empty-home.png` through `06-empty-settings.png` are signed-in main app tabs with no properties or entries.
- Milestone 2 build: `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Milestone 2 visual capture: `OUT_DIR=/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh` passed with 21 screenshots and `review.md`.
- Milestone 2 unit tests: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 69 / 69.
- Static design scans: reviewed; no new onboarding/root critical hits.
- Whitespace scan: `git diff --check` passed.
- Milestone 3 build: `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Milestone 3 visual capture: targeted Pro, notifications, and calendar screenshots passed after two fit iterations.
- Milestone 3 unit tests: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 69 / 69.
- Milestone 3 static scans: reviewed; no new onboarding hits.
- Milestone 3 whitespace scan: `git diff --check` passed.
- Milestone 4 full matrix: `OUT_DIR=/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-dark-a11y APPEARANCE=dark CONTENT_SIZE=accessibility-large SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh` passed with 21 screenshots.
- Milestone 4 targeted re-capture: five onboarding steps passed in dark/accessibility-large after the CTA and selector fixes.
- Milestone 4 unit tests: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 69 / 69.
- Milestone 4 static scans: reviewed; no new onboarding hits.
- Milestone 4 whitespace scan: `git diff --check` passed.

Completed in milestone 5:
- Added stable accessibility identifiers for Home activation tiles, Add Property fields, and Track first-log controls.
- Fixed the Home -> Properties -> Add Property race by routing the combined transition through the root tab coordinator before posting the sheet-open notification.
- Improved Add Property keyboard flow with explicit focus states and native Next/Done submit labels.
- Added a semantic UI test that completes the first-time path: Home activation -> Add Property -> Home -> First hour -> Track -> Log Time -> Home completion.

Verification:
- Targeted first-time activation UI test reported pass on the dedicated iOS 27 Pro Max lane: `LandlordHoursUITests/testFirstTimeActivationFlowAddsPropertyAndLogsFirstHour`.
- Result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/first-time-activation-202606221642.xcresult`
- Log: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs/first-time-activation-202606221642.log`
- Final build: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Final unit tests: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 69 / 69.
- Final whitespace scan: `git diff --check` passed.
- Build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622163017.xcresult`
- Unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622163030.xcresult`

Remaining First-Time follow-up:
- Xcode 27 beta UI testing still emits duplicate WebCore/WebKit accessibility warnings and can leave the runner slow to return after selected UI tests; treat the XCTest pass line/result bundle as the primary signal.

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

Status: Completed
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
- Continue monitoring lower Home cards around the floating tab bar during full-matrix visual runs.
- The core Property and First hour activation path now has semantic UI coverage; Learn and Report activation entry points can be covered later if their destination behavior changes.

### P2 - Learning Center Content Quality

Status: Completed; remaining imagery licensing decision is pre-submission polish
Files: `Sources/Views/LearningCenterView.swift`, `Sources/Views/DashboardView.swift`, `Assets.xcassets/LearningHero.imageset`, `Assets.xcassets/LearningArticle*.imageset`
Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-polish-202606220758/04-learn-hub-light-replaced.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-polish-202606220758/05-learn-hub-dark-replaced.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-ia-202606220856/01-learn-hub-light.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-dark-a11y-202606220948/01-learn-hub-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-dark-a11y-202606220948/02-article-reps-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-dark-a11y-202606220948/03-article-str-ltr-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-dark-a11y-202606220948/04-article-spouse-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-dark-a11y-202606220948/05-article-records-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-secondary-dark-a11y-202606221002/01-guide-reps-roadmap-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-secondary-dark-a11y-202606221002/02-guide-audit-proof-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-secondary-dark-a11y-202606221002/03-quick-read-hour-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-secondary-dark-a11y-202606221002/04-quick-read-receipts-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-lower-dark-a11y-202606221022/01-learn-guides-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-lower-dark-a11y-202606221022/02-learn-quick-reads-dark-a11y.png`

Problems:
- Learn used repeated generic article artwork, so different topics felt interchangeable.
- The first generated REPS artwork looked AI-generic and included fake app/UI cues.
- Article details were prose-heavy and needed more scannable concept structure.

Completed in milestone 1:
- Replaced the Learn hero and REPS lead art with a more realistic landlord/tax desk photo: keys, calendar, folder, receipts, and house model; no fake phone UI.
- Replaced the recordkeeping article image with more realistic receipt/folder photography.
- Kept the stronger STR vs LTR comparison artwork because it explains a real contrast rather than acting as filler.
- Added topic-specific image routing so REPS, STR/LTR, spouse strategy, records, and portfolio articles no longer repeat the same generic visuals.
- Added short section subtitles to make the Learn hub easier to scan.
- Added article detail `Quick map` cards so dense tax topics start with a structured three-point flow before long prose.
- Added a DEBUG launch argument for repeatable Learn visual QA:
  - `-LHOpenLearningCenter`

Completed in milestone 2:
- Simplified the Learn hub from many competing formats into three repeated patterns: a recommended core path, topic filters, and consistent content rows.
- Folded the realistic hero image into the core path card instead of using a separate standalone hero plus separate start rows.
- Replaced mixed featured-card plus two-column article cards with one article row pattern across all article sections.
- Replaced the horizontal guide carousel with guide rows so the lower Learn surface follows the same scan pattern.
- Kept quick answers as compact rows, matching the new library structure.

Completed in milestone 3:
- Added a DEBUG-only direct article-detail launch hook for reliable visual QA:
  - `-LHOpenLearningArticle <article-id>`
- Captured the Learn hub and four representative article details in forced dark appearance with accessibility-large Dynamic Type.
- Validated article detail headers, topic-specific media, quick maps, body text, and first callout regions for REPS, STR/LTR, spouse hours, and recordkeeping.
- Confirmed the direct Learn launch path still works through `-LHOpenLearningCenter`.

Completed in milestone 4:
- Added DEBUG-only direct routes for Learn guide and quick-read detail visual QA:
  - `-LHOpenLearningGuide <guide-id>`
  - `-LHOpenQuickRead <quick-read-id>`
- Replaced fixed light-mode colors in Guide, Lesson, and Quick Read detail surfaces with adaptive text and surface tokens.
- Captured two guide details and two quick-read details in forced dark appearance with accessibility-large Dynamic Type.
- Confirmed guide CTAs, lesson rows, source cards, quick-read headers, and body copy remain readable and unclipped.

Completed in milestone 5:
- Added DEBUG-only lower Learn hub scroll hooks for deterministic Guides and Quick Answers inspection:
  - `-LHScrollLearningGuides`
  - `-LHScrollLearningQuickReads`
- Replaced remaining fixed muted colors in article detail metadata and related rows with adaptive tertiary text.
- Captured the lower Learn hub in forced dark appearance with accessibility-large Dynamic Type.
- Confirmed Guides and Quick Answers use the simplified row pattern, remain readable, and do not collide with navigation or tab surfaces.

Verification:
- Build: `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Unit tests: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 69 / 69.
- Static design scans: reviewed; only intentional tax acronyms/badges were flagged.
- Visual screenshot inspection: first viewport now uses realistic editorial imagery and keeps the Home-to-Learn flow intact.
- Milestone 2 visual screenshot inspection: first viewport is easier to follow, with the recommended path visible before browsing.
- Milestone 3 build: `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Milestone 3 visual screenshot inspection: Learn hub and four article detail screens passed in forced dark/accessibility-large.
- Milestone 3 unit tests: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 69 / 69.
- Milestone 4 build: `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Milestone 4 visual screenshot inspection: two guide details and two quick-read details passed in forced dark/accessibility-large.
- Milestone 5 build: `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Milestone 5 visual screenshot inspection: Guides and Quick Answers lower hub states passed in forced dark/accessibility-large.
- Final unit tests: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 69 / 69.
- Final static design scans and `git diff --check`: passed.

Remaining Learn follow-up:
- Consider replacing remaining generated images with licensed real photography before App Store submission if budget/time allows.

### P2 - Settings / Home Maintenance

Status: Watch
Files: `Sources/Views/SettingsView.swift`, `Sources/Views/DashboardView.swift`

Notes:
- Recent Settings, Paywall, navigation, and Home Learning changes are directionally strong.
- Future work should be incremental: bottom inset, copy tightening, accessibility, and dark-mode checks.

### P2 - Signed-Out Welcome

Status: Completed
Files: `Sources/Services/AppleSignIn.swift`
Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/signed-out-welcome-ios27-20260622-final/01-welcome-light.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/signed-out-welcome-ios27-20260622-final/02-welcome-dark.png`

Problems:
- The signed-out screen used a rotating carousel with generic clay-style artwork and oversized marketing copy.
- The first screen after launch did not match the cleaner, premium utility direction of Home, Track, Reports, Learn, and the new launch screen.

Completed:
- Replaced the carousel with one focused welcome screen: brand mark, concise promise, useful preview, and auth actions.
- Removed the generic clay artwork and repeated slide structure.
- Deleted the unreferenced `OnboardingHeroQualification`, `OnboardingHeroLogging`, and `OnboardingHeroRecords` image sets so the old direction does not linger in the active asset catalog.
- Used the existing `WaveHouseIcon` and adaptive wordmark so the screen matches the app identity in light and dark mode.
- Added an iOS 26+/27 native glass card treatment for the preview module with an iOS 17+ fallback.
- Reframed the preview around useful capabilities: native sign-in, local parsing, speech/type entry, property context, and review-ready records.

Verification:
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Light and dark signed-out welcome screenshot inspection: passed.

Remaining follow-up:
- Include the signed-out welcome screen in the next full dark/light/accessibility visual matrix.

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
- Fixed the XcodeBuildMCP active defaults profile so automation uses the dedicated `LandlordHours iPhone 17 Pro Max iOS 27` simulator instead of a shared simulator.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/add-property.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-milestone-2-20260622032558/property-detail.png`

Verification:
- `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Active Xcode 27 profile now points at `LandlordHours iPhone 17 Pro Max iOS 27` (`B119FCEA-3C7B-4022-A57E-28357879F07D`).
- Static design scans: reviewed, no new Properties-specific critical hits.

Notes:
- XcodeBuildMCP accessibility snapshots currently fail against the Xcode 27 beta because the tool looks for a removed `SimulatorKit.framework` path. Screenshots still work via `simctl`.
- XcodeBuildMCP runtime logs are still being written under `/Users/brian/Library/Developer/XcodeBuildMCP/...`; DerivedData and result bundles are on SSD as expected.

Next:
- Validate Properties in dark mode and large Dynamic Type.
- Resolve first-time main-tab visual capture so onboarding and empty tab states can be audited separately.

### 2026-06-22 - Properties Dark / Dynamic Type Validation

Outcome:
- Validated the redesigned Properties list, Add Property sheet, and Property Detail screen in forced dark appearance with accessibility-large Dynamic Type.
- Confirmed empty, occasional, and frequent Pro Properties tab states remain readable in the 21-screen visual matrix.
- Confirmed Add Property's evidence-container hierarchy and bottom footer remain usable at large text.
- Confirmed Property Detail's evidence overview, identity fields, and location section remain usable in dark/accessibility-large.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-dark-a11y/07-empty-properties.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-dark-a11y/12-occasional-properties.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-dark-a11y/17-frequent-properties-pro.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-dark-a11y-202606220942/add-property-empty-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/properties-dark-a11y-202606220942/property-detail-dark-a11y.png`

Verification:
- Visual screenshot inspection: passed for first viewport and primary flows.

Next:
- Keep first-time tap-through activation under the First-Time / Onboarding Capture backlog.

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
- Dark/accessibility-large screenshot inspection: activation grid passed in `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-dark-a11y/06-empty-home.png`.

Next:
- Continue monitoring lower Home content around the floating tab bar during full-matrix visual runs.
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

### 2026-06-22 - Apple-Native Voice Logging

Outcome:
- Added a `Speak` control directly inside the Track Log composer.
- Built `VoiceEntryService` with Apple Speech + AVFAudio so dictated text flows into the same note field and parser used by typed entries.
- Kept MiniMax optional; voice-to-fields does not require a remote API key.
- Added speech and microphone usage descriptions to `Info.plist`.
- Improved parser coverage for dictation-like duration phrases.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/voice-logging-202606220657/track-voice-light.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/voice-logging-202606220657/track-voice-dark.png`

Verification:
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 69 / 69.
- Visual screenshot inspection: voice control is visible and does not crowd the first Track viewport in light or dark mode.

Next:
- Run real-device voice QA before treating speech recognition as release-complete.
- Continue with deterministic onboarding substep capture or Timer mode composition.

### 2026-06-22 - Timer Mode Composition

Outcome:
- Reworked Timer mode from an older standalone card into an evidence-first flow aligned with the redesigned Log composer.
- Added a shared Timer header with explicit idle, live, and review states.
- Reordered idle and running screens so the primary actions appear before the clock ring.
- Shortened and tightened the review screen so the note requirement and Save Timer Entry action are visible above the tab bar.
- Added DEBUG launch hooks for repeatable timer visual QA:
  - `-LHInitialTrackMode timer`
  - `-LHStartTimer`
  - `-LHShowTimerReview`
- Added accessibility identifiers for timer start, stop, save, and discard controls.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-20260622072543/timer-idle.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-20260622072543/timer-running.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-20260622072543/timer-review.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/timer-polish-dark-20260622072714/timer-running-dark.png`

Verification:
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 69 / 69.
- Static design scans: reviewed; no new Track-specific critical hits.

Next:
- Add deterministic capture for deeper onboarding steps.
- Add UI automation for Home activation-card actions.
- Keep Siri/Shortcuts/App Intents at the end of the roadmap unless user priority changes.

### 2026-06-22 - Learning Center Realistic Imagery / Scanability

Outcome:
- Replaced the generic Learn hero direction with realistic landlord/tax desk photography that avoids fake app UI and obvious AI-product-promo cues.
- Replaced the REPS and recordkeeping article images with realistic desk/receipt imagery.
- Preserved the STR vs LTR visual direction because it communicates a specific comparison instead of acting as repeated filler art.
- Added article-specific image routing so each major topic gets a more meaningful visual.
- Added short section subtitles and article detail `Quick map` cards to make dense tax concepts easier to scan before reading.
- Added `-LHOpenLearningCenter` for deterministic Learn screenshot capture from the real Home navigation stack.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-polish-202606220758/04-learn-hub-light-replaced.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-polish-202606220758/05-learn-hub-dark-replaced.png`

Verification:
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 69 / 69.
- Static design scans: reviewed; only intentional tax acronyms and the `IRS-ready records` badge were flagged.

Next:
- Capture scrolled Learn cards and article detail screens once UI automation is stable again.
- Validate Learn with app appearance forced to dark and with larger Dynamic Type.
- Continue replacing any remaining AI-looking generated artwork with realistic photography or purpose-built diagrams.

### 2026-06-22 - Learning Article Detail Dark / Dynamic Type Validation

Outcome:
- Added `-LHOpenLearningArticle <article-id>` so article detail screens can be captured deterministically without fragile tap automation.
- Captured the Learn hub plus REPS, STR/LTR, spouse hours, and recordkeeping article details in forced dark appearance with accessibility-large Dynamic Type.
- Confirmed the article header, topic-specific media, quick map, body text, and first callout regions remain readable and unclipped.
- Confirmed `-LHOpenLearningCenter` still opens the Learn area before routing into a detail article.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-dark-a11y-202606220948/01-learn-hub-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-dark-a11y-202606220948/02-article-reps-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-dark-a11y-202606220948/03-article-str-ltr-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-dark-a11y-202606220948/04-article-spouse-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-dark-a11y-202606220948/05-article-records-dark-a11y.png`

Verification:
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Targeted Learn dark/accessibility screenshot capture: passed.
- Visual screenshot inspection: passed for all five captures.

Next:
- Validate guide detail and quick-read detail screens in dark/accessibility-large.
- Capture lower-scroll Learn states after those detail surfaces are checked.

### 2026-06-22 - Learning Guide / Quick Read Dark Dynamic Type Validation

Outcome:
- Added direct Learn visual QA hooks for guide and quick-read details.
- Replaced fixed light-mode text/surface colors in Guide, Lesson, and Quick Read detail screens with adaptive colors.
- Captured two guide details and two quick-read details in forced dark appearance with accessibility-large Dynamic Type.
- Confirmed the secondary Learn surfaces now keep readable body text, visible guide CTAs, and unclipped lesson/source rows.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-secondary-dark-a11y-202606221002/01-guide-reps-roadmap-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-secondary-dark-a11y-202606221002/02-guide-audit-proof-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-secondary-dark-a11y-202606221002/03-quick-read-hour-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-secondary-dark-a11y-202606221002/04-quick-read-receipts-dark-a11y.png`

Verification:
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Targeted guide/quick-read dark/accessibility screenshot capture: passed.
- Visual screenshot inspection: passed for all four captures.

Next:
- Capture lower-scroll Learn states.
- Continue Home activation grid dark/accessibility validation.

### 2026-06-22 - Track Expanded Details Dark Dynamic Type Validation

Outcome:
- Added deterministic expanded-log visual QA hooks for the manual review form.
- Added extra expanded-form scroll runway so lower controls are reachable above the floating tab bar at accessibility-large text.
- Replaced remaining fixed muted colors in lower Track controls with adaptive colors.
- Confirmed the Date, Person, attachment, and property controls remain readable and usable in forced dark appearance with accessibility-large Dynamic Type.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/track-expanded-dark-a11y-202606221017/01-track-expanded-details-top-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/track-expanded-dark-a11y-202606221017/02-track-expanded-details-lower-dark-a11y.png`

Verification:
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Targeted Track dark/accessibility screenshot capture: passed.
- Visual screenshot inspection: passed for top and lower expanded-detail states.
- Final unit tests: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 69 / 69.
- Final static design scans and `git diff --check`: passed.

Next:
- Real-device voice QA remains the only Track-specific release signal that cannot be completed in Simulator.

### 2026-06-22 - Learning Lower Hub Dark Dynamic Type Validation

Outcome:
- Added DEBUG-only lower Learn hub scroll hooks for deterministic Guides and Quick Answers screenshots.
- Replaced remaining fixed muted colors in article-detail metadata with adaptive tertiary colors.
- Captured lower Learn hub sections in forced dark appearance with accessibility-large Dynamic Type.
- Confirmed Guides and Quick Answers now share the simplified row vocabulary and remain readable in the lower hub.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-lower-dark-a11y-202606221022/01-learn-guides-dark-a11y.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/learn-lower-dark-a11y-202606221022/02-learn-quick-reads-dark-a11y.png`

Verification:
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Targeted Learn lower-hub dark/accessibility screenshot capture: passed.
- Visual screenshot inspection: passed for Guides and Quick Answers.
- Final unit tests: `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 69 / 69.
- Final static design scans and `git diff --check`: passed.

Next:
- Treat remaining Learn imagery replacement as pre-submission content polish, not a blocked app-flow redesign.

### 2026-06-22 - Onboarding Depth Capture

Outcome:
- Added deterministic onboarding capture through `-LHOnboardingStep` so the visual loop can jump directly to goal, property, Pro/paywall, notifications, and calendar steps.
- Expanded the e2e visual script from 17 to 21 screenshots, separating true onboarding screens from signed-in empty main-tab screens.
- Updated `review.md` generation so future visual audits follow the new matrix without relying on memory.
- Captured all five onboarding steps and generated an onboarding contact sheet for faster visual review.
- Fixed the property onboarding screen after inspection showed the CTA sitting too close to the bottom safe area.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/01-onboarding-goal.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/02-onboarding-property.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/03-onboarding-paywall.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/04-onboarding-notifications.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/05-onboarding-calendar.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth/onboarding-contact-sheet.jpg`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-depth-fix-202606220910/02-onboarding-property-fixed.png`

Verification:
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `OUT_DIR=/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-depth SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh`: passed, 21 screenshots captured.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 69 / 69.
- `git diff --check`: passed.
- Static design scans: reviewed; no new onboarding/root critical hits.

Next:
- Polish the Pro/paywall, notifications, and calendar onboarding steps to match the newer Home, Track, Properties, and Learn quality bar.
- Validate onboarding with forced dark appearance and larger Dynamic Type.
- Add semantic UI automation for the full first-time activation flow after Xcode 27 beta UI automation transport is stable.

### 2026-06-22 - Onboarding Pro / Permissions Polish

Outcome:
- Reworked the Pro onboarding step around a single value card instead of a generic price-heavy layout.
- Removed fake star-rating proof and made the purchase promise more concrete: audit-ready PDFs, unlimited properties, and review-before-save.
- Replaced the notifications lock-screen mockup with a clearer reminder plan tied to property visits, weekly pace, and user control.
- Replaced the calendar mockup with an import preview and Scan -> Review -> Save flow so users understand that imported events become reviewed drafts.
- Made Calendar optional through the same `Skip for now` pattern used by notifications.
- Added shared onboarding UI helpers for headers, mini badges, benefit cards, detection rows, and flow steps.
- Iterated after screenshot review to fix Calendar title compression, flow-caption truncation, and Pro benefit truncation.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-polish-202606220930/04-onboarding-notifications-polished.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-polish-202606220930/05-onboarding-calendar-polished.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-polish-202606220933/03-onboarding-paywall-polished-final.png`

Verification:
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Targeted screenshot capture for Pro, notifications, and calendar: passed.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 69 / 69.
- `git diff --check`: passed.
- Static design scans: reviewed; no new onboarding hits.

Next:
- Validate the full onboarding flow in forced dark appearance and larger Dynamic Type.
- Run an end-to-end first-run activation flow once Xcode 27 beta UI automation transport is stable.

### 2026-06-22 - Onboarding Dark / Dynamic Type Validation

Outcome:
- Ran the full 21-screen visual matrix with `APPEARANCE=dark` and `CONTENT_SIZE=accessibility-large`.
- Confirmed the redesigned Pro, notifications, and calendar onboarding steps hold their layout in dark/accessibility-large.
- Fixed the shared onboarding CTA to use the semantic action color in dark mode instead of the older charcoal fill.
- Fixed the property-type selector so its selected state remains a dark-mode surface instead of becoming a near-white chip.
- Re-captured all five onboarding steps after the fixes and confirmed no clipped CTAs or broken primary content.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_onboarding-dark-a11y/review.md`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-dark-a11y-fix-202606220937/01-onboarding-goal-dark-a11y-fixed.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-dark-a11y-fix-202606220937/02-onboarding-property-dark-a11y-fixed.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-dark-a11y-fix-202606220937/03-onboarding-paywall-dark-a11y-fixed.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-dark-a11y-fix-202606220937/04-onboarding-notifications-dark-a11y-fixed.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-dark-a11y-fix-202606220937/05-onboarding-calendar-dark-a11y-fixed.png`

Verification:
- `LANE_TIMEOUT_SECONDS=240 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `APPEARANCE=dark CONTENT_SIZE=accessibility-large SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh`: passed, 21 screenshots captured.
- Targeted dark/accessibility onboarding re-capture: passed for all five onboarding steps.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 69 / 69.
- `git diff --check`: passed.
- Static design scans: reviewed; no new onboarding hits.

Next:
- Run an end-to-end first-run activation flow when the Xcode 27 beta UI automation transport is stable.
- Continue with Learn article-depth capture or Properties dark/Dynamic Type validation.

### 2026-06-22 - Pro Max iOS 27 Full Visual Audit

Outcome:
- Moved the dedicated project lane to `LandlordHours iPhone 17 Pro Max iOS 27` so screenshots match the larger device Brian wants to review on.
- Ran the full 21-screen matrix on the dedicated Pro Max simulator in forced dark appearance with accessibility-large Dynamic Type.
- Confirmed onboarding, empty tabs, occasional-user, frequent-Pro, and non-admin Settings states render without blank screens, broken tab selection, or contradictory Pro/tax copy.
- Found and fixed a P2 bottom-dock visual issue where long Settings/Reports content peeked too strongly behind the floating tab bar.
- Added a shared `tabBarUnderlay` in `ContentView` so the floating tab reads as an intentional dock and long scroll content fades cleanly behind it.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_promax-ios27-audit-r2/review.md`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_promax-ios27-audit-r3-targeted/settings-occasional.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_promax-ios27-audit-r3-targeted/reports-frequent.png`

Verification:
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 69 / 69.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed after the tab-bar underlay fix.
- `APPEARANCE=dark CONTENT_SIZE=accessibility-large SETTLE_SECONDS=5 ./ci_scripts/capture_iphone_e2e_visuals.sh`: passed, 21 screenshots captured.
- Targeted Pro Max screenshots for Settings and Reports after the final dock adjustment: passed.

Next:
- First-time activation semantic tap flow is verified on the dedicated Xcode 27 Pro Max lane.
- Real-device voice QA remains required before release.
- Siri/Shortcuts stay deferred per Brian's preference.

### 2026-06-22 - Launch / Loading Screen

Outcome:
- Fixed the blank white native launch frame by replacing the brittle `UILaunchScreen` image-dictionary approach with a real native `LaunchScreen.storyboard`.
- Simplified the native launch surface to a single brand wordmark. Removed tax-year copy, explanatory loading text, feature labels, and decorative rail because users are not reading during startup.
- Confirmed the storyboard launch surface renders immediately on cold unauthenticated launch, before SwiftUI is available.
- Reworked the SwiftUI bridge into a minimal brand mark, wordmark, and three-dot activity signal, and shortened its ready-state dwell time.
- Recreated the existing wave-house mark as reusable vector assets for future brand/product surfaces:
  - `Assets.xcassets/LandlordHoursMark.imageset/LandlordHoursMark.svg`
  - `Assets.xcassets/LandlordHoursMarkPDF.imageset/LandlordHoursMark.pdf`
- Kept the launch/loading direction aligned with the app's trustworthy tax-record utility identity instead of using a generic marketing or social-proof screen.
- Mobbin was requested for reference, but no Mobbin connector was available in this Codex session; the implemented pattern follows the common high-quality iOS approach of making the native launch screen a stable, static brand/product promise and keeping animation in SwiftUI.

Evidence:
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/loading-screen-20260622-storyboard-final/launch-light.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/loading-screen-20260622-storyboard-final/launch-dark.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/loading-screen-20260622-storyboard-r2/02-transition-light.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/loading-screen-20260622-vector-final/launch-light.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/loading-screen-20260622-vector-final/launch-dark.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/loading-screen-20260622-minimal-r2/01-first-frame-light.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/loading-screen-20260622-minimal-r2/03-first-frame-dark.png`
- `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/loading-screen-20260622-minimal-r2/05-after-5s-dark.png`

Verification:
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 69 / 69.
- Startup screenshot capture: passed for native storyboard launch in light and dark mode.
- `git diff --check`: passed.

Next:
- The iOS 27 simulator did not render either SVG or vector PDF image assets inside the native launch storyboard, so the final native launch design intentionally uses typography and simple native shapes only. Use the vector mark in SwiftUI/app-controlled surfaces, app icon exploration, export cover pages, paywall, and marketing assets where image rendering is reliable.

### 2026-06-22 - Xcode 27 Iteration Test Loop

Outcome:
- Added semantic UI coverage for the design roadmap so future iterations can be validated instead of judged only by screenshots.
- Added a main-tab visual smoke matrix across empty, occasional, and frequent user states. It attaches screenshots for Home, Properties, Track, Reports, and Settings, and fails if the old low-value `Welcome to LandlordHours` headline returns.
- Added Track empty-state routing coverage to verify `Add a property first` opens the property sheet with name/address fields.
- Added timer launch-state coverage for idle, running, and review states, with screenshot attachments for each.
- Added first-time activation coverage for Home setup cards: add property, return Home, log first hour, and confirm the setup prompt is removed.
- Hardened appearance-preference testing so dark mode selection shows `Saved - dark mode` and persists after relaunch.
- Hardened Reports export testing so the export sheet is opened, the generate-PDF action is reachable, and the ready/share state appears.
- Fixed the DEBUG mock subscription root cause where StoreKit entitlement refresh could overwrite mock Pro state during UI tests. Production StoreKit behavior is unchanged.

Verification:
- Unit: `LANE_TIMEOUT_SECONDS=600 ./ci_scripts/test_xcode27_lane.sh unit` passed, 82 / 82.
- Unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622202155.xcresult`
- UI: direct Xcode 27 run passed, 10 / 10.
- UI result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-direct-20260622203333.xcresult`
- UI log: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs/lane-ui-direct-20260622203333.log`
- `xcresulttool` verified both result bundles as readable.
- `git diff --check`: passed.

Notes:
- The first wrapper-based full UI run printed a clean 10 / 10 pass summary, but interrupting the beta `xcodebuild` finalization left that `.xcresult` without `Info.plist`; use the direct UI result bundle above as the canonical evidence.
- Xcode 27 beta still emits the duplicate WebCore/WebKit accessibility-class simulator warning during UI tests. It did not fail the suite.
- The final UI result contains two non-fatal `Invalid frame dimension (negative or non-finite)` runtime warnings. Treat this as a follow-up polish/debug signal for SwiftUI layout, not a test blocker.

### 2026-06-22 - Onboarding Goal Decision Polish

Outcome:
- Reworked the first onboarding decision screen from generic icon rows into tax-specific decision tiles.
- Replaced the repeated icon-badge pattern with custom SwiftUI mini-visuals for REPS progress, STR participation, clean records, and guided setup.
- Added short decision labels such as `750h + 50% rule`, `100h STR test`, `Records first`, and `Guided setup` so the screen explains why each path matters before the user taps Continue.
- Kept the visuals code-native instead of generated bitmap art. For this screen, deterministic SwiftUI diagrams are more appropriate than AI-generated images because the user is choosing a tax setup path, not consuming editorial content.
- Added a selected-state setup hint that explains how the choice changes the app experience.
- Added UI test assertions for the new decision labels so future redesigns do not silently fall back to generic cards.

Evidence:
- Light screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-goal-polish-20260622/goal-light.png`
- Dark screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-goal-polish-20260622/goal-dark.png`
- Second-pass light screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-goal-polish-20260622-r2/goal-light.png`
- Second-pass dark screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-goal-polish-20260622-r2/goal-dark.png`
- Second-pass light/dark comparison: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/onboarding-goal-polish-20260622-r2/goal-light-dark-comparison.jpg`

Verification:
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Targeted UI test: `LandlordHoursUITests/testFirstRunPropertySetupCTARequiresNameAndAddressForSaveCopy` passed, 1 / 1.
- UI result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-goal-onboarding-20260622205024.xcresult`

Second-pass refinement:
- Kept the selected-card animation and interaction model, but replaced the first-pass mini-icons with more concrete micro-diagrams.
- REPS now reads as a house, 750-hour target, and 50% progress check instead of an abstract ring.
- STR participation now reads as a calendar/evidence card with a 100-hour badge.
- Records-first now reads as a document stack with checked evidence lines.
- Guided setup now reads as a route card with progressive waypoints.
- Verified both light and dark mode side by side; contrast and selected-card hierarchy hold up in both appearances.

Second-pass verification:
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- Build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622212658.xcresult`
- Targeted UI test: `LandlordHoursUITests/testFirstRunPropertySetupCTARequiresNameAndAddressForSaveCopy` passed, 1 / 1.
- UI result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-goal-onboarding-r2-20260622212836.xcresult`

### 2026-06-23 - iOS 27 Skill-Stack Release Polish

Skills used:
- `build-ios-apps:swiftui-liquid-glass`
- `build-ios-apps:swiftui-ui-patterns`
- `build-ios-apps:ios-app-intents`
- `build-ios-apps:ios-debugger-agent`
- `impeccable`

Outcome:
- Applied an iOS 26+/27 native Liquid Glass treatment to the floating app dock, with the existing capsule surface preserved as the iOS 17 fallback.
- Kept the dock interactive and availability-gated instead of raising the minimum OS target.
- Tightened App Intent naming so Siri/Shortcuts expose task verbs: `Summarize Landlord Hours` and `Review Next Landlord Action`.
- Made engagement notification sound behavior explicit in `EngagementNotificationPlan`.
- Changed contextual calendar/year-end notifications to silent by default, preserving the product thesis that LandlordHours should be quiet unless the user is in an active timer-safety scenario.
- Added unit assertions so quiet notification behavior is validated instead of only documented.

Evidence:
- Screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/ios27-polish-home-glass-dock-202606230024.jpg`
- Build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260623002243.xcresult`
- Unit result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260623002439.xcresult`

Verification:
- `git diff --check`: passed.
- Static design scans from `docs/design-audit-playbook.md`: no new critical hits; remaining hits are expected domain acronyms, design-token definitions, and user-customizable category colors.
- `LANE_TIMEOUT_SECONDS=600 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- XcodeBuildMCP `build_run_sim` on `LandlordHours iPhone 17 Pro Max iOS 27`: passed.
- `LANE_TIMEOUT_SECONDS=900 ./ci_scripts/test_xcode27_lane.sh unit`: passed, 87 / 87.

Notes:
- XcodeBuildMCP launch logs for this MCP run wrote to its default internal `~/Library/Developer/XcodeBuildMCP/...` workspace even though the project lane build/test result bundles and DerivedData used the SSD-backed paths. Treat this as tooling-lane drift to clean up before unattended overnight runs.

### 2026-06-23 - Login Landing Screen Rework

Problem:
- The logged-out first-impression screen had been missed in the previous polish pass.
- It read like a utility explainer instead of a sign-up landing screen: generic icons, too much explanatory text, boxed feature rows, and weak emotional pull.

Outcome:
- Replaced the feature-list card with a more expressive landing-style hero moment.
- Cut the copy to one promise and one supporting line: `Never lose a landlord hour.`
- Added a code-native flowing hour trail and compact proof chips for voice, hours, property, and report-readiness.
- Preserved real product meaning without returning to generic icon rows.
- Verified both light and dark appearances on the dedicated iPhone 17 Pro Max iOS 27 simulator.

Evidence:
- Light screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/login-polish-20260623/login-light-r3-landing.jpg`
- Dark screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/login-polish-20260623/login-dark-r3-landing.jpg`
- Build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260623003728.xcresult`

Verification:
- `git diff --check`: passed.
- `LANE_TIMEOUT_SECONDS=600 ./ci_scripts/test_xcode27_lane.sh build`: passed.
- XcodeBuildMCP fresh logged-out launch: passed after uninstalling the simulator app to clear auth defaults.

### 2026-06-23 - Login Landing Screen R4 Copy And Product Moment

Problem:
- The r3 landing pass was cleaner than the old feature-list screen, but still did not sell the app hard enough as a first impression.
- The proof moment had too many small labels and the headline was more defensive than aspirational.

Outcome:
- Rewrote the main promise to `Turn property work into tax-ready hours.`
- Tightened the supporting line to `Speak, type, or tap. LandlordHours keeps the record ready for review.`
- Rebuilt the central proof moment around a single believable entry: `Porch repair`, `Oak Street • Today`, `1.0h`, `Repairs`.
- Renamed `Register` to `Create account` for clearer conversion intent.
- Added availability-gated Liquid Glass treatment to the landing proof panel and proof chips while keeping iOS 17 fallback behavior.
- Removed the obsolete boxed `welcomeGlass` helper from the previous direction.

Evidence:
- Light screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/login-polish-20260623/login-light-r4-after.png`
- Dark screenshot: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/login-polish-20260623/login-dark-r4-after.png`
- Build result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/login-polish-r4-build.xcresult`
- Full test result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/login-polish-r4-unit.xcresult`

Verification:
- `DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer xcodebuild -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj -scheme LandlordHours -destination 'id=B119FCEA-3C7B-4022-A57E-28357879F07D' -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27 -resultBundlePath /Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/login-polish-r4-build.xcresult build-for-testing`: passed.
- `DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer xcodebuild -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj -scheme LandlordHours -destination 'id=B119FCEA-3C7B-4022-A57E-28357879F07D' -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27 -resultBundlePath /Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/login-polish-r4-unit.xcresult test`: passed, 87 unit tests and 11 UI tests.
- `git diff --check`: passed.
- Fresh logged-out light and dark simulator screenshots captured after reinstalling the app on `LandlordHours iPhone 17 Pro Max iOS 27`.
