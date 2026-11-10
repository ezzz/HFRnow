"""Snowflake."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_snowflake.png")

def build():
    m = M("#E9F2FB", warm=False)
    for k in range(6):
        a = math.radians(60 * k); c, s = math.cos(a), math.sin(a)
        shade(tube("arm", [(0, 0, 0), (0.5 * c, 0, 0.5 * s), (1.0 * c, 0, 1.0 * s)], [0.05, 0.045, 0.03], res=6), m)
        for d, l in ((0.45, 0.25), (0.72, 0.18)):
            for sg in (1, -1):
                b = a + sg * math.radians(45)
                shade(tube("br", [(d * c, 0, d * s), (d * c + l * math.cos(b) / 2, 0, d * s + l * math.sin(b) / 2), (d * c + l * math.cos(b), 0, d * s + l * math.sin(b))], [0.035, 0.03, 0.02], res=6), m)
    return dict(view=(0.0, -1.0, 0.0))


run_subject(build, OUT)
