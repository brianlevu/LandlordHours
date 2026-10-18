#!/bin/bash
# Record an autoplaying concept screen. usage: SANDBOX_UDID=.. record-concept.sh <concept> <screen> <seconds> <name> [appearance]
set -u
U=${SANDBOX_UDID:?set SANDBOX_UDID}
C=$1; S=$2; SECS=$3; NAME=$4; AP=${5:-light}
OUT=${CONCEPT_OUT:-$HOME/AgentScratch/landlordhours/2026-10-18/creative-r3/frames}/$C/video
BID=com.openclaw.landlordhours.designsandbox
mkdir -p "$OUT"
RAW=$HOME/tmp/lh-rec-$NAME.mov
rm -f "$RAW"
xcrun simctl ui "$U" appearance "$AP"
xcrun simctl terminate "$U" $BID 2>/dev/null
xcrun simctl io "$U" recordVideo --codec=h264 --force "$RAW" > /dev/null 2>&1 &
RP=$!
sleep 1.5
xcrun simctl launch "$U" $BID -screen "$S" -appearance "$AP" -LHConcept "$C" > /dev/null
sleep "$SECS"
kill -INT $RP
wait $RP
# Trim the pre-launch home screen (first ~1.2 s), constant 30 fps.
ffmpeg -y -loglevel error -ss 1.3 -i "$RAW" -t "$SECS" -vf "tpad=stop_mode=clone:stop_duration=$SECS,fps=30,scale=590:-2" -r 30 -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$OUT/$NAME.mp4"
rm -f "$RAW"
echo "$OUT/$NAME.mp4 $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/$NAME.mp4")s"
