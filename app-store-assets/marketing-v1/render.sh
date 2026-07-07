#!/usr/bin/env bash
# Renders the LandlordHours App Store screenshot set (marketing-v1) at both
# ASC phone slots. Requires: playwright (Chromium).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTML="$DIR/index.html"
OUT="$DIR/exports"
mkdir -p "$OUT/iphone-6.9" "$OUT/iphone-6.5"
panels=(hero track goalmet portfolio honest)
i=1
for panel in "${panels[@]}"; do
  n=$(printf "%02d" "$i")
  playwright screenshot --viewport-size=1320,2868 --wait-for-timeout=400 \
    "file://$HTML?panel=$panel" "$OUT/iphone-6.9/$n-$panel.png"
  playwright screenshot --viewport-size=1284,2778 --wait-for-timeout=400 \
    "file://$HTML?panel=$panel" "$OUT/iphone-6.5/$n-$panel.png"
  echo "rendered $panel"
  i=$((i+1))
done
