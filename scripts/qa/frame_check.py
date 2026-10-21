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
Exit 0 clean, 1 flagged. Python 3 stdlib + Pillow. Heuristics: confirm every flag by eye.
Tokens come from docs/design/2.0-brand-system.md.
"""
import argparse, colorsys, hashlib, json, math, sys
from collections import deque
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter

SCALE = 3.0  # 3x captures
STATUS_PT = 54
TOKENS = {  # docs/design/2.0-brand-system.md
    "canvas": {"light": "#EEF2FA", "dark": "#0B1230"},
    "card": {"light": "#FFFFFF", "dark": "#141C3F"},
    "cardTertiary": {"light": "#F6F8FD", "dark": "#1B2550"},
    "action": {"light": "#1E3FA6", "dark": "#8FD3FF"},
    "actionSurface": {"light": "#E3E9FA", "dark": "#182A5C"},
    "brand": {"light": "#1E3FA6", "dark": "#1E3FA6"},  # theme-fixed blueprint hero
}
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


def sample_tokens(im):
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
    small = im.resize((W // 3, H // 3))
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
        out[name] = {"sampled": rgb2hex(rgb), "nearest": f"{best[1]}/{best[2]} {best[3]}", "deltaE": round(best[0], 1),
                     "flag": best[0] > DELTA_E_FLAG[name]}
    return out


def text_regions(im, min_ratio):
    """Find line boxes by edge density, measure glyph-vs-background contrast in each."""
    W, H = im.size
    g = im.convert("L").resize((W // 3, H // 3), Image.LANCZOS)
    e = g.filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 28 else 0)
    e = e.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MaxFilter(3))
    w, h = e.size
    data = e.load()
    seen = bytearray(w * h)
    boxes = []
    top = STATUS_PT  # status bar handled separately
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
        box = (max(0, (x1 + 3) * 3), max(0, (y1 + 3) * 3), min(W, (x2 - 2) * 3), min(H, (y2 - 2) * 3))
        if box[2] - box[0] < 24 or box[3] - box[1] < 15: continue
        px = region_pixels(im, box)
        r = ink_vs_bg(px)
        if not r: continue
        ink, bg, cr = r
        height_pt = (box[3] - box[1]) / SCALE
        big = height_pt >= 22
        need = 3.0 if big else min_ratio
        out.append({"box_pt": [round(box[0] / SCALE), round(box[1] / SCALE), round(box[2] / SCALE), round(box[3] / SCALE)],
                    "ink": rgb2hex(ink), "bg": rgb2hex(bg), "ratio": round(cr, 2), "need": need, "flag": cr < need,
                    "big": big, "_box": box})
    return out


# ----------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir"); ap.add_argument("--out", default=".")
    ap.add_argument("--recursive", action="store_true")
    ap.add_argument("--crops", action="store_true", help="save a crop of every flagged text region")
    ap.add_argument("--min-ratio", type=float, default=4.5)
    ap.add_argument("--violet-max", type=float, default=0.05, help="flag when violet pixels exceed this percent")
    a = ap.parse_args()
    root = Path(a.dir)
    files = sorted(root.rglob("*.png") if a.recursive else root.glob("*.png"))
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    frames, skipped, hashes = [], [], {}
    for f in files:
        hashes.setdefault(hashlib.sha256(f.read_bytes()).hexdigest(), []).append(f.name)
    dups = [v for v in hashes.values() if len(v) > 1]
    for f in files:
        try:
            im = Image.open(f).convert("RGB")
        except Exception as e:
            skipped.append((f.name, f"unreadable: {e}")); continue
        if im.width < 1000 or not (0.40 <= im.width / im.height <= 0.80):
            skipped.append((f.name, f"not a 3x phone/tablet frame ({im.width}x{im.height})")); continue
        rec = {"file": f.name, "size": [im.width, im.height], "flags": []}
        v = violet_pct(im); rec["violet_pct"] = round(v, 3)
        if v > a.violet_max: rec["flags"].append(f"violet {v:.2f}% of pixels")
        rec["status_bar"] = status_bar(im)
        for s in rec["status_bar"]:
            need = 4.5
            if s["ratio"] < need: rec["flags"].append(f"status bar {s['part']} {s['ratio']}:1 ({s['ink']} on {s['bg']})")
        rec["tokens"] = sample_tokens(im)
        for k, t in rec["tokens"].items():
            if t["flag"]: rec["flags"].append(f"token {k} {t['sampled']} is dE {t['deltaE']} from {t['nearest']}")
        tr = text_regions(im, a.min_ratio)
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
    rep = {"dir": str(root), "frames": len(frames), "duplicates": dups, "skipped": skipped, "results": frames}
    (out / "frame_check.json").write_text(json.dumps(rep, indent=1))
    L = [f"# frame_check: {root}", "",
         f"{len(frames)} frames, {sum(1 for r in frames if r['flags'])} flagged, {len(dups)} duplicate group(s), "
         f"{len(skipped)} skipped. Heuristics: confirm each flag by eye. Only flagged items are listed.", ""]
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


if __name__ == "__main__":
    sys.exit(main())
