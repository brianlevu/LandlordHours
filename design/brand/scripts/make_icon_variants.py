"""Build the iOS 18+ appearance variants of app icon B (WP-D, 2026-10-19).

usage: python3 make_icon_variants.py <out_dir>
Writes icon-b-dark-1024.png and icon-b-tinted-1024.png next to icon-b-1024.png (the approved
default, unchanged). Reuses make_icons.draw_b / centred_mark so the geometry is identical.

- dark: the full-colour mark on a transparent canvas; iOS supplies the dark backdrop (HIG: dark
  icons use a transparent background).
- tinted: an opaque grayscale image on black; iOS applies the user's tint by luminance. Built parts
  are the brightest (plaster white, roof and door slightly lower), the drawn linework is mid-grey so
  the half-drawn / half-built split survives tinting.
"""
import os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_icons as mi  # noqa: E402

def dark(out):
    im, _ = mi.centred_mark(mi.draw_b, (0, 0, 0, 0), show_grid=False)
    mi.down(im).save(os.path.join(out, 'icon-b-dark-1024.png'))

def tinted(out):
    saved = (mi.PLASTER, mi.TERRA, mi.TIMBER, mi.CYAN)
    mi.PLASTER, mi.TERRA, mi.TIMBER, mi.CYAN = '#FFFFFF', '#D6D6D6', '#BDBDBD', '#8C8C8C'
    try:
        im, _ = mi.centred_mark(mi.draw_b, (0, 0, 0, 255), show_grid=False)
    finally:
        mi.PLASTER, mi.TERRA, mi.TIMBER, mi.CYAN = saved
    mi.down(im).convert('L').convert('RGB').save(os.path.join(out, 'icon-b-tinted-1024.png'))

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else mi.ICON
    os.makedirs(out, exist_ok=True)
    dark(out); tinted(out)
    print('variants written to', out)
