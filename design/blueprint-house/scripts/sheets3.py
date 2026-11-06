"""Comparison sheets for the Craft pass 3 renders.

usage: python3 sheets3.py --new DIR3/renders/stills --old DIR2/renders/stills --refs TASTE_BOARD/img --out DIR3
Writes compare-references.jpg, compare-before-after-{light,dark}.jpg, compare-lit-unlit.jpg, work/thumb400_*.png.
Light-mode art sits on the cream page (#EEE8DD), dark-mode art on the navy page (#0B1230).
"""
import argparse, os
from PIL import Image, ImageDraw, ImageFont

ST = ['started', 'frame70', 'framing', 'half', 'complete']
try:
    F = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 26)
except Exception:
    F = ImageFont.load_default()

def comp(p, dark, s):
    im = Image.open(p).convert('RGBA')
    bg = Image.new('RGBA', im.size, (11, 18, 48, 255) if dark else (238, 232, 221, 255))
    bg.alpha_composite(im)
    return bg.convert('RGB').resize((s, s), Image.LANCZOS)

def label(d, xy, t):
    d.text(xy, t, fill='black', font=F)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--new', required=True); ap.add_argument('--old', required=True)
    ap.add_argument('--refs', required=True); ap.add_argument('--out', required=True)
    a = ap.parse_args()
    os.makedirs(os.path.join(a.out, 'work'), exist_ok=True)
    s = 420
    # before / after per mode: old (dir-craft2 day / night) on top, new (dusk / night, lit) below
    for v, name in (('light', 'dusk'), ('dark', 'night')):
        S = Image.new('RGB', (s * 5, s * 2 + 80), 'white'); d = ImageDraw.Draw(S)
        for i, st in enumerate(ST):
            S.paste(comp(f'{a.old}/craft_{st}_{v}.png', v == 'dark', s), (i * s, 40))
            S.paste(comp(f'{a.new}/craft_{st}_{v}.png', v == 'dark', s), (i * s, s + 80))
            label(d, (i * s + 10, 8), st)
        label(d, (10, s + 48), f'AFTER (dir-craft3, {name}, lit)        BEFORE row above: dir-craft2 ({"day" if v == "light" else "night"})')
        S.save(f'{a.out}/compare-before-after-{v}.jpg', quality=90)
    # lit vs unlit, every stage, both modes
    S = Image.new('RGB', (s * 5, s * 4 + 160), 'white'); d = ImageDraw.Draw(S); y = 0
    for v in ('light', 'dark'):
        for lit in ('', '-unlit'):
            label(d, (10, y + 8), f'{"dusk" if v == "light" else "night"} {"lit (hours logged today)" if not lit else "unlit (no hours today)"}')
            for i, st in enumerate(ST):
                S.paste(comp(f'{a.new}/craft_{st}{lit}_{v}.png', v == 'dark', s), (i * s, y + 40))
            y += s + 40
    S.save(f'{a.out}/compare-lit-unlit.jpg', quality=88)
    # references: ours dusk + night next to Opal, Not Boring Weather, Tolan at phone height
    H = 1170; tiles = []
    for v in ('light', 'dark'):
        tiles.append((f'ours {"dusk" if v == "light" else "night"}', comp(f'{a.new}/craft_complete_{v}.png', v == 'dark', H)))
    for n, lab in (('3-2-opal.jpg', 'Opal'), ('3-1-not-boring-weather.jpg', 'Not Boring Weather'), ('3-3-tolan.jpg', 'Tolan')):
        im = Image.open(f'{a.refs}/{n}').convert('RGB'); im = im.resize((int(im.width * H / im.height), H), Image.LANCZOS)
        tiles.append((lab, im))
    W = sum(t[1].width for t in tiles) + 20 * (len(tiles) - 1)
    S = Image.new('RGB', (W, H + 50), 'white'); d = ImageDraw.Draw(S); x = 0
    for lab, im in tiles:
        S.paste(im, (x, 50)); label(d, (x + 10, 12), lab); x += im.width + 20
    S.save(f'{a.out}/compare-references.jpg', quality=88)
    # 400 px reads
    for v in ('light', 'dark'):
        for st in ('complete', 'framing', 'half'):
            for lit in ('', '-unlit'):
                comp(f'{a.new}/craft_{st}{lit}_{v}.png', v == 'dark', 400).save(f'{a.out}/work/thumb400_{st}{lit}_{v}.png')
    print('sheets ok')

if __name__ == '__main__':
    main()
