"""Sculpt-pass comparison sheets (pass 3/4 art vs pass 5).

usage: python3 sheets5.py compare --before DIR --after DIR --out compare.jpg [--states complete,half] [--size 600] [--crop]
       python3 sheets5.py refs --after DIR --refs DIR --out compare-references.jpg
       python3 sheets5.py thumbs --after DIR --out thumbs400.jpg          # all 20 stills at 400px, on their pages
Pages: light = cream #EFE9DF (dusk), dark = navy #0B1230 (night), as in the app.
"""
import argparse, glob, os
from PIL import Image, ImageDraw, ImageFont

PAGE = {'light': (239, 233, 223), 'dark': (11, 18, 48)}
INK = {'light': (40, 40, 40), 'dark': (220, 225, 240)}

def font(n):
    for f in ('/System/Library/Fonts/SFNS.ttf', '/System/Library/Fonts/Helvetica.ttc'):
        if os.path.exists(f): return ImageFont.truetype(f, n)
    return ImageFont.load_default()

def tile(path, v, size, crop=None, label=''):
    im = Image.open(path).convert('RGBA')
    if crop: im = im.crop(crop)
    bg = Image.new('RGBA', im.size, PAGE[v] + (255,)); bg.alpha_composite(im)
    bg = bg.convert('RGB').resize((size, size), Image.LANCZOS)
    if label:
        d = ImageDraw.Draw(bg); d.text((10, 8), label, fill=INK[v], font=font(max(14, size // 26)))
    return bg

def grid(rows, size, gap=6):
    h = len(rows); w = max(len(r) for r in rows)
    out = Image.new('RGB', (w * size + (w - 1) * gap, h * size + (h - 1) * gap), (255, 255, 255))
    for i, r in enumerate(rows):
        for j, t in enumerate(r): out.paste(t, (j * (size + gap), i * (size + gap)))
    return out

def compare(a):
    rows = []
    crop = (330, 120, 930, 720) if a.crop else None
    for s in a.states.split(','):
        for v in ('light', 'dark'):
            name = f'craft_{s}_{v}.png'
            rows.append([tile(os.path.join(a.before, name), v, a.size, crop, f'before · {s} · {"dusk" if v == "light" else "night"}'),
                         tile(os.path.join(a.after, name), v, a.size, crop, f'after · {s} · {"dusk" if v == "light" else "night"}')])
    grid(rows, a.size).save(a.out, quality=88); print('wrote', a.out)

def refs(a):
    H = a.size
    ims = [tile(os.path.join(a.after, 'craft_complete_light.png'), 'light', H, None, 'ours · dusk'),
           tile(os.path.join(a.after, 'craft_complete_dark.png'), 'dark', H, None, 'ours · night')]
    for f, lab in (('3-2-opal.jpg', 'Opal'), ('3-3-tolan.jpg', 'Tolan')):
        r = Image.open(os.path.join(a.refs, f)).convert('RGB'); r = r.resize((int(r.width * H / r.height), H), Image.LANCZOS)
        d = ImageDraw.Draw(r); d.text((10, 8), lab, fill=(255, 255, 255), font=font(H // 26)); ims.append(r)
    W = sum(i.width for i in ims) + 6 * (len(ims) - 1)
    out = Image.new('RGB', (W, H), (255, 255, 255)); x = 0
    for i in ims: out.paste(i, (x, 0)); x += i.width + 6
    out.save(a.out, quality=88); print('wrote', a.out)

def thumbs(a):
    rows = []
    for v in ('light', 'dark'):
        for lit in ('', '-unlit'):
            rows.append([tile(os.path.join(a.after, f'craft_{s}{lit}_{v}.png'), v, 400, None, f'{s}{lit}')
                         for s in ('started', 'frame70', 'framing', 'half', 'complete')])
    grid(rows, 400).save(a.out, quality=85); print('wrote', a.out)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('mode')
    ap.add_argument('--before'); ap.add_argument('--after'); ap.add_argument('--refs'); ap.add_argument('--out', required=True)
    ap.add_argument('--states', default='complete,half'); ap.add_argument('--size', type=int, default=600)
    ap.add_argument('--crop', action='store_true')
    a = ap.parse_args(); {'compare': compare, 'refs': refs, 'thumbs': thumbs}[a.mode](a)
