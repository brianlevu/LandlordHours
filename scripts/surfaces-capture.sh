#!/usr/bin/env bash
# 2.0 surfaces captures: production views (DEBUG boards + real shell toasts + real launch storyboard).
# Usage: scripts/surfaces-capture.sh <udid> <out-dir>   (app already installed on <udid>)
set -euo pipefail
UDID=$1; OUT=$2; BID=com.openclaw.landlordhours
mkdir -p "$OUT"
shot() { # name scheme sleep args...
  local name=$1 scheme=$2 wait=$3; shift 3
  xcrun simctl ui "$UDID" appearance "$scheme" >/dev/null
  xcrun simctl terminate "$UDID" $BID >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" $BID -LHColorScheme "$scheme" -AppleLanguages "(en)" -AppleLocale en_US "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name-$scheme.png" >/dev/null 2>&1
  echo "$name-$scheme"
}
for s in light dark; do
  for b in widgets-home-a widgets-home-b widgets-home-c widgets-tinted widgets-lock toast-board siri launch-storyboard; do
    shot "sp-$b" $s 4 -LHSurfaceBoard $b
  done
  shot sp-toast-board-xxl $s 4 -LHSurfaceBoard toast-board -LHTypeSize xxl
  shot sp-toast-board-ax3 $s 4 -LHSurfaceBoard toast-board -LHTypeSize ax3
  shot sp-siri-xxl $s 4 -LHSurfaceBoard siri -LHTypeSize xxl
  shot sp-siri-ax3 $s 4 -LHSurfaceBoard siri -LHTypeSize ax3
  # Real shell toasts (Today with data, Properties for the added property).
  for t in saveError loadError timerDiscarded undo; do
    shot "sp-toast-$t" $s 6 -LHMockScenario occasional -LHInitialTab 0 -LHDebugToast $t
  done
  shot sp-toast-propertyAdded $s 6 -LHMockScenario occasional -LHInitialTab 1 -LHDebugToast propertyAddedLong
  shot sp-toast-saveError-ax3 $s 6 -LHMockScenario occasional -LHInitialTab 0 -LHDebugToast saveError -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
  # Launch hand-off frozen: first frame (= storyboard), mid-way to Today, mid-way to Welcome.
  shot sp-launch-first-frame $s 5 -LHMockScenario occasional -LHLaunchFreeze 0
  shot sp-launch-to-today $s 5 -LHMockScenario occasional -LHLaunchFreeze 0.6
  shot sp-launch-to-welcome $s 5 -LHMockScenario firstTime -LHResetProfilesForTesting -LHLaunchFreeze 0.6
  shot sp-launch-today-settled $s 6 -LHMockScenario occasional
done
xcrun simctl terminate "$UDID" $BID >/dev/null 2>&1 || true
