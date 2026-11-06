"""Direction CRAFT: the blueprint house as a lit, crafted diorama object.

Reuses house.py geometry and its build stages. Adds a cut-away lot block (lawn, topsoil, clay, stones),
a perspective camera, a soft key + rim + sky rig, AO from path tracing, timber grain, and a night rig with
warm window light. Writes transparent PNGs (the block casts a soft shadow onto a shadow catcher).

usage: .venv/bin/python craft.py --states framing,half,complete --variants light,dark --res 1206 --samples 128 --out DIR
       .venv/bin/python craft.py --anim --variants light,dark --res 1206 --samples 48 --out DIR
"""
import argparse, math, os, sys, time, json, random
sys.path.insert(0, os.path.dirname(__file__))
import bpy, bmesh
from mathutils import Vector, Matrix
import house as H

STATES = {
    'lot':       dict(stage=0),
    'started':   dict(stage=2, p=0.35),   # just started (framing only, partial)
    'started2':  dict(stage=2, p=0.55),
    'frame70':   dict(stage=2, p=0.70),   # default Today (46 of 100); the build motion starts here
    'framing':   dict(stage=2, p=1.0),    # framing only, complete frame
    'half':      dict(stage=4, p=0.45),   # roof on, siding about half
    'complete':  dict(stage=5),
}
ANIM_FROM, ANIM_TO = 0.70, 1.0     # one stage advance: the frame closes up

# ------------------------------------------------------------------ materials

def node(nt, kind, **kw):
    n = nt.nodes.new(kind)
    for k, v in kw.items():
        n.inputs[k].default_value = v
    return n

def timber_grain(m, a, b):
    """Swap a flat timber colour for long grain: noise stretched along Z (studs), per-object tone shift."""
    nt = m.node_tree; p = nt.nodes['Principled BSDF']
    for l in list(p.inputs['Base Color'].links):
        nt.links.remove(l)
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping'); mp.inputs['Scale'].default_value = (14, 14, 1.1)
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    wv = nt.nodes.new('ShaderNodeTexWave'); wv.wave_type = 'BANDS'; wv.bands_direction = 'X'
    wv.inputs['Scale'].default_value = 1.6; wv.inputs['Distortion'].default_value = 9.0; wv.inputs['Detail'].default_value = 4.0
    wv.inputs['Detail Scale'].default_value = 1.4
    nt.links.new(mp.outputs['Vector'], wv.inputs['Vector'])
    oi = nt.nodes.new('ShaderNodeObjectInfo')
    mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'
    mix.inputs['A'].default_value = H.lin(a); mix.inputs['B'].default_value = H.lin(b)
    f = nt.nodes.new('ShaderNodeMath'); f.operation = 'MULTIPLY_ADD'
    nt.links.new(wv.outputs['Fac'], f.inputs[0]); f.inputs[1].default_value = 0.55
    nt.links.new(oi.outputs['Random'], f.inputs[2])
    cl = nt.nodes.new('ShaderNodeClamp'); nt.links.new(f.outputs[0], cl.inputs['Value'])
    nt.links.new(cl.outputs[0], mix.inputs['Factor'])
    nt.links.new(mix.outputs['Result'], p.inputs['Base Color'])
    bp = nt.nodes.new('ShaderNodeBump'); bp.inputs['Strength'].default_value = 0.12; bp.inputs['Distance'].default_value = 0.01
    nt.links.new(wv.outputs['Fac'], bp.inputs['Height']); nt.links.new(bp.outputs['Normal'], p.inputs['Normal'])
    p.inputs['Roughness'].default_value = 0.62
    p.inputs['Specular IOR Level'].default_value = 0.4
    p.inputs['Subsurface Weight'].default_value = 0.04

def textured(name, a, b, scale, rough=0.9, bump=0.3, voronoi=None, stretch=(1, 1, 1)):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; p = nt.nodes['Principled BSDF']
    p.inputs['Roughness'].default_value = rough; p.inputs['Specular IOR Level'].default_value = 0.25
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping'); mp.inputs['Scale'].default_value = stretch
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    nz = node(nt, 'ShaderNodeTexNoise', Scale=scale, Detail=6.0, Roughness=0.62)
    nt.links.new(mp.outputs['Vector'], nz.inputs['Vector'])
    mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'
    mix.inputs['A'].default_value = H.lin(a); mix.inputs['B'].default_value = H.lin(b)
    nt.links.new(nz.outputs['Fac'], mix.inputs['Factor'])
    col = mix.outputs['Result']
    h = nz.outputs['Fac']
    if voronoi:
        vc, vs = voronoi
        vr = node(nt, 'ShaderNodeTexVoronoi', Scale=vs)
        nt.links.new(mp.outputs['Vector'], vr.inputs['Vector'])
        sm = nt.nodes.new('ShaderNodeMapRange')
        sm.inputs['From Min'].default_value = 0.0; sm.inputs['From Max'].default_value = 0.16
        sm.inputs['To Min'].default_value = 1.0; sm.inputs['To Max'].default_value = 0.0
        nt.links.new(vr.outputs['Distance'], sm.inputs['Value'])
        mx2 = nt.nodes.new('ShaderNodeMix'); mx2.data_type = 'RGBA'
        nt.links.new(col, mx2.inputs['A']); mx2.inputs['B'].default_value = H.lin(vc)
        thr = nt.nodes.new('ShaderNodeMath'); thr.operation = 'GREATER_THAN'; thr.inputs[1].default_value = 0.55
        nt.links.new(sm.outputs[0], thr.inputs[0])
        nt.links.new(thr.outputs[0], mx2.inputs['Factor'])
        col = mx2.outputs['Result']
        ad = nt.nodes.new('ShaderNodeMath'); ad.operation = 'MULTIPLY_ADD'; ad.inputs[1].default_value = 0.6
        nt.links.new(thr.outputs[0], ad.inputs[0]); nt.links.new(nz.outputs['Fac'], ad.inputs[2])
        h = ad.outputs[0]
    nt.links.new(col, p.inputs['Base Color'])
    bp = node(nt, 'ShaderNodeBump', Strength=bump, Distance=0.03)
    nt.links.new(h, bp.inputs['Height']); nt.links.new(bp.outputs['Normal'], p.inputs['Normal'])
    H.MATS[name] = m
    return m

def craft_materials():
    timber_grain(H.MATS['timber'], '#E2A865', '#B9783C')
    timber_grain(H.MATS['ply'], '#EFCB93', '#D3A467')
    textured('grass', '#86A65E', '#5F8544', 60.0, 0.95, 0.35)
    H.MATS['grass'].node_tree.nodes['Principled BSDF'].inputs['Specular IOR Level'].default_value = 0.08
    textured('topsoil', '#5B3F2C', '#3E2A1D', 24.0, 0.95, 0.6, voronoi=('#7A6656', 9.0))
    textured('clay', '#9E6C46', '#7C5233', 10.0, 0.95, 0.5, voronoi=('#B49C82', 5.0), stretch=(1, 1, 3))
    textured('stone', '#8E877C', '#6E685F', 18.0, 0.8, 0.4)
    # paver: warmer, slight variation already; make a touch rougher
    pv = H.MATS['paver'].node_tree.nodes['Principled BSDF']; pv.inputs['Roughness'].default_value = 0.88

def variant_materials(variant):
    # lit windows: warm, stronger at night
    lit = H.MATS['glass_lit'].node_tree.nodes['Principled BSDF']
    lit.inputs['Emission Color'].default_value = H.lin('#FFB65C')
    lit.inputs['Emission Strength'].default_value = 14.0 if variant == 'dark' else 2.5
    gl = H.MATS['glass'].node_tree.nodes['Principled BSDF']
    gl.inputs['Base Color'].default_value = H.lin('#2E364A'); gl.inputs['Roughness'].default_value = 0.08
    gl.inputs['Specular IOR Level'].default_value = 0.9

# ------------------------------------------------------------------ diorama block

def box(bm, c, s):
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(Vector(c)) @ Matrix.Diagonal((s[0], s[1], s[2], 1)))

def mk(name, mname, fn, bevel=0.0, smooth=False):
    me = bpy.data.meshes.new(name); bm = bmesh.new(); fn(bm); bm.to_mesh(me); bm.free()
    me.materials.append(H.MATS[mname])
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    if smooth:
        for p in me.polygons: p.use_smooth = True
    if bevel:
        bv = ob.modifiers.new('bevel', 'BEVEL'); bv.width = bevel; bv.segments = 3; bv.limit_method = 'ANGLE'
    ob['stage_req'] = -1; ob['t'] = 0.0; ob['role'] = ''; ob['kind'] = 'block'; ob['mats'] = mname
    H.OBJS.append(ob)
    return ob

BLOCK_BOTTOM = -1.55

def build_block():
    for n in ('lot_plinth', 'lot_lawn'):
        ob = bpy.data.objects.get(n)
        if ob:
            H.OBJS.remove(ob); bpy.data.objects.remove(ob)
    x0, x1, y0, y1 = H.LOT
    cx, cy, w, d = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
    mk('blk_grass', 'grass', lambda bm: box(bm, (cx, cy, -0.07), (w + 0.06, d + 0.06, 0.14)), bevel=0.05)
    mk('blk_topsoil', 'topsoil', lambda bm: box(bm, (cx, cy, -0.36), (w, d, 0.46)), bevel=0.03)
    mk('blk_clay', 'clay', lambda bm: box(bm, (cx, cy, (BLOCK_BOTTOM - 0.59) / 2), (w - 0.02, d - 0.02, -0.59 - BLOCK_BOTTOM)), bevel=0.04)
    # stones embedded in the two visible cut faces (x = x0, y = y0)
    rnd = random.Random(11)
    def stones(bm):
        for _ in range(30):
            r = rnd.uniform(0.1, 0.2)
            z = rnd.uniform(BLOCK_BOTTOM + 0.12, -0.25)
            if rnd.random() < 0.5:
                c = (x0 + r * 0.25, rnd.uniform(y0 + 0.3, y1 - 0.3), z)
            else:
                c = (rnd.uniform(x0 + 0.3, x1 - 0.3), y0 + r * 0.25, z)
            M = Matrix.Translation(Vector(c)) @ Matrix.Diagonal((r, r * rnd.uniform(0.7, 1.0), r * rnd.uniform(0.55, 0.8), 1))
            bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0, matrix=M)
    mk('blk_stones', 'stone', stones, smooth=True)
    # grass tufts along the lawn's front and left lip (soft fringe over the cut)
    def tufts(bm):
        for _ in range(160):
            if rnd.random() < 0.5:
                c = (x0 + rnd.uniform(-0.01, 0.05), rnd.uniform(y0, y1), -0.02)
            else:
                c = (rnd.uniform(x0, x1), y0 + rnd.uniform(-0.01, 0.05), -0.02)
            r = rnd.uniform(0.04, 0.08)
            M = Matrix.Translation(Vector(c)) @ Matrix.Diagonal((r, r, r * 1.3, 1))
            bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0, matrix=M)
    mk('blk_tufts', 'grass', tufts, smooth=True)

# ------------------------------------------------------------------ render setup

def setup_render(res, samples):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'; prefs.get_devices()
    for dv in prefs.devices: dv.use = (dv.type == 'METAL')
    sc.cycles.device = 'GPU'
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True; sc.cycles.adaptive_threshold = 0.01
    sc.cycles.use_denoising = True; sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = 8; sc.cycles.transparent_max_bounces = 8
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '8'
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'

def setup_camera():
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam'); cam.type = 'PERSP'; cam.lens = 50; cam.sensor_width = 36
    co = bpy.data.objects.new('cam', cam); sc.collection.objects.link(co); sc.camera = co
    target = Vector((0.85, -0.6, 1.55))
    az, el, dist = math.radians(-36), math.radians(21), 33.0
    # camera sits in front (-y), swung toward the left (-x) by az
    pos = target + Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))) * dist
    co.location = pos
    co.rotation_euler = (target - pos).to_track_quat('-Z', 'Y').to_euler()
    cam.clip_start = 1; cam.clip_end = 200
    frame_fit(co, target, pos)
    return co

def frame_fit(co, target, pos, fill=0.84, iters=4):
    """Dolly so the full lot + finished house spans `fill` of the frame, then centre it with lens shift."""
    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene; cam = co.data
    pts = [o.matrix_world @ Vector(c) for o in H.OBJS for c in o.bound_box]
    for _ in range(iters):
        bpy.context.view_layer.update()
        cam.shift_x = cam.shift_y = 0.0
        ndc = [world_to_camera_view(sc, co, p) for p in pts]
        xs = [v.x for v in ndc]; ys = [v.y for v in ndc]
        ext = max(max(xs) - min(xs), max(ys) - min(ys))
        d = (co.location - target)
        co.location = target + d * (ext / fill)
    bpy.context.view_layer.update()
    ndc = [world_to_camera_view(sc, co, p) for p in pts]
    xs = [v.x for v in ndc]; ys = [v.y for v in ndc]
    cam.shift_x = ((min(xs) + max(xs)) / 2 - 0.5)
    cam.shift_y = ((min(ys) + max(ys)) / 2 - 0.5) - 0.03   # leave room under the block for its cast shadow
    print('FRAME', round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), 'dist', round((co.location - target).length, 2))

def sun(name, frm, strength, angle, col):
    sc = bpy.context.scene
    L = bpy.data.lights.new(name, 'SUN'); L.energy = strength; L.angle = math.radians(angle); L.color = col
    o = bpy.data.objects.new(name, L); sc.collection.objects.link(o)
    o.rotation_euler = Vector(frm).normalized().to_track_quat('Z', 'Y').to_euler()
    return o

def point(name, loc, power, col, radius=0.1):
    sc = bpy.context.scene
    L = bpy.data.lights.new(name, 'POINT'); L.energy = power; L.color = col; L.shadow_soft_size = radius
    o = bpy.data.objects.new(name, L); sc.collection.objects.link(o); o.location = loc
    return o

def model_collection():
    rc = bpy.data.collections.get('model_only') or bpy.data.collections.new('model_only')
    for o in H.OBJS:
        if o.name not in rc.objects: rc.objects.link(o)
    return rc

def setup_lights(variant):
    sc = bpy.context.scene
    for o in [o for o in sc.objects if o.type == 'LIGHT' or o.name.startswith('shadow_catcher')]:
        bpy.data.objects.remove(o)
    w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
    bg = w.node_tree.nodes['Background']
    lights = {}
    if variant == 'light':
        bg.inputs['Color'].default_value = H.lin('#D8E2EE'); bg.inputs['Strength'].default_value = 0.34
        lights['key'] = sun('key', (-0.85, -0.45, 0.8), 4.0, 8, (1.0, 0.94, 0.84))       # soft warm sun, front-left high
        rim = sun('rim', (0.55, 0.95, 0.45), 3.4, 4, (1.0, 0.97, 0.92))                   # back-right rim
        lights['bounce'] = sun('bounce', (0.9, -0.3, 0.2), 0.35, 30, (0.9, 0.95, 1.0))     # cool fill on the right
        lights['bounce'].data.use_shadow = False
    else:
        bg.inputs['Color'].default_value = H.lin('#22305A'); bg.inputs['Strength'].default_value = 0.28
        lights['key'] = sun('key', (-0.7, -0.6, 0.75), 0.55, 5, (0.72, 0.8, 1.0))        # moonlight
        rim = sun('rim', (0.55, 0.95, 0.5), 3.2, 3, (0.62, 0.8, 1.0))                     # cool rim, strong
        lights['dusk'] = sun('dusk', (0.95, 0.15, 0.12), 0.35, 12, (1.0, 0.55, 0.35))      # last dusk glow, right
    rim.light_linking.receiver_collection = model_collection()   # rim lights the object, never throws a shadow at the viewer
    lights['rim'] = rim
    me = bpy.data.meshes.new('catcher'); s = 60
    me.from_pydata([(-s, -s, BLOCK_BOTTOM), (s, -s, BLOCK_BOTTOM), (s, s, BLOCK_BOTTOM), (-s, s, BLOCK_BOTTOM)], [], [(0, 1, 2, 3)])
    co = bpy.data.objects.new('shadow_catcher', me); sc.collection.objects.link(co); co.is_shadow_catcher = True
    return lights

NIGHT_LAMPS = []

def apply_state(st, variant):
    for name in NIGHT_LAMPS:
        o = bpy.data.objects.get(name)
        if o: bpy.data.objects.remove(o)
    NIGHT_LAMPS.clear()
    lit = st['stage'] >= 5
    for ob in H.OBJS:
        if ob['kind'] == 'block':
            ob.hide_render = False; continue
        b = H.is_built(ob, st)
        ob.hide_render = not b
        names = ob['mats'].split(',')
        for i, slot in enumerate(ob.material_slots):
            slot.material = H.MATS[names[i]]
        if 'glass_slot' in ob:
            ob.material_slots[ob['glass_slot']].material = H.MATS['glass_lit' if (lit and variant == 'dark') else 'glass']
        for m in ob.modifiers: m.show_render = True
    if variant == 'dark':
        warm = (1.0, 0.68, 0.36)
        if lit:
            NIGHT_LAMPS.append(pointn('porch_lamp', (1.6, -3.4, 2.3), 60, warm, 0.15))
            for (x, y) in ((-1.6, -3.4), (3.6, -0.6), (-3.6, -0.4)):   # window spill onto the lawn
                NIGHT_LAMPS.append(pointn('spill', (x, y, 1.4), 25, warm, 0.6))
        elif st['stage'] >= 2:
            NIGHT_LAMPS.append(pointn('work_lamp', (0.4, 0.2, 1.6), 260, warm, 0.25))   # site work lamp inside the frame

def pointn(*a, **k):
    # Lamps light the model only: on the shadow catcher they would read as a full-frame shadow
    # (the block hides the lamp from the ground plane), i.e. a dark box around the art.
    o = point(*a, **k)
    o.light_linking.receiver_collection = model_collection()
    return o.name

def render_to(path):
    bpy.context.scene.render.filepath = path
    t0 = time.time(); bpy.ops.render.render(write_still=True); return time.time() - t0

# ------------------------------------------------------------------ build motion

def anim(out, variant, fps, seconds):
    """Timber pieces of one stage advance (framing p ANIM_FROM -> ANIM_TO) drop into place, staggered."""
    st = dict(stage=2, p=ANIM_TO)
    apply_state(st, variant)
    pieces = sorted([o for o in H.OBJS if o['kind'] == 'frame' and ANIM_FROM < o['t'] <= ANIM_TO], key=lambda o: o['t'])
    base = {o.name: o.matrix_world.copy() for o in pieces}
    n = len(pieces); N = int(round(fps * seconds))
    dur = 0.42 * fps                       # each piece's flight
    hold = 0.18 * fps                      # settled hold at the end
    stagger = (N - dur - hold) / max(n - 1, 1)
    d = os.path.join(out, f'build_{variant}'); os.makedirs(d, exist_ok=True)
    def ease(x):                           # ease-out back, mild settle
        c1 = 1.25; c3 = c1 + 1
        return 1 + c3 * (x - 1) ** 3 + c1 * (x - 1) ** 2
    log = []
    for f in range(N):
        for i, o in enumerate(pieces):
            x = (f - i * stagger) / dur
            if x <= 0:
                o.hide_render = True; continue
            o.hide_render = False
            e = ease(min(x, 1.0))
            rise = 1.4 * (1 - e)
            piv = base[o.name].to_translation()
            M = Matrix.Translation((0, 0, rise)) @ base[o.name]
            o.matrix_world = M
        fn = os.path.join(d, f'f_{f:03d}.png')
        dt = render_to(fn); log.append(round(dt, 1))
        print('ANIM', variant, f, N, round(dt, 1), flush=True)
    for o in pieces:
        o.matrix_world = base[o.name]; o.hide_render = False
    return n, N, log

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--states', default='framing')
    ap.add_argument('--variants', default='light')
    ap.add_argument('--samples', type=int, default=128)
    ap.add_argument('--res', type=int, default=1206)
    ap.add_argument('--out', required=True)
    ap.add_argument('--anim', action='store_true')
    ap.add_argument('--fps', type=int, default=30)
    ap.add_argument('--seconds', type=float, default=2.0)
    ap.add_argument('--save-blend', default='')
    a = ap.parse_args()
    out = os.path.abspath(a.out); os.makedirs(out, exist_ok=True)
    H.build_all()
    craft_materials()
    build_block()
    setup_render(a.res, a.samples)
    setup_camera()
    meta = []
    for v in a.variants.split(','):
        variant_materials(v)
        setup_lights(v)
        if a.anim:
            n, N, log = anim(out, v, a.fps, a.seconds)
            meta.append(dict(anim=v, pieces=n, frames=N, fps=a.fps, sec_per_frame=sum(log) / len(log)))
            continue
        for s in a.states.split(','):
            apply_state(STATES[s], v)
            fn = os.path.join(out, f'craft_{s}_{v}.png')
            dt = render_to(fn)
            meta.append(dict(file=os.path.basename(fn), seconds=round(dt, 1), samples=a.samples, res=a.res))
            print('RENDERED', fn, round(dt, 1), flush=True)
    if a.save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.save_blend))
    with open(os.path.join(out, 'render-log.jsonl'), 'a') as f:
        for r in meta: f.write(json.dumps(r) + '\n')

if __name__ == '__main__':
    main()
