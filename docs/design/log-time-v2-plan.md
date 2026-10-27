# Log time v2 — build plan (design only, awaiting Brian)

2026-10-27 · branch `design/log-time-v2` · sandbox: `Sources/Views/Debug/LogTimeV2/` (DEBUG only, `-LHLogV2 A|B`).
Frames, videos and side-by-sides: `~/AgentScratch/landlordhours/2026-10-27/logtime-v2/`.

## The two directions

| | **A · One line** (my pick) | **B · Three doors** |
|---|---|---|
| Entry | "What did you do?" field with a mic, "Log again" chips, "Start a timer" row | Three rows: Say it / Type it / Time it, then "Log again" rows |
| Type | The card builds under the field 600 ms after you stop typing | Type step, then Next |
| Voice | Mic in the field; words fill it live; Stop | Say step: big live words, meter, Done |
| Review | Same screen, under the field | A separate "Check and log" step with your words quoted |
| Taps to log "fixed the sink at Pine Cabin, 1 hour" | type, Log (2) | Type it, type, Next, Log (4) |
| Anchors | Superlist quick add, Toggl | Todoist Ramble, Toggl |

**Pick A.** It is the daily screen, and A puts nothing between the thought and the card. B makes every log start with a choice, and adds a step. B is easier to explain and its listening screen is calmer. If Brian wants voice more visible, take B's Say step as A's listening state, not B's doors.

Shared by both: the review card, the inline question, the timer, the manual fallback, the free-plan line, and "Log 1h" as the one primary.

## Behaviour (both)

- The card shows five fields: Rental, Time, Work, Who (only with spouse tracking), Day. Nothing else.
- Each row shows where the value came from: nothing extra if the note said it; a footnote if we assumed it ("Your only rental", "Last used", "From the timer"); a "Needs you" tag if we have no safe answer.
- The first "Needs you" row opens itself with its answers as chips. Answering opens the next one. Log stays disabled until none are left.
- Hours are never assumed. A note with no time asks "How long did it take?" (today's sheet silently defaults to 1h).
- Free plan: the Rental answers end with a locked "Add a rental" chip and the line "Free covers one rental. Your hours here stay free." The chip opens the existing `.secondProperty` paywall (`LockEntry.propertiesLimit`). Logging, voice and reading are never gated.

## Standard amendments (proposed, written as §1 components)

All built from existing tokens; each lives in the sandbox as a reusable struct ready to move to `Views/Components`.

**§1.5a `LHReadRow` / `LHReadBack` (review card).** Inner surface (radius 12, `backgroundTertiary`) as §1.5. Row: label column `.subheadline` `textSecondary` (64pt scaled); value `.body.semibold` `textPrimary`; optional provenance `.footnote` `textSecondary`; trailing `LHChevron` `chevron.down`/`chevron.up`. Min 56, target 64, max 88 (D1). Needs-answer: question `.body.semibold` + `LHTag("Needs you", .caution)`. At most one row open; the open answer sits under its row, padding 16. At AX the label stacks above the value. Motion: `flow` open/close, `countChange` on values. [measured] row 56–88; [grep] one open row. **D1/D2 rule for this card:** the open answer is part of the card, not a row. D1 measures the row header only (56.3–62.7pt measured); the open answer is capped at 20% of the viewport (measured 112–116pt = 13% for three rental chips or five hour chips + the stepper). Today's `frame_check.py density` counts header + answer as one row (142–172pt) and fails D1/D2 on every open-question frame; the tool needs the same carve-out. The card is a value-row group, so D4 is exempt as the standard already says.

**§1.7a `LHCaptureField` + `LHLevelMeter`.** LHField's multi-line form at `.title3`, min 132 empty / 88 once a card shows, with a mic slot: `LHButton.icon` at rest; while listening a 44 `action` circle with a 14pt `onAction` stop square, a 1.5pt `action` stroke and, at the field's foot, a five-capsule meter (3pt, `action`, heights bound to the mic level, `feedback`) + "Listening" `.subheadline.semibold` `action`. Reduce Motion: static meter. [measured] mic 44×44.

**§1.16a `LHAnswerChips`.** `LHChip` used as answers inside a card: wraps (flow layout, 8 gaps), never scrolls, ≤ 8 chips, the current answer selected. Amends §1.16 "one strip per screen": answer chips are not a strip.

**§1.28 `LHTimerFace`.** Positive 8pt dot + "{Work} at {Rental}" `.headline`; elapsed in `lhHeroNumberFont()` (the existing 56/700 SF Rounded tabular token, capped 80); "Started 8:28 AM" `.subheadline` `textSecondary`. Updates once a second (no `repeatForever`). Matches the Live Activity's content order.

**§1.2a `LHRowGroup(inSheet:)`.** Rows in a sheet sit on the inner surface (radius 12, `backgroundTertiary`), because `LHRowGroup` (`backgroundSecondary`) vanishes on the opaque sheet. One flag, not a new component.

## Consistency check

| Used | Standard | A | B |
|---|---|---|---|
| `LHSheet` focused, `.large`, header 56, pinned primary, AX policy | §1.20 | ✓ | ✓ |
| `LHButton.primaryGlass` "Log 1h" / "Stop and log" / "Next" / "Done" | §1.13, §1.25 | ✓ | ✓ |
| `LHButton.tertiary` "Enter details yourself", "Skip the note", "Start over", "Type instead"; `.destructiveTertiary` "Discard timer" | §1.13 | ✓ | ✓ |
| `LHButton.icon` (close, mic at rest) | §1.13 | ✓ | ✓ |
| `LHRow.Browse` + `LHRowGlyph` (timer row, doors, recents) | §1.4 | ✓ | ✓ |
| `LHChip` / `LHChipStrip` ("Log again") | §1.16 | ✓ | — |
| `LHSectionHeader` ("Log again") | §1.15 | ✓ | ✓ |
| `LHTag` ("Needs you", caution) | §1.16 | ✓ | ✓ |
| `LHStepper` (Time, after a chip) | §1.9 | ✓ | ✓ |
| `LHSegmented` (Who) | §1.8 | ✓ | ✓ |
| `LHField` (manual note) | §1.7 | ✓ | ✓ |
| `LHDivider`, `LHChevron` | §1.2, §1.4 | ✓ | ✓ |
| `DraftingLoader(.document)` (reading) | existing | ✓ | ✓ |
| `LHToast` success "Logged 1h at Pine Cabin · Undo" | §1.19, §C.2 | ✓ | ✓ |
| `lhHeroNumberFont()` | brand §3 heroNumber | ✓ | ✓ |
| Tokens: `AdaptiveColors` only; `LHMetrics` gutter 20, radii 12/20/6/capsule; `AppAnimation` flow/reveal/feedback/quick | §1.2, D10, §B.2 | ✓ | ✓ |
| `LHReadRow` / `LHReadBack` | **proposed §1.5a** | ✓ | ✓ |
| `LHCaptureField` / `LHLevelMeter` | **proposed §1.7a** | ✓ | ✓ (Type step; Say step uses the meter alone) |
| `LHAnswerChips` | **proposed §1.16a** | ✓ | ✓ |
| `LHTimerFace` | **proposed §1.28** | ✓ | ✓ |
| `LHRowGroup(inSheet:)` | **proposed §1.2a** | ✓ | ✓ |

No hex, no `.system(size:)`, no Fraunces, no tool renders in the sheet (§1.17: never in decision rows).

## Builder self-check (sandbox frames, iPhone 17 Pro sim, iOS 27.0, 96 frames)

- `frame_check.py` (contrast, tokens, retired hues, identical frames): 96 frames, 0 flagged. Shared screens (timer, note, manual, logged) are captured once in `frames/shared/`.
- `frame_check.py breaks`: 0 mid-word breaks at default and XXL.
- Token contrast for every new text pair (`qa/contrast.txt`): 28 pairs, lowest 4.88:1 (dark placeholder on the dark inner surface), 0 below 4.5.
- `frame_check.py density`: 23 PASS, 18 FAIL. Every FAIL is one of two known cases: (1) an open answer counted as a row (D1/D2, above); (2) D4 "empty band" on the empty "What did you do?" field or on the value-row card, which D4 exempts. No AX3 frames yet: the gate needs them before build.
- `standard_lint.py`: the sandbox adds one `dynamic-type-clamp` (the DEBUG `-LHTypeSize` capture override, as `SurfaceCaptureBoard` does). Nothing in production code changed.

## Parser changes (NoteReading)

1. **Per-field source**, not a number: `enum FieldSource { note(tier), assumed(reason), timer, needed }` on each field. The rules tier knows when it matched; the model tiers are kept only when the rules agree or `NoteFactGuard` passes. A float confidence would be invented; a source is honest and testable.
2. **Property candidates**: when `mentionedPropertyCount ≥ 2` or the match is weak, return the candidates so the question shows those first.
3. **Unknown place**: flag a place-like phrase that matches no rental ("the duplex on Elm"), so a free user with one rental is asked, not silently filed under the only rental.
4. **No default hours**: the sheet stops pre-setting 1h; hours come from the note, the timer or the user.
5. Streaming: run the rules tier on the partial voice transcript (cheap), so A's card can build while you talk (Todoist Ramble does this).

## Analytics (PostHog, all new except the last)

`log_sheet_opened {entry}` · `log_path {type|voice|timer|recent|manual}` · `log_read {tier, filled[], needed[], ms}` · `log_question_answered {field}` · `log_field_corrected {field, from: note|assumed}` · `log_abandoned {stage}` · `entry_logged` gains `{path, corrections, seconds_to_log}`. The two numbers that say the design works: median seconds from open to Log, and corrections per log on note-filled fields.

## Tests

- Unit: provenance per field over the existing NoteReading eval set; "no hours → needed"; one-rental free user; two rentals named → needed with candidates; timer draft → rental/time/day `.timer`.
- UI (XCUITest, sim + iPad): type path, voice path (scripted transcript hook like `-LHLogV2Play voice`), question path, free path → paywall → back out, timer start/stop/note/log, manual. Existing `log.*` identifiers move to `logv2.*`; old LogTime UI tests are rewritten in the same package, no weakened assertions.
- Visual gate: every state, light/dark, default/XXL/AX3, plus density (row 56–88) and contrast.

## Size

| Package | Work | Size |
|---|---|---|
| 0 | Promote the five components into `Views/Components`, standard text, component sheet entries | S (1 day) |
| 1 | Parser: FieldSource, candidates, unknown place, no default hours, eval set | M (2 days) |
| 2 | New LogTimeSheet (A) on the real form, voice, timer, toast; delete the old rows/stepper layout | M–L (3 days) |
| 3 | Analytics + UI tests + gates | M (2 days) |

About 8 working days with 0 and 1 in parallel. The Live Activity and widgets are unchanged.
