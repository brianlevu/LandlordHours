"""Render passes for the Blueprint house.

usage: .venv/bin/python scripts/render.py --states frame40,roof --variants light,dark --passes built,lines
       [--samples 128] [--res 2048] [--out renders] [--anim] [--save-blend path] [--quick]
"""
import argparse, math, os, sys, time, json
sys.path.insert(0, os.path.dirname(__file__))
import bpy
from mathutils import Vector, Matrix
import house as H

STATES = {
    'stage0_lot':      dict(stage=0),
    'stage1_slab':     dict(stage=1),
    'stage2_frame25':  dict(stage=2, p=0.25),
    'stage2_frame40':  dict(stage=2, p=0.40),
    'stage2_frame50':  dict(stage=2, p=0.50),
    'stage2_frame75':  dict(stage=2, p=0.75),
    'stage3_trusses':  dict(stage=3, p=0.40),
    'stage3_roof':     dict(stage=3, p=1.0),
    'stage4_siding30': dict(stage=4, p=0.30),
    'stage4_siding60': dict(stage=4, p=0.60),
    'stage5_finished': dict(stage=5),
}

# WP-A app keyframes (hero house renderer). Order = build order; the app maps goal progress onto them.
KEYFRAMES = [
    ('k00_lot',       dict(stage=0)),
    ('k01_slab',      dict(stage=1)),
] + [('k%02d_frame%03d' % (1 + i, 10 * i), dict(stage=2, p=0.1 * i)) for i in range(1, 11)] + [
    ('k12_roof',      dict(stage=3, p=1.0)),
] + [('k%02d_siding%03d' % (12 + i, 20 * i), dict(stage=4, p=0.2 * i)) for i in range(1, 6)] + [
    ('k18_finished',  dict(stage=5)),
]
STATES.update({k: v for k, v in KEYFRAMES})

CYAN = '#8FD3FF'

def setup_render(res, samples):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'
    prefs.get_devices()
    for d in prefs.devices:
        d.use = (d.type == 'METAL')
    sc.cycles.device = 'GPU'
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.01
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = 6
    sc.cycles.transparent_max_bounces = 8
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '8'
    sc.view_settings.view_transform = 'Khronos PBR Neutral'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0

def setup_camera():
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam'); cam.type = 'ORTHO'
    co = bpy.data.objects.new('cam', cam); sc.collection.objects.link(co); sc.camera = co
    rot = Matrix.Rotation(math.radians(-45), 4, 'Z') @ Matrix.Rotation(math.radians(62), 4, 'X')
    fwd = (rot.to_3x3() @ Vector((0, 0, -1))); right = rot.to_3x3() @ Vector((1, 0, 0)); up = rot.to_3x3() @ Vector((0, 1, 0))
    pts = []
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in H.OBJS:
        for c in ob.bound_box:
            pts.append(ob.matrix_world @ Vector(c))
    xs = [p.dot(right) for p in pts]; ys = [p.dot(up) for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    ext = max(max(xs) - min(xs), max(ys) - min(ys))
    cam.ortho_scale = ext / 0.88
    center = right * cx + up * cy
    co.matrix_world = Matrix.Translation(center - fwd * 40) @ rot
    cam.clip_start = 1; cam.clip_end = 100
    return co

def setup_lights(variant):
    sc = bpy.context.scene
    w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
    bg = w.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = H.lin('#DCE3F0'); bg.inputs['Strength'].default_value = 0.55 if variant == 'light' else 0.45
    def sun(name, rot, strength, angle, col):
        L = bpy.data.lights.new(name, 'SUN'); L.energy = strength; L.angle = math.radians(angle); L.color = col
        o = bpy.data.objects.new(name, L); sc.collection.objects.link(o)
        o.rotation_euler = [math.radians(a) for a in rot]
        return o
    # key: from front-right-above (image upper-left-ish warm), soft
    key = sun('key', (36, 0, -28), 3.2, 16, (1.0, 0.95, 0.88))
    # fill: from the left, cool, weak
    fill = sun('fill', (65, 0, -107), 0.55, 30, (0.86, 0.91, 1.0))
    rim_s = 2.2 if variant == 'light' else 4.6
    rim = sun('rim', (62, 0, 135), rim_s, 6, (1.0, 0.97, 0.92) if variant == 'light' else (0.9, 0.95, 1.0))
    # WP-A: key, fill and rim light the model only. The catcher gets its own key whose only shadow blockers
    # are the lot plinth and lawn, so the tree/house never throw a smudge off the lot.
    rc = bpy.data.collections.get('rim_receivers') or bpy.data.collections.new('rim_receivers')
    for o in H.OBJS:
        if o.name not in rc.objects:
            rc.objects.link(o)
    for L in (key, fill, rim):
        L.light_linking.receiver_collection = rc
    keyc = sun('key_catcher', (36, 0, -28), 3.2, 16, (1.0, 0.95, 0.88))
    cc = bpy.data.collections.get('catcher_only') or bpy.data.collections.new('catcher_only')
    bc = bpy.data.collections.get('lot_blockers') or bpy.data.collections.new('lot_blockers')
    for o in H.OBJS:
        if o.name in ('lot_plinth', 'lot_lawn') and o.name not in bc.objects:
            bc.objects.link(o)
    keyc.light_linking.receiver_collection = cc
    keyc.light_linking.blocker_collection = bc
    # shadow catcher
    me = bpy.data.meshes.new('catcher')
    s = 40
    me.from_pydata([(-s, -s, -0.452), (s, -s, -0.452), (s, s, -0.452), (-s, s, -0.452)], [], [(0, 1, 2, 3)])
    co = bpy.data.objects.new('shadow_catcher', me); sc.collection.objects.link(co)
    co.is_shadow_catcher = True
    if co.name not in cc.objects:
        cc.objects.link(co)
    return co

def apply_state(st, mode, catcher, only=None):
    """mode: 'built', 'lines' or 'glow' (lit-window mask: everything holdout except lit glass as white emission).
    only: optional object; every other object becomes a camera holdout (still casts shadows/bounce)."""
    sc = bpy.context.scene
    lit = st['stage'] >= 5
    for ob in H.OBJS:
        b = H.is_built(ob, st)
        ob.is_holdout = False
        names = ob['mats'].split(',')
        for i, slot in enumerate(ob.material_slots):
            slot.material = H.MATS[names[i]]
        if 'glass_slot' in ob:
            ob.material_slots[ob['glass_slot']].material = H.MATS['glass_lit' if lit else 'glass']
        if mode == 'built':
            ob.hide_render = not b
            for m in ob.modifiers: m.show_render = True
            ob.is_holdout = (only is not None and ob != only)
        elif mode == 'fill':
            # coverage of the unbuilt finished-house skin, as ONE flat opaque silhouette (never stacks)
            for m in ob.modifiers: m.show_render = (m.name == 'lump')
            if b:
                ob.hide_render = False
                for slot in ob.material_slots: slot.material = H.MATS['holdout']
            elif ob['role']:
                ob.hide_render = False
                for slot in ob.material_slots: slot.material = H.MATS['glowmask']
            else:
                ob.hide_render = True
        elif mode == 'mask':
            # built structure only (not the lot/slab ground) as flat white: post.py cuts it out of the linework,
            # so linework drawn ABOVE built shows over the ground but never over the built structure
            ground = ob['kind'] in ('lot', 'slab', 'stake')
            ob.hide_render = (not b) or ground
            for m in ob.modifiers: m.show_render = True
            for slot in ob.material_slots:
                slot.material = H.MATS['glowmask']
        elif mode == 'glow':
            ob.hide_render = not b
            for m in ob.modifiers: m.show_render = True
            for i, slot in enumerate(ob.material_slots):
                lit_slot = lit and 'glass_slot' in ob and i == ob['glass_slot']
                slot.material = H.MATS['glowmask'] if lit_slot else H.MATS['holdout']
        else:
            for m in ob.modifiers: m.show_render = (m.name == 'lump')
            if b:
                ob.hide_render = False
                for slot in ob.material_slots: slot.material = H.MATS['holdout']
            elif ob['role']:
                ob.hide_render = False
                # gate fix: no translucent wash on the faces (it stacked to opaque); strokes only.
                # The flat fill comes from the separate 'fill' pass, combined with max() in post.py.
                for slot in ob.material_slots: slot.material = H.MATS['clear']
            else:
                ob.hide_render = True
    catcher.hide_render = (mode != 'built') or (only is not None)
    for L in [o for o in sc.objects if o.type == 'LIGHT']:
        L.hide_render = (mode != 'built')
    if mode in ('glow', 'mask', 'fill'):
        sc.view_settings.view_transform = 'Standard'
    # freestyle
    sc.render.use_freestyle = (mode == 'lines')
    for c in list(bpy.data.collections):
        if c.name.startswith('LINES_'):
            bpy.data.collections.remove(c)
    if mode == 'lines':
        sc.view_settings.view_transform = 'Standard'
        cols = {}
        for r in ('major', 'detail', 'all'):
            c = bpy.data.collections.new('LINES_' + r); cols[r] = c
            sc.collection.children.link(c)
            c.hide_render = False
        for ob in H.OBJS:
            if not H.is_built(ob, st) and ob['role']:
                cols[ob['role']].objects.link(ob)
                cols['all'].objects.link(ob)
        vl = sc.view_layers[0]; vl.use_freestyle = True
        fs = vl.freestyle_settings
        fs.crease_angle = math.radians(125)
        fs.use_culling = False
        for ls in list(fs.linesets): fs.linesets.remove(ls)
        sc.render.line_thickness_mode = 'ABSOLUTE'
        for r, thick in (('major', 3.0), ('detail', 1.7)):
            ls = fs.linesets.new(r)
            ls.select_by_visibility = True; ls.visibility = 'VISIBLE'
            ls.select_by_edge_types = True
            ls.select_silhouette = True; ls.select_border = True; ls.select_crease = True
            ls.select_by_collection = True; ls.collection = cols[r]
            lsty = ls.linestyle
            lsty.color = H.lin(CYAN)[:3]; lsty.thickness = thick; lsty.caps = 'ROUND'
            lsty.alpha = 1.0
        # contour of everything future, heavier
        ls = fs.linesets.new('contour')
        ls.select_by_visibility = True; ls.visibility = 'VISIBLE'
        ls.select_by_edge_types = True; ls.select_silhouette = False; ls.select_border = False; ls.select_crease = False
        ls.select_external_contour = True
        ls.select_by_collection = True; ls.collection = cols['all']
        ls.linestyle.color = H.lin(CYAN)[:3]; ls.linestyle.thickness = 3.4; ls.linestyle.caps = 'ROUND'
    elif mode == 'built':
        sc.view_settings.view_transform = 'Khronos PBR Neutral'

def render_to(path):
    bpy.context.scene.render.filepath = path
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    return time.time() - t0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--states', default='stage2_frame40')
    ap.add_argument('--variants', default='light')
    ap.add_argument('--passes', default='built,lines')
    ap.add_argument('--samples', type=int, default=128)
    ap.add_argument('--res', type=int, default=2048)
    ap.add_argument('--out', default=os.path.join(os.path.dirname(__file__), '..', 'renders'))
    ap.add_argument('--anim', action='store_true')
    ap.add_argument('--save-blend', default='')
    ap.add_argument('--row-only', action='store_true', help='anim: render only the moving row; the rest is a camera holdout')
    ap.add_argument('--anim-base', default='k14_siding040')
    a = ap.parse_args()
    if a.states == 'keyframes':
        a.states = ','.join(k for k, _ in KEYFRAMES)
    out = os.path.abspath(a.out); os.makedirs(out, exist_ok=True)
    walls, rows = H.build_all()
    setup_render(a.res, a.samples)
    cam = setup_camera()
    log = []
    catchers = {}
    for v in a.variants.split(','):
        # rebuild lights per variant
        for o in [o for o in bpy.context.scene.objects if o.type == 'LIGHT' or o.name.startswith('shadow_catcher')]:
            bpy.data.objects.remove(o)
        catcher = setup_lights(v)
        if a.anim:
            render_anim(out, v, a.samples, log, catcher, a.anim_base, a.row_only)
            continue
        for s in a.states.split(','):
            st = STATES[s]
            for p in a.passes.split(','):
                if p in ('lines', 'glow', 'mask', 'fill') and v != a.variants.split(',')[0]:
                    continue   # linework / glow mask are lighting-independent; render once
                if p == 'glow' and st['stage'] < 5:
                    continue   # windows are only lit when finished
                apply_state(st, p, catcher)
                sc = bpy.context.scene
                sc.cycles.samples = a.samples if p == 'built' else 16
                fn = os.path.join(out, f'{s}__{p}' + (f'__{v}' if p == 'built' else '') + '.png')
                if os.path.exists(fn) and os.environ.get('SKIP_EXISTING'):
                    continue
                dt = render_to(fn)
                log.append(dict(file=os.path.basename(fn), seconds=round(dt, 1)))
                print('RENDERED', fn, round(dt, 1), flush=True)
    if a.save_blend:
        st = STATES.get(a.states.split(',')[0], STATES['stage2_frame40'])
        apply_state(st, 'built', catcher)
        txt = bpy.data.texts.new('house.py'); txt.from_string(open(H.__file__).read())
        txt2 = bpy.data.texts.new('render.py'); txt2.from_string(open(__file__).read())
        bpy.context.scene['blueprint_state'] = json.dumps(st)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.save_blend))
        print('SAVED', a.save_blend)
    with open(os.path.join(out, 'render-log.jsonl'), 'a') as f:
        for r in log:
            f.write(json.dumps(r) + '\n')

def render_anim(out, v, samples, log, catcher, base_state='stage4_siding60', row_only=False):
    """One clapboard row (the next row after the base state) slides in from outside/above and settles.
    row_only: every other object is a camera holdout, so each frame is an overlay registered to the base keyframe."""
    st = dict(STATES[base_state])
    siding = sorted([o for o in H.OBJS if o['kind'] == 'siding'], key=lambda o: o['t'])
    nxt = [o for o in siding if o['t'] > st['p']][0]
    st2 = dict(st); st2['p'] = nxt['t']
    apply_state(st2, 'built', catcher, only=nxt if row_only else None)
    d = os.path.join(out, f'anim_confirm_row' + ('_overlay' if row_only else '') + f'__{v}'); os.makedirs(d, exist_ok=True)
    # gate fix: only the row segments on camera-facing walls (front, left, wing front); the back-wall segment
    # showed through the open upper framing as an orphan fragment
    import bmesh
    bm = bmesh.new(); bm.from_mesh(nxt.data); bm.faces.ensure_lookup_table()
    seen, drop_f = set(), []
    for f0 in bm.faces:                      # one island per siding box
        if f0.index in seen:
            continue
        isl, stack = [], [f0]; seen.add(f0.index)
        while stack:
            f = stack.pop(); isl.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index); stack.append(g)
        c = sum((f.calc_center_median() for f in isl), Vector()) / len(isl)
        if not (c.y < -2.3 or c.x < -2.5):   # front + left walls only (the wing front showed through the open framing)
            drop_f += isl
    bmesh.ops.delete(bm, geom=drop_f, context='FACES'); bm.to_mesh(nxt.data); bm.free()
    # gate fix: a darker paint (door tone) so the new board reads on the light card; outline + contact shadow in post.py
    for slot in nxt.material_slots:
        slot.material = H.MATS['door']
    base = nxt.matrix_world.copy()
    N = 13
    for f in range(N):
        t = f / (N - 1)
        spring = math.exp(-5 * t) * math.cos(2.5 * math.pi * t)   # 1 -> 0, one 13% overshoot, exactly 0 at t=1
        out_off = 0.55 * (1 - t) ** 3                            # slides in from outside, never into the wall
        drop = 0.45 * spring                                     # falls, dips below rest, settles
        if f == N - 1:
            out_off = drop = 0.0
        off = Vector((-0.7071 * out_off, -0.7071 * out_off, drop))
        nxt.matrix_world = Matrix.Translation(off) @ base
        fn = os.path.join(d, f'frame_{f:02d}.png')
        dt = render_to(fn)
        log.append(dict(file=os.path.join(os.path.basename(d), f'frame_{f:02d}.png'), seconds=round(dt, 1)))
        print('RENDERED', fn, round(dt, 1), flush=True)
    nxt.matrix_world = base

if __name__ == '__main__':
    main()
