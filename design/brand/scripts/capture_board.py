"""Captures of the brand board for QA. Desktop: one full page. Phone: one PNG per <section> (Chrome caps a
single capture at 16384px, so a 17k-px full page silently repeats), light and dark.
usage: python3 capture_board.py http://127.0.0.1:8791/index.html ../qa
"""
import sys, os
from playwright.sync_api import sync_playwright
url, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
with sync_playwright() as p:
    b = p.chromium.launch(channel='chrome', headless=True)
    for theme in ('light', 'dark'):
        ctx = b.new_context(viewport={'width': 1180, 'height': 900}, device_scale_factor=1, color_scheme=theme)
        pg = ctx.new_page(); pg.goto(f'{url}?theme={theme}', wait_until='networkidle'); pg.wait_for_timeout(800)
        fn = os.path.join(out, f'desktop-{theme}.png'); pg.screenshot(path=fn, full_page=True)
        print(fn, 'height', pg.evaluate('document.documentElement.scrollHeight'), 'scrollWidth', pg.evaluate('document.documentElement.scrollWidth')); ctx.close()
        ctx = b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, color_scheme=theme)
        pg = ctx.new_page(); pg.goto(f'{url}?theme={theme}', wait_until='networkidle'); pg.wait_for_timeout(800)
        w = pg.evaluate('document.documentElement.scrollWidth')
        boxes = pg.evaluate('''() => { const r=[]; const hd=document.querySelector('header'); const dc=document.querySelector('.decisions');
            r.push(['00-header', 0, dc.getBoundingClientRect().bottom + window.scrollY]);
            document.querySelectorAll('section').forEach((s,i)=>{ const b=s.getBoundingClientRect(); r.push([String(i+1).padStart(2,'0')+'-'+s.id, b.top+window.scrollY, b.bottom+window.scrollY]); });
            return r; }''')
        for name, top, bot in boxes:
            h = bot - top
            fn = os.path.join(out, f'phone-{theme}-{name}.png')
            pg.screenshot(path=fn, full_page=True, clip={'x': 0, 'y': top, 'width': 390, 'height': h})
            print(fn, f'{int(h)}px css', 'OVERFLOW' if w > 390 else 'ok')
        ctx.close()
    b.close()
