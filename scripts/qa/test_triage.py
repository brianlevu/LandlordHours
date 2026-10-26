#!/usr/bin/env python3
"""test_triage.py: label each failing UI test with a TypeSafe Jev Choice before an agent opens it.

Project-agnostic: reads any Xcode .xcresult (via `xcrun xcresulttool`) or xcodebuild ui.log.
Jev labels each failure from its test name and failure message only. Flags and routes; never
edits, retries or hides a failure.

    python3 test_triage.py triage RESULT.xcresult|ui.log [--out triage.json] [--calibration CAL.json] [--threshold P] [--no-ai]
    python3 test_triage.py calibrate --labels LABELS.json --out CAL.json     # measure against an answer key

Output of `triage`: a JSON list. One entry per failed test:
    {"test", "suite", "message", "label", "probability", "probs", "route", "reason"}
  route "label"  = Jev's label is at or above the calibrated threshold; the agent may start from it.
  route "agent"  = below the threshold, or Jev failed: unlabelled, route to agent. `label` is then null
                   (the below-threshold guess is kept as "suggested").
Fails open: no calibration file, no key, or any Jev error means route "agent", never a guess and never a drop.
Each project must calibrate its own threshold against its own answer key (see README.test_triage.md).

Stdlib only. Key: $TYPESAFE_API_KEY or ~/.config/typesafe/api_key (never printed).
Exit 0 always routes are produced; 2 if the input could not be read.
"""
import argparse, hashlib, json, os, re, subprocess, sys, time, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODEL = "jev-latest"
URL = "https://api.typesafe.ai/v1/systemone"
QUESTION_VERSION = "v2"
CACHE_FILE = Path(os.environ.get("JEV_TRIAGE_CACHE", Path.home() / "AgentScratch/jev-harness/test-triage-cache.json"))
DEFAULT_CAL = HERE / "test_triage_calibration.json"

LABELS = ["stale_selector_or_string", "real_behaviour_bug", "environment_or_infrastructure", "test_logic_bug"]
QUESTION = {
    "label": {
        "type": "choice",
        "instructions": "Why did this UI test fail?",
        "criteria": {
            "stale_selector_or_string": "The test looks for a button, label, identifier or piece of text that the app no longer "
                                        "shows, or now words differently, after a UI change. The app itself works.",
            "real_behaviour_bug": "The screen is there but the app shows or does the wrong thing, such as a wrong number or a wrong result.",
            "environment_or_infrastructure": "The test never really ran: the simulator or device was unavailable, the app crashed or "
                                             "was not running, a timeout hit, or the machine had no permission to automate the UI.",
            "test_logic_bug": "The test itself is wrong: a query that matches several elements, a bad assumption about timing, "
                              "the clock or the data, or steps in the wrong order.",
        },
    }
}
_stats = {"calls": 0, "cached": 0, "errors": 0, "model": None}
_cache = {}

# ---------------------------------------------------------------- parsing

LOG_ERR = re.compile(r"error: -\[([\w.]+?)\.(\w+) (\w+)\] : (.*)")


def parse_log(path):
    out = {}
    for line in Path(path).read_text(errors="replace").splitlines():
        m = LOG_ERR.search(line)
        if not m:
            continue
        mod_suite, test, msg = m.group(2), m.group(3), m.group(4).strip()
        key = (m.group(2), test)
        if key not in out:
            out[key] = {"test": test, "suite": m.group(2), "message": msg[:400]}
    # a failed test case with no "error:" line still counts
    for line in Path(path).read_text(errors="replace").splitlines():
        m = re.search(r"Test Case '-\[([\w.]+?)\.(\w+) (\w+)\]' failed", line)
        if m and (m.group(2), m.group(3)) not in out:
            out[(m.group(2), m.group(3))] = {"test": m.group(3), "suite": m.group(2), "message": "(no failure message in log)"}
    return list(out.values())


def parse_xcresult(path):
    r = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(path)],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip()[:200])
    data = json.loads(r.stdout)
    found = []

    def walk(n, suite=""):
        if n.get("nodeType") == "Test Suite":
            suite = n.get("name", suite)
        if n.get("nodeType") == "Test Case" and n.get("result") == "Failed":
            msgs = []
            def fm(x):
                if x.get("nodeType") == "Failure Message":
                    msgs.append(x.get("name", ""))
                for c in x.get("children", []): fm(c)
            fm(n)
            ident = n.get("nodeIdentifier", "")
            st = ident.split("/")[0] if "/" in ident else suite
            found.append({"test": n.get("name", "").rstrip("()"), "suite": st,
                          "message": (msgs[0] if msgs else "(no failure message)")[:400]})
        for c in n.get("children", []): walk(c, suite)

    for n in data.get("testNodes", []): walk(n)
    return found


def load_failures(path):
    p = Path(path)
    if p.suffix == ".xcresult" or p.is_dir():
        return parse_xcresult(p)
    return parse_log(p)

# ---------------------------------------------------------------- Jev

def api_key():
    k = os.environ.get("TYPESAFE_API_KEY")
    return k.strip() if k else (Path.home() / ".config/typesafe/api_key").read_text().strip()


def load_cache():
    global _cache
    try: _cache = json.loads(CACHE_FILE.read_text())
    except Exception: _cache = {}


def save_cache():
    try:
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        CACHE_FILE.write_text(json.dumps(_cache))
    except Exception: pass


def norm_msg(m):
    return re.sub(r"0x[0-9a-f]+|\d+(\.\d+)?", "N", m)[:80]


def add_group_facts(failures):
    """Facts code already knows, for the model: how many tests in this run failed in the same suite
    and with the same message. (A person reads a whole suite failing at once as one cause.)"""
    for f in failures:
        if "suite_failed" in f: continue
        f["suite_failed"] = sum(1 for g in failures if g["suite"] == f["suite"])
        f["same_message_failed"] = sum(1 for g in failures if norm_msg(g["message"]) == norm_msg(f["message"]))
    return failures


def state_for(f, context=None):
    s = {"test_name": f["test"], "test_suite": f["suite"], "failure_message": f["message"]}
    if "suite_failed" in f:
        s["failed_tests_in_this_suite_in_this_run"] = f["suite_failed"]
        s["failed_tests_with_this_message_in_this_run"] = f["same_message_failed"]
    if context: s["note_from_the_team"] = context
    return s


def ask(state, key, retries=3):
    """-> {label: prob} or None on any failure (fail open)."""
    ck = hashlib.sha1(f"{QUESTION_VERSION}|{MODEL}|{json.dumps(state, sort_keys=True)}".encode()).hexdigest()
    if ck in _cache:
        _stats["cached"] += 1
        return _cache[ck]
    body = json.dumps({"model": MODEL, "state": state, "questions": QUESTION}).encode()
    for attempt in range(retries):
        req = urllib.request.Request(URL, data=body, headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                j = json.load(r)
            probs = {k: float(v) for k, v in j["answers"]["label"]["probabilities"].items()}
            _stats["calls"] += 1
            _stats["model"] = j.get("model")
            _cache[ck] = probs
            return probs
        except urllib.error.HTTPError as e:
            _stats["errors"] += 1
            if e.code in (429, 529): time.sleep(2 * (attempt + 1)); continue
            if e.code in (400, 401, 422): return None
            time.sleep(1.5 * (attempt + 1))
        except Exception:
            _stats["errors"] += 1
            time.sleep(1.5 * (attempt + 1))
    return None


def ask_many(states, workers=6):
    key = api_key()
    load_cache()
    with ThreadPoolExecutor(max_workers=workers) as ex:
        res = list(ex.map(lambda s: ask(s, key), states))
    save_cache()
    return res


def top(probs):
    lab = max(probs, key=probs.get)
    return lab, probs[lab]

# ---------------------------------------------------------------- triage

def load_threshold(cal_path, override):
    if override is not None: return override
    try:
        cal = json.loads(Path(cal_path).read_text())
        return float(cal["threshold"]) if cal.get("ready") else None   # not READY: route everything to an agent
    except Exception: return None


def triage(failures, threshold, no_ai=False, context=None):
    add_group_facts(failures)
    results = [None] * len(failures)
    if not no_ai and failures:
        try:
            results = ask_many([state_for(f, context) for f in failures])
        except Exception as e:  # no key, no network: fail open
            results = [None] * len(failures)
    out = []
    for f, probs in zip(failures, results):
        e = {**f, "label": None, "probability": None, "probs": None, "route": "agent"}
        if probs is None:
            e["reason"] = "unlabelled, route to agent (no Jev answer)"
        else:
            lab, p = top(probs)
            e["probs"] = {k: round(v, 3) for k, v in probs.items()}
            e["suggested"] = lab
            e["probability"] = round(p, 3)
            if threshold is not None and p >= threshold:
                e["label"], e["route"], e["reason"] = lab, "label", f"p {p:.2f} >= threshold {threshold}"
            else:
                e["reason"] = "below threshold, route to agent" if threshold is not None else "no calibration: route to agent"
        out.append(e)
    return out

# ---------------------------------------------------------------- calibration

def split_of(item_id):
    """Deterministic: every third item (by hash) is held out."""
    return "heldout" if int(hashlib.sha1(item_id.encode()).hexdigest(), 16) % 3 == 0 else "dev"


def measure(rows, thr):
    """rows: [(truth, pred, p)]. -> accuracy among p>=thr, coverage."""
    kept = [r for r in rows if r[2] >= thr]
    acc = sum(1 for t, p, _ in kept if t == p) / len(kept) if kept else None
    return {"threshold": thr, "n": len(rows), "kept": len(kept), "coverage": round(len(kept) / len(rows), 3) if rows else 0,
            "accuracy": round(acc, 3) if acc is not None else None}


def pick_threshold(dev_rows, min_cov=0.5, target=0.85):
    """Lowest-risk rule: the highest threshold that still keeps >= min_cov coverage on the dev split;
    if accuracy there misses the target no threshold is claimed (returns None)."""
    best = None
    for thr in sorted({round(r[2], 3) for r in dev_rows}, reverse=True):
        m = measure(dev_rows, thr)
        if m["coverage"] >= min_cov:
            best = m
            break
    return best


def calibrate(labels_path, out_path, context=None):
    items = json.loads(Path(labels_path).read_text())["items"]
    states = [state_for({k: i[k] for k in ("test", "suite", "message", "suite_failed", "same_message_failed") if k in i}, context) for i in items]
    answers = ask_many(states)
    rows = {"dev": [], "heldout": []}
    detail = []
    for i, a in zip(items, answers):
        if a is None: detail.append({**i, "pred": None}); continue
        lab, p = top(a)
        sp = i.get("split") or split_of(i["id"])
        rows[sp].append((i["label"], lab, p))
        detail.append({**i, "split": sp, "pred": lab, "p": round(p, 3), "probs": {k: round(v, 3) for k, v in a.items()}})
    dev_pick = pick_threshold(rows["dev"])
    thr = dev_pick["threshold"] if dev_pick else 1.01
    held = measure(rows["heldout"], thr)
    majority = {}
    for sp, rs in rows.items():
        if rs:
            c = {}
            for t, _, _ in rs: c[t] = c.get(t, 0) + 1
            majority[sp] = round(max(c.values()) / len(rs), 3)
    conf = {}
    for sp in rows:
        for t, p, _ in rows[sp]:
            conf[f"{t} -> {p}"] = conf.get(f"{t} -> {p}", 0) + 1
    per_class = {}
    for sp in ("dev", "heldout"):
        for lab in LABELS:
            tr = [r for r in rows[sp] if r[0] == lab]
            per_class.setdefault(lab, {})[sp] = {"n": len(tr), "recalled": sum(1 for r in tr if r[1] == lab)}
    allrows = rows["dev"] + rows["heldout"]
    cal = {"model": _stats["model"], "question_version": QUESTION_VERSION, "threshold": thr,
           "threshold_rule": "highest dev threshold keeping >=50% coverage; 1.01 (route everything to an agent) if none",
           "dev": measure(rows["dev"], thr), "heldout": held,
           "heldout_at_no_threshold": measure(rows["heldout"], 0.0), "all_at_no_threshold": measure(allrows, 0.0),
           "majority_class_baseline": majority, "per_class": per_class, "confusion": dict(sorted(conf.items(), key=lambda x: -x[1])),
           "jev": {"calls": _stats["calls"], "cached": _stats["cached"], "errors": _stats["errors"]}, "items": detail}
    pooled_kept = [r for r in allrows if r[2] >= thr]
    pooled_acc = sum(1 for t, p, _ in pooled_kept if t == p) / len(pooled_kept) if pooled_kept else 0
    cal["pooled_at_threshold"] = {"kept": len(pooled_kept), "coverage": round(len(pooled_kept) / len(allrows), 3) if allrows else 0,
                                  "accuracy": round(pooled_acc, 3)}
    cal["ready"] = bool(dev_pick and held["accuracy"] is not None and held["accuracy"] >= 0.85 and held["coverage"] >= 0.5
                        and pooled_acc >= 0.85 and cal["dev"]["accuracy"] and cal["dev"]["accuracy"] >= 0.85)
    cal["ready_rule"] = "held-out AND dev AND pooled accuracy >= 0.85 at >= 0.5 coverage (a lone lucky split is not enough)"
    Path(out_path).write_text(json.dumps(cal, indent=1))
    print(json.dumps({k: cal[k] for k in ("threshold", "dev", "heldout", "heldout_at_no_threshold", "majority_class_baseline", "per_class", "confusion")}, indent=1))
    return cal

# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("triage")
    t.add_argument("input")
    t.add_argument("--out")
    t.add_argument("--calibration", default=str(DEFAULT_CAL))
    t.add_argument("--threshold", type=float)
    t.add_argument("--context", help="optional one-line note about the project's recent change, sent as state")
    t.add_argument("--no-ai", action="store_true")
    c = sub.add_parser("calibrate")
    c.add_argument("--labels", required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--context")
    a = ap.parse_args()
    if a.cmd == "calibrate":
        calibrate(a.labels, a.out, a.context); return 0
    try:
        failures = load_failures(a.input)
    except Exception as e:
        print(f"cannot read {a.input}: {e}", file=sys.stderr); return 2
    res = triage(failures, load_threshold(a.calibration, a.threshold), a.no_ai, a.context)
    text = json.dumps(res, indent=1)
    if a.out: Path(a.out).write_text(text)
    else: print(text)
    n_l = sum(1 for r in res if r["route"] == "label")
    print(f"{len(res)} failures: {n_l} labelled, {len(res) - n_l} routed to agent; jev calls {_stats['calls']} (+{_stats['cached']} cached)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
