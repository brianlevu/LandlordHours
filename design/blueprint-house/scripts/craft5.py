"""Direction CRAFT, pass 5: the sculpt pass. Same rig, palette, camera, stages and drop as craft3.py (pass 3 + the
night framing moon rim); only the forms change, plus the §F.1 slot contract.

Forms (stylised-soft, one radius ladder, not photoreal):
- Every bevelled part gets round, 3-segment bevels with hardened normals at one of four radii (RADII below):
  fine 0.014 (studs, siding boards), medium 0.03 (window and door casings, tiles, rails), large 0.05 (roof edges,
  chimney, porch posts, slab), lot 0.06 rim + 0.28 plan corners (the lot block reads as a soft cake, not a crate).
- Roof: overhang 0.35 -> 0.45, tiles 0.05 -> 0.07 thick, barge boards and fascia twice as thick (a soft slab edge),
  a gentle ridge sag (0.045 at mid-ridge, 0 at the gables and eaves, so nothing opens up).
- Windows and door: casings 0.09 -> 0.13 wide and prouder, deeper sill, chunkier sash and mullions.
- Chimney: rounder (large radius, 4 segments). Porch posts and beam chunkier.
- The camera is pinned to pass 3 (camera_pin.json), so the bigger overhang does not reframe the art.
- The 39-piece framing drop is untouched (framing geometry only gets the fine bevel).

§F.1 customisation slots (DESIGN-STANDARD v2): roof, siding, trim, door. SLOTS below maps each slot to its
materials; the materials are renamed LH_slot_<slot>[...] and tagged m['lh_slot'] = slot, so the names are stable.
- `--neutral` renders the slot materials at neutral albedo (sRGB #BCBCBC = linear 0.5), each keeping its own
  roughness and normal map. Not shipped until customisation is built.
- `--masks half,complete` writes craft_slots_<stage>.png (R roof, G siding, B trim, A door coverage), from an
  emission-only override render (geometry + camera only; shared by lit/unlit/dusk/night).

usage (bpy 5.0.1 venv, headless):
  .venv/bin/python craft5.py --states started,frame70,framing,half,complete --variants light,dark --lit on,off --out DIR
  .venv/bin/python craft5.py --anim --variants light,dark --samples 64 --out DIR
  .venv/bin/python craft5.py --masks half,complete --out DIR
  .venv/bin/python craft5.py --neutral --states complete --variants light,dark --out DIR
  .venv/bin/python craft5.py --no-sculpt ...        # pass-3 forms (with the pinned camera)
All craft3.py rig dials (--rim-dark, --moon-frame, ...) are accepted with the same defaults.
"""
import argparse, json, math, os, sys, time
SCR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCR)
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix
import craft3 as T
K, H, C = T.K, T.H, T.C

PIN = os.path.join(SCR, 'camera_pin.json')

# ------------------------------------------------------------------ §F.1 slots (stable names)
SLOTS = {                     # slot -> H.MATS keys
    'roof': ('tile', 'ridge'),
    'siding': ('plaster',),
    'trim': ('trim',),
    'door': ('door',),
}
SLOT_NAMES = {'tile': 'LH_slot_roof', 'ridge': 'LH_slot_roof_ridge', 'plaster': 'LH_slot_siding',
              'trim': 'LH_slot_trim', 'door': 'LH_slot_door'}
NEUTRAL = '#BCBCBC'           # sRGB 188 = linear 0.5
MASK_CHANNEL = {'roof': 0, 'siding': 1, 'trim': 2, 'door': 3}

# ------------------------------------------------------------------ sculpt knobs
SCULPT = dict(
    OH=0.45,
    S=dict(fw=0.13, frame_d=0.13, sill=(0.19, 0.21, 0.10), sash=0.06, mull=0.065, tile_th=0.07, tile_bevel=0.03,
           barge=(0.12, 0.48), barge_off=-0.06, fascia=(0.10, 0.30), post=0.21, beam=0.22),
    sag=0.045, sag_wing=0.03,
    lot_corner=0.28, lot_rim=0.06,
)
FINE, MED, LARGE = 0.014, 0.03, 0.05
RADII = [                     # (name prefix, radius, segments); first match wins
    ('frame_', FINE, 3), ('rafter_', FINE, 3), ('ridgeboard_', FINE, 3), ('sill_plates', FINE, 3),
    ('siding_', FINE, 3), ('sheath_', 0.01, 2),
    ('tiles_', MED, 3), ('unit_', MED, 3), ('casing_', MED, 3), ('porch_rail', 0.012, 3),
    ('roof_trim', LARGE, 4), ('chimney', LARGE, 4), ('porch_step', LARGE, 3), ('porch_deck', LARGE, 3),
    ('porch', MED, 3), ('slab', LARGE, 3), ('lot_path', MED, 3), ('work_lamp', 0.01, 2), ('key', 0.004, 2),
]

def radius_for(name):
    for p, r, s in RADII:
        if name.startswith(p): return r, s
    return None

def soften():
    n = 0
    for ob in H.OBJS:
        if ob.type != 'MESH' or ob['kind'] == 'block': continue
        bv = [m for m in ob.modifiers if m.type == 'BEVEL']
        rs = radius_for(ob.name)
        if not bv or not rs: continue
        b = bv[0]; b.width, b.segments = rs
        b.limit_method = 'ANGLE'; b.angle_limit = math.radians(40)
        b.use_clamp_overlap = True; b.profile = 0.5; b.harden_normals = True
        for p in ob.data.polygons: p.use_smooth = True
        n += 1
    print('SOFTEN', n, flush=True)

def soft_chimney():
    """One pot, softer proportions: a single thick corbel course and a thick cap, so the large radius can round them."""
    zb = H.F + 3.6
    shaft = [H.M_box((-1.4, 1.95, (zb + 7.95) / 2), (0.74, 0.74, 7.95 - zb))]
    corbel = [H.M_box((-1.4, 1.95, 8.04), (0.84, 0.84, 0.18))]
    cap = [H.M_box((-1.4, 1.95, 8.22), (0.92, 0.92, 0.18))]
    pots = [K.cone_fn(Matrix.Translation((-1.4, 1.95, 8.45)), 0.13, 0.105, 0.3, 28)]
    ob = K.obj('chimney')
    K.replace_mesh(ob, [('brick', shaft + corbel, []), ('capstone', cap, []), ('ridge', [], pots)], None)

# ------------------------------------------------------------------ roof sag

def _sag(ob, f):
    me = ob.data
    co = np.empty(len(me.vertices) * 3, np.float32); me.vertices.foreach_get('co', co); co = co.reshape(-1, 3)
    co[:, 2] -= f(co)
    me.vertices.foreach_set('co', co.ravel()); me.update()

def ridge_sag():
    ze = H.E + H.RT - H.OH * H.TT
    zr = H.E + H.RT + 2.6 * H.TT
    zw = H.E + H.RT + 1.2 * H.TT
    y0, y1 = -2.4 - H.OH - 0.1, 3.0 + H.OH + 0.1
    x0, x1 = 1.15, 4.4 + H.OH + 0.1
    def main(c):
        h = np.clip((c[:, 2] - ze) / (zr - ze), 0, 1)
        return SCULPT['sag'] * np.sin(np.pi * np.clip((c[:, 1] - y0) / (y1 - y0), 0, 1)) * h * h
    def wing(c):
        h = np.clip((c[:, 2] - ze) / (zw - ze), 0, 1)
        return SCULPT['sag_wing'] * np.sin(np.pi * np.clip((c[:, 0] - x0) / (x1 - x0), 0, 1)) * h * h
    k = 0
    for ob in H.OBJS:
        n = ob.name
        if n.startswith(('tiles_main', 'sheath_main', 'rafter_m', 'ridgeboard_m', 'ridgecap_m', 'roof_trim')):
            _sag(ob, main); k += 1
        elif n.startswith(('tiles_wing', 'sheath_wing', 'rafter_w', 'ridgeboard_w', 'ridgecap_w')):
            _sag(ob, wing); k += 1
    print('SAG', k, flush=True)

# ------------------------------------------------------------------ rounded lot

def rrect_prism(bm, cx, cy, w, d, z0, z1, r, seg=10, top_round=0.0):
    pts = []
    hx, hy = w / 2 - r, d / 2 - r
    for (sx, sy, a0) in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((cx + sx * hx + r * math.cos(a), cy + sy * hy + r * math.sin(a)))
    K.H.prism_fn(pts, z0, z1)(bm)
    if top_round:
        # round only the top rim: a bottom bevel would read as a dark undercut line at the grass/loam seam
        top = [e for e in bm.edges if all(abs(v.co.z - z1) < 1e-5 for v in e.verts) and len(e.link_faces) == 2
               and not all(abs(f.normal.z) > 0.99 for f in e.link_faces)]
        bmesh.ops.bevel(bm, geom=top, offset=top_round, offset_type='OFFSET', segments=4, profile=0.5, affect='EDGES',
                        clamp_overlap=True)

def round_lot():
    x0, x1, y0, y1 = H.LOT
    cx, cy, w, d = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
    R = SCULPT['lot_corner']
    spec = {'blk_grass': (w + 0.06, d + 0.06, -0.14, 0.0, R + 0.03, SCULPT['lot_rim']),
            'blk_topsoil': (w, d, -0.59, -0.13, R, 0.0),
            'blk_clay': (w - 0.02, d - 0.02, C.BLOCK_BOTTOM, -0.59, R - 0.01, 0.0)}
    for name, (ww, dd, za, zb, r, rim) in spec.items():
        ob = bpy.data.objects[name]
        me = bpy.data.meshes.new(name + '_v5'); bm = bmesh.new()
        rrect_prism(bm, cx, cy, ww, dd, za, zb, r, top_round=rim)
        bm.to_mesh(me); bm.free()
        for m in ob.data.materials: me.materials.append(m)
        ob.data = me
        for p in me.polygons: p.use_smooth = True
        for m in list(ob.modifiers):
            if m.type == 'BEVEL': ob.modifiers.remove(m)    # the plan corners and the grass rim are real geometry now
    # blades whose root falls outside the rounded grass slab are sunk out of sight
    bl = bpy.data.objects.get('blk_blades')
    if bl:
        me = bl.data; co = np.empty(len(me.vertices) * 3, np.float32); me.vertices.foreach_get('co', co)
        co = co.reshape(-1, 5, 3)
        base = (co[:, 0, :2] + co[:, 1, :2]) / 2
        r = R + 0.03
        dx = np.maximum(np.abs(base[:, 0] - cx) - ((w + 0.06) / 2 - r), 0)
        dy = np.maximum(np.abs(base[:, 1] - cy) - ((d + 0.06) / 2 - r), 0)
        out = np.hypot(dx, dy) > r - 0.01
        co[out, :, 2] -= 3.0
        me.vertices.foreach_set('co', co.ravel()); me.update()
        print('BLADES sunk', int(out.sum()), flush=True)

# ------------------------------------------------------------------ slots

def name_slots():
    for slot, keys in SLOTS.items():
        for k in keys:
            m = H.MATS[k]; m.name = SLOT_NAMES[k]; m['lh_slot'] = slot

def neutral_pbr():
    orig = K.pbr
    keys = {k for ks in SLOTS.values() for k in ks}
    def pbr(name, *a, **kw):
        if name in keys:
            if len(a) >= 2: a = (a[0], (NEUTRAL, NEUTRAL)) + tuple(a[2:])
            else: kw['tints'] = (NEUTRAL, NEUTRAL)
            kw['island_var'] = 0.0
            if name == 'tile': kw['grime'] = '#3A3A3A'
        return orig(name, *a, **kw)
    K.pbr = pbr

def render_masks(stages, out):
    sc = bpy.context.scene
    for o in [o for o in sc.objects if o.type == 'LIGHT' or o.name.startswith('shadow_catcher')]:
        bpy.data.objects.remove(o)
    w = bpy.data.worlds.new('mask'); w.use_nodes = True; w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0
    sc.world = w
    sc.cycles.samples = 64; sc.cycles.use_denoising = False; sc.cycles.use_adaptive_sampling = False
    sc.cycles.max_bounces = 0
    sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'
    def em(col):
        m = bpy.data.materials.new('mask'); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
        o = nt.nodes.new('ShaderNodeOutputMaterial'); e = nt.nodes.new('ShaderNodeEmission')
        e.inputs['Color'].default_value = col + (1.0,); e.inputs['Strength'].default_value = 1.0
        nt.links.new(e.outputs[0], o.inputs['Surface']); return m
    black = em((0, 0, 0))
    slot_of = {k: s for s, ks in SLOTS.items() for k in ks}
    passes = {0: em((1, 0, 0)), 1: em((0, 1, 0)), 2: em((0, 0, 1)), 3: em((1, 1, 1))}
    def load(fn):
        im = bpy.data.images.load(fn); im.colorspace_settings.name = 'Non-Color'
        px = np.empty(len(im.pixels), np.float32); im.pixels.foreach_get(px)
        w, h = im.size; bpy.data.images.remove(im); return px.reshape(h, w, 4)
    def save(arr, fn):
        h, w = arr.shape[:2]
        im = bpy.data.images.new('mask_out', w, h, alpha=True); im.colorspace_settings.name = 'Non-Color'
        im.pixels.foreach_set(arr.astype(np.float32).ravel()); im.filepath_raw = fn; im.file_format = 'PNG'; im.save()
        bpy.data.images.remove(im)
    files = []
    for st in stages:
        T.apply_state(C.STATES[st], 'dark', False)
        for o in [o for o in sc.objects if o.type == 'LIGHT']: bpy.data.objects.remove(o)
        pngs = {}
        for pname, chans in (('rgb', (0, 1, 2)), ('door', (3,))):
            for ob in H.OBJS:
                if ob.type != 'MESH' or ob.hide_render: continue
                names = ob['mats'].split(',')
                for i, sl in enumerate(ob.material_slots):
                    key = names[i] if i < len(names) else ''
                    if 'glass_slot' in ob and i == ob['glass_slot']: key = 'glass'
                    ch = MASK_CHANNEL.get(slot_of.get(key, ''), -1)
                    sl.material = passes[ch] if ch in chans else black
            fn = os.path.join(out, f'_mask_{st}_{pname}.png'); C.render_to(fn); pngs[pname] = fn
        a = load(pngs['rgb']); b = load(pngs['door'])
        cov = a[..., :3] * a[..., 3:4]                       # straight alpha -> coverage
        door = b[..., 0] * b[..., 3]
        mask = np.dstack([cov, door])
        fo = os.path.join(out, f'craft_slots_{st}.png')
        save(mask.clip(0, 1), fo)
        for f in pngs.values(): os.remove(f)
        print('MASK', fo, {k: round(float((mask[..., i] > 0.5).mean()), 4) for k, i in MASK_CHANNEL.items()}, flush=True)
        files.append(fo)
    return files

# ------------------------------------------------------------------ camera pin

def cam_state():
    co = bpy.context.scene.camera
    return dict(location=list(co.location), rotation=list(co.rotation_euler), lens=co.data.lens,
                sensor=co.data.sensor_width, shift_x=co.data.shift_x, shift_y=co.data.shift_y,
                clip=[co.data.clip_start, co.data.clip_end])

def pin_camera(path):
    p = json.load(open(path)); co = bpy.context.scene.camera
    co.location = p['location']; co.rotation_euler = p['rotation']
    co.data.lens = p['lens']; co.data.sensor_width = p['sensor']
    co.data.shift_x = p['shift_x']; co.data.shift_y = p['shift_y']
    co.data.clip_start, co.data.clip_end = p['clip']

# ------------------------------------------------------------------ main

def parser():
    ap = argparse.ArgumentParser()
    for k, d in (('--states', 'complete'), ('--variants', 'light,dark'), ('--lit', 'on'), ('--save-blend', ''),
                 ('--probes', ''), ('--masks', ''), ('--dump-camera', ''), ('--moon-col', T.RIM)):
        ap.add_argument(k, default=d)
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=128); ap.add_argument('--res', type=int, default=1206)
    ap.add_argument('--anim', action='store_true'); ap.add_argument('--fps', type=int, default=30)
    ap.add_argument('--seconds', type=float, default=2.0)
    ap.add_argument('--no-sculpt', action='store_true'); ap.add_argument('--neutral', action='store_true')
    for k, d in (('--sun', 4.0), ('--rim-light', 0.0), ('--rim-dark', 1.5), ('--fill-light', 1.5), ('--fill-dark', 0.45),
                 ('--win-light', 6.0), ('--win-dark', 32.0), ('--spill', 60.0), ('--spread', 50.0), ('--porch', 80.0),
                 ('--porch-lawn', 1500.0), ('--interior', 500.0), ('--work', 220.0), ('--work-lawn', 900.0),
                 ('--dusk-scale', 0.5), ('--dusk-work-scale', 1.6), ('--moon-frame', 4.0)):
        ap.add_argument(k, type=float, default=d)
    ap.add_argument('--moon-dir', type=float, nargs=3, default=(-0.6, 1.0, 0.6))
    ap.add_argument('--spill-off', type=float, default=0.27)   # window spill lamps sit just past the deeper sills (pass 3: 0.16)
    return ap

def build(a):
    if not a.no_sculpt:
        H.OH = SCULPT['OH']; H.KN.update(SCULPT['S'])
    if a.neutral:
        neutral_pbr()
    K.flower_box = lambda *x, **k: None
    orig = K.craft2_materials
    def mats():
        orig(); T.palette()          # with --neutral, neutral_pbr() intercepts the slot materials' tints
    K.craft2_materials = mats
    T.WALLS = K.build(a)
    T.declutter()
    T.work_lamp()
    for o in H.OBJS:
        if o['kind'] == 'block':
            names = o['mats'].split(',')
            for i, sl in enumerate(o.material_slots): sl.material = H.MATS[names[i]]
    if a.dump_camera:
        json.dump(cam_state(), open(a.dump_camera, 'w'), indent=1); print('CAMERA dumped', a.dump_camera)
    elif os.path.exists(PIN):
        pin_camera(PIN)
    if not a.no_sculpt:
        soft_chimney(); soften(); ridge_sag(); round_lot()
    name_slots()
    C.apply_state = lambda st, v: T.apply_state(st, v, True)     # the build-drop clip always plays lit

def main():
    a = parser().parse_args(); T.ARGS = a
    out = os.path.abspath(a.out); os.makedirs(out, exist_ok=True)
    t0 = time.time()
    build(a)
    print('BUILD', round(time.time() - t0, 1), flush=True)
    if a.probes:
        T.probes(a.probes); return
    if a.dump_camera:
        return
    if a.masks:
        render_masks(a.masks.split(','), out); return
    pieces = [o for o in H.OBJS if o['kind'] == 'frame' and C.ANIM_FROM < o['t'] <= C.ANIM_TO]
    print('DROP pieces', len(pieces), flush=True)
    meta = []
    tag = '-neutral' if a.neutral else ''
    for v in a.variants.split(','):
        T.setup_lights(v)
        if a.anim:
            n, Nf, log = C.anim(out, v, a.fps, a.seconds)
            meta.append(dict(anim=v, pieces=n, frames=Nf, fps=a.fps, sec_per_frame=round(sum(log) / len(log), 2), samples=a.samples))
            continue
        for lit in a.lit.split(','):
            for s in a.states.split(','):
                T.apply_state(C.STATES[s], v, lit == 'on')
                fn = os.path.join(out, f'craft_{s}{tag}_{v}.png' if lit == 'on' else f'craft_{s}-unlit{tag}_{v}.png')
                dt = C.render_to(fn)
                meta.append(dict(file=os.path.basename(fn), seconds=round(dt, 1), samples=a.samples, res=a.res))
                print('RENDERED', fn, round(dt, 1), flush=True)
    if a.save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.save_blend))
    with open(os.path.join(out, 'render-log.jsonl'), 'a') as f:
        for r in meta: f.write(json.dumps(dict(r, args=vars(a))) + '\n')

if __name__ == '__main__':
    main()
