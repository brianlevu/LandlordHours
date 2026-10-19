"""Contact sheet of tool renders on the three QA grounds + the plaster tile.
usage: tool_sheet.py <dir_with_tool_*__{variant}.png> <out.png> [cell]"""
import sys, os, glob
from PIL import Image, ImageDraw
d, out = sys.argv[1], sys.argv[2]
cell = int(sys.argv[3]) if len(sys.argv) > 3 else 256
names = ['repairs', 'showing', 'comms', 'bookkeeping', 'travel', 'inspection', 'renovation', 'cleaning', 'legal', 'supplies', 'management']
rows = [('light', '#FFFFFF'), ('light', '#F4EFE6'), ('light', '#1E3FA6'), ('dark', '#0B1230'), ('dark', '#1E3FA6')]
S = Image.new('RGB', (cell * len(names), cell * len(rows)), '#888')
for r, (v, bg) in enumerate(rows):
    for c, n in enumerate(names):
        p = os.path.join(d, f'tool_{n}__{v}.png')
        if not os.path.exists(p): continue
        im = Image.open(p).convert('RGBa').resize((cell, cell), Image.LANCZOS).convert('RGBA')
        base = Image.new('RGBA', (cell, cell), bg)
        S.paste(Image.alpha_composite(base, im).convert('RGB'), (c * cell, r * cell))
S.save(out); print(out, S.size)
