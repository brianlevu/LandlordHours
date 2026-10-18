"""Measure Blueprint confirm frames: plaster pixels in the hero house (must never drop) and the
visible height of the card CTA pill above the tab bar. usage: measure_confirm.py <frames_dir>"""
import glob, os, re, sys
import numpy as np
from PIL import Image

D = sys.argv[1]
for ap in ['light', 'dark']:
    fs = sorted(glob.glob(f'{D}/confirm-*s-{ap}.png'), key=lambda f: float(re.search(r'confirm-([\d.]+)s', f).group(1)))
    prev = None
    print(f'--- {ap}')
    for f in fs:
        a = np.asarray(Image.open(f).convert('RGB')).astype(int)
        H, W = a.shape[:2]
        # hero house region (right 60% of the hero card): plaster = warm cream
        hero = a[int(H * 0.20):int(H * 0.56), int(W * 0.40):int(W * 0.96)]
        r, g, b = hero[..., 0], hero[..., 1], hero[..., 2]
        # built material = warm pixels (plaster, timber, terracotta); blueprint paper and cyan lines are blue-dominant
        plaster = int(((r - b) > 25).sum())
        # CTA pill: rows where a wide run is the action-wash tint, above the bottom 12% (tab bar zone)
        if ap == 'light':
            pill = (np.abs(a[..., 0] - 233) < 10) & (np.abs(a[..., 1] - 231) < 10) & (a[..., 2] > 243)
        else:
            pill = (np.abs(a[..., 0] - 53) < 14) & (np.abs(a[..., 1] - 50) < 14) & (np.abs(a[..., 2] - 96) < 18)
        rows = np.where(pill.sum(axis=1) > W * 0.5)[0]
        rows = rows[(rows > H * 0.62) & (rows < H * 0.88)]   # the card CTA band, above the tab bar zone
        vis = len(rows) / 3
        t = re.search(r'confirm-([\d.]+)s', f).group(1)
        flag = '' if prev is None or plaster >= prev * 0.98 else '  <-- DROP'
        print(f'{t:>5}s plaster={plaster:6d}{flag}   CTA pill visible ≈ {vis:4.0f} pt')
        prev = plaster
