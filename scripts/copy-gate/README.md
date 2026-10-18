# copy-gate: claim-honesty check for LandlordHours copy

Asks TypeSafe Jev (`jev-1.14.0`, one Noul question per line) whether a line of
user-facing copy "overclaims a tax outcome or gives tax advice". Lines at or above
the threshold are flagged. Advisory first-pass screen, not a legal review.

## Run

    python3 scripts/copy-gate/copy_gate.py check                      # all metadata/**/*.json
    python3 scripts/copy-gate/copy_gate.py check Sources/Views/PaywallView.swift notes.txt
    python3 scripts/copy-gate/copy_gate.py calibrate                  # re-measure, rewrites threshold.json

Python 3 stdlib only. Key: `$TYPESAFE_API_KEY` or `~/.config/typesafe/api_key` (never printed).
Exit codes: 0 clean, 1 flagged, 2 some lines NOT checked (API errors). Exit 2 is a loud
warning, never a pass. Gives up after 3 API failures. `--strict` turns exit 2 into 1.
`.swift` files: quoted strings of 12+ chars with a space are extracted.

## Calibration (48 hand-labelled lines, `calibration.json`)

- Agreement at 0.5: 47/48 (98%). The one miss is "Track spouse hours separately when
  you file jointly" (score 0.68-0.75, labelled fine).
- Threshold 0.5: catches 24/24 labelled overclaims, 1/24 false alarm. The tightest cut
  (0.725) would give 0 false alarms but sits in a 0.01 gap between classes, so it
  would not hold on new text. We chose margin over tidiness: a miss is legal exposure,
  a false alarm is a glance.
- Scores move ~0.03-0.05 between runs. Treat 0.45-0.55 as "read it yourself".

## Known blind spots

Obvious overclaims ("audit-proof", "guaranteed", "IRS-approved") score 0.9+. Subtle
marketing language does not: "Export an audit-ready PDF your CPA can actually use"
scored 0.23 and slipped through. Anything with "audit-ready", "proof", or "loophole"
needs a human regardless of the gate. The calibration set has no such borderline
cases yet; add them as you rule on them.

## Cost

About $0.001 per full run (~25k input tokens at $0.042 per million). Output is free.
