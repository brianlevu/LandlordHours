# Spec: Persistence hardening — file-based attachments + surfaced save errors

Date: 2026-07-07 · Owner: Brian · Status: approved for 1.0.4

## Problem

The full dataset — properties, entries, and every photo attachment as inline `Data` (`Models.swift` ~141-156) — is encoded as JSON blobs into `UserDefaults` with `try?` (`AppViewModel.swift` ~751-756). When the blob grows past UserDefaults' practical limits (photos guarantee it will), encoding fails silently: the user keeps logging, nothing saves, no error. For a tax-evidence app that is the worst possible failure. Photos are also excluded from CloudKit sync (`CloudKitSyncService.swift` ~185), so they die with the device, and nothing tells the user.

## Changes (locked)

1. **File-based attachments.** Store attachment bytes as files under `Application Support/Attachments/<attachment-uuid>.jpg` (or original extension). `TimeAttachment` keeps its identity/metadata; bytes load lazily from disk. Keep a legacy optional `data` decode path so old blobs still decode (migration rule: existing data never regresses).
2. **One-time migration.** On first load after update: decode legacy inline `data`, write each to its file, drop inline bytes from the persisted blob, re-save. Must be idempotent and safe against partial completion (crash mid-migration → next launch finishes it; never delete inline data before its file write is verified).
3. **Surfaced save errors.** Replace `try?` with do/catch on all save/load paths in `AppViewModel`. On failure: log via `os.log` `Logger` and set a published error state rendered as a non-blocking banner ("Couldn't save your latest changes — free up space and try again" style, existing toast/banner component). Load-failure of a corrupt blob must not crash and must not silently present an empty dataset as if it were real — surface it.
4. **Honest disclosure.** Where photos are attached (TimeLogView / entry detail) and in Settings, one sentence: photos are stored on this device only and are not included in iCloud sync. No design changes beyond design-system components.
5. **CloudKit untouched** except that sync must keep working with the new attachment model (it already excludes attachment bytes).

## Explicitly out of scope

CloudKit CKAsset photo sync, CSV export, AppViewModel decomposition. Do not refactor beyond what the above requires.

## Acceptance criteria

- Unit tests: save/load round-trip (properties + entries + attachments); legacy-blob migration (inline data → files, idempotent, re-runs safely); corrupt-blob load surfaces error without crash or silent empty state; save-failure path sets the published error. Plus tax-year boundary tests for `entriesForYear` (Dec 31 23:00 local, Jan 1, prior-year exclusion) since persistence and year-scoping share the data path.
- Build succeeds and full unit suite passes via the repo lane.
- Simulator journey check: attach a photo to an entry, force-quit, relaunch, photo still renders; disclosure text visible.
- No fixtures/placeholders in production paths; no new `try?` on persistence paths.

## Acceptance environment

iPhone simulator per repo lane config; unit suite; fresh captures/journey run, not archived screenshots.
