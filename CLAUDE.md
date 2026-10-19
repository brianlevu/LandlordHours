# LandlordHours Design System

> **App Name:** LandlordHours
> **Tagline:** *"Track your path to tax qualification"*
> **Platform:** iOS 17.0+ (SwiftUI)
> **Architecture:** MVVM
> **Design Style:** 2.0 "Blueprint" — honest, crafted, earned (docs/design/2.0-brand-system.md). Violet and Lucide are retired.

For full-screen-by-screen design audits, use `docs/design-audit-playbook.md` before changing UI.

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
│   ├── TaxYearView.swift         ← Annual tax year view
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
    ├── WeeklySummaryService.swift ← Weekly digest
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

## Figma Redesign — Implementation Specs

> **Superseded for colour, type and icons by the 2.0 brand system** (see Brand Identity above). The violet palettes, DM Serif/DM Sans and the Lucide/LHIcon tab glyphs below describe 1.x; keep the layout notes only where 2.0 docs say nothing.

> **Figma File:** `Mikfhrs0aGwyzgYQd3Utpu`
> **HTML Mockups:** `figma-redesign/` directory — these are the **source of truth** for implementation, not the Figma captures
> **Design Language:** Tiimo-inspired, soft rounded UI, DM Serif Display + DM Sans fonts

### Figma vs Implementation Fidelity

The Figma captures lose some visual fidelity due to HTML-to-design limitations:
- No `backdrop-filter: blur()` — glass effects flatten
- No CSS animations or spring physics
- SVG `stroke-dasharray` segmented tracks render as solid
- `filter: blur()` floating blobs disappear
- Gradient vibrancy is reduced

**IMPORTANT:** Always reference the HTML mockups (open in browser) as the true design target. SwiftUI natively supports all these effects and will look **better** than the HTML:
- `Circle().trim(from:to:).stroke()` for ring progress
- `.animation(.spring(response:dampingFraction:))` for spring physics
- `.ultraThinMaterial` and `.blur()` for glass effects
- `LinearGradient` / `MeshGradient` for backgrounds
- `withAnimation(.spring())` for interactive transitions

---

### Screen: Reports — Interactive Goal Switcher

**Reference file:** `figma-redesign/reports-v3.html`
**Figma node:** `33:2` (Reports — Interactive Goal Switcher)

#### Architecture

Single view with 3 goal modes driven by one data source. All UI elements (background, ring, pills, stats, properties) react to the selected goal.

```swift
// Data model — single source of truth
struct GoalMode {
    let type: GoalType           // .reps750, .mp500, .mp100
    let outerTarget: CGFloat     // ring fill ratio (0...1)
    let innerTarget: CGFloat     // inner ring fill ratio (0 for MP goals)
    let showInnerRing: Bool      // true only for REPS
    let outerGradient: [Color]   // ring stroke gradient
    let innerGradient: [Color]   // inner ring gradient
    let accent: Color            // pill active color, link color
    let backgroundPalette: BackgroundPalette
    let isMet: Bool              // triggers celebration state
    // ... stats, pace, properties
}
```

#### Dual-Ring Progress Indicator

- **Outer ring:** 18pt stroke, r=108 in 260x260 viewBox. Circumference = 2π×108 ≈ 679
- **Inner ring:** 10pt stroke, r=82. Circumference = 2π×82 ≈ 515. Only visible for REPS (shows 50% rule)
- **Track background:** Segmented dashes (stroke-dasharray equivalent). Use `.dash([3, 5])` modifier in SwiftUI
- **Progress fill:** Gradient stroke with spring animation
- **Ambient glow:** Radial gradient behind ring, 240×240pt, transitions color per goal

```swift
// SwiftUI ring implementation
Circle()
    .trim(from: 0, to: progress)
    .stroke(
        LinearGradient(colors: goal.outerGradient, startPoint: .leading, endPoint: .trailing),
        style: StrokeStyle(lineWidth: 18, lineCap: .round)
    )
    .rotationEffect(.degrees(-90))
    .frame(width: 260, height: 260)
    .animation(.spring(response: 0.8, dampingFraction: 0.75), value: progress)
```

#### Spring Physics Values

| Parameter | Value | SwiftUI Equivalent |
|-----------|-------|--------------------|
| Stiffness | 0.065 | `response: 0.8` |
| Damping | 0.78 | `dampingFraction: 0.75` |
| Threshold | 0.15 | Automatic in SwiftUI |

For the ring progress animation, use:
```swift
.animation(.spring(response: 0.8, dampingFraction: 0.75), value: goalProgress)
```

For pill bounce feedback:
```swift
.animation(.spring(response: 0.45, dampingFraction: 0.6), value: selectedGoal)
// Scale: 1.0 → 1.08 → 0.97 → 1.0
```

#### Goal-Specific Color Palettes

**REPS 750h (Muted Lavender)**
| Element | Value |
|---------|-------|
| Outer ring gradient | `#8B5CF6` → `#A78BFA` |
| Inner ring gradient | `#34D399` → `#6EE7B7` |
| Track outer | `#EDE9FE` |
| Track inner | `#ECFDF5` |
| Accent | `#8B5CF6` |
| Background | `linear-gradient(145deg, #DDD8EE → #E4DDFA → #ECE6FF → #F2EEFF → #F7F3FF → #FAF7F2)` |
| Blob colors | `rgba(139,92,246,0.15)`, `rgba(167,139,250,0.10)` |

**Material Participation 500h (Warm Purple/Coral)**
| Element | Value |
|---------|-------|
| Outer ring gradient | `#8B5CF6` → `#C084FC` |
| Inner ring | Hidden (showInner: false) |
| Accent | `#A855F7` |
| Background | `linear-gradient(145deg, #DDE0EE → #E4DCF5 → #EEDDEE → #F5E6EF → #FAEFF0 → #FFF8F5)` |
| Blob colors | `rgba(168,85,247,0.14)`, `rgba(244,114,182,0.08)` |

**Material Participation 100h — Goal Met (Green Celebration)**
| Element | Value |
|---------|-------|
| Outer ring gradient | `#34D399` → `#6EE7B7` |
| Ring fills to 100% | Full circle |
| Accent | `#059669` |
| Background | `linear-gradient(145deg, #D5E8DD → #DAEFDF → #DFFAE5 → #E5FAEB → #EDFFF0 → #F5FFF8)` |
| Center text | Checkmark icon + "Goal met!" in `#059669` |
| Blob colors | `rgba(52,211,153,0.15)`, `rgba(110,231,183,0.10)` |

#### Background Gradient Morphing

- 3 pre-defined gradient layers, crossfaded via opacity (0.9s cubic-bezier)
- In SwiftUI: use `LinearGradient` with animated color stops, or layer 3 gradients with `.opacity()` transitions
- 2 floating blobs: large circles with `.blur(radius: 70)` and `.blur(radius: 60)`, positioned at corners
- Blob colors and positions transition per goal selection

#### Ring Center Content

- **Normal state:** Large number (52px bold) + "of X hours" label (14px)
- **Goal met state:** Checkmark icon (32×32) + "Goal met!" label (16px bold, `#059669`)
- **Transition:** Crossfade (opacity 0→1 with 250ms delay after fade-out)

#### Stat Row

3 equal-width chips with glass background (`rgba(255,255,255,0.65)` + blur):
- Chip 1: Remaining hours
- Chip 2: Days left in year
- Chip 3: 50% Rule percentage (REPS) / Complete percentage (MP) / Test status (100h met)

#### Property Cards

- Color bar accent (4×40pt, rounded) matching property's assigned color
- Property name + meta (type + location or hours progress)
- Horizontal progress bar with gradient fill
- Hours/percentage on right side

---

### Screen: Track Time — AI-Assisted Entry

**Reference file:** `figma-redesign/track-v3.html`
**Figma node:** `13:2` (Track Time — V3)

3 states in a single flow:

#### State 1: Empty
- Greeting: "Track Time" (DM Serif Display 28px) + date subtitle
- Notes textarea with subtle border (`--snow`)
- AI hint: sparkle icon + "Describe your work and we'll fill in the details" (12px, `--mist`)
- Category chips: horizontal scroll, 11 categories with color dots
- Property picker: icon + "Select property" + chevron
- Hours stepper: -/+ buttons (44×44pt circles) + large display (DM Serif 40px)
- Date picker row
- Participant segment: Self / Spouse toggle
- Attach receipt button
- "Log Time" primary button (full-width capsule, `--violet`)

#### State 2: AI Suggestion Active
- Notes filled with user text, border changes to `--violet-soft`
- AI suggestion bar appears: purple sparkle badge + detected chips (Category, Property, Hours) + "Auto-fill" button
- All other fields remain in empty/default state

#### State 3: After Auto-fill
- Notes unchanged
- Green checkmark + "Auto-filled from your description" confirmation
- Category chip auto-selected (highlighted in `--violet`)
- Property auto-selected (shows name instead of placeholder)
- Hours auto-set (e.g., 2.0h)
- "Log Time" button ready

#### Key UI Specs
- Card padding: 20px, border-radius: 20px
- Category chips: `padding: 10px 16px`, `border-radius: 999px`, `font-size: 13px`
- Active chip: `background: var(--violet)`, `color: white`
- AI suggestion bar: `background: var(--violet-wash)`, `border: 1.5px solid var(--violet-soft)`, `border-radius: 14px`
- AI sparkle badge: 28×28px, `border-radius: 8px`, `background: var(--violet)`, white star icon

---

### Screen: Onboarding Flow

**Reference file:** `figma-redesign/onboarding-full.html`
**Figma node:** `25:2` (LandlordHours — Complete Onboarding Flow)

7 screens (A through G):

| Screen | Title | Purpose |
|--------|-------|---------|
| A. Welcome | "Track your path to tax qualification" | Logo, tagline, "Get Started" CTA |
| B. Goal | "What's your goal?" | 3 goal cards: REPS 750h (recommended), General Hour Tracking, Material Participation |
| C. Review | "Your tracking plan" | Summary of selected goal with explanation |
| D. Property | "Add your first property" | Property type toggle (LTR/STR) + Who manages (3 radio cards: Self / Me & Spouse / Property Manager) + Address form |
| E. Permissions | "Stay on track" | 3 permission cards: Notifications, Calendar sync, Location detection |
| F. AI Demo | "AI does the heavy lifting" | Animated mockup of AI auto-fill feature |
| G. Complete | "You're all set" | Motivational message + "Start Tracking" CTA |

#### Screen D Details (Property Setup)
- **Property Type toggle:** LTR / STR segment control
- **Management cards:** 3 selection cards with icon + title + description + radio button
  - "Just me" — person icon — "I self-manage this property"
  - "Me & spouse" — two-person icon — "We manage together (counts toward 50% rule)"
  - "Property manager" — building icon — "Professional management company"
- **Address form:** Property Name + Street Address text fields
- **Section divider** between management cards and address form

#### Onboarding Shared Specs
- Progress bar at top: thin rounded track, `height: 3px`, fill gradient `#7B68EE → #A78BFA`
- Navigation: Back arrow (top-left) + Skip link (top-right, `13px 600 #A8A8BC`)
- Primary CTA: full-width capsule button, `padding: 16px`, `border-radius: 999px`, `background: #7B68EE`
- Screen background: white `#FFFFFF`
- Content padding: `24px` horizontal

---

### Screen: Property Setup + Tax Profile

**Reference file:** `figma-redesign/property-and-tax-profile.html`
**Figma node:** `22:2` (Property Setup + Tax Profile)

2 screens side by side:

#### Add Property (Updated)
- Property type toggle (LTR/STR)
- Management selection cards (3 options with radio buttons)
- Address fields
- "Add Property" primary CTA

#### Tax Profile Setup
- "Spouse Hours" toggle — enables/disables spouse tracking
- 50% Rule tracking explanation
- "Determines your Reports dashboard" subtitle
- Filing status, tax year settings

---

### Tab Bar (All Screens)

5 tabs: Home, Properties, Track, Reports, Settings

| Tab | Icon | Active Color |
|-----|------|-------------|
| Home | House + circle | `#7B68EE` (system) / `#8B5CF6` (reports) |
| Properties | Two stacked cards | Same |
| Track | Clock circle | Same |
| Reports | Bar chart (3 bars) | Same |
| Settings | Gear/sun | Same |

- Tab bar: `height: 80px`, glass background (`rgba(255,255,255,0.85)` + blur 20px)
- Active tab: colored icon + text + 4px dot indicator below text
- Inactive: `#C4C4D4` (reports) / `var(--mist)` (#A8A8BC in other screens)
- Font: 10px weight 500

---

### Figma Redesign Color Tokens (Expanded)

These colors extend the base design system for the redesigned screens:

| Token | Hex | Context |
|-------|-----|---------|
| `reportsAccent` | `#8B5CF6` | Reports ring, pills, active states |
| `reportsAccentSoft` | `#A78BFA` | Gradient end, secondary accent |
| `reportsAccentWash` | `#EDE9FE` | Track background, year badge bg |
| `mpAccent` | `#A855F7` | Material Participation 500h accent |
| `mpAccentWash` | `#F3E8FF` | MP 500h backgrounds |
| `successGreen` | `#059669` | Goal met state, qualified badge |
| `successGreenLight` | `#34D399` | Progress fill (green), inner ring |
| `successGreenWash` | `#ECFDF5` | Track inner bg, pace badge bg |
| `successGreenSoft` | `#6EE7B7` | Gradient end, celebration ring |
| `charcoal` | `#1A1A2E` | Primary text, ring center number |
| `ink` | `#2D2D3F` | Secondary text |
| `slate` | `#6E6E82` | Inactive pills, labels |
| `mist` | `#A8A8BC` | Subtitles, ring label, stat labels |
| `cloud` | `#D4D4E0` | Borders, inactive elements |
| `snow` | `#F0EFF4` | Input backgrounds, segment bg |
| `cream` | `#FAF7F2` | Page backgrounds |

### CSS Custom Properties → SwiftUI Mapping

```swift
// Map HTML CSS vars to SwiftUI
extension AppColors {
    static let reportsAccent = Color(hex: "#8B5CF6")
    static let reportsAccentSoft = Color(hex: "#A78BFA")
    static let reportsAccentWash = Color(hex: "#EDE9FE")
    static let successGreen = Color(hex: "#059669")
    static let successGreenLight = Color(hex: "#34D399")
    static let successGreenWash = Color(hex: "#ECFDF5")
    static let charcoal = Color(hex: "#1A1A2E")
    static let ink = Color(hex: "#2D2D3F")
    static let slate = Color(hex: "#6E6E82")
    static let mist = Color(hex: "#A8A8BC")
    static let snow = Color(hex: "#F0EFF4")
    static let cream = Color(hex: "#FAF7F2")
}
```

---

### Typography (Redesign Specific)

| Element | Font | Size | Weight | Tracking |
|---------|------|------|--------|----------|
| Screen title (Reports) | DM Serif Display | 28px | Regular | 0 |
| Ring center number | DM Sans | 52px | 800 (Extra Bold) | -2px |
| Ring label | DM Sans | 14px | 500 | 0 |
| Goal pill | DM Sans | 13px | 600 | 0 |
| Stat value | DM Sans | 18px | 700 | 0 |
| Stat label | DM Sans | 11px | 500 | 0 |
| Section title | DM Sans | 17px | 700 | 0 |
| Property name | DM Sans | 15px | 600 | 0 |
| Greeting name (Track) | DM Serif Display | 28px | Regular | 0 |
| Stepper value (Track) | DM Serif Display | 40px | Regular | 0 |

In SwiftUI, map DM Serif Display to `.system(design: .serif)` and DM Sans to `.system(design: .default)`.

---

*Design System v2.0 — February 2026*


## Xcode Build Rules (MANDATORY)

- **DerivedData**: ALWAYS pass `-derivedDataPath /Volumes/Home/DerivedData` when running `xcodebuild`. The boot disk is only 228GB. Never use the default ~/Library/Developer/Xcode/DerivedData/.
- **Simulators**: Local simulators OK — device files symlinked to external SSD. Use Device Hub to manage. Max 1-2 at a time (16GB RAM). Always use `-derivedDataPath /Volumes/Home/DerivedData`.
- **Temp files**: Build artifacts in /tmp fill the boot disk. Prefer `/Volumes/Home/tmp` for large intermediate files.
