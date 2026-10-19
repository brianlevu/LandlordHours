"""Re-render a hero state (full lot) WITHOUT the ground-shadow catcher, for the brand board's Today card:
the soft shadow read as a black halo on blueprint blue.
usage: .venv/bin/python render_hero.py --state stage2_frame75 --out ../renders [--res 1400] [--samples 96]
"""
import argparse, os, sys, json
PROJ = '/Users/brian/Projects/LandlordHours/design/blueprint-house/scripts'
sys.path.insert(0, PROJ)
import bpy
import house as H
import render as R

ap = argparse.ArgumentParser()
ap.add_argument('--state', default='stage2_frame75')
ap.add_argument('--out', default=os.path.join(os.path.dirname(__file__), '..', 'renders'))
ap.add_argument('--res', type=int, default=1400)
ap.add_argument('--samples', type=int, default=96)
a = ap.parse_args()
out = os.path.abspath(a.out); os.makedirs(out, exist_ok=True)
H.build_all()
R.setup_render(a.res, a.samples)
R.setup_camera()
catcher = R.setup_lights('dark')
st = R.STATES[a.state]
for p in ('built', 'lines'):
    R.apply_state(st, p, catcher)
    catcher.hide_render = True
    bpy.context.scene.cycles.samples = a.samples if p == 'built' else 16
    fn = os.path.join(out, f'hero_{a.state}_noshadow__{p}.png')
    dt = R.render_to(fn)
    print('RENDERED', fn, round(dt, 1), flush=True)
    with open(os.path.join(out, 'render-log.jsonl'), 'a') as f:
        f.write(json.dumps(dict(file=os.path.basename(fn), seconds=round(dt, 1))) + '\n')
print('DONE', flush=True)
