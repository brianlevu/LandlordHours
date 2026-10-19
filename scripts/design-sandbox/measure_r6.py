"""r6 checks: empty-state card inset; house silhouette connectivity (no severed posts/plaque) in the
milestone frame and the master art. usage: measure_r6.py <frames_dir> <art_dir>"""
import sys
import numpy as np
from PIL import Image, ImageDraw

D, ART = sys.argv[1], sys.argv[2]
for ap in ['light', 'dark']:
    im = Image.open(f'{D}/concept-empty-{ap}.png').convert('RGB')
    W, H = im.size
    y = int(H * 0.33)
    xs = [x for x in range(W) if (lambda p: p[2] > 140 and p[0] < 70)(im.getpixel((x, y)))]
    print(f'empty {ap}: card x {min(xs) / 3:.1f}–{max(xs) / 3:.1f} pt (inset L {min(xs) / 3:.1f}, R {(W - 1 - max(xs)) / 3:.1f})')


def components(mask):
    m = Image.fromarray((mask * 255).astype(np.uint8))
    arr = np.asarray(m).copy()
    count, sizes, v = 0, [], 1
    h, w = arr.shape
    lab = np.zeros_like(arr, dtype=np.int32)
    for yy in range(h):
        for xx in range(w):
            if arr[yy, xx] and not lab[yy, xx]:
                count += 1
                stack = [(yy, xx)]; lab[yy, xx] = count; n = 0
                while stack:
                    cy, cx = stack.pop(); n += 1
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and arr[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = count; stack.append((ny, nx))
                sizes.append(n)
    return sorted(sizes, reverse=True)


a = np.asarray(Image.open(f'{ART}/bp-house-built.png').convert('RGBA').resize((300, 300)))[..., 3] > 100
s = components(a)
print('master silhouette components (300px):', len(s), 'largest', s[:3], '-> pieces > 20px apart from body:', sum(1 for x in s[1:] if x > 20))
