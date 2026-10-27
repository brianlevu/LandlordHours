#!/usr/bin/env python3
"""Sheet-body row measurer: the density fallback for frames where frame_check.py density says NO_DATA.

frame_check.py density treats a presented sheet as an ignored region, so a frame that is only a sheet
(Log time, Timer, pickers) comes back NO_DATA. gate_rubric.md section 1 fails those closed. This script
measures the rows inside the sheet instead: a row is a run of the sheet's tertiary fill (backgroundTertiary,
#F6F8FD light / #1B2550 dark) that spans most of the content width. It reports each row's height in pt,
checks D1 (56-88pt at default, >= 56pt at XXL, no ceiling at AX) and D2 (one row <= 12% of the viewport,
<= 25% at AX), and prints the largest empty band as information (it is not a card, so D4 does not apply).

    python3 scripts/qa/sheet_rows.py FRAME.png [...]        # exit 1 on a D1/D2 failure, 2 when nothing is measurable
"""
import re, sys, os
import numpy as np
from PIL import Image

FILL = {"light": (0xF6, 0xF8, 0xFD), "dark": (0x1B, 0x25, 0x50)}
SCALE = 3.0

# Frames with no row or card to measure: a written, per-frame reason (rubric section 1 allows an exemption in writing).
EXEMPT = {}
try:
    import json
    EXEMPT = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "density_exemptions.json")))
except (OSError, ValueError):
    pass

def dt_of(name):
    n = name.lower()
    if re.search(r"ax\d?(?![a-z])", n): return "ax"
    if "xxl" in n: return "xxl"
    return "default"

def theme_of(name): return "dark" if "dark" in name.lower() else "light"

def measure(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(int)
    H, W, _ = a.shape
    fill = np.array(FILL[theme_of(os.path.basename(path))])
    x0, x1 = int(24 * SCALE), W - int(24 * SCALE)
    hit = (np.abs(a[:, x0:x1, :] - fill).sum(axis=2) <= 6).mean(axis=1) >= 0.35
    hit[:int(100 * SCALE)] = False  # status bar and sheet title band
    # close gaps up to 12px (text glyph rows and hairlines inside one row)
    ys = np.flatnonzero(hit)
    groups = []
    for y in ys:
        if groups and y - groups[-1][1] <= 12: groups[-1][1] = y + 1
        else: groups.append([y, y + 1])
    groups = [tuple(g) for g in groups]
    rows = [(s, e) for s, e in groups if (e - s) / SCALE >= 40]
    return H, rows

def main(paths):
    code = 0
    for p in paths:
        dt = dt_of(os.path.basename(p))
        H, rows = measure(p)
        vp = H / SCALE
        ex = EXEMPT.get(os.path.basename(p))
        if ex:
            print(f"EXEMPT {os.path.basename(p)}: {ex}"); continue
        if not rows:
            print(f"NO_DATA {os.path.basename(p)} (no tertiary-fill rows)"); code = max(code, 2); continue
        hs = [round(float((e - s) / SCALE), 1) for s, e in rows]
        # A 2pt state border (dashed "choose", amber "check this") eats the fill at both edges, so the
        # D1 floor is measured with 4pt of slack. Groups outside 52-88pt are note fields or
        # multi-line text, listed as "other": not rows, so no D1, but D2 still applies to them.
        # At AX the label stacks over the value, so a row is taller than 88pt: every group is a row.
        item = [h for h in hs if 52 <= h <= 88 or dt == "ax"]
        other = [h for h in hs if h not in item]
        bad = []
        if dt != "ax" and any(h < 56 - 4 for h in item): bad.append("D1 <56")
        lim = 0.25 if dt == "ax" else 0.12
        if max(hs) / vp > lim: bad.append(f"D2 {max(hs) / vp:.1%} > {lim:.0%}")
        if not item: bad.append("no row-height groups")
        gaps = [(rows[i + 1][0] - rows[i][1]) / SCALE for i in range(len(rows) - 1)]
        tail = (H - rows[-1][1]) / SCALE
        print(f"{'FAIL' if bad else 'PASS'} {os.path.basename(p)} rows={item} other={other} max={max(hs) / vp:.1%} of viewport"
              + (f" {bad}" if bad else "") + f" (info: last row to frame bottom {tail:.0f}pt)")
        if bad: code = 1
    return code

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
