# Changelog

All notable changes to LandlordHours will be documented in this file.

**Current live version: 1.0.3** (verified via App Store Connect API, 2026-07-07 — `READY_FOR_SALE` / `READY_FOR_DISTRIBUTION`, created 2026-06-23).

> Note on 1.0.1/1.0.2/1.0.3 attribution: `MARKETING_VERSION` is not committed to source in this repo — it is passed as an environment variable at `fastlane` build/upload time (see `fastlane/Fastfile`, `docs/xcode27-lane.md`), and there are no version-bump commits or tags to anchor against. The entries below were reconstructed from `git log`, commit dates, and the dated docs in `docs/` (`app-store-resubmission-audit-2026-06-16.md`, `session-handoff-2026-06-23-stable-appstore-resubmission.md`, `xcode27-lane.md`). The 1.0.3 entry is well-evidenced (explicitly named in those docs with a matching build/date). The exact commit boundary between 1.0.1 and 1.0.2 could **not** be reliably determined — App Store Connect shows both as separately released, but nothing in the repo indicates which commits shipped in which of the two — so those changes are presented together below rather than split arbitrarily.

## [1.0.3] - 2026-06-23 (current, live on the App Store)

Confirmed by `docs/xcode27-lane.md` ("App Store Connect version `1.0.3` upload completed on 2026-06-23") and `docs/session-handoff-2026-06-23-stable-appstore-resubmission.md`.

### Fixed
- Alternate app icon references corrected for App Store binary validation — the manual `CFBundleIcons` plist block was overriding Xcode's asset-catalog-generated `CFBundleIconName` metadata, causing upload error `90032` (`Invalid Image Path`) (`7bf532b`, `docs/session-handoff-2026-06-23-stable-appstore-resubmission.md`).

### Changed
- Polished the release experience ahead of resubmission (`703e349`).

### Added
- 13-inch iPad App Store screenshots (`f098b0b`).

### Documentation
- Documented the App Store submission blocker investigation (`a6f466a`) — see status addendum above; the blocker was resolved after this doc was written.

## [1.0.1] and [1.0.2] - reconstructed, 2026-06-16 to 2026-06-22 (exact split uncertain — see note above)

Commits between the 2026-06-16 App Store resubmission audit and the 2026-06-23 (1.0.3) release:

### Fixed
- Root-caused and fixed the App Store review rejection of build `1.0 (202605181544)` (Apple guideline 2.1(a), reviewer got a purchase error): App Store Connect's draft IAP (`premium`, consumable) didn't match the binary's requested product (`com.openclaw.landlordhours.pro`, non-consumable), so StoreKit had no matching product to return. See `docs/app-store-resubmission-audit-2026-06-16.md` (`4828f69`).
- Centralized paywall purchases through `SubscriptionManager.purchasePro()` and removed onboarding logic that silently advanced when StoreKit products failed to load (`4828f69`).
- Added explicit `Sources/App/Info.plist` with `UIBackgroundModes` (`remote-notification`) and fixed a CloudKit simulator startup crash on builds without iCloud entitlements (`4828f69`).
- Fixed appearance (light/dark/system) preference feedback (`58d5b72`).

### Added
- Apple-native voice time entry via `VoiceEntryService`, with local-first transcript parsing for property, category, participant, and hours (`cd341b5`).
- Appearance preference setting — light/dark/system (`3472488`).
- Large roadmap/UI polish pass: alternate app icons, onboarding learning content, category management, calendar import review flow, AI time entry service refinements (`4828f69`, merged via `5a1cd2e`).

### Changed
- Updated Settings copy from subscription language to one-time Pro-access language (`4828f69`).

### Other
- Added MIT license (`e86630b`, 2026-05-31) — repo housekeeping, not tied to a specific app version.

## [1.0.0] - 2026-02-20

### Added
- Timer with start/stop functionality
- Manual time entry
- Property management (LTR/STR types)
- REPS progress tracking (750-hour requirement)
- 50% working time rule calculator
- 11 activity categories (8 REPS-qualified, 3 non-REPS)
- Multi-participant tracking (Self/Spouse)
- Dashboard with today's stats
- Reports with property and category breakdowns
- Year selector for historical data
- Settings screen

### Technical
- MVVM architecture
- SwiftUI for iOS 17.0+
- UserDefaults for local persistence
- Clean, modern UI with card-based design

---

*For future releases, see [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md)*
