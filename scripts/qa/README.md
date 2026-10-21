# scripts/qa: cheap pre-checks before a human or visual gate reads anything

Two tools. Both flag; neither rewrites or approves. Python 3 + Pillow, nothing else.
Run them before handoff; paste the flagged list into the handoff.

## copy_gate.py (copy)

    python3 scripts/qa/copy_gate.py check --root . --label my-branch --out ~/AgentScratch/landlordhours/<date>/copy-gate
    python3 scripts/qa/copy_gate.py check --root . --label my-branch --out DIR --baseline DIR/release-2.0.json   # new strings only
    python3 scripts/qa/copy_gate.py check ... --no-ai       # deterministic rules only, no API call
    python3 scripts/qa/copy_gate.py calibrate               # re-measure Jev against copy_gate_calibration.json

- Extracts strings from `Sources/` (Text, Label, Button, alerts, notifications, intents, enum display names, Info.plist purpose strings) and reports what it skipped.
- Rules (no AI): banned words, straight apostrophes, Title Case labels.
- Jev (one request per string, cached in `~/AgentScratch/landlordhours/copy-gate-cache.json`): plain speech, tax claim or advice, tone. Key from `$TYPESAFE_API_KEY` or `~/.config/typesafe/api_key`; never printed.
- Jev errors fail open: the string is listed as "unchecked", never dropped. Exit 0 clean, 1 flagged, 2 unchecked.
- Thresholds and the advisory-only marks live in `copy_gate_calibration.json` (89 hand-labelled strings). Add rows when you rule on a new case, then re-run `calibrate`.
- Use `--baseline` on a work-package branch so the report lists only strings that are new vs release.

## frame_check.py (captures)

    python3 scripts/qa/frame_check.py FRAME_DIR --out OUT_DIR --crops

Checks 3x PNGs: byte-identical files, violet pixels, status-bar ink contrast (top 54pt), canvas/card/action colour vs brand tokens (deltaE76), and text contrast per glyph cluster (4.5:1, 3:1 for big text). `frame_check.md` lists only flagged frames and regions in points; `--crops` saves each flagged text region.
Heuristics: tiny preview text, gradients and translucent bars can false-flag, and token sampling assumes a canvas gutter. Confirm by eye.

## Who uses what

- Builder: run both before handoff, fix every flag you agree with, and state in the handoff which you reject and why.
- Visual gate: read the flagged lists first, open only those frames or crops, confirm or dismiss each by eye, then do the normal full read. A clean tool run is not a pass.
