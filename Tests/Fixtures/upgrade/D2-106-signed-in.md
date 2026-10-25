# D2 · 1.0.6 signed in (email account)

Build: LandlordHours 1.0.6 (`9c6a25e`, build 202608260402), Debug, simulator iOS 27.0.
Seed: `-LHMockScenario frequent` (1.0.6's own seed), re-keyed `debug-frequent` → `email-upgrade.tester@example.com`.
Expect: one group, Pro on, spouse tracking on, onboarding complete, no Welcome after 2.2.

Expected counts (decoded from the captured blobs):

- `email-upgrade.tester@example.com`: 97 entries, 3 properties

Captured by `scripts/qa/capture_upgrade_fixture.sh`, re-keyed by `scripts/qa/rekey_fixture.py`.
Do not edit by hand; re-run the capture instead.
