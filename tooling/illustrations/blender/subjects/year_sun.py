"""Sun with rays."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "year_sun.png")

def build():
    shade(ell("sun", (0, 0, 0), (0.75, 0.75, 0.75), seg=64), M("#FFC83D", warm=False))
    for k in range(12):
        a = math.radians(30 * k)
        shade(cyl("ray", (1.15 * math.cos(a), 0, 1.15 * math.sin(a)), 0.11, 0.0, 0.42, rot=(0, 90 - math.degrees(a), 0)), M("#FFB21F", warm=False))
    return dict(view=(0.0, -1.0, 0.0))


run_subject(build, OUT)
