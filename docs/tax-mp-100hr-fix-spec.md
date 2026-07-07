# Spec: Fix 100-hour material participation false positive

Date: 2026-07-07 · Owner: Brian · Status: approved for 1.0.4

## Problem

`Models.swift` (~345-347) sets `meets100HourTest: hours > 100` and (~296-298) `isMateriallyParticipating = meets500HourTest || meets100HourTest`. IRS Test 3 requires >100 hours **AND** that no other individual (property manager, contractor, co-owner) participated more. The live app shows a false "materially participating" for exactly the highest-risk users (e.g., 101 owner hours, 500 property-manager hours). The Learning Center already states the rule correctly (`LearningCenterView.swift` ~409); the engine doesn't enforce it.

## Product decision (locked)

Add a per-tax-year confirmation rather than an others'-hours ledger (keep 1.0.4 scope tight):

1. New stored field on the tax profile / goal state, scoped per user and tax year:
   `noOneParticipatedMore: Bool?` — `nil` = unanswered, `true` = confirmed, `false` = someone else did more.
2. Logic change:
   - `meets100HourTest` = `hours > 100 && noOneParticipatedMore == true`
   - New derived state for `hours > 100 && noOneParticipatedMore == nil`: **conditional** — surfaced as "100-hour threshold reached — confirm no one participated more."
   - `hours > 100 && noOneParticipatedMore == false` → not materially participating via Test 3 (500h test still applies).
   - 500-hour test, REPS logic, spouse-combination rules: unchanged.
3. UI (operational language, per PRODUCT.md — no legalese):
   - Reports (goal ring area) and anywhere "materially participating" is asserted: show the conditional state with a one-tap affordance to answer the confirmation.
   - Settings → tax profile: the same toggle/question with one plain-language sentence explaining who counts as "someone else" (property manager, contractor, co-owner who isn't your spouse).
   - Status must remain color-independent (icon + text, not color alone).
4. Copy for the question: "Did anyone else — like a property manager or contractor — spend more time on this property than you (and your spouse) this year?" Answers: "No one did more" / "Someone did more". Keep the existing design system (AppColors/AdaptiveColors, LH components); no new visual styles.

## Migration

Existing users have no stored answer → `nil` → they move from "materially participating" to the conditional prompt. That is intended: honest downgrade, one tap to restore if true. No data regresses.

## Acceptance criteria

- Unit tests: 100/101 hour boundaries × three confirmation states; 500h path unaffected by confirmation; spouse rules unchanged; prior tests still pass.
- Build succeeds and full unit suite passes via the repo's lane (`ci_scripts/test_xcode27_lane.sh unit` or equivalent xcodebuild against the configured simulator).
- Fresh simulator screenshots of: Reports showing the conditional state, the confirmation UI, and the confirmed state.
- No change to REPS (750h / 50%-rule) outputs for any input.

## Acceptance environment

iPhone simulator per repo lane config; unit suite; fresh captures only (never the screenshots archive).
