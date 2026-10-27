# D9 · unscoped 1.0.x keys (never signed in after per-user scoping)

Build: 1.0.6 (`9c6a25e`) records, `u.debug-frequent.` prefix stripped (the pre-scoping key names
are the same base names, see `AppViewModel.unscopedLegacyKeys`). Pair with zone case `Z4-ownerless`.
Expect: one `legacy-unscoped` group.

Expected counts (decoded from the captured blobs):

- `(unscoped)`: 97 entries, 3 properties

Captured by `scripts/qa/capture_upgrade_fixture.sh`, re-keyed by `scripts/qa/rekey_fixture.py`.
Do not edit by hand; re-run the capture instead.
