#!/usr/bin/env bash
# capture_upgrade_fixture.sh — capture package K's upgrade fixtures from SHIPPED builds.
#
# Each fixture under Tests/Fixtures/upgrade/<state>/ is the UserDefaults domain (and Application
# Support files) that a real 1.0.6 or 2.0.1 build wrote on a simulator. Nothing is typed by hand:
# the build's own seed path writes the records (1.0.6: its DEBUG `-LHMockScenario`; 2.0.1: its
# DEBUG `-LHMockScenario`, `-LHSeedLegacyEmailProfile`, `-LHSeedWelcomeState`, `-LHSeedSuggestions`).
# The only post-processing is `rekey_fixture.py`, which renames the DEBUG profile ids those seeds
# use (`debug-<scenario>`) to the id kinds real users carry (`email-…`, `local-<UUID>`, an Apple id).
# Values are byte-identical to what the build wrote.
#
# Usage:
#   scripts/qa/capture_upgrade_fixture.sh <sim-udid> <app-1.0.6> <app-2.0.1> <out-dir>
# Build the apps first (detached worktrees at 9c6a25e and 188cacd):
#   xcodebuild build -project LandlordHours.xcodeproj -scheme LandlordHours -configuration Debug \
#     -destination 'generic/platform=iOS Simulator' -derivedDataPath ~/tmp/DerivedData/<lane> CODE_SIGNING_ALLOWED=NO
# The simulator must be booted through simboot.sh. This script never boots or kills anything else.
set -euo pipefail

UDID="$1"; APP106="$2"; APP201="$3"; OUT="$4"
BUNDLE=com.openclaw.landlordhours
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT/raw"

reset_app() {
  xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$1"
}

run_app() {
  # Launch with args, let the seed run and settle, then terminate (cfprefsd flushes on exit).
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep 9
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 4
}

export_state() {
  local name="$1"
  local dir="$OUT/raw/$name"
  mkdir -p "$dir"
  local data
  data="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
  # The app's own preferences file, written by cfprefsd when the app exited (an app-container
  # domain is not reachable through `simctl spawn defaults`).
  cp "$data/Library/Preferences/$BUNDLE.plist" "$dir/defaults.plist"
  plutil -convert xml1 "$dir/defaults.plist"
  if [ -d "$data/Library/Application Support" ]; then
    mkdir -p "$dir/ApplicationSupport"
    for sub in Capture Sync; do
      [ -d "$data/Library/Application Support/$sub" ] && cp -R "$data/Library/Application Support/$sub" "$dir/ApplicationSupport/"
    done
  fi
  echo "captured $name"
}

# --- 1.0.6 (9c6a25e): email "accounts" -------------------------------------------------------
reset_app "$APP106"
run_app -LHMockScenario occasional          # debug-occasional (later: the signed-out email B)
run_app -LHMockScenario frequent            # debug-frequent, active (later: email A, Pro, spouse)
export_state "106-two-email"

reset_app "$APP106"
run_app -LHMockScenario frequent
export_state "106-one-email"

# --- 2.0.1 (188cacd) -----------------------------------------------------------------------------
reset_app "$APP201"
run_app -LHSeedLegacyEmailProfile -LHMockEmail upgrade.tester@example.com
export_state "201-email-migrated"           # 2.0.1 itself migrated emailUserId → localProfileId

reset_app "$APP201"
run_app -LHMockScenario occasional
export_state "201-one-local"

reset_app "$APP201"
run_app -LHMockScenario occasional
run_app -LHMockScenario frequent
export_state "201-two-local"

reset_app "$APP201"
run_app -LHSeedWelcomeState deadEnd         # the half-made "Get started" profile (empty)
run_app -LHMockScenario frequent            # becomes the Apple-signed-in profile after rekey
export_state "201-apple-plus-empty-local"

reset_app "$APP201"
run_app -LHMockScenario emptyMainTabs -LHSeedSuggestions inbox -LHFixedNow 2026-10-16T15:00
export_state "201-suggestions"

xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1 || true

# --- re-key the DEBUG ids to real id kinds --------------------------------------------------------
python3 "$HERE/rekey_fixture.py" "$OUT"
echo "done: $OUT"
