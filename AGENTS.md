# LandlordHours Design System

> **App Name:** LandlordHours
> **Tagline:** *"Track your path to tax qualification"*
> **Platform:** iOS 17.0+ (SwiftUI)
> **Architecture:** MVVM
> **Design Style:** Tiimo-inspired — soft, rounded, friendly, modern

For full-screen-by-screen design audits, use `docs/design-audit-playbook.md` before changing UI.

---

## Brand Identity

### Logo

- **Primary Logo:** `LHLogo` — House + clock composite icon inside a purple gradient circle
- **Compact Logo:** `LHCompactLogo` — Same mark at smaller sizes (32pt default) for nav bars/headers
- **Wordmark:** `LHWordmark` — "Landlord" (dark) + "Hours" (purple accent)
- **Logo gradient:** `#8B5CF6` → `#6D28D9` (top-leading → bottom-trailing)
- File: `Sources/App/LHLogo.swift`

### Logo Usage

```swift
LHLogo(size: 80, showText: true, animated: false)   // Full logo with text
LHCompactLogo(size: 32)                               // Nav bar / header
LHWordmark(fontSize: 28)                               // Text-only
```

---

## Color System

All colors defined in `Sources/App/LandlordHoursApp.swift` → `AppColors` enum.

### Light Theme

| Token                   | Hex       | Usage                               |
|-------------------------|-----------|--------------------------------------|
| `background`            | `#F5F5F5` | Page backgrounds                     |
| `backgroundSecondary`   | `#FFFFFF` | Cards, sheets                        |
| `backgroundTertiary`    | `#EBEBEB` | Inputs, tags, subtle surfaces        |
| `primary`               | `#7C6FF7` | Buttons, accents, tab tint           |
| `primaryLight`          | `#A78BFA` | Gradients, secondary accents         |
| `primarySurface`        | `#EDE9FE` | Lavender tint for badge backgrounds  |
| `primaryDark`           | `#6355E8` | Pressed states                       |
| `success`               | `#34D399` | Progress met, qualified indicators   |
| `warning`               | `#FBBF24` | Near-goal alerts                     |
| `error`                 | `#F472B6` | Errors, delete actions               |
| `info`                  | `#60A5FA` | Informational badges                 |
| `textPrimary`           | `#0D0D0D` | Headlines, body text                 |
| `textSecondary`         | `#6B7280` | Captions, labels                     |
| `textTertiary`          | `#9CA3AF` | Placeholders, disabled text          |
| `border`                | `#D1D5DB` | Card borders, dividers               |
| `borderLight`           | `#E5E7EB` | Subtle separators                    |

### Dark Theme

| Token                      | Hex/Value          | Usage                          |
|----------------------------|--------------------|--------------------------------|
| `darkBackground`           | `#0D0D0D`          | Page backgrounds               |
| `darkBackgroundSecondary`  | `#1C1C1C`          | Cards, sheets                  |
| `darkBackgroundTertiary`   | `#2A2A2A`          | Inputs, tags                   |
| `darkPrimarySurface`       | `#2D2A4A`          | Lavender tint for dark mode    |
| `darkPrimary`              | `#9D8FF5`          | Primary actions in dark mode   |
| `darkTextPrimary`          | `Color.white`      | Headlines                      |
| `darkTextSecondary`        | `rgb(0.68,0.70,0.74)` | Captions                    |
| `darkTextTertiary`         | `rgb(0.48,0.50,0.54)` | Placeholders                |
| `darkBorder`               | `rgb(0.28,0.28,0.30)` | Card borders                |

### Adaptive Colors (Color-Scheme Aware)

Use `AdaptiveColors` in views to automatically resolve light/dark:

```swift
@Environment(\.colorScheme) var colorScheme
private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

// Usage:
.foregroundStyle(colors.textPrimary)
.background(colors.background)
```

### Intent-Based Color Framework

Use semantic intent first, raw hue names second. New UI should prefer the intent aliases in `AppColors` / `AdaptiveColors`:

| Intent role | Token(s) | Meaning | Use for | Do not use for |
|-------------|----------|---------|---------|----------------|
| Primary action | `AppColors.action`, `colors.action`, `colors.actionSurface`, `AppColors.onAction` | The thing the user should do next | Primary CTAs, selected navigation, focus, links, AI assistance before completion | Success, healthy progress, decorative badges |
| Positive | `AppColors.positive`, `colors.positive`, `colors.positiveSurface` | Success, qualified, complete, healthy | Saved states, Pro active, qualified badges, goal met, completed lessons | Primary CTAs before the user has completed anything |
| Caution | `AppColors.caution`, `colors.caution`, `colors.cautionSurface` | Warning or needs attention | Behind pace, near-deadline, incomplete setup, risky audit conditions | Generic emphasis |
| Destructive | `AppColors.destructive`, `colors.destructive`, `colors.destructiveSurface` | Delete, error-adjacent, repair/maintenance emphasis | Delete actions, destructive confirmations, repair category accent | Primary actions or success |
| Informational | `AppColors.informational`, `colors.informational`, `colors.informationalSurface` | Informational/system context | Calendar import, sync, external data, neutral explainers | Warning or success states |
| Human/spouse | `AppColors.rose`, `colors.rose`, `colors.roseWash` | People and household participation | Spouse, participant, shared-management emphasis | Error/destructive actions |

### IMPORTANT Color Rules

- IMPORTANT: Violet/action is the primary brand/action color. A screen's main CTA should use `colors.action` and `AppColors.onAction` unless it is explicitly destructive.
- IMPORTANT: Sage/positive is reserved for success, qualified, complete, healthy progress, and active Pro/member states. Do not use green for ordinary "continue", "add", "save", "review", or "upgrade" buttons.
- IMPORTANT: Honey/caution means warning or needs attention. Coral/destructive means delete/error-adjacent or repair/maintenance. Sky/informational means imports, calendar, sync, or neutral information.
- IMPORTANT: Never hardcode hex values inline in views. Add a token in `AppColors` or use `AdaptiveColors`.
- IMPORTANT: Every view must support dark mode via `AdaptiveColors`.
- IMPORTANT: Avoid assigning color by aesthetics alone. Every non-neutral color must answer: action, positive, caution, destructive, informational, category, or human/spouse.
- Category-specific colors are allowed for user-customizable categories, but category color must not override action/state semantics.

---

## Typography

Defined in `Sources/App/LandlordHoursApp.swift` → `AppTypography` enum.

| Token           | Size | Weight    | Usage                        |
|-----------------|------|-----------|------------------------------|
| `largeTitle`    | 34   | Bold      | Main screen titles           |
| `title1`        | 28   | Bold      | Section headers (dashboard)  |
| `title2`        | 22   | Bold      | Card titles                  |
| `title3`        | 20   | Semibold  | Sub-section headers          |
| `headline`      | 17   | Semibold  | Emphasized body text         |
| `bodyLarge`     | 17   | Regular   | Primary body text            |
| `body`          | 15   | Regular   | Standard body text           |
| `bodySmall`     | 13   | Regular   | Compact body text            |
| `subheadline`   | 15   | Regular   | Secondary descriptions       |
| `footnote`      | 13   | Regular   | Fine print                   |
| `caption`       | 12   | Regular   | Timestamps, metadata         |
| `buttonLarge`   | 17   | Semibold  | Primary buttons              |
| `button`        | 15   | Semibold  | Standard buttons             |
| `buttonSmall`   | 13   | Semibold  | Compact/inline buttons       |

### Typography Patterns

- **Dashboard headers:** `.system(size: 28, weight: .bold, design: .serif)`
- **Progress numbers:** `.system(size: 46, weight: .bold, design: .rounded)`
- **Logo/brand text:** `.system(weight: .bold, design: .rounded)`
- **Status labels:** `.system(size: 10, weight: .bold)` with `.tracking(0.6)` uppercase
- IMPORTANT: Use `AppTypography.*` tokens for consistency

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

## Icon System

Three icon systems are used, each with a specific role. All defined in `Sources/App/LHIcons.swift`.

### 1. LHIcon (Custom SwiftUI Shapes) — Tab Bar Only

Hand-drawn SwiftUI `Shape` paths in a 24×24 grid. **Used exclusively for the tab bar.**

```swift
// Tab bar image (for .tabItem)
LHIcon.home.tabItemImage
```

Tab icons: `home`, `properties`, `track`, `reports`, `settings`

### 2. Lucide Icons (Primary Icon Library) — All UI

Imported via SPM: `lucide-icons-swift` v0.575.0. Used for all in-app icons.

```swift
import LucideIcons

// Type-safe usage (preferred — compile-time checked):
LucideIcon(image: Lucide.clock, size: 20)

// Inside JellyBadge (string-based, kebab-case):
JellyBadge(systemName: "clock", color: AppColors.primary)
```

**JellyBadge** (`LandlordHoursApp.swift`) resolves icons with a two-step fallback:
1. Try `UIImage(lucideId: systemName)` — Lucide lookup by kebab-case asset name
2. Fall back to `Image(systemName:)` — SF Symbol

IMPORTANT: When passing string icon names to JellyBadge, use **Lucide kebab-case asset names** (e.g., `"file-text"`, `"building-2"`, `"badge-check"`), NOT SF Symbol names.

### 3. SF Symbols — Category Picker Only

SF Symbols are used **only** for user-customizable category icons in `availableCategoryIcons` array and `CategoryManagementView`/`CategoryPickerSheet` (via `Image(systemName:)`).

### IMPORTANT Icon Rules

- IMPORTANT: Use **Lucide icons** for all new UI. Use type-safe `Lucide.*` properties when possible (compile-time checked). Use string-based kebab-case names only when dynamic lookup is needed (e.g., JellyBadge).
- IMPORTANT: Use **LHIcon** only for tab bar icons via `.tabItemImage`.
- IMPORTANT: Use **SF Symbols** only in `availableCategoryIcons` for user-customizable category icons.
- IMPORTANT: When adding a new string-based icon reference, verify the kebab-case name exists in the Lucide package (`Lucide+iOS.swift`).

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
- **Participants:** Self and Spouse — tracked separately for 50% rule compliance. Spouse hours can count toward REPS if filing jointly
- **Grouping Election:** IRS allows grouping multiple properties as single activity for material participation. Important for multi-property landlords

---

## Figma Redesign — Implementation Specs

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
