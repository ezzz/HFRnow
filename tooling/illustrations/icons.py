"""Alternate app icon masters (draft), 1024x1024 full-bleed square SVG, unmasked
(the system applies the shape). See ICONS.md. Legacy icons are referenced as PNG."""
import base64, os
import art
from png_art import img, silhouette_filter, png_defs, size as png_size
from art import INK, place

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "..", "legacy-ref")
ORANGE_HFR = "#F18F18"  # orange-hfr: forum_logo.gif, exact pixel count (ICONS.md §4)
NAVY_HFR = "#012040"


def png_uri(name, small=True):
    path = os.path.join(REF, ("s-" if small else "icon-") + name + ".png")
    return "data:image/png;base64," + base64.b64encode(open(path, "rb").read()).decode()


def svg(body, defs=""):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="100%" height="100%"><defs>{defs}{png_defs(body)}</defs>{body}</svg>'


def hfr_letters(fill_h="#FFFFFF", fill_fr="#FFFFFF", y=640, size=360):
    return (f'<text x="512" y="{y}" text-anchor="middle" font-family="Avenir Next, Avenir, Helvetica Neue, sans-serif" '
            f'font-weight="800" font-size="{size}" letter-spacing="-8"><tspan fill="{fill_h}">H</tspan><tspan fill="{fill_fr}">FR</tspan></text>')


FACE_SCALE, FACE_OFF = 10.08, 8  # ring = 86.7 % of the icon, as in the legacy Icon-REDFACE


def face(scale=FACE_SCALE, x=FACE_OFF, y=FACE_OFF, **kw):
    return place(art.smiley(**kw), x, y, scale)


def legacy_png(name, small=True):
    return svg(f'<image href="{png_uri(name, small)}" x="0" y="0" width="1024" height="1024" preserveAspectRatio="none"/>')


def i_default(p):
    defs = f'<linearGradient id="{p}d" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#D0160A"/><stop offset="1" stop-color="#8E0300"/></linearGradient>'
    return svg(f'<rect width="1024" height="1024" fill="url(#{p}d)"/>' + face(scale=8.4, x=92, y=92, face="#FF2A1A"), defs)


def i_redface(p, blue=False):
    top, bot, ring = ("#1859FF", "#1535FF", "#EAEAEA") if blue else ("#FF4560", "#FF5835", "#FFFFFF")
    defs = f'<linearGradient id="{p}rf" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bot}"/></linearGradient>'
    return svg(f'<rect width="1024" height="1024" fill="url(#{p}rf)"/>' + face(face="none", ink=ring), defs)


def i_orange(p):
    return svg(f'<rect width="1024" height="1024" fill="{ORANGE_HFR}"/>' + hfr_letters())


def i_beta_red(p, small=True):
    defs = (f'<filter id="{p}thick" x="0" y="0" width="100%" height="100%">'
            '<feColorMatrix type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 -1 0 0 1"/>'
            '<feMorphology operator="dilate" radius="5"/>'
            '<feComponentTransfer><feFuncA type="linear" slope="3" intercept="-0.4"/></feComponentTransfer></filter>')
    return svg(f'<rect width="1024" height="1024" fill="#E8242C"/>'
               f'<image href="{png_uri("beta", small)}" x="0" y="0" width="1024" height="1024" filter="url(#{p}thick)"/>', defs)


def i_xface(p):
    return svg('<rect width="1024" height="1024" fill="#FF0000"/>' + face(face="none"))


def _pride_diag(p):
    cols = ["#E40303", "#FF8C00", "#FFED00", "#008026", "#004DFF", "#750787"]
    w = 1450 / 6
    bands = "".join(f'<rect x="{-213 + i*w:.1f}" y="-300" width="{w+1:.1f}" height="1700" fill="{c}"/>' for i, c in enumerate(cols))
    return f'<g transform="rotate(-45 512 512)">{bands}</g>'


def i_pride(p):
    return svg(_pride_diag(p) + face(face="#FF0000"))


def i_pride_outline(p):
    return svg(_pride_diag(p) + face(face="none"))


def _halos(p, dark):
    a1, a2 = (0.55, 0.35) if dark else (0.35, 0.25)
    return (f'<radialGradient id="{p}h1" cx="0" cy="0" r="0.9"><stop offset="0" stop-color="#6D5DFC" stop-opacity="{a1}"/><stop offset="1" stop-color="#6D5DFC" stop-opacity="0"/></radialGradient>'
            f'<radialGradient id="{p}h2" cx="1" cy="1" r="0.9"><stop offset="0" stop-color="#E45FD2" stop-opacity="{a2}"/><stop offset="1" stop-color="#E45FD2" stop-opacity="0"/></radialGradient>')


def i_grad(p, dark=False):
    end = "#F0649A" if dark else "#D9437F"
    defs = _halos(p, dark) + (f'<linearGradient id="{p}au" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5B4BFF"/>'
                              f'<stop offset="0.5" stop-color="#B45CF0"/><stop offset="1" stop-color="{end}"/></linearGradient>')
    bg = "#1C1F2B" if dark else "#F2F3F9"
    ink = "#1C1F2B"
    body = (f'<rect width="1024" height="1024" fill="{bg}"/><rect width="1024" height="1024" fill="url(#{p}h1)"/>'
            f'<rect width="1024" height="1024" fill="url(#{p}h2)"/>' + face(face=f"url(#{p}au)", ink=ink))
    return svg(body, defs)


def _gold(p):
    return (f'<linearGradient id="{p}g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#8C6A12"/><stop offset="0.3" stop-color="#F5D77A"/>'
            f'<stop offset="0.55" stop-color="#B8902A"/><stop offset="0.8" stop-color="#FFE9A0"/><stop offset="1" stop-color="#9C7A1C"/></linearGradient>')


def i_gold(p):
    return svg(f'<rect width="1024" height="1024" fill="url(#{p}g)"/>' + face(face="#FF0000"), _gold(p))


def i_gold_on_black(p):
    return svg('<rect width="1024" height="1024" fill="#000"/>' + face(face="none", ink=f"url(#{p}g)"), _gold(p))


def i_gold_outline(p):
    return svg(f'<rect width="1024" height="1024" fill="url(#{p}g)"/>' + face(face="none"), _gold(p))


def i_5250(p):
    """Redface in the Rétro 5250 green-screen style: phosphor green strokes on black, scanlines."""
    defs = (f'<pattern id="{p}scan" width="8" height="8" patternUnits="userSpaceOnUse"><rect width="8" height="4" fill="#000" fill-opacity="0.35"/></pattern>'
            f'<filter id="{p}glow" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="9"/></filter>')
    green = "#33FF33"
    return svg('<rect width="1024" height="1024" fill="#000"/>'
               + f'<g filter="url(#{p}glow)" opacity="0.55">{face(face="none", ink=green)}</g>' + face(face="none", ink=green)
               + f'<rect x="700" y="868" width="60" height="18" fill="{green}"/>'
               + f'<rect width="1024" height="1024" fill="url(#{p}scan)"/>', defs)


def i_negative(p):
    return svg('<rect width="1024" height="1024" fill="#000"/>' + face(face="none", ink="#FFFFFF"))


def i_negative_inv(p):
    return svg('<rect width="1024" height="1024" fill="#FFF"/>' + face(face="none", ink="#000000"))


def i_sunset(p):
    defs = f'<linearGradient id="{p}s" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#E52421"/><stop offset="1" stop-color="#FFD400"/></linearGradient>'
    return svg(f'<rect width="1024" height="1024" fill="url(#{p}s)"/>' + face(face="none"), defs)


# Season icons: the redface stays the measured vector; every illustration is a Blender render (src/blender/out, THEMES.md §7).
def i_noel_redface(p):
    return svg('<rect width="1024" height="1024" fill="#FFFFFF"/>'
               + img("noel_tree", 20, 470, 400) + img("noel_gift", 10, 840, 150) + img("noel_gift_blue", 150, 870, 120) + img("noel_gift_gold", 280, 860, 130)
               + face(scale=6.4, x=380, y=300, face="#FF0000")
               + img("acc_santa_hat", 520, 90, 420, rot=-12))


def i_noel_hfr(p):
    flakes = "".join(img("noel_snowflake", x, y, s_, rot=r_) for x, y, s_, r_ in
                     ((70, 250, 50, 10), (900, 230, 44, 30), (850, 660, 36, 0), (120, 540, 34, 20), (470, 190, 30, 40), (640, 220, 40, 15), (300, 210, 34, 5), (950, 500, 46, 25)))
    body = (f'<rect width="1024" height="1024" fill="{art.N["fir"]}"/>' + flakes
            + f'<rect x="150" y="350" width="724" height="320" rx="56" fill="{ORANGE_HFR}" stroke="{INK}" stroke-width="6"/>'
            + hfr_letters(y=620, size=300)
            + img("noel_snowpile", 130, 300, 764, h=110) + img("noel_snowpile", 230, 392, 120, h=34) + img("noel_snowpile", 470, 392, 170, h=36) + img("noel_snowpile", 690, 394, 130, h=34)
            + img("noel_garland", -40, 0, 1104)
            + img("noel_snowman", 30, 640, h=370) + img("noel_gift", 690, 720, 290))
    return svg(body)


def i_halloween_jack(p):
    """The redface turned into a jack-o'-lantern: same measured vector face and proportions (uniform scale), filled orange,
    the round mouth replaced by a carved smile centred on the mouth, side lobes, ribs and a stem."""
    k, o = 7.4, 142   # uniform scale of the 100-unit redface grid; leaves room for the lobes and the stem
    defs = (f'<radialGradient id="{p}or" cx="0.42" cy="0.38" r="0.7"><stop offset="0" stop-color="#FFB25A"/><stop offset="0.6" stop-color="#F28C1E"/><stop offset="1" stop-color="#D96A0A"/></radialGradient>'
            f'<linearGradient id="{p}lobe" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#E67C14"/><stop offset="1" stop-color="#B9550A"/></linearGradient>'
            f'<radialGradient id="{p}glow" cx="0.5" cy="0.4" r="0.6"><stop offset="0" stop-color="#FFE27A"/><stop offset="1" stop-color="#FF9A1F"/></radialGradient>')
    sw = 4.12
    # carved smile with two square teeth, centred on the redface mouth (50, 63.1)
    smile = ("M27,58 Q32,59.3 37,59.8 L37,66.5 L44.5,66.5 L44.5,60.4 Q58,60.6 73,58 "
             "C72,70 67,78 62,80.6 L62,74 L54.5,74 L54.5,81.8 C40,82 29,74 27,58 Z")
    g = (f'<path d="M50,10 C48,2 52,-6 60,-10" fill="none" stroke="{INK}" stroke-width="9" stroke-linecap="round"/>'
         f'<path d="M50,10 C48,2 52,-6 60,-10" fill="none" stroke="#5E8A3A" stroke-width="5" stroke-linecap="round"/>'
         f'<ellipse cx="14" cy="52" rx="20" ry="36" fill="url(#{p}lobe)" stroke="{INK}" stroke-width="{sw}"/>'
         f'<ellipse cx="86" cy="52" rx="20" ry="36" fill="url(#{p}lobe)" stroke="{INK}" stroke-width="{sw}"/>'
         f'<circle cx="50" cy="50" r="41.94" fill="url(#{p}or)" stroke="{INK}" stroke-width="{sw}"/>'
         f'<path d="M30,14 C18,34 18,66 30,86 M70,14 C82,34 82,66 70,86" fill="none" stroke="{INK}" stroke-width="1.6" stroke-linecap="round" opacity="0.55"/>'
         f'<path d="M28.39,32.9 a7.81,7.81 0 0 0 15.62,0 M55.99,32.9 a7.81,7.81 0 0 0 15.62,0" fill="none" stroke="{INK}" stroke-width="{sw}" stroke-linecap="round"/>'
         f'<g transform="translate(0,-6.9)"><path d="{smile}" fill="url(#{p}glow)" stroke="{INK}" stroke-width="{sw}" stroke-linejoin="round"/></g>')
    return svg(f'<rect width="1024" height="1024" fill="{art.S["night"]}"/>' + f'<g transform="translate({o},{o + 30}) scale({k})">{g}</g>', defs)


def i_halloween_hfr(p):
    defs = silhouette_filter(f"{p}sil", INK)
    return svg(f'<rect width="1024" height="1024" fill="{ORANGE_HFR}"/>'
               + img("samain_moon", 640, 50, 320) + img("samain_witch", 600, 130, 360, filt=f"{p}sil")
               + img("samain_web", 0, 0, 340, filt=f"{p}sil") + hfr_letters(y=700)
               + img("samain_bat", 60, 740, 300) + img("samain_bat", 760, 800, 190, rot=-10), defs)


def i_spring(p):
    defs = f'<linearGradient id="{p}sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF4F7"/><stop offset="1" stop-color="#FCE1EA"/></linearGradient>'
    return svg(f'<rect width="1024" height="1024" fill="url(#{p}sky)"/>' + img("year_cherry_tree", -80, -10, 1100)
               + face(scale=6.4, x=380, y=360, face="#FF0000"), defs)


def i_summer(p):
    return svg(f'<rect width="1024" height="1024" fill="{art.Y["sky"]}"/>' + img("year_sun", 600, -80, 480)
               + f'<path d="M-10,935 C180,880 380,900 560,930 C720,955 880,920 1034,890 L1034,1034 L-10,1034 Z" fill="#F2D49B" stroke="{INK}" stroke-width="6"/>'
               + img("year_palm", -10, 560, h=440)
               + face(scale=7.4, x=230, y=230, face="#FF0000", accessory="sunglasses"))


def i_winter(p):
    """Restored pre-Blender version (operator, 2026-10-28): dense, randomly spread vector snowflakes, vector scarf."""
    import random
    r = random.Random(11)
    flakes = ""
    for _ in range(46):
        x, y, sc = r.uniform(-30, 1000), r.uniform(-30, 1000), r.choice([0.25, 0.35, 0.45, 0.6, 0.8])
        flakes += place(art.snowflake("#FFFFFF", 2), x, y, sc, r.uniform(0, 60))
    dots = "".join(f'<circle cx="{r.uniform(0,1024):.0f}" cy="{r.uniform(0,1024):.0f}" r="{r.choice([5,7,9])}" fill="#FFFFFF" fill-opacity="0.9"/>' for _ in range(60))
    return svg('<rect width="1024" height="1024" fill="#CFE3F5"/>' + flakes + dots + face(scale=7.6, x=132, y=70, face="#FF0000", accessory="scarf"))


PACKS = [
    ("legacy", "Legacy", [
        ("legacy-default", "Défaut", "primary icon: legacy Icon-RedFace3D.icon (Icon Composer, reused as is; shown approximated)", i_default, None),
        ("legacy-redface", "REDFACE", "vector redraw of Icon-REDFACE (measured)", i_redface, None),
        ("legacy-redface-blue", "REDFACE Blue", "vector redraw of Icon-REDFACEBLUE (measured)", lambda p: i_redface(p, True), None),
        ("legacy-blue", "Blue", "Icon-BLUE (legacy 1024)", lambda p: legacy_png("blue"), None),
        ("legacy-orange", "Orange", "new: Blue layout, white HFR on orange-hfr", i_orange, None),
        ("legacy-classic-yellow", "Classique Yellow", "Icon-CLASSIC (legacy 1024)", lambda p: legacy_png("classic"), None),
        ("legacy-classic-red", "Classique Red", "Icon-CLASSIC-RED (legacy 1024)", lambda p: legacy_png("classic-red"), None),
        ("legacy-classic-blue", "Classique Blue", "Classic-Blue (legacy 1024); kept", lambda p: legacy_png("classic-blue"), None),
        ("legacy-white", "White", "Icon-WHITE (legacy 1024); kept", lambda p: legacy_png("white"), None),
    ]),
    ("beta", "Beta", [
        ("beta-legacy", "Beta", "Icon-BETA (legacy 1024)", lambda p: legacy_png("beta"), None),
        ("beta-red", "Beta rouge", "new: black strokes on red, strokes ~+10 %", i_beta_red, None),
    ]),
    ("xface", "X-face", [
        ("xface-red", "X-face", "base: :o black on red", i_xface, None),
        ("xface-pride", "Fierté", "diagonal Pride flag, solid redface", i_pride, None),
        ("xface-pride-outline", "Fierté contour", "diagonal Pride flag, redface strokes only", i_pride_outline, None),
        ("xface-gradient-light", "Dégradé clair", "Swift theme light (aurora)", lambda p: i_grad(p, False), None),
        ("xface-gradient-dark", "Dégradé sombre", "Swift theme dark (aurora)", lambda p: i_grad(p, True), None),
        ("xface-gold", "Or", "gold background", i_gold, None),
        ("xface-gold-on-black", "Or sur noir", "drawing in gold on black", i_gold_on_black, None),
        ("xface-gold-outline", "Or contour", "gold background, black outline, no fill", i_gold_outline, None),
        ("xface-5250", "Terminal 5250", "green phosphor redface, Rétro 5250 style", i_5250, None),
        ("xface-negative", "Négatif", "white on black", i_negative, None),
        ("xface-negative-inverted", "Négatif inversé", "black on white", i_negative_inv, None),
        ("xface-sunset", "Coucher de soleil", "red to yellow gradient", i_sunset, None),
    ]),
    ("season", "Saisons", [
        ("noel-redface", "Noël REDFACE", "01/12–26/12", i_noel_redface, ("12-01", "12-26")),
        ("noel-hfr", "Noël HFR", "01/12–26/12", i_noel_hfr, ("12-01", "12-26")),
        ("halloween-jack", "Halloween citrouille", "01/10–31/10", i_halloween_jack, ("10-01", "10-31")),
        ("halloween-hfr", "Halloween HFR", "01/10–31/10", i_halloween_hfr, ("10-01", "10-31")),
        ("spring-sakura", "Printemps", "toute l'année", i_spring, None),
        ("summer-sun", "Été", "toute l'année", i_summer, None),
        ("winter-scarf", "Hiver", "toute l'année", i_winter, None),
    ]),
]


def all_icons():
    for pack_id, pack_name, items in PACKS:
        for item in items:
            yield pack_id, pack_name, item
