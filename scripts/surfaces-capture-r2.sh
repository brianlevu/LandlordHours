#!/usr/bin/env bash
# Gate r2 recaptures, one FRESH slim sim per theme (appearance set before install, so the dark
# frames come from a dark boot and Springboard has no remembered notification-group state).
# Usage: scripts/surfaces-capture-r2.sh <out-dir> <light|dark>
set -uo pipefail
OUT=$1; S=$2; BID=com.openclaw.landlordhours
DD=/Users/brian/tmp/DerivedData/landlordhours-surfaces
export SIMBOOT_OWNER=wp-surfaces
SB=/Users/brian/.local/share/simboot/simboot.sh
mkdir -p "$OUT"
UDID=$($SB boot "lh-surfaces-$S" "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-0 --wait 30) || { echo "boot failed"; exit 2; }
echo "UDID $UDID"
xcrun simctl ui "$UDID" appearance "$S"
xcrun simctl install "$UDID" "$DD/Build/Products/Debug-iphonesimulator/LandlordHours.app"
shot() { local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$UDID" $BID >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" $BID -LHColorScheme "$S" -AppleLanguages "(en)" -AppleLocale en_US "$@" >/dev/null
  sleep "$wait"; xcrun simctl io "$UDID" screenshot "$OUT/$name-$S.png" >/dev/null 2>&1; echo "$name-$S"; }
shot sp-launch-storyboard 4 -LHSurfaceBoard launch-storyboard
shot sp-launch-first-frame 5 -LHMockScenario occasional -LHLaunchFreeze 0
shot sp-launch-to-today 5 -LHMockScenario occasional -LHLaunchFreeze 0.6
shot sp-launch-to-welcome 5 -LHMockScenario firstTime -LHResetProfilesForTesting -LHLaunchFreeze 0.6
shot sp-siri 4 -LHSurfaceBoard siri
xcrun simctl terminate "$UDID" $BID >/dev/null 2>&1 || true
cd /Users/brian/tmp/wt-surfaces
TEST_RUNNER_LH_SHOT_DIR="$OUT" TEST_RUNNER_LH_SCHEME="$S" xcodebuild -project LandlordHours.xcodeproj -scheme LandlordHours \
  -destination "id=$UDID" -derivedDataPath "$DD" test-without-building \
  -only-testing:LandlordHoursUITests/SurfacesNotificationUITests \
  -resultBundlePath "$OUT/../surfaces-r2-tools/notif-$S-$(date +%H%M%S).xcresult" 2>&1 | grep -E "TEST EXECUTE|error:.*Surfaces"
$SB release "$UDID" 2>&1 | tail -1
