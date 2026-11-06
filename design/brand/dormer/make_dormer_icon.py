#!/usr/bin/env python3
"""Dormer brand mark (V3, approved 2026-10-27) and every icon artefact built from it.

One geometry, many outputs. Run from the repo root:

    python3 design/brand/dormer/make_dormer_icon.py            # write everything
    python3 design/brand/dormer/make_dormer_icon.py --measure  # print geometry numbers only

Writes:
    design/brand/dormer/dormer-mark.svg          the polished mark, white, 1024 grid
    design/brand/dormer/dormer-mark-mono.svg     the mark in currentColor (for docs/web)
    AppIcon.icon/                                Icon Composer document (iOS 26+, Liquid Glass)
    Assets.xcassets/AppIcon.appiconset/*.png     embossed 1024s: default, dark, tinted. NOTE: while
                                                 AppIcon.icon is in the target, actool ignores this set
                                                 and flattens the .icon for iOS 18-25 itself (verified
                                                 2026-10-27). The set ships only without the .icon.
    Assets.xcassets/onb-appicon.imageset/        the icon picture used in the onboarding preview
    Assets.xcassets/LaunchMark.imageset/*.pdf    launch-screen mark, textPrimary per appearance
    design/brand/dormer/DormerMarkGeometry.txt   the Swift constants (mirrored in Sources/Shared/DormerMark.swift)

V3 source: ~/AgentScratch/landlordhours/2026-10-27/dormer-e-refine/variants.py (_v3).
An outlined capital D whose counter is a house-shaped room under a shallow gable.

Optical polish over the approved V3 (all in the 1024 grid):
  * stroke contrast: stem 160 -> 164, top/bottom 112 -> 108, gable walls 112 -> 118.
    Diagonals read thinner than horizontals at the same width, so they get the extra ink;
    the stem stays the heaviest stroke, like a letter.
  * corners: stem 40 -> 44, shoulders 30 -> 34, point 18 -> 22; the counter 10 -> 14 and its
    gable 6 -> 10. Liquid Glass lights rounded geometry; the point stays the sharpest corner.
  * overshoot: the nominal apex moves 874 -> 880 so the rounded tip still reaches past the
    stem's optical edge (the tip's extreme x is printed by --measure).
  * size: scaled 1.04 about the canvas centre so the mark fills the safe area. Placement is the
    approved one (bbox centre ~18px right of the canvas centre, because the point carries little
    weight); --measure prints the centroid rule's answer for reference.
"""
import argparse
import json
import math
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
GRID = 1024

# ---------------------------------------------------------------- geometry

APEX = (880.0, 472.0)
OUTER = [(186.0, 196.0), (650.0, 196.0), APEX, (650.0, 828.0), (186.0, 828.0)]
# walls, edge by edge: top, upper gable, lower gable, bottom, stem
WALLS = [108.0, 118.0, 118.0, 108.0, 164.0]
R_OUTER = [44.0, 34.0, 22.0, 34.0, 44.0]   # stem-top, shoulder, point, shoulder, stem-bottom
R_INNER = [14.0, 14.0, 10.0, 14.0, 14.0]
SCALE = 1.04


def inset(poly, ds):
    """Inward offset of a clockwise (screen coords) convex polygon, per-edge distances."""
    n = len(poly)
    lines = []
    for i in range(n):
        (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % n]
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy)
        nx, ny = -dy / L, dx / L
        d = ds[i]
        lines.append(((x1 + nx * d, y1 + ny * d), (x2 + nx * d, y2 + ny * d)))
    out = []
    for i in range(n):
        (p1, p2), (p3, p4) = lines[i - 1], lines[i]
        x1, y1 = p1; x2, y2 = p2; x3, y3 = p3; x4, y4 = p4
        den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
        out.append((x1 + t * (x2 - x1), y1 + t * (y2 - y1)))
    return out


def corners(poly, radii):
    """Each vertex becomes (a, control, b): a quadratic from a to b with the vertex as control."""
    n = len(poly)
    segs = []
    for i in range(n):
        p0, p1, p2 = poly[i - 1], poly[i], poly[(i + 1) % n]
        v0 = (p0[0] - p1[0], p0[1] - p1[1]); l0 = math.hypot(*v0)
        v2 = (p2[0] - p1[0], p2[1] - p1[1]); l2 = math.hypot(*v2)
        r = min(radii[i], l0 / 2, l2 / 2)
        a = (p1[0] + v0[0] / l0 * r, p1[1] + v0[1] / l0 * r)
        b = (p1[0] + v2[0] / l2 * r, p1[1] + v2[1] / l2 * r)
        segs.append((a, p1, b))
    return segs


def transform(poly, scale, dx):
    c = GRID / 2
    return [((x - c) * scale + c + dx, (y - c) * scale + c) for x, y in poly]


def flatten(segs, steps=32):
    pts = []
    for a, c, b in segs:
        for k in range(steps + 1):
            t = k / steps
            x = (1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t ** 2 * b[0]
            y = (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t ** 2 * b[1]
            pts.append((x, y))
    return pts


def build(dx=0.0):
    outer = transform(OUTER, SCALE, dx)
    walls = [w * SCALE for w in WALLS]
    inner = inset(outer, walls)
    return corners(outer, R_OUTER_S()), corners(inner, [r * SCALE for r in R_INNER]), outer, inner


def R_OUTER_S():
    return [r * SCALE for r in R_OUTER]


def mask(px, dx=None, ss=4):
    o, i, _, _ = build(DX if dx is None else dx)
    big = px * ss
    s = big / GRID
    im = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(im)
    d.polygon([(x * s, y * s) for x, y in flatten(o)], fill=255)
    d.polygon([(x * s, y * s) for x, y in flatten(i)], fill=0)
    return im.resize((px, px), Image.LANCZOS)


def solve_dx():
    """Horizontal shift so (bbox centre + ink centroid) / 2 lands on the canvas centre."""
    m = np.asarray(mask(1024, 0.0, ss=2), dtype=np.float64) / 255
    ys, xs = np.nonzero(m > 0.5)
    cx = (m.sum(axis=0) * np.arange(1024)).sum() / m.sum()
    bbox_c = (xs.min() + xs.max() + 1) / 2
    return GRID / 2 - (bbox_c + cx) / 2, dict(bbox=(int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())),
                                               centroid_x=round(cx, 1), bbox_cx=bbox_c)


# The centroid rule (solve_dx) asks for +16px, which pushes the tip into the right-hand bleed:
# the D's stem holds the weight and the point holds almost none. The approved V3 sat with its bbox
# centre ~15px right of the canvas centre; scaling about the centre keeps that (bbox centre ~530).
_, _M0 = solve_dx()
DX = 0.0


def path_d(dx=DX):
    o, i, _, _ = build(dx)
    out = []
    for segs in (o, i):
        for k, (a, c, b) in enumerate(segs):
            out.append(("M" if k == 0 else "L") + f"{a[0]:.1f} {a[1]:.1f}")
            out.append(f"Q{c[0]:.1f} {c[1]:.1f} {b[0]:.1f} {b[1]:.1f}")
        out.append("Z")
    return " ".join(out)


def svg(body, bg=None):
    rect = f'<rect width="{GRID}" height="{GRID}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {GRID} {GRID}" '
            f'width="{GRID}" height="{GRID}">{rect}{body}</svg>\n')


def mark_svg(color="#FFFFFF", bottom=None):
    """The mark. With `bottom`, a top-to-bottom gradient colour -> bottom (the raised finish)."""
    if bottom is None:
        return svg(f'<path d="{path_d()}" fill="{color}" fill-rule="evenodd"/>')
    defs = (f'<defs><linearGradient id="raised" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{color}"/><stop offset="1" stop-color="{bottom}"/>'
            f'</linearGradient></defs>')
    return svg(f'{defs}<path d="{path_d()}" fill="url(#raised)" fill-rule="evenodd"/>')


RAISED_WHITE_BOTTOM = "#E3E7F0"   # white -> very light grey, same family
RAISED_CYAN_BOTTOM = "#7FC3EE"
SHADOW_OPACITY = 0.8


# ---------------------------------------------------------------- colour

def hx(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


LIGHT_STOPS = [(0.0, "#2A4FC0"), (0.55, "#1E3FA6"), (1.0, "#152E80")]   # approved embossed-1 ground
DARK_STOPS = [(0.0, "#13205A"), (0.55, "#0B1230"), (1.0, "#070B1F")]    # blueprint paper, deepened
CYAN = "#8FD3FF"                                                          # dark action / drafting
MARK_WHITE = "#FFFFFF"


def gradient(px, stops):
    yy, xx = np.mgrid[0:px, 0:px].astype(np.float64)
    t = (xx + yy) / (2 * (px - 1))
    out = np.zeros((px, px, 3))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        sel = (t >= t0) & (t <= t1)
        u = ((t - t0) / (t1 - t0))[sel][:, None]
        out[sel] = hx(c0) * (1 - u) + hx(c1) * u
    return out


def blur(a, r):
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), "L")
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), dtype=np.float64) / 255


def shift(a, dx, dy):
    out = np.zeros_like(a)
    h, w = a.shape
    ys = slice(max(dy, 0), h + min(dy, 0)); ysrc = slice(max(-dy, 0), h + min(-dy, 0))
    xs = slice(max(dx, 0), w + min(dx, 0)); xsrc = slice(max(-dx, 0), w + min(-dx, 0))
    out[ys, xs] = a[ysrc, xsrc]
    return out


def embossed(px, stops, mark_hex, shadow_hex, emboss=1.0, bottom_hex=None):
    """The approved 'soft emboss' look (gen/embossed-1.png), rendered from the vector.

    Only for the iOS 18-25 fallback, where the system adds no glass. One soft key light from the
    upper left: a low contact shadow under the slab, a faint lit rim on the top-left edges and a
    faint shade on the bottom-right ones. Kept shallow so it reads as a few millimetres of relief.
    """
    k = px / 1024
    bottom_hex = bottom_hex or mark_hex
    m = np.asarray(mask(px), dtype=np.float64) / 255
    base = gradient(px, stops)
    # contact shadow: soft, short, straight down
    sh = shift(blur(m, 14 * k), 0, int(round(9 * k))) * 0.55 * emboss
    sh = sh * (1 - m)
    base = base * (1 - sh[..., None]) + hx(shadow_hex) * sh[..., None]
    # relief: gradient of a blurred mask, lit from the upper left
    b = blur(m, 5 * k)
    gy, gx = np.gradient(b)
    light = (-gx * -1 + -gy * -1) / math.sqrt(2)          # dot(normal, toward-light)
    light = light / (np.abs(light).max() + 1e-9)
    top, bot = hx(mark_hex), hx(bottom_hex)
    t = (np.arange(px) / (px - 1))[:, None, None]
    mark = (top * (1 - t) + bot * t) * np.ones((px, px, 3))
    shade = np.clip(-light, 0, 1)[..., None]
    mark = mark * (1 - 0.13 * emboss * shade)
    # a whisper of body shading so the slab is not a flat sticker: 2% darker toward bottom right
    yy, xx = np.mgrid[0:px, 0:px] / px
    mark = mark * (1 - 0.035 * emboss * ((xx + yy) / 2))[..., None]
    out = base * (1 - m[..., None]) + mark * m[..., None]
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGB")


def flat(px, stops, mark_hex):
    m = np.asarray(mask(px), dtype=np.float64)[..., None] / 255
    base = gradient(px, stops)
    out = base * (1 - m) + hx(mark_hex) * m
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGB")


def tinted(px):
    """iOS 18 tinted: greyscale, opaque. The system maps luminance to the user's tint."""
    m = np.asarray(mask(px), dtype=np.float64) / 255
    ground = np.full((px, px), 0.0)
    out = ground * (1 - m) + 255 * m
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "L").convert("RGB")


# ---------------------------------------------------------------- Icon Composer document

def write_icon_doc(dest):
    """AppIcon.icon: a full-bleed ground layer and one glass mark layer, per appearance.

    Margin's ictool lessons (session-learnings/margin.md): the Dark rendition ignores the
    document `fill`, so the ground is a full-bleed layer with its own dark specialization;
    translucency washes a saturated layer, so it is off; specular stays on the mark, which is
    where the glass is.
    """
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(os.path.join(dest, "Assets"))
    A = os.path.join(dest, "Assets")
    gsvg = lambda stops, name: (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {GRID} {GRID}" width="{GRID}" height="{GRID}">'
        f'<defs><linearGradient id="{name}" x1="0" y1="0" x2="1" y2="1">'
        + "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
        + f'</linearGradient></defs><rect width="{GRID}" height="{GRID}" fill="url(#{name})"/></svg>\n')
    # Icon Composer reads SVG layers, but its SVG importer does not promise gradient support, so the
    # grounds ship as PNG renders of the same gradient; the mark is pure vector.
    gradient_img = lambda stops: Image.fromarray(np.clip(gradient(GRID, stops) + 0.5, 0, 255).astype(np.uint8), "RGB")
    gradient_img(LIGHT_STOPS).save(os.path.join(A, "ground-light.png"))
    gradient_img(DARK_STOPS).save(os.path.join(A, "ground-dark.png"))
    Image.new("RGB", (GRID, GRID), (0, 0, 0)).save(os.path.join(A, "ground-tinted.png"))
    with open(os.path.join(A, "mark.svg"), "w") as f:
        f.write(mark_svg(MARK_WHITE, RAISED_WHITE_BOTTOM))
    with open(os.path.join(A, "mark-dark.svg"), "w") as f:
        f.write(mark_svg(CYAN, RAISED_CYAN_BOTTOM))
    _ = gsvg  # kept for reference; see note above

    def layer(name, light, dark, tinted_name, glass):
        return {
            "name": name,
            "image-name-specializations": [
                {"value": light},
                {"appearance": "dark", "value": dark},
                {"appearance": "tinted", "value": tinted_name},
            ],
            "glass": glass,
            "hidden": False,
            "opacity": 1,
            "position": {"scale": 1, "translation-in-points": [0, 0]},
        }

    doc = {
        "fill": {"solid": "extended-srgb:0.11765,0.24706,0.65098,1.00000"},
        "groups": [
            {
                "name": "Mark",
                "layers": [layer("mark", "mark.svg", "mark-dark.svg", "mark.svg", True)],
                "specular": True,
                "shadow": {"kind": "neutral", "opacity": SHADOW_OPACITY},
                "translucency": {"enabled": False, "value": 0.0},
            },
            {
                "name": "Ground",
                "layers": [layer("ground", "ground-light.png", "ground-dark.png", "ground-tinted.png", False)],
                "specular": False,
                "shadow": {"kind": "none", "opacity": 0.0},
                "translucency": {"enabled": False, "value": 0.0},
            },
        ],
        "supported-platforms": {"squares": ["iOS"]},
    }
    with open(os.path.join(dest, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")


# ---------------------------------------------------------------- launch mark PDF

def pdf_mark(dest, rgb, side_pt=112.0):
    """A one-path vector PDF of the mark, fill-evenodd, on a side_pt square page."""
    o, i, _, _ = build(DX)
    s = side_pt / GRID
    ops = []

    def P(p):
        return p[0] * s, side_pt - p[1] * s  # PDF y is up

    for segs in (o, i):
        for k, (a, c, b) in enumerate(segs):
            ax, ay = P(a)
            ops.append(f"{ax:.3f} {ay:.3f} {'m' if k == 0 else 'l'}")
            # quadratic -> cubic
            c1 = (a[0] + 2 / 3 * (c[0] - a[0]), a[1] + 2 / 3 * (c[1] - a[1]))
            c2 = (b[0] + 2 / 3 * (c[0] - b[0]), b[1] + 2 / 3 * (c[1] - b[1]))
            (x1, y1), (x2, y2), (x3, y3) = P(c1), P(c2), P(b)
            ops.append(f"{x1:.3f} {y1:.3f} {x2:.3f} {y2:.3f} {x3:.3f} {y3:.3f} c")
        ops.append("h")
    r, g, b_ = (v / 255 for v in hx(rgb))
    content = f"{r:.4f} {g:.4f} {b_:.4f} rg\n" + "\n".join(ops) + "\nf*\n"
    objs = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {side_pt:g} {side_pt:g}] /Contents 4 0 R /Resources << >> >>",
        f"<< /Length {len(content.encode())} >>\nstream\n{content}endstream",
    ]
    out = b"%PDF-1.4\n"
    offs = []
    for n, body in enumerate(objs, 1):
        offs.append(len(out))
        out += f"{n} 0 obj\n{body}\nendobj\n".encode()
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    for o_ in offs:
        out += f"{o_:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    with open(dest, "wb") as f:
        f.write(out)


# ---------------------------------------------------------------- Swift constants

def swift_constants():
    _, _, outer, inner = build(DX)
    fmt = lambda pts: ", ".join(f"({x:.2f}, {y:.2f})" for x, y in pts)
    return (f"outer = [{fmt(outer)}]\nouterRadii = {[round(r * SCALE, 2) for r in R_OUTER]}\n"
            f"inner = [{fmt(inner)}]\ninnerRadii = {[round(r * SCALE, 2) for r in R_INNER]}\n")


def measure():
    m = np.asarray(mask(1024), dtype=np.float64) / 255
    ys, xs = np.nonzero(m > 0.5)
    cx = (m.sum(axis=0) * np.arange(1024)).sum() / m.sum()
    cy = (m.sum(axis=1) * np.arange(1024)).sum() / m.sum()
    o, _, _, _ = build(DX)
    a, c, b = o[2]
    tip_x = 0.25 * a[0] + 0.5 * c[0] + 0.25 * b[0]
    # farthest ink from the canvas centre, as a fraction of the half-width (safe circle = 0.88)
    yy, xx = np.nonzero(m > 0.5)
    rmax = np.sqrt((xx + 0.5 - 512) ** 2 + (yy + 0.5 - 512) ** 2).max() / 512
    return dict(dx=DX, before_shift=_M0, bbox=(int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())),
                bbox_w_pct=round((xs.max() - xs.min() + 1) / 10.24, 1),
                bbox_h_pct=round((ys.max() - ys.min() + 1) / 10.24, 1),
                ink_pct=round(m.mean() * 100, 1), centroid=(round(cx, 1), round(cy, 1)),
                tip_x=round(tip_x, 1), stem_left=round(build(DX)[2][0][0], 1),
                max_radius_frac=round(float(rmax), 3))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--measure", action="store_true")
    args = ap.parse_args()
    print(json.dumps(measure(), indent=1))
    if args.measure:
        return
    with open(os.path.join(HERE, "dormer-mark.svg"), "w") as f:
        f.write(mark_svg(MARK_WHITE))
    with open(os.path.join(HERE, "dormer-mark-mono.svg"), "w") as f:
        f.write(svg(f'<path d="{path_d()}" fill="currentColor" fill-rule="evenodd"/>'))
    with open(os.path.join(HERE, "DormerMarkGeometry.txt"), "w") as f:
        f.write(swift_constants())

    write_icon_doc(os.path.join(ROOT, "AppIcon.icon"))

    ai = os.path.join(ROOT, "Assets.xcassets", "AppIcon.appiconset")
    embossed(1024, LIGHT_STOPS, "#FFFFFF", "#0A1A55", bottom_hex=RAISED_WHITE_BOTTOM).save(os.path.join(ai, "AppIcon.png"))
    embossed(1024, DARK_STOPS, CYAN, "#000000", emboss=0.8, bottom_hex=RAISED_CYAN_BOTTOM).save(os.path.join(ai, "AppIcon-Dark.png"))
    tinted(1024).save(os.path.join(ai, "AppIcon-Tinted.png"))
    embossed(1024, LIGHT_STOPS, "#FFFFFF", "#0A1A55", bottom_hex=RAISED_WHITE_BOTTOM).save(
        os.path.join(ROOT, "Assets.xcassets", "onb-appicon.imageset", "onb-appicon.png"))

    lm = os.path.join(ROOT, "Assets.xcassets", "LaunchMark.imageset")
    pdf_mark(os.path.join(lm, "LaunchMark.pdf"), "#121B33")
    pdf_mark(os.path.join(lm, "LaunchMark-dark.pdf"), "#F2F4FA")
    print(swift_constants())


if __name__ == "__main__":
    sys.exit(main())
