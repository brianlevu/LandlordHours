#!/usr/bin/env bash
# release_flags_check.sh — a Release binary carries no DEBUG `-LH*` launch flags.
#
# Every `-LH…` launch argument is a DEBUG fixture or QA switch and must sit inside `#if DEBUG`, so
# the Release binary holds none of their strings. The 2.3 release gate found `-LHOpenLearningCenter`
# read outside `#if DEBUG` (DashboardView). This check keeps that from coming back.
#
# Two layers: Swift keeps strings of 15 bytes or fewer inline in the code, so `strings` never sees
# short flags such as `-LHInitialTab`. release_flags_source_check.py therefore runs first and fails
# on any `-LH` literal outside `#if DEBUG`; the binary grep below then checks the long ones.
#
# Allowed in Release (one entry, deliberate):
#   -LHAnalyticsForce  Sources/App/Analytics.swift. The opt-in switch that turns analytics ON under
#                      other `-LH` QA flags so event flow can be checked on a QA launch. It only
#                      matters when another `-LH` argument is present, which a store user can't
#                      pass, and it never turns on a fixture, seed or screen.
#
# Usage:
#   scripts/qa/release_flags_check.sh <path to Dormer.app or its binary>
#   scripts/qa/release_flags_check.sh --build [derived-data-path]
#     (builds Release for generic iOS, CODE_SIGNING_ALLOWED=NO, then checks)
# Exit 0 when only allowed entries are present; 1 when an unexpected `-LH` string is found.
set -euo pipefail

ALLOWED=("-LHAnalyticsForce")
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

python3 "$HERE/release_flags_source_check.py" "$ROOT" || exit 1

if [[ "${1:-}" == "--build" ]]; then
  DD="${2:-$HOME/tmp/DerivedData/landlordhours-release-flags}"
  xcodebuild build -project "$ROOT/LandlordHours.xcodeproj" -scheme LandlordHours -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO -quiet
  TARGET="$(find "$DD/Build/Products/Release-iphoneos" -maxdepth 1 -name '*.app' ! -name '*Widget*' | head -1)"
else
  TARGET="${1:?usage: release_flags_check.sh <app-or-binary> | --build [derived-data]}"
fi

if [[ -d "$TARGET" ]]; then
  EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$TARGET/Info.plist")"
  BIN="$TARGET/$EXE"
else
  BIN="$TARGET"
fi
[[ -f "$BIN" ]] || { echo "release_flags_check: no binary at $BIN" >&2; exit 2; }

FOUND="$(strings -a "$BIN" | grep '^-LH' | sort -u || true)"
UNEXPECTED=()
while IFS= read -r flag; do
  [[ -z "$flag" ]] && continue
  ok=0
  for a in "${ALLOWED[@]}"; do [[ "$flag" == "$a" ]] && ok=1; done
  [[ $ok -eq 1 ]] || UNEXPECTED+=("$flag")
done <<< "$FOUND"

echo "release_flags_check: $BIN"
echo "  -LH strings found: $(printf '%s' "$FOUND" | grep -c . || true) (${FOUND//$'\n'/, })"
if (( ${#UNEXPECTED[@]} > 0 )); then
  echo "  FAIL: not allowed in Release (move behind #if DEBUG):" >&2
  printf '    %s\n' "${UNEXPECTED[@]}" >&2
  exit 1
fi
echo "  PASS: only allowed entries (${ALLOWED[*]})"
