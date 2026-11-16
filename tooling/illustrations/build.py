#!/usr/bin/env python3
"""Build the theme / icon mockup boards (HTML) from tokens/themes.json, src/art.py and
src/icons.py, then render them to JPEG with headless Chrome + sips (macOS).
Usage: python3 src/build.py [board-id ...]"""
import json, os, subprocess, sys, html
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art, icons, math
from png_art import img, silhouette_filter, png_defs, data_uri, size as png_size
from art import INK, place

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "boards")
SRC = os.path.join(OUT, "src")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
T = json.load(open(os.path.join(ROOT, "tokens", "themes.json")))
THEMES = {t["id"]: t for t in T["themes"]}
import colorsys
ACCM = THEMES["legacy"]["accentModel"]
CAT_SUB = dict(zip(["Hardware", "Hardware - Périphériques", "Ordinateurs portables", "Overclocking, Cooling & Modding", "Electronique, domotique, DIY", "Technologies Mobiles", "Apple", "Video & Son", "Photo numérique", "Jeux Video", "Windows & Software", "Réseaux grand public / SoHo"], [16, 9, 9, 7, 8, 11, 8, 5, 11, 8, 13, 9]))  # legacy counts: R01 links + « Tous les sujets » + hard-coded extras (ObjCForumsParser.m:84-499)
ICON_IX = {n: i for i, n in enumerate(["Hardware", "Hardware - Périphériques", "Ordinateurs portables", "Overclocking, Cooling & Modding", "Electronique, domotique, DIY", "Technologies Mobiles", "Apple", "Video & Son", "Photo numérique", "Jeux Video", "Windows & Software"])}


def hsbx(h, s_, b_):
    r, g, b = colorsys.hsv_to_rgb(h, s_, b_)
    return "#%02X%02X%02X" % (round(r * 255), round(g * 255), round(b * 255))


def _lum(x):
    x = x.lstrip("#"); c = [int(x[i:i+2], 16) / 255 for i in (0, 2, 4)]
    c = [v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def _cr(a, b):
    A, B = sorted((_lum(a), _lum(b)), reverse=True); return (A + 0.05) / (B + 0.05)


def legacy_accent(h, dark):
    """Legacy hue slider (Common.swift:514-519, AppSettingsView.swift:328-333) + derived accentText."""
    if dark:
        fill = hsbx(h, 0.70, 0.95); s_ = 0.70
        txt = fill
        while _cr(txt, "#1C1C1E") < 4.6 and s_ > 0:
            s_ -= 0.01; txt = hsbx(h, s_, 0.95)
    else:
        fill = hsbx(h, 0.65, 1.0); b_ = 1.0
        txt = hsbx(h, 0.9, b_)
        while _cr(txt, "#FFFFFF") < 4.6 and b_ > 0.2:
            b_ -= 0.01; txt = hsbx(h, 0.9, b_)
    on = "#000000" if _cr("#000000", fill) >= _cr("#FFFFFF", fill) else "#FFFFFF"
    return fill, txt, on


CAT_ICONS = {
    0: '<rect x="6" y="6" width="16" height="16" rx="2.5" fill="none" stroke="C" stroke-width="2"/><rect x="10" y="10" width="8" height="8" fill="C"/><path d="M10,2v4M14,2v4M18,2v4M10,22v4M14,22v4M18,22v4M2,10h4M2,14h4M2,18h4M22,10h4M22,14h4M22,18h4" stroke="C" stroke-width="1.6"/>',
    1: '<rect x="2" y="7" width="24" height="14" rx="2.5" fill="C"/><path d="M6,11h2M10,11h2M14,11h2M18,11h2M8,15h12" stroke="BG" stroke-width="1.8"/>',
    2: '<rect x="5" y="6" width="18" height="12" rx="1.5" fill="none" stroke="C" stroke-width="2"/><path d="M2,21h24" stroke="C" stroke-width="2.4" stroke-linecap="round"/>',
    3: '<path d="M18,4a6,6 0 0 0 -5,8l-9,9a2,2 0 0 0 3,3l9,-9a6,6 0 0 0 8,-5l-4,2l-3,-3z" fill="C"/>',
    4: '<rect x="3" y="3" width="22" height="22" rx="5" fill="C"/><circle cx="10" cy="10" r="2.4" fill="BG"/><circle cx="18" cy="18" r="2.4" fill="BG"/><path d="M10,10 L18,18" stroke="BG" stroke-width="1.6"/>',
    5: '<rect x="4" y="3" width="11" height="20" rx="2" fill="none" stroke="C" stroke-width="2"/><rect x="15" y="9" width="9" height="15" rx="2" fill="none" stroke="C" stroke-width="2"/>',
    6: '<circle cx="14" cy="14" r="9" fill="C"/><circle cx="14" cy="14" r="3.5" fill="BG"/>',
    7: '<rect x="2" y="8" width="16" height="13" rx="2.5" fill="C"/><path d="M19,12l7,-4v13l-7,-4z" fill="C"/>',
    8: '<path d="M3,9h5l2,-3h8l2,3h5v14h-22z" fill="C"/><circle cx="14" cy="15" r="4.5" fill="BG"/>',
    9: '<path d="M5,10h18a3,3 0 0 1 3,3l-1,8a3,3 0 0 1 -5,1l-2,-3h-8l-2,3a3,3 0 0 1 -5,-1l-1,-8a3,3 0 0 1 3,-3z" fill="C"/><path d="M8,13v5M5.5,15.5h5" stroke="BG" stroke-width="1.8"/><circle cx="19" cy="14" r="1.4" fill="BG"/><circle cx="21" cy="17" r="1.4" fill="BG"/>',
    10: '<rect x="3" y="4" width="22" height="20" rx="2" fill="none" stroke="C" stroke-width="2"/><path d="M3,9h22" stroke="C" stroke-width="2"/>',
}


def cat_icon(i, c, bg):
    body = CAT_ICONS.get(i, '<path d="M3,8h8l2,2h12v13h-22z" fill="C"/>').replace('"C"', f'"{c}"').replace('"BG"', f'"{bg}"')
    return f'<svg width="28" height="28" viewBox="0 0 28 28" style="flex:none">{body}</svg>'

CATS = ["Hardware", "Hardware - Périphériques", "Ordinateurs portables", "Overclocking, Cooling & Modding",
        "Electronique, domotique, DIY", "Technologies Mobiles", "Video & Son", "Photo numérique",
        "Jeux Video", "Windows & Software", "Réseaux grand public / SoHo"]
W, H = 393, 852
SYS = "-apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif"
FONTS = {"default": SYS, "rounded": "ui-rounded, 'SF Pro Rounded', -apple-system, sans-serif",
         "monospaced": "'SF Mono', Menlo, monospace"}


def esc(s):
    return html.escape(s)


def svg_layer(body, defs=""):
    return f'<svg class="layer" viewBox="0 0 {W} {H}" width="{W}" height="{H}"><defs>{defs}</defs>{body}</svg>'


def flag_icon(c):
    return f'<svg width="26" height="26" viewBox="0 0 26 26"><path d="M5,24 V3 M5,4 C10,1 14,7 21,4 V15 C14,18 10,12 5,15" fill="none" stroke="{c}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/></svg>'


def star_icon(c):
    return f'<svg width="26" height="26" viewBox="0 0 26 26"><polygon points="13,2.5 16.2,9.4 23.6,10.1 18,15 19.6,22.4 13,18.6 6.4,22.4 8,15 2.4,10.1 9.8,9.4" fill="none" stroke="{c}" stroke-width="1.8" stroke-linejoin="round"/></svg>'


def person_icon(c):
    return f'<svg width="30" height="30" viewBox="0 0 30 30"><circle cx="15" cy="15" r="13" fill="none" stroke="{c}" stroke-width="2"/><circle cx="15" cy="12" r="4.5" fill="none" stroke="{c}" stroke-width="2"/><path d="M7.5,24 q7.5,-9 15,0" fill="none" stroke="{c}" stroke-width="2"/></svg>'


def chevron(c, retro=False):
    if retro:
        return f'<span style="color:{c}">&gt;</span>'
    return f'<svg width="12" height="18" viewBox="0 0 12 18"><path d="M3,3 L9,9 L3,15" fill="none" stroke="{c}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>'


# ---------------- decorations (phone-space SVG) ----------------
def deco(kind, tok, variant, behind=True):
    """Return (behind_svg, front_svg, defs) for a decoration layer kind (Blender renders, src/blender/out)."""
    b, f, defs = "", "", ""
    if kind == "noel-full":
        defs = ('<pattern id="np" width="80" height="80" patternUnits="userSpaceOnUse">'
                + img("noel_snowflake", 6, 6, 20, opacity=0.35) + img("noel_star", 46, 44, 18, opacity=0.45) + '</pattern>')
        b = f'<rect width="{W}" height="{H}" fill="url(#np)"/>'
        b += (img("noel_tree", 262, 650, 125, opacity=0.55) + img("noel_gift", 18, 770, 62, opacity=0.55)
              + img("noel_gift_blue", 82, 784, 48, opacity=0.55) + img("noel_gift_gold", 200, 776, 54, opacity=0.55))
        f = img("noel_garland", -6, 34, 405)
        f += img("noel_ornament", 118, 92, 30) + img("noel_candy_cane", 160, 88, 22) + img("noel_star", 196, 94, 30)
        f += img("noel_holly", 300, 170, 70)
    elif kind == "noel-soft":
        import random
        rnd = random.Random(7)
        for _ in range(38):
            x, y, s_ = rnd.uniform(0, W), rnd.uniform(40, H), rnd.choice([8, 10, 12, 15])
            f += img("noel_snowflake", x, y, s_, rot=rnd.uniform(0, 60), opacity=0.95)
        f += img("noel_snowpile", 22, 136, 140) + img("noel_snowpile", 222, 140, 96)
        f += img("noel_snowpile", -20, H - 40, 440, h=52)
    elif kind == "samain-full":
        b = img("samain_moon", 220, 64, 140, opacity=0.95)
        b += img("samain_web", W - 120, 0, 120, opacity=0.6) + img("samain_web", W - 140, H - 140, 140, rot=90, opacity=0.5)
        b += img("samain_pumpkin", 8, 752, 78, opacity=0.6) + img("samain_pumpkin", 82, 774, 58, opacity=0.6) + img("samain_candelabra", 300, 720, 80, opacity=0.6)
        f = img("samain_bat", 244, 92, 80, rot=12) + img("samain_bat", 304, 132, 56, rot=-8) + img("samain_bat", 196, 140, 44)
    elif kind == "samain-soft":
        f = img("samain_web", W - 110, 0, 110, opacity=0.8)
        f += img("samain_candelabra", 100, 92, 46)
        f += img("samain_bat", 150, 104, 52, rot=10)
    elif kind == "retro-cursor":
        pass
    return b, f, defs


# ---------------- phone ----------------
def phone(theme_id, variant, accent=None, overlay="", label="", note="", screen=None):
    t = THEMES[theme_id]
    tok = dict(t["variants"][variant])
    for k, fb in T.get("optionalTokenKeys", {}).items():
        tok.setdefault(k, tok[fb])
    if accent is not None:
        fill, txt, on = legacy_accent(accent, variant == "dark")
        tok["accent"], tok["accentText"], tok["onAccent"], tok["link"] = fill, txt, on, txt
    if t.get("listStyle") == "ogTable" and not screen:
        screen = og_home
    retro = theme_id == "retro"
    font = FONTS[t.get("fontDesign", "default")]
    ext = t.get("extras", {})
    radius = 0 if retro else ext.get("cardRadius", 22)
    behind, front, defs = deco(t.get("decorations") or "", tok, variant)
    bg = tok["background"]
    halo = ""
    if theme_id == "swift":
        hs = ext[variant]["halos"]
        halo = (f'<div class="layer" style="background: radial-gradient(circle at 0% 0%, {hs[0]["color"]} 0, transparent {hs[0]["radius"]*0.75}px),'
                f' radial-gradient(circle at 100% 100%, {hs[1]["color"]} 0, transparent {hs[1]["radius"]*0.75}px)"></div>')
    card_style = f"background:{tok['surface']};border-radius:{radius}px;"
    if theme_id == "swift":
        sc = ext[variant]
        card_style += f"border:1px solid {sc['cardStroke']};" + (f"box-shadow:0 4px 14px {sc['cardShadow']['color']};" if sc["cardShadow"] else "")
    if retro:
        card_style += f"border:1px dashed {tok['separator']};"
    status_c = tok["title"]
    title = "HFR" + (f'<span class="cursor" style="background:{tok["textPrimary"]}"></span>' if retro else "")
    rows = ""
    if screen:
        content = screen(tok, font, radius, retro)
    else:
        sel = f"background:{tok['selection']};color:{tok['background']};" if retro else ""
        pill = f'<span class="pill" style="background:{tok["unread"]};color:{tok["onUnread"]}">12</span>'
        sep = f'<div class="sep" style="background:{tok["separator"]}"></div>' if not retro else f'<div class="sep" style="border-top:1px dashed {tok["separator"]}"></div>'
        c1 = tok["background"] if retro else tok["accentText"]
        card = (f'<div class="card" style="{card_style}">'
                f'<div class="row" style="{sel}">{flag_icon(c1)}<span style="color:{tok["background"] if retro else tok["textPrimary"]}">{"DRAPEAUX" if retro else "Drapeaux"}</span>{pill}</div>{sep}'
                f'<div class="row">{star_icon(tok["accentText"])}<span style="color:{tok["textPrimary"]}">{"FAVORIS" if retro else "Favoris"}</span></div></div>')
        for i, c in enumerate(CATS):
            name = c.upper() if retro else c
            pre = f'<span style="color:{tok["textSecondary"]}">{i+1:02d}. </span>' if retro else ""
            rows += (f'<div class="cat" style="color:{tok["sectionHeader"]}">{pre}<span>{esc(name)}</span>'
                     f'{chevron(tok["textPrimary"] if not retro else tok["accentText"], retro)}</div>')
        content = card + f'<div class="cats">{rows}</div>'
        if t.get("listStyle") == "legacyCards":
            ic = tok["textPrimary"]
            lrows = ""
            for i, c in enumerate(CATS[:10]):
                last = i == 9
                lrows += (f'<div style="display:flex;align-items:center;gap:14px;padding:0 16px;height:62px">{cat_icon(ICON_IX.get(c, 99), ic, tok["surface"])}'
                          f'<div style="flex:1;min-width:0;{"" if last else "border-bottom:1px solid " + tok["separator"] + ";"}height:62px;display:flex;align-items:center;justify-content:space-between">'
                          f'<div><div style="font-size:16px;color:{tok["textPrimary"]}">{esc(c)}</div><div style="font-size:13px;color:{tok["textSecondary"]}">{CAT_SUB[c]} sous-forums</div></div>'
                          f'{chevron(tok["textSecondary"])}</div></div>')
            content = card + f'<div class="card" style="{card_style};margin-top:18px">{lrows}</div>'
        if retro:
            content += f'<div class="fkeys" style="color:{tok["textPrimary"]};border-top:1px dashed {tok["separator"]}">F3=Quitter&nbsp; F5=Actualiser&nbsp; F12=Annuler</div>'
    nav = (f'<div class="status" style="color:{status_c}"><b>9:41</b><span class="sb">▮▮▮▮ ◠ ▭</span></div>'
           f'<div class="navtop">{person_icon(tok["accentText"] if not retro else tok["textPrimary"])}</div>'
           f'<div class="title" style="color:{tok["title"]}">{title}</div>') if not screen else \
          f'<div class="status" style="color:{status_c}"><b>9:41</b><span class="sb">▮▮▮▮ ◠ ▭</span></div>'
    return (f'<div class="pwrap"><div class="phone" style="background:{bg};font-family:{font}">{halo}'
            f'{svg_layer(behind, defs)}<div class="content">{nav}{content}</div>{svg_layer(front)}{overlay}'
            f'<div class="home" style="background:{tok["title"]}"></div></div>'
            f'<div class="plabel"><b>{esc(label)}</b><br><span>{note}</span></div></div>')


CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{background:#E7E5EA;font-family:-apple-system,'SF Pro Text',sans-serif;color:#1d1d1f;padding:36px 40px}
h1{font-size:30px;font-weight:700;letter-spacing:-.3px}
.sub{font-size:15px;color:#555;margin:6px 0 24px;max-width:1500px;line-height:1.4}
.grid{display:flex;flex-wrap:wrap;gap:34px;align-items:flex-start}
.pwrap{width:393px}
.phone{position:relative;width:393px;height:852px;border-radius:54px;overflow:hidden;box-shadow:0 0 0 9px #111,0 0 0 10px #444,0 20px 40px rgba(0,0,0,.25)}
.layer{position:absolute;inset:0;pointer-events:none}
.content{position:absolute;inset:0;padding:0 16px}
.status{display:flex;justify-content:space-between;padding:18px 26px 0 30px;font-size:16px}
.status .sb{font-size:11px;letter-spacing:1px}
.navtop{display:flex;justify-content:flex-end;padding:20px 6px 0}
.title{font-size:34px;font-weight:700;padding:12px 4px 10px;display:flex;align-items:center}
.cursor{display:inline-block;width:16px;height:30px;margin-left:6px}
.card{overflow:hidden}
.row{display:flex;align-items:center;gap:16px;padding:0 16px;height:52px;font-size:17px}
.row .pill{margin-left:auto;font-size:13px;font-weight:600;padding:2px 9px;border-radius:12px}
.sep{height:1px;margin-left:58px}
.cats{padding:6px 0}
.cat{display:flex;justify-content:space-between;align-items:center;height:51px;padding:0 20px 0 22px;font-size:17px;font-weight:600}
.cat span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:300px}
.fkeys{position:absolute;bottom:40px;left:16px;right:16px;font-size:12.5px;padding-top:8px}
.home{position:absolute;bottom:8px;left:50%;width:134px;height:5px;border-radius:3px;transform:translateX(-50%);opacity:.85}
.plabel{margin-top:22px;font-size:15px;line-height:1.35}
.plabel span{color:#555;font-size:13px}
.panel{background:#fff;border-radius:18px;padding:22px 24px;box-shadow:0 2px 10px rgba(0,0,0,.06);font-size:14px;line-height:1.45}
.panel h3{font-size:16px;margin-bottom:10px}
.sw{display:inline-flex;flex-direction:column;align-items:center;width:84px;margin:0 6px 12px 0;font-size:11.5px;text-align:center}
.sw i{display:block;width:44px;height:44px;border-radius:22px;margin-bottom:5px;border:1px solid rgba(0,0,0,.08)}
.tag{display:inline-block;font-size:12px;padding:2px 8px;border-radius:8px;background:#eee;margin-right:6px}
.scrim{position:absolute;inset:0}
.alert{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:290px;border-radius:26px;background:rgba(246,246,248,.96);text-align:center;box-shadow:0 10px 40px rgba(0,0,0,.3);overflow:hidden;color:#111}
.alert .t{font-weight:700;font-size:17px;padding:22px 18px 4px}
.alert .m{font-size:14px;padding:0 18px 18px;color:#333}
.alert .b{display:flex;gap:8px;padding:0 14px 14px}
.alert .b div{flex:1;border-radius:20px;padding:11px 0;font-size:16px;font-weight:600;background:rgba(0,0,0,.07)}
.capsule{position:absolute;left:50%;transform:translateX(-50%);padding:10px 20px;border-radius:24px;font-weight:700;font-size:19px;white-space:nowrap;box-shadow:0 6px 20px rgba(0,0,0,.25)}
.timer{position:absolute;top:58px;right:22px;font-size:11px;background:rgba(0,0,0,.55);color:#fff;padding:3px 8px;border-radius:10px}
"""


def page(title, sub, body, width):
    return (f'<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>{esc(title)}</title><style>{CSS}</style></head>'
            f'<body style="width:{width+80}px"><svg width="0" height="0" style="position:absolute"><defs>{png_defs(body)}</defs></svg>'
            f'<h1>{esc(title)}</h1><div class="sub">{sub}</div>{body}</body></html>')


# ---------------- boards ----------------
def b_swift():
    ex = THEMES["swift"]["extras"]
    panel = ('<div class="panel" style="width:430px"><h3>Langage « dashboard dégradé »</h3>'
             '<ul style="margin:8px 0 0 18px">'
             f'<li>Cartes opaques, rayon {ex["cardRadius"]}, contour 1 pt, ombre douce en clair seulement</li>'
             '<li>Deux halos radiaux diffus (violet en haut à gauche, rose en bas à droite)</li>'
             '<li>Accent indigo <code>#5B4BE0</code> (clair) / orchidée <code>#C26BF2</code> (sombre)</li>'
             '<li>Dégradé aurora réservé aux petites surfaces (pastille non-lu, aperçu du sélecteur, icônes X-face dégradé)</li>'
             '<li>Chiffres en arrondi léger, Dynamic Type partout</li></ul>'
             '<div style="display:flex;gap:10px;margin-top:14px"><div style="flex:1;height:34px;border-radius:17px;background:linear-gradient(90deg,#5B4BFF,#B45CF0,#D9437F)"></div>'
             '<div style="flex:1;height:34px;border-radius:17px;background:linear-gradient(90deg,#5B4BFF,#B45CF0,#F0649A)"></div></div>'
             '<p style="font-size:12px;color:#666;margin-top:4px">aurora clair · aurora sombre</p></div>')
    body = '<div class="grid">' + phone("swift", "light", label="Swift — clair") + phone("swift", "dark", label="Swift — sombre") + panel + '</div>'
    return page("Thème Swift ", "Fond bleu nuit, cartes douces, halos, accent violet.", body, 1340)


def b_retro():
    t = THEMES["retro"]["variants"]["any"]
    spec = ('<div class="panel" style="width:520px;background:#000;color:#33FF33;font-family:\'SF Mono\',Menlo,monospace">'
            '<h3 style="color:#fff">RÉTRO 5250 — TERMINAL À ÉCRAN VERT</h3>'
            '<p>VERT PHOSPHORE #33FF33 SUR NOIR · BLANC = EN-TÊTES · JAUNE #FFFF55 = NON-LU / CODE · TURQUOISE #40E0D0 = LIENS</p>'
            '<p style="margin-top:10px">SÉLECTION EN VIDÉO INVERSE · COINS CARRÉS · SÉPARATEURS EN TIRETS · POLICE MONOSPACE (SF MONO) À TOUTES LES TAILLES DYNAMIC TYPE</p>'
            '<p style="margin-top:10px">CURSEUR BLOC CLIGNOTANT APRÈS LE TITRE (FIXE SI « RÉDUIRE LES ANIMATIONS »)</p>'
            '<p style="margin-top:10px">IDENTIQUE EN CLAIR ET EN SOMBRE.</p>'
            '<p style="margin-top:14px;color:#1FB81F">===&gt; _</p></div>')
    body = '<div class="grid">' + phone("retro", "any", label="Rétro 5250 — unique", note="même rendu en clair et en sombre") + spec + '</div>'
    return page("Thème Rétro 5250 ", "Inspiré des terminaux à écran vert IBM 5250 : monospace vert sur noir.", body, 1040)


def crossing(kind, y, x, width, color, flip=False, label="objet qui traverse", angle=0):
    """A crossing object in silhouette (soft themes): enters by one edge, leaves by the opposite one, facing its direction of travel."""
    name = {"sleigh": "noel_sleigh", "witch": "samain_witch", "ghost": "samain_ghost", "bat": "samain_bat"}[kind]
    fid = "sil" + kind
    iw, ih = png_size(name); h = width * ih / iw
    ty = y + h / 2
    dy = math.tan(math.radians(angle)) * W
    trail = (f'<path d="M{x + (0 if flip else width):.0f},{ty:.0f} L{(W + 20) if flip else -20},{ty - dy if not flip else ty + dy:.0f}" '
             f'stroke="{color}" stroke-width="1.5" stroke-dasharray="3 8" opacity=".6"/>')
    return (f'<svg class="layer" viewBox="0 0 {W} {H}"><defs>{silhouette_filter(fid, color)}</defs>{trail}'
            f'{img(name, x, y, width, rot=angle, flip=flip, filt=fid)}</svg><div class="timer">{label}</div>')


def b_noel():
    soft_cross = crossing("sleigh", 330, 150, 210, THEMES["noel-soft"]["variants"]["light"]["textSecondary"], label="≤ 3 s · toutes les 20–90 min", angle=-12)
    body = '<div class="grid">' + phone("noel-abuse", "any", label="Noël abusé — unique", note="identique en clair et en sombre") \
        + phone("noel-soft", "light", label="Noël soft — clair", note="neige légère, neige amoncelée") \
        + phone("noel-soft", "dark", label="Noël soft — sombre") \
        + phone("noel-soft", "light", overlay=soft_cross, label="Noël soft — objet qui traverse", note="silhouette, 20–90 min, jamais moins de 20") + '</div>'
    return page("Thèmes Noël ", "Famille Noël, sélectionnable du 01/12 au 26/12. Noël soft activé par défaut le 01/12.", body, 1780)


def b_samain():
    cross = crossing("witch", 240, 70, 170, THEMES["spooktober-soft"]["variants"]["dark"]["textSecondary"], label="≤ 3 s · toutes les 20–90 min", angle=8)
    body = '<div class="grid">' + phone("spooktober-abuse", "any", label="Spooktober abusé — unique", note="orange / noir / violet") \
        + phone("spooktober-soft", "light", label="Spooktober soft — clair", note="toile, chandelier, petite chauve-souris") \
        + phone("spooktober-soft", "dark", label="Spooktober soft — sombre") \
        + phone("spooktober-soft", "dark", overlay=cross, label="Spooktober soft — objet qui traverse", note="éclair, fantôme ou sorcière, 20–90 min") + '</div>'
    return page("Thèmes Samain ", "Famille Samain, sélectionnable du 01/10 au 31/10. Spooktober soft activé par défaut le 01/10.", body, 1780)


def alert(title, msg, b1="OK", b2="Désactiver"):
    return (f'<div class="scrim" style="background:rgba(0,0,0,.28)"></div><div class="alert"><div class="t">{esc(title)}</div>'
            f'<div class="m">{esc(msg)}</div><div class="b"><div style="color:#0A66D8">{b1}</div><div style="color:#C62828">{b2}</div></div></div>')


def b_events():
    sleigh = (f'<svg class="layer" viewBox="0 0 {W} {H}">{img("noel_sleigh", -40, 300, 420)}'
              "</svg><div class=\"timer\">≤ 3 s · 1/4 de l'écran · haptique légère</div>")
    elves = (f'<div class="scrim" style="background:rgba(10,20,15,.35)"></div><svg class="layer" viewBox="0 0 {W} {H}">'
             + img("noel_garland", 150, 40, 250) + img("noel_elf", 10, 560, 120) + img("noel_elf", 140, 600, 112) + img("noel_elf", 262, 560, 116, flip=True)
             + img("noel_ornament", 120, 520, 26, rot=20) + '</svg>'
             '<div class="capsule" style="top:420px;background:#FFF8EC;color:#9E1530">Allez on remballe</div><div class="timer">≤ 5 s</div>')
    witchx = (f'<svg class="layer" viewBox="0 0 {W} {H}">{img("samain_witch", 110, 280, 280, rot=-6)}</svg><div class="timer">≤ 3 s · sorcière, fantôme ou vampire</div>')
    sweep = (f'<div class="scrim" style="background:rgba(20,10,31,.35)"></div><svg class="layer" viewBox="0 0 {W} {H}">'
             + img("samain_witch_sweep", 40, 520, 270) + img("samain_pumpkin", 280, 700, 70, rot=-30) + img("samain_web", 300, 630, 70, rot=20, opacity=0.8)
             + img("samain_bat", 300, 580, 60, rot=-20) + '</svg>'
             '<div class="capsule" style="top:420px;background:#FF7A00;color:#140A1F">Allez on remballe</div><div class="timer">≤ 5 s</div>')
    fete = (f'<div class="scrim" style="background:rgba(0,30,70,.62)"></div><svg class="layer" viewBox="0 0 {W} {H}">'
            + img("fete_fireworks", 10, 150, 150) + img("fete_fireworks_gold", 250, 120, 130) + img("fete_fireworks_red", 270, 300, 120)
            + img("fete_fireworks", 0, 360, 100) + img("marianne-1600", 46, 250, 300) + '</svg>'
            '<div class="capsule" style="top:590px;background:#fff;color:#0055A4">Fête <span style="color:#EF4135">nationale</span></div><div class="timer">3–5 s</div>')
    body = '<div class="grid">' \
        + phone("legacy", "light", 0.528, overlay=sleigh, label="Noël 1 · premier lancement 01/12–26/12", note="le traîneau, tiré par les rennes, traverse l'écran ; activation auto de Noël soft seulement 01/12–24/12") \
        + phone("noel-soft", "light", overlay=alert("Oh Oh Oh !", "Thème disponible dans les réglages"), label="Noël 2 · popup", note="Noël soft déjà actif ; Désactiver = retour au thème précédent pour l'année") \
        + phone("noel-soft", "light", overlay=elves, label="Noël 3 · premier lancement 27/12–02/01", note="si un thème Noël était actif ; plus tard : retour silencieux au thème précédent") \
        + phone("legacy", "dark", 0.528, overlay=witchx, label="Samain 1 · premier lancement 01/10–31/10", note="sorcière, fantôme ou vampire (tirage)") \
        + phone("spooktober-soft", "dark", overlay=alert("Spooktober est là !", "Thème disponible dans les réglages"), label="Samain 2 · popup") \
        + phone("spooktober-soft", "dark", overlay=sweep, label="Samain 3 · premier lancement 01/11–07/11", note="la sorcière balaie les décorations ; plus tard : retour silencieux") \
        + phone("legacy", "light", 0.528, overlay=fete, label="14 juillet · premier lancement du jour", note="buste de Marianne façon statue, feux d'artifice, 3–5 s ; soumis à « Animations de saison »") \
        + '</div>'
    return page("Événements saisonniers (overlays)", "Overlays ≤ 5 s, touchables pour fermer, jamais sur une saisie, muets pour VoiceOver ; remplacés par un simple fondu ou supprimés avec « Réduire les animations ». Désactivables via Réglages › Thème › Animations de saison.", body, 1780)


def swatch(theme_id, variant, w=46, h=64):
    tok = THEMES[theme_id]["variants"][variant]
    return (f'<div style="width:{w}px;height:{h}px;border-radius:9px;background:{tok["background"]};border:1px solid rgba(0,0,0,.15);padding:6px 5px;flex:none">'
            f'<div style="height:5px;width:20px;border-radius:2px;background:{tok["title"]};margin-bottom:5px"></div>'
            f'<div style="height:18px;border-radius:4px;background:{tok["surface"]};padding:4px"><div style="width:7px;height:7px;border-radius:4px;background:{tok["accent"]}"></div></div>'
            f'<div style="height:3px;width:28px;background:{tok["sectionHeader"]};margin-top:6px;border-radius:2px"></div>'
            f'<div style="height:3px;width:22px;background:{tok["sectionHeader"]};margin-top:5px;border-radius:2px"></div></div>')


def settings_screen_theme(tok, font, radius, retro):
    def sec(title, rows, foot=""):
        return (f'<div style="font-size:13px;color:{tok["sectionHeader"]};padding:16px 16px 6px;text-transform:uppercase">{title}</div>'
                f'<div class="card" style="background:{tok["surface"]};border-radius:{radius}px">{rows}</div>'
                + (f'<div style="font-size:12.5px;color:{tok["textSecondary"]};padding:6px 16px 0;line-height:1.35">{foot}</div>' if foot else ""))
    def trow(tid, sel=False, last=False):
        t = THEMES[tid]
        v = "light" if "light" in t["variants"] else "any"
        both = "" if "light" in t["variants"] else ' · <i>clair = sombre</i>'
        pair = swatch(tid, v) + (swatch(tid, "dark") if "dark" in t["variants"] else "")
        check = f'<span style="margin-left:auto;color:{tok["accentText"]};font-size:20px;font-weight:600">✓</span>' if sel else ""
        sep = "" if last else f'<div style="height:1px;background:{tok["separator"]};margin-left:124px"></div>'
        return (f'<div style="display:flex;align-items:center;gap:8px;padding:9px 16px">{pair}<div style="margin-left:8px">'
                f'<div style="font-size:16px;color:{tok["textPrimary"]}">{esc(t["name"])}</div><div style="font-size:12.5px;color:{tok["textSecondary"]}">{("par " + esc(t["author"]) + both) if t.get("author") else both.removeprefix(" · ")}</div></div>{check}</div>{sep}')
    seg = (f'<div style="display:flex;margin:10px 12px;background:{tok["background"]};border-radius:9px;padding:2px">'
           + "".join(f'<div style="flex:1;text-align:center;padding:6px 0;font-size:14px;border-radius:7px;{("background:" + ("#fff" if tok["background"] > "#8" else "#5A5B60") + ";box-shadow:0 1px 3px rgba(0,0,0,.15);font-weight:600") if i == 0 else ""};color:{tok["textPrimary"]}">{n}</div>' for i, n in enumerate(["Système", "Clair", "Sombre"])) + '</div>')
    accents = hue_slider(0.528, tok, 250)
    tog = f'<span style="margin-left:auto;width:51px;height:31px;border-radius:16px;background:#34C759;position:relative"><span style="position:absolute;right:2px;top:2px;width:27px;height:27px;border-radius:14px;background:#fff"></span></span>'
    body = (f'<div style="display:flex;align-items:center;padding:14px 4px 0;color:{tok["accentText"]};font-size:17px">‹ Réglages</div>'
            f'<div class="title" style="color:{tok["title"]};padding-top:4px">Thème</div>'
            + sec("Apparence", seg, "Réglage général. Par défaut : Système (recommandé par Apple). Certains thèmes sont identiques en clair et en sombre.")
            + sec("Classiques", trow("legacy", True) + f'<div style="padding:4px 14px 10px 26px">{accents}</div><div style="height:1px;background:{tok["separator"]};margin-left:124px"></div>' + trow("swift", last=True))
            + sec("Rétro", trow("retro", last=True))
            + sec("Samain · jusqu'au 31 octobre", trow("spooktober-abuse") + trow("spooktober-soft", last=True))
            + sec("Animations", f'<div class="row" style="color:{tok["textPrimary"]}">Animations de saison{tog}</div>',
                  "Neige, objets qui traversent l'écran, surprises (Noël, Samain, 14 juillet). Coupées si « Réduire les animations » est actif.")
            + f'<div style="font-size:12.5px;color:{tok["textSecondary"]};padding:14px 16px;line-height:1.35">Envie de proposer un thème ? Les règles sont dans le dépôt : <span style="color:{tok["link"]}">docs/THEMES.md</span> (voir le README).</div>')
    return f'<div style="height:{H-60}px;overflow:hidden">{body}</div>'


def icon_html(svgstr, size, shadow=True):
    return (f'<div style="width:{size}px;height:{size}px;border-radius:{size*0.2237:.1f}px;overflow:hidden;flex:none;'
            f'{"box-shadow:0 1px 3px rgba(0,0,0,.25);" if shadow else ""}">{svgstr}</div>')


def settings_screen_icon(tok, font, radius, retro):
    out = (f'<div style="display:flex;align-items:center;padding:14px 4px 0;color:{tok["accentText"]};font-size:17px">‹ Réglages</div>'
           f'<div class="title" style="color:{tok["title"]};padding-top:4px">Icône de l\'app</div>')
    n = 0
    for pack_id, pack_name, items in icons.PACKS:
        cells = ""
        for (iid, name, src, fn, win) in items:
            if win and win[0] == "12-01":
                continue
            n += 1
            sel = iid == "legacy-blue"
            ring = f'box-shadow:0 0 0 2px {tok["surface"]},0 0 0 4.5px {tok["accentText"]};border-radius:13px;' if sel else ""
            cells += (f'<div style="width:72px;text-align:center;font-size:10.5px;color:{tok["textPrimary"]};margin-bottom:8px">'
                      f'<div style="display:inline-block;{ring}">{icon_html(fn("s" + iid.replace("-", "") + "x"), 56)}</div><div style="margin-top:4px;line-height:1.15">{esc(name)}</div></div>')
        foot = "Noël : du 1er au 26 décembre." if pack_id == "season" else ""
        out += (f'<div style="font-size:13px;color:{tok["sectionHeader"]};padding:14px 16px 6px;text-transform:uppercase">{pack_name}</div>'
                f'<div class="card" style="background:{tok["surface"]};border-radius:{radius}px;padding:12px 6px 4px;display:flex;flex-wrap:wrap">{cells}</div>'
                + (f'<div style="font-size:12.5px;color:{tok["textSecondary"]};padding:6px 16px 0">{foot}</div>' if foot else ""))
    return f'<div style="height:{H-60}px;overflow:hidden">{out}</div>'


def b_selector():
    body = '<div class="grid">' \
        + phone("legacy", "light", 0.528, screen=settings_screen_theme, label="Réglages › Thème", note="familles, aperçu clair/sombre, auteur, accent si Legacy ; état au 28/10 (Samain visible, Noël caché)") \
        + phone("legacy", "dark", 0.528, screen=settings_screen_theme, label="Réglages › Thème — sombre") \
        + phone("legacy", "light", 0.528, screen=settings_screen_icon, label="Réglages › Icône de l'app", note="grille par pack ; saisonnières datées visibles seulement dans leur fenêtre") \
        + '</div>'
    return page("Sélecteurs de thème et d'icône", "Pages dédiées ouvertes depuis Réglages. Clair/Sombre/Système est un réglage général, séparé du thème.", body, 1360)


def b_charter():
    lib = [("noel_tree", "sapin"), ("noel_gift", "cadeau"), ("noel_ornament", "boule"), ("noel_candy_cane", "sucre d'orge"), ("noel_snowman", "bonhomme de neige"),
           ("noel_holly", "houx"), ("noel_star", "étoile"), ("noel_snowflake", "flocon"), ("noel_elf", "lutin"), ("acc_santa_hat", "bonnet"),
           ("samain_pumpkin", "citrouille"), ("samain_bat", "chauve-souris (grise)"), ("samain_ghost", "fantôme"), ("samain_vampire", "vampire"),
           ("samain_witch", "sorcière sur balai"), ("samain_witch_sweep", "sorcière qui balaie"), ("samain_web", "toile"), ("samain_candelabra", "chandelier"),
           ("samain_lightning", "éclair"), ("samain_moon", "lune"), ("fete_fireworks", "feu d'artifice"), ("year_cherry_tree", "cerisier"), ("year_palm", "cocotier"),
           ("year_sun", "soleil"), ("acc_scarf", "écharpe"), ("noel_garland", "guirlande"), ("noel_snowpile", "neige amoncelée")]
    cells = "".join(f'<div style="width:190px;text-align:center;font-size:12.5px"><div style="background:#F8F5F0;border-radius:14px;height:170px;display:flex;align-items:center;justify-content:center">'
                    f'<svg viewBox="0 0 170 160" width="170" height="160">{_fit(n, 170, 160)}</svg></div><code>{n}</code><br>{esc(t)}</div>' for n, t in lib)
    big = (f'<div style="width:560px;text-align:center;font-size:12.5px"><div style="background:#F8F5F0;border-radius:14px;height:250px;display:flex;align-items:center;justify-content:center">'
           f'<svg viewBox="0 0 540 240" width="540" height="240">{_fit("noel_sleigh", 540, 240)}</svg></div><code>noel_sleigh</code> — tiré par les rennes, sens de la marche →</div>'
           f'<div style="width:300px;text-align:center;font-size:12.5px"><div style="background:#F8F5F0;border-radius:14px;height:250px;display:flex;align-items:center;justify-content:center">'
           f'<svg viewBox="0 0 280 240" width="280" height="240">{_fit("marianne-1600", 280, 240)}</svg></div><code>marianne</code></div>')
    sil = (f'<svg viewBox="0 0 520 120" width="520" height="120"><defs>{silhouette_filter("cs", "#56627A")}</defs>'
           + img("samain_witch", 0, 10, 170, filt="cs") + img("samain_ghost", 190, 0, 90, filt="cs") + img("samain_lightning", 300, 0, 60, filt="cs")
           + img("noel_sleigh", 370, 40, 150, filt="cs") + '</svg>')
    rules = ('<div class="panel" style="width:600px"><h3>Charte « croquis numérique » (pipeline Blender)</h3><ol style="margin-left:18px">'
             '<li><b>Volumes</b> modélisés par script (<code>src/blender/subjects/&lt;sujet&gt;.py</code>) à partir de primitives douces fusionnées (remaillage voxel) ; aucun asset externe.</li>'
             '<li><b>Ombrage cel</b> 3–4 tons plats, sans dégradé : ombre gris-bleu froide, terminateur pêche chaud, lumière = couleur de base ; lumière en haut à gauche.</li>'
             '<li><b>Encre</b> Freestyle <code>#2B2F3A</code> : contour extérieur épais (côté/170), contours intérieurs fins (côté/520), effilés ; traits courts filtrés ; détails dessinés à l\'encre sur la surface (paupières, nervures, mèches).</li>'
             '<li><b>Sens de déplacement</b> : tout objet qui traverse regarde vers où il va ; le traîneau est tiré par les rennes attelés devant.</li>'
             '<li><b>Thèmes soft</b> : objets qui traversent en silhouette <code>textSecondary</code> ; décor sur fond sombre ≥ 3:1.</li>'
             '<li><b>Originaux</b> seulement : pas de personnage protégé ni de logo.</li></ol></div>')
    body = (f'<div style="display:flex;gap:30px;align-items:flex-start;margin-bottom:26px">{rules}<div class="panel" style="width:560px"><h3>Silhouettes (thèmes soft)</h3>{sil}</div></div>'
            f'<div class="grid" style="gap:16px">{big}{cells}</div>')
    return page("Charte des illustrations — croquis numérique", "Toutes les illustrations rendues par le pipeline Blender (Freestyle + cel-shading), validé par l\'opérateur le 28/10.", body, 1780)


def _fit(name, bw, bh):
    iw, ih = png_size(name)
    k = min(bw / iw, bh / ih) * 0.92
    w, h = iw * k, ih * k
    return img(name, (bw - w) / 2, (bh - h) / 2, w)


def b_icons(pack_id):
    pack = [p for p in icons.PACKS if p[0] == pack_id][0]
    _, pack_name, items = pack
    large = "".join(f'<div style="width:250px;font-size:13px"><div style="display:flex;justify-content:center;background:#fff;border-radius:18px;padding:16px">'
                    f'{icon_html(fn("L" + iid.replace("-", "")), 200)}</div><div style="margin-top:8px"><b>{esc(name)}</b> · <code>{iid}</code><br>'
                    f'<span style="color:#555">{esc(src)}</span></div></div>' for (iid, name, src, fn, win) in items)
    def strip(bg, fg):
        cells = "".join(f'<div style="width:86px;text-align:center;color:{fg};font-size:11.5px">{icon_html(fn("h" + iid.replace("-", "") + bg[1:4]), 62, False)}'
                        f'<div style="margin-top:5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{esc(name)}</div></div>' for (iid, name, src, fn, win) in items)
        return f'<div style="background:{bg};border-radius:24px;padding:22px;display:flex;flex-wrap:wrap;gap:14px 10px;width:860px">{cells}</div>'
    homes = ('<div style="display:flex;gap:26px;margin-top:30px">'
             + strip("linear-gradient(160deg,#F4EEE6,#D9E4F2)", "#1d1d1f").replace("background:linear", "background:linear")
             + strip("linear-gradient(160deg,#1B1F2E,#0B0C10)", "#ffffff") + '</div>'
             '<p style="font-size:13px;color:#555;margin-top:10px">Écran d\'accueil clair et sombre, icônes à 62 px (≈ taille réelle iPhone). Les variantes dark / clear / tinted iOS 27 sont produites dans Icon Composer par le lot de génération (ICONS.md §1).</p>')
    body = f'<div class="grid" style="gap:22px">{large}</div>{homes}'
    sub = {"legacy": "Icônes de l'app legacy (PNG d'<code>origin/master</code>) + la nouvelle « Orange » (HFR blanc sur <code>orange-hfr</code> #F18F18, forum_logo.gif).",
           "beta": "Icône bêta legacy et sa version redessinée : traits noirs sur rouge, traits légèrement plus épais.",
           "xface": "Variations du smiley :o (redface) noir sur rouge.",
           "season": "Pack saisons : Noël (01/12–26/12) et Halloween (01/10–31/10) datés ; printemps, été, hiver toute l'année."}[pack_id]
    return page(f"Icônes — pack {pack_name}", sub, body, 1800)


def hue_slider(h, tok, width=300, presets=True):
    """Legacy continuous hue slider (0-1) with the 10 proposed presets as tick marks."""
    stops = ",".join(hsbx(x / 12, 0.65, 1.0) for x in range(13))
    ticks = ""
    if presets:
        for pr in ACCM["presets"]:
            ticks += (f'<span title="{esc(pr["name"])}" style="position:absolute;left:{pr["hue"]*width-5:.0f}px;top:20px;width:10px;height:10px;border-radius:5px;'
                      f'background:{hsbx(pr["hue"], 0.65, 1.0)};border:1px solid rgba(0,0,0,.25)"></span>')
    knob = f'<span style="position:absolute;left:{h*width-14:.0f}px;top:-7px;width:28px;height:20px;border-radius:10px;background:#fff;box-shadow:0 1px 4px rgba(0,0,0,.35)"></span>'
    return (f'<div style="position:relative;width:{width}px;height:34px;margin-top:8px"><div style="height:6px;border-radius:3px;background:linear-gradient(90deg,{stops})"></div>'
            f'{knob}{ticks}</div>')


def legacy_settings(h):
    def scr(tok, font, radius, retro):
        fill, txt, on = legacy_accent(h, tok["background"] == "#000000")
        blue = "#0A84FF" if tok["background"] == "#000000" else "#007AFF"
        def row(lbl, val, last=False):
            return (f'<div style="display:flex;justify-content:space-between;padding:14px 16px;{"" if last else "border-bottom:1px solid " + tok["separator"]};font-size:16px;color:{tok["textPrimary"]}">'
                    f'<span>{lbl}</span><span style="color:{blue}">{val} ⌃</span></div>')
        def tog(lbl, last=False):
            return (f'<div style="display:flex;justify-content:space-between;align-items:center;padding:10px 16px;{"" if last else "border-bottom:1px solid " + tok["separator"]};font-size:16px;color:{tok["textPrimary"]}">'
                    f'<span>{lbl}</span><span style="width:58px;height:28px;border-radius:14px;background:{fill};position:relative"><span style="position:absolute;right:2px;top:2px;width:34px;height:24px;border-radius:12px;background:#fff"></span></span></div>')
        hdr = lambda x: f'<div style="font-size:15px;font-weight:600;color:{tok["sectionHeader"]};padding:18px 16px 8px">{x}</div>'
        card = lambda x: f'<div style="background:{tok["surface"]};border-radius:22px;overflow:hidden">{x}</div>'
        body = (f'<div style="text-align:center;font-weight:600;font-size:17px;color:{tok["textPrimary"]};padding:16px 0 6px">Réglages</div>'
                + card(tog("Retours haptiques") + tog("Rotation d'écran") + row("Icône", "Défaut", True))
                + hdr("Thème")
                + card(row("Changement de thème", "Manuel") + row("Luminosité du thème", "Sombre" if tok["background"] == "#000000" else "Clair")
                       + f'<div style="padding:12px 16px;color:{tok["textPrimary"]};font-size:16px"><div style="display:flex;justify-content:space-between"><span>Teinte d\'accent</span>'
                         f'<span style="color:{tok["textSecondary"]}">{h:.2f}'.replace(".", ",") + '</span></div>{hue_slider(h, tok, 330)}</div>')
                + f'<div style="font-size:12.5px;color:{tok["textSecondary"]};padding:8px 16px;line-height:1.35">Pastilles = 10 teintes prédéfinies proposées (clic = raccourci) ; le curseur reste continu (parité legacy).</div>'
                + hdr("Sujets") + card(row("Style des messages", "Moderne") + tog("Swipe changement de page", True)))
        return f'<div style="height:{H-60}px;overflow:hidden">{body}</div>'
    return scr


def og_band(tok, left, right=""):
    return (f'<div style="background:{tok["headerBand"]};color:{tok["onHeaderBand"]};display:flex;align-items:center;justify-content:space-between;'
            f'padding:10px 14px;font-weight:700;font-size:15px;border-bottom:1px solid {tok["separator"]}">{left}<span>{right}</span></div>')


def og_wordmark(tok):
    return (f'<div style="background:{tok["headerBand"]};padding:12px 16px 10px;display:flex;align-items:center;justify-content:space-between">'
            f'<div style="display:flex;align-items:center;gap:8px"><span style="width:22px;height:22px;background:{tok["accent"]};display:inline-block;transform:skewX(-12deg)"></span>'
            f'<span style="font:900 26px/1 \'Avenir Next\',Helvetica,sans-serif;color:#fff;letter-spacing:-.5px">HFR<span style="color:{tok["accent"]}">.</span></span></div>'
            f'{person_icon("#FFFFFF")}</div>'
            f'<div style="background:{tok["headerBand"]};border-top:1px solid rgba(255,255,255,.18);color:#fff;font-weight:700;font-size:14px;padding:6px 16px 8px">Forum&nbsp; | &nbsp;Drapeaux&nbsp; | &nbsp;Favoris&nbsp; | &nbsp;Messages</div>')


def bulb(c="#F4D03F"):
    return (f'<svg width="16" height="20" viewBox="0 0 16 20"><circle cx="8" cy="7" r="6" fill="{c}" stroke="#7A6A00" stroke-width="1"/>'
            f'<rect x="5" y="13" width="6" height="4" rx="1" fill="#B0B0B0" stroke="#666" stroke-width=".8"/></svg>')


def og_cell(tok, inner, alt=False, w=None, extra=""):
    st = f"background:{tok['rowAlt'] if alt else tok['surface']};border-right:1px solid {tok['separator']};padding:8px 8px;"
    st += f"width:{w}px;flex:none;" if w else "flex:1;min-width:0;"
    return f'<div style="{st}{extra}">{inner}</div>'


def og_home(tok, font, radius, retro):
    rows = ""
    for i, c in enumerate(CATS[:10]):
        rows += (f'<div style="display:flex;border-bottom:1px solid {tok["separator"]};">'
                 + og_cell(tok, bulb(), True, 30, "display:flex;align-items:center;justify-content:center;padding:0")
                 + og_cell(tok, f'<div style="font-weight:700;font-size:16px;color:{tok["link"]}">{esc(c)}</div>'
                                f'<div style="font-size:12px;font-weight:700;color:{tok["meta"]}">{CAT_SUB[c]} sous-forums</div>')
                 + og_cell(tok, f'<div style="font-size:11px;font-weight:700;color:{tok.get("counter", tok["textPrimary"])};text-align:center">›</div>', True, 30,
                           "display:flex;align-items:center;justify-content:center") + '</div>')
    mine = (f'<div style="display:flex;border-bottom:1px solid {tok["separator"]};border-left:1px solid {tok["separator"]}">'
            + og_cell(tok, flag_icon("#CC0000").replace('width="26" height="26"', 'width="18" height="18"'), True, 30, "display:flex;align-items:center;justify-content:center;padding:0")
            + og_cell(tok, f'<span style="font-weight:700;color:{tok["link"]}">Drapeaux</span>')
            + og_cell(tok, f'<span style="display:inline-block;background:{tok["unread"]};color:{tok["onUnread"]};font-size:11px;font-weight:700;padding:1px 6px">12</span>', True, 48, "text-align:center") + '</div>'
            + f'<div style="display:flex;border-bottom:1px solid {tok["separator"]};border-left:1px solid {tok["separator"]}">'
            + og_cell(tok, star_icon("#C9A400").replace('width="26" height="26"', 'width="18" height="18"'), True, 30, "display:flex;align-items:center;justify-content:center;padding:0")
            + og_cell(tok, f'<span style="font-weight:700;color:{tok["link"]}">Favoris</span>') + og_cell(tok, "", True, 48) + '</div>')
    body = og_wordmark(tok) + '<div style="height:10px"></div>' + og_band(tok, "Mes sujets") + mine + '<div style="height:10px"></div>' + og_band(tok, "Catégories", "Sous-forums") + rows
    return f'<div style="height:{H-60}px;overflow:hidden;margin:0 -16px">{body}</div>'


R04_TOPICS = [  # anonymized capture R04 (Discussions, page 1)
    ("Message important : user9 nous a quittés", 84, "user3", 3350, "24-10-2026 à 12:44", True),
    ("KiMarc - kimousses en hommage à user9", 6, "user5", 219, "29-09-2026 à 17:56", True),
    ("Liste des user100 topics - A lire avant de poster", 19, "user7", 722, "14-09-2026 à 19:49", True),
]


def og_topics(tok, font, radius, retro):
    import re as _re
    h = open(os.path.join(ROOT, "legacy-ref", "R04-titles.txt"), encoding="utf-8").read().splitlines() if os.path.exists(os.path.join(ROOT, "legacy-ref", "R04-titles.txt")) else []
    topics = list(R04_TOPICS)
    for line in h:
        t, pg, au, rep, dt = line.split("\t")
        topics.append((t, int(pg or 0), au, int(rep), dt, False))
    rows = ""
    for i, (title, pages, author, rep, date, sticky) in enumerate(topics[:12]):
        flagc = "#CC0000" if i % 3 == 0 else ("#2E6BD6" if i % 3 == 1 else None)
        fl = flag_icon(flagc).replace('width="26" height="26"', 'width="16" height="16"') if flagc else ""
        ttl = (f'<span style="color:{tok["unread"]}">» </span>' if sticky else "") + esc(title)
        rows += (f'<div style="display:flex;border-bottom:1px solid {tok["separator"]};">'
                 + og_cell(tok, fl, True, 26, "display:flex;align-items:center;justify-content:center;padding:0")
                 + og_cell(tok, f'<div style="font-size:14.5px;{"font-weight:700;" if sticky else ""}color:{tok["textPrimary"]};line-height:1.25">{ttl}</div>'
                                f'<div style="font-size:11px;font-weight:700;color:{tok["meta"]};margin-top:3px">{author} · {date}</div>')
                 + og_cell(tok, f'<div style="font-size:12px;font-weight:700;color:{tok.get("counter", tok["link"])};text-align:right">{rep}</div>'
                                f'<div style="font-size:10.5px;color:{tok["meta"]};text-align:right">{pages or ""} p.</div>', True, 62) + '</div>')
    pagebar = (f'<div style="position:absolute;left:0;right:0;bottom:0;background:{tok["pageBar"]};color:{tok["onPageBar"]};font-weight:700;font-size:15px;'
               f'padding:10px 16px 30px;border-top:1px solid {tok["separator"]}">Page : <b>1</b> 2 3 4 5 … 500 <span style="float:right">›</span></div>')
    nav = (f'<div style="background:{tok["headerBand"]};color:#fff;padding:12px 16px;display:flex;justify-content:space-between;font-weight:700">'
           f'<span>‹ Forum</span><span>Discussions</span><span>✎</span></div>')
    body = nav + og_band(tok, "Sujet", "Rép.") + rows
    return f'<div style="height:{H-60}px;overflow:hidden;margin:0 -16px">{body}</div>' + pagebar


def b_og():
    note = ("<b>OG gris sert-il de variante sombre ?</b> Non par défaut : c'est un thème gris moyen (texte noir sur #AAAAAA), pas un mode sombre. "
            "Décision (opérateur, 28/10) : deux thèmes séparés à variante unique (clair = sombre), OG clair et OG gris.")
    fixes = "".join(f"<li>{esc(x)}</li>" for t in ("og-clair", "og-gris") for x in THEMES[t].get("wcagFixes", []))
    panel = (f'<div class="panel" style="width:1680px"><h3>Source et corrections</h3><p>Couleurs : feuilles de style du forum récupérées le 28/10 (<code>the_style1.php</code> pour les deux peaux + <code>the_style.css</code>, <code>og-css/findings.md</code>) : sélecteur → couleur → rôle. Code : fond #FFFFFF bordé de noir ; pas de règle a:visited ; aucun orange dans le CSS : accent = <code>orange-hfr</code> échantillonné sur le logo. Alternance du web = par colonnes '
             f'(cBackCouleurTab1/2), reprise ici par la cellule de fin de ligne <code>rowAlt</code>. Pas de bitmap du logo : mot-symbole générique.</p>'
             f'<p style="margin-top:8px"><b>Écarts WCAG corrigés :</b></p><ul style="margin-left:18px">{fixes}</ul><p style="margin-top:8px">{note}</p></div>')
    body = ('<div class="grid">' + phone("og-clair", "any", label="OG clair — accueil", note="bandeaux marine #001932, lignes #F7F7F7, colonnes #DEDFDF, liens marine gras")
            + phone("og-clair", "any", screen=og_topics, label="OG clair — liste de sujets", note="Discussions, capture R04 anonymisée")
            + phone("og-gris", "any", label="OG gris — accueil", note="lignes #AAAAAA, colonnes #BBBBBB, fond #666666")
            + phone("og-gris", "any", screen=og_topics, label="OG gris — liste de sujets", note="compteurs bleus assombris #0000B0")
            + panel + '</div>')
    return page("Famille OG Web", "Le look HTML du forum transposé sur la mise en page SwiftUI de SwiftHFR : bandeau d'en-tête, lignes denses, séparateurs de colonnes, méta en petit gras.", body, 1780)


def b_legacy():
    note = lambda h: f"teinte {h:.2f} → remplissage {legacy_accent(h, False)[0]} / {legacy_accent(h, True)[0]}"
    body = ('<div class="grid">'
            + phone("legacy", "light", 0.74, label="Legacy — clair, teinte 0,74", note=note(0.74))
            + phone("legacy", "dark", 0.50, label="Legacy — sombre, teinte 0,50", note=note(0.50))
            + phone("legacy", "light", 0.528, label="Legacy — clair, teinte par défaut 0,53 (190°)", note=note(0.528))
            + phone("legacy", "dark", 0.74, label="Legacy — sombre, teinte 0,74", note=note(0.74) + " ; texte d'accent éclairci pour 4,5:1")
            + phone("legacy", "dark", 0.50, screen=legacy_settings(0.50), label="Réglages › Thème (legacy, parité)", note="curseur continu conservé + 10 pastilles prédéfinies")
            + phone("legacy", "light", 0.74, screen=legacy_settings(0.74), label="Réglages › Thème — clair, 0,74")
            + '</div>')
    return page("Thème Legacy — par Ezzz", "L'app legacy actuelle (couche SwiftUI, origin/master 21173e7), vérifiée sur 11 captures d'écran de l'opérateur : fond groupé système (#F2F2F7 / noir), cartes #FFFFFF / #1C1C1E, "
                "séparateurs système, icônes de catégorie + « N sous-forums » (comptes legacy : liens R01 + « Tous les sujets » + ajouts codés en dur), teinte d'accent continue (0–1). Mise en page SwiftHFR (pas de barre d'onglets, LOT-082).", body, 1780)


def b_da():
    import da
    head = '<div style="display:flex;gap:16px;margin-left:300px;margin-bottom:6px">' + "".join(
        f'<div style="width:{(260 if n != "Sorcière sur balai" else 300)}px;font-weight:600;font-size:14px;text-align:center">{n}</div>' for n, _, _ in da.SUBJECTS) + '</div>'
    rows = ""
    for sid, title, desc in da.STYLES:
        cells = ""
        for j, (n, items, vb) in enumerate(da.SUBJECTS):
            defs, art_ = da.render(items, sid, f"{sid}{j}")
            w = 300 if n == "Sorcière sur balai" else 260
            x0, y0, x1, y1 = vb
            cells += (f'<div style="width:{w}px;height:240px;border-radius:14px;background:{da.BG[sid]};display:flex;align-items:center;justify-content:center">'
                      f'<svg viewBox="{x0-8} {y0-8} {x1-x0+16} {y1-y0+16}" width="{w-30}" height="220"><defs>{defs}</defs>{art_}</svg></div>')
        star = ' style="outline:3px solid #E9781A;outline-offset:6px;border-radius:16px"' if sid == "croquis" else ""
        rows += (f'<div style="display:flex;gap:16px;align-items:center;margin-bottom:22px"><div style="width:284px;font-size:13.5px;line-height:1.4">'
                 f'<b style="font-size:15px">{esc(title)}</b><br>{esc(desc)}</div><div style="display:flex;gap:16px"{star}>{cells}</div></div>')
    # E: Spooktober soft bat on the dark background
    bg = THEMES["spooktober-soft"]["variants"]["dark"]["background"]
    opts = [("Actuel : noir", "#000000", None), ("Gris (textSecondary)", "#A99AAD", None), ("Violet", "#9B59D0", None), ("Noir + liseré orange", "#000000", "#FF8A2A")]
    cells = ""
    for name, fill, rim in opts:
        ratio = _cr(rim or fill, bg)
        ok = "≥ 3:1 ✓" if ratio >= 3 else "< 3:1 ✗"
        batsvg = art.bat(fill)
        if rim:
            batsvg = f'<g transform="translate(60,60) scale(1.09) translate(-60,-60)">{art.bat(rim).replace(art.INK, rim)}</g>' + art.bat(fill)
        cells += (f'<div style="width:270px;text-align:center;font-size:13px"><div style="background:{bg};border-radius:14px;padding:10px">'
                  f'<svg viewBox="0 20 120 70" width="200" height="117">{batsvg}</svg></div><b>{esc(name)}</b><br>'
                  f'{(rim or fill)} sur {bg} : {ratio:.2f}:1 {ok}</div>')
    bat = (f'<div class="panel" style="width:1160px;margin-top:10px"><h3>E · Spooktober soft : la chauve-souris disparaît sur le fond sombre</h3>'
           f'<p>Objet graphique : cible WCAG 1.4.11 ≥ 3:1 contre <code>{bg}</code>. Recommandation : <b>gris textSecondary</b> (règle « silhouette = textSecondary » déjà dans la charte) '
           f'ou le liseré orange si l\'on veut garder la chauve-souris noire.</p><div style="display:flex;gap:22px;margin-top:12px">{cells}</div></div>')
    sleigh = ('<div class="panel" style="width:1160px;margin-top:22px"><h3>C · Sens de déplacement (règle de charte)</h3>'
              '<p>Tout objet qui traverse regarde vers où il va : le traîneau est <b>tiré</b> par les rennes attelés <b>devant</b> lui, tête dans le sens de la marche ; '
              'la sorcière a la tête et le chapeau devant, la paille du balai derrière. Le dessin actuel du traîneau (rennes tournés vers le traîneau) est faux : '
              'il sera redessiné dans la DA retenue. Voir THEMES.md §7.</p></div>')
    body = head + rows + sleigh + bat
    return page("Direction artistique — 5 styles candidats", "Mêmes sujets (buste de Marianne, citrouille, sorcière sur balai) dans chaque style. Les références de l\'opérateur donnent le style seulement : rien n\'est copié ni décalqué. Toutes les illustrations seront redessinées dans la DA choisie.", body, 1180)


def b_da2():
    import da2
    subj = ["Buste de Marianne", "Citrouille (jack-o\'-lantern)", "Sorcière sur balai (vole vers la gauche)"]
    head = '<div style="display:flex;gap:18px;margin-left:318px;margin-bottom:20px">' + "".join(f'<div style="width:420px;font-weight:700;font-size:16px;text-align:center">{n}</div>' for n in subj) + '</div>'
    rows = ""
    styles = list(da2.STYLES) + [("actuel", "6 · Style actuel (référence)", "Aplats, encre régulière 3,5 u, sans ombre : la base v1, pour comparaison.", "#FFFFFF",
                                  (lambda: place(art.marianne(), 80, 60, 1.6), lambda: place(art.pumpkin(), 50, 60, 2.5), lambda: place(art.witch(), 60, 90, 2.3)))]
    for sid, title, desc, bg, fns in styles:
        tiles = "".join(f'<div style="width:420px;height:420px;border-radius:16px;overflow:hidden;background:{bg}"><svg viewBox="0 0 400 400" width="420" height="420">{f()}</svg></div>' for f in fns)
        mark = "outline:4px solid #E9781A;outline-offset:8px;border-radius:18px;" if sid == "croquis" else ""
        rows += (f'<div style="display:flex;gap:18px;align-items:center;margin-bottom:30px"><div style="width:300px;font-size:14px;line-height:1.45">'
                 f'<b style="font-size:18px">{esc(title)}</b><br>{esc(desc)}</div><div style="display:flex;gap:18px;{mark}">{tiles}</div></div>')
    return page("Direction artistique v2 — 6 styles", "Nouveaux dessins pour chaque style (pas de filtre sur les anciens). Mêmes sujets partout ; la sorcière vole vers la gauche, tête et chapeau devant, paille du balai derrière. "
                "Références de l\'opérateur : style seulement, rien n\'est copié ni décalqué.", head + rows, 1620)


def b_da2_closeup():
    import da2
    body = (f'<div style="display:flex;gap:30px;align-items:flex-start"><div style="width:1000px;height:1000px;border-radius:20px;background:{da2.P1["paper"]}">'
            f'<svg viewBox="0 0 400 400" width="1000" height="1000">{da2.marianne_s1()}</svg></div>'
            '<div class="panel" style="width:380px"><h3>Style 1 — croquis numérique, gros plan</h3><ul style="margin-left:18px">'
            '<li>Encre <code>#2B2F3A</code> : contours extérieurs 2,8–3,4 u, contours intérieurs et plis 1,0–1,8 u.</li>'
            '<li>Cel-shading plat, 2–3 tons par surface, sans dégradé : base <code>#F4EFE8</code>, lumière pêche <code>#F2AE8C</code> / <code>#F7CDB4</code>, ombre gris-bleu <code>#A9B6C2</code> / <code>#8796A6</code>.</li>'
            '<li>Papier <code>#F8F5F0</code> ; lumière venant d\'en haut à gauche.</li>'
            '<li>Seule couleur d\'accent : la cocarde.</li></ul>'
            '<p style="margin-top:12px"><b>Limite honnête :</b> c\'est un dessin SVG tracé à la main en code (≈ 60 formes). Il donne la grammaire du style '
            '(trait, aplats, deux familles d\'ombre), pas la finition d\'un illustrateur : anatomie et plis restent simplifiés. Voir README pour la suite proposée.</p></div></div>')
    return page("Style 1 — gros plan : buste de Marianne", "Pour juger la finition du style « croquis numérique ».", body, 1480)


def b_blender_closeup():
    img = data_uri("marianne-1600")
    body = ('<div style="display:flex;gap:30px;align-items:flex-start"><div style="width:1100px;height:1100px;border-radius:20px;background:#F8F5F0;overflow:hidden">'
            f'<img src="{img}" width="1100" height="1100"></div>'
            '<div class="panel" style="width:360px"><h3>Nouveau pipeline : Blender</h3><ul style="margin-left:18px">'
            '<li>Buste modelé de façon procédurale (script Python dans <code>src/blender/marianne.py</code>, aucun asset externe) : primitives douces fusionnées par remaillage voxel, comme une sculpture en terre.</li>'
            '<li>Ombrage cel « croquis numérique » : 4 tons plats sans dégradé — ombre gris-bleu <code>#A9B6C2</code>/<code>#8796A6</code>, terminateur pêche <code>#F2AE8C</code>/<code>#F7CDB4</code>, lumière blanc cassé <code>#F4EFE8</code>.</li>'
            '<li>Encre Freestyle <code>#2B2F3A</code> : contour extérieur épais, contours intérieurs (traits, plis) fins, effilés aux extrémités ; traits trop courts filtrés.</li>'
            '<li>Lumière en haut à gauche ; papier <code>#F8F5F0</code>.</li>'
            '<li>Rendu 1600 px en ≈ 20 s ; chaque sujet = un script, toutes tailles/variantes regénérables.</li></ul>'
            '<p style="margin-top:10px"><b>Validé</b> par l\'opérateur le 28/10 ; corrections appliquées : traits du visage, bonnet qui retombe vers l\'avant, mèches.</p>'
            '<p style="margin-top:8px"><b>Réglables à la demande</b> : traits intérieurs plus nombreux, plis plus marqués, coiffe plus haute, angle de vue, plus ou moins de pêche.</p></div></div>')
    return page("Style 1 · gros plan Blender : buste de Marianne", "Rendu du nouveau pipeline (Blender, Freestyle + cel-shading) pour juger la finition par rapport à la référence.", body, 1520)


BOARDS = {
    "theme-legacy": b_legacy, "theme-og": b_og, "da-styles": b_da2, "da-closeup": b_da2_closeup, "blender-closeup": b_blender_closeup, "theme-swift": b_swift, "theme-retro": b_retro, "theme-noel": b_noel,
    "theme-samain": b_samain, "events": b_events, "selectors": b_selector, "style-charter": b_charter,
    "icons-legacy": lambda: b_icons("legacy"), "icons-beta": lambda: b_icons("beta"),
    "icons-xface": lambda: b_icons("xface"), "icons-season": lambda: b_icons("season"),
}


def render(name, htmlstr, width):
    os.makedirs(SRC, exist_ok=True)
    hp = os.path.join(SRC, name + ".html")
    open(hp, "w").write(htmlstr)
    png = os.path.join(SRC, name + ".png")
    # tall window, then crop to content height measured by a second pass is overkill: use fixed heights per board
    height = {"style-charter": 1480, "blender-closeup": 1280, "da-styles": 3050, "da-closeup": 1180, "theme-legacy": 2140, "theme-og": 1420, "events": 2140, "selectors": 1100, "theme-retro": 1100}.get(name, 1100)
    if name.startswith("icons-"):
        rows = (len([p for p in icons.PACKS if p[0] == name[6:]][0][2]) + 5) // 6
        height = 140 + rows * 310 + 330
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--window-size={width + 80},{height}", f"--screenshot={png}", "file://" + hp],
                   check=True, capture_output=True)
    jpg = os.path.join(OUT, name + ".jpg")
    q = 82
    while True:
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(q), png, "--out", jpg], check=True, capture_output=True)
        if os.path.getsize(jpg) < 1_000_000 or q <= 40:
            break
        q -= 8
    os.remove(png)
    print(f"{name}.jpg {os.path.getsize(jpg)//1024} KB q{q}")


def export_icons_1024():
    d = os.path.join(OUT, "icons-1024")
    os.makedirs(d, exist_ok=True)
    for pack_id, pack_name, (iid, name, src, fn, win) in icons.all_icons():
        if src.startswith("Icon-") or "legacy" in src and "new" not in src:
            continue  # legacy PNGs already exist at origin/master
        s = fn("x")
        if iid == "beta-red":
            s = icons.i_beta_red("x", small=False)
        sp = os.path.join(d, iid + ".svg")
        open(sp, "w").write(s)
        hp = os.path.join(SRC, "icon-" + iid + ".html")
        open(hp, "w").write(f'<!doctype html><html><body style="margin:0;width:1024px;height:1024px">{s}</body></html>')
        png = os.path.join(d, iid + ".png")
        subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1", "--window-size=1024,1024",
                        f"--screenshot={png}", "file://" + hp], check=True, capture_output=True)
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "85", png, "--out", os.path.join(d, iid + ".jpg")], check=True, capture_output=True)
        os.remove(png)
        os.remove(hp)
    print("icons-1024 done")


if __name__ == "__main__":
    want = sys.argv[1:] or list(BOARDS) + ["icons1024"]
    for n in want:
        if n == "icons1024":
            export_icons_1024()
            continue
        hs = BOARDS[n]()
        width = int(hs.split('body style="width:')[1].split("px")[0]) - 80
        render(n, hs, width)
