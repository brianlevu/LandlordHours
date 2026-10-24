# QA tool changes for design standard v2 (spec, not code)

2026-10-24. The standard's §H and §F add [measured] rules the current tools cannot check. This file specifies the changes; nothing here is implemented yet. Each item names the rule, the tool, the input, the number it must print and the pass condition. Every new check fails closed (no data = BLOCKED).

## 1. `frame_check.py density`: the hero is not a card

Rule: standard §2 D6 (v2), §H.1 H1–H4, §H.8.

Today: the density pass finds cards as closed rectangles of card-coloured pixels and would read the 390pt hero frame as a 44% card and FAIL D6. On the dusk page it also reports `token canvas #DED5C7 is dE 15.7 from canvas/light #EEF2FA` on every hero frame (12 of 21 reference frames flagged for that alone).

Change:
- New frame classifier `hero_frame`: a frame is a hero frame when (a) its name matches `--hero-glob` (default `today-*`, `rental-*`, `welcome*`, `inbox-empty*`, `milestone*`) or (b) the top 54–120pt band samples within ΔE 6 of `pageTop`/`pageMid`. On hero frames the canvas token table is the dusk/night gradient: `pageTop #EAE3D7`, `pageMid #D8CFC0`, `pageBottom #E8E0D3` (light), `#0B1230` → `#080C1D` (dark). A sample is matched against the gradient value at its y, not a flat token.
- Hero detection: the largest connected region of non-page pixels whose bbox is wider than 60% of the window and whose top edge is within 54–120pt of the window top (default) or 54–200pt (AX) is the **house art**. It is excluded from card detection (D6) and from D2/D4.
- Print per hero frame: `H1 frame_side_pt` (the square the art is clipped to, found from the art's horizontal extent and the ground line at 92%), `H2 art_share = art_bbox_h / window_h` with the verdict 36–46% (default) or `H3` 24–32% (AX, detected by `--dt ax` or the glyph size), `H4 number_overlap_pt` (frame bottom minus the numeral bbox top; expected 44 ± 4 at default, 0 at AX), `card_edge_around_art` (TRUE when a closed rectangle of a non-page colour encloses ≥ 90% of the art bbox perimeter = FAIL "hero in a card").
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
- `p99_contrast`: relative-luminance contrast of the 99th-percentile art pixel vs the page colour at the art's ground line, inside the art bbox. PASS ≥ 3.0 for frames named `*-lit*` or `*-lamp-lit*`; PASS ≥ 2.4 for `*-unlit*`/`*-dark*`/`*-lamp-off*`; below = BLOCKED. (Reference: unlit night half 2.51, finished 2.48, framing 3.09–3.23.)
- `window_delta`: for a `lit`/`unlit` pair of the same stage and appearance, mean luma in the window boxes (a fixed list of boxes per stage in `craft_windows.json`, in frame fractions, written by the art lane) must be ≥ 20% higher in the lit frame; `sha256` must differ. Equal hashes = FAIL "state not captured".
- `saturation_share`: share of art pixels with S ≥ 0.25; PASS ≤ 40% light, ≤ 28% dark. `mean_S` ≤ 0.52.
- `hue_bins`: 30° hue bins ≥ 3% of art pixels, printed for the gate (judgment, not a verdict).
- `ground_line`: y of the lowest opaque art row as a fraction of the frame; PASS 0.91–0.93.

## 4. `asset_check.py` (new)

Rule: §H.3.

Input: `Assets.xcassets/Craft/`, `Sources/Resources/Craft/`. Prints a table and exits 1 on any FAIL:
- Every stage in {started, frame70, framing, half, complete} has imagesets `craft_<stage>` and `craft_<stage>-unlit`, each with an `Any` and a `Dark` entry at 3x, universal; `craft_thumb_<stage>` at 2x and 3x.
- Per file: format (HEIC expected; PNG allowed only with `--allow-png` for the fallback case), pixel size 1206×1206 (stills) / 240 and 360 (thumbs), alpha channel present, size ≤ 450 KB (still) / ≤ 40 KB (thumb); totals ≤ 10 MB stills, ≤ 14 MB whole set; clips exist, are HEVC with alpha (`hvc1`, `kCVPixelFormatType_32BGRA`-decodable), 60 frames at 30 fps, ≤ 1.5 MB.
- Hashes: `sha256(lit) ≠ sha256(unlit)`, `sha256(Any) ≠ sha256(Dark)` per stage.
- Camera pin: the opaque bbox's left and right edges within ± 4px across all 20 stills; lowest opaque row at 92% ± 1% of 1206.
- Alpha fringe: for edge pixels (alpha 0.1–0.9), luminance within 10% of the mean of the adjacent opaque pixels; report the worst 5.
- Clip ends: first frame vs `craft_frame70` and last frame vs `craft_framing` mean ΔE ≤ 2 in the house bbox (lamp box excluded).
- Reserved names (§F.1) must not exist yet: FAIL if any `craft_slots_*`, `craft_*_build_*`, or a second style prefix appears before §F.1 is built (`--allow-future` turns this off).

## 5. `motion_check.py` (new)

Rule: §H.6, §5.1 item 10.

Input: a 30 fps CFR capture of the log flow (`log-confirm-first-hour-*.mp4`) and the lot region in frame fractions. Prints per-frame changed-pixel counts in the lot region (the `dir-craft-final2/selfcheck/motion-numbers.txt` method):
- `drop_frames`: the longest run of consecutive frames with ≥ 40 changed pixels; PASS ≥ 24.
- `hard_cuts`: frames where the lot region's mean luma steps > 25% from the previous frame, excluding the two declared crossfade windows (clip-in 0.20 s, clip-out 0.30 s) and the sheet dismiss; PASS 0.
- `windows_fade`: after the clip ends, the window-box luma rises monotonically over 9–14 frames (0.30–0.47 s) when the capture is a first-hour run; PASS present. Under Reduce Motion captures (`*-rm*`), the clip run must be absent and the fade linear.
- `order`: drop end < windows start, and (when §F.2 ships) scene start ≥ windows end + 0.5 s.

## 6. `standard_lint.py` rule changes

Rule: §H.1 H9, §H.4, §H.7, §H.8, §1.15, §1.25, §B.

- `dynamic-type-clamp`: max **3** sites; the allow-list is `CraftHouseView.swift` (numeral, frame) and the rental chip in the Today root. Any other site is NEW.
- `custom-swipe`: add `CraftHouseView.swift` to the allow-list for `DragGesture(` (the hero swipe); rows stay banned.
- New `craft-image`: `Image("craft_` or `Image(stage.rawValue` only inside `CraftHouseView.swift` and `LHThumb.swift`.
- New `hero-card`: in `House/` and the Today root, no `.background(…, in: RoundedRectangle` / `.clipShape(RoundedRectangle` / `LHCard` wrapping `CraftHouseView`.
- New `blueprint-retired`: FAIL on `BlueprintGrid`, `InboxBlueprintPaper`, `TapeMeasure`, `StampView`, `kraft`, `vellum`, `HouseHeroView` (the v1 card hero) anywhere in `Sources/` after the Today package merges (baseline them until then).
- New `tab-shell`: exactly five `Tab(` at the root, one with `role: .search`; zero `.buttonStyle(.glass)` buttons whose label is `plus`; zero `.tint(Color(hex:` on a `TabView`.
- New `page-ink`: in files that render on the page (`CraftHouseView`, the Today root, the rental page, Welcome, the Inbox empty state, the milestone), `foregroundStyle(` arguments must be one of `textPrimary`, `textSecondary`, `action`, `behind`, `positiveOnPage`, `ink`, or inside a card builder; list every other token as a finding for the gate to confirm against the frame.
- `onappear-animation` allow-list: unchanged (no `House/` entry; `timberDrop` is bound to the stage value).
- `spring-response`: unchanged. `repeat-forever`: unchanged. Add `timeline-view`: no `TimelineView(` in `House/`.
- `section-header-mono`: `LHSectionHeader` may not take `.monospaced`; `design: .monospaced` allowed only in `PDF/` and `ReportsView` eyebrow.

## 7. `swatch_matrix.py` (new, §F.1; build when the feature starts)

Input: the swatch table (names + hex per slot) and the neutral-base stills plus mask packs. For every allowed combination × stage {half, complete} × {lit, unlit} × {dusk, night}: composite with the §F.1 formula in Python (same maths as Core Image), then run §3's `p99_contrast` (≥ 2.4 unlit night) and write a 400px contact sheet for the read test. Also check per-slot HSV bounds (roof S ≤ 0.70, V 0.20–0.80; siding S ≤ 0.50, V 0.30–0.96; trim S ≤ 0.65; door S ≤ 0.70, V 0.12–0.80; hue not in 252–300) and the roof/siding luminance ratio ≥ 1.3 either way. Exit 1 if any combination fails; print the failing pairs so they can be removed from the offer.

## 8. `ambient_check.py` (new, §F.2; build when the feature starts)

Input: a capture of a scene and the frame geometry. Prints the sprite bbox per frame; PASS when the bbox never intersects the number block, chip or dots, never leaves the street band (x 0.66–0.94, y 0.76–0.90) or the sky band (y 0.00–0.62), enters and exits only at the declared edge, and the scene lasts ≤ 3.6 s (enter ≤ 0.6, hold ≤ 2.4, exit ≤ 0.6). Lighting match from the sprite's own render: shadow angle within ±10° of the house's, mean luminance within ±15% of the lit siding, S ≤ 0.55.

## 9. `copy_gate.py`

No rule change. Add the new canonical keys when the Today package lands: `today.toConfirm` ("To confirm · %lld"), `today.seeAll` ("See all %lld"), `today.ofHours` ("of %lld hours"), `today.pace.behind` ("Behind by %lldh."), `today.pace.onPace` ("On pace."), `today.pace.done` ("Done for %lld."), `today.pace.weekly` ("%lldh a week gets you to %lld."), `today.toast.logged` ("%@ on the books. %@."). The hero's accessibility label "House, framing going up, lights on" is copy and goes through the gate.

## 10. `gate_rubric.md`

Updated in this commit with a short v2 addendum (anchors, hero measures, page inks). The full rubric stays §5 of the standard.
