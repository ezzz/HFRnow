"""Christmas bauble with gold cap and hook."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_ornament.png")

def build():
    shade(ell("ball", (0, 0, 0), (0.6, 0.6, 0.6), seg=64), M("#D21F3C"))
    shade(cyl("cap", (0, 0, 0.62), 0.14, 0.14, 0.16), M("#E3B341"))
    shade(tube("hook", [(0, 0, 0.70), (0.08, 0, 0.86), (0, 0, 0.98), (-0.08, 0, 0.88)], [0.02] * 4), M("#B08A2E"))
    return dict(view=(-0.15, -1.0, 0.25))


run_subject(build, OUT)
