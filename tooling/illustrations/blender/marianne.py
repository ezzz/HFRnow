"""Marianne: marble bust with a Phrygian cap, procedurally modelled (no external asset).
blender -b -P marianne.py -- out.png 1600"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from common import *

a = args()
OUT = a[0] if a else "/tmp/marianne.png"
SIZE = int(a[1]) if len(a) > 1 else 1200

sc = reset()
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.30
stone = toon("stone", [("#8796A6", 0.0), ("#A9B6C2", 0.12), ("#F2AE8C", 0.27), ("#F7CDB4", 0.345), ("#F4EFE8", 0.42)])

# ---------------- head (face toward -Y), built from soft primitives then voxel-remeshed like clay
parts = [
    ell("cranium", (0, 0.15, 0.35), (0.78, 0.90, 0.92)),
    ell("face", (0, -0.22, -0.02), (0.58, 0.52, 0.78)),
    ell("jaw", (0, -0.34, -0.50), (0.40, 0.40, 0.32)),
    ell("chin", (0, -0.56, -0.68), (0.17, 0.14, 0.15)),
    ell("cheekL", (0.36, -0.42, -0.12), (0.25, 0.22, 0.24)),
    ell("cheekR", (-0.36, -0.42, -0.12), (0.25, 0.22, 0.24)),
    ell("brow", (0, -0.60, 0.24), (0.48, 0.10, 0.07)),
    ell("noseBridge", (0, -0.70, 0.02), (0.075, 0.13, 0.27), rot=(-14, 0, 0)),
    ell("noseTip", (0, -0.83, -0.23), (0.095, 0.09, 0.09)),
    ell("nostrilL", (0.09, -0.76, -0.28), (0.065, 0.06, 0.055)),
    ell("nostrilR", (-0.09, -0.76, -0.28), (0.065, 0.06, 0.055)),
    ell("lipU", (0, -0.72, -0.42), (0.20, 0.085, 0.06)),
    ell("lipL", (0, -0.69, -0.51), (0.17, 0.09, 0.07)),
    ell("earL", (0.70, 0.08, -0.02), (0.13, 0.18, 0.26), rot=(0, 0, 12)),
    ell("earR", (-0.70, 0.08, -0.02), (0.13, 0.18, 0.26), rot=(0, 0, -12)),
    cyl("neck", (0, 0.08, -1.10), 0.40, 0.36, 1.05, rot=(-10, 0, 0)),
]
head = join(parts, "head")
remesh(head, voxel=0.022, smooth=4, factor=0.5)
for sx in (0.28, -0.28):
    boolean(head, ell("socket", (sx, -0.68, 0.10), (0.15, 0.12, 0.09)))
remesh(head, voxel=0.018, smooth=4, factor=0.5)
eyes = [ell("eyeL", (0.28, -0.585, 0.09), (0.12, 0.10, 0.085)), ell("eyeR", (-0.28, -0.585, 0.09), (0.12, 0.10, 0.085)),
        ell("lidL", (0.28, -0.62, 0.15), (0.15, 0.09, 0.045), rot=(10, 0, 0)), ell("lidR", (-0.28, -0.62, 0.15), (0.15, 0.09, 0.045), rot=(10, 0, 0))]
eyes = join(eyes, "eyes")
shade(head, stone); shade(eyes, stone)

# ---------------- hair: wavy locks from under the cap band, behind the ear, to the nape; curls
locks = []
for side in (1, -1):
    for k in range(14):
        ang = math.radians(78 + k * 7.5)          # 0 = straight ahead (-Y); 90 = the side; 180 = the back
        pts, rad = [], []
        for t in range(7):
            z = 0.36 - t * 0.33
            r = 0.84 + 0.05 * t - (0.10 if t >= 4 else 0.0) * (k > 9)
            a = ang + math.radians(4 * t)            # drifts towards the back as it falls
            wav = 0.05 * math.sin(t * 1.7 + k * 0.9)
            pts.append((side * (r + wav) * math.sin(a), 0.12 - (r + wav) * math.cos(a), z))
            rad.append(max(0.04, 0.115 - 0.012 * t))
        locks.append(tube(f"lock{side}{k}", pts, rad, res=20))
locks.append(ell("back", (0, 0.55, -0.35), (0.62, 0.42, 0.85)))
locks.append(ell("nape", (0, 0.32, -0.95), (0.62, 0.48, 0.62)))
for sx in (1, -1):
    locks.append(ell("fill", (sx * 0.52, 0.12, -0.72), (0.28, 0.38, 0.55)))
    locks.append(ell("fill2", (sx * 0.66, 0.22, -1.0), (0.24, 0.32, 0.38)))
hair = join(locks, "hair"); remesh(hair, voxel=0.016, smooth=3, factor=0.4); shade(hair, stone)

# ---------------- Phrygian cap: rolled band + soft cone whose tip folds forward
band_pts = []
for i in range(13):
    t = 2 * math.pi * i / 12
    band_pts.append((0.80 * math.sin(t), 0.14 - 0.90 * math.cos(t), 0.40 + 0.14 * math.cos(t)))
cu = bpy.data.curves.new("band", "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = 1; cu.bevel_resolution = 6; cu.resolution_u = 24
sp = cu.splines.new("BEZIER"); sp.bezier_points.add(len(band_pts) - 2); sp.use_cyclic_u = True
for bp, p in zip(sp.bezier_points, band_pts[:-1]):
    bp.co = p; bp.handle_left_type = bp.handle_right_type = "AUTO"; bp.radius = 0.06
band = to_mesh(link(bpy.data.objects.new("band", cu)))
cone = tube("cone", [(0, 0.12, 0.46), (0, 0.26, 0.92), (0, 0.14, 1.24), (0, -0.26, 1.36), (0, -0.66, 1.24), (0, -0.94, 1.04), (0, -1.00, 0.84)],
            [0.80, 0.72, 0.56, 0.40, 0.29, 0.19, 0.11], res=40)
cap = join([cone], "cap")
d = cap.modifiers.new("d", "DISPLACE")
tex = bpy.data.textures.new("folds", "CLOUDS"); tex.noise_scale = 0.6; d.texture = tex; d.strength = 0.025
remesh(cap, voxel=0.02, smooth=10, factor=0.6)
shade(cap, stone); shade(band, stone)
# cockade on the visible (subject's left, +X) side
for r, col, dx in ((0.17, "#3D5FA8", 0.0), (0.11, "#FFFFFF", 0.012), (0.055, "#D9473E", 0.024)):
    ck = cyl("cock", (0.86 + dx, -0.12, 0.78), r, r, 0.03, rot=(0, 90, 0))
    shade(ck, toon("ck" + col, flat=col))

# ---------------- torso, shoulders, clavicles; drapery over the left shoulder
tparts = [ell("chest", (0, 0.22, -2.10), (1.62, 0.95, 0.95)), ell("shL", (1.20, 0.22, -1.80), (0.55, 0.55, 0.45)),
          ell("shR", (-1.20, 0.22, -1.80), (0.55, 0.55, 0.45)), ell("pecL", (0.55, -0.40, -2.25), (0.55, 0.30, 0.42)),
          ell("pecR", (-0.55, -0.40, -2.25), (0.55, 0.30, 0.42)),
          tube("clavL", [(0.15, -0.42, -1.62), (0.6, -0.40, -1.58), (1.1, -0.2, -1.52)], [0.07, 0.06, 0.05]),
          tube("clavR", [(-0.15, -0.42, -1.62), (-0.6, -0.40, -1.58), (-1.1, -0.2, -1.52)], [0.07, 0.06, 0.05])]
torso = join(tparts, "torso")
boolean(torso, box("cut", (0, 0, -3.55), (6, 6, 1.6), bevel=0))
for sx in (1, -1):   # classical bust truncation at the arms
    c = box("armcut", (sx * 2.35, 0.2, -2.2), (1.4, 3.0, 3.0), bevel=0); c.rotation_euler.y = math.radians(sx * 18)
    boolean(torso, c)
remesh(torso, voxel=0.03, smooth=16, factor=0.7); shade(torso, stone)
folds = []
for k in range(6):
    o = (k - 2.5) * 0.20
    sag = 0.05 * math.sin(k * 1.7)
    folds.append(tube(f"fold{k}", [(1.70, 0.55 + o * 0.3, -1.66 + o * 0.6), (1.25, -0.25, -1.55 + o * 0.7), (0.70, -0.74 + sag - 0.08 * (k % 2), -1.95 + o),
                                   (0.0, -0.90 - sag - 0.09 * (k % 2), -2.35 + o * 1.15), (-0.80, -0.74 - 0.08 * (k % 2), -2.55 + o * 1.05), (-1.60, -0.22, -2.62 + o * 0.45)],
                      [0.07, 0.10 + 0.02 * (k % 2), 0.12, 0.13 + 0.03 * (k % 3 == 0), 0.11, 0.08], res=28))
drape = join(folds, "drape"); remesh(drape, voxel=0.02, smooth=5, factor=0.5)
boolean(drape, box("cut2", (0, 0, -3.55), (6, 6, 1.6), bevel=0))
shade(drape, stone)

# ---------------- pedestal
socle = cyl("socle", (0, 0.22, -2.95), 0.80, 0.62, 0.36); shade(socle, stone)
block = box("block", (0, 0.22, -3.30), (2.5, 1.7, 0.36), bevel=0.04); shade(block, stone)
base = box("base", (0, 0.22, -3.62), (2.9, 2.0, 0.28), bevel=0.04); shade(base, stone)

# ---------------- ink drawn on the surfaces (projected onto the mesh, lifted along the normal)
def ink_on(target, name, pts, r=0.011, lift=0.012):
    bpy.context.view_layer.update()
    mw = target.matrix_world; inv = mw.inverted()
    proj = []
    for p in pts:
        ok, loc, nor, _ = target.closest_point_on_mesh(inv @ Vector(p))
        proj.append(tuple(mw @ (loc + nor * lift)) if ok else p)
    return ink_line(name, proj, r)


face_ink = []
for sx in (1, -1):
    face_ink += [ink_on(head, "lidU", [(sx * 0.17, -0.70, 0.15), (sx * 0.28, -0.72, 0.19), (sx * 0.40, -0.66, 0.15)], 0.010),
                 ink_on(head, "lidL", [(sx * 0.19, -0.70, 0.04), (sx * 0.28, -0.71, 0.02), (sx * 0.37, -0.67, 0.05)], 0.008),
                 ink_on(head, "brow", [(sx * 0.16, -0.72, 0.28), (sx * 0.28, -0.72, 0.31), (sx * 0.42, -0.64, 0.27)], 0.006),
                 ink_on(head, "wing", [(sx * 0.12, -0.80, -0.20), (sx * 0.17, -0.78, -0.27), (sx * 0.12, -0.82, -0.33)], 0.010),
                 ]
face_ink += [ink_on(head, "mouth", [(-0.17, -0.78, -0.47), (-0.06, -0.80, -0.465), (0, -0.80, -0.47), (0.06, -0.80, -0.465), (0.17, -0.78, -0.47)], 0.011),
             ink_on(head, "lipL", [(-0.10, -0.78, -0.58), (0, -0.79, -0.595), (0.10, -0.78, -0.58)], 0.007),
             ink_on(head, "jaw", [(0.46, -0.36, -0.60), (0.60, -0.15, -0.44), (0.66, 0.02, -0.30)], 0.008),
             ink_on(head, "neckL", [(0.22, -0.40, -0.95), (0.26, -0.30, -1.30)], 0.007)]
face_ink = join(face_ink, "faceInk")

# hair: ink strands along each lock, curls at the ends
strands = []
for side in (1, -1):
    for k in range(0, 14, 2):
        ang = math.radians(78 + k * 7.5)
        pts = []
        for t in range(7):
            z = 0.36 - t * 0.33
            r = 0.84 + 0.05 * t + 0.10
            a = ang + math.radians(4 * t)
            wav = 0.05 * math.sin(t * 1.7 + k * 0.9)
            pts.append((side * (r + wav) * math.sin(a), 0.12 - (r + wav) * math.cos(a), z))
        strands.append(ink_on(hair, f"strand{side}{k}", pts, 0.009, lift=0.01))
        ex, ey, ez = pts[-1]
        curl = [(ex + 0.10 * math.cos(u) * (1 - u / 9), ey + 0.10 * math.sin(u) * (1 - u / 9), ez - 0.02 * u) for u in [j * 0.9 for j in range(9)]]
cap_ink = [ink_on(cap, "fold1", [(0.0, -0.60, 0.94), (0.0, -0.44, 1.10), (0.0, -0.16, 1.22)], 0.012),
           ink_on(cap, "fold2", [(0.40, -0.20, 0.70), (0.42, 0.0, 1.0), (0.30, 0.10, 1.20)], 0.008),
           ink_on(cap, "fold3", [(-0.40, -0.20, 0.70), (-0.42, 0.0, 1.0), (-0.30, 0.10, 1.20)], 0.008)]

# turn the head and cap three-quarters to the viewer's left, the bust slightly (rotate rigs about the world origin)
def rig(objs, name, rz):
    e = link(bpy.data.objects.new(name, None))
    bpy.context.view_layer.update()
    for o in objs:
        mw = o.matrix_world.copy(); o.parent = e; o.matrix_world = mw
    e.rotation_euler.z = math.radians(rz)
    return e


rig([head, eyes, hair, cap, band, face_ink] + strands + cap_ink + [x for x in bpy.data.objects if x.name.startswith("cock")], "headRig", -52)
rig([torso, drape, socle, block, base], "bodyRig", -10)

sun(rot=(50, 0, -28), strength=3.2)
camera((0.6, -15.5, -0.6), (0, 0, -1.05), lens=85)
freestyle(outer=SIZE / 190, inner=SIZE / 560, crease=120, suggestive=True, min_len=SIZE / 55)

if os.environ.get('NOFS'):
    bpy.context.scene.render.use_freestyle = False
render(OUT, SIZE, SIZE, samples=16)
