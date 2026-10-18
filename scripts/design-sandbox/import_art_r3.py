"""Import creative-r3 concept art into DesignSandbox/Art (prefix bp- / pl- / tw-).

Blueprint house layers (master, frame, blueprint linework) arrive as opaque, registered renders.
They are matted with a border-connected colour key (soft edge keeps the contact shadow), the
blueprint render becomes transparent cyan linework, and all three are cropped with ONE shared box
so SwiftUI can stack them and reveal the built layers with a rising mask.
"""
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

SRC = sys.argv[1] if len(sys.argv) > 1 else '/Users/brian/AgentScratch/landlordhours/2026-10-18/creative-r3/assets'
DST = os.path.join(os.path.dirname(__file__), '..', '..', 'DesignSandbox', 'Art')
os.makedirs(DST, exist_ok=True)


MATTES = os.environ.get('MATTE_DIR', '/Users/brian/AgentScratch/landlordhours/2026-10-18/creative-r3/sandbox-mattes')


def matte(path, work=1024):
    # Prefer a birefnet cutout (fal-ai/birefnet/v2) made for this sandbox; colour key is the fallback.
    pre = os.path.join(MATTES, os.path.basename(path))
    if os.path.exists(pre):
        return Image.open(pre).convert('RGBA').resize((work, work), Image.LANCZOS)
    im = Image.open(path).convert('RGB').resize((work, work), Image.LANCZOS)
    a = np.asarray(im).astype(np.int32)
    bg = np.median(np.concatenate([a[:8].reshape(-1, 3), a[-8:].reshape(-1, 3), a[:, :8].reshape(-1, 3), a[:, -8:].reshape(-1, 3)]), axis=0)
    dist = np.sqrt(((a - bg) ** 2).sum(axis=2))
    near = Image.fromarray(np.where(dist < 34, 255, 0).astype(np.uint8)).copy()
    for seed in [(0, 0), (work - 1, 0), (0, work - 1), (work - 1, work - 1)]:
        if near.getpixel(seed) == 255:
            ImageDraw.floodfill(near, seed, 128, thresh=0)
    region = np.asarray(near) == 128
    alpha = np.where(region, np.clip((dist - 7) * 255 / 27, 0, 255), 255).astype(np.uint8)
    rgba = np.dstack([a.astype(np.uint8), alpha])
    return Image.fromarray(rgba, 'RGBA')


def linework(path, work=1024):
    im = Image.open(path).convert('RGB').resize((work, work), Image.LANCZOS)
    a = np.asarray(im).astype(np.int32)
    bg = np.array([9, 59, 109])
    lift = np.clip((a - bg).max(axis=2), 0, 255)
    alpha = np.clip(lift * 1.6, 0, 255).astype(np.uint8)
    rgb = np.zeros_like(a, dtype=np.uint8)
    rgb[..., 0], rgb[..., 1], rgb[..., 2] = 0x8F, 0xD3, 0xFF
    return Image.fromarray(np.dstack([rgb, alpha]), 'RGBA')


def crop_to(im, box, size):
    out = im.crop(box)
    out.thumbnail((size, size), Image.LANCZOS)
    return out


def save_obj(path, name, size=320):
    im = Image.open(path).convert('RGBA')
    bb = im.getchannel('A').point(lambda v: 255 if v > 12 else 0).getbbox()
    if bb:
        im = im.crop(bb)
        pad = int(max(im.size) * 0.04)
        side = max(im.size) + 2 * pad
        c = Image.new('RGBA', (side, side), (0, 0, 0, 0))
        c.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        im = c
    im.thumbnail((size, size), Image.LANCZOS)
    im.save(os.path.join(DST, name + '.png'), optimize=True)


bp = os.path.join(SRC, 'blueprint')
if os.path.exists(os.path.join(bp, 'house_master.png')):
    master = matte(os.path.join(bp, 'house_master.png'))
    layers = {'bp-house-built': master}
    if os.path.exists(os.path.join(bp, 'stage_3_frame.png')):
        layers['bp-house-frame'] = matte(os.path.join(bp, 'stage_3_frame.png'))
    if os.path.exists(os.path.join(bp, 'stage_1_blueprint.png')):
        layers['bp-house-lines'] = linework(os.path.join(bp, 'stage_1_blueprint.png'))
    # one shared box: the union of the opaque parts of master + frame, plus a margin
    boxes = [l.getchannel('A').point(lambda v: 255 if v > 200 else 0).getbbox() for k, l in layers.items() if k != 'bp-house-lines']
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes); x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    m = 24
    side = max(x1 - x0, y1 - y0) + 2 * m
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    box = (cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)
    print('house box', box, 'opaque extent y', y0, y1, 'fraction in box', (y0 - box[1]) / side, (y1 - box[1]) / side)
    for k, l in layers.items():
        crop_to(l, box, 900).save(os.path.join(DST, k + '.png'), optimize=True)

objects = {
    'empty_lot_stake': 'bp-empty-lot', 'plaque_blank': 'bp-plaque-blank', 'rolled_blueprint_tools': 'bp-rolled-blueprint',
    'tool_clipboard': 'bp-tool-inspections', 'tool_key': 'bp-tool-leasing', 'tool_ledger': 'bp-tool-bookkeeping',
    'tool_wrench': 'bp-tool-repairs', 'type_apartment': 'bp-type-apartment', 'type_cabin': 'bp-type-cabin',
    'type_duplex': 'bp-type-duplex', 'type_single': 'bp-type-single',
}
for src, dst in objects.items():
    p = os.path.join(bp, src + '.png')
    if os.path.exists(p):
        save_obj(p, dst, 640 if 'empty' in dst or 'rolled' in dst else 320)

for concept, prefix in [('porchlight', 'pl-'), ('tilework', 'tw-')]:
    d = os.path.join(SRC, concept)
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            if f.endswith('.png') and not f.startswith('_'):
                im = Image.open(os.path.join(d, f))
                if im.mode == 'RGBA':
                    save_obj(os.path.join(d, f), prefix + f[:-4].replace('_', '-'), 640)
print(sorted(x for x in os.listdir(DST) if x.startswith(('bp-', 'pl-', 'tw-'))))

# Porchlight extras: unlit lamp (cone + glow removed), softer lit cone, autumn ground strip.
pl = os.path.join(SRC, 'porchlight')
lp = os.path.join(DST, 'pl-lamp-lit.png')
if os.path.exists(lp):
    a = np.asarray(Image.open(lp).convert('RGBA')).astype(np.int32)
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    unlit = a.copy()
    unlit[..., 3] = np.where(lum < 150, a[..., 3], 0)
    Image.fromarray(unlit.astype(np.uint8)).save(os.path.join(DST, 'pl-lamp-unlit.png'), optimize=True)
    lit = a.copy()
    lit[..., 3] = np.where(lum >= 150, (a[..., 3] * 0.6).astype(np.int32), a[..., 3])
    Image.fromarray(lit.astype(np.uint8)).save(os.path.join(DST, 'pl-lamp-lit.png'), optimize=True)
gp = os.path.join(pl, 'ground_autumn.png')
if os.path.exists(gp):
    g = Image.open(gp).convert('RGB')
    g = g.crop((0, 0, g.width, int(g.height * 0.62)))   # lawn + sidewalk; drop the lower band
    g.thumbnail((1400, 1400), Image.LANCZOS)
    g.save(os.path.join(DST, 'pl-ground-autumn.png'), optimize=True)
print('porchlight extras done')

# Blueprint tools set (assets/blueprint/tools): one consistent 3D object per category.
tools = os.path.join(bp, 'tools')
tool_map = {'repairs': 'tool_wrench', 'renovation': 'tool_roller', 'cleaning': 'tool_bucket_sponge', 'leasing': 'tool_key',
            'tenant': 'tool_phone', 'bookkeeping': 'tool_ledger', 'travel': 'tool_carkey', 'inspections': 'tool_flashlight',
            'legal': 'tool_stamp', 'supplies': 'tool_hardware_bag', 'management': 'tool_clipboard'}
missing = []
for cat, f in tool_map.items():
    p = os.path.join(tools, f + '.png')
    if os.path.exists(p):
        save_obj(p, 'bp-tool-' + cat, 320)
    else:
        missing.append(cat)
print('tools missing:', missing)
