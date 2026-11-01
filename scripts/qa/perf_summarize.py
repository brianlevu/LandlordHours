#!/usr/bin/env python3
"""Summarise a PerfMetricsUITests .xcresult into results.json + results.md.

Called by perf_check.sh. Reads `xcresulttool get test-results metrics` and `... summary`.
Run with `python3 -I`.
"""
import argparse
import json
import statistics
import subprocess
import sys


def xcresult(*args):
    out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", *args, "--compact"],
                         capture_output=True, text=True, timeout=300)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "xcresulttool failed")
    return json.loads(out.stdout)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--xcresult", required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--destination", default="")
    ap.add_argument("--iterations", type=int, default=5)
    ap.add_argument("--crashes", type=int, default=0)
    ap.add_argument("--test-rc", type=int, default=0)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    result = {"label": a.label, "destination": a.destination, "iterations": a.iterations,
              "crashes": a.crashes, "test_rc": a.test_rc, "tests": {}, "failures": [], "device": ""}
    try:
        summary = xcresult("summary", "--path", a.xcresult)
        result["counts"] = {k: summary.get(k) for k in
                            ("passedTests", "failedTests", "skippedTests", "totalTestCount", "result")}
        result["failures"] = [f.get("failureText", "") for f in summary.get("testFailures", [])][:20]
        devs = summary.get("devicesAndConfigurations", [])
        if devs:
            d = devs[0].get("device", {})
            result["device"] = "{} {} ({})".format(d.get("modelName", ""), d.get("osVersion", ""),
                                                   d.get("deviceName", ""))
        metrics = xcresult("metrics", "--path", a.xcresult)
    except Exception as exc:  # report, never hide
        result["error"] = str(exc)
        metrics = []

    for t in metrics:
        name = t["testIdentifier"].split("/")[-1].rstrip("()")
        for run in t.get("testRuns", []):
            for m in run.get("metrics", []):
                vals = [float(v) for v in m.get("measurements", [])]
                if not vals:
                    continue
                result["tests"].setdefault(name, {})[m["displayName"]] = {
                    "unit": m.get("unitOfMeasurement", ""),
                    "n": len(vals),
                    "mean": statistics.fmean(vals),
                    "median": statistics.median(vals),
                    "stdev": statistics.pstdev(vals) if len(vals) > 1 else 0.0,
                    "min": min(vals),
                    "max": max(vals),
                    "values": vals,
                }

    with open(a.out + "/results.json", "w") as f:
        json.dump(result, f, indent=2)

    lines = ["# Perf run: {}".format(a.label), "",
             "- destination: {} {}".format(a.destination, result["device"]),
             "- iterations requested: {}".format(a.iterations),
             "- crashes for this app during the run: {}".format(a.crashes),
             "- counts: {}".format(result.get("counts")), ""]
    if result.get("error"):
        lines += ["ERROR reading result bundle: {}".format(result["error"]), ""]
    for f in result["failures"]:
        lines.append("- FAILURE: {}".format(f))
    lines += ["", "| test | metric | unit | n | mean | median | stdev | min | max |", "|---|---|---|---|---|---|---|---|---|"]
    for test in sorted(result["tests"]):
        for metric, s in sorted(result["tests"][test].items()):
            lines.append("| {} | {} | {} | {} | {:.4g} | {:.4g} | {:.3g} | {:.4g} | {:.4g} |".format(
                test, metric, s["unit"], s["n"], s["mean"], s["median"], s["stdev"], s["min"], s["max"]))
    with open(a.out + "/results.md", "w") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
