# LandlordHours Design System

> **App Name:** LandlordHours
> **Platform:** iOS 17.0+ (SwiftUI)
> **Architecture:** MVVM
> **Design Style:** Blueprint — drafting-paper canvas, SF type, one tool-render house; calm and plain-spoken

The bar is `docs/design/DESIGN-STANDARD.md`. Brand tokens and the blueprint world are in `docs/design/2.0-brand-system.md`. For full-screen audits use `docs/design-audit-playbook.md` before changing UI.

---

## Design standard (replaces the 1.x Tiimo/violet/Lucide rules)

Every rule in the standard is tagged **[measured]**, **[grep]** or **[judgment]**. Builders run the checks below and put the numbers in the hand-off; the gate re-measures.

**Colour.** Blueprint blue `#1E3FA6` is the brand and the light action colour; drafting cyan `#8FD3FF` is the dark action colour. Violet is retired. Tokens and contrast are in `docs/design/2.0-brand-system.md` §2; usage rules are in `docs/design/DESIGN-STANDARD.md`. Intent first: action, positive, caution, destructive, informational. Never hardcode a hex in a view; add a token or use `AdaptiveColors`. Every view supports dark mode.

**Type.** SF Pro / SF Pro Rounded (numbers, tabular) / SF Mono (drafting labels, 11pt caps) / Fraunces (tab titles and display, ≥ 28pt only). DM Serif Display and DM Sans are retired. Use text styles, not `.system(size:)`.

**Layout.** Gutter 20, section gap 24, header to content 8, card padding 16. Headers come only from the screen scaffolds (`.lhTabScreen`, `.lhSheetScreen`; standard §S): a screen never places its own title or top inset. Rows live in one grouped container with hairline dividers; a card per list item is a defect.

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
python3 scripts/qa/frame_check.py consistency <inbox> <records> <rentals> <settings> --hero <today> --sheet <logtime>  # Screen anatomy S1-S3 across tabs: one title baseline (<=1pt), one header-to-content gap (<=2pt)
```

`scripts/qa/gate_rubric.md` is the addendum the `visual-gate` agent applies, including the written anchor-app judgment.

---

## File Organization

```
Sources/
├── App/
│   ├── LandlordHoursApp.swift    ← Design system tokens (Colors, Typography, Spacing, Radius, Animation)
│   ├── LHLogo.swift              ← Logo components (LHLogo, LHCompactLogo, LHWordmark)
│   └── LHIcons.swift             ← Tab bar icons (LHIcon, retiring), Lucide bridge and JellyBadge (retiring; see standard §4 Delete)
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


## Figma MCP Integration Rules

Run `get_design_context` then `get_screenshot` for the exact node before implementing, and validate against Figma afterwards. Treat the output as design intent, not code style.

- IMPORTANT: Replace hardcoded colours with `AppColors.*` tokens or `AdaptiveColors`; reuse the standard's `LH*` components; use SF Symbols (no new icon packages); store image assets in `Assets.xcassets`.
- All new views support dark mode and follow MVVM (`@EnvironmentObject var viewModel: AppViewModel`).

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
