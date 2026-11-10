"""Witch standing and sweeping the decorations away to the right (end of Spooktober)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "samain_witch_sweep.png")

def build():
    robe, skin, hat = M("#5B3A8A"), M("#EBC9A9"), M("#2E2840")
    clay([cyl("dress", (0, 0, 0.55), 0.55, 0.22, 1.1), ell("chest", (0, 0, 1.05), (0.25, 0.20, 0.22))], "body", robe, voxel=0.025)
    shade(tube("armF", [(0.10, -0.22, 1.05), (0.35, -0.30, 0.80), (0.55, -0.30, 0.62)], [0.09, 0.08, 0.07]), robe)
    shade(tube("armB", [(-0.10, -0.15, 1.05), (0.10, -0.32, 0.95), (0.30, -0.32, 0.92)], [0.09, 0.08, 0.07]), robe)
    shade(tube("stick", [(0.15, -0.32, 1.05), (0.80, -0.34, 0.45), (1.25, -0.35, 0.10)], [0.045, 0.045, 0.045]), M("#9A6A3A"))
    for k in range(12):
        a = -0.6 + 1.2 * k / 11
        shade(tube("straw", [(1.22, -0.35, 0.12), (1.45 + 0.1 * math.sin(a), -0.35 + 0.25 * a, 0.02), (1.75 + 0.15 * math.sin(a), -0.35 + 0.45 * a, -0.02)], [0.045, 0.04, 0.03]), M("#E1B866"))
    for x, z, r in ((2.0, 0.10, 0.10), (2.25, 0.22, 0.07), (2.1, 0.30, 0.05), (2.45, 0.12, 0.06)):
        shade(ell("dust", (x, -0.3, z), (r, r, r)), M("#C9C2CC", warm=False))
    clay([ell("head", (0.02, 0, 1.45), (0.22, 0.21, 0.24)), cyl("nose", (0.0, -0.30, 1.42), 0.06, 0.01, 0.30, rot=(90, 0, 0))], "head", skin, voxel=0.012)
    shade(tube("hair", [(0.0, 0.12, 1.55), (0.05, 0.25, 1.20), (0.0, 0.28, 0.90)], [0.22, 0.18, 0.06]), M("#4A3A3A"))
    shade(cyl("brim", (0.02, 0, 1.62), 0.55, 0.55, 0.04), hat)
    shade(tube("cone", [(0.02, 0, 1.62), (0.05, 0.02, 1.95), (0.20, 0.06, 2.25), (0.45, 0.08, 2.35)], [0.30, 0.22, 0.12, 0.03]), hat)
    shade(cyl("band", (0.02, 0, 1.69), 0.29, 0.27, 0.08), M("#E9781A"))
    return dict(view=(-0.25, -1.0, 0.18))


run_subject(build, OUT)
