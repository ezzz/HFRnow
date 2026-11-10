"""Art-direction (DA) candidates: the same subjects (Marianne bust, jack-o'-lantern, witch on a
broom) rendered in 5 candidate styles from one layered description. Original drawings only:
the operator's references set the *style*, nothing is traced or reused."""


def ell(cx, cy, rx, ry):
    return f"M{cx-rx},{cy} a{rx},{ry} 0 1 0 {2*rx},0 a{rx},{ry} 0 1 0 {-2*rx},0 Z"


# item = (kind, d, role); kinds: fill (outlined shape), shadow (flat shade inside), line (interior ink)
MARIANNE = [
    ("fill", "M56,202 h88 v16 h-88 z", "stoneShade"),
    ("fill", "M68,190 h64 v12 h-64 z", "stone"),
    ("fill", "M28,192 C30,152 60,132 100,130 C140,132 170,152 172,192 Z", "stone"),
    ("shadow", "M100,132 C140,134 168,152 172,192 L132,192 C136,166 122,146 100,140 Z", "stone"),
    ("fill", "M46,154 L53,149 L124,192 L110,192 Z", "blue"),
    ("fill", "M53,149 L60,144 L138,192 L124,192 Z", "white"),
    ("fill", "M60,144 L67,139 L152,192 L138,192 Z", "red"),
    ("fill", "M86,128 L86,106 L114,106 L114,128 Z", "stone"),
    ("shadow", "M100,108 L114,106 L114,128 L100,124 Z", "stone"),
    ("fill", "M78,70 C70,92 74,112 64,126 C80,122 86,106 86,92 Z", "stone"),
    ("fill", "M122,70 C130,92 126,112 136,126 C120,122 114,106 114,92 Z", "stone"),
    ("fill", ell(100, 82, 22, 28), "stone"),
    ("shadow", "M106,56 C120,62 125,80 120,96 C116,106 108,110 102,110 C111,98 113,76 106,56 Z", "stone"),
    ("fill", "M75,72 C69,44 84,22 108,22 C128,24 140,40 132,54 C128,60 120,58 118,52 C124,62 128,68 126,74 C110,66 90,66 75,72 Z", "cap"),
    ("shadow", "M108,22 C128,24 140,40 132,54 C128,60 120,58 118,52 C122,44 118,30 108,22 Z", "cap"),
    ("fill", ell(84, 64, 6, 6), "blue"), ("fill", ell(84, 64, 3.6, 3.6), "white"), ("fill", ell(84, 64, 1.6, 1.6), "red"),
    ("line", "M89,82 q4,-2.5 8,0 M104,82 q4,-2.5 8,0 M101,85 l-2.5,10 h5 M95,102 q5,2.5 10,0", "ink"),
    ("line", "M58,164 q18,10 28,28 M146,152 q-8,20 -4,40 M96,142 q4,22 0,50 M90,40 q12,10 26,7", "ink"),
]

PUMPKIN = [
    ("fill", "M98,44 C96,28 102,18 114,12 L118,20 C110,26 108,32 110,44 Z", "stem"),
    ("fill", ell(62, 108, 44, 58), "orange"),
    ("fill", ell(138, 108, 44, 58), "orange"),
    ("shadow", "M138,50 C168,58 184,86 182,112 C180,142 166,162 138,166 C160,142 162,82 138,50 Z", "orange"),
    ("fill", ell(100, 108, 46, 66), "orangeLight"),
    ("shadow", "M100,42 C130,46 146,80 146,108 C146,140 130,170 100,174 C122,150 128,80 100,42 Z", "orangeLight"),
    ("fill", "M66,92 L88,74 L92,98 Z", "glow"),
    ("fill", "M134,92 L112,74 L108,98 Z", "glow"),
    ("fill", "M60,122 Q75,128 86,129 L86,140 L98,140 L98,130 Q120,129 140,122 C138,142 124,154 112,156 L112,146 L100,146 L100,158 C78,157 62,144 60,122 Z", "glow"),
    ("line", "M100,44 q-12,64 0,128 M58,52 q-18,56 0,112 M142,52 q18,56 0,112", "ink"),
]

WITCH = [  # flies to the LEFT: head, nose and hat lead, broom straw trails behind (charter rule)
    ("fill", "M196,82 L234,70 L240,120 L204,106 Z", "straw"),
    ("line", "M206,88 l30,-6 M206,96 l32,-2 M206,104 l32,6", "ink"),
    ("fill", "M8,128 L206,88 L210,96 L12,136 Z", "wood"),
    ("fill", "M140,74 C170,72 192,88 202,106 C182,100 162,102 146,112 Z", "purpleDark"),
    ("fill", "M70,122 C66,82 90,64 116,66 C140,70 150,98 146,126 C130,120 100,120 70,122 Z", "purple"),
    ("shadow", "M116,66 C140,70 150,98 146,126 C136,122 126,120 120,120 C130,102 128,82 116,66 Z", "purple"),
    ("fill", "M88,122 L76,142 L62,144 L64,136 L74,134 L80,120 Z", "dark"),
    ("fill", "M86,88 C78,98 72,110 68,120 L76,122 C82,112 90,102 96,94 Z", "purple"),
    ("fill", ell(70, 121, 5, 5), "skin"),
    ("fill", "M88,50 C104,54 112,72 106,92 C102,78 96,68 90,64 Z", "hair"),
    ("fill", ell(78, 58, 16, 16), "skin"),
    ("shadow", "M86,46 C96,54 96,66 88,72 C92,62 92,54 86,46 Z", "skin"),
    ("fill", "M64,56 L50,63 L64,64 Z", "skin"),
    ("fill", "M52,44 C70,38 100,38 120,46 C100,50 72,50 52,44 Z", "hat"),
    ("fill", "M64,42 C70,22 84,6 104,2 C96,16 94,30 100,44 Z", "hat"),
    ("fill", "M66,38 C78,34 92,34 100,38 L100,43 C90,40 78,40 66,43 Z", "band"),
    ("line", "M71,56 l4,0 M67,66 q4,3 8,0 M102,92 q6,14 4,28", "ink"),
]

SUBJECTS = [("Marianne (buste)", MARIANNE, (0, 0, 200, 222)), ("Citrouille", PUMPKIN, (0, 4, 200, 180)), ("Sorcière sur balai", WITCH, (0, 0, 244, 150))]

PAL = {"stone": "#ECE7DD", "stoneShade": "#D3CABC", "blue": "#2B4C9B", "white": "#FFFFFF", "red": "#E5413B", "cap": "#D9443A",
       "stem": "#5E8A3A", "orange": "#E9781A", "orangeLight": "#F59A2E", "glow": "#FFD75A", "straw": "#D9A441", "wood": "#9A6A3A",
       "purple": "#6A3A9A", "purpleDark": "#45246A", "dark": "#2A1A2E", "skin": "#F2C9A3", "hair": "#3A2A2A", "hat": "#2A1A3A",
       "band": "#E9781A", "ink": "#2A2320"}
SKETCH = dict(PAL, stone="#F1ECE4", stoneShade="#DCCFBF", orange="#EE8A33", orangeLight="#F6A548", purple="#6C4A96",
              purpleDark="#4B3570", cap="#D35A4A", blue="#3A5DA8", red="#D9534A")


def _hex(c):
    c = c.lstrip("#"); return [int(c[i:i+2], 16) for i in (0, 2, 4)]


def _mix(c, k, warm=(232, 196, 170)):
    r, g, b = _hex(c)
    return "#%02X%02X%02X" % tuple(int(v * k + w * (1 - k) * 0.35) for v, w in zip((r, g, b), warm))


def _grey(c, lo=150, hi=246):
    r, g, b = _hex(c); y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    v = int(lo + (hi - lo) * y); return "#%02X%02X%02X" % (v, v, v)


STYLES = [
    ("actuel", "1 · Actuel — aplats + encre régulière",
     "Aplats francs, trait d'encre uniforme 3,5 u, pas d'ombre. Très lisible petit, un peu « clipart »."),
    ("croquis", "2 · Croquis numérique (préféré)",
     "Aplats de couleur, 1 ton d'ombre plat à bord net (teinte chaude), trait d'encre propre à épaisseur variable : contour épais, détails fins. Papier blanc cassé."),
    ("lavis", "3 · Encre et lavis gris",
     "Encre noire, valeurs grises en lavis, hachures dans les ombres ; couleur réservée à un accent (cocarde, lueur). Façon carnet de croquis."),
    ("feutre", "4 · Feutre texturé",
     "Couleurs au feutre avec grain, contours légèrement tremblés, ombre portée douce au sol. Chaleureux, plus « fait main »."),
    ("silhouette", "5 · Silhouette + liseré",
     "Formes pleines sombres avec un liseré de lumière ; idéal pour les objets qui traversent (lisibles en mouvement), pauvre en détail."),
]


def render(items, style, uid):
    defs, out = "", ""
    if style == "actuel":
        for k, d, role in items:
            if k == "fill":
                out += f'<path d="{d}" fill="{PAL[role]}" stroke="#1E1A1D" stroke-width="3.5" stroke-linejoin="round"/>'
            elif k == "line":
                out += f'<path d="{d}" fill="none" stroke="#1E1A1D" stroke-width="2.6" stroke-linecap="round"/>'
    elif style == "croquis":
        under = "".join(f'<path d="{d}" fill="none" stroke="#2A2320" stroke-width="5.2" stroke-linejoin="round"/>' for k, d, r in items if k == "fill")
        out += under
        for k, d, role in items:
            if k == "fill":
                out += f'<path d="{d}" fill="{SKETCH[role]}" stroke="#2A2320" stroke-width="1.4" stroke-linejoin="round"/>'
            elif k == "shadow":
                out += f'<path d="{d}" fill="{_mix(SKETCH[role], 0.86)}"/>'
            else:
                out += f'<path d="{d}" fill="none" stroke="#2A2320" stroke-width="1.3" stroke-linecap="round"/>'
    elif style == "lavis":
        defs += (f'<pattern id="h{uid}" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(40)">'
                 f'<path d="M0,0 V5" stroke="#1A1A1A" stroke-width="0.9"/></pattern>')
        for k, d, role in items:
            if k == "fill":
                accent = role in ("blue", "red", "glow")
                fill = PAL[role] if accent else _grey(PAL[role])
                out += f'<path d="{d}" fill="{fill}" stroke="#111" stroke-width="2.2" stroke-linejoin="round"/>'
            elif k == "shadow":
                out += f'<path d="{d}" fill="#7D7D7D" fill-opacity="0.45"/><path d="{d}" fill="url(#h{uid})" opacity="0.55"/>'
            else:
                out += f'<path d="{d}" fill="none" stroke="#111" stroke-width="1.5" stroke-linecap="round"/>'
    elif style == "feutre":
        defs += (f'<filter id="r{uid}"><feTurbulence type="fractalNoise" baseFrequency="0.05" numOctaves="2" seed="4"/>'
                 f'<feDisplacementMap in="SourceGraphic" scale="3"/></filter>'
                 f'<filter id="g{uid}" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="2" result="n"/>'
                 f'<feColorMatrix in="n" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -1.2 0.9" result="a"/>'
                 f'<feComposite in="SourceGraphic" in2="a" operator="in"/></filter>'
                 f'<filter id="b{uid}"><feGaussianBlur stdDeviation="5"/></filter>')
        out += f'<ellipse cx="110" cy="214" rx="70" ry="7" fill="#000" opacity="0.18" filter="url(#b{uid})"/>'
        body = ""
        for k, d, role in items:
            if k == "fill":
                body += f'<path d="{d}" fill="{SKETCH[role]}" stroke="#3A2E2A" stroke-width="2" stroke-linejoin="round"/>'
            elif k == "shadow":
                body += f'<path d="{d}" fill="{_mix(SKETCH[role], 0.8)}" opacity="0.8"/>'
            else:
                body += f'<path d="{d}" fill="none" stroke="#3A2E2A" stroke-width="1.6" stroke-linecap="round"/>'
        out += f'<g filter="url(#r{uid})">{body}</g><g filter="url(#g{uid})" opacity="0.35">{body}</g>'
    elif style == "silhouette":
        under = "".join(f'<path d="{d}" fill="none" stroke="#FFC85A" stroke-width="4" stroke-linejoin="round" transform="translate(-1.5,-1.5)"/>' for k, d, r in items if k == "fill")
        out += under + "".join(f'<path d="{d}" fill="#1E1A2A"/>' for k, d, r in items if k == "fill")
        out += "".join(f'<path d="{d}" fill="{PAL["glow"]}"/>' for k, d, r in items if k == "fill" and r == "glow")
    return defs, out


BG = {"actuel": "#FFFFFF", "croquis": "#FBF7F0", "lavis": "#F3EEE4", "feutre": "#F7F4EE", "silhouette": "linear-gradient(180deg,#3B2A5A,#E77B4A)"}
