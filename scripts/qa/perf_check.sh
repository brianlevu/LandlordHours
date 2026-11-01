#!/bin/bash
# Repeatable performance + crash check for Dormer (LandlordHours).
#
# Runs UITests/PerfMetricsUITests.swift (launch, tab switches, Records scroll hitches, Log time,
# PDF export; clock + memory + launch + scroll-signpost metrics) on ONE destination, then writes a
# summary (results.json + results.md) and checks for crashes. Compare two runs with
# scripts/qa/perf_compare.py (a >10% regression or any crash fails).
#
# Usage:
#   scripts/qa/perf_check.sh --label v2.2-iphone-sim --sim iphone
#   scripts/qa/perf_check.sh --label v2.2-ipad-sim   --sim ipad
#   scripts/qa/perf_check.sh --label v2.2-ipad10     --device 00008101-001C5DE43E2BA01E
#
# Options:
#   --label NAME        run name; also the output folder name (required)
#   --sim iphone|ipad   boot a throwaway simulator through simboot (iPhone 16 Plus / iPad 10th gen,
#                       iOS 26.5, the closest match to the lab devices)
#   --device UDID       run on a physical device. Refused when the claims file shows another
#                       session holding it; refuses BLV-Phone and the stale iPad Air.
#   --iterations N      measured iterations per test (default 5)
#   --only NAME         one test method, e.g. testColdLaunchToToday (default: all)
#   --derived-label L   reuse the DerivedData of an earlier run labelled L (incremental build)
#   --src DIR           checkout to build (default: the repo this script lives in). To baseline a
#                       release, point it at a worktree of that tag with this test file copied in.
#   --out DIR           output root (default ~/AgentScratch/landlordhours-perf/<date>)
#
# Rules this script keeps (ios-dev-harness): simulators only through simboot and released on every
# exit; devices claimed in claims.tsv and released on exit; DerivedData under ~/tmp/DerivedData;
# only PIDs this script started are ever signalled.
#
# Numbers are DEBUG-build numbers (the fixtures the UI tests use are DEBUG-only). Compare a build
# only to another build measured the same way on the same destination, under similar host load.
set -o pipefail
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$SELF_DIR/../.." && pwd)"
LABEL=""; SIM=""; DEVICE=""; ITER=5; ONLY=""; DERIVED_LABEL=""
OUT_ROOT="$HOME/AgentScratch/landlordhours-perf/$(date +%Y-%m-%d)"
SIMBOOT=/Users/brian/.local/share/simboot/simboot.sh
CLAIMS=/Users/brian/.local/share/device-claims/claims.tsv
RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-26-5
BLOCKED_DEVICES="00008140-001C682C0E7B001C 00008132-000A01823AA2401C"   # BLV-Phone, stale iPad Air pairing

die() { echo "perf_check: $*" >&2; exit "${2:-2}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="$2"; shift 2;;
    --sim) SIM="$2"; shift 2;;
    --device) DEVICE="$2"; shift 2;;
    --iterations) ITER="$2"; shift 2;;
    --only) ONLY="$2"; shift 2;;
    --derived-label) DERIVED_LABEL="$2"; shift 2;;
    --src) SRC="$(cd "$2" && pwd)"; shift 2;;
    --out) OUT_ROOT="$2"; shift 2;;
    -h|--help) sed -n 2,32p "$0"; exit 0;;
    *) die "unknown option $1";;
  esac
done
[ -n "$LABEL" ] || die "--label is required"
{ [ -n "$SIM" ] || [ -n "$DEVICE" ]; } || die "pass --sim iphone|ipad or --device UDID"
{ [ -n "$SIM" ] && [ -n "$DEVICE" ]; } && die "pass only one of --sim / --device"

OUT="$OUT_ROOT/$LABEL"
mkdir -p "$OUT" || die "cannot create $OUT"
DERIVED="$HOME/tmp/DerivedData/landlordhours-perf-${DERIVED_LABEL:-$LABEL}"
OWNER="perf-$LABEL-$$"
STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"   # local time, for find -newermt
SIM_UDID=""; CLAIMED=0

cleanup() {
  if [ -n "$SIM_UDID" ]; then
    "$SIMBOOT" release "$SIM_UDID" --owner "$OWNER" >>"$OUT/simboot.log" 2>&1
    SIM_UDID=""
  fi
  if [ "$CLAIMED" = 1 ]; then
    python3 -I - "$CLAIMS" "$DEVICE" "$OWNER" <<'PY'
import sys, datetime
path, udid, owner = sys.argv[1:4]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
rows = open(path).read().split("\n")
for i in range(len(rows) - 1, -1, -1):
    c = rows[i].split("\t")
    if len(c) >= 5 and c[0] == udid and c[2] == owner and (len(c) < 6 or not c[5].strip()):
        rows[i] = "\t".join(c[:5] + [now + " (RELEASED: perf_check finished; nothing installed or deleted beyond the test bundle)"])
        break
open(path, "w").write("\n".join(rows))
PY
    CLAIMED=0
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ---- sanity: the test file must be in the checkout ---------------------------------------------
[ -f "$SRC/UITests/PerfMetricsUITests.swift" ] || die "$SRC has no UITests/PerfMetricsUITests.swift (copy it in for a release baseline)"

# ---- project: add the test file to the Xcode project if needed ----------------------------------
if ! grep -q PerfMetricsUITests "$SRC/LandlordHours.xcodeproj/project.pbxproj"; then
  echo "[perf] xcodegen generate (new test file not in the project yet)"
  (cd "$SRC" && xcodegen generate >"$OUT/xcodegen.log" 2>&1) || die "xcodegen failed, see $OUT/xcodegen.log"
fi

# ---- destination (device: claim now; simulator: boot just before the test so the build never holds a slot)
if [ -z "$SIM" ]; then
  for b in $BLOCKED_DEVICES; do [ "$b" = "$DEVICE" ] && die "$DEVICE is never used for tests"; done
  if awk -F'\t' -v u="$DEVICE" '$1==u && $6=="" {f=1} END{exit !f}' "$CLAIMS"; then
    die "$DEVICE is claimed by another session (open row in $CLAIMS); skipping" 3
  fi
  printf '%s\t%s\t%s\t%s\t%s\t\n' "$DEVICE" "device" "$OWNER" "perf_check $LABEL (no app/data deletion)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$CLAIMS"
  CLAIMED=1
  xcrun devicectl device info lockState --device "$DEVICE" >"$OUT/lockstate.log" 2>&1
  grep -q '"passcodeRequired" : true' "$OUT/lockstate.log" && die "$DEVICE is locked; unlock it and retry" 3
  DEST="id=$DEVICE"
  DESTNAME="device $DEVICE"
fi

# ---- build ----------------------------------------------------------------------------------
SIGN=()
if [ -n "$DEVICE" ]; then
  SIGN=(-allowProvisioningUpdates
        -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_QTQXKZ5CN8.p8"
        -authenticationKeyID QTQXKZ5CN8
        -authenticationKeyIssuerID ab32fd62-caed-497e-bb3f-d2b444bd74d7)
fi
BUILD_DEST="${DEST:-generic/platform=iOS Simulator}"
echo "[perf] build-for-testing (log: $OUT/build.log)"
xcodebuild build-for-testing -quiet \
  -project "$SRC/LandlordHours.xcodeproj" -scheme LandlordHours \
  -destination "$BUILD_DEST" -derivedDataPath "$DERIVED" \
  ${SIGN[@]+"${SIGN[@]}"} >"$OUT/build.log" 2>&1
RC=$?
[ $RC -eq 0 ] || { tail -20 "$OUT/build.log"; die "build failed rc=$RC (rc=137 with an empty log means the Bash sandbox killed xcodebuild; run with the sandbox off)" 4; }

if [ -n "$SIM" ]; then
  case "$SIM" in
    iphone) TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus; NAME="perf-iphone-$$";;
    ipad)   TYPE=com.apple.CoreSimulator.SimDeviceType.iPad-10th-generation; NAME="perf-ipad-$$";;
    *) die "--sim takes iphone or ipad";;
  esac
  echo "[perf] booting $NAME ($TYPE) through simboot"
  SIM_UDID="$("$SIMBOOT" boot "$NAME" "$TYPE" "$RUNTIME" --owner "$OWNER" --wait 45 2>>"$OUT/simboot.log" | tail -1)"
  case "$SIM_UDID" in
    [0-9A-F]*-*-*-*-*) ;;
    *) SIM_UDID=""; die "simboot did not return a UDID, see $OUT/simboot.log" 3;;
  esac
  DEST="id=$SIM_UDID"
  DESTNAME="simulator $SIM ($RUNTIME)"
fi

# ---- test -----------------------------------------------------------------------------------
ONLYARG="LandlordHoursUITests/PerfMetricsUITests"
[ -n "$ONLY" ] && ONLYARG="$ONLYARG/$ONLY"
RESULT="$OUT/result.xcresult"
[ -e "$RESULT" ] && RESULT="$OUT/result-$(date +%H%M%S).xcresult"   # xcodebuild refuses to overwrite
echo "[perf] test-without-building, $ITER iterations (log: $OUT/test.log)"
TEST_RUNNER_PERF_ITERATIONS="$ITER" \
xcodebuild test-without-building \
  -project "$SRC/LandlordHours.xcodeproj" -scheme LandlordHours \
  -destination "$DEST" -derivedDataPath "$DERIVED" \
  -only-testing:"$ONLYARG" -resultBundlePath "$RESULT" \
  ${SIGN[@]+"${SIGN[@]}"} >"$OUT/test.log" 2>&1
TEST_RC=$?
echo "[perf] xcodebuild test rc=$TEST_RC"

# ---- crash check ----------------------------------------------------------------------------
# Simulator app crashes land in the Mac's DiagnosticReports; filter to this app's process only.
CRASH_DIR="$OUT/crashes"; mkdir -p "$CRASH_DIR"
find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 2 -type f \( -name 'LandlordHours*.ips' -o -name 'Dormer*.ips' \) \
  -newermt "$STARTED_AT" 2>/dev/null | while read -r f; do cp "$f" "$CRASH_DIR/"; done
if [ -n "$DEVICE" ]; then
  xcrun devicectl device info files --device "$DEVICE" --domain-type systemCrashLogs >"$OUT/device-crash-list.log" 2>&1
  grep -E 'LandlordHours|Dormer' "$OUT/device-crash-list.log" >"$OUT/device-crash-list.app.log" 2>/dev/null
fi
CRASHES=$(find "$CRASH_DIR" -type f | wc -l | tr -d ' ')

# ---- summarise ------------------------------------------------------------------------------
python3 -I "$SELF_DIR/perf_summarize.py" --xcresult "$RESULT" --label "$LABEL" --destination "$DESTNAME" \
  --iterations "$ITER" --crashes "$CRASHES" --test-rc "$TEST_RC" --out "$OUT" || true
echo "[perf] results: $OUT/results.md  $OUT/results.json"

if [ "$CRASHES" != 0 ]; then echo "[perf] FAIL: $CRASHES crash log(s) for this app in $CRASH_DIR"; exit 5; fi
[ $TEST_RC -eq 0 ] || { echo "[perf] FAIL: tests failed (see $OUT/test.log)"; exit 6; }
exit 0
