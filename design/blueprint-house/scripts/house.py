"""LandlordHours 2.0 "Blueprint" house — one procedural Blender scene.

Every object carries custom props:
  stage_req (int), t (float 0..1)  -> built when stage > stage_req, or stage == stage_req and t <= p
  role ('major'|'detail'|'')        -> drawn as cyan linework while unbuilt (finished-house skin only)
  kind                              -> grouping label

Run through render.py (bpy module, Python 3.11 venv).
"""
import math, random
import bpy, bmesh
from mathutils import Vector, Matrix

TH = math.radians(42.0)          # roof pitch
TT = math.tan(TH)
F = 0.25                         # floor level (top of slab)
E = F + 5.0                      # eave / wall-top height
DR = 0.18                        # rafter depth (perpendicular)
RT = DR / math.cos(TH)           # vertical rafter thickness
OH = 0.35                        # roof overhang
SD = 0.16                        # stud depth
SW = 0.09                        # stud width
PL = 0.08                        # plate thickness

random.seed(41100)

# ---------------------------------------------------------------- colour/materials

def lin(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)

MATS = {}

def mat(name, hexa, rough=0.8, hexb=None, metal=0.0, spec=0.35, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes['Principled BSDF']
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    p.inputs['Specular IOR Level'].default_value = spec
    if coat:
        p.inputs['Coat Weight'].default_value = coat
    if hexb:
        oi = nt.nodes.new('ShaderNodeObjectInfo')
        mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'
        mix.inputs['A'].default_value = lin(hexa); mix.inputs['B'].default_value = lin(hexb)
        nt.links.new(oi.outputs['Random'], mix.inputs['Factor'])
        nt.links.new(mix.outputs['Result'], p.inputs['Base Color'])
    else:
        p.inputs['Base Color'].default_value = lin(hexa)
    m['base_hex'] = hexa
    MATS[name] = m
    return m

def foliage(name, a, b, c):
    """Clay foliage: two greens mixed by a soft noise, a per-object tint and a gentle bump."""
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; p = nt.nodes['Principled BSDF']
    p.inputs['Roughness'].default_value = 0.82; p.inputs['Specular IOR Level'].default_value = 0.3
    tc = nt.nodes.new('ShaderNodeTexCoord')
    nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = 3.2; nz.inputs['Detail'].default_value = 2.0
    nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    ramp = nt.nodes.new('ShaderNodeMix'); ramp.data_type = 'RGBA'
    ramp.inputs['A'].default_value = lin(b); ramp.inputs['B'].default_value = lin(a)
    nt.links.new(nz.outputs['Fac'], ramp.inputs['Factor'])
    oi = nt.nodes.new('ShaderNodeObjectInfo')
    mr = nt.nodes.new('ShaderNodeMath'); mr.operation = 'MULTIPLY'; mr.inputs[1].default_value = 0.45
    nt.links.new(oi.outputs['Random'], mr.inputs[0])
    tint = nt.nodes.new('ShaderNodeMix'); tint.data_type = 'RGBA'
    tint.inputs['B'].default_value = lin(c)
    nt.links.new(ramp.outputs['Result'], tint.inputs['A']); nt.links.new(mr.outputs[0], tint.inputs['Factor'])
    nt.links.new(tint.outputs['Result'], p.inputs['Base Color'])
    bn = nt.nodes.new('ShaderNodeBump'); bn.inputs['Strength'].default_value = 0.25; bn.inputs['Distance'].default_value = 0.05
    nz2 = nt.nodes.new('ShaderNodeTexNoise'); nz2.inputs['Scale'].default_value = 14.0
    nt.links.new(tc.outputs['Object'], nz2.inputs['Vector'])
    nt.links.new(nz2.outputs['Fac'], bn.inputs['Height']); nt.links.new(bn.outputs['Normal'], p.inputs['Normal'])
    m['base_hex'] = a
    MATS[name] = m
    return m

def make_materials():
    mat('stone', '#E6E0D6', 0.85)
    mat('paver', '#EDE7DC', 0.8, '#E2DACB')
    mat('lawn', '#B3CB98', 0.9)
    mat('shrub', '#84AE68', 0.75, '#6A9A58')
    mat('trunk', '#9A6B45', 0.8)
    foliage('foliage', '#86B26A', '#5E9150', '#A6C982')
    mat('concrete', '#D3CEC6', 0.9, '#CBC5BB')
    mat('timber', '#E8B474', 0.72, '#DDA35E')       # framing
    mat('ply', '#EBC994', 0.8, '#E2BC80')           # sheathing
    mat('tile', '#D46A4A', 0.62, '#C95E40')         # terracotta roof
    mat('ridge', '#C85A3E', 0.6)
    mat('trim', '#CB8442', 0.6)                     # window/porch timber
    mat('door', '#C98545', 0.55)
    mat('plaster', '#F4EBDD', 0.82)                 # clapboard, painted cream
    mat('lintel', '#DAD6CF', 0.85)
    mat('slate', '#A9A7A2', 0.75, '#9C9A95')
    mat('brick', '#B86A3F', 0.85, '#AD5F38')
    mat('copper', '#C27A55', 0.5, None, 0.3)
    mat('brass', '#D9B45A', 0.32, None, 0.85)
    mat('flag', '#E07A3A', 0.7)
    mat('string', '#F4EFE6', 0.6)
    g = bpy.data.materials.new('glass'); g.use_nodes = True
    p = g.node_tree.nodes['Principled BSDF']
    p.inputs['Base Color'].default_value = lin('#46506B'); p.inputs['Roughness'].default_value = 0.22
    p.inputs['Specular IOR Level'].default_value = 0.6
    MATS['glass'] = g
    lit = bpy.data.materials.new('glass_lit'); lit.use_nodes = True
    p = lit.node_tree.nodes['Principled BSDF']
    p.inputs['Base Color'].default_value = lin('#FFD98C')
    p.inputs['Emission Color'].default_value = lin('#FFC864')
    p.inputs['Emission Strength'].default_value = 9.0      # WP-A: windows read as lit; bloom is baked in post (post.py)
    p.inputs['Roughness'].default_value = 0.3
    MATS['glass_lit'] = lit
    # linework wash: 8% drafting cyan over transparent
    w = bpy.data.materials.new('wash'); w.use_nodes = True
    nt = w.node_tree; nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    tr = nt.nodes.new('ShaderNodeBsdfTransparent')
    em = nt.nodes.new('ShaderNodeEmission'); em.inputs['Color'].default_value = lin('#8FD3FF'); em.inputs['Strength'].default_value = 1.0
    mx = nt.nodes.new('ShaderNodeMixShader'); mx.inputs['Fac'].default_value = 0.07
    nt.links.new(tr.outputs[0], mx.inputs[1]); nt.links.new(em.outputs[0], mx.inputs[2])
    nt.links.new(mx.outputs[0], out.inputs['Surface'])
    MATS['wash'] = w
    ho = bpy.data.materials.new('holdout'); ho.use_nodes = True
    nt = ho.node_tree; nt.nodes.clear()
    o2 = nt.nodes.new('ShaderNodeOutputMaterial'); hn = nt.nodes.new('ShaderNodeHoldout')
    nt.links.new(hn.outputs[0], o2.inputs['Surface'])
    MATS['holdout'] = ho
    gm = bpy.data.materials.new('glowmask'); gm.use_nodes = True
    nt = gm.node_tree; nt.nodes.clear()
    o3 = nt.nodes.new('ShaderNodeOutputMaterial'); en = nt.nodes.new('ShaderNodeEmission')
    en.inputs['Color'].default_value = (1, 1, 1, 1); en.inputs['Strength'].default_value = 1.0
    nt.links.new(en.outputs[0], o3.inputs['Surface'])
    MATS['glowmask'] = gm

# ---------------------------------------------------------------- geometry helpers

def M_box(center, size, rotz=0.0, rotx=0.0):
    R = (Matrix.Rotation(rotz, 4, 'Z') @ Matrix.Rotation(rotx, 4, 'X'))
    S = Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    return Matrix.Translation(Vector(center)) @ R @ S

def M_axes(center, xa, za, size):
    xa = Vector(xa).normalized(); za = Vector(za)
    za = (za - xa * za.dot(xa)).normalized()
    ya = za.cross(xa)
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0] = xa[i] * size[0]; m[i][1] = ya[i] * size[1]; m[i][2] = za[i] * size[2]; m[i][3] = center[i]
    return m

def M_line(a, b, w, h, up):
    a = Vector(a); b = Vector(b)
    return M_axes((a + b) / 2, b - a, up, ((b - a).length, w, h))

OBJS = []

def new_obj(name, mats, stage_req, t=0.0, role='', kind='', bevel=0.012, smooth=False):
    """mats: list of (material_name, [matrices], [extra bmesh builders])"""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    mlist = []
    for mi, (mname, boxes, extras) in enumerate(mats):
        mlist.append(MATS[mname])
        before = set(bm.faces)
        for M in boxes:
            bmesh.ops.create_cube(bm, size=1.0, matrix=M)
        for fn in extras:
            fn(bm)
        for f in bm.faces:
            if f not in before:
                f.material_index = mi
    bm.to_mesh(me); bm.free()
    for m in mlist:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    if bevel:
        bv = ob.modifiers.new('bevel', 'BEVEL')
        bv.width = bevel; bv.segments = 2; bv.limit_method = 'ANGLE'
        bv.angle_limit = math.radians(40); bv.use_clamp_overlap = True
        bv.harden_normals = False
    ob['stage_req'] = stage_req; ob['t'] = float(t); ob['role'] = role; ob['kind'] = kind
    ob['mats'] = ','.join(x[0] for x in mats)
    OBJS.append(ob)
    return ob

def cyl_fn(M, r, depth, seg=24):
    def f(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=depth, matrix=M)
    return f

def sphere_fn(center, r, sub=3, squash=1.0):
    def f(bm):
        M = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((r, r, r * squash, 1))
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0, matrix=M)
    return f

def torus_fn(center, axis, R, r, seg=28, rseg=10):
    axis = Vector(axis).normalized()
    q = axis.to_track_quat('Z', 'Y').to_matrix()
    def f(bm):
        rings = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            ring = []
            for j in range(rseg):
                b = 2 * math.pi * j / rseg
                p = Vector(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
                ring.append(bm.verts.new(Vector(center) + q @ p))
            rings.append(ring)
        for i in range(seg):
            for j in range(rseg):
                a, b = rings[i], rings[(i + 1) % seg]
                bm.faces.new((a[j], b[j], b[(j + 1) % rseg], a[(j + 1) % rseg]))
    return f

def prism_fn(pts2d, z0, z1):
    def f(bm):
        bot = [bm.verts.new((x, y, z0)) for x, y in pts2d]
        top = [bm.verts.new((x, y, z1)) for x, y in pts2d]
        bm.faces.new(list(reversed(bot))); bm.faces.new(top)
        n = len(pts2d)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((bot[i], bot[j], top[j], top[i]))
    return f

# ---------------------------------------------------------------- walls

class Wall:
    def __init__(s, name, p0, p1, n, openings=(), gable=None, trim=0.0, ext=(0.0, 0.0)):
        s.name = name
        s.p0 = Vector((p0[0], p0[1], 0)); p1 = Vector((p1[0], p1[1], 0))
        s.L = (p1 - s.p0).length; s.d = (p1 - s.p0).normalized(); s.n = Vector((n[0], n[1], 0))
        s.ang = math.atan2(s.d.y, s.d.x)
        s.ly = Vector((-s.d.y, s.d.x, 0))
        s.sgn = 1 if s.ly.dot(s.n) > 0 else -1
        s.openings = list(openings)   # dicts u0,u1,z0,z1,type
        s.gable = gable               # fn(u)-> top z (abs) or None
        s.trim = trim
        s.ext = ext                   # siding extension beyond ends (start,end)
    def P(s, u, off=0.0, z=0.0):
        return s.p0 + s.d * u + s.n * off + Vector((0, 0, z))
    def top(s, u):
        if s.gable:
            g = s.gable(u)
            if g is not None:
                return g
        return E

def gable_x(xmapping, half, cx):
    def g(u):
        x = xmapping(u)
        w = half - abs(x - cx)
        if w < -1e-6:
            return None
        return E + max(w, 0.0) * TT
    return g

def build_walls():
    W = []
    # front (-Y) main, gable
    W.append(Wall('front', (-2.6, -2.4), (2.6, -2.4), (0, -1), [
        dict(u0=0.75, u1=1.75, z0=F + 0.9, z1=F + 2.15, type='win', lintel=True, cols=2),
        dict(u0=2.75, u1=3.7, z0=F, z1=F + 2.15, type='door'),
        dict(u0=4.05, u1=4.85, z0=F + 0.9, z1=F + 2.15, type='win', cols=2),
        dict(u0=3.0, u1=3.95, z0=F + 3.25, z1=F + 4.4, type='win', shutters=True, cols=2),
        dict(u0=0.95, u1=1.55, z0=F + 3.35, z1=F + 4.3, type='win', cols=1),
    ], gable=gable_x(lambda u: -2.6 + u, 2.6, 0.0), ext=(0.06, 0.06)))
    W.append(Wall('right', (2.6, -2.4), (2.6, 0.6), (1, 0), [
        dict(u0=1.1, u1=1.9, z0=F + 0.9, z1=F + 2.15, type='win', cols=2),
        dict(u0=1.1, u1=1.9, z0=F + 3.3, z1=F + 4.35, type='win', cols=2),
    ], trim=SD))
    W.append(Wall('wingfront', (2.6, 0.6), (4.4, 0.6), (0, -1), [
        dict(u0=0.5, u1=1.3, z0=F + 0.9, z1=F + 2.15, type='win', cols=2),
        dict(u0=0.5, u1=1.3, z0=F + 3.3, z1=F + 4.35, type='win', cols=2),
    ], ext=(0.0, 0.06)))
    W.append(Wall('wingend', (4.4, 0.6), (4.4, 3.0), (1, 0), [],
                  gable=gable_x(lambda u: 0.6 + u, 1.2, 1.8), trim=SD))
    W.append(Wall('back', (4.4, 3.0), (-2.6, 3.0), (0, 1), [],
                  gable=gable_x(lambda u: 4.4 - u, 2.6, 0.0), ext=(0.06, 0.06)))
    W.append(Wall('left', (-2.6, 3.0), (-2.6, -2.4), (-1, 0), [
        dict(u0=0.85, u1=1.65, z0=F + 0.9, z1=F + 2.15, type='win', cols=2),
        dict(u0=0.9, u1=1.6, z0=F + 3.3, z1=F + 4.35, type='win', cols=2),
        dict(u0=3.3, u1=4.7, z0=F + 0.85, z1=F + 2.15, type='win', lintel=True, cols=3),
        dict(u0=3.55, u1=4.45, z0=F + 3.3, z1=F + 4.4, type='win', cols=2),
    ], trim=SD))
    return W

# ---------------------------------------------------------------- framing (stage 2)

STOREYS = [(F, F + 2.5), (F + 2.75, E)]

def stud_positions(w, z0, z1):
    us, ue = w.trim + SW / 2, w.L - w.trim - SW / 2
    ops = [o for o in w.openings if o['z0'] < z1 and o['z1'] > z0]
    pos = []
    k = 0
    while us + k * 0.6 < ue - 0.12:
        pos.append(us + k * 0.6); k += 1
    pos.append(ue)
    pos = [u for u in pos if not any(o['u0'] - SW < u < o['u1'] + SW for o in ops)]
    for o in ops:
        pos += [o['u0'] - SW / 2, o['u1'] + SW / 2]
    pos.sort()
    out = []
    for u in pos:
        if out and u - out[-1] < SW * 1.2:
            continue
        out.append(u)
    return out, ops

def wall_frame_bays(w, si):
    z0, z1 = STOREYS[si]
    pos, ops = stud_positions(w, z0, z1)
    bays = []
    for i, a in enumerate(pos):
        boxes = []
        def B(u0, u1, za, zb, dep=SD, off=SD / 2):
            c = w.P((u0 + u1) / 2, -off, (za + zb) / 2)
            boxes.append(M_box(c, (u1 - u0, dep, zb - za), w.ang))
        B(a - SW / 2, a + SW / 2, z0 + PL, z1 - 2 * PL, SD - 0.008)
        if i + 1 < len(pos):
            b = pos[i + 1]
            mid = (a + b) / 2
            inside = [o for o in ops if o['u0'] <= mid <= o['u1']]
            door = any(o['type'] == 'door' for o in inside)
            lo, hi = a - SW / 2, b - SW / 2
            if i + 2 == len(pos):
                hi = b + SW / 2
            if not door:
                B(lo, hi, z0, z0 + PL)
            B(lo, hi, z1 - 2 * PL, z1 - PL)
            B(lo, hi, z1 - PL, z1)
            for o in inside:
                hz = min(o['z1'] + 0.2, z1 - 2 * PL)
                B(a + SW / 2, b - SW / 2, o['z1'], hz, SD - 0.01)
                if o['type'] == 'win':
                    B(a + SW / 2, b - SW / 2, o['z0'] - PL, o['z0'], SD - 0.01)
                # cripples
                k = a + 0.45
                while k < b - 0.2:
                    if z1 - 2 * PL - hz > 0.15:
                        B(k - SW / 2, k + SW / 2, hz, z1 - 2 * PL, SD - 0.012)
                    if o['type'] == 'win' and o['z0'] - PL - (z0 + PL) > 0.15:
                        B(k - SW / 2, k + SW / 2, z0 + PL, o['z0'] - PL, SD - 0.012)
                    k += 0.5
        else:
            pass
        bays.append(boxes)
    return bays

def gable_bays(w):
    if not w.gable:
        return []
    pos, _ = stud_positions(w, E, E + 5)
    bays = []
    for u in pos:
        g = w.gable(u)
        if g is None:
            continue
        h = (g - E) - 0.06
        if h < 0.25:
            continue
        c = w.P(u, -SD / 2, E + h / 2)
        bays.append([M_box(c, (SW, SD - 0.008, h), w.ang)])
    return bays

def build_frame(walls):
    seq = []   # list of box-lists in build order
    for si in (0, 1):
        for w in walls:
            for b in wall_frame_bays(w, si):
                seq.append(('wall%d' % si, w.name, b))
        if si == 0:
            # floor platform: rim joists + joists (main along X, wing along X)
            zj0, zj1 = F + 2.5, F + 2.75
            for w in walls:
                L0, L1 = w.trim, w.L - w.trim
                c = w.P((L0 + L1) / 2, -0.03, (zj0 + zj1) / 2)
                seq.append(('joist', w.name, [M_box(c, (L1 - L0, 0.06, zj1 - zj0), w.ang)]))
            y = -2.4 + 0.35
            while y < 3.0 - 0.1:
                x1 = 4.4 - 0.06 if y > 0.66 else 2.6 - 0.06
                seq.append(('joist', 'j', [M_box(((-2.54 + x1) / 2, y, (zj0 + zj1) / 2), (x1 + 2.54, 0.07, zj1 - zj0))]))
                y += 0.6
    for w in walls:
        for b in gable_bays(w):
            seq.append(('gable', w.name, b))
    n = len(seq)
    for i, (grp, wn, boxes) in enumerate(seq):
        new_obj('frame_%03d_%s_%s' % (i, grp, wn), [('timber', boxes, [])], 2, (i + 1) / n, '', 'frame', bevel=0.008)

# ---------------------------------------------------------------- roof (stage 3)

class Slope:
    def __init__(s, base, sdir, nrm, rdir, S, r0, r1):
        s.base = Vector(base); s.s = Vector(sdir).normalized(); s.n = Vector(nrm).normalized()
        s.r = Vector(rdir).normalized(); s.S = S; s.r0 = r0; s.r1 = r1
    def P(s, sd, rp, off=0.0):
        return s.base + s.s * sd + s.r * rp + s.n * off

def roof_slopes():
    c, sn = math.cos(TH), math.sin(TH)
    ze = E + RT - OH * TT
    Sm = (2.6 + OH) / c
    Sw = (1.2 + OH) / c
    return {
        'mainL': Slope((-2.6 - OH, 0, ze), (c, 0, sn), (-sn, 0, c), (0, 1, 0), Sm, -2.4 - OH, 3.0 + OH),
        'mainR': Slope((2.6 + OH, 0, ze), (-c, 0, sn), (sn, 0, c), (0, 1, 0), Sm, -2.4 - OH, 3.0 + OH),
        'wingF': Slope((0, 0.6 - OH, ze), (0, c, sn), (0, -sn, c), (1, 0, 0), Sw, 1.15, 4.4 + OH),
        'wingB': Slope((0, 3.0 + OH, ze), (0, -c, sn), (0, sn, c), (1, 0, 0), Sw, 1.15, 4.4 + OH),
    }

def build_roof():
    SL = roof_slopes()
    items = []   # (phase, order, name, mats, role)
    # rafters
    ys = [-2.4 - OH + 0.04, -2.4 + 0.09]
    y = -2.4 + 0.6
    while y < 3.0 - 0.15:
        ys.append(y); y += 0.6
    ys += [3.0 - 0.09, 3.0 + OH - 0.04]
    for i, y in enumerate(ys):
        boxes = []
        for key in ('mainL', 'mainR'):
            sl = SL[key]
            s0 = 0.0
            if key == 'mainR' and 0.55 < y < 3.05:
                s0 = OH / math.cos(TH) + 0.02   # wing covers these tails
            a = sl.P(s0, y, -DR / 2); b = sl.P(sl.S - 0.03, y, -DR / 2)
            boxes.append(M_line(a, b, 0.08, DR, sl.n))
        items.append((0, i, 'rafter_m%02d' % i, [('timber', boxes, [])], ''))
    ridge_z = E + RT + 2.6 * TT
    items.append((0, 99, 'ridgeboard_m', [('timber', [M_box((0, 0.3, ridge_z - DR * 0.6), (0.05, 5.4 + 2 * OH, DR * 1.2))], [])], ''))
    xs = [2.75 + 0.6 * k for k in range(4)] + [4.4 - 0.09, 4.4 + OH - 0.04]
    for i, x in enumerate(xs):
        boxes = []
        for key in ('wingF', 'wingB'):
            sl = SL[key]
            a = sl.P(0, x, -DR / 2); b = sl.P(sl.S - 0.03, x, -DR / 2)
            boxes.append(M_line(a, b, 0.08, DR, sl.n))
        items.append((0, 100 + i, 'rafter_w%02d' % i, [('timber', boxes, [])], ''))
    wr_z = E + RT + 1.2 * TT
    items.append((0, 199, 'ridgeboard_w', [('timber', [M_box((3.5, 1.8, wr_z - DR * 0.6), (2.5 + OH, 0.05, DR * 1.2))], [])], ''))
    # sheathing strips (3 per slope)
    for key, sl in SL.items():
        for k in range(3):
            s0, s1 = sl.S * k / 3, sl.S * (k + 1) / 3 + (0.0 if k < 2 else 0.02)
            c = sl.P((s0 + s1) / 2, (sl.r0 + sl.r1) / 2, 0.0125)
            M = M_axes(c, sl.s, sl.n, (s1 - s0, sl.r1 - sl.r0, 0.025))
            items.append((1, k, 'sheath_%s_%d' % (key, k), [('ply', [M], [])], ''))
    # tiles: rows bottom-up
    phi = math.radians(6)
    rowh, tl, tw, gap, th = 0.33, 0.42, 0.44, 0.016, 0.05
    for key, sl in SL.items():
        nrows = int(math.ceil((sl.S - 0.05) / rowh))
        for i in range(nrows):
            sc = -0.06 + i * rowh + tl / 2
            if sc + tl / 2 > sl.S + 0.06:
                sc = sl.S + 0.06 - tl / 2
            xa = sl.s * math.cos(phi) - sl.n * math.sin(phi)
            za = sl.s * math.sin(phi) + sl.n * math.cos(phi)
            boxes = []
            off = (tw / 2) * (i % 2)
            rp = sl.r0 - off
            while rp < sl.r1 - 0.02:
                a, b = max(rp, sl.r0) + gap / 2, min(rp + tw, sl.r1) - gap / 2
                if b - a > 0.05:
                    c = sl.P(sc, (a + b) / 2, 0.025 + th / 2 + (tl / 2) * math.sin(phi))
                    boxes.append(M_axes(c, xa, za, (tl, b - a, th)))
                rp += tw
            items.append((2, i, 'tiles_%s_%02d' % (key, i), [('tile', boxes, [])], 'detail'))
    # ridge caps
    rz = E + RT + 2.6 * TT + 0.07
    cap = Matrix.Translation((0, 0.3, rz)) @ Matrix.Rotation(math.radians(90), 4, 'X')
    items.append((3, 0, 'ridgecap_m', [('ridge', [], [cyl_fn(cap, 0.12, 5.4 + 2 * OH + 0.1)])], 'major'))
    wz = E + RT + 1.2 * TT + 0.07
    capw = Matrix.Translation((3.15 + OH / 2, 1.8, wz)) @ Matrix.Rotation(math.radians(90), 4, 'Y')
    items.append((3, 1, 'ridgecap_w', [('ridge', [], [cyl_fn(capw, 0.11, 3.2 + OH)])], 'major'))
    # barge boards + fascia + front gable truss
    trimb = []
    for key in ('mainL', 'mainR'):
        sl = SL[key]
        for yb in (-2.4 - OH - 0.03, 3.0 + OH + 0.03):
            a = sl.P(-0.03, yb, -0.06); b = sl.P(sl.S, yb, -0.06)
            trimb.append(M_line(a, b, 0.06, 0.3, sl.n))
        xf = sl.P(0, 0, 0)
        trimb.append(M_box((xf.x + (-0.03 if key == 'mainL' else 0.03), 0.3, xf.z - 0.1), (0.05, 5.4 + 2 * OH + 0.12, 0.26)))
    for key in ('wingF', 'wingB'):
        sl = SL[key]
        a = sl.P(-0.03, 4.4 + OH + 0.03, -0.06); b = sl.P(sl.S, 4.4 + OH + 0.03, -0.06)
        trimb.append(M_line(a, b, 0.06, 0.3, sl.n))
        xf = sl.P(0, 0, 0)
        trimb.append(M_box((3.0 + OH / 2 + 0.2, xf.y + (-0.03 if key == 'wingF' else 0.03), xf.z - 0.1), (2.9 + OH, 0.05, 0.26)))
    # decorative gable truss (front)
    yt = -2.4 - OH + 0.12
    cz = E + 1.25
    trimb.append(M_box((0, yt, cz), (2 * (2.6 - (cz - E) / TT) - 0.1, 0.1, 0.14)))       # collar
    kz0, kz1 = cz - 0.07, E + 2.6 * TT - 0.02
    trimb.append(M_box((0, yt, (kz0 + kz1) / 2), (0.12, 0.1, kz1 - kz0)))               # king post
    for sgn in (-1, 1):   # V-struts from king post down to the collar
        a = Vector((0, yt, cz + 0.85)); b = Vector((sgn * 0.85, yt, cz + 0.05))
        trimb.append(M_line(a, b, 0.09, 0.09, (0, -1, 0)))
    items.append((3, 2, 'roof_trim', [('trim', trimb, [])], 'major'))
    # chimney
    ch = [M_box((-1.4, 1.95, (F + 3.6 + 8.25) / 2), (0.72, 0.72, 8.25 - F - 3.6)),
          M_box((-1.4, 1.95, 8.3), (0.86, 0.86, 0.1))]
    pot = Matrix.Translation((-1.4, 1.95, 8.45))
    items.append((3, 3, 'chimney', [('brick', ch, [cyl_fn(pot, 0.12, 0.22, 20)])], 'major'))
    # order -> t
    items.sort(key=lambda it: (it[0], it[1]))
    n = len(items)
    phase_span = {0: (0.0, 0.4), 1: (0.4, 0.6), 2: (0.6, 0.97), 3: (0.97, 1.0)}
    for ph in phase_span:
        grp = [it for it in items if it[0] == ph]
        a, b = phase_span[ph]
        for j, it in enumerate(grp):
            t = a + (b - a) * (j + 1) / len(grp)
            new_obj(it[2], it[3], 3, t, it[4], 'roof', bevel=0.01 if ph != 2 else 0.008)

# ---------------------------------------------------------------- siding (stage 4)

ROW_EXP = 0.22
ROW_H = 0.26

def build_siding(walls):
    phi = math.radians(3.5)
    rows = []
    z = F + 0.02
    while z < E + 2.6 * TT:
        rows.append(z); z += ROW_EXP
    corners = [((-2.6, -2.4), (-1, -1)), ((2.6, -2.4), (1, -1)), ((4.4, 0.6), (1, -1)),
               ((4.4, 3.0), (1, 1)), ((-2.6, 3.0), (-1, 1))]
    nr = len(rows)
    for ri, zb in enumerate(rows):
        zt = zb + ROW_H
        boxes = []
        for w in walls:
            lo, hi = -w.ext[0], w.L + w.ext[1]
            ivs = []
            if zb < E - 0.05:
                if zt > E:
                    zt_ = E
                ivs = [(lo, hi)]
            elif w.gable:
                # find gable span at height zb+0.08
                us = [u / 100 for u in range(int(lo * 100), int(hi * 100) + 1)]
                ok = [u for u in us if (w.gable(u) or 0) > zb + 0.08]
                if ok:
                    ivs = [(min(ok), max(ok))]
            for o in w.openings:
                if o['z0'] < zt - 0.02 and o['z1'] > zb + 0.02:
                    new = []
                    for a, b in ivs:
                        if o['u1'] <= a or o['u0'] >= b:
                            new.append((a, b)); continue
                        if o['u0'] - a > 0.03: new.append((a, o['u0']))
                        if b - o['u1'] > 0.03: new.append((o['u1'], b))
                    ivs = new
            zlo, h = zb, ROW_H
            if zb < E - 0.05 and zb + ROW_H > E:
                h = E - zb
            elif zb >= E - 0.05 and zb - E < ROW_EXP:
                zlo = E - 0.01; h = zb + ROW_H - zlo      # first gable row reaches down to the eave row
            for a, b in ivs:
                off = 0.012 + 0.016 + (h / 2) * math.sin(phi)
                c = w.P((a + b) / 2, off, zlo + h / 2)
                boxes.append(M_box(c, (b - a, 0.032, h), w.ang, w.sgn * phi))
        if zb < E - 0.05:
            h = min(ROW_EXP, E - zb)
            for (cx, cy), (sx, sy) in corners:
                c = (cx + sx * 0.045, cy + sy * 0.045, zb + h / 2)
                boxes.append(M_box(c, (0.13, 0.13, h - 0.002)))
        if boxes:
            new_obj('siding_%02d' % ri, [('plaster', boxes, [])], 4, (ri + 1) / nr, 'detail', 'siding', bevel=0.006)
    return rows

# ---------------------------------------------------------------- windows, door, porch, key

def build_units(walls):
    for w in walls:
        for k, o in enumerate(w.openings):
            u0, u1, z0, z1 = o['u0'], o['u1'], o['z0'], o['z1']
            tb = []
            gl = []
            def B(ua, ub, za, zb, off0, off1, lst=tb):
                c = w.P((ua + ub) / 2, (off0 + off1) / 2, (za + zb) / 2)
                lst.append(M_box(c, (ub - ua, off1 - off0, zb - za), w.ang))
            fw = 0.09
            if o['type'] == 'win':
                B(u0 - fw, u0, z0 - fw, z1 + fw, 0.0, 0.1)
                B(u1, u1 + fw, z0 - fw, z1 + fw, 0.0, 0.1)
                B(u0, u1, z1, z1 + fw, 0.0, 0.1)
                B(u0, u1, z0 - fw, z0, 0.0, 0.1)
                B(u0 - 0.16, u1 + 0.16, z0 - fw - 0.07, z0 - fw + 0.01, 0.0, 0.17)   # sill
                # sash border + mullions (recessed)
                sb = 0.045
                B(u0, u0 + sb, z0, z1, -0.06, 0.0); B(u1 - sb, u1, z0, z1, -0.06, 0.0)
                B(u0 + sb, u1 - sb, z1 - sb, z1, -0.06, 0.0); B(u0 + sb, u1 - sb, z0, z0 + sb, -0.06, 0.0)
                cols = o.get('cols', 2)
                for c in range(1, cols):
                    uc = u0 + (u1 - u0) * c / cols
                    B(uc - 0.025, uc + 0.025, z0 + sb, z1 - sb, -0.055, -0.005)
                zm = z0 + (z1 - z0) * 0.55
                B(u0 + sb, u1 - sb, zm - 0.025, zm + 0.025, -0.055, -0.005)
                B(u0, u1, z0, z1, -0.09, -0.07, gl)
                extra = []
                if o.get('lintel'):
                    lb = []
                    B(u0 - 0.14, u1 + 0.14, z1 + fw, z1 + fw + 0.14, 0.0, 0.13, lb)
                    extra.append(('lintel', lb, []))
                if o.get('shutters'):
                    for side in (-1, 1):
                        ua = u0 - fw - 0.46 if side < 0 else u1 + fw
                        ub = ua + 0.46
                        B(ua, ub, z0 - 0.02, z1 + 0.02, 0.02, 0.07)
                        nsl = 7
                        for s_ in range(nsl):
                            zz = z0 + 0.12 + s_ * (z1 - z0 - 0.2) / (nsl - 1)
                            B(ua + 0.06, ub - 0.06, zz - 0.02, zz + 0.02, 0.07, 0.095)
                ob = new_obj('unit_%s_%d' % (w.name, k), [('trim', tb, [])] + extra + [('glass', gl, [])], 4, 0.0, 'major', 'unit', bevel=0.008)
                ob['glass_slot'] = len(extra) + 1
            else:   # door
                B(u0 - fw, u0, z0, z1 + fw, 0.0, 0.11)
                B(u1, u1 + fw, z0, z1 + fw, 0.0, 0.11)
                B(u0 - fw, u1 + fw, z1 + fw, z1 + fw + 0.05, 0.0, 0.13)
                db = []
                B(u0, u1, z0, z1, -0.07, -0.02, db)
                # raised panels
                pz = [(z0 + 0.15, z0 + 0.95)]
                for (za, zb) in pz:
                    B(u0 + 0.12, (u0 + u1) / 2 - 0.05, za, zb, -0.02, 0.0, db)
                    B((u0 + u1) / 2 + 0.05, u1 - 0.12, za, zb, -0.02, 0.0, db)
                # glazed top: glass + muntins
                ga, gb_ = z0 + 1.15, z1 - 0.15
                B(u0 + 0.14, u1 - 0.14, ga, gb_, -0.03, -0.015, gl)
                B((u0 + u1) / 2 - 0.02, (u0 + u1) / 2 + 0.02, ga, gb_, -0.03, 0.0, db)
                B(u0 + 0.14, u1 - 0.14, (ga + gb_) / 2 - 0.02, (ga + gb_) / 2 + 0.02, -0.03, 0.0, db)
                knob = w.P(u1 - 0.14, 0.03, z0 + 1.0)
                kb = []
                hook = w.P(u0 - fw - 0.1, 0.03, z0 + 1.55)
                kb.append(M_box(hook, (0.05, 0.06, 0.05), w.ang))
                ob = new_obj('unit_door', [('trim', tb, []), ('door', db, []), ('brass', kb, [sphere_fn(knob, 0.045, 2)]), ('glass', gl, [])],
                             4, 0.0, 'major', 'unit', bevel=0.008)
                ob['glass_slot'] = 3
                # key (750h)
                KS = 1.5
                ring_c = w.P(u0 - fw - 0.1, 0.07, z0 + 1.55 - 0.05 * KS)
                bow_c = ring_c + Vector((0, 0, -0.1 * KS))
                kbx = [M_box(bow_c + Vector((0, 0, -0.06 * KS - 0.11 * KS)), (0.025 * KS, 0.02 * KS, 0.22 * KS), w.ang)]
                bit = bow_c + Vector((0, 0, -0.06 * KS - 0.19 * KS)) + w.d * (0.035 * KS)
                kbx.append(M_box(bit, (0.05 * KS, 0.02 * KS, 0.025 * KS), w.ang))
                bit2 = bow_c + Vector((0, 0, -0.06 * KS - 0.14 * KS)) + w.d * (0.03 * KS)
                kbx.append(M_box(bit2, (0.04 * KS, 0.02 * KS, 0.02 * KS), w.ang))
                new_obj('key', [('brass', kbx, [torus_fn(ring_c, w.n, 0.035 * KS, 0.007 * KS),
                                                 torus_fn(bow_c, w.n, 0.05 * KS, 0.014 * KS)])], 5, 0.0, '', 'key', bevel=0.004)

def build_porch():
    pb = []
    posts = [(-0.45, -3.85), (2.8, -3.85)]
    ztop = F + 2.62
    for (x, y) in posts:
        pb.append(M_box((x, y, (F - 0.05 + ztop) / 2), (0.16, 0.16, ztop - F + 0.05)))
        pb.append(M_box((x, y, F - 0.05 + 0.06), (0.24, 0.24, 0.12)))    # plinth block
        for sx in (-1, 1):
            if (x < 0 and sx < 0) or (x > 2 and sx > 0):
                continue
            a = Vector((x, y, ztop - 0.6)); b = Vector((x + sx * 0.55, y, ztop - 0.05))
            pb.append(M_line(a, b, 0.09, 0.09, (0, -1, 0)))
    pb.append(M_box((1.175, -3.85, ztop + 0.09), (3.55, 0.16, 0.18)))   # beam
    # shed roof
    y0, z0 = -2.4 - 0.06, F + 3.08
    y1, z1 = -4.12, ztop + 0.2
    ang = math.atan2(z0 - z1, y0 - y1)
    sdir = Vector((0, math.cos(ang), math.sin(ang)))    # up-slope towards wall
    nrm = Vector((0, -math.sin(ang), math.cos(ang)))
    S = ((y0 - y1) ** 2 + (z0 - z1) ** 2) ** 0.5
    base = Vector((0, y1, z1))
    for k in range(4):   # rafters
        x = -0.55 + k * (3.45 / 3)
        a = base + Vector((x, 0, 0)) - nrm * 0.07; b = a + sdir * S
        pb.append(M_line(a, b, 0.07, 0.14, nrm))
    c = base + sdir * (S / 2) + Vector((1.175, 0, 0)) + nrm * 0.0125
    sheet = [M_axes(c, sdir, nrm, (S, 3.7, 0.025))]
    fas = [M_axes(base + Vector((1.175, 0, -0.06)) - sdir * 0.02, (1, 0, 0), (0, 0, 1), (3.72, 0.05, 0.2))]
    sl = []
    phi = math.radians(5)
    rowh, tl, tw = 0.36, 0.44, 0.5
    nrows = int(math.ceil(S / rowh))
    for i in range(nrows):
        sc = -0.05 + i * rowh + tl / 2
        sc = min(sc, S - tl / 2 + 0.02)
        xa = sdir * math.cos(phi) - nrm * math.sin(phi); za = sdir * math.sin(phi) + nrm * math.cos(phi)
        rp = -0.65 - (tw / 2) * (i % 2)
        while rp < 3.0 - 0.02:
            a, b = max(rp, -0.65) + 0.008, min(rp + tw, 3.0) - 0.008
            if b - a > 0.05:
                cc = base + sdir * sc + Vector(((a + b) / 2, 0, 0)) + nrm * (0.025 + 0.022 + (tl / 2) * math.sin(phi))
                sl.append(M_axes(cc, xa, za, (tl, b - a, 0.044)))
            rp += tw
    new_obj('porch', [('trim', pb + fas, []), ('ply', sheet, []), ('slate', sl, [])], 4, 0.97, 'major', 'porch', bevel=0.008)
    # downpipe + gutter
    dp = []
    M = Matrix.Translation((-2.73, -2.25, (0.0 + E) / 2))
    g = Matrix.Translation((-2.6 - OH - 0.08, 0.3, E - 0.12)) @ Matrix.Rotation(math.radians(90), 4, 'X')
    new_obj('downpipe', [('copper', [], [cyl_fn(M, 0.045, E, 16), cyl_fn(g, 0.07, 5.4 + 2 * OH, 16)])], 4, 0.97, 'major', 'porch', bevel=0)

# ---------------------------------------------------------------- lot, slab, stake

LOT = (-4.0, 5.8, -5.8, 4.4)
FOOT = [(-2.75, -2.55), (2.75, -2.55), (2.75, 0.45), (4.55, 0.45), (4.55, 3.15), (-2.75, 3.15)]

def build_lot():
    x0, x1, y0, y1 = LOT
    new_obj('lot_plinth', [('stone', [M_box(((x0 + x1) / 2, (y0 + y1) / 2, -0.25), (x1 - x0, y1 - y0, 0.4))], [])], -1, 0, '', 'lot', bevel=0.05)
    i = 0.22
    new_obj('lot_lawn', [('lawn', [M_box(((x0 + x1) / 2, (y0 + y1) / 2, -0.06), (x1 - x0 - 2 * i, y1 - y0 - 2 * i, 0.12))], [])], -1, 0, '', 'lot', bevel=0.03)
    pv = []
    y = y0 + 0.28
    k = 0
    while y < -4.05:
        for (xa, xb) in ([(0.45, 1.05), (1.11, 1.71)] if k % 2 == 0 else [(0.45, 0.75), (0.81, 1.41), (1.47, 1.71)]):
            pv.append(M_box(((xa + xb) / 2, y + 0.21, 0.015), (xb - xa, 0.42, 0.09)))
        y += 0.48; k += 1
    new_obj('lot_path', [('paver', pv, [])], -1, 0, '', 'lot', bevel=0.015)
    # shrubs + tree (WP-A: lumpy clay clusters, tree kept inside the lot so no shadow falls off it)
    rnd = random.Random(7)
    shrubs = [(-3.3, -1.9, 0.36), (-3.35, -1.3, 0.28), (-3.3, 0.6, 0.33), (-3.32, 2.35, 0.36), (-3.25, 1.2, 0.26),
              (-1.9, -3.4, 0.33), (-2.5, -3.62, 0.25), (3.6, -3.3, 0.35), (4.2, -2.9, 0.27), (5.1, -0.4, 0.33), (5.2, 0.4, 0.25)]
    for j, (x, y, r) in enumerate(shrubs):
        fns = [sphere_fn((x, y, r * 0.62), r * 0.82, 4, 0.9)]
        n = 7
        for k in range(n):
            a_ = 2 * math.pi * k / n + rnd.uniform(-0.3, 0.3)
            rr = r * rnd.uniform(0.5, 0.62)
            d = r * rnd.uniform(0.5, 0.62)
            fns.append(sphere_fn((x + math.cos(a_) * d, y + math.sin(a_) * d, rr * 0.75 + rnd.uniform(0, r * 0.25)), rr, 3, 0.92))
        fns.append(sphere_fn((x + rnd.uniform(-0.08, 0.08), y + rnd.uniform(-0.08, 0.08), r * 1.0), r * 0.5, 3, 0.95))
        ob = new_obj('shrub_%02d' % j, [('foliage', [], fns)], -1, 0, '', 'lot', bevel=0, smooth=True)
        lumpy(ob, 0.045 * (r / 0.33), 0.35 + 0.1 * (j % 3))
    tx, ty = -3.18, 3.68
    trunk = []
    def taper(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.17, radius2=0.08, depth=1.8,
                              matrix=Matrix.Translation((tx, ty, 0.9)))
    trunk.append(taper)
    for (dx, dy, dz, ang) in ((0.22, -0.1, 1.35, 0.7), (-0.18, 0.12, 1.5, -0.8)):
        M = Matrix.Translation((tx + dx * 0.5, ty + dy * 0.5, dz)) @ Matrix.Rotation(ang, 4, 'Y' if abs(dx) > abs(dy) else 'X')
        trunk.append(cyl_fn(M, 0.045, 0.55, 10))
    crown = [(0.0, 0.0, 2.55, 0.6), (0.3, -0.22, 2.25, 0.42), (-0.32, 0.18, 2.2, 0.42), (0.22, 0.3, 2.45, 0.4),
             (-0.25, -0.28, 2.5, 0.4), (0.05, -0.05, 3.0, 0.42), (0.35, 0.05, 2.7, 0.34), (-0.3, -0.02, 2.85, 0.34)]
    canopy = [sphere_fn((tx + cx * 1.05, ty + cy * 1.1, cz - 0.28), r * 1.18, 4 if r > 0.5 else 3, 0.95) for (cx, cy, cz, r) in crown]
    ob = new_obj('tree', [('trunk', [], trunk), ('foliage', [], canopy)], -1, 0, '', 'lot', bevel=0, smooth=True)
    lumpy(ob, 0.06, 0.4, vgroup_mat=1)

def lumpy(ob, strength, size, vgroup_mat=None):
    """Organic displacement for foliage (optionally only the faces of one material slot)."""
    tex = bpy.data.textures.new(ob.name + '_lump', 'CLOUDS'); tex.noise_scale = size; tex.noise_depth = 1
    dm = ob.modifiers.new('lump', 'DISPLACE'); dm.texture = tex; dm.strength = strength; dm.mid_level = 0.5
    dm.texture_coords = 'GLOBAL'
    if vgroup_mat is not None:
        vg = ob.vertex_groups.new(name='foliage')
        idx = sorted({v for p in ob.data.polygons if p.material_index == vgroup_mat for v in p.vertices})
        vg.add(idx, 1.0, 'REPLACE')
        dm.vertex_group = 'foliage'

def build_slab():
    new_obj('slab', [('concrete', [], [prism_fn(FOOT, -0.06, F)])], 1, 0, 'major', 'slab', bevel=0.02)
    new_obj('porch_deck', [('concrete', [M_box((1.175, -3.275, (F - 0.06 - 0.06) / 2), (3.55, 1.45, F - 0.06 + 0.06))], [])], 1, 0, 'major', 'slab', bevel=0.02)

def build_stake():
    sb = []
    pts = FOOT
    for (x, y) in pts:
        sb.append(M_box((x, y, 0.2), (0.05, 0.05, 0.4)))
    st = []
    for i in range(len(pts)):
        a = Vector((pts[i][0], pts[i][1], 0.32)); b = Vector((pts[(i + 1) % len(pts)][0], pts[(i + 1) % len(pts)][1], 0.32))
        st.append(M_line(a, b, 0.018, 0.018, (0, 0, 1)))
    sx, sy = -3.35, -3.1
    sb.append(M_box((sx, sy, 0.55), (0.08, 0.08, 1.1)))
    flag = [M_box((sx + 0.22, sy, 0.95), (0.36, 0.02, 0.24))]
    new_obj('stake', [('trunk', sb, []), ('string', st, []), ('flag', flag, [])], 0, 0, '', 'stake', bevel=0.006)

# ---------------------------------------------------------------- scene

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    OBJS.clear(); MATS.clear()

def build_all():
    reset()
    make_materials()
    walls = build_walls()
    build_lot(); build_stake(); build_slab()
    build_frame(walls); build_roof()
    rows = build_siding(walls)
    build_units(walls); build_porch()
    return walls, rows

def is_built(ob, st):
    sr = ob['stage_req']
    if ob['kind'] == 'stake':
        return st['stage'] == 0
    if sr < 0:
        return True
    if st['stage'] > sr:
        return True
    if st['stage'] == sr:
        return ob['t'] <= st.get('p', 1.0) + 1e-9
    return False
