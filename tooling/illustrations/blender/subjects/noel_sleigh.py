"""Santa's sleigh PULLED by two reindeer harnessed in front, all facing the direction of travel (+X, to the right)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import *
import common
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "noel_sleigh.png")

def reindeer(x0, lead=False):
    clay([ell("torso", (x0, 0, 0.75), (0.55, 0.24, 0.26)), tube("neck", [(x0 + 0.40, 0, 0.85), (x0 + 0.55, 0, 1.10), (x0 + 0.62, 0, 1.25)], [0.16, 0.13, 0.11]),
          ell("head", (x0 + 0.72, 0, 1.30), (0.17, 0.12, 0.12)), ell("snout", (x0 + 0.86, 0, 1.25), (0.09, 0.08, 0.07)),
          tube("legFL", [(x0 + 0.35, -0.12, 0.65), (x0 + 0.62, -0.12, 0.40), (x0 + 0.75, -0.12, 0.18)], [0.07, 0.05, 0.04]),
          tube("legFR", [(x0 + 0.30, 0.12, 0.65), (x0 + 0.50, 0.12, 0.42), (x0 + 0.45, 0.12, 0.15)], [0.07, 0.05, 0.04]),
          tube("legBL", [(x0 - 0.35, -0.12, 0.65), (x0 - 0.55, -0.12, 0.40), (x0 - 0.80, -0.12, 0.30)], [0.08, 0.05, 0.04]),
          tube("legBR", [(x0 - 0.30, 0.12, 0.65), (x0 - 0.50, 0.12, 0.45), (x0 - 0.68, 0.12, 0.25)], [0.08, 0.05, 0.04]),
          ell("tail", (x0 - 0.56, 0, 0.88), (0.07, 0.05, 0.06)), ell("ear", (x0 + 0.62, 0, 1.42), (0.08, 0.03, 0.04))],
         "reindeer", M("#8A5A3B"), voxel=0.018, smooth=4)
    for s in (1, -1):
        shade(tube("antler", [(x0 + 0.66, s * 0.06, 1.40), (x0 + 0.60, s * 0.10, 1.62), (x0 + 0.48, s * 0.14, 1.78)], [0.025, 0.022, 0.015]), M("#C9A26B"))
        shade(tube("tine", [(x0 + 0.60, s * 0.10, 1.60), (x0 + 0.72, s * 0.14, 1.74)], [0.02, 0.012]), M("#C9A26B"))
    shade(ell("nose", (x0 + 0.95, 0, 1.25), (0.05, 0.05, 0.05)), M("#D21F3C" if lead else "#2B2F3A"))
    shade(tube("collar", [(x0 + 0.45 + 0.13 * math.cos(math.radians(d)), 0.19 * math.sin(math.radians(d)), 0.98) for d in range(0, 361, 30)], [0.035] * 13, res=8), M("#D21F3C"))


def build():
    red, gold, white = M("#B3263A"), M("#E3B341"), M("#F4F2EE", warm=False)
    prof = [(-1.9, 0.20), (-0.55, 0.20), (-0.35, 0.40), (-0.30, 0.75), (-0.75, 0.80), (-1.10, 0.70), (-1.75, 0.95), (-2.05, 1.20), (-2.05, 0.55)]
    sl = poly_prism("sleigh", prof, 0.9, loc=(0, 0.45, 0), rot=(90, 0, 0)); m = sl.modifiers.new("b", "BEVEL"); m.width = 0.04; m.segments = 2; solid(sl, red)
    for y in (-0.42, 0.42):
        shade(tube("runner", [(-2.0, y, 0.20), (-1.0, y, 0.0), (-0.3, y, 0.0), (0.05, y, 0.12), (0.05, y, 0.32), (-0.10, y, 0.38)], [0.035] * 6), gold)
        shade(tube("trim", [(-2.05, y * 1.04, 1.18), (-1.75, y * 1.04, 0.93), (-1.10, y * 1.04, 0.70), (-0.75, y * 1.04, 0.78), (-0.32, y * 1.04, 0.74)], [0.03] * 5), gold)
    clay([ell("sack", (-1.55, 0, 1.15), (0.35, 0.32, 0.40)), tube("neck", [(-1.55, 0, 1.45), (-1.62, 0, 1.62)], [0.10, 0.12])], "sack", M("#9A6A3A"), voxel=0.02)
    clay([ell("santa", (-0.95, 0, 1.05), (0.30, 0.28, 0.34)), tube("arm", [(-0.80, -0.22, 1.15), (-0.55, -0.26, 1.05), (-0.35, -0.24, 1.05)], [0.08, 0.07, 0.06])], "coat", M("#C8283A"), voxel=0.02)
    shade(cyl("belt", (-0.95, 0, 0.98), 0.31, 0.31, 0.08), M("#2B2F3A"))
    shade(ell("face", (-0.86, 0, 1.47), (0.15, 0.14, 0.15)), M("#EBC9A9"))
    shade(ell("beard", (-0.80, -0.02, 1.35), (0.15, 0.15, 0.17)), white)
    shade(tube("hat", [(-0.88, 0, 1.58), (-0.94, 0, 1.75), (-1.11, 0, 1.82), (-1.26, 0, 1.70)], [0.15, 0.11, 0.06, 0.02]), M("#C8283A"))
    shade(ell("pom", (-1.26, 0, 1.68), (0.06, 0.06, 0.06)), white)
    shade(cyl("fur", (-0.88, 0, 1.58), 0.16, 0.16, 0.06), white)
    reindeer(1.05, lead=False); reindeer(2.70, lead=True)
    for y in (-0.10, 0.10):
        shade(tube("rein", [(-0.35, y, 1.05), (0.60, y, 1.00), (1.50, y, 0.98), (2.30, y, 1.05), (3.15, y, 1.08)], [0.012] * 5, res=10), M("#5A3A28"))
    return dict(view=(0.05, -1.0, 0.16))


run_subject(build, OUT)
