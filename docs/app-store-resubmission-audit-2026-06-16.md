# LandlordHours App Store Resubmission Audit - 2026-06-16

## Current Apple Review Issue

- Submission ID: `289c06c0-0490-421b-93d7-8f60c90eed74`
- Review date: 2026-05-20
- Reviewed build: `1.0 (202605181544)`
- Apple guideline: `2.1(a) Performance - App Completeness`
- Apple issue: reviewer received an error message while trying to purchase the app's paid access.

## Root Cause Found

App Store Connect does not match the binary's StoreKit product configuration.

- Binary requests product ID: `com.openclaw.landlordhours.pro`
- Local StoreKit config defines: `com.openclaw.landlordhours.pro` as `NonConsumable`
- App Store Connect currently has draft IAP:
  - Product ID: `premium`
  - Type: `Consumable`
  - Status: `Missing Metadata`
- The rejected app version does not show an in-app purchase attached to the version page.

This explains the reviewer-visible purchase failure: StoreKit cannot return the product the binary asks for when App Store Connect only has a different draft product.

## Code Fixes Applied Locally

- Added an explicit `Sources/App/Info.plist` with `UIBackgroundModes` containing `remote-notification`.
- Pointed the Xcode project and `project.yml` at the explicit plist.
- Aligned `project.yml` with the current team `G68NLC3DA3` and automatic signing so project regeneration does not regress signing.
- Changed simulator CloudKit startup to avoid crashing when simulator builds do not carry iCloud entitlements.
- Replaced the async remote-notification delegate method with the completion-handler variant to avoid the Swift 6 non-Sendable warning path.
- Centralized paywall purchase attempts through `SubscriptionManager.purchasePro()`.
- Removed onboarding behavior that silently advanced when StoreKit products failed to load.
- Updated Settings copy from subscription language to one-time Pro access language.

## Verified Locally

- Debug iPhone simulator build succeeds with scoped Xcode:
  - `DEVELOPER_DIR=/Volumes/Home/Applications/Xcode.app/Contents/Developer`
- Unit tests pass:
  - 50 tests
  - 0 failures
- Packaged app plist now contains:
  - `UIBackgroundModes = [remote-notification]`

## Required App Store Connect Repair

Before resubmitting, fix monetization in App Store Connect:

1. Delete or ignore the invalid draft IAP `premium` if it cannot be changed.
2. Create a new non-consumable in-app purchase:
   - Reference name: `LandlordHours Pro (Lifetime)`
   - Product ID: `com.openclaw.landlordhours.pro`
   - Type: `Non-Consumable`
   - Display name: `LandlordHours Pro`
   - Description: `Unlock unlimited properties, AI-assisted time logging, iCloud backup, photo evidence, and audit-ready PDF reports.`
3. Add required IAP review screenshot and notes.
4. Attach the IAP to the iOS app version before submitting the app version for review.
5. Add App Review notes explaining the fix:
   - The previous purchase issue was caused by an App Store Connect IAP configuration mismatch.
   - The new build requests `com.openclaw.landlordhours.pro`, and the matching non-consumable IAP is included with the app version.
6. Keep final submission as an explicit approval step before clicking `Submit for Review`.

## Metadata Gaps Observed

- iPhone screenshots: 4 uploaded.
- App Review sign-in credentials: not provided.
- App version release setting: automatic release after approval.
- Current description is serviceable, but it should avoid implying tax qualification is guaranteed.

## UX Backlog

- P0: Complete App Store Connect IAP repair and verify product loads before resubmission.
- P0: Upload a fresh build after the plist, CloudKit simulator, and StoreKit flow fixes.
- P1: Add UI tests for first launch, email sign-in path, onboarding paywall, and paywall error state.
- P1: Generate final iPhone screenshots from current UI after the next release build.
- P1: Review App Privacy and accessibility metadata before resubmission.
- P2: Refresh README branding to match the current violet/Tiimo design system.
- P2: Decide whether LandlordHours should remain iPhone-only or add real universal iPad support later.
