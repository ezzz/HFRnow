"""Small coconut palm."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "year_palm.png")

def build():
    shade(tube("trunk", [(0, 0, 0), (0.15, 0, 0.8), (0.10, 0, 1.6), (-0.10, 0, 2.3)], [0.16, 0.13, 0.11, 0.10], res=24), M("#A97B4F"))
    for i in range(9):
        shade(cyl("ring", (0.07 * math.sin(i * 0.6), 0, 0.2 + i * 0.24), 0.16 - i * 0.006, 0.17 - i * 0.006, 0.03), M("#7A5A3A"))
    for k in range(8):
        a = math.radians(k * 45 + 10); c, s = math.cos(a), math.sin(a)
        f = tube("frond", [(0, 0, 0), (0.6 * c, 0.6 * s, 0.25), (1.1 * c, 1.1 * s, 0.05), (1.4 * c, 1.4 * s, -0.35)], [0.05, 0.16, 0.13, 0.02], res=24)
        f.scale = (1, 1, 0.35); f.location = (-0.10, 0, 2.3)
        solid(f, M("#2E9E44"))
    for p in ((-0.02, -0.12, 2.15), (-0.18, -0.08, 2.18), (-0.08, 0.10, 2.12)):
        shade(ell("coco", p, (0.09, 0.09, 0.09)), M("#6B4630"))
    return dict(view=(-0.1, -1.0, 0.2))


run_subject(build, OUT)
