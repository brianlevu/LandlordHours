# D3 · 1.0.6 signed out, two email profiles on the device

Build: 1.0.6 (`9c6a25e`). Seed: `-LHMockScenario occasional`, then `-LHMockScenario frequent`;
re-keyed to two email ids; the sign-in keys removed (what 1.0.6 sign-out leaves).
Expect: two non-empty groups; the larger is primary; the two-sets question for the other.

Expected counts (decoded from the captured blobs):

- `email-old.profile@example.com`: 10 entries, 1 properties
- `email-upgrade.tester@example.com`: 97 entries, 3 properties

Captured by `scripts/qa/capture_upgrade_fixture.sh`, re-keyed by `scripts/qa/rekey_fixture.py`.
Do not edit by hand; re-run the capture instead.
