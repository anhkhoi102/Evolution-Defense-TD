"""Shared Blender setup for the Evolution Defense art bake.

One orthographic camera tilted to the game's 3/4 view, one sun + sky fill,
a shadow-catcher ground, transparent film, Standard view transform.
1 Blender unit = 1 map tile = `pointsPerUnit` points; renders are @2x.
"""
import bpy, json, math, os, sys, mathutils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from palette import grade

HERE = os.path.dirname(os.path.abspath(__file__))
VIEW = json.load(open(os.path.join(HERE, "..", "view.json")))
E = math.radians(VIEW["elevationDegrees"])
PPU = VIEW["pointsPerUnit"]
PX = VIEW["pixelScale"]
GROUND_SY = math.sin(E)    # ground depth squash on screen
HEIGHT_SY = math.cos(E)    # how much 1 unit of height moves up the screen


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _done.clear()
    _templates.clear()
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        s.cycles.device = "GPU"
    except Exception:
        s.cycles.device = "CPU"
    s.cycles.samples = 24
    s.cycles.use_denoising = True
    s.cycles.max_bounces = 4
    s.render.film_transparent = True
    s.view_settings.view_transform = "Standard"
    s.view_settings.look = "None"
    s.view_settings.exposure = 0.0
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("Sky")
    s.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.62, 0.72, 0.86, 1)   # cool sky fill
    bg.inputs[1].default_value = 0.55
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.4
    sun.angle = math.radians(6)
    sun.color = (1.0, 0.95, 0.86)
    so = bpy.data.objects.new("Sun", sun)
    az, el = math.radians(VIEW["sunAzimuthDegrees"]), math.radians(VIEW["sunElevationDegrees"])
    # Sun shining from the upper-left of the screen, shadows fall down-right.
    d = mathutils.Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
    so.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    s.collection.objects.link(so)
    cam = bpy.data.cameras.new("Cam")
    cam.type = "ORTHO"
    co = bpy.data.objects.new("Cam", cam)
    s.collection.objects.link(co)
    s.camera = co
    return s


def shadow_catcher(size=6.0):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    p = bpy.context.active_object
    p.name = "ShadowCatcher"
    p.is_shadow_catcher = True
    return p


def frame_camera(width_pt, height_pt, anchor=(0.5, 0.25), target=(0.0, 0.0, 0.0)):
    """Points the camera so that world `target` lands at `anchor` (0…1 from the
    bottom-left) of a width×height point image."""
    s = bpy.context.scene
    cam = s.camera
    s.render.resolution_x = int(round(width_pt * PX))
    s.render.resolution_y = int(round(height_pt * PX))
    cam.data.ortho_scale = max(width_pt, height_pt) / PPU
    cam.rotation_euler = (math.pi / 2 - E, 0, 0)
    bpy.context.view_layer.update()
    m = cam.matrix_world.to_3x3()
    right, up, back = m.col[0].normalized(), m.col[1].normalized(), m.col[2].normalized()
    ux = (anchor[0] - 0.5) * width_pt / PPU
    uy = (anchor[1] - 0.5) * height_pt / PPU
    t = mathutils.Vector(target)
    cam.location = t - right * ux - up * uy + back * 30


def import_model(path):
    before = set(bpy.data.objects)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".blend":
        # Append objects + actions as data only (no scripts run in background mode).
        with bpy.data.libraries.load(path, link=False) as (src, dst):
            dst.objects = [n for n in src.objects]
            dst.actions = [n for n in src.actions]
        for o in dst.objects:
            if o is not None and o.type in {"MESH", "ARMATURE", "EMPTY"}:
                bpy.context.scene.collection.objects.link(o)
    new = [o for o in bpy.data.objects if o not in before]
    # Rigged Kenney/Quaternius models carry an invisible collision sphere.
    for o in list(new):
        if o.type == "MESH" and o.name.lower().startswith("icosphere"):
            new.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
    relink_images(path)
    fix_materials(new)
    remove_inner_shells(new)
    roots = [o for o in new if o.parent is None]
    # Pivot at the footprint centre, ground at z=0 (some Kenney kits are authored
    # off-origin on a 4×4 grid), so every part rotates and places predictably.
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in new if o.type == "MESH" for v in o.data.vertices]
    pivot = bpy.data.objects.new(os.path.basename(path), None)
    bpy.context.scene.collection.objects.link(pivot)
    if pts:
        cx = (min(p.x for p in pts) + max(p.x for p in pts)) / 2
        cy = (min(p.y for p in pts) + max(p.y for p in pts)) / 2
        z0 = min(p.z for p in pts)
    else:
        cx = cy = z0 = 0
    for r in roots:
        r.parent = pivot
        r.location = r.location - mathutils.Vector((cx, cy, z0))
    return pivot, new + [pivot]


def render_to(path):
    s = bpy.context.scene
    s.render.filepath = path
    bpy.ops.render.render(write_still=True)


SRC_DIR = os.path.normpath(os.path.join(HERE, "..", "sources"))
TEX_DIR = os.path.normpath(os.path.join(HERE, "..", "out", "textures"))
_done = set()


def _lin(c):   # sRGB → linear
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _srgb(c):  # linear → sRGB
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def fix_materials(objs):
    """Swaps textures for the graded RGBA copies and grades flat base colours,
    so every pack shares one palette."""
    for o in objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            m = slot.material
            if not m or m.name in _done or not m.node_tree:
                continue
            _done.add(m.name)
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image:
                    p = bpy.path.abspath(n.image.filepath)
                    p = os.path.normpath(p)
                    if p.startswith(SRC_DIR):
                        alt = os.path.join(TEX_DIR, os.path.relpath(p, SRC_DIR))
                        if os.path.exists(alt):
                            n.image = bpy.data.images.load(alt, check_existing=True)
                elif n.type == "BSDF_PRINCIPLED":
                    bc = n.inputs["Base Color"]
                    if not bc.is_linked:
                        r, g, b, a = bc.default_value
                        gr = grade(_srgb(r), _srgb(g), _srgb(b))
                        bc.default_value = (_lin(gr[0]), _lin(gr[1]), _lin(gr[2]), a)
                    n.inputs["Roughness"].default_value = max(0.6, n.inputs["Roughness"].default_value)
                    if "Specular IOR Level" in n.inputs:
                        n.inputs["Specular IOR Level"].default_value = 0.25


def remove_inner_shells(objs):
    """Kenney's tower-defense/castle meshes duplicate surfaces with opposite
    normals (for engines with back-face culling). In a ray tracer the
    coincident twin blocks all light and the surface renders black, so the
    inward-facing twin of every coincident pair is deleted."""
    import bmesh
    for o in objs:
        if o.type != "MESH":
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        centre = sum((v.co for v in bm.verts), mathutils.Vector()) / max(1, len(bm.verts))
        buckets = {}
        for f in bm.faces:
            c = f.calc_center_median()
            key = (round(c.x, 3), round(c.y, 3), round(c.z, 3))
            buckets.setdefault(key, []).append(f)
        dead = []
        for faces in buckets.values():
            if len(faces) < 2:
                continue
            for i, a in enumerate(faces):
                for b in faces[i + 1:]:
                    if a.normal.dot(b.normal) < -0.99:
                        # Keep the face pointing away from the mesh centre.
                        ca = a.calc_center_median() - centre
                        dead.append(a if a.normal.dot(ca) < b.normal.dot(ca) else b)
        if dead:
            bmesh.ops.delete(bm, geom=list(set(dead)), context="FACES")
            bm.to_mesh(o.data)
        bm.free()


_templates = {}


def instance(path):
    """Like import_model, but imports each file once and returns linked copies
    afterwards (fast when scattering hundreds of props)."""
    s = bpy.context.scene
    lib = bpy.data.collections.get("_templates")
    if lib is None or lib.name not in s.collection.children:
        lib = bpy.data.collections.new("_templates")
        s.collection.children.link(lib)
        lib.hide_render = True
        _templates.clear()
    if path not in _templates:
        root, objs = import_model(path)
        for o in objs:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            lib.objects.link(o)
        _templates[path] = root
    src = _templates[path]

    def copy(o, parent):
        c = o.copy()
        s.collection.objects.link(c)
        c.parent = parent
        if parent is not None:
            c.matrix_parent_inverse = o.matrix_parent_inverse.copy()
        for ch in o.children:
            copy(ch, c)
        return c
    root = copy(src, None)
    return root


def bounds(objs):
    """World-space bounds of the evaluated (posed, modified) meshes."""
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        pts += [mw @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    if not pts:
        return None
    mn = mathutils.Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = mathutils.Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def relink_images(model_path):
    """Appended .blend/.fbx files often point at textures by paths that don't
    exist here; find each missing image by file name inside the source pack."""
    src = os.path.normpath(SRC_DIR)
    p = os.path.normpath(os.path.abspath(model_path))
    if not p.startswith(src):
        return
    pack = os.path.join(src, os.path.relpath(p, src).split(os.sep)[0])
    index = None
    for img in bpy.data.images:
        if img.source != "FILE" or img.packed_file is not None:
            continue
        if img.size[0] > 0:
            continue
        name = os.path.basename(bpy.path.abspath(img.filepath).replace("\\", "/"))
        if not name:
            continue
        if index is None:
            index = {}
            for dp, _, fs in os.walk(pack):
                for f in fs:
                    index.setdefault(f.lower(), os.path.join(dp, f))
        hit = index.get(name.lower())
        if hit:
            img.filepath = hit
            img.reload()
