"""Spider web in a corner (quarter web), threads as thin tubes."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "samain_web.png")

def build():
    m = M("#D9D3DE", warm=False)
    spokes = [math.radians(a) for a in range(0, 91, 15)]
    for a in spokes:
        shade(tube("spoke", [(0, 0, 0), (1.0 * math.cos(a), 0, -1.0 * math.sin(a)), (2.0 * math.cos(a), 0, -2.0 * math.sin(a))], [0.014] * 3, res=6), m)
    for r in (0.45, 0.8, 1.15, 1.5, 1.85):
        pts = []
        for i, a in enumerate(spokes):
            pts.append((r * math.cos(a), 0, -r * math.sin(a)))
            if i < len(spokes) - 1:
                b = (a + spokes[i + 1]) / 2
                pts.append((r * 0.9 * math.cos(b), 0, -r * 0.9 * math.sin(b)))
        shade(tube("ring", pts, [0.012] * len(pts), res=8), m)
    return dict(view=(0.0, -1.0, 0.0))


run_subject(build, OUT)
