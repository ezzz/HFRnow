"""Witch on a broom flying to the LEFT: head, nose and hat lead; cape, hair and broom straw trail."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "samain_witch.png")

def build():
    robe, skin, hat = M("#5B3A8A"), M("#EBC9A9"), M("#2E2840")
    shade(tube("stick", [(-1.4, 0, 0.10), (0.0, 0, -0.10), (1.3, 0, -0.30)], [0.05, 0.05, 0.05]), M("#9A6A3A"))
    for k in range(14):
        a = 2 * math.pi * k / 14
        shade(tube("straw", [(1.25, 0, -0.30), (1.70, 0.12 * math.cos(a), -0.36 + 0.12 * math.sin(a)), (2.15, 0.26 * math.cos(a), -0.40 + 0.24 * math.sin(a))], [0.045, 0.04, 0.03]), M("#E1B866"))
    shade(cyl("bind", (1.28, 0, -0.30), 0.10, 0.10, 0.12, rot=(0, 90, 0)), M("#7A4A2A"))
    clay([tube("dress", [(-0.10, 0, 0.95), (0.05, 0, 0.45), (0.25, 0, 0.0)], [0.26, 0.36, 0.42]),
          tube("legF", [(0.0, -0.18, 0.05), (-0.25, -0.22, -0.30), (-0.35, -0.20, -0.55)], [0.10, 0.08, 0.07]),
          tube("legB", [(0.15, 0.18, 0.05), (0.0, 0.20, -0.30), (-0.05, 0.18, -0.55)], [0.10, 0.08, 0.07])], "body", robe, voxel=0.025)
    for y, dx in ((-0.20, 0.0), (0.18, 0.3)):
        shade(tube("boot", [(-0.30 + dx, y, -0.55), (-0.52 + dx, y, -0.58), (-0.60 + dx, y, -0.50)], [0.08, 0.07, 0.05]), M("#2B2440"))
    shade(tube("cape", [(-0.10, 0, 1.0), (0.45, 0, 0.85), (0.95, 0, 0.55), (1.35, 0, 0.45)], [0.30, 0.34, 0.30, 0.12], res=28), M("#3B2A5A"))
    shade(tube("arm", [(-0.15, -0.22, 0.80), (-0.45, -0.25, 0.45), (-0.70, -0.08, 0.10)], [0.09, 0.08, 0.07]), robe)
    shade(ell("hand", (-0.72, -0.05, 0.09), (0.07, 0.07, 0.07)), skin)
    clay([ell("head", (-0.20, 0, 1.25), (0.22, 0.21, 0.24)), cyl("nose", (-0.48, 0, 1.22), 0.06, 0.01, 0.30, rot=(0, -80, 0)),
          ell("chin", (-0.36, 0, 1.06), (0.08, 0.08, 0.08))], "head", skin, voxel=0.012, smooth=4)
    shade(tube("hair", [(-0.05, 0, 1.30), (0.30, 0, 1.15), (0.70, 0, 0.95), (1.05, 0, 0.85)], [0.20, 0.18, 0.12, 0.04], res=24), M("#4A3A3A"))
    shade(cyl("brim", (-0.18, 0, 1.40), 0.55, 0.55, 0.04, rot=(0, 8, 0)), hat)
    shade(tube("cone", [(-0.18, 0, 1.40), (-0.10, 0, 1.75), (0.15, 0, 2.05), (0.45, 0, 2.15)], [0.30, 0.22, 0.12, 0.03], res=24), hat)
    shade(cyl("band", (-0.17, 0, 1.47), 0.29, 0.27, 0.08, rot=(0, 8, 0)), M("#E9781A"))
    tgt = proxy([((-0.20, 0, 1.25), (0.22, 0.21, 0.24))], "px")
    decal("eye", [(-0.34 + 0.03 * math.cos(t), 1.28 + 0.035 * math.sin(t)) for t in [k * math.pi / 6 for k in range(12)]], 0, tgt, F("#2B2F3A"))
    return dict(view=(0.05, -1.0, 0.15))


run_subject(build, OUT)
