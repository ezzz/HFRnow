"""Lightning bolt (shown as 5 flashes of 0.3 s)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "samain_lightning.png")

def build():
    pts = [(0.30, 2.0), (-0.40, 0.75), (0.05, 0.75), (-0.35, -0.45), (0.65, 1.05), (0.15, 1.05), (0.75, 2.0)]
    shade(poly_prism("bolt", pts, 0.18, rot=(90, 0, 0)), M("#FFD23F", warm=False))
    return dict(view=(0.15, -1.0, 0.10))


run_subject(build, OUT)
