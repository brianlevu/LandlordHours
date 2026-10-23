#!/usr/bin/env python3
"""standard_lint.py - grep-based linter for the [grep] rules of docs/design/DESIGN-STANDARD.md.

  python3 scripts/qa/standard_lint.py                 # check Sources/ against the baseline (exit 1 on NEW violations)
  python3 scripts/qa/standard_lint.py --baseline      # record current violations to scripts/qa/standard_lint_baseline.json
  python3 scripts/qa/standard_lint.py --all           # list every violation, ignore the baseline
  python3 scripts/qa/standard_lint.py --json out.json # machine-readable report
  python3 scripts/qa/standard_lint.py --rules         # print the rule table

Baseline: a multiset of (rule, file, normalised line text). A violation is NEW when a file has
more occurrences of that exact (rule, text) than the baseline recorded, so moving code is free
but adding a violation fails. Fixing violations never fails; re-run --baseline to ratchet down.
Scope: Sources/**/*.swift. Token files (where raw sizes and hex are defined) are allowlisted per rule.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import re
import subprocess
import sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                      cwd=os.path.dirname(os.path.abspath(__file__))).stdout.strip() or os.getcwd()
BASELINE = os.path.join(ROOT, "scripts/qa/standard_lint_baseline.json")
SRC = "Sources"

TOKEN_FILES = {"Sources/App/LandlordHoursApp.swift", "Sources/App/LHLogo.swift",
               "Sources/App/LHIcons.swift", "Sources/Views/Components/AppDesignSystem.swift"}
NOT_VIEWS = ("Sources/Models/", "Sources/Services/", "Sources/ViewModels/")

EMOJI = re.compile("[\U0001F300-\U0001FAFF☀-➿⭐⬆✅❌\U0001F1E6-\U0001F1FF]")
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')

# word list from standard C.1.6 and C.4 (the "Avoid" column), matched inside string literals only
BANNED = [r"qualif\w*", r"audit[- ]ready", r"evidence", r"\bproof\b", r"compliance", r"time entr(?:y|ies)",
          r"log item", r"activity log", r"\battribute[sd]?\b", r"\beligible\b", r"\bcountable\b",
          r"non-countable", r"material participation", r"\bREPS\b", r"tax professional", r"\badvis[eo]r\b",
          r"\bapprove\b", r"\bdismiss\b", r"\breject\b", r"\barchive\b", r"low confidence", r"\buncertain\b",
          r"\bparticipants?\b", r"\bhousehold\b", r"\btelemetry\b", r"\banalytics\b", r"audit log",
          r"\bclassif(?:y|ied|ication)\b", r"\bdetect(?:ed|s)?\b", r"tax profile", r"\bpowerful\b",
          r"\bseamless(?:ly)?\b", r"\beffortless(?:ly)?\b"]
BANNED_RE = re.compile("|".join(BANNED), re.I)
# string literals that are identifiers, not copy
NON_COPY_LINE = re.compile(r'accessibilityIdentifier|Logger|\.track\(|print\(|NSLog|os_log|UserDefaults|'
                           r'@AppStorage|forKey:|\.sf\b|systemName:|Image\(|#Preview|\bcase\b.*=\s*"|CodingKeys|'
                           r'rawValue|logger\.|AppLog|subsystem|category:|URL\(string|Notification\.Name|'
                           r'identifier:|key:\s*"|Analytics')


def is_view(path):
    return not path.startswith(NOT_VIEWS)


def r_system_size(path, line):
    return path not in TOKEN_FILES and ".system(size:" in line


def r_color_hex(path, line):
    return path not in TOKEN_FILES and bool(re.search(r"Color\(\s*hex:", line))


def r_lucide(path, line):
    return bool(re.search(r"import LucideIcons|\bLucide\.|LucideIcon\(|lucideId", line))


def r_emoji(path, line):
    if not is_view(path) or line.lstrip().startswith("//"):
        return False
    return any(EMOJI.search(m.group(1)) for m in STRING.finditer(line))


def r_banned(path, line):
    s = line.lstrip()
    if s.startswith("//") or NON_COPY_LINE.search(line):
        return False
    return any(BANNED_RE.search(m.group(1)) for m in STRING.finditer(line))


def r_button_style(path, line):
    if path.endswith("/LHButton.swift"):
        return False
    if re.search(r"struct\s+\w+\s*:\s*(?:\w+,\s*)*ButtonStyle\b", line):
        return True
    m = re.search(r"\.buttonStyle\(\s*([^)\n]*)", line)
    if not m:
        return False
    arg = m.group(1).strip()
    return not (arg.startswith("LHButton") or arg in (".plain", ".borderless", ".automatic"))


def r_swipe(path, line):
    return bool(re.search(r"\bDragGesture\(|TodaySwipeRow|TodaySwipeHint|swipePreviewOffset", line))


def r_bp_tool(path, line):
    return bool(re.search(r'Image\(\s*"bp_tool_', line))


def r_dyn_type(path, line):
    return ".dynamicTypeSize(" in line and not line.lstrip().startswith("//")


def r_spring_response(path, line):
    return bool(re.search(r"\.spring\(\s*response:", line))


def r_repeat_forever(path, line):
    return "repeatForever" in line


def r_onappear_anim(path, line):
    return bool(re.search(r"onAppear\s*\{\s*withAnimation", line))


def r_radius(path, line):
    if path in TOKEN_FILES:
        return False
    for m in re.finditer(r"cornerRadius:\s*(\d+(?:\.\d+)?)", line):
        if float(m.group(1)) not in (6, 12, 16, 20):
            return True
    return False


def r_alert(path, line):
    return bool(re.search(r"\.alert\(", line))


def r_fixed_size(path, line):
    return ".fixedSize(" in line and not line.lstrip().startswith("//")


def r_hand_card(path, line):
    return bool(re.search(r"\.propertyCard\(|lhSurfaceCard", line))


RULES = [
    ("system-size", "no .system(size:) outside token files (1.2)", r_system_size),
    ("color-hex", "no Color(hex:) outside token files (1.2)", r_color_hex),
    ("lucide", "no Lucide (1.17)", r_lucide),
    ("emoji", "no emoji literal in strings (1.17)", r_emoji),
    ("banned-word", "word list C.1.6 / C.4 inside string literals", r_banned),
    ("button-style", "only LHButton styles (1.13)", r_button_style),
    ("custom-swipe", "no DragGesture swipe / TodaySwipeRow, system .swipeActions only (1.3a)", r_swipe),
    ("bp-tool-image", "no Image(\"bp_tool_\") outside CategoryToolTile (1.17)", r_bp_tool),
    ("dynamic-type-clamp", ".dynamicTypeSize( only on hero number and house art, max 2 sites (2)", r_dyn_type),
    ("spring-response", "springs are .spring(duration:bounce:), not response:/dampingFraction: (B.1)", r_spring_response),
    ("repeat-forever", "repeatForever only in scanningLine (B.1)", r_repeat_forever),
    ("onappear-animation", ".onAppear { withAnimation only in emptyStateEntrance / milestone (B.1)", r_onappear_anim),
    ("radius", "corner radii in {6, 12, 16, 20, capsule} (D10)", r_radius),
    ("alert", ".alert( only for irreversible destructive acts (1.21)", r_alert),
    ("fixed-size", "fixedSize at AX only; review each (2)", r_fixed_size),
    ("hand-card", "no hand-built card around rows: .propertyCard / lhSurfaceCard (1.3a)", r_hand_card),
]


def scan():
    out = []
    for dirpath, _, files in os.walk(os.path.join(ROOT, SRC)):
        for fn in sorted(files):
            if not fn.endswith(".swift"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT)
            try:
                lines = open(full, encoding="utf-8").read().splitlines()
            except UnicodeDecodeError:
                continue
            for i, line in enumerate(lines, 1):
                for rule, _, fn_ in RULES:
                    if fn_(rel, line):
                        out.append(dict(rule=rule, file=rel, line=i, text=re.sub(r"\s+", " ", line.strip())[:160]))
    out.sort(key=lambda v: (v["rule"], v["file"], v["line"]))
    return out


def key(v):
    return f"{v['rule']}|{v['file']}|{v['text']}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--baseline", action="store_true", help="record current violations as the baseline")
    ap.add_argument("--all", action="store_true", help="list every violation, ignore the baseline")
    ap.add_argument("--json", help="write the full report here")
    ap.add_argument("--rules", action="store_true")
    args = ap.parse_args()
    if args.rules:
        for r, d, _ in RULES:
            print(f"{r:20} {d}")
        return 0
    found = scan()
    by_rule = collections.Counter(v["rule"] for v in found)
    if args.baseline:
        ms = collections.Counter(key(v) for v in found)
        data = {"note": "Ratchet: new code may not add violations. Regenerate with --baseline after fixing some.",
                "counts_by_rule": {r: by_rule.get(r, 0) for r, _, _ in RULES},
                "total": len(found), "entries": dict(sorted(ms.items()))}
        with open(BASELINE, "w") as fh:
            json.dump(data, fh, indent=1, sort_keys=False)
            fh.write("\n")
        print(f"baseline written: {len(found)} violations")
        for r, _, _ in RULES:
            print(f"  {r:20} {by_rule.get(r, 0)}")
        return 0
    base = {}
    if os.path.exists(BASELINE) and not args.all:
        base = json.load(open(BASELINE))["entries"]
    seen = collections.Counter()
    new = []
    for v in found:
        k = key(v)
        seen[k] += 1
        if args.all or seen[k] > base.get(k, 0):
            new.append(v)
    if args.json:
        json.dump(dict(total=len(found), by_rule=dict(by_rule), new=new), open(args.json, "w"), indent=1)
    for v in new:
        print(f"{v['file']}:{v['line']}: [{v['rule']}] {v['text']}")
    label = "violations" if args.all else "NEW violations (beyond baseline)"
    print(f"standard_lint: {len(new)} {label}; {len(found)} total in Sources/", file=sys.stderr)
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main())
