"""Santa hat accessory (worn by the Noel redface icon)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "acc_santa_hat.png")

def build():
    shade(tube("hat", [(0, 0, 0), (0.05, 0, 0.55), (0.35, 0, 0.95), (0.80, 0, 0.85)], [0.62, 0.45, 0.20, 0.04], res=32), M("#C8283A"))
    clay([tube("fur", [(0.62 * math.cos(math.radians(d)), 0.62 * math.sin(math.radians(d)), 0.0) for d in range(0, 361, 20)], [0.14] * 19)], "fur", M("#F4F2EE", warm=False), voxel=0.02, smooth=4)
    clay([ell("pom", (0.84, 0, 0.80), (0.16, 0.16, 0.16))], "pom", M("#F4F2EE", warm=False), voxel=0.015)
    return dict(view=(-0.1, -1.0, 0.25))


run_subject(build, OUT)
