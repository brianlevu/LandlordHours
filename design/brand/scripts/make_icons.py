"""Draw the vector logo/icon options with PIL (4x supersampled), compose the 3D option from the
Blender renders, and build small-size + home-screen previews.

usage: python3 make_icons.py all | b | c | a | previews
Writes into ../icon and ../logo. Pure PIL; no external raster tools.
"""
import os, sys, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
ICON = os.path.join(ROOT, 'icon'); LOGO = os.path.join(ROOT, 'logo'); REN = os.path.join(ROOT, 'renders')
os.makedirs(ICON, exist_ok=True); os.makedirs(LOGO, exist_ok=True)

BLUE = '#1E3FA6'; CYAN = '#8FD3FF'; PLASTER = '#F4EFE6'; TERRA = '#C8553D'; TIMBER = '#E0A458'; INK = '#121B33'
S = 4  # supersample

def canvas(bg, size=1024):
    im = Image.new('RGBA', (size * S, size * S), bg)
    return im, ImageDraw.Draw(im)

def P(pts):
    return [(x * S, y * S) for x, y in pts]

def down(im, size=1024):
    return im.resize((size, size), Image.LANCZOS)

def grid_layer(size=1024, step=64, alpha=16, r_in=360, r_out=440, ss=1):
    """faint drafting grid as an RGBA layer, faded to nothing before the squircle corners.
    Always alpha-composited (ImageDraw writes RGBA values straight into the pixels, which is how a
    (255,255,255,14) edge line became pure white once alpha was dropped)."""
    W = size * ss
    layer = Image.new('RGBA', (W, W), (0, 0, 0, 0)); ld = ImageDraw.Draw(layer)
    for i in range(step, size, step):          # interior lines only: never on the canvas edge
        ld.line([(i * ss, 0), (i * ss, W)], fill=(255, 255, 255, alpha), width=ss)
        ld.line([(0, i * ss), (W, i * ss)], fill=(255, 255, 255, alpha), width=ss)
    mask = Image.new('L', (size, size), 0); md = ImageDraw.Draw(mask)
    steps = 24
    for k in range(steps, -1, -1):
        r = r_in + (r_out - r_in) * k / steps
        md.ellipse([size / 2 - r, size / 2 - r, size / 2 + r, size / 2 + r], fill=int(255 * (1 - k / steps)))
    mask = mask.resize((W, W), Image.LANCZOS)
    a = Image.composite(layer.split()[3], Image.new('L', (W, W), 0), mask); layer.putalpha(a)
    return layer

def grid(d, size=1024, step=64, color=None):
    im = d._image
    im.alpha_composite(grid_layer(size, step, ss=S))

# ---------------------------------------------------------------- option B: half drawn, half built
def draw_b(d, mono=False, line_w=26, show_grid=True):
    """House elevation. Foundation, left wall, left roof slope and door are built (plaster / terracotta / timber);
    the right roof slope, the upper right wall and the window are still drawn in cyan linework.
    The built part rises from the bottom-left, the way the hero's built mask rises with hours."""
    c_plaster = '#FFFFFF' if mono else PLASTER
    c_terra = '#FFFFFF' if mono else TERRA
    c_timber = '#FFFFFF' if mono else TIMBER
    c_line = '#FFFFFF' if mono else CYAN
    if show_grid and not mono:
        grid(d)
    w = line_w * S
    def dot(pt, r):
        d.ellipse(P([(pt[0] - r, pt[1] - r), (pt[0] + r, pt[1] + r)]), fill=c_line)
    # drawn first (built parts sit on top of the linework, as in the hero)
    d.line(P([(512, 232), (836, 486)]), fill=c_line, width=w); dot((836, 486), line_w / 2)     # right roof slope
    d.line(P([(770, 436), (770, 700)]), fill=c_line, width=w); dot((770, 436), line_w / 2)      # right wall edge, down to the built course
    d.rounded_rectangle(P([(588, 540), (708, 636)]), radius=12 * S, outline=c_line, width=w)   # window, drawn
    # built
    d.rounded_rectangle(P([(222, 808), (802, 848)]), radius=10 * S, fill=c_plaster)            # slab (100h: foundation is always built)
    d.rectangle(P([(250, 470), (512, 812)]), fill=c_plaster)                                   # left wall
    d.rectangle(P([(512, 690), (770, 812)]), fill=c_plaster)                                   # right wall, built to the course
    ROOF = 66
    d.line(P([(512, 232), (188, 486)]), fill=c_terra, width=ROOF * S)                          # left roof slope, solid
    for pt in ((512, 232), (188, 486)):
        d.ellipse(P([(pt[0] - ROOF / 2, pt[1] - ROOF / 2), (pt[0] + ROOF / 2, pt[1] + ROOF / 2)]), fill=c_terra)
    d.rounded_rectangle(P([(382, 636), (476, 812)]), radius=46 * S, fill=c_timber)             # door
    d.rectangle(P([(382, 700), (476, 812)]), fill=c_timber)

def centred_mark(draw_fn, bg, mono=False, show_grid=True):
    """Draw the mark on a transparent layer, measure its bbox, and paste it so the bbox centre is the canvas centre."""
    layer, ld = canvas((0, 0, 0, 0)); draw_fn(ld, mono=mono, show_grid=False)
    bb = layer.getbbox(); cx = (bb[0] + bb[2]) / 2; cy = (bb[1] + bb[3]) / 2
    dx = int(round(512 * S - cx)); dy = int(round(512 * S - cy))
    im, d = canvas(bg)
    if show_grid and bg != (0, 0, 0, 0):
        grid(d)
    im.alpha_composite(layer, (max(dx, 0), max(dy, 0))) if (dx >= 0 and dy >= 0) else im.alpha_composite(layer.crop((-min(dx, 0), -min(dy, 0), layer.width, layer.height)), (max(dx, 0), max(dy, 0)))
    print(f'  centred: bbox {tuple(v // S for v in bb)} offset ({dx // S}, {dy // S}) px at 1024')
    return im, (dx / S, dy / S)

def icon_b():
    im, off = centred_mark(draw_b, BLUE)
    down(im).convert('RGB').save(os.path.join(ICON, 'icon-b-1024.png'))
    im, _ = centred_mark(draw_b, (0, 0, 0, 0), mono=True); down(im).save(os.path.join(LOGO, 'mark-b-mono-1024.png'))
    im, _ = centred_mark(draw_b, (0, 0, 0, 0)); down(im).save(os.path.join(LOGO, 'mark-b-colour-1024.png'))
    with open(os.path.join(LOGO, 'mark-b-offset.txt'), 'w') as f:
        f.write(f'translate({off[0]:.1f} {off[1]:.1f})  # apply to the SVG geometry so the mark is optically centred\n')
    print('icon-b written')

# ---------------------------------------------------------------- option C: LH monogram
def draw_c(d, mono=False, line_w=26, show_grid=True):
    """LH monogram. L and the H's crossbar are built (plaster); the H's right stud is still drafted (cyan)."""
    c_fill = '#FFFFFF' if mono else PLASTER
    c_line = '#FFFFFF' if mono else CYAN
    if show_grid and not mono:
        grid(d)
    w = line_w * S
    d.rounded_rectangle(P([(648, 240), (744, 784)]), radius=20 * S, outline=c_line, width=w)   # drafted right stud
    d.rounded_rectangle(P([(280, 240), (376, 784)]), radius=20 * S, fill=c_fill)               # L stem = H left stud
    d.rounded_rectangle(P([(280, 688), (588, 784)]), radius=20 * S, fill=c_fill)               # L foot
    d.rounded_rectangle(P([(376, 464), (662, 560)]), radius=14 * S, fill=c_fill)               # H crossbar, built, meets the drafted stud

def icon_c():
    im, _ = centred_mark(draw_c, BLUE)
    down(im).convert('RGB').save(os.path.join(ICON, 'icon-c-1024.png'))
    im, _ = centred_mark(draw_c, (0, 0, 0, 0), mono=True); down(im).save(os.path.join(LOGO, 'mark-c-mono-1024.png'))
    print('icon-c written')

# ---------------------------------------------------------------- option A: Blender house
def icon_a(state='finished', lines=None, name='icon-a-1024.png', fill=1.0):
    built = os.path.join(REN, f'icon_{state}__built.png')
    base = Image.new('RGBA', (1024, 1024), BLUE)
    base.alpha_composite(grid_layer(1024))
    if lines:
        l = Image.open(os.path.join(REN, f'icon_{lines}__lines.png')).convert('RGBA').resize((1024, 1024), Image.LANCZOS)
        base = Image.alpha_composite(base, l)
    b = Image.open(built).convert('RGBA').resize((1024, 1024), Image.LANCZOS)
    if fill != 1.0:
        n = int(1024 * fill); b = b.resize((n, n), Image.LANCZOS)
        pad = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0)); pad.paste(b, ((1024 - n) // 2, (1024 - n) // 2)); b = pad
    base = Image.alpha_composite(base, b)
    base.convert('RGB').save(os.path.join(ICON, name)); print(name, 'written')

# ---------------------------------------------------------------- previews
def squircle_mask(size):
    """continuous-curvature approximation: superellipse n=5"""
    m = Image.new('L', (size * S, size * S), 0)
    d = ImageDraw.Draw(m)
    n = 5.0; r = size * S / 2
    pts = []
    for i in range(720):
        t = i / 720 * 2 * math.pi
        ct, st = math.cos(t), math.sin(t)
        x = r + r * math.copysign(abs(ct) ** (2 / n), ct)
        y = r + r * math.copysign(abs(st) ** (2 / n), st)
        pts.append((x, y))
    d.polygon(pts, fill=255)
    return m.resize((size, size), Image.LANCZOS)

def rounded_icon(path, size):
    im = Image.open(path).convert('RGBA').resize((size * S, size * S), Image.LANCZOS).resize((size, size), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0)); out.paste(im, (0, 0), squircle_mask(size)); return out

def font(size, mono=False, rounded=False):
    for fp in ([ '/System/Library/Fonts/SFNSMono.ttf'] if mono else ['/System/Library/Fonts/SFNSRounded.ttf'] if rounded else ['/System/Library/Fonts/SFNS.ttf', '/System/Library/Fonts/Helvetica.ttc']):
        if os.path.exists(fp):
            return ImageFont.truetype(fp, size)
    return ImageFont.load_default()

def size_strip(paths, out, label):
    """1024 icon at 180 / 120 / 60 / 29 px on light and dark."""
    sizes = [180, 120, 60, 40, 29]
    cell = 220; W = cell * len(sizes) + 40; rowh = 260
    img = Image.new('RGB', (W, rowh * 2 * len(paths)), '#EEF2FA')
    d = ImageDraw.Draw(img); f = font(16); fm = font(13, mono=True)
    y = 0
    for name, p in paths:
        for bg, txt in (('#EEF2FA', '#121B33'), ('#0B1230', '#F2F4FA')):
            d.rectangle([0, y, W, y + rowh], fill=bg)
            d.text((20, y + 12), f'{name}', fill=txt, font=f)
            for i, s in enumerate(sizes):
                ic = rounded_icon(p, s)
                x = 20 + i * cell + (cell - s) // 2
                img.paste(ic, (x, y + 40 + (180 - s) // 2), ic)
                d.text((20 + i * cell + cell // 2 - 14, y + 232), f'{s}px', fill=txt, font=fm)
            y += rowh
    img.save(out); print(out)

def wallpaper(W, H, kind):
    img = Image.new('RGB', (W, H))
    if kind == 'black':
        return img
    if kind == 'photo':
        # busy, warm, photo-like: the finished house render blown up and blurred over a sunset gradient
        top, bot = (236, 150, 90), (70, 60, 120)
        for yy in range(H):
            t = yy / H; img.paste(tuple(int(top[k] + (bot[k] - top[k]) * t) for k in range(3)), [0, yy, W, yy + 1])
        ph = os.path.join(ROOT, 'img', 'house-finished-dark.png')
        if os.path.exists(ph):
            h = Image.open(ph).convert('RGBA').resize((int(W * 1.6), int(W * 1.6)), Image.LANCZOS).filter(ImageFilter.GaussianBlur(6))
            img.paste(h, (-int(W * 0.3), -int(W * 0.2)), h)
        return img
    dark = kind == 'dark'
    top = (12, 18, 48) if dark else (232, 236, 246); bot = (30, 45, 110) if dark else (200, 212, 236)
    for yy in range(H):
        t = yy / H
        img.paste(tuple(int(top[k] + (bot[k] - top[k]) * t) for k in range(3)), [0, yy, W, yy + 1])
    return img

def home_screen(path, out, dark):
    """A 3x home-screen crop: four rows of 60pt icons, the candidate among neutral placeholders.
    dark: False (light), True (dark), 'black' (true black), 'photo' (busy photo-like)."""
    W, H = 1179, 1400
    kind = dark if isinstance(dark, str) else ('dark' if dark else 'light')
    img = wallpaper(W, H, kind); dark = kind != 'light'
    d = ImageDraw.Draw(img); f = font(33)
    cols = 4; icon = 180; gapx = (W - cols * icon) // (cols + 1); gapy = 100
    labels = ['Calendar', 'Notes', 'LandlordHours', 'Files', 'Mail', 'Maps', 'Wallet', 'Photos', 'Home', 'Weather', 'Clock', 'Settings']
    neutral = [(255, 255, 255), (242, 243, 247), (225, 228, 236), (205, 210, 222)] if not dark else [(44, 48, 66), (58, 62, 84), (72, 78, 104), (90, 96, 124)]
    k = 0
    for r in range(3):
        for c in range(cols):
            x = gapx + c * (icon + gapx); y = 120 + r * (icon + gapy + 40)
            if labels[k] == 'LandlordHours':
                ic = rounded_icon(path, icon); img.paste(ic, (x, y), ic)
            else:
                ph = Image.new('RGBA', (icon, icon), neutral[k % 4] + (255,))
                pd = ImageDraw.Draw(ph); pd.ellipse([icon * 0.3, icon * 0.3, icon * 0.7, icon * 0.7], fill=neutral[(k + 2) % 4] + (255,))
                m = squircle_mask(icon); o = Image.new('RGBA', (icon, icon), (0, 0, 0, 0)); o.paste(ph, (0, 0), m); img.paste(o, (x, y), o)
            tw = d.textlength(labels[k], font=f)
            d.text((x + icon / 2 - tw / 2, y + icon + 14), labels[k], fill=(255, 255, 255) if dark else (20, 24, 40), font=f)
            k += 1
    img.save(out); print(out)

def previews():
    cands = [(n, os.path.join(ICON, fn)) for n, fn in (('A · 3D house (finished)', 'icon-a-1024.png'), ('A2 · 3D house (roof on, siding drawn)', 'icon-a2-1024.png'),
                                                        ('B · half drawn, half built', 'icon-b-1024.png'), ('C · LH monogram', 'icon-c-1024.png')) if os.path.exists(os.path.join(ICON, fn))]
    size_strip(cands, os.path.join(ICON, 'preview-sizes.png'), 'sizes')
    for n, p in cands:
        key = p.split('icon-')[1].split('-')[0]
        home_screen(p, os.path.join(ICON, f'preview-home-{key}-light.png'), False)
        home_screen(p, os.path.join(ICON, f'preview-home-{key}-dark.png'), True)
        if key == 'b':
            home_screen(p, os.path.join(ICON, f'preview-home-{key}-black.png'), 'black')
            home_screen(p, os.path.join(ICON, f'preview-home-{key}-photo.png'), 'photo')

if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if what in ('b', 'all'): icon_b()
    if what in ('c', 'all'): icon_c()
    if what in ('a', 'all'):
        icon_a('finished_ns', None, 'icon-a-1024.png')
        icon_a('siding60_ns', 'siding60_ns', 'icon-a2-1024.png')
    if what in ('previews', 'all'): previews()
