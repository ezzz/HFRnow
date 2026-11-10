"""Elf carrying a box of tree ornaments (packing away at the end of Christmas)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_elf.png")

def build():
    green, skin, red, white = M("#2F8F46"), M("#EBC9A9"), M("#C8283A"), M("#F4F2EE", warm=False)
    clay([cyl("tunic", (0, 0, 0.62), 0.42, 0.22, 0.65), ell("chest", (0, 0, 0.95), (0.22, 0.18, 0.15))], "tunic", green, voxel=0.02)
    shade(cyl("belt", (0, 0, 0.42), 0.36, 0.36, 0.08), M("#2B2F3A"))
    for s in (1, -1):
        shade(tube("leg", [(s * 0.12, 0, 0.30), (s * 0.13, 0, 0.12), (s * 0.13, 0, 0.0)], [0.07, 0.06, 0.06]), M("#E9E3D6", warm=False))
        shade(tube("shoe", [(s * 0.13, 0.04, -0.02), (s * 0.15, -0.18, -0.02), (s * 0.15, -0.28, 0.08)], [0.07, 0.06, 0.03]), red)
        shade(tube("arm", [(s * 0.20, 0, 0.95), (s * 0.30, -0.20, 0.80), (s * 0.24, -0.38, 0.75)], [0.06, 0.055, 0.05]), green)
        shade(cyl("ear", (s * 0.24, 0, 1.25), 0.05, 0.0, 0.20, rot=(0, s * 70, 0)), skin)
    clay([ell("head", (0, 0, 1.22), (0.20, 0.19, 0.21)), ell("nose", (0, -0.19, 1.20), (0.045, 0.04, 0.045))], "head", skin, voxel=0.012)
    shade(tube("hat", [(0, 0, 1.36), (0.02, 0, 1.60), (0.18, 0, 1.78), (0.36, 0, 1.70)], [0.21, 0.14, 0.07, 0.02]), red)
    shade(cyl("brim", (0, 0, 1.37), 0.22, 0.22, 0.07), white); shade(ell("pom", (0.37, 0, 1.68), (0.06, 0.06, 0.06)), white)
    solid(common.box("box", (0, -0.52, 0.72), (0.65, 0.42, 0.34), bevel=0.02), M("#C9A26B"))
    for x, c in ((-0.18, "#D21F3C"), (0.0, "#2E86DE"), (0.18, "#E3B341")):
        shade(ell("orn", (x, -0.52, 0.95), (0.09, 0.09, 0.09)), M(c))
    tgt = proxy([((0, 0, 1.22), (0.20, 0.19, 0.21))], "px")
    for sx in (-0.07, 0.07):
        decal("eye", [(sx + 0.02 * math.cos(t), 1.26 + 0.025 * math.sin(t)) for t in [k * math.pi / 6 for k in range(12)]], 0, tgt, F("#2B2F3A"))
    decal("smile", [(-0.07, 1.14), (0.0, 1.10), (0.07, 1.14), (0.0, 1.12)], 0, tgt, F("#2B2F3A"))
    return dict(view=(-0.25, -1.0, 0.18))


run_subject(build, OUT)
