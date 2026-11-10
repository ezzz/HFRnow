"""Snowman with top hat, carrot nose, scarf and stick arms."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_snowman.png")

def build():
    clay([ell("b", (0, 0, 0.55), (0.62, 0.62, 0.58)), ell("m", (0, 0, 1.30), (0.44, 0.44, 0.42)), ell("h", (0, 0, 1.88), (0.30, 0.30, 0.30))], "snowman", M("#F4F6FA", warm=False), voxel=0.02)
    coal = M("#2B2F3A")
    for p in ((-0.10, -0.27, 1.95), (0.10, -0.27, 1.95), (0, -0.43, 1.40), (0, -0.44, 1.22), (0, -0.60, 0.70)):
        shade(ell("coal", p, (0.04, 0.04, 0.04)), coal)
    shade(cyl("carrot", (0, -0.40, 1.86), 0.05, 0.0, 0.30, rot=(90, 0, 0)), M("#F28C1E"))
    shade(cyl("brim", (0, 0, 2.15), 0.38, 0.38, 0.05), coal); shade(cyl("top", (0, 0, 2.37), 0.24, 0.24, 0.42), coal)
    shade(cyl("hb", (0, 0, 2.22), 0.25, 0.25, 0.07), M("#D21F3C"))
    shade(tube("scarf", [(0.32 * math.cos(math.radians(d)), 0.32 * math.sin(math.radians(d)), 1.62) for d in range(0, 361, 30)], [0.07] * 13, res=10), M("#D21F3C"))
    shade(tube("tail", [(0.18, -0.26, 1.60), (0.24, -0.34, 1.40), (0.28, -0.36, 1.22)], [0.07, 0.06, 0.05]), M("#D21F3C"))
    for s in (1, -1):
        shade(tube("arm", [(s * 0.40, 0, 1.35), (s * 0.80, 0, 1.60), (s * 1.0, 0, 1.75)], [0.03, 0.025, 0.015]), M("#7A4A2A"))
    return dict(view=(-0.2, -1.0, 0.18))


run_subject(build, OUT)
