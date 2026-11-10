"""Firework burst, blue / white / red / gold sparks (env COLS, SEED for variants)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "fete_fireworks.png")

def build():
    import random
    rnd = random.Random(int(os.environ.get("SEED", "3")))
    cols = os.environ.get("COLS", "#2B5CC8,#F4F2EE,#E5413B,#E3B341").split(",")
    for i in range(36):
        a = 2 * math.pi * i / 36 + rnd.uniform(-0.05, 0.05)
        r0, r1 = 0.25, rnd.uniform(1.2, 1.7)
        c = cols[i % len(cols)]
        shade(tube("streak", [(r0 * math.cos(a), 0, r0 * math.sin(a)), ((r0 + r1) / 2 * math.cos(a), 0, (r0 + r1) / 2 * math.sin(a) - 0.04), (r1 * math.cos(a), 0, r1 * math.sin(a) - 0.12)], [0.012, 0.03, 0.02], res=8), M(c, warm=False))
        shade(ell("spark", (r1 * 1.06 * math.cos(a), 0, r1 * 1.06 * math.sin(a) - 0.14), (0.05, 0.05, 0.05)), F(c))
    for i in range(14):
        a = rnd.uniform(0, 2 * math.pi); r = rnd.uniform(0.5, 1.1)
        shade(ell("dot", (r * math.cos(a), 0, r * math.sin(a)), (0.025, 0.025, 0.025)), F(cols[i % len(cols)]))
    return dict(view=(0.0, -1.0, 0.0))


run_subject(build, OUT)
