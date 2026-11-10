"""Candy cane, red and white stripes."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_candy_cane.png")

def build():
    path = [(0, 0, 0.3 * i) for i in range(6)] + [(-0.30 + 0.30 * math.cos(math.radians(a)), 0, 1.5 + 0.30 * math.sin(math.radians(a))) for a in range(0, 181, 30)]
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        shade(tube("seg", [a, tuple((x + y) / 2 for x, y in zip(a, b)), b], [0.09] * 3, res=6), M("#D21F3C" if i % 2 else "#F4F2EE"))
    return dict(view=(0.0, -1.0, 0.1))


run_subject(build, OUT)
