# iPhone E2E UX Checklist - 2026-06-16

Scope: iPhone only. Do not install additional iOS runtimes. Do not use iPad simulators.

## Testing Contract

Do not report "everything checks out" from build success, unit tests, or screenshot existence alone. A screen, flow, or release candidate is only clean when the reviewer has inspected the screenshot or live simulator and recorded a Pass verdict for all relevant acceptance criteria.

This is app-wide. Onboarding is not special. The same standard applies to Home, Properties, Track, Reports, Settings, paywalls, exports, empty states, error states, admin-only controls, and subscription recovery.

Required evidence for each visual pass:

- Screenshot path or live simulator step.
- Expected target/action.
- Actual highlighted or tapped UI.
- Pass/Fail verdict.
- Severity for every Fail: P0 blocks core flow, P1 harms App Review or user trust, P2 is visible polish/UX debt, P3 is minor.
- Fix follow-up and rerun screenshot for every Fail.

Use this command to create the baseline visual evidence folder:

```bash
ci_scripts/capture_iphone_e2e_visuals.sh
```

The script writes a dated folder under `docs/e2e-visual-runs/` with screenshots and a `review.md` checklist. The checklist must be completed before the run can be called clean.

## Required Visual Matrix

Every release-candidate QA run must cover these iPhone states:

| Scenario | Home | Properties | Track | Reports | Settings |
| --- | --- | --- | --- | --- | --- |
| First-time user | Required | Required | Required | Required | Required |
| Occasional user | Required | Required | Required | Required | Required |
| Frequent Pro user | Required | Required | Required | Required | Required |

For each screenshot, record:

- Is the screen unstuck and nonblank after launch settles?
- Is the selected tab correct?
- Is the first viewport useful without requiring a scroll to understand the screen?
- Are primary actions visible, tappable, and not hidden by the tab bar or sheets?
- Does the copy match the user's scenario and entitlement?
- Are tax numbers, labels, and goal states internally consistent?
- Is any admin/debug surface hidden from non-admin users?
- Are there obvious visual defects: overlap, clipping, tiny text, low contrast, confusing spotlight, inconsistent controls, or dead-end CTAs?

## Required Flow Matrix

The screenshot matrix is necessary but not sufficient. These flows must also be run with tap-level evidence or marked `BLOCKED` with the exact tooling failure:

- First-time activation: Home -> Properties -> Add Property -> Track -> save first activity.
- Occasional logging: add one activity, verify Home and Reports update consistently.
- Frequent Pro: verify multi-property state, export affordance, and Pro status.
- Subscription recovery: non-Pro sees truthful upgrade/recovery copy; Pro does not see blocked Pro features.
- Calendar import: review import candidates, reject unmatched rows, import valid rows, verify no duplicate import.
- Export: blocked for free users, functional for Pro users with entries, disabled or explained for no-entry state.
- Settings safety: sign out, account deletion entry point, support contact, admin-only debug visibility.

## Verified Locally

- Debug build succeeds on existing iPhone simulator.
- Unit test suite passes: 50 tests, 0 failures.
- Updated app installs and launches on simulator `4AD99860-3D9D-428B-8DAE-975250462395`.
- StoreKit-unavailable state no longer shows a fake Pro price.
- Reports export now uses the same Pro gate as Settings.
- Free-plan copy no longer promises an unenforced monthly entry limit.

## Manual End-to-End Flow

1. Login
   - Use the local QA demo account credentials configured for this machine; do not commit or paste the password.
   - Confirm login copy distinguishes account creation from email login.

2. Onboarding
   - In guided setup, coach copy must match the highlighted element. Example: `Open Properties` must spotlight the Properties tab icon and label, not Home, Track, or empty space.
   - The spotlight must not be clipped by the screen edge, tab bar, or coach card.
   - The dimmed area must leave the intended target visually obvious.
   - The coach card must not hide the target it asks the user to tap.
   - Select each goal once and confirm copy is precise.
   - On property setup, confirm empty property name shows `Skip property setup`.
   - Add a property name and confirm the button changes to `Save property`.
   - On Pro step, confirm unavailable StoreKit shows `Pro availability check`, not a price.
   - Confirm free/trial path can continue without a purchase.

3. Track
   - If no properties exist, Track should explain why a property is required and offer `Add property`.
   - With one property, log mode should default to that property.
   - Disabled Log Time should explain the missing field: property or description.
   - AI suggestion should be reviewable before applying.
   - Timer cancel should confirm with `Discard this timer?`.

4. Reports
   - Goal switcher should update ring, stats, and section copy.
   - REPS should show `Qualified` only when 750h and 50% rule are both satisfied.
   - 100h mode should count properties meeting 100h, not total properties.
   - Locked export icon should open the paywall, not the PDF export sheet.

5. Settings
   - Locked export row should open paywall.
   - Restore Purchase should show progress text and a result alert.
   - Debug unlock should only exist in Debug builds.
   - Sync status should not expose raw CloudKit implementation errors to users.

6. Export
   - Pro-only export should disable when there are no entries.
   - Export copy should describe CPA/records use, not alarming audit language.
   - Generated PDF should say `REPS-counted Hours`, not `REPS Qualified Hours`.

## Remaining Blocker

Email login is currently local/demo-style authentication. Before App Store resubmission, decide whether to:

- Wire real backend authentication and password verification, or
- Remove password-style email login from the App Store build and rely on Sign in with Apple.
