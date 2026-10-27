# D8 · 2.0.1 two local profiles with records (Switch profile)

Build: 2.0.1 (`188cacd`). Seed: `-LHMockScenario occasional`, then `-LHMockScenario frequent`;
re-keyed to two `local-<UUID>` ids; `previousProfileId` names the first.
Expect: two non-empty groups; the two-sets question.

Expected counts (decoded from the captured blobs):

- `local-6F1E2D3C-0000-4000-8000-0000000C0A01`: 10 entries, 1 properties
- `local-6F1E2D3C-0000-4000-8000-0000000C0B02`: 97 entries, 3 properties

Captured by `scripts/qa/capture_upgrade_fixture.sh`, re-keyed by `scripts/qa/rekey_fixture.py`.
Do not edit by hand; re-run the capture instead.
