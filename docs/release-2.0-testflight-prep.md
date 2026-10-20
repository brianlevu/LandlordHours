# LandlordHours 2.0: first TestFlight build, preparation

Prepared 2026-10-20 from `origin/release/2.0` @ f80538a (detached worktree). Nothing was uploaded, submitted or changed in App Store Connect or the CloudKit console. Read-only `asc` queries only.

**Not yet in release/2.0 (three branches still to merge):** `wp-log` (Log time), `wp-today` (Today), `wp-paywall` (paywall). Where a check depends on them it says so. Re-run section 6 after they merge.

## Blocks shipping (needs the owner)

1. **Deploy the CloudKit schema to Production** (section 1). Without it, every sync batch from a TestFlight build fails.
2. **Paywall Terms and Privacy links** only exist on `wp-paywall` (section 4). Merge that branch before the build.
3. **Terms link goes to the wrong page.** `https://www.altaiventures.co/landlord-hours/terms` (used in Settings and the new paywall) redirects to the LandlordHours product page, not a terms document. The real pages are `https://www.altaiventures.co/terms/` and `https://www.altaiventures.co/privacy/` (both 200, both mention LandlordHours). The new paywall's Privacy link is a GitHub gist. Fine for TestFlight; fix before App Review (guideline 3.1.2).
4. **Xcode 27.1 (27A9275) is installed on this Mac**, and Xcode Cloud is pinned to 27.0 GA (27A266a). I could not confirm Apple accepts 27.1 builds. A local upload could process as VALID and then flip to INVALID_BINARY. See section 2.

## 1. CloudKit Production schema checklist

Container `iCloud.com.openclaw.landlordhours`, private database, zone `LandlordHoursZone`. Derived from `CloudKitSyncService.swift` (record mappers) on release/2.0, diffed against `origin/main` (the 1.x field set).

No new record types. Five types exist already: `Property`, `TimeEntry`, `CustomCategory`, `GoalSettings`, `TaxProfile`. No new indexes: the only query is `appUserId == …` (delete account), and 1.x already needed that.

New fields 2.0 writes that 1.x Production lacks (8 in total):

| Record type | Field | CloudKit type | Written |
|---|---|---|---|
| TimeEntry | `detectedAt` | Date/Time | only when set |
| TimeEntry | `confirmedAt` | Date/Time | only when set |
| TimeEntry | `sourceDetail` | String | only when set |
| TimeEntry | `sourceKey` | String | only when set |
| Property | `aliases` | String (List) | always, may be empty |
| Property | `aliasCount` | Int(64) | always |
| Property | `isOwnerOccupied` | Int(64) | always |
| GoalSettings | `materialParticipationTarget` | Int(64) | always (the 500 h goal) |

Plan check: the plan lists the TimeEntry four and the Property three. The plan does not list `GoalSettings.materialParticipationTarget`, which the code writes (added by WP-Onboarding). It is the eighth field. `GoalSettings` is not a new record type, only a new field.

Pending, not in release/2.0: branch `wp-ai-log` (AI note filling, build 2) adds `TimeEntry.recordDescription` (String). Deploying is one-way and fields cannot be deleted from Production. If a Debug build of that branch has already written it to Development, the deploy will carry it along; that is harmless. Deploy it deliberately before any build that contains it.

Why this is safe for 1.x devices: 2.0 never writes nil to optional fields, and 1.x pushes use `.changedKeys`, so older clients ignore the new fields.

### Click-by-click for the owner

1. Open https://icloud.developer.apple.com/dashboard/ and sign in with the Apple Developer account for team G68NLC3DA3.
2. Pick the container `iCloud.com.openclaw.landlordhours`.
3. Make sure the environment switcher says **Development**. Open **Schema > Record Types**.
4. Open `TimeEntry` and check that `detectedAt`, `confirmedAt`, `sourceDetail` and `sourceKey` exist with the types above. Open `Property` (`aliases`, `aliasCount`, `isOwnerOccupied`). Open `GoalSettings` (`materialParticipationTarget`).
5. If any field is missing: Development only creates a field when a Development-signed build first saves a record containing it. Run a Debug build from Xcode on an iPhone signed in to iCloud. Then: add a property with a nickname and turn on "I live here"; pick the 500-hour goal in onboarding or Settings; confirm one Inbox suggestion (needs a calendar event); wait one minute. Refresh the console and re-check step 4.
6. Click **Deploy Schema Changes…** (Development environment, schema section of the sidebar).
7. In the dialog, read the list of changes. It should list exactly the 8 fields above (plus `recordDescription` only if you ran the `wp-ai-log` build). If it lists anything else, such as a record type or an index you do not recognise, stop and ask.
8. Click **Deploy**, then confirm.
9. Switch the switcher to **Production**. Open `TimeEntry`, `Property`, `GoalSettings` and confirm the 8 fields are there.
10. Tell Claude "schema deployed". Only then upload the build.

## 2. Version and build

**Versions.** `MARKETING_VERSION` is `2.0` in `project.yml` (base setting, inherited by every target), in both project-level configurations of `LandlordHours.xcodeproj` (Debug and Release), and `Sources/App/Info.plist` reads `$(MARKETING_VERSION)`. The archive's Info.plist shows `CFBundleShortVersionString = 2.0`. There is **no widget or extension target in 2.0**: `Sources/Widget` is excluded from the app target and the project has only the app plus unit and UI test targets. (The widget moved to 2.1.) `Sources/Widget/Info.plist` also reads `$(MARKETING_VERSION)`, so it will follow when the target returns. Orphan file `LandlordHoursWidget.entitlements` is unused.

**asc read-only (app 6759508794, bundle `com.openclaw.landlordhours`):**
- Versions: 1.0, 1.0.1 to 1.0.6, all READY_FOR_DISTRIBUTION. 1.0.6 is live. There is no 1.1 or 2.0 version record yet (not needed for TestFlight).
- Latest build: `202608260402` (1.0.6, VALID, uploaded 2026-08-26). Build numbers have always been `YYYYMMDDHHMM` timestamps from local uploads. 19 builds in total.
- `project.yml` still has `CURRENT_PROJECT_VERSION: 202608260402`, the same as the live 1.0.6 build. It would be accepted (numbers only need to be unique inside version 2.0) but it is stale and confusing.
- TestFlight: one internal group, "Test Users", with one tester (brianlevu@gmail.com, INSTALLED). TestFlight app info (description, feedback email) and Beta App Review details are **empty**. That is fine for internal testers; it must be filled in before any external group.

**Xcode Cloud state.** Workflow "Default" (`A377B832-EA65-4C20-837A-95EADC22E31F`) is enabled, pinned to Xcode 27A266a and macOS 26A434, and starts on pushes to `main` only. It has a single Archive action with **no distribution destination**. Runs #22 to #27 all succeeded between Oct 18 and 19 and produced **no builds in App Store Connect**. So Xcode Cloud is configured to compile, not to deliver to TestFlight. Merging to `main` will start a harmless archive run.

**Recommended build number: a timestamp, supplied at archive time, e.g. `202610211000`** (YYYYMMDDHHMM at the moment you archive). It is above every existing number and keeps the existing scheme. Do not edit `project.yml` for this; the script passes `CURRENT_PROJECT_VERSION` on the command line.

Global rule to respect: Xcode Cloud numbers builds from its own counter (now at run 27, so the next build would be 28), not from `CURRENT_PROJECT_VERSION`. Never mix the two schemes inside the 2.0 train: a later Xcode Cloud build `28` would be rejected as lower than `202610211000`. If you move to Xcode Cloud later, set Next Build Number in ASC above the last timestamp first.

**Recommended build path: local archive plus `asc builds upload`** (fastest, no workflow changes). Xcode Cloud is the better long-term path, but today it needs workflow edits (owner clicks, below).

One command (archive proven; export and verify untested, so read the output the first time). It stops before uploading:

```bash
cd /Users/brian/Projects/LandlordHours && scripts/testflight-build.sh
```

It refuses a dirty tree and a beta macOS, archives Release with a fresh timestamp build number, exports with the App Store method, checks version 2.0 and that `BuildMachineOSBuild` has no letter suffix, and prints the upload command. Run it from a clean checkout or worktree of the merged branch, never from a dirty main. To upload (take the shared asc lock first, `shipping.md`):

```bash
cd /Users/brian/Projects/LandlordHours && scripts/testflight-build.sh --upload
```

After upload, wait for VALID, then add the notes in section 5:

```bash
asc builds list --app 6759508794 --sort -uploadedDate --limit 1
asc build-localizations --help   # create/update the en-US "What to Test" text for that build id
```

The new build lands in the internal "Test Users" group only if that group has automatic distribution on; otherwise add the build to the group in ASC (owner click).

**If you prefer Xcode Cloud** (Xcode 27A266a, known-good): in App Store Connect > Xcode Cloud > Default workflow > Edit: (a) add a start condition for the branch you ship, (b) add a post-action "TestFlight Internal Testing" for group "Test Users", (c) set Next Build Number to `202610211001` or higher before the first run. Then push the branch. Per the harness, a `build/*` push that does not register within 5 minutes should be re-pushed under the next `build/` name.

**Toolchain risk (decide before uploading).** This Mac has Xcode 27.1 (27A9275, SDK iOS 27.1, installed Oct 16). The archive's `DTXcodeBuild` is 27A9275. Xcode Cloud uses 27A266a. The harness only records 27.0 GA as accepted. Safest: do the first upload from Xcode Cloud, or watch the build for INVALID_BINARY after it first shows VALID. macOS build is 26A428 (no letter suffix, so the beta-OS rule is satisfied).

## 3. Privacy

**Verdict: 2.0 does not change the App Privacy label.** Nothing new is collected or sent off device by our code.

The app has no `URLSession` calls of its own; the only network traffic is CloudKit (private database), StoreKit, RevenueCat and PostHog. The 2.0 additions (calendar reading, the classifier, Apple on-device models, Private Cloud Compute for receipts) add no network destinations of ours.

Manifests embedded in the archive (SDK versions from `Package.resolved`):

| Source | Data types declared | Linked | Tracking | Purpose | Required-reason APIs |
|---|---|---|---|---|---|
| Our app `Sources/App/PrivacyInfo.xcprivacy` | Purchase History | No | No | App Functionality | UserDefaults `CA92.1` |
| RevenueCat 5.86.0 | Purchase History | No | No | App Functionality | UserDefaults `CA92.1` |
| PostHog 3.68.2 | Product Interaction, Other Usage Data | No | No | Analytics | UserDefaults `CA92.1` |
| PostHog PHPLCrashReporter (nested bundle) | Crash Data, Other Diagnostic Data | No | No | App Functionality | none |
| LucideIcons | no manifest (assets only) | | | | |

**Union for the ASC label:** Purchase History (App Functionality), Product Interaction (Analytics), Other Usage Data (Analytics), Crash Data (App Functionality), Other Diagnostic Data (App Functionality). All "not linked to you", none used for tracking.

Findings:
- **Our own manifest does not restate the PostHog data types or the crash-reporter types.** It only lists Purchase History, with a comment that the SDK manifests cover the rest. Apple merges the SDK manifests, so the build is valid. The ASC label must still be the full union above.
- PostHog is set up with no session replay, no autocapture, screen views off, lifecycle events on, no `identify()` calls, and a user opt-out ("Share Anonymous Usage"). PostHog's anonymous device-scoped ID is not declared as a Device ID in its manifest. If the live label says "Device ID", keep it; do not remove categories to match the manifests.
- Crash Data and Other Diagnostic Data come from PostHog's bundled crash reporter. Check that the live ASC label includes both, since an app-level manifest alone does not cover them.
- **Apple Foundation Models (on device) and Private Cloud Compute add no category.** The plan's position: processing is on device or in Apple's stateless PCC, and the developer receives nothing. I checked the iOS 27.1 SDK locally: `FoundationModels.swiftinterface` declares `PrivateCloudComputeLanguageModel` with availability and quota APIs and no privacy or data-retention text, and no Apple App Privacy guidance is available offline. So this part is **consistent with the plan but unverified locally**; confirm against Apple's App Privacy Details page and the Foundation Models terms before App Review (2.0 submission), not before TestFlight.
- Calendar: event titles are read on device and never leave it (no network code touches them), which keeps this out of the label.
- Per the harness rule, the label is the union of every SDK manifest, never derived from our call sites alone.

**ASC clicks for the owner (not needed for TestFlight, needed before submitting 2.0):** App Store Connect > LandlordHours > App Privacy: confirm the five types above are listed, unchanged, and that "Data Used to Track You" is empty; then Publish only if something changed. App Review notes should disclose Apple on-device AI and PCC (guideline 5.1.2(i)); that is already in the plan.

## 4. Compliance checks

- **`asc review doctor --app 6759508794`**: 0 errors, 0 warnings, 2 infos, nothing blocking. It looks at the live 1.0.6 version only (no 2.0 version exists yet), so it says nothing about 2.0. It notes it does not check the web-only "App Store Regulations and Permits" declarations; check those in ASC when you create the 2.0 version.
- **Account deletion (5.1.1(v)): PASS.** Settings > account section has "Delete account and data" (Apple profile) or "Delete all data" (local profile). It calls `deleteAccountAndData`, which removes the iCloud records, scoped keys, attachment files, then signs out.
- **Paywall Terms and Privacy links: FAIL on release/2.0, PASS after `wp-paywall` merges.** Today's `PaywallView.swift` has no Terms or Privacy link; Settings has one "Terms and privacy" row. `wp-paywall` adds both inside the plan card, visible without scrolling, plus a "Restore purchase" button. Fix the destinations as noted in "Blocks shipping" item 3.
- **Info.plist purpose strings: PASS, honest.**
  - `NSCalendarsFullAccessUsageDescription`: "LandlordHours reads event titles on your iPhone to suggest rental work, like a plumber visit. Nothing is saved until you confirm it." Matches confirm-first behaviour. No "pre-fill your log" wording.
  - `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`: dictation for time-entry notes. Voice entry is still used (`VoiceEntryService`, kept on all three open branches), so both strings are needed and accurate.
  - No location, photos, camera or Face ID strings, and none are needed: location is 2.1, and no code requests them.
  - Notifications need no plist string (`requestAuthorization` in `CaptureSetupFlow.swift`).
  - `UIBackgroundModes`: `remote-notification` (CloudKit), `fetch`, `processing` (capture refresh). `BGTaskSchedulerPermittedIdentifiers` lists `.capture.refresh` and `.capture.backfill`. App Review may ask why `processing` is declared; the answer is the capture refresh task.
  - `NSSupportsLiveActivities` is `false` (correct, no Live Activity in 2.0).
- **Export compliance: PASS.** `ITSAppUsesNonExemptEncryption = false` in Info.plist. ASC shows every prior build as "exempt".
- **Entitlements** are unchanged from 1.0.6 (Sign in with Apple, App Group, iCloud/CloudKit, KVS), so the existing App Store profile `LandlordHours App Store` (expires 2027-08-08) still covers the app.
- **Brand check:** `grep -ri minimax Sources` returns nothing.

## 5. TestFlight "What to Test" (build 1, 100 words)

> LandlordHours 2.0 is a big redesign. New: a first-run setup that looks through your calendar, an Inbox where you confirm or skip suggested hours (nothing counts until you confirm), a Today screen, a faster Log time sheet, and redesigned Properties.
>
> Please try: finish onboarding, confirm and dismiss a few Inbox items, log time by hand and with the timer, add a property, and open the paywall (use a sandbox purchase).
>
> Not in this build yet: widgets, reminder notifications, some wording polish and AI note filling. Those come in build 2.
>
> Tell us anything confusing. Shake or screenshot to send feedback.

## 6. Release build check

Run on this Mac: macOS 27.0 build **26A428** (no letter suffix), Xcode 27.1 (27A9275), SDK iOS 27.1. Detached worktree of `origin/release/2.0` @ f80538a, DerivedData `/Users/brian/tmp/DerivedData/landlordhours-release`, `generic/platform=iOS`, Release.

- **Compiles: YES.** Unsigned (`CODE_SIGNING_ALLOWED=NO`) and signed archives both end in `** ARCHIVE SUCCEEDED **`.
- **Signs: YES, with a caveat.** A plain automatic-signing archive failed: the "iOS Team Provisioning Profile: com.openclaw.landlordhours" does not include the local certificate "Apple Development: Vu Le (M43MX2N2YG)". The harness recipe fixed it: automatic signing with `-allowProvisioningUpdates` and the App Store Connect API key flags. That lets Xcode refresh its development profile in the Apple Developer portal. I did not touch App Store Connect or CloudKit. Archive signature: Apple Development, team G68NLC3DA3. The store certificate/profile is applied at export (the script).
- **Archive Info.plist:** version 2.0, build 202608260402 (the stale project value, which the script overrides), `MinimumOSVersion` 17.0, `BuildMachineOSBuild` **26A428**, `DTXcodeBuild` 27A9275, `ITSAppUsesNonExemptEncryption` false.
- **Embedded privacy manifests:** app, PostHog, PostHog crash reporter, RevenueCat (matches section 3).
- **IPA:** not exported (exporting with provisioning updates can create cloud-managed distribution certificates and profiles in the developer portal, which is outside this task). The IPA inherits the archive's `BuildMachineOSBuild`, **26A428**, and the script re-checks it after export.
- Archives: `~/AgentScratch/landlordhours/2026-10-20/archive/signed/` and `.../unsigned/` (regenerable; safe to delete).

### After the last three branches merge

1. Re-run the unsigned archive (compile gate) and the CloudKit diff: `git diff origin/release/2.0 <merged> -- Sources/Services/CloudKitSyncService.swift` and `Sources/App/Info.plist`. Today none of `wp-log`, `wp-today` or `wp-paywall` touches CloudKit, Info.plist, entitlements or the privacy manifest.
2. Confirm the paywall shows Terms and Privacy, pointed at pages that exist.
3. Deploy the CloudKit schema (section 1), run `scripts/testflight-build.sh`, upload, add the section 5 notes.

## Process notes

- asc lock taken for the read-only queries (holder pid 96573, released at the end).
- I created and then deleted a `release-prep` branch in the main checkout by mistake (briefly switched branches, main was restored with its uncommitted files untouched). This doc is committed from its own worktree instead.
