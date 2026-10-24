"""Soft page-shadow fade for Craft pass-3 PNGs (run after craft_post.py).

The dusk sky fill throws a broad soft shadow onto the catcher; near the canvas edges craft_post.py's hard
alpha<40 cut left a ragged contour. This fades only the shadow (low alpha), smoothly, toward every edge,
and leaves the object (alpha >= 200) untouched.
usage: python3 craft3_post.py <png>...   (in place)
"""
import sys
import numpy as np
from PIL import Image

BAND = 0.2
for f in sys.argv[1:]:
    im = np.array(Image.open(f).convert('RGBA')).astype(np.float32)
    h, w = im.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum.reduce([xx, w - 1 - xx, yy, h - 1 - yy]).astype(np.float32) / (BAND * min(w, h))
    t = np.clip(d, 0, 1); ramp = t * t * (3 - 2 * t)               # smoothstep to 0 at the edge
    a = im[:, :, 3]
    s = np.clip((a - 120) / 80, 0, 1); keep = s * s * (3 - 2 * s)   # 1 for the object, 0 for the shadow
    im[:, :, 3] = a * (keep + (1 - keep) * ramp)
    Image.fromarray(im.clip(0, 255).astype(np.uint8)).save(f, optimize=True)
    print('post3', f)
