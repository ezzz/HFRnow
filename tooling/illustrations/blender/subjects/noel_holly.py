"""Holly: two spiky leaves and three berries."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_holly.png")

def build():
    leaf = [(0, 0), (0.25, 0.18), (0.40, 0.10), (0.55, 0.28), (0.70, 0.18), (0.88, 0.32), (1.05, 0.10), (0.88, -0.02), (0.70, -0.10),
            (0.55, -0.02), (0.40, -0.14), (0.25, -0.06)]
    for s in (1, -1):
        pts = [(s * x, z) for x, z in leaf]
        if s < 0:
            pts = list(reversed(pts))
        shade(poly_prism("leaf", pts, 0.04, rot=(90, 0, 0)), M("#2E7D4F"))
        ink_line("vein", [(s * 0.05, -0.05, 0.0), (s * 0.5, -0.05, 0.08), (s * 0.95, -0.05, 0.10)], 0.012)
    for p in ((0, -0.12, 0.10), (0.12, -0.10, 0.02), (-0.10, -0.10, 0.0)):
        shade(ell("berry", p, (0.09, 0.09, 0.09)), M("#D21F3C"))
    return dict(view=(0.0, -1.0, 0.25))


run_subject(build, OUT)
