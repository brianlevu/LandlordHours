# LandlordHours Stable App Store Resubmission Handoff

Date: 2026-06-23
Project: `/Users/brian/Projects/LandlordHours`
Branch before merge: `codex/landlordhours-voice-logging-ios27`

## Current Decision

Use Xcode 26.5 for the App Store release artifact.

Keep Xcode 27 beta as the forward-looking development/test lane. The earlier June 23 App Store uploads did not become eligible because App Store Connect rejected the package's alternate-icon metadata, not because of a confirmed Xcode 27-only rejection.

## Release State

- App Store Connect app ID: `6759508794`
- Bundle ID: `com.openclaw.landlordhours`
- Prepared App Store version: `1.0.3`
- Current App Store version state from API: `PREPARE_FOR_SUBMISSION`
- Current selected build on version `1.0.3`: none until a newly processed build is attached (`/appStoreVersions/<id>/build` returned `data: null`)
- Review information exists and is populated in App Store Connect.
- App Store screenshots remain in `appstore-screenshots/` and should be kept for metadata upload.

## App Store Upload Failure Root Cause

The first June 23 Xcode 26.5 IPA was verified as:

- `CFBundleIdentifier`: `com.openclaw.landlordhours`
- `CFBundleShortVersionString`: `1.0.3`
- `CFBundleVersion`: `202606230738`
- `DTXcode`: `2650`
- `DTSDKName`: `iphoneos26.5`
- `DTPlatformVersion`: `26.5`
- `MinimumOSVersion`: `17.0`

Fastlane/Transporter reported upload success, but App Store Connect's build-upload API showed the package failed validation:

- Build `202606230738`: `FAILED`
- Error `90032`: `Invalid Image Path - No image found at the path referenced under key 'CFBundleAlternateIcons'`
- Missing referenced names: `AppIcon-Violet`, `AppIcon-Clock`, `AppIcon-Sunset`, `AppIcon-Aurora`

Root cause: `Sources/App/Info.plist` manually declared alternate icons using `CFBundleIconFiles`, but the alternate icons are asset-catalog entries. Xcode-generated asset-catalog metadata correctly uses `CFBundleIconName`; the manual plist block overrode that and made App Store processing look for root PNG files that were not packaged.

Fix:

- Added `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` for all four alternate icons in Debug and Release.
- Added `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`.
- Removed the manual `CFBundleIcons` block from `Sources/App/Info.plist` so Xcode generates correct `CFBundleIconName` metadata for iPhone and iPad.

The corrected Xcode 26.5 IPA was verified locally as:

- `CFBundleShortVersionString`: `1.0.3`
- `CFBundleVersion`: `202606230805`
- `DTXcode`: `2650`
- `DTSDKName`: `iphoneos26.5`
- Alternate icons present in `Assets.car`
- Alternate plist entries use only `CFBundleIconName`, not stale `CFBundleIconFiles`

App Store Connect build-upload status immediately after upload:

- Build `202606230805`: `PROCESSING`
- Validation errors: none reported at first status check

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

After uploading the corrected Xcode 26.5 build, verify:

1. App Store Connect build-upload state becomes `COMPLETE`.
2. App Store Connect build list includes the new build.
3. Build attributes show:
   - `processingState`: `VALID`
   - `buildAudienceType`: `APP_STORE_ELIGIBLE`
   - `minOsVersion`: `17.0`
4. App Store version `1.0.3` has a build attached.
5. Review submission moves from `PREPARE_FOR_SUBMISSION` to `WAITING_FOR_REVIEW`.

## Next Resume Prompt

Resume from `/Users/brian/Projects/LandlordHours`.

Use stable Xcode 26.5 for App Store release:

1. Confirm branch is `main` and includes the latest LandlordHours polish work.
2. Confirm `tmp` is still the SSD symlink.
3. Build/archive with `/Volumes/Home/Applications/Xcode.app/Contents/Developer`.
4. Upload the Xcode 26.5 / iOS 26.5 SDK build to App Store Connect for version `1.0.3`.
5. Verify build `202606230805` or any newer corrected build appears as `APP_STORE_ELIGIBLE`.
6. Attach it to version `1.0.3`.
7. Submit version `1.0.3` for App Review.
