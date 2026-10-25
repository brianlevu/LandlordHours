# LandlordHours Design Standard

**v2, 2026-10-24.** Status: the system Brian locked ("the crafted house"); every screen is redone against it in one pass (`docs/design/v2-revamp-plan.md`; plain-English summary in `docs/design/v2-summary.md`). v1 (draft r2, 2026-10-23) covered components, density, motion, voice and adaptive layout; most of it stands. v2 adds **§H The crafted object** and **§F Future extensions**, and amends the rules listed in the changelog. **v2 r2 (same day)** applies every fix from the fresh-context review (`~/AgentScratch/landlordhours/2026-10-24/v2-review/review.md`, verdict READY AFTER FIXES); the review response table is below the changelog. The hero rules were measured on the CRAFT reference frames, not on production code.

## Changelog: v1 → v2

Brian's locked decisions (2026-10-24): the house is the hero (a rendered diorama on Today at ~44% of the screen, ~28% at AX, never in a card); dusk in light, night in dark, one key light, a cool rim and warm interior light; windows show state (lit when hours were logged today; a work lamp on the framing stages); the motion signature is the timber drop then the windows; a native iOS 27 tab bar with "+" as a native fifth "Log time" item; new tokens `behind`, `positiveOnPage`, `pageCardEdge`, the dusk page gradient and the spill pool; the blueprint-grid canvas, tape measure, stamp, kraft and vellum dropped; Porch Light and The Record dropped; minimum OS iOS 18.

| # | Rule | v1 said | v2 says | Where |
|---|---|---|---|---|
| 1 | Hero container | the blueprint hero is a card ≤ 320pt (§1.10 exception) | the house sits on the page, never in a card; frame 390 (44.6%) at default, 295 (art 24–32%) at AX | §H.1, §1.10 |
| 2 | D3c | hero switches to a compact variant, **art hidden**, ≤ 160pt at AX | the art holds at 28% and the page scrolls beneath; nothing is hidden | §2 D3c, §H.1 H3 |
| 3 | D3b | title + hero + section header + ≥ 2 rows + "This week" header above the fold | chip + hero + number + pace + "To confirm" + 2 rows + foot; pace tiles leave Today | §2 D3b, §H.8 |
| 4 | D6 | hero incl. header ≤ 40% of viewport | the hero is not a card; D6 applies to cards only; the hero is measured by H2/H3 | §2 D6 |
| 5 | Rental switcher | a row of small houses inside the hero card | a quiet `Menu` chip above the hero, page dots, swipe on the house | §1.10, §H.8 |
| 6 | Hero number | 56/700 SF Rounded | Fraunces 84/600 opsz 144 (54 at AX); the one numeral in Fraunces | §1.14 |
| 7 | Section header on hero screens | SF Mono 11 caps drafting label | `.headline` sentence case with the count ("To confirm · 7"); the drafting label stays only in the PDF and Reports eyebrows | §1.15 |
| 8 | Create action | detached glass "+" beside the bar; "Log time is not a tab" | native fifth tab "Log time", `plus`, `role: .search`, restores the previous tab | §1.25, §H.7 |
| 9 | Canvas | one canvas `#EEF2FA` / `#0B1230`; the blueprint grid on hero surfaces | hero screens take the dusk/night page gradient; lists and forms keep the plain canvas; the grid, tape measure, stamp, kraft and vellum are retired | §H.4 |
| 10 | Text on the page | — | only `textPrimary`, `textSecondary`, `action`, `behind`, `positiveOnPage` may be text on the light page (measured: every other ink < 4.5:1 on `#D8CFC0`) | §H.4 |
| 11 | Card on the page | hairline in dark only | 1pt `pageCardEdge` on hero screens (a card is 1.3–1.5:1 on the page) | §H.4 |
| 12 | Toast | 12pt above the tab bar everywhere | on hero screens a glass capsule at the top that replaces the rental chip while it shows, announced to VoiceOver; elsewhere unchanged | §1.19 |
| 13 | Signature motion | `buildStep`: the new band builds in the framing style ≤ 0.60 | `timberDrop` (2.0 s pre-rendered clip, the one motion over 0.60 s) then `windowsOn` 0.40; `stageFade` 0.25 for other stage changes; `rentalSlide` 0.30; the milestone adds one confetti beat, no sign | §B.1, §B.2, §B.3, §H.6 |
| 14 | Ambient scenes | sky follows the time of day; van, guest car, person scenes | sky retired (the appearance is the clock); scenes become §F.2's ambient layer with z-layers, regions, caps and a rendering contract; not built in v2 | §B.4 → §F.2 |
| 15 | Dynamic Type clamps | ≤ 2 sites | 3 sites: numeral, art frame, rental chip | §2, §H.1 H9 |
| 16 | Empty Inbox | blueprint art ≤ 40% | the diorama of the first rental, frame ≤ 240 (≤ 28%), on the page | §1.18, §H.5 |
| 17 | Paywall | blueprint band ≤ 40% with the record preview | the record preview on the plain canvas; no house, no blueprint band | §1.23 |
| 18 | Welcome | theme-fixed blueprint blue | the dusk/night page with the finished house lit, follows the appearance | §1.24, §H.5 |
| 19 | Properties row ornament | house tile at 36 | house-only thumbnail at 44, lit state by `loggedToday` | §1.4, §H.5 |
| 20 | §A "Quietly crafted" | blueprint grid, mono eyebrows, the brass sign | the lit house, one drop, the windows; no mascots, no idle motion, no load-in choreography (unchanged) | §A |
| 21 | Batch confirm on Today | foot "Confirm N likely" or a pinned bar | Today shows ≤ 2 rows and a "See all N" foot; batch confirm lives in Inbox | §1.3 |
| 22 | Brand doc | — | conflicts listed in §D for the same-revision update of `2.0-brand-system.md` | §D |
| 23 | Future features | — | §F: per-rental house customisation and the ambient layer, designed for and not built | §F |
| 24 | Tool changes | — | specified, not coded: `scripts/qa/NOTES-standard-v2.md` | §5 |
| 25 | Adaptive layout (2026-10-24) | bands A/B/C, iPad sidebar, `NavigationSplitView`, `Table`, `.inspector`; Duo open one column | **one model:** compact (one column) below 800×645pt, two-pane at 800×645 and up or with the Duo held open (house left, workstation right, the same on iPad and the Duo), stacked when the Duo is propped; no sidebar; the bar at the right pane's foot; AD1–AD17 list each change | §1.27 |
| 26 | Duo unfold | no custom transition on fold | `duoUnfold`: the door swings and the right pane lights from the fold, ≤ 0.80 s, on a hinge event only; token `duoDoor`; new colour `duoNightCardEdge` #3C4675 | §1.27, §B.2, §B.3 |
| 27 | "All rentals" number | the sum against the largest goal | "N hours across M rentals" and "N of M behind" in every mode, never a goal (**decided 2026-10-24**) | §H.1 H10 |

### Review response (v2 r2, 2026-10-24)

Each finding of the fresh-context review and what r2 did. "Plan" is `v2-revamp-plan.md`, "Notes" is `scripts/qa/NOTES-standard-v2.md`.

| # | Finding | What r2 did | Where |
|---|---|---|---|
| R1 | `int/2.1` lacks `main`, the standard, the QA tools and the CRAFT code and art | Plan step 0: build `int/2.1-v2` from `int/2.1`, merge `origin/design/standard-v2` (carries `main`), `origin/proto/dir-craft`, and `origin/chore/qa-v2-tools` if pushed by then; expected conflicts named. The orchestrator merges. | Plan §0 |
| R2 | Packages not file-disjoint (`BlueprintList`, `CategoryToolTile`, `InboxBlueprintPaper`, the toast, `ProfileManagementViews`) | New package **0 Shared components**, built first in the same lane as A; the others consume and never edit. `ProfileManagementViews` is used by Onboarding (B) and Settings (H), not by rentals, so it goes to 0, not F as the review suggested. | Plan §4 |
| R3 | Unowned files; `HouseProgress` vs `CraftStage` | Every file in `Sources/Views/` on `origin/int/2.1` has one owner, checked against `git ls-tree`; the unowned ones are listed with their new owner. Stage logic goes to 0: `CraftStage.stage(hours:goal:)` is the one function and `HouseProgress` forwards to it. | Plan §4, §H.3 |
| R4 | Launch screen missing; flashes blueprint blue before a dusk Welcome | Added (plan row 0, package B): launch colour = `pageTop` per appearance, mark B in ink; never `#1E3FA6`. | §H.5, Plan §2 |
| R5 | "Check my goal" is not on `int/2.1` | Marked future: it lives on `origin/feat/home-2.1` (`Sources/Views/GoalCheck/`), not merged; DEBUG mocks on `proto/dir-craft`. Removed from the §H.5 citations; §1.27 mentions marked "when it lands". | §H.5, §1.27 |
| R6 | §1.15 allows `caution` on hero pages; §H.4 bans it | One rule: on the page, state headers use `behind`/`positiveOnPage` only; `caution` only inside a card or on the plain canvas. | §1.15, §H.4 |
| R7 | Mono eyebrows still in §1.10, §1.14 and §D row 2 | Deleted from the Summary card and sheet titles; kept only in the PDF and the Reports eyebrow; §D row 2 struck; §1.2 and §1.15a aligned. | §1.2, §1.10, §1.14, §1.15a, §D |
| R8 | "Log time" drawn detached on iOS 26+, but the locked frame shows it inside the bar | Described as the fifth item inside the bar; captures on iOS 18, 26 and 27 required; explicit `accessibilityLabel("Log time")` because `role: .search` may announce "Search". | §1.25, §H.7 |
| R9 | "Text over glass" names the blueprint hero and a glass action | Busiest backdrop is now the diorama under the bar; every "glass action" / "glass +" reference replaced by the fifth tab. | §1.25, §1.27, §4, §5.2 |
| R10 | `houseStageAdvance` keeps linework and a brass sign | Rewritten: the stage change (`timberDrop` or `stageFade`), then `windowsOn`, then one confetti beat in the house palette; no sign, no words, no linework. Plan row 13 fixed. | §B.3, Plan §2 |
| R11 | `rentalSlide` 0.45 s breaks the 0.30 spring cap | 0.30 s; removed from the signature-token list. | §B.1, §B.2, §H.6 |
| R12 | "≤ 3 lights" does not match `craft3.py` | Replaced with the rig's actual light list per stage and appearance (from `setup_lights` and `apply_state` on `proto/dir-craft`), including the night framing moon rim. | §H.2 |
| R13 | `craft3.py --list-objects` does not exist | Specified as a flag to build (Notes §11); marked "to build" in §H.2. | §H.2, Notes §11 |
| R14 | §F.1 masks "rendered but unused" vs asset_check FAIL; trim swatch hex | Masks live in `design/` only, never in the bundle, until §F.1 is built; trim named `#A98666`. | §F.1 |
| R15 | Undefined: "All" hero, two-stage jumps, D3b on SE | "All rentals" hero defined (H10); jump rule in §H.6; D3b at `H < 700` is 1 row. | §H.1, §H.6, §2, §H.8 |
| R16 | Ground-line check breaks on scaled, lifted early stages | Ground line is an asset check only; on screen the frame side is derived from the art's width and the stage scale. | §H.1, §5.1, Notes §1, §3 |
| R17 | Art share counts the night backlight and spill pool | Art share comes from the still's alpha at the known placement; the glow and pool are excluded. | §H.1 H2, Notes §1 |
| R18 | p99 is a highlight proxy; night bar has no margin; 2.51/2.48 vs 2.40 | p99 called a proxy; mean-luma lift added; stated margin: PASS ≥ 2.55, MARGINAL 2.40–2.55, BLOCKED < 2.40; art target ≥ 2.8. Today half and finished are MARGINAL. | §H.2, Notes §3 |
| R19 | AX3: the 54pt numeral reads smaller than "of 100 hours" | Routed to the visual gate as an open finding; not changed here. | Rubric §6, Plan §5 |
| R20 | §F.1 "starting set, all checked" is false; recolouring unproven | Relabelled "proposed, unchecked"; a required spike (neutral render, mask pass, 6-swatch check against the locked art) comes before any customisation build. | §F.1, Plan §6 |
| R21 | §F.2 fractions assume a 390 frame; van vs guest car | Keep-outs in points from the number block, chip and dots, at every hero size (SE 297, Duo 287); street band holds one occupant at a time. | §F.2, §B.4 |
| R22 | Owner summary: jargon, two wrong lines, three missing risks | Rewritten in plain words, every sentence ≤ 20 words; the two lines fixed; the asset budget, night readability and untested colours added. | `v2-summary.md` |
| R23 | Open questions 1, 4, 5 need follow-ups | Tab name written as "Rentals" everywhere; a light-mode tab-switch capture added to the gate; the hero toast replaces the chip while it shows and is announced. | §1.19, §1.25, §H.4, §H.7, Rubric §6 |

Kept from v1 without change: component grammar §1.1–1.9, 1.11–1.13, 1.16, 1.17, 1.20–1.22, 1.26; density D1, D2, D4, D5, D7–D10; the voice rules §C in full; the adaptive layout §1.27 (rewritten 2026-10-24 as one model: compact, two-pane, stacked); the gate rubric §5 (hero measures added).

Why this exists. Brian, on the Today "To confirm" card: "These card designs also waste too much space. I feel like we don't have a standard and bar for the design system and harness, which results in some amateur design like this." CLAUDE.md holds tokens, the brand doc holds the blueprint world, and nothing says how a row, a card, a button or a sentence is built, or how dense a screen must be. Each screen was composed alone, which is why the app has four tinted-capsule button styles, three primary pill styles, six hand-built close buttons and two hours steppers (§4).

Platform: iOS 18.0 minimum for 2.1 (§1.25); Liquid Glass on iOS 26+ behind `#available`, system materials below it.

Every rule here is one of three kinds, and says which: **[measured]** a number a script or PIL checks; **[grep]** a pattern a code search checks; **[judgment]** a call the independent reviewer makes in writing. Nothing else counts as a rule.

Evidence: `docs/design/2.0-brand-system.md`; code at `/Users/brian/tmp/lh-release2/Sources/Views`; frames under `~/AgentScratch/landlordhours/2026-10-2*/`; Mobbin anchors: [Copilot "To review"](https://mobbin.com/screens/39e851c1-7c5d-4f1e-bf81-1c3be05e5566) (rows ≈36pt, no per-row buttons, batch action at the foot), [Apple Reminders](https://mobbin.com/screens/4fcb0751-165a-429f-a395-defd9b2d9de3) (22pt leading control, swipes, meta line), [Things 3](https://mobbin.com/screens/5bc4a73d-af7d-4e63-aca2-27d13a2b1ed1), [Apple Fitness Summary](https://mobbin.com/screens/2745a5a7-c443-46cf-80bb-a3e7b72ff8f7), Apple Settings (forms).

---

## H. The crafted object

Brian's pick, 2026-10-24, after the taste board (`~/AgentScratch/landlordhours/2026-10-24/taste-board/`): the "crafted object" cluster, anchored on [Opal](https://mobbin.com/screens/1b3deee1-a193-4e36-93b0-7e89740f9c5c) (a lit gem on a plinth in a dark cave), [(Not Boring) Weather](https://mobbin.com/screens/fd38c9a5-7d60-491b-8b41-d710c27b9ac5) (the data is the sculpted object) and [Tolan](https://mobbin.com/screens/36a924c2-a748-43f5-bfd1-bc5861191977) (a lit place you visit). Direction CRAFT (`proto/dir-craft`, `Sources/Views/Debug/DirCraft/DirCraftToday.swift`) is the reference implementation; its frames (`dir-craft-final2/frames`, 21 frames, regate PASS 2026-10-24 08:20 with two FAILs fixed since) are the acceptance reference for the rules below. Every number here was measured on those frames or in the render pipeline (`dir-craft3/README.md`, `dir-craft2/verdict.md`).

What it means in one line: **the house is a small lit object the user keeps, placed on a page that has a time of day. Nothing else on the screen competes with it.**

### H.1 The hero: sizes and placement

The house is a rendered 3D diorama (one Blender rig, `design/blueprint-house/scripts/craft3.py`) shown directly on the page. It is the only picture on Today. It never sits inside a card, a rounded rectangle or a tinted band **[grep]** (no `.background(…, in: RoundedRectangle…)`, `.clipShape`, `LHCard` or `.propertyCard()` around `CraftHouseView`; the frame is `.clipped()` to a plain square only) **[measured]** (no closed rectangle of edge pixels around the art; the page gradient runs under and around it).

| Rule | Spec | Kind |
|---|---|---|
| H1 hero frame, band A, default to XXL | A square frame, side `min(W − 12, round(0.446 × H))` where `W` and `H` are the window size. 402×874 → **390pt (44.6%)**. 393×852 → 380. 375×667 (SE class) → 297. Content inside is the 1206² still scaled to fit, then scaled about its bottom centre and lifted per stage (table below). In the **asset** the lot's ground line sits at 92% of the still; on screen it moves with the stage scale and lift, so the ground line is checked on assets only (§H.3). **On a frame, the side is derived from the art's horizontal extent:** `side = lot_width / (0.96 × stage_scale)` (H5), where `lot_width` is the widest row of the still's opaque pixels as placed. | measured |
| Stage placement | `started` scale 1.18, lift 30pt · `frame70` 1.08, 12pt · `framing`, `half`, `complete` 1.0, 0 · lifts are at a 390 frame and scale with `side / 390`; the scaled art is clipped to the frame (`CraftHouseView.stageScale`/`stageLift`, from `DirCraftToday.swift` on `proto/dir-craft`). | grep: one table |
| H2 house art share, default | Art bounding box **36–46% of the window height**. The box is the still's alpha bbox (alpha ≥ 0.5) mapped through the known placement (frame origin and side, stage scale, lift), never a count of non-page pixels: that count includes the night backlight (0.88 × side) and the spill pool, which are page layers, not art. Measured on the reference frames: 37% (just started, scaled 1.18 about the ground line, lifted 30pt), 40% (frame70, 1.08, +12pt), 42% (half, finished). Early stages are scaled and lifted so the frame never shows dead space under the rental chip. | measured |
| H3 hero at AX1–AX5 | The frame holds at **295pt** on a 402 window (`round(0.337 × H)`, same clamp to `W − 12`), the art is **24–32%** of the window height (measured 31.6% light, 27.1% dark at AX3), the numerals cap at **54pt**, the rental chip moves above the frame, the pace sentence stays above the tab bar, and the rows scroll beneath. The art is never hidden. This amends D3c. | measured |
| H4 position | Frame top ≤ 110pt from the window top at default (status bar 54 + chip 36 + gaps); the number block overlaps the frame bottom by 44pt (the number sits in the diorama's shadow, as a score under a gem); at AX the overlap is 0. | measured |
| H5 width | The lot fills 96% of the frame width (the spill ellipse); the house footprint is about 60% of the frame width at `craft_complete`. | measured on the stills |
| H6 compact wide and two-pane (§1.27, rewritten 2026-10-25) | **Compact with `W ≥ 600`:** frame side **`min(390, H1)`**, where H1 is §H.1 H1's height formula, centred in the ≤ 600 column (iPad mini portrait 1133 tall → 390; a 1000×600 Stage Manager window → `min(390, 268)` = 268). **Floor 220:** when H1 gives less than 220 (short windows, an iPhone held sideways at 402 or 440 tall), the hero holds at **220**, the numeral at 64, and the rows scroll beneath it as at AX (§H.1 H3); the diorama is never drawn under 220 in any compact window except the closed Duo (287) and SE (297), which are above it anyway. **Two-pane:** the hero sits in the left (house) pane at `clamp(round(0.626 × pane), 290, 390)`, never above 0.45 × the window height (Duo open 290; iPad 10th gen portrait 290, landscape 362; 13" 390); the number block below it, then the shelf. No sidebar header (retired with the sidebar). | measured |
| H7 iPhone Duo | Closed, outer display (app area 382×644): side `min(370, 287)` = **287**; numerals cap at **64pt** whenever `H < 700` (compact mode). Held open (951×669): two-pane, side **290**, numeral 76. Propped (669×951): stacked, side **220** beside the number, numeral 60. The frame never straddles the fold (`reservedRegions(kind: .division)`). Supersedes "inner display one column, side 390" (2026-10-24). | measured (closed on the Duo simulator; open and propped from off-screen @3x renders, `duo-concept-v6`) |
| H8 hysteresis | The side is recomputed only when the mode or band changes (§1.27's 8pt hysteresis) or the window height changes by ≥ 40pt; never per pixel during a resize. | grep |
| H9 clamps | `.dynamicTypeSize(` is allowed at exactly three sites: the hero numeral (cap 54 at AX), the house art frame, the rental chip (`…accessibility2`). The §2 clamp rule moves from 2 sites to 3. | grep |
| H10 "All rentals" (rewritten 2026-10-25; one rule, every mode) | **No single house, no stage and no goal for "All rentals".** The hero is the **skyline**: each rental's own house-only render (`LHThumb(stage:lit:size:)`, §H.5) at **its own** `CraftStage.stage(hours:goal:)` and its own lit state (`loggedToday`), standing in one row on one shared ground line inside the hero frame. **The skyline ignores `stageScale` and `stageLift`** (1.18 and 30pt for `started`, §H.1 stage placement): every house is bottom-aligned to the shared ground line at its computed side, so an early stage reads smaller only by its own art. **Art fallback:** no `craft_thumb_*` assets exist on `int/2.1-v2` yet, so until they land `LHThumb` crops the lit still to the house's bounding box and shows unlit by dimming that crop; the skyline uses whatever `LHThumb` draws and never its own crop. The page's spill pool and one shared contact shadow sit under the row, with the page's spill pool and one shared contact shadow. Order = the shelf's order. House side = `min(0.42 × S, (0.92 × S − 0.04 × S × (n − 1)) / n)` for frame side `S`; houses are never under 44pt. **Cap: 5 houses when `S ≥ 290`, 4 when `S < 290`** (stacked 220 → 4 at 44.0pt each; closed Duo 287 → 4; at 290 with 5 each is 44.1pt). Over the cap (for example 8 rentals), the skyline shows the most-behind rentals first (largest gap to their own pace, ties by shelf order) up to the cap, and nothing in the art counts the rest (no "+3", no words in the scene, §H.2); the number line already says "across 8 rentals" and the shelf shows all 8. The number block (`HouseNumberBlock`, shared) reads "312 hours across 3 rentals · 3 of 3 behind" (or "· All on pace"), then "Tap a house to see its pace." Motion: no `timberDrop` or `houseStageAdvance` on the skyline; a mini house whose rental changes stage takes `stageFade`, and its windows take `windowsOn`. `duoUnfold` on "All rentals" plays the pane light only. It is the first page dot and the first shelf slot. | grep, runnable: `standard_lint.py` rule `allRentalsNoAggregate` fails on any `reduce` whose closure reads `.goal`, and on any `CraftStage.stage(` call whose `hours:` argument is a `reduce`/`sum` or a property named `total*`/`all*`, in `Sources/Views/` and `Sources/ViewModels/` |

### H.2 Art direction: the lighting rig, the palette, the kitsch list

One rig, two exposures. Light appearance is **dusk**; dark appearance is **night**. There is no noon render and no moon **key** light (the night framing stages carry a moon **rim**, listed below). The appearance is the clock: a user with automatic Dark Mode at sunset gets dusk by day and night after dark for free, with no clock logic in the app.

| Rule | Spec | Kind |
|---|---|---|
| Key light | Dusk: one low sun, ~3000K, behind-right of the house, sun disc clipped from the sky HDRI (it was a hidden second key). Night: no sun; sky fill at 5–8% in cool `#4A5A8A`; **one** low rim in drafting cyan `#8FD3FF` from the dusk sun's direction, kissing ridge, chimney and gutter beads. | judgment |
| The rig's lights, as shipped | From `craft3.py` `setup_lights` and `apply_state` (`proto/dir-craft` cdfeec5). **Every state:** the sky world fill (tinted `#A3ADC4` dusk, `#4A5A8A` night) and a shadow catcher. **Dusk:** `dusk_sun` (key, model only) and a `rim` sun at strength 0 (present, off). **Night:** `rim` sun 1.5, model only. **Night, framing stages (`started`, `frame70`, `framing`), lit and unlit:** plus `moon_rim`, one drafting-cyan sun at 4.0 from back-left, model only (`--moon-frame 4.0`, bcebadd; it lifted unlit night framing from p99 1.28 to ~3.3). **Lit only:** framing stages: `work_lamp` (area, model) + `work_lamp_lawn` (its lawn-only twin); `half`: two interior point lamps, one per storey; `complete`: one area spill lamp per ground-floor window and door glass (lawn only), `porch_light` (model) + `porch_spill` (lawn only). **Emission:** window glass (camera-only) and the work-lamp lens. **Unlit:** no interior, spill, porch or work lamp. Nothing else may emit or light the scene; a new light is a standard change, not an art tweak. | judgment, checked against this list (by reading `craft3.py` until `--list-objects` exists, Notes §11) |
| Interior light | Window glass glows to the camera only (emission); the light that reaches the lawn comes from one aimed area lamp per lit ground-floor window plus the porch bulb, light-linked to the lawn. The porch bulb sits low behind the railing so the balusters throw long shadows across the grass. | judgment |
| Windows show state | Base asset = **lit** (hours logged today on the shown rental, or on any rental for "All"). `-unlit` twin = dark glass, no interior light, no porch light. Same sky and rim. On the framing stages (no windows) a small tripod **work lamp on the slab** plays the lit role and fans stud shadows across the front-left lawn. "Someone worked here today" reads the same from the first stud to the finished house. | grep: `TodayWindowState.loggedToday(entries:rentalIDs:)` is the one source |
| Palette | Warm family: cream siding, pine framing, trim in timber one shade darker than the framing (ochre retired). Cool family: sage lawn and leaves, near-black loam, one muted clay band. Accent: the terracotta roof; brick pulled into the same family. Door: greyed blueprint `#3A4A6E`. Gutters and porch roof: warm greys. ≤ 6 material families counted by hand. | judgment + count |
| Night values | Shadow-side siding V ≤ 0.28 (measured 0.27). Unlit lawn V ≤ 0.12 and S ≤ 0.45 (0.09 / 0.32). Spill pool on the lawn: hue 35–50°, S 0.50–0.70, V 0.33–0.45 (47–49° / 0.60–0.66 / 0.33–0.44). Night unlit grass S ≤ dusk grass S. | measured, `measure3.py` probes |
| Dusk values | Lawn S ≈ 0.35 (0.35), hue 76–95° (76). Saturated pixel share (S ≥ 0.25) ≤ 40% light (36%), ≤ 28% dark (25%); mean S ≤ 0.52 (0.50). | measured |
| Readability on the page | Two numbers, both in the house box. **p99 contrast** (relative luminance of the 99th-percentile art pixel vs the page) is a **proxy**: it measures the brightest highlight, not the silhouette. **Mean-luma lift** (house mean minus page mean, 0–255) measures the silhouette. Lit, and framing stages with the lamp: p99 **≥ 3.0:1** and lift ≥ +5. Unlit at night, with a stated margin: p99 **PASS ≥ 2.55**, **MARGINAL 2.40–2.55** (goes to Brian with the frame), **BLOCKED < 2.40**, and lift ≥ +5. The 0.15 margin is the spread two tools gave on the same art (gate 2.51 vs the final2 self-check 2.40). Measured 2026-10-24 (`qa/gate-log.jsonl`, `dir-craft-final2/README.md`): unlit night framing 3.09–3.89 (about 3.3, PASS); half 2.51 and finished 2.48 (MARGINAL); lift +6.9 to +15.5. **Art target for the sculpt pass: unlit night half and finished ≥ 2.8.** | measured, `frame_check.py` hero probe (Notes §3) |
| The 400px read | Every one of the 20 stills (5 stages × lit/unlit × dusk/night) is identified by a fresh reviewer at a 400px thumbnail: stage and lit state both named correctly. | judgment, written |
| Materials | Roughness ≥ 0.45 on every opaque material (no toy gloss); glass is the only specular surface. Grain, tiles, gutters, downpipes and porch stay. CAD-clean boxes are a known gap: a sculpt pass (chamfers, ridge sag) is owed and does not change any rule here. | judgment |
| Forbidden kitsch | Flower boxes, blooms, planters, pebbles in the soil cut, lanterns, a second chimney pot, garden ornaments, pets, string lights, seasonal decoration, snow, weather, smoke, sway, flags, mailboxes, signage with words, cartoon outlines, exaggerated proportions. One chimney, one tree, two shrubs at most. | grep on the scene object list + judgment. The list comes from `craft3.py --list-objects`, a flag **to build** (Notes §11; it does not exist yet). Until then the gate reads the object names in `craft2.py`/`craft3.py` by hand. |
| Cost | A still ≤ 25s at 128 spp and an animation frame ≤ 20s at 64 spp on the Mini; the full set (20 stills + 120 frames) regenerates in ≤ 60 min. | measured |

### H.3 Asset contract

Stage thresholds are a share of the rental's chosen goal (100, 500 or 750): `started` < 0.20 · `frame70` < 0.47 · `framing` < 0.60 · `half` < 1.0 · `complete` ≥ 1.0 **[grep: one function, `CraftStage.stage(hours:goal:)`]**. The v1 `Services/House/HouseProgress.swift` stage logic (used by Today, Onboarding, Reports, the widget and `TodayHouse`) forwards to it, so there is one answer for "what stage is this rental"; the forwarder is deleted when its last caller moves (plan package 0). Hours crossing 100 / 500 / 750 still play `houseStageAdvance` (§B.3); the stage art is what the house shows between milestones.

| Asset | Name | Files | Notes |
|---|---|---|---|
| Stills, lit | `craft_started`, `craft_frame70`, `craft_framing`, `craft_half`, `craft_complete` | one imageset each, **Any** = dusk, **Dark** = night, universal, 3x only | Swift: `Image(stage.rawValue + (loggedToday ? "" : "-unlit"))` |
| Stills, unlit | `<stage>-unlit` × 5 | same layout | a missing twin falls back to the lit asset and is a gate FAIL |
| Build clip | `craft_build_light.mov`, `craft_build_dark.mov` in `Sources/Resources/Craft/` | HEVC with alpha, 60 frames at 30 fps (2.0 s), frame70 → framing, work lamp on | no `-unlit` clip: the drop always follows a log, so it is always lit. First frame = `craft_frame70` + lamp; last frame = `craft_framing` within mean ΔE 2 |
| Thumbnail | `craft_thumb_<stage>` × 5 | **house only** (camera framed at 90% of the house bounding box, no lot, contact shadow only), Any/Dark, 2x + 3x at 120pt (240 / 360px) | lit only; used at 44, 56 and 120pt (H.5) |
| Source | 1206×1206 RGBA PNG renders in `design/blueprint-house/renders/` | not in the app bundle | regenerate with `craft3.py`, `craft3_post.py`; "pass 3" in `design/blueprint-house/README.md` |

Formats and budget **[measured by `scripts/qa/asset_check.py`, spec in `scripts/qa/NOTES-standard-v2.md`]**: the catalog ships **HEIC (HEIF with alpha)** at 3x only, quality 0.85, ≤ **450 KB** per still, ≤ **10 MB** for the 20 stills; clips ≤ **1.5 MB** each; thumbnails ≤ **40 KB** each; the whole hero set ≤ **14 MB**. Today the proto carries 18.0 MB of PNG stills plus 2.2 MB of clips, which is over budget: the HEIC pass is a merge condition. If a target OS fails to decode alpha HEIC in the build test, the fallback is lossless-optimised PNG at 3x only (never palette PNG; the gradients band).

Integrity checks **[measured]**: every imageset has Any + Dark; every stage has lit + unlit; `sha256(lit) ≠ sha256(unlit)` and `sha256(Any) ≠ sha256(Dark)` for every stage; the camera is pinned (ground line at 92% ± 1% of the frame; house bbox left and right edges within ± 4px across stages and states); alpha edges are clean (no dark fringe: edge-pixel luminance within 10% of the adjacent opaque pixels). Naming for future styles and material variants is reserved in §F.1 and must not be used before that section is built.

### H.4 Page treatment: dusk, night, the pool

The page under a hero is a vertical gradient, never flat, never a drawn grid.

| Token | Light (dusk) | Dark (night) | Where |
|---|---|---|---|
| `pageTop` | `#EAE3D7` at 0 | `#0B1230` at 0 | `BrandHex.duskTop` / `darkNightTop` |
| `pageMid` | `#D8CFC0` at 0.32 (behind the hero) | `#0B1230` at 0.32 | `duskMid` |
| `pageBottom` | `#E8E0D3` at 1.0 | `#080C1D` at 1.0 | `duskBottom` / `darkNightBottom` |
| `spillPool` | `#E9A558` at 0.34 | `#E9A558` at 0.12 | radial ellipse 0.96 × 0.33 of the frame, centred at y = 0.345 × side; opacity × 0.2 when unlit; fades with the windows (0.4 s) |
| `backlight` (night only) | none | `#5E86D6` 0.50 → 0 inside 0.88 × side, plus a rim ellipse 0.34 → 0 | so the silhouette reads against the page |
| contact shadow | black 0.30 | black 0.55 | 0.80 × 0.07 of the frame, blur 0.035 × side |
| `pageCardEdge` | `#A3966F` 1pt | `#2A3560` 1pt | the grouped container's edge on the page (a white card is 1.31:1 on `pageBottom`, 1.54 on `pageMid`; the edge reads at 2.2 / 1.9) |
| `behind` | `#9A3624` | `#F08A70` | "Behind by 14h." 5.03:1 at the pace row (4.65 on `pageMid`), 7.73 dark |
| `positiveOnPage` | `#0C5A30` | `#4ED48A` | "On pace." / "Done for 2026." 5.84 light, 10.01 dark; the standard `positive` is 3.50 on `pageMid` and is not used as text on the page |

**Which inks may be text on the page [measured]:** on the light gradient only `textPrimary` (11.1:1 on `pageMid`), `textSecondary` (5.2), `action` (5.9), `behind` (4.65) and `positiveOnPage` (5.4) clear 4.5:1. `textTertiary` (3.55), `positive` (3.50), `caution` (3.67), `destructive` (3.63), `informational` (3.90), `draftingInk` (3.62) and `rose` (3.56) do not, so they appear only inside a card on the page, never on the gradient. Dark is unconstrained (every dark ink ≥ 5.2:1 on the night page). The gate samples every text pair on hero frames against the gradient step behind it.

**Which screens get the page:** Today, the rental page, Welcome, the Inbox empty state and the milestone (H.5). **Every other screen keeps the plain `background` canvas (`#EEF2FA` / `#0B1230`)**, because the intent inks fail on the warm page and lists need all of them. Two canvases in one app is deliberate: the hero screens are rooms with a time of day; lists and forms are paper. The dark canvas and the night page share `#0B1230`, so dark mode reads as one world; in light the handoff is the push or sheet transition, never a visible seam inside one screen **[judgment]**. A tab switch (Today → Inbox) has no push, so in light the warm-to-cool jump is visible: every hand-off that touches a hero screen includes a **light-mode tab-switch capture** (Today → Inbox → Today, 30 fps), and the gate judges it in writing. A warm-neutral canvas for lists is logged as a test to run against the intent inks (plan §5), not adopted.

**State headers on the page:** a header or line on the gradient that names a state uses `behind` or `positiveOnPage` only. `caution` (3.67:1) never sits on the page; it appears only inside a card on the page or on the plain canvas. §1.15 says the same.

The Job Site blueprint-grid canvas, the tape measure, the stamp, kraft and vellum are retired **[grep: no `BlueprintGrid`, `InboxBlueprintPaper`, `TapeMeasure`, `StampView`, `kraft`, `vellum` in `Sources/`]**. Directions "Porch Light" and "The Record" are dropped entirely.

### H.5 Where the house appears

| Screen | Treatment | Size | Reason |
|---|---|---|---|
| **Today** | the hero (H.1) | H1–H3 | The one place the house is the subject. |
| **Rental page** (Properties detail) | the hero at the **medium** size: frame `min(W − 12, round(0.343 × H))` = **300** on 402×874, art 28–34%; AX frame 220, art 20–26%; number block below, same rules | 300 / 220 | The rental is the thing the user owns; §F.1 customisation lands here, so the user must see "their" house full size with its name as the title. One size smaller than Today so the tab root stays the biggest. |
| **Properties list** (All rentals, `LHRow.Browse`) | house-only thumbnail, lit state by `loggedToday` | **44** in a 56–64 row (min) | One ornament per row (§1.4); replaces the 36 house tile and the 40 seal. Identity, not stage: the row's meta line says the stage in words. |
| **Launch screen** (`LaunchScreen.storyboard`, then `LaunchHandoffView`) | no house; mark B at 112pt in `textPrimary` per appearance, on a named colour that is `pageTop` (`#EAE3D7` light, `#0B1230` dark) with Any and Dark entries | — | The first frame of the conversion path. Today's `LaunchBlueprint` (`#1E3FA6` in both appearances) flashes blueprint blue before a dusk Welcome; it is retired **[grep: no `LaunchBlueprint`; the launch colour set has a Dark entry]**. `LaunchHandoffView` repeats the launch frame exactly, then crossfades (`reveal`) into Welcome or the restored tab **[measured: launch, handoff and first screen frames in light and dark; no frame whose mean colour is ΔE > 20 from `pageTop`/the canvas]**. |
| **Welcome** (onboarding) | the hero, `craft_complete`, lit, on the dusk/night page | H1 (AX: H3) | The conversion path sells the object. "This is what the year builds." |
| **Onboarding, add-a-rental step** | thumbnail of `craft_started`, lit, beside the name field | **120** | "Every hour you log starts with a place." One picture, no hero, so the step stays quick. |
| **Other onboarding steps** | none | | Questions, not pictures. |
| **Inbox, empty** | the diorama of the first rental (unlit if nothing today) as the empty-state picture, on the page | frame ≤ **240** (≤ 28% of height), one headline, one line, one `.primary` | The world is the empty state (Flighty's globe); it is the screen users see most often when the Inbox is clear. |
| **Inbox rows, To confirm rows, Suggestion confirm sheet** | none | | Decision rows carry no identity art (§1.3). The confirm sheet header keeps the 56 category tool render. |
| **Records** | none; `CategoryToolTile` 36 stays | | A record is about an activity. The tool carries identity; the house belongs to rentals. |
| **Reports** | thumbnail in the per-rental breakdown rows only | **44** | Reports is the ring's screen (§1.12). Two heroes compete. |
| **Settings, Learn, Export, Contact, Delete, Profiles, Capture setup** | none | | Utility. Mark C (the LH monogram, brand doc §5) may sit in the Settings header. |
| **Paywall** | none; the record preview is the picture, on the plain canvas | | The paywall sells the PDF record and must open about the thing tapped. Two pictures compete; the preview title stays `pdf.title`. |
| **Log time sheet, confirm sheet** | none | | "No hero art in task sheets" (§1.20) stands. |
| **Check my goal** (future) | none when it lands | | **Not on `int/2.1`.** It lives on `origin/feat/home-2.1` (`Sources/Views/GoalCheck/GoalCheckView.swift`, `GoalCheckLogic.swift`, `Models/RentalPlan.swift`), unmerged; DEBUG mocks are on `proto/dir-craft` (`HomeProtoGoalCheck`, `StdProtoGoalCheck`). It gets a §H.5 row and a plan package when that branch is scheduled. |
| **Milestone celebration** (100 / 500 / 750) | the hero on the page; `houseStageAdvance` plays here | H1 | The signature moment. |
| **Widgets** | medium, large, extra large: house-only thumbnail at 120, lit by `loggedToday`, appearance by the widget's scheme; small and accessory: the mono mark B | 120 | A 3D bitmap cannot tint; the mark can (§1.26). |
| **Live Activity, Dynamic Island** | mono mark B | 10pt glyph | §1.26 |
| **Thumbnail minimum** | **44pt**, house only. The diorama (with lot) is never shown under 220pt. | | At 44 the house reads; the lot does not. |

### H.6 The motion signature

Two moves, in this order, and then stillness: **the 39-piece timber drop, then the windows coming on.** Nothing loops. There is no idle gimmick (no smoke, sway, birds, clouds, weather). Named motions are in §B.3 (`timberDrop`, `windowsOn`, `stageFade`, `rentalSlide`).

| Rule | Spec | Kind |
|---|---|---|
| The drop | On a log or confirm that carries the shown rental from `frame70` to `framing` while Today is visible: the clip fades in over the still (0.20), plays 2.0 s, crossfades to `craft_framing` (0.30); the number rolls as the last timber lands, with one `.impact(flexibility: .rigid, intensity: 0.8)` (the wood knock). Pre-rendered, so it may exceed the 0.60 signature cap; it plays at most once per stage per rental. | measured on a 30 fps capture: ≥ 24 consecutive frames with changed pixels in the lot region; no frame-to-frame luma step > 25% in the lot region outside the two crossfade windows |
| Lights on | When the log is the first of the day: windows are **held dark** through the drop (the lit clip is multiplied to the unlit still's mean luma, 0.66 night / 0.76 dusk), then fade on over **0.40 s** after the crossfade. Without a drop: fade on 0.30 s after the still settles. The spill pool fades with them. | measured (luma 22.9 → 28.3 over ~11 frames in the reference capture) |
| Other stage changes | 0.25 s crossfade with a 0.97 → 1 scale settle, no clip. | grep: `stageFade` |
| One log, two or more stages | The house never plays the stages in between. If the new stage is `framing` (from `started` or `frame70`), the drop plays: its 0.20 fade-in covers the jump from the old still. Any other jump (for example `frame70` → `half`, `started` → `complete`) is one `stageFade` straight to the new stage, with no drop. | grep: `CraftHouseView` picks the motion from (old, new) in one switch |
| Rental switch | Slide the diorama in from the trailing edge (**0.30 s** spring, bounce 0), `.selection` haptic, number `numericText` 0.40. | grep: `rentalSlide` |
| Reduce Motion | No clip (the still crossfades 0.15); windows fade linear 0.40; slides become 0.20 fades. | grep: every branch present |
| Never | On appear. On a timer. On scroll. Twice for one event. | grep: no `onAppear { withAnimation` in `House/`; no `TimelineView`, no `repeatForever` |

### H.7 Chrome: the native tab bar and the fifth item

Native `TabView` only (§1.25 stands). **The create action is a native fifth tab, "Log time", `plus`, `role: .search`.** The locked iOS 27 frame shows it as the **fifth item inside the bar**, and that is the spec. Whether a given OS draws the `.search` tab inside the bar or in its own position is the system's call, so every hand-off that touches the shell includes captures on **iOS 18, 26 and 27**, and the gate compares each to the locked frame. Because `role: .search` may make VoiceOver announce "Search", the tab carries an explicit `accessibilityLabel("Log time")`, checked with VoiceOver on each of those OS versions **[measured]**. Selecting it opens the Log time sheet and restores the previous tab (`onChange(of: tab)`), so it never becomes the selected tab **[grep]**. The detached glass "+" of v1 §1.25 and the "+" in any title row are retired. Tabs: Today (`sun.horizon`), Inbox (`tray`, badge), Records (`book.closed`), **Rentals** (`house`; the locked frames already say Rentals; confirmed 2026-10-24), Log time (`plus`). Tint is `action` per appearance; measured selected-label contrast: dark `#9BE1FF` on `#0D1430` 12.6:1, light `#143497` on `#E3DACB` 7.7:1. The old hardcoded light `.tint` on the `TabView` (3.21:1 in dark) is the defect that failed look 2 on 2026-10-24 and must not return **[measured]**.

### H.8 Today, the anatomy at default size

Top to bottom on 402×874, light: rental chip (`Menu`, capsule 36, `.subheadline.semibold` ink + `chevron.down`, white 0.65 fill with a `#C9BFA8` 0.8 hairline; dark: white 0.08 / 0.14) · the hero (H1) with page dots (6pt, 7 gap) under the house when there is more than one rental · the number (Fraunces 84/600 opsz 144, tracking −2, `textPrimary`, `numericText`) · "of 100 hours" `.body` `textSecondary` · the pace sentence (`.subheadline`: lead in `behind` or `positiveOnPage` semibold, rest `textSecondary`; "Behind by 14h. 9h a week gets you to 100.") · "To confirm · 7" (`.headline`) · one grouped container (`backgroundSecondary`, radius 20, `pageCardEdge`) with **≤ 2** `LHRow.Action` rows and a foot `.tertiary` "See all 7" · nothing else. The toast on hero screens is a glass capsule at the **top**, in the chip's slot: it **replaces the chip while it shows** (the chip fades out, the toast fades in, then back), because 48pt under the status bar lands on the chip and the half and finished roofs reach the chip's band. It never covers a row or the house, and VoiceOver announces it (everywhere else §1.19 stands). Pace tiles and "This week" leave Today; they live on the rental page and in Reports. Swiping the house changes the rental (the one allowed `DragGesture` outside rows; lint allow-list `CraftHouseView`).

**D3b amended:** at default, chip + hero + number block + pace + "To confirm" header + 2 rows + foot are above the tab bar (measured on `today-light-L-windows-lit`). At XXL, 1 row. **When the window is under 700pt tall** (SE class 667, Duo closed 644): 1 row and the foot (arithmetic for 375×667: status 20 + chip 36 + frame 297 − overlap 44 + numeral 64 + "of 100 hours" 22 + pace 20 + header 30 + row 64 + foot 44 + gaps ≈ 585 of 618 above the bar); Duo closed keeps §1.27's allowance that rows may sit below the fold. At AX, the hero (H3), the number and the pace sentence are above the tab bar and the rows scroll (`today-*-AX3-scrolled`); the AX3 chip must never truncate mid-word ("Might b…" with 33pt free was the FAIL on 2026-10-24).

---

## 0. The measured problem (v1 background)

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

Page gutter **20** (Today's 24 and Properties' 16 retire) · section gap **24** · header→content **8** · card padding **16** · card radius **20 continuous** · inner surface **12** · tag **6** · stat tile **16** · hairline `border` 0.5 · type: system text styles, `design: .rounded` for numbers (always `monospacedDigit()`), `design: .monospaced` for drafting labels only in the PDF and the Reports eyebrow (v2: retired on every other screen), Fraunces only for tab titles and display (§1.14) · colours: intent tokens only. **[grep]** no `.system(size:)`, no `Color(hex:)` outside the token files.

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
| Meta line | `.subheadline`, `textSecondary`, one line, tail-truncates at default, wraps at AX. SF source glyph via `Label` (`calendar` / `checklist`) · time range ("12–2", "9–10:30") · one `LHTag`: category, or a status tag ("Not sure", "Needs hours", "Might be logged") which replaces the category. **No date in the row**: the date is the day header above it (§1.15a). Max 2 tags, overflow "+1". |
| Trailing: hours | `.subheadline.semibold` `.rounded` tabular, `textPrimary`, trailing-aligned, hugging its content: min 19pt ("2h"), max **68pt** (fits "12h 30m" at 65.1pt). "—" `textTertiary` when unknown. |
| Row tap | Opens the confirm sheet. |
| Swipe | System `.swipeActions` only (§1.3a). Trailing full swipe = "Not rental work" (`textSecondary` tint, `xmark`); leading full swipe = Confirm (`positive`, `checkmark`). |
| Decline | Via trailing swipe or the sheet's "Not rental work" `.tertiary`. No ✕ in the row. |
| Batch | **Inbox only (v2).** "Confirm N likely" (N = rows with `canQuickLog` and not `notSure`), shown when N ≥ 2; one tap logs them with one toast "Logged 3 · Undo". Two placements, one implementation: when the section fits the viewport, an `LHButton.tertiary` at the card foot; when the section's bottom edge is below the viewport (scroll geometry), a **pinned bar** (§1.3b). **Today** shows ≤ 2 rows and one foot `.tertiary` "See all N" (N > 2); it has no batch action and no pinned bar (§H.8). |
| Icons | SF Symbols only. No `CategoryToolTile` in a decision row; the render returns at 56pt in the sheet header. |
| Height **[measured]** | 64 with a 1-line title; 86 with 2 lines; ceiling 88 at default. |

#### 1.3a Swipe: one implementation, stated

**Decision: fully system.** `List` + `.swipeActions(edge:allowsFullSwipe: true)` in both Inbox and Today. No custom threshold, no `DragGesture`, no 96pt projection, no peek hint. Consequence: Today's root becomes a `List` with `.listStyle(.insetGrouped)` for the whole screen (as Reminders and Things are lists). The hero, timer slot and pace tiles are rows with `.listRowBackground(Color.clear)`, `.listRowInsets(EdgeInsets())` and `.listRowSeparator(.hidden)`; the To confirm rows are an ordinary inset-grouped section so the system draws the card and the swipe backgrounds clip to its corners. No hand-built card (`.propertyCard()`, `clipShape`) around rows anywhere **[grep]**: a custom card cannot clip a system swipe background correctly. `TodaySwipeRow`, `TodaySwipeHint` and `TodayDebugSeed.swipePreviewOffset` are deleted **[grep]**. The leading control is the visible affordance; Reminders ships no hint either. The haptic on a full swipe is ours, bound to the state change (§B.3), because the system fires none.

#### 1.3b Pinned batch bar

Anchor: Copilot's pinned "Yes, these are probably duplicates". Rendered with `safeAreaInset(edge: .bottom)`, 12pt above the tab bar, horizontal inset 20, in the slot the toast uses (a toast stacks above it). Capsule, height 44, `.regularMaterial` with a hairline `border`, label "Confirm N likely" in `.subheadline.semibold` `action` ink, `countChange` on N. It is `.secondary`-sized, not a `.primary`, so D8 holds. Appears with `toastIn`, leaves with `toastOut` when the section scrolls fully into view or N < 2. Density treatment **[measured]**: it is not a row and is excluded from D1, D2, D3 counts and D6; D3/D3b are measured with the bar present (it takes 56pt of the fold), so "≥ 2 rows above the fold" must hold with it on screen. `accessibilityIdentifier` `today.confirm.batch`.

### 1.4 Browse row `LHRow.Browse`

Records, Properties, Learn, picker lists. Same grid as 1.3: leading **36pt** tile (`CategoryToolTile(36)` in Records; the **house-only thumbnail at 44** in Properties (`LHThumb(stage:lit:size:)` at 44, `LHThumb.row`, lit state by `loggedToday`, §H.5); an SF glyph in a 36 wash tile elsewhere), 12 gap, title 1 line + meta 1 line, trailing value (`LHFormat.hours`, `.subheadline.rounded`) and `chevron.right` `textTertiary`. Height 56–64. One ornament per row **[grep]**: Properties shows the thumbnail, never the monogram seal beside it (today `PropertyRow` has a 40pt seal, a 48pt house tile and a chevron).

### 1.5 Value row `LHRow.Value` (pickers)

Inside sheets and forms, in an inner surface (radius 12, `backgroundTertiary`): `minHeight` **56** (D1's floor; r2's 52 contradicted it), label `.body` left, value `.body` `textSecondary` right + `chevron.right` (or `chevron.up.chevron.down` for a menu). Tap opens a sheet (≥ 6 options) or a `Menu` (≤ 5). Replaces the hand-built value rows in `LogTimeSheet:593` and `SuggestionConfirmSheet`. **[measured]** 56–88pt, like every row.

### 1.6 Toggle row `LHRow.Toggle`

`SettingToggleRow` as is: min 44, label `.body` + optional one-line `.subheadline` subtitle, system `Toggle` tinted `action`. The subtitle says the effect, not the mechanism ("At most two a day, never at night.").

### 1.7 Text field `LHField`

Single line: inner surface radius 12, height 52, padding 16/14, `.body`. Placeholder in `textTertiary` (#5F6983, 5.5:1), never the system placeholder grey **[measured contrast]**. Focus: 1.5pt `action` stroke, crossfade 0.15. Error: `destructive` stroke + `errorShake` + one `.footnote` line under the field saying what to do. Clear button: 20pt glyph in a 44 frame. Multi-line (Log time note): min 104, same radius; the field is the first thing in the sheet and takes focus on open.

### 1.8 Segmented control `LHSegmented`

One struct replaces `BPSegmentedPicker`, `LogWhoPicker` and the picker in `SuggestionConfirmSheet:376`. Capsule track `backgroundTertiary`, height 36, 2–3 segments (more → `LHRow.Value`), labels `.subheadline.semibold`; selected thumb `backgroundSecondary` with hairline, label `textPrimary`; motion `segmentSlide`; haptic `.selection`. Min segment width 64 **[measured]**.

### 1.9 Stepper `LHStepper`

One struct replaces `LogHoursStepper` and `SuggestionConfirmSheet:252`. Two `LHButton.icon` (`minus`, `plus`) flanking the value in `.title2.rounded.semibold` tabular, value column **100pt** (fits "12h 30m" ≈ 94). Not 40pt digits. Step 15m; long-press repeats every 0.12s after 0.4s; `.selection` per step; min 0, max 24h with the "ran past 24h" line.

### 1.10 Summary card `LHCard.Summary`

Anchor: Fitness Summary tiles. `backgroundSecondary`, radius 20, padding 16, hairline in dark only. Order: value (`.largeTitle.rounded.bold` tabular) → label `.subheadline` `textSecondary` → optional `.footnote` → optional one `LHButton.secondary`, or the card is one `.lhPressable` target. Ceiling 160pt at default **[measured]**. **v2: there is no hero card.** The house sits on the page (§H.1); no `LHCard` carries an illustration. The blueprint hero card and its drafting-cyan eyebrow are retired. **v2: the Summary card has no eyebrow**; the SF Mono drafting label is kept only in the PDF and as the Reports eyebrow over the ring (§1.15) **[grep: no `.monospaced` in `LHCard`]**.

**Today decision (2026-10-24, supersedes 2026-10-23):** the rental switcher is a quiet `Menu` chip above the hero (capsule 36, the rental's name + `chevron.down`), page dots under the house, and a swipe on the house (§H.8). The row of small houses inside the hero card is retired with the card. Switching slides the diorama (`rentalSlide`) and rolls the number (`numericText`).

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

Press = motion `press`. Disabled = no opacity dim on a button: `textSecondary` ink (≥ 4.5:1) on a `backgroundTertiary` fill with a hairline `border` (primary, secondary), `textSecondary` ink alone on tertiary, `textTertiary` on the icon circle. A whole-row `press` target still dims to 40%. The symbol weight inside `.icon` is the one place a symbol weight is set explicitly (§1.17).

### 1.14 Screen titles `LHScreenTitle`

Tab roots: **Fraunces 34/500** via `Font.custom("Fraunces", size: 34, relativeTo: .largeTitle)` (brand doc §3), optional one-line `.subheadline` `textSecondary` subtitle, 20 gutter, 8 below, one trailing `.icon` at most. Sheets: SF `.title2.semibold`, no eyebrow (v2: the drafting eyebrow is retired from sheets; a date goes in a `.subheadline` `textSecondary` subtitle, "Today, Thu Oct 22"). Display (Welcome, milestone): Fraunces 34. **The hero numeral (v2): Fraunces 84/600, opsz 144, tracking −2, `textPrimary`; 54 at AX; 64 when the window is under 700pt tall** (§H.8). It is the one numeral set in Fraunces; every other number stays SF Rounded tabular. **[grep]** Fraunces never under 28pt and never inside a row, card or button.

**Decision (2026-10-23): "See all" push roots may use Fraunces 34.** A pushed screen that presents a whole collection reached from a section header ("See all" → All rentals, All records, Muted suggestions) is a collection root and takes the tab-root title style (Fraunces 34 + subtitle), with a back `.icon` in the leading slot. A pushed screen about one item (a rental's detail, a record) takes SF `.title1.semibold`. Checkable: `LHScreenTitle(style:)` has two cases, `.collection` (Fraunces) and `.detail` (SF); `.collection` is allowed in tab roots and in the files listed as collection roots in the hand-off **[grep]**. All rentals is therefore conforming, not drift.

### 1.15 Section header `LHSectionHeader`

**v2:** `.headline` `textPrimary`, sentence case, the count after a middle dot ("To confirm · 7", "Your rentals · 3"); no count capsule. When the header names a state ("Needs attention", "On pace") it uses `behind`/`positiveOnPage` on the hero page (never `caution`, 3.67:1 there; §H.4) and `caution`/`positive` on the plain canvas or inside a card. Trailing slot: one `.tertiary`. 24 above, 8 below. The SF Mono 11 caps drafting label (`draftingInk`) is kept **only** in the PDF record and as the Reports eyebrow over the ring; it no longer heads sections **[grep: `LHSectionHeader` has no `.monospaced` style]**. Replaces `TodaySectionHeader`, the inline header in `InboxView:85` and `BPSectionHeader` **[grep]**.

#### 1.15a Day headers in actionable lists

Anchor: Copilot's date dividers, Things' "Today / This Evening". Every actionable list (Today To confirm, Inbox) groups rows by day; the row's meta line carries no date. Header: `.subheadline.semibold` `textSecondary` in sentence case, **not** the drafting mono (v2: retired on screens; it survives only in the PDF and the Reports eyebrow). Text: "Today", "Yesterday", then weekday + date without year for the last 6 days ("Mon Oct 19"), then "Oct 12" beyond that, "Oct 12, 2025" in another year; relative words come from `RelativeDateTimeFormatter`-equivalent rules in `InboxFormat.dayHeader(_:now:)` **[grep: one source]**. Layout: inside the inset-grouped section as the `Section` header, 16pt leading inset to align with the control, 16 above, 6 below; height 28 **[measured]**. A day header is not a row (excluded from D1/D3 counts). Ordering: newest day first; within a day, by start time. One header per day, even for a single row. Empty days are not shown.

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

In a container: SF Symbol 28 in `positive`/`action` → `.headline` → `.subheadline` `textSecondary` ≤ 2 lines → optional `.secondary`. Padding 20, total ≤ 160 **[measured]**. Full-screen (Inbox with nothing): **v2: the diorama of the first rental** (unlit when nothing was logged today) on the dusk/night page, frame ≤ 240pt (≤ 28% of the viewport), one headline, one line, one `.primary` (§H.5). The blueprint art is retired.

### 1.19 Toast `LHToast`

Current component (radius 22, min 52): one glyph + ≤ 2 lines + one `.tertiary`. 12 above the tab bar. **v2, hero screens (Today, the rental page, the milestone): a glass capsule at the top, in the rental chip's slot, replacing the chip while it shows (chip out, toast in, `quick`; reversed on dismiss), so it never covers a row or the roof** (§H.8). It posts a VoiceOver announcement (`AccessibilityNotification.Announcement`) with its text **[grep]**. The placement is one parameter of the toast center (`.top` on hero screens, `.bottom` elsewhere), owned by plan package 0; `.glassEffect(.regular, in: .capsule)` on iOS 26+, `.regularMaterial` below. 4s; 8s with an action. Swipe down (or up, at the top) dismisses. One at a time, crossfade on replace.

### 1.20 Sheet `LHSheet`

System `.sheet`, detents `[.medium, .large]` when content allows, drag indicator visible. Header 56: title (§1.14 sheet style) left, `.icon` close right. Gutter 20. `.primary` pinned via `safeAreaInset`, 16 inset; ≤ 1 `.tertiary` above it. No hero art in task sheets.

**Focused-entry sheets (Log time, the confirm sheet), decided by Brian 2026-10-23:** an **opaque** `.large` sheet on `backgroundSecondary`, with the system's push-back and dim of the screen behind it, so the task has the whole screen and nothing shows through. Liquid Glass appears only on the Log (`.primary`) button and on the system keyboard; the sheet surface itself is never glass or translucent material. **[grep]** no `.presentationBackground(.thinMaterial/.ultraThinMaterial/.glass…)` on `LogTimeSheet` or `SuggestionConfirmSheet`; `.presentationDetents([.large])` on both; the primary button carries the glass style only inside the `#available(iOS 26, *)` branch.

### 1.21 Alerts and dialogs

System `.alert` only for irreversible destructive acts (delete all data, remove a rental): title ≤ 6 words, message ≤ 2 sentences, buttons are verbs ("Delete", "Keep"), destructive role set; never "OK"/"Yes". ≥ 3 choices → `.confirmationDialog`. Everything reversible gets a toast with Undo, never an alert **[grep: `.alert(` sites listed in the hand-off]**.

### 1.22 CPA footnote `LHFootnote.cpa`

`.footnote`, `textSecondary` (tertiary fails AA on canvas at 12pt), last element of the content, at most one per screen **[grep]**. Canonical key `common.cpaFootnote` = "Your CPA decides what the numbers mean."

### 1.23 Paywall scaffold

**v2: on the plain canvas, no blueprint band, no house.** The record preview (≤ 40% of viewport; its title string is the same key as the real PDF title, §C.5) → plan card radius 20: name + `LHTag` "PAY ONCE" → price `.largeTitle.rounded.bold` + "once, yours to keep" `.subheadline` → one body line → `.primary` "Unlock for $29.99" → `.tertiary` "Restore purchase" → status line → benefits as 56pt `LHRow.Browse` with SF glyphs → legal `.footnote` links in 44 frames. Close is `.icon`. No countdowns, no fake scarcity, no `dynamicTypeSize` clamp. The paywall opens about the thing tapped (the record, the export, the second rental) and names it in its first line.

### 1.24 Onboarding scaffold

Uses the app's components and tokens; `OnbColor` and the `Onb*` styles are deleted **[grep]**. **Welcome (v2):** the dusk/night page with `craft_complete` lit at the Today hero size (§H.5), the headline in Fraunces 34, one `.primary` pinned in a `safeAreaInset`, "Have an account?" as a `.tertiary` that never truncates; frames at AX5 required (the 2026-10-23 Duo probe found the headline clipped under the button at AX5). The add-a-rental step shows the 120pt `craft_started` thumbnail beside the field. Progress: 3pt track `border`, fill `action`. Back `.icon`, Skip `.tertiary`. Step title SF `.title1.semibold` (Fraunces only on Welcome). Option cards are `LHRow.Browse` rows in one grouped container; selection is shown the Apple Settings way, with a **trailing `checkmark` in `action`** (`.body.semibold`, 44 frame) on the selected row and the row's hairline stroke turning `action`; the leading slot holds the option's SF glyph. The 22pt leading circle is reserved for confirm in §1.3 and never appears in onboarding or pickers **[grep]**. One `.primary` pinned. No Dynamic Type clamps; frames at AX3 required.

### 1.25 Navigation and Liquid Glass

**Minimum OS for 2.1: iOS 18.0** (Brian's decision, 2026-10-23; up from 17. Drops no iPhone; on iPad it drops the iPad 6th gen and the iPad Pro 2nd gen). Every Liquid Glass API below sits behind `#available(iOS 26, *)`; on iOS 18–25 the same view uses the system material the OS ships (`TabView` draws its own bar, including the fifth "Log time" item; `.regularMaterial` for the batch bar and toast). The fallback is the system's material, never a hand-made imitation of glass. **[grep]** every `.glassEffect(`, `.glass`, `.glassProminent`, `.tabBarMinimizeBehavior(` and `.tabViewBottomAccessory` is inside an `if #available(iOS 26, *)` branch; the deployment target in the project is 18.0; no `#available(iOS 17` checks remain.

Brian's question, 2026-10-23: does the navigation use the latest Liquid Glass design? Today it does not: `ContentView.swift` draws a custom floating tab bar with its own material, a detached "+" circle and hand-set sizes. Decision: **the native `TabView` only**, so the system draws the Liquid Glass bar and keeps it current with every iOS release. (v2: the detached "+" is gone; "Log time" is the fifth tab, §H.7.)

| Rule | Spec | Kind |
|---|---|---|
| Tab bar | SwiftUI `TabView` with `Tab` items (Today `sun.horizon`, Inbox `tray`, Records `book.closed`, **Rentals** `house` (confirmed 2026-10-24), **Log time `plus` with `role: .search`** and `accessibilityLabel("Log time")`), SF Symbols, `.tint(colors.action)` per appearance (never a fixed light tint: the hardcoded light tint measured 3.21:1 in dark on 2026-10-24). No custom tab bar, no `ZStack` overlay bar, no `UITabBar` appearance hacks, **except one line (2026-10-24, §1.27 AD17): `UITabBar.appearance().unselectedItemTintColor` = `textPrimary` at 0.85, so unselected items take the house ink in every mode.** | **[grep]** `TabView(` present at the root; five `Tab(`s, one with `role: .search`; zero views named `*TabBar*` outside previews; zero `.toolbar(.hidden, for: .tabBar)` at the root. |
| Minimize behaviour | `.tabBarMinimizeBehavior(.onScrollDown)`: the bar shrinks to the active tab as the user scrolls down and returns on scroll up. Nothing else may react to the bar's size; use the system safe-area insets. | [grep] modifier present once, at the root |
| Create action | **v2 (Brian, 2026-10-24): "Log time" is the native fifth tab**, `plus`, `role: .search`, shown as the **fifth item inside the bar** as in the locked iOS 27 frame. Captures on iOS 18, 26 and 27 are required with every shell change, each compared to that frame; an explicit `accessibilityLabel("Log time")` stops VoiceOver reading the `.search` role as "Search", checked on each OS. Selecting it opens `LogTimeSheet` and restores the previous tab in `onChange(of: tab)`, so it is never the selected tab and the sheet always returns to where the user was. The detached glass "+" `Button` in a `safeAreaInset` is retired. One create action for the whole app; screens never add a second "+" in their title row (Rentals' "Add rental" moves to the list's empty state and the screen's `.toolbar` trailing item). | [grep] one `Tab(… role: .search)` whose selection is reverted and which carries an `accessibilityLabel`; zero `.buttonStyle(.glass)` "+" buttons; no `plus` in `LHScreenTitle` trailing slots. [measured] iOS 18/26/27 captures and a VoiceOver read |
| Badges | System `.badge(_:)` on the Inbox tab only, with the To confirm count (likely + not sure; muted excluded). Hidden at 0. No badge on Today, Records or Rentals. Red system badge is accepted (it is the system's semantic, not our `destructive`). | [grep] one `.badge(` call, on the Inbox `Tab` |
| Content under the bar | Scroll views and lists run edge to edge under the bar; **no reserved bottom heights** (`padding(.bottom, 100)`, `Spacer(minLength: 80)`, fixed `tabBarHeight` constants are deleted). Bottom-anchored controls (`LHButton.primary` in sheets, the pinned batch bar §1.3b, `LHToast`) use `safeAreaInset(edge: .bottom)` so they follow the bar as it minimizes. The system scroll-edge effect replaces our `TodayTopEdgeFade`. | [grep] no bottom padding ≥ 60 at a tab root; `TodayTopEdgeFade` deleted |
| System materials | Bars, sheets, popovers and menus use the system: `TabView`, `NavigationStack` toolbars, `.sheet`, `Menu`, `.glassEffect()` on the few floating controls we own (the pinned batch bar, the toast, the Log time sheet's `.primary` on iOS 26+). No hand-made glass: no `.ultraThinMaterial` + hairline + shadow stacks imitating a bar, no blurred `Rectangle`s, no `backdrop`-style layers. Light and dark follow the system; we never force a material's tint. | [grep] `.glassEffect(` / `.glass` only in `LHButton` (the sheet `.primary` and the `.icon` glass variant), `LHToast`, the batch bar; zero `.ultraThinMaterial`/`.thinMaterial` on bar-shaped views |
| Text over glass | Text on a glass surface uses `textPrimary`/`textSecondary` with the system's vibrancy (`.foregroundStyle(.primary/.secondary)` inside the glass container), never a fixed hex. Measured contrast ≥ 4.5:1 for every glass label against the busiest backdrop we ship (**the diorama** scrolled under the bar at AX, where the rows and the house pass beneath it, and the darkest dark-mode night page), light and dark. Icon-only glass controls carry an `accessibilityLabel`. Glass never holds more than one line of text. | [measured] frames with the diorama under the bar |
| Reduced transparency / contrast | System materials already honour Reduce Transparency and Increase Contrast; we add nothing and remove nothing. Frames at `accessibilityReduceTransparency` are part of the hand-off for any change that touches a glass surface. | [measured] |

What this changes elsewhere in this document: "12pt above the tab bar" in §1.3b and §1.19 means "inside `safeAreaInset(edge: .bottom)`", which the system positions above the live bar height; D3's "above the tab bar" is measured to the bar's top edge in its full (not minimized) state at scroll offset 0.

### 1.26 Widgets and Live Activity

SF Symbols and the mono mark B template only; numbers `.rounded` tabular via `LHFormat.hours`; small: value + label; medium: value + current house render; Lock Screen/Island: mono glyph + hours; checked in accented and tinted modes; ≤ 2 text lines; no tool renders.

### 1.27 Adaptive layout: one model for iPhone, iPad and the iPhone Duo

**Rewritten 2026-10-24** (Brian: "make sure the design system is updated so that the layout for normal iPhone, iPad and iPhone Duo are consistent"). The 2026-10-23 model (bands A/B/C, `NavigationSplitView`, the iPad sidebar, a `Table`, an `.inspector`) is replaced by the model the locked Duo design proved: **two layout modes, chosen by the width the app actually gets.** Every change to the 2026-10-23 rules is listed in "What changed" at the end of this section. Earlier spec: `~/AgentScratch/landlordhours/2026-10-23/adaptive/spec.md` r2 (history only).

#### The model

| Mode | Who gets it | Layout |
|---|---|---|
| **Compact** | every iPhone in portrait **and in landscape, the Pro Max included** (H < 645), the closed Duo (382×644), iPad mini portrait, narrow Split View tiles (1/3, 1/2, and 2/3 on 11"), Slide Over, Stage Manager windows under 800 wide or 645 tall | **One column**: the house hero on top, then the work. This is the locked Today, unchanged. |
| **Two-pane** | the Duo held open (951×669), iPad 10th gen, Air and Pro 11" and 13" in portrait and landscape, iPad mini landscape, the 2/3 tile on 13", Stage Manager windows at least 800×645 | **The house on the left, the workstation on the right, always.** Left: the hero, the hours, the pace and the rental shelf. Right: the work (To confirm, Inbox, Records, the rental page, Log time), with detail and Log time opening **inside the right pane** over the interior wall. Same panes, same order and same contents on iPad and on the Duo. |
| **Stacked** | the Duo propped up (669×951, the fold across) | Two-pane turned on its side: the house and shelf in the top half, the workstation and the bar in the bottom half. |

**Choosing the mode** **[grep]**: `LayoutMode.resolve(previous:size:division:live:)` is the only place it is computed. Inputs are the scene's size `W`×`H` (from `onGeometryChange` on the root; never the screen, idiom, device name or orientation), the active `.division` region, if any (`GeometryProxy.reservedRegions(kind: .division)`), and whether a resize is live.
- A **vertical** active division (the Duo held open) → two-pane, split at the division, **only if each pane is ≥ 380 wide**; otherwise compact.
- A **horizontal** active division (the Duo propped) → stacked, split at the division, only if each half is ≥ 380 tall; otherwise compact.
- No division: **two-pane iff `W ≥ 800` and `H ≥ 645`**, else compact. 800 gives panes of 388 (≥ 380) and sits above the 11" 2/3 tile (≈ 780–795), so that tile is always compact. **645 is the height floor**: below it the hero cannot keep both its 290 minimum and its 0.45 × H cap (290 / 0.45 = 645), so short windows stay compact. This also keeps an iPhone in landscape compact, the Pro Max included (956×440), if `~iphone` landscape is ever turned on. Inside compact, `W` < 600 is the phone layout (gutter 20); `W` ≥ 600 is one column ≤ 600 centred (gutter 24), as band B was.
- **Hysteresis only during a live resize, and only above the threshold:** while a resize is live, two-pane turns on at `W ≥ 808` / `H ≥ 653` and off below 800 / 645. When the size has been still for 0.3 s, and at every scene connect and launch, the mode is re-resolved **with no history** (`previous: nil`). The mode therefore never depends on the path taken: a window settled at a given size always gets the same mode. **Accepted:** a live resize that stops between 800 and 808 (or 645 and 653) flips the layout 0.3 s after the user lets go; that late flip is captured in every adaptive hand-off (must-prove 12). The A/B split inside compact keeps 592/608 the same way.
- Minimum pane width **380**: the narrowest pane must hold the 290 hero with 16 gutters and a phone-width list. iPad mini portrait (744) stays compact; iPad 10th gen portrait (820) gets two panes of 398. Captures at 799/800 and 644/645, each reached from both sides and then settled, are part of every adaptive hand-off.

**Platform.** Minimum OS **iOS 18.0** (decided 2026-10-23). `ArrangementView`, `reservedRegions`, `onHingeChange` and `toolbarVerticalBehavior` sit behind `#available(iOS 27.1, *)`; below it, two-pane is the same two views in an `HStack` and nothing hinge-keyed exists. Glass stays behind `#available(iOS 26, *)` with the system-material fallback (§1.25). `Info.plist` stays `~iphone` portrait-only and `~ipad` all orientations; Duo open landscape is kept pending the orientation probe (must-prove 6).

**The gap.** On iPad there is no hinge, so the gap between the panes takes the hinge band's place at a design width of **24pt** (the same as the Duo's assumed fold band). It is page, not a divider: no line, no shadow, no control, no text crosses it, and the door's light wash (`FoldWash`) centres on it in every two-pane window, so the two walls meet the same way on both devices. On the Duo the gap is whatever `reservedRegions(kind: .division)` returns (frame plus margins).

**Split.** The panes are equal: each is `(W − gap) / 2`. Content inside a pane is capped at 600 and centred (13" landscape: panes 676, content 600). The left pane never widens to take spare room; consistency beats filling a 13" screen.

**The door.** `duoUnfold` (§B.3) plays **only on a Duo hinge event**. On iPad, and whenever the app opens already in two-pane, the right pane is simply lit at rest: no door, no light-up on appear (§B.1 never animates on appear, and an iPad has no physical event for the light to answer). **Decided 2026-10-24: nothing on iPad** (a light-up on first appearance would read as decoration).

**Navigation and the tab bar, every mode.** One root `TabView` (Today, Inbox, Records, Rentals, the `.search`-role "Log time", §1.25), `.tabViewStyle(.tabBarOnly)`: **no sidebar on iPad**. The bar is the same system bottom bar in every mode:
- Compact: the foot of the screen (the closed Duo's trailing rail is the system's and stays).
- Two-pane: the foot of the **right pane** only, as on the open Duo; the left pane has no bar. **The one allowed bridge:** the right pane's `TabView` is hosted in **one child `UIHostingController`** whose `traitOverrides.horizontalSizeClass = .compact`, so the system itself draws its compact bottom bar there. A SwiftUI `.environment(\.horizontalSizeClass, …)` override is not documented to change the bar and is not used. This must be proven on **iPadOS 18, 26 and 27** (must-prove 12; §H.7 requires all three OSes). **If it fails on any of them, that OS gets the system's own iPad tab bar over the right pane (the floating top bar), never a custom bar.** The Duo uses the same bridge.
- Stacked: the foot of the screen (the bottom half).
- `.toolbarVerticalBehavior(.disabled)` (iOS 27.1, behind `#available`) in two-pane and stacked, so the Duo never folds the bar into a side rail beside the fold.
- **Decided 2026-10-24 (Brian): no sidebar on iPad**, the bar at the right pane's foot as on the open Duo. A sidebar beside house-left and workstation-right would make three competing columns, and its per-rental tabs duplicate the shelf.
- Settings is reached as on the phone: the gear on Today's root, top trailing (in two-pane, the top trailing of the left pane); it opens in the right pane.
- Unselected bar items take the house ink (`textPrimary` at 0.85) in every mode, through one `UITabBar.appearance().unselectedItemTintColor` line in `LandlordHoursAppEntry` (§1.25 amended: the one allowed appearance setting); selection is `colors.action`.

**[grep]** zero `userInterfaceIdiom`, zero `UIDevice.orientation`, zero `*Pad*`/`*iPad*`/`*Duo*` view names outside `Views/Adaptive/` (the two-pane parts are named for their role, `HousePane`, `WorkPane`, not for a device); zero `NavigationSplitView`, `.inspector(`, `TabSection(`, `.sidebarAdaptable`, `tabViewSidebarHeader`; `traitOverrides.horizontalSizeClass` set in exactly one place (the right pane's hosting controller), and no `.environment(\.horizontalSizeClass` anywhere; no hard-coded 951, 669 or 24 in shipping layout code (the gap constant `LayoutMode.paneGap` is the one exception, for iPad).

#### What sits where

Same components (`LHRow.*`, `LHCard`, `LHTag`, `LHChip`, `LHButton`, `CraftHouseView`) in every mode; only the system chrome differs.

| Tab | Compact (one column) | Two-pane: left (house) | Two-pane: right (workstation) | Stacked (top / bottom) |
|---|---|---|---|---|
| **Today** | rental `Menu` chip, hero, number, pace, "To confirm · N" with 2 rows and "See all" (D3b) | hero (the skyline on "All rentals"), number, pace, the shelf ("All rentals" first) | To confirm (filter chip, count, rows, "N more at other rentals"), then "On the record today"; a row's detail and Log time open here with "‹ To confirm" | house + number + shelf / To confirm (1 row + "See all N", DU13) + On the record |
| **Inbox** | the Inbox list; detail is the confirm sheet | the same house pane (the shelf does **not** filter the Inbox: it shows every rental in every mode, as on the phone) | the Inbox list; detail opens in the pane with a back link | house / list |
| **Records** | `LHRow.Browse` list with the `LHChip` strip; record opens as a push | the same house pane (the shelf does not filter Records; Records keeps its own `LHChip` strip, the same as compact) | the same list; record opens in the pane | house / list |
| **Rentals** | the rentals list; a rental page pushes (its own hero) | the selected rental's hero + shelf (the shelf **is** the rentals list) | the selected rental's page body (pace tiles, this week, its records, Log time here); "Add rental" in the pane's toolbar | house / rental body |
| **Log time** (the fifth tab) | `LogTimeSheet`, `.large` sheet; restores the previous tab | unchanged | `LogTimeSheet`'s content **in the pane**, naming the rental shown; restores the previous tab | house / Log time |
| **Settings** | push from the gear | unchanged | Settings in the pane | house / Settings |

**What the shelf selects:** the hero, the number block and Today's To confirm filter (Today only), and which rental page the Rentals tab shows. Nothing else. The compact chip selects exactly the same things. The house pane is the same view in every tab: switching tabs never moves or re-lays the house, only the right pane changes. Sheets that are not Log time or a detail (the paywall, onboarding, export, capture setup) stay system sheets over the whole window, `.presentationSizing(.form)` when wider than compact.

#### Sizes by mode

| Size (pt) | Device or window | Mode | Pane(s) | Hero | Numeral | Switcher | Rows |
|---|---|---|---|---|---|---|---|
| 402×874 · 440×956 | iPhone 17, Pro Max, portrait | compact A | 402 · 440 | H1: 390 · 426 cap 390 | 84 | chip + dots | D3b: 2 + foot |
| 874×402 · 956×440 | iPhone landscape (if ever enabled) | compact (H < 645) | one column ≤ 600 | **220** (H1 gives 179–196, below the floor; rows scroll) | 64 (H < 700) | chip | 1 + foot, scrolling |
| 375×667 | SE class | compact A | 375 | 297 | 64 | chip | 1 + foot |
| 382×644 | Duo closed | compact A | 382 | 287 | 64 | chip | 1 + foot |
| 744×1133 · 768×1024 | iPad mini portrait | compact B | column 600 | 390 | 84 | chip | D3b |
| 1133×744 | iPad mini landscape | two-pane | 554.5 | 347 | 76 | shelf | DU4 |
| 820×1180 · 834×1210 | iPad 10th gen / Air 11" · Pro 11" portrait | two-pane | 398 · 405 | 290 | 76 | shelf | DU4; Inbox/Records ≥ 7 |
| 1180×820 · 1210×834 | the same, landscape | two-pane | 578 · 593 (content 600) | 362 · 371 | 76 | shelf | DU4; ≥ 7 |
| 1032×1376 | 13" portrait | two-pane | 504 | 316 | 76 | shelf | DU4; ≥ 9 |
| 1376×1032 | 13" landscape | two-pane | 676 (content 600) | 390 | 76 | shelf | DU4; ≥ 9 |
| ≈ 905–920 × 1032 | 13" landscape, 2/3 tile | two-pane | ≈ 440 | 290 | 76 | shelf | DU4 |
| ≈ 780–795 × 820 | 11" landscape, 2/3 tile | **compact** (< 800, either path) | column 600 | 390 | 84 | chip | D3b |
| ≈ 375–690 | 1/3 and 1/2 tiles, Slide Over (≈ 320–375) | compact A or B | — | H1 / 390 | 84 | chip | D3b |
| any W × < 645 | short Stage Manager window | compact | — | `min(390, H1)`, floor 220 (H6) | 64 (H < 700) | chip | 1 + foot |
| 951×669 | Duo open | two-pane | **463.5** (24 fold) | **290** | 76 | shelf: models 104 in 108 slots | DU4 |
| 669×951 | Duo propped | stacked | 669 per half | **220** beside the number | 60 | shelf | DU13: 1 + foot + On the record |

Hero: compact by §H.1 H1 (390 cap, 287 closed Duo, 297 SE; `W ≥ 600` by H6, `min(390, H1)` with a 220 floor); two-pane `clamp(round(0.626 × pane), 290, 390)`, never above 0.45 × H; stacked 220. At AX every two-pane and stacked hero is × 0.75 and the numeral 54. The 1/3, 1/2 and 2/3 widths are approximate and are measured on the iPad 10th gen, mini and an 11" before J2's iPad half closes (NOTES §13).

#### Rules kept from 2026-10-23 (re-scoped to the two modes)

| Rule | Spec | Kind |
|---|---|---|
| Create action | One "Log time": the fifth tab in every mode, plus ⌘N. In compact it opens `LogTimeSheet` (`.large`); in two-pane and stacked it opens in the right pane. Not a popover, not an inspector, never a second "+" | grep |
| Window controls | In a compact iPadOS window the window controls (≈ 50×26, top-leading) sat over the phone layout's in-content title. The compact root reads `layoutGuide(for: .safeArea(cornerAdaptation: .vertical))` and moves the `TabView` down by the difference to the safe area (43pt measured; under 8pt is corner rounding and ignored). In two-pane they sit over the house pane's top leading, which keeps 52pt clear | measured |
| Row grammar | `LHRow.*`, `LHTag`, `LHChip`, `LHButton` identical in every mode; width grows only the title column; no mode-specific row or card type | grep |
| Widths | Text ≤ 640pt wide; explainer cards ≤ 560; `LHTile.Stat` 2-up only in a pane or column ≥ 440, else 1-up; below 360pt the hours label drops "of N" | measured |
| The fold or gap | The hero never straddles the gap or the fold; no text, art or control crosses it (DU2) | measured |
| **D8 amended** | One `.primary` per **pane or sheet**; ≤ 2 `.secondary` visible per pane. Two primaries on one screen only when the two panes have their own tasks | grep |
| Pointer and keyboard | `.hoverEffect(.highlight)` on rows and chips; `.help()` on `.icon` buttons; `.contextMenu` on To confirm rows (Confirm · Change hours… · Not rental work · Open), Records rows (Open · Edit · Duplicate · Delete) and rental rows (Open · Open in New Window · Log time here; Check my goal added when it lands). ⌘N log, ⌘⇧N timer, ⌘F Records search (not while a text field is focused), Space confirm / ⌫ not rental work on a focused To confirm row, Esc dismiss, ⌘Return log in sheets. ⌘1–4 only if verified free on iPadOS. All via `.keyboardShortcut` / `.onKeyPress`. | grep |
| Drop | `.dropDestination` for images and PDFs on the Log time sheet, To confirm rows, Records rows and Today's canvas (opens Log time with the receipt attached); the target takes a 1.5pt `action` stroke on hover (`tileFocus`); ≤ 5 attachments per record; ⌘V pastes the same payload; a rejected type shows nothing. | grep + measured |
| Scenes | `UIApplicationSupportsMultipleScenes` is already true. Tab, navigation path, column state, selection, drafts (`LogTimeDraft`, `SuggestionDraft`; `GoalCheckDraft` when Check my goal lands), toast, scroll anchor and band live in a per-scene `SceneState`; records, rentals, hours and the timer in the shared `AppModel`. `@SceneStorage` restores tab, selected rental and path; drafts persist per scene on background and reopen with "Draft from earlier · Discard". `WindowGroup(for: RentalID.self)` + `openWindow` for "Open in New Window" (hidden when `supportsMultipleWindows` is false). A fold, unfold or resize rebuilds views and loses nothing. | grep + measured (kill and relaunch with a draft open) |
| Continuity | No custom transition on fold or resize; the system animates. `onHingeChange`, if available, only pauses §B.4 scenes between poses. **Amended 2026-10-24 for the hinge-keyed door only:** `duoUnfold` (§B.3) plays on `onHingeChange` and nothing else; it never plays on a resize, an arrangement change or a scene change, and every other transition stays the system's. | grep |
| Widgets | Adds `systemLarge` (house + number + 3 To confirm rows with an interactive Confirm), `systemExtraLarge` (iPad Home Screen: mini Today left column + 5 rows) and `systemExtraLargePortrait` (iPad Lock Screen in landscape: stacked mini column + 3 rows). §1.26 rules apply. | measured in accented and tinted |
| Hardware | **Measured on the iOS 27.1 iPhone Duo simulator (2026-10-23):** outer 466×678pt @3x (screenshot 1398×2034), inner 669×951pt @3x (2007×2853); closed: app area 382×644, safe area trailing 84 and bottom 34, compact/regular, hinge Closed 0°, portrait-only honoured. Hinge API is UIKit `UIHingeInteraction` (`UIHinge.status`, `angle`, iOS 27.1). **Corrected 2026-10-24:** SwiftUI does have `onHingeChange(isEnabled:_:)` with `DeviceHingeContext.hinge?.status`/`angle` (SwiftUICore swiftinterface, lines 16741–16772, read in `duo-concept-v2/concept.md`); "SwiftUI has no `onHingeChange`" is superseded, and `UIHingeInteraction` is the fallback. Open poses are not yet measured (posture needs Device Hub); full-bleed surfaces read `safeAreaInsets`. | measured |
| App Store | iPad 13" frames only of a build that has these layouts (Guideline 2.3.3); stretched frames invite 2.4.1. Duo ships as two sizes (outer 1398×2034, inner 2007×2853). | judgment |
| Dynamic Type | Two-pane holds at AX1+ (each pane is phone-width, so a pane takes the phone's AX rules: hero × 0.75, numeral 54, rows wrap); XXL and AX3 frames per mode required | measured |
| Acceptance environments | Two-pane iPad frames: iPad 10th gen (iPadOS 27) portrait and landscape, one Stage Manager window at 800 (two-pane) and one at 700 (compact), a 1/3 tile, with Apple's Reminders, Health, Fitness and Settings captured on the same iPad (§5.5). Duo frames: the iOS 27.1 Duo simulator closed, plus off-screen @3x renders open and propped until a device exists (the must-prove list below). Frames at 799/800 and 644/645 (the mode switch, each reached from both sides and settled) and 599/600 in light and dark in every adaptive hand-off | judgment |

System chrome and contrast (2026-10-23, mock lane; sidebar parts retired with the sidebar): our own text stays at ≥ 4.5:1 (≥ 3:1 for icons) against the actual pixels behind it, including the glass bar in the right pane; the tab bar's selected label ≥ 4.5:1 on its pill (v6 Duo: 7.80 lowest). `colors.action` is the tint in every mode (#1E3FA6 light, #8FD3FF dark).

Density addendum: in two-pane, D3, D4 and D6 are measured per pane; D6's hero share is H2 against the pane height; the gutter inside a pane is 16 on the Duo and in iPad panes under 440, else 24.

#### Two-pane in detail (from the locked Duo design, 2026-10-24, after six rounds)

Sources: `~/AgentScratch/landlordhours/2026-10-24/duo-concept-v6/` (README, frames, `selfcheck/measure-v6.txt`), `duo-concept-v5/concept.md` (layout), `duo-concept-v2/concept.md` (API citations with SwiftUICore swiftinterface lines), `duo-concept-v4/README.md` (the filter), `duo-gate6/` and `duo-critic5/verdict.md` (the numbers). **The numbers are v6's; `duo-concept-v7/` (the final fix pass on the critic's five gaps) is the capture of record**, and where v7 measures differently, v7 wins and this section is updated. Prototype code: `Sources/Views/Debug/DirCraft/DuoTwoPane.swift` on `proto/duo-door-v2` (package J ports it; it is not merged). The iPad two-pane frames do not exist yet; package J captures them against these same rules.

- **Container:** on the Duo, `ArrangementView { HousePane } secondary: { WorkPane }` with `.arrangementViewStyle(.split.axes(.horizontal))` (`.vertical` when stacked) and `.splitArrangementLayoutRatio(0.5)`; on iPad the same two views in an `HStack` with the 24 gap. One `TwoPaneLayout` view chooses; the panes do not know which. The house must render **leading (left) and on top**: which side `ArrangementView` gives its primary is unproven (the prototype made the workstation primary), so J1 confirms it on the 27.1 SDK and swaps primary and secondary if needed (must-prove 15).
- **House pane:** the selected rental's lit diorama, the Fraunces number, "of 500 hours · Pine Cabin", the pace sentence, then the **timber shelf**: "All rentals" first, then one model per rental with its name and "46 of 100h". Tap a model or swipe the house to switch (`rentalSlide`). The shelf scrolls and fades at both edges when it overflows. Nothing else in this pane is operable except the Settings gear.
- **"All rentals" is honest:** the hero is the **skyline** (§H.1 H10), never one house at one stage; the number block reads "312 hours across 3 rentals · 3 of 3 behind" and the pace line "Tap a house to see its pace." (or "Every rental is on pace."); the shelf label reads "3 of 3 behind" or "All on pace". **No goal, no summed goal and no stage are computed for "All rentals"** **[grep]**: no `reduce` over `goal` and no `CraftStage.stage(` call on an aggregate in `Views/Adaptive/`, Today or the shared number block. J2 **does not port** the prototype's `stage: .complete` and `goal: reduce(+goal)` (`DuoTwoPane.swift:82–83`). Decided 2026-10-24 for every mode.
- **Work pane:** an opaque `LHCard` over the interior wall. To confirm's header is "To confirm", the rental filter chip and the count set large. Picking a rental filters the list to that rental's items plus items with no rental yet; "4 more at other rentals" sits at the foot and, like clearing the chip, shows all rentals. "On the record today" lists that rental's logged entries and fills the pane to the bar.
- **The interior wall:** the Today page gradient continues across the gap; by day round-1 A's room shows through, dusty and away from the gap; by night the navy page with one warm pool at the gap.

**[measured] rules.** Builder self-checks these on the @3x frames before hand-off (`scripts/adaptive/two_pane_check.py`, package J; its regions start from `duo-gate6/aa.py`); the gate re-measures.

| # | Rule | Number (v6 measured) | Kind |
|---|---|---|---|
| DU1 | Pane width | each pane = (W − fold band) / 2; **463.5 at the assumed 24pt band**; the band is read from `reservedRegions(kind: .division)` at runtime (frame + margins), never hard-coded in shipping code; 24 is a capture fallback until a device read. **iPad:** the 24 gap, panes `(W − 24)/2` |  measured |
| DU2 | Fold band | 0 text-edge pixels (neighbour luminance step > 40) inside the band on every open and propped frame (v6: 0 of 20 frames) | measured |
| DU3 | Pane gutter | 16 inside each pane; card padding 16; rows per §1 (D1 56–88, target 64; v6 row pitch ≈ 65) | measured |
| DU4 | Right pane density | **filtered:** ≥ 3 To confirm rows + the "N more" foot + "On the record today" above the bar; **All rentals:** rows run to the bar (v6: 7). Empty wall between the last card and the bar ≤ 20% of the pane (v6: 0%). The last row clears the bar glass **at rest** (v7: bottom content inset 84pt, `barClearance`; the last subtitle 7.05:1 dusk, 8.85 night) | measured |
| DU5 | Zero logged today | "On the record today" stays: its header (no "0h"), a hairline and one line "Nothing logged yet today.", no button; the wall below ≤ 20% of the pane (v7 `open-zerologged`: the state sits at 442–515pt, ≈ 100pt of wall above the bar = 15%; line 7.01:1 dusk, 8.85 night) | measured |
| DU6 | Left pane density | the shelf replaces the rental `Menu` chip here; hero 290, number block, pace sentence and the shelf are all above the pane foot at default size; at XXL the shelf labels wrap to 2 lines and nothing ellipsizes | measured |
| DU7 | Shelf edge fade | steep and symmetric: clear 0–9pt, 80% by 13pt, full by 36pt from each edge; **no label glyph clipped at either edge** at 3 and 8 rentals (v7: every visible glyph 10.1–12.7:1 dusk, 14–17.7 night; "Oak Cottage" whole, ending at x 438). At XXL glyphs ≥ 8.0:1 from x 12; the 9pt cut sliver at the edge reads 2.4 and is exempt as the clip, not text. At AX3 the slot widens with the type so names break at words | measured |
| DU8 | Text contrast over the interior | every text pair ≥ 4.5:1, icons ≥ 3:1, sampled against the actual pixels behind (v6 lowest: dusk "Behind by 143h" 5.15, tags 5.51; night tags 6.97) | measured |
| DU9 | One wall across the fold | ΔE76 between the two walls at the fold: mean ≤ 5, max ≤ 10 (v6: dusk 1.5 / 3.2, night 3.4 / 6.1; the critic's ceiling was 15). Far interior wall C* ≤ 15 by day (v6 #B2A595, 10.2) | measured |
| DU10 | Light comes from the door | the brightest wall pixel at y = 60pt sits ≤ 120pt from the fold (v6: 13 dusk, 12 night); `FoldWash` mirrors the door glow ~150pt into the house pane at the same strength | measured |
| DU11 | Night card edge | `duoNightCardEdge` **#3C4675** (dark only, on the work pane in every two-pane and stacked window; light keeps `pageCardEdge`) ≥ 1.9:1 on the night room away from the warm pool (v6: 2.02). Inside the pool the flat token measures 1.75: **accepted MARGINAL**. v7 reached 1.99 there with a leading-edge ramp (#444E80 fading to #3A4778 by 55% of the width; 2.30 lower down), which is not a token: J ships the flat locked token unless Brian adds a second one. The prototype's `#3A4778` is superseded | measured |
| DU15 | Shelf at rest (added 2026-10-25, gate r8) | the shelf snaps to whole items, so no partial glyph shows at either edge at any type size (r8 measured ≥27pt clearance). **"All rentals" is always the first slot and is visible at rest** in every mode and at every type size: snapping must never push it off. A count line sits above the plank in plain SF `.footnote` `textSecondary`, e.g. "3 of 8 rentals" (visible count of total). It is the honest scroll cue; fades, page dots and a trailing "+5" tile are not used. | measured |
| DU16 | Night house-pane wash (gate r8) | the door-side wash must reach into the house pane: at y = 60pt the wall luminance rises toward the fold across at least the last 100pt (v7 ramp 0.0114→0.0171 over x = 400–456 @1x). A flat house-pane wall with the glow confined to the fold band fails. DU11 does not constrain this, because there is no card in the house pane. | measured |
| DU12 | Tab bar | at the right pane's foot (v6 bar top 618pt of 669), never across the fold, never a side rail; glass from the wall behind (cream by day, navy at night); unselected items `textPrimary` at 0.85, selected `action`; selected label ≥ 4.5:1 on its pill (v6 lowest 7.80) | measured |
| DU13 | Stacked fill and rows | the bottom half runs the open card logic: To confirm with **1 row + "See all N"**, then "On the record today"; card-to-bar gap ≤ 20% of the half (v7 `propped`: 36pt = 7.6%). **Relaxed 2026-10-25 from "≥ 3 rows" to the measured frame, by arithmetic:** the half is 463pt; less the bar (≈ 80pt) leaves ≈ 380pt. Three rows plus the header and the foot need ≈ 306pt, and "On the record today" needs ≥ 100pt more: ≈ 406pt against ≈ 380pt, so it does not fit. **"All rentals" when propped:** the same 1 row + "See all N" + "On the record today" (the record card lists every rental's entries), not rows to the bar; the top half shows the skyline (4 houses at 220) | measured |
| DU14 | Step pool (Duo only) | the door's light on the step is a radial with 5 stops and no hard edge, sheared and rotated by the door angle so it lies along the step and path, ≤ 60% opacity (v7 `crop-door-*`: passes by eye; edge not yet measured) | judgment + measured edge |

**[grep]** `toolbarVerticalBehavior(.disabled)` appears only in `Views/Adaptive/`; no hex literal in `Views/Adaptive/` outside `DoorArt` (the art constants, like `HouseTokens`). DU1–DU13 apply to every two-pane and stacked window, iPad included; DU14 is Duo-only.

**Motion.** One named motion, `duoUnfold` (§B.3), on token `duoDoor` (§B.2). Summary: on unfold, the left house's door swings open and the right pane lights from the fold outward, ≤ 0.80s, reversed in 0.50s on fold, a 0.20s crossfade under Reduce Motion; the layout is live and hit-testable from frame 0. It is keyed to `onHingeChange` (`DeviceHinge.status` `.closed` → `.partiallyOpen` or `.fullyOpen`; UIKit `UIHingeInteraction` as the fallback), **never** to a size, arrangement or scene change, so an iPad resize or a Stage Manager window never plays it. Rentals on `started`, `frame70` or `framing` (no door yet) get the light without a door swing. **This amends the Continuity row's "no custom transition on fold" for this hinge-keyed door only**; everything else on fold, unfold and resize is still the system's.

**Asset contract.**

| Asset | Contract |
|---|---|
| Door, `half` (dusk, night) | No video clip. The leaf is **the still's own door pixels** (`craft_half`, 1206px), masked to the door rect **x 627, y 567, w 49, h 145** (px in the 1206 still, scaled by `side / 1206`) and turned live about its left edge. The hall behind it is drawn: dusk a dim hall (`DoorArt.hallDusk` #2A1C12 → #4A3220, plus a lamp glow `DoorArt.warmDusk` #F2B872 at 0.75) whose luma stays **below the facade** (v6: 52 vs 66); night the brightest thing on the house (`DoorArt.warmNight` #FFC877 → 0.78). The step pool per DU14 |
| Door, `complete` (dusk, night) | The same contract; the door rect in `craft_complete` is **not yet measured**: J measures it from the still and adds it to `DoorArt.doorRect(stage:)` before any capture |
| Door, `started` / `frame70` / `framing` | No door entry: `DoorArt.doorRect` returns nil and only the pane light plays |
| A recoloured house (§F.1, later) | The leaf is masked from the recoloured still, so it follows the door colour with no new asset |
| Interior backdrop `duo_interior` | Round-1 A's room, **dusk only** (`interior_dusk.jpg`, 156 KB). Drawn over `CraftPage` at saturation 0.45, `multiply`, opacity 0.42, masked clear for the first 18% from the fold and full by 85%. At night the room is not drawn: the navy page plus one warm pool at the fold. The prototype's `interior_night.jpg` is dropped |
| Shelf `duo_shelf` | Tiled timber, light and dark PNG (≈ 62 KB each), `resizingMode: .tile` |
| Location | `Assets.xcassets/Adaptive/` (package J), not `Craft/` (A's) |
| Budget | Two-pane assets ≤ 0.4 MB total, counted against the app's 14 MB asset limit |

**Shared keys** (table `Shared`, `Sources/Resources/Strings/Shared.xcstrings`, used by the one shared number-block view `HouseNumberBlock` in compact Today, the rental page and the house pane alike; owner A2):

| Key | Line |
|---|---|
| `allRentals.name` | "All rentals" |
| `allRentals.hoursAcross` | "%lld hours across %lld rentals" |
| `allRentals.behind` | "%lld of %lld behind" (the shelf label and, after " · ", the number line) |
| `allRentals.allOnPace` | "All on pace" (shelf) · `allRentals.everyOnPace` "Every rental is on pace." (pace line) |
| `allRentals.tapHouse` | "Tap a house to see its pace." |
| `hero.ofGoal` | "of %lld hours · %@" (one rental) |

**Two-pane keys** (table `Adaptive`, `Sources/Resources/Strings/Adaptive.xcstrings`, the same keys on iPad and the Duo; counts use plural variations; canonical keys from §C.5 are reused, never copied):

| Key | Line |
|---|---|
| `twoPane.shelf.progress` | "%lld of %lldh" |
| `twoPane.list.filterA11y` | "Showing %@. Show all rentals" (the chip's accessibility label) |
| `twoPane.list.moreElsewhere` | "%lld more at other rentals" |
| `twoPane.record.title` | "On the record today" |
| `twoPane.record.empty` | "Nothing logged yet today." (v7) |
| `twoPane.detail.back` | "To confirm" (the back link) |
| reused | `row.action.confirm`, `row.action.notRentalWork`, Today's "To confirm" header and "See all %lld" keys (C), the Log time sheet's "Log %@ at %@" key (E), which takes **the rental shown** (v5 named the wrong rental) |

**Must prove on a real device** (from `duo-critic/verdict.md`, `duo-critic5/verdict.md` and the v4–v6 assumptions). Until each Duo item is captured on a Duo running iOS 27.1 (and each iPad item on the iPad 10th gen, iPadOS 27), package J's work stays **UNPROVEN** and unmerged to a release branch; the simulator cannot unfold, so the frames are off-screen `drawHierarchy` renders.
1. The fold band: `reservedRegions(kind: .division)` frame and margins in both poses; DU1 and DU2 re-measured on it.
2. `onHingeChange` fires on the hinge only: never on a resize, and never on cold launch already open.
3. The real unfold order: when the scene resize lands against the hinge event, and that the first frame at the new size is the door at t = 0 with no flash or jump.
4. Inner safe areas in both poses (assumed top 24, bottom 20 open); the status bar over the house's roof at night ≥ 4.5:1.
5. The size class in the open pose, and that the right-pane `TabView` draws the compact bottom bar with five items; `toolbarVerticalBehavior(.disabled)` holds in both poses.
6. Open landscape survives `Info.plist`'s `~iphone` portrait-only setting (the §1.27 orientation probe).
7. A tap at 0.1s into the door lands on its row; a touch jumps the door to its end.
8. Fold plays the 0.50s reverse and the outer display shows the closed layout with no stale frame.
9. Reduce Motion gives the 0.20s crossfade and no leaf turn.
10. Instruments: 0 hitches over the unfold with 8 rentals; memory flat after 10 unfold/fold cycles.
11. The night pool edge (DU11) and the dusk step pool (DU14) on the device panel.
12. **The right-pane bar on iPad, on iPadOS 18, 26 and 27:** the one child `UIHostingController` with `traitOverrides.horizontalSizeClass = .compact` makes the system draw its compact bottom bar at the right pane's foot, with five items, the Inbox badge and the Log time revert; `.tabBarOnly` shows no sidebar toggle. **J2's iPad half is blocked until this passes**; an OS where it fails ships the system's own iPad bar over the right pane, never a custom bar; the mode switch at 800/808 (and 645/653) in Stage Manager loses nothing (tab, path, drafts), including the late flip 0.3 s after a resize stops between 800 and 808.
13. iPad: the window controls clear the house pane's top leading in a Stage Manager window.
14. **Brian's gut check** of the first in-app door on a device or a short clip, before any polish round (the owner's-eye rule).
15. Which side `ArrangementView` renders its primary on, in both poses: the house must be leading and on top.
16. The mode settles the same at 799/800 and 644/645 whichever side it is reached from, after a live resize, a scene connect and a cold launch.

---


#### What changed from the 2026-10-23 adaptive rules

| # | 2026-10-23 rule | Now | Why |
|---|---|---|---|
| AD1 | Bands A < 600, B 600–899, C ≥ 900; two columns iff band C and `Wc ≥ 744` | Two modes: compact (W < 800 or H < 645, with the old A/B split inside it) and two-pane (W ≥ 800 and H ≥ 645, or a vertical Duo division leaving panes ≥ 380); stacked for a horizontal division. Hysteresis only during a live resize, 800–808 / 645–653; re-resolved with no history when the resize settles and at scene connect (**decided 2026-10-25**, review F2, F3) | One rule for all three device families; the Duo proved 463pt panes work; no path-dependent mode for the 11" 2/3 tile |
| AD2 | `Wc = W − sidebar − 48`; sidebar 280 docked in landscape | Removed: no sidebar, so `W` alone decides | No three-column layout |
| AD3 | `.tabViewStyle(.sidebarAdaptable)`; `TabSection("Your rentals")` of per-rental tabs with `.tabPlacement(.sidebarOnly)`; Settings at the sidebar foot | `.tabBarOnly`, the bottom bar at the right pane's foot; the shelf replaces the per-rental tabs; Settings from Today's gear in every mode | Same bar placement as the open Duo; the shelf already switches rentals (**decided 2026-10-24**, Brian) |
| AD4 | `tabViewSidebarHeader` = the house-only thumbnail at 120 (§H.1 H6, §H.5) | Removed; the thumbnail stays for the rentals list and widgets | No sidebar |
| AD5 | Bar and sidebar capped at xxxLarge (`ShellChromeLimits`, `ReaderTypeSize`, the `§1.27-sidebar-clamp` code) | **Decided 2026-10-25: removed.** The cap existed only because the sidebar broke words at AX; the system tab bar handles Dynamic Type itself (large content viewer). A2 deletes both modifiers | No sidebar, so no cap |
| AD6 | Regular width: toolbar `.primaryAction` "+" on every root; the sidebar hides the fifth tab | The fifth "Log time" tab in every mode, plus ⌘N | One create action everywhere |
| AD7 | Inbox and Rentals in `NavigationSplitView` (list 320) in band C | The list is the right pane; detail opens in the same pane with a back link | Detail in-pane over the interior, as on the Duo |
| AD8 | Today, two columns: left chip + hero (390) + number + pace; right To confirm | Left: hero + number + pace + **shelf** (no chip); right: To confirm + On the record today | The locked Duo layout |
| AD9 | Records: a `Table` when `Wc ≥ 720`, rows 70, an `.inspector` (280) for the record | The `LHRow.Browse` list in every mode; the record opens in the pane (no pane reaches 720) | One row grammar; the `Table` and inspector are retired (**decided 2026-10-24**) |
| AD10 | Decisions with a pinned `.primary` (Log time) are sheets in every band | Sheets in compact; in the right pane in two-pane and stacked | The locked Duo layout |
| AD11 | Hero: bands B/C a fixed 390 frame; Duo open one column, frame 390 | By mode (table above): 290 on the Duo, `clamp(0.626 × pane, 290, 390)` on iPad, 220 stacked | Panes are narrower than a column |
| AD12 | Rows visible: 13" landscape ≥ 8 in Today's right column; Duo landscape ≥ 6 | DU4 per right pane; Inbox and Records ≥ 7 on iPad | — |
| AD13 | Continuity: no custom transition on fold or resize | Amended for the hinge-keyed door only (`duoUnfold`) | The locked door |
| AD14 | Hardware: "SwiftUI has no `onHingeChange`" | Corrected: `onHingeChange(isEnabled:_:)` exists (SwiftUICore swiftinterface 16741–16772); `UIHingeInteraction` is the fallback | Read in `duo-concept-v2` |
| AD15 | Regular-width tint #4774C6 in dark (white on the sidebar selection) | `colors.action` in every mode; #4774C6 retired with the sidebar | No sidebar selection (**decided 2026-10-24**) |
| AD16 | Dynamic Type: two columns collapse to one at AX1+ | Two-pane holds at AX; each pane takes the phone's AX rules | Each pane is phone-width |
| AD17 | §1.25: "no `UITabBar` appearance hacks" | One allowed line: `unselectedItemTintColor` = house ink, in every mode | The locked bar (v6 #4) |
| AD18 | (new) | **"All rentals" hero = the skyline** of each rental's own house at its own stage, cap 5 (4 under a 290 frame), most-behind first over the cap; no aggregate stage, no goal (§H.1 H10) (**decided 2026-10-25**) | H10 contradicted itself; the v7 frame showed a finished house at 312h |
| AD19 | (new) | The shelf selects the hero, the number block, Today's To confirm filter and the Rentals page only; Inbox and Records are never filtered by it, in any mode (**decided 2026-10-25**) | The same tab behaves the same in every mode |
| AD20 | (new) | The right-pane bar uses one child `UIHostingController` with `traitOverrides.horizontalSizeClass = .compact`, proven on iPadOS 18, 26 and 27; fallback the system's own iPad bar, never custom (**decided 2026-10-25**) | A SwiftUI environment override is not documented to change the bar; v7 forced compact on the whole off-screen window |
| AD21 | Stacked: ≥ 3 To confirm rows | 1 row + "See all N" + On the record today, gap ≤ 20%, "All rentals" included (**relaxed 2026-10-25** to the v7 frame) | ≈ 380pt free in the half against ≈ 406pt for 3 rows + header + foot + On the record |

---

## 2. Density rules

Default Dynamic Type, 402×874pt, light and dark, unless stated. The builder reports these numbers before hand-off; the gate re-measures (§5).

| # | Rule | Number | Kind |
|---|---|---|---|
| D1 | Actionable row height, divider to divider | 56–88; target 64 | measured |
| D2 | One list item's share of viewport | ≤ 12% default; ≤ 45% at AX3 (a two-line row at AX3 cannot meet 30%; mockup review 2026-10-23) | measured |
| D3 | List tab (Inbox, Records, Properties) with ≥ 5 items present: complete rows visible under the title, above the tab bar | ≥ 5 at default, ≥ 4 at XXL | measured |
| D3b | Today above the fold **at default size only** | **v2:** rental chip + hero (H1) + number block + pace sentence + "To confirm · N" + 2 rows + the "See all" foot, all above the tab bar's top edge. At XXL, 1 row. **When the window is under 700pt tall (SE, Duo closed): 1 row** (§H.8). **Features are never dropped to fit; the hero shrinks first** (H3), then row text wraps. Pace tiles and "This week" are not on Today (they are on the rental page and in Reports). | measured |
| D3c | Today at AX1–AX5 | **v2 (amended by Brian's decision):** the hero holds at the H3 size (frame 295 on 402, art 24–32% of the viewport), numerals 54, chip above the frame; chip + hero + number + pace sentence are above the tab bar and the rows scroll beneath. The art is never hidden. | measured |
| D4 | Empty bands inside a card: pixel rows within the card inset 16 that are all card background (ΔE ≤ 3), as share of card height | ≤ 35%. Applies to `LHCard.*` and the hero. Grouped value-row containers (Settings-style `LHRow.Value`/`LHRow.Toggle` groups, as in Settings, Log time and the confirm sheet) are exempt: their padding is the row rhythm, and Settings itself would fail | measured |
| D5 | Primary actions per card; actions in a row | 1 per card; rows: one leading control, no pills | grep |
| D6 | Non-hero card viewport share | ≤ 20%. **v2: the hero is not a card and is excluded from D6; it is measured by H2 (36–46% at default) and H3 (24–32% at AX).** `frame_check.py density` must stop treating the hero frame as a card (tool spec in `scripts/qa/NOTES-standard-v2.md`). | measured |
| D7 | Text lines per row | ≤ 3 (title ≤ 2, meta 1) | measured |
| D8 | Buttons per screen | 1 `.primary`; ≤ 2 `.secondary` visible | grep |
| D9 | Gutter / card padding / section gap | 20 / 16 / 24, ±1 | measured |
| D10 | Radii on one screen | ⊆ {6, 12, 16, 20, capsule} | grep |

Dynamic Type (XXL and AX3 frames required):
- Rows grow and reflow: at AX sizes `LHRow.Action` stacks (control + title; meta below; hours after the meta).
- `lineLimit(nil)` and `fixedSize(horizontal: false, vertical: true)` at AX **[grep]**.
- `minimumScaleFactor` ≥ 0.8, never on `.body` **[grep]**.
- `.dynamicTypeSize(` clamps only on the hero numeral, the house art frame and the rental chip **[grep: ≤ 3 sites]** (§H.1 H9).

---

## 3. The To confirm item, redesigned

Three items at default, 402pt:

```
TO CONFIRM  (3)                                             See all
┌────────────────────────────────────────────────────────────────┐
│  Today                                                         │  ← day header, 28pt
│  ◯   Plumber at Pine Cabin                                2h   │
│      ▦ Calendar · 12–2 · [Repairs]                             │
│                                                                │
│  Thu Oct 8                                                     │
│  ◯   Making monthly mortgage payment                       —   │
│      ☑ Reminder · [Needs hours]                                │
│     ─────────────────────────────────────────────────────────  │
│  ◯   Showing at Oak Street                              1h 30m │
│      ▦ Calendar · 9–10:30 · [Not sure]                         │
│     ─────────────────────────────────────────────────────────  │
│                      Confirm 1 likely                          │  ← when N ≥ 2; here N = 1 so hidden
└────────────────────────────────────────────────────────────────┘
```

(▦ `calendar`, ☑ `checklist`; `[ ]` an `LHTag`; ◯ the 22pt leading control in a 44 frame. Dates live in the day headers (§1.15a), so the meta line is source · time · tag. Row 2 wraps to 86pt because its title is 282pt wide. In this sample only row 1 is quick-loggable and likely, so the foot is hidden; with two such rows it reads "Confirm 2 likely", and if the section overflowed the viewport it would pin above the tab bar instead (§1.3b).)

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
| House hero | `House/HouseHeroView.swift` | **Redesign (v2):** the card hero is deleted; `CraftHouseView` on the page replaces it (§H.1, §H.8). No compact variant: the art holds at 28% at AX (H3). |
| Tab bar | `ContentView.swift` | **Redesign (moved from Drift, 2026-10-23):** custom floating bar with its own material and a detached "+" circle → native `TabView` with system Liquid Glass, `.tabBarMinimizeBehavior(.onScrollDown)`, "Log time" as the fifth tab (§1.25, §H.7). `LHIcon` custom tab shapes retire. |

### Standard

`LHToast`, `BPEmptyState`, `BPFilterChip` (→ `LHChip` at 34), `CategoryToolTile` as a component.

### Delete

`TasksView.swift`, `CategoryManagementView.swift` (unreachable, Lucide, `Color(hex: category.colorHex)`), `EntryListRow` (`DashboardView:957`), `lhSurfaceCard`, `LHSuccessToast`, `LHIconTile`, Lucide `CelebrationType`, the `lucide-icons-swift` package, `TodaySwipeRow`, `TodaySwipeHint`.

### Consistency inventory

Every touched screen is labelled **new-system**, **recoloured-legacy** or **untouched**, literally. The v2 inventory of every screen, with its label, its v2 changes, its order and its build package, is `docs/design/v2-revamp-plan.md`. As of 2026-10-24 nothing shipped is new-system; every shipped screen is recoloured-legacy or untouched.

---

## 5. Gate rubric addendum

Builder runs these and puts the numbers in the hand-off; the gate re-measures and confirms. A measurable defect the builder could have caught is a process failure.

### 5.1 Density (PIL) — `scripts/density_gate.py <frame.png> --rows <ids>`

1. Item share = item bbox height ÷ frame height (D2). 2. Items above the fold = complete row boxes between the title's bottom and the tab bar's top, found by divider runs (`border`-coloured pixels ≥ 60% of card width) or XCUITest element bounds (D3/D3b/D3c). 3. Empty bands (D4), skipping exempt value-row groups. 4. Row height between dividers (D1); a card's foot action ("Confirm N likely", `today.confirm.batch`) is not a row and is excluded from D1 and from the D3 row count, identified by its accessibility identifier or by having no divider above it. 5. Gutter = frame edge to first non-canvas pixel in the content column (D9). 6. Contrast ≥ 4.5:1 on every text pair including placeholders, disabled, secondary and tag ink on wash; on hero frames each pair is sampled against the gradient step behind it and the ink must be one of the §H.4 page inks. 7. No two differently named state frames byte-identical. **8. Hero (v2):** the house art bbox share of the viewport from the still's alpha at the known placement, never a non-page pixel count (H2 36–46% default, H3 24–32% AX); the frame side derived from the art's width and the stage scale (H1), with the ground line checked on assets only; no closed edge rectangle around the art (not in a card); art p99 contrast vs the page ≥ 3.0 lit, and unlit night PASS ≥ 2.55 / MARGINAL 2.40–2.55 / BLOCKED < 2.40, plus the mean-luma lift ≥ +5 (§H.2); the number block overlaps the frame bottom by 44pt at default and the chip, dots and number never intersect the art's bbox except that overlap; lit and unlit frames of one state differ; the `-unlit` frame is darker in the window region. 9. Assets: `asset_check.py` (§H.3 budget and integrity). 10. Motion capture: ≥ 24 consecutive changed frames in the lot region during the drop, no hard cuts outside the crossfade windows (§H.6).

### 5.2 Component conformance

**[grep]** Every row, card, tag, chip, button, header, field, segmented control, stepper, empty state, toast, sheet and alert in the diff is a §1 component by name, listed in the hand-off. Zero new `.system(size:)`, `Color(hex:)`, `Image("bp_tool_`, `Lucide`, emoji, `.fontWeight` on symbols outside `LHButton.icon`, or `.dynamicTypeSize(` outside the three sites (§H.1 H9). Radii ∈ D10. `CategoryToolTile(size:)` ∈ {36, 56} and never in `Inbox/` or `Today/` rows. Navigation (§1.25): the root is a `TabView` with `.tabBarMinimizeBehavior(.onScrollDown)`; no view named `*TabBar*`, no reserved bottom padding ≥ 60 at a tab root, five `Tab`s with one `role: .search` "Log time" carrying an `accessibilityLabel` and no `plus` glass button, one `.badge(` on the Inbox tab, no `.ultraThinMaterial`/`.thinMaterial` on bar-shaped views, and glass text contrast ≥ 4.5:1 in the frames with the diorama scrolled under the bar. Shell changes carry captures on iOS 18, 26 and 27. Frames at default, XXL, AX3, light and dark; no clipping, no mid-word break, no truncation at AX.

### 5.3 Motion conformance

Hand-off names the §B motion for each animated change and its token. **[grep]** every spring is `.spring(duration:bounce:)` with duration ≤ 0.30 (signature tokens ≤ 0.60) and `bounce` > 0 only inside a gesture `onEnded`/`swipeActions` commit path; every `withAnimation`/`.animation` is bound to a state `value:` or a gesture; `.onAppear { withAnimation` only in `emptyStateEntrance` and the milestone; `repeatForever` only in `scanningLine`; every `.sensoryFeedback(trigger:)` trigger is the same `@State` that an `.animation(value:)` watches; no haptic or trigger increment inside `asyncAfter`.

### 5.4 Copy conformance

Copy gate + §C: **[grep over `Localizable.xcstrings`]** banned words absent; per-screen average ≤ 14 words per sentence, hard max 22 (`scripts/copy_gate.py --screen <prefix>`); canonical ideas use their canonical key (§C.5). **[judgment]** read-aloud test by the assessor as the named persona.

### 5.5 Anchor question **[judgment]**

The gate puts the frame beside the anchor (Copilot, Reminders, Things, Fitness, Apple Settings for lists and forms; **Opal, (Not Boring) Weather and Tolan for the hero screens**, §H) and writes the answer to: "Would this sit next to the anchor app without looking like the hobby version?" For the hero the question is sharper: "Is this a lit object someone keeps, or a toy on a background?" Passing numbers with a "no" here is MARGINAL and goes to Brian with both frames.

---

## F. Future extensions (designed for, not built)

Brian, 2026-10-24: v2 must take two later features without a redesign. Neither is built in the v2 revamp. The rules below fix the contracts (naming, layers, budgets, guard rails) so the house art, the data model and the hero component are built once. Backlog items: `docs/design/v2-revamp-plan.md` §6.

### F.1 A house of their own: per-rental customisation

What the user will change: roof colour or material, siding colour, trim colour, door colour; later, a small set of house styles. Brian already asked for "roof colour per house".

**What stays fixed, for the brand [grep + judgment]:** the lighting rig (H.2), the camera and the frame (H.3 integrity checks), the lot (lawn, loam, path, slab, tree, shrubs), the window glow and the spill colour `#E9A558`, and **the timber framing stages** (`started`, `frame70`, `framing` and the drop clip). Timber is timber: the framing is identical for every rental, which also keeps one drop clip. Identity before the roof goes on is the rental's name in the chip. Only `half` and `complete` carry slots.

**Slots:** `roof`, `siding`, `trim`, `door`. Four, no more. Windows, gutters, chimney and porch are not slots.

**Approach, compared:**

| | A · pre-rendered variants | B · neutral base + per-slot masks, recoloured at runtime | C · pre-rendered material variants |
|---|---|---|---|
| What ships | one still per combination | one neutral still per state + one mask pack per stage | one still set per material |
| Count for 6 roof × 8 siding × 3 trim × 4 door | 576 × 2 stages × lit/unlit × dusk/night = **4,608 stills** | 20 stills + **2 mask packs** (+2 for thumbnails) | 20 stills × materials |
| Size | impossible | +0.6 MB | +10 MB per material |
| Render time | weeks | none per swatch | one full pass per material |
| Can change | colour only | colour only | texture and geometry (tile → metal roof) |
| Runtime cost | 0 | one Core Image composite per (rental, stage, lit, appearance), cached | 0 |

**Recommendation: B for colour, now; C only for roof material, later, capped at 3 materials.** B keeps the lighting baked and the brand fixed, costs nothing per swatch, and the whole swatch matrix can be checked offline with the same maths.

**Pipeline contract for B [measured]:**
- Blender renders `half` and `complete` (lit, unlit, dusk, night) with the four slot materials set to a **neutral albedo** (linear 0.5 grey, each slot's own roughness and normal map). These are the shipped stills from the day customisation lands; until then the stills carry the default swatches baked in. **Mask packs and neutral renders live in `design/blueprint-house/` only and never enter the app bundle before §F.1 is built** (`asset_check.py` FAILs on any `craft_slots_*` in the catalog, §H.3).
- A **mask pack** per stage, `craft_slots_<stage>` (half, complete), one RGBA PNG at 1206²: R = roof, G = siding, B = trim, A = door coverage, antialiased, from a material-index pass (`craft3.py` has no material-index AOV today; the spike below adds it). Thumbnails get `craft_thumb_slots_<stage>` at 360px. Masks depend only on geometry and camera, so they are shared across lit/unlit/dusk/night.
- Composite, in linear light: `out = base × Π_slots (1 + mask_s × (swatch_s / 0.5 − 1))`, Core Image (`CIBlendWithMask` × 4 over `CIColorMatrix`), rendered once per (rental, stage, lit, appearance) into a cached image (memory ≤ 4 composites at 5.8 MB; disk cache in `Caches/` keyed by swatch set + asset version). Budget ≤ 40 ms per composite on an A15; a cache hit is free. The widget reads the same cache through the app group.
- The window glow and the lawn spill are part of the base and are not multiplied (they sit outside every mask), so a dark siding still shows warm windows.

**Palette guard rails [measured, `scripts/qa/swatch_matrix.py`, spec in `scripts/qa/NOTES-standard-v2.md`]:** swatches only, named, never a colour picker or a hex field. Per slot: roof S ≤ 0.70, V 0.20–0.80; siding S ≤ 0.50, V 0.30–0.96; trim S ≤ 0.65; door S ≤ 0.70, V 0.12–0.80; no hue in 252–300 (violet is retired); ≤ 8 swatches per slot. Every roof/siding pair keeps a relative-luminance ratio ≥ 1.3:1 either way so the silhouette reads (navy siding `#2F3E5C` with a charcoal roof `#2B2F38` is 1.26 and is therefore not offered together). Every allowed combination passes the H.2 night readability bar (unlit p99 PASS ≥ 2.55, lift ≥ +5) and the 400px read before a swatch ships. **Proposed set, unchecked** (no neutral base, mask pass or `swatch_matrix.py` exists yet): roof {Terracotta `#C8553D` default, Slate `#4A5560`, Charcoal `#2B2F38`, Cedar `#8A5A3C`, Moss `#55684A`, Clay `#9E4B3B`}; siding {Cream `#F1E9DA` default, Chalk `#EDEDE6`, Sage `#9AA88F`, Dove `#B8BCC2`, Harbour `#5C7A96`, Navy `#2F3E5C`, Barn `#8E3B32`}; trim {Timber `#A98666` default (one shade darker than the framing pine, §H.2), White `#F3F1EA`, Charcoal `#2B2F38`}; door {Blueprint `#3A4A6E` default, Terracotta `#C8553D`, Sage `#5F7A5A`, Black `#1E2024`}.

**Required spike before any customisation build [measured + judgment].** Multiplying a grey render to recolour it is the riskiest assumption here and is unproven. Before F1-a (data model) or any picker work, one spike must pass: (1) **a neutral render** of `half` and `complete`, lit and unlit, dusk and night, with the four slots at linear 0.5 grey; (2) **a mask pass**: a material-index AOV added to `craft3.py` and the two `craft_slots_<stage>` packs, edge-checked at 3x; (3) **a swatch check on 6 swatches** composited with the formula above in Python: siding Navy `#2F3E5C` and Barn `#8E3B32`, roof Charcoal `#2B2F38` and Slate `#4A5560`, door Black `#1E2024`, plus the default set as the control. Each is judged **beside the locked art** (`dir-craft-final3/frames`) by a fresh reviewer at full size and at 400px, and measured: unlit night p99 and lift (§H.2), 8-bit banding in the dark slots after the HEIC pass (night values already sit at V ≤ 0.28), and whether the baked grey bounce light reads wrong next to a coloured wall. The default-swatch composite must match the shipped still within mean ΔE 2. If the spike fails, §F.1 falls back to approach C for the one slot that failed, or that swatch is not offered.

**Where it lives in the UI (not built):** the rental edit sheet gets one `LHRow.Value` "House" that opens a sheet with four swatch rows (44pt `LHChip` swatches, `tileFocus` on select) above a live 300pt preview using the same composite; saving updates the Today hero with `stageFade`. Data: `RentalProperty.houseLook: HouseLook { roof, siding, trim, door, style }`, swatch **names** not hex, default `.standard`, synced with the rental.

**Styles later:** the current names are the implicit default style. A second style ships as `craft_<style>_<stage>`, `craft_<style>_<stage>-unlit`, `craft_<style>_build_<light|dark>.mov`, `craft_<style>_slots_<stage>`, with all five stages, both appearances, both window states and its own drop clip, or it does not ship. Styles are brand-authored (≤ 3), never user-generated.

### F.2 The ambient layer: life around the house

Earlier decisions kept: vehicles now, people later (a contractor van after a repair, the guest car leaving at a turnover); each scene plays once and lasts ≤ 3.6 s; no looping gimmicks; one moment at a time; never on top of the timber drop. **Changed:** "the sky follows the time of day" is retired, because the rig has one dusk and one night exposure and the appearance already follows the user's clock (H.2). Clouds are therefore static or absent, never a scene.

**Z-layers inside the hero frame (back to front), [grep: one `ZStack` in `CraftHouseView`, layers in this order]:**

| Z | Layer | Owner |
|---|---|---|
| Z0 | page gradient (`CraftPage`) | page |
| Z1 | night backlight | hero |
| Z2 | spill pool + contact shadow | hero |
| **Z3** | **sky band**: ambient *behind* the lot (birds, balloons; clouds only if ever rendered into the still) | ambient |
| Z4 | the house still, the drop clip, the F.1 composite | hero |
| **Z5** | **street band**: ambient *in front of* the lot (van, guest car, people) | ambient |
| Z6 | chip, page dots, toast | page |

**Regions are relative to the hero frame, never a fixed 390pt frame [measured: bbox intersection with every keep-out = 0 on every captured frame, at every hero size].** The bands are fractions of the frame side, as placed on screen: sky band y 0.00–0.62, behind the house (occlusion is natural); street band, the lot's front-right corner, x 0.66–0.94, y 0.76–0.90; people on the porch path x 0.40–0.60, y 0.70–0.86. **Keep-outs are in points from the live layout, not fractions:** the number block (numeral bbox + "of N hours" + the pace sentence) grown by 8pt, the chip grown by 8pt, the page dots grown by 8pt, and the bottom 10% of the frame. A band's usable area is the band minus the keep-outs. At SE (frame 297) the 44pt overlap puts the numeral top at y 0.85 of the frame, inside the street band's x 0.66–0.69, so the usable street band there starts right of the numeral's box; Duo closed (287, numeral 64) is computed the same way. If a size leaves the usable street band narrower than 0.20 × side, street scenes do not play at that size. The `ambient_check.py` capture set includes SE and Duo closed.

**Entry and exit:** vehicles enter and leave through the **right frame edge only**, along the lot's front edge, stopping at the kerb. Sky elements enter at the left or right edge inside the sky band and leave by the far edge or the top. Nothing appears or vanishes mid-frame; opacity changes only within 24pt of an edge and last ≤ 0.30 s. People enter from the vehicle or the right edge and leave the same way.

**Scale, against the `craft_complete` house (footprint ≈ 0.60 of the frame width, height ≈ 0.50) [measured on the sprite's bbox]:** van 0.45–0.55 of the house width; car 0.40–0.48; a person 0.22–0.26 of the house height; a balloon cluster ≤ 0.15 of the frame height; birds 8–14pt each, 3–5 per flock; a cloud ≤ 0.35 of the frame width at ≤ 0.6 opacity dusk, ≤ 0.35 night.

**Lighting match [measured]:** every ambient asset is rendered through the same camera and rig, in both exposures (dusk, night); its ground shadow direction is within ±10° of the house's; its mean luminance is within ±15% of the lit siding at the same stage and appearance; S ≤ 0.55. Vehicles carry no headlights, no beacons; people carry no faces at this scale.

**Triggers, real events only [grep: trigger bound to the entry id; no timers]:**

| Scene | Fires when | Then |
|---|---|---|
| `contractorVan` | Repairs or Maintenance logged or confirmed for the shown rental, while Today is visible | arrives (≤ 0.6), idles (≤ 2.4), engine-off settle (≤ 0.6); stays parked as a still until Today disappears. While it is parked it **occupies the street band**: no other street scene plays (a `guestCarLeaves` trigger is skipped, not queued) |
| `guestCarLeaves` | Turnover or Cleaning logged | starts parked, pulls away right; nothing remains |
| `visitorAtDoor` (people, later) | Showing or tenant meeting logged | walks to the door, pauses, leaves |
| `balloons` | goal reached (750, or the chosen goal) | one release from the porch, exits the top; plays once per goal per year, after `houseStageAdvance` |
| windows on | first log of the day | H.6; not a scene, always first |

**Order and caps [grep + measured]:** drop → windows → scene, never overlapping, and no scene starts within 0.5 s of the clip's end. One scene at a time; **the street band holds one occupant at a time** (a parked prop counts); ≤ 1 per entry (keyed by id in `TodayScenePlayed`); ≤ 3 per Today appearance; ≤ 6 per day; ≥ 20 s between scenes; a batch confirm plays at most one (the newest matching entry). Skipped, never queued, under the §B.4 conditions (Reduce Motion, Low Power, inactive, a sheet or alert up, hero < 50% visible, VoiceOver, a milestone playing). Total ≤ 3.6 s: enter ≤ 0.6, hold ≤ 2.4, exit ≤ 0.6. Reduce Motion: the still prop fades in over 0.30 and stays; no path.

**Rendering approach, compared:**

| | Blender rig clips (HEVC alpha) | Stills from the rig + SwiftUI transform | SwiftUI-drawn shapes |
|---|---|---|---|
| Matches the lighting | yes, by construction | yes for the sprite, no self-motion (wheels, walk) | no |
| Size per scene, both appearances | ≤ 2.4 MB (two sub-frame clips 1206 × ≤ 480px, ≤ 108 frames) | ≤ 0.2 MB | 0 |
| Fit | vehicles, people | birds, balloons, clouds | nothing in this system |

**Recommendation: rig clips for the street band, rig stills moved by SwiftUI (translation and opacity only, one `drawingGroup`) for the sky band, nothing hand-drawn.** Budget ≤ 8 MB for the whole ambient set in 2.x, ≤ 6 scenes. The camera and the lot's ground plane are frozen in `design/blueprint-house/scenes/camera.json` so every clip composites at the frame origin with no per-device offset; ambient clips never include the house, so F.1 recolours never invalidate them. Tests: bbox rules above, durations, no overlap, no scene inside the drop window, Instruments hitches = 0 over a 5-scene session.

---

## A. Brand personality

The house is the brand: progress you can see, numbers you can stand behind. The app sounds like the person who built it.

| Trait | What it is | What it is not |
|---|---|---|
| **A calm friend who knows the rules** | One plain sentence per number; points to your CPA for the verdict; never raises its voice. "206 of 750. Your CPA decides what that means." | Not a lawyer (no disclaimer per line), not a cheerleader (no "Amazing!", no streak guilt), not an advisor. |
| **A good contractor** | Says what was done, with the count. Shows the work: every hour has a date and a source. | Not a salesman: never "powerful", "seamless", "effortless"; never a number behind a metaphor. |
| **Honest about uncertainty** | "Not sure" is a tag, not a failure. Nothing counts until you confirm it. Hatched parts are drawn, not built. | Never claims an unconfirmed hour; never "qualified", "audit-ready", "proof". |
| **Quietly crafted** | A small lit house on a page with a time of day; timber that drops once; windows that come on when you worked. Motion shows cause and effect, then stops. | Not playful for its own sake: no confetti outside the three milestones, no mascots, no idle motion, no load-in choreography, no kitsch on the lot (§H.2). |

Test **[judgment]**: would the contractor who built the house say this in the doorway, in under ten words?

---

## B. Motion language

### B.1 Purpose and rules

Motion is for three things: cause and effect (you pressed it, it moved), progress (the number counts, the house rises), confirmation (one beat that says saved, then stillness).

Rules, all **[grep]** unless marked:
- Springs are written `.spring(duration:bounce:)` (available on every OS we ship; minimum iOS 18). A single animation ≤ 0.30s; a two-step sequence ≤ 0.40s total; the signature tokens (`stage`, `ringProgress`, `count`) ≤ 0.60s (`rentalSlide` is 0.30 since v2 r2, inside the normal cap). **One exception (v2): `timberDrop` is a pre-rendered 2.0 s clip** (§H.6); it is not a SwiftUI animation, plays at most once per stage per rental, and was the only motion in the app longer than 0.60 s. **Second exception (2026-10-24): `duoUnfold` ≤ 0.80 s** (§1.27 "Duo open"), keyed to the hinge only, hit-testable from frame 0, a touch jumps it to the end.
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
| `windows` | `.easeInOut(0.40)` (linear under Reduce Motion) — the windows and the spill pool only | new (v2) |
| `stageFade` | `.easeOut(0.25)` with scale 0.97 → 1 — a stage change without a clip | new (v2) |
| `rentalSlide` | `.spring(duration: 0.30, bounce: 0)` — the diorama sliding on a rental switch (0.45 in r1 broke the 0.30 spring cap) | new (v2) |
| `duoDoor` | a 0.80 s door clock `t` 0 → 1 (`.linear(duration: 0.80)`; 0.50 s 1 → 0 on fold); each layer is an ease-out cubic of `t` over its own window — the Duo unfold only | new (2026-10-24) |

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
| `heroCountUp` | hours value changes while Today is visible, never on appear | digits roll with `numericText` (0.40); if the stage changes, `stageFade` or `timberDrop` carries the art | `count` | none (the row's `.success` already fired) | digits jump; art crossfades 0.15 |
| `timberDrop` (v2, replaces `buildStep`) | a log or confirm carries the shown rental from `frame70` to `framing` while Today is visible (signature; the brand's own move) | the 39-piece framing clip fades in over the still (0.20), plays 2.0 s, crossfades to `craft_framing` (0.30); the number rolls as the last timber lands. Bound to the stage `value:`; never on appear; one-shot. When the same log crosses a milestone, the drop is the first move of `houseStageAdvance` (§B.3), so it never plays twice and nothing plays on top of it. | clip + `stageFade` | `.impact(flexibility: .rigid, intensity: 0.8)` once, as the last timber lands; the row's `.success` is the only other haptic | no clip: the still crossfades 0.15; the knock is kept |
| `windowsOn` (v2) | the first log or confirm of the day for the shown rental | windows held dark through any drop, then the lit still fades over the unlit one (0.40); the spill pool fades with it | `windows` | none | linear 0.40 |
| `stageFade` (v2) | any other stage change | crossfade 0.25 with scale 0.97 → 1 | `stageFade` | none | crossfade 0.15 |
| `rentalSlide` (v2) | the rental chip or a swipe on the house changes the rental | the diorama slides in from the trailing edge (leading when going back) with opacity; the number rolls | `rentalSlide`, `count` | `.selection` | 0.20 fade |
| `duoUnfold` (2026-10-24) | `onHingeChange`: `.closed` → `.partiallyOpen` / `.fullyOpen` on the iPhone Duo (never a resize, an arrangement change or cold launch; an iPad never plays it) | **door:** on `half` and `complete` the left house's leaf turns 0 → 78° about its hinge edge in perspective (`rotation3DEffect`, perspective 2.2), darkening by 0.12 with a 0.35 shadow, over `t` 0–0.42; the hall and step light rise over `t` 0.05–0.50. **Pane:** the right pane's dark veil wipes away from the fold outward over `t` 0.12–0.76, then the door's warm pool stays behind the cards. Total ≤ 0.80 s; on fold the same clock runs back in 0.50 s. Overlays are `allowsHitTesting(false)`; the layout is live from frame 0 and a touch sets `t` = 1. Framing stages (`started`, `frame70`, `framing`) play the pane light only | `duoDoor` | none | a 0.20 s crossfade from the closed state to the lit end state; no leaf turn, no wipe |
| `houseStageAdvance` | hours cross 100 / 500 / 750 (signature) | the house's own moves first: the stage change (`timberDrop` when it ends at `framing`, else `stageFade`, §H.6), then `windowsOn` if it was the first log of the day; then **one milestone beat**: a single confetti burst in the house palette (timber `#A98666`, terracotta, cream; ≤ 24 pieces, no streamers, stars or glitter) falling once from above the frame behind the chip, ≤ 0.60, never over the number; the Fraunces display line ("500 hours.") fades in with it. No sign, no words in the scene, no linework (§H.2). | `stageFade` / clip, `windows`, `reveal` | `.success` once at the beat | no confetti; the still crossfades 0.15, the line fades in |
| `toastIn` / `toastOut` | toast shown / dismissed | in: y +24 → 0 with opacity (0.22); out: opacity → 0, y 0 → +12 (0.15); swipe-down follows the finger then `settle` | `reveal` / `quick` | `.success` saves, `.error` failures, none info | opacity only |
| `sheetUnfold` | section expands inside a sheet | height with content fade (0.30); ≤ 4 rows stagger at 30ms | `flow`, `reveal` | none | fade 0.2, no stagger |
| `buttonStateChange` | Confirm → Logged, Save → Saved | label crossfade with 2pt blur (0.22) | `reveal` | carried by the event | crossfade, no blur |
| `errorShake` | save failed, invalid field | x 0 → 8 → −6 → 4 → 0 over 0.28; stroke → `destructive` (0.15) | keyframes, `quick` | `.error` | stroke colour only |
| `pullToRefresh` | Inbox / Records pulled | system `refreshable`; `DraftingLoader` line draws once per cycle | linear | `.success` only if something new | same |
| `emptyStateEntrance` | empty state replaces a list | glyph, headline, body fade and rise 8pt, 40ms apart (≤ 0.30 total) | `reveal` | none | fade only |
| `scanningLine` | "Looking through your calendar" | line draws across; cycle ≥ 1.6s | linear | none | static dashed line |
| `fieldFocus` | `LHField` focused | stroke `border` → `action` (0.15) | `quick` | none | same |

### B.4 Ambient scenes on the hero (v2: designed in §F.2, not built)

Brian's pick (2026-10-23): "your work shows up" scenes on the hero: a **van** parked by the house after Repairs; a **guest car** leaving after a Turnover or Cleaning; a **person at the door** after a Showing or a tenant meeting (later). **The time-of-day sky is retired in v2**: the rig has one dusk and one night exposure and the appearance follows the user's clock (§H.2). The rules below stand and §F.2 adds the z-layers, regions, scale, lighting match, triggers, caps and the rendering contract. Nothing in this section ships in the v2 revamp.

| Rule | Spec | Kind |
|---|---|---|
| When | A scene plays only after a matching entry for the shown rental is confirmed or logged **while Today is visible**, after `timberDrop` and `windowsOn` have finished (≥ 0.5 s after the clip's end). Once per entry, keyed by the entry id (`TodayScenePlayed` set); never on appear, never on a timer, never on a loop. A batch confirm plays at most one scene (the newest matching entry). | grep (trigger bound to the entry id; no `repeatForever`, no `TimelineView(.animation)` in `House/`) |
| Duration | Enter ≤ 0.60 (`stage`), hold ≤ 2.4s static, exit ≤ 0.60 (`reveal` reversed). Total ≤ 3.6s. After the exit the prop may remain as a still detail (the van stays parked) until Today disappears; no motion after the exit. | measured in code |
| Where | §F.2's street and sky bands, minus the keep-outs, which are in points from the number block, the chip and the dots at every hero size (SE 297, Duo 287, 390, AX 295); the street band holds one occupant at a time **[measured: bbox intersection with every keep-out = 0]**. | measured |
| Over the number | Never. If a scene would need to cross the number's band, it is not a scene we ship. | measured |
| Pause / skip | Skipped (not queued) when: Reduce Motion is on; Low Power Mode is on; the app is not active; a sheet or alert is presented; the hero is less than 50% visible; VoiceOver is running (the scene is `accessibilityHidden`, decorative); a `houseStageAdvance` is playing (the milestone wins). A scene in flight pauses when the app resigns active and finishes its exit on return. | grep |
| Reduced motion | The still prop fades in (0.30) and stays; no path motion, no figure movement. | grep |
| Battery | Transforms and opacity only, inside one `drawingGroup`; no per-frame work when idle; the sky updates via an hourly timer, not a `TimelineView`; Instruments Animation Hitches = 0 and Energy Impact "Low" on an iPhone 12-class device over a 5-scene session; no scene on Low Power Mode. | measured (Instruments) |
| Density | Scenes add nothing to the hero frame (H1/H3) and never move the chip, the dots or the number block. | measured |
| Copy | Scenes carry no text. No speech bubbles, no labels. | grep |

A scene is the house acknowledging the record, once. If a reviewer can describe it as "the app is doing something in the background", it has failed **[judgment]**.

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
| Eyebrow / drafting label colour | `draftingInk` on cards (`#2369B5` / `#60A8E6`), drafting cyan on blueprint | ~~`draftingInk` everywhere on canvas and cards~~ (struck in v2 r2) | **v2:** no eyebrows on screens, cards or sheets; the drafting label survives only in the PDF and the Reports eyebrow, in `draftingInk`. See the "Drafting labels (v2)" row below. |
| Fraunces | Tab titles 34/500, display 34, never under 28pt | r1 omitted it | §1.14 names it. |
| **Canvas (v2)** | blueprint paper `#0B1230` in dark, `#EEF2FA` in light, the drafting grid on hero surfaces | hero screens take the dusk/night page gradient (§H.4); lists keep the plain canvas; the grid, tape measure, stamp, kraft and vellum are retired | Standard wins; brand doc §2 and §4 to be updated in the brand-doc pass (`v2-revamp-plan.md` P0). |
| **Hero (v2)** | "the Today hero restyled" as a blueprint card with a cyan eyebrow and the half-drawn/half-built house | a rendered diorama on the page, no card, no linework, windows show state | Standard wins; the linework/mask metaphor survives only in mark B and the widgets' mono glyph. |
| **Dark action vs page (v2)** | dark action `#8FD3FF` on `#0B1230` | unchanged; the night page is the same hex, so the ink-on-paper story holds | none |
| **Drafting labels (v2)** | SF Mono 11 caps eyebrows on cards | only in the PDF and the Reports eyebrow | Standard wins (§1.15). |
| **Hero numeral (v2)** | heroNumber 56/700 SF Rounded | Fraunces 84/600 on Today and the rental page | Standard wins (§1.14); brand doc §3 scale to add `display numeral 84/600`. |

The project `CLAUDE.md` is stale against both documents: it still names radius 12 for cards, Lucide as the primary icon library, violet `#7C6FF7` as `primary`, and DM Serif/DM Sans. Proposed replacement for its "Icon System" and "Corner Radius" sections and the colour header (not applied; Brian's call):

> **Colour.** Blueprint blue `#1E3FA6` is the brand and the light action colour; drafting cyan `#8FD3FF` is the dark action colour. Violet is retired. Tokens and contrast are in `docs/design/2.0-brand-system.md` §2; usage rules are in `docs/design/DESIGN-STANDARD.md`.
> **Type.** SF Pro / SF Pro Rounded (numbers, tabular) / SF Mono (drafting labels, 11pt caps, only in the PDF and the Reports eyebrow) / Fraunces (tab titles and display, ≥ 28pt only). DM Serif Display and DM Sans are retired.
> **Corner radius.** Cards 20 (continuous), inner surfaces 12, stat tiles 16, tags 6, buttons and chips capsule. Nothing else.
> **Icons.** SF Symbols for everything functional. Brand tool renders (`CategoryToolTile`) at 36 in browse rows and picker lists, 56 in picker grids and sheet headers, never in decision rows, never under 32. No Lucide (package removed), no emoji, no `Image("bp_tool_…")` outside the tile. Tab bar: SF Symbols (`LHIcon` custom shapes retired).
> **Navigation.** Native `TabView` with system Liquid Glass, `.tabBarMinimizeBehavior(.onScrollDown)`, "Log time" as the native fifth tab (`plus`, `role: .search`, reverts the selection), system `.badge` on Inbox only, content scrolling under the bar with no reserved heights, system materials for every bar and sheet. No custom tab bars. Details: `DESIGN-STANDARD.md` §1.25 and §H.7.
> **The house.** A rendered diorama on the page, never in a card: 44% of Today at default, 28% at AX; dusk in light, night in dark; windows lit when hours were logged today; the timber drop then the windows as the only signature motion; `behind`, `positiveOnPage`, `pageCardEdge`, the dusk page and the spill pool as tokens. Where it appears and at what size: `DESIGN-STANDARD.md` §H.5. Future customisation and ambient scenes: §F.
> **Components and density.** `docs/design/DESIGN-STANDARD.md` is the bar; its §5 is the gate rubric.

---

## Appendix: rollout order (v1; superseded by `docs/design/v2-revamp-plan.md`)

1. `Components/`: `LHButton`, `LHTag`, `LHChip`, `LHSectionHeader`, `LHScreenTitle`, `LHRow.Action/.Browse/.Value`, `LHField`, `LHSegmented`, `LHStepper`, `LHEmptyState`, `LHFormat.hours`, the revised `AppAnimation`; `scripts/density_gate.py`, `scripts/copy_gate.py`. **Create `Sources/Resources/Localizable.xcstrings`** with the canonical keys from §C.5 and migrate the view literals into it (today only `Learn.xcstrings` exists; the copy gate greps both catalogs, and a string that is not in a catalog is a gate fail).
2. Today (as a `List` root) + Inbox rows on `LHRow.Action`, one lane. Frames default/XXL/AX3, light/dark; density numbers in the hand-off; visual gate with the anchor question; Brian's eye on the first frame before polish rounds.
3. Log time, Properties, Suggestion confirm sheet, Onboarding, Paywall.
4. Delete the dead screens, Lucide, the custom swipe.
5. Copy pass from §C.5, `pdf.title` first.

Independent assessment required before Brian decides: `visual-gate` on the §3 row rendered as SwiftUI frames beside the Reminders and Copilot anchors; a copy assessor as the named persona on §C; and a fresh-context read of this r2.
