#!/bin/bash
# Render the creative-direction screens. usage: SANDBOX_UDID=<simboot udid> capture-directions.sh [dirs...]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${CREATIVE_OUT:-$HOME/AgentScratch/landlordhours/2026-10-18/creative/frames}
SCREENS="today-onpace inbox records onb-welcome empty-today today-onpace-scrolled"
DIRS=${@:-waypoint clayhouse inkwell}
for d in $DIRS; do
  mkdir -p "$ROOT/$d"
  for ap in light dark; do
    # Waypoint: one warm-up pass so MapKit snapshots are cached before the real capture.
    if [ "$d" = "waypoint" ]; then
      SANDBOX_DIRECTION=$d SANDBOX_OUT="$ROOT/$d" "$HERE/capture.sh" $ap records today-onpace >/dev/null
    fi
    SANDBOX_DIRECTION=$d SANDBOX_OUT="$ROOT/$d" "$HERE/capture.sh" $ap $SCREENS | sed "s#^#$d/#"
  done
done
