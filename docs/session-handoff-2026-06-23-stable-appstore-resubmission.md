# LandlordHours Stable App Store Resubmission Handoff

Date: 2026-06-23
Project: `/Users/brian/Projects/LandlordHours`
Branch before merge: `codex/landlordhours-voice-logging-ios27`

## Current Decision

Use Xcode 26.5 for the App Store release artifact.

Keep Xcode 27 beta as the forward-looking development/test lane, but do not submit an Xcode 27 / iOS 27 SDK build for App Review until Apple explicitly supports that path for App Store release. The current Xcode 27 IPA uploaded successfully through Transporter/Fastlane, but it did not become an eligible App Store build and could not be attached to version `1.0.3`.

## Release State

- App Store Connect app ID: `6759508794`
- Bundle ID: `com.openclaw.landlordhours`
- Prepared App Store version: `1.0.3`
- Current App Store version state from API: `PREPARE_FOR_SUBMISSION`
- Current selected build on version `1.0.3`: none (`/appStoreVersions/<id>/build` returned `data: null`)
- Review information exists and is populated in App Store Connect.
- App Store screenshots remain in `appstore-screenshots/` and should be kept for metadata upload.

## Why The Xcode 27 Upload Was Not Submitted

The uploaded IPA was verified as:

- `CFBundleIdentifier`: `com.openclaw.landlordhours`
- `CFBundleShortVersionString`: `1.0.3`
- `CFBundleVersion`: `202606230116`
- `DTXcode`: `2700`
- `DTSDKName`: `iphoneos27.0`
- `DTPlatformVersion`: `27.0`
- `MinimumOSVersion`: `17.0`

Fastlane/Transporter reported the package upload as successful, but App Store Connect's build API did not list the June 23 build as an available App Store build. The `1.0.3` app version had no selected build, and the new `reviewSubmissions` API returned Apple server errors:

- `GET /reviewSubmissions`: `500 UNEXPECTED_ERROR`
- `POST /reviewSubmissions`: `500 UNEXPECTED_ERROR`

The likely root cause is that Xcode 27 beta / iOS 27 SDK builds are currently suitable for TestFlight testing but not App Store production review. The actionable blocker is no eligible build attached to version `1.0.3`.

## Stable Xcode 26 Readiness

Stable toolchain:

- Xcode path: `/Volumes/Home/Applications/Xcode.app/Contents/Developer`
- Xcode version: Xcode 26.5, build `17F42`
- iOS SDK: iOS 26.5

The current codebase compiled successfully with stable Xcode 26.5 using the iOS 26.5 simulator SDK:

```bash
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project LandlordHours.xcodeproj \
  -scheme LandlordHours \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode26-stable-check \
  build
```

Result: `BUILD SUCCEEDED`.

This means the current iOS 27-facing polish is sufficiently availability-gated to compile with the stable iOS 26.5 SDK.

## Storage Cleanup Completed

Internal drive was low on space. Cleanup performed:

- Deleted generated UI evidence screenshots: `docs/e2e-visual-runs/`
- Deleted stale LandlordHours iOS 27 simulator device:
  - Name: `LandlordHours iPhone 17 Pro Max iOS 27`
  - UUID: `B119FCEA-3C7B-4022-A57E-28357879F07D`
- Deleted stale LandlordHours DerivedData:
  - `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27`
  - `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27-fastlane`
  - `/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode26-stable-check`
- Pruned stale XcodeBuildMCP result bundles for this project.
- Restored `tmp` as a symlink to SSD-backed storage:
  - `tmp -> /Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours/tmp`

Free space after cleanup:

- Internal `/`: about `20Gi` free
- `/Volumes/Home`: about `3.5Ti` free

Do not move or symlink CoreSimulator devices. CoreSimulator remains internal by design.

## Stable Release Build Pattern

Use a separate stable lane so artifacts do not collide with Xcode 27 development output:

```bash
RUN=LandlordHours-Xcode26-$(date +%Y%m%d%H%M%S)
DEVELOPER_DIR=/Volumes/Home/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project /Users/brian/Projects/LandlordHours/LandlordHours.xcodeproj \
  -scheme LandlordHours \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode26-release \
  -archivePath /Volumes/Home/XcodeStorage/Archives/${RUN}.xcarchive \
  MARKETING_VERSION=1.0.3 \
  CURRENT_PROJECT_VERSION=$(date +%Y%m%d%H%M) \
  DEVELOPMENT_TEAM=G68NLC3DA3 \
  -allowProvisioningUpdates \
  archive
```

After archive, export/upload with App Store Connect API key authentication. Do not print or commit secrets.

## Verification After Stable Upload

After uploading the Xcode 26.5 build, verify:

1. App Store Connect build list includes the new build.
2. Build attributes show:
   - `processingState`: `VALID`
   - `buildAudienceType`: `APP_STORE_ELIGIBLE`
   - `minOsVersion`: `17.0`
3. App Store version `1.0.3` has a build attached.
4. Review submission moves from `PREPARE_FOR_SUBMISSION` to `WAITING_FOR_REVIEW`.

## Next Resume Prompt

Resume from `/Users/brian/Projects/LandlordHours`.

Use stable Xcode 26.5 for App Store release:

1. Confirm branch is `main` and includes the latest LandlordHours polish work.
2. Confirm `tmp` is still the SSD symlink.
3. Build/archive with `/Volumes/Home/Applications/Xcode.app/Contents/Developer`.
4. Upload the Xcode 26.5 / iOS 26.5 SDK build to App Store Connect for version `1.0.3`.
5. Verify the new build appears as `APP_STORE_ELIGIBLE`.
6. Attach it to version `1.0.3`.
7. Submit version `1.0.3` for App Review.
8. Do not use the Xcode 27 beta IPA for App Review until Apple supports that release path.
