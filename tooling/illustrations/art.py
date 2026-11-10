"""SwiftHFR illustration library (draft). Every drawing follows the style charter
in THEMES.md §7: 120-unit grid, ink outline 3.5 u (~3 % of the box), round caps and
joins, flat fills from the season palette, one highlight tone (white 35 %), no text,
no gradients. Functions return SVG fragments drawn in their own box (default 120x120)."""

INK = "#1E1A1D"
SW = 3.5
HL = 'fill="#FFFFFF" fill-opacity="0.35" stroke="none"'

PAL = {
    "noel": {"red": "#D21F3C", "darkred": "#9E1530", "green": "#1E6B3A", "fir": "#0F4D2E",
             "gold": "#E3B341", "snow": "#FFFFFF", "skin": "#F4C7A1", "brown": "#7A4A2A",
             "cream": "#FFF8EC"},
    "samain": {"orange": "#FF7A00", "pumpkin": "#F28C1E", "night": "#140A1F", "purple": "#6B2FA3",
               "lilac": "#9B59D0", "ghost": "#F7F4FF", "moon": "#FFE9A8", "bolt": "#FFD23F",
               "skin": "#F4C7A1", "brown": "#7A4A2A", "green": "#4E8A3A"},
    "fete": {"blue": "#0055A4", "white": "#FFFFFF", "red": "#EF4135", "stone": "#ECE7DD",
             "stoneshade": "#CFC6B8", "gold": "#E3B341"},
    "year": {"sakura": "#F7B7C8", "sakuradeep": "#E0839F", "sun": "#FFC83D", "sky": "#2F8FE0",
             "scarf": "#D21F3C", "glass": "#1E1A1D"},
}
N, S, F, Y = PAL["noel"], PAL["samain"], PAL["fete"], PAL["year"]


def s(fill, extra=""):
    return f'fill="{fill}" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round" stroke-linecap="round" {extra}'


def place(frag, x, y, scale=1.0, rot=0, flip=False, extra=""):
    fx = -scale if flip else scale
    return f'<g transform="translate({x},{y}) rotate({rot}) scale({fx},{scale})" {extra}>{frag}</g>'


# ---------- Noël ----------
def tree():
    return (f'<rect x="52" y="96" width="16" height="18" rx="2" {s(N["brown"])}/>'
            f'<polygon points="60,46 10,100 110,100" {s(N["green"])}/>'
            f'<polygon points="60,26 18,76 102,76" {s(N["green"])}/>'
            f'<polygon points="60,10 28,52 92,52" {s(N["green"])}/>'
            f'<circle cx="44" cy="66" r="5" {s(N["red"])}/><circle cx="76" cy="88" r="5" {s(N["gold"])}/>'
            f'<circle cx="66" cy="44" r="4.5" {s(N["gold"])}/><circle cx="38" cy="92" r="5" {s(N["red"])}/>'
            f'<polygon points="60,0 64,9 73,9 66,15 69,24 60,18 51,24 54,15 47,9 56,9" {s(N["gold"])}/>')


def ornament(color=None):
    c = color or N["red"]
    return (f'<path d="M60,4 v12" stroke="{INK}" stroke-width="{SW}" stroke-linecap="round"/>'
            f'<rect x="51" y="16" width="18" height="12" rx="2" {s(N["gold"])}/>'
            f'<circle cx="60" cy="66" r="38" {s(c)}/>'
            f'<ellipse cx="45" cy="52" rx="7" ry="13" transform="rotate(30 45 52)" {HL}/>'
            f'<path d="M24,70 q36,14 72,0" fill="none" stroke="{N["gold"]}" stroke-width="5"/>')


def gift(box=None, ribbon=None):
    b, r = box or N["red"], ribbon or N["gold"]
    return (f'<rect x="18" y="48" width="84" height="64" rx="3" {s(b)}/>'
            f'<rect x="12" y="36" width="96" height="18" rx="3" {s(b)}/>'
            f'<rect x="53" y="36" width="14" height="76" {s(r)}/>'
            f'<ellipse cx="44" cy="26" rx="16" ry="9" transform="rotate(-20 44 26)" {s(r)}/>'
            f'<ellipse cx="76" cy="26" rx="16" ry="9" transform="rotate(20 76 26)" {s(r)}/>'
            f'<circle cx="60" cy="33" r="6" {s(r)}/>')


def candy_cane():
    d = "M72,112 L72,40 A20,20 0 0 0 32,40 L32,48"
    return (f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="20" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="#FFFFFF" stroke-width="13" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="{N["red"]}" stroke-width="13" stroke-dasharray="9 9"/>')


def snowman():
    return (f'<circle cx="60" cy="88" r="28" {s("#FFFFFF")}/><circle cx="60" cy="46" r="20" {s("#FFFFFF")}/>'
            f'<rect x="44" y="12" width="32" height="20" rx="2" {s(INK)}/><rect x="36" y="28" width="48" height="7" rx="2" {s(INK)}/>'
            f'<circle cx="53" cy="44" r="2.6" fill="{INK}"/><circle cx="67" cy="44" r="2.6" fill="{INK}"/>'
            f'<polygon points="60,49 78,53 60,55" {s("#F28C1E")}/>'
            f'<path d="M40,62 q20,10 40,0 l2,8 q-22,10 -44,0 z" {s(N["red"])}/>'
            f'<rect x="64" y="66" width="10" height="22" rx="3" {s(N["red"])}/>'
            f'<circle cx="60" cy="82" r="2.6" fill="{INK}"/><circle cx="60" cy="94" r="2.6" fill="{INK}"/>')


def snowflake(color="#FFFFFF", w=3):
    arms = "".join(f'<g transform="rotate({a} 60 60)"><path d="M60,60 V14 M60,28 l-9,-9 M60,28 l9,-9 M60,42 l-7,-7 M60,42 l7,-7" '
                   f'fill="none" stroke="{color}" stroke-width="{w*3}" stroke-linecap="round"/></g>' for a in range(0, 360, 60))
    return arms


def santa_hat():
    return (f'<path d="M14,92 C20,50 50,18 86,20 C100,22 108,34 104,50 C96,40 84,38 76,46 C70,60 82,80 94,92 Z" {s(N["red"])}/>'
            f'<rect x="6" y="84" width="96" height="22" rx="11" {s("#FFFFFF")}/>'
            f'<circle cx="104" cy="54" r="12" {s("#FFFFFF")}/>')


def holly():
    leaf = 'M0,0 q10,-12 22,-8 q-2,6 4,10 q-8,4 -4,10 q-12,2 -22,-12 z'
    return (place(f'<path d="{leaf}" {s(N["green"])}/>', 60, 62, 1.8, -150)
            + place(f'<path d="{leaf}" {s(N["green"])}/>', 60, 62, 1.8, -30)
            + f'<circle cx="54" cy="58" r="7" {s(N["red"])}/><circle cx="66" cy="58" r="7" {s(N["red"])}/><circle cx="60" cy="68" r="7" {s(N["red"])}/>')


def garland(width, sag=18, step=70):
    pts, bulbs, cols = [], [], [N["red"], N["gold"], "#2E86DE", N["green"]]
    x, i = 0, 0
    d = f"M0,4"
    while x < width:
        d += f" Q{x+step/2},{4+sag*2} {x+step},4"
        bulbs.append((x + step / 2, 4 + sag, cols[i % 4]))
        x += step
        i += 1
    out = f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>'
    out += f'<path d="{d}" fill="none" stroke="{N["green"]}" stroke-width="3" stroke-dasharray="2 5"/>'
    for bx, by, c in bulbs:
        out += f'<ellipse cx="{bx}" cy="{by+9}" rx="6" ry="9" {s(c, "stroke-width=\'2.5\'")}/><rect x="{bx-4}" y="{by-2}" width="8" height="5" fill="{N["gold"]}" stroke="{INK}" stroke-width="2"/>'
    return out


def reindeer(lead=False):
    b = "#9A6239"
    nose = N["red"] if lead else INK
    return (f'<path d="M30,72 l-6,34 M40,74 l2,32 M66,74 l-2,32 M76,70 l8,34" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
            f'<ellipse cx="52" cy="62" rx="32" ry="17" {s(b)}/>'
            f'<path d="M74,56 L88,30" stroke="{INK}" stroke-width="16" stroke-linecap="round"/><path d="M74,56 L88,30" stroke="{b}" stroke-width="9" stroke-linecap="round"/>'
            f'<ellipse cx="96" cy="28" rx="15" ry="10" {s(b)}/>'
            f'<path d="M88,20 l-6,-14 l-6,4 M82,6 l4,-6 M96,18 l2,-14 l6,-4 M98,8 l-6,-6" fill="none" stroke="{INK}" stroke-width="3.5" stroke-linecap="round"/>'
            f'<circle cx="110" cy="30" r="5.5" {s(nose)}/><circle cx="96" cy="25" r="2.4" fill="{INK}"/>'
            f'<path d="M22,56 l-10,-6" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>')


def sleigh():
    return (f'<path d="M6,104 H118 q12,0 12,-12" fill="none" stroke="{N["gold"]}" stroke-width="7" stroke-linecap="round"/>'
            f'<path d="M6,104 H118 q12,0 12,-12" fill="none" stroke="{INK}" stroke-width="2"/>'
            f'<path d="M28,104 v-12 M98,104 v-12" stroke="{INK}" stroke-width="5"/>'
            # Santa
            f'<circle cx="58" cy="40" r="22" {s(N["red"])}/><circle cx="60" cy="22" r="12" {s(N["skin"])}/>'
            f'<path d="M48,24 q12,22 24,0 q2,14 -12,18 q-14,-4 -12,-18z" {s("#FFFFFF")}/>'
            f'<path d="M46,16 q14,-22 30,-4 l6,10" {s(N["red"])}/><circle cx="84" cy="24" r="5" {s("#FFFFFF")}/>'
            f'<rect x="44" y="12" width="32" height="7" rx="3.5" {s("#FFFFFF")}/>'
            # sack
            f'<path d="M84,58 q-4,-30 18,-34 q16,4 8,34z" {s(N["brown"])}/>'
            # body
            f'<path d="M2,50 q6,40 40,42 H112 q14,0 14,-20 V52 H30 q-10,0 -14,-12z" {s(N["red"])}/>'
            f'<path d="M30,62 H118" stroke="{N["gold"]}" stroke-width="4"/>')


def sleigh_team():
    """360x120: two reindeer and the sleigh, facing right (moves left to right)."""
    reins = f'<path d="M200,70 C170,50 140,60 120,48 C100,58 80,50 60,48" fill="none" stroke="{N["darkred"]}" stroke-width="3"/>'
    return place(sleigh(), 214, 0, 1.0) + reins + place(reindeer(False), 110, 4, 0.95) + place(reindeer(True), 0, 4, 0.95, flip=False)


def sleigh_team_rtl():
    return place(sleigh_team(), 360, 0, 1.0, flip=True)


def elf(carry="ornament"):
    g = "#2F8F46"
    out = (f'<path d="M44,112 l2,-14 M76,112 l-2,-14" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>'
           f'<path d="M36,100 Q60,46 84,100 Z" {s(g)}/><rect x="40" y="84" width="40" height="7" {s(INK)}/>'
           f'<rect x="56" y="84" width="8" height="7" fill="{N["gold"]}"/>'
           f'<polygon points="34,44 26,34 36,40" {s(N["skin"])}/><polygon points="86,44 94,34 84,40" {s(N["skin"])}/>'
           f'<circle cx="60" cy="48" r="17" {s(N["skin"])}/>'
           f'<circle cx="54" cy="47" r="2.3" fill="{INK}"/><circle cx="66" cy="47" r="2.3" fill="{INK}"/>'
           f'<path d="M54,55 q6,5 12,0" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round"/>'
           f'<path d="M40,38 Q50,0 92,6 Q74,14 80,36 Z" {s(N["red"])}/><circle cx="94" cy="8" r="6" {s("#FFFFFF")}/>'
           f'<rect x="38" y="32" width="44" height="9" rx="4.5" {s("#FFFFFF")}/>')
    if carry == "ornament":
        out += place(ornament(N["gold"]), 74, 62, 0.32)
    elif carry == "box":
        out += f'<rect x="70" y="70" width="40" height="30" rx="2" {s("#C9A26B")}/><path d="M70,80 H110" stroke="{INK}" stroke-width="2"/>' \
               + place(ornament(N["red"]), 72, 52, 0.18) + place(ornament("#2E86DE"), 86, 50, 0.18)
    return out


# ---------- Samain ----------
def pumpkin(face=True):
    o = S["pumpkin"]
    out = (f'<path d="M58,30 q-2,-14 8,-22" fill="none" stroke="{S["green"]}" stroke-width="8" stroke-linecap="round"/>'
           f'<ellipse cx="34" cy="70" rx="26" ry="38" {s(o)}/><ellipse cx="86" cy="70" rx="26" ry="38" {s(o)}/>'
           f'<ellipse cx="60" cy="70" rx="26" ry="42" {s(S["orange"])}/>')
    if face:
        out += (f'<polygon points="36,58 50,58 43,46" fill="{INK}"/><polygon points="70,58 84,58 77,46" fill="{INK}"/>'
                f'<path d="M30,76 Q60,104 90,76 L82,80 L76,74 L68,82 L60,74 L52,82 L44,74 L38,80Z" fill="{INK}"/>')
    return out


def bat(color=None):
    c = color or S["night"]
    wing = "M60,56 C54,40 36,34 6,40 C14,46 16,54 12,62 C22,56 30,60 32,70 C40,62 50,64 56,72 Z"
    return (f'<path d="{wing}" {s(c)}/><path d="{wing}" transform="translate(120,0) scale(-1,1)" {s(c)}/>'
            f'<ellipse cx="60" cy="62" rx="9" ry="13" {s(c)}/><polygon points="53,52 55,42 59,50" {s(c)}/><polygon points="67,52 65,42 61,50" {s(c)}/>'
            f'<circle cx="56.5" cy="57" r="2" fill="{S["bolt"]}"/><circle cx="63.5" cy="57" r="2" fill="{S["bolt"]}"/>')


def ghost():
    return (f'<path d="M28,108 L28,52 A32,32 0 0 1 92,52 L92,108 L82,98 L72,108 L60,98 L48,108 L38,98 Z" {s(S["ghost"])}/>'
            f'<ellipse cx="48" cy="54" rx="5" ry="8" fill="{INK}"/><ellipse cx="72" cy="54" rx="5" ry="8" fill="{INK}"/>'
            f'<ellipse cx="60" cy="74" rx="6" ry="8" fill="{INK}"/><path d="M92,70 q12,-4 16,-16" fill="none" stroke="{INK}" stroke-width="{SW}" stroke-linecap="round"/>')


def witch(sweeping=False):
    p = S["purple"]
    broom = (f'<path d="M8,{86 if not sweeping else 60} L116,{62 if not sweeping else 110}" stroke="{INK}" stroke-width="9" stroke-linecap="round"/>'
             f'<path d="M8,{86 if not sweeping else 60} L116,{62 if not sweeping else 110}" stroke="{S["brown"]}" stroke-width="4.5" stroke-linecap="round"/>')
    if sweeping:
        straw = f'<path d="M104,104 L126,96 L132,122 L100,124 Z" {s(S["bolt"])}/><path d="M108,110 l20,-4 M106,116 l24,-2" stroke="{INK}" stroke-width="2"/>'
    else:
        straw = f'<path d="M0,70 L-26,62 L-28,96 L4,90 Z" transform="translate(14,4)" {s(S["bolt"])}/>'
    body = (f'<path d="M40,80 Q44,40 66,40 Q86,44 84,78 Z" {s(p)}/>'
            f'<path d="M44,78 q-10,14 -20,10 q10,-6 12,-16" {s(p)}/>'
            f'<circle cx="66" cy="34" r="12" {s(S["skin"])}/>'
            f'<circle cx="70" cy="32" r="2" fill="{INK}"/>'
            f'<path d="M56,26 q-10,10 -8,22 M58,30 q-6,10 -2,20" fill="none" stroke="{S["orange"]}" stroke-width="4" stroke-linecap="round"/>'
            f'<ellipse cx="64" cy="24" rx="22" ry="5" {s(S["night"])}/>'
            f'<path d="M50,22 L60,-6 Q64,-10 66,-4 L72,10 L80,22 Z" {s(S["night"])}/>'
            f'<path d="M52,18 H78" stroke="{S["orange"]}" stroke-width="4"/>'
            f'<path d="M80,52 L96,{64 if not sweeping else 84}" stroke="{INK}" stroke-width="8" stroke-linecap="round"/>')
    return broom + straw + body


def web(size=120, color=INK, w=1.6):
    import math
    out = ""
    angs = [i * 15 for i in range(0, 7)]
    for a in angs:
        r = math.radians(a)
        out += f'<path d="M0,0 L{size*math.cos(r):.1f},{size*math.sin(r):.1f}" stroke="{color}" stroke-width="{w}"/>'
    for k in (0.25, 0.45, 0.65, 0.85):
        pts = []
        for i, a in enumerate(angs):
            r = math.radians(a)
            pts.append((size * k * math.cos(r), size * k * math.sin(r)))
        d = f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            mx, my = (x0 + x1) / 2 * 0.86, (y0 + y1) / 2 * 0.86
            d += f" Q{mx:.1f},{my:.1f} {x1:.1f},{y1:.1f}"
        out += f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}"/>'
    return out


def candelabra():
    g = N["gold"]
    def candle(x, y):
        return (f'<rect x="{x-6}" y="{y}" width="12" height="28" rx="2" {s("#FFF3D6")}/>'
                f'<path d="M{x},{y-18} q8,10 0,16 q-8,-6 0,-16z" {s(S["bolt"])}/><path d="M{x},{y-10} q3,4 0,7 q-3,-3 0,-7z" fill="{S["orange"]}"/>')
    return (f'<path d="M30,62 q0,16 30,16 q30,0 30,-16" fill="none" stroke="{INK}" stroke-width="9"/><path d="M30,62 q0,16 30,16 q30,0 30,-16" fill="none" stroke="{g}" stroke-width="4.5"/>'
            f'<rect x="56" y="54" width="8" height="52" {s(g)}/><path d="M40,112 q20,-12 40,0 z" {s(g)}/>'
            f'<rect x="24" y="58" width="12" height="6" {s(g)}/><rect x="84" y="58" width="12" height="6" {s(g)}/><rect x="54" y="48" width="12" height="6" {s(g)}/>'
            + candle(30, 30) + candle(90, 30) + candle(60, 20))


def lightning():
    return f'<polygon points="70,4 30,64 56,64 42,116 94,46 66,46 84,4" {s(S["bolt"])}/>'


def moon(color=None):
    return f'<circle cx="60" cy="60" r="50" fill="{color or S["moon"]}"/><circle cx="44" cy="44" r="8" fill="#000" fill-opacity="0.08"/><circle cx="74" cy="72" r="12" fill="#000" fill-opacity="0.08"/>'


# ---------- Fête nationale ----------
def marianne():
    st, sh = F["stone"], F["stoneshade"]
    return (f'<rect x="30" y="150" width="100" height="18" rx="3" {s(sh)}/><rect x="40" y="138" width="80" height="14" rx="3" {s(st)}/>'
            f'<path d="M22,140 Q24,100 60,94 L100,94 Q136,100 138,140 Z" {s(st)}/>'
            f'<path d="M40,118 q20,10 40,-6 q18,14 40,6" fill="none" stroke="{sh}" stroke-width="3"/>'
            f'<path d="M68,96 L68,80 L92,80 L92,96" {s(st)}/>'
            f'<path d="M58,52 Q56,86 80,88 Q104,86 102,52 Z" {s(st)}/>'
            f'<path d="M70,64 q4,-3 8,0 M86,64 q4,-3 8,0" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round"/>'
            f'<path d="M80,68 l-3,9 h5" fill="none" stroke="{INK}" stroke-width="2.2" stroke-linecap="round"/>'
            f'<path d="M74,81 q6,4 12,0" fill="#D98A8A" stroke="{INK}" stroke-width="2" stroke-linecap="round"/>'
            # Phrygian cap: soft cone whose tip folds forward, cockade on the side
            f'<path d="M50,60 C44,30 60,10 86,12 C106,14 116,30 110,42 C106,50 96,48 94,40 C100,48 108,52 110,60 Z" {s(F["red"])}/>'
            f'<path d="M50,60 Q80,52 110,60" fill="none" stroke="{INK}" stroke-width="{SW}"/>'
            f'<circle cx="58" cy="52" r="8" {s(F["blue"])}/><circle cx="58" cy="52" r="5.2" fill="#FFFFFF"/><circle cx="58" cy="52" r="2.6" fill="{F["red"]}"/>'
            # long stone hair falling on the shoulders
            f'<path d="M56,60 C48,78 52,96 40,110 C54,108 60,96 62,84 Z" {s(sh)}/>'
            f'<path d="M104,60 C112,78 108,96 120,110 C106,108 100,96 98,84 Z" {s(sh)}/>')


def firework(r=50, colors=None):
    import math
    cols = colors or [F["blue"], "#FFFFFF", F["red"], F["gold"]]
    out = ""
    for i in range(16):
        a = math.radians(i * 22.5)
        c = cols[i % len(cols)]
        x1, y1 = r * 0.35 * math.cos(a), r * 0.35 * math.sin(a)
        x2, y2 = r * math.cos(a), r * math.sin(a)
        out += f'<path d="M{x1:.1f},{y1:.1f} L{x2:.1f},{y2:.1f}" stroke="{c}" stroke-width="4" stroke-linecap="round"/><circle cx="{x2*1.12:.1f}" cy="{y2*1.12:.1f}" r="3" fill="{c}"/>'
    return out


# ---------- All year ----------
def sakura():
    pet = f'<path d="M60,60 C46,40 48,18 60,16 L64,24 L68,16 C80,20 74,42 60,60 Z" {s(Y["sakura"], "stroke-width=\'2.5\'")}/>'
    out = "".join(f'<g transform="rotate({a} 60 60)">{pet}</g>' for a in range(0, 360, 72))
    out += f'<circle cx="60" cy="60" r="7" fill="{Y["sakuradeep"]}"/>'
    out += "".join(f'<circle cx="{60+11*__import__("math").cos(__import__("math").radians(a)):.1f}" cy="{60+11*__import__("math").sin(__import__("math").radians(a)):.1f}" r="2.4" fill="#FFC83D"/>' for a in range(18, 378, 72))
    return out


def sun():
    rays = "".join(f'<g transform="rotate({a} 60 60)"><path d="M60,6 V22" stroke="{INK}" stroke-width="{SW+4}" stroke-linecap="round"/><path d="M60,6 V22" stroke="{Y["sun"]}" stroke-width="{SW}" stroke-linecap="round"/></g>' for a in range(0, 360, 45))
    return rays + f'<circle cx="60" cy="60" r="28" {s(Y["sun"])}/>'


def smiley(face="#FF0000", ink=INK, accessory=None, w=None, hat_ink=True):
    """The HFR redface ':o' on a 100-unit grid, measured on the legacy 180 px Icon-REDFACE
    (legacy-ref, src/cc.swift): ring outer diameter 88 u (156 px), stroke 4.12 u (7.3 px, 4.7 %),
    eyes = semicircles r 7.81 u centred x 36.2 / 63.8 with their tips at y 32.9, mouth = circle
    r 11.8 u centred (50, 63.1). w overrides the stroke."""
    sw = 4.12 if w is None else w
    out = f'<circle cx="50" cy="50" r="41.94" fill="{face}" stroke="{ink}" stroke-width="{sw}"/>'
    out += (f'<path d="M28.39,32.9 a7.81,7.81 0 0 0 15.62,0 M55.99,32.9 a7.81,7.81 0 0 0 15.62,0" fill="none" stroke="{ink}" stroke-width="{sw}" stroke-linecap="round"/>'
            f'<circle cx="50" cy="63.1" r="11.8" fill="none" stroke="{ink}" stroke-width="{sw}"/>')
    if accessory == "sunglasses":
        out += (f'<path d="M14,34 H86" stroke="{INK}" stroke-width="4"/>'
                f'<rect x="24" y="28" width="24" height="17" rx="7" fill="{INK}"/><rect x="52" y="28" width="24" height="17" rx="7" fill="{INK}"/>'
                f'<rect x="28" y="31" width="8" height="4" rx="2" fill="#FFFFFF" fill-opacity="0.5"/><rect x="56" y="31" width="8" height="4" rx="2" fill="#FFFFFF" fill-opacity="0.5"/>')
    if accessory == "scarf":
        out += (f'<path d="M14,80 Q50,98 86,80 L88,92 Q50,110 12,92 Z" fill="{Y["scarf"]}" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>'
                f'<path d="M30,88 l2,10 M46,92 l0,10 M62,92 l-1,10" stroke="#FFFFFF" stroke-width="4"/>'
                f'<path d="M66,94 L76,124 L92,120 L80,90 Z" fill="{Y["scarf"]}" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>'
                f'<path d="M70,104 l12,-3 M74,114 l12,-3" stroke="#FFFFFF" stroke-width="4"/>')
    if accessory == "santa":
        out += place(santa_hat(), 18, -36, 0.55, -10)
    return out
