#!/bin/bash
# WP-A full render set, one Blender process at a time (memory is shared on the Mini).
# usage: scripts/render_all.sh <out_dir>     then: scripts/post.py ... (see README)
set -e
OUT="$1"
PY="${PY:-$HOME/AgentScratch/landlordhours/2026-10-18/blender/.venv/bin/python}"
cd "$(dirname "$0")/.."
mkdir -p "$OUT/tools" "$OUT/final"
T0=$(date +%s)
"$PY" scripts/tools.py --out "$OUT/tools" --variants light,dark --res 1024 --samples 96
T1=$(date +%s); echo "PHASE tools $((T1-T0))s"
"$PY" scripts/render.py --states keyframes --variants light,dark --passes built,lines,glow,mask --res 1920 --samples 128 --out "$OUT/final"
T2=$(date +%s); echo "PHASE house $((T2-T1))s"
"$PY" scripts/render.py --anim --row-only --anim-base k14_siding040 --variants light,dark --res 1440 --samples 96 --out "$OUT/final"
T3=$(date +%s); echo "PHASE anim $((T3-T2))s"
echo ALLDONE
