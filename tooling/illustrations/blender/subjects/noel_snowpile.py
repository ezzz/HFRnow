"""Snow piled up (on cards, letters, the bottom of the screen)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_snowpile.png")

def build():
    parts = [ell("lump", (-2.0 + i * 0.5, 0, 0), (0.42 + 0.08 * (i % 3), 0.35, 0.36 + 0.10 * ((i + 1) % 2))) for i in range(9)]
    o = clay(parts, "snow", M("#F4F7FB", warm=False), voxel=0.03, smooth=6)
    boolean(o, common.box("cut", (0, 0, -0.5), (6, 2, 1.0), bevel=0))
    return dict(view=(0.0, -1.0, 0.35))


run_subject(build, OUT)
