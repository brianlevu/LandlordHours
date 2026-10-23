# The design standard, on one page

For Brian. The full document is `DESIGN-STANDARD.md` (draft r2). Nothing is built yet; this is the bar for what gets built.

## What went wrong

The To confirm card took up to 40% of your screen for one calendar item. Each item was built like a detail card: big stacked hours, a 36pt tool picture, three or four lines of text, a Confirm pill and a text link under it. Copilot shows six items in the same space. Reminders shows one in 64pt. We had tokens and a brand, but no rule for how a row, a card or a button is built, so every screen was built on its own. The app has four tinted button styles, three primary pill styles, six hand-made close buttons and two hours steppers.

## Six rules

1. **Rows, not cards, for lists.** Items live in one grouped list with thin dividers. A row is 56 to 88pt tall. No item takes more than 12% of the screen; no card more than 20%, except the house.
2. **No buttons inside rows.** A row has one small confirm circle on the left and swipes. The one batch action sits at the bottom of the list. One big button per screen.
3. **One button, four sizes.** Primary (52pt), secondary (44pt), text link, icon circle. Everything else goes.
4. **Symbols for function, house art for identity.** SF Symbols everywhere you tap. The tool pictures only where there is room: 36pt in browse lists, 56pt in pickers and sheet headers, never in a decision row. No emoji-style art. Lucide is removed.
5. **Numbers before adjectives.** Builders measure their own frames before hand-off: row height, items above the fold, empty space inside cards, text contrast. The gate confirms and then asks one question in writing: would this sit next to Reminders or Copilot without looking like the hobby version?
6. **Every animation and every sentence has a name.** Motion comes from a table of named moves with set durations. Copy comes from a word list and a set of fixed lines. Both are checked by script.

## The row, before and after

Before: `2h` stacked, tool picture, "Calendar · Today 12–2", "Plumber at Pine Cabin" on two lines, "Repairs" in yellow, a "Not sure" chip, a Confirm pill, "Not rental work" as a link. 160 to 236pt.

After, 64pt:

```
◯  Plumber at Pine Cabin                         2h
   Calendar · Today 12–2 · Repairs
```

Tap the circle to confirm. Tap the row for details. Swipe right to confirm, swipe left for "Not rental work". When two or more items are clear, "Confirm 2 likely" appears at the bottom. Long titles take two lines (86pt). Same row on Today and in Inbox, with the system swipe, not our own.

Found on the way: "Making Monthly Mortgage Payment" was filed under Management because the loan-payment rule only runs when the first guess was Financing. Separate fix.

## Who the app is

A calm friend who knows the rules: one plain sentence per number, points you to your CPA, never raises its voice. A good contractor: says what was done, with the count. Honest about uncertainty: "Not sure" is a tag, not a failure; nothing counts until you confirm it. Quietly crafted: the blueprint grid and the brass sign do the talking; motion shows cause and effect, then stops.

## Five named motions

| Name | What happens | How long |
|---|---|---|
| Press | Anything you touch shrinks to 97% and comes back | 0.12s down, 0.15s up |
| Row confirm | The circle fills green with a check, then the row folds away | 0.12s + 0.25s |
| Count change | Hours and counts roll to the new number | 0.24s |
| House stage | At 100, 500 and 750 hours the new part turns from lines to solid, the brass sign appears, one burst of confetti | under 0.6s, once |
| Toast | Slides up 24pt and fades in; fades out faster than it came | 0.22s in, 0.15s out |

Bounce only after your finger lets go of a swipe. Taps never bounce. Everything has a reduced-motion version.

## Five copy fixes

| Now | Proposed |
|---|---|
| "Rental Activity Time Log: Tax Year 2026" (the PDF) vs "2026 hours record" (the paywall preview) | "Rental hours record 2026", in both |
| "Material participation test 1 needs more than 500 hours. You're at the line." | "You're at the line for the 500-hour test, based on your records. Your CPA decides what that means." |
| "Treat all your rentals as one activity for material participation." | "Count all your rentals together." (footnote: your CPA may call this a grouping election) |
| "Did anyone else, like a property manager or contractor, spend more time on any of your rentals than you and your spouse this year?" | "Did a manager or contractor put in more hours than you and your spouse this year, at any rental?" |
| Seven versions of "nothing counts until you confirm" | One line everywhere: "Nothing counts until you confirm it." |

## Screens to redesign, in order

1. **Today** — the row above, and the whole screen becomes a real list.
2. **Inbox** — same row; the question card with three stacked pills shrinks.
3. **Log time** — one button style, smaller digits, fewer fixed sizes.
4. **Properties** — one picture per row, not two; same gutter as everywhere else.
5. **Confirm sheet** — shares the stepper and Me/Spouse control instead of its own copies.
6. **Onboarding** — uses the app's own buttons and colours; no text-size clamps.
7. **Paywall** — close already; fix the tiny preview text and the PDF title.

## What needs you

Nothing is built. Before any lane starts: your read on the row above, and whether Today becoming a list (like Reminders) sits right with you. An independent reviewer has read the standard twice; the frames will get the same treatment before you see them.
