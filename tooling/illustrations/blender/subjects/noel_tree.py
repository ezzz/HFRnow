"""Christmas fir tree: tiers, trunk, gold star, baubles and a garland."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_tree.png")

def build():
    green = M("#2E7D4F")
    for i, (z, r1, r2, h) in enumerate([(0.25, 1.30, 0.35, 0.80), (0.95, 1.05, 0.25, 0.75), (1.55, 0.80, 0.15, 0.70), (2.10, 0.55, 0.02, 0.65)]):
        t = cyl(f"tier{i}", (0, 0, z + h / 2), r1, r2, h, seg=12)
        d = t.modifiers.new("d", "DISPLACE"); tex = bpy.data.textures.new("n", "CLOUDS"); tex.noise_scale = 0.25; d.texture = tex; d.strength = 0.06
        solid(t, green)
    shade(cyl("trunk", (0, 0, 0.0), 0.16, 0.16, 0.5), M("#7A4A2A"))
    shade(poly_prism("star", star2d(5, 0.32, 0.14), 0.10, loc=(0, 0.05, 2.95), rot=(90, 0, 0)), M("#E3B341"))
    cols = ["#D21F3C", "#E3B341", "#2E86DE", "#D21F3C", "#F2F2F2"]
    k = 0
    for z, r in ((0.45, 1.12), (0.75, 0.70), (1.10, 0.92), (1.45, 0.55), (1.70, 0.72), (2.25, 0.45)):
        for a in (-110, -70, -40):
            aa = math.radians(a + 25 * (k % 3)); k += 1
            shade(ell("bauble", (r * math.cos(aa), r * math.sin(aa), z), (0.10, 0.10, 0.10)), M(cols[k % 5]))
    gp = []
    for i in range(40):
        t = i / 39
        z = 0.35 + 2.0 * t; r = 1.30 - 1.05 * t; a = math.radians(-160 + 720 * t)
        gp.append((r * math.cos(a), r * math.sin(a), z))
    shade(tube("garland", gp, [0.035] * len(gp), res=8), M("#E3B341"))
    return dict(view=(-0.2, -1.0, 0.15))


run_subject(build, OUT)
