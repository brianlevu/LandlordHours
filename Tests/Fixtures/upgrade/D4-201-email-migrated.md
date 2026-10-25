# D4 · 2.0.1 upgrader: email id kept as the local profile id

Build: LandlordHours 2.0.1 lineage (`188cacd`), Debug. Seed: `-LHSeedLegacyEmailProfile` (2.0.1's
own 1.0.6-shaped seed), after which 2.0.1's `ProfileMigration` moved `emailUserId` to `localProfileId`.
Expect: active group `email-upgrade.tester@example.com` plus a signed-out `email-old.profile@example.com`.

Expected counts (decoded from the captured blobs):

- `email-old.profile@example.com`: 1 entries, 1 properties
- `email-upgrade.tester@example.com`: 5 entries, 2 properties

Captured by `scripts/qa/capture_upgrade_fixture.sh`, re-keyed by `scripts/qa/rekey_fixture.py`.
Do not edit by hand; re-run the capture instead.
