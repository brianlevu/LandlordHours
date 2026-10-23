#!/usr/bin/env python3
"""Deterministic pre-checks for a directory of iOS captures (3x PNGs). No AI.

  frame_check.py FRAME_DIR [--out DIR] [--recursive] [--crops] [--min-ratio 4.5]

Per frame:
  duplicates   byte-identical files under different names (sha256)
  violet       share of pixels with hue 252-300, s>0.35, v>0.45 (retired brand hue)
  status bar   ink-vs-background contrast of the top 54pt (time and icon halves, each on its own)
  tokens       canvas / card / action colours sampled at fixed points, nearest brand token + deltaE76
  text         glyph clusters (edge-density line boxes): glyph colour vs local background contrast;
               flags < 4.5:1, or < 3:1 for big text (box height >= 22pt)
Writes frame_check.json (everything) and frame_check.md (ONLY flagged frames and regions).
Suppression (defaults in DEFAULTS, override with --config JSON, disable with --no-suppress):
  skip frames   names matching `*midfade*` (mid-animation) get no checks and are listed under Skipped
  iOS-drawn     lock-screen / wallpaper frames: only the duplicate check runs
  theme-fixed   Welcome frames: dark/light byte-identical pairs are expected; Welcome and paywall-* frames may have blueprint blue as canvas
  bands         text is ignored inside the status bar, home indicator, tab bar and the scroll fade above it
  allowed       per-region token allow-list (blueprint #1E3FA6, hero gradient #1D3EA4>#19358E)
  glyph size    clusters smaller than --min-cluster-pt, or small square-ish blobs (card corners), are not text
Exit 0 clean, 1 flagged. Python 3 stdlib + Pillow. Heuristics: confirm every flag by eye.
Tokens come from docs/design/2.0-brand-system.md.

Mode `density` (the [measured] rules of docs/design/DESIGN-STANDARD.md section 2; needs numpy):
  frame_check.py density FRAME.png [FRAME2.png ...] [--json out.json] [--dt auto|default|xxl|ax]
                         [--scale 3] [--fold 0.88] [--items-present N]
  Per frame: list row heights, largest card share of the viewport, complete rows above the fold,
  empty-band share inside cards. Verdicts: D1 row 56-88pt (default Dynamic Type), D2 item <= 12%
  (<= 45% AX3), D3 >= 5 items above fold (with --items-present), D4 empty bands <= 35%, D6 card <= 20%
  / hero <= 40% (grouped list containers are judged per row). Exit 1 on any FAIL.
  Standard amendments applied: D2 <= 45% at AX3; D4 skips grouped value-row containers (>= 3 rows of
  44-68pt, 88pt at XXL; D4 only, D1 and D2 still apply); a card's centred foot action ("Confirm N likely", last
  row < 56pt) is not a row for D1/D2/D3. Not counted as cards: sheets (a box that reaches the screen
  edge; its inner cards are found against the sheet fill), day section headers (1.15a: a left-only text
  band above a row that starts with a ring control; not a row, and its spacing is not an empty band),
  the pinned "Confirm N likely" bar (1.3b: two hairlines 38-48pt apart at the fold; its top edge becomes
  the fold), header bands of a sheet, blue controls under
  120pt, outlined input fields, and at AX3 any block cut by the fold (judged by D2 on its visible part).
"""
from __future__ import annotations
import argparse, colorsys, fnmatch, hashlib, json, math, sys
from collections import deque
from pathlib import Path
import os, re
from PIL import Image, ImageChops, ImageFilter
try:
    import numpy as np
except ImportError:  # density mode only
    np = None

SCALE = 3.0  # px per pt of the frame being checked; set per frame by use_scale()
# Known device capture sizes (portrait and landscape): px per pt and device class.
KNOWN_SIZES = {
    (1206, 2622): (3.0, "iphone"), (1320, 2868): (3.0, "iphone"), (1179, 2556): (3.0, "iphone"),
    (2064, 2752): (2.0, "ipad"), (2752, 2064): (2.0, "ipad"),      # iPad Pro 13" at 2x
    (1398, 2034): (3.0, "duo"), (2034, 1398): (3.0, "duo"),        # Duo closed
    (2007, 2853): (3.0, "duo"), (2853, 2007): (3.0, "duo"),        # Duo open
}


def infer_scale(w, h):
    """(px per pt, device class) from the capture size; unknown phone-like sizes are 3x."""
    if (w, h) in KNOWN_SIZES:
        return KNOWN_SIZES[(w, h)]
    return 3.0, "unknown"


def use_scale(scale):
    global SCALE
    SCALE = float(scale)

STATUS_PT = 54
TOKENS = {  # docs/design/2.0-brand-system.md
    "canvas": {"light": "#EEF2FA", "dark": "#0B1230"},
    "card": {"light": "#FFFFFF", "dark": "#141C3F"},
    "cardTertiary": {"light": "#F6F8FD", "dark": "#1B2550"},
    "action": {"light": "#1E3FA6", "dark": "#8FD3FF"},
    "actionSurface": {"light": "#E3E9FA", "dark": "#182A5C"},
    "brand": {"light": "#1E3FA6", "dark": "#1E3FA6"},  # theme-fixed blueprint hero
}
# Everything a gate has repeatedly rejected as a false positive lives here. Override with --config FILE.json.
DEFAULTS = {
    "bands_pt": {"status_bar": 54, "home_indicator": 34, "tab_bar": 112, "scroll_fade": 28},  # heights; tab_bar includes the home indicator
    "skip_frame_globs": ["*midfade*"],
    "ios_drawn_globs": ["*lockscreen*", "*lock-screen*", "*lock_screen*", "*wallpaper*"],
    "theme_fixed_globs": ["*welcome*"],  # dark/light byte-identical pairs are expected (not paywalls: identical AX3 states are a real defect)
    "blueprint_canvas_globs": ["*welcome*", "*paywall-*"],  # full-bleed blueprint screens: blueprint blue is the canvas
    "min_cluster_pt": [16, 8],       # (width, height) of a glyph cluster, in points
    "corner_blob_max_pt": [24, 1.6],  # clusters narrower than this AND with width/height below the ratio are card corners
    "allowed_tokens": {  # region -> [{"color": "#hex" | "#a>#b" gradient, "tol": dE, "frames": optional glob}]
        "card": [{"color": "#1E3FA6", "tol": 8}, {"color": "#1D3EA4>#19358E", "tol": 10}],
        "action": [{"color": "#1E3FA6", "tol": 8}, {"color": "#1D3EA4>#19358E", "tol": 10}],
        "canvas": [{"color": "#1E3FA6", "tol": 10, "frames": "@blueprint_canvas"},
                   {"color": "#1D3EA4>#19358E", "tol": 12, "frames": "@blueprint_canvas"}],
    },
}
CFG = DEFAULTS


def seg_dist(c, a, b):
    """Smallest dE from colour c to the RGB segment a-b (sampled; gradients are linear in RGB)."""
    return min(dE(c, tuple(a[i] + (b[i] - a[i]) * t / 20 for i in range(3))) for t in range(21))


def allowed(region, rgb, fname):
    for e in CFG["allowed_tokens"].get(region, []):
        fr = e.get("frames")
        if fr and not (matches(fname, CFG["blueprint_canvas_globs"]) if fr == "@blueprint_canvas" else fnmatch.fnmatch(fname, fr)): continue
        a, _, b = e["color"].partition(">")
        d = seg_dist(rgb, hex2rgb(a), hex2rgb(b)) if b else dE(rgb, hex2rgb(a))
        if d <= e.get("tol", 8): return e["color"]
    return None


def matches(name, globs): return any(fnmatch.fnmatch(name, g) for g in globs)


DELTA_E_FLAG = {"canvas": 8.0, "card": 8.0, "action": 16.0}


def hex2rgb(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
def rgb2hex(c): return "#%02X%02X%02X" % tuple(int(round(x)) for x in c)


def lin(v):
    v /= 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def lum(c): return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])


def ratio(a, b):
    la, lb = lum(a), lum(b)
    if la < lb: la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def lab(c):
    r, g, b = (lin(x) for x in c)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def dE(a, b): return math.dist(lab(a), lab(b))


def median_color(px):
    n = len(px)
    return tuple(sorted(p[i] for p in px)[n // 2] for i in range(3))


def mode_color(px, q=4):
    from collections import Counter
    c = Counter((p[0] // q, p[1] // q, p[2] // q) for p in px)
    (r, g, b), _ = c.most_common(1)[0]
    return (r * q + q // 2, g * q + q // 2, b * q + q // 2)


def region_pixels(im, box):
    return list(im.crop(box).getdata())


# ---------------------------------------------------------------- checks

def violet_pct(im):
    small = im.resize((im.width // 2, im.height // 2))
    h, s, v = small.convert("HSV").split()
    m = ImageChops.multiply(ImageChops.multiply(h.point(lambda x: 255 if 178.5 <= x <= 212.5 else 0),
                                                s.point(lambda x: 255 if x > 0.35 * 255 else 0)),
                            v.point(lambda x: 255 if x > 0.45 * 255 else 0))
    hist = m.histogram()
    return 100.0 * hist[255] / (small.width * small.height)


def ink_vs_bg(px):
    """Split a region into background (median) and ink (farthest pixels). Returns (ink, bg, ratio) or None."""
    bg = median_color(px)
    dist = sorted(px, key=lambda p: -sum(abs(p[i] - bg[i]) for i in range(3)))
    far = dist[:max(8, len(px) // 40)]
    if sum(abs(far[0][i] - bg[i]) for i in range(3)) < 90:
        return None  # no glyphs here
    core = dist[:max(6, len(far) // 3)]
    ink = median_color(core)
    return ink, bg, ratio(ink, bg)


def status_bar(im):
    h = int(STATUS_PT * SCALE)
    out = []
    for name, (x0, x1) in (("time", (0.08, 0.40)), ("icons", (0.62, 0.95))):
        px = region_pixels(im, (int(im.width * x0), int(12 * SCALE), int(im.width * x1), h))
        r = ink_vs_bg(px)
        if r:
            out.append({"part": name, "ink": rgb2hex(r[0]), "bg": rgb2hex(r[1]), "ratio": round(r[2], 2)})
    return out


def sample_tokens(im, fname="", suppress=True):
    W, H = im.size
    res = {}
    # canvas: gutter strip x = 3..9pt, four heights
    px = []
    for fy in (0.25, 0.4, 0.6, 0.8):
        y = int(H * fy)
        px += region_pixels(im, (int(3 * SCALE), y, int(9 * SCALE), y + 6))
    c = median_color(px)
    res["canvas"] = c
    # card: modal colour in the column x = 26..32pt that is not canvas
    col = [p for p in region_pixels(im, (int(26 * SCALE), int(H * 0.15), int(32 * SCALE), int(H * 0.85)))
           if dE(p, c) > 3]
    if len(col) > 200:
        res["card"] = mode_color(col, 2)
    # action: modal saturated blue/cyan pixel
    small = im.resize((max(1, W // 3), max(1, H // 3)))
    blue = []
    for p in small.getdata():
        hh, ss, vv = colorsys.rgb_to_hsv(p[0] / 255, p[1] / 255, p[2] / 255)
        if 0.52 <= hh <= 0.68 and ss > 0.5 and 0.35 < vv < 0.95:
            blue.append(p)
    if len(blue) > 0.002 * small.width * small.height:
        res["action"] = mode_color(blue, 4)
    out = {}
    for name, rgb in res.items():
        names = {"canvas": ["canvas"], "card": ["card", "cardTertiary", "actionSurface", "brand"],
                 "action": ["action", "brand", "actionSurface", "card", "canvas"]}[name]
        best = None
        for tn in names:
            for theme, hx in TOKENS[tn].items():
                d = dE(rgb, hex2rgb(hx))
                if best is None or d < best[0]: best = (d, tn, theme, hx)
        flag = best[0] > DELTA_E_FLAG[name]
        ok = allowed(name, rgb, fname) if (flag and suppress) else None
        out[name] = {"sampled": rgb2hex(rgb), "nearest": f"{best[1]}/{best[2]} {best[3]}", "deltaE": round(best[0], 1),
                     "flag": flag and not ok}
        if ok: out[name]["allowed_by"] = ok
    return out


def text_regions(im, min_ratio, suppress=True, stats=None):
    """Find line boxes by edge density, measure glyph-vs-background contrast in each."""
    W, H = im.size
    D = max(1, int(round(SCALE)))  # downsample so one pixel is one point
    g = im.convert("L").resize((W // D, H // D), Image.LANCZOS)
    e = g.filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 28 else 0)
    e = e.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MaxFilter(3))
    w, h = e.size
    data = e.load()
    seen = bytearray(w * h)
    boxes = []
    b = CFG["bands_pt"]
    top = STATUS_PT if not suppress else b["status_bar"]  # status bar handled separately
    ph = H / SCALE
    bottom_cut = ph - b["tab_bar"] - b["scroll_fade"]  # tab bar, home indicator and the fade above it
    stats = stats if stats is not None else {}
    def bump(k): stats[k] = stats.get(k, 0) + 1
    for y0 in range(top, h):
        for x0 in range(w):
            if data[x0, y0] and not seen[y0 * w + x0]:
                q = deque([(x0, y0)]); seen[y0 * w + x0] = 1
                x1 = x2 = x0; y1 = y2 = y0; n = 0
                while q:
                    x, y = q.popleft(); n += 1
                    x1 = min(x1, x); x2 = max(x2, x); y1 = min(y1, y); y2 = max(y2, y)
                    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                        if 0 <= nx < w and top <= ny < h and data[nx, ny] and not seen[ny * w + nx]:
                            seen[ny * w + nx] = 1; q.append((nx, ny))
                bw, bh = x2 - x1 + 1, y2 - y1 + 1
                if 6 <= bh <= 40 and bw >= 12 and n > 20:
                    boxes.append((x1, y1, x2, y2))
    out = []
    for x1, y1, x2, y2 in boxes:
        # shrink the dilation (3 passes of 3x3 = ~3px) back to the glyph extent
        box = (max(0, (x1 + 3) * D), max(0, (y1 + 3) * D), min(W, (x2 - 2) * D), min(H, (y2 - 2) * D))
        if box[2] - box[0] < 8 * SCALE or box[3] - box[1] < 5 * SCALE: continue
        px = region_pixels(im, box)
        r = ink_vs_bg(px)
        if not r: continue
        ink, bg, cr = r
        height_pt = (box[3] - box[1]) / SCALE
        width_pt = (box[2] - box[0]) / SCALE
        if suppress:
            if (box[1] / SCALE + height_pt / 2) >= bottom_cut: bump("band: tab bar / home indicator / scroll fade"); continue
            mw, mh = CFG["min_cluster_pt"]
            if width_pt < mw or height_pt < mh: bump("glyph cluster too small"); continue
            cw, cr_ = CFG["corner_blob_max_pt"]
            if width_pt < cw and width_pt / max(height_pt, 1) < cr_: bump("corner-like blob"); continue
        big = height_pt >= 22
        need = 3.0 if big else min_ratio
        out.append({"box_pt": [round(box[0] / SCALE), round(box[1] / SCALE), round(box[2] / SCALE), round(box[3] / SCALE)],
                    "ink": rgb2hex(ink), "bg": rgb2hex(bg), "ratio": round(cr, 2), "need": need, "flag": cr < need,
                    "big": big, "_box": box})
    return out


# ----------------------------------------------------------------- main

def legacy_main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir"); ap.add_argument("--out", default=".")
    ap.add_argument("--recursive", action="store_true")
    ap.add_argument("--crops", action="store_true", help="save a crop of every flagged text region")
    ap.add_argument("--min-ratio", type=float, default=4.5)
    ap.add_argument("--violet-max", type=float, default=0.05, help="flag when violet pixels exceed this percent")
    ap.add_argument("--config", help="JSON file overriding DEFAULTS (bands_pt, skip_frame_globs, allowed_tokens, ...)")
    ap.add_argument("--scale", type=float, help="px per pt; default is inferred from the capture size (iPhone 3x, iPad Pro 13in 2x, Duo 3x)")
    ap.add_argument("--skip-glob", action="append", default=[], help="extra frame-name glob to skip (repeatable)")
    ap.add_argument("--exclude-top", type=float, help="status bar band height in pt (text ignored above it)")
    ap.add_argument("--exclude-bottom", type=float, help="tab bar band height in pt, home indicator included")
    ap.add_argument("--min-cluster-pt", help="WxH minimum glyph cluster in pt, e.g. 16x8")
    ap.add_argument("--no-suppress", action="store_true", help="old behaviour: every raw flag, no suppression rules")
    a = ap.parse_args()
    global CFG
    CFG = json.loads(json.dumps(DEFAULTS))
    if a.config:
        for k, v in json.loads(Path(a.config).read_text()).items():
            CFG[k].update(v) if isinstance(CFG.get(k), dict) else CFG.__setitem__(k, v)
    CFG["skip_frame_globs"] += a.skip_glob
    if a.exclude_top is not None: CFG["bands_pt"]["status_bar"] = a.exclude_top
    if a.exclude_bottom is not None: CFG["bands_pt"]["tab_bar"] = a.exclude_bottom
    BANDS_DEFAULT = dict(CFG["bands_pt"])
    # iPad / Duo: 24pt status bar, no bottom tab bar (the sidebar or top tab bar is content), home indicator only
    BANDS_TABLET = dict(status_bar=24, home_indicator=20, tab_bar=20, scroll_fade=0)
    if a.min_cluster_pt: CFG["min_cluster_pt"] = [float(x) for x in a.min_cluster_pt.lower().split("x")]
    sup = not a.no_suppress
    suppressed = {}
    root = Path(a.dir)
    files = sorted(root.rglob("*.png") if a.recursive else root.glob("*.png"))
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    frames, skipped, hashes = [], [], {}
    for f in files:
        hashes.setdefault(hashlib.sha256(f.read_bytes()).hexdigest(), []).append(f.name)
    def dup_exempt(n): return sup and (matches(n, CFG["skip_frame_globs"]) or matches(n, CFG["theme_fixed_globs"]))
    dups = []
    for v in hashes.values():
        v = [n for n in v if not (sup and matches(n, CFG["skip_frame_globs"]))]
        if len(v) > 1 and not (all(dup_exempt(n) for n in v)):
            dups.append(v)
        elif len(v) > 1: suppressed["theme-fixed identical pair"] = suppressed.get("theme-fixed identical pair", 0) + 1
    for f in files:
        if sup and matches(f.name, CFG["skip_frame_globs"]):
            skipped.append((f.name, "mid-animation frame (skip glob)")); continue
        try:
            im = Image.open(f).convert("RGB")
        except Exception as e:
            skipped.append((f.name, f"unreadable: {e}")); continue
        if a.scale:
            sc, dev = a.scale, "custom"
        else:
            sc, dev = infer_scale(im.width, im.height)
        if dev == "unknown" and (im.width < 1000 or not (0.40 <= im.width / im.height <= 0.80)):
            skipped.append((f.name, f"unknown capture size ({im.width}x{im.height}); pass --scale N to check it")); continue
        use_scale(sc)
        CFG["bands_pt"] = dict(BANDS_DEFAULT if dev in ("iphone", "unknown", "custom") else BANDS_TABLET)
        rec = {"file": f.name, "size": [im.width, im.height], "flags": []}
        ios = sup and matches(f.name, CFG["ios_drawn_globs"])
        if ios:
            skipped.append((f.name, "iOS-drawn frame: only the duplicate check applies")); frames.append(rec); continue
        v = violet_pct(im); rec["violet_pct"] = round(v, 3)
        if v > a.violet_max: rec["flags"].append(f"violet {v:.2f}% of pixels")
        rec["status_bar"] = status_bar(im)
        for s in rec["status_bar"]:
            need = 4.5
            if s["ratio"] < need: rec["flags"].append(f"status bar {s['part']} {s['ratio']}:1 ({s['ink']} on {s['bg']})")
        rec["tokens"] = sample_tokens(im, f.name, sup)
        for k, t in rec["tokens"].items():
            if t["flag"]: rec["flags"].append(f"token {k} {t['sampled']} is dE {t['deltaE']} from {t['nearest']}")
        tr = text_regions(im, a.min_ratio, sup, suppressed)
        rec["text_regions"] = [{k: v for k, v in t.items() if k != "_box"} for t in tr]
        for i, t in enumerate(tr):
            if t["flag"]:
                rec["flags"].append(f"text {t['box_pt']} {t['ratio']}:1 < {t['need']} ({t['ink']} on {t['bg']})")
                if a.crops:
                    cd = out / "flagged"; cd.mkdir(exist_ok=True)
                    b = t["_box"]; pad = 12
                    im.crop((max(0, b[0] - pad), max(0, b[1] - pad), min(im.width, b[2] + pad), min(im.height, b[3] + pad))
                            ).save(cd / f"{f.stem}__{i}.png")
        frames.append(rec)
    dup_names = {n for g in dups for n in g}
    for r in frames:
        if r["file"] in dup_names:
            grp = next(g for g in dups if r["file"] in g)
            r["flags"].insert(0, "byte-identical to " + ", ".join(n for n in grp if n != r["file"]))
    rep = {"dir": str(root), "frames": len(frames), "duplicates": dups, "skipped": skipped, "suppressed": suppressed, "results": frames}
    (out / "frame_check.json").write_text(json.dumps(rep, indent=1))
    L = [f"# frame_check: {root}", "",
         f"{len(frames)} frames, {sum(1 for r in frames if r['flags'])} flagged, {len(dups)} duplicate group(s), "
         f"{len(skipped)} skipped. Heuristics: confirm each flag by eye. Only flagged items are listed.", ""]
    if suppressed:
        L += ["Suppressed (not flagged): " + "; ".join(f"{k} x{v}" for k, v in sorted(suppressed.items())), ""]
    if dups:
        L += ["## Byte-identical files", ""] + ["- " + ", ".join(g) for g in dups] + [""]
    flagged = [r for r in frames if r["flags"]]
    if flagged:
        L += ["## Flagged frames", ""]
        for r in flagged:
            L.append(f"### {r['file']}")
            L += [f"- {x}" for x in r["flags"][:40]]
            if len(r["flags"]) > 40: L.append(f"- ... {len(r['flags']) - 40} more in the JSON")
            L.append("")
    if skipped:
        L += ["## Skipped", ""] + [f"- {n}: {why}" for n, why in skipped[:20]]
    (out / "frame_check.md").write_text("\n".join(L) + "\n")
    print(f"{len(frames)} frames, {len(flagged)} flagged, {len(dups)} duplicate groups -> {out}/frame_check.md")
    return 1 if flagged else 0


# ---- density mode (design standard section 2) ----
D1_MIN, D1_MAX = 56.0, 88.0
D2_DEFAULT, D2_AX = 0.12, 0.45
D4_MAX = 0.35
D6_CARD, D6_HERO = 0.20, 0.40
FOLD_FRAC = 0.88


def rgb_to_lab(a: np.ndarray) -> np.ndarray:
    c = a.astype(np.float64) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]),
                     200 * (f[..., 1] - f[..., 2])], axis=-1)


def runs(mask: np.ndarray, min_len: int = 1, close_gap: int = 0):
    idx = np.flatnonzero(mask)
    if idx.size == 0:
        return []
    out, start, prev = [], idx[0], idx[0]
    for i in idx[1:]:
        if i - prev - 1 > close_gap:
            out.append((start, prev + 1))
            start = i
        prev = i
    out.append((start, prev + 1))
    return [(a, b) for a, b in out if b - a >= min_len]


def detect_dt(name: str) -> str:
    n = name.lower()
    if re.search(r"ax\d?(?![a-z])", n):
        return "ax"
    if "xxl" in n:
        return "xxl"
    return "default"


def analyse(path: str, dt: str, scale: float, fold_frac: float, items_present: int | None, device: str = "iphone",
            crop_pt=None):
    img = Image.open(path).convert("RGB")
    if crop_pt:  # analyse one pane of a multi-column iPad/Duo layout: x0:x1 in points
        img = img.crop((int(crop_pt[0] * scale), 0, int(crop_pt[1] * scale), img.height))
    W, H = img.size
    a = np.asarray(img)
    lab = rgb_to_lab(a)
    vp_pt = H / scale
    fold = int(H * fold_frac)
    # pinned batch bar (standard 1.3b): a 44pt capsule just above the tab bar. It is not a row or a
    # card; content under it is hidden, so the bar's top edge becomes the effective fold.
    bar = None
    xs_ = slice(int(54 * scale), W - int(54 * scale))
    edge_rows = []
    for y in range(max(fold - int(90 * scale), 8), min(fold + int(14 * scale), H - 8)):
        up = (np.linalg.norm(lab[y, xs_] - lab[y - 4, xs_], axis=1) > 2).mean()
        dn = (np.linalg.norm(lab[y, xs_] - lab[y + 4, xs_], axis=1) > 2).mean()
        if up > 0.7 and dn > 0.7:
            edge_rows.append(y)
    for ytop in edge_rows:
        for ybot in edge_rows:
            if 38 * scale <= ybot - ytop <= 48 * scale:
                bar = (ytop, ybot)
                break
        if bar:
            break
    if bar:
        fold = min(fold, bar[0])
    # iPad/Duo with a sidebar: the content column starts at the sidebar's long vertical edge
    cx = 0
    if device not in ("iphone", "unknown", "custom") and W > H * 0.9:
        lo_, hi_ = int(180 * scale), int(460 * scale)
        rows_ = slice(int(80 * scale), H - int(80 * scale), 4)
        prof = [np.linalg.norm(lab[rows_, x] - lab[rows_, x - 3], axis=1).mean() for x in range(lo_, min(hi_, W - 10))]
        if prof and max(prof) > 1.5:
            cx = lo_ + int(np.argmax(prof))
    canvas0 = lab[:, cx + 6, :]  # per-row canvas colour
    probes = [cx + int(40 * scale), W - int(40 * scale)]
    top_skip = int((62 if device in ("iphone", "unknown", "custom") else 30) * scale)  # status bar / dynamic island

    def detect(canvas, ylo, yhi):
        """Card boxes between ylo and yhi against a per-row canvas colour."""
        both = np.ones(H, dtype=bool)
        for px in probes:
            band = lab[:, px - 3:px + 3, :]
            d = np.linalg.norm(band - canvas[:, None, :], axis=2)
            both &= (d > 2.5).mean(axis=1) > 0.8
        both[:ylo] = False
        both[yhi:] = False
        out = []
        for (y0, y1) in runs(both, min_len=int(40 * scale), close_gap=3):
            ym = (y0 + y1) // 2
            x0 = probes[0]
            # leftmost edge over sampled rows: a sheet reaches the screen edge somewhere on
            # its height (its top corners are rounded), a card never gets closer than its gutter
            for yy in sorted({ym, *range(y0 + 10, y1 - 10, 30)}):
                xx = probes[0]
                while xx > cx and np.linalg.norm(lab[yy, xx - 1] - canvas[yy]) > 4.5:
                    xx -= 1
                x0 = min(x0, xx)
            x1 = probes[1]
            while x1 < W - 1 and np.linalg.norm(lab[ym, x1 + 1] - canvas[ym]) > 4.5:
                x1 += 1
            x1 += 1
            cols = [x0 + int(22 * scale), x1 - int(22 * scale)]

            def inside(y):
                return all(np.linalg.norm(lab[y, cx] - canvas[y]) > 2.5 for cx in cols)
            while y0 > ylo and inside(y0 - 1):
                y0 -= 1
            while y1 < yhi and inside(y1):
                y1 += 1
            inner = a[y0:y1, x0 + 6:x1 - 6].reshape(-1, 3)
            vals, counts = np.unique((inner // 4), axis=0, return_counts=True)
            fill_rgb = (vals[counts.argmax()] * 4 + 2).astype(np.uint8)
            fr, fg, fb = [int(v) for v in fill_rgb]
            blue = fb >= 120 and fb - fr >= 80 and (fb - fr) / max(fb, 1) > 0.6
            out.append(dict(y0=int(y0), y1=int(y1), x0=int(x0), x1=int(x1), canvas=canvas,
                            fill=rgb_to_lab(fill_rgb[None, :])[0], blue=bool(blue)))
        return out

    # 1. cards against the page canvas; wide runs touching the screen edge are sheets / header bands
    sheet_x = cx + int(12 * scale)
    cards, sheets, controls = [], [], []
    for c in detect(canvas0, top_skip, fold):
        if c["x0"] < sheet_x:
            sheets.append(c)
            continue
        cards.append(c)
    # 2. inside each sheet the canvas is the sheet fill, so find its cards again
    for s in sheets:
        # sheet fill from the gutter strip just inside its edge (cards never touch it)
        sy0 = s["y0"] + (s["y1"] - s["y0"]) // 3
        strip = a[sy0:s["y1"], s["x0"] + 8:s["x0"] + 30].reshape(-1, 3)
        vals, counts = np.unique(strip // 4, axis=0, return_counts=True)
        sfill = rgb_to_lab((vals[counts.argmax()] * 4 + 2).astype(np.uint8)[None, :])[0]
        canvas2 = canvas0.copy()
        canvas2[s["y0"]:s["y1"]] = sfill
        for c in detect(canvas2, max(s["y0"], top_skip), min(s["y1"], fold)):
            if c["x0"] >= sheet_x and (c["x0"], c["y0"]) not in [(k["x0"], k["y0"]) for k in cards]:
                cards.append(c)
    # 3. saturated blue boxes shorter than 120pt are buttons, not heroes or cards
    kept = []
    for c in cards:
        c["hero"] = c["blue"] and (c["y1"] - c["y0"]) >= 120 * scale
        if c["blue"] and not c["hero"]:
            controls.append(c)
            continue
        kept.append(c)
    # 4. an outlined box (edge pixels clearly differ from its own fill) is an input field, not a card
    cards = []
    fields = []
    for c in sorted(kept, key=lambda c: c["y0"]):
        ym = (c["y0"] + c["y1"]) // 2
        edge = min(np.linalg.norm(lab[ym, c["x0"] + k] - c["fill"]) for k in (1, 2))
        if not c["hero"] and edge > 5 and np.linalg.norm(c["fill"] - c["canvas"][ym]) > 2.5:
            fields.append(c)
        else:
            cards.append(c)
    canvas = canvas0

    res_cards, all_rows = [], []
    for c in cards:
        cv = c["canvas"]
        y0, y1, x0, x1 = c["y0"], min(c["y1"], H), c["x0"], c["x1"]
        cut = c["y1"] >= fold - 2
        vis_y1 = min(y1, fold) if cut else y1
        band = lab[y0:vis_y1, x0 + 3:x1 - 3, :]
        div_rows = []
        n = band.shape[0]
        off = 4
        if not c["hero"] and n > 2 * off + 2:
            # divider candidate at y: differs from both y-off and y+off across >= 50% of the width
            cand = np.zeros(n, dtype=bool)
            ys = np.arange(off, n - off)
            d_up = np.linalg.norm(band[ys] - band[ys - off], axis=2) > 2.5
            d_dn = np.linalg.norm(band[ys] - band[ys + off], axis=2) > 2.5
            # hairline dividers run to the card's trailing edge; progress tracks and
            # text do not, so require the strip near the trailing edge to differ too
            # (window 8-15pt from the edge: iPhone dividers run to the edge, iPad ones stop ~7pt short)
            # iPad inset-grouped dividers stop 15pt short of the card edge (the content inset)
            tab = device not in ("iphone", "unknown", "custom")
            t0, t1 = (int(24 * scale), int(16 * scale)) if tab else (int(15 * scale), int(8 * scale))
            tail = (d_up[:, -t0:-t1].mean(axis=1) >= 0.9) & (d_dn[:, -t0:-t1].mean(axis=1) >= 0.9)
            # a progress bar (coloured fill + grey track) is not a divider: hairlines are neutral
            chroma = np.hypot(band[ys][:, :, 1], band[ys][:, :, 2])
            neutral = (chroma > 38).mean(axis=1) < 0.03  # dark-theme hairlines are navy (chroma ~29)
            cand[ys] = (d_up.mean(axis=1) >= 0.5) & (d_dn.mean(axis=1) >= 0.5) & tail & neutral
            for (a0, a1) in runs(cand, close_gap=1):
                if a1 - a0 <= 4 and a0 > 8 and n - a1 > 8:
                    div_rows.append(y0 + (a0 + a1) // 2)
        # day section headers (standard 1.15a): a left-aligned text band with no trailing value,
        # directly above a row that starts with a leading ring control. Not a row.
        headers = []
        bands = []
        if not c["hero"]:
            ink = (np.linalg.norm(lab[y0:vis_y1, x0 + 6:x1 - 6, :] - c["fill"], axis=2) > 22)
            bands = runs(ink.any(axis=1), min_len=int(5 * scale), close_gap=int(2 * scale))
            cw = (x1 - x0) - 12

            def extent(b):
                cols = np.flatnonzero(ink[b[0]:b[1]].any(axis=0))
                return cols[0], cols[-1]

            def starts_with_ring(b, partial=False):
                sub = ink[b[0]:b[1]]
                cols = np.flatnonzero(sub.any(axis=0))
                if cols.size == 0 or cols[0] > int(24 * scale):
                    return False
                run0 = runs(sub.any(axis=0), close_gap=int(2 * scale))[0]
                w = run0[1] - run0[0]
                blob = sub[:, run0[0]:run0[1]]
                rr = np.flatnonzero(blob.any(axis=1))
                h = rr[-1] - rr[0] + 1
                fillr = blob[rr[0]:rr[-1] + 1].mean()
                hmin = 4 * scale if partial else 16 * scale  # a ring clipped by the fold or the pinned bar
                return 16 * scale <= w <= 30 * scale and hmin <= h <= 30 * scale and (partial or fillr < 0.45)
            for bi in range(len(bands) - 1):
                b = bands[bi]
                lo, hi = extent(b)
                # the band under a header starts with a ring control; the header itself does not, and
                # may carry a trailing action label ("Review all"), so no limit on its right extent
                if (lo <= int(24 * scale) and (b[1] - b[0]) <= 30 * scale and not starts_with_ring(b)
                        and starts_with_ring(bands[bi + 1], partial=bool(cut and bi + 1 == len(bands) - 1))):
                    headers.append(dict(ink_top=y0 + b[0], ink_bot=y0 + b[1],
                                        prev_bot=(y0 + bands[bi - 1][1]) if bi > 0 else None,
                                        next_top=y0 + bands[bi + 1][0]))
        if bands and cut and not c["hero"]:
            b = bands[-1]
            lo, hi = extent(b)
            if (lo <= int(24 * scale) and hi <= 0.62 * cw and (b[1] - b[0]) <= 30 * scale
                    and (vis_y1 - y0) - b[1] <= int(60 * scale)
                    and not any(h["ink_top"] == y0 + b[0] for h in headers)):
                headers.append(dict(ink_top=y0 + b[0], ink_bot=y0 + b[1],
                                    prev_bot=(y0 + bands[-2][1]) if len(bands) > 1 else None, next_top=None))
        pad = int(10 * scale)  # row insets 10/10
        bounds = [y0] + div_rows + [y1]
        segs = [[bounds[i], bounds[i + 1]] for i in range(len(bounds) - 1)]
        for h in headers:
            for sg in list(segs):
                if sg[0] <= h["ink_top"] < sg[1]:
                    i = segs.index(sg)
                    parts = []
                    # a divider may sit between the previous day's last row and this header
                    # (r8): then the segment starts after prev_bot and has no row above the header
                    if h["prev_bot"] is not None and h["prev_bot"] + pad > sg[0] + 2 * pad:
                        parts.append([sg[0], h["prev_bot"] + pad])
                    if h["next_top"] is not None:
                        parts.append([h["next_top"] - pad, sg[1]])
                    segs[i:i + 1] = parts
                    break
        rows = []
        for i, (top, bot) in enumerate(segs):
            last = i == len(segs) - 1
            complete = bot <= fold and not (last and cut)
            rows.append(dict(y0=top, y1=bot, h_pt=round((bot - top) / scale, 1), complete=bool(complete), foot=False))
        is_list = len(div_rows) >= 1 or len(headers) >= 1
        # foot action ("Confirm N likely"): the last row of a list container, shorter than the
        # D1 minimum, whose ink is one centred text run. It is not a list item.
        if is_list and len(rows) >= 2:
            lr = rows[-1]
            if lr["h_pt"] < D1_MIN and lr["complete"]:
                seg = lab[lr["y0"] + 3:lr["y1"] - 3, x0 + 3:x1 - 3, :]
                ink = (np.linalg.norm(seg - c["fill"], axis=2) > 12).any(axis=0)
                xs = np.flatnonzero(ink)
                if xs.size:
                    mid = (xs[0] + xs[-1]) / 2 / seg.shape[1]
                    span = (xs[-1] - xs[0]) / seg.shape[1]
                    if abs(mid - 0.5) <= 0.12 and span <= 0.7:
                        lr["foot"] = True
        item_rows = [r for r in rows if not r["foot"]]
        # D4 exemption: grouped value rows (Settings-style) have uniform rows of 44-64pt
        # at default type (<= 84pt at XXL); their padding is the row rhythm.
        value_group = False
        if is_list and dt in ("default", "xxl") and len(item_rows) >= 3:
            cap = 68 if dt == "default" else 88  # LHRow.Value is 52pt; the stepper row runs taller
            hs = [r["h_pt"] for r in item_rows if r["complete"]]
            core = [h for h in hs if 44 <= h <= cap]
            value_group = (len(core) >= 3 and len(core) >= 0.6 * len(hs)
                           and (max(core) - min(core)) <= max(14, 0.3 * min(core))
                           and all(h <= 120 for h in hs))  # one taller row (stepper, gap note) is allowed
        # empty bands: rows inside card (x inset 16pt) all card fill or canvas
        ix0, ix1 = x0 + int(16 * scale), x1 - int(16 * scale)
        empty_share = None
        if not c["hero"] and ix1 > ix0:
            iy0, iy1 = y0 + int(16 * scale), vis_y1 - (0 if cut else int(16 * scale))
            if iy1 > iy0:
                reg = lab[iy0:iy1, ix0:ix1, :]
                near_fill = np.linalg.norm(reg - c["fill"], axis=2) <= 3
                near_canvas = np.linalg.norm(reg - cv[iy0:iy1, None, :], axis=2) <= 3
                empty_row = (near_fill | near_canvas).all(axis=1)
                for h in headers:  # the spacing a day header adds (1.15a) is structure, not an empty band
                    za = (h["prev_bot"] if h["prev_bot"] is not None else y0) + pad - iy0
                    zb = ((h["next_top"] - pad) if h["next_top"] is not None else vis_y1) - iy0
                    empty_row[max(za, 0):max(zb, 0)] = False
                empty_share = round(float(empty_row.sum() / (vis_y1 - y0)), 3)
            else:
                empty_share = 0.0
        h_pt = (y1 - y0) / scale
        vis_pt = (vis_y1 - y0) / scale
        res_cards.append(dict(
            bbox_px=[c["x0"], y0, c["x1"], y1], hero=c["hero"], list_container=is_list,
            height_pt=round(h_pt, 1), visible_height_pt=round(vis_pt, 1),
            viewport_share=round(vis_pt / vp_pt, 3), cut_by_fold=bool(cut),
            empty_band_share=empty_share, d4_exempt_value_rows=bool(value_group),
            rows=rows if is_list else [], gutter_pt=round(c["x0"] / scale, 1),
            day_headers=[dict(y0=h["ink_top"], y1=h["ink_bot"], ink_h_pt=round((h["ink_bot"] - h["ink_top"]) / scale, 1)) for h in headers]))
        if is_list:
            all_rows += rows

    checks = []

    def chk(rule, ok, detail):
        checks.append(dict(rule=rule, pass_=bool(ok), detail=detail))

    item_rows_all = [r for r in all_rows if not r["foot"]]
    done = [r for r in item_rows_all if r["complete"]]
    if dt in ("default", "xxl") and done:
        # rows only grow with Dynamic Type, so the 56pt floor holds at XXL; the 88pt ceiling is default only
        hi = D1_MAX if dt == "default" else 1e9
        bad = [r["h_pt"] for r in done if not (D1_MIN <= r["h_pt"] <= hi)]
        chk("D1 row height 56-88pt" if dt == "default" else "D1 row height >= 56pt (XXL)", not bad,
            f"rows {[float(r['h_pt']) for r in done]}" + (f"; out of range {[float(b) for b in bad]}" if bad else ""))
    lim = D2_AX if dt == "ax" else D2_DEFAULT
    # D2: complete rows, plus the visible part of a row cut by the fold (a lower bound)
    d2_rows = [r["h_pt"] for r in done]
    d2_rows += [r["h_pt"] if r["complete"] else (min(r["y1"], fold) - r["y0"]) / scale
                for r in item_rows_all if not r["complete"]]
    d2_rows = [h for h in d2_rows]
    for c in res_cards:
        if c["cut_by_fold"] and not c["list_container"] and dt == "ax":
            d2_rows.append(c["visible_height_pt"])  # a cut single block at AX is judged as one item
    if d2_rows:
        worst = max(d2_rows) / vp_pt
        chk(f"D2 item share <= {int(lim * 100)}%", worst <= lim, f"largest row {worst:.1%}")
    for c in [c for c in res_cards if not c["hero"] and not c["list_container"]]:
        if c["cut_by_fold"] and dt == "ax":
            continue  # cut by the fold at AX3: a container, judged by D2, not a card
        chk("D6 card share <= 20%", c["viewport_share"] <= D6_CARD,
            f"card at y={c['bbox_px'][1]} is {c['viewport_share']:.1%} ({c['visible_height_pt']}pt)")
    for c in res_cards:
        if c["hero"]:
            chk("D6 hero share <= 40%", c["viewport_share"] <= D6_HERO,
                f"hero {c['viewport_share']:.1%}")
        if c["empty_band_share"] is not None and not c["d4_exempt_value_rows"]:
            chk("D4 empty bands <= 35%", c["empty_band_share"] <= D4_MAX,
                f"card at y={c['bbox_px'][1]} empty {c['empty_band_share']:.1%}")
    n_items = len(done)
    if items_present is not None and items_present >= 5:
        need = 4 if dt in ("xxl", "ax") else 5
        chk(f"D3 items above fold >= {need}", n_items >= need, f"{n_items} complete rows above fold")

    verdict = "PASS" if all(c["pass_"] for c in checks) and checks else ("FAIL" if checks else "NO_DATA")
    return dict(
        frame=path, size_px=[W, H], viewport_pt=[round(W / scale, 1), round(vp_pt, 1)], dynamic_type=dt,
        fold_px=fold, cards=res_cards,
        ignored=dict(sheets=[[s["x0"], s["y0"], s["x1"], s["y1"]] for s in sheets],
                     controls=[[s["x0"], s["y0"], s["x1"], s["y1"]] for s in controls],
                     fields=[[s["x0"], s["y0"], s["x1"], s["y1"]] for s in fields],
                     pinned_bar=[int(v) for v in bar] if bar else None),
        summary=dict(
            row_heights_pt=[r["h_pt"] for r in done],
            largest_card_share=max([c["viewport_share"] for c in res_cards], default=0.0),
            largest_non_list_card_share=max([c["viewport_share"] for c in res_cards if not c["list_container"] and not c["hero"]], default=0.0),
            items_above_fold=n_items,
            max_empty_band_share=max([c["empty_band_share"] or 0 for c in res_cards], default=0.0),
            gutter_pt_info=(res_cards[0]["gutter_pt"] if res_cards else None)),
        checks=checks, verdict=verdict)


def _j(o):
    if isinstance(o, np.integer):
        return int(o)
    if isinstance(o, np.floating):
        return float(o)
    raise TypeError(type(o))


def cmd_density(args) -> int:
    results = []
    for f in args.frames:
        dt = args.dt if args.dt != "auto" else detect_dt(os.path.basename(f))
        with Image.open(f) as im0:
            sc, dev = infer_scale(*im0.size)
        if args.scale:
            sc, dev = args.scale, ("custom" if dev == "unknown" else dev)
        fold = args.fold if args.fold else (0.88 if dev in ("iphone", "unknown", "custom") else 0.97)
        use_scale(sc)
        crop = [float(v) for v in args.crop.split(":")] if args.crop else None
        r = analyse(f, dt, sc, fold, args.items_present, dev, crop)
        r["scale"], r["device"] = sc, dev
        results.append(r)
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(results, fh, indent=2, default=_j)
    else:
        print(json.dumps(results, indent=2, default=_j))
    for r in results:
        s = r["summary"]
        fails = [c["rule"] for c in r["checks"] if not c["pass_"]]
        print(f"{r['verdict']:7} {os.path.basename(r['frame'])} rows={[float(x) for x in s['row_heights_pt']]} "
              f"maxcard={s['largest_card_share']:.0%} items={s['items_above_fold']} "
              f"empty={s['max_empty_band_share']:.0%}" + (f" fails={fails}" if fails else ""),
              file=sys.stderr if not args.json else sys.stdout)
    n_fail = sum(r["verdict"] == "FAIL" for r in results)
    n_nod = sum(r["verdict"] == "NO_DATA" for r in results)
    line = (f"density: {len(results) - n_fail - n_nod}/{len(results)} frames pass, {n_fail} fail, "
            f"{n_nod} no data (nothing measurable above the fold)")
    print(line, file=sys.stderr if not args.json else sys.stdout)
    return 1 if n_fail else 0


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "density":
        if np is None:
            sys.exit("density mode needs numpy")
        p = argparse.ArgumentParser(prog="frame_check.py density", description="measured density rules (standard section 2)")
        p.add_argument("mode")
        p.add_argument("frames", nargs="+")
        p.add_argument("--json", help="write JSON here (default: stdout)")
        p.add_argument("--dt", choices=["auto", "default", "xxl", "ax"], default="auto",
                       help="Dynamic Type of the frame; auto reads _ax3 / xxl from the file name")
        p.add_argument("--scale", type=float, help="px per pt; default inferred from the capture size (iPhone 3x, iPad Pro 13in 2x, Duo 3x)")
        p.add_argument("--fold", type=float, help="fold as a fraction of frame height (default 0.88 phone with tab bar, 0.97 iPad/Duo)")
        p.add_argument("--crop", help="x0:x1 in pt: analyse one pane of a multi-column layout (list pane, detail pane)")
        p.add_argument("--items-present", type=int, help="items that exist in the screen's data; enables D3")
        return cmd_density(p.parse_args())
    return legacy_main()


if __name__ == "__main__":
    sys.exit(main())
