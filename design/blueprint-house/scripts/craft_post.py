"""Clean the faint shadow-catcher alpha at the art's edges so the PNG never shows a frame on the page.

Pixels in the outer border band with low alpha (sky-occlusion residue, < 40/255) fade to 0 toward the edge.
usage: python craft_post.py <png>...   (in place)
"""
import sys
import numpy as np
from PIL import Image

BAND = 0.08
for f in sys.argv[1:]:
    im = np.array(Image.open(f).convert('RGBA')).astype(np.float32)
    h, w = im.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum.reduce([xx, w - 1 - xx, yy, h - 1 - yy]).astype(np.float32) / (BAND * min(w, h))
    ramp = np.clip(d, 0, 1) ** 1.5
    a = im[:, :, 3]
    low = a < 40
    a[low] = a[low] * ramp[low]
    im[:, :, 3] = a
    Image.fromarray(im.clip(0, 255).astype(np.uint8)).save(f, optimize=True)
    print('post', f)
