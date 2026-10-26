# Rentals layouts — throwaway comparison mock (proto/rentals-layouts)

Not production. A DEBUG-only switch on the Rentals tab so Brian can pick a layout.

## Run it

```
-LHMockScenario occasional -LHInitialTab 1 -LHPropertiesGoal mp100 \
  -LHPropertiesSeed layouts3|layouts8|layouts1 -LHPropertiesLitToday 0 \
  -LHRentalsLayout gallery|cards|list
```

- `gallery` — two-column house tiles: house at its stage (lit/unlit), name, "46 of 100h", one-line pace.
  With exactly one rental, the tab opens straight on that rental's page (the existing `PropertyDetailView`).
- `cards` — one big card per rental: large house, name, hours of goal, pace, "2 to confirm", last logged date.
- `list` (or no flag) — the current merged Rentals list, unchanged.

Seeds (`PropertiesDebugSeed.swift`): `layouts3` = Santa Ray Ave 88h, Delaney Ct 46h, Pine Cabin 8h
(added this week); `layouts8` adds five more, including a finished house, a long name and a 0h rental;
`layouts1` = Delaney Ct alone.

## Deliberate exceptions and mock data

- **Gallery and cards break the standard's "rows, not cards" rule (§1.4) and the per-item density
  limits (one item ≤ 12% of the viewport) on purpose.** They exist to be compared, not shipped as is.
- **"N to confirm" is mock data** (`RentalMockInfo.mockToConfirm`, by name). The Inbox has no
  per-rental count yet; shipping cards would need one.
- Pace words: lead of the rental page's pace sentence ("Behind by 36h", "On pace"); "Done for the
  year" once the goal is met; "Nh a week to go" while pace isn't ready yet (under 10h and 2 weeks).
- Houses use the craft still with its lot, scaled from the ground line and cropped by the tile's inner
  surface (`RentalMockHouse`). `LHThumb`'s interim crop cuts the lot inside its own square, which drew
  a hard edge at tile sizes.

Code: everything lives under `#if DEBUG` at the bottom of `Sources/Views/PropertiesView.swift`.
Frames and the comparison sheet: `~/AgentScratch/landlordhours/2026-10-26/rentals-layouts/`.
