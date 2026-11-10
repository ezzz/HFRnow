"""Three-branch candelabra with lit candles and wax drips."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "samain_candelabra.png")

def build():
    wax = M("#F3EAD6", warm=False)
    clay([cyl("foot", (0, 0, 0.06), 0.42, 0.28, 0.12), cyl("stem", (0, 0, 0.6), 0.06, 0.05, 1.0), ell("knob1", (0, 0, 0.35), (0.11, 0.11, 0.08)),
          ell("knob2", (0, 0, 0.85), (0.10, 0.10, 0.07)),
          tube("armL", [(0, 0, 1.0), (-0.40, 0, 1.0), (-0.62, 0, 1.25)], [0.045, 0.045, 0.045]),
          tube("armR", [(0, 0, 1.0), (0.40, 0, 1.0), (0.62, 0, 1.25)], [0.045, 0.045, 0.045]),
          cyl("cupC", (0, 0, 1.12), 0.12, 0.08, 0.10), cyl("cupL", (-0.62, 0, 1.30), 0.11, 0.07, 0.10), cyl("cupR", (0.62, 0, 1.30), 0.11, 0.07, 0.10)],
         "candelabra", M("#D9A441"), voxel=0.015, smooth=3)
    for x, z, h in ((0, 1.17, 0.55), (-0.62, 1.35, 0.42), (0.62, 1.35, 0.46)):
        shade(cyl("candle", (x, 0, z + h / 2), 0.065, 0.065, h), wax)
        shade(ell("drip", (x + 0.05, -0.04, z + h - 0.1), (0.025, 0.025, 0.08)), wax)
        shade(tube("flame", [(x, 0, z + h + 0.02), (x, 0, z + h + 0.12), (x + 0.02, 0, z + h + 0.28)], [0.05, 0.055, 0.005]), F("#FFB547"))
        shade(ell("core", (x, -0.03, z + h + 0.09), (0.022, 0.02, 0.05)), F("#FFF1B0"))
    return dict(view=(-0.2, -1.0, 0.2))


run_subject(build, OUT)
