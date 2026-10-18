"""Find the baked-in lit windows in the Porchlight house renders so code can overlay lit/unlit glass.

Prints normalized rects (x, y, w, h in 0…1 of the cropped image) per house as Swift literals.
Run after import_art_r3.py has produced DesignSandbox/Art/pl-house-*.png.
"""
import os
import numpy as np
from PIL import Image

ART = os.path.join(os.path.dirname(__file__), '..', '..', 'DesignSandbox', 'Art')


def windows(path, min_px=40):
    im = np.asarray(Image.open(path).convert('RGBA')).astype(int)
    r, g, b, a = im[..., 0], im[..., 1], im[..., 2], im[..., 3]
    yellow = (r > 200) & (g > 165) & (b < 150) & (a > 200) & (r - b > 80)
    h, w = yellow.shape
    seen = np.zeros_like(yellow)
    rects = []
    for y in range(h):
        for x in range(w):
            if yellow[y, x] and not seen[y, x]:
                stack = [(y, x)]; seen[y, x] = True
                ys, xs = [], []
                while stack:
                    cy, cx = stack.pop(); ys.append(cy); xs.append(cx)
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and yellow[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True; stack.append((ny, nx))
                if len(ys) >= min_px:
                    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
                    if (x1 - x0) > 4 and (y1 - y0) > 4:
                        rects.append((x0 / w, y0 / h, (x1 - x0 + 1) / w, (y1 - y0 + 1) / h))
    # merge panes that touch (mullions split one window into 2-4 panes)
    merged = []
    for rc in sorted(rects, key=lambda t: (t[1], t[0])):
        for i, m in enumerate(merged):
            if rc[0] < m[0] + m[2] + 0.012 and m[0] < rc[0] + rc[2] + 0.012 and rc[1] < m[1] + m[3] + 0.012 and m[1] < rc[1] + rc[3] + 0.012:
                x0 = min(m[0], rc[0]); y0 = min(m[1], rc[1])
                x1 = max(m[0] + m[2], rc[0] + rc[2]); y1 = max(m[1] + m[3], rc[1] + rc[3])
                merged[i] = (x0, y0, x1 - x0, y1 - y0)
                break
        else:
            merged.append(rc)
    merged = [m for m in merged if m[2] * m[3] > 0.0006]
    return sorted(merged, key=lambda t: (round(t[1], 1), t[0]))


for name in ['pl-house-cabin', 'pl-house-duplex']:
    p = os.path.join(ART, name + '.png')
    if os.path.exists(p):
        ws = windows(p)
        lits = ', '.join(f'CGRect(x: {x:.3f}, y: {y:.3f}, width: {w:.3f}, height: {h:.3f})' for x, y, w, h in ws)
        print(f'"{name}": [{lits}],')
