# D7 · 2.0.1 Apple sign-in plus the empty "Get started" profile (Brian's 2.0 shape)

Build: 2.0.1 (`188cacd`). Seed: `-LHSeedWelcomeState deadEnd` (empty `local-welcome-fixture`), then
`-LHMockScenario frequent`, re-keyed to an Apple id under `appleUserId`.
Expect: one non-empty group (the Apple id); the empty local group dropped silently.

Expected counts (decoded from the captured blobs):

- `001234.k7f1xture0a00000000000000000000.0101`: 97 entries, 3 properties

Captured by `scripts/qa/capture_upgrade_fixture.sh`, re-keyed by `scripts/qa/rekey_fixture.py`.
Do not edit by hand; re-run the capture instead.
