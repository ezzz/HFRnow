"""Grey bat (Spooktober soft: textSecondary #A99AAD), wings spread, facing the viewer."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "samain_bat.png")

def build():
    wing = [(0.12, 0.10), (0.50, 0.40), (0.95, 0.50), (1.40, 0.32), (1.72, 0.02), (1.50, -0.06), (1.30, -0.30), (1.05, -0.12),
            (0.85, -0.36), (0.60, -0.14), (0.38, -0.32), (0.15, -0.12)]
    for side in (1, -1):
        pts = [(side * x, z) for x, z in wing]
        if side < 0:
            pts = list(reversed(pts))
        w = poly_prism("wing", pts, 0.04, loc=(0, 0.02, 0), rot=(90, 0, 0))
        shade(w, M("#A99AAD"))
        for tip in ((1.72, 0.02), (1.30, -0.30), (0.85, -0.36), (0.38, -0.32)):
            ink_line("bone", [(side * 0.15, -0.03, 0.12), (side * tip[0] * 0.55, -0.03, tip[1] * 0.5 + 0.14), (side * tip[0], -0.03, tip[1])], 0.012)
    clay([ell("b", (0, 0, -0.05), (0.20, 0.17, 0.34)), ell("h", (0, -0.02, 0.32), (0.17, 0.16, 0.15)),
          cyl("earL", (0.09, -0.01, 0.50), 0.06, 0.0, 0.18, rot=(0, 12, 0)), cyl("earR", (-0.09, -0.01, 0.50), 0.06, 0.0, 0.18, rot=(0, -12, 0)),
          ell("snout", (0, -0.15, 0.29), (0.07, 0.06, 0.05))], "bat", M("#A99AAD"), voxel=0.012, smooth=3)
    for sx in (0.06, -0.06):
        shade(ell("eye", (sx, -0.15, 0.36), (0.028, 0.02, 0.028)), F("#FFD23F"))
    return dict(view=(0.0, -1.0, 0.25))


run_subject(build, OUT)
