"""Vampire in a high-collared cape spread like wings, pale face, slicked hair, facing the viewer."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "samain_vampire.png")

def build():
    cloak, lining = M("#2B2440"), M("#A3263A")
    clay([cyl("body", (0, 0, 0.8), 0.32, 0.26, 1.6), ell("shoulders", (0, 0, 1.55), (0.42, 0.24, 0.16))], "suit", M("#3A3550"), voxel=0.025)
    for side in (1, -1):
        pts = [(side * x, z) for x, z in [(0.25, 1.65), (0.9, 1.75), (1.45, 1.35), (1.35, 0.95), (1.15, 1.05), (1.05, 0.55), (0.85, 0.70), (0.70, 0.10), (0.30, 0.0)]]
        if side < 0:
            pts = list(reversed(pts))
        shade(poly_prism("cape", pts, 0.05, loc=(0, 0.20, 0), rot=(90, 0, 0)), cloak)
        shade(poly_prism("lining", [(x * 0.9, z * 0.97 + 0.02) for x, z in pts], 0.02, loc=(0, 0.14, 0), rot=(90, 0, 0)), lining)
        cp = [(side * 0.16, 1.62), (side * 0.48, 2.10), (side * 0.40, 1.60)]
        shade(poly_prism("collar", cp if side > 0 else list(reversed(cp)), 0.04, loc=(0, 0.06, 0), rot=(90, 0, 0)), lining)
    clay([ell("head", (0, 0, 1.92), (0.20, 0.19, 0.25)), ell("chin", (0, -0.08, 1.72), (0.09, 0.08, 0.07))], "head", M("#E8E2EA", warm=False), voxel=0.012)
    shade(ell("hair", (0, 0.03, 2.03), (0.21, 0.20, 0.17)), M("#1E1A2A"))
    tgt = proxy([((0, 0, 1.92), (0.20, 0.19, 0.25))], "px")
    decal("peak", [(-0.10, 2.10), (0.0, 1.98), (0.10, 2.10)], 0, tgt, F("#1E1A2A"))
    for sx in (-0.07, 0.07):
        decal("eye", [(sx + 0.035 * math.cos(t), 1.93 + 0.02 * math.sin(t)) for t in [k * math.pi / 6 for k in range(12)]], 0, tgt, F("#A3263A"))
    decal("mouth", [(-0.06, 1.80), (0.06, 1.80), (0.04, 1.78), (-0.04, 1.78)], 0, tgt, F("#2B2F3A"))
    decal("fangs", [(-0.04, 1.78), (-0.025, 1.745), (-0.015, 1.78), (0.015, 1.78), (0.025, 1.745), (0.04, 1.78)], 0, tgt, F("#FFFFFF"), offset=0.03)
    return dict(view=(0.0, -1.0, 0.10))


run_subject(build, OUT)
