"""Copy the generated creative-direction art into DesignSandbox/Art at app sizes.

Usage: python3 scripts/design-sandbox/import_art.py [assets_dir]
Inkwell drawings arrive as opaque white JPEG-like PNGs; white is keyed to alpha so the
line art sits on any surface (alpha = distance from paper white, colour un-premultiplied).
"""
import os
import sys
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else '/Users/brian/AgentScratch/landlordhours/2026-10-18/creative/assets'
DST = os.path.join(os.path.dirname(__file__), '..', '..', 'DesignSandbox', 'Art')
os.makedirs(DST, exist_ok=True)


def save(im, name, size):
    im = im.convert('RGBA')
    # Crop to the visible object (generated art carries wide transparent margins), keep 4% air.
    bbox = im.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
    if bbox:
        im = im.crop(bbox)
        pad = int(max(im.size) * 0.04)
        side = max(im.size) + 2 * pad
        canvas = Image.new('RGBA', (side, side) if 'welcome' not in name or name.startswith('clay') else (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0))
        canvas.paste(im, ((canvas.width - im.width) // 2, (canvas.height - im.height) // 2))
        im = canvas
    im.thumbnail((size, size), Image.LANCZOS)
    im.save(os.path.join(DST, name + '.png'), optimize=True)


def key_white(im):
    im = im.convert('RGB')
    px = im.load()
    out = Image.new('RGBA', im.size)
    po = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = px[x, y]
            d = 255 - min(r, g, b)
            a = min(255, int(d * 2.2))
            if a < 10:
                po[x, y] = (0, 0, 0, 0)
                continue
            f = a / 255
            un = lambda c: max(0, min(255, int(255 - (255 - c) / f)))
            po[x, y] = (un(r), un(g), un(b), a)
    return out


clay = os.path.join(SRC, 'clayhouse')
for f in sorted(os.listdir(clay)):
    if not f.endswith('.png') or f.startswith('_'):
        continue
    base = f[:-4]
    size = 768 if base.startswith('scene') else 256
    save(Image.open(os.path.join(clay, f)), 'clay-' + base, size)

way = os.path.join(SRC, 'waypoint')
for f in sorted(os.listdir(way)):
    if f.endswith('.png') and not f.startswith('_'):
        save(Image.open(os.path.join(way, f)), 'way-' + f[:-4], 1400 if 'welcome' in f else 768)

ink = os.path.join(SRC, 'inkwell')
for f in ['cabin.png', 'keyring.png', 'receipt-envelope.png']:  # ledger-pen has misspelled lettering; not used
    p = os.path.join(ink, f)
    if os.path.exists(p):
        im = Image.open(p)
        im.thumbnail((640, 640), Image.LANCZOS)
        save(key_white(im), 'ink-' + f[:-4], 640)

print(sorted(os.listdir(DST)))
