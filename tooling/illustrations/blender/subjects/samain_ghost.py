"""Sheet ghost leaning forward to the LEFT (its direction of travel), wavy hem, arms trailing."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "samain_ghost.png")

def build():
    parts = [ell("dome", (0, 0, 1.05), (0.56, 0.56, 0.58)), tube("sheet", [(0, 0, 1.0), (0, 0, 0.6), (0.08, 0, 0.0), (0.18, 0, -0.55)], [0.56, 0.60, 0.66, 0.78], res=24)]
    for i in range(9):
        a = 2 * math.pi * i / 9
        parts.append(ell("hem", (0.18 + 0.72 * math.cos(a), 0.72 * math.sin(a), -0.62 - 0.06 * (i % 2)), (0.22, 0.22, 0.20)))
    parts.append(tube("armL", [(0.0, -0.45, 0.55), (0.45, -0.58, 0.30), (0.85, -0.52, 0.12)], [0.20, 0.15, 0.06]))
    parts.append(tube("armR", [(0.0, 0.45, 0.55), (0.45, 0.58, 0.35), (0.85, 0.52, 0.20)], [0.20, 0.15, 0.06]))
    clay(parts, "ghost", M("#F2F0F7", warm=False), voxel=0.03, smooth=8)
    tgt = proxy([((0, 0, 0.9), (0.56, 0.56, 0.62))], "px")
    ring = lambda cx, cz, rx, rz: [(cx + rx * math.cos(t), cz + rz * math.sin(t)) for t in [k * math.pi / 8 for k in range(16)]]
    decal("eyeL", ring(-0.22, 0.95, 0.07, 0.11), 0, tgt, F("#2B2F3A"))
    decal("eyeR", ring(0.10, 0.95, 0.07, 0.11), 0, tgt, F("#2B2F3A"))
    decal("mouth", ring(-0.06, 0.70, 0.07, 0.09), 0, tgt, F("#2B2F3A"))
    return dict(view=(0.0, -1.0, 0.15))


run_subject(build, OUT)
