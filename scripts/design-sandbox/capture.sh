#!/bin/bash
# usage: lh-capture.sh <appearance> [screens...]
U=${SANDBOX_UDID:?set SANDBOX_UDID to a simboot-leased sim}
APP=/Users/brian/tmp/DerivedData/landlordhours-sandbox/Build/Products/Debug-iphonesimulator/LHDesignSandbox.app
OUT=${SANDBOX_OUT:-$HOME/AgentScratch/landlordhours/2026-10-18/hifi-frames-r2}
BID=com.openclaw.landlordhours.designsandbox
AP=$1; shift
SCREENS=${@:-today-behind today-onpace today-onpace-scrolled inbox detail onb-welcome onb-property onb-calendar onb-location lockscreen share records report export paywall locked settings empty-today empty-inbox}
xcrun simctl ui $U appearance $AP
xcrun simctl status_bar $U override --time "9:41" --batteryState discharging --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --operatorName ""
xcrun simctl install $U "$APP"
for s in $SCREENS; do
  xcrun simctl terminate $U $BID 2>/dev/null
  xcrun simctl launch $U $BID -screen $s -appearance $AP >/dev/null
  sleep 4
  xcrun simctl io $U screenshot "$OUT/$s-$AP.png" >/dev/null 2>&1
  echo "$s-$AP"
done
