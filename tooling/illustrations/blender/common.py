"""Shared Blender helpers for the 'digital sketching' pipeline (SwiftHFR illustrations).
Procedural meshes only (no downloaded asset). Look: Freestyle ink lines of varying weight
+ flat cel shading in 3-4 tones (cool blue-grey shadow, warm peach terminator, off-white light).
Run: blender -b -P <subject>.py -- <out.png> [size]"""
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix

INK = (0x2B / 255, 0x2F / 255, 0x3A / 255)


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


# statue palette (THEMES.md §7b, style 1)
STONE = [("#8796A6", 0.0), ("#A9B6C2", 0.16), ("#F2AE8C", 0.40), ("#F7CDB4", 0.50), ("#F4EFE8", 0.60)]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    try:
        sc.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    sc.view_settings.look = "None" if "None" in [i.identifier for i in sc.view_settings.bl_rna.properties["look"].enum_items] else sc.view_settings.look
    sc.render.film_transparent = True
    w = bpy.data.worlds.new("W"); sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (1, 1, 1, 1); bg.inputs[1].default_value = 0.0
    return sc


def toon(name, stops=STONE, flat=None):
    """Cel material: Diffuse -> Shader to RGB -> constant ColorRamp -> Emission. flat = hex for an unshaded accent."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], out.inputs[0])
    if flat:
        em.inputs[0].default_value = srgb(flat)
        return m
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    while len(els) > 1:
        els.remove(els[-1])
    els[0].position = stops[0][1]; els[0].color = srgb(stops[0][0])
    for hx, pos in stops[1:]:
        e = els.new(pos); e.color = srgb(hx)
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], bw.inputs[0])
    nt.links.new(bw.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], em.inputs[0])
    return m


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_from_bm(name, bm):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    return link(bpy.data.objects.new(name, me))


def ell(name, loc, scale, rot=(0, 0, 0), seg=48):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=1.0)
    o = mesh_from_bm(name, bm)
    o.location = loc; o.scale = scale; o.rotation_euler = [math.radians(a) for a in rot]
    return o


def box(name, loc, size, bevel=0.03):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    o = mesh_from_bm(name, bm)
    o.location = loc; o.scale = size
    if bevel:
        m = o.modifiers.new("b", "BEVEL"); m.width = bevel; m.segments = 2
    return o


def cyl(name, loc, r1, r2, depth, rot=(0, 0, 0), seg=64):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=depth)
    o = mesh_from_bm(name, bm)
    o.location = loc; o.rotation_euler = [math.radians(a) for a in rot]
    return o


def tube(name, pts, radii, res=24, bevel_res=6, profile=None):
    """Bezier tube through pts with per-point radius; returns a mesh object."""
    cu = bpy.data.curves.new(name, "CURVE"); cu.dimensions = "3D"
    cu.bevel_depth = 1.0; cu.bevel_resolution = bevel_res; cu.resolution_u = res
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER"); sp.bezier_points.add(len(pts) - 1)
    for bp, p, r in zip(sp.bezier_points, pts, radii):
        bp.co = p; bp.handle_left_type = bp.handle_right_type = "AUTO"; bp.radius = r
    o = link(bpy.data.objects.new(name, cu))
    return to_mesh(o)


def to_mesh(o):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = o; o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    return bpy.context.view_layer.objects.active


def apply_all(o):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = o; o.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def join(objs, name):
    for o in objs:
        apply_all(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active; o.name = name
    return o


def boolean(o, cutter, op="DIFFERENCE"):
    m = o.modifiers.new("bool", "BOOLEAN"); m.object = cutter; m.operation = op; m.solver = "EXACT"
    apply_all(o); bpy.data.objects.remove(cutter)
    return o


def remesh(o, voxel=0.03, smooth=8, factor=0.6):
    m = o.modifiers.new("r", "REMESH"); m.mode = "VOXEL"; m.voxel_size = voxel
    s = o.modifiers.new("s", "SMOOTH"); s.iterations = smooth; s.factor = factor
    apply_all(o)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def shade(o, mat):
    o.data.materials.clear(); o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def sun(rot=(50, 0, -40), strength=4.0):
    l = bpy.data.lights.new("sun", "SUN"); l.energy = strength; l.angle = 0.0
    o = link(bpy.data.objects.new("sun", l)); o.rotation_euler = [math.radians(a) for a in rot]
    return o


def camera(loc, look_at, ortho=None, lens=85):
    c = bpy.data.cameras.new("cam")
    if ortho:
        c.type = "ORTHO"; c.ortho_scale = ortho
    else:
        c.lens = lens
    o = link(bpy.data.objects.new("cam", c)); o.location = loc
    d = Vector(look_at) - Vector(loc)
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = o
    return o


def freestyle(outer=4.2, inner=1.7, crease=138, suggestive=True, min_len=0):
    sc = bpy.context.scene
    sc.render.use_freestyle = True
    sc.render.line_thickness_mode = "ABSOLUTE"
    vl = bpy.context.view_layer
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(crease)
    fs.use_smoothness = True
    fs.use_culling = False
    try:
        fs.kr_derivative_epsilon = 0.6
        fs.sphere_radius = 3.0
    except AttributeError:
        pass
    for ls in list(fs.linesets):
        fs.linesets.remove(ls)

    def lineset(name, thick, **flags):
        ls = fs.linesets.new(name)
        ls.select_by_visibility = True; ls.visibility = "VISIBLE"
        ls.select_by_edge_types = True
        for f in ("select_silhouette", "select_border", "select_crease", "select_contour", "select_external_contour",
                  "select_material_boundary", "select_suggestive_contour", "select_ridge_valley"):
            setattr(ls, f, flags.get(f, False))
        st = bpy.data.linestyles.new("ls_" + name); ls.linestyle = st
        st.color = srgb("#2B2F3A")[:3]; st.thickness = thick; st.thickness_position = "CENTER"
        st.caps = "ROUND"; st.chaining = "SKETCHY" if flags.get("sketchy") else "PLAIN"
        if flags.get("min_len"):
            st.use_length_min = True; st.length_min = flags["min_len"]
        mod = st.thickness_modifiers.new("along", "ALONG_STROKE")
        mod.mapping = "CURVE"; mod.blend = "MULTIPLY"
        c = mod.curve.curves[0]
        c.points[0].location = (0, 0.35); c.points[1].location = (1, 0.35)
        c.points.new(0.5, 1.0)
        mod.curve.update()
        return ls

    lineset("outer", outer, select_external_contour=True, min_len=min_len * 0.6)
    lineset("inner", inner, select_silhouette=True, select_crease=True, select_border=True, select_material_boundary=True,
            select_suggestive_contour=suggestive, min_len=min_len)
    return fs


def render(path, w, h, samples=16):
    sc = bpy.context.scene
    sc.render.resolution_x = w; sc.render.resolution_y = h; sc.render.resolution_percentage = 100
    try:
        sc.eevee.taa_render_samples = samples
    except AttributeError:
        pass
    sc.render.filepath = path
    sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_mode = "RGBA"
    bpy.ops.render.render(write_still=True)


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return a


# ---------------------------------------------------------------- shared conventions for every subject script
def _hex(h):
    h = h.lstrip("#"); return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def _mix(a, b, t):
    A, B = _hex(a), _hex(b)
    return "#%02X%02X%02X" % tuple(round(x + (y - x) * t) for x, y in zip(A, B))


def _scale(a, k):
    return "#%02X%02X%02X" % tuple(min(255, round(x * k)) for x in _hex(a))


def toon_color(name, base, warm=True):
    """Cel ramp for a coloured surface, same grammar as the stone: cool shadow, warm terminator, light = base."""
    shade = _scale(_mix(base, "#A9B6C2", 0.45), 0.86)
    shade2 = _scale(_mix(base, "#8796A6", 0.45), 0.70)
    peach = _mix(base, "#F2AE8C", 0.35) if warm else _scale(base, 0.92)
    return toon(name, [(shade2, 0.0), (shade, 0.12), (peach, 0.27), (base, 0.36)])


def ink_mat():
    m = bpy.data.materials.get("ink")
    return m or toon("ink", flat="#2B2F3A")


def ink_line(name, pts, r=0.012):
    """A drawn ink stroke on a surface: a thin dark tube (for eyelids, lips, strands, folds)."""
    o = tube(name, pts, [r * 0.4] + [r] * (len(pts) - 2) + [r * 0.4], res=16, bevel_res=2)
    return shade(o, ink_mat())


def frame_and_render(out, view=(-0.35, -1.0, 0.30), max_px=900, margin=0.06, roll=0.0, outer=None, inner=None, sun_rot=(50, 0, -30), sun_k=3.2, min_len=None):
    """Orthographic camera fitted to the meshes' bounding box seen from `view`; image aspect follows the subject."""
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.hide_render]
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    ctr = sum(pts, Vector()) / len(pts)
    d = Vector(view).normalized()
    cam_loc = ctr + d * 60   # view = direction from the subject towards the camera
    cam = camera(tuple(cam_loc), tuple(ctr), ortho=1.0)
    cam.rotation_euler.rotate_axis("Z", math.radians(roll))
    bpy.context.view_layer.update()
    inv = cam.matrix_world.inverted()
    loc = [inv @ p for p in pts]
    xs, ys = [p.x for p in loc], [p.y for p in loc]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    cam.location = cam.matrix_world @ Vector((cx, cy, 0))
    span = max(w, h) * (1 + 2 * margin)
    cam.data.ortho_scale = span
    W = max_px if w >= h else max(64, round(max_px * (w + 2 * margin * max(w, h)) / span))
    H = max_px if h >= w else max(64, round(max_px * (h + 2 * margin * max(w, h)) / span))
    sun(rot=sun_rot, strength=sun_k)
    big = max(W, H)
    freestyle(outer=outer or big / 170, inner=inner or big / 520, crease=120, suggestive=True, min_len=min_len or big / 40)
    render(out, W, H, samples=16)
    return W, H


def run_subject(build, default_out):
    a = args()
    out = a[0] if a else default_out
    px = int(a[1]) if len(a) > 1 else 900
    sc = reset()
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.30
    opts = build() or {}
    return frame_and_render(out, max_px=px, **opts)


_MATS = {}


def M(hexcol, warm=True):
    """Cached cel material for a base colour."""
    key = (hexcol, warm)
    if key not in _MATS:
        _MATS[key] = toon_color("c" + hexcol, hexcol, warm)
    return _MATS[key]


def F(hexcol):
    """Cached flat (unshaded) material: glows, flames, the cockade."""
    key = ("flat", hexcol)
    if key not in _MATS:
        _MATS[key] = toon("f" + hexcol, flat=hexcol)
    return _MATS[key]


def clay(objs, name, mat, voxel=0.03, smooth=6, factor=0.5):
    """Join soft primitives and voxel-remesh them into one sculpted volume."""
    o = join(objs, name) if len(objs) > 1 else apply_all(objs[0])
    remesh(o, voxel=voxel, smooth=smooth, factor=factor)
    return shade(o, mat)


def solid(o, mat):
    apply_all(o)
    return shade(o, mat)


def poly_prism(name, pts2d, depth, loc=(0, 0, 0), rot=(90, 0, 0)):
    """Extrude a 2D polygon (x, y) by depth; default rotation stands it up in the XZ plane facing -Y."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, 0)) for x, y in pts2d]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z += depth
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_from_bm(name, bm)
    o.location = loc; o.rotation_euler = [math.radians(a) for a in rot]
    return o


def star2d(n, r1, r2, phase=90):
    return [((r1 if i % 2 == 0 else r2) * math.cos(math.radians(phase + i * 180 / n)),
             (r1 if i % 2 == 0 else r2) * math.sin(math.radians(phase + i * 180 / n))) for i in range(2 * n)]


def decal(name, pts2d, z, target, mat, x=0.0, offset=0.025, front_y=-3.0):
    """A flat 2D shape (x, z) projected along +Y onto `target`'s front surface: eyes, carved mouths, patterns."""
    c = poly_prism(name, [(px + x, pz) for px, pz in pts2d], 0.03, loc=(0, front_y, z), rot=(90, 0, 0))
    apply_all(c)
    bpy.ops.object.select_all(action="DESELECT"); bpy.context.view_layer.objects.active = c; c.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT"); bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.mesh.subdivide(number_cuts=10); bpy.ops.object.mode_set(mode="OBJECT")
    sw = c.modifiers.new("sw", "SHRINKWRAP"); sw.target = target; sw.wrap_method = "PROJECT"
    sw.use_project_y = True; sw.use_negative_direction = True; sw.use_positive_direction = True; sw.offset = offset
    apply_all(c)
    return shade(c, mat)


def proxy(objs_specs, name):
    """Hidden joined copy of ellipsoids used as a shrinkwrap target."""
    o = join([ell(f"{name}{i}", *sp) for i, sp in enumerate(objs_specs)], name)
    o.hide_render = True
    return o


def preamble_out(fname):
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", fname)
