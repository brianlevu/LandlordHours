# Apple Services Test Plan

Use this checklist for the Apple-service surfaces that cannot be fully proven by normal simulator UI tests.

## Current Automated Coverage

Run:

```sh
xcodegen generate
xcodebuild test \
  -project LandlordHours.xcodeproj \
  -scheme LandlordHours \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Automated coverage now includes:

- StoreKit local configuration loads `com.openclaw.landlordhours.pro` from `LandlordHours.storekit`.
- Product metadata matches the app expectation: `LandlordHours Pro`, non-consumable.
- Core simulator UI flows still run through `LandlordHoursUITests`.

Known boundary:

- `SKTestSession.buyProduct` currently returns `notEntitled` from the unit-test host in this project setup. Purchase and restore must be verified from the app process using local StoreKit UI, App Store sandbox, and TestFlight.

## StoreKit Local Xcode Test

Purpose: prove the in-app purchase UX works before using App Store Connect.

Prerequisites:

- Open `LandlordHours.xcodeproj`.
- Edit the `LandlordHours` scheme.
- In Run > Options, set StoreKit Configuration to `LandlordHours.storekit`.
- Run a Debug build on an iOS simulator or device.

Checklist:

- [ ] Fresh install with no Pro entitlement.
- [ ] Product loads on paywall as `LandlordHours Pro`.
- [ ] Purchase succeeds.
- [ ] Pro state unlocks immediately.
- [ ] Kill and relaunch app; Pro remains unlocked.
- [ ] Sign out/sign in; Pro state is scoped to the expected user behavior.
- [ ] Restore purchases after deleting local Pro defaults.
- [ ] Simulate failed transaction from StoreKit configuration; app shows recoverable error.
- [ ] Simulate cancelled purchase; app does not show an error.
- [ ] Simulate pending purchase; app shows pending approval copy.

Evidence to capture:

- Paywall before purchase.
- Purchase success/unlocked Pro screen.
- Restore success.
- Failed/cancelled/pending states.

## StoreKit App Store Sandbox

Purpose: prove real App Store product lookup and transaction plumbing.

Prerequisites:

- `com.openclaw.landlordhours.pro` exists in App Store Connect.
- Product is cleared for testing and attached to the app.
- A Sandbox Tester account exists in App Store Connect.
- Test on a physical device signed into the sandbox purchase prompt when asked.

Checklist:

- [ ] Fresh Test/Debug install on physical device.
- [ ] Product loads from App Store, not local StoreKit config.
- [ ] Purchase with sandbox tester succeeds.
- [ ] Pro state unlocks immediately.
- [ ] Relaunch app; Pro remains unlocked after `refreshEntitlements`.
- [ ] Delete and reinstall app; Restore Purchases unlocks Pro.
- [ ] Test cancelled purchase.
- [ ] Test network-offline product-load failure.
- [ ] Test restore when no purchase exists.

Evidence to capture:

- Device, iOS version, Apple ID sandbox tester identifier.
- Product screen with price.
- Purchase result.
- Restore result after reinstall.

## StoreKit TestFlight

Purpose: validate the release build path closest to App Review.

Checklist:

- [ ] Install from TestFlight, not Xcode.
- [ ] Confirm product loads.
- [ ] Purchase succeeds using sandbox behavior.
- [ ] Restore succeeds after reinstall.
- [ ] Pro-gated features work: unlimited properties, PDF export, AI smart entry, iCloud backup if gated.
- [ ] No debug scenario picker is visible for non-admin user.
- [ ] App Review notes mention the purchase path and any test account needed.

Evidence to capture:

- TestFlight build number.
- Purchase and restore screenshots.
- App logs if product lookup fails.

## iCloud / CloudKit Development

Purpose: prove CloudKit account, zone, subscription, push, pull, conflict, and delete behavior in Development.

Prerequisites:

- Device or simulator is signed into iCloud.
- iCloud Drive is enabled.
- App has `iCloud.com.openclaw.landlordhours` entitlement.
- CloudKit Console is open to the Development environment.

Checklist:

- [ ] Signed-out iCloud state: app does not crash and surfaces unavailable sync state.
- [ ] Signed-in iCloud state: `accountAvailable == true`.
- [ ] First launch creates `LandlordHoursZone`.
- [ ] First launch creates private database subscription.
- [ ] Add property; record appears in CloudKit Console.
- [ ] Add time entry; record appears in CloudKit Console.
- [ ] Update property/time entry; modified value appears in CloudKit Console.
- [ ] Delete property; CloudKit record is deleted or tombstoned as expected.
- [ ] Reset local data; remote records do not leak into a different app user.
- [ ] Device A creates data, Device B pulls it.
- [ ] Device B edits same property, Device A pulls latest state.
- [ ] Account deletion removes current user's CloudKit records.

Evidence to capture:

- CloudKit Console screenshots of zone, subscription, property record, time-entry record.
- Device A/B before and after sync screenshots.
- Logs around `start`, `pushAll`, `pullChanges`, and delete.

## iCloud / CloudKit Production Dry Run

Purpose: prove TestFlight release behavior after deploying schema.

Prerequisites:

- Development schema deployed to Production in CloudKit Console.
- TestFlight build uses the production container.
- Test with a non-developer iCloud account if possible.

Checklist:

- [ ] Fresh TestFlight install creates/pulls production records.
- [ ] Add/update/delete property and time entry.
- [ ] Reinstall app and confirm remote data returns.
- [ ] Second device pulls data.
- [ ] Account deletion removes records.
- [ ] No development-only test records are visible.

Evidence to capture:

- TestFlight build number.
- CloudKit Production Console screenshots.
- Two-device sync screenshots.

## Release Gate

Do not mark Apple services ready until these are true:

- [ ] Simulator suite passes.
- [ ] StoreKit local purchase checklist passes.
- [ ] StoreKit sandbox checklist passes on a physical device.
- [ ] TestFlight purchase/restore checklist passes.
- [ ] CloudKit development two-device checklist passes.
- [ ] CloudKit production dry run passes.
- [ ] Evidence screenshots/logs are saved under `docs/apple-services-runs/<date>/`.
