# scripts/qa: cheap pre-checks before a human or visual gate reads anything

Three pieces (two tools plus the gate rubric). Both tools flag; neither rewrites or approves. Python 3 + Pillow, nothing else.
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
- `python3 scripts/qa/copy_gate.py l10n --root . --out DIR [--show 3]` is a separate deterministic pass for NON-LOCALIZABLE strings (no AI, no API call, flags only, counts per file). Patterns: `string-var-in-ui` (a `let`/`var` String literal later passed to Text/Label/Button/...), `concatenation` (`"a" + b` inside a UI call), `text-verbatim-words` (`Text(verbatim:)` with words), `text-from-String` (`Text(String(...))`, `Text(String(format:))`; also fires on number-only conversions, so skim), and `plist-literal` (usage descriptions and display names hardcoded in Info.plist with no `InfoPlist.xcstrings`). Exit 1 when anything is found.
- Use `--baseline` on a work-package branch so the report lists only strings that are new vs release.

## frame_check.py (captures)

    python3 scripts/qa/frame_check.py FRAME_DIR --out OUT_DIR --crops

Checks 3x PNGs: byte-identical files, violet pixels, status-bar ink contrast (top 54pt), canvas/card/action colour vs brand tokens (deltaE76), and text contrast per glyph cluster (4.5:1, 3:1 for big text). `frame_check.md` lists only flagged frames and regions in points; `--crops` saves each flagged text region.
Suppression, on by default (rules and defaults sit in `DEFAULTS` at the top of the file; override with `--config file.json`, or `--no-suppress` for the old raw output):

- **Bands**: text inside the status bar (54pt), the tab bar plus home indicator (112pt) and the 28pt scroll fade above it is ignored. `--exclude-top PT`, `--exclude-bottom PT`. The status-bar clock/icon contrast check itself stays on, so dark ink over the blue hero still flags.
- **Skip frames**: names matching `*midfade*` (add more with `--skip-glob`) get no checks and are listed under Skipped. `*lockscreen*`, `*lock-screen*`, `*wallpaper*` frames only get the duplicate check (iOS draws them).
- **Theme-fixed screens**: `*welcome*` dark/light byte-identical pairs are expected; `*welcome*` and `*paywall-*` may use blueprint blue as the canvas (`blueprint_canvas_globs`).
- **Allowed tokens per region** (`allowed_tokens`): blueprint `#1E3FA6` and the hero gradient `#1D3EA4>#19358E` are accepted for card and action samples everywhere, and for canvas on theme-fixed frames. Entries take `color` (hex or `a>b` gradient), `tol` (deltaE) and optional `frames` glob.
- **Glyph size**: clusters under 16x8pt, or small square-ish blobs (card corners), are not treated as text. `--min-cluster-pt WxH`.
- The report lists how many items each rule suppressed, so a gate can see what was hidden. Byte-identical groups that are NOT theme-fixed (for example three AX3 paywall states) still flag.

Heuristics: tiny preview text, gradients and translucent bars can false-flag, and token sampling assumes a canvas gutter. Confirm by eye.

## gate_rubric.md and scripts/visual_gate.py

`scripts/qa/gate_rubric.md` is the 2.0 Blueprint rubric (from `docs/design/2.0-brand-system.md`): tokens, intent rules, type, icons, the known false alarms, and the "BLOCKER needs a measurement" rule. `python3 scripts/visual_gate.py --print-prompt` prints it (no model calls), and the visual-gate agent uses it as its design bar. The legacy OpenRouter mode in `visual_gate.py` loads the same file; edit the markdown, not the script. When the brand doc changes, update the rubric in the same commit.

## Who uses what

- Builder: run both before handoff, fix every flag you agree with, and state in the handoff which you reject and why.
- Visual gate: read the flagged lists first, open only those frames or crops, confirm or dismiss each by eye, then do the normal full read. A clean tool run is not a pass.

## v2 tools (standard H, NOTES-standard-v2.md)

- `frame_check.py density` now handles the dusk/night page: hero art is auto-detected (`--hero-rect x0,y0,x1,y1` in pt overrides, `--hero-glob` adds hero names) and excluded from D6/D2/D4; a card with a 1pt `pageCardEdge` ring is a card, not an input field; a card's foot row is not the pinned bar. A card enclosing the art fails "H hero not in a card". H1/H2 print as advisory (the frame square is not visible in a screenshot).
- `frame_check.py DIR` on hero frames: canvas is matched against the page gradient path (dE 6), the card sample skips gradient pixels, the art is masked from the action sample, light-page text must be an allowed page ink, and every card needs its `pageCardEdge` ring (>= 1.8:1 light, 1.5:1 dark, because #2A3560 on the night page measures 1.62).
- `frame_check.py hero A.png ... --pairs lit=dark [--windows craft_windows.json] [--strict]`: p99 art contrast, window delta, saturation, hue bins, ground line. Saturation is REVIEW unless `--strict` (screenshot masks include shadow and ground).
- `asset_check.py`, `motion_check.py`: new, with `test_asset_check.py`, `test_motion_check.py`.
- `standard_lint.py`: clamp quota 3, CraftHouseView `DragGesture`, `craft-image`, `hero-card`, `blueprint-retired`, `tab-shell`, `page-ink`, `timeline-view`, `section-header-mono`. New rules are baselined; `swatch_matrix.py` and `ambient_check.py` (items 7 and 8) wait for features F.1 and F.2.

## test_triage.py (Jev failure triage): NOT READY, do not integrate

    python3 scripts/qa/test_triage.py triage RESULT.xcresult|ui.log [--out triage.json] [--calibration CAL.json] [--threshold P] [--no-ai]
    python3 scripts/qa/test_triage.py calibrate --labels scripts/qa/test_triage_labels.json --out scripts/qa/test_triage_calibration.json

- Project-agnostic, stdlib only. Reads an `.xcresult` (via `xcrun xcresulttool`) or an xcodebuild log, and sends each failure's test name, suite, first failure message and two counts (failures in the same suite and with the same message in that run) to Jev as one Choice: stale selector or string / real behaviour bug / environment or infrastructure / test logic bug.
- Output is a JSON list: `label`, `probability`, `probs`, `route`. `route: "agent"` means unlabelled, route to agent. It fails open: no key, no network, a Jev error, no calibration, or a calibration marked `ready: false` all give `route: "agent"`. It never drops a failure and never retries or edits a test.
- Key and cache: `$TYPESAFE_API_KEY` or `~/.config/typesafe/api_key` (never printed); cache `~/AgentScratch/jev-harness/test-triage-cache.json`.
- Calibration (51 labelled failures, 16 held out): the 38 UI failures of the 2026-10-25 base run, labelled from the `fix/uitests-bc` repair, plus 13 from other 2026-10 logs labelled from the message (`test_triage_labels.json`). Result in `test_triage_calibration.json`.
  - Held-out: 87.5% at 50% coverage (7 of 8), but only 8 items. Dev at the same threshold: 72%. Pooled: 77% at 51%. With no threshold: 45% overall against a 69% always-stale baseline. So: NOT READY.
  - Why: 39 of 51 labels are "stale selector", and 1 is a real bug. A bare "XCTAssertTrue failed - House, Frame going up, lights off" gives no clue, so Jev scatters those across test-logic and real-bug. It is right on environment failures (8 of 8) and on explicit "Multiple matching elements".
  - What would improve it: an answer key with real bugs and test-logic cases (aim for 10+ of each); the failing element's accessibility dump or the assertion source line as state; and a before/after diff of the UI strings. Recalibrate and re-test on fresh failures before trusting it.
- Each new project calibrates its own threshold against its own answer key before relying on it.
