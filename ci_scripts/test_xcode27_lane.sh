#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/LandlordHours.xcodeproj}"
SCHEME="${SCHEME:-LandlordHours}"
BUNDLE_ID="${BUNDLE_ID:-com.openclaw.landlordhours}"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer}"

SIMULATOR_NAME="${SIMULATOR_NAME:-LandlordHours iPhone iOS 27}"
SIMULATOR_ID="${SIMULATOR_ID:-C8B22181-D398-477F-91D3-ED67F1B8851C}"
DERIVED_DATA="${DERIVED_DATA:-/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/Volumes/Home/XcodeStorage/XcodeBuildMCP/workspaces/landlordhours}"
RESULTS_DIR="${RESULTS_DIR:-$WORKSPACE_DIR/results}"
LOGS_DIR="${LOGS_DIR:-$ROOT_DIR/tmp/xcode27/logs}"
SCREENSHOTS_DIR="${SCREENSHOTS_DIR:-$ROOT_DIR/tmp/xcode27/screenshots}"
LANE_TIMEOUT_SECONDS="${LANE_TIMEOUT_SECONDS:-300}"

mkdir -p "$RESULTS_DIR" "$LOGS_DIR" "$SCREENSHOTS_DIR"

timestamp() {
  date +%Y%m%d%H%M%S
}

run_xcodebuild() {
  local name="$1"
  shift

  local run_name="${name}-$(timestamp)"
  local result_path="$RESULTS_DIR/${run_name}.xcresult"
  local log_path="$LOGS_DIR/${run_name}.log"

  echo "Xcode: $DEVELOPER_DIR"
  echo "Simulator: $SIMULATOR_NAME ($SIMULATOR_ID)"
  echo "DerivedData: $DERIVED_DATA"
  echo "Result: $result_path"
  echo "Log: $log_path"

  /usr/bin/xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true

  set +e
  /usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "id=$SIMULATOR_ID" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$result_path" \
    "$@" \
    >"$log_path" 2>&1 &
  local build_pid=$!

  tail -f "$log_path" &
  local tail_pid=$!

  local start_seconds
  start_seconds="$(date +%s)"
  local status=0

  while kill -0 "$build_pid" >/dev/null 2>&1; do
    sleep 2
    local now_seconds
    now_seconds="$(date +%s)"
    if (( now_seconds - start_seconds > LANE_TIMEOUT_SECONDS )); then
      echo "Timed out after ${LANE_TIMEOUT_SECONDS}s; stopping xcodebuild pid ${build_pid}." | tee -a "$log_path"
      kill "$build_pid" >/dev/null 2>&1 || true
      status=124
      break
    fi
  done

  if [[ "$status" -eq 0 ]]; then
    wait "$build_pid"
    status=$?
  else
    wait "$build_pid" >/dev/null 2>&1 || true
  fi

  kill "$tail_pid" >/dev/null 2>&1 || true
  wait "$tail_pid" >/dev/null 2>&1 || true
  set -e

  return "$status"
}

doctor() {
  echo "Selected Xcode:"
  /usr/bin/xcode-select -p
  echo
  echo "Lane Xcode:"
  /usr/bin/xcodebuild -version
  echo
  echo "iOS 27 SDKs:"
  /usr/bin/xcodebuild -showsdks | grep -E 'iOS.*27|iphonesimulator27' || true
  echo
  echo "Dedicated simulator:"
  /usr/bin/xcrun simctl list devices available | grep "$SIMULATOR_NAME" || {
    echo "Missing simulator: $SIMULATOR_NAME" >&2
    exit 1
  }
  echo
  echo "SSD paths:"
  printf "DerivedData symlink: "
  readlink "$HOME/Library/Developer/Xcode/DerivedData" || true
  printf "Archives symlink: "
  readlink "$HOME/Library/Developer/Xcode/Archives" || true
  printf "XcodeBuildMCP symlink: "
  readlink "$HOME/Library/Developer/XcodeBuildMCP" || true
}

case "${1:-doctor}" in
  doctor)
    doctor
    ;;
  build)
    run_xcodebuild "lane-build-for-testing" build-for-testing
    ;;
  unit)
    run_xcodebuild "lane-unit-test" -only-testing:LandlordHoursTests test
    ;;
  ui)
    run_xcodebuild "lane-ui-test" -only-testing:LandlordHoursUITests test
    ;;
  full)
    run_xcodebuild "lane-full-test" test
    ;;
  erase-sim)
    /usr/bin/xcrun simctl shutdown "$SIMULATOR_ID" >/dev/null 2>&1 || true
    /usr/bin/xcrun simctl erase "$SIMULATOR_ID"
    ;;
  launch)
    run_xcodebuild "lane-build" build
    app_path="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/LandlordHours.app"
    /usr/bin/xcrun simctl install "$SIMULATOR_ID" "$app_path"
    /usr/bin/xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"
    ;;
  *)
    echo "Usage: $0 [doctor|build|unit|ui|full|erase-sim|launch]" >&2
    exit 2
    ;;
esac
