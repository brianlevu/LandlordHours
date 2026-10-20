"""LandlordHours 2.0 category tool icons, modelled in Blender with the house's material set and light rig.

usage: .venv/bin/python scripts/tools.py --out <dir> [--tools repairs,showing] [--variants light,dark]
       [--res 1024] [--samples 96]

Every tool is built at roughly real proportions, then given one shared presentation: the house's
3/4 ortho camera (Rz -45 deg, Rx 62 deg), flat-lay objects tilted 40 deg toward the camera, standing objects
upright, and each scaled so its projected bounding box fills FILL of the frame. Same key/fill/rim suns as
the house (render.setup_lights), no ground: the icons float on a plaster tile in the app.
Output: <out>/tool_<name>__<variant>.png, transparent, 1024 square.
"""
import argparse, math, os, sys, time, json
sys.path.insert(0, os.path.dirname(__file__))
import bpy, bmesh
from mathutils import Vector, Matrix
import house as H
import render as R

FILL = 0.80
ROT = Matrix.Rotation(math.radians(-45), 4, 'Z') @ Matrix.Rotation(math.radians(62), 4, 'X')
R3 = ROT.to_3x3()
FWD = R3 @ Vector((0, 0, -1)); RIGHT = R3 @ Vector((1, 0, 0)); UP = R3 @ Vector((0, 1, 0))
TILT = Matrix.Rotation(math.radians(40), 4, Vector((0.7071, -0.7071, 0)))

TOOLS = ['repairs', 'showing', 'comms', 'bookkeeping', 'travel', 'inspection',
         'renovation', 'cleaning', 'legal', 'supplies', 'management',
         'investing', 'financing', 'insurance', 'negotiation']
LABELS = {'repairs': 'Repairs · wrench', 'showing': 'Showing / leasing · sign', 'comms': 'Tenant comms · phone',
          'bookkeeping': 'Bookkeeping · ledger', 'travel': 'Travel · truck', 'inspection': 'Inspection · flashlight',
          'renovation': 'Renovation · roller', 'cleaning': 'Turnover · bucket + sponge', 'legal': 'Legal / admin · sealed document',
          'supplies': 'Supplies · hardware bag', 'management': 'Management · clipboard',
          'investing': 'Investing · rising coin stacks', 'financing': 'Financing · house key + tag',
          'insurance': 'Insurance · shield + house', 'negotiation': 'Negotiation · two speech bubbles'}

# ------------------------------------------------------------------ materials (house set + a few in the same matte language)

def extra_materials():
    """Gate fix: every tool material takes its colour from the house set (render.py/house.py MATS);
    the names below are aliases with the house hexes, plus glass-like screen/lens/rubber accents."""
    m = H.mat
    m('steel', '#A9A7A2', 0.34, None, 0.75)     # slate
    m('graphite', '#4A5068', 0.55)              # brand graphite
    m('rubber', '#4A5068', 0.7)
    m('sponge', '#D9B45A', 0.95)                # brass hex, matte
    m('galv', '#A9A7A2', 0.42, None, 0.5)       # slate, satin
    m('water', '#46506B', 0.12)                 # window glass
    m('moss', '#6A9A58', 0.7)                   # shrub green
    m('kraft', '#EBC994', 0.9)                  # ply
    m('paper', '#F4EBDD', 0.85)                 # plaster
    m('inkline', '#A9A7A2', 0.8)                # slate
    m('wax', '#C8553D', 0.45)                   # terracotta
    m('board', '#E8B474', 0.75)                 # timber
    m('lens', '#FFD98C', 0.15)                  # lit-window glass
    l = H.MATS['lens'].node_tree.nodes['Principled BSDF']
    l.inputs['Emission Color'].default_value = H.lin('#FFC864'); l.inputs['Emission Strength'].default_value = 1.6
    m('screen', '#46506B', 0.18)                # window glass
    m('hubcap', '#F4EBDD', 0.5)                 # plaster
    m('shell', '#F4EBDD', 0.42)                 # plaster
    m('coin', '#D9B45A', 0.36, None, 0.8)       # brass (investing)
    m('navy', '#46506B', 0.55)                  # window glass, matte (insurance shield)
    m('flag', '#E07A3A', 0.68)                  # house flag orange (negotiation)
    m('keysteel', '#9A6B45', 0.42, None, 0.35)  # house trunk bronze, satin (financing key)

# ------------------------------------------------------------------ geometry helpers

PARTS = []

def obj(name, mat, fns, bevel=0.02, segs=3, smooth=False, booleans=(), mod_extra=None):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    for f in fns:
        f(bm)
    bm.to_mesh(me); bm.free()
    me.materials.append(H.MATS[mat])
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    if smooth:
        for p in me.polygons: p.use_smooth = True
    for cut in booleans:
        b = ob.modifiers.new('bool', 'BOOLEAN'); b.operation = 'DIFFERENCE'; b.solver = 'EXACT'; b.object = cut
    if mod_extra:
        mod_extra(ob)
    if bevel:
        bv = ob.modifiers.new('bevel', 'BEVEL'); bv.width = bevel; bv.segments = segs
        bv.limit_method = 'ANGLE'; bv.angle_limit = math.radians(35); bv.use_clamp_overlap = True
        bv.harden_normals = False
    if bevel or smooth:
        for p in me.polygons: p.use_smooth = True
        if hasattr(me, 'set_sharp_from_angle'):
            me.set_sharp_from_angle(angle=math.radians(40))
    PARTS.append(ob)
    return ob

def cutter(name, fns):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    for f in fns: f(bm)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    ob.hide_render = True; ob.hide_viewport = True
    return ob

def box(c, s, rz=0.0, rx=0.0, ry=0.0):
    M = Matrix.Translation(Vector(c)) @ Matrix.Rotation(rz, 4, 'Z') @ Matrix.Rotation(ry, 4, 'Y') @ Matrix.Rotation(rx, 4, 'X') \
        @ Matrix.Diagonal((s[0], s[1], s[2], 1.0))
    return lambda bm: bmesh.ops.create_cube(bm, size=1.0, matrix=M)

def cyl(c, r, depth, axis='Z', seg=40, r2=None, rot=None):
    M = Matrix.Translation(Vector(c))
    if rot is not None:
        M = M @ rot
    elif axis == 'X':
        M = M @ Matrix.Rotation(math.radians(90), 4, 'Y')
    elif axis == 'Y':
        M = M @ Matrix.Rotation(math.radians(90), 4, 'X')
    return lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2,
                                            depth=depth, matrix=M)

def sphere(c, r, sub=4, sq=(1, 1, 1)):
    M = Matrix.Translation(Vector(c)) @ Matrix.Diagonal((r * sq[0], r * sq[1], r * sq[2], 1))
    return lambda bm: bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0, matrix=M)

def prism(pts, z0, z1):
    return H.prism_fn(pts, z0, z1)

def rounded_rect(w, h, r, seg=8):
    pts = []
    for (cx, cy, a0) in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

def tube_path(pts, r, seg=14):
    """A round bar following a polyline (spheres at joints) -- wire handles, chains."""
    fns = []
    for a, b in zip(pts[:-1], pts[1:]):
        a = Vector(a); b = Vector(b); d = b - a
        q = d.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
        fns.append(cyl((a + b) / 2, r, d.length, rot=q, seg=seg))
    for p in pts:
        fns.append(sphere(p, r, 2))
    return fns

def arc(center, R_, a0, a1, plane='XZ', n=16):
    c = Vector(center); out = []
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        if plane == 'XZ':
            out.append(c + Vector((R_ * math.cos(a), 0, R_ * math.sin(a))))
        elif plane == 'YZ':
            out.append(c + Vector((0, R_ * math.cos(a), R_ * math.sin(a))))
        else:
            out.append(c + Vector((R_ * math.cos(a), R_ * math.sin(a), 0)))
    return out

# ------------------------------------------------------------------ the eleven tools (z up, metres-ish, lying on z=0)

def notch_disc(r, w, depth, seg=56):
    """Disc of radius r with an open-end jaw of half-width w cut in from -X to x=depth (2D outline)."""
    t1 = math.pi - math.asin(w / r)
    pts = [(r * math.cos(-t1 + 2 * t1 * k / seg), r * math.sin(-t1 + 2 * t1 * k / seg)) for k in range(seg + 1)]
    pts += [(depth, w), (depth, -w)]
    return pts

def annulus(c, r0, r1, z0, z1, seg_in=12, seg_out=56):
    """Flat ring (box-end of a wrench): outer circle r1, inner polygon r0 (12-point), z0..z1."""
    cx, cy = c
    def f(bm):
        n = seg_out
        outer = [(cx + r1 * math.cos(2 * math.pi * k / n), cy + r1 * math.sin(2 * math.pi * k / n)) for k in range(n)]
        inner = [(cx + r0 * math.cos(2 * math.pi * k / n + math.pi / 12), cy + r0 * math.sin(2 * math.pi * k / n + math.pi / 12)) for k in range(n)]
        lay = {}
        for z in (z0, z1):
            lay[z] = ([bm.verts.new((x, y, z)) for x, y in outer], [bm.verts.new((x, y, z)) for x, y in inner])
        for k in range(n):
            j = (k + 1) % n
            for z, flip in ((z1, False), (z0, True)):
                o, i_ = lay[z]
                q = (o[k], o[j], i_[j], i_[k])
                bm.faces.new(tuple(reversed(q)) if flip else q)
            ob_, ot_ = lay[z0][0], lay[z1][0]
            bm.faces.new((ob_[k], ob_[j], ot_[j], ot_[k]))
            ib, it = lay[z0][1], lay[z1][1]
            bm.faces.new((ib[j], ib[k], it[k], it[j]))
    return f

def t_repairs():
    # combination wrench: open jaw (left), box-end ring (right), a chunky handle with a terracotta grip
    obj('wrench_handle', 'copper', [box((0, 0, 0.06), (1.3, 0.48, 0.11))], bevel=0.035)
    obj('wrench_grip', 'graphite', [box((0.0, 0, 0.065), (1.1, 0.54, 0.15))], bevel=0.06, segs=4)
    def c_ring(cx, cy, r0, r1, z0, z1, gap_deg, n=48):
        """Open-end jaw: a thick C (ring with its opening toward -X), all convex quads."""
        def f(bm):
            g = math.radians(gap_deg)
            angs = [g + (2 * math.pi - 2 * g) * k / n for k in range(n + 1)]
            ring = []
            for a_ in angs:
                ca, sa = math.cos(a_ + math.pi), math.sin(a_ + math.pi)
                ring.append([bm.verts.new((cx + r * ca, cy + r * sa, z)) for (r, z) in ((r0, z0), (r1, z0), (r1, z1), (r0, z1))])
            for k in range(n):
                A, B = ring[k], ring[k + 1]
                for i in range(4):
                    j = (i + 1) % 4
                    bm.faces.new((A[i], A[j], B[j], B[i]))
            bm.faces.new(tuple(reversed(ring[0]))); bm.faces.new(tuple(ring[-1]))
        return f
    obj('wrench_jaw', 'copper', [c_ring(-0.85, 0, 0.18, 0.46, 0.0, 0.13, 36)], bevel=0.025)
    PARTS[-1].matrix_world = Matrix.Translation((-0.85, 0, 0)) @ Matrix.Rotation(math.radians(-18), 4, 'Z') @ Matrix.Translation((0.85, 0, 0))
    obj('wrench_ring', 'copper', [annulus((0.85, 0), 0.18, 0.38, 0.0, 0.13)], bevel=0.025)
    return 'flat', math.radians(48)

def t_showing():
    obj('post', 'timber', [box((-0.55, 0, 1.0), (0.18, 0.18, 2.0)), box((0.1, 0, 1.86), (1.5, 0.15, 0.15))], bevel=0.03)
    obj('post_cap', 'trim', [box((-0.55, 0, 2.03), (0.18, 0.18, 0.07))], bevel=0.015)
    for x in (-0.15, 0.65):
        obj('hook%.1f' % x, 'steel', tube_path([(x, 0, 1.8), (x, 0, 1.58)], 0.025), bevel=0, smooth=True)
    obj('sign_frame', 'tile', [prism(rounded_rect(1.25, 0.95, 0.07), -0.05, 0.05)], bevel=0.012,
        mod_extra=lambda ob: None)
    sf = PARTS[-1]; sf.matrix_world = Matrix.Translation((0.25, 0, 1.12)) @ Matrix.Rotation(math.radians(90), 4, 'X')
    obj('sign_face', 'paper', [prism(rounded_rect(1.05, 0.75, 0.05), -0.055, 0.055)], bevel=0.008)
    PARTS[-1].matrix_world = Matrix.Translation((0.25, 0, 1.12)) @ Matrix.Rotation(math.radians(90), 4, 'X')
    obj('base', 'concrete', [box((-0.55, 0, 0.04), (0.42, 0.42, 0.08))], bevel=0.02)
    return 'stand', math.radians(-28)

def t_comms():
    obj('phone_body', 'shell', [prism(rounded_rect(0.95, 1.9, 0.16, 10), 0, 0.12)], bevel=0.03)
    obj('phone_screen', 'screen', [prism(rounded_rect(0.84, 1.78, 0.11, 10), 0.11, 0.128)], bevel=0.004)
    obj('phone_island', 'rubber', [prism(rounded_rect(0.26, 0.07, 0.035, 6), 0.127, 0.134)], bevel=0)
    PARTS[-1].location = (0, 0.74, 0)
    # three message bubbles on the screen: the "tenant comms" read
    for i, (x, y, w) in enumerate(((-0.12, 0.38, 0.5), (0.14, 0.08, 0.44), (-0.1, -0.22, 0.56))):
        obj('bubble%d' % i, 'paper' if i % 2 == 0 else 'sponge', [prism(rounded_rect(w, 0.2, 0.08, 6), 0.128, 0.142)], bevel=0.006)
        PARTS[-1].location = (x, y, 0)
    return 'flat', math.radians(-12)

def t_bookkeeping():
    W, D, T = 1.25, 1.65, 0.34
    obj('ledger_cover', 'moss', [box((0, 0, 0.025), (W, D, 0.05)), box((0, 0, T - 0.025), (W, D, 0.05)),
                                  box((-W / 2 + 0.03, 0, T / 2), (0.08, D, T))], bevel=0.018)
    obj('ledger_pages', 'paper', [box((0.02, 0, T / 2), (W - 0.1, D - 0.08, T - 0.1))], bevel=0.006)
    # page edge lines
    for k in range(4):
        z = 0.08 + k * 0.055
        obj('pageline%d' % k, 'inkline', [box((W / 2 - 0.025, 0, z), (0.012, D - 0.1, 0.008))], bevel=0)
    obj('spine_band', 'brass', [box((-W / 2 - 0.012, 0, T / 2), (0.03, 0.12, T + 0.01)),
                                 box((-W / 2 - 0.012, 0.5, T / 2), (0.03, 0.06, T + 0.01)),
                                 box((-W / 2 - 0.012, -0.5, T / 2), (0.03, 0.06, T + 0.01))], bevel=0.006)
    obj('label', 'paper', [box((0.05, 0.25, T + 0.003), (0.62, 0.3, 0.012))], bevel=0.005)
    obj('ribbon', 'wax', [box((0.3, -D / 2 - 0.14, 0.2), (0.07, 0.32, 0.012), rx=math.radians(-30))], bevel=0)
    return 'flat', math.radians(28)

def t_travel():
    # small pickup truck, terracotta body, cab on the left, open bed on the right
    z0 = 0.3
    body = [box((0, 0, z0 + 0.1), (2.0, 0.9, 0.22)),                 # chassis
            box((-0.43, 0, z0 + 0.5), (0.78, 0.88, 0.62)),            # cab
            box((-0.86, 0, z0 + 0.3), (0.34, 0.9, 0.22)),             # hood
            box((0.97, 0, z0 + 0.36), (0.07, 0.9, 0.34)),             # tailgate
            box((0.41, -0.415, z0 + 0.36), (1.06, 0.07, 0.34)),       # bed sides
            box((0.41, 0.415, z0 + 0.36), (1.06, 0.07, 0.34))]
    obj('truck_body', 'tile', [body[0]] + body[3:], bevel=0.045)
    obj('truck_cab', 'paper', body[1:3], bevel=0.045)
    obj('truck_roof', 'paper', [box((-0.43, 0, z0 + 0.83), (0.7, 0.84, 0.06))], bevel=0.03)
    obj('truck_glass', 'glass', [box((-0.83, 0, z0 + 0.6), (0.02, 0.7, 0.3)),
                                 box((-0.43, -0.445, z0 + 0.6), (0.6, 0.02, 0.3)),
                                 box((-0.43, 0.445, z0 + 0.6), (0.6, 0.02, 0.3))], bevel=0.008)
    obj('truck_bed', 'board', [box((0.41, 0, z0 + 0.22), (1.06, 0.78, 0.04))], bevel=0.01)
    obj('truck_bumper', 'galv', [box((-1.04, 0, z0 + 0.06), (0.08, 0.96, 0.12)), box((1.04, 0, z0 + 0.06), (0.08, 0.96, 0.12))], bevel=0.03)
    obj('truck_lights', 'lens', [box((-1.035, -0.32, z0 + 0.32), (0.02, 0.16, 0.09)), box((-1.035, 0.32, z0 + 0.32), (0.02, 0.16, 0.09))], bevel=0.01)
    obj('truck_handle', 'galv', [box((-0.3, -0.447, z0 + 0.36), (0.14, 0.02, 0.035))], bevel=0.008)
    for x in (-0.6, 0.6):
        for y in (-0.46, 0.46):
            obj('wheel', 'rubber', [cyl((x, y, 0.28), 0.28, 0.2, 'Y', 40)], bevel=0.05)
            obj('hub', 'hubcap', [cyl((x, math.copysign(0.565, y), 0.28), 0.13, 0.04, 'Y', 32)], bevel=0.012)
    # a ladder strapped in the bed: the landlord's truck
    obj('ladder', 'galv', [box((0.4, y, z0 + 0.62), (1.4, 0.04, 0.04)) for y in (-0.14, 0.14)] +
        [box((x, 0, z0 + 0.62), (0.035, 0.28, 0.03)) for x in (-0.15, 0.12, 0.39, 0.66, 0.93)], bevel=0.008)
    return 'stand', math.radians(-25)

def t_inspection():
    # flashlight lying flat, head toward the upper right
    obj('fl_body', 'sponge', [cyl((0.15, 0, 0.2), 0.25, 1.3, 'X', 40)], bevel=0.025)
    obj('fl_grip', 'rubber', [cyl((x, 0, 0.2), 0.262, 0.07, 'X', 40) for x in (-0.15, 0.0, 0.15, 0.3)], bevel=0.015)
    obj('fl_head', 'graphite', [cyl((-0.68, 0, 0.2), 0.37, 0.42, 'X', 48, r2=0.25,
                                    rot=Matrix.Rotation(math.radians(-90), 4, 'Y'))], bevel=0.02)
    obj('fl_rim', 'steel', [cyl((-0.9, 0, 0.2), 0.38, 0.06, 'X', 48)], bevel=0.015)
    obj('fl_lens', 'lens', [cyl((-0.93, 0, 0.2), 0.31, 0.02, 'X', 48)], bevel=0.005)
    obj('fl_tail', 'graphite', [cyl((0.84, 0, 0.2), 0.255, 0.1, 'X', 40)], bevel=0.02)
    obj('fl_switch', 'tile', [box((-0.32, 0, 0.46), (0.18, 0.12, 0.06))], bevel=0.02)
    return 'flat', math.radians(55)

def t_renovation():
    # paint roller, compact: terracotta-loaded cover on top, short timber handle under its middle
    obj('roller_cover', 'plaster', [cyl((0.0, 0.5, 0.3), 0.36, 1.15, 'X', 48)], bevel=0.05)
    obj('roller_paint', 'tile', [cyl((0.16, 0.5, 0.3), 0.372, 0.62, 'X', 48)], bevel=0.03)
    obj('roller_caps', 'galv', [cyl((-0.6, 0.5, 0.3), 0.13, 0.05, 'X', 32), cyl((0.6, 0.5, 0.3), 0.13, 0.05, 'X', 32)], bevel=0.01)
    frame = [(0.62, 0.5, 0.3), (0.78, 0.5, 0.3), (0.78, 0.0, 0.3), (0.15, -0.12, 0.3), (0.15, -0.3, 0.3)]
    obj('roller_frame', 'steel', tube_path(frame, 0.055), bevel=0, smooth=True)
    obj('roller_ferrule', 'galv', [cyl((0.15, -0.34, 0.3), 0.11, 0.12, 'Y', 32)], bevel=0.012)
    obj('roller_handle', 'timber', [cyl((0.15, -0.66, 0.3), 0.15, 0.55, 'Y', 32, r2=0.13)], bevel=0.04)
    obj('roller_end', 'tile', [cyl((0.15, -0.95, 0.3), 0.13, 0.05, 'Y', 32)], bevel=0.012)
    return 'flat', math.radians(30)

def t_cleaning():
    # galvanised bucket with water, sponge on the rim
    r0, r1, h = 0.62, 0.78, 1.15
    def bucket(bm):
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=56, radius1=r0, radius2=r1, depth=h,
                              matrix=Matrix.Translation((0, 0, h / 2)))
    def solid(ob):
        # hollow the bucket: remove the top cap then thicken
        bm = bmesh.new(); bm.from_mesh(ob.data)
        top = [f for f in bm.faces if f.normal.z > 0.9]
        bmesh.ops.delete(bm, geom=top, context='FACES')
        bm.to_mesh(ob.data); bm.free()
        s = ob.modifiers.new('thick', 'SOLIDIFY'); s.thickness = 0.04; s.offset = -1
    obj('bucket', 'board', [bucket], bevel=0.012, mod_extra=solid)
    for z in (0.25, 0.85):
        rz = r0 + (r1 - r0) * z / h
        obj('hoop%.2f' % z, 'steel', [H.torus_fn((0, 0, z), (0, 0, 1), rz + 0.005, 0.022, 56, 10)], bevel=0, smooth=True)
    obj('rim', 'steel', [H.torus_fn((0, 0, h), (0, 0, 1), r1 - 0.01, 0.035, 56, 12)], bevel=0, smooth=True)
    obj('water', 'water', [cyl((0, 0, h * 0.78), r0 + (r1 - r0) * 0.78 - 0.04, 0.02, seg=56)], bevel=0)
    # wire handle: an arc over the top, ears on the sides
    hp = arc((0, 0, h), r1 + 0.03, 0, 180, 'YZ', 20)
    hp = [Vector((0, p.y, h - 0.15 + (p.z - h) * 0.85)) for p in hp]
    hp = [Matrix.Rotation(math.radians(55), 3, 'Z') @ p for p in hp]
    obj('handle', 'steel', tube_path(hp, 0.022, 10), bevel=0, smooth=True)
    for s in (-1, 1):
        e = Matrix.Rotation(math.radians(55), 3, 'Z') @ Vector((0, s * (r1 - 0.0), h - 0.15))
        obj('ear', 'galv', [sphere(e, 0.06, 2, (1, 0.6, 1))], bevel=0, smooth=True)
    # sponge resting across the rim, front-left
    sp = obj('sponge', 'sponge', [box((0, 0, 0), (0.62, 0.42, 0.24))], bevel=0.06, segs=4)
    sp.matrix_world = Matrix.Translation((-0.32, -0.42, h + 0.06)) @ Matrix.Rotation(math.radians(30), 4, 'Z') @ Matrix.Rotation(math.radians(-12), 4, 'X')
    sc = obj('scourer', 'moss', [box((0, 0, 0), (0.62, 0.42, 0.06))], bevel=0.02)
    sc.matrix_world = sp.matrix_world @ Matrix.Translation((0, 0, -0.14))
    return 'stand', math.radians(-20)

def t_legal():
    # one sheet, slightly curled, text lines, a wax seal with ribbon tails
    W, D = 1.0, 1.4
    def sheet(bm):
        nx, ny = 10, 14
        vs = {}
        for i in range(nx + 1):
            for j in range(ny + 1):
                x = -W / 2 + W * i / nx; y = -D / 2 + D * j / ny
                z = 0.05 * ((y + D / 2) / D) ** 3 * 2.4 + 0.012 * math.sin(math.pi * i / nx)   # top edge lifts
                vs[i, j] = bm.verts.new((x, y, z))
        for i in range(nx):
            for j in range(ny):
                bm.faces.new((vs[i, j], vs[i + 1, j], vs[i + 1, j + 1], vs[i, j + 1]))
    obj('folder', 'board', [prism(rounded_rect(W + 0.55, D + 0.3, 0.06, 6), -0.05, -0.01)], bevel=0.01)
    PARTS[-1].location = (0.2, -0.1, 0)
    obj('folder_tab', 'board', [prism(rounded_rect(0.5, 0.2, 0.05, 6), -0.05, -0.01)], bevel=0.01)
    PARTS[-1].location = (-0.25, D / 2 + 0.03, 0)
    obj('sheet', 'paper', [sheet], bevel=0, smooth=True,
        mod_extra=lambda ob: setattr(ob.modifiers.new('thick', 'SOLIDIFY'), 'thickness', 0.025))
    lines = [(0.48, 0.62, 0.8), (0.32, 0.9, 0.0), (0.2, 0.9, 0.0), (0.08, 0.9, 0.0), (-0.04, 0.62, -0.14)]
    for k, (y, w, xo) in enumerate(lines):
        zz = 0.05 * ((y + D / 2) / D) ** 3 * 2.4 + 0.012 + 0.02
        obj('line%d' % k, 'inkline' if k else 'graphite', [box((-W / 2 + 0.17 + w / 2 + (0 if k else 0.0), y, zz), (w, 0.045 if k else 0.07, 0.01))], bevel=0)
    # wax seal + ribbon
    sx, sy = 0.24, -0.45
    obj('ribbon_l', 'tile', [box((sx - 0.12, sy - 0.3, 0.035), (0.11, 0.5, 0.012), rz=math.radians(18))], bevel=0.004)
    obj('ribbon_r', 'tile', [box((sx + 0.12, sy - 0.3, 0.035), (0.11, 0.5, 0.012), rz=math.radians(-18))], bevel=0.004)
    def seal(bm):
        n = 18; pts = []
        for k in range(n * 2):
            a = math.pi * k / n
            r = 0.27 if k % 2 == 0 else 0.235
            pts.append((sx + r * math.cos(a), sy + r * math.sin(a)))
        H.prism_fn(pts, 0.03, 0.11)(bm)
    obj('seal', 'wax', [seal], bevel=0.025, segs=3)
    obj('seal_boss', 'wax', [cyl((sx, sy, 0.12), 0.16, 0.04, seg=40)], bevel=0.018)
    obj('seal_mark', 'brass', [H.torus_fn((sx, sy, 0.142), (0, 0, 1), 0.1, 0.012, 36, 8)], bevel=0, smooth=True)
    return 'flat', math.radians(8)

def t_supplies():
    # kraft hardware bag, cuff folded over, a hammer and a level standing in it
    W, D, Hh = 1.0, 0.62, 1.1
    obj('bag', 'kraft', [box((0, 0, Hh / 2), (W, D, Hh))], bevel=0.025)
    obj('bag_opening', 'rubber', [box((0, 0, Hh + 0.001), (W - 0.1, D - 0.1, 0.004))], bevel=0)
    obj('bag_cuff', 'board', [box((0, -D / 2 - 0.012, Hh - 0.09), (W + 0.02, 0.025, 0.18)),
                              box((0, D / 2 + 0.012, Hh - 0.09), (W + 0.02, 0.025, 0.18)),
                              box((-W / 2 - 0.012, 0, Hh - 0.09), (0.025, D + 0.05, 0.18)),
                              box((W / 2 + 0.012, 0, Hh - 0.09), (0.025, D + 0.05, 0.18))], bevel=0.008)
    obj('bag_gusset', 'board', [box((-W / 2 - 0.004, 0, Hh * 0.42), (0.01, 0.02, Hh * 0.7))], bevel=0)
    obj('bag_label', 'paper', [box((0.0, -D / 2 - 0.014, Hh * 0.47), (0.52, 0.012, 0.32))], bevel=0.004)
    obj('label_mark', 'tile', [box((0.0, -D / 2 - 0.022, Hh * 0.52), (0.32, 0.008, 0.07)),
                               box((0.0, -D / 2 - 0.022, Hh * 0.42), (0.22, 0.008, 0.045))], bevel=0)
    # hammer: handle leaning left, head on top
    hr = Matrix.Rotation(math.radians(-16), 4, 'Y') @ Matrix.Rotation(math.radians(-8), 4, 'X')
    o = obj('hammer_handle', 'timber', [cyl((0, 0, 0), 0.06, 1.1, rot=hr, seg=24)], bevel=0.01)
    base = Vector((-0.15, 0.05, 1.05)); o.location = base
    tip = (hr.to_3x3() @ Vector((0, 0, 0.55))) + base
    hd = obj('hammer_head', 'graphite', [box((0, 0, 0), (0.46, 0.15, 0.15))], bevel=0.03)
    hd.matrix_world = Matrix.Translation(tip) @ hr
    cl = obj('hammer_claw', 'graphite', [box((0, 0, 0), (0.2, 0.12, 0.08))], bevel=0.02)
    cl.matrix_world = Matrix.Translation(tip) @ hr @ Matrix.Translation((0.29, 0, -0.03)) @ Matrix.Rotation(math.radians(-25), 4, 'Y')
    # level, leaning right
    lv = obj('level', 'sponge', [box((0, 0, 0), (0.12, 0.17, 1.0))], bevel=0.02)
    lv.matrix_world = Matrix.Translation((0.24, 0.0, 1.12)) @ Matrix.Rotation(math.radians(14), 4, 'Y')
    vial = obj('vial', 'water', [box((0, 0, 0), (0.125, 0.09, 0.16))], bevel=0.02)
    vial.matrix_world = lv.matrix_world @ Matrix.Translation((0, 0, 0.3))
    return 'stand', math.radians(-24)

def t_management():
    W, D = 1.25, 1.75
    obj('cb_board', 'trim', [prism(rounded_rect(W, D, 0.1, 8), 0, 0.05)], bevel=0.015)
    obj('cb_paper', 'paper', [box((0, -0.08, 0.06), (W - 0.34, D - 0.46, 0.012))], bevel=0.003)
    for k in range(4):
        y = 0.38 - k * 0.27
        obj('cb_box%d' % k, 'inkline', [box((-0.3, y, 0.072), (0.12, 0.12, 0.012))], bevel=0.004)
        obj('cb_line%d' % k, 'inkline', [box((0.05, y, 0.07), (0.5 - 0.1 * (k % 2), 0.045, 0.008))], bevel=0)
    # ticks in the first two boxes: timber-coloured, illustration only
    for k in range(2):
        y = 0.38 - k * 0.27
        obj('cb_tick%d' % k, 'graphite', tube_path([(-0.35, y + 0.005, 0.085), (-0.31, y - 0.04, 0.085), (-0.23, y + 0.06, 0.085)], 0.018, 8), bevel=0, smooth=True)
    obj('cb_clip_base', 'brass', [prism(rounded_rect(0.62, 0.2, 0.06, 6), 0.05, 0.1)], bevel=0.015)
    PARTS[-1].location = (0, D / 2 - 0.16, 0)
    obj('cb_clip_top', 'brass', [box((0, D / 2 - 0.12, 0.14), (0.42, 0.18, 0.06), rx=math.radians(-12))], bevel=0.02)
    obj('cb_clip_ring', 'steel', [H.torus_fn((0, D / 2 - 0.02, 0.17), (0, 0, 1), 0.07, 0.018, 24, 8)], bevel=0, smooth=True)
    return 'flat', math.radians(12)

# ------------------------------------------------------------------ r4: four more categories (2026-10-19)

def upright(y=0.0, x=0.0, z=0.0):
    """Prism drawn in XY, stood up in the XZ plane (extrusion along Y, front face toward -Y = camera)."""
    return Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(90), 4, 'X')

def t_investing():
    # three brass coin stacks rising left to right, a moss growth arrow climbing over them
    import random
    rnd = random.Random(7)
    r, t = 0.3, 0.1
    for si, (x, n) in enumerate(((-0.72, 3), (0.0, 6), (0.72, 9))):
        fns = []
        for k in range(n):
            fns.append(cyl((x + rnd.uniform(-0.025, 0.025), rnd.uniform(-0.025, 0.025), t / 2 + k * t), r, t * 0.92, seg=48))
        obj('coins%d' % si, 'coin', fns, bevel=0.022)
        obj('coin_face%d' % si, 'trim', [cyl((x, 0, n * t + 0.004), r * 0.62, 0.012, seg=40)], bevel=0.004)
    pts = [(-0.95, -0.42, 0.62), (-0.35, -0.42, 0.98), (0.05, -0.42, 0.86), (0.62, -0.42, 1.34)]
    obj('arrow', 'moss', tube_path(pts, 0.065, 16), bevel=0, smooth=True)
    d = (Vector(pts[-1]) - Vector(pts[-2])).normalized()
    q = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    obj('arrow_head', 'moss', [cyl(Vector(pts[-1]) + d * 0.14, 0.17, 0.32, rot=q, seg=32, r2=0.0)], bevel=0.02)
    return 'stand', math.radians(-18)

def t_financing():
    # a house-shaped key bow (window cut through it), shaft and bit, on a split ring with a round tag
    cut = cutter('key_window', [box((-0.575, -0.02, 0.06), (0.24, 0.24, 0.4))])
    cut.hide_viewport = False; cut.display_type = 'WIRE'   # a viewport-hidden cutter drops out of the depsgraph
    bow = [(-0.95, -0.36), (-0.2, -0.36), (-0.2, 0.18), (-0.575, 0.52), (-0.95, 0.18)]
    kb = obj('key_bow', 'keysteel', [prism(bow, 0.0, 0.12)], bevel=0.03, booleans=(cut,))
    cut.parent = kb   # build_tool/normalize only move PARTS; the cutter has to ride along
    obj('key_shaft', 'keysteel', [box((0.32, -0.12, 0.06), (1.05, 0.15, 0.1))], bevel=0.025)
    obj('key_bit', 'keysteel', [prism([(0.45, -0.2), (0.45, -0.4), (0.58, -0.4), (0.64, -0.3), (0.72, -0.3), (0.72, -0.4),
                                        (0.84, -0.4), (0.84, -0.2)], 0.0, 0.1)], bevel=0.015)
    obj('key_ring', 'coin', [H.torus_fn((-0.575, 0.68, 0.08), (0, 0, 1), 0.2, 0.035, 40, 10)], bevel=0, smooth=True)
    obj('tag', 'tile', [cyl((-0.3, 1.16, 0.05), 0.34, 0.06, seg=48)], bevel=0.02)
    obj('tag_eye', 'galv', [H.torus_fn((-0.44, 0.9, 0.09), (0, 0, 1), 0.05, 0.016, 20, 8)], bevel=0, smooth=True)
    obj('tag_mark', 'paper', [box((-0.3, 1.16, 0.085), (0.3, 0.07, 0.012))], bevel=0.003)
    return 'flat', math.radians(-30)

def shield_outline(w, h, n=14):
    """Heater shield, counter-clockwise: slightly arched top, sides curving down to one point."""
    top = h * 0.5
    def side(u, sgn):
        return (sgn * (w / 2) * math.cos(u * math.pi / 2) ** 0.75, top - 0.08 - (h - 0.08) * u ** 1.15)
    pts = [side(k / n, 1) for k in range(n + 1)]                 # right shoulder -> tip
    pts += [side(k / n, -1) for k in range(n - 1, -1, -1)]       # tip -> left shoulder
    pts += [(-w / 2 + w * k / 8, top - 0.08 + 0.08 * math.sin(math.pi * k / 8)) for k in range(1, 8)]   # top arc, left -> right
    return list(reversed(pts))

def t_insurance():
    W, Hs = 1.5, 1.8
    outer = shield_outline(W, Hs)
    obj('shield_rim', 'coin', [prism(outer, -0.11, 0.11)], bevel=0.04)
    PARTS[-1].matrix_world = upright(0.0, 0, Hs / 2)
    inner = [(x * 0.84, y * 0.86 - 0.02) for x, y in outer]
    obj('shield_face', 'navy', [prism(inner, -0.15, 0.15)], bevel=0.035)
    PARTS[-1].matrix_world = upright(0.0, 0, Hs / 2)
    # house emblem, raised on the front face (prism z -> -Y, toward the camera)
    hz = Hs / 2 + 0.04
    obj('em_wall', 'paper', [prism([(-0.3, -0.32), (0.3, -0.32), (0.3, 0.08), (-0.3, 0.08)], 0.12, 0.22)], bevel=0.02)
    PARTS[-1].matrix_world = upright(0, 0, hz)
    obj('em_roof', 'tile', [prism([(-0.44, 0.02), (0.44, 0.02), (0.0, 0.42)], 0.12, 0.25)], bevel=0.02)
    PARTS[-1].matrix_world = upright(0, 0, hz)
    obj('em_door', 'trim', [prism([(-0.08, -0.32), (0.08, -0.32), (0.08, -0.06), (-0.08, -0.06)], 0.21, 0.25)], bevel=0.01)
    PARTS[-1].matrix_world = upright(0, 0, hz)
    return 'stand', math.radians(-16)

def bubble(w, h, r, tail_side, seg=8):
    pts = rounded_rect(w, h, r, seg)
    # bottom edge sits between the BL corner (index 3*(seg+1)-1) and the BR corner start
    i = 3 * (seg + 1)
    if tail_side < 0:
        x1, x2, tip = -w / 2 + r + 0.02, -w / 2 + r + 0.3, (-w / 2 + 0.02, -h / 2 - 0.32)
    else:
        x1, x2, tip = w / 2 - r - 0.3, w / 2 - r - 0.02, (w / 2 - 0.02, -h / 2 - 0.32)
    return pts[:i] + [(x1, -h / 2), tip, (x2, -h / 2)] + pts[i:]

def t_negotiation():
    # two chunky speech bubbles facing each other: a plaster one behind (upper left), a flag-orange one in front (lower right)
    obj('bub_back', 'paper', [prism(bubble(1.3, 0.85, 0.36, -1), -0.12, 0.12)], bevel=0.05, segs=4)
    PARTS[-1].matrix_world = upright(0.22, -0.42, 1.35)
    obj('back_lines', 'slate', [box((-0.5, 0.085, 1.48), (0.62, 0.03, 0.07)),
                                 box((-0.6, 0.085, 1.3), (0.42, 0.03, 0.07))], bevel=0.012)
    obj('bub_front', 'flag', [prism(bubble(1.3, 0.85, 0.36, +1), -0.13, 0.13)], bevel=0.05, segs=4)
    PARTS[-1].matrix_world = upright(-0.22, 0.42, 0.78)
    for k, x in enumerate((-0.3, 0.0, 0.3)):
        obj('dot%d' % k, 'paper', [sphere((0.42 + x, -0.35, 0.8), 0.085, 3, (1, 0.45, 1))], bevel=0, smooth=True)
    return 'stand', math.radians(-10)

BUILDERS = {'repairs': t_repairs, 'showing': t_showing, 'comms': t_comms, 'bookkeeping': t_bookkeeping, 'travel': t_travel,
            'inspection': t_inspection, 'renovation': t_renovation, 'cleaning': t_cleaning, 'legal': t_legal,
            'supplies': t_supplies, 'management': t_management, 'investing': t_investing, 'financing': t_financing,
            'insurance': t_insurance, 'negotiation': t_negotiation}

# ------------------------------------------------------------------ scene

def build_tool(name):
    H.reset(); H.make_materials(); extra_materials()
    PARTS.clear()
    pose, spin = BUILDERS[name]()
    bpy.context.view_layer.update()
    # presentation: spin about Z (seen from the camera), then tilt flat-lays toward the camera
    M = Matrix.Rotation(math.radians(-45), 4, 'Z') @ Matrix.Rotation(spin, 4, 'Z')   # local +X -> screen-right, -Y -> camera
    if pose == 'flat':
        M = TILT @ M
    for ob in PARTS:
        ob.matrix_world = M @ ob.matrix_world
    bpy.context.view_layer.update()
    # register the parts with the house module so render.setup_lights links them as receivers
    H.OBJS.extend(PARTS)
    for ob in PARTS:
        ob['stage_req'] = -1; ob['t'] = 0.0; ob['role'] = ''; ob['kind'] = 'tool'; ob['mats'] = ''
    return pose

def frame_camera(fill=FILL):
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam'); cam.type = 'ORTHO'
    co = bpy.data.objects.new('cam', cam); sc.collection.objects.link(co); sc.camera = co
    dg = bpy.context.evaluated_depsgraph_get()
    xs, ys = [], []
    for ob in PARTS:
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        for v in me.vertices:
            p = ev.matrix_world @ v.co
            xs.append(p.dot(RIGHT)); ys.append(p.dot(UP))
        ev.to_mesh_clear()
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    ext = max(max(xs) - min(xs), max(ys) - min(ys))
    cam.ortho_scale = ext / fill
    co.matrix_world = Matrix.Translation(RIGHT * cx + UP * cy - FWD * 40) @ ROT
    cam.clip_start = 1; cam.clip_end = 100
    return dict(ortho_scale=cam.ortho_scale, extent=ext)

ORTHO = 3.0          # ONE camera for every tool: same rotation, same ortho scale
TARGET_FILL = 0.30   # optical size: alpha coverage of the square canvas
MAX_EXT = 0.90       # never let the projected bounding box exceed this share of the frame

def projected_bbox():
    dg = bpy.context.evaluated_depsgraph_get()
    xs, ys = [], []
    for ob in PARTS:
        ev = ob.evaluated_get(dg); me = ev.to_mesh()
        for v in me.vertices:
            p = ev.matrix_world @ v.co
            xs.append(p.dot(RIGHT)); ys.append(p.dot(UP))
        ev.to_mesh_clear()
    return min(xs), max(xs), min(ys), max(ys)

def scale_parts(k):
    x0, x1, y0, y1 = projected_bbox()
    # scale about the bbox centre (any point works for ortho; this keeps numbers small)
    c = RIGHT * ((x0 + x1) / 2) + UP * ((y0 + y1) / 2)
    M = Matrix.Translation(c) @ Matrix.Scale(k, 4) @ Matrix.Translation(-c)
    for ob in PARTS:
        ob.matrix_world = M @ ob.matrix_world
    bpy.context.view_layer.update()

def place_camera(co, cx, cy):
    co.data.ortho_scale = ORTHO
    co.matrix_world = Matrix.Translation(RIGHT * cx + UP * cy - FWD * 40) @ ROT

def measure(tmp):
    """Quick alpha-only render: coverage and alpha centroid offset (in world units along RIGHT/UP)."""
    sc = bpy.context.scene
    keep = (sc.render.resolution_x, sc.cycles.samples, sc.cycles.use_denoising)
    sc.render.resolution_x = sc.render.resolution_y = 256; sc.cycles.samples = 2; sc.cycles.use_denoising = False
    R.render_to(tmp)
    sc.render.resolution_x = sc.render.resolution_y = keep[0]; sc.cycles.samples = keep[1]; sc.cycles.use_denoising = keep[2]
    import numpy as np
    from PIL import Image
    a = np.asarray(Image.open(tmp).convert('RGBA'))[..., 3].astype(np.float64) / 255.0
    n = a.shape[0]
    cov = a.mean()
    yy, xx = np.mgrid[0:n, 0:n]
    cx = ((a * xx).sum() / a.sum() + 0.5) / n - 0.5
    cy = ((a * yy).sum() / a.sum() + 0.5) / n - 0.5
    return cov, cx * ORTHO, -cy * ORTHO

def normalize(tmp, log):
    """Scale the tool to TARGET_FILL coverage (clamped by MAX_EXT) and centre its alpha centroid."""
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam'); cam.type = 'ORTHO'
    co = bpy.data.objects.new('cam', cam); sc.collection.objects.link(co); sc.camera = co
    cam.clip_start = 1; cam.clip_end = 100
    for it in range(4):
        x0, x1, y0, y1 = projected_bbox()
        ext = max(x1 - x0, y1 - y0)
        place_camera(co, (x0 + x1) / 2, (y0 + y1) / 2)
        cov, dx, dy = measure(tmp)
        k = math.sqrt(TARGET_FILL / max(cov, 1e-4))
        # the box must still fit once the alpha centroid is moved to the frame centre
        k = min(k, 0.97 * ORTHO / (ext + 2 * max(abs(dx), abs(dy))), MAX_EXT * ORTHO / ext)
        if abs(k - 1) < 0.01:
            break
        scale_parts(k)
    x0, x1, y0, y1 = projected_bbox()
    place_camera(co, (x0 + x1) / 2, (y0 + y1) / 2)
    cov, dx, dy = measure(tmp)
    # optical centre = alpha centroid, but never push the bounding box past 97% of the frame
    lim_x = max(0.0, (0.97 * ORTHO - (x1 - x0)) / 2); lim_y = max(0.0, (0.97 * ORTHO - (y1 - y0)) / 2)
    dx = max(-lim_x, min(lim_x, dx)); dy = max(-lim_y, min(lim_y, dy))
    place_camera(co, (x0 + x1) / 2 + dx, (y0 + y1) / 2 + dy)
    cov2, dx2, dy2 = measure(tmp)
    log.update(dict(coverage=round(cov2, 4), centroid_off_px_1024=(round(dx2 / ORTHO * 1024, 1), round(-dy2 / ORTHO * 1024, 1)),
                    bbox_ext=round(max(x1 - x0, y1 - y0) / ORTHO, 3)))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--tools', default=','.join(TOOLS))
    ap.add_argument('--variants', default='light,dark')
    ap.add_argument('--res', type=int, default=1024)
    ap.add_argument('--samples', type=int, default=96)
    a = ap.parse_args()
    out = os.path.abspath(a.out); os.makedirs(out, exist_ok=True)
    log = []
    for t in a.tools.split(','):
        build_tool(t)
        R.setup_render(a.res, a.samples)
        for o in [o for o in bpy.context.scene.objects if o.type == 'LIGHT' or o.name.startswith('shadow_catcher')]:
            bpy.data.objects.remove(o)
        catcher = R.setup_lights('light'); catcher.hide_render = True
        info = {}
        normalize(os.path.join(out, f'_measure_{t}.png'), info)
        for v in a.variants.split(','):
            for o in [o for o in bpy.context.scene.objects if o.type == 'LIGHT' or o.name.startswith('shadow_catcher')]:
                bpy.data.objects.remove(o)
            catcher = R.setup_lights(v)
            catcher.hide_render = True
            fn = os.path.join(out, f'tool_{t}__{v}.png')
            dt = R.render_to(fn)
            log.append(dict(file=os.path.basename(fn), seconds=round(dt, 1), **info))
            print('RENDERED', fn, round(dt, 1), json.dumps(info), flush=True)
        os.remove(os.path.join(out, f'_measure_{t}.png'))
    with open(os.path.join(out, 'render-log.jsonl'), 'a') as f:
        for r in log:
            f.write(json.dumps(r) + '\n')

if __name__ == '__main__':
    main()
