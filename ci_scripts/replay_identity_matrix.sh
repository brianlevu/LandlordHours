#!/usr/bin/env bash
# replay_identity_matrix.sh — package K's test bar in one command (§5).
#
#   ci_scripts/replay_identity_matrix.sh <destination> [<derived-data>] [<pulled-container-dir>]
#
#   <destination>   an xcodebuild destination, e.g. 'platform=iOS Simulator,id=<udid>' or
#                   'platform=iOS,id=00008101-001C5DE43E2BA01E' (iPad 10th gen). Never BLV-Phone.
#   <derived-data>  default ~/tmp/DerivedData/landlordhours-identity-matrix
#   <container>     optional: an app data container pulled after a device run
#                   (xcrun devicectl device copy from --domain-type appDataContainer ...); the
#                   invariant is then recomputed independently by scripts/qa/identity_invariant.py.
#
# Runs: the rules, ledger, upgrade-fixture, state-machine and household-sync unit suites (U1–U38
# against the captured fixtures and the fake zone), the schema-manifest drift test, and the
# identity journey UI tests. Exit non-zero on any failure. Timeouts are never raised to get green.
set -euo pipefail
DEST="$1"
DD="${2:-$HOME/tmp/DerivedData/landlordhours-identity-matrix}"
CONTAINER="${3:-}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
xcodegen generate >/dev/null
xcodebuild build-for-testing -project LandlordHours.xcodeproj -scheme LandlordHours -destination "$DEST" -derivedDataPath "$DD" -quiet
xcodebuild test-without-building -project LandlordHours.xcodeproj -scheme LandlordHours -destination "$DEST" -derivedDataPath "$DD" \
  -only-testing:LandlordHoursTests/MigrationRulesTests \
  -only-testing:LandlordHoursTests/RecordLedgerTests \
  -only-testing:LandlordHoursTests/UpgradeFixtureTests \
  -only-testing:LandlordHoursTests/HouseholdSyncTests \
  -only-testing:LandlordHoursTests/CloudKitSchemaManifestTests \
  -only-testing:LandlordHoursTests/AccountDeleteTests \
  -only-testing:LandlordHoursUITests/IdentityJourneyUITests
if [ -n "$CONTAINER" ]; then
  python3 scripts/qa/identity_invariant.py "$CONTAINER"
fi
echo "identity matrix: PASS on $DEST"
