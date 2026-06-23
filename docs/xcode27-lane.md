# LandlordHours Xcode 27 Lane

Updated: 2026-06-23 07:35 America/Los_Angeles

Use this lane for LandlordHours Xcode 27 beta development. Do not use shared/generic Codex simulators, generic DerivedData, or shared result bundle locations for active work in this project.

## Project Identity

- App name: LandlordHours
- Project: `/Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj`
- Scheme: `LandlordHours`
- Widget scheme: `LandlordHoursWidgetExtension`
- App bundle ID: `com.openclaw.landlordhours`
- Widget bundle ID: `com.openclaw.landlordhours.widget`
- Unit test bundle ID: `com.openclaw.landlordhours.tests`
- UI test bundle ID: `com.openclaw.landlordhours.uitests`
- Shared App Group for widget state: `group.com.openclaw.landlordhours`
- System surfaces: App Intents, App Shortcuts, WidgetKit widgets, and ActivityKit timer Live Activity.
- Current system-surface scope: Home Screen widgets, Lock Screen accessory widgets, local notification actions, App Intents/App Shortcuts, and active-timer Live Activity / Dynamic Island.

Signing note:

- The App Group entitlement is now present locally in `LandlordHours.entitlements` and `LandlordHoursWidget.entitlements`.
- For App Store continuity, keep this existing App Store Connect namespace even if public-facing company/support copy uses Altai Ventures.
- Before real-device, TestFlight, or App Store signing, register/enable Sign in with Apple, iCloud container, and App Group for the existing app identifiers in Apple Developer.

## Xcode

- Xcode 27 beta: `/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer`
- Stable fallback Xcode: `/Volumes/Home/Applications/Xcode.app/Contents/Developer`

Prefer setting `DEVELOPER_DIR` per command instead of relying on global state:

```bash
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer
```

## Dedicated Simulator

- Simulator name: `LandlordHours iPhone 17 Pro Max iOS 27`
- Simulator UUID: recreate before next Xcode 27 UI pass
- Runtime: iOS 27.0
- Device type: iPhone 17 Pro Max

Do not use `Codex iPhone 17 Pro iOS 27.0` for active LandlordHours work. CoreSimulator device storage stays internal at `~/Library/Developer/CoreSimulator/Devices`; do not symlink or move it.

Storage cleanup note:

- The previous dedicated simulator `B119FCEA-3C7B-4022-A57E-28357879F07D` was deleted on 2026-06-23 to reclaim internal-drive space.
- Recreate it only when Xcode 27 UI validation resumes:

```bash
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
xcrun simctl create "LandlordHours iPhone 17 Pro Max iOS 27" "iPhone 17 Pro Max" "iOS 27.0"
```

## SSD Storage

- DerivedData: `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27`
- XcodeBuildMCP workspace/results: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours`
- Result bundles: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results`
- Archives: `/Volumes/Home/XcodeStorage/Archives`
- Fastlane output: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/fastlane`
- Lane logs/screenshots/tmp: `/Users/brian/Projects/LandlordHours/tmp/xcode27`
- Lane logs: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs`
- Lane screenshots: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots`

Storage note:

- `/Users/brian/Projects/LandlordHours/tmp/xcode27` is a symlink to `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/tmp/xcode27`.
- Keep this symlink. The internal drive hit `No space left on device` when logs/screenshots were stored directly under the project checkout.
- Do not move keychain, signing, provisioning, or CoreSimulator device storage.

System-level links verified:

- `~/Library/Developer/Xcode/DerivedData` -> `/Volumes/Home/XcodeStorage/DerivedData`
- `~/Library/Developer/Xcode/Archives` -> `/Volumes/Home/XcodeStorage/Archives`
- `~/Library/Developer/Xcode/iOS DeviceSupport` -> `/Volumes/Home/XcodeStorage/DeviceSupport/iOS`
- `~/Library/Developer/XcodeBuildMCP` -> `/Volumes/Home/XcodeStorage/XcodeBuildMCP`

## Command Patterns

Preferred local runner:

```bash
./ci_scripts/test_xcode27_lane.sh doctor
./ci_scripts/test_xcode27_lane.sh build
./ci_scripts/test_xcode27_lane.sh unit
./ci_scripts/test_xcode27_lane.sh ui
./ci_scripts/test_xcode27_lane.sh full
```

The runner pins:

- Xcode: `/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer`
- Simulator: `LandlordHours iPhone 17 Pro Max iOS 27` (`B119FCEA-3C7B-4022-A57E-28357879F07D`)
- DerivedData: `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27`
- Results: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results`
- Logs: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs`
- Screenshots: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots`
- Backing tmp path: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/tmp/xcode27`

Build for testing:

```bash
RUN=lane-build-for-testing-$(date +%Y%m%d%H%M%S)
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
xcodebuild \
  -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj \
  -scheme LandlordHours \
  -destination 'id=B119FCEA-3C7B-4022-A57E-28357879F07D' \
  -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27 \
  -resultBundlePath /Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/${RUN}.xcresult \
  build-for-testing \
  2>&1 | tee /Users/brian/Projects/LandlordHours/tmp/xcode27/logs/${RUN}.log
```

Unit tests only:

```bash
RUN=lane-unit-test-$(date +%Y%m%d%H%M%S)
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
xcodebuild \
  -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj \
  -scheme LandlordHours \
  -destination 'id=B119FCEA-3C7B-4022-A57E-28357879F07D' \
  -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27 \
  -resultBundlePath /Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/${RUN}.xcresult \
  -only-testing:LandlordHoursTests \
  test-without-building \
  2>&1 | tee /Users/brian/Projects/LandlordHours/tmp/xcode27/logs/${RUN}.log
```

Full test suite:

```bash
RUN=lane-full-test-$(date +%Y%m%d%H%M%S)
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
xcodebuild \
  -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj \
  -scheme LandlordHours \
  -destination 'id=B119FCEA-3C7B-4022-A57E-28357879F07D' \
  -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27 \
  -resultBundlePath /Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/${RUN}.xcresult \
  test \
  2>&1 | tee /Users/brian/Projects/LandlordHours/tmp/xcode27/logs/${RUN}.log
```

Release archive:

```bash
RUN=LandlordHours-$(date +%Y%m%d%H%M%S)
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
xcodebuild \
  -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj \
  -scheme LandlordHours \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27 \
  -archivePath /Volumes/Home/XcodeStorage/Archives/${RUN}.xcarchive \
  archive
```

App Store Connect export dry run:

```bash
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
xcodebuild -exportArchive \
  -archivePath /Volumes/Home/XcodeStorage/Archives/LandlordHours-20260622215945.xcarchive \
  -exportPath /Volumes/Home/XcodeStorage/Archives/LandlordHours-20260622215945-export \
  -exportOptionsPlist /Users/brian/Projects/LandlordHours/tmp/xcode27/ExportOptions-app-store-connect.plist \
  -allowProvisioningUpdates
```

This verifies packaging/signing locally. It does not upload to TestFlight or submit the app.

App Store Connect upload without App Review submission:

```bash
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
MARKETING_VERSION=1.0.3 \
fastlane ios release
```

If App Store Connect screenshot processing stalls after the IPA has already exported, verify the IPA version and upload only the binary:

```bash
python3 - <<'PY'
import zipfile, plistlib
ipa = "/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/fastlane/LandlordHours.ipa"
with zipfile.ZipFile(ipa) as z:
    plist_name = next(n for n in z.namelist() if n.startswith("Payload/") and n.endswith(".app/Info.plist"))
    info = plistlib.loads(z.read(plist_name))
print(info["CFBundleIdentifier"], info["CFBundleShortVersionString"], info["CFBundleVersion"])
PY

DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
APP_VERSION=1.0.3 \
fastlane ios upload_binary_only
```

This uploads to the prepared App Store Connect version but does not submit for App Review.

App Store review note:

- Do not submit the Xcode 27 beta / iOS 27 SDK IPA for App Review until Apple explicitly supports that path for App Store production release.
- On 2026-06-23, the Xcode 27 IPA uploaded but did not appear as an eligible App Store build. Version `1.0.3` had no selected build, and the review-submission API returned Apple `500 UNEXPECTED_ERROR`.
- Use the stable Xcode 26.5 release path documented in `docs/session-handoff-2026-06-23-stable-appstore-resubmission.md` for App Store review.

## Verification Status

Latest lane verification:

- App Store Connect version `1.0.3` upload completed on 2026-06-23 without App Review submission.
- Corrected IPA: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/fastlane/LandlordHours.ipa`
- Corrected IPA version/build: `1.0.3` / `202606230116`
- Metadata/screenshots upload log: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs/appstore-release-20260623011007.log`
- Corrected binary-only upload log: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs/appstore-binary-only-20260623013127-v103.log`
- `LANE_TIMEOUT_SECONDS=900 ./ci_scripts/test_xcode27_lane.sh build` passed with Xcode 27 beta after Lock Screen widget, Dynamic Island action, notification action, and Engagement Lab QA hardening.
- Build result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622224343.xcresult`
- `LANE_TIMEOUT_SECONDS=900 ./ci_scripts/test_xcode27_lane.sh unit` passed, confirmed from xcresult as 85 passed / 0 failed.
- Unit result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622224511.xcresult`
- Targeted Engagement Lab UI run passed, 1 passed / 0 failed, covering widget, Live Activity / Dynamic Island, and Siri / Shortcut preview routes.
- UI result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-engagement-lab-r3-20260622225608.xcresult`
- Real-device manual validation is still required for placing widgets, Lock Screen accessories, Dynamic Island expansion/taps, Focus-mode notification behavior, and Siri phrase discovery.

Previous release-gate verification:

- `LANE_TIMEOUT_SECONDS=900 ./ci_scripts/test_xcode27_lane.sh build` passed with Xcode 27 beta.
- Build result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622214920.xcresult`
- `LANE_TIMEOUT_SECONDS=900 ./ci_scripts/test_xcode27_lane.sh unit` passed, confirmed from xcresult as 82 passed / 0 failed.
- Unit result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622214112.xcresult`
- Full UI run on `LandlordHours iPhone 17 Pro Max iOS 27` passed, 10 passed / 0 failed.
- UI result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-full-patched-20260622214920.xcresult`
- Physical-device build against `BLV-Phone` on iOS 27 passed.
- Device result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-20260622215713.xcresult`
- Release archive passed.
- Archive: `/Volumes/Home/XcodeStorage/Archives/LandlordHours-20260622215945.xcarchive`
- App Store Connect export dry run passed and produced an IPA without upload/submission.
- Export: `/Volumes/Home/XcodeStorage/Archives/LandlordHours-20260622215945-export/LandlordHours.ipa`
- Privacy manifest is packaged in the app bundle.
- App Intents metadata is generated in the app bundle.
- Widget extension is embedded in the app bundle.

Earlier lane verification:

- `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build` passed with Xcode 27 beta.
- Build result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622045041.xcresult`
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, confirmed from xcresult as 66 passed / 0 failed.
- Unit result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622045117.xcresult`
- Direct UI test run emitted a clean pass summary: 5 passed / 0 failed.
- UI log: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs/direct-ui-test-202606220455.log`
- Dark + accessibility-large visual matrix completed with 17 screenshots.
- Visual evidence: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_roadmap-dark-a11y-final2`

Post-restart lane hardening:

- `.xcodebuildmcp/config.yaml` now points to `LandlordHours iPhone 17 Pro Max iOS 27`, not the shared `Codex iPhone 17 Pro iOS 27.0` simulator.
- `ci_scripts/test_xcode27_lane.sh` is the canonical project-local build/test entry point.
- `ci_scripts/test_xcode27_lane.sh` has a timeout guard through `LANE_TIMEOUT_SECONDS` so stuck Xcode 27 XCTest launches do not occupy the lane indefinitely.
- `ci_scripts/capture_iphone_e2e_visuals.sh` now defaults to the same Xcode 27 lane and writes screenshots under `tmp/xcode27/screenshots`.
- `.gitignore` ignores local lane artifacts, generated IPA files, and dSYM zip files so they do not pollute future sessions.

Widget milestone verification:

- `DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer xcodebuild -list -project LandlordHours.xcodeproj` passed and lists `LandlordHoursWidgetExtension`.
- `plutil -lint Sources/App/Info.plist Sources/Widget/Info.plist LandlordHours.entitlements LandlordHoursWidget.entitlements` passed.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build` passed with the widget extension embedded.
- Build result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622172910.xcresult`
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 82 / 82.
- Unit result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622172942.xcresult`

Live Activity milestone verification:

- `NSSupportsLiveActivities` is enabled in `Sources/App/Info.plist`.
- `LandlordHoursTimerAttributes.swift` is compiled into both `LandlordHours` and `LandlordHoursWidgetExtension`.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build` passed with the ActivityKit widget extension.
- Build result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622173410.xcresult`
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 82 / 82.
- Unit result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622173436.xcresult`
- Remaining validation: real-device Lock Screen and Dynamic Island QA, because Simulator is not a complete signal for Live Activity feel.

Notification tap routing verification:

- Engagement notification taps now route through `AppIntentNavigationRequest.pendingDestinationKey`, matching App Intents and widget deep links.
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh build` passed.
- Build result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622173637.xcresult`
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, 82 / 82.
- Unit result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622173718.xcresult`
- Remaining validation: real-device notification tap and Focus-mode behavior.

System-surface hardening verification:

- Lock Screen widget families are enabled for accessory circular, accessory rectangular, and accessory inline in `LandlordHoursWidgetExtension`.
- Dynamic Island expanded bottom region includes an app deep link to the timer/review path.
- Engagement notification categories now expose focused action buttons for track, calendar review, export, reports, property setup, and timer review.
- Engagement Lab supports direct surface launch through `-LHEngagementSurface widget`, `-LHEngagementSurface liveActivity`, and `-LHEngagementSurface siri`.
- Targeted UI test: `LandlordHoursUITests/LandlordHoursUITests/testEngagementLabSurfacesStayReviewable`.
- UI result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-ui-engagement-lab-r3-20260622225608.xcresult`

Real-device signing probe:

- Device destination found by Xcode: `BLV-Phone` (`00008140-001C682C0E7B001C`), iOS 27.0.
- `devicectl` reports `BLV-Phone` as available and paired.
- Command run:

```bash
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
xcodebuild \
  -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj \
  -scheme LandlordHours \
  -destination 'platform=iOS,id=00008140-001C682C0E7B001C' \
  -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27 \
  -resultBundlePath /Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-altai-20260622174951.xcresult \
  build
```

- Result: failed at provisioning before compilation.
- Result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-altai-20260622174951.xcresult`
- Exact blocker:
  - Provisioning profile for `com.openclaw.landlordhours` does not include App Groups, Sign in with Apple, or iCloud.
  - Provisioning profile for `com.openclaw.landlordhours` does not support `group.com.openclaw.landlordhours`.
  - Provisioning profile for `com.openclaw.landlordhours` does not support `iCloud.com.openclaw.landlordhours`.
  - Provisioning profile for `com.openclaw.landlordhours.widget` does not include App Groups.
  - Provisioning profile for `com.openclaw.landlordhours.widget` does not support `group.com.openclaw.landlordhours`.

Required Apple Developer action:

1. In Apple Developer Certificates, Identifiers & Profiles, open the app identifier `com.openclaw.landlordhours`.
2. Enable Sign in with Apple.
3. Enable iCloud / CloudKit and add/select `iCloud.com.openclaw.landlordhours`.
4. Enable App Groups and add/select `group.com.openclaw.landlordhours`.
5. Open the widget extension identifier `com.openclaw.landlordhours.widget`.
6. Enable App Groups and add/select the same `group.com.openclaw.landlordhours`.
7. Regenerate or refresh the affected development provisioning profiles in Xcode.
8. Rerun the real-device build command above.

Managed provisioning attempt:

- `xcodebuild -allowProvisioningUpdates` was also attempted after the continuity decision to keep the existing bundle IDs.
- Initial result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-altai-managed-20260622175445.xcresult`
- Initial result: failed before compilation because Xcode 27 reported `No Accounts: Add a new account in Accounts settings`.
- After signing into Xcode 27 Accounts, managed provisioning succeeded.
- Successful result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-altai-managed-20260622180549.xcresult`
- The earlier successful `lane-device-build-altai-managed-20260622180549.xcresult` verified Apple account access and managed provisioning, but it used the temporary Altai bundle IDs before the continuity decision.
- After restoring the existing App Store Connect namespace, real-device managed provisioning succeeded.
- Continuity result bundle: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-openclaw-managed-20260622182805.xcresult`
- Continuity command: `DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer xcodebuild -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj -scheme LandlordHours -destination 'platform=iOS,id=00008140-001C682C0E7B001C' -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27 -resultBundlePath /Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-device-build-openclaw-managed-20260622182805.xcresult -allowProvisioningUpdates build`
- Continuity result: `BUILD SUCCEEDED`.
- Signing used Team ID `G68NLC3DA3`, app profile `iOS Team Provisioning Profile: com.openclaw.landlordhours`, and widget profile `iOS Team Provisioning Profile: com.openclaw.landlordhours.widget`.

Known current blocker:

- Xcode 27 beta can keep the shell process attached after UI tests have already printed the pass summary. In the latest direct UI run, all 5 tests passed and the process was stopped manually only after the success output was written.
- Xcode 27 beta logs an Apple simulator accessibility warning about duplicate WebCore/WebKit accessibility classes during UI tests. It did not fail the test suite.

## Cleanup Notes

- It is safe to delete `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27` to force a clean lane rebuild.
- It is safe to delete old result bundles under `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results`.
- It is safe to delete old generated logs/screenshots under `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/tmp/xcode27` when they are no longer needed for evidence.
- It is safe to erase only the dedicated simulator with:

```bash
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
xcrun simctl erase B119FCEA-3C7B-4022-A57E-28357879F07D
```

- Do not delete or move signing/keychain material.
- Do not symlink `~/Library/Developer/CoreSimulator/Devices`.
