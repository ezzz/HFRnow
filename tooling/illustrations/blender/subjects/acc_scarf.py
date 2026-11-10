"""Winter scarf accessory (worn by the Winter redface icon)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "acc_scarf.png")

def build():
    red, white = M("#D21F3C"), M("#F4F2EE", warm=False)
    shade(tube("wrap", [(1.0 * math.cos(math.radians(d)), 0.55 * math.sin(math.radians(d)), 0.10 * math.cos(math.radians(d)) ** 2) for d in range(0, 361, 20)], [0.22] * 19, res=12), red)
    shade(tube("tail", [(0.40, -0.55, 0.0), (0.55, -0.62, -0.45), (0.62, -0.60, -0.95)], [0.18, 0.17, 0.16], res=12), red)
    for z in (-0.35, -0.65):
        shade(cyl("stripe", (0.56 + 0.07 * (z + 0.35) / -0.3, -0.62, z), 0.18, 0.18, 0.07), white)
    return dict(view=(0.0, -1.0, 0.45))


run_subject(build, OUT)
