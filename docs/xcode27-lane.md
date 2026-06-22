# LandlordHours Xcode 27 Lane

Updated: 2026-06-22 02:51 America/Los_Angeles

Use this lane for LandlordHours Xcode 27 beta development. Do not use shared/generic Codex simulators, generic DerivedData, or shared result bundle locations for active work in this project.

## Project Identity

- App name: LandlordHours
- Project: `/Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj`
- Scheme: `LandlordHours`
- App bundle ID: `com.openclaw.landlordhours`
- Unit test bundle ID: `com.openclaw.landlordhours.tests`
- UI test bundle ID: `com.openclaw.landlordhours.uitests`

## Xcode

- Xcode 27 beta: `/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer`
- Stable fallback Xcode: `/Volumes/Home/Applications/Xcode.app/Contents/Developer`

Prefer setting `DEVELOPER_DIR` per command instead of relying on global state:

```bash
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer
```

## Dedicated Simulator

- Simulator name: `LandlordHours iPhone iOS 27`
- Simulator UUID: `C8B22181-D398-477F-91D3-ED67F1B8851C`
- Runtime: iOS 27.0
- Device type: iPhone 17 Pro

Do not use `Codex iPhone 17 Pro iOS 27.0` for active LandlordHours work. CoreSimulator device storage stays internal at `~/Library/Developer/CoreSimulator/Devices`; do not symlink or move it.

## SSD Storage

- DerivedData: `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27`
- XcodeBuildMCP workspace/results: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours`
- Result bundles: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results`
- Lane logs/screenshots/tmp: `/Users/brian/Projects/LandlordHours/tmp/xcode27`
- Lane logs: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs`
- Lane screenshots: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots`

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
- Simulator: `LandlordHours iPhone iOS 27` (`C8B22181-D398-477F-91D3-ED67F1B8851C`)
- DerivedData: `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27`
- Results: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results`
- Logs: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs`
- Screenshots: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots`

Build for testing:

```bash
RUN=lane-build-for-testing-$(date +%Y%m%d%H%M%S)
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
xcodebuild \
  -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj \
  -scheme LandlordHours \
  -destination 'id=C8B22181-D398-477F-91D3-ED67F1B8851C' \
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
  -destination 'id=C8B22181-D398-477F-91D3-ED67F1B8851C' \
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
  -destination 'id=C8B22181-D398-477F-91D3-ED67F1B8851C' \
  -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27 \
  -resultBundlePath /Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/${RUN}.xcresult \
  test \
  2>&1 | tee /Users/brian/Projects/LandlordHours/tmp/xcode27/logs/${RUN}.log
```

## Verification Status

Latest lane verification:

- `LANE_TIMEOUT_SECONDS=180 ./ci_scripts/test_xcode27_lane.sh build` passed with Xcode 27 beta.
- Build result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-build-for-testing-20260622045041.xcresult`
- `LANE_TIMEOUT_SECONDS=300 ./ci_scripts/test_xcode27_lane.sh unit` passed, confirmed from xcresult as 66 passed / 0 failed.
- Unit result: `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results/lane-unit-test-20260622045117.xcresult`
- Direct UI test run emitted a clean pass summary: 5 passed / 0 failed.
- UI log: `/Users/brian/Projects/LandlordHours/tmp/xcode27/logs/direct-ui-test-202606220455.log`
- Dark + accessibility-large visual matrix completed with 17 screenshots.
- Visual evidence: `/Users/brian/Projects/LandlordHours/tmp/xcode27/screenshots/e2e-visual-runs/2026-06-22_roadmap-dark-a11y-final2`

Post-restart lane hardening:

- `.xcodebuildmcp/config.yaml` now points to `LandlordHours iPhone iOS 27`, not the shared `Codex iPhone 17 Pro iOS 27.0` simulator.
- `ci_scripts/test_xcode27_lane.sh` is the canonical project-local build/test entry point.
- `ci_scripts/test_xcode27_lane.sh` has a timeout guard through `LANE_TIMEOUT_SECONDS` so stuck Xcode 27 XCTest launches do not occupy the lane indefinitely.
- `ci_scripts/capture_iphone_e2e_visuals.sh` now defaults to the same Xcode 27 lane and writes screenshots under `tmp/xcode27/screenshots`.
- `.gitignore` ignores local lane artifacts, generated IPA files, and dSYM zip files so they do not pollute future sessions.

Known current blocker:

- Xcode 27 beta can keep the shell process attached after UI tests have already printed the pass summary. In the latest direct UI run, all 5 tests passed and the process was stopped manually only after the success output was written.
- Xcode 27 beta logs an Apple simulator accessibility warning about duplicate WebCore/WebKit accessibility classes during UI tests. It did not fail the test suite.

## Cleanup Notes

- It is safe to delete `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27` to force a clean lane rebuild.
- It is safe to delete old result bundles under `/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/results`.
- It is safe to erase only the dedicated simulator with:

```bash
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer \
xcrun simctl erase C8B22181-D398-477F-91D3-ED67F1B8851C
```

- Do not delete or move signing/keychain material.
- Do not symlink `~/Library/Developer/CoreSimulator/Devices`.
