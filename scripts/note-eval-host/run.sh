#!/usr/bin/env bash
# Builds the host-Mac note eval from the app's sources and runs it. Usage: run.sh [--pcc] [--chain]
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${TMPDIR:-/tmp}/note-eval-host"
cd "$root"
swiftc -parse-as-library -D NOTE_EVAL_HOST -O -o "$out" \
  scripts/note-eval-host/main.swift scripts/note-eval-host/Stubs.swift Tests/NoteEvalSupport.swift \
  Sources/Services/NoteReading/*.swift Sources/Models/Models.swift Sources/Models/Suggestion.swift Sources/Models/EntrySource.swift \
  Sources/Services/Capture/Classifier/RulesEngine.swift Sources/Services/Capture/Classifier/ClassifierKeywords.swift \
  Sources/Services/Capture/Classifier/ModelAvailability.swift Sources/Services/Capture/Classifier/PCCReceiptReader.swift \
  Sources/Services/Capture/Classifier/OnDeviceClassifier.swift Sources/Services/Capture/Classifier/RulesClassifier.swift Sources/Services/Capture/Classifier/ClassifierThresholds.swift Sources/Services/Capture/CaptureProtocols.swift Sources/Services/AITimeEntryService.swift
"$out" "${FIXTURE:-Tests/Fixtures/note-eval.json}" "$@"
