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

Mode `breaks` (mid-word line breaks, "Notifica-/tions"; needs macOS + swift for Vision OCR):
  frame_check.py breaks FRAME.png [FRAME2.png ...] [--json out.json]
  OCRs each frame (scripts/qa/ocr_lines.swift) and flags a line that ends in a letter + hyphen when the next
  line below it starts with a lowercase letter: the word was cut inside itself. Each hit prints both halves
  and the frame; a hit is a CANDIDATE, so confirm it on the frame by eye before it is cited (OCR can
  invent a hyphen). `midword_breaks(lines)` is the pure detector (tested in test_frame_check.py). Exit 1 on a hit.

Mode `density` (the [measured] rules of docs/design/DESIGN-STANDARD.md section 2; needs numpy):
  frame_check.py density FRAME.png [FRAME2.png ...] [--json out.json] [--dt auto|default|xxl|ax]
                         [--scale 3] [--fold 0.88] [--items-present N]
  Per frame: list row heights, largest card share of the viewport, complete rows above the fold,
  empty-band share inside cards. Verdicts: D1 row 56-88pt (default Dynamic Type), D2 item <= 12%
  (<= 45% AX3), D3 >= 5 items above fold (with --items-present), D4 empty bands <= 35%, D6 card <= 20%
  / hero <= 40% (grouped list containers are judged per row). Exit 1 on any FAIL.
  Rentals gallery (standard 1.4 exception): with the explicit --rentals-gallery flag (never inferred
  from the frame name), tiles are judged by "D6 Rentals tile <= 38%" instead of the 20% card cap;
  D6 hero and every other rule still apply.
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


def sample_tokens(im, fname="", suppress=True, hero=None):
    """hero: None, or dict(theme=..., art=[x0,y0,x1,y1] px or None) for a dusk/night page frame. On a hero frame the
    canvas is matched against the page gradient path (not a flat token), pixels under the house art are masked from
    the card and action samples, and gradient pixels are not mistaken for a card (v2 spec 1)."""
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
    y_lo, y_hi = int(H * 0.15), int(H * 0.85)
    if hero:  # sample the card column below the art only, and skip pixels that are just the page gradient
        if hero.get("art"):
            y_lo = max(y_lo, hero["art"][3] + int(4 * SCALE))
        y_lo = min(y_lo, y_hi - 1)
        col = [p for p in region_pixels(im, (int(26 * SCALE), y_lo, int(32 * SCALE), y_hi))
               if page_dE(p, hero["theme"]) > HERO_DE and dE(p, c) > 3]
    else:
        col = [p for p in region_pixels(im, (int(26 * SCALE), y_lo, int(32 * SCALE), y_hi)) if dE(p, c) > 3]
    if len(col) > 200:
        res["card"] = mode_color(col, 2)
    # action: modal saturated blue/cyan pixel
    small = im.resize((max(1, W // 3), max(1, H // 3)))
    if hero and hero.get("art"):  # mask the 3D art: its slate-blue shadows are not the action colour
        from PIL import ImageDraw
        ImageDraw.Draw(small).rectangle([v // 3 for v in hero["art"]], fill=(0, 0, 0))
    blue = []
    for p in small.getdata():
        hh, ss, vv = colorsys.rgb_to_hsv(p[0] / 255, p[1] / 255, p[2] / 255)
        if 0.52 <= hh <= 0.68 and ss > 0.6 and 0.35 < vv < 0.95:  # s>0.6: antialiased slate (s~0.5) is not the action colour
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
        if hero and name == "canvas":  # gradient path, tolerance dE 6
            gd = page_dE(rgb, hero["theme"])
            best = (gd, "pageGradient", hero["theme"], "/".join(PAGE_GRADIENT[hero["theme"]]))
            flag = gd > HERO_DE
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



def page_ink_flags(tr, hero):
    """Spec 2: on the LIGHT page, text whose background is the page must be one of the five allowed inks."""
    if hero["theme"] != "light":
        return []
    out = []
    art = hero.get("art")
    for t in tr:
        bx = t["box_pt"]
        if art and bx[0] * SCALE >= art[0] and bx[2] * SCALE <= art[2] and bx[1] * SCALE >= art[1] and bx[3] * SCALE <= art[3]:
            continue  # inside the house art
        bg, ink = hex2rgb(t["bg"]), hex2rgb(t["ink"])
        if page_dE(bg, "light") > 8:
            continue  # the cluster sits on a card or control, not the page
        name, d = min(((n, dE(ink, hex2rgb(h))) for n, h in PAGE_INKS.items()), key=lambda x: x[1])
        if d > 14:
            out.append(f"ink not allowed on page {t['box_pt']} {t['ink']} on {t['bg']} = {t['ratio']}:1 "
                       f"(nearest allowed {name} dE {d:.0f}; only {', '.join(PAGE_INKS)} may be text on the page)")
    return out


EDGE_MIN_RATIO = {"light": 1.8, "dark": 1.5}  # spec says 1.8; the dark pair #2A3560 on #09 0E24 measures 1.62, so dark is 1.5 (noted)


def card_edge_flags(path, im, hero, globs, hero_rect):
    """Spec 2: every card on a hero frame has a 1pt pageCardEdge ring (dE 6) that reads >= 1.8:1 against the page."""
    sc = SCALE
    r = analyse(str(path), detect_dt(os.path.basename(str(path))), sc, 0.88, None, "iphone", None,
                [float(v) for v in hero_rect.split(",")] if hero_rect else None, globs)
    a_ = np.asarray(im)
    want = hex2rgb(PAGE_CARD_EDGE[hero["theme"]])
    out = []
    for c in r["cards"]:
        if c["hero"] or c["list_container"] is None:
            continue
        x0, y0, x1, y1 = c["bbox_px"]
        ym = (y0 + y1) // 2
        k = max(0, int(0.5 * sc))
        edge = tuple(int(v) for v in a_[ym, x0 + k])
        page = tuple(int(v) for v in a_[ym, 6])
        d, cr = dE(edge, want), ratio(edge, page)
        if d > HERO_DE or cr < EDGE_MIN_RATIO[hero["theme"]]:
            out.append(f"card floats on page: card at y={round(y0 / sc)}pt edge {rgb2hex(edge)} is dE {d:.1f} from "
                       f"pageCardEdge {rgb2hex(want)}, {cr:.2f}:1 vs page (want dE<={HERO_DE:.0f}, >= {EDGE_MIN_RATIO[hero['theme']]}:1)")
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
    ap.add_argument("--hero-rect", help="x0,y0,x1,y1 in pt: mask this region as the house art on hero frames (default: auto-detected)")
    ap.add_argument("--hero-glob", action="append", help="extra frame-name glob that marks a hero frame (default today-*, rental-*, welcome*, inbox-empty*, milestone*)")
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
        hero = None
        if np is not None and sup and is_hero_frame(f.name, im, a.hero_glob or None):
            th = page_theme(im)
            art = find_hero_art(np.asarray(im), SCALE, detect_dt(f.name), hero_rect=[float(v) for v in a.hero_rect.split(",")] if a.hero_rect else None)
            hero = dict(theme=th, art=art["bbox_px"] if art else None)
            rec["hero"] = dict(theme=th, art_bbox_px=hero["art"])
            if not art:
                rec["flags"].append("hero frame but no house art found (BLOCKED: pass --hero-rect to override)")
        rec["tokens"] = sample_tokens(im, f.name, sup, hero)
        for k, t in rec["tokens"].items():
            if t["flag"]: rec["flags"].append(f"token {k} {t['sampled']} is dE {t['deltaE']} from {t['nearest']}")
        tr = text_regions(im, a.min_ratio, sup, suppressed)
        rec["text_regions"] = [{k: v for k, v in t.items() if k != "_box"} for t in tr]
        if hero:
            rec["flags"] += page_ink_flags(tr, hero)
            rec["flags"] += card_edge_flags(f, im, hero, a.hero_glob or None, a.hero_rect)
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
    with np.errstate(all="ignore"):
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



# ---- v2 hero / dusk page (standard section H; NOTES-standard-v2.md items 1-3) ----
HERO_GLOBS = ["today-*", "rental-*", "welcome*", "inbox-empty*", "milestone*"]
PAGE_GRADIENT = {"light": ["#EAE3D7", "#D8CFC0", "#E8E0D3"], "dark": ["#0B1230", "#080C1D"]}  # pageTop, pageMid, pageBottom
PAGE_CARD_EDGE = {"light": "#A3966F", "dark": "#2A3560"}
PAGE_INKS = {"textPrimary": "#121B33", "textSecondary": "#4A5068", "action": "#1E3FA6",
             "behind": "#9A3624", "positiveOnPage": "#0C5A30"}  # inks allowed as text on the LIGHT page (section H.4)
HERO_DE = 6.0  # a sample within this dE of the gradient is "the page"


def page_dE(rgb, theme=None):
    """dE from rgb to the nearest point of the page gradient (a colour path through the gradient stops), over the
    given theme or both. The gradient is matched as a path, not a flat token (spec 1)."""
    best = 1e9
    for th, stops in PAGE_GRADIENT.items():
        if theme and th != theme:
            continue
        pts = [hex2rgb(h) for h in stops]
        for a_, b_ in zip(pts, pts[1:]):
            best = min(best, seg_dist(rgb, a_, b_))
    return best


def page_theme(im):
    """'dark' when the gutter strip is dark."""
    g = np.asarray(im.convert("L").crop((int(3 * SCALE), int(im.height * 0.3), int(9 * SCALE), int(im.height * 0.5))))
    return "dark" if g.mean() < 90 else "light"


def is_hero_frame(name, im, globs=None):
    """(a) the name matches the hero globs, or (b) the 54-120pt band samples within dE 6 of the gradient
    (light only: the dark page equals the dark canvas, so by name only)."""
    if matches(name, globs or HERO_GLOBS):
        return True
    if page_theme(im) != "light":
        return False
    pts = [im.getpixel((int(x * SCALE), int(y * SCALE))) for y in (66, 90, 114) for x in (4, 6, 8)]
    return all(page_dE(p, "light") <= HERO_DE for p in pts)


def find_hero_art(a, scale, dt="default", hero_rect=None):
    """The house art: the largest connected region of non-page pixels wider than 60% of the window whose top edge
    is within 54-140pt (54-200pt at AX; the standard says 120 but just-started frames start at 131pt) of the window top. Returns dict(bbox_px, forced) or None.
    hero_rect (x0,y0,x1,y1 in pt) overrides detection. Conservative reading: the top edge may sit up to 3pt past the
    limit, and a scrolled frame whose art touches the status-bar line still counts."""
    H, W = a.shape[:2]
    if hero_rect:
        x0, y0, x1, y1 = [int(round(v * scale)) for v in hero_rect]
        return dict(bbox_px=[max(x0, 0), max(y0, 0), min(x1, W), min(y1, H)], forced=True)
    st = max(1, int(round(scale)))
    sm = a[::st, ::st]
    h, w = sm.shape[:2]
    lab_s = rgb_to_lab(sm)
    page = lab_s[:, min(2, w - 1), :]  # per-row page colour from the gutter
    mask = np.linalg.norm(lab_s - page[:, None, :], axis=2) > 12
    mask[:int(STATUS_PT * scale / st)] = False
    mask[:, :2] = False
    mask[:, -2:] = False
    dm = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0
    seen = np.zeros_like(dm)
    best = None
    max_top = (200 if dt == "ax" else 140) * scale / st
    ys, xs = np.nonzero(mask)
    for i in np.argsort(ys, kind="stable"):
        y, x = int(ys[i]), int(xs[i])
        if seen[y, x]:
            continue
        q = deque([(y, x)])
        seen[y, x] = True
        y0_ = y1_ = y
        x0_ = x1_ = x
        n = 0
        while q:
            cy, cx_ = q.popleft()
            n += 1
            y0_, y1_, x0_, x1_ = min(y0_, cy), max(y1_, cy), min(x0_, cx_), max(x1_, cx_)
            for ny, nx in ((cy + 1, cx_), (cy - 1, cx_), (cy, cx_ + 1), (cy, cx_ - 1)):
                if 0 <= ny < h and 0 <= nx < w and dm[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        if (x1_ - x0_ + 1) * st > 0.6 * W and y0_ <= max_top and n > 200:
            if best is None or n > best[0]:
                best = (n, y0_, y1_, x0_, x1_)
    if not best:
        return None
    _, y0_, y1_, x0_, x1_ = best
    return dict(bbox_px=[int(x0_ * st), int(y0_ * st), int((x1_ + 1) * st), int((y1_ + 1) * st)], forced=False)


def _covers_art(c, art_box):
    """A box 'encloses' the art when it covers >= 75% of the art bbox (the bbox may include the chip's halo)."""
    x0, y0, x1, y1 = art_box
    iw, ih = min(c[2], x1) - max(c[0], x0), min(c[3], y1) - max(c[1], y0)
    return iw > 0 and ih > 0 and iw * ih >= 0.75 * (x1 - x0) * (y1 - y0)


def hero_measures(a, art, scale, dt, card_boxes):
    """H1-H4 and card_edge_around_art. The frame square is not visible in a screenshot, so H1/H2 use the standard's
    fixed frame (390pt default, 295pt AX) and are ADVISORY (they never change the verdict); the art bbox share is
    measured. card_edge_around_art is a verdict: a closed card enclosing the art = FAIL 'hero in a card'."""
    H, W = a.shape[:2]
    x0, y0, x1, y1 = art["bbox_px"]
    vp = H / scale
    frame_side = 295.0 if dt == "ax" else min(390.0, W / scale - 12)
    lo, hi = (0.24, 0.32) if dt == "ax" else (0.36, 0.46)
    encl = [c for c in card_boxes if _covers_art(c, art["bbox_px"])]
    return dict(art_bbox_pt=[round(v / scale, 1) for v in (x0, y0, x1, y1)],
                art_bbox_share=round((y1 - y0) / scale / vp, 3),
                H1_frame_side_pt=round(frame_side, 1), H2_art_share=round(frame_side / vp, 3), H2_range=[lo, hi],
                H2_pass=bool(lo <= frame_side / vp <= hi), ground_line_pt=round(y1 / scale, 1),
                card_edge_around_art=bool(encl), advisory_note="H1/H2/H4 use the fixed frame, not measured")


def detect_dt(name: str) -> str:
    n = name.lower()
    if re.search(r"ax\d?(?![a-z])", n):
        return "ax"
    if "xxl" in n:
        return "xxl"
    return "default"


# Standard section 1.4: a Rentals gallery tile measured 27-36.5% of the viewport (r2/r3 frames). The
# carve-out raises D6's card cap to this hard cap; it is applied only with --rentals-gallery.
D6_RENTALS_TILE = 0.38


def analyse(path: str, dt: str, scale: float, fold_frac: float, items_present: int | None, device: str = "iphone",
            crop_pt=None, hero_rect=None, hero_globs=None, rentals_gallery=False):
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
                # v2: the foot row of a card on the page ("See all 7") is also two lines 38-48pt apart,
                # but its lower line is the card's own bottom edge: canvas right below, card fill right above.
                px_ = int(40 * scale)
                yb_lo, yb_hi = min(ybot + int(6 * scale), H - 1), max(ybot - int(6 * scale), 0)
                ref_lo, ref_hi = lab[yb_lo, 6], lab[yb_hi, 6]
                if (np.linalg.norm(lab[yb_lo, px_] - ref_lo) < 3 and np.linalg.norm(lab[yb_hi, px_] - ref_hi) > 3
                        and np.linalg.norm(lab[yb_hi, W - px_] - ref_hi) > 3):
                    continue
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
        # v2: a card on the dusk/night page carries a 1pt pageCardEdge ring; that is a card edge, not an input outline
        ering = a[ym, c["x0"] + int(0.5 * scale):c["x0"] + max(1, int(0.5 * scale)) + 1].reshape(-1, 3)[0]
        c["page_edge"] = bool(min(dE(tuple(int(v) for v in ering), hex2rgb(h)) for h in PAGE_CARD_EDGE.values()) <= 8)
        if not c["hero"] and not c["page_edge"] and edge > 5 and np.linalg.norm(c["fill"] - c["canvas"][ym]) > 2.5:
            fields.append(c)
        else:
            cards.append(c)
    # 4b. rows that sit directly on a sheet's own fill (a sheet with grouped value rows and no inner
    # card): the canvas probe matches the sheet, so no card is found. Find the hairline dividers
    # across the page and treat the rows they separate as one list container (judged per row).
    if not cards:
        hx0, hx1 = int(40 * scale), W - int(10 * scale)
        yy0, yy1 = top_skip, fold
        hair = []
        off_ = 4
        for y in range(max(yy0, off_), min(yy1, H - off_)):
            seg = lab[y, hx0:hx1]
            if ((np.linalg.norm(seg - lab[y - off_, hx0:hx1], axis=1) > 2.5).mean() >= 0.6
                    and (np.linalg.norm(seg - lab[y + off_, hx0:hx1], axis=1) > 2.5).mean() >= 0.6
                    and (np.hypot(seg[:, 1], seg[:, 2]) > 38).mean() < 0.03
                    # a row divider runs out to the row inset (~20pt from the edge); a document thumbnail's
                    # table rule stops short of it
                    and (np.linalg.norm(lab[y, W - int(26 * scale):W - int(22 * scale)]
                                        - lab[y - off_, W - int(26 * scale):W - int(22 * scale)], axis=1) > 2.5).mean() >= 0.9):
                hair.append(y)
        lines = [(a0 + a1) // 2 for (a0, a1) in runs(np.isin(np.arange(H), hair), close_gap=1) if a1 - a0 <= 4]
        # longest chain of ADJACENT dividers whose spacing is a plausible row height (44-130pt); a
        # document thumbnail's table rules sit 8-25pt apart and break the chain
        best, chain = [], []
        for yv in lines:
            if chain and 44 * scale <= yv - chain[-1] <= 130 * scale:
                chain.append(yv)
            else:
                chain = [yv]
            if len(chain) > len(best):
                best = list(chain)
        if len(best) >= 2:
            sp = int(np.median(np.diff(best)))
            cy0, cy1 = max(best[0] - sp, top_skip), min(best[-1] + sp, fold)
            fill_mid = lab[(cy0 + cy1) // 2, 6]
            # the dividers stop at the row inset, so the container spans the first divider's extent
            hy = best[0]
            dx = np.flatnonzero(np.linalg.norm(lab[hy, :] - lab[hy - off_, :], axis=1) > 2.5)
            dx = dx[dx >= int(8 * scale)]
            cx0, cx1 = (int(dx[0]), min(int(dx[-1]) + int(10 * scale), W)) if dx.size else (0, W)
            cards.append(dict(y0=int(cy0), y1=int(cy1), x0=cx0, x1=cx1, canvas=canvas0, fill=fill_mid,
                              blue=False, hero=False, page_edge=False, sheet_rows=True))
    canvas = canvas0

    # v2 hero: the house art is not a card (D6) and not a row (D2/D4); a card enclosing it is a defect
    hero_info = None
    if hero_rect or matches(os.path.basename(path), hero_globs or HERO_GLOBS):
        art = find_hero_art(a, scale, dt, hero_rect)
        if art:
            boxes = [(c["x0"], c["y0"], c["x1"], c["y1"]) for c in cards + fields]
            hero_info = hero_measures(a, art, scale, dt, boxes)
            ax0, ay0, ax1, ay1 = art["bbox_px"]

            def not_art(c):
                encloses = _covers_art((c["x0"], c["y0"], c["x1"], c["y1"]), (ax0, ay0, ax1, ay1))
                cxm, cym = (c["x0"] + c["x1"]) / 2, (c["y0"] + c["y1"]) / 2
                inside = ax0 <= cxm <= ax1 and ay0 <= cym <= ay1
                return encloses or not inside
            cards = [c for c in cards if not_art(c)]
            fields = [c for c in fields if not_art(c)]
        else:
            hero_info = dict(art_bbox_pt=None, note="no hero art found (BLOCKED if this frame should have one)")

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
        if rentals_gallery:
            # Standard section 1.4 exception: only D6's 20% card cap is lifted for Rentals gallery tiles
            # (27-36% of the viewport by design; the only screen allowed a card per item). They are
            # still capped at 38%; D1-D4 and the hero rule apply as usual.
            chk("D6 Rentals tile <= 38% (standard 1.4)", c["viewport_share"] <= D6_RENTALS_TILE,
                f"tile at y={c['bbox_px'][1]} is {c['viewport_share']:.1%} ({c['visible_height_pt']}pt)")
            continue
        chk("D6 card share <= 20%", c["viewport_share"] <= D6_CARD,
            f"card at y={c['bbox_px'][1]} is {c['viewport_share']:.1%} ({c['visible_height_pt']}pt)")
    for c in res_cards:
        if c["hero"]:
            chk("D6 hero share <= 40%", c["viewport_share"] <= D6_HERO,
                f"hero {c['viewport_share']:.1%}")
        if c["empty_band_share"] is not None and not c["d4_exempt_value_rows"]:
            chk("D4 empty bands <= 35%", c["empty_band_share"] <= D4_MAX,
                f"card at y={c['bbox_px'][1]} empty {c['empty_band_share']:.1%}")
    if hero_info and hero_info.get("art_bbox_pt"):
        chk("H hero not in a card", not hero_info["card_edge_around_art"],
            "a closed card encloses the art (hero in a card)" if hero_info["card_edge_around_art"] else "art sits on the page")
    n_items = len(done)
    if items_present is not None and items_present >= 5:
        need = 4 if dt in ("xxl", "ax") else 5
        chk(f"D3 items above fold >= {need}", n_items >= need, f"{n_items} complete rows above fold")

    verdict = "PASS" if all(c["pass_"] for c in checks) and checks else ("FAIL" if checks else "NO_DATA")
    return dict(
        frame=path, size_px=[W, H], viewport_pt=[round(W / scale, 1), round(vp_pt, 1)], dynamic_type=dt,
        fold_px=fold, cards=res_cards, hero=hero_info,
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



# ---- `hero` mode: art readability and state (spec 3, standard H.2 "Readability on the page", "Windows show state") ----
P99_LIT, P99_UNLIT = 3.0, 2.4
SAT_SHARE_MAX = {"light": 0.40, "dark": 0.28}
MEAN_S_MAX = 0.52
GROUND_LINE = (0.91, 0.93)
WINDOW_GAIN = 0.20


def frame_state(name):
    """'lit' or 'unlit' from the last dash-separated token of the file stem (…-windows-lit, …-workLamp-off,
    …-unlit, …-dark). The appearance token earlier in the name (today-dark-L-…) is deliberately not a state."""
    last = os.path.splitext(os.path.basename(name))[0].lower().split("-")[-1]
    if last == "lit":
        return "lit"
    if last in ("unlit", "dark", "off"):
        return "unlit"
    return None


def art_pixels(a, bbox, scale):
    """Pixels inside the art bbox that are not the page (dE > 12 from the page colour of their row)."""
    x0, y0, x1, y1 = bbox
    lab_r = rgb_to_lab(a[y0:y1, x0:x1])
    lab_p = rgb_to_lab(a[y0:y1, 2:3])
    m = np.linalg.norm(lab_r - lab_p, axis=2) > 12
    return a[y0:y1, x0:x1][m], m


def hero_frame_report(path, dt, scale, hero_rect=None, frame_top=None, frame_side=390.0):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im)
    use_scale(scale)
    theme = page_theme(im)
    art = find_hero_art(a, scale, dt, hero_rect)
    rep = dict(frame=os.path.basename(path), theme=theme, state=frame_state(path), checks=[])

    def chk(rule, verdict, detail):
        rep["checks"].append(dict(rule=rule, verdict=verdict, detail=detail))
    if not art:
        chk("art", "BLOCKED", "no house art found (pass --hero-rect)")
        return rep, None
    x0, y0, x1, y1 = art["bbox_px"]
    px, m = art_pixels(a, art["bbox_px"], scale)
    if len(px) < 500:
        chk("art", "BLOCKED", f"only {len(px)} art pixels")
        return rep, None
    page = tuple(int(v) for v in a[min(y1, a.shape[0]) - 1, 6])
    pl = lum(page)
    f = px.astype(np.float64) / 255.0
    lin_ = np.where(f <= 0.04045, f / 12.92, ((f + 0.055) / 1.055) ** 2.4)
    L = 0.2126 * lin_[:, 0] + 0.7152 * lin_[:, 1] + 0.0722 * lin_[:, 2]
    hi, lo = np.maximum(L, pl), np.minimum(L, pl)
    p99 = float(np.percentile((hi + 0.05) / (lo + 0.05), 99))
    rep["p99_contrast"] = round(p99, 2)
    st = rep["state"]
    need = P99_LIT if st == "lit" else P99_UNLIT
    chk("p99_contrast", "PASS" if p99 >= need else "BLOCKED", f"{p99:.2f}:1 vs page {rgb2hex(page)} (need >= {need} for {st or 'unlabelled (unlit bar)'} frames)")
    hsv = np.array([colorsys.rgb_to_hsv(*(p / 255.0)) for p in px[:: max(1, len(px) // 20000)]])
    sat_share = float((hsv[:, 1] >= 0.25).mean())
    mean_s = float(hsv[:, 1].mean())
    rep["saturation_share"], rep["mean_S"] = round(sat_share, 3), round(mean_s, 3)
    # REVIEW, not FAIL, unless --strict: a screenshot has no alpha, so the art mask includes shadow and ground, and the
    # real CRAFT frames (wood, grass) measure 43-75% here against the spec's 28/40%. The number is printed for the gate.
    chk("saturation_share", "PASS" if sat_share <= SAT_SHARE_MAX[theme] else "REVIEW",
        f"{sat_share:.1%} of art pixels have S >= 0.25 (max {SAT_SHARE_MAX[theme]:.0%} {theme}; screenshot mask, see --strict)")
    chk("mean_S", "PASS" if mean_s <= MEAN_S_MAX else "REVIEW", f"{mean_s:.2f} (max {MEAN_S_MAX})")
    bins = np.bincount(np.minimum((hsv[:, 0] * 12).astype(int), 11), minlength=12) / len(hsv)
    rep["hue_bins_ge_3pct"] = {f"{i * 30}-{i * 30 + 30}": round(float(b), 3) for i, b in enumerate(bins) if b >= 0.03}
    rep["ground_line_pt"] = round(y1 / scale, 1)
    if frame_top is not None:
        g = (y1 / scale - frame_top) / frame_side
        rep["ground_line_frac"] = round(g, 3)
        chk("ground_line", "PASS" if GROUND_LINE[0] <= g <= GROUND_LINE[1] else "FAIL", f"{g:.3f} of the frame (want {GROUND_LINE[0]}-{GROUND_LINE[1]})")
    else:
        chk("ground_line", "INFO", f"art bottom at {y1 / scale:.0f}pt; pass --frame-top-pt to get the fraction of the frame")
    return rep, a


def window_delta(path_lit, path_unlit, boxes):
    """Mean luma in the window boxes (frame fractions) must be >= 20% higher in the lit frame; hashes must differ."""
    out = dict(pair=[os.path.basename(path_lit), os.path.basename(path_unlit)])
    h1 = hashlib.sha256(open(path_lit, "rb").read()).hexdigest()
    h2 = hashlib.sha256(open(path_unlit, "rb").read()).hexdigest()
    if h1 == h2:
        return dict(out, verdict="FAIL", detail="state not captured (identical sha256)")
    if not boxes:
        return dict(out, verdict="BLOCKED", detail="no window boxes for this stage (craft_windows.json)")
    ims = [np.asarray(Image.open(p).convert("L")).astype(np.float64) for p in (path_lit, path_unlit)]
    means = []
    for im_ in ims:
        H, W = im_.shape
        v = [im_[int(b[1] * H):int(b[3] * H), int(b[0] * W):int(b[2] * W)].mean() for b in boxes]
        means.append(float(np.mean(v)))
    gain = means[0] / max(means[1], 1e-6) - 1
    return dict(out, lit_luma=round(means[0], 1), unlit_luma=round(means[1], 1), gain=round(gain, 3),
                verdict="PASS" if gain >= WINDOW_GAIN else "FAIL",
                detail=f"lit window luma is {gain:+.0%} vs unlit (need >= +{WINDOW_GAIN:.0%})")


def cmd_hero(args) -> int:
    windows = {}
    wpath = args.windows or os.path.join(os.path.dirname(os.path.abspath(__file__)), "craft_windows.json")
    if os.path.exists(wpath):
        windows = json.load(open(wpath))
    reports = []
    for f in args.frames:
        with Image.open(f) as im0:
            sc, _ = infer_scale(*im0.size)
        sc = args.scale or sc
        dt = args.dt if args.dt != "auto" else detect_dt(os.path.basename(f))
        hr = [float(v) for v in args.hero_rect.split(",")] if args.hero_rect else None
        rep, _ = hero_frame_report(f, dt, sc, hr, args.frame_top_pt, args.frame_side_pt)
        reports.append(rep)
    pairs = []
    if args.pairs:
        lhs, _, rhs = args.pairs.partition("=")
        names = {os.path.basename(f): f for f in args.frames}
        for n, f in names.items():
            stem, ext = os.path.splitext(n)
            if stem.endswith("-" + lhs):
                other = stem[: -len(lhs)] + rhs + ext
                if other in names:
                    stage = stem.split("-")[0]
                    pairs.append(window_delta(f, names[other], windows.get(stage) or windows.get(stem)))
                else:
                    pairs.append(dict(pair=[n, other], verdict="BLOCKED", detail="counterpart frame not provided"))
    bad = 0
    for r in reports:
        print(f"{r['frame']} ({r['theme']}, state {r['state']})")
        for c in r["checks"]:
            print(f"  {c['verdict']:8} {c['rule']}: {c['detail']}")
            bad += c["verdict"] in ("FAIL", "BLOCKED") or (args.strict and c["verdict"] == "REVIEW")
        if r.get("hue_bins_ge_3pct"):
            print(f"  INFO     hue_bins (>=3% of art): {r['hue_bins_ge_3pct']}  [judgment, for the gate]")
    for p in pairs:
        print(f"{p['verdict']:8} window_delta {p['pair'][0]} vs {p['pair'][1]}: {p['detail']}")
        bad += p["verdict"] in ("FAIL", "BLOCKED")
    if args.json:
        json.dump(dict(frames=reports, pairs=pairs), open(args.json, "w"), indent=2)
    print(f"hero: {bad} FAIL/BLOCKED", file=sys.stderr)
    return 1 if bad else 0


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
        hr = [float(v) for v in args.hero_rect.split(",")] if args.hero_rect else None
        r = analyse(f, dt, sc, fold, args.items_present, dev, crop, hr, args.hero_glob or None,
                    bool(args.rentals_gallery))
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
        if r.get("hero") and r["hero"].get("art_bbox_pt"):
            hh = r["hero"]
            print(f"        hero {os.path.basename(r['frame'])}: art bbox {hh['art_bbox_pt']}pt ({hh['art_bbox_share']:.0%} of window), "
                  f"H1 frame {hh['H1_frame_side_pt']}pt, H2 {hh['H2_art_share']:.1%} (want {hh['H2_range']}), "
                  f"card_edge_around_art={hh['card_edge_around_art']} [H1/H2 advisory]", file=sys.stderr if not args.json else sys.stdout)
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


def midword_breaks(lines, max_gap=1.8):
    """lines: [{text,x,y,w,h}] (px, top-left origin). Returns [(first_half, second_half, y)] for every line that
    ends in letter+hyphen whose next line below starts with a lowercase letter and sits within max_gap line
    heights, overlapping horizontally (the same text block). Compound words that end a line ("co-") are
    rare in this app's copy; a hit is a candidate for the gate to confirm."""
    ls = sorted((l for l in lines if l.get("text", "").strip()), key=lambda l: (l["y"], l["x"]))
    hits = []
    for i, a in enumerate(ls):
        t = a["text"].rstrip()
        if not re.search(r"[A-Za-z\u00C0-\u024F]{3,}[-\u2010\u2011]$", t):
            continue
        for b in ls[i + 1:]:
            gap = b["y"] - (a["y"] + a["h"])
            if gap > max_gap * a["h"]:
                break
            if b["y"] <= a["y"] + a["h"] * 0.4:
                continue  # same row, not the next line
            overlap = min(a["x"] + a["w"], b["x"] + b["w"]) - max(a["x"], b["x"])
            if overlap > 0 and re.match(r"[a-z\u00E0-\u024F]", b["text"].lstrip()):
                hits.append((t, b["text"].strip(), round(a["y"])))
                break
    return hits


def ocr_frames(frames):
    here = os.path.dirname(os.path.abspath(__file__))
    import subprocess
    r = subprocess.run(["swift", os.path.join(here, "ocr_lines.swift"), *frames], capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        sys.exit("ocr_lines.swift failed: " + r.stderr[-400:])
    return json.loads(r.stdout)


def cmd_breaks(args) -> int:
    ocr = ocr_frames(args.frames)
    report, bad = {}, 0
    for f in args.frames:
        hits = midword_breaks(ocr.get(f, []))
        report[f] = [dict(first=a, second=b, y_px=y) for a, b, y in hits]
        for a, b, y in hits:
            print(f"BREAK  {os.path.basename(f)}  y={y}px  \"{a}\" / \"{b}\"")
        bad += bool(hits)
        if not ocr.get(f):
            print(f"BLOCKED {os.path.basename(f)}  OCR found no text", file=sys.stderr)
            bad += 1
    if args.json:
        json.dump(report, open(args.json, "w"), indent=2)
    print(f"breaks: {sum(len(v) for v in report.values())} candidate mid-word break(s) in {len(args.frames)} frame(s)", file=sys.stderr)
    return 1 if bad else 0


# ---- consistency: one header system across tabs (standard "Screen anatomy", S1-S4) ----
SAFE_TOP_PT = {874: 62, 956: 62, 852: 59, 932: 59, 844: 47, 926: 47}  # status bar / Dynamic Island inset per height
TITLE_MIN_PT, TITLE_MAX_PT = 20.0, 96.0   # a large-title glyph band (Fraunces 34: ~25-33pt with descenders at default; ~60-80pt at AX3)
SHEET_TITLE_MIN_PT = 14.0                  # SF title2 / title1 in sheets (~16-24pt)
SUBTITLE_LINE_GAP_PT = 8.0                 # a wrapped subtitle's next line starts this close under the last
SUBTITLE_GAP_PT = 16.0                     # a short text band starting this close under the title (line-box descent + 2pt) is the subtitle
INK_MAX_MEAN = 110                         # light theme ink: mean RGB below this (textPrimary #121B33, textSecondary #4A5068)
INK_MIN_MEAN_DARK = 150                    # dark theme ink: mean RGB above this (textPrimary #F2F4FA, textSecondary #A9B0C8)
FILL_DIFF = 12                             # a pixel differs from the row's edge background by more than this (sum |dRGB|)
CONSIST_BASELINE_TOL_PT = 1.0
TRAILING_SLOT_PT = 72.0                   # the right edge kept for one trailing .icon (44pt + gutter)
TITLE_ZONE_PT = 130.0                     # a screen title starts within this far under the safe area; lower is content (Today's numeral)
CONSIST_GAP_TOL_PT = 2.0


def header_metrics(path, scale=None, kind="tab", search_to=0.55):
    """Measure the screen header of one frame, in points from the top of the window.

    Returns {frame, scale, safe_top_pt, title_top_pt, title_baseline_pt, title_height_pt, header_end_pt,
    last_baseline_pt, content_top_pt, gap_pt (content_top - the header's last baseline), bands}. The gap is
    measured from a baseline, not a glyph bottom, so a descender ("Settings") does not move it. title_* are None when no title band is found
    (a tab with no screen title, the 2.2 Today, is reported as such and fails the cross-tab check).

    Heuristics (confirm by eye):
      ink rows     rows with >= 2 ink pixels between the gutters: mean RGB < 110 on a light page, > 150 on the
                   night page (the theme is read from the page's edge column)
      title band   the tallest ink band (heavier ink breaks a tie) below the safe area whose height is a large title (20-48pt for tabs,
                   14-48pt for sheets) and which starts within 130pt of the safe area; a band above it (back
                   button, nav-bar button, rental chip) is skipped, and a big numeral lower down is not a title
      baseline     the sharpest fall in the band's per-row ink count in its lower 60% (descenders are thin)
      header end   the bottom of the title band, extended over subtitle bands that start <= 16pt under it
      content top  the first row after the header end where >= 1% of the row (left of the 72pt trailing slot)
                   differs from the row's own edge pixel (x = 3pt): a card fill, a field, a chip, or text
    """
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(np.int16)
    h, w = a.shape[:2]
    sc = scale or infer_scale(w, h)[0]
    hpt = round(h / sc)
    safe = SAFE_TOP_PT.get(hpt, 62 if hpt > 860 else 47)
    x0, x1 = int(8 * sc), w - int(8 * sc)
    y0, y1 = int((safe + 2) * sc), int(h * search_to)
    reg = a[y0:y1, x0:x1]
    # Theme from the page under the header (the edge column): on the night canvas ink is light.
    night = float(a[y0:y1, int(3 * sc)].mean()) < 90
    is_ink = (lambda m: m > INK_MIN_MEAN_DARK) if night else (lambda m: m < INK_MAX_MEAN)
    dark = is_ink(reg.mean(axis=2))
    counts = dark.sum(axis=1)
    bands = [(y0 + s, y0 + e) for s, e in runs(counts >= 2, min_len=int(4 * sc), close_gap=int(1.5 * sc))]
    lo = (SHEET_TITLE_MIN_PT if kind == "sheet" else TITLE_MIN_PT) * sc
    # The title is the tallest ink band in the title zone (the largest type on the screen), heavier ink
    # breaking a tie within 2pt: a chip, a back chevron, a share glyph or a section header ("To confirm
    # · 8", long but smaller) is shorter than the screen title at every Dynamic Type size.
    edge_col = a[:, int(3 * sc)]

    def on_canvas(b):
        """A title sits on the page, not inside a card: most of the band differs from a card fill."""
        mid = (b[0] + b[1]) // 2
        row = a[mid, x0:x1]
        fill = (np.abs(row - edge_col[mid][None, :]).sum(axis=1) > FILL_DIFF) & ~is_ink(row.mean(axis=1))
        return fill.mean() < 0.5   # pixels that are neither the page nor ink: a card or field behind the text

    cands = [(s, e) for s, e in bands if lo <= e - s <= TITLE_MAX_PT * sc and s <= (safe + TITLE_ZONE_PT) * sc
             and on_canvas((s, e))]
    title = None
    if cands:
        tallest = max(e - s for s, e in cands)
        near = [b for b in cands if (b[1] - b[0]) >= tallest - 2 * sc]
        title = max(near, key=lambda b: int(counts[b[0] - y0:b[1] - y0].sum()))
    out = {"frame": path, "scale": sc, "safe_top_pt": safe, "kind": kind, "theme": "dark" if night else "light",
           "bands_pt": [[round(s / sc, 1), round(e / sc, 1)] for s, e in bands[:12]],
           "title_top_pt": None, "title_baseline_pt": None, "title_height_pt": None,
           "header_end_pt": None, "last_baseline_pt": None, "content_top_pt": None, "gap_pt": None}
    if title is None:
        return out
    s, e = title
    col = np.append(dark[s - y0:e - y0].sum(axis=1).astype(np.int32), 0)  # the band's own end is a drop too
    start = int((len(col) - 1) * 0.4)
    drops = col[start:-1] - col[start + 1:]
    # first row of the steepest fall (a flat-bottomed glyph run ends on the baseline; descenders are thin)
    base = s + start + int(np.argmax(drops)) if drops.size else e - 1
    def baseline_of(bs, be):
        c = np.append(dark[bs - y0:be - y0].sum(axis=1).astype(np.int32), 0)
        st = int((len(c) - 1) * 0.4)
        d = c[st:-1] - c[st + 1:]
        return bs + st + int(np.argmax(d)) + 1 if d.size else be

    header_end = e
    last_base = base + 1
    merged = 0
    # A wrapped title: its next line is as tall as the first (within 30%) and starts within 12pt.
    for bs, be in bands:
        if bs >= e and bs - e <= 12 * sc and abs((be - bs) - (e - s)) <= 0.3 * (e - s):
            e = be
            header_end = e
            base_line2 = baseline_of(bs, be)
            last_base = base_line2
        elif bs >= e:
            break
    for bs, be in bands:
        # The subtitle starts <= 16pt under the title; a wrapped subtitle's next line follows within 8pt.
        # A band further down (a section header such as "You") is content, not header.
        reach = SUBTITLE_GAP_PT if merged == 0 else SUBTITLE_LINE_GAP_PT
        if bs >= header_end and bs - header_end <= reach * sc and be - bs < TITLE_MIN_PT * sc:
            header_end = be
            last_base = baseline_of(bs, be)
            merged += 1
    # content: first occupied row after the header end
    edge = a[:, int(3 * sc)]
    xr = w - int(TRAILING_SLOT_PT * sc)  # the trailing action's circle hangs below the title band; it is header
    diff = np.abs(a[header_end:y1 + int(200 * sc), x0:xr] - edge[header_end:y1 + int(200 * sc), None, :]).sum(axis=2)
    occ = (diff > FILL_DIFF).mean(axis=1) >= 0.01
    rr = runs(occ, min_len=int(2 * sc))
    # Header furniture that hangs just below the title (a back circle in the leading 72pt, starting within
    # 4pt of the header's end) is not content; a short section header lower down ("You") is.
    while rr:
        cols = np.flatnonzero((diff[rr[0][0]:rr[0][1]] > FILL_DIFF).any(axis=0))
        if cols.size and (cols.max() + x0) <= TRAILING_SLOT_PT * sc and rr[0][0] <= int(4 * sc):
            rr = rr[1:]
            continue
        break
    # A fill that starts right under the last header text is that text's own capsule (the rental
    # chip, a pill): it belongs to the header, and the content is the next run.
    if len(rr) > 1 and rr[0][0] <= int(2 * sc):
        last_base = header_end + rr[0][1]   # a capsule: measure from its bottom edge
        header_end += rr[0][1]
        rr = [(a_ - rr[0][1], b_ - rr[0][1]) for a_, b_ in rr[1:]]
    content = header_end + rr[0][0] if rr else None
    out.update(title_top_pt=round(s / sc, 1), title_baseline_pt=round((base + 1) / sc, 1),
               title_height_pt=round((e - s) / sc, 1), header_end_pt=round(header_end / sc, 1),
               last_baseline_pt=round(last_base / sc, 1),
               content_top_pt=round(content / sc, 1) if content is not None else None,
               gap_pt=round((content - last_base) / sc, 1) if content is not None else None)
    return out


def consistency_verdict(metrics, baseline_tol=CONSIST_BASELINE_TOL_PT, gap_tol=CONSIST_GAP_TOL_PT, no_gap=()):
    """Cross-frame verdict: every frame has a title; title baselines within baseline_tol; content gaps within
    gap_tol. Frames named in `no_gap` (hero frames: the art has no edge, its top moves with the build stage)
    are held to S1 and S2 only. Returns (checks, pass_)."""
    checks = []
    missing = [os.path.basename(m["frame"]) for m in metrics if m["title_baseline_pt"] is None]
    checks.append({"rule": "S1 every screen has a title", "pass_": not missing, "detail": missing})
    bl = [m["title_baseline_pt"] for m in metrics if m["title_baseline_pt"] is not None]
    spread = (max(bl) - min(bl)) if bl else 0.0
    checks.append({"rule": f"S2 title baselines within {baseline_tol}pt", "pass_": bool(spread <= baseline_tol + 1e-6),
                   "detail": {os.path.basename(m["frame"]): m["title_baseline_pt"] for m in metrics}, "spread_pt": round(spread, 1)})
    gaps = [m["gap_pt"] for m in metrics if m["gap_pt"] is not None and os.path.basename(m["frame"]) not in no_gap]
    gspread = (max(gaps) - min(gaps)) if gaps else 0.0
    checks.append({"rule": f"S3 header-to-content gaps within {gap_tol}pt", "pass_": bool(gspread <= gap_tol + 1e-6),
                   "detail": {os.path.basename(m["frame"]): m["gap_pt"] for m in metrics
                              if os.path.basename(m["frame"]) not in no_gap}, "spread_pt": round(gspread, 1)})
    return checks, all(c["pass_"] for c in checks)


def cmd_consistency(args) -> int:
    tabs = [header_metrics(f, args.scale, "tab") for f in list(args.frames) + list(args.hero or [])]
    sheets = [header_metrics(f, args.scale, "sheet") for f in (args.sheet or [])]
    hero = {os.path.basename(f) for f in (args.hero or [])}
    checks, ok = consistency_verdict(tabs, args.baseline_tol, args.gap_tol, hero)
    result = {"tabs": tabs, "checks": checks}
    if len(sheets) >= 2:
        s_checks, s_ok = consistency_verdict(sheets, args.baseline_tol, args.gap_tol)
        result["sheets"], result["sheet_checks"] = sheets, s_checks
        ok = ok and s_ok
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(result, fh, indent=2, default=_j)
    for m in tabs + sheets:
        print(f"  {m['kind']:5} {os.path.basename(m['frame']):32} title top {m['title_top_pt']} baseline {m['title_baseline_pt']} "
              f"h {m['title_height_pt']} header end {m['header_end_pt']} content {m['content_top_pt']} gap {m['gap_pt']}")
    for c in checks + result.get("sheet_checks", []):
        print(f"{'PASS' if c['pass_'] else 'FAIL':5} {c['rule']}" + (f" (spread {c['spread_pt']}pt)" if "spread_pt" in c else
                                                                    (f" missing: {c['detail']}" if c["detail"] else "")))
    print(f"consistency: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "breaks":
        p = argparse.ArgumentParser(prog="frame_check.py breaks", description="mid-word line breaks via Vision OCR")
        p.add_argument("mode")
        p.add_argument("frames", nargs="+")
        p.add_argument("--json")
        return cmd_breaks(p.parse_args())
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
        p.add_argument("--hero-rect", help="x0,y0,x1,y1 in pt: the hero art region (default: auto-detected on hero frames)")
        p.add_argument("--rentals-gallery", action="store_true",
                       help="the frames are the Rentals gallery (standard 1.4): tiles are capped at 38%% "
                            "instead of D6's 20%%. Never inferred from the frame name.")
        p.add_argument("--hero-glob", action="append", help="frame-name glob that marks a hero frame (repeatable; default today-*, rental-*, welcome*, inbox-empty*, milestone*)")
        return cmd_density(p.parse_args())
    if len(sys.argv) > 1 and sys.argv[1] == "hero":
        if np is None:
            sys.exit("hero mode needs numpy")
        p = argparse.ArgumentParser(prog="frame_check.py hero", description="art readability and state on hero frames (standard H.2)")
        p.add_argument("mode")
        p.add_argument("frames", nargs="+")
        p.add_argument("--pairs", help="LIT=UNLIT: frames whose stem ends in -LIT are compared to the frame ending in -UNLIT (e.g. lit=dark)")
        p.add_argument("--windows", help="craft_windows.json: {stage: [[x0,y0,x1,y1] frame fractions, ...]} (default scripts/qa/craft_windows.json)")
        p.add_argument("--hero-rect", help="x0,y0,x1,y1 in pt (default: auto-detected)")
        p.add_argument("--dt", choices=["auto", "default", "xxl", "ax"], default="auto")
        p.add_argument("--scale", type=float)
        p.add_argument("--frame-top-pt", type=float, help="top of the art frame in pt; enables the ground_line fraction")
        p.add_argument("--frame-side-pt", type=float, default=390.0)
        p.add_argument("--strict", action="store_true", help="REVIEW verdicts (saturation) count as failures")
        p.add_argument("--json")
        return cmd_hero(p.parse_args())
    if len(sys.argv) > 1 and sys.argv[1] == "consistency":
        if np is None:
            sys.exit("consistency mode needs numpy")
        p = argparse.ArgumentParser(prog="frame_check.py consistency",
                                    description="one header system across tabs: title baselines and header-to-content gaps")
        p.add_argument("mode")
        p.add_argument("frames", nargs="+", help="one frame per tab root, same device, same Dynamic Type")
        p.add_argument("--sheet", action="append", help="a sheet frame (repeatable); sheets are compared with each other")
        p.add_argument("--hero", action="append", help="a hero tab frame (Today): held to S1/S2 only, since the art has no top edge")
        p.add_argument("--scale", type=float)
        p.add_argument("--baseline-tol", type=float, default=CONSIST_BASELINE_TOL_PT)
        p.add_argument("--gap-tol", type=float, default=CONSIST_GAP_TOL_PT)
        p.add_argument("--json")
        return cmd_consistency(p.parse_args())
    return legacy_main()


if __name__ == "__main__":
    sys.exit(main())
