#!/usr/bin/env python3
"""Claim-honesty gate for LandlordHours copy, powered by TypeSafe Jev (Noul).

  copy_gate.py calibrate            score calibration.json, report agreement, write threshold.json
  copy_gate.py check [files...]     score metadata/**/*.json (+ extra files), exit 1 on flagged lines
  add --strict to make API errors fail the run (default: warn, exit 2 = unchecked)

Stdlib only. API key: $TYPESAFE_API_KEY or ~/.config/typesafe/api_key (never printed).
Exit codes: 0 clean, 1 flagged lines, 2 could not fully check (API errors; fail-open WARNING, not a pass).
"""
import json, os, re, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
MODEL = "jev-1.14.0"  # pinned: the threshold is calibrated on this model
URL = "https://api.typesafe.ai/v1/systemone"
PRICE_PER_TOK = 0.042 / 1e6
MAX_API_FAILS = 3

INSTRUCTIONS = {
    "context": "The state is one line of user-facing copy for a tax record-keeping app (an hour log for rental property owners, used for REPS and material participation documentation).",
    "question": "Does this line overclaim a tax outcome or give tax advice? Count: guaranteeing or implying a user will qualify for a tax status, pass or survive an audit, save money, or be accepted by the IRS; claiming IRS approval or certification; telling the user what to do on their return; replacing a tax professional. Do not count: plain descriptions of recordkeeping features, exports for a CPA, and disclaimers that say the app does not give advice or decide qualification.",
}
CRITERIA = {
    "true": "Promises or implies a tax, audit, or legal outcome, or gives tax advice.",
    "false": "Describes a feature, or disclaims tax advice, without promising an outcome.",
}

_usage = {"tokens": 0}
_fails = {"n": 0}


def api_key():
    k = os.environ.get("TYPESAFE_API_KEY")
    if k:
        return k.strip()
    return (Path.home() / ".config/typesafe/api_key").read_text().strip()


def score_line(text, key):
    """Return yes-probability, or None on API failure."""
    body = json.dumps({
        "state": text, "model": MODEL,
        "questions": {"q": {"type": "noul", "instructions": INSTRUCTIONS, "criteria": CRITERIA}},
    }).encode()
    for attempt in range(3):
        if _fails["n"] >= MAX_API_FAILS:
            return None
        req = urllib.request.Request(URL, data=body, headers={
            "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                j = json.load(r)
            _usage["tokens"] += j.get("usage", {}).get("input_tokens", 0)
            return float(j["answers"]["q"]["noul"])
        except (urllib.error.URLError, KeyError, ValueError, TimeoutError) as e:
            _fails["n"] += 1
            print(f"  [api error] {type(e).__name__}: {str(e)[:80]}", file=sys.stderr)
            time.sleep(1.5 * (attempt + 1))
    return None


def score_all(texts):
    key = api_key()
    with ThreadPoolExecutor(max_workers=6) as ex:
        return list(ex.map(lambda t: score_line(t, key), texts))


def calibrate():
    rows = json.load(open(HERE / "calibration.json"))["lines"]
    scores = score_all([r["text"] for r in rows])
    if any(s is None for s in scores):
        print("Calibration aborted: API failures. No threshold written.", file=sys.stderr)
        return 2
    pos = sorted(s for r, s in zip(rows, scores) if r["overclaim"])
    neg = sorted(s for r, s in zip(rows, scores) if not r["overclaim"])
    # Catch every overclaim: threshold = just below the lowest-scoring labelled overclaim,
    # then take the highest threshold that still catches all (fewest false alarms).
    # Margin: halfway down toward the next-lower score, so one borderline miss doesn't slip.
    lo_pos = pos[0]
    below = [s for s in neg if s < lo_pos]
    thr = round((lo_pos + (max(below) if below else 0.0)) / 2, 3) if below else round(lo_pos - 0.01, 3)
    thr = min(thr, lo_pos - 1e-6)
    # Safety margin: the tightest cut can sit in a 0.01 gap between classes (unstable on new text).
    # A miss is legal exposure and a false alarm is a glance, so never cut above 0.5.
    thr = min(thr, 0.5)
    tp = sum(s >= thr for s in pos); fp = sum(s >= thr for s in neg)
    correct = tp + (len(neg) - fp)
    agree50 = sum((s >= 0.5) == r["overclaim"] for r, s in zip(rows, scores))
    print(f"model {MODEL}  n={len(rows)}  tokens={_usage['tokens']}  cost=${_usage['tokens']*PRICE_PER_TOK:.6f}")
    print(f"agreement @0.5: {agree50}/{len(rows)} = {agree50/len(rows):.0%}")
    print(f"chosen threshold {thr}: caught {tp}/{len(pos)} overclaims, {fp}/{len(neg)} false alarms, "
          f"agreement {correct}/{len(rows)} = {correct/len(rows):.0%}")
    for r, s in sorted(zip(rows, scores), key=lambda x: -x[1]):
        mark = "" if (s >= thr) == r["overclaim"] else "   <-- MISMATCH"
        print(f"  {s:.3f} {'OVER' if r['overclaim'] else 'ok  '} {r['text']}{mark}")
    json.dump({"model": MODEL, "threshold": thr, "n": len(rows), "overclaims_caught": tp,
               "overclaims_total": len(pos), "false_alarms": fp, "agreement_at_threshold": round(correct/len(rows), 3),
               "agreement_at_0.5": round(agree50/len(rows), 3)}, open(HERE / "threshold.json", "w"), indent=1)
    return 0


def strings_of(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for k, v in node.items():
            if k in ("privacyPolicyUrl", "marketingUrl", "supportUrl", "keywords"):
                continue  # URLs are not claims; keywords handled separately below
            yield from strings_of(v)
    elif isinstance(node, list):
        for v in node:
            yield from strings_of(v)


def split_units(s):
    out = []
    for line in s.split("\n"):
        line = re.sub(r"^\s*[•\-\*]\s*", "", line).strip()
        if not line:
            continue
        # sentence split, keep short fragments together
        parts = re.split(r"(?<=[.!?])\s+(?=[A-Z])", line)
        out += [p.strip() for p in parts if len(p.strip()) >= 12]
    return out


def swift_strings(path):
    txt = Path(path).read_text()
    for m in re.finditer(r'"((?:[^"\\\n]|\\.){12,})"', txt):
        s = m.group(1)
        if " " in s and not s.startswith(("http", "system", ".")):
            yield s


def collect(files):
    units = []  # (source, text)
    paths = list((REPO / "metadata").rglob("*.json")) + [Path(f) for f in files]
    for p in paths:
        if p.suffix == ".json":
            try:
                data = json.load(open(p))
            except Exception as e:
                print(f"skip {p}: {e}", file=sys.stderr); continue
            for s in strings_of(data):
                for u in split_units(s):
                    units.append((str(p.relative_to(REPO)) if p.is_relative_to(REPO) else str(p), u))
        elif p.suffix == ".swift":
            for s in swift_strings(p):
                for u in split_units(s) or [s]:
                    units.append((str(p), u))
        else:
            for u in split_units(p.read_text()):
                units.append((str(p), u))
    seen, out = set(), []
    for src, u in units:
        if (src, u) not in seen:
            seen.add((src, u)); out.append((src, u))
    return out


def check(files):
    cfg = json.load(open(HERE / "threshold.json"))
    thr = cfg["threshold"]
    units = collect(files)
    scores = score_all([u for _, u in units])
    flagged = [(s, src, u) for (src, u), s in zip(units, scores) if s is not None and s >= thr]
    errs = sum(s is None for s in scores)
    print(f"checked {len(units) - errs}/{len(units)} lines, model {cfg['model']}, threshold {thr}, "
          f"cost ${_usage['tokens']*PRICE_PER_TOK:.6f}")
    for s, src, u in sorted(flagged, key=lambda x: -x[0]):
        print(f"FLAG {s:.3f}  {src}\n      {u}")
    if errs:
        print(f"WARNING: {errs} line(s) NOT CHECKED (TypeSafe API errors). Gate failed OPEN to a warning, "
              f"not a pass. Re-run or review by hand.", file=sys.stderr)
    if flagged:
        return 1
    if errs:
        return 2 if "--strict" not in sys.argv else 1
    print("clean")
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args or args[0] not in ("calibrate", "check"):
        print(__doc__); sys.exit(64)
    sys.exit(calibrate() if args[0] == "calibrate" else check(args[1:]))
