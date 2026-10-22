#!/bin/bash
# usage: cap.sh <udid> <name> <wait> args...
U=$1; N=$2; W=$3; shift 3; BID=com.openclaw.landlordhours
OUT=/Users/brian/AgentScratch/landlordhours/2026-10-22/appstore/rawpad
xcrun simctl terminate $U $BID >/dev/null 2>&1
xcrun simctl launch $U $BID -LHColorScheme light -AppleLanguages "(en)" -AppleLocale en_US -LHNoSwipePeek -LHResetProfilesForTesting "$@" >/dev/null
sleep $W; xcrun simctl io $U screenshot $OUT/$N.png >/dev/null 2>&1; echo $N
