# int/build2 — integration notes (2026-10-20/21)

This branch starts from release/2.0 at c133ac6 (build 1). It merges, in order:
- wp-surfaces 1851342
- wp-ai-log 9851e24
- release/2.0 24ddf49 (the onboarding race fix and qa-tools-2)
- wp-ai-log c00720d (the iOS 27 LanguageModelError mapping)

Every merge was checked for its exit code, run through xcodegen and grepped for conflict markers.
Evidence is in `~/AgentScratch/landlordhours/2026-10-20/int2/`.

## Conflicts and resolutions

| File | Conflict | Resolution |
|---|---|---|
| `Sources/Widget/LandlordHoursWidget.swift` | Build 1 renamed one string inside the timer Live Activity. Surfaces removed the Live Activity, which never ran because `NSSupportsLiveActivities` is NO. | Took surfaces. The copy change no longer applies. `AppViewModel` still requests activities, but they can't start. That's cleanup for later. |
| `CaptureNotificationCenter.swift` | Build 1 changed the action titles from "landlord" to "rental". Surfaces moved the titles into `NotificationCopy` and added icons. | Took surfaces. The titles are the same: Log it / Edit… / Not rental work. |
| `EngagementIntelligenceService.swift` | Build 1 changed the nudge wording. Surfaces moved the nudges to the new copy sheet. | Took surfaces. No "landlord work" string is left. |
| `Inbox/InboxViewModel.swift` `dismiss(_:)` | Build 1 added `waitList.remove(...)`. Surfaces only changed the lines around it. | Kept the build-1 line. |
| `Inbox/InboxView.swift` `InboxUndoToast` | Build 1 gave the view `showsUndo`/`identifier` so the shell could reuse it. Surfaces redrew it as `LHToast`. | Took surfaces. The shell no longer reuses this view (see below). |
| `ContentView.swift` | Build 1 had the Log sheet route, the shell toast overlay, the paywall host and a DEBUG cover. Surfaces had the `LHToastHost`, the persistence toast and Get help. | Kept both sides' features and removed the second toast overlay. |
| `project.pbxproj` (both merges) | Generated file. | Regenerated with xcodegen. |

**One toast system, as the brief asked.** `AppToastCenter`, the build-1 toast for Log time, the timer and Today, used to draw its own overlay. It is now a thin wrapper that hands each toast to `LHToastCenter.shared`. The shell's `LHToastHost` draws it as an `LHToast`. Call sites didn't change.
- `LHToastSpec` gained `identifier`, `actionIdentifier` and `holdSeconds`. Build-1 toasts keep the `shell.toast` / `inbox.undo` identifiers that the UI tests use.
- The Inbox still takes the toast slot first.
- `dismiss()` and `undo()` act only on a toast this wrapper created.

## Builds

- Simulator build-for-testing: passes at every merge.
- Device build-for-testing: passes. Plain `-allowProvisioningUpdates` fails from an agent shell ("No Accounts", widget profile). It needs the ASC key flags (ios-dev-harness, devices.md Option A).
- The widget `LandlordHoursWidgetExtension.appex` (com.openclaw.landlordhours.widget) is embedded in the app.
- `codesign --verify --strict` passes on both the app and the widget, team G68NLC3DA3.
- Both are signed with the App Group `group.com.openclaw.landlordhours`. This matches the three identifiers used in code.

## Tests

Frame-capture-only tests (`testCapture*`) were skipped: 60 of 173 UI tests. That leaves 113.
- Sims: slim iPhone 17 Pro on iOS 27.0, booted through simboot with store, pim and iCloud kept on. simslim doctor confirmed calendar, storekit, icloud and keychain-sync.
- The AI shard also kept siri on.
- Device: iPad 10th gen, iOS 27.

**The first full pass ran at 362d1c4**, before release 24ddf49 and ai-log c00720d.
- Unit, sim: 879 passed, 3 skipped. The StoreKit purchase class failed once and then hung; it ran separately.
- UI, 113 tests:
  - iPad: 82 tests, 6 failures.
  - simA: 22 tests, 0 failures.
  - simB: 9 tests (onboarding), 6 failures. These are the known onboarding race.
- The simulator lane got only two sims, because the simboot budget was full with other sessions.

**The final SHA was retested** after 24ddf49 and c00720d. Those merges touched onboarding, CloudKitSync (DEBUG only), the note reader and scripts.
- Unit, sim: 892 executed, 3 skipped, 0 failed.
- Unit, iPad: 889 executed, 8 skipped, 1 failed. `InitialSyncGateTests` ran separately: 3/3 passed.
- Onboarding:
  - sim: 11/11.
  - iPad: 10/10 (at 24ddf49).
- LandlordHoursUITests:
  - sim: 12/13.
  - iPad: 10/13.
- TodayConfirm:
  - sim: 7/8.
  - iPad: 7/8.
- AI shard (Siri on): LogTime and Inbox 34/34. Note reader and classifier units 33 passed, 1 skipped.

### Failures and their class (each was rerun alone once)

| Test | Class | Evidence |
|---|---|---|
| `LandlordHoursUITests.testFirstTimeActivationFlowAddsPropertyAndLogsFirstHour` (LandlordHoursUITests.swift:299) | **REAL** | Fails on int2 on the iPad, on a sim, and on a Siri-on sim. Passes on release c133ac6 on the iPad. The note "Reviewed tenant message at Oak Street Duplex for 1 hour" no longer gets a category: the screen says "Pick the kind of work to log this", so Log stays disabled. ai-log's rules dropped the bare "tenant" keyword. Owner: ai-log. Either fix the rules or update the test. |
| `TodayConfirmUITests.testConfirmFromTodayLogsBuildsTheHouseAndDropsTheBadge` (TodayConfirmUITests.swift:112, hero hours never go above `before`) | **flaky, only on int2** | Fails in the suite on the final SHA, on both sim and iPad. Passes alone on the iPad. Release 24ddf49 passes 8/8 in the suite on the iPad, and so did int2 362d1c4. Needs a look. |
| `LandlordHoursUITests.testReportsExportGeneratesShareablePDFState` (:93) | device-env | Fails on the iPad on int2 and on release c133ac6. Passes on sim. |
| `SignInReplacementUITests` ×2 (:43, :82) | device-env | Same pattern as the export test. |
| `PaywallCaptureUITests.testStatusBandFollowsScroll` (:83) | device-env | Same pattern as the export test. |
| `LandlordHoursUITests.testSettingsSecondaryFlowsOpenWithoutSwitchingTabs` and `testAppearancePreferenceShowsSavedStateAndPersists` (:425, hittability) | flaky | Each passed alone on the iPad. The settings test failed once alone on a sim. |
| `LocalProfileFlowTests.testLocalDelete…` (LocalProfileTests.swift:613, CKError "Unknown Item") | device-env | The iPad uses real CloudKit. Passes on sim. |
| `ProPurchaseStoreKitTests` (ProGateTests.swift:510, then a hang) | flaky | 4/4 alone. Passed in the final full sim run. |
| `InitialSyncGateTests` (hung on iPad once) | flaky / device-env | 3/3 alone on the iPad. |
| `OnboardingUITests` ×6 at 362d1c4 | real, now fixed | The first-tap race, fixed by fix/onb-start in 24ddf49. Now 11/11 on sim and 10/10 on the iPad. |

**TodayConfirm on plain release/2.0 24ddf49** (coordinator question): it ran 8/8 in the suite on the iPad, so the polish lane's four failures did not reproduce. Their sims probably had iCloud or pim slimmed off.

## Surfaces code check

- **Widget timeline is self-only for REPS.** It uses `houseCountableHours`, which for REPS is `repsStatus(.selfParticipant)`. Spouses are combined only for material participation tracked jointly. OK.
- **To-confirm count.** It is `InboxLogic.visible(suggestionStore.suggestions)`, the same source and filter as `InboxViewModel.badgeCount`. OK.
- **Notification actions.**
  - Log it re-checks the event: reconcile, then `eventChecker.check`, then the "might already be logged" check, then the write.
  - Edit… opens the confirm sheet.
  - Not rental work dismisses only a pending item and offers the mute follow-up. It does not re-check the event; that's harmless because dismiss can't touch a confirmed entry.
  - Every action checks the profile id first.
  - `calendarReview` now routes to the Inbox.
  - OK.
- **Launch status bar.** `LaunchStatusBarWindow` is hidden when the hand-off loop ends, and the loop always ends. The only path that leaves it up is the DEBUG `-LHLaunchFreeze` capture hook. No window is left behind in Release. OK.
- **Info.plist strings.** Calendar, microphone and speech all say nothing is saved until the user confirms. Honest. OK.
- **No Lucide, no violet, no ProgressView** in the new surfaces or ai-log code. Grep is clean.
- **Localization: flagged, not rewritten.**
  - The repo has no String Catalog (no `.xcstrings`).
  - Strings built in code are plain `String`s with interpolation and hand-made plurals:
    - `NotificationCopy` (`endOfVisit` concatenates `ask += " at …"`, plus `followUp`, `inactive` and `yearEnd`)
    - `EngagementIntelligenceService` ("\(count) to confirm")
    - the Siri dialog in `LandlordHoursAppIntents.swift:233–259` (`"\(lead) \(pace), and \(waiting)."` and a first-letter `uppercased()`)
    - the widget display strings in `WidgetSurface.swift` ("Behind by \(gap)h", "\(goalNumber)h reached")
    - `WidgetSurfaceViews` `Text(" " + status.text)`
    - the toast "Added \(property.name)"
  - Fix: add a String Catalog, use `String(localized:)` with format arguments, and handle plurals in the catalog.

## Copy gate

Command: `copy_gate.py check --baseline release-2.0.json`

23 new flagged strings compared with release/2.0. None is a banned word.
- Most come from ai-log's model prompt and schema text, which users never see. Examples: "Fields for one time-log entry…" for straight apostrophes, and the date regexes.
- User-facing flags:
  - Settings "Private Cloud Compute": Title Case and jargon. It is Apple's name for the service.
  - Three Settings AI disclosure sentences: plain speech, 0.70–0.87.
  - Siri "Opening Properties." / "Opening Reports.", the intent descriptions, and the `"{} {}, and {}."` dialog.
  - The widget description.
  - "Added {}".
  - "{} calendar events look like rental work.": tax claim 0.31, just over the 0.30 threshold.

Report: `~/AgentScratch/landlordhours/2026-10-20/int2/copy-gate/int-build2-final.md`.
