#!/bin/bash
# Round-3 concept renders. usage: SANDBOX_UDID=<simboot udid> capture-concepts.sh [concepts...]
set -u
U=${SANDBOX_UDID:?set SANDBOX_UDID to a simboot-leased sim}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${CONCEPT_OUT:-$HOME/AgentScratch/landlordhours/2026-10-18/creative-r3/frames}
BID=com.openclaw.landlordhours.designsandbox
CONCEPTS=${@:-blueprint porchlight tilework}

burst() {  # concept appearance screen prefix delays...
  local c=$1 ap=$2 screen=$3 prefix=$4; shift 4
  xcrun simctl terminate "$U" $BID 2>/dev/null
  xcrun simctl launch "$U" $BID -screen "$screen" -appearance "$ap" -LHConcept "$c" >/dev/null
  local t0 now
  t0=$(python3 -c 'import time;print(time.time())')
  for d in "$@"; do
    python3 -c "import time;t=$t0+$d-time.time();time.sleep(t if t>0 else 0)"
    xcrun simctl io "$U" screenshot "$ROOT/$c/$prefix-${d}s-$ap.png" >/dev/null 2>&1
    echo "$c/$prefix-${d}s-$ap"
  done
}

for c in $CONCEPTS; do
  mkdir -p "$ROOT/$c"
  for ap in light dark; do
    if [ "$c" = "blueprint" ]; then
      SANDBOX_CONCEPT=$c SANDBOX_OUT="$ROOT/$c" "$HERE/capture.sh" $ap concept-today inbox concept-welcome concept-lockscreen concept-empty | sed "s#^#$c/#"
      burst $c $ap concept-milestone milestone 0.6 1.15 1.5 3.5
      burst $c $ap concept-backfill backfill 0.5 1.4 2.6 4.6
    else
      SANDBOX_CONCEPT=$c SANDBOX_OUT="$ROOT/$c" "$HERE/capture.sh" $ap concept-today | sed "s#^#$c/#"
    fi
    burst $c $ap concept-confirm confirm 1.2 1.95 2.25 3.6
  done
done
