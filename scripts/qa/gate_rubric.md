# Gate rubric addendum: the design standard

Source of truth: `docs/design/DESIGN-STANDARD.md` (section 5). Applies to every UI change on top of the existing visual-gate rubric (`scripts/visual_gate.py --print-prompt`). The builder runs these checks first and pastes the numbers into the hand-off. The gate re-measures and confirms. A measurable defect the builder could have caught is a process failure.

Frames: 3x iPhone 16 Pro captures (1206x2622), default, XXL and AX3 Dynamic Type, light and dark. Say the device and OS before you gate. A BLOCKER needs a measurement; an impression without one is MARGINAL and is triaged in writing. Missing, blank or wrong-theme frames are BLOCKED.

## 1. Density (measured)

```bash
python3 scripts/qa/frame_check.py density <frames...> --json density.json
# add --items-present N for list tabs that have N >= 5 items (enables D3)
```

| Rule | Limit |
|---|---|
| D1 list row height (default Dynamic Type) | 56-88pt, target 64 |
| D2 one list item's share of the viewport | <= 12% default and XXL, <= 30% AX3 |
| D3 list tab with >= 5 items: complete rows above the fold | >= 5 default, >= 4 XXL |
| D4 empty bands inside a non-hero card (x and y inset 16pt) | <= 35% of card height |
| D6 non-hero card share of viewport / hero incl. header | <= 20% / <= 40% |

A grouped list container is judged per row (D1, D2), not as one card (D6). Not covered by the script, so the gate reads them by eye with a pixel measurement: D3b/D3c (Today above the fold, AX compact hero), D7 text lines per row (title <= 2, meta 1), D9 gutter 20 / padding 16 / section gap 24 (the script reports gutter as info), contrast >= 4.5:1 on every text pair including placeholders, disabled and secondary text, and no two differently named state frames byte-identical.

Any `FAIL` line from the script is a BLOCKER. Report the printed numbers, not a paraphrase.

## 2. Component conformance (grep)

```bash
python3 scripts/qa/standard_lint.py        # must print 0 NEW violations
```

Then list, in the hand-off, every row, card, tag, chip, button, header, field, segmented control, stepper, empty state, toast, sheet and alert in the diff by its standard component name (`LHRow.Action`, `LHButton.primary`, and so on). A one-off view where a component exists is a finding. Zero new `.system(size:)`, `Color(hex:)`, `Image("bp_tool_`, Lucide, emoji, `.dynamicTypeSize(` clamps outside the two allowed sites, or hand-built cards around rows. `CategoryToolTile(size:)` is 36 or 56 and never inside Today or Inbox decision rows. Radii are in {6, 12, 16, 20, capsule}. Frames at XXL and AX3 show no clipping, no mid-word break and no truncation at AX.

## 3. Motion conformance (grep + named motions)

The hand-off names the standard section B motion for each animated change (`press`, `rowConfirm`, `swipeConfirm`, `rowDismiss`, `segmentSlide`, `tileFocus`, `countChange`, `heroCountUp`, `houseStageAdvance`, `toastIn/toastOut`, `sheetUnfold`, `buttonStateChange`, `errorShake`, `pullToRefresh`, `emptyStateEntrance`, `scanningLine`, `fieldFocus`) and its token (`feedback`, `quick`, `reveal`, `standard`, `smooth`, `flow`, `collapse`, `settle`, `pop`, `count`, `ringProgress`, `stage`). Check against the code:

- Springs are `.spring(duration:bounce:)`, duration <= 0.30s (signature tokens `stage`, `ringProgress`, `count` <= 0.60s). `bounce` > 0 only inside a gesture end or swipe-commit path. The lint's `spring-response` rule must not grow.
- Every `withAnimation` / `.animation` is bound to a state `value:` or a gesture. `.onAppear { withAnimation` only in `emptyStateEntrance` and the milestone. `repeatForever` only in `scanningLine`.
- Every `.sensoryFeedback(trigger:)` watches the same state as the animation; no haptic inside `asyncAfter`.
- Every event that moves, scales or shakes has a reduce-motion branch that keeps opacity and colour only.

An animation with no named motion in the hand-off is a finding.

## 4. Copy conformance

- Banned words absent (the lint's `banned-word` rule must not grow): never "qualify/qualified/qualification", "audit-ready", "evidence", "proof", "compliance", plus the Avoid column of standard C.4.
- `scripts/copy-gate/copy_gate.py` per screen: average <= 14 words per sentence, hard max 22.
- Canonical ideas use their String Catalog key (`common.nothingCountsUntilConfirm`, `common.cpaFootnote`, `row.action.*`, `pdf.title`), at most one CPA footnote per screen.
- Judgment, written: the read-aloud test as the named persona (a landlord with two rentals and a W-2 job). Write the first thing you understood in 5 seconds. A line that scores well but reads stiff fails.

## 5. Anchor question (judgment, written)

Put each key frame beside its anchor: Copilot "To review" (decision lists), Apple Reminders (leading control, meta line, swipes), Things 3, Apple Fitness Summary (summary cards), Apple Settings (forms). Write one paragraph per screen answering:

> Would this sit next to the anchor app without looking like the hobby version?

Say which anchor, what matches (row rhythm, type scale, spacing, motion), and what does not. Passing numbers with a "no" here is MARGINAL and goes to Brian with both frames side by side. An answer without the anchor frame in view is invalid.

## Verdict format

`PASS`, `PASS_WITH_FIXES` or `FAIL`, then one line per section above with the evidence (script output, lint count, named motions, copy numbers, anchor paragraph). Fail closed: if the density script returns `NO_DATA` for a frame that should contain cards or rows, the frame is BLOCKED, not passed.
