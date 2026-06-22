#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMULATOR_ID="${SIMULATOR_ID:-C8B22181-D398-477F-91D3-ED67F1B8851C}"
DERIVED_DATA="${DERIVED_DATA:-/Volumes/Home/XcodeStorage/DerivedData/landlordhours-xcode27}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Volumes/Home/Applications/Xcode-27-beta.app/Contents/Developer}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/tmp/xcode27/screenshots/e2e-visual-runs/$(date +%Y-%m-%d_%H-%M-%S)}"
BUNDLE_ID="com.openclaw.landlordhours"
APPEARANCE="${APPEARANCE:-light}"
CONTENT_SIZE="${CONTENT_SIZE:-large}"

export DEVELOPER_DIR

mkdir -p "$OUT_DIR"

echo "Building LandlordHours for iPhone simulator $SIMULATOR_ID..."
/usr/bin/xcodebuild build \
  -project "$ROOT_DIR/LandlordHours.xcodeproj" \
  -scheme LandlordHours \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/LandlordHours.app"

echo "Installing $APP_PATH..."
/usr/bin/xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
/usr/bin/xcrun simctl ui "$SIMULATOR_ID" appearance "$APPEARANCE" >/dev/null
/usr/bin/xcrun simctl ui "$SIMULATOR_ID" content_size "$CONTENT_SIZE" >/dev/null
/usr/bin/xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

capture_scenario_tab() {
  local scenario="$1"
  local tab="$2"
  local name="$3"
  local email="${4:-}"
  local display_name="${5:-}"
  local path="$OUT_DIR/$name.png"
  local launch_args=(-LHMockScenario "$scenario" -LHInitialTab "$tab" -LHColorScheme "$APPEARANCE")

  if [[ -n "$email" ]]; then
    launch_args+=(-LHMockEmail "$email")
  fi
  if [[ -n "$display_name" ]]; then
    launch_args+=(-LHMockName "$display_name")
  fi

  # Keep visual evidence honest if another installed app is currently foreground.
  # The simulator can otherwise screenshot that app with a "back to LandlordHours" status link.
  /usr/bin/xcrun simctl terminate "$SIMULATOR_ID" com.brianlevu.NeuRest >/dev/null 2>&1 || true
  /usr/bin/xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  /usr/bin/xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" "${launch_args[@]}" >/dev/null
  sleep "${SETTLE_SECONDS:-6}"
  /usr/bin/xcrun simctl io "$SIMULATOR_ID" screenshot "$path" >/dev/null
  echo "$path"
}

ONBOARDING_START="$(capture_scenario_tab firstTime 0 01-onboarding-goal)"

EMPTY_HOME="$(capture_scenario_tab emptyMainTabs 0 02-empty-home)"
EMPTY_PROPERTIES="$(capture_scenario_tab emptyMainTabs 1 03-empty-properties)"
EMPTY_TRACK="$(capture_scenario_tab emptyMainTabs 2 04-empty-track)"
EMPTY_REPORTS="$(capture_scenario_tab emptyMainTabs 3 05-empty-reports)"
EMPTY_SETTINGS="$(capture_scenario_tab emptyMainTabs 4 06-empty-settings)"

OCC_HOME="$(capture_scenario_tab occasional 0 07-occasional-home)"
OCC_PROPERTIES="$(capture_scenario_tab occasional 1 08-occasional-properties)"
OCC_TRACK="$(capture_scenario_tab occasional 2 09-occasional-track)"
OCC_REPORTS="$(capture_scenario_tab occasional 3 10-occasional-reports)"
OCC_SETTINGS="$(capture_scenario_tab occasional 4 11-occasional-settings)"

FREQ_HOME="$(capture_scenario_tab frequent 0 12-frequent-home-pro)"
FREQ_PROPERTIES="$(capture_scenario_tab frequent 1 13-frequent-properties-pro)"
FREQ_TRACK="$(capture_scenario_tab frequent 2 14-frequent-track-pro)"
FREQ_REPORTS="$(capture_scenario_tab frequent 3 15-frequent-reports-pro)"
FREQ_SETTINGS="$(capture_scenario_tab frequent 4 16-frequent-settings-pro)"

NONADMIN_SETTINGS="$(capture_scenario_tab occasional 4 17-nonadmin-settings-no-debug qa-user@landlordhours.local "QA User")"

cat > "$OUT_DIR/review.md" <<EOF
# iPhone E2E Visual Review

Simulator: \`$SIMULATOR_ID\`
Build: \`$APP_PATH\`
Appearance: \`$APPEARANCE\`
Content size: \`$CONTENT_SIZE\`
Date: $(date)

## Required Rule

Do not call this run clean until every item below has an explicit Pass or Fail verdict.

## App-Wide Screenshot Matrix

Each item must be reviewed for: no blank/stuck screen, no clipped or overlapping primary content, readable text, correct tab selection, truthful Pro state, consistent visual system, and no contradictory tax or onboarding guidance.

### Onboarding

- [ ] 01 Onboarding goal screen: \`$ONBOARDING_START\`
  - This is a true onboarding screen, not a main-tab empty state.

### Empty Main Tabs

- [ ] 02 Empty Home: \`$EMPTY_HOME\`
- [ ] 03 Empty Properties: \`$EMPTY_PROPERTIES\`
- [ ] 04 Empty Track: \`$EMPTY_TRACK\`
- [ ] 05 Empty Reports: \`$EMPTY_REPORTS\`
- [ ] 06 Empty Settings: \`$EMPTY_SETTINGS\`
  - These must show signed-in main app tabs with no properties or entries.
  - They must not be intercepted by onboarding or the guided setup spotlight.

### Occasional User

- [ ] 07 Home dashboard: \`$OCC_HOME\`
- [ ] 08 Properties list/detail affordances: \`$OCC_PROPERTIES\`
- [ ] 09 Track logging form: \`$OCC_TRACK\`
- [ ] 10 Reports and goal interpretation: \`$OCC_REPORTS\`
- [ ] 11 Settings/account/export/admin visibility: \`$OCC_SETTINGS\`

### Frequent Pro User

- [ ] 12 Home Pro dashboard: \`$FREQ_HOME\`
- [ ] 13 Properties multi-property state: \`$FREQ_PROPERTIES\`
- [ ] 14 Track logging form with populated data: \`$FREQ_TRACK\`
- [ ] 15 Reports REPS/50% rule/pro export state: \`$FREQ_REPORTS\`
- [ ] 16 Settings Pro/admin/debug visibility: \`$FREQ_SETTINGS\`

### Non-Admin Verification

- [ ] 17 Settings as non-admin user: \`$NONADMIN_SETTINGS\`
  - Debug unlock and debug scenarios must not be visible.
  - Pro gating and Restore Purchase remain visible and understandable.

## Required Flow Checks

- [ ] First-time activation: Home -> Properties -> Add Property -> Track -> save first activity.
- [ ] Occasional user: Track an entry, verify Home and Reports update without contradictory math.
- [ ] Frequent user: verify Pro access, export affordance, multi-property reports, and Settings recovery options.
- [ ] Subscription recovery: non-Pro sees truthful upgrade copy; Pro does not see blocked Pro features.
- [ ] Admin-only debug controls are visible only for \`brianlevu@gmail.com\` and hidden in screenshot 17.
- [ ] Calendar import and export paths are either functional or clearly gated with no dead-end UI.

## Manual Follow-Up Required

- [ ] If semantic UI automation is unavailable, record it as BLOCKED with the exact tool failure and do not mark the flow passed.
- [ ] Capture a screenshot after each tap if any spotlight, screen, or copy looks wrong.
- [ ] Record every issue with file path, screenshot path, exact expected behavior, severity, and fix status.
EOF

echo "Visual evidence written to: $OUT_DIR"
echo "Review checklist: $OUT_DIR/review.md"
