#!/usr/bin/env python3
"""WCAG 2.x contrast check of every theme variant in tokens/themes.json."""
import json, sys
def lum(h):
    h = h.lstrip('#'); c = [int(h[i:i+2], 16)/255 for i in (0, 2, 4)]
    c = [x/12.92 if x <= 0.03928 else ((x+0.055)/1.055)**2.4 for x in c]
    return 0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2]
def cr(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True); return (la+0.05)/(lb+0.05)
PAIRS = [("title","background",4.5),("textPrimary","surface",4.5),("textSecondary","surface",4.5),
 ("sectionHeader","background",4.5),("accentText","surface",4.5),("link","surface",4.5),
 ("onAccent","accent",4.5),("onUnread","unread",4.5),("codeText","codeBackground",4.5),
 ("spoilerText","spoilerBackground",4.5),("textPrimary","quoteBackground",4.5)]
OPT = [("onHeaderBand","headerBand",4.5),("textPrimary","rowAlt",4.5),("link","rowAlt",4.5),("meta","surface",4.5),("meta","rowAlt",4.5),("onPageBar","pageBar",4.5),("counter","surface",4.5),("counter","rowAlt",4.5)]
d = json.load(open(sys.argv[1])); fails = 0
for t in d["themes"]:
    for v, tok in t["variants"].items():
        tok = dict(tok)
        for k, fb in d.get("optionalTokenKeys", {}).items():
            tok.setdefault(k, tok[fb])
        for fg, bg, req in PAIRS + [x for x in OPT if x[0] in tok]:
            r = cr(tok[fg], tok[bg]); ok = r >= req; fails += not ok
            if not ok or "-v" in sys.argv: print(f"{'ok ' if ok else 'KO '} {t['id']}/{v}: {fg} on {bg} = {r:.2f} (>= {req})")
import colorsys
for t in d["themes"]:
    am = t.get("accentModel")
    if not am: continue
    for pr in am["presets"] + [{"name": "slider", "hue": x / 100} for x in range(0, 101, 5)]:
        h = pr["hue"]
        def hx(s_, b_):
            r, g, b = colorsys.hsv_to_rgb(h, s_, b_); return "#%02X%02X%02X" % (round(r*255), round(g*255), round(b*255))
        lt = hx(am["light"]["saturation"], am["light"]["brightness"]); dk = hx(am["dark"]["saturation"], am["dark"]["brightness"])
        def derive(bg, s0, b0, step_s, step_b):
            s_, b_ = s0, b0
            while cr(hx(s_, b_), bg) < 4.6 and 0 <= s_ <= 1 and 0 <= b_ <= 1:
                s_ += step_s; b_ += step_b
            return hx(max(0, min(1, s_)), max(0, min(1, b_)))
        lt_text = derive("#FFFFFF", 0.9, 1.0, 0, -0.01)
        dk_text = derive("#1C1C1E", am["dark"]["saturation"], am["dark"]["brightness"], -0.01, 0)
        for lab, fg, bg in (("light fill+best of black/white", "#000000" if cr("#000000", lt) >= cr("#FFFFFF", lt) else "#FFFFFF", lt), ("dark fill+best of black/white", "#000000" if cr("#000000", dk) >= cr("#FFFFFF", dk) else "#FFFFFF", dk), ("light accentText on white", lt_text, "#FFFFFF"),
                            ("dark accentText on #1C1C1E", dk_text, "#1C1C1E"), ("raw light tint on white (legacy)", lt, "#FFFFFF"), ("raw dark tint on #1C1C1E (legacy)", dk, "#1C1C1E")):
            r = cr(fg, bg); ok = r >= 4.5
            if lab.startswith("raw"):
                if "-v" in sys.argv: print(f"info accent {pr['name']} {lab} = {r:.2f}")
                continue
            fails += not ok
            if not ok or "-v" in sys.argv: print(f"{'ok ' if ok else 'KO '} accent {pr['name']} h={h:.3f} {lab} = {r:.2f}")
print("fails:", fails)
