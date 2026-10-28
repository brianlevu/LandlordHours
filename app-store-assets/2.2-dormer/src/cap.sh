#!/usr/bin/env bash
# cap.sh <udid> <out-dir> <theme>   SHOTS env: lines "shot name wait args..."
set -uo pipefail
UDID=$1; OUT=$2; THEME=${3:-light}; BID=com.openclaw.landlordhours
APP=/Users/brian/tmp/DerivedData/landlordhours-shots/Build/Products/Debug-iphonesimulator/LandlordHours.app
mkdir -p "$OUT"
xcrun simctl ui "$UDID" appearance "$THEME"; xcrun simctl ui "$UDID" content_size large
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi >/dev/null 2>&1
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true >/dev/null 2>&1
[ "${NOINSTALL:-}" = 1 ] || { xcrun simctl uninstall "$UDID" $BID >/dev/null 2>&1; xcrun simctl install "$UDID" "$APP"; }
SEED=(-LHMockScenario emptyMainTabs -LHPropertiesSeed ${PSEED:-layouts3} -LHPropertiesGoal mp100 -LHGoalChoice mp100 -LHSeedSuggestions ${SSEED:-inbox} -LHFakeZone empty -LHColorScheme "$THEME" -AppleLanguages "(en)" -AppleLocale en_US)
shot() { local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$UDID" $BID >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" $BID "${SEED[@]}" "$@" >/dev/null
  sleep "$wait"; xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1; echo "$name"; }
eval "$SHOTS"
xcrun simctl terminate "$UDID" $BID >/dev/null 2>&1 || true
