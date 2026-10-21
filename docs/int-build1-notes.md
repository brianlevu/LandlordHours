# Integration rehearsal: 2.0 TestFlight build 1 (`int/build1`)

Base: `origin/release/2.0` at f80538a. Merge order: wp-paywall (2821ed4), wp-log (075afb3), wp-today (6924765).

## Conflicts and resolutions

| # | Merge | File | What clashed | Resolution | Side that won |
|---|-------|------|--------------|------------|---------------|
| 1 | wp-log | `project.pbxproj` | Both added files | Took wp-log's copy, then `xcodegen generate` | Regenerated |
| 2 | wp-log | `Inbox/InboxViewModel.swift` `dismiss(_:)` | Paywall added `waitList.remove(...)`; Log changed the toast copy | Kept both: the wait-list removal and "Marked not rental work" | Both |
| 3 | wp-today | `project.pbxproj` | Both added files | Took wp-today's copy, then `xcodegen generate` | Regenerated |
| 4 | wp-today | `Inbox/InboxViewModel.swift` | Same hunk as #2 | Same: kept the wait-list removal and Log's copy | Both |
| 5 | wp-today | `DashboardView.swift` state | Old week/pace helpers + paywall's `showRecordExport`, against Today's `showPaywall` | Dropped the old helpers (Today deleted them). Kept `showRecordExport`. Dropped `showPaywall` | Today layout, Paywall state |
| 6 | wp-today | `DashboardView.swift` body | Old `recentEntriesSection`/`thisWeekCard`/`yourRecordLock`, against Today's new sections | Today's layout. "Your record" now comes from `TodayRecordSlot` | Today |
| 7 | wp-today | `DashboardView.swift` helpers | Old quick-action pills + paywall's `yourRecordLock`/`shouldShowProNudge`, which Today deleted | Dropped them. `TodayRecordLockCard` stays (paywall) | Today (layout), Paywall (card) |

## Seams wired with no textual conflict

- **Today draft/timer card → Log's card.** wp-log added `TodayTimerSection()` right under the hero. wp-today added `TodayTimerSlot` (with its own `TodayDraftCard`) in its "below the house" stack. Today owns where the card sits, so I removed Log's extra call. `TodayTimerSlot` now renders `TodayTimerSection()`, which uses Log's generic `DraftCard`. I deleted `TodayDraftCard` and the slot's `ran`/`meta` helpers, as the INTEGRATION notes asked. Log's copy wins for timer meta: it includes the day, for example "Started Oct 19, 10:25.".
  - I removed `TodayTests.testTimerDraftMetaSaysWhatHappened`, because it tested those deleted helpers.
  - In `TodayCaptureUITests`, the "draft" capture now anchors on Log's `draft.card` instead of `today.draft`.
- **Today's Pro seam → ProGate's LockedPreview.** `TodayRecordSlot` keeps Today's section header. Its card is now paywall's `TodayRecordLockCard` (`LockedPreview(.card)`, entry `.todayRecord`). `isShown` calls `ProGate.showsTodayRecordLock`, and the local 10h constant is gone. After a purchase, the card opens the export (`showRecordExport`).
- **Log's property-limit seam → ProGate.** I deleted `LogProGate`. `LogPropertyPicker` asks `viewModel.canAddProperty()`, which is ProGate-backed. The at-limit row is paywall's `PropertiesAtLimitRow` (`LockedPreview(.row)`, `.propertiesLimit`). Unlock now opens `.proPaywall` with `ProPaywallRequest(context: .secondProperty, entry: .propertiesLimit)` and no longer uses Log's own `PaywallView` sheet. After a purchase, it goes straight to Add property.
- **Inbox copy.** Log and Today both changed "Not landlord work" to "Not rental work". Git merged these with no conflict, and no user-facing "landlord work" string is left.

## Open items for the final merge
- Today shows "Your record" whenever there are entries. Paywall's old `shouldShowProNudge` also required at least one property. I kept Today's rule. Today owns the layout, and ProGate's lock rule is unchanged.
