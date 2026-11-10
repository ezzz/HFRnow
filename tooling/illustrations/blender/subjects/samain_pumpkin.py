"""Jack-o'-lantern: ribbed pumpkin (separate lobes, so each rib keeps its own contour line), curled stem,
glowing carved eyes, nose and a smile with two square teeth (thin prisms shrink-wrapped onto the skin)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out")


def carve(name, pts, z, target, mat):
    c = poly_prism(name, pts, 0.03, loc=(0, -2.0, z), rot=(90, 0, 0))
    apply_all(c)
    bpy.ops.object.select_all(action="DESELECT"); bpy.context.view_layer.objects.active = c; c.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT"); bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.mesh.subdivide(number_cuts=12); bpy.ops.object.mode_set(mode="OBJECT")
    sw = c.modifiers.new("sw", "SHRINKWRAP"); sw.target = target; sw.wrap_method = "PROJECT"
    sw.use_project_y = True; sw.use_negative_direction = True; sw.use_positive_direction = True; sw.offset = 0.025
    apply_all(c)
    return shade(c, mat)


def build():
    lobes = []
    for i in range(10):
        a = 2 * math.pi * i / 10
        lobes.append(shade(ell(f"lobe{i}", (0.52 * math.cos(a), 0.52 * math.sin(a), 0), (0.50, 0.66, 0.82), rot=(0, 0, math.degrees(a) + 90), seg=64), M("#EE8A33")))
    core = shade(ell("core", (0, 0, 0), (0.98, 0.98, 0.80), seg=64), M("#EE8A33"))
    skin = []
    for i in range(10):
        a = 2 * math.pi * i / 10
        skin.append(ell(f"skin{i}", (0.52 * math.cos(a), 0.52 * math.sin(a), 0), (0.50, 0.66, 0.82), rot=(0, 0, math.degrees(a) + 90), seg=64))
    body = join(skin, "skin")
    glow = F("#FFD36B")
    if os.environ.get("NOFACE"):
        bpy.data.objects.remove(body)
        stem = tube("stem", [(0, 0, 0.70), (0.02, 0.0, 0.92), (0.12, -0.04, 1.08), (0.28, -0.10, 1.12)], [0.11, 0.09, 0.07, 0.05]); shade(stem, M("#7C9B5A"))
        return dict(view=(-0.2, -1.0, 0.25))
    carve("eyeL", [(-0.62, 0.0), (-0.18, 0.0), (-0.36, 0.34)], 0.18, body, glow)
    carve("eyeR", [(0.18, 0.0), (0.62, 0.0), (0.40, 0.34)], 0.18, body, glow)
    carve("nose", [(-0.10, 0.0), (0.10, 0.0), (0.0, 0.16)], 0.0, body, glow)
    carve("mouth", [(-0.80, 0.10), (-0.50, -0.02), (-0.30, -0.06), (-0.30, -0.20), (-0.10, -0.20), (-0.10, -0.08), (0.30, -0.06),
                    (0.62, 0.02), (0.80, 0.12), (0.62, -0.20), (0.30, -0.36), (0.30, -0.26), (0.10, -0.26), (0.10, -0.40), (-0.30, -0.40), (-0.62, -0.24)],
          -0.06, body, glow)
    stem = tube("stem", [(0, 0, 0.70), (0.02, 0.0, 0.92), (0.12, -0.04, 1.08), (0.28, -0.10, 1.12)], [0.11, 0.09, 0.07, 0.05])
    shade(stem, M("#7C9B5A"))
    bpy.data.objects.remove(body)
    return dict(view=(-0.2, -1.0, 0.25))


run_subject(build, os.path.join(OUTDIR, "samain_pumpkin.png"))
