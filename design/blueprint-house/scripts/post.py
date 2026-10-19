"""WP-A post-processing and asset-catalog export for the Blueprint art.

usage: python post.py --renders <dir> --catalog <Assets.xcassets/Blueprint> --masters <dir> [--only house,tools,anim]

House keyframes (render.py --states keyframes, 1920 px):
  built  : alpha veil cleaned, shadow limited, lit-window bloom baked in for the finished keyframe,
           Any = light lighting, Dark = dark lighting.
  lines  : rendered once in cyan, re-inked to the exact brand tokens: Any #8FD3FF, Dark #60A8E6.
  -> 960 px @3x and 640 px @2x (320 pt hero).
Tools (tools.py, 1024 px): 36 pt and 56 pt @2x/@3x, Any/Dark; plus 1024 masters.
Confirm animation (render.py --anim --row-only, overlay frames registered to the k15 keyframe): 960/640 px.
Every resize happens on premultiplied alpha (no dark or light fringes), then pngquant.
"""
import argparse, glob, json, os, shutil, subprocess, sys
import numpy as np
from PIL import Image, ImageFilter
sys.path.insert(0, os.path.dirname(__file__))
from clean_alpha import clean, limit_shadow
import render as R   # only for KEYFRAMES (bpy import is fine in the venv)

LINE_INK = {'any': (0x8F, 0xD3, 0xFF), 'dark': (0x60, 0xA8, 0xE6)}
GLOW = np.array([255, 205, 120], np.float32) / 255.0
HERO_PT = 320
BUILT_Q = '65-90'
LINES_Q = '50-85'
TOOL_PT = (36, 56)
PNGQUANT = shutil.which('pngquant')

def premul_resize(im, size):
    im = im.convert('RGBA')
    if im.size == (size, size):
        return im
    return im.convert('RGBa').resize((size, size), Image.LANCZOS).convert('RGBA')

def quantize(path, quality='82-98'):
    if not PNGQUANT:
        return
    subprocess.run([PNGQUANT, '--force', '--skip-if-larger', '--speed', '1', '--strip', '--quality', quality,
                    '--output', path, path], check=False)

def save(im, path, q=True, quality='82-98'):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, optimize=True)
    if q:
        quantize(path, quality)

def bloom(built_path, glow_path, strength):
    """Lit windows: soft warm bloom from the window mask, added inside the house silhouette only."""
    im = np.asarray(Image.open(built_path).convert('RGBA')).astype(np.float32) / 255.0
    g = np.asarray(Image.open(glow_path).convert('RGBA')).astype(np.float32) / 255.0
    mask = g[..., 3] * g[..., :3].mean(-1)
    m = Image.fromarray((mask * 255).astype(np.uint8))
    w = im.shape[1]
    b1 = np.asarray(m.filter(ImageFilter.GaussianBlur(w * 0.004))).astype(np.float32) / 255.0
    b2 = np.asarray(m.filter(ImageFilter.GaussianBlur(w * 0.014))).astype(np.float32) / 255.0
    halo = np.clip(0.55 * b1 + 0.75 * b2, 0, 1) * strength
    core = mask[..., None]
    rgb = im[..., :3]
    # windows themselves: lift toward warm light
    rgb = rgb * (1 - 0.55 * core) + (np.array([1.0, 0.9, 0.62]) * 0.55) * core
    # bloom: screen blend, only where the house is opaque (no glow spills onto the transparent canvas)
    add = halo[..., None] * GLOW
    rgb = 1 - (1 - rgb) * (1 - add)
    im[..., :3] = rgb
    return Image.fromarray((np.clip(im, 0, 1) * 255).round().astype(np.uint8), 'RGBA')

def reink(path, rgb):
    a = np.asarray(Image.open(path).convert('RGBA'))
    out = np.zeros_like(a)
    out[..., 0], out[..., 1], out[..., 2] = rgb
    out[..., 3] = a[..., 3]
    return Image.fromarray(out, 'RGBA')

# ------------------------------------------------------------------ catalog

def contents(images):
    return {'images': images, 'info': {'author': 'xcode', 'version': 1}}

def write_imageset(catalog, group, name, variants, quality='82-98', template=False):
    """variants: dict appearance('any'|'dark') -> {scale: PIL image}"""
    d = os.path.join(catalog, group, name + '.imageset')
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d)
    imgs = []
    for app, scales in variants.items():
        for sc, im in scales.items():
            fn = f'{name}{"-dark" if app == "dark" else ""}@{sc}x.png'
            save(im, os.path.join(d, fn), quality=quality)
            e = {'idiom': 'universal', 'filename': fn, 'scale': f'{sc}x'}
            if app == 'dark':
                e['appearances'] = [{'appearance': 'luminosity', 'value': 'dark'}]
            imgs.append(e)
    c = contents(imgs)
    if template:
        c['properties'] = {'template-rendering-intent': 'template'}
    with open(os.path.join(d, 'Contents.json'), 'w') as f:
        json.dump(c, f, indent=2)

def write_colorset(catalog, group, name, any_hex, dark_hex):
    d = os.path.join(catalog, group, name + '.colorset'); os.makedirs(d, exist_ok=True)
    def comp_(h):
        h = h.lstrip('#')
        return {'color-space': 'srgb', 'components': {'red': '0x' + h[0:2], 'green': '0x' + h[2:4], 'blue': '0x' + h[4:6], 'alpha': '1.000'}}
    c = {'colors': [{'idiom': 'universal', 'color': comp_(any_hex)},
                    {'idiom': 'universal', 'color': comp_(dark_hex), 'appearances': [{'appearance': 'luminosity', 'value': 'dark'}]}],
         'info': {'author': 'xcode', 'version': 1}}
    with open(os.path.join(d, 'Contents.json'), 'w') as f:
        json.dump(c, f, indent=2)

def write_group(catalog, group):
    os.makedirs(os.path.join(catalog, group), exist_ok=True)
    with open(os.path.join(catalog, group, 'Contents.json'), 'w') as f:
        json.dump({'info': {'author': 'xcode', 'version': 1}}, f, indent=2)

# ------------------------------------------------------------------ steps

def do_house(rd, catalog, masters):
    stage = masters; os.makedirs(stage, exist_ok=True)   # 1920 px intermediates (scratch, not committed)
    manifest = []
    for k, st in R.KEYFRAMES:
        variants_b, variants_l = {}, {}
        for v, app in (('light', 'any'), ('dark', 'dark')):
            src = os.path.join(rd, f'{k}__built__{v}.png')
            tmp = os.path.join(stage, f'{k}__built__{v}.png')
            shutil.copy(src, tmp); clean(tmp); limit_shadow(tmp, reach=84, feather=56)
            im = Image.open(tmp).convert('RGBA')
            glow = os.path.join(rd, f'{k}__glow.png')
            if st['stage'] >= 5 and os.path.exists(glow):
                im = bloom(tmp, glow, 0.55 if v == 'light' else 0.8)
                im.save(tmp)
            variants_b[app] = {3: premul_resize(im, HERO_PT * 3), 2: premul_resize(im, HERO_PT * 2)}
        # linework: one alpha-only template image, tinted by the bp_drafting colour (Any #8FD3FF, Dark #60A8E6)
        li = reink(os.path.join(rd, f'{k}__lines.png'), (255, 255, 255))
        mk = os.path.join(rd, f'{k}__mask.png')
        if os.path.exists(mk):
            # cut the built structure out of the linework: lines are drawn ABOVE built, over the ground only
            la = np.asarray(li).astype(np.float32)
            ma = np.asarray(Image.open(mk).convert('RGBA'))[..., 3].astype(np.float32) / 255.0
            la[..., 3] *= (1.0 - ma)
            li = Image.fromarray(la.round().astype(np.uint8), 'RGBA')
        variants_l['any'] = {3: premul_resize(li, HERO_PT * 3), 2: premul_resize(li, HERO_PT * 2)}
        write_imageset(catalog, 'House', f'bp_house_{k}_built', variants_b, quality=BUILT_Q)
        write_imageset(catalog, 'House', f'bp_house_{k}_lines', variants_l, quality=LINES_Q, template=True)
        manifest.append(dict(key=k, state=st, built=f'bp_house_{k}_built', lines=f'bp_house_{k}_lines'))
        print('house', k, flush=True)
    return manifest

def do_tools(rd, catalog, masters):
    import tools as T
    md = os.path.join(masters, 'tools'); os.makedirs(md, exist_ok=True)
    out = []
    for t in T.TOOLS:
        ims = {}
        for v, app in (('light', 'any'), ('dark', 'dark')):
            p = os.path.join(rd, f'tool_{t}__{v}.png')
            tmp = os.path.join(md, f'bp_tool_{t}{"-dark" if app == "dark" else ""}_1024.png')
            im = Image.open(p).convert('RGBA')
            a = np.asarray(im).copy(); a[..., 3] = np.where(a[..., 3] < 3, 0, a[..., 3]); im = Image.fromarray(a, 'RGBA')
            save(im, tmp, quality='85-98')
            ims[app] = im
        for pt in TOOL_PT:
            write_imageset(catalog, 'Tools', f'bp_tool_{t}_{pt}',
                           {app: {3: premul_resize(im, pt * 3), 2: premul_resize(im, pt * 2)} for app, im in ims.items()})
        out.append(dict(category=t, label=T.LABELS[t], images=[f'bp_tool_{t}_{pt}' for pt in TOOL_PT]))
        print('tool', t, flush=True)
    return out

def do_anim(rd, catalog, masters, base_key='k14_siding040'):
    frames = {}
    for v, app in (('light', 'any'), ('dark', 'dark')):
        d = os.path.join(rd, f'anim_confirm_row_overlay__{v}')
        frames[app] = sorted(glob.glob(os.path.join(d, 'frame_*.png')))
    n = len(frames['any'])
    for i in range(n):
        var = {}
        for app in ('any', 'dark'):
            im = Image.open(frames[app][i]).convert('RGBA')
            a = np.asarray(im).copy(); a[..., 3] = np.where(a[..., 3] < 3, 0, a[..., 3]); im = Image.fromarray(a, 'RGBA')
            var[app] = {3: premul_resize(im, HERO_PT * 3), 2: premul_resize(im, HERO_PT * 2)}
        write_imageset(catalog, 'ConfirmRow', f'bp_confirm_row_{i:02d}', var)
    print('anim frames', n, flush=True)
    return dict(frames=[f'bp_confirm_row_{i:02d}' for i in range(n)], fps=30, base=f'bp_house_{base_key}_built',
                note='Overlay frames, registered to the hero canvas: draw over the base keyframe built pass.')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--renders', required=True)
    ap.add_argument('--tool-renders', default='')
    ap.add_argument('--catalog', required=True)
    ap.add_argument('--masters', required=True)
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--only', default='house,tools,anim')
    ap.add_argument('--house-stage', default='/tmp/bp_house_stage')
    a = ap.parse_args()
    cat = os.path.abspath(a.catalog)
    os.makedirs(cat, exist_ok=True)
    with open(os.path.join(cat, 'Contents.json'), 'w') as f:
        json.dump({'info': {'author': 'xcode', 'version': 1}}, f, indent=2)
    man = json.load(open(a.manifest)) if os.path.exists(a.manifest) else {}
    only = a.only.split(',')
    if 'house' in only:
        write_group(cat, 'House'); man['house'] = do_house(a.renders, cat, a.house_stage)
        write_colorset(cat, 'House', 'bp_drafting', '#8FD3FF', '#60A8E6')
        man['house_notes'] = ('Draw lines ABOVE built (the built structure is already cut out of them, so they show over the ground and never over built parts). Each keyframe pair shares one camera (320 pt square). '
                              'Built: Any = light-theme lighting, Dark = dark-theme lighting. Lines are template images '
                              '(alpha only): tint with Color("bp_drafting") = Any #8FD3FF, Dark #60A8E6. On the theme-fixed '
                              'blueprint hero use #8FD3FF in both modes if the hero does not step down.')
    if 'tools' in only:
        write_group(cat, 'Tools'); man['tools'] = do_tools(a.tool_renders or a.renders, cat, a.masters)
    if 'anim' in only:
        write_group(cat, 'ConfirmRow'); man['confirm_row'] = do_anim(a.renders, cat, a.masters)
    with open(a.manifest, 'w') as f:
        json.dump(man, f, indent=1)

if __name__ == '__main__':
    main()
