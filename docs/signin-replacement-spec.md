# Spec: Replace fake email sign-in with local profiles (1.1)

Date: 2026-10-17 · Status: rev 2 (reviewer must-fixes folded in) · Scope: 1.1

## Decision

Keep every existing email user's **profile ID exactly as it is** and stop calling it an account. The ID `email-<address>` becomes an opaque local profile ID, so no data key, attachment file or CloudKit record moves. 1.1 removes the email forms and offers "Sign in with Apple" or "Continue without an account". Old email profiles found on the device **or in iCloud** can be restored with one tap, from the welcome screen or from Settings. Linking to Sign in with Apple waits for 1.2 (it's a merge problem).

## How data is keyed today (evidence)

- **Profile ID:** `UserScope.userId` = `appleUserId ?? emailUserId` (AppViewModel.swift:15-18). Email "sign-in" sets `emailUserId = "email-" + email` and ignores the password (AppleSignIn.swift:127-140).
- **UserDefaults:** all user data lives under `u.<userId>.<base>` (AppViewModel.swift:21-31). That covers entries, properties, timer, Pro, categories, goals, tax profile, onboarding and CloudKit tokens (CloudKitSyncService.swift:50-54).
- **Attachments:** files at `Application Support/Attachments/<uuid>.<ext>`, not keyed by user (Models.swift:231-262). **They never sync.** `entryToRecord` has no attachment field (CloudKitSyncService.swift:562-577).
- **CloudKit:** one private zone. Records are named by UUID and tagged with `appUserId`, plus `GoalSettings-<id>` and `TaxProfile-<id>` (:642, :659). Pull drops records from other users (:287-297). So today a reinstall or new-phone user gets their iCloud data back by typing their email.
- **Sign-out:** clears auth keys; per-user data stays (AppViewModel.swift:149-163).
- **Delete:** removes CloudKit records by ID and by an `appUserId` query (:494-531), then scoped keys (AppViewModel.swift:189-226, :350-382). Gaps:
  - Attachment files and `notification.lastScheduled.*` keys are not deleted.
  - When iCloud is unavailable, cloud records are silently left behind (:203-213).

## Is local mode already supported?

No. With no profile ID, `UserScope.key` falls back to **unscoped** keys (:21-23), and ContentView forces `LoginView` (ContentView.swift:121-122). Scoped storage, sync, reset and delete already work for any opaque ID.

## Recommended design

1. **Identity:**
   - A new unscoped key, `localProfileId`.
   - `UserScope.userId` = `appleUserId ?? localProfileId ?? emailUserId`. The last one is a read-only legacy fallback.
   - `LoginType` gains `.local`, and the stored value `"email"` still decodes.
2. **Migration** runs first in `AppViewModel.init`, before `migrateUnscopedLegacyData`, as `static func migrateEmailProfile(defaults:)`.
   - If `appleUserId` is set, do nothing.
   - If `emailUserId = X` and `localProfileId` is unset:
     1. Write `localProfileId = X`, `localProfileName/Email` and `loginType = local`.
     2. Then delete `emailUserId/Name/Email`.
   - Every intermediate state resolves to X: crash-safe and idempotent, following the persistence-hardening pattern.
3. **Every consumer of the email keys gets a local-profile branch:**
   - `checkSignInState` (AppViewModel.swift:100-108)
   - `checkExistingSignIn` (AppleSignIn.swift:117)
   - the `signIn` name lookup (AppViewModel.swift:130)
   - `updateProfile` (AppleSignIn.swift:153, :163)
   - `AdminAccess.currentEmail` (AppleSignIn.swift:80; only gates DEBUG tools)
   - the DEBUG mock (AppViewModel.swift:1237-1244)
   - `signOut` in both AppleSignIn.swift:173 and AppViewModel.swift:149 (also clears `localProfile*`)
4. **Profile discovery** returns `email-*` profiles that aren't active, from two sources:
   - **Device:** keys `u.email-*.LandlordHours.entries` or `.properties` in `dictionaryRepresentation()`.
   - **iCloud:** a discovery-only zone fetch with no change token. It groups records by `appUserId` with the `email-` prefix and counts them. It's a separate method, since the normal pull drops other users' records (:287-297). It needs no new index; offline gives device-only results.
   - Merged by ID; each shows masked email, entry count, last date and source.
5. **Restore:**
   - Set `localProfileId = X`, then run `signIn()`.
   - For a profile that exists only in iCloud, **first set `u.X.cloudkit.migrationDone = true`**. Otherwise `start()` pushes empty local state before pulling (CloudKitSyncService.swift:84-87), and default `GoalSettings-X`/`TaxProfile-X` records overwrite the cloud copies.
   - Attachments can't come back from iCloud. The UI says so.
6. **Welcome screen:** Sign in with Apple, "Continue without an account", and a "Restore earlier data" row when discovery finds profiles.
   - "Continue" creates `local-<UUID>`, sets the ID, calls `migrateUnscopedLegacyData()`, then clears the onboarding flag and calls `signIn()`. It must **not** call `signUp()`, which wipes unscoped legacy data (AppViewModel.swift:143).
   - Remove `signInWithEmail` and the email forms (AppleSignIn.swift:127-148, :555, :680), and the "email sign-up" error copy (:52).
7. **Settings (signed in):**
   - **"Switch profile"** replaces sign-out for local profiles. It shows a confirm that says data stays on this device.
   - **"Restore other data"** row: visible whenever discovery finds an inactive `email-*` profile, including for Apple-ID users. Picking one switches to it. Merging into the Apple profile is not offered in 1.1.
8. **Sign-out ordering fix:** `saveTimerState()` currently runs after the auth keys are cleared (AppViewModel.swift:162 then :170), so it writes timer state to unscoped keys. Stop the timer and save before clearing the ID.
9. **Delete:**
   - Apple profiles keep "Delete Account and Data". Local profiles get "Delete All Data", which uses the same path and also clears `localProfileId`.
   - Both delete attachment files and notification keys.
   - When iCloud is unavailable, don't proceed silently. Ask: "iCloud is off, so copies saved there can't be removed now. Delete from this iPhone anyway, or turn on iCloud and retry?"

## App Review

- **5.1.1(v):** Sign in with Apple is still account creation, so in-app deletion stays (SettingsView.swift:1120-1172). This change makes deletion more complete: files, plus the iCloud-off case. Pre-existing gap: no Sign in with Apple token revocation. It needs a server (Q3).
- **5.1.1(i):** no-account mode removes forced login, which is an improvement.
- **Onboarding** works with no account; Pro uses `Transaction.currentEntitlements` (SubscriptionManager.swift:75), so local users can buy and restore.

## Test plan

**Unit tests** (UserDefaults suite and a temp `AttachmentStore`, as at LandlordHoursTests.swift:1133 and :1537; CloudKit discovery behind a protocol with a fake):
1. Email profile → `localProfileId == X`, email keys gone, `u.X.*` unchanged.
2. Apple profile, with or without a stale `emailUserId` → defaults unchanged.
3. Crash midway (both keys set) → re-run finishes, and the ID is still X.
4. Run twice → no change.
5. Device discovery with two email profiles and one Apple profile → returns the two, with correct counts.
6. iCloud discovery with fake records under `email-a`, `email-b` and the active ID → returns the inactive two. Merging with device results removes duplicates.
7. iCloud-only restore → `migrationDone` is set before `start()`. The fake records zero pushes before the first pull.
8. "Continue" → `local-<UUID>`, unscoped legacy data migrated rather than wiped, onboarding keys scoped.
9. Sign-out → no unscoped `LandlordHours.timer` key afterwards.
10. Local delete → keys, files and `localProfileId` gone; other profiles intact.
11. Delete with iCloud unavailable → error state is raised, not a silent success.
12. Each branch in design item 3 resolves name and email for a local profile.

**Device journey QA** (iPad 10th gen, iOS 27, a real upgrade from 1.0.6, iCloud signed in):
1. On 1.0.6: email A with 2 properties, 5 entries and 1 photo; sign out; email B with 1 entry; stay signed in.
2. Install 1.1 over it. B's data shows with no prompt, and there's no email login anywhere.
3. Settings → Restore other data → switch to A; entries and photo are back.
4. Delete the app, reinstall 1.1, then Restore earlier data. A and B appear "in iCloud". Restore A: entries, goals and tax profile match, and the photo-not-synced note shows.
5. Apple-ID device with an old email profile → no prompt at launch; the Settings row appears.
6. Fresh install → Continue → onboarding → log an entry → force-quit → data persists.
7. iCloud off → Delete → the warning appears.
8. Airplane mode on first 1.1 launch → migration completes; discovery shows device results only.

## Open questions for Brian

1. **iCloud wording for local profiles.** *Recommend: "Hours, properties and settings sync to your iCloud. Photos stay on this iPhone." Not "backup". Photo sync (CKAsset) is a 1.2 item.*
2. **Should Apple-ID users be able to merge an old email profile into their Apple profile?** *Recommend: not in 1.1. Switching is enough; merging is part of 1.2 linking.*
3. **Sign in with Apple token revocation server in 1.1?** *Recommend: no. It's pre-existing; track it for 1.2.*
4. **Restore list privacy:** *Recommend: masked email (`b•••@gmail.com`), plus counts and dates.*

## Implementation checklist (~28 h)

- [ ] `UserScope`, `.local`, `localProfile*` keys — 1 h
- [ ] `migrateEmailProfile(defaults:)` and the init call — 2 h
- [ ] Local branches for every email-key consumer (item 3) — 2 h
- [ ] Device discovery — 1.5 h
- [ ] iCloud discovery method and merge — 3 h
- [ ] Restore flow, including the push-before-pull guard — 2 h
- [ ] Welcome screen rewrite and "Continue" path — 3 h
- [ ] Settings: Switch profile, Restore other data, Delete All Data — 2.5 h
- [ ] Sign-out ordering fix, delete completeness, iCloud-off warning — 1.5 h
- [ ] Unit tests 1-12 — 4.5 h
- [ ] Device upgrade and reinstall journey by an independent verifier — 3.5 h
- [ ] Visual gate on welcome, restore and Settings — 1 h
- [ ] App Review notes and What's New — 0.5 h
