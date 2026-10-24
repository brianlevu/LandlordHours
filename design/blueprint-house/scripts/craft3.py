"""Direction CRAFT, pass 3: lighting + palette pass on top of craft2.py (geometry, camera, stages unchanged).

Spec: the dir-craft2 art-direction verdict (2026-10-23) and Brian's locked decisions (2026-10-24).
- One rig, two exposures. Light mode = DUSK (low 3000K sun behind-right, 10% cool fill); dark mode = NIGHT
  (5% cool #4A5A8A fill + one low drafting-cyan rim from back-right). No noon, no moon key.
- Windows are state. `--lit on`: warm 2700K interior (window emission, window spill area lamps onto the lawn,
  porch light whose railing balusters throw long shadows across the grass). `--lit off`: dark glass, no interior light.
  Framing stages have no windows: their "lit" state is a site work lamp on a tripod inside the frame.
- Palette cut to a warm family (cream siding, pine framing, darker unpainted trim; ochre retired), a cool family
  (sage lawn and foliage, near-black loam, one clay band) and one accent (terracotta roof). Door: greyed blueprint blue.
- Kitsch removed: flower boxes + flowers (the teal planters), soil-cut pebbles, the porch lantern, one chimney pot.

usage (bpy 5.0.1 venv, headless):
  .venv/bin/python craft3.py --states started,frame70,framing,half,complete --variants light,dark --lit on,off --out DIR
  .venv/bin/python craft3.py --anim --variants light,dark --samples 64 --out DIR        # framing drop, lit (work lamp)
  .venv/bin/python craft3.py --probes DIR/probes.json --out DIR                          # camera probes for measure3.py
Outputs: craft_<stage>_<variant>.png (lit) and craft_<stage>-unlit_<variant>.png, 1206² RGBA.
"""
import argparse, json, math, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Matrix
import craft2 as K
H, C = K.H, K.C

WARM = '#FFB46B'           # window glass glow (what the camera sees)
LAMP = '#FFBB80'           # ~2700K lamp light on the house (less orange than the glass, so siding stays cream)
LAWN_LAMP = '#FFB87C'      # the same bulbs as the lawn sees them: amber pool on sage, S ~0.6 (warmer pushed it to 0.8)
DUSK_SUN = (1.0, 0.70, 0.42)   # ~3000K
RIM = '#8FD3FF'            # drafting cyan
NIGHT_FILL = '#4A5A8A'

# ------------------------------------------------------------------ palette

def palette():
    P = K.pbr
    # warm family
    P('plaster', 'rough_wood', ('#EFE7DA', '#E7DECF'), 0.9, detail=0.12, nstr=0.35, rough=(0.55, 0.75), spec=0.4,
      edge=0.4, edge_r=0.006, ao=0.55, ao_dist=0.3, island_var=0.8, dirt_z=(0.15, 0.9, 0.2), grime='#7A7064')
    # trim: unpainted timber one shade darker than the framing (ochre paint retired)
    P('trim', 'rough_wood', ('#A98666', '#9C7A5B'), 0.8, detail=0.35, nstr=0.45, rough=(0.5, 0.7), spec=0.4,
      edge=0.45, edge_r=0.008, ao=0.45, ao_dist=0.25, grime='#3E3024')
    P('door', 'rough_wood', ('#3A4A6E', '#36456A'), 0.8, detail=0.2, nstr=0.35, rough=(0.35, 0.55), spec=0.5,
      edge=0.4, edge_r=0.008, ao=0.4, grime='#1C2234')
    # accent: terracotta roof (slightly muted), chimney brick pulled into the same family
    P('tile', 'worn_rock_natural_01', ('#CC6A4C', '#B4583D'), 1.4, detail=0.35, nstr=0.5, rough=(0.5, 0.75), spec=0.45,
      edge=0.55, edge_r=0.012, ao=0.6, ao_dist=0.3, grime='#4A2418')
    P('ridge', 'worn_rock_natural_01', ('#BE5A3F', '#AE5038'), 1.4, detail=0.35, nstr=0.5, rough=(0.5, 0.7), edge=0.5, ao=0.4, grime='#4A2418')
    P('brick', 'red_brick_03', ('#D69C82', '#CC9078'), 1.6, coords='BOX', raw=True, nstr=1.0, rough=(0.7, 0.95),
      edge=0.3, edge_r=0.01, ao=0.4, island_var=0.0)
    # neutrals
    P('slate', 'worn_rock_natural_01', ('#7C7873', '#6E6A65'), 1.3, detail=0.45, nstr=0.6, rough=(0.5, 0.8), edge=0.45, ao=0.5)
    P('copper', None, ('#5F5852', '#5F5852'), metal=0.35, rough=(0.4, 0.4), spec=0.5, edge=0.6, edge_r=0.006, ao=0.3)
    P('paver', 'worn_rock_natural_01', ('#CDC6B9', '#BDB5A7'), 1.0, coords='BOX', detail=0.5, nstr=0.9, rough=(0.75, 0.95),
      edge=0.45, edge_r=0.02, ao=0.5)
    P('trunk', 'rough_wood', ('#5E4C3E', '#4C3D32'), 0.6, detail=0.9, nstr=1.2, rough=(0.7, 0.95), edge=0.25, ao=0.5)
    # cool family: sage lawn, near-black loam with one clay band
    P('grass', 'leafy_grass', ('#76836A', '#6C7961'), 1.6, coords='BOX', detail=0.5, nstr=0.6, rough=(0.85, 1.0), spec=0.15,
      edge=0.0, edge_r=0, ao=0.0, island_var=0.0)
    P('topsoil', 'brown_mud_rocks_01', ('#2C2622', '#2C2622'), 1.6, coords='BOX', detail=0.7, nstr=1.0, rough=(0.8, 1.0),
      spec=0.2, edge=0.2, edge_r=0.02, ao=0.0, island_var=0.0)
    P('clay', 'excavated_soil_wall', ('#7A6556', '#7A6556'), 2.4, coords='BOX', detail=0.7, nstr=1.0, rough=(0.8, 1.0),
      spec=0.2, edge=0.2, edge_r=0.02, ao=0.0, island_var=0.0)
    K.leaf_mat('leaf', ('#5C7656', '#6E8668', '#4C6448', '#80957A'))
    K.leaf_mat('leaf_tree', ('#5A7454', '#6B8465', '#4A6246', '#84987C'))
    inner = H.MATS['foliage']; inner.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = H.lin('#283426')
    sage_blades()
    # interior glow + dark glass
    lit = H.MATS['glass_lit'].node_tree.nodes['Principled BSDF']
    lit.inputs['Base Color'].default_value = H.lin('#FFD7A0')
    lit.inputs['Emission Color'].default_value = H.lin(WARM)
    camera_only_emission(H.MATS['glass_lit'])
    gl = H.MATS['glass'].node_tree.nodes['Principled BSDF']
    gl.inputs['Base Color'].default_value = H.lin('#1E2433'); gl.inputs['Roughness'].default_value = 0.08
    gl.inputs['Specular IOR Level'].default_value = 0.9
    # work lamp parts
    for nm, col, em in (('lamp_metal', '#2A2B2E', 0.0), ('lamp_lens', '#FFE2B8', 1.0)):
        m = bpy.data.materials.new(nm); m.use_nodes = True; p = m.node_tree.nodes['Principled BSDF']
        p.inputs['Base Color'].default_value = H.lin(col); p.inputs['Roughness'].default_value = 0.45
        if em:
            p.inputs['Emission Color'].default_value = H.lin(WARM); p.inputs['Emission Strength'].default_value = 30.0
            camera_only_emission(m)
        H.MATS[nm] = m

def camera_only_emission(m):
    """Glowing glass reads as lit to the camera but does not flood the scene: the spill lamps do the lighting,
    so the light falls where we aim it (pools on the lawn) instead of washing every surface orange.
    Emission strength = dial x (camera ray + 3% leak). The dial lives on the node labelled 'dial'."""
    nt = m.node_tree; p = nt.nodes['Principled BSDF']
    lp = nt.nodes.new('ShaderNodeLightPath')
    dial = nt.nodes.new('ShaderNodeValue'); dial.label = dial.name = 'dial'
    dial.outputs[0].default_value = p.inputs['Emission Strength'].default_value
    k = K.math_(nt, 'ADD', lp.outputs['Is Camera Ray'], 0.03)
    K.L(nt, K.math_(nt, 'MULTIPLY', k, dial.outputs[0]), p.inputs['Emission Strength'])

def set_emission(m, v):
    m.node_tree.nodes['dial'].outputs[0].default_value = v

def sage_blades():
    """Blade grass in sage (hue ~90-100 before light, low chroma), still dark at the base and lighter at the tip."""
    m = bpy.data.materials.new('blade'); m.use_nodes = True
    nt = m.node_tree; p = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord'); sep = nt.nodes.new('ShaderNodeSeparateXYZ'); K.L(nt, tc.outputs['UV'], sep.inputs[0])
    geo = nt.nodes.new('ShaderNodeNewGeometry'); r = geo.outputs['Random Per Island']
    nz = K.N(nt, 'ShaderNodeTexNoise', Scale=0.35, Detail=2.0); K.L(nt, tc.outputs['Object'], nz.inputs['Vector'])
    tip = K.mixc(nt, H.lin('#A6C8B2'), H.lin('#B8CDB8'), K.maprange(nt, nz.outputs['Fac'], 0.4, 0.65))
    tip = K.mixc(nt, tip, H.lin('#9ABFA8'), K.maprange(nt, r, 0.0, 0.35, 0.6, 0.0))
    base = K.mixc(nt, H.lin('#587C6A'), H.lin('#668774'), r)
    c = K.mixc(nt, base, tip, K.maprange(nt, sep.outputs['Y'], 0.0, 1.0))
    K.L(nt, c, p.inputs['Base Color'])
    p.inputs['Roughness'].default_value = 0.6; p.inputs['Specular IOR Level'].default_value = 0.3
    tr = nt.nodes.new('ShaderNodeBsdfTranslucent'); K.L(nt, c, tr.inputs['Color'])
    mx = nt.nodes.new('ShaderNodeMixShader'); mx.inputs['Fac'].default_value = 0.25
    out = nt.nodes['Material Output']
    K.L(nt, p.outputs[0], mx.inputs[1]); K.L(nt, tr.outputs[0], mx.inputs[2]); K.L(nt, mx.outputs[0], out.inputs['Surface'])
    H.MATS['blade'] = m

# ------------------------------------------------------------------ kitsch removal

def drop(name):
    o = bpy.data.objects.get(name)
    if o:
        if o in H.OBJS: H.OBJS.remove(o)
        bpy.data.objects.remove(o)

def declutter():
    drop('porch_lantern')            # the day lantern (a grey box)
    drop('blk_stones')               # pebbles in the soil cut
    for o in [o for o in H.OBJS if o.name.startswith(('planter_',))]:
        drop(o.name)                 # flower boxes, leaves and blooms (built before we could stop them on old runs)
    # chimney: one pot, not two
    zb = H.F + 3.6
    shaft = [H.M_box((-1.4, 1.95, (zb + 7.95) / 2), (0.72, 0.72, 7.95 - zb))]
    corbel = [H.M_box((-1.4, 1.95, 8.0), (0.8, 0.8, 0.1)), H.M_box((-1.4, 1.95, 8.12), (0.76, 0.76, 0.14))]
    cap = [H.M_box((-1.4, 1.95, 8.27), (0.88, 0.88, 0.1))]
    pots = [K.cone_fn(Matrix.Translation((-1.4, 1.95, 8.43)), 0.1, 0.085, 0.24, 20)]
    K.replace_mesh(K.obj('chimney'), [('brick', shaft + corbel, []), ('capstone', cap, []), ('ridge', [], pots)], None)

def work_lamp():
    """A small tripod work lamp standing on the slab inside the frame (framing stages' "lit" state)."""
    x, y = -0.9, -1.4
    legs = []
    for k in range(3):
        a = math.radians(90 + k * 120)
        foot = Vector((x + 0.32 * math.cos(a), y + 0.32 * math.sin(a), H.F + 0.01))
        top = Vector((x, y, H.F + 1.05))
        d = top - foot
        legs.append(K.cone_fn(Matrix.Translation((foot + top) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4(), 0.018, 0.018, d.length, 8))
    mast = [K.cone_fn(Matrix.Translation((x, y, H.F + 1.35)), 0.022, 0.022, 0.65, 8)]
    head = H.M_box((x, y - 0.06, H.F + 1.72), (0.3, 0.12, 0.24))
    lens = H.M_box((x, y - 0.125, H.F + 1.72), (0.25, 0.012, 0.19))
    ob = H.new_obj('work_lamp_fixture', [('lamp_metal', [head], legs + mast), ('lamp_lens', [lens], [])], 99, 0.0, '', 'worklamp', bevel=0.006)
    ob.hide_render = True
    return ob

# ------------------------------------------------------------------ rig

def world(variant):
    sc = bpy.context.scene
    w = bpy.data.worlds.new('w3'); sc.world = w; w.use_nodes = True
    nt = w.node_tree; bg = nt.nodes['Background']
    env = nt.nodes.new('ShaderNodeTexEnvironment'); env.image = bpy.data.images.load(K.HDRI, check_existing=True)
    tc = nt.nodes.new('ShaderNodeTexCoord'); mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Rotation'].default_value = (0, 0, math.radians(200))
    K.L(nt, tc.outputs['Generated'], mp.inputs['Vector']); K.L(nt, mp.outputs['Vector'], env.inputs['Vector'])
    # flatten the HDRI to luminance, tint it: the sky is a fill, never a second key
    bw = nt.nodes.new('ShaderNodeRGBToBW'); K.L(nt, env.outputs['Color'], bw.inputs['Color'])
    # the pure-sky HDRI carries a sun disc: clip it, or it becomes a hard second key with a page shadow
    sky = K.math_(nt, 'MINIMUM', bw.outputs['Val'], 1.2)
    tint = '#A3ADC4' if variant == 'light' else NIGHT_FILL
    col = K.mixc(nt, H.lin(tint), H.lin(tint), 0.0)
    sc_ = nt.nodes.new('ShaderNodeVectorMath'); sc_.operation = 'SCALE'
    K.L(nt, col, sc_.inputs[0]); K.L(nt, sky, sc_.inputs['Scale'])
    K.L(nt, sc_.outputs['Vector'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = ARGS.fill_light if variant == 'light' else ARGS.fill_dark

def setup_lights(variant):
    sc = bpy.context.scene
    for o in [o for o in sc.objects if o.type == 'LIGHT' or o.name.startswith('shadow_catcher')]:
        bpy.data.objects.remove(o)
    world(variant)
    mc = C.model_collection()
    if variant == 'light':
        # dusk: low warm sun behind-right (~17 deg), lights the object only (no long page shadow)
        key = C.sun('dusk_sun', (-0.3, 1.0, 0.5), ARGS.sun, 2.0, DUSK_SUN)
        key.light_linking.receiver_collection = mc
        rim = C.sun('rim', (-0.3, 1.0, 0.5), ARGS.rim_light, 2.0, H.lin(RIM)[:3])
    else:
        rim = C.sun('rim', (-0.3, 1.0, 0.5), ARGS.rim_dark, 2.0, H.lin(RIM)[:3])    # ~30 deg elevation
    rim.light_linking.receiver_collection = mc
    me = bpy.data.meshes.new('catcher'); s = 60; zb = C.BLOCK_BOTTOM
    me.from_pydata([(-s, -s, zb), (s, -s, zb), (s, s, zb), (-s, s, zb)], [], [(0, 1, 2, 3)])
    co = bpy.data.objects.new('shadow_catcher', me); sc.collection.objects.link(co); co.is_shadow_catcher = True

LAMPS = []

def lawn_collection():
    lc = bpy.data.collections.get('lawn_only') or bpy.data.collections.new('lawn_only')
    for o in H.OBJS:
        if o.name.startswith(('blk_blades', 'blk_grass', 'lot_path', 'porch_step', 'shrub_')) and o.name not in lc.objects:
            lc.objects.link(o)
    return lc

def linked(o, lawn=False):
    o.light_linking.receiver_collection = lawn_collection() if lawn else C.model_collection()
    LAMPS.append(o.name)
    return o

def area(name, loc, direction, size, power, col, spread=180.0, lawn=False):
    L_ = bpy.data.lights.new(name, 'AREA'); L_.shape = 'RECTANGLE'; L_.size, L_.size_y = size
    L_.energy = power; L_.color = H.lin(col)[:3]; L_.spread = math.radians(spread)
    o = bpy.data.objects.new(name, L_); bpy.context.scene.collection.objects.link(o)
    o.location = loc; o.rotation_euler = Vector(direction).normalized().to_track_quat('-Z', 'Y').to_euler()
    return linked(o, lawn)

def spill_lamps(variant, scale):
    """One area lamp just outside each lit ground-floor window and the door glass, aimed out and down at the lawn.
    The porch railing sits between the porch window and the lawn, so its balusters throw long shadows."""
    for w in WALLS:
        for k, o in enumerate(w.openings):
            if o['z0'] > H.F + 1.5: continue
            u0, u1, z0, z1 = o['u0'], o['u1'], o['z0'], o['z1']
            if o['type'] == 'door':
                z0 = z0 + 1.15
            uc, zc = (u0 + u1) / 2, (z0 + z1) / 2
            d = w.n * math.cos(math.radians(38)) + Vector((0, 0, -math.sin(math.radians(38))))
            area('spill_%s_%d' % (w.name, k), w.P(uc, 0.16, zc), d, (u1 - u0, z1 - z0),
                 ARGS.spill * scale * (u1 - u0) * (z1 - z0), LAWN_LAMP, ARGS.spread, lawn=True)
    # porch ceiling light: low and behind the railing -> baluster shadows fan out over the grass
    p = C.point('porch_light', (1.0, -2.8, H.F + 1.45), ARGS.porch * scale, H.lin(LAMP)[:3], 0.03)
    linked(p)
    # the same bulb as seen by the lawn only: strong enough to pool on the grass without blowing out the deck
    q = C.point('porch_spill', (1.0, -2.8, H.F + 1.45), ARGS.porch_lawn * scale, H.lin(LAWN_LAMP)[:3], 0.03)
    linked(q, lawn=True)

def apply_state(st, variant, lit=True):
    for n in LAMPS:
        o = bpy.data.objects.get(n)
        if o: bpy.data.objects.remove(o)
    LAMPS.clear()
    scale = 1.0 if variant == 'dark' else ARGS.dusk_scale
    for ob in H.OBJS:
        if ob['kind'] == 'block':
            ob.hide_render = False; continue
        if ob['kind'] == 'worklamp':
            ob.hide_render = not (lit and st['stage'] == 2); continue
        ob.hide_render = not H.is_built(ob, st)
        names = ob['mats'].split(',')
        for i, slot in enumerate(ob.material_slots):
            slot.material = H.MATS[names[i]]
        if 'glass_slot' in ob:
            ob.material_slots[ob['glass_slot']].material = H.MATS['glass_lit' if lit else 'glass']
    set_emission(H.MATS['glass_lit'], ARGS.win_dark if variant == 'dark' else ARGS.win_light)
    set_emission(H.MATS['lamp_lens'], 40.0 if variant == 'dark' else 30.0)
    if not lit:
        return
    if st['stage'] >= 5:
        spill_lamps(variant, scale)
    elif st['stage'] >= 3:
        # half: open walls, so a warm interior lamp per storey spills through the studs
        for i, z in enumerate((H.F + 1.6, H.F + 4.0)):
            linked(C.point('interior_%d' % i, (0.0, 0.3, z), ARGS.interior * scale, H.lin(LAMP)[:3], 0.3))
    elif st['stage'] == 2:
        # a work lamp is small: at dusk it needs the full night power or the lit/unlit states look the same
        scale = max(scale, ARGS.dusk_work_scale) if variant == 'light' else scale
        # work lamp head, aimed out over the front-left lawn: studs throw long shadows
        linked(area('work_lamp', (-0.9, -1.52, H.F + 1.72), (-0.35, -1.0, -0.42), (0.24, 0.18), ARGS.work * scale, LAMP))
        # lawn-only twin: the studs throw a fan of long shadows across the grass, like the porch balusters
        linked(area('work_lamp_lawn', (-0.9, -1.55, H.F + 1.72), (-0.35, -1.0, -0.42), (0.24, 0.18), ARGS.work_lawn * scale,
                    LAWN_LAMP, lawn=True), lawn=True)

# ------------------------------------------------------------------ main

ARGS = None
WALLS = None

def probes(path):
    """Screen positions (pixels, 1206²) of fixed world points used by measure3.py."""
    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene; cam = sc.camera; R = sc.render.resolution_x
    def px(p):
        v = world_to_camera_view(sc, cam, Vector(p)); return [round(v.x * R, 1), round((1 - v.y) * R, 1)]
    def patch(pts): return [px(p) for p in pts]
    F = H.F
    out = dict(
        res=R,
        siding_left=patch([(-2.62, y, z) for y in (0.05, 0.5, 0.95) for z in (F + 1.2, F + 1.7, F + 2.2)]),
        siding_front=patch([(x, -2.42, z) for x in (-2.3, -2.05) for z in (F + 1.2, F + 1.7, F + 3.0)]),
        lawn_spill_frontleft=patch([(x, y, 0.06) for x in (-1.6, -1.35, -1.1) for y in (-3.1, -3.4, -3.7)]),
        lawn_spill_porch=patch([(x, y, 0.06) for x in (2.1, 2.35, 2.6) for y in (-4.3, -4.6, -4.9)]),
        lawn_dark=patch([(x, y, 0.06) for x in (4.6, 5.0, 5.4) for y in (-5.0, -5.3)] + [(x, y, 0.06) for x in (-3.6, -3.3) for y in (-5.2, -5.5)]),
        lawn_grid=patch([(x / 4.0, y / 4.0, 0.06) for x in range(-15, 23) for y in range(-22, 17)
                         if (x / 4.0 < -2.9 or y / 4.0 < -4.0) and not (0.2 < x / 4.0 < 2.0 and y / 4.0 < -3.9)]),
    )
    json.dump(out, open(path, 'w'))
    print('PROBES', path)

def main():
    global ARGS, WALLS
    ap = argparse.ArgumentParser()
    ap.add_argument('--states', default='complete')
    ap.add_argument('--variants', default='light,dark')
    ap.add_argument('--lit', default='on')
    ap.add_argument('--samples', type=int, default=128)
    ap.add_argument('--res', type=int, default=1206)
    ap.add_argument('--out', required=True)
    ap.add_argument('--anim', action='store_true')
    ap.add_argument('--fps', type=int, default=30)
    ap.add_argument('--seconds', type=float, default=2.0)
    ap.add_argument('--save-blend', default='')
    ap.add_argument('--probes', default='')
    # rig dials (defaults are the shipped values)
    ap.add_argument('--sun', type=float, default=4.0)
    ap.add_argument('--rim-light', type=float, default=0.0)
    ap.add_argument('--rim-dark', type=float, default=1.5)
    ap.add_argument('--fill-light', type=float, default=1.5)
    ap.add_argument('--fill-dark', type=float, default=0.45)
    ap.add_argument('--win-light', type=float, default=6.0)
    ap.add_argument('--win-dark', type=float, default=32.0)
    ap.add_argument('--spill', type=float, default=60.0)
    ap.add_argument('--spread', type=float, default=50.0)
    ap.add_argument('--porch', type=float, default=80.0)
    ap.add_argument('--porch-lawn', type=float, default=1500.0)
    ap.add_argument('--interior', type=float, default=500.0)
    ap.add_argument('--work', type=float, default=220.0)
    ap.add_argument('--work-lawn', type=float, default=900.0)
    ap.add_argument('--dusk-scale', type=float, default=0.5)
    ap.add_argument('--dusk-work-scale', type=float, default=1.6)
    a = ap.parse_args(); ARGS = a
    out = os.path.abspath(a.out); os.makedirs(out, exist_ok=True)
    t0 = time.time()
    K.flower_box = lambda *x, **k: None
    orig = K.craft2_materials
    def mats():
        orig(); palette()
    K.craft2_materials = mats
    WALLS = K.build(a)
    declutter()
    work_lamp()
    for o in H.OBJS:
        if o['kind'] == 'block':
            names = o['mats'].split(',')
            for i, sl in enumerate(o.material_slots): sl.material = H.MATS[names[i]]
    C.apply_state = lambda st, v: apply_state(st, v, True)     # the build-drop clip always plays lit
    print('BUILD', round(time.time() - t0, 1), flush=True)
    if a.probes:
        probes(a.probes); return
    meta = []
    for v in a.variants.split(','):
        setup_lights(v)
        if a.anim:
            n, Nf, log = C.anim(out, v, a.fps, a.seconds)
            meta.append(dict(anim=v, pieces=n, frames=Nf, fps=a.fps, sec_per_frame=round(sum(log) / len(log), 2), samples=a.samples))
            continue
        for lit in a.lit.split(','):
            for s in a.states.split(','):
                apply_state(C.STATES[s], v, lit == 'on')
                fn = os.path.join(out, f'craft_{s}_{v}.png' if lit == 'on' else f'craft_{s}-unlit_{v}.png')
                dt = C.render_to(fn)
                meta.append(dict(file=os.path.basename(fn), seconds=round(dt, 1), samples=a.samples, res=a.res))
                print('RENDERED', fn, round(dt, 1), flush=True)
    if a.save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.save_blend))
    with open(os.path.join(out, 'render-log.jsonl'), 'a') as f:
        for r in meta: f.write(json.dumps(dict(r, args=vars(a))) + '\n')

if __name__ == '__main__':
    main()
