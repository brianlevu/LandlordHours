#!/usr/bin/env bash
# Gate r3: launch hand-off evidence. Settled first screens (Welcome, Today) after the hand-off ends,
# plus pinned phases (-LHLaunchFreeze) so light and dark sit at the exact same point:
#   midfade = 0.5 (white ink, before the switch), midfade-late = 0.6 (dark ink on light Today).
# One fresh slim sim per theme. Usage: scripts/surfaces-capture-r3.sh <out-dir> <light|dark> [--unit]
set -uo pipefail
OUT=$1; S=$2; UNIT=${3:-}; BID=com.openclaw.landlordhours
DD=/Users/brian/tmp/DerivedData/landlordhours-surfaces
export SIMBOOT_OWNER=wp-surfaces
SB=/Users/brian/.local/share/simboot/simboot.sh
mkdir -p "$OUT"
UDID=$($SB boot "lh-surfaces-r3-$S" "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-0 --wait 30) || { echo "boot failed"; exit 2; }
echo "UDID $UDID"
xcrun simctl ui "$UDID" appearance "$S"
xcrun simctl install "$UDID" "$DD/Build/Products/Debug-iphonesimulator/LandlordHours.app"
shot() { local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$UDID" $BID >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" $BID -LHColorScheme "$S" -AppleLanguages "(en)" -AppleLocale en_US "$@" >/dev/null
  sleep "$wait"; xcrun simctl io "$UDID" screenshot "$OUT/$name-$S.png" >/dev/null 2>&1; echo "$name-$S"; }
shot sp-launch-welcome-settled 7 -LHMockScenario firstTime -LHResetProfilesForTesting
shot sp-launch-today-settled 7 -LHMockScenario occasional
shot sp-launch-to-welcome-midfade 5 -LHMockScenario firstTime -LHResetProfilesForTesting -LHLaunchFreeze 0.5
shot sp-launch-to-today-midfade 5 -LHMockScenario occasional -LHLaunchFreeze 0.5
shot sp-launch-to-today-midfade-late 5 -LHMockScenario occasional -LHLaunchFreeze 0.6
xcrun simctl terminate "$UDID" $BID >/dev/null 2>&1 || true
if [ "$UNIT" = "--unit" ]; then
  cd /Users/brian/tmp/wt-surfaces && xcodebuild -project LandlordHours.xcodeproj -scheme LandlordHours -destination "id=$UDID" \
    -derivedDataPath "$DD" test-without-building -only-testing:LandlordHoursTests \
    -resultBundlePath "$OUT/../surfaces-r3-tools/unit-$(date +%H%M%S).xcresult" 2>&1 | grep -E "Executed [0-9]+ tests.*seconds|TEST EXECUTE|error:" | tail -3
fi
$SB release "$UDID" 2>&1 | tail -1
