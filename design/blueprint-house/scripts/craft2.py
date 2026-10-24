"""Direction CRAFT, pass 2: detail + materials on top of house.py / craft.py.

Keeps every object, stage_req / t value and the camera of craft.py (the app's stage logic and framing are unchanged).
Adds: per-piece UVs (grain along the long axis, end grain on cut faces), CC0 PBR texture detail tinted to the
palette, shader bevel edge highlights + AO grime, jittered roof tiles, segmented ridge caps, gutters + downpipes,
window head casings + aprons, flower boxes, porch railings + step, porch lantern, chimney corbel + cap,
blade grass, leaf-card foliage on the old clay silhouettes, CC0 HDRI fill.

usage: ~/tmp/lh-craft/.venv/bin/python craft2.py --states started,frame70,framing,half,complete --variants light,dark --out DIR
       ~/tmp/lh-craft/.venv/bin/python craft2.py --anim --variants light,dark --samples 64 --out DIR
"""
import argparse, json, math, os, random, sys, time, zlib
SCR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCR)
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix
import house as H
import craft as C

# CC0 Poly Haven textures + HDRI (fetch with fetch_ph.py); not committed (296 MB)
DL = os.environ.get('LH_CC0_DIR', os.path.expanduser('~/AgentScratch/landlordhours/2026-10-24/dir-craft2/downloads'))
HDRI = os.path.join(DL, 'kloofendal_48d_partly_cloudy_puresky', 'kloofendal_48d_partly_cloudy_puresky_2k.hdr')

# ------------------------------------------------------------------ texture helpers

_IMG = {}
_MEAN = {}

def img(tid, kind, colour=False):
    key = (tid, kind)
    if key not in _IMG:
        im = bpy.data.images.load(os.path.join(DL, tid, f'{tid}_{kind}_1k.jpg'), check_existing=True)
        im.colorspace_settings.name = 'sRGB' if colour else 'Non-Color'
        _IMG[key] = im
    return _IMG[key]

def lum_mean(tid):
    if tid not in _MEAN:
        im = img(tid, 'diff', True)
        px = np.empty(len(im.pixels), dtype=np.float32); im.pixels.foreach_get(px)
        px = px.reshape(-1, 4)[::7]
        _MEAN[tid] = float((px[:, 0] * 0.2126 + px[:, 1] * 0.7152 + px[:, 2] * 0.0722).mean())
    return _MEAN[tid]

def N(nt, kind, loc=None, **kw):
    n = nt.nodes.new(kind)
    for k, v in kw.items():
        n.inputs[k].default_value = v
    return n

def L(nt, a, b):
    nt.links.new(a, b)

def mixc(nt, a, b, fac, blend='MIX'):
    m = nt.nodes.new('ShaderNodeMix'); m.data_type = 'RGBA'; m.blend_type = blend
    m.clamp_result = True
    for slot, v in (('A', a), ('B', b)):
        if isinstance(v, tuple): m.inputs[slot].default_value = v
        else: L(nt, v, m.inputs[slot])
    if isinstance(fac, (int, float)): m.inputs['Factor'].default_value = fac
    else: L(nt, fac, m.inputs['Factor'])
    return m.outputs['Result']

def math_(nt, op, a, b=None, c=None, clamp=False):
    m = nt.nodes.new('ShaderNodeMath'); m.operation = op; m.use_clamp = clamp
    for i, v in enumerate((a, b, c)):
        if v is None: continue
        if isinstance(v, (int, float)): m.inputs[i].default_value = v
        else: L(nt, v, m.inputs[i])
    return m.outputs[0]

def maprange(nt, v, f0, f1, t0=0.0, t1=1.0):
    m = nt.nodes.new('ShaderNodeMapRange'); m.clamp = True
    m.inputs['From Min'].default_value = f0; m.inputs['From Max'].default_value = f1
    m.inputs['To Min'].default_value = t0; m.inputs['To Max'].default_value = t1
    L(nt, v, m.inputs['Value']); return m.outputs['Result']

def pbr(name, tid=None, tints=('#FFFFFF', '#FFFFFF'), tex_size=1.0, coords='UV', detail=0.6, nstr=0.6,
        rough=(0.6, 0.9), spec=0.35, edge=0.25, edge_r=0.012, ao=0.35, ao_dist=0.35, raw=False, island_var=1.0,
        endgrain=None, dirt_z=None, subsurf=0.0, metal=0.0, coat=0.0, grime='#3B2E22'):
    """Principled material: palette tint x texture luminance detail, texture normal + roughness, shader-bevel edge
    highlight (rounded edges catch light), AO grime in creases. Registered in H.MATS under `name`."""
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; p = nt.nodes['Principled BSDF']
    p.inputs['Specular IOR Level'].default_value = spec
    p.inputs['Metallic'].default_value = metal
    if coat: p.inputs['Coat Weight'].default_value = coat
    if subsurf: p.inputs['Subsurface Weight'].default_value = subsurf
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    tc = nt.nodes.new('ShaderNodeTexCoord')
    a, b = H.lin(tints[0]), H.lin(tints[1])
    rnd = math_(nt, 'MULTIPLY', geo.outputs['Random Per Island'], island_var)
    base = mixc(nt, a, b, rnd)
    nrm_out = None
    rough_out = None
    if tid:
        mp = nt.nodes.new('ShaderNodeMapping'); s = 1.0 / tex_size
        mp.inputs['Scale'].default_value = (s, s, s)
        L(nt, tc.outputs['UV' if coords == 'UV' else 'Object'], mp.inputs['Vector'])
        def T(kind, colour=False):
            t = nt.nodes.new('ShaderNodeTexImage'); t.image = img(tid, kind, colour)
            if coords == 'BOX': t.projection = 'BOX'; t.projection_blend = 0.25
            L(nt, mp.outputs['Vector'], t.inputs['Vector']); return t
        d = T('diff', True)
        if raw:
            base = mixc(nt, d.outputs['Color'], base, 1.0, 'MULTIPLY')
        else:
            bw = nt.nodes.new('ShaderNodeRGBToBW'); L(nt, d.outputs['Color'], bw.inputs['Color'])
            k = math_(nt, 'DIVIDE', bw.outputs['Val'], lum_mean(tid))
            k = math_(nt, 'MULTIPLY_ADD', math_(nt, 'SUBTRACT', k, 1.0), detail, 0.0)
            ma = nt.nodes.new('ShaderNodeMath'); ma.operation = 'ADD'; ma.inputs[1].default_value = 1.0
            L(nt, k, ma.inputs[0])
            sc = nt.nodes.new('ShaderNodeVectorMath'); sc.operation = 'SCALE'
            L(nt, base, sc.inputs[0]); L(nt, ma.outputs[0], sc.inputs['Scale'])
            base = sc.outputs['Vector']
        r = T('rough'); rough_out = maprange(nt, r.outputs['Color'], 0.0, 1.0, rough[0], rough[1])
        nn = T('nor_gl'); nmap = N(nt, 'ShaderNodeNormalMap', Strength=nstr); L(nt, nn.outputs['Color'], nmap.inputs['Color'])
        nrm_out = nmap.outputs['Normal']
    if endgrain:
        # cut faces (face attribute 'endgrain' = 1): darker, with growth rings centred on the piece
        at = nt.nodes.new('ShaderNodeAttribute'); at.attribute_type = 'GEOMETRY'; at.attribute_name = 'endgrain'
        wv = nt.nodes.new('ShaderNodeTexWave'); wv.wave_type = 'RINGS'
        wv.inputs['Scale'].default_value = 18.0; wv.inputs['Distortion'].default_value = 3.0
        wv.inputs['Detail'].default_value = 2.0
        L(nt, tc.outputs['UV'], wv.inputs['Vector'])
        ring = mixc(nt, H.lin(endgrain[0]), H.lin(endgrain[1]), wv.outputs['Fac'])
        base = mixc(nt, base, ring, at.outputs['Fac'])
    if dirt_z is not None:
        # rain splash / grime near the ground
        sep = nt.nodes.new('ShaderNodeSeparateXYZ'); L(nt, tc.outputs['Object'], sep.inputs[0])
        nz = N(nt, 'ShaderNodeTexNoise', Scale=6.0, Detail=4.0); L(nt, tc.outputs['Object'], nz.inputs['Vector'])
        zf = maprange(nt, sep.outputs['Z'], dirt_z[0], dirt_z[1], 1.0, 0.0)
        zf = math_(nt, 'MULTIPLY', zf, math_(nt, 'MULTIPLY_ADD', nz.outputs['Fac'], 0.8, 0.3))
        base = mixc(nt, base, H.lin(grime), math_(nt, 'MULTIPLY', zf, dirt_z[2], clamp=True))
    if ao:
        aon = nt.nodes.new('ShaderNodeAmbientOcclusion'); aon.inputs['Distance'].default_value = ao_dist; aon.samples = 8
        g = math_(nt, 'MULTIPLY', math_(nt, 'SUBTRACT', 1.0, aon.outputs['AO'], clamp=True), ao)
        base = mixc(nt, base, H.lin(grime), g, 'MULTIPLY')
    if edge_r:
        bev = nt.nodes.new('ShaderNodeBevel'); bev.samples = 8; bev.inputs['Radius'].default_value = edge_r
        if nrm_out: L(nt, nrm_out, bev.inputs['Normal'])
        nrm_out = bev.outputs['Normal']
        if edge:
            dp = nt.nodes.new('ShaderNodeVectorMath'); dp.operation = 'DOT_PRODUCT'
            L(nt, bev.outputs['Normal'], dp.inputs[0]); L(nt, geo.outputs['Normal'], dp.inputs[1])
            ef = maprange(nt, dp.outputs['Value'], 0.995, 0.86)
            nz = N(nt, 'ShaderNodeTexNoise', Scale=40.0, Detail=3.0); L(nt, tc.outputs['Object'], nz.inputs['Vector'])
            ef = math_(nt, 'MULTIPLY', ef, maprange(nt, nz.outputs['Fac'], 0.35, 0.6, 0.35, 1.0))
            light = nt.nodes.new('ShaderNodeVectorMath'); light.operation = 'SCALE'
            L(nt, base, light.inputs[0]); light.inputs['Scale'].default_value = 1.35
            base = mixc(nt, base, light.outputs['Vector'], math_(nt, 'MULTIPLY', ef, edge, clamp=True))
    L(nt, base, p.inputs['Base Color'])
    if rough_out: L(nt, rough_out, p.inputs['Roughness'])
    else: p.inputs['Roughness'].default_value = (rough[0] + rough[1]) / 2
    if nrm_out: L(nt, nrm_out, p.inputs['Normal'])
    m['base_hex'] = tints[0]
    H.MATS[name] = m
    return m

# ------------------------------------------------------------------ per-island UVs (grain along the long axis)

def island_uvs(ob, tex_jitter=True, seed=0):
    me = ob.data
    bm = bmesh.new(); bm.from_mesh(me)
    uvl = bm.loops.layers.uv.get('UVMap') or bm.loops.layers.uv.new('UVMap')
    eg = bm.faces.layers.float.get('endgrain') or bm.faces.layers.float.new('endgrain')
    bm.verts.ensure_lookup_table()
    parent = list(range(len(bm.verts)))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    for e in bm.edges:
        a, b = find(e.verts[0].index), find(e.verts[1].index)
        if a != b: parent[a] = b
    groups = {}
    for v in bm.verts:
        groups.setdefault(find(v.index), []).append(v.index)
    rnd = random.Random(seed + len(bm.verts))
    info = {}
    co = np.array([v.co[:] for v in bm.verts])
    for r, idx in groups.items():
        P = co[idx]; c = P.mean(0)
        if len(idx) < 4:
            ax = np.eye(3)
        else:
            w, V = np.linalg.eigh(np.cov((P - c).T) + np.eye(3) * 1e-9)
            ax = V[:, ::-1].T            # rows: long, mid, short
        off = (rnd.random() * 7.0, rnd.random() * 7.0) if tex_jitter else (0, 0)
        info[r] = (c, ax, off)
    for f in bm.faces:
        r = find(f.verts[0].index); c, ax, off = info[r]
        n = np.array(f.normal[:]); Lx = ax[0]
        end = abs(n.dot(Lx)) > 0.8
        f[eg] = 1.0 if end else 0.0
        if end:
            u_ax, v_ax = ax[1], ax[2]
        else:
            u_ax = np.cross(n, Lx); nn = np.linalg.norm(u_ax)
            u_ax = u_ax / nn if nn > 1e-6 else ax[1]
            v_ax = Lx                     # grain runs along V (texture grain is vertical)
        for lp in f.loops:
            p = np.array(lp.vert.co[:]) - c
            if end:
                lp[uvl].uv = (p.dot(u_ax) + 0.03, p.dot(v_ax) + 0.02)
            else:
                lp[uvl].uv = (p.dot(u_ax) + off[0], p.dot(v_ax) + off[1])
    bm.to_mesh(me); bm.free()

def jitter_islands(ob, rot_deg=2.0, tilt_deg=1.2, lift=0.004, seed=3):
    """Hand-laid feel: rotate each island (tile) a little about its own centre."""
    me = ob.data
    bm = bmesh.new(); bm.from_mesh(me)
    rnd = random.Random(seed)
    seen = set()
    for f in bm.faces:
        if f.index in seen: continue
        stack = [f]; isl = set()
        while stack:
            g = stack.pop()
            if g in isl: continue
            isl.add(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h not in isl: stack.append(h)
        for g in isl: seen.add(g.index)
        verts = {v for g in isl for v in g.verts}
        c = sum((v.co for v in verts), Vector()) / len(verts)
        nrm = sum((g.normal * g.calc_area() for g in isl), Vector())
        big = max(isl, key=lambda g: g.calc_area()); nrm = big.normal.copy()
        t = Vector((nrm.y, -nrm.x, 0)); t = t.normalized() if t.length > 1e-6 else Vector((1, 0, 0))
        R = (Matrix.Rotation(math.radians(rnd.uniform(-rot_deg, rot_deg)), 4, nrm) @
             Matrix.Rotation(math.radians(rnd.uniform(-tilt_deg, tilt_deg)), 4, t))
        d = nrm * rnd.uniform(-lift, lift)
        for v in verts:
            v.co = c + (R @ (v.co - c)) + d
    bm.to_mesh(me); bm.free()

# ------------------------------------------------------------------ materials

def craft2_materials():
    # timber framing: warm pine, grain from the CC0 rough_wood scan, end grain rings on cut faces
    pbr('timber', 'rough_wood', ('#E6AE6C', '#C98A4A'), 1.1, detail=0.75, nstr=0.9, rough=(0.55, 0.85), edge=0.35,
        edge_r=0.008, ao=0.4, ao_dist=0.25, endgrain=('#C7955E', '#9E6A3A'), subsurf=0.03)
    pbr('ply', 'plywood', ('#F0CB92', '#DDB177'), 1.2, detail=0.9, nstr=0.5, rough=(0.6, 0.85), edge=0.3, edge_r=0.006, ao=0.4)
    # painted lap siding: cream paint over wood grain, per-board shade, grime at the base and under eaves (AO)
    pbr('plaster', 'rough_wood', ('#F5ECDD', '#EDE1CF'), 0.9, detail=0.12, nstr=0.35, rough=(0.55, 0.75), spec=0.4,
        edge=0.45, edge_r=0.006, ao=0.55, ao_dist=0.3, island_var=0.8, dirt_z=(0.15, 0.9, 0.22), grime='#8C7B66')
    # painted trim (windows, porch, fascia): ochre timber paint, worn lighter edges
    pbr('trim', 'rough_wood', ('#C98446', '#B97538'), 0.8, detail=0.25, nstr=0.4, rough=(0.45, 0.65), spec=0.45,
        edge=0.55, edge_r=0.008, ao=0.45, ao_dist=0.25, grime='#5A3A22')
    pbr('door', 'rough_wood', ('#C17E40', '#B6743A'), 0.8, detail=0.25, nstr=0.4, rough=(0.35, 0.55), spec=0.5,
        edge=0.5, edge_r=0.008, ao=0.4)
    # clay roof tiles: three fired shades by tile, ceramic micro surface, light-catching rounded edges
    pbr('tile', 'worn_rock_natural_01', ('#D87050', '#B9573A'), 1.4, detail=0.35, nstr=0.5, rough=(0.5, 0.75), spec=0.45,
        edge=0.6, edge_r=0.012, ao=0.6, ao_dist=0.3, grime='#5A2A1A')
    pbr('ridge', 'worn_rock_natural_01', ('#C85A3E', '#B44E34'), 1.4, detail=0.35, nstr=0.5, rough=(0.5, 0.7), edge=0.5, ao=0.4, grime='#5A2A1A')
    pbr('slate', 'worn_rock_natural_01', ('#A8A6A2', '#8F8D88'), 1.3, detail=0.45, nstr=0.6, rough=(0.5, 0.8), edge=0.5, ao=0.5)
    pbr('brick', 'red_brick_03', ('#E89A72', '#D98A62'), 1.6, coords='BOX', raw=True, nstr=1.0, rough=(0.7, 0.95),
        edge=0.3, edge_r=0.01, ao=0.4, island_var=0.0)
    pbr('capstone', 'worn_rock_natural_01', ('#BDB6AA', '#B0A99D'), 1.2, coords='BOX', detail=0.5, nstr=0.7, rough=(0.7, 0.9), edge=0.5, ao=0.4)
    pbr('concrete', 'worn_rock_natural_01', ('#A29D94', '#97928A'), 2.0, coords='BOX', detail=0.45, nstr=0.5, rough=(0.8, 0.95),
        edge=0.4, edge_r=0.015, ao=0.5, island_var=0.3)
    pbr('paver', 'worn_rock_natural_01', ('#E4DCCD', '#CFC5B4'), 1.0, coords='BOX', detail=0.5, nstr=0.9, rough=(0.75, 0.95),
        edge=0.5, edge_r=0.02, ao=0.5)
    pbr('lintel', 'worn_rock_natural_01', ('#DAD5CC', '#CEC8BD'), 1.0, coords='BOX', detail=0.4, nstr=0.6, rough=(0.7, 0.9), edge=0.5)
    pbr('trunk', 'rough_wood', ('#8A6146', '#6E4A33'), 0.6, detail=0.9, nstr=1.2, rough=(0.7, 0.95), edge=0.3, ao=0.5)
    pbr('copper', None, ('#8C6A50', '#8C6A50'), metal=0.55, rough=(0.36, 0.36), spec=0.5, edge=0.5, edge_r=0.006, ao=0.3)
    pbr('brass', None, ('#D6B25E', '#D6B25E'), metal=0.9, rough=(0.3, 0.3), spec=0.5, edge=0.3, edge_r=0.003, ao=0.0)
    pbr('planter', 'rough_wood', ('#5E7C88', '#56727E'), 0.8, detail=0.3, nstr=0.4, rough=(0.5, 0.7), edge=0.6, edge_r=0.008, ao=0.4)
    # ground
    pbr('grass', 'leafy_grass', ('#86AE5C', '#76A050'), 1.6, coords='BOX', detail=0.6, nstr=0.6, rough=(0.85, 1.0), spec=0.15,
        edge=0.0, edge_r=0, ao=0.0, island_var=0.0)
    pbr('topsoil', 'brown_mud_rocks_01', ('#5E4230', '#5E4230'), 1.6, coords='BOX', detail=0.85, nstr=1.0, rough=(0.8, 1.0),
        spec=0.2, edge=0.25, edge_r=0.02, ao=0.0, island_var=0.0)
    pbr('clay', 'excavated_soil_wall', ('#A9774F', '#A9774F'), 2.4, coords='BOX', detail=0.8, nstr=1.0, rough=(0.8, 1.0),
        spec=0.2, edge=0.25, edge_r=0.02, ao=0.0, island_var=0.0)
    pbr('stone', 'worn_rock_natural_01', ('#8F877B', '#776F64'), 0.8, coords='BOX', detail=0.6, nstr=1.0, rough=(0.6, 0.9), edge=0.3, ao=0.3)
    # foliage
    leaf_mat('leaf', ('#5E9A48', '#7DB356', '#4B843E', '#9CC46A'))
    leaf_mat('leaf_tree', ('#5C9446', '#79AD52', '#47803B', '#A2C76C'))
    inner = bpy.data.materials.new('foliage_inner'); inner.use_nodes = True
    pi = inner.node_tree.nodes['Principled BSDF']; pi.inputs['Base Color'].default_value = H.lin('#2F5428'); pi.inputs['Roughness'].default_value = 0.9
    H.MATS['foliage'] = inner
    blade_mat()
    for nm, col in (('bloom_w', '#F6F1E7'), ('bloom_p', '#E9A3B5'), ('bloom_y', '#F2C94C')):
        b = bpy.data.materials.new(nm); b.use_nodes = True
        pb = b.node_tree.nodes['Principled BSDF']; pb.inputs['Base Color'].default_value = H.lin(col)
        pb.inputs['Roughness'].default_value = 0.6; pb.inputs['Subsurface Weight'].default_value = 0.2
        H.MATS[nm] = b
    lantern = bpy.data.materials.new('lantern_glass'); lantern.use_nodes = True
    pl = lantern.node_tree.nodes['Principled BSDF']; pl.inputs['Base Color'].default_value = H.lin('#F3E2BE')
    pl.inputs['Roughness'].default_value = 0.2
    H.MATS['lantern_glass'] = lantern

def leaf_mat(name, cols):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; p = nt.nodes['Principled BSDF']
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    r = geo.outputs['Random Per Island']
    c = mixc(nt, H.lin(cols[0]), H.lin(cols[1]), maprange(nt, r, 0.0, 0.5))
    c = mixc(nt, c, H.lin(cols[2]), maprange(nt, r, 0.55, 0.8))
    c = mixc(nt, c, H.lin(cols[3]), maprange(nt, r, 0.88, 1.0))
    aon = nt.nodes.new('ShaderNodeAmbientOcclusion'); aon.inputs['Distance'].default_value = 0.25; aon.samples = 6
    g = math_(nt, 'MULTIPLY', math_(nt, 'SUBTRACT', 1.0, aon.outputs['AO'], clamp=True), 0.55)
    c = mixc(nt, c, H.lin('#1E3A1C'), g, 'MULTIPLY')
    L(nt, c, p.inputs['Base Color'])
    p.inputs['Roughness'].default_value = 0.48; p.inputs['Specular IOR Level'].default_value = 0.45
    p.inputs['Subsurface Weight'].default_value = 0.0
    # thin leaves: let the key light glow through (translucency mix)
    tr = nt.nodes.new('ShaderNodeBsdfTranslucent'); L(nt, c, tr.inputs['Color'])
    mx = nt.nodes.new('ShaderNodeMixShader'); mx.inputs['Fac'].default_value = 0.22
    out = nt.nodes['Material Output']
    L(nt, p.outputs[0], mx.inputs[1]); L(nt, tr.outputs[0], mx.inputs[2]); L(nt, mx.outputs[0], out.inputs['Surface'])
    m['base_hex'] = cols[0]
    H.MATS[name] = m

def blade_mat():
    m = bpy.data.materials.new('blade'); m.use_nodes = True
    nt = m.node_tree; p = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord'); sep = nt.nodes.new('ShaderNodeSeparateXYZ'); L(nt, tc.outputs['UV'], sep.inputs[0])
    geo = nt.nodes.new('ShaderNodeNewGeometry'); r = geo.outputs['Random Per Island']
    # large-scale patchiness so the lawn isn't one flat green
    nz = N(nt, 'ShaderNodeTexNoise', Scale=0.35, Detail=2.0); L(nt, tc.outputs['Object'], nz.inputs['Vector'])
    tip = mixc(nt, H.lin('#A6CB6C'), H.lin('#C8D98C'), maprange(nt, nz.outputs['Fac'], 0.4, 0.65))
    tip = mixc(nt, tip, H.lin('#8DBA5C'), maprange(nt, r, 0.0, 0.35, 0.6, 0.0))
    base = mixc(nt, H.lin('#58833F'), H.lin('#6A9148'), r)
    c = mixc(nt, base, tip, maprange(nt, sep.outputs['Y'], 0.0, 1.0))
    L(nt, c, p.inputs['Base Color'])
    p.inputs['Roughness'].default_value = 0.55; p.inputs['Specular IOR Level'].default_value = 0.35
    tr = nt.nodes.new('ShaderNodeBsdfTranslucent'); L(nt, c, tr.inputs['Color'])
    mx = nt.nodes.new('ShaderNodeMixShader'); mx.inputs['Fac'].default_value = 0.35
    out = nt.nodes['Material Output']
    L(nt, p.outputs[0], mx.inputs[1]); L(nt, tr.outputs[0], mx.inputs[2]); L(nt, mx.outputs[0], out.inputs['Surface'])
    H.MATS['blade'] = m

# ------------------------------------------------------------------ mesh utilities

def mesh_obj(name, verts, face_groups, mname, uvs=None, stage_req=-1, t=0.0, kind='lot', role=''):
    """face_groups: list of (n, k) int arrays (homogeneous faces)."""
    me = bpy.data.meshes.new(name)
    verts = np.asarray(verts, dtype=np.float32)
    me.vertices.add(len(verts)); me.vertices.foreach_set('co', verts.ravel())
    sizes = np.concatenate([np.full(len(g), g.shape[1], np.int32) for g in face_groups])
    li = np.concatenate([np.asarray(g, np.int32).ravel() for g in face_groups])
    me.loops.add(len(li)); me.polygons.add(len(sizes))
    me.loops.foreach_set('vertex_index', li)
    starts = np.concatenate([[0], np.cumsum(sizes)[:-1]]).astype(np.int32)
    me.polygons.foreach_set('loop_start', starts)
    me.update(calc_edges=True)
    if uvs is not None:
        uvl = me.uv_layers.new(name='UVMap')
        uvl.data.foreach_set('uv', np.asarray(uvs, dtype=np.float32)[li].ravel())
    me.materials.append(H.MATS[mname])
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    ob['stage_req'] = stage_req; ob['t'] = float(t); ob['role'] = role; ob['kind'] = kind; ob['mats'] = mname
    H.OBJS.append(ob)
    return ob

def replace_mesh(ob, builders, mats, bevel=None):
    """Rebuild an existing object's mesh from (material, [box matrices], [bmesh fns]) groups; keeps stage props."""
    me = bpy.data.meshes.new(ob.name + '_v2'); bm = bmesh.new()
    for mi, (mname, boxes, extras) in enumerate(builders):
        before = set(bm.faces)
        for M in boxes: bmesh.ops.create_cube(bm, size=1.0, matrix=M)
        for fn in extras: fn(bm)
        for f in bm.faces:
            if f not in before: f.material_index = mi
    bm.to_mesh(me); bm.free()
    for mname, _, _ in builders: me.materials.append(H.MATS[mname])
    ob.data = me
    ob['mats'] = ','.join(b[0] for b in builders)
    if bevel is not None:
        for m in ob.modifiers:
            if m.type == 'BEVEL': m.width = bevel

def obj(name):
    return bpy.data.objects[name]

# ------------------------------------------------------------------ house detail

def detail_roof():
    for ob in H.OBJS:
        if ob.name.startswith('tiles_'):
            jitter_islands(ob, 2.2, 1.4, 0.005, seed=zlib.crc32(ob.name.encode()))
    # segmented, overlapping ridge caps (was one cylinder each)
    rz = H.E + H.RT + 2.6 * H.TT + 0.07
    y0, y1 = -2.4 - H.OH - 0.06, 3.0 + H.OH + 0.06
    fns = []
    n = int(math.ceil((y1 - y0) / 0.34))
    rnd = random.Random(5)
    for i in range(n):
        yc = y0 + 0.19 + i * (y1 - y0 - 0.38) / max(n - 1, 1)
        M = (Matrix.Translation((0, yc, rz + 0.004 * (i % 2))) @ Matrix.Rotation(math.radians(-90), 4, 'X') @
             Matrix.Rotation(math.radians(rnd.uniform(-1.5, 1.5)), 4, 'Y'))
        fns.append(cone_fn(M, 0.13, 0.118, 0.4, 18))
    replace_mesh(obj('ridgecap_m'), [('ridge', [], fns)], None)
    wz = H.E + H.RT + 1.2 * H.TT + 0.07
    x0, x1 = 2.6 - 0.05, 4.4 + H.OH + 0.06
    n = int(math.ceil((x1 - x0) / 0.34)); fns = []
    for i in range(n):
        xc = x0 + 0.19 + i * (x1 - x0 - 0.38) / max(n - 1, 1)
        M = (Matrix.Translation((xc, 1.8, wz + 0.004 * (i % 2))) @ Matrix.Rotation(math.radians(90), 4, 'Y'))
        fns.append(cone_fn(M, 0.12, 0.108, 0.4, 18))
    replace_mesh(obj('ridgecap_w'), [('ridge', [], fns)], None)
    for nm in ('ridgecap_m', 'ridgecap_w'):
        o = obj(nm)
        for p in o.data.polygons: p.use_smooth = True
    # chimney: brick shaft, corbelled brick course, stone cap, terracotta pot (same footprint and height)
    zb = H.F + 3.6
    shaft = [H.M_box((-1.4, 1.95, (zb + 7.95) / 2), (0.72, 0.72, 7.95 - zb))]
    corbel = [H.M_box((-1.4, 1.95, 8.0), (0.8, 0.8, 0.1)), H.M_box((-1.4, 1.95, 8.12), (0.76, 0.76, 0.14))]
    cap = [H.M_box((-1.4, 1.95, 8.27), (0.88, 0.88, 0.1))]
    pots = [cone_fn(Matrix.Translation((-1.52, 1.95, 8.43)), 0.1, 0.085, 0.24, 20),
            cone_fn(Matrix.Translation((-1.24, 1.95, 8.41)), 0.09, 0.08, 0.2, 20)]
    replace_mesh(obj('chimney'), [('brick', shaft + corbel, []), ('capstone', cap, []), ('ridge', [], pots)], None)

def cone_fn(M, r1, r2, depth, seg=16):
    def f(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r1, radius2=r2, depth=depth, matrix=M)
    return f

def halfpipe_fn(a, b, r, seg=14):
    """Open half-round gutter channel from a to b (axis horizontal), opening up."""
    a = Vector(a); b = Vector(b); d = (b - a).normalized()
    side = d.cross(Vector((0, 0, 1))).normalized()
    def f(bm):
        rings = []
        for p in (a, b):
            ring = []
            for k in range(seg + 1):
                ang = math.pi * k / seg
                off = side * (math.cos(ang) * r) + Vector((0, 0, -math.sin(ang) * r))
                ring.append(bm.verts.new(p + off))
            rings.append(ring)
        for k in range(seg):
            bm.faces.new((rings[0][k], rings[0][k + 1], rings[1][k + 1], rings[1][k]))
        # rolled bead on the outer lip
        for p0, p1 in ((a, b),):
            pass
    return f

def detail_gutters():
    """Half-round gutters on every eave the camera sees + downpipes at the corners (stage 4, with the porch)."""
    zg = H.E - 0.1
    gx = 2.6 + H.OH + 0.07
    runs = [((-gx, -2.4 - H.OH - 0.05, zg), (-gx, 3.0 + H.OH + 0.05, zg)),      # left eave (replaces the old tube)
            ((gx, -2.4 - H.OH - 0.05, zg), (gx, 0.6 - H.OH - 0.02, zg)),        # right eave, front of the wing
            ((2.6 + H.OH - 0.05, 0.6 - H.OH - 0.07, zg), (4.4 + H.OH + 0.05, 0.6 - H.OH - 0.07, zg))]   # wing front eave
    fns = [halfpipe_fn(a, b, 0.075) for a, b in runs]
    beads = []
    for a, b in runs:
        a = Vector(a); b = Vector(b); d = (b - a).normalized()
        side = d.cross(Vector((0, 0, 1))).normalized()
        out = side if side.dot(Vector((a.x, a.y, 0))) > 0 else -side
        if abs(a.x) < 1e-3 or True:
            pass
        mid = (a + b) / 2 + out * 0.075
        M = Matrix.Translation(mid) @ (d.to_track_quat('Z', 'Y').to_matrix().to_4x4())
        beads.append(cone_fn(M, 0.014, 0.014, (b - a).length, 8))
    pipes = []
    zt = zg - 0.38
    for (px, py), (gxp, gyp) in (((-2.71, -2.25), (-gx, -2.25)), ((2.71, -2.25), (gx, -2.25)), ((4.49, 0.5), (4.49, 0.6 - H.OH - 0.07))):
        a = Vector((gxp, gyp, zg - 0.04)); b = Vector((px, py, zt)); d = b - a
        pipes.append(cone_fn(Matrix.Translation((a + b) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4(), 0.045, 0.045, d.length + 0.04, 14))
        pipes.append(cone_fn(Matrix.Translation((px, py, (zt + 0.02) / 2)), 0.045, 0.045, zt - 0.02, 14))
        pipes.append(cone_fn(Matrix.Translation((px, py, 0.08)), 0.062, 0.058, 0.12, 14))       # shoe
        for zz in (0.9, 2.9, 4.4):                                                               # wall brackets
            pipes.append(cone_fn(Matrix.Translation((px, py, zz)), 0.056, 0.056, 0.05, 14))
    old = obj('downpipe')
    replace_mesh(old, [('copper', [], fns + beads + pipes)], None)
    for m in old.modifiers:
        if m.type == 'BEVEL': old.modifiers.remove(m)
    so = old.modifiers.new('solid', 'SOLIDIFY'); so.thickness = 0.012; so.offset = 1.0
    for p in old.data.polygons: p.use_smooth = True

def detail_windows(walls):
    """Head casing with drip cap + apron under every window sill; flower boxes under the two front ground windows."""
    for w in walls:
        for k, o in enumerate(w.openings):
            if o['type'] != 'win': continue
            u0, u1, z0, z1 = o['u0'], o['u1'], o['z0'], o['z1']
            fw = 0.09; bx = []
            def B(ua, ub, za, zb, off0, off1, lst):
                c = w.P((ua + ub) / 2, (off0 + off1) / 2, (za + zb) / 2)
                lst.append(H.M_box(c, (ub - ua, off1 - off0, zb - za), w.ang))
            if not o.get('lintel'):
                B(u0 - 0.15, u1 + 0.15, z1 + fw, z1 + fw + 0.11, 0.0, 0.12, bx)          # head casing
                B(u0 - 0.19, u1 + 0.19, z1 + fw + 0.11, z1 + fw + 0.145, 0.0, 0.16, bx)  # drip cap
            B(u0 - 0.06, u1 + 0.06, z0 - fw - 0.07 - 0.13, z0 - fw - 0.07, 0.0, 0.07, bx)   # apron
            ob = H.new_obj('casing_%s_%d' % (w.name, k), [('trim', bx, [])], 4, 0.0, 'major', 'unit', bevel=0.008)
            island_uvs(ob, seed=k)
            if w.name == 'front' and z0 < H.F + 1.5:
                flower_box(w, u0, u1, z0 - fw - 0.07 - 0.02, k)

def flower_box(w, u0, u1, ztop, k):
    bx = []
    zb = ztop - 0.26
    def B(ua, ub, za, zb_, off0, off1):
        c = w.P((ua + ub) / 2, (off0 + off1) / 2, (za + zb_) / 2)
        bx.append(H.M_box(c, (ub - ua, off1 - off0, zb_ - za), w.ang))
    B(u0 - 0.05, u1 + 0.05, zb, ztop, 0.06, 0.34)
    for uu in (u0 + 0.05, u1 - 0.05):                       # brackets
        B(uu - 0.03, uu + 0.03, zb - 0.14, zb, 0.02, 0.26)
    ob = H.new_obj('planter_%s_%d' % (w.name, k), [('planter', bx, [])], 5, 0.0, '', 'unit', bevel=0.01)
    island_uvs(ob, seed=k + 7)
    # plants: a low soft mound of leaves + blooms spilling over the front
    c0 = w.P((u0 + u1) / 2, 0.2, ztop)
    rnd = random.Random(31 + k)
    pts, nrms = [], []
    span = (u1 - u0) + 0.06
    for _ in range(420):
        uu = rnd.uniform(-span / 2, span / 2); vv = rnd.uniform(-0.12, 0.12)
        hh = 0.11 * math.sqrt(max(0.0, 1 - (2 * uu / span) ** 2)) * math.sqrt(max(0.0, 1 - (vv / 0.15) ** 2)) + rnd.uniform(0, 0.03)
        p = c0 + w.d * uu + w.n * vv + Vector((0, 0, hh))
        nr = (w.n * (vv / 0.15) + w.d * (2 * uu / span) * 0.5 + Vector((0, 0, 1.0))).normalized()
        pts.append(p); nrms.append(nr)
    leaves_object('planter_leaves_%s_%d' % (w.name, k), pts, nrms, 0.06, 0.03, 'leaf', 5, rnd)
    blooms = []
    for i in range(46):
        j = rnd.randrange(len(pts)); p = pts[j] + nrms[j] * 0.025
        blooms.append(H.sphere_fn(p, rnd.uniform(0.022, 0.032), 1, 0.85))
    H.new_obj('planter_blooms_%s_%d' % (w.name, k), [('bloom_p' if k == 0 else 'bloom_w', [], blooms)], 5, 0.0, '', 'unit', bevel=0, smooth=True)

def detail_porch():
    """Railings with balusters between the posts and the wall, a front step on the path line, a hanging lantern."""
    zd = 0.19                     # porch deck top
    rails = []
    def rail_run(a, b):
        a = Vector((a[0], a[1], 0)); b = Vector((b[0], b[1], 0)); d = b - a; Ln = d.length; dn = d.normalized()
        for z, h, wd in ((zd + 0.86, 0.07, 0.1), (zd + 0.16, 0.05, 0.07)):
            rails.append(H.M_line(a + Vector((0, 0, z)), b + Vector((0, 0, z)), wd, h, (0, 0, 1)))
        nb = int(Ln / 0.13)
        for i in range(1, nb):
            p = a + dn * (Ln * i / nb)
            rails.append(H.M_box((p.x, p.y, zd + 0.51), (0.035, 0.035, 0.66)))
    rail_run((-0.45, -3.78), (-0.45, -2.48))
    rail_run((2.8, -3.78), (2.8, -2.48))
    rail_run((-0.38, -3.85), (0.3, -3.85))
    rail_run((1.86, -3.85), (2.73, -3.85))
    for x in (0.3, 1.86):        # newel posts at the opening
        rails.append(H.M_box((x, -3.85, zd + 0.5), (0.11, 0.11, 1.0)))
        rails.append(H.M_box((x, -3.85, zd + 1.03), (0.15, 0.15, 0.05)))
    ob = H.new_obj('porch_rail', [('trim', rails, [])], 4, 0.97, 'major', 'porch', bevel=0.006)
    island_uvs(ob, seed=11)
    st = H.new_obj('porch_step', [('concrete', [H.M_box((1.08, -4.14, 0.05), (1.5, 0.3, 0.12))], [])], 1, 0, 'major', 'slab', bevel=0.02)
    # lantern under the porch beam (lit with the porch lamp at night)
    lx, ly, lz = 1.6, -3.55, H.F + 2.25
    frame = [H.M_box((lx, ly, lz + 0.2), (0.2, 0.2, 0.03)), H.M_box((lx, ly, lz - 0.17), (0.18, 0.18, 0.03)),
             H.M_box((lx, ly, lz + 0.3), (0.02, 0.02, 0.2))]
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.append(H.M_box((lx + sx * 0.08, ly + sy * 0.08, lz), (0.022, 0.022, 0.36)))
    gl = [H.M_box((lx, ly, lz + 0.015), (0.15, 0.15, 0.33))]
    lob = H.new_obj('porch_lantern', [('copper', frame, []), ('glass', gl, [])], 4, 0.97, '', 'porch', bevel=0.004)
    lob['glass_slot'] = 1

def detail_timber():
    for ob in H.OBJS:
        n = ob.name
        if (n.startswith(('frame_', 'rafter_', 'ridgeboard_', 'sill_plates', 'siding_', 'sheath_', 'tiles_', 'unit_', 'porch',
                          'roof_trim')) and ob.type == 'MESH' and n not in ('porch_step',)):
            if 'UVMap' not in ob.data.uv_layers or n.startswith(('frame_', 'rafter_', 'tiles_')):
                island_uvs(ob, seed=len(n))

# ------------------------------------------------------------------ ground

def in_poly(x, y, poly):
    inside = np.zeros_like(x, dtype=bool)
    n = len(poly)
    for i in range(n):
        xa, ya = poly[i]; xb, yb = poly[(i + 1) % n]
        cond = ((ya > y) != (yb > y)) & (x < (xb - xa) * (y - ya) / (yb - ya + 1e-12) + xa)
        inside ^= cond
    return inside

def grass_blades(seed=2):
    """Short stylised blade grass over the lawn: ~2 tris per blade, tip-light gradient in V, droop over the cut lip."""
    rng = np.random.default_rng(seed)
    x0, x1, y0, y1 = H.LOT
    n = 150000
    x = rng.uniform(x0 - 0.02, x1 + 0.02, n); y = rng.uniform(y0 - 0.02, y1 + 0.02, n)
    foot = [(px * 1.0, py * 1.0) for px, py in H.FOOT]
    keep = ~in_poly(x, y, [(px + (0.04 if px > 0 else -0.04), py + (0.04 if py > 0 else -0.04)) for px, py in foot])
    pv = []
    yy = y0 + 0.28; k = 0
    while yy < -4.05:
        for (xa, xb) in ([(0.45, 1.05), (1.11, 1.71)] if k % 2 == 0 else [(0.45, 0.75), (0.81, 1.41), (1.47, 1.71)]):
            pv.append((xa + 0.01, xb - 0.01, yy + 0.01, yy + 0.41))
        yy += 0.48; k += 1
    for (ax, bx, ay, by) in pv + [(-0.62, 2.97, -4.03, -2.5), (0.33, 1.83, -4.3, -3.99)]:
        keep &= ~((x > ax) & (x < bx) & (y > ay) & (y < by))
    x, y = x[keep], y[keep]; n = len(x)
    # edge fringe: extra blades on the two camera-facing lips, leaning out
    m = 9000
    ex = np.concatenate([rng.uniform(x0 - 0.03, x0 + 0.05, m // 2), rng.uniform(x0, x1, m // 2)])
    ey = np.concatenate([rng.uniform(y0, y1, m // 2), rng.uniform(y0 - 0.03, y0 + 0.05, m // 2)])
    keep = ~((ex > 0.33) & (ex < 1.83) & (ey < y0 + 0.3))     # path end
    ex, ey = ex[keep], ey[keep]
    x = np.concatenate([x, ex]); y = np.concatenate([y, ey]); n = len(x)
    edge = np.zeros(n, dtype=bool); edge[-len(ex):] = True
    h = rng.uniform(0.05, 0.1, n) * (1 + 0.25 * np.sin(x * 1.3 + y * 0.9))
    w = rng.uniform(0.022, 0.034, n)
    yaw = rng.uniform(0, 2 * np.pi, n)
    lean = rng.uniform(0.05, 0.5, n)
    la = rng.uniform(0, 2 * np.pi, n)
    # fringe leans outward over the cut
    out = np.where(np.abs(x - x0) < np.abs(y - y0), np.pi, -np.pi / 2)
    la = np.where(edge, out + rng.uniform(-0.6, 0.6, n), la)
    lean = np.where(edge, rng.uniform(0.6, 1.1, n), lean)
    d = np.stack([np.cos(la) * np.sin(lean), np.sin(la) * np.sin(lean), np.cos(lean)], 1)
    s = np.stack([np.cos(yaw), np.sin(yaw), np.zeros(n)], 1)
    s = s - d * (s * d).sum(1, keepdims=True); s /= np.linalg.norm(s, axis=1, keepdims=True) + 1e-9
    b = np.stack([x, y, np.full(n, -0.012)], 1)
    bend = np.stack([np.cos(la), np.sin(la), np.zeros(n)], 1) * (h * lean * 0.35)[:, None]
    mid = b + d * (h * 0.55)[:, None]
    tip = b + d * h[:, None] + bend
    V = np.empty((n, 5, 3), np.float32)
    V[:, 0] = b - s * (w / 2)[:, None]; V[:, 1] = b + s * (w / 2)[:, None]
    V[:, 2] = mid + s * (w * 0.32)[:, None]; V[:, 3] = mid - s * (w * 0.32)[:, None]; V[:, 4] = tip
    UV = np.tile(np.array([[0, 0], [1, 0], [0.8, 0.55], [0.2, 0.55], [0.5, 1.0]], np.float32), (n, 1))
    base = (np.arange(n) * 5)[:, None]
    quads = base + np.array([0, 1, 2, 3]); tris = base + np.array([3, 2, 4])
    ob = mesh_obj('blk_blades', V.reshape(-1, 3), [quads, tris], 'blade', UV, kind='block')
    ob['kind'] = 'block'
    print('GRASS blades', n, 'tris', n * 3)
    return n * 3

def ground_detail():
    t = obj('blk_tufts')
    H.OBJS.remove(t); bpy.data.objects.remove(t)
    st = obj('blk_stones')
    for p in st.data.polygons: p.use_smooth = True

# ------------------------------------------------------------------ foliage

def sample_surface(ob, mat_index=None, density=1000.0, cap=None, seed=0):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg); me = ev.to_mesh()
    me.calc_loop_triangles()
    tri = np.empty(len(me.loop_triangles) * 3, np.int32); me.loop_triangles.foreach_get('vertices', tri); tri = tri.reshape(-1, 3)
    mi = np.empty(len(me.loop_triangles), np.int32); me.loop_triangles.foreach_get('material_index', mi)
    co = np.empty(len(me.vertices) * 3, np.float32); me.vertices.foreach_get('co', co); co = co.reshape(-1, 3)
    vn = np.empty(len(me.vertices) * 3, np.float32); me.vertices.foreach_get('normal', vn); vn = vn.reshape(-1, 3)
    ev.to_mesh_clear()
    if mat_index is not None:
        tri = tri[mi == mat_index]
    A, B, Cc = co[tri[:, 0]], co[tri[:, 1]], co[tri[:, 2]]
    area = np.linalg.norm(np.cross(B - A, Cc - A), axis=1) / 2
    # drop faces buried inside neighbouring blobs: keep faces whose centroid is not inside another sphere
    rng = np.random.default_rng(seed)
    k = int(area.sum() * density)
    if cap: k = min(k, cap)
    idx = rng.choice(len(tri), k, p=area / area.sum())
    r1 = np.sqrt(rng.random(k)); r2 = rng.random(k)
    P = A[idx] * (1 - r1)[:, None] + B[idx] * (r1 * (1 - r2))[:, None] + Cc[idx] * (r1 * r2)[:, None]
    Nn = vn[tri[idx, 0]] * (1 - r1)[:, None] + vn[tri[idx, 1]] * (r1 * (1 - r2))[:, None] + vn[tri[idx, 2]] * (r1 * r2)[:, None]
    Nn /= np.linalg.norm(Nn, axis=1, keepdims=True) + 1e-9
    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromObject(ob, dg)
    keep = np.ones(len(P), bool)
    for i in range(len(P)):
        o = Vector(P[i]) + Vector(Nn[i]) * 0.004
        hit = bvh.ray_cast(o, Vector(Nn[i]), 0.25)
        if hit[0] is not None: keep[i] = False
    P, Nn = P[keep], Nn[keep]
    M = np.array(ob.matrix_world)
    P = P @ M[:3, :3].T + M[:3, 3]; Nn = Nn @ M[:3, :3].T
    return P, Nn

def leaves_object(name, pts, nrms, size, jitter, mname, stage_req, rnd=None, kind='lot', fold=0.18):
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    P = np.asarray([tuple(p) for p in pts], np.float32); Nn = np.asarray([tuple(v) for v in nrms], np.float32)
    n = len(P)
    # random tilt of the leaf normal away from the surface normal
    t = rng.normal(0, 0.55, (n, 3)).astype(np.float32)
    nn = Nn + t; nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-9
    up = np.where(np.abs(nn[:, 2:3]) > 0.9, np.array([[1, 0, 0]], np.float32), np.array([[0, 0, 1]], np.float32))
    a1 = np.cross(up, nn); a1 /= np.linalg.norm(a1, axis=1, keepdims=True) + 1e-9
    a2 = np.cross(nn, a1)
    ang = rng.uniform(0, 2 * np.pi, n)
    L_ = (a1 * np.cos(ang)[:, None] + a2 * np.sin(ang)[:, None])           # leaf length axis
    W_ = np.cross(nn, L_)
    s = size * rng.uniform(0.75, 1.25, n)
    wdt = s * 0.48
    base = P + Nn * rng.uniform(-0.2, 1.0, n)[:, None] * jitter - L_ * (s * 0.3)[:, None]
    # leaf: base, two shoulders, two upper sides, tip; sides drop along -n to fold the leaf about the midrib
    prof = [(0, 0.0, 0), (-0.5, 0.33, 1), (0.5, 0.33, 1), (-0.36, 0.7, 1), (0.36, 0.7, 1), (0, 1.0, 0)]
    V = np.empty((n, 6, 3), np.float32)
    for i, (wx, ly, side) in enumerate(prof):
        V[:, i] = base + L_ * (s * ly)[:, None] + W_ * (wdt * wx)[:, None] - nn * (wdt * fold * side)[:, None]
    UV = np.tile(np.array([[0.5, 0], [0, .33], [1, .33], [.1, .7], [.9, .7], [.5, 1]], np.float32), (n, 1))
    b = (np.arange(n) * 6)[:, None]
    f1 = b + np.array([0, 2, 1]); f2 = b + np.array([1, 2, 4, 3]); f3 = b + np.array([3, 4, 5])
    ob = mesh_obj(name, V.reshape(-1, 3), [f1, f2, f3], mname, UV, stage_req=stage_req, kind=kind)
    return ob

def foliage_detail():
    total = 0
    for ob in list(H.OBJS):
        if ob.name.startswith('shrub_') and not ob.name.endswith('_leaves'):
            P, Nn = sample_surface(ob, None, density=1500.0, seed=len(ob.name) + int(ob.name[-2:]))
            # skip samples buried inside the blob cluster (pointing down into the lawn)
            keep = P[:, 2] > 0.03
            leaves_object(ob.name + '_leaves', P[keep], Nn[keep], 0.085, 0.03, 'leaf', -1)
            total += int(keep.sum())
            for s in ob.material_slots: s.material = H.MATS['foliage']
    tree = obj('tree')
    P, Nn = sample_surface(tree, 1, density=900.0, seed=9)
    leaves_object('tree_leaves', P, Nn, 0.13, 0.05, 'leaf_tree', -1)
    total += len(P)
    # extra limbs reaching into the crown so the canopy reads as carried by branches
    tx, ty = -3.18, 3.68
    rnd = random.Random(4)
    limbs = []
    for (dx, dy, dz) in ((0.45, -0.3, 2.3), (-0.45, 0.25, 2.25), (0.1, 0.45, 2.5), (-0.15, -0.45, 2.45), (0.05, 0.0, 2.85)):
        a = Vector((tx, ty, 1.45)); b = Vector((tx + dx, ty + dy, dz))
        d = b - a
        M = Matrix.Translation((a + b) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
        limbs.append(cone_fn(M, 0.06, 0.03, d.length, 10))
    H.new_obj('tree_limbs', [('trunk', [], limbs)], -1, 0, '', 'lot', bevel=0, smooth=True)
    print('LEAVES', total, 'tris', total * 4)
    return total * 4

# ------------------------------------------------------------------ world

def hdri_world(variant):
    sc = bpy.context.scene
    w = sc.world; nt = w.node_tree
    bg = nt.nodes['Background']
    env = nt.nodes.new('ShaderNodeTexEnvironment'); env.image = bpy.data.images.load(HDRI, check_existing=True)
    tc = nt.nodes.new('ShaderNodeTexCoord'); mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Rotation'].default_value = (0, 0, math.radians(200))
    L(nt, tc.outputs['Generated'], mp.inputs['Vector']); L(nt, mp.outputs['Vector'], env.inputs['Vector'])
    tint = bg.inputs['Color'].default_value[:]
    mul = mixc(nt, env.outputs['Color'], tuple(tint), 1.0 if variant == 'dark' else 0.55, 'MULTIPLY')
    L(nt, mul, bg.inputs['Color'])
    bg.inputs['Strength'].default_value = 0.42 if variant == 'light' else 0.3

# ------------------------------------------------------------------ main

def stats():
    tris = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in H.OBJS:
        if o.type != 'MESH': continue
        ev = o.evaluated_get(dg); me = ev.to_mesh(); me.calc_loop_triangles(); tris += len(me.loop_triangles); ev.to_mesh_clear()
    return tris

def build(args):
    walls, rows = H.build_all()
    C.craft_materials()
    C.build_block()
    C.setup_render(args.res, args.samples)
    cam = C.setup_camera()                      # same objects as craft.py -> identical framing
    craft2_materials()
    ground_detail()
    detail_roof()
    detail_gutters()
    detail_windows(walls)
    detail_porch()
    detail_timber()
    g = grass_blades()
    lv = foliage_detail()
    for o in H.OBJS:
        if o['kind'] == 'block':
            names = o['mats'].split(',')
            for i, sl in enumerate(o.material_slots): sl.material = H.MATS[names[i]]
    return walls

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--states', default='complete')
    ap.add_argument('--variants', default='light')
    ap.add_argument('--samples', type=int, default=128)
    ap.add_argument('--res', type=int, default=1206)
    ap.add_argument('--out', required=True)
    ap.add_argument('--anim', action='store_true')
    ap.add_argument('--fps', type=int, default=30)
    ap.add_argument('--seconds', type=float, default=2.0)
    ap.add_argument('--save-blend', default='')
    ap.add_argument('--stats', action='store_true')
    a = ap.parse_args()
    out = os.path.abspath(a.out); os.makedirs(out, exist_ok=True)
    t0 = time.time()
    build(a)
    print('BUILD', round(time.time() - t0, 1), flush=True)
    if a.stats:
        print('TRIS', stats())
    meta = []
    for v in a.variants.split(','):
        C.variant_materials(v)
        C.setup_lights(v)
        hdri_world(v)
        if a.anim:
            n, Nf, log = C.anim(out, v, a.fps, a.seconds)
            meta.append(dict(anim=v, pieces=n, frames=Nf, fps=a.fps, sec_per_frame=round(sum(log) / len(log), 2), samples=a.samples))
            continue
        for s in a.states.split(','):
            C.apply_state(C.STATES[s], v)
            fn = os.path.join(out, f'craft_{s}_{v}.png')
            dt = C.render_to(fn)
            meta.append(dict(file=os.path.basename(fn), seconds=round(dt, 1), samples=a.samples, res=a.res))
            print('RENDERED', fn, round(dt, 1), flush=True)
    if a.save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.save_blend))
    with open(os.path.join(out, 'render-log.jsonl'), 'a') as f:
        for r in meta: f.write(json.dumps(r) + '\n')

if __name__ == '__main__':
    main()
