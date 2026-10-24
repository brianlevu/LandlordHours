# QA tool changes for design standard v2 (spec, not code)

2026-10-24, r2 (applies the independent review; see the review response table in `DESIGN-STANDARD.md`). The standard's §H and §F add [measured] rules the current tools cannot check. This file specifies the changes; nothing here is implemented yet. Each item names the rule, the tool, the input, the number it must print and the pass condition. Every new check fails closed (no data = BLOCKED).

## 1. `frame_check.py density`: the hero is not a card

Rule: standard §2 D6 (v2), §H.1 H1–H4, §H.8.

Today: the density pass finds cards as closed rectangles of card-coloured pixels and would read the 390pt hero frame as a 44% card and FAIL D6. On the dusk page it also reports `token canvas #DED5C7 is dE 15.7 from canvas/light #EEF2FA` on every hero frame (12 of 21 reference frames flagged for that alone).

Change:
- New frame classifier `hero_frame`: a frame is a hero frame when (a) its name matches `--hero-glob` (default `today-*`, `rental-*`, `welcome*`, `inbox-empty*`, `milestone*`) or (b) the top 54–120pt band samples within ΔE 6 of `pageTop`/`pageMid`. On hero frames the canvas token table is the dusk/night gradient: `pageTop #EAE3D7`, `pageMid #D8CFC0`, `pageBottom #E8E0D3` (light), `#0B1230` → `#080C1D` (dark). A sample is matched against the gradient value at its y, not a flat token.
- Hero detection: the largest connected region of non-page pixels whose bbox is wider than 60% of the window and whose top edge is within 54–120pt of the window top (default) or 54–200pt (AX) is the **hero region** (art plus backlight and spill pool). It is excluded from card detection (D6) and from D2/D4. It is only used to locate the hero, never to size the art.
- Stage: from the frame name (`--stage`, or the `started|frame70|framing|half|complete` token in the name); no stage = BLOCKED for the hero checks.
- `H1 frame_side_pt` = `lot_width_pt / (0.96 × stage_scale)`, where `lot_width_pt` is the widest pixel row of the hero region within the frame's bottom 15% at the lot's colour (sampled against the still's alpha, see below) and `stage_scale` is the §H.1 placement table (started 1.18, frame70 1.08, else 1.0). **No ground-line test on screen frames**: the scale about the ground and the lift (30pt, 12pt at 390) move it; the ground line is checked on assets only (§4).
- `H2 art_share`: map the still's alpha bbox (alpha ≥ 0.5, read from `Assets.xcassets/Craft/<stage>…`) through the placement (frame origin from the hero region's horizontal centre and the chip bottom, `side`, `stage_scale`, `lift × side / 390`) and divide its height by the window height; verdict 36–46% (default) or `H3` 24–32% (AX, detected by `--dt ax` or the glyph size). The old non-page pixel count is retired: it includes the night backlight (0.88 × side) and the spill pool. Cross-check: the mapped bbox top must match the first art row found on the frame in the centre 20% column within ± 6pt, else BLOCKED "placement not found". `H4 number_overlap_pt` (frame bottom minus the numeral bbox top; expected 44 ± 4 at default, 0 at AX), `card_edge_around_art` (TRUE when a closed rectangle of a non-page colour encloses ≥ 90% of the art bbox perimeter = FAIL "hero in a card").
- D3b (v2) by eye stays, but the script prints the y of: chip bottom, frame bottom, numeral baseline, pace sentence bottom, "To confirm" header, each row's dividers, the foot, the tab bar top; the gate reads the order from the numbers.

## 2. `frame_check.py`: page inks and the card edge

Rule: §H.4.

- On hero frames, every glyph cluster's ink is matched to the nearest token; on the **light gradient** the ink must be one of `textPrimary`, `textSecondary`, `action`, `behind #9A3624`, `positiveOnPage #0C5A30` when the cluster's background is a page colour (not a card). Any other ink on the page is a FAIL "ink not allowed on page" with the measured ratio (expected < 4.5:1: `positive` 3.50, `caution` 3.67, `destructive` 3.63, `informational` 3.90, `draftingInk` 3.62, `textTertiary` 3.55, `rose` 3.56 on `#D8CFC0`).
- Text contrast on hero frames is computed against the gradient step behind the cluster (sample the page 24pt left of the cluster at the same y), not against a single canvas token.
- Card edge: for each card on a hero frame, sample its 1pt edge ring; expected `pageCardEdge #A3966F` (light) / `#2A3560` (dark) within ΔE 6, and edge-vs-page contrast ≥ 1.8:1. Missing edge = FAIL "card floats on page".
- Dark hero frames: the `card` token is `#141C3F`; the reference frame `today-dark-AX3-windows-lit` sampled `#090F25` (dE 11.8) because the sample point hit the gradient under the card; fix the sample point to the card's centre.

## 3. `frame_check.py hero`: art readability and state

Rule: §H.2 "Readability on the page", "Windows show state", §5.1 item 8.

New mode `frame_check.py hero A.png [B.png …] --pairs lit=unlit`:
- `p99_contrast` (a **proxy**: it measures the brightest highlight, not the silhouette): relative-luminance contrast of the 99th-percentile art pixel vs the page colour behind the art, inside the mapped art bbox (§1), art pixels only (the still's alpha ≥ 0.5 at the placement). Lit (`*-lit*`, `*-lamp-lit*`): PASS ≥ 3.0, else BLOCKED. Unlit at night (`*-unlit*`/`*-windows-dark*`/`*-lamp-off*` in dark): **PASS ≥ 2.55, MARGINAL 2.40–2.55, BLOCKED < 2.40**. The 0.15 margin is the spread two tools gave on the same art (gate 2.51 vs final2 self-check 2.40). Reference 2026-10-24 (`qa/gate-log.jsonl`): unlit night framing 3.32–3.89 (PASS), half 2.51 and finished 2.48 (MARGINAL). Unlit by day: report only.
- `mean_luma_lift`: mean luma (0–255) of the art pixels minus the mean of the page pixels in a 24pt ring around the mapped bbox; PASS ≥ +5 in every state. Reference (final2 README): +6.9 to +15.5 at night unlit.
- `window_delta`: for a `lit`/`unlit` pair of the same stage and appearance, mean luma in the window boxes (a fixed list of boxes per stage in `craft_windows.json`, in frame fractions, written by the art lane) must be ≥ 20% higher in the lit frame; `sha256` must differ. Equal hashes = FAIL "state not captured".
- `saturation_share`: share of art pixels with S ≥ 0.25; PASS ≤ 40% light, ≤ 28% dark. `mean_S` ≤ 0.52.
- `hue_bins`: 30° hue bins ≥ 3% of art pixels, printed for the gate (judgment, not a verdict).
- `ground_line`: **removed from screen frames** (r2). It lives in `asset_check.py` (§4), on the stills.

## 4. `asset_check.py` (new; the only ground-line check)

Rule: §H.3.

Input: `Assets.xcassets/Craft/`, `Sources/Resources/Craft/`. Prints a table and exits 1 on any FAIL:
- Every stage in {started, frame70, framing, half, complete} has imagesets `craft_<stage>` and `craft_<stage>-unlit`, each with an `Any` and a `Dark` entry at 3x, universal; `craft_thumb_<stage>` at 2x and 3x.
- Per file: format (HEIC expected; PNG allowed only with `--allow-png` for the fallback case), pixel size 1206×1206 (stills) / 240 and 360 (thumbs), alpha channel present, size ≤ 450 KB (still) / ≤ 40 KB (thumb); totals ≤ 10 MB stills, ≤ 14 MB whole set; clips exist, are HEVC with alpha (`hvc1`, `kCVPixelFormatType_32BGRA`-decodable), 60 frames at 30 fps, ≤ 1.5 MB.
- Hashes: `sha256(lit) ≠ sha256(unlit)`, `sha256(Any) ≠ sha256(Dark)` per stage.
- Camera pin: the opaque bbox's left and right edges within ± 4px across all 20 stills; lowest opaque row at 92% ± 1% of 1206.
- Alpha fringe: for edge pixels (alpha 0.1–0.9), luminance within 10% of the mean of the adjacent opaque pixels; report the worst 5.
- Clip ends: first frame vs `craft_frame70` and last frame vs `craft_framing` mean ΔE ≤ 2 in the house bbox (lamp box excluded).
- Reserved names (§F.1) must not exist yet: FAIL if any `craft_slots_*`, `craft_*_build_*`, or a second style prefix appears **in the app bundle's catalogs** before §F.1 is built (`--allow-future` turns this off). Neutral renders and mask packs for the F1-0 spike live under `design/blueprint-house/` and are not scanned.
- Launch: FAIL if `LaunchBlueprint.colorset` exists or the launch colour set has no Dark entry (§H.5).

## 5. `motion_check.py` (new)

Rule: §H.6, §5.1 item 10.

Input: a 30 fps CFR capture of the log flow (`log-confirm-first-hour-*.mp4`) and the lot region in frame fractions. Prints per-frame changed-pixel counts in the lot region (the `dir-craft-final2/selfcheck/motion-numbers.txt` method):
- `drop_frames`: the longest run of consecutive frames with ≥ 40 changed pixels; PASS ≥ 24.
- `hard_cuts`: frames where the lot region's mean luma steps > 25% from the previous frame, excluding the two declared crossfade windows (clip-in 0.20 s, clip-out 0.30 s) and the sheet dismiss; PASS 0.
- `windows_fade`: after the clip ends, the window-box luma rises monotonically over 9–14 frames (0.30–0.47 s) when the capture is a first-hour run; PASS present. Under Reduce Motion captures (`*-rm*`), the clip run must be absent and the fade linear.
- `order`: drop end < windows start, and (when §F.2 ships) scene start ≥ windows end + 0.5 s.

## 6. `standard_lint.py` rule changes

Rule: §H.1 H9, §H.4, §H.7, §H.8, §1.15, §1.25, §B.

- `dynamic-type-clamp`: max **3** sites (r1's "2" in §5.2 is fixed); the allow-list is `CraftHouseView.swift` (numeral, frame) and the rental chip in the Today root. Any other site is NEW.
- `custom-swipe`: add `CraftHouseView.swift` to the allow-list for `DragGesture(` (the hero swipe); rows stay banned.
- New `craft-image`: `Image("craft_` or `Image(stage.rawValue` only inside `CraftHouseView.swift` and `LHThumb.swift`.
- New `hero-card`: in `House/` and the Today root, no `.background(…, in: RoundedRectangle` / `.clipShape(RoundedRectangle` / `LHCard` wrapping `CraftHouseView`.
- New `blueprint-retired`: FAIL on `BlueprintGrid`, `InboxBlueprintPaper`, `TapeMeasure`, `StampView`, `kraft`, `vellum`, `HouseHeroView` (the v1 card hero) anywhere in `Sources/` after the Today package merges (baseline them until then).
- New `tab-shell`: exactly five `Tab(` at the root, one with `role: .search` that carries `.accessibilityLabel(`; zero `.buttonStyle(.glass)` buttons whose label is `plus`; zero `.tint(Color(hex:` on a `TabView`.
- New `eyebrow-retired`: no `.monospaced` in `LHCard`, `LHScreenTitle` or `LHSheet`; `design: .monospaced` only in `PDF/`, `AuditReportPDFRenderer.swift` and the `ReportsView` eyebrow.
- New `toast-announce`: the toast center posts an `AccessibilityNotification.Announcement`; on hero screens the chip is hidden while a toast shows (one `@State`, grep both sites).
- New `stage-function`: one definition of a stage threshold table (`CraftStage.stage(hours:goal:)`); `HouseProgress` may only forward to it.
- New `page-ink`: in files that render on the page (`CraftHouseView`, the Today root, the rental page, Welcome, the Inbox empty state, the milestone), `foregroundStyle(` arguments must be one of `textPrimary`, `textSecondary`, `action`, `behind`, `positiveOnPage`, `ink`, or inside a card builder; `caution` outside a card builder is always a finding (§1.15, §H.4); list every other token as a finding for the gate to confirm against the frame.
- `onappear-animation` allow-list: unchanged (no `House/` entry; `timberDrop` is bound to the stage value).
- `spring-response`: unchanged (`rentalSlide` is 0.30 in r2, so it needs no exception). `repeat-forever`: unchanged. Add `timeline-view`: no `TimelineView(` in `House/`.
- `section-header-mono`: `LHSectionHeader` may not take `.monospaced`; `design: .monospaced` allowed only in `PDF/` and `ReportsView` eyebrow.

## 7. `swatch_matrix.py` (new, §F.1; a first cut is built for the F1-0 spike)

The F1-0 spike (standard §F.1) runs this on 6 swatches before anything else: siding Navy and Barn, roof Charcoal and Slate, door Black, and the default set as the control; it adds a banding probe (count of distinct 8-bit values per slot region after a HEIC round-trip; FAIL when a slot gradient shows steps wider than 3 levels over 12px) and writes each composite beside the locked frame for the fresh reviewer. Then, for the full set: input: the swatch table (names + hex per slot) and the neutral-base stills plus mask packs. For every allowed combination × stage {half, complete} × {lit, unlit} × {dusk, night}: composite with the §F.1 formula in Python (same maths as Core Image), then run §3's `p99_contrast` (unlit night PASS ≥ 2.55) and `mean_luma_lift` and write a 400px contact sheet for the read test. Also check per-slot HSV bounds (roof S ≤ 0.70, V 0.20–0.80; siding S ≤ 0.50, V 0.30–0.96; trim S ≤ 0.65; door S ≤ 0.70, V 0.12–0.80; hue not in 252–300) and the roof/siding luminance ratio ≥ 1.3 either way. Exit 1 if any combination fails; print the failing pairs so they can be removed from the offer.

## 8. `ambient_check.py` (new, §F.2; build when the feature starts)

Input: a capture of a scene and the live geometry (frame rect, number block, chip and dot rects in points, from the XCUITest element frames). Captures at frame 390, 295 (AX), SE 297 and Duo closed 287 are required. Prints the sprite bbox per frame; PASS when the bbox never intersects the keep-outs (number block, chip and dots each grown by 8pt, and the bottom 10% of the frame), never leaves the street band (x 0.66–0.94, y 0.76–0.90 of the placed frame) or the sky band (y 0.00–0.62), the street band never holds two occupants (a parked prop counts), enters and exits only at the declared edge, and the scene lasts ≤ 3.6 s (enter ≤ 0.6, hold ≤ 2.4, exit ≤ 0.6). Lighting match from the sprite's own render: shadow angle within ±10° of the house's, mean luminance within ±15% of the lit siding, S ≤ 0.55.

## 9. `copy_gate.py`

One change: read every `*.xcstrings` under `Sources/Resources/` (the per-package catalogs, plan §4), not only `Localizable` and `Learn`. Add the new canonical keys when the Today package lands: `today.toConfirm` ("To confirm · %lld"), `today.seeAll` ("See all %lld"), `today.ofHours` ("of %lld hours"), `today.pace.behind` ("Behind by %lldh."), `today.pace.onPace` ("On pace."), `today.pace.done` ("Done for %lld."), `today.pace.weekly` ("%lldh a week gets you to %lld."), `today.toast.logged` ("%@ on the books. %@."). The hero's accessibility label "House, framing going up, lights on" is copy and goes through the gate.

## 10. `gate_rubric.md`

Updated in this commit with a short v2 addendum (anchors, hero measures, page inks). The full rubric stays §5 of the standard.

## 11. `craft3.py --list-objects` (new flag, to build)

Rule: §H.2 "Forbidden kitsch" and "The rig's lights, as shipped". The flag does not exist today. Spec: `craft3.py --list-objects --states <…> --variants light,dark --lit on,off` builds each scene without rendering and prints JSON per (stage, variant, lit): every visible object name with its `kind`, and every light (name, type, strength, colour, light-linking collection). `scripts/qa/rig_check.py` then FAILs on (a) any object name in the retired list (flower, bloom, planter, pebble, lantern, pot, ornament, pet, string_light, snow, smoke, flag, mailbox, sign) and (b) any light not in the §H.2 table for that state. Until it exists, the gate reads `setup_lights`/`apply_state` and the object names in `craft2.py`/`craft3.py` by hand and says so.

## 12. Capture set additions (r2)

- **Tab switch, light:** Today → Inbox → Today at 30 fps for every hand-off that touches a hero screen (§H.4). Judged in writing; no number.
- **Shell on three OSes:** any change to `ContentView.swift` or the tab items carries frames on iOS 18, 26 and 27, and a VoiceOver read of the fifth tab ("Log time", not "Search") (§H.7).
- **Launch:** launch → handoff → first screen, light and dark, cold start (§H.5).
- **Small windows:** Today on 375×667 and Duo closed (382×644) at default: D3b's 1-row rule (§H.8).
- **AX3 numeral:** package C's first AX3 Today frame names the open finding "54pt numeral smaller than 'of 100 hours'" for the gate.
