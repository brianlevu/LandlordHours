#!/usr/bin/env python3
"""two_pane_check.py: the §1.27 DU self-check on two-pane and stacked frames (package J).

Reads each <frame>.png with its <frame>.panes.json sidecar (written by the off-screen renderer,
`AdaptiveSnapshotter`, or by hand for device screenshots: {"mode", "panes", "gap", "bar"} in points).
Measures, per frame:
  DU1  pane widths = (W - gap) / 2 (two-pane) or halves (stacked)
  DU2  text-edge pixels inside the gap/fold rect (neighbour luma step > 40, 8-bit): must be 0
  DU4  right pane (bottom half when stacked): bare wall between the last card row and the bar top,
       as % of the pane height: <= 20% (DU13 on stacked frames)
  WALL largest band of bare wall in each pane (rows with no card, art or text): <= 20% (plan J iPad note)
  DU9  dE76 between the two walls at the fold (mean <= 5, max <= 10)
  DU10 brightest wall pixel at y = 60pt in the work pane: <= 120pt from the fold
  DU12 bar inside the right pane, at its foot (top > 75% of H), never across the gap
  DU16 (dark only) the house-pane wall rises toward the fold at y = 60pt over the last 100pt
Usage: two_pane_check.py <dir-or-frames...> [--json out.json] [--scale N]
Copies of the Duo gate scripts it started from: duo_gate6_aa.py, duo_gate6_m.py, duo_v7_measure7.py.
"""
import json, sys, os, glob, argparse
import numpy as np
from PIL import Image

CARD = {"light": np.array([0xFF, 0xFF, 0xFF]), "dark": np.array([0x14, 0x1C, 0x3F])}


def lin(c):
    c = np.asarray(c, float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def luma(rgb):
    r, g, b = np.moveaxis(lin(rgb), -1, 0)[:3]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def lab(rgb):
    r, g, b = lin(np.asarray(rgb, float))[:3]
    X = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    Z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: np.cbrt(t) if t > 0.008856 else 7.787 * t + 16 / 116
    return np.array([116 * f(Y) - 16, 500 * (f(X) - f(Y)), 200 * (f(Y) - f(Z))])


def theme_of(name):
    return "dark" if ("-dark" in name or "night" in name) else "light"


def row_kinds(img, x0, x1, y0, y1, s, theme):
    """Per row (pt) in [y0, y1): 'card' if >= 40% of the strip is the card colour, 'content' if the
    strip has edges (art or text: neighbour luma step > 12 on 8-bit gray), else 'wall'."""
    gray = np.asarray(Image.fromarray(img).convert("L"), int)
    kinds = []
    for y in range(int(y0), int(y1)):
        py = min(int(y * s + s / 2), img.shape[0] - 1)
        strip = img[py, int(x0 * s):int(x1 * s), :3].astype(int)
        g = gray[py, int(x0 * s):int(x1 * s)]
        if strip.size == 0:
            kinds.append("wall"); continue
        card = (np.abs(strip - CARD[theme]).max(axis=1) < 8).mean()
        edges = (np.abs(np.diff(g)) > 12).sum()
        kinds.append("card" if card >= 0.4 else ("content" if edges >= 2 else "wall"))
    return kinds


def longest(kinds, what="wall"):
    best = cur = 0
    for k in kinds:
        cur = cur + 1 if k == what else 0
        best = max(best, cur)
    return best


def check(png, scale=None):
    side = png[:-4] + ".panes.json"
    if not os.path.exists(side):
        return None
    meta = json.load(open(side))
    img = np.asarray(Image.open(png).convert("RGB"))
    name = os.path.basename(png)[:-4]
    theme = theme_of(name)
    mode = meta.get("mode")
    panes = meta.get("panes", [])
    H, W = img.shape[:2]
    out = {"frame": name, "mode": mode, "theme": theme}
    if mode == "compact" or len(panes) < 2:
        out["skipped"] = "compact"
        return out
    Wpt = panes[1][0] + panes[1][2] if mode == "twoPane" else panes[0][2]
    s = scale or (W / Wpt)
    gap = meta["gap"]
    gx, gy, gw, gh = gap
    first, second = panes
    # DU1
    if mode == "twoPane":
        out["DU1_panes_pt"] = [round(first[2], 1), round(second[2], 1)]
        out["DU1"] = "PASS" if abs(first[2] - second[2]) < 1 else "FAIL"
    else:
        out["DU1_halves_pt"] = [round(first[3], 1), round(second[3], 1)]
        out["DU1"] = "PASS" if abs(first[3] - second[3]) < 1 else "FAIL"
    # DU2: text edges inside the gap (inset 2pt so the card edges beside it do not count)
    gray = np.asarray(Image.fromarray(img).convert("L"), int)
    if mode == "twoPane":
        band = gray[:, int((gx + 2) * s):int((gx + gw - 2) * s)]
        steps = np.abs(np.diff(band, axis=1))
    else:
        band = gray[int((gy + 2) * s):int((gy + gh - 2) * s), :]
        steps = np.abs(np.diff(band, axis=0))
    out["DU2_edge_px"] = int((steps > 40).sum())
    out["DU2"] = "PASS" if out["DU2_edge_px"] == 0 else "FAIL"
    # DU12 + DU4
    bar = meta.get("bar") or []
    work = second
    if bar:
        bx, by, bw, bh = bar
        inside = bx >= work[0] - 1 and bx + bw <= work[0] + work[2] + 1
        foot = by > 0.75 * (H / s)
        out["DU12_bar_pt"] = [round(v, 1) for v in bar]
        out["DU12"] = "PASS" if inside and foot else "FAIL"
        x0, x1 = work[0] + 20, work[0] + work[2] - 20
        kinds = row_kinds(img, x0, x1, work[1], by, s, theme)
        last = max([i for i, k in enumerate(kinds) if k != "wall"], default=-1)
        wall = (len(kinds) - 1 - last) if last >= 0 else len(kinds)
        out["DU4_wall_pt"] = wall
        out["DU4_wall_pct"] = round(100 * wall / work[3], 1)
        out["DU4"] = "PASS" if out["DU4_wall_pct"] <= 20 else "FAIL"
    # WALL: largest bare band in each pane (house pane: whole height; work pane: above the bar)
    for label, p, ybot in (("house", first, first[1] + first[3]), ("work", work, (bar[1] if bar else work[1] + work[3]))):
        kinds = row_kinds(img, p[0] + 12, p[0] + p[2] - 12, p[1] + 24, ybot - 4, s, theme)
        band = longest(kinds)
        out[f"WALL_{label}_pct"] = round(100 * band / p[3], 1)
    out["WALL"] = "PASS" if max(out["WALL_house_pct"], out["WALL_work_pct"]) <= 20 else "FAIL"
    if mode == "twoPane":
        # DU9: wall either side of the fold, rows where both sides are bare wall
        dEs = []
        for y in range(40, int(H / s) - 100, 30):
            a = np.median(img[int(y * s):int((y + 4) * s), int((gx - 6) * s):int((gx - 1) * s)].reshape(-1, 3), axis=0)
            b = np.median(img[int(y * s):int((y + 4) * s), int((gx + gw + 1) * s):int((gx + gw + 6) * s)].reshape(-1, 3), axis=0)
            if np.abs(a - CARD[theme]).max() < 8 or np.abs(b - CARD[theme]).max() < 8:
                continue
            dEs.append(float(np.linalg.norm(lab(a) - lab(b))))
        if dEs:
            out["DU9_dE_mean"] = round(float(np.mean(dEs)), 1)
            out["DU9_dE_max"] = round(float(np.max(dEs)), 1)
            out["DU9"] = "PASS" if out["DU9_dE_mean"] <= 5 and out["DU9_dE_max"] <= 10 else "FAIL"
        # DU10: brightest wall pixel at y = 60pt across the work pane
        row = img[int(60 * s), int((gx + gw) * s):int((work[0] + work[2]) * s), :3]
        L = luma(row.astype(float))
        xb = int(np.argmax(L)) / s
        out["DU10_brightest_from_fold_pt"] = round(xb, 1)
        out["DU10"] = "PASS" if xb <= 120 else "FAIL"
        if theme == "dark":
            r = img[int(60 * s), int((gx - 100) * s):int((gx - 1) * s), :3].astype(float)
            lw = luma(r)
            out["DU16_luma_100pt_vs_fold"] = [round(float(np.mean(lw[:6])), 4), round(float(np.mean(lw[-6:])), 4)]
            out["DU16"] = "PASS" if lw[-6:].mean() > lw[:6].mean() else "FAIL"
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--json")
    ap.add_argument("--scale", type=float)
    a = ap.parse_args()
    files = []
    for i in a.inputs:
        files += sorted(glob.glob(os.path.join(i, "*.png"))) if os.path.isdir(i) else [i]
    res = [r for r in (check(f, a.scale) for f in files) if r]
    fails = 0
    for r in res:
        if r.get("skipped"):
            print(f"{r['frame']}: compact, skipped"); continue
        verdicts = {k: v for k, v in r.items() if v in ("PASS", "FAIL")}
        bad = [k for k, v in verdicts.items() if v == "FAIL"]
        fails += len(bad)
        nums = {k: v for k, v in r.items() if k not in verdicts and k not in ("frame", "mode", "theme")}
        print(f"{r['frame']} [{r['mode']}] {'FAIL ' + ','.join(bad) if bad else 'PASS'} {nums}")
    if a.json:
        json.dump(res, open(a.json, "w"), indent=1)
    print(f"frames {len(res)}, failing checks {fails}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
