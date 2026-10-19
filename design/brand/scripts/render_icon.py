"""Render the Blueprint house as an app-icon subject (house only, no lot/tree/stake).

usage: .venv/bin/python render_icon.py --out ../renders [--res 1024] [--samples 64]
Imports the project's house.py / render.py from design/blueprint-house/scripts.
Outputs transparent PNGs per state: built pass (dark-variant lighting, made for the blue ground)
and a cyan linework pass; icon_compose.py puts them on blueprint blue.
"""
import argparse, math, os, sys, time, json
PROJ = '/Users/brian/Projects/LandlordHours/design/blueprint-house/scripts'
sys.path.insert(0, PROJ)
import bpy
from mathutils import Vector, Matrix
import house as H
import render as R

ICON_STATES = {
    'finished': R.STATES['stage5_finished'],
    'roof':     R.STATES['stage3_roof'],
    'siding60': R.STATES['stage4_siding60'],
    'frame75':  R.STATES['stage2_frame75'],
}

def house_objs():
    return [o for o in H.OBJS if o['kind'] not in ('lot', 'stake')]

def setup_camera_house(fill=0.80):
    """Same 3/4 ortho rotation as the hero, framed on the house only."""
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam'); cam.type = 'ORTHO'
    co = bpy.data.objects.new('cam', cam); sc.collection.objects.link(co); sc.camera = co
    rot = Matrix.Rotation(math.radians(-45), 4, 'Z') @ Matrix.Rotation(math.radians(62), 4, 'X')
    r3 = rot.to_3x3()
    fwd = r3 @ Vector((0, 0, -1)); right = r3 @ Vector((1, 0, 0)); up = r3 @ Vector((0, 1, 0))
    pts = []
    for ob in house_objs():
        for c in ob.bound_box:
            pts.append(ob.matrix_world @ Vector(c))
    xs = [p.dot(right) for p in pts]; ys = [p.dot(up) for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    ext = max(max(xs) - min(xs), max(ys) - min(ys))
    cam.ortho_scale = ext / fill
    center = right * cx + up * cy
    co.matrix_world = Matrix.Translation(center - fwd * 40) @ rot
    cam.clip_start = 1; cam.clip_end = 100
    return co

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(os.path.dirname(__file__), '..', 'renders'))
    ap.add_argument('--res', type=int, default=1024)
    ap.add_argument('--samples', type=int, default=64)
    ap.add_argument('--states', default='finished,roof,siding60,frame75')
    ap.add_argument('--fill', type=float, default=0.80)
    ap.add_argument('--no-shadow', action='store_true', help='no ground plane: hide the shadow catcher (app-icon rule: one object, no scene)')
    ap.add_argument('--suffix', default='')
    a = ap.parse_args()
    out = os.path.abspath(a.out); os.makedirs(out, exist_ok=True)
    H.build_all()
    R.setup_render(a.res, a.samples)
    setup_camera_house(a.fill)
    catcher = R.setup_lights('dark')
    # lot is gone: lift the shadow catcher to the underside of the slab so the contact shadow sits under the house
    catcher.location.z = 0.452 - 0.06
    # never render the lot or the stake, whatever the state says
    hidden = [o for o in H.OBJS if o['kind'] in ('lot', 'stake')]
    log = []
    for s in a.states.split(','):
        st = ICON_STATES[s]
        for p in ('built', 'lines'):
            R.apply_state(st, p, catcher)
            for o in hidden:
                o.hide_render = True
            if a.no_shadow:
                catcher.hide_render = True
            bpy.context.scene.cycles.samples = a.samples if p == 'built' else 16
            fn = os.path.join(out, f'icon_{s}{a.suffix}__{p}.png')
            dt = R.render_to(fn)
            log.append(dict(file=os.path.basename(fn), seconds=round(dt, 1)))
            print('RENDERED', fn, round(dt, 1), flush=True)
    with open(os.path.join(out, 'render-log.jsonl'), 'a') as f:
        for r in log:
            f.write(json.dumps(r) + '\n')
    print('DONE', flush=True)

if __name__ == '__main__':
    main()
