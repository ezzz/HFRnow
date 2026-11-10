"""Blender-rendered illustrations (src/blender/out/*.png) placed in SVG boards and icons.
img("noel_tree", x, y, w=120) returns a <use> of a shared <image id="png-noel_tree">; png_defs(text) returns
the matching <image> definitions embedded as data URIs, so every exported file is self-contained."""
import base64, os, re, struct

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "blender", "out")
_uri = {}


def size(name):
    with open(os.path.join(OUT, name + ".png"), "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def data_uri(name):
    if name not in _uri:
        _uri[name] = "data:image/png;base64," + base64.b64encode(open(os.path.join(OUT, name + ".png"), "rb").read()).decode()
    return _uri[name]


def img(name, x, y, w=None, h=None, rot=0, flip=False, opacity=1.0, filt=None):
    iw, ih = size(name)
    if w is None:
        w = h * iw / ih
    if h is None:
        h = w * ih / iw
    cx, cy = x + w / 2, y + h / 2
    tr = f"rotate({rot} {cx:.1f} {cy:.1f})" + (f" translate({2 * cx:.1f},0) scale(-1,1)" if flip else "")
    tr += f" translate({x:.1f},{y:.1f}) scale({w / iw:.5f},{h / ih:.5f})"
    f = f' filter="url(#{filt})"' if filt else ""
    return f'<use href="#png-{name}" transform="{tr}" opacity="{opacity}"{f}/>'


def png_defs(text):
    names = sorted(set(re.findall(r'href="#png-([A-Za-z0-9_\-]+)"', text)))
    return "".join(f'<image id="png-{n}" width="{size(n)[0]}" height="{size(n)[1]}" href="{data_uri(n)}"/>' for n in names)


def silhouette_filter(fid, color):
    return f'<filter id="{fid}" x="-5%" y="-5%" width="110%" height="110%"><feFlood flood-color="{color}"/><feComposite in2="SourceAlpha" operator="in"/></filter>'
