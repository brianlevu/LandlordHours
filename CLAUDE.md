# LandlordHours Design System

> **App Name:** LandlordHours
> **Platform:** iOS 17.0+ (SwiftUI)
> **Architecture:** MVVM
> **Design Style:** 2.0 "Blueprint" — honest, crafted, earned (docs/design/2.0-brand-system.md). Violet and Lucide are retired.

For full-screen-by-screen design audits, use `docs/design-audit-playbook.md` before changing UI.

---

## Design standard (the bar; supersedes any 1.x rule below)

Every rule in the standard is tagged **[measured]**, **[grep]** or **[judgment]**. Builders run the checks below and put the numbers in the hand-off; the gate re-measures.

**Colour.** Blueprint blue `#1E3FA6` is the brand and the light action colour; drafting cyan `#8FD3FF` is the dark action colour. Violet is retired. Tokens and contrast are in `docs/design/2.0-brand-system.md` §2; usage rules are in `docs/design/DESIGN-STANDARD.md`. Intent first: action, positive, caution, destructive, informational. Never hardcode a hex in a view; add a token or use `AdaptiveColors`. Every view supports dark mode.

**Type.** SF Pro / SF Pro Rounded (numbers, tabular) / SF Mono (drafting labels, 11pt caps) / Fraunces (tab titles and display, ≥ 28pt only). DM Serif Display and DM Sans are retired. Use text styles, not `.system(size:)`.

**Layout.** Gutter 20, section gap 24, header to content 8, card padding 16. Rows live in one grouped container with hairline dividers; a card per list item is a defect.

**Corner radius.** Cards 20 (continuous), inner surfaces 12, stat tiles 16, tags 6, buttons and chips capsule. Nothing else.

**Icons.** SF Symbols for everything functional. Brand tool renders (`CategoryToolTile`) at 36 in browse rows and picker lists, 56 in picker grids and sheet headers, never in decision rows, never under 32. No Lucide (package removed), no emoji, no `Image("bp_tool_…")` outside the tile. Tab bar: SF Symbols (`LHIcon` custom shapes retired).

**Components and density.** `docs/design/DESIGN-STANDARD.md` is the bar; its §5 is the gate rubric. Components are named `LHButton` (4 cases), `LHRow.Action/.Browse/.Value/.Toggle`, `LHCard.Summary`, `LHTile.Stat`, `LHTag`, `LHChip`, `LHField`, `LHSegmented`, `LHStepper`, `LHSectionHeader`, `LHScreenTitle`, `LHEmptyState`, `LHToast`, `LHSheet`. A row is 56–88pt (target 64), one list item is ≤ 12% of the viewport, a non-hero card ≤ 20%, empty bands inside a card ≤ 35%. No button inside a row; swipes are system `.swipeActions` only.

**Motion.** Named motions and tokens are in standard §B. Springs are `.spring(duration:bounce:)`, ≤ 0.30s; bounce only on gesture release; every animation is bound to a state change; honour reduce motion.

**Voice.** Standard §C: short plain sentences (average ≤ 14 words), the word list, canonical strings by key, never "qualify/qualified", "audit-ready", "evidence", "proof", "compliance". All user-facing text goes through the String Catalog.

### QA tooling that enforces the standard

```bash
python3 scripts/qa/frame_check.py density <frames...>   # D1, D2, D4, D6 (+ D3 with --items-present N) on 3x frames
python3 scripts/qa/standard_lint.py                      # [grep] rules vs scripts/qa/standard_lint_baseline.json; fails on NEW violations
python3 scripts/qa/standard_lint.py --baseline           # ratchet the baseline down after fixing violations
```

`scripts/qa/gate_rubric.md` is the addendum the `visual-gate` agent applies, including the written anchor-app judgment.

---


---

## Brand Identity (2.0 "Blueprint", locked by Brian 2026-10-19)

Where the brand lives:
- **`docs/design/2.0-brand-system.md`** — personality, colour tokens, type, icon language, logo and app icon. The source of truth.
- **`design/brand/`** — `contrast.txt` (every pair, WCAG ratios), `logo/` (mark-b, mark-b-mono, wordmark, lockups as SVG), `icon/` (`icon-b-1024.png` = the approved app icon, plus `-dark` / `-tinted` variants), `scripts/` (`make_icons.py`, `make_icon_variants.py`, `contrast.py`, `verify_icon.py`).
- **`docs/design/2.0-hifi-reference-spec.md`** — per-surface layout (tab bar, Inbox, sheets, Settings).

Personality: **Honest. Crafted. Earned.** Say what was done, in short sentences; never "qualified" (that is the CPA's word).

**Retired in 2.0: violet (every shade) and Lucide icons.** Violet-named tokens still exist so old screens compile, but they resolve to blueprint values; never pick a violet hex again. Lucide is being removed (see Icon System).

### Logo — mark B, "half drawn, half built"

A house elevation on blueprint blue: foundation, left wall, left roof slope and door are built (plaster, terracotta, timber); the right slope, upper right wall and window are still drafting-cyan linework. File: `Sources/App/LHLogo.swift` (vector paths from `design/brand/logo/mark-b.svg`).

```swift
LHLogo(size: 80, showText: true, animated: false)   // tile + wordmark
LHCompactLogo(size: 32)                               // nav bar / header
WaveHouseIcon(size: 44)                               // the mark on its blueprint tile (in-app twin of the app icon)
LHMark(size: 120)                                     // colour mark, transparent (on blueprint surfaces)
LHMarkShape().fill(...)                               // mono template (widgets, Island, accented modes)
LHWordmark(fontSize: 34)                              // "Landlord" ink + "Hours" action colour; Fraunces 600 at ≥28pt
```

App icon: `Assets.xcassets/AppIcon.appiconset` = icon B (1024 full-bleed, no baked corners) with dark (transparent background) and tinted (grayscale) appearances. Regenerate variants with `python3 design/brand/scripts/make_icon_variants.py design/brand/icon`. The 1.x alternate icons (Violet, Sunset, Clock, Aurora) and the Settings "App Icon" picker were removed in WP-D: there is one app icon, and iOS handles the dark and tinted looks.

---

## Color System

All tokens live in `Sources/App/LandlordHoursApp.swift`: hex sources in `AppColors.Hex`, `AppColors` statics, and `AdaptiveColors` (resolves per scheme). Values and contrast: `docs/design/2.0-brand-system.md` §2 and `design/brand/contrast.txt`; `Tests/ColorContrastTests.swift` asserts every text pair ≥ 4.5:1 in both schemes, the locked hexes, and that no token is violet.

**Blueprint blue `#1E3FA6` is the brand and the light-mode action colour. Dark mode's action is drafting cyan `#8FD3FF`** ("the action colour is always the ink on the paper"). Dark linework and drafting labels step down to `#60A8E6` so linework never shares a hex with the dark action.

| Intent token | Light | Dark | Use |
|---|---|---|---|
| `background` (canvas) | `#EEF2FA` | `#0B1230` | Page |
| `backgroundSecondary` (card) | `#FFFFFF` | `#141C3F` | Cards, sheets |
| `backgroundTertiary` | `#F6F8FD` | `#1B2550` | Inputs, segments |
| `brand` (new) | `#1E3FA6` | `#1E3FA6` | Hero, icon, brand fills (theme-fixed) |
| `action` / `primary` | `#1E3FA6` | `#8FD3FF` | Primary CTAs, selection, links |
| `onAction` | `#FFFFFF` | `#0B1230` | Text/glyphs on `action` |
| `actionSurface` / `primarySurface` | `#E3E9FA` | `#182A5C` | Selected tab, action wash |
| `drafting` (new) | `#8FD3FF` | `#60A8E6` | Decorative linework only, never text on white |
| `draftingInk` (new) | `#2369B5` | `#60A8E6` | SF Mono drafting labels |
| `timber` / `timberInk` (new) | `#E0A458` / `#8A5A1B` | `#E0A458` / `#F0BE7A` | Warm material accent / its text form |
| `brass`, `terracotta`, `plaster` (new) | `#D9B45A`, `#C8553D`, `#F4EFE6` | same | Illustration only |
| `textPrimary` / `Secondary` / `Tertiary` | `#121B33` / `#4A5068` / `#5F6983` | `#F2F4FA` / `#B4BCD2` / `#8A94B2` (lifted from the doc's #7E88A6 to pass on the dark input fill) | Text levels |
| `border` | `#D5DBEA` | `#2A3560` | Decorative hairline (cards separate by fill) |
| `positive` (+Surface) | `#137A42` / `#E4F7EB` | `#4ED48A` / `#123A2A` | Met, confirmed, on pace |
| `caution` (+Surface) | `#9A560C` / `#FCF0DC` | `#FFB454` / `#3D2A10` | Behind pace, incomplete setup |
| `destructive` (+Surface) | `#C1303A` / `#FCE4E5` | `#FF7A7A` / `#44181C` | Delete, errors |
| `informational` (+Surface) | `#4A6392` / `#E6ECF6` | `#9BB0D0` / `#1E2A4A` | Imports, sync, neutral info (slate, never mistaken for action) |
| `rose` (+Wash) | `#B04266` | `#F08BAA` | Spouse / people |

Legacy names map onto these: `sage`→positive, `honey`→caution, `coral`→terracotta/destructive, `sky`→informational, `success`/`warning`/`error` → the intents, `reportsAccent*`/`mpAccent*`/`lavender*`/`celebration*`/`logo*` → blueprint-family values. Intent statics in `AppColors` are dynamic (`Color.lhDynamic`), so a bare `AppColors.action` follows the scheme; light-named neutrals (`charcoal`, `slate`, `snow`…) stay light-only.

### IMPORTANT Color Rules

- IMPORTANT: One blue, owned completely. A screen's main CTA uses `colors.action` + `colors.onAction` (or `AppColors.action` / `AppColors.onAction`) unless it is destructive. On the blueprint hero the primary button is a white pill with blueprint text.
- IMPORTANT: Positive only for met/confirmed/on-pace; caution for behind-pace and incomplete setup; destructive for delete; informational is slate. Never green for ordinary "continue/add/save" buttons.
- IMPORTANT: Drafting cyan is linework, not text on light surfaces (1.6:1 on white). Text in drafting style uses `draftingInk`.
- IMPORTANT: Never hardcode hex values in views. Add a token to `AppColors.Hex` + `AppColors`/`AdaptiveColors`, and a contrast assertion if it carries text.
- IMPORTANT: Every view supports dark mode via `AdaptiveColors`.
- IMPORTANT: No violet. `testVioletIsRetired` fails if a token drifts back to a purple hue.
- Category colours stay as materials, at 12% washes behind row icons; they never override intent colours.

---

## Typography

Defined in `Sources/App/LandlordHoursApp.swift` → `AppTypography`, `LHDisplayStyle`, `LHFont`.

- **SF Pro** for body and UI. Tokens use text styles, so they follow Dynamic Type.
- **SF Pro Rounded, tabular digits** for numbers: `heroNumber` (56/700; use `.lhHeroNumberFont()`, which scales relative to .largeTitle and caps at 80pt), `ringNumber` (46), `metric` (title2 rounded bold), `number` (body rounded semibold).
- **SF Mono** for drafting labels: `AppTypography.drafting` (= `label`), 11pt, uppercase, `.tracking(1.3)` at the call site.
- **Fraunces** (Undercase Type, SIL OFL 1.1; `Sources/Resources/Fonts/Fraunces.ttf` + `Fraunces-OFL.txt`, registered in `Info.plist` `UIAppFonts`) for **display at 28pt and up only**: tab titles, Welcome, milestones, Today's header. **Never** in lists, never on numbers or tax lines, never in the PDF. If it fails to register, the code falls back to New York (`design: .serif`).

| Token | Font | Size / weight | Notes |
|---|---|---|---|
| `.lhDisplayFont(.display)` / `AppTypography.display` | Fraunces | 34 / 500, opsz 144, SOFT 50 | Welcome, milestones |
| `.lhDisplayFont(.largeTitle)` / `largeTitle` | Fraunces | 34 / 500, opsz 96 | Tab titles, Today header |
| `.lhDisplayFont(.title)` / `headline`, `title1` | Fraunces | 28 / 500, opsz 72 | Section display |
| `title2` / `title3` | SF Pro | 22 / 20 semibold | Card titles |
| `subheadline` / `buttonLarge` | SF Pro | 17 semibold | |
| `bodyLarge` / `body` / `bodySmall` | SF Pro | 17 / 15 / 13 | |
| `caption` | SF Pro | 12 medium | |
| `button` / `buttonSmall` | SF Pro | 16 / 13 semibold | |

- Prefer `.lhDisplayFont(_:)`: it sets the wght/opsz/SOFT axes, follows Dynamic Type and never drops under 28pt. The `Font` tokens are the simple fallback for `Text` concatenation.
- IMPORTANT: Use `AppTypography.*` tokens; no new `.system(size:...design: .rounded)` for body text.

---

## Spacing Scale

Defined in `Sources/App/LandlordHoursApp.swift` → `AppSpacing` enum.

| Token   | Value  | Usage                         |
|---------|--------|-------------------------------|
| `xxs`   | 4pt    | Tight internal spacing        |
| `xs`    | 8pt    | Icon-to-text gaps             |
| `sm`    | 12pt   | Compact card padding          |
| `md`    | 16pt   | Standard padding              |
| `lg`    | 20pt   | Section padding (horizontal)  |
| `xl`    | 24pt   | Section spacing (vertical)    |
| `xxl`   | 32pt   | Large section gaps            |
| `xxxl`  | 48pt   | Major layout separation       |

### Layout Conventions

- Horizontal page padding: `20pt` (`.padding(.horizontal, 20)`)
- Vertical section spacing: `24pt` (VStack spacing)
- Card internal spacing: `12–16pt`
- Bottom scroll padding: `40pt`

---

## Corner Radius

Defined in `Sources/App/LandlordHoursApp.swift` → `AppCornerRadius` enum.

| Token    | Value | Usage                       |
|----------|-------|-----------------------------|
| `small`  | 8pt   | Small buttons, tags         |
| `medium` | 12pt  | Cards, input fields         |
| `large`  | 16pt  | Modal sheets, large cards   |
| `xl`     | 20pt  | Bottom sheets, containers   |

- Pill/capsule buttons use `Capsule()` clipShape
- Status badges use `Capsule()` clipShape

---

## Animation Presets

Defined in `Sources/App/LandlordHoursApp.swift` → `AppAnimation` enum.

| Token      | Definition                                     | Usage                   |
|------------|------------------------------------------------|-------------------------|
| `quick`    | `easeInOut(duration: 0.15)`                    | Micro-interactions      |
| `standard` | `easeInOut(duration: 0.24)`                    | State transitions       |
| `smooth`   | `spring(response: 0.28, dampingFraction: 0.9)` | Smooth reveals          |
| `feedback` | `easeOut(duration: 0.12)`                      | Press feedback          |
| `reveal`   | `easeOut(duration: 0.22)`                      | Toasts and small reveals |
| `flow`     | `spring(response: 0.34, dampingFraction: 0.88)` | In-flow expansion       |
| `bouncy`   | `spring(response: 0.32, dampingFraction: 0.86)` | Selective playful feedback |

- Progress ring: `spring(response: 0.7, dampingFraction: 0.82)`
- Pill pop: `spring(response: 0.26, dampingFraction: 0.82)`
- Logo entrance: `spring(response: 0.45, dampingFraction: 0.86)`
- Use `.lhMotion(..., value:)` for implicit animation so reduced-motion settings are honored.
- Use `.buttonStyle(.lhPressable)` for custom tappable buttons, chips, and capsule controls.
- Motion should clarify cause and effect: field expansion, selected state, saved confirmation, progress change. Avoid decorative page-load choreography.

---

## Icon System (2.0)

Two tiers, nothing else (`docs/design/2.0-brand-system.md` §4):

1. **SF Symbols for everything functional** — tab bar, toolbars, buttons, badges, Settings, widgets, Live Activity, the Dynamic Island. They tint, carry weight, follow Dynamic Type and render in accented/tinted modes. Weights: `.regular` in lists at 17–22pt, `.semibold` inline with semibold text; filled circle variants for status; filled variants for the selected tab.
2. **3D tool renders on a plaster tile (36–48pt)** for category rows, Inbox, the category picker and the milestone share (to be re-made from the Blender material set; WP-R).

**Lucide is retired.** Do not add new `Lucide.*`, `LucideIcon(...)` or Lucide string names. As of WP-D (2026-10-19) 361 `Lucide.*` references remain across 24 files (plus `JellyBadge` string lookups and `LHIcons.swift`); they map one-to-one to SF Symbols and go screen by screen in the WP-R reskin, after which the `LucideIcons` package is dropped from `project.yml`. `LHIcon` tab glyphs are retired too (the shell uses SF Symbols).

- `JellyBadge(systemName:)` still resolves a Lucide name first, then an SF Symbol; pass SF Symbol names in new code.
- SF Symbols remain the category-picker icons (`availableCategoryIcons`).

### Navigation shell (2.0)

`Sources/Views/ContentView.swift`: a floating glass capsule with four tabs — **Today** (Dashboard), **Inbox** (placeholder until WP3), **Records** (History), **Properties** — and a separate round **+** (log time / Track). Liquid Glass (`.glassEffect`) on iOS 26+, solid card fill before. Reports and Settings open from Today's header. Integer tab indices keep their 1.x meaning (`ShellTab` in `Sources/App/AppDestination.swift`: 0 Today, 1 Properties, 2 Log time, 3 Reports, 4 Settings, 5 Inbox, 6 Records) so `.switchToTab`, `-LHInitialTab`, intents and deep links resolve. UI tests address tabs by identifier: `tab.today`, `tab.inbox`, `tab.records`, `tab.properties`, `tab.logTime`.

---

## Component Patterns

### View Architecture

Every view follows this adaptive color pattern:

```swift
struct ExampleView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(colors.background)
        }
    }
}
```

### Cards

Cards use white (light) or `darkBackgroundSecondary` (dark) backgrounds:

```swift
.background(colors.backgroundSecondary)
.clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
```

### Primary Buttons

```swift
Button { /* action */ } label: {
    Text("Button Label")
        .font(.system(size: 16, weight: .semibold))
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(colors.action)
        .foregroundStyle(AppColors.onAction)
        .clipShape(Capsule())
}
```

### Empty States

```swift
VStack(spacing: 20) {
    LHSoftBadge(icon: .someIcon, color: AppColors.primary, size: 72)
    Text("Title Text")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(colors.textPrimary)
    Text("Description text")
        .font(.system(size: 15))
        .foregroundStyle(colors.textSecondary)
        .multilineTextAlignment(.center)
    // CTA button
}
```

### Status Badges / Capsule Labels

```swift
Text("LABEL")
    .font(.system(size: 10, weight: .bold))
    .tracking(0.6)
    .foregroundStyle(colors.positive)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(colors.positiveSurface)
    .clipShape(Capsule())
```

### View Modifiers

- `.formDarkBackground()` — For Form/List views to override background
- `.adaptiveText(isSecondary:, isTertiary:)` — Apply adaptive text colors
- `.adaptiveCard()` — Apply adaptive card background
- `.adaptiveBackground(colorScheme)` — Apply adaptive page background

---

## File Organization

```
Sources/
├── App/
│   ├── LandlordHoursApp.swift    ← Design system tokens (Colors, Typography, Spacing, Radius, Animation)
│   ├── LHLogo.swift              ← Logo components (LHLogo, LHCompactLogo, LHWordmark)
│   └── LHIcons.swift             ← Tab bar icons (LHIcon), Lucide bridge (LucideIcon), JellyBadge
├── Models/
│   └── Models.swift              ← Data models (RentalProperty, TimeEntry, ActivityCategory, etc.)
├── ViewModels/
│   └── AppViewModel.swift        ← Main app state
├── Views/
│   ├── ContentView.swift         ← Root view with tab bar
│   ├── DashboardView.swift       ← Home tab
│   ├── PropertiesView.swift      ← Properties tab
│   ├── TimeLogView.swift         ← Track tab (timer)
│   ├── HistoryView.swift         ← Time entry history
│   ├── ReportsView.swift         ← Reports tab
│   ├── SettingsView.swift        ← Settings tab
│   ├── OnboardingView.swift      ← Onboarding flow
│   ├── PaywallView.swift         ← Subscription paywall
│   ├── TasksView.swift           ← Task management
│   ├── CategoryPickerSheet.swift ← Category selection
│   ├── CategoryManagementView.swift ← Custom category CRUD
│   ├── ExportPDFView.swift       ← PDF report export
│   ├── TrialBannerView.swift     ← Trial period banner
│   ├── ContactSupportView.swift  ← Support contact
│   └── Components/
│       └── AppDesignSystem.swift  ← View modifiers (formDarkBackground)
└── Services/
    ├── SubscriptionManager.swift ← In-app purchases
    ├── AppleSignIn.swift         ← Authentication
    └── AITimeEntryService.swift  ← AI-assisted time logging
```

### Naming Conventions

- **Views:** PascalCase with `View` suffix (e.g., `DashboardView`)
- **Models:** PascalCase (e.g., `RentalProperty`, `TimeEntry`)
- **Enums:** PascalCase (e.g., `ActivityCategory`, `PropertyType`)
- **Design tokens:** PascalCase enum + camelCase statics (e.g., `AppColors.primaryLight`)
- **Icon components:** `LH` prefix (e.g., `LHIcon`, `LHLogo`, `LHCircleBadge`)

---

## Figma MCP Integration Rules

### Required Flow (do not skip)

1. Run `get_design_context` first to fetch the structured representation for the exact node(s)
2. If the response is too large or truncated, run `get_metadata` to get the high-level node map, then re-fetch only the required node(s) with `get_design_context`
3. Run `get_screenshot` for a visual reference of the node variant being implemented
4. Only after you have both `get_design_context` and `get_screenshot`, download any assets needed and start implementation
5. Translate the output into SwiftUI following this project's design system tokens, components, and architecture
6. Validate against Figma for 1:1 look and behavior before marking complete

### Implementation Rules

- Treat the Figma MCP output as a representation of design and behavior, not final code style
- IMPORTANT: Replace any hardcoded colors with `AppColors.*` tokens or `AdaptiveColors` properties
- IMPORTANT: Reuse existing components from `Sources/Views/` and icons from `LHIcons.swift` instead of duplicating
- Use the project's spacing scale (`AppSpacing.*`), corner radius (`AppCornerRadius.*`), and typography (`AppTypography.*`)
- All new views must support dark mode via `AdaptiveColors`
- Follow the MVVM pattern: views observe `@EnvironmentObject var viewModel: AppViewModel`

### Asset Handling

- IMPORTANT: If the Figma MCP server returns a localhost source for an image or SVG, use that source directly
- IMPORTANT: Use Lucide icons (`import LucideIcons`) for all new UI icons — do NOT add other icon packages
- IMPORTANT: DO NOT use or create placeholders if a localhost source is provided
- Store downloaded image assets in `Assets.xcassets`

---

## Key Domain Concepts

- **REPS:** IRS Real Estate Professional Status — requires more than 750 hours/year in real estate activities AND the 50% rule (RE hours > 50% of total working hours)
- **Material Participation Tests:** Test 1 = 500h, Test 3 = 100h. Different from REPS — no 50% rule required
- **50% Rule:** Working time must be ≥50% in real estate to qualify. Only applies to REPS, not Material Participation
- **LTR/STR:** Long-Term Rental / Short-Term Rental property types. STR (avg stay <7 days) is automatically non-passive — different tax treatment
- **Participants:** Self and Spouse — tracked separately. For REPS (750h + more-than-half test), ONE spouse must meet both tests individually; spouse hours never combine (IRC 469(c)(7)(B)). For material participation, spouse hours DO count together when filing jointly.
- **Grouping Election:** IRS allows grouping multiple properties as single activity for material participation. Important for multi-property landlords

---

## Xcode Build Rules (MANDATORY)

- **DerivedData**: ALWAYS pass `-derivedDataPath /Volumes/Home/DerivedData` when running `xcodebuild`. The boot disk is only 228GB. Never use the default ~/Library/Developer/Xcode/DerivedData/.
- **Simulators**: Local simulators OK — device files symlinked to external SSD. Use Device Hub to manage. Max 1-2 at a time (16GB RAM). Always use `-derivedDataPath /Volumes/Home/DerivedData`.
- **Temp files**: Build artifacts in /tmp fill the boot disk. Prefer `/Volumes/Home/tmp` for large intermediate files.
