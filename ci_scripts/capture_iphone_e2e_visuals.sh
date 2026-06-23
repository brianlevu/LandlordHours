#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMULATOR_ID="${SIMULATOR_ID:-B119FCEA-3C7B-4022-A57E-28357879F07D}"
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
  local tmp_path
  tmp_path="$(mktemp "/tmp/landlordhours-${name}.XXXXXX.png")"
  /usr/bin/xcrun simctl io "$SIMULATOR_ID" screenshot "$tmp_path" >/dev/null
  cp "$tmp_path" "$path"
  rm -f "$tmp_path"
  echo "$path"
}

capture_onboarding_step() {
  local step="$1"
  local name="$2"
  local path="$OUT_DIR/$name.png"
  local launch_args=(-LHMockScenario firstTime -LHInitialTab 0 -LHColorScheme "$APPEARANCE" -LHOnboardingStep "$step")

  /usr/bin/xcrun simctl terminate "$SIMULATOR_ID" com.brianlevu.NeuRest >/dev/null 2>&1 || true
  /usr/bin/xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  /usr/bin/xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" "${launch_args[@]}" >/dev/null
  sleep "${SETTLE_SECONDS:-6}"
  local tmp_path
  tmp_path="$(mktemp "/tmp/landlordhours-${name}.XXXXXX.png")"
  /usr/bin/xcrun simctl io "$SIMULATOR_ID" screenshot "$tmp_path" >/dev/null
  cp "$tmp_path" "$path"
  rm -f "$tmp_path"
  echo "$path"
}

ONBOARDING_GOAL="$(capture_onboarding_step goal 01-onboarding-goal)"
ONBOARDING_PROPERTY="$(capture_onboarding_step property 02-onboarding-property)"
ONBOARDING_PAYWALL="$(capture_onboarding_step paywall 03-onboarding-paywall)"
ONBOARDING_NOTIFICATIONS="$(capture_onboarding_step notifications 04-onboarding-notifications)"
ONBOARDING_CALENDAR="$(capture_onboarding_step calendar 05-onboarding-calendar)"

EMPTY_HOME="$(capture_scenario_tab emptyMainTabs 0 06-empty-home)"
EMPTY_PROPERTIES="$(capture_scenario_tab emptyMainTabs 1 07-empty-properties)"
EMPTY_TRACK="$(capture_scenario_tab emptyMainTabs 2 08-empty-track)"
EMPTY_REPORTS="$(capture_scenario_tab emptyMainTabs 3 09-empty-reports)"
EMPTY_SETTINGS="$(capture_scenario_tab emptyMainTabs 4 10-empty-settings)"

OCC_HOME="$(capture_scenario_tab occasional 0 11-occasional-home)"
OCC_PROPERTIES="$(capture_scenario_tab occasional 1 12-occasional-properties)"
OCC_TRACK="$(capture_scenario_tab occasional 2 13-occasional-track)"
OCC_REPORTS="$(capture_scenario_tab occasional 3 14-occasional-reports)"
OCC_SETTINGS="$(capture_scenario_tab occasional 4 15-occasional-settings)"

FREQ_HOME="$(capture_scenario_tab frequent 0 16-frequent-home-pro)"
FREQ_PROPERTIES="$(capture_scenario_tab frequent 1 17-frequent-properties-pro)"
FREQ_TRACK="$(capture_scenario_tab frequent 2 18-frequent-track-pro)"
FREQ_REPORTS="$(capture_scenario_tab frequent 3 19-frequent-reports-pro)"
FREQ_SETTINGS="$(capture_scenario_tab frequent 4 20-frequent-settings-pro)"

NONADMIN_SETTINGS="$(capture_scenario_tab occasional 4 21-nonadmin-settings-no-debug qa-user@landlordhours.local "QA User")"

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

- [ ] 01 Onboarding goal screen: \`$ONBOARDING_GOAL\`
- [ ] 02 Onboarding property setup screen: \`$ONBOARDING_PROPERTY\`
- [ ] 03 Onboarding Pro/paywall screen: \`$ONBOARDING_PAYWALL\`
- [ ] 04 Onboarding notifications screen: \`$ONBOARDING_NOTIFICATIONS\`
- [ ] 05 Onboarding calendar screen: \`$ONBOARDING_CALENDAR\`
  - These are true onboarding screens, not main-tab empty states.

### Empty Main Tabs

- [ ] 06 Empty Home: \`$EMPTY_HOME\`
- [ ] 07 Empty Properties: \`$EMPTY_PROPERTIES\`
- [ ] 08 Empty Track: \`$EMPTY_TRACK\`
- [ ] 09 Empty Reports: \`$EMPTY_REPORTS\`
- [ ] 10 Empty Settings: \`$EMPTY_SETTINGS\`
  - These must show signed-in main app tabs with no properties or entries.
  - They must not be intercepted by onboarding or the guided setup spotlight.

### Occasional User

- [ ] 11 Home dashboard: \`$OCC_HOME\`
- [ ] 12 Properties list/detail affordances: \`$OCC_PROPERTIES\`
- [ ] 13 Track logging form: \`$OCC_TRACK\`
- [ ] 14 Reports and goal interpretation: \`$OCC_REPORTS\`
- [ ] 15 Settings/account/export/admin visibility: \`$OCC_SETTINGS\`

### Frequent Pro User

- [ ] 16 Home Pro dashboard: \`$FREQ_HOME\`
- [ ] 17 Properties multi-property state: \`$FREQ_PROPERTIES\`
- [ ] 18 Track logging form with populated data: \`$FREQ_TRACK\`
- [ ] 19 Reports REPS/50% rule/pro export state: \`$FREQ_REPORTS\`
- [ ] 20 Settings Pro/admin/debug visibility: \`$FREQ_SETTINGS\`

### Non-Admin Verification

- [ ] 21 Settings as non-admin user: \`$NONADMIN_SETTINGS\`
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
