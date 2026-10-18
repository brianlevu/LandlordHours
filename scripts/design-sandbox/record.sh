#!/bin/bash
# usage: lh-record.sh <testName> <outName>
U=${SANDBOX_UDID:?set SANDBOX_UDID to a simboot-leased sim}
OUT=${SANDBOX_OUT:-$HOME/AgentScratch/landlordhours/2026-10-18/hifi-frames-r2}/video
mkdir -p "$OUT"
RAW=/Users/brian/tmp/lh-rec-$2.mov
rm -f "$RAW"
cd /Users/brian/Projects/LandlordHours/.claude/worktrees/agent-a28254a53d48d7705 || exit 2
xcrun simctl io "$U" recordVideo --codec=h264 --force "$RAW" > "/Users/brian/tmp/lh-rec-$2.log" 2>&1 &
RP=$!
REC_START=$(python3 -c 'import time;print(time.time())')
sleep 1
xcodebuild test-without-building -project LandlordHours.xcodeproj -scheme LHDesignSandbox \
  -destination "id=$U" -derivedDataPath /Users/brian/tmp/DerivedData/landlordhours-sandbox \
  -only-testing:LHDesignSandboxUITests/SandboxDemoTests/$1 > "/Users/brian/tmp/lh-test-$2.log" 2>&1
TRC=$?
kill -INT $RP
wait $RP
MARK=$(grep -o "DEMO_START [0-9.]*" "/Users/brian/tmp/lh-test-$2.log" | head -1 | awk '{print $2}')
echo "test rc=$TRC rec_start=$REC_START mark=$MARK"
grep -E "Executed|error:|failed" "/Users/brian/tmp/lh-test-$2.log" | tail -3
OFF=$(python3 -c "print(max(0,${MARK:-0}-$REC_START-4.5))")
ffmpeg -y -loglevel error -ss "$OFF" -i "$RAW" -t 14.5 -vf "fps=30,scale=590:-2" -r 30 -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$OUT/$2.mp4"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/$2.mp4"
