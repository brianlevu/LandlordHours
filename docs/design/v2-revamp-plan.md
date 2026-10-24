# LandlordHours v2 revamp plan: every screen against the crafted-house system

2026-10-24. Companion to `DESIGN-STANDARD.md` v2 (§H the crafted object, §F future extensions). The system is locked; this plan says what every screen is today, what changes, in what order, and which lanes can build at the same time without touching each other's files.

**Base branch for the build: `int/2.1`** (255 commits ahead of `main`; it holds Inbox, Log time, House, Onboarding and Paywall as folders; `main` is the shipped 2.0 with a flat `Sources/Views/`). File paths below are `int/2.1` paths. The reference implementation to port is `Sources/Views/Debug/DirCraft/DirCraftToday.swift` on `proto/dir-craft` (DEBUG only; it is deleted once the Today package ships).

## 1. Labels, literally

- **new-system**: built from the `LH*` components and the §H hero against the standard. **Nothing shipped is new-system today.** The only new-system code is the DEBUG mock on `proto/dir-craft` and `Components/LHToast.swift`.
- **recoloured-legacy**: a 1.x layout with 2.0 blueprint tokens applied. Every shipped screen. Lint evidence: zero `LH*` component uses outside `LHToast`; `.system(size:)`, `Color(hex:)` and hand-built button styles across the tree (`standard_lint_baseline.json`).
- **untouched**: still on 1.x code paths (violet palette, Lucide, `Onb*` styles) with no 2.0 pass. Three screens; two of them are unreachable and are deleted.

The status column below is what the gate must be able to say about each screen when the package is done. "recoloured" is never written as "redesigned".

## 2. Screen inventory

Order = build order. Conversion-path screens first (onboarding, paywall, first run on Today), then the daily loop, then the rest. Package letters are defined in §4.

| # | Screen | Files (`int/2.1`) | Status now | What changes under v2 | Pkg |
|---|---|---|---|---|---|
| 1 | **Welcome** (onboarding step 0) | `Onboarding/OnboardingView.swift`, `OnboardingScene.swift`, `OnboardingStyle.swift` | recoloured-legacy (own palette, `Onb*` pills, three `.dynamicTypeSize(.large)` clamps; AX5 clips the headline under the button) | Dusk/night page, `craft_complete` lit at the Today hero size, Fraunces 34 headline, one `LHButton.primary` in a `safeAreaInset`, `.tertiary` "Have an account?"; the `Onb*` styles and clamps go; AX5 and Duo-trailing-strip frames required (§1.24, §H.5). | B |
| 2 | **Onboarding steps** (rental, goal, who files, calendar opt-in) | `Onboarding/OnboardingFlow.swift`, `OnboardingSteps.swift`, `OnboardingSupport.swift` | recoloured-legacy (135 legacy hits in `OnboardingSteps`, 23 `fixedSize`s) | `LHRow.Browse` option rows with the trailing `checkmark`, `LHField`, `LHSegmented`, `LHButton`; the add-a-rental step gets the 120pt `craft_started` thumbnail; copy from §C.2 "First run"; no clamps. | B |
| 3 | **Paywall** + locked preview | `Paywall/PaywallView.swift`, `RecordPagePreview.swift`, `PaywallPreviewLaunch.swift`, `Components/LockedPreview.swift` | recoloured-legacy (4 literal hexes, 5.5–13pt preview type, `…xxLarge` clamp, preview title ≠ `pdf.title`) | Plain canvas, no blueprint band, no house; record preview ≤ 40% with `pdf.title`; `LHButton` cases; "What you get" above the fold; opens about the thing tapped; free-user journey verified per entry point (§1.23). | B |
| 4 | **Tab shell** | `ContentView.swift` (617 lines; `ShellTab`, custom "Log time" button) | recoloured-legacy (custom bar and detached button) | Native `TabView`, five `Tab`s, "Log time" as `plus` with `role: .search` and the revert-selection `onChange`; `.tabBarMinimizeBehavior(.onScrollDown)`; `.badge` on Inbox; no reserved bottom heights; `LHIcon` tab shapes deleted (§1.25, §H.7). | A |
| 5 | **Today** | `DashboardView.swift` (1222), `Today/TodayComponents.swift`, `Today/TodayLogic.swift`, `House/HouseHeroView.swift`, `HouseArtView.swift`, `ConfirmBuildAnimation.swift`, `HouseTokens.swift` | recoloured-legacy (card stack, 160–236pt items, custom swipe, blueprint card hero) | Port the CRAFT mock: dusk page, `CraftHouseView` hero (H1–H4), rental `Menu` chip + dots + swipe, Fraunces numeral, pace sentence with `behind`/`positiveOnPage`, "To confirm · N" `.headline`, ≤ 2 `LHRow.Action` rows in a `pageCardEdge` container, "See all N" foot, top toast; pace tiles removed; `timberDrop`, `windowsOn`, `stageFade`, `rentalSlide`; `HouseHeroView` and the card hero deleted (§H.8). | C |
| 6 | **Hero component** (shared) | new `House/CraftHouseView.swift`, `House/CraftStage.swift`, `House/TodayWindowState.swift`, `Components/LHThumb.swift`, `Assets.xcassets/Craft/`, `Sources/Resources/Craft/` | new-system (DEBUG mock only) | Production `CraftHouseView(size:)` with the three sizes (hero 390/295, medium 300/220, thumbnail 44/56/120), the clip player, the spill pool, backlight and contact shadow; HEIC pass to the §H.3 budget; `asset_check.py` green; reserved slots for §F.1 masks and §F.2 layers (empty `ZStack` slots Z3 and Z5, no code). | A |
| 7 | **Inbox** (list, day headers, question card, capture setup) | `Inbox/InboxView.swift`, `SuggestionRowView.swift`, `InboxComponents.swift`, `InboxViewModel.swift`, `InboxLogic.swift`, `BackfillProgressHeader.swift`, `CaptureOptIn.swift`, `CaptureSetupFlow.swift` | recoloured-legacy (row + pill, 300pt question card, inline header) | `LHRow.Action` rows with day headers, system swipes, "Confirm N likely" foot or pinned bar, `.headline` section headers; the empty state is the diorama ≤ 240 on the page (§H.5); capture setup on standard components; plain canvas elsewhere. | D |
| 8 | **Suggestion confirm sheet** | `Inbox/SuggestionConfirmSheet.swift` (698) | recoloured-legacy (second stepper, second Me/Spouse picker, two close buttons) | Opaque `.large` sheet (§1.20), `LHStepper`, `LHSegmented`, `LHRow.Value`, one `.icon` close, 56 category tool in the header, no house. | D |
| 9 | **Log time sheet** + timer | `LogTime/LogTimeSheet.swift` (1255), `LogPickers.swift`, `TodayTimerSection.swift`, `LogSheetDebug.swift`, `AppToastCenter.swift` | recoloured-legacy (own 52pt style, raw sizes, 17 `fixedSize`s, `InboxBlueprintPaper`) | Opaque `.large` sheet, note field first, `LHStepper` (100pt value column), `LHSegmented`, `LHRow.Value` pickers, one pinned `.primary` (glass on iOS 26+), `InboxBlueprintPaper` deleted; no hero art. | E |
| 10 | **Properties list** (All rentals) | `PropertiesView.swift` (1271, list part), `Properties/PropertyComponents.swift` | recoloured-legacy (40pt seal + 48pt tile + chevron, gutter 16, "+" in the title row) | `LHRow.Browse` with the 44pt house-only thumbnail (lit by `loggedToday`), one ornament, gutter 20, "Add rental" in the toolbar and the empty state; plain canvas. | F |
| 11 | **Rental page** (Properties detail) | `PropertiesView.swift` (detail part) | recoloured-legacy (188pt r24 hero, inline r20 cards) | The medium hero (frame 300, art 28–34%; AX 220) on the dusk/night page with the number block and pace; `LHTile.Stat` 2-up (the tiles that left Today); records as `LHRow.Browse`; `.title1.semibold` title. Reserved: one `LHRow.Value` "House" slot for §F.1, hidden until built. | F |
| 12 | **Rental edit sheet** | `PropertiesView.swift` (edit sheet), `ProfileManagementViews.swift` (nickname/other names) | recoloured-legacy | `LHField`, `LHRow.Value`, `LHSegmented` for type; copy line 7 from §C.5; §F.1 "House" row reserved. | F |
| 13 | **Milestone celebration** (100 / 500 / 750) + backfill reveal | `House/MilestoneCelebrationView.swift`, `House/BackfillRevealView.swift`, `Components/CelebrationOverlayView.swift` | recoloured-legacy (8 raw sizes) | The diorama at hero size on the page; `houseStageAdvance` with the brass sign rendered in the rig; one confetti burst; tokens only. | C |
| 14 | **Records** | `HistoryView.swift`, `Records/RecordsLogic.swift` | recoloured-legacy (drift: chips r10, 2-line titles) | `LHRow.Browse` with `CategoryToolTile(36)`, `LHChip` strip, 1-line titles; no house; plain canvas; `Table` in band C (§1.27). | G |
| 15 | **Time entry detail** | `TimeEntryDetailView.swift` | recoloured-legacy (drift) | Token and radius swaps (thumbnails r12), 56 tool header stays. | G |
| 16 | **Reports** | `ReportsView.swift`, `Reports/ReportsLogic.swift`, `Components/BlueprintList.swift` | recoloured-legacy (drift: r16/r20 mix, `StandingCard` padding 18) | `LHRing` 260, the drafting eyebrow (the one place it survives on screen), `LHTile.Stat`, per-rental rows with 44 thumbnails; `BlueprintList` renamed and de-blueprinted; copy line 2 from §C.5. | G |
| 17 | **Settings** | `SettingsView.swift` (1299), `Components/BlueprintList.swift` | recoloured-legacy (closest to standard) | One `List`, `LHRow.Toggle`/`.Value`, Pro card r20 with `LHButton.secondary`, mark C in the header (optional); copy lines 3 and 10 from §C.5. | H |
| 18 | **Learn** | `Learn/LearningCenterView.swift`, `Learn/LearnLibrary.swift` | recoloured-legacy (drift: rows 60/52, hero 150 r24) | Rows 56, `LHCard.Summary` header, no house. | H |
| 19 | **Export** | `ExportPDFView.swift`, `ExportJob.swift` | recoloured-legacy | Standard containers, `LHButton`, `pdf.title`; the paywall opens about the export. | H |
| 20 | **Contact support, Delete all data, profile sheets** | `ContactSupportView.swift`, `DeleteAllDataView.swift`, `ProfileManagementViews.swift` (switch sheets) | recoloured-legacy | Button and close swaps, `.alert` only for Delete all data (§1.21). | H |
| 21 | **Launch handoff / loading** | `Components/LaunchHandoffView.swift`, `Components/DraftingLoader.swift` | recoloured-legacy | `scanningLine` stays the one `repeatForever`; the drafting line is allowed as a loader; tokens only. | H |
| 22 | **Widgets, Live Activity, Controls** | `Sources/Widget/LandlordHoursWidget.swift`, `WidgetSurfaceViews.swift`, `Sources/Shared/WidgetSurface.swift`, `scripts/widget/make_widget_house.py` | recoloured-legacy | Medium/large/extra-large: the 120 house-only thumbnail lit by `loggedToday`; small and accessory: mono mark B; `systemExtraLargePortrait`; accented and tinted frames (§1.26, §H.5). | I |
| 23 | **Toast** | `Components/LHToast.swift` | new-system (v1 component) | Add the hero-screen top placement variant (§1.19). | A |
| 24 | **Debug: Engagement lab, surface capture board, DirCraft mock** | `EngagementLabView.swift` (`#if DEBUG`), `Debug/SurfaceCaptureBoard.swift`, `Debug/SurfaceDebugHooks.swift`, `proto/dir-craft` `Debug/DirCraft/*` | untouched (DEBUG) | Not user-facing. `EngagementLabView` keeps working or is deleted; the DirCraft mock is deleted when package C lands; capture hooks move to `-LHCraftWindows`, `-LHCraftFirstHour`, `-LHCraftScroll`. | C |
| 25 | **Tasks, Category management** | `TasksView.swift`, `CategoryManagementView.swift` | untouched (1.x, Lucide, `Color(hex: category.colorHex)`; reachable only from previews) | **Delete** (standard §4 "Delete"). | A |

Not screens, but in scope for the same pass: `Sources/App/LandlordHoursApp.swift` and `Sources/Shared/BrandPalette.swift` (tokens, package A); `Localizable.xcstrings` (canonical keys, package A then each lane adds its own); `docs/design/2.0-brand-system.md` (the §D conflicts, package A); `CLAUDE.md` design section (package A).

## 3. Order and why

1. **A Foundations** first: tokens, the `LH*` components that do not exist yet, the production hero component with the HEIC assets, the tab shell, the QA tool changes from `scripts/qa/NOTES-standard-v2.md`. Nothing else can be gated without them.
2. **B Conversion path** and **C Today** in parallel: Welcome, steps, paywall; Today and the milestone. A free install's first ten minutes are Welcome → steps → Today → the first log → the paywall at the second rental or the export. The release verifier drives that journey as a free user and reports taps-to-purchase per entry point.
3. **D Inbox** and **E Log time** in parallel: the daily loop.
4. **F Rentals**: list, rental page, edit sheet (carries the §F.1 reservation).
5. **G Records and Reports**, **H Settings and the long tail**, **I Widgets**, in parallel.
6. Deletes, the copy pass (§C.5 lines in order, `pdf.title` first), the brand-doc and `CLAUDE.md` updates, the consistency inventory re-labelled from the frames.

Every package ends with: frames at default, XXL and AX3 (AX5 for Welcome) in light and dark, `frame_check.py` and `standard_lint.py` numbers in the hand-off, the named motions, a `visual-gate` pass (two looks for a new surface), and the §5.5 anchor paragraph. Brian sees the first Today frame and the first Welcome frame before any polish round.

## 4. Build packages (file-disjoint)

Each package owns its files; a file appears in exactly one package. Shared files are owned by A and frozen once A merges; later packages that need a token or a component ask A's owner rather than editing.

| Pkg | Name | Owns | Depends on | Model tier |
|---|---|---|---|---|
| **A** | Foundations | `Sources/App/LandlordHoursApp.swift`, `Sources/Shared/BrandPalette.swift`, `Sources/Views/Components/LH*.swift` (new: `LHButton`, `LHRow`, `LHCard`, `LHTile`, `LHTag`, `LHChip`, `LHField`, `LHSegmented`, `LHStepper`, `LHSectionHeader`, `LHScreenTitle`, `LHEmptyState`, `LHSheet`, `LHThumb`, `LHFormat`), `Components/LHToast.swift`, `House/CraftHouseView.swift`, `House/CraftStage.swift`, `House/TodayWindowState.swift`, `Assets.xcassets/Craft/`, `Sources/Resources/Craft/`, `ContentView.swift`, `Sources/Resources/Localizable.xcstrings` (keys only), `scripts/qa/*`, `docs/design/2.0-brand-system.md`, `CLAUDE.md`; deletes `TasksView.swift`, `CategoryManagementView.swift`, `LHIcons.swift` tab shapes | none | Opus (components and hero), Sonnet (tool changes), Haiku (asset conversion script) |
| **B** | Conversion path | `Onboarding/*`, `Paywall/*`, `Components/LockedPreview.swift` | A | Opus |
| **C** | Today and milestone | `DashboardView.swift`, `Today/*`, `House/HouseHeroView.swift` (delete), `House/HouseArtView.swift`, `House/ConfirmBuildAnimation.swift`, `House/HouseTokens.swift`, `House/MilestoneCelebrationView.swift`, `House/BackfillRevealView.swift`, `Components/CelebrationOverlayView.swift`, `Debug/*`, `proto/dir-craft` `Debug/DirCraft/*` (delete after port) | A | Opus |
| **D** | Inbox | `Inbox/*` | A | Sonnet (rows are fully specified) |
| **E** | Log time | `LogTime/*` | A | Sonnet |
| **F** | Rentals | `PropertiesView.swift`, `Properties/*`, `ProfileManagementViews.swift` | A | Opus (the medium hero and the §F.1 reservation) |
| **G** | Records and Reports | `HistoryView.swift`, `Records/*`, `TimeEntryDetailView.swift`, `ReportsView.swift`, `Reports/*`, `Components/BlueprintList.swift` | A | Sonnet |
| **H** | Settings and the long tail | `SettingsView.swift`, `Learn/*`, `ExportPDFView.swift`, `ExportJob.swift`, `ContactSupportView.swift`, `DeleteAllDataView.swift`, `Components/LaunchHandoffView.swift`, `Components/DraftingLoader.swift` | A | Sonnet |
| **I** | Widgets | `Sources/Widget/*`, `Sources/Shared/WidgetSurface.swift`, `Sources/ViewModels/WidgetSurfaceBuilder.swift`, `scripts/widget/*` | A | Sonnet |

Concurrency: A alone; then B + C (+ D if a third lane is free); then D/E; then F + G + H + I two or three at a time. Cap at 3–4 lanes when MCP tools are in play. Each lane in its own worktree under `~/tmp/worktrees/`, branched from `int/2.1` after A merges.

## 5. Open questions for Brian (each with the recommendation)

1. **Fourth tab name: "Properties" (standard) or "Rentals" (the CRAFT mock).** Recommend **Rentals**: it is the word every sentence uses (§C.4), and one word for one thing is a voice rule.
2. **Pace tiles off Today, onto the rental page and Reports.** The locked frames have none. Recommend **yes**: the pace sentence under the number carries the same fact in one line; tiles return on the rental page where there is room.
3. **Drafting mono labels retired from screens** (kept in the PDF and the Reports eyebrow). Recommend **retire**: with the blueprint canvas gone they read as leftovers, and the locked frames use `.headline`.
4. **Two canvases: dusk page on hero screens, plain canvas on lists.** Recommend **keep both**: the warm page fails AA for seven intent inks, so an app-wide warm canvas would need a second token set and a re-gate of every list. The dark side is already one hex.
5. **Toast at the top on hero screens.** Recommend **yes**, as in the locked frames; everywhere else it stays above the tab bar.

## 6. Backlog: designed for, not built (standard §F)

| Item | What | Blocks on | Pkg later |
|---|---|---|---|
| F1-a | `HouseLook` on `RentalProperty` (roof, siding, trim, door, style; swatch names; synced) | F merged | J |
| F1-b | Blender: neutral-albedo base renders for `half` and `complete`; mask packs `craft_slots_<stage>` and `craft_thumb_slots_<stage>` | art lane | J |
| F1-c | `HouseLookCompositor` (Core Image, cached, ≤ 40 ms on A15; app-group cache for the widget) | F1-b | J |
| F1-d | "House" picker sheet in the rental edit sheet (four swatch rows, live 300pt preview) | F1-a, F1-c | J |
| F1-e | `scripts/qa/swatch_matrix.py` and the starting swatch set gated (night p99 ≥ 2.4, 400px read, luminance pairs) | F1-b | J |
| F1-f | Roof **material** variants (≤ 3) as pre-rendered sets, only if colour alone is not enough | F1-d shipped and used | K |
| F1-g | Second house style (`craft_<style>_*`, all five stages + clip + masks) | F1-d | K |
| F2-a | Freeze the camera and the lot plane in `design/blueprint-house/scenes/camera.json`; render the `contractorVan` and `guestCarLeaves` clips (dusk, night, sub-frame band) | C merged | L |
| F2-b | `AmbientScheduler` (triggers by entry id, caps, skip conditions, order after `windowsOn`) | C merged | L |
| F2-c | Z3/Z5 slots filled; `TodayScenePlayed` persistence | F2-a, F2-b | L |
| F2-d | `scripts/qa/ambient_check.py`; Instruments hitches = 0 over a 5-scene session | F2-c | L |
| F2-e | `visitorAtDoor` (people) and `balloons` at goal reached | F2-c | M |
| F2-f | Sky-band stills (birds) moved by SwiftUI; clouds only if rendered into the stills | F2-c | M |

## 7. Evidence

Frames and numbers: `~/AgentScratch/landlordhours/2026-10-24/dir-craft-final2/` (21 frames, self-check), `craft-gate1/2/3` and `qa/gate-log.jsonl` (verdicts), `dir-craft3/README.md` (render measurements), `dir-craft2/verdict.md` (art direction), `taste-board/` (the pick), `trend-audit/report.md`, `platform-research/report.md`. Code: `proto/dir-craft` at `0f9995a`.
