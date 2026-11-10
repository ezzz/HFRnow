"""Cherry tree in bloom: trunk, branches, dense blossom clouds, falling petals."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "year_cherry_tree.png")

def build():
    import random
    rnd = random.Random(5)
    branches = [[(0, 0, 0), (0.05, 0, 0.8), (-0.10, 0, 1.4)], [(-0.10, 0, 1.4), (-0.6, -0.1, 1.9), (-1.1, 0, 2.2)], [(-0.10, 0, 1.4), (0.5, 0.1, 2.0), (1.0, 0, 2.3)],
                [(0.05, 0, 0.9), (0.7, -0.1, 1.3), (1.3, 0, 1.4)], [(-0.10, 0, 1.4), (-0.05, 0, 2.1), (0.1, 0, 2.6)]]
    for i, b in enumerate(branches):
        shade(tube("br", b, [0.18, 0.12, 0.08] if i == 0 else [0.10, 0.07, 0.03]), M("#6B4630"))
    blob = []
    for c in ((-1.1, 0, 2.25), (1.0, 0, 2.35), (1.3, 0, 1.45), (0.1, 0, 2.65), (-0.5, 0, 2.0), (0.5, 0, 2.05), (-0.2, 0, 2.4), (0.8, 0, 1.75), (-0.8, 0, 1.7)):
        for _ in range(7):
            blob.append(ell("b", (c[0] + rnd.uniform(-0.35, 0.35), rnd.uniform(-0.3, 0.3), c[2] + rnd.uniform(-0.25, 0.25)), (0.28, 0.28, 0.24)))
    clay(blob, "bloom", M("#F4B6C8"), voxel=0.035, smooth=3)
    for _ in range(18):
        shade(ell("petal", (rnd.uniform(-1.6, 1.6), -0.6, rnd.uniform(0.0, 1.3)), (0.06, 0.02, 0.04), rot=(rnd.uniform(0, 90), rnd.uniform(0, 90), 0)), M("#F7C9D6"))
    return dict(view=(-0.1, -1.0, 0.12))


run_subject(build, OUT)
