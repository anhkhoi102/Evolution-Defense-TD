"""App icon artwork: a floating meadow island with an evolved (level-5) tower,
a stretch of road, trees, rocks and a wolf on the way in. Same kits, palette
grade and lighting as the game art. Rendered on transparency; the macOS icon
shape and background are added by Tools/bake/compose_icon.py.

  out/icon/island.png   (2048 × 2048, transparent)

blender -b --factory-startup -P render_icon.py
"""
import bmesh, bpy, math, os, random, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(__file__))
import rig

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "out", "icon")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "sources")
TDK = os.path.join(SRC, "kenney-tower-defense-kit", "Models", "GLB format")
NAT = os.path.join(SRC, "kenney-nature-kit", "Models", "GLTF format")
UAA = os.path.join(SRC, "quaternius-ultimateanimatedanimals", "Ultimate Animated Animals - July 2021", "glTF")


def T(n): return os.path.join(TDK, n + ".glb")
def N(n): return os.path.join(NAT, n + ".glb")
def lin(c): return tuple(rig._lin(x) for x in c) + (1,)


def material(name, color, rough=0.85, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(color)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = lin(color)
        b.inputs["Emission Strength"].default_value = emit
    return m


def place(path, loc, rot=0.0, scale=1.0):
    r = rig.instance(path)
    r.location = loc
    r.rotation_euler.z = rot
    r.scale = (scale, scale, scale)
    bpy.context.view_layer.update()
    return r


def objs_of(root):
    return [root] + list(root.children_recursive)


# ------------------------------------------------------------------ scene
s = rig.reset()
s.cycles.samples = 128
s.render.resolution_x = s.render.resolution_y = 2048
random.seed(7)

TOP_R, TOP_Z, SIDES = 1.55, 0.0, 11


def island():
    """Low-poly floating island: grassy cap, dirt rim, rocky cone underneath."""
    bm = bmesh.new()
    rings = [  # (radius, z, material index)
        (TOP_R, TOP_Z, 0), (TOP_R * 1.02, -0.10, 1), (TOP_R * 0.95, -0.32, 1),
        (TOP_R * 0.78, -0.62, 2), (TOP_R * 0.52, -1.00, 2), (TOP_R * 0.24, -1.42, 2),
    ]
    verts = []
    for i, (r, z, _) in enumerate(rings):
        ring = []
        for k in range(SIDES):
            a = k / SIDES * math.tau + (0.13 * i)
            j = 1 + (random.uniform(-0.07, 0.07) if i > 0 else random.uniform(-0.03, 0.03))
            zz = z + (random.uniform(-0.05, 0.05) if i > 1 else 0)
            ring.append(bm.verts.new((math.cos(a) * r * j, math.sin(a) * r * j, zz)))
        verts.append(ring)
    tip = bm.verts.new((0.05, -0.04, -1.85))
    top = bm.faces.new(verts[0]); top.material_index = 0
    for i in range(len(rings) - 1):
        for k in range(SIDES):
            f = bm.faces.new((verts[i][k], verts[i][(k + 1) % SIDES], verts[i + 1][(k + 1) % SIDES], verts[i + 1][k]))
            f.material_index = 0 if i == 0 else rings[i + 1][2]
    for k in range(SIDES):
        f = bm.faces.new((verts[-1][k], verts[-1][(k + 1) % SIDES], tip)); f.material_index = 2
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Island"); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new("Island", me)
    s.collection.objects.link(o)
    for m in (material("Grass", (0.40, 0.66, 0.27)), material("Dirt", (0.47, 0.33, 0.21)), material("Rock", (0.42, 0.37, 0.33))):
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = False
    return o


def road():
    """Dirt road curving across the cap (the defended path)."""
    pts = [(-1.52, -0.40), (-0.8, -0.58), (-0.1, -0.32), (0.5, -0.55), (0.85, -0.90), (0.93, -0.98)]
    samples = []
    spl = [Vector((x, y, 0)) for x, y in pts]
    for i in range(len(spl) - 1):
        for t in range(8):
            u = t / 8
            p0, p1 = spl[i], spl[i + 1]
            pm = spl[i - 1] if i > 0 else p0
            pn = spl[i + 2] if i + 2 < len(spl) else p1
            # Catmull-Rom
            q = 0.5 * ((2 * p0) + (-pm + p1) * u + (2 * pm - 5 * p0 + 4 * p1 - pn) * u * u + (-pm + 3 * p0 - 3 * p1 + pn) * u ** 3)
            samples.append(q)
    samples.append(spl[-1])
    bm = bmesh.new()
    left, right = [], []
    for i, p in enumerate(samples):
        a = samples[min(i + 1, len(samples) - 1)] - samples[max(i - 1, 0)]
        n = Vector((-a.y, a.x, 0)).normalized()
        w = 0.21
        left.append(bm.verts.new(p + n * w + Vector((0, 0, TOP_Z + 0.006))))
        right.append(bm.verts.new(p - n * w + Vector((0, 0, TOP_Z + 0.006))))
    for i in range(len(samples) - 1):
        bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
    me = bpy.data.meshes.new("RoadMesh"); bm.to_mesh(me); bm.free()
    r = bpy.data.objects.new("Road", me); s.collection.objects.link(r)
    me.materials.append(material("Road", (0.66, 0.50, 0.33)))
    return r


isl = island()
road()

# Evolved tower: level-5 stone base with the glowing crystal crown.
z = TOP_Z
tower = []
for part in ["tower-round-bottom-c", "tower-round-crystals"]:
    r = place(T(part), (0.30, 0.38, z), 0.4, 1.25)
    o = objs_of(r)
    tower += o
    z = rig.bounds(o)[1].z
crown_z = z
# Make the crystals glow (the kit's crystal material) and add a soft cyan light.
for o in tower:
    for sl in getattr(o, "material_slots", []):
        m = sl.material
        if m and m.node_tree and ("crystal" in m.name.lower() or "purple" in m.name.lower() or "blue" in m.name.lower()):
            b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if b:
                b.inputs["Emission Color"].default_value = lin((0.35, 0.92, 1.0))
                b.inputs["Emission Strength"].default_value = 2.2
bpy.ops.object.light_add(type="POINT", location=(0.30, 0.20, crown_z - 0.15))
lt = bpy.context.active_object; lt.data.energy = 160; lt.data.color = (0.45, 0.9, 1.0); lt.data.shadow_soft_size = 0.4

# Trees and rocks around the rim (behind and to the sides, never in front of the tower).
for path, loc, rot, sc in [
    (N("tree_default"), (-0.75, 0.95, 0), 0.3, 1.0), (N("tree_oak"), (-0.25, 1.05, 0), 1.2, 1.1),
    (N("tree_default_dark"), (1.05, 0.55, 0), 2.0, 1.0), (N("tree_detailed"), (-1.15, 0.30, 0), 0.8, 0.8),
    (N("rock_largeA"), (0.95, -0.15, 0), 0.5, 0.45), (N("rock_largeC"), (-0.55, 0.25, 0), 1.3, 0.35),
]:
    place(path, loc, rot, sc)

# A wolf trotting along the road towards the tower.
# Skinned models need a real import (linked copies lose their armature binding).
wolf, wobjs = rig.import_model(os.path.join(UAA, "Wolf.gltf"))
wolf.location = (-0.95, -0.60, TOP_Z)
arm = next((o for o in wobjs if o.type == "ARMATURE"), None)
walk = next((a for a in bpy.data.actions if a.name.split("|")[-1] == "Walk"), None)
if arm and walk:
    arm.animation_data_create(); arm.animation_data.action = walk
    try:
        arm.animation_data.action_slot = walk.slots[0]
    except Exception:
        pass
    s.frame_set(int(walk.frame_range[0] + 6))
bpy.context.view_layer.update()
b = rig.bounds(wobjs); k = 0.78 / max((b[1] - b[0]).x, (b[1] - b[0]).y)
wolf.scale = (k, k, k)
wolf.rotation_euler.z = math.pi / 2 - math.radians(12)   # glTF animals face −y; turn to walk along the road
bpy.context.view_layer.update()

# ------------------------------------------------------------------ camera & light
cam = s.camera
cam.data.type = "ORTHO"
cam.data.ortho_scale = 4.6
elev, azim = math.radians(30), math.radians(-20)
cam.rotation_euler = (math.pi / 2 - elev, 0, azim)
target = Vector((0.05, 0.0, 0.05))
bpy.context.view_layer.update()
back = cam.matrix_world.to_3x3().col[2].normalized()
cam.location = target + back * 30
# Rim light from behind-right for a little "futuristic" edge.
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(60), 0, math.radians(200)))
rim = bpy.context.active_object; rim.data.energy = 1.6; rim.data.color = (0.6, 0.85, 1.0)

rig.render_to(os.path.join(OUT, "island.png"))
print("ICON_DONE")
