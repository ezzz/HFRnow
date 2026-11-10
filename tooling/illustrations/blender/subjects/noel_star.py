"""Gold star (tree top, crossing shooting star)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_star.png")

def build():
    s = poly_prism("star", star2d(5, 1.0, 0.45), 0.25, rot=(90, 0, 0))
    m = s.modifiers.new("b", "BEVEL"); m.width = 0.08; m.segments = 3
    solid(s, M("#E3B341"))
    return dict(view=(-0.2, -1.0, 0.15))


run_subject(build, OUT)
