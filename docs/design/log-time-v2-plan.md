# Log time v2 — build plan (design only, awaiting Brian)

2026-10-27 · branch `design/log-time-v2` · sandbox: `Sources/Views/Debug/LogTimeV2/` (DEBUG only).

**Launch arguments:**

| Launch | What it shows |
|---|---|
| `-LHLogV2 A -LHLogV2Variant beam` | **A1 · Beam** (round 3) |
| `-LHLogV2 A -LHLogV2Variant object` | **A2 · Object** (round 3) |
| `-LHLogV2Variant r2` | round 2 |
| `-LHLogV2 A -LHLogV2R1` | round 1 A |
| `-LHLogV2 B` | round 1 B |

States: `-LHLogV2State entry|typing|review|question|howLong|listening|timerRunning|timerNote|timerReview|celebrate|logged|manual|freeRental`, plus `-LHLogV2Free`. Videos use `-LHLogV2Play type|voice|timer`.

**Evidence:** `~/AgentScratch/landlordhours/2026-10-27/logtime-v2/`
- round 1 at the root
- `r2/`
- `calibration/` (the board Brian tapped)
- `r3/` (this round)

## Where we are

- **Round 1:** Brian approved A's flow and rejected its look: "very common, like any typical form… even the default app is better for hours selection".
- **Calibration:** he picked *bold numerals*, *crafted object* and *editorial calm*, and skipped *soft tactile*.
- **Round 3:** the same flow in that style, as two variants.

## Round 4: A1 Beam, Brian's pick (Object dropped)

Launch with `-LHLogV2 A -LHLogV2Variant beam`. Round 3's Beam is `beamR3`; Object stays reachable as `object`, with no more work on it. Evidence is in `logtime-v2/r4/`.

These are the round-3 critic's fixes:
1. **The ruler.**
   - Centred under the numerals, the card's full inner width, clipped to the card with 10% edge fades.
   - 24pt per 15 minutes, so 1h is 96pt.
   - The reading line (3pt `action` capsule with a small pointer) spans only the ticks and the beam. The hour labels sit below it and are never covered.
   - **Presets:** `LHChip` 30m · 1h · 2h · 4h under the ruler, as Opal has them. The selected chip follows the ruler.
2. **The note is shown once.** While typing, it is the field. When the note is done (keyboard Done, focus leaving the field, "Next", a "Log again" row, or voice Done), the field grows into the record card and the note becomes the Fraunces sentence, with a pencil. Tapping the sentence shrinks the card back into the field. There is no live swap while typing.
3. **One continuous move.** The white surface is one `matchedGeometryEffect` from field to card (`flow`), and the "Log again" rows move down and out. No crossfade over text.
4. **The house moment.**
   - After Log, the rental's house steps forward (matched move) to 78% of the sheet's width, at most 340pt.
   - The windows light (`windows` 0.40, after a 0.25s delay). If the log crosses a stage, the next stage fades in (`stageFade`).
   - The line under it: Fraunces "Logged 1h at Pine Cabin." plus "The roof goes on."
   - It holds 1.9s, then the sheet closes and the toast shows.
   - Houses are the production `RentalTileHouse` (the §1.4 Rentals tile recipe: night exposure, plus the `backlight` glow on roofed stages in dark).
5. **"Which rental?"** collapses the duration to its numerals (56pt, no ruler or presets) until a house is picked. The free-plan line sits right under the sentence.

### Amendment: the record card is a HERO, with limits (ruling 2026-10-27)

The record card is the Log time sheet's one object, as the house is on Today. It is measured as a hero, not under D6's 20% cap for non-hero cards, and only while all of these hold:
- **H-L1 [measured]:** the numerals, the duration control (ruler and presets) and the pinned Log button are fully above the fold at default and XXL. "Which rental?" counts as the control while it is open.
- **H-L2 [grep + judgment]:** the hero holds no duplicate note. The note shows once, as the field or as the sentence, never both.
- **H-L3 [measured]:** D4's empty-band rule still applies inside the card, at 35% or less.
- **H-L4 [measured]:** at AX3 the card may scroll, but the duration control must be reachable with one scroll (one viewport height) from the top.
- The house moment after Log is a transient full-sheet state. It is not measured by D6 or D4, it lasts 2.5s at most, and it never plays out of sight (§B.1 "reveal on return").

### Round 4 self-check (`r4/qa/`)

48 frames on a slim iPhone 17 Pro simulator, iOS 27.0: 11 states at default and XXL in light and dark, plus AX3 for the review and duration states.

- **AA:** `frame_check.py` flagged 4 frames, all false positives checked by eye:
  - house art in the "Log again" rows (2)
  - rows fading under the pinned footer at XXL and AX3 (2), as §1.20 intends
  - The round-3 table (20 pairs, lowest 4.31:1 on large text) still holds; round 4 added no new ink.
- **Breaks and truncation:** 0 mid-word breaks in 48 frames. No truncation at default or XXL, checked by eye.
- **H-L3, empty band (D4 ≤ 35%):** every card passes. Default 27.2–35.0% (the highest are the needs-time and needs-rental states at 35.0%, right at the limit); XXL 24.4–31.8%.
- **H-L1, above the fold:** measured on the dark frames, where the chip fill separates from the card; the layout is identical in light, which I checked by eye. Presets bottom vs Log top:
  - default: 443.7 / 468.0 / 491.7pt against 774pt
  - XXL: up to 591pt against 774pt
  - so the numerals, ruler and presets are always above the pinned Log button.
  - When "Which rental?" is open, the house choices and the collapsed numerals sit above the fold.
- **H-L4, AX3:** in the review state the ruler and presets are in the first viewport. In the needs-time state the numerals start at the bottom edge and are reachable with one scroll.
- **House moment:** about 270×294pt, 65–69% of the width and 33–34% of the height, a bounding box of 22–23% of the screen. Round 3's card house was about 4%.
- **D6 (non-hero card ≤ 20%):** fails on every card state (record card 61–70%, timer card about 50%). This is waived for the record card by the hero ruling above. The timer card is not covered by the ruling and is listed as open.

## The flow (unchanged, both variants)

1. **One calm screen on the page colour.**
   - A white "What did you do?" field with a filled 44pt mic.
   - "Log again" rows, each led by that rental's house.
   - "Start a timer".
   - "Enter details yourself" as the one tertiary.
2. **Type:** 600 ms after the last key, the record card appears under the field.
3. **Speak:** the mic pushes "Say it": the live words in Fraunces, a level meter, Done, and "Type instead". Every voice frame and video uses a scripted transcript.
4. **The record card** (one white card):
   - Your note read back as one Fraunces sentence ("Fixed the sink at Pine Cabin."), with the duration phrase dropped because the numerals say it.
   - The duration as the hero numeral.
   - The rental's own house.
   - Work, who and day as quiet menus.
   - One footnote naming everything assumed ("Not in your note: You, Today.").
5. **Needs you:** only the missing thing asks.
   - No rental: pick one of your houses.
   - No time: the numerals show "0 h 00 m" in quiet ink with "How long did it take? · Needs you", and the beam or dial is ready to set.
   - The Log button says what's missing: "Pick a rental to log" or "Set the time to log".
6. **Log:** the house beat plays, the sheet closes, and the toast "Logged 1h at Pine Cabin · Undo" shows on Today.
   - The house beat: the windows light (`windows` 0.40). If this log crosses a stage, the next stage fades in (`stageFade` 0.25).
   - The toast waits for the sheet to dismiss, which fixes the double sheet.
7. **Timer:** the timer's face is shaped like the variant (beam filling, or the dial sweeping), then "Stop and log", an optional note, and the same card. The duration is the exact minutes it ran: 1h 12m on the note step and on the card, with the footnote "From the timer: 1h 12m, not rounded."
8. **Manual:** the same card, with time needed. Hours are never assumed anywhere.
9. **Free plan:**
   - Logging, voice and reading are never gated.
   - The rental menu ends with a locked "Add a rental · Pro" item. It is wired to nothing in the sandbox; it should open the existing second-rental paywall (`LockEntry.propertiesLimit`).
   - A footnote under the details says "Free covers one rental. Your hours here stay free."

## A1 · Beam vs A2 · Object

| | A1 · Beam | A2 · Object |
|---|---|---|
| Duration | Fraunces hero numeral at 84 ("1 h 00 m"), centred, above a **timber beam on a blueprint ruler**. Drag sideways: timber is built, the dashed drafting line is not yet; 15-minute snaps with a selection haptic. | A **blueprint dial plate** (brand blue, drafting rings, white ticks). One turn is one hour; the white arc is the minutes and the pips are the whole hours; 15-minute detents. The numerals sit inside the plate. |
| House | 120pt, under the duration, beside "Pine Cabin · 59 → 60 of 100h. The roof goes on." | 108pt beside the sentence, at the top. |
| Reads like | Flighty and Wise: one number owns the screen. | Opal: an object you turn. |
| Timer | Beam fills as time runs, under the Fraunces numerals and the house. | The dial sweeps. |

## Standard amendments (round 3)

New components (5) and changes to existing ones (3). Everything else is an existing component or token.

**§1.7a `LHCaptureField` + `LHLevelMeter`** (from round 2):
- The note field: `.title3`, inner radius 12, white on the page.
- The filled `action` mic: 44pt, growing with Dynamic Type.
- A listening state: `stop.fill` and a 1.5pt `action` stroke.
- The meter: five 3pt capsules bound to the mic level.

**§1.28 `LHDurationBeam`** (A1; round 4 values: 24pt per quarter, height 80, clipped to the card, reading line 52 over ticks and beam only, presets below):
- Height 76.
- 18pt per 15 minutes; range 0–12h.
- The reading line is a 3pt `action` capsule.
- Built part `timber` with `timberInk` grain; unbuilt part a 1pt `drafting` dashed outline.
- Ticks: `draftingInk` (hour 14pt, quarter 7pt). Hour labels `.caption` `textSecondary`.
- 12% edge fades.
- Snaps to 0.25h, with `.sensoryFeedback(.selection)` on each step.
- `accessibilityAdjustableAction` steps ±15 min.
- [measured] height 76, tap area full width. [grep] no `repeatForever`.

**§1.29 `LHDurationDial`** (A2):
- 236pt (220 at AX), `brand` fill on both themes.
- Drafting cyan rings and ticks (the dark `action` token).
- Labels 60/15/30/45 in white at 85%.
- The minutes as a white arc, 6pt with a round cap; a white knob 26pt; one 6pt pip per whole hour.
- Numerals: the hero numeral at 44 in white.
- One turn is 60 min; 15-min detents with a selection haptic; adjustable action ±15 min.
- [measured] white on `brand` 9.06:1.

**§1.30 `LHHouseReadback`:**
- The rental's real still (`CraftStage.assetName(lit:)`).
- When this log crosses a stage, the next stage is drafted behind it (its still × `drafting` at 60%).
- On Log: the lit still fades over the unlit one (`windows` 0.40), and a crossed stage swaps with `stageFade` (opacity + 0.97→1).
- Dark: the §1.4 night exposure (plus-lighter 0.30 roofed / 0.12 framing).
- Reduce Motion: crossfades only.
- It only ever shows the rental's own stage.

**§1.28 `LHTimerFace`** (from round 2): replaced by the variant's own face (beam or dial) plus the "Management at Pine Cabin" line and "Started 8:28 AM · 08s".

**§1.14 amendment: the hero numeral in two places.** `LHFont.heroNumeral` is used for Today's "165" and Log time's duration. Sizes: 84 at default and 54 at AX, as Today uses (44 inside the dial).

**§1.14 amendment: one Fraunces sentence in a task sheet.** The read-back is `LHFont.fraunces(.title)` (28pt, never smaller), and "Say it" shows its live words the same way. It wraps; it never truncates.

**§1.20 `LHSheet(surface: .page)`** (from round 2): the focused sheet on the tinted page, with white cards.

## Consistency check (round 3)

| Used | Standard |
|---|---|
| `LHSheet` shape on `surface: .page`: header 56, `.icon` close, pinned `.primary`, ≤ 1 tertiary, AX policy | §1.20 + amendment |
| `LHButton.primaryGlass`, `.tertiary`, `.destructiveTertiary`, `.icon` | §1.13 |
| `LHRowGroup`, `LHRow.Browse` with `LHThumb.row` (Log again) and `LHRowGlyph` (Start a timer) | §1.4 |
| `LHThumb.header` (the rental choices) | §1.4, §H.5 |
| `LHSectionHeader`, `LHTag("Needs you", .caution)`, `LHDivider`, `LHChevron`-style `chevron.down` in menus | §1.15, §1.16, §1.2 |
| System `Menu` (work, who, day, rental) | §1.5 (≤ 5 options a menu; work has 8, so build uses a sheet) |
| Card: white, radius 20, padding 16, dark hairline | §1.10 |
| `LHFont.heroNumeral`, `LHFont.fraunces(.title)` | §1.14 + amendments |
| `DraftingLoader(.document)`, `LHToast` success with Undo | existing, §1.19 |
| Motion: `flow` (push), `windows` 0.40, `stageFade` 0.25, `standard` (numerals), `feedback`, `reduced` | §B.2/§B.3 |
| Tokens only: `AdaptiveColors`, `AppColors.brand`, `LHMetrics` (gutter 20, radii 12/20/6/capsule) | §1.2, D10 |
| **New:** `LHCaptureField`, `LHLevelMeter`, `LHDurationBeam`, `LHDurationDial`, `LHHouseReadback` | §1.7a, §1.28–1.30 |

## Builder self-check (round 3)

Captured on a slim iPhone 17 Pro simulator, iOS 27.0. 88 frames: 28 per variant and 16 shared (entry, typing, listening and logged are identical in both variants). They cover default and XXL in light and dark, plus AX3 for the review and duration states.

- **`frame_check.py`:** 72 unique frames, 3 flagged, 0 duplicates. All 3 were checked by eye and are not text defects:
  - 2 are house art in the "Log again" rows.
  - 1 is a row fading under the pinned footer at XXL (§1.20).
- **`frame_check.py breaks`:** 0 mid-word breaks in 88 frames. No truncation at default or XXL, checked by eye on every review, question, duration and timer frame. Long sentences wrap.
- **Contrast:** 20 new text pairs (`r3/qa/contrast-r3.txt`), 0 failures. The lowest is the unset dial numerals, white at 60% on `brand`: 4.31:1, which is large text (44pt), so it only needs 3:1. Next lowest are the "Say it" placeholder (4.88) and "Needs you" (5.02).
- **`frame_check.py density`:** 6 PASS, 26 FAIL, all from two rules:
  - **D6 (a non-hero card ≤ 20%):** the record card takes 56–63% of the screen, and the timer card 42–50%. This is deliberate: the card is the sheet's hero, like Today's house. Proposed rule: the record card is measured as a hero (H2-style), not as a non-hero card.
  - **D4 (empty bands ≤ 35%):** the Beam card measures 37–40%, from the air around the numerals. Marginal.
  - D2 also reads 47% "largest row" on dark Beam frames; the card is being measured as a row.

## Parser changes

1. **Field sources** (`note(tier)`, `assumed(reason)`, `timer`, `needed`). They drive the footnote and "Needs you".
2. **The span of the duration phrase.** The read-back drops it; the sandbox uses a comma heuristic.
3. **Property candidates and "unknown place"** for a one-rental free user.
4. **No default hours anywhere.** Timer hours are the exact minutes.

## Analytics, tests, size

- **Analytics:** as in round 2, plus `log_duration_control {beam|dial, drags, final_step}`. That shows whether people use the control or trust the note.
- **Tests:** as in round 2, plus unit tests for snapping (0.25h), the dial's wrap and accumulation (0–12h), `crossesStage`, and the read-back sentence.
- **Size:** about 10 working days. The beam or dial (2–3 days with haptics and accessibility) and the house beat (1 day, shared with Today's motion code) add to round 2's 8.

## Before build

- Brian picks A1 or A2.
- An independent critic reviews `r3/`.
- **A real-voice spike** on a device, about one day: every voice frame here is scripted.
- **AX3** for the whole flow. Only the review and duration frames are captured.
- **The house beat on a device**, inside the real shell.
