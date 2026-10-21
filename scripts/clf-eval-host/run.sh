#!/usr/bin/env bash
# Builds the host-Mac classifier eval from the app's sources and runs it (needs Apple
# Intelligence on this Mac). Usage: scripts/clf-eval-host/run.sh [split ...]; VERBOSE=1 for rows.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${TMPDIR:-/tmp}/clf-eval-host"
cd "$root"
c=Sources/Services/Capture/Classifier
swiftc -parse-as-library -O -target arm64-apple-macos26.0 -o "$out" \
  scripts/clf-eval-host/main.swift scripts/clf-eval-host/Stubs.swift \
  Sources/Models/Models.swift Sources/Models/Suggestion.swift Sources/Models/EntrySource.swift \
  $c/RulesEngine.swift $c/ClassifierKeywords.swift $c/ModelAvailability.swift $c/OnDeviceClassifier.swift \
  $c/RulesClassifier.swift $c/ClassifierThresholds.swift $c/ClassifierChain.swift \
  Sources/Services/Capture/CaptureProtocols.swift
"$out" "$@"
