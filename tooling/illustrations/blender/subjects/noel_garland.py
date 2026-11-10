"""Garland of fir with coloured bulbs (hangs along the top of a screen)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_garland.png")

def build():
    sag = lambda x: -0.30 * (1 - ((x % 2) - 1) ** 2)
    pts = [(x, 0, sag(x)) for x in [i * 0.25 for i in range(25)]]
    shade(tube("wire", pts, [0.07] * len(pts), res=8), M("#2E7D4F"))
    cols = ["#D21F3C", "#E3B341", "#2E86DE", "#2E9E44"]
    for i, x in enumerate([0.5, 1.0, 1.5, 2.5, 3.0, 3.5, 4.5, 5.0, 5.5]):
        z = sag(x)
        shade(cyl("cap", (x, 0, z - 0.08), 0.05, 0.05, 0.08), M("#B08A2E"))
        shade(ell("bulb", (x, 0, z - 0.22), (0.08, 0.08, 0.13)), M(cols[i % 4]))
    return dict(view=(0.0, -1.0, 0.1))


run_subject(build, OUT)
