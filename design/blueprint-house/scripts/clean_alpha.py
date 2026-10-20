"""Remove the faint shadow-catcher veil (alpha <= 10/255 from world occlusion) that would
otherwise tint the whole canvas. Ramps alpha 10..22 -> 0..22 so soft shadow edges stay smooth.
usage: clean_alpha.py <png> [<png> ...]   (in place)"""
import sys
import numpy as np
from PIL import Image
def clean(p):
    im = np.asarray(Image.open(p).convert('RGBA')).astype(np.float32)
    a = im[..., 3]
    lo, hi = 10.0, 22.0
    ramp = np.clip((a - lo) / (hi - lo), 0, 1)
    a2 = np.where(a < hi, a * ramp, a)
    im[..., 3] = a2
    Image.fromarray(im.round().astype(np.uint8), 'RGBA').save(p)

def limit_shadow(p, reach=90, feather=60):
    """Keep shadow-catcher alpha only within `reach` px of the opaque model, feathered,
    so long cast shadows never hit the canvas edge with a hard cut."""
    from PIL import ImageFilter
    im = Image.open(p).convert('RGBA'); arr = np.asarray(im).astype(np.float32)
    a = arr[..., 3]
    solid = Image.fromarray(((a > 250) * 255).astype(np.uint8))
    s = 4
    small = solid.resize((solid.width // s, solid.height // s), Image.BILINEAR)
    small = small.filter(ImageFilter.MaxFilter(2 * (reach // s) + 1))
    small = small.filter(ImageFilter.GaussianBlur(feather / s))
    m = np.asarray(small.resize(solid.size, Image.BILINEAR)).astype(np.float32) / 255.0
    arr[..., 3] = np.where(a > 250, a, a * m)
    Image.fromarray(arr.round().astype(np.uint8), 'RGBA').save(p)

if __name__ == '__main__':
    for p in sys.argv[1:]:
        clean(p); limit_shadow(p)
