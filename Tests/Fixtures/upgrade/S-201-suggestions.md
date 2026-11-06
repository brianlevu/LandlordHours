# 2.0.1 capture inbox file

Build: 2.0.1 (`188cacd`). Seed: `-LHMockScenario emptyMainTabs -LHSeedSuggestions inbox -LHFixedNow 2026-10-16T15:00`;
`Capture/<id>/suggestions.json` re-keyed (folder name) to a `local-<UUID>` id.

Expected counts (decoded from the captured blobs):

- `local-6F1E2D3C-0000-4000-8000-0000000C0533`: 1 entries, 2 properties

Capture inbox file: `S-201-suggestions.local-6F1E2D3C-0000-4000-8000-0000000C0533.suggestions.json`

Captured by `scripts/qa/capture_upgrade_fixture.sh`, re-keyed by `scripts/qa/rekey_fixture.py`.
Do not edit by hand; re-run the capture instead.
