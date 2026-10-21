#!/usr/bin/env python3
"""Optional TypeSafe Jev fact-check for the note eval (EVAL ONLY: never ships in the app).

Asks Jev one Noul per (note, description): "Is every fact in this description stated in the
note?" and measures agreement with NoteFactGuard's verdicts from a host eval log
(scripts/note-eval-host/run.sh output: "on-device desc" = kept, "on-device rejected" = rejected).

Usage: jev_factcheck.py <fixture.json> <host-eval-log.txt> [--threshold 0.5]
Fails open: any Jev error leaves that pair to NoteFactGuard and is counted, never dropped.
The eval notes are synthetic (no user data). Key: ~/.config/typesafe/api_key (never printed).
"""
import json, os, re, sys, time, urllib.request

PRICE_PER_MTOK = 0.042  # docs.typesafe.ai/models: Jev input tokens; output tokens free.

def load_pairs(fixture_path, log_path):
    cases = {c["id"]: c for c in json.load(open(fixture_path))["cases"]}
    props = json.load(open(fixture_path))["properties"]
    pairs = []
    for line in open(log_path):
        m = re.match(r"NOTE-EVAL on-device desc (\w+): (.*)$", line.rstrip("\n"))
        if m:
            pairs.append((m.group(1), m.group(2), True)); continue
        m = re.match(r"NOTE-EVAL on-device rejected (\w+): (.*) \[[^\]]*\]$", line.rstrip("\n"))
        if m:
            pairs.append((m.group(1), m.group(2), False))
    return [(cid, cases[cid]["note"], d, kept) for cid, d, kept in pairs if cid in cases], props

def ask(key, note, description, props):
    body = {
        "model": "jev-latest",
        "state": {
            "note": note,
            "description": description,
            "properties": [{"name": p["name"], "address": p["address"], "also_called": p["aliases"]} for p in props],
        },
        "questions": {
            "faithful": {
                "type": "noul",
                "instructions": "Is every fact in `description` stated in `note`? The description is a short record of the landlord's work written from the note.",
                "criteria": {
                    "true": "Every action, object, person, place, cause, result and quantity in `description` is said in `note`. Rewording is fine (\"fixed\" for \"fixd\", \"repaired\" for \"fixed\"). Naming a property from `properties` is fine only when the note refers to that property by its name, another name, or its street.",
                    "false": "`description` adds anything the note does not say: a room, a cause, a trade or role, a result such as fixed or completed, a quantity, a person, or a property the note doesn't refer to.",
                },
            }
        },
    }
    req = urllib.request.Request("https://api.typesafe.ai/v1/systemone", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        out = json.load(r)
    return out["answers"]["faithful"]["noul"], out.get("usage", {}).get("input_tokens", 0)

def main():
    fixture, log = sys.argv[1], sys.argv[2]
    threshold = float(sys.argv[sys.argv.index("--threshold") + 1]) if "--threshold" in sys.argv else 0.5
    key = open(os.path.expanduser("~/.config/typesafe/api_key")).read().strip()
    pairs, props = load_pairs(fixture, log)
    agree = errors = tokens = 0
    rows = []
    t0 = time.time()
    for cid, note, desc, kept in pairs:
        try:
            p, used = ask(key, note, desc, props)
            tokens += used
        except Exception as e:  # fail open: the code guard's verdict stands
            errors += 1
            rows.append((cid, None, kept, desc, type(e).__name__)); continue
        jev_kept = p >= threshold
        agree += jev_kept == kept
        rows.append((cid, p, kept, desc, ""))
    n = len(pairs) - errors
    print(f"JEV pairs={len(pairs)} answered={n} errors={errors} threshold={threshold}")
    print(f"JEV agreement with NoteFactGuard: {agree}/{n} = {100*agree/max(n,1):.1f}%")
    print(f"JEV input tokens={tokens} cost=${tokens*PRICE_PER_MTOK/1e6:.6f} per-100-notes=${tokens*PRICE_PER_MTOK/1e6/max(n,1)*100:.6f} wall={time.time()-t0:.1f}s")
    for cid, p, kept, desc, err in rows:
        if err or (p >= threshold) != kept:
            print(f"JEV disagree {cid}: guard={'kept' if kept else 'rejected'} jev={p if p is None else round(p,3)} {err} | {desc}")
    # Threshold sweep (calibration).
    scored = [(p, kept) for _, p, kept, _, err in rows if not err]
    for t in [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]:
        a = sum((p >= t) == k for p, k in scored)
        print(f"JEV sweep t={t}: {100*a/max(len(scored),1):.1f}%")

if __name__ == "__main__":
    main()
