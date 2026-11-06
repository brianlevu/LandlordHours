"""Tool-set consistency metrics (the WP-A gate's measures): alpha fill %, mean HSV saturation and luminance of
opaque pixels, key-light direction proxy (luminance of the upper-left vs lower-right half of the object),
and alpha-centroid offset in pt at 36 pt.
usage: tool_metrics.py <dir> [variant]"""
import sys, glob, os, json
import numpy as np
from PIL import Image
d = sys.argv[1]; v = sys.argv[2] if len(sys.argv) > 2 else 'light'
rows = {}
for p in sorted(glob.glob(os.path.join(d, f'tool_*__{v}.png'))):
    a = np.asarray(Image.open(p).convert('RGBA')).astype(float) / 255
    al = a[..., 3]; m = al > 0.5; n = al.shape[0]
    rgb = a[..., :3][m]; mx = rgb.max(1); mn = rgb.min(1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0).mean()
    lum = (0.2126 * rgb[:, 0] + 0.7152 * rgb[:, 1] + 0.0722 * rgb[:, 2])
    yy, xx = np.mgrid[0:n, 0:n]
    cx = (al * xx).sum() / al.sum() - (n - 1) / 2; cy = (al * yy).sum() / al.sum() - (n - 1) / 2
    L = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
    diag = (xx - (al * xx).sum() / al.sum()) + (yy - (al * yy).sum() / al.sum())
    ul = L[m & (diag < 0)].mean(); lr = L[m & (diag >= 0)].mean()
    rows[os.path.basename(p)[5:-len(f'__{v}.png')]] = dict(fill_pct=round(100 * al.mean(), 1), sat=round(sat, 3), lum=round(lum.mean(), 3),
        key_ul_minus_lr=round(ul - lr, 3), centroid_off_pt36=(round(cx / n * 36, 2), round(cy / n * 36, 2)))
for k, r in rows.items(): print(k.ljust(12), r)
f = [r['fill_pct'] for r in rows.values()]; s = [r['sat'] for r in rows.values()]; c = [max(map(abs, r['centroid_off_pt36'])) for r in rows.values()]
print('fill %.1f-%.1f  sat %.2f-%.2f  max centroid off %.2fpt' % (min(f), max(f), min(s), max(s), max(c)))
