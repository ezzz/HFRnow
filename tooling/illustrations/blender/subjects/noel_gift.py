"""Gift box with ribbon and bow."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_gift.png")

def build():
    box, ribbon = os.environ.get("BOX", "#D21F3C"), os.environ.get("RIBBON", "#E3B341")
    solid(common.box("box", (0, 0, 0.45), (1.0, 1.0, 0.9), bevel=0.04), M(box))
    solid(common.box("lid", (0, 0, 0.95), (1.1, 1.1, 0.18), bevel=0.04), M(box))
    solid(common.box("r1", (0, 0, 0.55), (0.18, 1.12, 1.14), bevel=0.01), M(ribbon))
    solid(common.box("r2", (0, 0, 0.55), (1.12, 0.18, 1.14), bevel=0.01), M(ribbon))
    for s in (1, -1):
        shade(tube("loop", [(0, 0, 1.06), (s * 0.25, -0.05, 1.30), (s * 0.42, 0, 1.18), (s * 0.20, 0.02, 1.06)], [0.06, 0.08, 0.08, 0.06]), M(ribbon))
    shade(ell("knot", (0, 0, 1.08), (0.10, 0.10, 0.08)), M(ribbon))
    return dict(view=(-0.55, -1.0, 0.45))


run_subject(build, OUT)
