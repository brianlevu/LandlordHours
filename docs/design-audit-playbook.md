# LandlordHours End-to-End Design Audit Playbook

Use this when an agent is asked to audit, modernize, polish, or make the app cohesive end to end.

## Design North Star

LandlordHours is a calm, trustworthy iOS utility for rental-property owners tracking tax-qualification evidence. Design should make the next action obvious, make qualification status legible, and make records feel organized without becoming dense tax software.

The current direction is modern, soft, tactile, and phone-native:

- Rounded SwiftUI surfaces on `LHMobileCanvas`
- Realistic contextual imagery only in learning/onboarding/education surfaces
- Lucide icons for UI, custom `LHIcon` only for tab bar
- Restrained color strategy: neutral surfaces carry the app, color carries meaning

## Color Governance

Audit color by intent, not by hue.

| Intent | Canonical tokens | Meaning |
|--------|------------------|---------|
| Action | `colors.action`, `colors.actionSurface`, `AppColors.onAction` | Primary CTA, selected nav, focus, links, AI help before completion |
| Positive | `colors.positive`, `colors.positiveSurface` | Saved, complete, qualified, healthy progress, Pro active |
| Caution | `colors.caution`, `colors.cautionSurface` | Behind pace, warning, setup gap, needs attention |
| Destructive | `colors.destructive`, `colors.destructiveSurface` | Delete, destructive, error-adjacent, repair emphasis |
| Informational | `colors.informational`, `colors.informationalSurface` | Calendar, sync, import, explanatory state |
| Human/spouse | `colors.rose`, `colors.roseWash` | People, spouse, shared participation |

Rules:

- Main CTAs use action violet, not sage.
- Green is earned after something is complete or healthy.
- Yellow warns. Coral deletes or marks repair/maintenance.
- Blue is informational/system context.
- Category colors are allowed, but they must not replace state/action meaning.
- Avoid raw `Color(hex:)` in views. Add a semantic token or use existing `AppColors`.

## Full App Audit Route

Run through every reachable user flow, not just individual tabs.

1. Onboarding and auth:
   - Welcome, goal selection, tracking plan, property setup, permissions, AI demo, complete
   - Login and sign-up

2. Main tabs:
   - Home dashboard, empty and populated
   - Properties list, empty, add, detail, edit, delete confirmation
   - Track time, empty-no-property, log mode, AI hint, AI detected, auto-filled, timer idle/running/finishing
   - Reports, every goal mode, year selector, export entry points
   - Settings, Pro/free states, profile/tax, learning center, export/import, support

3. Secondary flows:
   - Learning hub, article cards, article detail, guides, quick reads
   - Calendar import review
   - Category picker and category management
   - Time entry history and detail
   - Paywall, contact support, export PDF, tax year, tasks

4. State matrix:
   - Empty data
   - First-time seeded data
   - Occasional user
   - Frequent user with spouse/calendar imports
   - Free plan and Pro plan
   - Light mode and dark mode
   - Large Dynamic Type

## Required Verification Loop

Use the Build iOS Apps plugin / XcodeBuildMCP.

1. Confirm defaults with `session_show_defaults`.
2. Build and run a seeded scenario:
   - `-LHMockScenario firstTime -LHInitialTab 0`
   - `-LHMockScenario occasional -LHInitialTab 0`
   - `-LHMockScenario frequent -LHInitialTab 0`
3. Capture screenshots for changed screens.
4. Use runtime UI snapshots to verify tap targets and accessibility labels.
5. Set Dynamic Type to an accessibility size, inspect Home, Track, Properties, Reports, Settings, then restore normal size.
6. Run tests with `test_sim(progress: false)`.
7. Leave the simulator launched on a useful screen if the browser mirror is active.

## Static Scans

Run these before finishing:

```bash
rg -n "\\bList \\{|\\bForm \\{|\\.tracking\\(|Text\\(\\\"[A-Z][A-Z ]{2,}|\\[DEBUG\\]" Sources/Views Sources/Services
rg -n "Color\\(hex:|background\\(AppColors\\.sage\\)|foregroundStyle\\(Color\\.white\\)" Sources/Views Sources/App
```

Interpretation:

- `List` and `Form` are not banned, but they need a deliberate reason. Most app surfaces should use custom scroll/card layouts.
- `.tracking` and uppercase text should be rare, usually badges only.
- `Color(hex:)` inside views is usually a token violation.
- `AppColors.sage` on a button is suspicious unless the button confirms a completed/positive state.
- White text is fine on photos, destructive buttons, and primary action buttons, but prefer `AppColors.onAction` for primary action.

## Motion Audit

Motion is part of app coherence, not decoration.

- Use `AppAnimation` presets and `.lhMotion(..., value:)`; avoid raw `.animation(...)` in views unless there is a specific reason.
- Use `.buttonStyle(.lhPressable)` on custom buttons, chips, capsules, and large row controls so taps feel consistent.
- Respect Reduce Motion. For explicit state changes in a view, route through a local helper that skips `withAnimation` when `accessibilityReduceMotion` is true.
- Animate cause-and-effect moments: selected states, field expansion, AI auto-fill, saved confirmations, and progress rings.
- Avoid decorative page-load entrance choreography, long delays, and repeated bouncing. Product flows should usually resolve in 150-250ms; progress rings can run slightly longer.
- Verify Track log mode, Track timer mode, Reports goal switching, onboarding step changes, and tab changes in Simulator/browser before finishing.

## Visual Quality Checklist

- Primary action is visually obvious and consistently violet.
- Green only appears for complete/healthy/qualified states.
- No random pastel accents just because a card needed color.
- Body text has enough contrast in light and dark mode.
- Cards are not nested inside cards.
- No large decorative gradients fighting content.
- Images are useful context, not filler; use them mainly in onboarding, learning, empty states, and paywall education.
- Dynamic Type does not overlap, clip, or hide primary actions.
- VoiceOver exposes full-row tap targets, not just small icons.

## Done Criteria

Do not mark a design pass complete until:

- Changed screens are visually inspected in the simulator or browser mirror.
- Build succeeds with no warnings.
- Tests pass.
- Static scans have no unreviewed critical hits.
- Any new visual rule is reflected here or in `AGENTS.md` if future agents need to preserve it.
