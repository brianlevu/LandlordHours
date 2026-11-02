#!/usr/bin/env python3
"""release_flags_source_check.py — every `-LH…` launch flag literal sits inside `#if DEBUG`.

The binary check (release_flags_check.sh) greps `strings` of a Release build, but Swift stores
strings of 15 bytes or fewer inline in the code, so short flags (`-LHInitialTab`, `-LHColorScheme`)
never show up there. This source check closes that gap: it walks Sources/**/*.swift, tracks
`#if DEBUG` / `#else` / `#endif` nesting, and fails on any `"-LH<Name>"` literal that would compile
into a Release build.

Allowed outside DEBUG (deliberate, documented in release_flags_check.sh):
  -LHAnalyticsForce  Sources/App/Analytics.swift

Usage: python3 scripts/qa/release_flags_source_check.py [repo-root]
Exit 0 clean, 1 on a Release-visible flag.
"""
import re
import sys
from pathlib import Path

ALLOWED = {"-LHAnalyticsForce"}
FLAG = re.compile(r'"(-LH[A-Z][A-Za-z0-9]*)"')
IF = re.compile(r"^\s*#if\s+(.*)$")
ELSEIF = re.compile(r"^\s*#elseif\b")
ELSE = re.compile(r"^\s*#else\b")
ENDIF = re.compile(r"^\s*#endif\b")


def release_lines(text):
    """Yields (line_no, line) for lines that compile when DEBUG is not set."""
    # Each frame: (branch_compiles_in_release, frame_is_debug_conditional)
    stack = []
    for no, line in enumerate(text.splitlines(), 1):
        m = IF.match(line)
        if m:
            cond = m.group(1).split("//")[0].strip()
            if cond == "DEBUG":
                stack.append([False, True])
            elif cond in ("!DEBUG", "!(DEBUG)"):
                stack.append([True, True])
            else:
                stack.append([True, False])   # other conditions: assume both branches compile
            continue
        if ELSEIF.match(line) and stack:
            if stack[-1][1]:
                stack[-1][0] = True            # `#if DEBUG … #elseif X` — the elseif can compile in Release
            continue
        if ELSE.match(line) and stack:
            if stack[-1][1]:
                stack[-1][0] = not stack[-1][0]
            continue
        if ENDIF.match(line) and stack:
            stack.pop()
            continue
        if all(frame[0] for frame in stack):
            yield no, line


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])
    hits = []
    for path in sorted((root / "Sources").rglob("*.swift")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for no, line in release_lines(text):
            code = line.split("//")[0] if not line.lstrip().startswith("///") else ""
            for flag in FLAG.findall(code):
                if flag not in ALLOWED:
                    hits.append(f"{path.relative_to(root)}:{no}: {flag}")
    if hits:
        print(f"release_flags_source_check: FAIL, {len(hits)} -LH flag(s) compile into Release (move behind #if DEBUG):")
        print("\n".join("  " + h for h in hits))
        return 1
    print("release_flags_source_check: PASS (only " + ", ".join(sorted(ALLOWED)) + " outside #if DEBUG)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
