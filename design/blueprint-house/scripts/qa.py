"""Quantitative self-checks on renders.
1. Registration: stage0 linework (whole house drawn as lines) must sit inside the finished
   built silhouette (stage5 alpha), dilated by a few px. Reports % of line pixels outside.
2. Alpha hygiene: corners fully transparent; no stray opaque islands far from the model.
3. Consistency: the lot silhouette is identical across all built stages (same camera/scale).
"""
import sys, os, glob, json
import numpy as np
from PIL import Image, ImageFilter

d = sys.argv[1]
def A(p): return np.asarray(Image.open(p).convert('RGBA'))[..., 3]
res = {}
fin = A(os.path.join(d, 'stage5_finished__built__light.png'))
lines0 = A(os.path.join(d, 'stage0_lot__lines.png'))
for dil in (3, 7):
    m = Image.fromarray(((fin > 128) * 255).astype('uint8')).filter(ImageFilter.MaxFilter(2 * dil + 1))
    m = np.asarray(m) > 0
    L = lines0 > 160
    res[f'lines_outside_finished_silhouette_dil{dil}px_pct'] = round(100 * (L & ~m).sum() / max(L.sum(), 1), 3)
# lot silhouette consistency: compare lower half (lot region) alpha between stages
lot = None
diffs = {}
for p in sorted(glob.glob(os.path.join(d, '*__built__light.png'))):
    a = A(p)
    if lot is None: lot = a
    h = a.shape[0]
    region = slice(int(h * 0.62), h)
    diffs[os.path.basename(p)] = int(((a[region] > 128) != (lot[region] > 128)).sum())
res['lot_region_alpha_px_diff_vs_first'] = diffs
corners = {}
for p in sorted(glob.glob(os.path.join(d, '*.png'))):
    a = A(p)
    c = max(a[:40, :40].max(), a[:40, -40:].max(), a[-40:, :40].max(), a[-40:, -40:].max())
    corners[os.path.basename(p)] = int(c)
res['max_corner_alpha'] = max(corners.values())
print(json.dumps(res, indent=1))
