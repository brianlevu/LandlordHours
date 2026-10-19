"""Composite helpers: lines under built over a background colour; contact sheets.

usage:
  composite.py one <built.png> <lines.png|-> <bg hex> <out.png>
  composite.py sheet <renders_dir> <out_prefix>
"""
import sys, os, glob
from PIL import Image, ImageDraw, ImageFont

def comp(built, lines, bg, size=None):
    b = Image.open(built).convert('RGBA') if built else None
    l = Image.open(lines).convert('RGBA') if lines and os.path.exists(lines) else None
    ref = b or l
    base = Image.new('RGBA', ref.size, bg)
    if l: base = Image.alpha_composite(base, l)
    if b: base = Image.alpha_composite(base, b)
    if size: base = base.resize((size, size), Image.LANCZOS)
    return base.convert('RGB')

STATES = ['stage0_lot', 'stage1_slab', 'stage2_frame25', 'stage2_frame40', 'stage2_frame50', 'stage2_frame75', 'stage3_trusses',
          'stage3_roof', 'stage4_siding30', 'stage4_siding60', 'stage5_finished']

def sheet(d, prefix):
    cell = 480
    font = None
    for fp in ['/System/Library/Fonts/SFNS.ttf', '/System/Library/Fonts/Helvetica.ttc']:
        if os.path.exists(fp):
            font = ImageFont.truetype(fp, 22); break
    for bgname, bg, variant, txt in (('blue', '#1E3FA6', 'dark', '#FFFFFF'), ('light', '#EEF2FA', 'light', '#121B33')):
        states = [s for s in STATES if os.path.exists(os.path.join(d, f'{s}__built__{variant}.png'))]
        rows = [('built + linework', 'both'), ('built only', 'built'), ('linework only', 'lines')]
        W = cell * len(states); Hh = (cell + 40) * len(rows)
        img = Image.new('RGB', (W, Hh), bg)
        dr = ImageDraw.Draw(img)
        for ri, (label, mode) in enumerate(rows):
            for ci, s in enumerate(states):
                b = os.path.join(d, f'{s}__built__{variant}.png'); l = os.path.join(d, f'{s}__lines.png')
                im = comp(b if mode != 'lines' else None, l if mode != 'built' else None, bg, cell)
                img.paste(im, (ci * cell, ri * (cell + 40) + 40))
                dr.text((ci * cell + 12, ri * (cell + 40) + 8), f'{s.split("_",1)[1]} · {label}', fill=txt, font=font)
        img.save(f'{prefix}-{bgname}.png')
        print('sheet', f'{prefix}-{bgname}.png', img.size)

if __name__ == '__main__':
    if sys.argv[1] == 'one':
        _, _, b, l, bg, o = sys.argv
        comp(b, None if l == '-' else l, bg).save(o)
    elif sys.argv[1] == 'sheet':
        sheet(sys.argv[2], sys.argv[3])
