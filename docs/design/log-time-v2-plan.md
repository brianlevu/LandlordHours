# Log time v2 — build plan (design only, awaiting Brian)

2026-10-27 · branch `design/log-time-v2` · sandbox: `Sources/Views/Debug/LogTimeV2/` (DEBUG only).
Launch: `-LHLogV2 A` (round 2), `-LHLogV2 A -LHLogV2R1` (A as in round 1), `-LHLogV2 B` (round 1, kept for comparison).
Evidence: `~/AgentScratch/landlordhours/2026-10-27/logtime-v2/` (round 1) and `.../logtime-v2/r2/` (round 2). Critique: `.../logtime-v2/critic.md`.

## Decision so far

The independent critic picked **A (one line)**, with B's "Say it" screen as A's listening state. B ("three doors") stays in the sandbox, unchanged, for comparison: it takes 4 taps and starts every log with a choice.

## A, round 2: the flow

1. **One calm screen on the app's page colour.** A white "What did you do?" field with a filled 44pt mic. Below it, "Log again" chips (inset at the leading edge, faded at the trailing edge), a "Start a timer" row, and "Enter details yourself" as the one tertiary.
2. **Type:** 600 ms after the last key, a white card appears under the field.
3. **Speak:** tapping the mic pushes the "Say it" screen: big live words, a level meter, "Done", "Type instead". Done pops back with the words in the field, then the card.
4. **The card:**
   - A header that says where the values came from: "From your note", "From what you said", "From the timer", or "From the timer and your note".
   - The values as tokens (`LHChip`, wrapping), time first.
   - One footnote naming every value that was not in the note: "Not in your note: You, Today." or "Pine Cabin (your only rental)".
   - One open answer at a time. A field with no safe answer opens itself and shows "Needs you".
   - No chevrons.
5. **Log:** one primary, "Log 1h". When it is disabled it says why: "Answer 1 question".
6. **The timer** shows the Live Activity's content order, then "Stop and log", then an optional note, then the same card. The timer logs the minutes it ran (1h 12m in the note step, 1h 12m on the card), never a rounded value.
7. **Manual:** the same card with nothing assumed for time ("How long?" opens itself).
8. **Free plan:** opening the Rental token ends its answers with a locked "Add a rental" chip and the line "Free covers one rental. Your hours here stay free." That chip opens the existing `.secondProperty` paywall (`LockEntry.propertiesLimit`). Logging, voice and note reading are never gated.
9. **Motion:**
   - Steps push (`.push(from:)`, `flow`); "Done" and "Type instead" push back. Reduce Motion crossfades.
   - The card arrives with `flow` (opacity + 8pt). Values roll with `countChange`.
   - After Log the sheet dismisses first, and the toast appears only once it is gone.

## Standard amendments (r2: two new components, three small changes)

**New §1.7a `LHCaptureField` + `LHLevelMeter`.** The Log time note field, LHField's multi-line form:
- Type and size: `.title3`, inner radius 12, padding 16/14, placeholder `textTertiary`.
- Empty: min 104. Compact once the card shows: min 56, mic beside the words.
- On the page surface: `backgroundSecondary` fill (dark: hairline `border`).
- Mic: a filled `action` circle, 44pt, with an `onAction` `mic.fill`.
- Listening: `stop.fill` and a 1.5pt `action` stroke.
- `LHLevelMeter`: five 3pt `action` capsules bound to the mic level (`feedback`); static under Reduce Motion.
- [measured] mic 44×44. [grep] one per screen.

**New §1.28 `LHTimerFace`.**
- Line 1: a positive 8pt dot and "{Work} at {Rental}" in `.headline`.
- The elapsed time in `lhHeroNumberFont()` (the existing 56/700 SF Rounded tabular token).
- "Started 8:28 AM" in `.subheadline` `textSecondary`.
- It ticks once a second. No `repeatForever`.

**§1.20 `LHSheet(surface: .page)`.** A focused-entry sheet may sit on `background` (the tinted page) with its header and footer on the same colour, so white rows and cards read the way they do on Today, Rentals and Settings. `LogV2PageSheet` is this parameter, written out in the sandbox. This amends §1.20's "opaque sheet on backgroundSecondary".

**§1.16 `LHChipStrip(wraps: true)`.** `LHChip` in a wrapping layout (8 gaps) for values and answers inside a card. A non-wrapping strip that bleeds to the screen edge gets a 32pt trailing fade.

**§1.16 value tokens.** Inside the review card a chip shows a value (SF glyph + value). "Selected" means that its answers are open; it never means "on".

`LHReadRow`, `LHReadBack`, `LHAnswerChips` and `LHRowGroup(inSheet:)` from round 1 are dropped.

## Consistency check (A, round 2)

| Used | Standard |
|---|---|
| `LHSheet` shape (header 56, title2 + subheadline, `.icon` close, pinned `.primary`, ≤ 1 tertiary, AX policy) on `surface: .page` | §1.20 (+ amendment) |
| `LHButton.primaryGlass` ("Log 1h", "Answer 1 question" disabled, "Done", "Next", "Stop and log") | §1.13, §1.25 |
| `LHButton.tertiary` ("Enter details yourself", "Type instead", "Skip the note"), `.destructiveTertiary` ("Discard timer"), `.icon` (close) | §1.13 |
| `LHRowGroup` + `LHRow.Browse` + `LHRowGlyph` (Start a timer; the timer's rental and work) | §1.4, §1.10 |
| `LHChip`, `LHChipStrip` (Log again, value tokens, answers) | §1.16 (+ wraps) |
| `LHSectionHeader` ("Log again"), `LHTag("Needs you", .caution)`, `LHDivider` | §1.15, §1.16, §1.2 |
| `LHStepper` (time, after a chip), `LHSegmented` (who) | §1.9, §1.8 |
| Card: `backgroundSecondary`, radius 20, padding 16, dark hairline | §1.10 / `LHRowGroup` |
| `DraftingLoader(.document)` (reading), `LHToast` success with Undo, `lhHeroNumberFont()` | existing, §1.19, brand §3 |
| Tokens: `AdaptiveColors`; gutter 20, radii {12, 20, 6, capsule}; `AppAnimation` flow / reveal / feedback / quick / reduced | §1.2, D10, §B.2 |
| `LHCaptureField` + `LHLevelMeter` | **new §1.7a** |
| `LHTimerFace` | **new §1.28** |

No hex values, no `.system(size:)`, no Fraunces, no tool renders (§1.17). Every SF glyph sits in a `Label`-style slot under its text's font.

## Builder self-check (round 2)

Stopped mid-way on 2026-10-27. Brian approved A's flow but rejected the visual ("looks very common… like any typical form"), so round 2 was halted before its self-check. Its 72 frames are in `r2/frames` (A at default, XXL and AX3, light and dark), unchecked and not re-recorded. Next step: a calibration board (`logtime-v2/calibration/`) before any new SwiftUI.

## Parser changes (NoteReading)

1. **Per-field source**, not a number: `enum FieldSource { note(tier), assumed(reason), timer, needed }` on each field. The card's header and its "Not in your note" line come straight from this. A float confidence would be invented; a source is honest and testable.
2. **Property candidates:** when `mentionedPropertyCount ≥ 2` or the match is weak, return the candidates so the question shows those first.
3. **Unknown place:** flag a place-like phrase that matches no rental ("the duplex on Elm"). A free user with one rental is then asked, instead of having it silently filed under the only rental.
4. **No default hours anywhere**, the manual path included (today's sheet pre-sets 1h). Timer hours are the minutes it ran.
5. **Streaming:** run the rules tier on the partial voice transcript, so the card can start building while you talk.

## Before build (from the critique)

- **AX3:** frames for the main states are in `r2/frames`. The gate still has to review them.
- **Real-voice spike (1 day, a device):** on-device recognition of rental names ("Oak Street Duplex") in street and car noise. Every voice frame and video here uses a scripted transcript.
- **Sheet re-present glitch:** fixed in the sandbox (the toast waits for `onDismiss`). It still has to be proved on a device in the real shell.

## Analytics (PostHog, all new except the last)

`log_sheet_opened {entry}` · `log_path {type|voice|timer|recent|manual}` · `log_read {tier, filled[], needed[], ms}` · `log_question_answered {field}` · `log_field_corrected {field, from: note|assumed|timer}` · `log_abandoned {stage}` · `entry_logged` gains `{path, corrections, seconds_to_log}`.

Two numbers say whether the design works: the median seconds from open to Log, and the corrections per log on note-filled fields.

## Tests

- **Unit:**
  - field sources over the NoteReading eval set
  - no hours → needed (manual included)
  - a one-rental free user
  - two rentals named → needed, with candidates
  - timer minutes are not rounded
  - the disabled-Log reason count
- **UI** (XCUITest, sim + iPad): the type path, voice (scripted hook), question, free → paywall → back out, timer start/stop/note/log, and manual. `log.*` identifiers move to `logv2.*`. The old LogTime UI tests are rewritten in the same package, with no weakened assertions.
- **Visual gate:** every state in light and dark at default, XXL and AX3, plus density and contrast.

## Size

| Package | Work | Size |
|---|---|---|
| 0 | `LHCaptureField`, `LHLevelMeter`, `LHTimerFace` into `Views/Components`; `LHSheet(surface:)`, `LHChipStrip(wraps:)`; standard text | S (1 day) |
| 1 | Parser: FieldSource, candidates, unknown place, no default hours, eval set | M (2 days) |
| 2 | New LogTimeSheet (A) on the real form, voice, timer, toast; delete the old rows/stepper layout | M–L (3 days) |
| 3 | Analytics, UI tests, gates; real-voice spike on a device | M (2–3 days) |

About 8–9 working days, with packages 0 and 1 in parallel. The Live Activity and widgets are unchanged.
