"""Silhouette IoU between the Blueprint house layers, normalised to plinth width.

Each layer's alpha (linework is filled into a solid silhouette) is cropped to its plinth's
horizontal extent, scaled so the plinth is 400px wide, aligned on the plinth's bottom-centre,
and compared with the built master. Usage: python3 house_iou.py [art_dir]
"""
import os
import sys
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

ART = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', '..', 'DesignSandbox', 'Art')


def silhouette(name, fill=False):
    a = Image.open(os.path.join(ART, name + '.png')).convert('RGBA').getchannel('A')
    m = a.point(lambda v: 255 if v > 60 else 0)
    if fill:
        # close the line drawing, then flood the outside; everything not outside is the silhouette
        m = m.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(5))
        m = m.convert('L')
        ImageDraw.floodfill(m, (0, 0), 128, thresh=0)
        arr = np.asarray(m)
        m = Image.fromarray(np.where(arr == 128, 0, 255).astype(np.uint8))
    return np.asarray(m) > 127


def normalise(s, W=400, H=480):
    ys, xs = np.where(s)
    # plinth = the widest band in the lowest 20% of the shape
    y0, y1 = ys.min(), ys.max()
    low = s[int(y1 - (y1 - y0) * 0.2):y1 + 1]
    cols = np.where(low.any(axis=0))[0]
    px0, px1 = cols.min(), cols.max()
    scale = W / (px1 - px0 + 1)
    im = Image.fromarray((s * 255).astype(np.uint8))
    im = im.resize((int(s.shape[1] * scale), int(s.shape[0] * scale)), Image.NEAREST)
    out = Image.new('L', (W + 40, H), 0)
    cx = (px0 + px1) / 2 * scale
    out.paste(im, (int(round((W + 40) / 2 - cx)), int(round(H - 10 - y1 * scale))))
    return np.asarray(out) > 127


def iou(a, b):
    return (a & b).sum() / max(1, (a | b).sum())


built = normalise(silhouette('bp-house-built'))
res = {}
for name, fill in [('bp-house-lines', True), ('bp-house-frame', True)]:
    if os.path.exists(os.path.join(ART, name + '.png')):
        res[name] = iou(built, normalise(silhouette(name, fill)))
for k, v in res.items():
    print(f'{k:16s} IoU vs built master: {v:.3f} {"PASS" if v >= 0.95 else "FAIL"}')
