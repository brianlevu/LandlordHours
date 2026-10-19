#!/usr/bin/env python3
"""Geometry + hygiene gate for app icon artwork.

Fails closed: any check that cannot be evaluated is reported as a FAIL, never a pass.

    verify_icon.py art.png --platform ios
    verify_icon.py art.png --platform macos-legacy
    verify_icon.py art.png --platform macos-tahoe

Exit 0 = all checks pass. Exit 1 = at least one FAIL. Exit 2 = could not run.
"""

import argparse
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:  # fail closed
    print(f"FAIL  cannot run checks: {exc}", file=sys.stderr)
    sys.exit(2)

# --- Apple geometry constants -------------------------------------------------
CANVAS = 1024
MACOS_BODY = 824  # legacy macOS icon body, centered on the 1024 canvas
MACOS_RADIUS = 185.4
MACOS_MARGIN = (CANVAS - MACOS_BODY) / 2  # 100.0
SQUIRCLE_N = 5.0  # superellipse exponent modelling Apple's continuous corner curve
SAFE_FRACTION = 0.88  # meaningful content should sit inside this centered fraction
SALIENT_THRESHOLD = 60  # RGB-sum distance separating subject from backdrop


class Report:
    def __init__(self):
        self.rows = []

    def add(self, ok, name, detail=""):
        self.rows.append((ok, name, detail))

    def failed(self):
        return any(not ok for ok, _, _ in self.rows)

    def render(self):
        width = max(len(n) for _, n, _ in self.rows)
        for ok, name, detail in self.rows:
            tag = "PASS" if ok else "FAIL"
            line = f"{tag}  {name.ljust(width)}"
            if detail:
                line += f"  {detail}"
            print(line)


def squircle_mask(size, n=SQUIRCLE_N):
    """Boolean mask of Apple's continuous-curvature icon shape at `size`."""
    axis = (np.arange(size) + 0.5) / size * 2.0 - 1.0  # -1..1, pixel centers
    x = np.abs(axis)[None, :]
    y = np.abs(axis)[:, None]
    return (x**n + y**n) <= 1.0


def load(path):
    img = Image.open(path)
    img.load()
    return img


def alpha_of(img):
    if "A" in img.getbands():
        return np.asarray(img.convert("RGBA"))[:, :, 3]
    return None


def content_mask(rgba, alpha, threshold=30):
    """Pixels that carry artwork rather than flat background.

    With alpha: opaque pixels. Without: pixels differing from the dominant
    corner-sampled background colour by more than `threshold` (summed over RGB).

    A low threshold catches any deviation and is right for detecting a drawn
    shell. A high threshold isolates the salient subject and is right for
    clipping/safe-area work, where a flat or gently graded backdrop is *meant*
    to run off the edge and be masked.
    """
    if alpha is not None:
        return alpha > 8

    rgb = rgba[:, :, :3].astype(np.int16)
    h, w = rgb.shape[:2]
    k = max(2, min(h, w) // 128)
    # Median over the whole border ring, not just the four corner patches: a
    # subject that reaches into the corners would otherwise be mistaken for the
    # backdrop, inverting every downstream check.
    ring = np.concatenate(
        [
            rgb[:k, :].reshape(-1, 3),
            rgb[-k:, :].reshape(-1, 3),
            rgb[:, :k].reshape(-1, 3),
            rgb[:, -k:].reshape(-1, 3),
        ]
    )
    bg = np.median(ring, axis=0)
    dist = np.abs(rgb - bg).sum(axis=2)
    return dist > threshold


def check_dimensions(rep, img, platform):
    w, h = img.size
    if w != h:
        rep.add(False, "square canvas", f"{w}x{h} is not square")
        return False
    if w < CANVAS:
        rep.add(False, "canvas size", f"{w}x{h}; need at least {CANVAS}x{CANVAS}")
        return False
    note = f"{w}x{h}"
    if w != CANVAS:
        note += f" (will be scaled to {CANVAS} for export)"
    rep.add(True, "canvas size", note)
    return True


def check_alpha(rep, img, alpha, platform):
    if platform == "ios" or platform == "macos-tahoe":
        if alpha is None:
            rep.add(True, "no alpha channel", "fully opaque, correct for full-bleed")
            return
        transparent = int((alpha < 250).sum())
        if transparent:
            pct = 100.0 * transparent / alpha.size
            rep.add(
                False,
                "no alpha channel",
                f"{pct:.2f}% of pixels are non-opaque; full-bleed artwork must be flattened",
            )
        else:
            rep.add(True, "no alpha channel", "alpha present but fully opaque; flatten before ship")
    else:  # macos-legacy
        if alpha is None:
            rep.add(
                False,
                "alpha channel present",
                "macOS legacy needs transparent margin around the 824 body",
            )
            return
        if (alpha < 250).sum() == 0:
            rep.add(False, "alpha channel present", "image is fully opaque; no inset margin")
        else:
            rep.add(True, "alpha channel present", "")


def check_full_bleed_corners(rep, rgba, alpha, size):
    """Corners must be filled background, not transparent and not a drawn shell."""
    if alpha is not None and (alpha < 250).any():
        k = max(2, size // 64)
        patches = [alpha[:k, :k], alpha[:k, -k:], alpha[-k:, :k], alpha[-k:, -k:]]
        clear = [p.mean() < 200 for p in patches]
        if any(clear):
            rep.add(
                False,
                "corners filled",
                f"{sum(clear)}/4 corners transparent; iOS artwork must bleed to the edge",
            )
            return
    rep.add(True, "corners filled", "")


def check_no_baked_shell(rep, rgba, alpha, size):
    """Detect an icon-shaped card drawn into the artwork (double-rounding defect).

    The signature of a baked shell is a large, rectangle-filling block of
    non-backdrop pixels that stops short of the canvas on every side. A
    legitimate subject-on-background icon differs on all three counts: the
    subject is smaller, it rarely fills its own bounding box, and the
    background it sits on runs to the edge.
    """
    content = content_mask(rgba, alpha, threshold=30)
    total = int(content.sum())
    if total == 0:
        rep.add(False, "no baked rounded shell", "no artwork detected against background")
        return

    cols = np.where(content.any(axis=0))[0]
    rows = np.where(content.any(axis=1))[0]
    x0, x1 = int(cols[0]), int(cols[-1])
    y0, y1 = int(rows[0]), int(rows[-1])
    bw, bh = x1 - x0 + 1, y1 - y0 + 1

    bbox_frac = (bw * bh) / float(size * size)
    fill_ratio = total / float(bw * bh)
    inset_frac = min(x0, y0, size - 1 - x1, size - 1 - y1) / float(size)

    shell = bbox_frac > 0.55 and fill_ratio > 0.88 and inset_frac > 0.015
    detail = (
        f"bbox {bw}x{bh} ({bbox_frac*100:.0f}% of canvas), "
        f"fill {fill_ratio*100:.0f}%, inset {inset_frac*100:.1f}%"
    )
    if shell:
        rep.add(
            False,
            "no baked rounded shell",
            detail + " — artwork contains its own icon-shaped card; "
            "remove the frame and bleed the background to the edge",
        )
    else:
        rep.add(True, "no baked rounded shell", detail)


def check_squircle_clipping(rep, rgba, alpha, size):
    """Salient content falling outside the system squircle will be cut off.

    Measured against the salient mask: a flat or graded backdrop is supposed to
    bleed past the mask, so counting it here would flag every correct icon.
    """
    content = content_mask(rgba, alpha, threshold=SALIENT_THRESHOLD)
    mask = squircle_mask(size)
    outside = content & ~mask
    total = int(content.sum())
    if total == 0:
        rep.add(False, "content survives mask", "no artwork detected against background")
        return

    lost = int(outside.sum())
    pct = 100.0 * lost / total
    if pct > 0.5:
        half = size // 2
        quads = {
            "top-left": outside[:half, :half].sum(),
            "top-right": outside[:half, half:].sum(),
            "bottom-left": outside[half:, :half].sum(),
            "bottom-right": outside[half:, half:].sum(),
        }
        worst = max(quads, key=quads.get)
        rep.add(
            False,
            "content survives mask",
            f"{pct:.1f}% of artwork sits outside the squircle; worst corner {worst}",
        )
    else:
        rep.add(True, "content survives mask", f"{pct:.2f}% clipped")


def check_safe_area(rep, rgba, alpha, size):
    content = content_mask(rgba, alpha, threshold=SALIENT_THRESHOLD)
    total = int(content.sum())
    if total == 0:
        rep.add(False, "safe area", "no artwork detected")
        return
    yy, xx = np.mgrid[0:size, 0:size]
    c = (size - 1) / 2.0
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2)
    outside = content & (r > SAFE_FRACTION * size / 2.0)
    pct = 100.0 * int(outside.sum()) / total
    if pct > 8.0:
        rep.add(
            False,
            "safe area",
            f"{pct:.1f}% of artwork outside the {int(SAFE_FRACTION*100)}% safe circle",
        )
    else:
        rep.add(True, "safe area", f"{pct:.1f}% near edge")


def check_macos_geometry(rep, alpha, size):
    if alpha is None:
        rep.add(False, "824 grid", "no alpha channel; cannot measure body")
        return
    solid = alpha > 8
    cols = np.where(solid.any(axis=0))[0]
    rows = np.where(solid.any(axis=1))[0]
    if cols.size == 0 or rows.size == 0:
        rep.add(False, "824 grid", "image is empty")
        return

    scale = size / CANVAS
    x0, x1 = int(cols[0]), int(cols[-1])
    y0, y1 = int(rows[0]), int(rows[-1])
    bw = (x1 - x0 + 1) / scale
    bh = (y1 - y0 + 1) / scale

    # Protruding elements are idiomatic; allow overshoot but never edge contact.
    if x0 <= 1 or y0 <= 1 or x1 >= size - 2 or y1 >= size - 2:
        rep.add(False, "clear of canvas edge", "artwork touches the 1024 edge; shadow has no room")
    else:
        rep.add(True, "clear of canvas edge", f"margins l{x0/scale:.0f} t{y0/scale:.0f}")

    tol = 24
    ok = abs(bw - MACOS_BODY) <= tol and abs(bh - MACOS_BODY) <= tol
    detail = f"body {bw:.0f}x{bh:.0f}, expected {MACOS_BODY}x{MACOS_BODY} +/-{tol}"
    if not ok and (bw > MACOS_BODY or bh > MACOS_BODY):
        detail += " (larger is acceptable only for deliberately protruding elements)"
    rep.add(ok, "824 grid", detail)

    cx = (x0 + x1 + 1) / 2.0 / scale
    cy = (y0 + y1 + 1) / 2.0 / scale
    off = max(abs(cx - CANVAS / 2), abs(cy - CANVAS / 2))
    rep.add(off <= 12, "centered", f"center offset {off:.1f}px")


def check_small_size_legibility(rep, rgba, alpha, size):
    """A silhouette that dissolves at 32px will not survive the Dock."""
    content = content_mask(rgba, alpha, threshold=SALIENT_THRESHOLD)
    img = Image.fromarray((content * 255).astype(np.uint8))
    small = np.asarray(img.resize((32, 32), Image.LANCZOS)).astype(np.float32) / 255.0
    coverage = float(small.mean())
    # Fraction of pixels that are neither clearly on nor clearly off.
    mush = float(((small > 0.25) & (small < 0.75)).mean())
    if coverage < 0.06:
        rep.add(False, "32px legibility", f"only {coverage*100:.1f}% coverage; subject too small")
    elif mush > 0.55:
        rep.add(False, "32px legibility", f"{mush*100:.0f}% of the 32px render is mush")
    else:
        rep.add(True, "32px legibility", f"coverage {coverage*100:.0f}%, soft {mush*100:.0f}%")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image")
    ap.add_argument(
        "--platform",
        required=True,
        choices=["ios", "macos-legacy", "macos-tahoe"],
        help="ios and macos-tahoe are full-bleed; macos-legacy uses the 824 inset grid",
    )
    args = ap.parse_args()

    try:
        img = load(args.image)
    except Exception as exc:
        print(f"FAIL  could not open {args.image}: {exc}", file=sys.stderr)
        sys.exit(2)

    rep = Report()
    print(f"\n{args.image}  [{args.platform}]\n")

    if not check_dimensions(rep, img, args.platform):
        rep.render()
        print("\nRESULT: FAIL — fix the above before shipping.\n")
        sys.exit(1)

    size = img.size[0]
    alpha = alpha_of(img)
    rgba = np.asarray(img.convert("RGBA"))

    check_alpha(rep, img, alpha, args.platform)

    if args.platform in ("ios", "macos-tahoe"):
        check_full_bleed_corners(rep, rgba, alpha, size)
        check_no_baked_shell(rep, rgba, alpha, size)
        check_squircle_clipping(rep, rgba, alpha, size)
        check_safe_area(rep, rgba, alpha, size)
    else:
        check_macos_geometry(rep, alpha, size)

    check_small_size_legibility(rep, rgba, alpha, size)

    rep.render()
    if rep.failed():
        print("\nRESULT: FAIL — fix the above before shipping.\n")
        sys.exit(1)
    print("\nRESULT: PASS — geometry is clean. Craft still needs the vision gate.\n")


if __name__ == "__main__":
    main()
