"""Night contrast vs the navy canvas #0B1230: composite each RGBA still over navy, per-pixel WCAG contrast vs navy.
Hero = pixels with alpha >= A (the object, not the soft shadow). 'studs' = hero pixels that are timber-ish (non-lawn):
we report p99 and share >= 3:1 for hero, plus p99 over the brightest silhouette band (alpha>=200).
usage: python measure_night.py [--alpha 128] file.png ..."""
import sys, json, numpy as np
from PIL import Image
NAVY = np.array([0x0B, 0x12, 0x30], np.float32) / 255
def lum(c):
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]
Ln = float(lum(NAVY))
args = sys.argv[1:]; A = 128
if args and args[0] == '--alpha': A = int(args[1]); args = args[2:]
out = {}
for f in args:
    im = np.asarray(Image.open(f).convert('RGBA')).astype(np.float32) / 255
    a = im[..., 3:4]; rgb = im[..., :3] * a + NAVY * (1 - a)
    L = lum(rgb); cr = (np.maximum(L, Ln) + 0.05) / (np.minimum(L, Ln) + 0.05)
    hero = im[..., 3] >= A / 255
    v = cr[hero]
    out[f.split('/')[-1]] = dict(p99=round(float(np.percentile(v, 99)), 2), p90=round(float(np.percentile(v, 90)), 2),
                                 median=round(float(np.median(v)), 2), share_ge3=round(float((v >= 3).mean() * 100), 2),
                                 share_ge2=round(float((v >= 2).mean() * 100), 2), px=int(hero.sum()))
for k, r in out.items(): print(k, r)
if '--json' in sys.argv: pass
