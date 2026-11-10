"""Full moon with soft craters."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "samain_moon.png")

def build():
    moon = shade(ell("moon", (0, 0, 0), (1, 1, 1), seg=96), M("#FFE9A8", warm=False))
    for x, z, r in ((-0.3, 0.35, 0.18), (0.25, -0.2, 0.26), (0.45, 0.4, 0.12), (-0.4, -0.35, 0.10)):
        decal("crater", [(x + r * math.cos(t), z + r * math.sin(t)) for t in [k * math.pi / 10 for k in range(20)]], 0, moon, M("#EBD38C", warm=False), offset=0.01)
    return dict(view=(0.0, -1.0, 0.0))


run_subject(build, OUT)
