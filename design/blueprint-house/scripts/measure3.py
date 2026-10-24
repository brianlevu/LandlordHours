"""Repeat the dir-craft2 verdict's measurements on Craft stills (camera unchanged, so probes fit every pass).

usage: python3 measure3.py --probes probes.json --light craft_complete_light.png --dark craft_complete_dark.png [--overlay out.png]
Prints JSON: siding V (night), lawn hue/S/V under the lit windows vs unlit lawn, night vs day lawn S, visible hue count.
Probes come from `craft3.py --probes` (world points projected through the Craft camera).
"""
import argparse, colorsys, json
import numpy as np
from PIL import Image, ImageDraw

def load(p):
    return np.asarray(Image.open(p).convert('RGBA')).astype(np.float32) / 255.0

def hsv_at(im, pts, r=6):
    out = []
    for x, y in pts:
        x, y = int(round(x)), int(round(y))
        patch = im[y - r:y + r + 1, x - r:x + r + 1]
        patch = patch[patch[..., 3] > 0.98]
        if len(patch): out.append(patch[:, :3])
    if not out: return None
    rgb = np.concatenate(out).mean(0)
    rgb = [float(c) for c in rgb]; h, s, v = colorsys.rgb_to_hsv(*rgb)
    return dict(hue=round(h * 360), S=round(s, 2), V=round(v, 2), hex='#%02X%02X%02X' % tuple(int(c * 255) for c in rgb))

def lawn_s(im, pts):
    vals = []
    for x, y in pts:
        x, y = int(round(x)), int(round(y))
        if not (0 <= x < im.shape[1] and 0 <= y < im.shape[0]): continue
        p = im[y, x]
        if p[3] < 0.98: continue
        h, s, v = colorsys.rgb_to_hsv(*[float(c) for c in p[:3]])
        if 40 / 360 < h < 170 / 360 or s < 0.12:      # lawn (green or near-neutral), not roof/path/timber
            vals.append((h * 360, s, v))
    a = np.array(vals)
    return dict(n=len(a), hue_med=round(float(np.median(a[:, 0]))), S_med=round(float(np.median(a[:, 1])), 2),
                V_med=round(float(np.median(a[:, 2])), 2))

def hue_count(im, smin=0.25, vmin=0.2, share=0.03):
    """Visible hue families: opaque pixels with S>=smin, V>=vmin, binned into 12 x 30 deg; bins >= `share` count."""
    px = im[im[..., 3] > 0.98][:, :3]
    mx = px.max(1); mn = px.min(1); s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    keep = (s >= smin) & (mx >= vmin); q = px[keep]
    hs = np.array([colorsys.rgb_to_hsv(*c)[0] * 360 for c in q[::7]])
    bins = np.bincount(((hs + 15) % 360 // 30).astype(int), minlength=12) / max(len(hs), 1)
    names = ['red', 'orange', 'yellow', 'yellow-green', 'green', 'green-cyan', 'cyan', 'azure', 'blue', 'violet', 'magenta', 'rose']
    fam = {names[i]: round(float(b), 3) for i, b in enumerate(bins) if b >= 0.01}
    b15 = np.bincount(((hs + 7.5) % 360 // 15).astype(int), minlength=24) / max(len(hs), 1)
    return dict(saturated_share=round(float(keep.mean()), 3), mean_S_saturated=round(float(s[keep].mean()), 2),
                bins=fam, count=int((bins >= share).sum()), count15=int((b15 >= share).sum()),
                red_orange=round(float(bins[0] + bins[1]), 2), green=round(float(bins[3] + bins[4] + bins[5]), 2),
                blue=round(float(bins[6] + bins[7] + bins[8]), 2))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--probes', required=True); ap.add_argument('--light', required=True); ap.add_argument('--dark', required=True)
    ap.add_argument('--overlay', default='')
    a = ap.parse_args()
    P = json.load(open(a.probes)); L = load(a.light); D = load(a.dark)
    res = dict(
        night_siding_left=hsv_at(D, P['siding_left']), night_siding_front=hsv_at(D, P['siding_front']),
        day_siding_left=hsv_at(L, P['siding_left']),
        night_lawn_spill_frontleft=hsv_at(D, P['lawn_spill_frontleft']), night_lawn_spill_porch=hsv_at(D, P['lawn_spill_porch']),
        night_lawn_unlit=hsv_at(D, P['lawn_dark']),
        day_lawn_spill_frontleft=hsv_at(L, P['lawn_spill_frontleft']),
        lawn_light=lawn_s(L, P['lawn_grid']), lawn_dark=lawn_s(D, P['lawn_grid']),
        hues_light=hue_count(L), hues_dark=hue_count(D),
    )
    print(json.dumps(res, indent=1))
    if a.overlay:
        im = Image.open(a.dark).convert('RGBA'); bg = Image.new('RGBA', im.size, (11, 18, 48, 255)); bg.alpha_composite(im)
        d = ImageDraw.Draw(bg)
        for k, col in (('siding_left', 'cyan'), ('siding_front', 'cyan'), ('lawn_spill_frontleft', 'yellow'),
                       ('lawn_spill_porch', 'orange'), ('lawn_dark', 'magenta')):
            for x, y in P[k]: d.rectangle([x - 6, y - 6, x + 6, y + 6], outline=col, width=2)
        for x, y in P['lawn_grid']: d.point((x, y), fill='white')
        bg.convert('RGB').save(a.overlay)

if __name__ == '__main__':
    main()
