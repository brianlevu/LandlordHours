#!/usr/bin/env python3
"""Compare two perf_check results.json files. A regression over the threshold, or any crash, fails.

  python3 -I scripts/qa/perf_compare.py baseline/results.json candidate/results.json [--threshold 10]

Compares the MEDIAN of each gating (test, metric): clock time, launch durations, peak and absolute
memory (lower is better) and scroll frame rate (higher is better). Hitch time ratio gates on an
absolute 5 ms/s cap because its baseline is ~0. Baselines under a per-unit noise floor are skipped.
Exit 0 pass, 1 regression, 2 crash or unreadable input.
"""
import argparse
import json
import re
import sys

# Below these baseline medians a percentage is noise (unit -> floor).
FLOORS = {"s": 0.05, "ms": 50.0, "kB": 2000.0}
# Metrics that gate a release. Lower is better unless listed in HIGHER_IS_BETTER.
# "Memory Physical" (the per-iteration delta) goes negative and is noise, so it is printed only.
GATING = ("CPU Time", "Clock Monotonic Time", "Duration (AppLaunch)", "Duration (ApplicationFirstFramePresentationResponsive)",
          "Memory Peak Physical", "Absolute Memory Physical", "Frame Rate")
HIGHER_IS_BETTER = ("Frame Rate",)
# Hitch metrics have a zero baseline, so they gate on an absolute cap instead of a percentage.
# Apple's guidance: under 5 ms of hitch per second feels smooth.
HITCH_RATIO_CAP_MS_PER_S = 5.0


def load(path):
    # Several result files (for example the main run and an --only idle run) may be joined with commas.
    data = {"tests": {}, "crashes": 0, "test_rc": 0}
    for one in path.split(","):
        with open(one) as f:
            part = json.load(f)
        data["tests"].update(part.get("tests", {}))
        data["crashes"] += part.get("crashes", 0)
        data["test_rc"] = data["test_rc"] or part.get("test_rc", 0)
    # Metric names carry the process name, e.g. "Memory Peak Physical (landlordhours)". A rename
    # to Dormer must not turn every metric into MISSING, so the process suffix is dropped.
    for test, metrics in data.get("tests", {}).items():
        data["tests"][test] = {re.sub(r" \((landlordhours|dormer)\)$", "", k, flags=re.I): v
                               for k, v in metrics.items()}
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("baseline")
    ap.add_argument("candidate")
    ap.add_argument("--threshold", type=float, default=10.0, help="percent regression that fails")
    a = ap.parse_args()
    try:
        base, cand = load(a.baseline), load(a.candidate)
    except Exception as exc:
        print("cannot read input: {}".format(exc))
        return 2
    status = 0
    if cand.get("crashes", 0) or cand.get("test_rc", 0) not in (0,):
        print("FAIL: candidate had {} crash log(s), test rc {}".format(cand.get("crashes"), cand.get("test_rc")))
        status = 2
    rows = []
    for test, metrics in sorted(base["tests"].items()):
        for metric, b in sorted(metrics.items()):
            c = cand["tests"].get(test, {}).get(metric)
            if c is None:
                if any(g in metric for g in GATING) or "Hitch Time Ratio" in metric:
                    rows.append((test, metric, b["median"], None, None, "MISSING"))
                    status = max(status, 1)
                continue
            if "Hitch Time Ratio" in metric:
                over = c["median"] > HITCH_RATIO_CAP_MS_PER_S
                rows.append((test, metric, b["median"], c["median"], None,
                             "REGRESSION (over {} ms/s)".format(HITCH_RATIO_CAP_MS_PER_S) if over else "ok"))
                if over:
                    status = max(status, 1)
                continue
            if not any(g in metric for g in GATING):
                continue
            floor = FLOORS.get(b["unit"], 0.0)
            if b["median"] < floor:
                rows.append((test, metric, b["median"], c["median"], None, "below noise floor"))
                continue
            pct = (c["median"] - b["median"]) / b["median"] * 100.0
            worse = -pct if any(h in metric for h in HIGHER_IS_BETTER) else pct
            verdict = "REGRESSION" if worse > a.threshold else "ok"
            if verdict != "ok":
                status = max(status, 1)
            rows.append((test, metric, b["median"], c["median"], pct, verdict))
    print("{:<34} {:<34} {:>10} {:>10} {:>8}  {}".format("test", "metric", "base", "cand", "delta%", "verdict"))
    for t, m, b, c, p, v in rows:
        print("{:<34} {:<34} {:>10.4g} {:>10} {:>8}  {}".format(
            t, m[:34], b, "-" if c is None else "{:.4g}".format(c), "-" if p is None else "{:+.1f}".format(p), v))
    print("RESULT:", {0: "PASS", 1: "FAIL (regression over {}%)".format(a.threshold), 2: "FAIL (crash)"}[status])
    return status


if __name__ == "__main__":
    sys.exit(main())
