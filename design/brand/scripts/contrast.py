"""WCAG 2.x contrast for the LandlordHours 2.0 Blueprint token set. Prints the table brand.md quotes.
usage: python3 contrast.py [--json out.json]
"""
import json, sys

def lum(h):
    h = h.lstrip('#'); r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def grade(r, large=False):
    if r >= 7: return 'AAA'
    if r >= 4.5: return 'AA'
    if r >= 3: return 'AA-large' if large else 'AA large only'
    return 'FAIL'

# --- tokens: light / dark -----------------------------------------------------------
T = {
    'canvas':            ('#EEF2FA', '#0B1230'),
    'card':              ('#FFFFFF', '#141C3F'),
    'cardRaised':        ('#F6F8FD', '#1B2550'),
    'brand (blueprint)': ('#1E3FA6', '#1E3FA6'),
    'action':            ('#1E3FA6', '#8FD3FF'),
    'onAction':          ('#FFFFFF', '#0B1230'),
    'actionSurface':     ('#E3E9FA', '#182A5C'),
    'drafting (cyan)':   ('#8FD3FF', '#60A8E6'),
    'draftingInk':       ('#2369B5', '#60A8E6'),
    'timber':            ('#E0A458', '#E0A458'),
    'timberInk':         ('#8A5A1B', '#F0BE7A'),
    'brass':             ('#D9B45A', '#D9B45A'),
    'terracotta':        ('#C8553D', '#C8553D'),
    'plaster':           ('#F4EFE6', '#F4EFE6'),
    'textPrimary':       ('#121B33', '#F2F4FA'),
    'textSecondary':     ('#4A5068', '#B4BCD2'),
    'textTertiary':      ('#5F6983', '#7E88A6'),
    'border':            ('#D5DBEA', '#2A3560'),
    'positive':          ('#137A42', '#4ED48A'),
    'positiveSurface':   ('#E4F7EB', '#123A2A'),
    'caution':           ('#9A560C', '#FFB454'),
    'cautionSurface':    ('#FCF0DC', '#3D2A10'),
    'destructive':       ('#C1303A', '#FF7A7A'),
    'destructiveSurface':('#FCE4E5', '#44181C'),
    'informational':     ('#4A6392', '#9BB0D0'),
    'informationalSurface': ('#E6ECF6', '#1E2A4A'),
}

rows = []
def chk(label, fg, bg, large=False):
    r = ratio(fg, bg); rows.append((label, fg, bg, round(r, 2), grade(r, large)))

for mode, i in (('light', 0), ('dark', 1)):
    canvas, card = T['canvas'][i], T['card'][i]
    for name in ('textPrimary', 'textSecondary', 'textTertiary', 'action', 'positive', 'caution', 'destructive', 'informational', 'timberInk', 'draftingInk'):
        chk(f'{mode} · {name} on card', T[name][i], card)
        chk(f'{mode} · {name} on canvas', T[name][i], canvas)
    chk(f'{mode} · onAction on action', T['onAction'][i], T['action'][i])
    chk(f'{mode} · action on actionSurface', T['action'][i], T['actionSurface'][i])
    for s in ('positive', 'caution', 'destructive', 'informational'):
        chk(f'{mode} · {s} on {s}Surface', T[s][i], T[s + 'Surface'][i])
    chk(f'{mode} · border on card (decorative hairline, WCAG-exempt; cards separate by fill)', T['border'][i], card, large=True)

# blueprint surface (same in both modes)
BP = '#1E3FA6'
chk('blueprint · white text', '#FFFFFF', BP)
chk('blueprint · drafting cyan linework (light mode)', '#8FD3FF', BP)
chk('blueprint · drafting linework, dark mode #60A8E6 (non-text 3:1)', '#60A8E6', BP, large=True)
chk('dark · drafting #60A8E6 vs action #8FD3FF (separation, not a text pair)', '#60A8E6', '#8FD3FF', large=True)
chk('blueprint · timber', '#E0A458', BP, large=True)
chk('blueprint · brass', '#D9B45A', BP, large=True)
chk('blueprint · plaster', '#F4EFE6', BP)
chk('blueprint · positive (dark variant) text', '#4ED48A', BP)
chk('blueprint · caution (dark variant) text', '#FFB454', BP)
chk('blueprint · blueprint text on white pill', BP, '#FFFFFF')
chk('blueprint · white pill on blueprint (non-text)', '#FFFFFF', BP, large=True)
# retired violet, for the record
chk('record · violet #5B4CDB next to blueprint (hue clash check, not a text pair)', '#5B4CDB', BP, large=True)
chk('record · drafting cyan as text on white (why it is not the light action)', '#8FD3FF', '#FFFFFF')

w = max(len(r[0]) for r in rows)
print(f'{"pair".ljust(w)}  fg       bg       ratio  grade')
for r in rows:
    print(f'{r[0].ljust(w)}  {r[1]}  {r[2]}  {str(r[3]).rjust(5)}  {r[4]}')
fails = [r for r in rows if r[4] == 'FAIL']
print(f'\n{len(rows)} pairs, {len(fails)} FAIL')
if '--json' in sys.argv:
    with open(sys.argv[sys.argv.index('--json') + 1], 'w') as f:
        json.dump([dict(pair=r[0], fg=r[1], bg=r[2], ratio=r[3], grade=r[4]) for r in rows], f, indent=1)
