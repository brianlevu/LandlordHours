# LandlordHours Xcode 27 Readiness Handoff

Date: 2026-06-22
Project: `/Users/brian/Projects/LandlordHours`

## Executive Summary

LandlordHours is the active Swift/SwiftUI iOS app, not the old non-Swift LandlordHouse implementation.

The project is ready to be validated under Xcode 27 beta after the local developer environment is upgraded, but it has not yet been compiled with Xcode 27 locally. Current verification passed on Xcode 26.5 with the iOS 26.5 SDK.

Do not raise the minimum deployment target to iOS 27 without explicit approval. Keep the current broad device support and add iOS 27-only features behind availability checks.

## Current Local Toolchain

- Selected developer directory: `/Volumes/Home/Applications/Xcode.app/Contents/Developer`
- Current Xcode: Xcode 26.5, build 17F42
- Current SDKs installed: iOS 26.5 and iOS Simulator 26.5
- Current simulator used by XcodeBuildMCP: iPhone 17, iOS 26.5
- macOS: 26.5.1, arm64
- XcodeGen: 2.45.4

Apple's release feed lists Xcode 27 beta and iOS 27 beta as available on June 8, 2026. Apple Xcode 27 beta release notes state that Xcode 27 beta requires macOS Tahoe 26.4 or later. This machine satisfies that OS requirement, but Xcode 27 beta is not currently selected or installed as the active developer directory.

Sources:
- https://developer.apple.com/news/releases/
- https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes

## Project Type And Build System

- App type: native iOS application
- Language/UI: Swift and SwiftUI
- Architecture: MVVM-style app state through `AppViewModel`
- Build system source of truth: XcodeGen `project.yml`
- Generated project: `LandlordHours.xcodeproj`
- Scheme: `LandlordHours`
- Package dependencies:
  - `lucide-icons-swift` from `https://github.com/JakubMazur/lucide-icons-swift.git`, version `0.575.0+`

The project should continue to be edited through source files and `project.yml`, then regenerated with XcodeGen when target membership or build settings change.

## App Targets

From `project.yml`:

- `LandlordHours`
  - Type: iOS application
  - Bundle ID: `com.openclaw.landlordhours`
  - Deployment target: iOS 17.0
  - Swift version setting: 5.9
  - Team: `G68NLC3DA3`
  - Code signing: Automatic
  - Entitlements:
    - CloudKit container: `iCloud.com.openclaw.landlordhours`
    - iCloud services: CloudKit
    - Sign in with Apple
- `LandlordHoursTests`
  - Type: iOS unit test bundle
  - Includes `LandlordHours.storekit` as a test resource
- `LandlordHoursUITests`
  - Type: iOS UI test bundle
  - Depends on `LandlordHours`

## TestFlight And App Store Readiness

The repo includes Fastlane lanes for distribution:

- `fastlane beta`: builds and uploads to TestFlight
- `fastlane release`: builds and uploads App Store metadata/screenshots without submitting for review
- `fastlane submit_review`: submits an already-prepared App Store version for review
- `fastlane update_screenshots`: updates App Store screenshots

Current release setup signals:

- App identifier: `com.openclaw.landlordhours`
- Team ID: `G68NLC3DA3`
- Export method: `app-store`
- Automatic signing is configured.
- App Store Connect API key material is expected to stay local under the user's private key storage; do not commit key filenames or key contents.
- In-app purchase product ID used by code/tests: `com.openclaw.landlordhours.pro`.

Before a real upload, verify the App Store Connect key still exists locally and that automatic signing can create or refresh App Store profiles under the selected Xcode version.

## Verification Completed

Command path:

- XcodeBuildMCP defaults:
  - Project: `/Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj`
  - Scheme: `LandlordHours`
  - Simulator: `iPhone 17`
  - Bundle ID: `com.openclaw.landlordhours`

Result:

- `test_sim(progress: false)` passed
- 70 tests passed
- 0 failed
- 0 skipped
- No warnings reported by XcodeBuildMCP

Artifacts:

- Build log: `/Users/brian/Library/Developer/XcodeBuildMCP/workspaces/LandlordHours-2cd7c93f013b/logs/test_sim_2026-06-22T07-52-57-868Z_pid98941_9ca4093c.log`
- Result bundle: `/Users/brian/Library/Developer/XcodeBuildMCP/workspaces/LandlordHours-2cd7c93f013b/result-bundles/test_sim_2026-06-22T07-52-57-869Z_pid98941_80c2c99a.xcresult`

## Legacy LandlordHouse Check

Within `/Users/brian/Projects`, the landlord-related scan found only the active Swift project:

- `/Users/brian/Projects/LandlordHours`

No separate old non-Swift LandlordHouse folder was found in that scope during this audit.

Cleanup rule for future sessions:

If an older non-Swift LandlordHouse or LandlordHours implementation is found elsewhere, do not continue improving it. Identify it as legacy and list:

- exact folder path
- technology stack
- whether it contains unique assets, copy, data, screenshots, or release metadata worth preserving
- recommended action: archive or delete

Then ask Brian for explicit confirmation before deleting anything. Never delete `/Users/brian/Projects/LandlordHours`.

## What Changed In This Audit

Added this handoff document:

- `/Users/brian/Projects/LandlordHours/docs/session-handoff-2026-06-22-xcode27-readiness.md`

No project code, signing settings, deployment target, package versions, storage paths, or generated project files were changed by this audit.

## Xcode 27 Readiness Assessment

Ready:

- Native Swift/SwiftUI app structure
- XcodeGen-managed project
- iOS 17.0 deployment target, so iOS 27 is additive rather than required
- Current simulator test suite passes
- StoreKit local test coverage exists
- CloudKit and Sign in with Apple entitlements are declared
- Fastlane distribution lanes exist

Needs post-upgrade validation:

- Install/select Xcode 27 beta.
- Confirm `xcodebuild -version` reports Xcode 27 beta.
- Confirm `xcodebuild -showsdks` includes iOS 27 and iOS Simulator 27.
- Install an iOS 27 simulator runtime if it is not bundled or not visible.
- Regenerate the project only if XcodeGen output changes are required.
- Run the full unit/UI test suite on an iOS 27 simulator.
- Run a compile/archive check with app-store signing after confirming credentials/profiles.
- Review any new Xcode 27 Swift warnings before adding iOS 27-specific features.

## Xcode 27 Verification Update

Updated: 2026-06-22 01:59 America/Los_Angeles

Current selected Xcode is now Xcode 27 beta:

- Developer directory: `/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer`
- Xcode version: Xcode 27.0, build 27A5194q
- SDKs: iOS 27.0 and iOS Simulator 27.0 are installed
- iOS 27 runtime: `iOS 27.0 (24A5355p)` is Ready

SSD-backed development paths verified:

- `~/Library/Developer/Xcode/DerivedData` -> `/Volumes/Home/XcodeStorage/DerivedData`
- `~/Library/Developer/Xcode/Archives` -> `/Volumes/Home/XcodeStorage/Archives`
- `~/Library/Developer/Xcode/iOS DeviceSupport` -> `/Volumes/Home/XcodeStorage/DeviceSupport/iOS`
- `~/Library/Developer/XcodeBuildMCP` -> `/Volumes/Home/XcodeStorage/XcodeBuildMCP`

CoreSimulator device storage remains internal by design:

- `~/Library/Developer/CoreSimulator/Devices`

Verification outputs for this app used explicit SSD paths:

- DerivedData: `/Volumes/Home/XcodeStorage/LandlordHours-Xcode27/DerivedData`
- Build log: `/Volumes/Home/XcodeStorage/LandlordHours-Xcode27/logs/build-for-testing-20260622014404.log`
- Full test log: `/Volumes/Home/XcodeStorage/LandlordHours-Xcode27/logs/test-without-building-20260622014910.log`
- Full test result bundle: `/Volumes/Home/XcodeStorage/LandlordHours-Xcode27/result-bundles/test-without-building-20260622014910.xcresult`
- Unit test log: `/Volumes/Home/XcodeStorage/LandlordHours-Xcode27/logs/unit-tests-20260622015149.log`
- Unit test result bundle: `/Volumes/Home/XcodeStorage/LandlordHours-Xcode27/result-bundles/unit-tests-20260622015149.xcresult`
- UI test log: `/Volumes/Home/XcodeStorage/LandlordHours-Xcode27/logs/ui-tests-20260622015431.log`
- UI test result bundle: `/Volumes/Home/XcodeStorage/LandlordHours-Xcode27/result-bundles/ui-tests-20260622015431.xcresult`

Results:

- `build-for-testing` succeeded under Xcode 27 beta on an iOS 27 simulator.
- Unit tests succeeded: 65 passed, 0 failed.
- Full test run did not complete because the iOS 27 simulator failed to launch the UI test runner on `NeuRest Dev iPhone 17 iOS 27` with `Invalid connectionUUID specified`.
- A fresh simulator, `LandlordHours Test iPhone iOS 27`, launched the UI test runner but the runner crashed while bootstrapping before test methods reported results.

Current blocker:

- App build and unit tests are Xcode 27-ready.
- UI tests need a follow-up iOS 27 simulator/XCTest runner stability pass. This appears to be simulator-runner level, not a failing UI assertion.

Warnings to track:

- `AppleSignIn.swift` has Xcode 27 warnings around availability/result-builder behavior in the login action view.
- StoreKitTest emits a deprecation warning from Apple's SDK header for `SKPaymentTransactionState`.
- AppIntents metadata extraction logs "no AppIntents.framework dependency found"; this is informational for the current target.

## Dedicated Xcode 27 Lane Update

Updated: 2026-06-22 02:22 America/Los_Angeles

Use the project-specific Xcode 27 lane documented at:

- `/Users/brian/Projects/LandlordHours/docs/xcode27-lane.md`

Current lane:

- Simulator: `LandlordHours iPhone 17 Pro Max iOS 27`
- Simulator UUID: `B119FCEA-3C7B-4022-A57E-28357879F07D`
- DerivedData: `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27`
- Results: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results`
- Logs/screenshots/tmp: `/Users/brian/Projects/LandlordHours/tmp/xcode27`

Latest lane verification:

- `build-for-testing` succeeded with Xcode 27 beta.
- Build log: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs/lane-build-for-testing-20260622022215.log`
- Result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622022215.xcresult`

Do not use the shared/generic `Codex iPhone 17 Pro iOS 27.0` simulator for active LandlordHours work.

## Post-Restart Dedicated Testing Path

Updated: 2026-06-22 02:51 America/Los_Angeles

The dedicated lane is now encoded in project-local files:

- `.xcodebuildmcp/config.yaml` points to `LandlordHours iPhone 17 Pro Max iOS 27` (`B119FCEA-3C7B-4022-A57E-28357879F07D`), not the shared Codex simulator.
- `ci_scripts/test_xcode27_lane.sh` is the canonical local test runner.
- `ci_scripts/capture_iphone_e2e_visuals.sh` defaults to the same Xcode 27 simulator and SSD DerivedData path.
- `.gitignore` ignores local `tmp/`, generated `.ipa`, and generated `.app.dSYM.zip` artifacts.

Verification after forced restart:

- `./ci_scripts/test_xcode27_lane.sh doctor` passed.
- `LANE_TIMEOUT_SECONDS=120 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Latest build log: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs/lane-build-for-testing-20260622025107.log`
- Latest result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622025107.xcresult`

Use these commands for future sessions:

```sh
./ci_scripts/test_xcode27_lane.sh doctor
./ci_scripts/test_xcode27_lane.sh build
./ci_scripts/test_xcode27_lane.sh unit
./ci_scripts/test_xcode27_lane.sh ui
./ci_scripts/test_xcode27_lane.sh full
```

If XCTest hangs under the iOS 27 beta runner, use a bounded run:

```sh
LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh unit
```

## Latest Release Gate

Updated: 2026-06-22 23:00 America/Los_Angeles

Current automated status:

- Xcode 27 beta build gate: passed.
- Unit test gate: passed, 85 / 85 after system-surface hardening.
- Full UI test gate: passed, 10 / 10.
- Targeted Engagement Lab system-surface UI gate: passed, 1 / 1.
- Physical-device iOS 27 build gate: passed on `BLV-Phone`.
- Release archive gate: passed.
- App Store Connect export dry run: passed and produced an IPA without uploading or submitting.
- Privacy manifest: added and packaged in the app bundle.
- Widget extension: embedded in the app bundle.
- Lock Screen accessory widget families: added for circular, rectangular, and inline.
- Dynamic Island preview/action path: added for the active timer review flow.
- Local notification action categories: added for track, calendar review, export, reports, property setup, and timer review.
- App Intents metadata: generated in the app bundle.
- Fastlane build/output paths: moved to the LandlordHours SSD-backed lane instead of shared `/tmp`.

Evidence:

- Latest build result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622224343.xcresult`
- Latest unit result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622224511.xcresult`
- Targeted Engagement Lab UI result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-engagement-lab-r3-20260622225608.xcresult`
- Release-gate build result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622214920.xcresult`
- Release-gate unit result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622214112.xcresult`
- UI result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-full-patched-20260622214920.xcresult`
- Device build result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-20260622215713.xcresult`
- Archive: `/Volumes/Home/XcodeStorage/Archives/LandlordHours-20260622215945.xcarchive`
- Export: `/Volumes/Home/XcodeStorage/Archives/LandlordHours-20260622215945-export/LandlordHours.ipa`

Remaining manual checks:

- Do not upload to TestFlight or submit for App Review without Brian's explicit approval.
- Run real-device hands-on QA for Siri phrases, Shortcuts discovery, widgets, Live Activity / Dynamic Island, notification tap routing under Focus modes, and voice logging.
- Validate StoreKit product lookup and purchase/restore behavior through sandbox or TestFlight.
- Investigate the two non-fatal SwiftUI `Invalid frame dimension (negative or non-finite)` warnings in the final UI result if visible layout issues appear.

## Recommended Post-Upgrade Commands

After Xcode 27 beta is installed and selected:

```sh
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
xcrun simctl list runtimes
xcodegen generate
```

Then use XcodeBuildMCP:

1. `session_show_defaults`
2. If defaults still point to `/Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj`, scheme `LandlordHours`, and an iOS 27 simulator, run `test_sim(progress: false)`.
3. If the default simulator is still iOS 26.5, switch the simulator default before treating the app as iOS 27-validated.

For distribution validation:

```sh
MARKETING_VERSION=1.0.3 fastlane ios beta
```

Only run a real TestFlight upload when Brian explicitly wants it. App Store review submission must remain explicit.

## Roadmap After Xcode 27 Upgrade

1. Validate current app under Xcode 27 beta and iOS 27 simulator.
2. Continue the design improvement roadmap:
   - Properties screen polish
   - Onboarding/first-run capture
   - Reports inset/detail pass
   - Settings IA and upgrade presentation polish
3. Add Apple-native voice/time entry support where practical:
   - Prefer built-in Apple speech/dictation and local parsing first.
   - Keep API-backed parsing optional, not required for core logging.
   - Gate any iOS 27-only APIs with availability checks.
4. Keep deployment target at iOS 17.0 unless Brian explicitly approves a strategic bump.

## Exact Resume Prompt

```markdown
We are continuing LandlordHours after the Xcode 27 beta environment setup.

Project:
`/Users/brian/Projects/LandlordHours`

Read first:
- `/Users/brian/Projects/LandlordHours/AGENTS.md`
- `/Users/brian/Projects/LandlordHours/docs/session-handoff-2026-06-22-xcode27-readiness.md`
- `/Users/brian/Projects/LandlordHours/docs/design-improvement-backlog.md`

First verify:
- `xcode-select -p`
- `xcodebuild -version`
- `xcodebuild -showsdks`
- iOS 27 simulator availability

Then use XcodeBuildMCP:
1. `session_show_defaults`
2. Update defaults only if needed.
3. Run the full simulator test suite on iOS 27.

Do not raise the minimum deployment target to iOS 27 unless I explicitly approve it. Use availability checks for iOS 27-only APIs.

If Xcode 27 validation passes, continue the app roadmap. Prioritize Properties screen design polish unless I ask to start Apple-native voice/time entry first.
```
