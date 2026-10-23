# LandlordHours Design Standard

Draft r2, 2026-10-23. Status: proposal for Brian's review, not committed. Revision history: r1 reviewed independently → NOT READY (row contradicted its anchors, springs not measurable, swipe split, copy rewrites changed meaning, grammar gaps). r2 applies every finding. r2 is itself UNASSESSED until a fresh-context reviewer re-reads it.

Why this exists. Brian, on the Today "To confirm" card: "These card designs also waste too much space. I feel like we don't have a standard and bar for the design system and harness, which results in some amateur design like this." CLAUDE.md holds tokens, the brand doc holds the blueprint world, and nothing says how a row, a card, a button or a sentence is built, or how dense a screen must be. Each screen was composed alone, which is why the app has four tinted-capsule button styles, three primary pill styles, six hand-built close buttons and two hours steppers (§4).

Every rule here is one of three kinds, and says which: **[measured]** a number a script or PIL checks; **[grep]** a pattern a code search checks; **[judgment]** a call the independent reviewer makes in writing. Nothing else counts as a rule.

Evidence: `docs/design/2.0-brand-system.md`; code at `/Users/brian/tmp/lh-release2/Sources/Views`; frames under `~/AgentScratch/landlordhours/2026-10-2*/`; Mobbin anchors: [Copilot "To review"](https://mobbin.com/screens/39e851c1-7c5d-4f1e-bf81-1c3be05e5566) (rows ≈36pt, no per-row buttons, batch action at the foot), [Apple Reminders](https://mobbin.com/screens/4fcb0751-165a-429f-a395-defd9b2d9de3) (22pt leading control, swipes, meta line), [Things 3](https://mobbin.com/screens/5bc4a73d-af7d-4e63-aca2-27d13a2b1ed1), [Apple Fitness Summary](https://mobbin.com/screens/2745a5a7-c443-46cf-80bb-a3e7b72ff8f7), Apple Settings (forms).

---

## 0. The measured problem

One To confirm item on Today (`TodayComponents.swift:275`, `SuggestionRowView.swift`, `InboxComponents.swift:287`), default Dynamic Type, 402×874pt:

| Part | Height |
|---|---|
| Row: 12 padding + source line 20 + title 22 (2 lines: 44) + category/badge line 22 + 12 padding | 98–120pt |
| `InboxRowActions`: Confirm pill 44 + "Not rental work" 44, + 10 bottom padding | 54pt (108 when stacked) |
| Card padding and divider | 8pt |
| **One item** | **160–236pt = 18–27% of the viewport** |

Brian's phone showed about 40%; that is this anatomy at the Large/xLarge text size he runs. Copilot shows six review rows in 230pt; Reminders shows a task with subtitle, date, repeat and tag in 64pt. Target: one item ≈ 64pt, 7% of the viewport.

Causes, which repeat across the app: a decision row built like a detail card; the action as a pill under the words; a third text line that belongs in the sheet; a 36pt identity render in a row that is a decision; a card per thing instead of rows in a container.

---

## 1. Component grammar

### 1.1 Card, row, tag, chip, link

| Use | When | Never |
|---|---|---|
| **Card** `LHCard` | One subject needing two kinds of content at once: number + picture (hero), summary + CTA (Pro), question + answers. One card per subject. | A card per list item; a card holding only a title and a line. |
| **Row** `LHRow.*` | Items in a set to scan or decide on. Rows live in one grouped container (inset-grouped `List`), hairline dividers. | A lone row as a card; a pill under a row's text. |
| **Tag** `LHTag` | Read-only metadata on a row. ≤ 2 per row. | A tag that is a button. |
| **Chip** `LHChip` | Filter or prefill in a horizontal strip. | A chip as a primary action. |
| **Text link** `LHButton.tertiary` | The one secondary action in a header ("See all") or sheet footer ("Restore purchase"). | Row-level actions; two links side by side. |

From the anchors: Reminders, Things and Copilot never put a button in a row. The row is the tap target; per-item decisions are a leading control, a swipe, or the detail view; the batch action sits once at the card's foot. We do the same.

### 1.2 Tokens the components use

Page gutter **20** (Today's 24 and Properties' 16 retire) · section gap **24** · header→content **8** · card padding **16** · card radius **20 continuous** · inner surface **12** · tag **6** · stat tile **16** · hairline `border` 0.5 · type: system text styles, `design: .rounded` for numbers (always `monospacedDigit()`), `design: .monospaced` for drafting labels, Fraunces only for tab titles and display (§1.14) · colours: intent tokens only. **[grep]** no `.system(size:)`, no `Color(hex:)` outside the token files.

Hours format **[grep]**: one formatter `LHFormat.hours(_:)` → `"2h"`, `"30m"`, `"1h 30m"`, `"12h 30m"`, `"—"` for unknown. Replaces `InboxFormat.hours` and `AppFormat.hours` ("1.5h"). Decimal hours ("14.5") are allowed only inside the PDF/CSV tables. Measured widths (SF Pro Rounded semibold, tabular, AppKit): `.subheadline` 15: "12h 30m" 65.1pt, "1h 30m" 55.2; `.body` 17: 72.9 / 61.8; `.title2` 22 ≈ 94 (title3 20 measured 85.2). Column widths below come from these.

### 1.3 Actionable row `LHRow.Action` (the confirm item)

Anchor: Reminders for the leading control and meta line; Copilot for the batch foot.

```
┌──────────────────────────────────────────────────────────┐
│  ◯   Plumber at Pine Cabin                          2h    │  64pt
│      ▦ Calendar · Today 12–2 · [Repairs]                  │
└──────────────────────────────────────────────────────────┘
  16  22  12  ←──── 216–265pt title ────→  12  19–68  16
```

Width arithmetic (402pt screen): an inset-grouped card is 362pt wide (20pt system insets). Row content = 362 − 32 = 330. Control 22 + 12 gap = 34. Hours column hugs its content, trailing-aligned, min 19 ("2h") max 68 ("12h 30m"), + 12 gap. Title column = 330 − 34 − (hours + 12) = **216pt at the widest hours, 265pt at "2h"**. Measured at `.body` 17 semibold: "Plumber at Pine Cabin" 175pt fits beside any hours value (row 64); "Showing at Oak Street Duplex" 236pt fits beside "2h" (265) and wraps beside "1h 30m" (229 available; row 86); "Making monthly mortgage payment" 282pt and "Tenant call about the lease renewal" 278pt wrap in every case (row 86). So: short titles 64pt, long titles 86pt, ceiling 88 holds (D1). Titles are not shortened to force one line; the two-line case is the normal case for long reminder titles, as it is in Reminders.

| Part | Spec |
|---|---|
| Container | `List(.insetGrouped)` section; row insets 16/10/16/10; `minHeight: 56`; divider inset 50 (16+22+12). |
| Leading control | 22pt circle, 1.5pt stroke `textTertiary`, inside a 44×44 tap frame. Tap: if `canQuickLog` → fills `positive` with a white `checkmark` (motion `rowConfirm`); else opens the sheet (the "Needs hours" tag says why). `accessibilityLabel` "Confirm 2 hours" / "Review and confirm". **[measured]** 22pt glyph, 44pt frame. |
| Title | `.body.semibold`, `textPrimary`, `lineLimit(2)` at default, nil at AX. Source is one function, `InboxFormat.rowTitle(suggestion, propertyName)` → "Plumber at Pine Cabin" **[grep]**; whether the noun is the right noun is **[judgment]**. 216–265pt available (arithmetic above): "Plumber at Pine Cabin" 175pt fits on one line; titles over ~216pt wrap to two (row 86). |
| Meta line | `.subheadline`, `textSecondary`, one line, tail-truncates at default, wraps at AX. SF source glyph via `Label` (`calendar` / `checklist`) · relative date · time range · one `LHTag`: category, or a status tag ("Not sure", "Needs hours", "Might be logged") which replaces the category. Max 2 tags, overflow "+1". |
| Trailing: hours | `.subheadline.semibold` `.rounded` tabular, `textPrimary`, trailing-aligned, hugging its content: min 19pt ("2h"), max **68pt** (fits "12h 30m" at 65.1pt). "—" `textTertiary` when unknown. |
| Row tap | Opens the confirm sheet. |
| Swipe | System `.swipeActions` only (§1.3a). Trailing full swipe = "Not rental work" (`textSecondary` tint, `xmark`); leading full swipe = Confirm (`positive`, `checkmark`). |
| Decline | Via trailing swipe or the sheet's "Not rental work" `.tertiary`. No ✕ in the row. |
| Batch | Card foot: `LHButton.tertiary` "Confirm N likely" (N = rows with `canQuickLog` and not `notSure`); shown when N ≥ 2; one tap logs them with one toast "Logged 3 · Undo". Header keeps "See all". |
| Icons | SF Symbols only. No `CategoryToolTile` in a decision row; the render returns at 56pt in the sheet header. |
| Height **[measured]** | 64 with a 1-line title; 86 with 2 lines; ceiling 88 at default. |

#### 1.3a Swipe: one implementation, stated

**Decision: fully system.** `List` + `.swipeActions(edge:allowsFullSwipe: true)` in both Inbox and Today. No custom threshold, no `DragGesture`, no 96pt projection, no peek hint. Consequence: Today's root becomes a `List` with `.listStyle(.insetGrouped)` for the whole screen (as Reminders and Things are lists). The hero, timer slot and pace tiles are rows with `.listRowBackground(Color.clear)`, `.listRowInsets(EdgeInsets())` and `.listRowSeparator(.hidden)`; the To confirm rows are an ordinary inset-grouped section so the system draws the card and the swipe backgrounds clip to its corners. No hand-built card (`.propertyCard()`, `clipShape`) around rows anywhere **[grep]**: a custom card cannot clip a system swipe background correctly. `TodaySwipeRow`, `TodaySwipeHint` and `TodayDebugSeed.swipePreviewOffset` are deleted **[grep]**. The leading control is the visible affordance; Reminders ships no hint either. The haptic on a full swipe is ours, bound to the state change (§B.3), because the system fires none.

### 1.4 Browse row `LHRow.Browse`

Records, Properties, Learn, picker lists. Same grid as 1.3: leading **36pt** tile (`CategoryToolTile(36)` in Records; the house tile at 36 in Properties; an SF glyph in a 36 wash tile elsewhere), 12 gap, title 1 line + meta 1 line, trailing value (`LHFormat.hours`, `.subheadline.rounded`) and `chevron.right` `textTertiary`. Height 56–64. One ornament per row **[grep]**: Properties shows the house tile OR the monogram seal, never both (today `PropertyRow` has a 40pt seal, a 48pt house tile and a chevron).

### 1.5 Value row `LHRow.Value` (pickers)

Inside sheets and forms, in an inner surface (radius 12, `backgroundTertiary`): height 52, label `.body` left, value `.body` `textSecondary` right + `chevron.right` (or `chevron.up.chevron.down` for a menu). Tap opens a sheet (≥ 6 options) or a `Menu` (≤ 5). Replaces the hand-built value rows in `LogTimeSheet:593` and `SuggestionConfirmSheet`. **[measured]** 52pt.

### 1.6 Toggle row `LHRow.Toggle`

`SettingToggleRow` as is: min 44, label `.body` + optional one-line `.subheadline` subtitle, system `Toggle` tinted `action`. The subtitle says the effect, not the mechanism ("At most two a day, never at night.").

### 1.7 Text field `LHField`

Single line: inner surface radius 12, height 52, padding 16/14, `.body`. Placeholder in `textTertiary` (#5F6983, 5.5:1), never the system placeholder grey **[measured contrast]**. Focus: 1.5pt `action` stroke, crossfade 0.15. Error: `destructive` stroke + `errorShake` + one `.footnote` line under the field saying what to do. Clear button: 20pt glyph in a 44 frame. Multi-line (Log time note): min 104, same radius; the field is the first thing in the sheet and takes focus on open.

### 1.8 Segmented control `LHSegmented`

One struct replaces `BPSegmentedPicker`, `LogWhoPicker` and the picker in `SuggestionConfirmSheet:376`. Capsule track `backgroundTertiary`, height 36, 2–3 segments (more → `LHRow.Value`), labels `.subheadline.semibold`; selected thumb `backgroundSecondary` with hairline, label `textPrimary`; motion `segmentSlide`; haptic `.selection`. Min segment width 64 **[measured]**.

### 1.9 Stepper `LHStepper`

One struct replaces `LogHoursStepper` and `SuggestionConfirmSheet:252`. Two `LHButton.icon` (`minus`, `plus`) flanking the value in `.title2.rounded.semibold` tabular, value column **100pt** (fits "12h 30m" ≈ 94). Not 40pt digits. Step 15m; long-press repeats every 0.12s after 0.4s; `.selection` per step; min 0, max 24h with the "ran past 24h" line.

### 1.10 Summary card `LHCard.Summary`

Anchor: Fitness Summary tiles. `backgroundSecondary`, radius 20, padding 16, hairline in dark only. Order: eyebrow (drafting: SF Mono 11 `.medium` caps +12% tracking, **`draftingInk`**) → value (`.largeTitle.rounded.bold` tabular) → label `.subheadline` `textSecondary` → optional `.footnote` → optional one `LHButton.secondary`, or the card is one `.lhPressable` target. Ceiling 160pt at default **[measured]**. The blueprint hero is the one exception (≤ 320pt; the only card with an illustration; eyebrow in drafting cyan `#8FD3FF` on blueprint per the brand doc).

**Today decision (2026-10-23, after the first mockup pass):** the rental switcher lives **inside the bottom of the house card**, as one slim row of small houses (one per rental plus "All"), each ≤ 32pt tall in a 44pt tap frame, horizontally scrolling when they do not fit. The selected house carries a 1.5pt drafting-cyan ring; switching crossfades the hero number and art (`countChange`, `heroCountUp`). There is **no separate tile strip** under the hero; the hero's 320pt ceiling includes this row.

### 1.11 Stat tile `LHTile.Stat`

Two-up, 12 gutter, radius 16, padding 14. Value `.title2.rounded.bold` tabular; label `.caption` `textSecondary` one line; optional trend glyph. 84–96pt **[measured]**. Read-only or whole-tile tap.

### 1.12 Chart and ring `LHRing`, `LHBarRow`

Ring (Reports): 18pt stroke, 260pt, track `actionSurface`, fill `action`; pace states use `positive`/`caution`; no gradients outside the hero. Bars: 8pt, radius 4, label `.subheadline` left, value tabular right. Animate on value change only (`ringProgress`), never on appear **[grep]**. `accessibilityValue` carries the number and the target ("206 of 750 hours").

### 1.13 Buttons `LHButton`

One `ButtonStyle` enum, four cases. Retire `PropertyTintedButtonStyle`, `ProTintedButtonStyle`, `TodayTintedButtonStyle`, the inline Confirm capsule, `ProUnlockButtonStyle`, `OnbPrimaryPill`, `OnbOutlinePill`, `OnbHeroPill`, `InboxPrimaryButtonStyle`, and the six hand-built close circles **[grep]**.

| Case | Size | Fill / ink | Where |
|---|---|---|---|
| `.primary` | 52 full width capsule, `.body.semibold` | `action` / `onAction`; on blueprint: white / brand | One per screen or sheet, pinned bottom in sheets. |
| `.secondary` | 44 hug, padding 18, capsule, `.subheadline.semibold` | `actionSurface` / `action` | Section actions ("Turn on"). |
| `.tertiary` | 44 text, `.subheadline.semibold` | clear / `action` (or `destructive`) | "See all", "Confirm 3 likely", "Restore purchase", "Undo". |
| `.icon` | 44 circle, symbol `.body.semibold` | `backgroundTertiary` / `textSecondary`; on blueprint `white.opacity(0.14)` / white | Close, mic, stepper. |

Press = motion `press`. Disabled = 40% opacity. The symbol weight inside `.icon` is the one place a symbol weight is set explicitly (§1.17).

### 1.14 Screen titles `LHScreenTitle`

Tab roots: **Fraunces 34/500** via `Font.custom("Fraunces", size: 34, relativeTo: .largeTitle)` (brand doc §3), optional one-line `.subheadline` `textSecondary` subtitle, 20 gutter, 8 below, one trailing `.icon` at most. Sheets: SF `.title2.semibold` with an optional drafting eyebrow ("TODAY · THU, OCT 22") in `draftingInk`. Display (Welcome, milestone): Fraunces 34. **[grep]** Fraunces never under 28pt and never inside a row, card or button.

### 1.15 Section header `LHSectionHeader`

Drafting label (SF Mono 11 `.medium` caps +12%) in **`draftingInk`**; when the header names a state ("NEEDS ATTENTION", "ON PACE") it may use `caution`/`positive` ink (intent colour on words, brand doc §2). Optional count capsule (height 20, `.caption2.semibold`, `actionSurface`/`action`). Trailing slot: one `.tertiary`. 24 above, 8 below. Replaces `TodaySectionHeader`, the inline header in `InboxView:85` and `BPSectionHeader` **[grep]**.

### 1.16 Tags and chips

| | `LHTag` | `LHChip` |
|---|---|---|
| Height | 20 | 34 |
| Type | `.caption2.medium` | `.subheadline.medium` |
| Padding | 6/2 | 12/0 |
| Shape | radius 6 | capsule |
| Colour | intent ink on 12% wash (category wash for categories) | selected `action`/`onAction`; idle `backgroundTertiary`/`textPrimary` |
| Limit | 2 per row | one strip per screen, 8 gaps |

### 1.17 Icon rules

- SF Symbols for everything functional. Weight follows the text automatically: symbols are placed with `Label` or `Image(systemName:)` under the same `.font` as their text; **[grep]** no explicit `.fontWeight`/`weight:` on a symbol outside `LHButton.icon`.
- Brand tool renders (`CategoryToolTile`): **36pt in browse rows and picker lists, 56pt in picker grids and sheet headers; never in decision rows (Today To confirm, Inbox rows); never under 32pt** **[grep on the `size:` argument]**. This supersedes the brand doc's "36–48pt in category rows and Inbox" and is written back into it (brand doc §4, same revision). No `Image("bp_tool_…")` outside the tile (two sites today).
- No emoji, no emoji-style art, no Lucide (package removed).
- Tap targets ≥ 44×44 for every control **[measured]**.

### 1.18 Empty state `LHEmptyState`

In a container: SF Symbol 28 in `positive`/`action` → `.headline` → `.subheadline` `textSecondary` ≤ 2 lines → optional `.secondary`. Padding 20, total ≤ 160 **[measured]**. Full-screen (Inbox with nothing): blueprint art ≤ 40% of viewport, one headline, one line, one `.primary`.

### 1.19 Toast `LHToast`

Current component (radius 22, min 52): one glyph + ≤ 2 lines + one `.tertiary`. 12 above the tab bar. 4s; 8s with an action. Swipe down dismisses. One at a time, crossfade on replace.

### 1.20 Sheet `LHSheet`

System `.sheet`, detents `[.medium, .large]` when content allows, drag indicator visible. Header 56: title (§1.14 sheet style) left, `.icon` close right. Gutter 20. `.primary` pinned via `safeAreaInset`, 16 inset; ≤ 1 `.tertiary` above it. No hero art in task sheets.

### 1.21 Alerts and dialogs

System `.alert` only for irreversible destructive acts (delete all data, remove a rental): title ≤ 6 words, message ≤ 2 sentences, buttons are verbs ("Delete", "Keep"), destructive role set; never "OK"/"Yes". ≥ 3 choices → `.confirmationDialog`. Everything reversible gets a toast with Undo, never an alert **[grep: `.alert(` sites listed in the hand-off]**.

### 1.22 CPA footnote `LHFootnote.cpa`

`.footnote`, `textSecondary` (tertiary fails AA on canvas at 12pt), last element of the content, at most one per screen **[grep]**. Canonical key `common.cpaFootnote` = "Your CPA decides what the numbers mean."

### 1.23 Paywall scaffold

Blueprint band ≤ 40% of viewport with the record preview (the preview's title string is the same key as the real PDF title, §C.5) → plan card radius 20: name + `LHTag` "PAY ONCE" → price `.largeTitle.rounded.bold` + "once, yours to keep" `.subheadline` → one body line → `.primary` "Unlock for $29.99" → `.tertiary` "Restore purchase" → status line → benefits as 52pt `LHRow.Browse` with SF glyphs → legal `.footnote` links in 44 frames. Close is `.icon` on blueprint. No countdowns, no fake scarcity, no `dynamicTypeSize` clamp.

### 1.24 Onboarding scaffold

Uses the app's components and tokens; `OnbColor` and the `Onb*` styles are deleted **[grep]**. Progress: 3pt track `border`, fill `action`. Back `.icon`, Skip `.tertiary`. Step title SF `.title1.semibold` (Fraunces only on Welcome). Option cards are `LHRow.Browse` rows in one grouped container; selection is shown the Apple Settings way, with a **trailing `checkmark` in `action`** (`.body.semibold`, 44 frame) on the selected row and the row's hairline stroke turning `action`; the leading slot holds the option's SF glyph. The 22pt leading circle is reserved for confirm in §1.3 and never appears in onboarding or pickers **[grep]**. One `.primary` pinned. No Dynamic Type clamps; frames at AX3 required.

### 1.25 Widgets and Live Activity

SF Symbols and the mono mark B template only; numbers `.rounded` tabular via `LHFormat.hours`; small: value + label; medium: value + current house render; Lock Screen/Island: mono glyph + hours; checked in accented and tinted modes; ≤ 2 text lines; no tool renders.

---

## 2. Density rules

Default Dynamic Type, 402×874pt, light and dark, unless stated. The builder reports these numbers before hand-off; the gate re-measures (§5).

| # | Rule | Number | Kind |
|---|---|---|---|
| D1 | Actionable row height, divider to divider | 56–88; target 64 | measured |
| D2 | One list item's share of viewport | ≤ 12% default; ≤ 45% at AX3 (a two-line row at AX3 cannot meet 30%; mockup review 2026-10-23) | measured |
| D3 | List tab (Inbox, Records, Properties) with ≥ 5 items present: complete rows visible under the title, above the tab bar | ≥ 5 at default, ≥ 4 at XXL | measured |
| D3b | Today above the fold at default and XXL | title + hero + section header + ≥ 2 rows + next header | measured |
| D3c | Today at AX1–AX3 | hero switches to its compact variant (number + label, art hidden, ≤ 160pt); title + compact hero + header + ≥ 1 row visible | measured |
| D4 | Empty bands inside a card: pixel rows within the card inset 16 that are all card background (ΔE ≤ 3), as share of card height | ≤ 35%. Applies to `LHCard.*` and the hero. Grouped value-row containers (Settings-style `LHRow.Value`/`LHRow.Toggle` groups, as in Settings, Log time and the confirm sheet) are exempt: their padding is the row rhythm, and Settings itself would fail | measured |
| D5 | Primary actions per card; actions in a row | 1 per card; rows: one leading control, no pills | grep |
| D6 | Non-hero card viewport share; hero incl. its header | ≤ 20%; ≤ 40% | measured |
| D7 | Text lines per row | ≤ 3 (title ≤ 2, meta 1) | measured |
| D8 | Buttons per screen | 1 `.primary`; ≤ 2 `.secondary` visible | grep |
| D9 | Gutter / card padding / section gap | 20 / 16 / 24, ±1 | measured |
| D10 | Radii on one screen | ⊆ {6, 12, 16, 20, capsule} | grep |

Dynamic Type (XXL and AX3 frames required):
- Rows grow and reflow: at AX sizes `LHRow.Action` stacks (control + title; meta below; hours after the meta).
- `lineLimit(nil)` and `fixedSize(horizontal: false, vertical: true)` at AX **[grep]**.
- `minimumScaleFactor` ≥ 0.8, never on `.body` **[grep]**.
- `.dynamicTypeSize(` clamps only on the hero number and the house art **[grep: ≤ 2 sites]**.

---

## 3. The To confirm item, redesigned

Three items at default, 402pt:

```
TO CONFIRM  (3)                                             See all
┌────────────────────────────────────────────────────────────────┐
│  ◯   Plumber at Pine Cabin                                2h   │
│      ▦ Calendar · Today 12–2 · [Repairs]                       │
│     ─────────────────────────────────────────────────────────  │
│  ◯   Making monthly mortgage payment                       —   │
│      ☑ Reminder · Oct 8 · [Needs hours]                        │
│     ─────────────────────────────────────────────────────────  │
│  ◯   Showing at Oak Street                              1h 30m │
│      ▦ Calendar · Oct 8 9–10:30 · [Not sure]                   │
│     ─────────────────────────────────────────────────────────  │
│                      Confirm 1 likely                          │  ← when N ≥ 2; here N = 1 so hidden
└────────────────────────────────────────────────────────────────┘
```

(▦ `calendar`, ☑ `checklist`; `[ ]` an `LHTag`; ◯ the 22pt leading control in a 44 frame. Row 2 wraps to 86pt because its title is 282pt wide. In this sample only row 1 is quick-loggable and likely, so the foot is hidden; with two such rows it reads "Confirm 2 likely".)

| Before | After | Why |
|---|---|---|
| Hours stacked "1h / 30m" `.title2`, 52pt leading | "1h 30m" `.subheadline.rounded`, 68pt trailing | Copilot's amount column; one line |
| 36pt tool render | none; 56pt in the sheet header | Identity art has no room in a decision row |
| Source line, then title, then category, then badges | Title, then one meta line with one tag | Title is what you decide on |
| Confirm pill 44 + "Not rental work" 44 under the words | 22pt leading control + system swipes + "Confirm N likely" at the foot | Reminders control, Copilot foot; 54–108pt saved per item |
| 160–236pt per item | 64 (86 for a 2-line title) | D1 |
| Custom `DragGesture` on Today, `.swipeActions` in Inbox | `.swipeActions` in both | One implementation |

VoiceOver: row = "Plumber at Pine Cabin, Calendar, today 12 to 2, Repairs, 2 hours. Button." Actions: "Confirm 2 hours", "Not rental work" (`accessibilityAction`s as in `TodaySwipeRow:333`). The leading control is its own element, "Confirm 2 hours, button".

Interaction: row tap → sheet. Control tap → `rowConfirm` (no bounce; `.success`); needs-decision items open the sheet. Leading full swipe → confirm with `.success`; trailing full swipe → "Not rental work" with `.impact(.light)` and a toast "Marked not rental work · Undo". Foot → batch confirm, one toast "Logged 3 · Undo".

Classifier issue (separate fix): "Making Monthly Mortgage Payment" was proposed as Management, "Not sure". `RulesClassifier.apply` (`Sources/Services/Capture/Classifier/RulesClassifier.swift:189`) remaps a loan payment to Bookkeeping only when the incoming category is already Financing; the keyword table scored it Management, so the guard never fired. Fix: evaluate `isLoanPayment` for any category before the Financing guard; add that exact title as a test. Second issue: a reminder with no duration showed "30m"; proposed hours for durationless items should be nil ("Needs hours"), not a guess.

---

## 4. Full-app audit inventory

**Standard** = conforms or token swaps only · **Drift** = right pattern, wrong numbers · **Redesign** = wrong pattern for the job. Facts from the code inventory and the 2026-10-21/23 frames.

### Redesign, ranked by user impact

| # | Screen | File | Reason |
|---|---|---|---|
| 1 | **Today** | `DashboardView.swift`, `Today/TodayComponents.swift` | Items 160–236pt (18–27%); custom swipe; card stack of pace cards and 92pt activation tiles; 16 raw sizes; becomes a `List` root (§1.3a). |
| 2 | **Inbox** | `Inbox/InboxView.swift`, `SuggestionRowView.swift`, `InboxComponents.swift` | Same row plus pill; the question card stacks three 52pt pills for one yes/no/unsure (300pt, > 35% empty by D4); title and header drawn inline. |
| 3 | **Log time** | `LogTime/LogTimeSheet.swift` (1255 lines) | Own 52pt style, 64pt timer and 40pt stepper digits in raw sizes (7), 17 `fixedSize`s, 2-line prefill chips, mid-sheet text link; `InboxBlueprintPaper` r24 inside a sheet. |
| 4 | **Properties** | `PropertiesView.swift` | Two ornaments per row (40pt seal + 48pt house tile) + chevron; gutter 16; "Add property" pill in the title row; detail hero 188 r24; inline r20 cards in the edit sheet. |
| 5 | **Suggestion confirm sheet** | `Inbox/SuggestionConfirmSheet.swift` (698 lines) | Second stepper and second Me/Spouse picker; r12/r16 mix; 8 raw sizes; two close buttons at different fonts. |
| 6 | **Onboarding** | `Onboarding/*` | Own palette, three pill styles and a link style, `.dynamicTypeSize(.large)` on three screens, 23 `fixedSize`s; the conversion path shares no component with the app. |
| 7 | **Paywall** | `Paywall/PaywallView.swift`, `RecordPagePreview.swift` | Near-standard, but 5.5–13pt mini-document type, 4 literal hexes, a `...xxLarge` clamp, "WHAT YOU GET" below the fold, and the preview title ("2026 hours record") differs from the real PDF ("Rental Activity Time Log"). |

### Drift (fix in place)

| Screen | File | Reason |
|---|---|---|
| Records | `HistoryView.swift` | Right container; tile stays 36 (§1.17); chips r10 → `LHChip`; 2-line titles → 1. |
| Reports | `ReportsView.swift` | r16/r20 mix, `StandingCard` padding 18, 8 `fixedSize`s, `BlueprintList.swift:5` says "list". |
| Time entry detail | `TimeEntryDetailView.swift` | Right container; 56 tile OK as header; thumbnails r10 → 12. |
| Settings | `SettingsView.swift`, `BlueprintList.swift` | Closest to standard; Pro card r12 → 20; `ProTintedButtonStyle` retired; two `Form`s → `List`. |
| Learning Center | `Learn/LearningCenterView.swift` | Rows 60/52 → 56; hero 150 r24 → `LHCard.Summary`; 9 `fixedSize`s. |
| Milestone | `House/MilestoneCelebrationView.swift` | Signature, allowed big; 8 raw sizes → tokens. |
| Locked preview | `Components/LockedPreview.swift` | `ProUnlockButtonStyle` → `LHButton`; `...xxxLarge` clamp goes. |
| Export, Contact support, Delete all data, Profile sheets | respective files | Standard containers; button/close swaps. |
| House hero | `House/HouseHeroView.swift` | The allowed tall card; eyebrow wraps to two lines at default ("MORE THAN ANYONE ELSE") → trim to one; compact variant for AX (D3c). |
| Tab bar | `ContentView.swift` | Standard; 4 raw sizes → tokens. |

### Standard

`LHToast`, `BPEmptyState`, `BPFilterChip` (→ `LHChip` at 34), `CategoryToolTile` as a component.

### Delete

`TasksView.swift`, `CategoryManagementView.swift` (unreachable, Lucide, `Color(hex: category.colorHex)`), `EntryListRow` (`DashboardView:957`), `lhSurfaceCard`, `LHSuccessToast`, `LHIconTile`, Lucide `CelebrationType`, the `lucide-icons-swift` package, `TodaySwipeRow`, `TodaySwipeHint`.

### Consistency inventory

Every touched screen is labelled **new-system**, **recoloured-legacy** or **untouched**, literally. Today, Inbox, Log time and Properties are recoloured-legacy now.

---

## 5. Gate rubric addendum

Builder runs these and puts the numbers in the hand-off; the gate re-measures and confirms. A measurable defect the builder could have caught is a process failure.

### 5.1 Density (PIL) — `scripts/density_gate.py <frame.png> --rows <ids>`

1. Item share = item bbox height ÷ frame height (D2). 2. Items above the fold = complete row boxes between the title's bottom and the tab bar's top, found by divider runs (`border`-coloured pixels ≥ 60% of card width) or XCUITest element bounds (D3/D3b/D3c). 3. Empty bands (D4), skipping exempt value-row groups. 4. Row height between dividers (D1); a card's foot action ("Confirm N likely", `today.confirm.batch`) is not a row and is excluded from D1 and from the D3 row count, identified by its accessibility identifier or by having no divider above it. 5. Gutter = frame edge to first non-canvas pixel in the content column (D9). 6. Contrast ≥ 4.5:1 on every text pair including placeholders, disabled, secondary and tag ink on wash. 7. No two differently named state frames byte-identical.

### 5.2 Component conformance

**[grep]** Every row, card, tag, chip, button, header, field, segmented control, stepper, empty state, toast, sheet and alert in the diff is a §1 component by name, listed in the hand-off. Zero new `.system(size:)`, `Color(hex:)`, `Image("bp_tool_`, `Lucide`, emoji, `.fontWeight` on symbols outside `LHButton.icon`, or `.dynamicTypeSize(` outside the two sites. Radii ∈ D10. `CategoryToolTile(size:)` ∈ {36, 56} and never in `Inbox/` or `Today/` rows. Frames at default, XXL, AX3, light and dark; no clipping, no mid-word break, no truncation at AX.

### 5.3 Motion conformance

Hand-off names the §B motion for each animated change and its token. **[grep]** every spring is `.spring(duration:bounce:)` with duration ≤ 0.30 (signature tokens ≤ 0.60) and `bounce` > 0 only inside a gesture `onEnded`/`swipeActions` commit path; every `withAnimation`/`.animation` is bound to a state `value:` or a gesture; `.onAppear { withAnimation` only in `emptyStateEntrance` and the milestone; `repeatForever` only in `scanningLine`; every `.sensoryFeedback(trigger:)` trigger is the same `@State` that an `.animation(value:)` watches; no haptic or trigger increment inside `asyncAfter`.

### 5.4 Copy conformance

Copy gate + §C: **[grep over `Localizable.xcstrings`]** banned words absent; per-screen average ≤ 14 words per sentence, hard max 22 (`scripts/copy_gate.py --screen <prefix>`); canonical ideas use their canonical key (§C.5). **[judgment]** read-aloud test by the assessor as the named persona.

### 5.5 Anchor question **[judgment]**

The gate puts the frame beside the anchor (Copilot, Reminders, Things, Fitness, Apple Settings) and writes the answer to: "Would this sit next to the anchor app without looking like the hobby version?" Passing numbers with a "no" here is MARGINAL and goes to Brian with both frames.

---

## A. Brand personality

The house is the brand: progress you can see, numbers you can stand behind. The app sounds like the person who built it.

| Trait | What it is | What it is not |
|---|---|---|
| **A calm friend who knows the rules** | One plain sentence per number; points to your CPA for the verdict; never raises its voice. "206 of 750. Your CPA decides what that means." | Not a lawyer (no disclaimer per line), not a cheerleader (no "Amazing!", no streak guilt), not an advisor. |
| **A good contractor** | Says what was done, with the count. Shows the work: every hour has a date and a source. | Not a salesman: never "powerful", "seamless", "effortless"; never a number behind a metaphor. |
| **Honest about uncertainty** | "Not sure" is a tag, not a failure. Nothing counts until you confirm it. Hatched parts are drawn, not built. | Never claims an unconfirmed hour; never "qualified", "audit-ready", "proof". |
| **Quietly crafted** | Blueprint grid, mono eyebrows, the brass sign at 500h. Motion shows cause and effect, then stops. | Not playful for its own sake: no confetti outside the three milestones, no mascots, no load-in choreography. |

Test **[judgment]**: would the contractor who built the house say this in the doorway, in under ten words?

---

## B. Motion language

### B.1 Purpose and rules

Motion is for three things: cause and effect (you pressed it, it moved), progress (the number counts, the house rises), confirmation (one beat that says saved, then stillness).

Rules, all **[grep]** unless marked:
- Springs are written `.spring(duration:bounce:)` (iOS 17+). A single animation ≤ 0.30s; a two-step sequence ≤ 0.40s total; the signature tokens (`stage`, `ringProgress`, `count`) ≤ 0.60s.
- `bounce` > 0 only on a gesture release (swipe commit, drag settle). Taps get `bounce: 0`. The existing `checkPop` (`spring(response: 0.26, dampingFraction: 0.5)` on swipe commit in `TodaySwipeRow:373`) is the gesture case and maps to `pop`; a tap on the leading control never pops.
- Every animation is bound to a state change (`.animation(_:value:)`, `withAnimation` in an action, or a gesture). `.onAppear { withAnimation` is allowed in exactly two places (`emptyStateEntrance`, the milestone's `houseStageAdvance`). `repeatForever` only in `scanningLine`. That is what "never decoration" means here.
- Haptics: one per event; the `.sensoryFeedback(trigger:)` state is the same state the animation watches, so they fire on the same frame; no `asyncAfter` before a haptic.
- Every event that translates, scales or shakes has a `reduceMotion` branch that keeps opacity and colour only.

### B.2 Tokens (`AppAnimation`, revised)

| Token | Value | Replaces |
|---|---|---|
| `feedback` | `.easeOut(0.12)` | same |
| `quick` | `.easeInOut(0.15)` | same |
| `reveal` | `.easeOut(0.22)` | same |
| `standard` | `.easeInOut(0.24)` | same |
| `smooth` | `.spring(duration: 0.28, bounce: 0)` | `spring(response: 0.28, dampingFraction: 0.9)` |
| `flow` | `.spring(duration: 0.30, bounce: 0)` | `spring(0.34, 0.88)` |
| `collapse` | `.spring(duration: 0.25, bounce: 0)` | new |
| `settle` | `.spring(duration: 0.30, bounce: 0.15)` — gesture release only | `bouncy` 0.32/0.86 |
| `pop` | `.spring(duration: 0.26, bounce: 0.30)` — gesture commit only | `pillPop`, `checkPop` |
| `count` | `.easeOut(0.60)` — hero digits only | new |
| `ringProgress` | `.spring(duration: 0.60, bounce: 0)` — hero mask, ring | `spring(0.7, 0.82)` |
| `stage` | `.spring(duration: 0.45, bounce: 0)` — milestone only | `logoEntrance` |

### B.3 Named motions

| Name | Event | Motion | Token(s) | Haptic | Reduced motion |
|---|---|---|---|---|---|
| `press` | any button, chip, tile, row | scale 1 → 0.97 on down; back on up | `feedback` / `quick` | none | opacity 1 → 0.8 |
| `rowConfirm` | leading control tapped (or batch) | control fills `positive`, checkmark fades in (0.12); row height → 0 and opacity → 0 (0.25). Total 0.37 | `feedback` then `collapse` | `.success` at the fill | colour fill; row fades 0.15; layout snaps |
| `swipeConfirm` | leading full swipe commits (system) | system swipe; on commit the control pops 1 → 1.15 → 1 (0.26) while the row collapses (0.25); total ≤ 0.40 | `pop` then `collapse` | `.success` | fill + fade 0.15 |
| `rowDismiss` | trailing full swipe (system) or sheet "Not rental work" | system swipe-out; then collapse (0.25) | `collapse` | `.impact(.light)` | fade 0.15 |
| `segmentSlide` | `LHSegmented` change | thumb x translates (0.25), labels crossfade (0.15) | `.spring(duration: 0.25, bounce: 0)`, `quick` | `.selection` | crossfade only |
| `tileFocus` | picker tile selected | ring stroke `border` → `action` crossfade (0.15); no scale | `quick` | `.selection` | same |
| `countChange` | count capsule, row hours, stat values | `contentTransition(.numericText())` | `standard` | none | crossfade |
| `heroCountUp` | hours value changes while Today is visible, never on appear | digits count from the previous value (0.60); house mask rises (0.60) | `count`, `ringProgress` | none | digits jump; mask crossfades 0.2 |
| `houseStageAdvance` | hours cross 100 / 500 / 750 (signature) | linework → solid crossfade (0.22) while the new part scales 0.96 → 1 (0.45); brass sign fades in at 0.30; one confetti burst ≤ 0.60; total ≤ 0.60 | `reveal`, `stage` | `.success` once at the sign | solid part fades in 0.3; no scale, no confetti |
| `toastIn` / `toastOut` | toast shown / dismissed | in: y +24 → 0 with opacity (0.22); out: opacity → 0, y 0 → +12 (0.15); swipe-down follows the finger then `settle` | `reveal` / `quick` | `.success` saves, `.error` failures, none info | opacity only |
| `sheetUnfold` | section expands inside a sheet | height with content fade (0.30); ≤ 4 rows stagger at 30ms | `flow`, `reveal` | none | fade 0.2, no stagger |
| `buttonStateChange` | Confirm → Logged, Save → Saved | label crossfade with 2pt blur (0.22) | `reveal` | carried by the event | crossfade, no blur |
| `errorShake` | save failed, invalid field | x 0 → 8 → −6 → 4 → 0 over 0.28; stroke → `destructive` (0.15) | keyframes, `quick` | `.error` | stroke colour only |
| `pullToRefresh` | Inbox / Records pulled | system `refreshable`; `DraftingLoader` line draws once per cycle | linear | `.success` only if something new | same |
| `emptyStateEntrance` | empty state replaces a list | glyph, headline, body fade and rise 8pt, 40ms apart (≤ 0.30 total) | `reveal` | none | fade only |
| `scanningLine` | "Looking through your calendar" | line draws across; cycle ≥ 1.6s | linear | none | static dashed line |
| `fieldFocus` | `LHField` focused | stroke `border` → `action` (0.15) | `quick` | none | same |

---

## C. Voice and tone

### C.1 Voice rules

1. Short sentences: per screen average ≤ 14 words, hard max 22 **[grep script]**.
2. Plain words: the word list (C.4) **[grep]**; the read-aloud test (C.3) **[judgment]**.
3. Second person; "we" only when the app did something **[judgment]**.
4. Numbers first; numerals for ≥ 2 **[grep: no spelled numbers ≥ two]**.
5. No tax advice; the CPA footnote at most once per screen **[grep]**.
6. Never "qualify/qualified/qualification", "audit-ready", "evidence", "proof", "compliance", including the PDF title and file names **[grep]**.
7. Verbs over nouns ("Log an hour", "Count toward") **[judgment]**.
8. One idea per sentence, one sentence per label, two per body line, three per empty state **[measured in the copy gate]**.
9. Say the effect, not the state ("Nothing counts until you confirm it") **[judgment]**.
10. Same word for the same thing: canonical keys (C.5) **[grep]**.

### C.2 Tone by context

| Context | Tone | Do | Don't |
|---|---|---|---|
| First run | Welcoming, brief, no promises | "Every hour you log starts with a place." · "Add a rental. Hours you confirm count toward your goal." · "A nickname is fine. The rest comes later." | "Track your path to tax qualification" · "A few quick steps make every hour easier to review later." · "LandlordHours can notice your rental work" |
| Progress | Count, then one next step | "206 of 750 hours." · "Log a few weeks to see your pace." · "Roof at 500h." | "Your hours now build a house." first · "Know where you stand on your hours." |
| Behind pace | Factual, forward, no blame | "55h a week to finish by Dec 31." · "Behind by 396h." · "Add last week's hours and this moves." | "You're falling behind!" · "Needs a few weeks of hours" · "No urgent action right now." |
| Success | One beat, then quiet | "Logged 1h 30m at Pine Cabin." · "Roof is on. 500 hours." · "Saved." | "Amazing!" · "Material participation test 1 met, based on your records." · "You're all set!" after every save |
| Error | What happened, then what to do | "Couldn't save. Pick a property for this one." · "Can't read your calendar. Allow Full Access in Settings." · "Timer ran past 24h. Check the hours." | "That didn't go through. Try again in a moment." · "Not saved. This one needs Pro." · "Something went wrong" |
| Paywall | Plain price, plain list | "$29.99 once, yours to keep." · "Every rental, the PDF and the spreadsheet." · "No subscription." | "Unlock the full power" · "audit-ready records" · "Don't risk your deduction" |
| Empty state | What this is for, one action | "Hours you log or confirm show up here, by month." · "Nothing in the last 90 days looked like rental work." · "Add your first rental." | "It's quiet in here!" · "No data available" · three sentences for one |
| Notification | Fact, question, done | "Plumber visit just ended. Log 2 hours at Pine Cabin?" · "Your timer's still going. 6h so far." · "3 calendar events look like rental work." | "Don't forget to log your hours!" · "Refresh your latest REPS pace." · anything after 9 pm |

### C.3 The read-aloud test **[judgment]**

Say the line to a friend who owns one rental. If you would rephrase mid-sentence, rewrite. If it needs a comma to breathe, split. If it has a kitchen-foreign word ("activity", "participation", "profile"), swap. The assessor runs this as the named persona (a landlord with two rentals and a W-2 job) and writes the first thing understood in 5 seconds.

### C.4 Word list **[grep]**

| Use | Avoid | Note |
|---|---|---|
| hours, 1h 30m | time entry, entry, log item, activity log | "record" is the year's set |
| rental, your rentals, this place | property (except the tab name and address fields), asset, unit | Tab rename is Brian's call |
| count toward, counts, doesn't count | attribute, eligible, countable, non-countable | |
| your goal, the 750, the 500-hour test, the 100-hour test | material participation, REPS, Test 1/Test 3 | Allowed once on the goal step and in Learn, plain name first |
| your CPA | tax professional, advisor; "accountant" PDF only | |
| confirm, log, not rental work | approve, accept, dismiss, reject, archive | |
| not sure, needs hours, might be logged | low confidence, uncertain, duplicate | Tags, sentence case |
| the record, your PDF | report, audit log, export (noun), evidence | |
| you, your spouse | participant, user, member, household | |
| settings, sign-in, who files | profile, account (except "Apple Account"), tax profile | |
| spot, find, looks like | detect, classify, AI, model, engine | |
| anonymous usage stats | data, telemetry, analytics | |

### C.5 Canonical lines and the 10 worst lines today

Canonical lines are String Catalog keys; a screen that needs the idea uses the key, never a variant **[grep]**:

| Key | Line |
|---|---|
| `common.nothingCountsUntilConfirm` | "Nothing counts until you confirm it." (replaces seven variants found in the code) |
| `common.cpaFootnote` | "Your CPA decides what the numbers mean." |
| `row.action.confirm` | "Confirm" |
| `row.action.notRentalWork` | "Not rental work" (also the swipe label) |
| `row.action.dontSuggestAgain` | "Don't suggest this again" (the mute; replaces "Don't suggest events like this") |
| `row.batch.confirmLikely` | "Confirm %lld likely" |
| `pdf.title` | "Rental hours record %lld" — used by the PDF, the CSV file name and the paywall preview |

The 10 worst live lines, with rewrites that keep their meaning:

| # | Where | Current | Rewrite |
|---|---|---|---|
| 1 | PDF (`AuditReportPDFRenderer.swift:52,127`) and paywall preview | "Rental Activity Time Log: Tax Year 2026" vs "2026 hours record" | `pdf.title` → "Rental hours record 2026" in both |
| 2 | Reports | "Material participation test 1 needs more than 500 hours. You're at the line." | "You're at the line for the 500-hour test, based on your records. Your CPA decides what that means." |
| 3 | Settings, tax section | "Treat all your rentals as one activity for material participation." | "Count all your rentals together." + footnote "Your CPA may call this a grouping election." |
| 4 | PDF/CSV headers | "Hours in REPS-countable activities" / "Hours in investor-level activities (not countable)" | "Hours that count toward 750" / "Investor hours (don't count)" |
| 5 | Goal step | "Counts rental hours you log here. Brokerage and other real-estate work aren't tracked yet. Only your spouse's own hours count." | "Counts the rental hours you log here. Other real-estate work isn't tracked yet." (the spouse rule moves to the spouse toggle: "For the 750, one of you has to get there alone.") |
| 6 | Goal step + Inbox question card | "Change this any time. Reaching a number is based on your records; your CPA decides what it means." | "You can change this later." + `common.cpaFootnote` |
| 7 | Property edit, other names | "The names you use for this place in your calendar, like "the cabin". We use them to match events. Use at least 3 characters. You can add up to 10 other names." | "What you call this place in your calendar, like "the cabin". Up to 10 names, 3 letters or more." |
| 8 | Participation question | "Did anyone else, like a property manager or contractor, spend more time on any of your rentals than you and your spouse this year?" | "Did a manager or contractor put in more hours than you and your spouse this year, at any rental?" |
| 9 | Calendar permission | "LandlordHours can only add events. Allow Full Access in iOS Settings to get suggestions." | "We can add to your calendar but can't read it yet. Allow Full Access in Settings to get suggestions." |
| 10 | Settings privacy toggle | "Share anonymous usage data" | "Share anonymous usage stats" |

---

## D. Brand-doc alignment and stale project rules

Conflicts between this standard and `2.0-brand-system.md`, resolved in the same revision:

| Topic | Brand doc said | Standard says | Resolution |
|---|---|---|---|
| Tool renders | "Category rows, Inbox, the category picker and the milestone share get the tool renders on a plaster tile at 36–48pt", and "unreadable under 28pt" | 36 in browse rows and picker lists, 56 in picker grids and sheet headers, never in decision rows, never under 32 | Standard wins; brand doc §4 updated to the same sentence. |
| Eyebrow / drafting label colour | `draftingInk` on cards (`#2369B5` / `#60A8E6`), drafting cyan on blueprint | r1 said `textSecondary` | `draftingInk` everywhere on canvas and cards; cyan on blueprint; intent ink allowed when the header names a state. r1 corrected. |
| Fraunces | Tab titles 34/500, display 34, never under 28pt | r1 omitted it | §1.14 names it. |

The project `CLAUDE.md` is stale against both documents: it still names radius 12 for cards, Lucide as the primary icon library, violet `#7C6FF7` as `primary`, and DM Serif/DM Sans. Proposed replacement for its "Icon System" and "Corner Radius" sections and the colour header (not applied; Brian's call):

> **Colour.** Blueprint blue `#1E3FA6` is the brand and the light action colour; drafting cyan `#8FD3FF` is the dark action colour. Violet is retired. Tokens and contrast are in `docs/design/2.0-brand-system.md` §2; usage rules are in `docs/design/DESIGN-STANDARD.md`.
> **Type.** SF Pro / SF Pro Rounded (numbers, tabular) / SF Mono (drafting labels, 11pt caps) / Fraunces (tab titles and display, ≥ 28pt only). DM Serif Display and DM Sans are retired.
> **Corner radius.** Cards 20 (continuous), inner surfaces 12, stat tiles 16, tags 6, buttons and chips capsule. Nothing else.
> **Icons.** SF Symbols for everything functional. Brand tool renders (`CategoryToolTile`) at 36 in browse rows and picker lists, 56 in picker grids and sheet headers, never in decision rows, never under 32. No Lucide (package removed), no emoji, no `Image("bp_tool_…")` outside the tile. Tab bar: SF Symbols (`LHIcon` custom shapes retired).
> **Components and density.** `docs/design/DESIGN-STANDARD.md` is the bar; its §5 is the gate rubric.

---

## Appendix: rollout order

1. `Components/`: `LHButton`, `LHTag`, `LHChip`, `LHSectionHeader`, `LHScreenTitle`, `LHRow.Action/.Browse/.Value`, `LHField`, `LHSegmented`, `LHStepper`, `LHEmptyState`, `LHFormat.hours`, the revised `AppAnimation`; `scripts/density_gate.py`, `scripts/copy_gate.py`. **Create `Sources/Resources/Localizable.xcstrings`** with the canonical keys from §C.5 and migrate the view literals into it (today only `Learn.xcstrings` exists; the copy gate greps both catalogs, and a string that is not in a catalog is a gate fail).
2. Today (as a `List` root) + Inbox rows on `LHRow.Action`, one lane. Frames default/XXL/AX3, light/dark; density numbers in the hand-off; visual gate with the anchor question; Brian's eye on the first frame before polish rounds.
3. Log time, Properties, Suggestion confirm sheet, Onboarding, Paywall.
4. Delete the dead screens, Lucide, the custom swipe.
5. Copy pass from §C.5, `pdf.title` first.

Independent assessment required before Brian decides: `visual-gate` on the §3 row rendered as SwiftUI frames beside the Reminders and Copilot anchors; a copy assessor as the named persona on §C; and a fresh-context read of this r2.
