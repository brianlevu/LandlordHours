"""Per-screen compare sheet: baseline r4 | Waypoint | Clayhouse | Inkwell, light row + dark row."""
import os
from PIL import Image, ImageDraw, ImageFont

BASE = '/Users/brian/AgentScratch/landlordhours/2026-10-18'
R4 = f'{BASE}/hifi-frames-r4'
CF = f'{BASE}/creative/frames'
OUT = f'{BASE}/creative/frames/compare'
os.makedirs(OUT, exist_ok=True)
COLS = [('Baseline r4', R4), ('Waypoint', f'{CF}/waypoint'), ('Clayhouse', f'{CF}/clayhouse'), ('Inkwell', f'{CF}/inkwell')]
SCREENS = ['today-onpace', 'today-onpace-scrolled', 'inbox', 'records', 'onb-welcome', 'empty-today']
H = 1100
try:
    font = ImageFont.truetype('/System/Library/Fonts/SFNS.ttf', 34)
except Exception:
    font = ImageFont.load_default()

for s in SCREENS:
    rows = []
    for ap in ['light', 'dark']:
        ims = []
        for _, d in COLS:
            im = Image.open(f'{d}/{s}-{ap}.png').convert('RGB')
            ims.append(im.resize((int(im.width * H / im.height), H)))
        rows.append(ims)
    w = rows[0][0].width
    W = 40 + 4 * (w + 40)
    m = Image.new('RGB', (W, 90 + 2 * (H + 40)), (236, 236, 240))
    d = ImageDraw.Draw(m)
    for i, (label, _) in enumerate(COLS):
        d.text((40 + i * (w + 40), 30), label, fill=(25, 25, 30), font=font)
    for r, ims in enumerate(rows):
        for i, im in enumerate(ims):
            m.paste(im, (40 + i * (w + 40), 90 + r * (H + 40)))
    m.save(f'{OUT}/{s}.jpg', quality=86)
print(sorted(os.listdir(OUT)))
