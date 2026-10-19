"""WP-A QA: registration, alpha hygiene/halo checks and contact sheets for the exported catalog assets.

usage: qa_wp_a.py <Assets.xcassets/Blueprint> <out_dir>
Writes <out_dir>/qa.json and contact sheets:
  house-blueprint.png  every keyframe, Any variant, lines under built, on #1E3FA6
  house-dark.png       every keyframe, Dark variant, on #0B1230
  house-white.png      every keyframe, Any variant, on #FFFFFF
  registration.png     k00 linework (whole house) drawn OVER k18 built at 60% + diff tint per keyframe
  tools-*.png          tools on white / #1E3FA6 / #0B1230 / plaster tile, at 1:1 app size and 4x zoom
  confirm-row-*.png    animation frames composited on their base keyframe
"""
import glob, json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

CAT, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
BGS = {'blueprint': '#1E3FA6', 'white': '#FFFFFF', 'navy': '#0B1230'}
FONT = None
for fp in ['/System/Library/Fonts/SFNS.ttf', '/System/Library/Fonts/Helvetica.ttc']:
    if os.path.exists(fp):
        FONT = ImageFont.truetype(fp, 20); break

def load(name, dark=False, scale=3):
    g = glob.glob(os.path.join(CAT, '*', name + '.imageset', f'{name}{"-dark" if dark else ""}@{scale}x.png'))
    return Image.open(g[0]).convert('RGBA') if g else None

def lines(k, dark=False, scale=3):
    """Linework is a template image (alpha only); tint it the way SwiftUI will, with bp_drafting."""
    im = load(f'bp_house_{k}_lines', False, scale)
    a = np.asarray(im).copy()
    a[..., 0], a[..., 1], a[..., 2] = (0x60, 0xA8, 0xE6) if dark else (0x8F, 0xD3, 0xFF)
    return Image.fromarray(a, 'RGBA')

def comp(layers, bg, size=None):
    base = Image.new('RGBA', layers[0].size, bg)
    for l in layers:
        if l is not None:
            base = Image.alpha_composite(base, l)
    if size:
        base = base.convert('RGBa').resize(size, Image.LANCZOS).convert('RGBA')
    return base.convert('RGB')

def label(img, xy, text, fill):
    ImageDraw.Draw(img).text(xy, text, fill=fill, font=FONT)

def halo_metrics(im):
    """Edge pixels (alpha 0.35..0.98, touching an opaque pixel): compare their straight colour's luminance with the
    opaque neighbours'. A light/dark fringe shows as edge pixels brighter than every neighbour (light halo, from
    a white matte) or darker than every neighbour (dark halo, from a black matte)."""
    a = np.asarray(im).astype(np.float32)
    al = a[..., 3] / 255.0
    lum = (0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]) / 255.0
    opaque = al > 0.98
    op_img = Image.fromarray((opaque * 255).astype(np.uint8))
    near = np.asarray(op_img.filter(ImageFilter.MaxFilter(3))) > 0
    edge = (al > 0.35) & (al <= 0.98) & near
    lum_op = np.where(opaque, lum, np.nan)
    L = Image.fromarray(np.nan_to_num(lum_op, nan=0.0).astype(np.float32), 'F')
    Lhi = np.asarray(L.filter(ImageFilter.MaxFilter(5)))
    Lneg = Image.fromarray(np.nan_to_num(-lum_op, nan=-2.0).astype(np.float32), 'F')
    Llo = -np.asarray(Lneg.filter(ImageFilter.MaxFilter(5)))
    n = int(edge.sum())
    if n == 0:
        return dict(edge_px=0, light_halo_pct=0.0, dark_halo_pct=0.0)
    light = edge & (lum > Lhi + 0.18)
    dark = edge & (lum < Llo - 0.18)
    return dict(edge_px=n, light_halo_pct=round(100 * light.sum() / n, 3), dark_halo_pct=round(100 * dark.sum() / n, 3))

def corners(im):
    a = np.asarray(im)[..., 3]
    return int(max(a[:12, :12].max(), a[:12, -12:].max(), a[-12:, :12].max(), a[-12:, -12:].max()))

def specks(im):
    """Isolated faint pixels far from the subject (> 24 px from any alpha>20 pixel)."""
    a = np.asarray(im)[..., 3]
    body = Image.fromarray(((a > 20) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(49))
    far = np.asarray(body) == 0
    return int(((a > 0) & far).sum())

res = dict(assets={}, registration={})
sets = sorted(glob.glob(os.path.join(CAT, '*', '*.imageset')))
worst = dict(light_halo_pct=0, dark_halo_pct=0, corner_alpha=0, specks=0)
for s in sets:
    for png in sorted(glob.glob(os.path.join(s, '*.png'))):
        im = Image.open(png).convert('RGBA')
        m = halo_metrics(im); m['corner_alpha'] = corners(im); m['specks'] = specks(im)
        res['assets'][os.path.relpath(png, CAT)] = m
        for k in worst:
            worst[k] = max(worst[k], m[k])
res['worst'] = worst

# ---------------------------------------------------------------- house sheets
keys = sorted({os.path.basename(p).split('.imageset')[0][len('bp_house_'):-len('_built')]
               for p in glob.glob(os.path.join(CAT, 'House', 'bp_house_*_built.imageset'))})
cell = 360
for nm, bg, dark, txt in (('blueprint', BGS['blueprint'], False, '#FFFFFF'), ('dark', BGS['navy'], True, '#F2F4FA'),
                          ('white', BGS['white'], False, '#121B33'), ('dark-on-blueprint', BGS['blueprint'], True, '#FFFFFF')):
    cols = 7
    rows = (len(keys) + cols - 1) // cols
    S = Image.new('RGB', (cell * cols, (cell + 30) * rows), bg)
    for i, k in enumerate(keys):
        b = load(f'bp_house_{k}_built', dark); l = lines(k, dark)
        S.paste(comp([l, b], bg, (cell, cell)), ((i % cols) * cell, (i // cols) * (cell + 30) + 30))
        label(S, ((i % cols) * cell + 10, (i // cols) * (cell + 30) + 4), k, txt)
    S.save(os.path.join(OUT, f'house-{nm}.png'))

# ---------------------------------------------------------------- registration
fin = load('bp_house_k18_finished_built'); fa = np.asarray(fin)[..., 3]
l0 = load('bp_house_k00_lot_lines'); la = np.asarray(l0)[..., 3]
for dil in (2, 4):
    m = np.asarray(Image.fromarray(((fa > 128) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * dil + 1))) > 0
    L = la > 160
    res['registration'][f'k00_lines_outside_k18_silhouette_dil{dil}px_pct'] = round(100 * (L & ~m).sum() / max(L.sum(), 1), 3)
# per keyframe (informational): share of strong line pixels that sit over opaque built pixels, i.e. over the ground

ov = {}
for k in keys:
    b = np.asarray(load(f'bp_house_{k}_built'))[..., 3]; l = np.asarray(load(f'bp_house_{k}_lines'))[..., 3]
    inner = np.asarray(Image.fromarray(((b > 250) * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5))) > 0
    ov[k] = round(100 * ((l > 200) & inner).sum() / max((l > 200).sum(), 1), 3)
res['registration']['lines_over_opaque_built_pct_info'] = ov   # lines are drawn ABOVE built; overlap = future house over the lot/slab (expected)
# lot silhouette identical across keyframes
lots = {}
ref = np.asarray(load('bp_house_k00_lot_built'))[..., 3]
h = ref.shape[0]
for k in keys:
    a = np.asarray(load(f'bp_house_{k}_built'))[..., 3]
    lots[k] = int(((a[int(h * 0.80):] > 128) != (ref[int(h * 0.80):] > 128)).sum())
res['registration']['lot_bottom_band_px_diff_vs_k00'] = lots
ovl = Image.alpha_composite(Image.new('RGBA', fin.size, BGS['navy']), fin)
red = np.asarray(l0).copy(); red[..., 0], red[..., 1], red[..., 2] = 255, 60, 200
red[..., 3] = (red[..., 3] * 0.8).astype(np.uint8)
ovl = Image.alpha_composite(ovl, Image.fromarray(red, 'RGBA'))
ovl.save(os.path.join(OUT, 'registration-k00lines-over-k18built.png'))

# ---------------------------------------------------------------- tools
tools = sorted({os.path.basename(p).split('.imageset')[0][len('bp_tool_'):-3]
                for p in glob.glob(os.path.join(CAT, 'Tools', 'bp_tool_*_36.imageset'))})
for pt in (36, 56):
    for sc in (3,):
        px = pt * sc
        tile = int(px * 1.33)
        rows = [('white', BGS['white'], False), ('plaster tile', '#F4EFE6', False), ('blueprint', BGS['blueprint'], False),
                ('navy · dark', BGS['navy'], True), ('blueprint · dark', BGS['blueprint'], True)]
        S = Image.new('RGB', (tile * len(tools) + 200, tile * len(rows)), '#777')
        for r, (nm, bg, dark) in enumerate(rows):
            label(S, (8, r * tile + tile // 2 - 10), nm, '#FFFFFF')
            for c, t in enumerate(tools):
                im = load(f'bp_tool_{t}_{pt}', dark, sc)
                base = Image.new('RGBA', (tile, tile), bg)
                base.alpha_composite(im, ((tile - px) // 2, (tile - px) // 2))
                S.paste(base.convert('RGB'), (200 + c * tile, r * tile))
        S.save(os.path.join(OUT, f'tools-{pt}pt@{sc}x.png'))
# 1:1 at device scale for 36pt @2x, zoomed 4x nearest so fringes are visible
z = []
for bgname, bg in BGS.items():
    for dark in (False, True):
        row = Image.new('RGB', (len(tools) * 84, 84), bg)
        for c, t in enumerate(tools):
            im = load(f'bp_tool_{t}_36', dark, 2)
            base = Image.new('RGBA', (84, 84), bg); base.alpha_composite(im, (6, 6))
            row.paste(base.convert('RGB'), (c * 84, 0))
        z.append(row.resize((row.width * 3, row.height * 3), Image.NEAREST))
S = Image.new('RGB', (z[0].width, sum(r.height for r in z)))
y = 0
for r in z:
    S.paste(r, (0, y)); y += r.height
S.save(os.path.join(OUT, 'tools-36pt@2x-zoom3-nearest.png'))

# ---------------------------------------------------------------- confirm row
frames = sorted(glob.glob(os.path.join(CAT, 'ConfirmRow', 'bp_confirm_row_*.imageset')))
for dark, bg in (((False, BGS['blueprint']), (True, BGS['navy'])) if frames else ()):
    base_b = load('bp_house_k14_siding040_built', dark); base_l = lines('k14_siding040', dark)
    cols = 6; cw = 420
    S = Image.new('RGB', (cw * cols, (cw + 26) * ((len(frames) + cols - 1) // cols)), bg)
    for i, f in enumerate(frames):
        n = os.path.basename(f).split('.imageset')[0]
        fr = load(n, dark)
        im = comp([base_l, base_b, fr], bg)
        im = im.crop((int(im.width * 0.1), int(im.height * 0.1), int(im.width * 0.9), int(im.height * 0.9))).resize((cw, cw), Image.LANCZOS)
        S.paste(im, ((i % cols) * cw, (i // cols) * (cw + 26) + 26))
        label(S, ((i % cols) * cw + 8, (i // cols) * (cw + 26) + 3), n[-2:], '#FFFFFF')
    S.save(os.path.join(OUT, f'confirm-row-{"dark" if dark else "any"}.png'))
    if frames:
        # last overlay frame on the base vs the next keyframe-ish reference: rest position check
        res.setdefault('confirm_row', {})['frames'] = len(frames)

with open(os.path.join(OUT, 'qa.json'), 'w') as f:
    json.dump(res, f, indent=1)
print(json.dumps(dict(worst=res['worst'], registration={k: v for k, v in res['registration'].items() if not isinstance(v, dict)},
                      lines_over_ground_max_pct=max(ov.values()) if ov else None, lot_diff_max=max(lots.values()) if lots else None), indent=1))
