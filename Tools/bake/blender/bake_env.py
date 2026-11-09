"""Stage 2 — environment bake.

Renders, with the shared 3/4 camera and light rig:
  out/env/background.png      the playfield diorama (ground, road, ground props, filler forest)
  out/env/deco_<kind>_<n>.png  depth-sorted decoration sprites (trees/pines in front of gameplay)
  out/env/slot*.png, spawn.png, base_<era>.png
  out/env/env.json            sizes + anchors for the manifest

Gameplay geometry comes from Tools/bake/map.json (exported by `edtool export-map`),
so the road, pads, spawn and base sit exactly where the simulation expects.

blender -b --factory-startup -P bake_env.py [-- only=<name>]
"""
import bpy, bmesh, json, math, os, random, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(__file__))
import rig

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUT = os.path.join(ROOT, "out", "env")
os.makedirs(OUT, exist_ok=True)
MAP = json.load(open(os.path.join(ROOT, "map.json")))
U = MAP["tileSize"]                     # points per unit
NAT = os.path.join(ROOT, "sources", "kenney-nature-kit", "Models", "GLTF format")
CAS = os.path.join(ROOT, "sources", "kenney-castle-kit", "Models", "GLB format")
TDK = os.path.join(ROOT, "sources", "kenney-tower-defense-kit", "Models", "GLB format")
SPC = os.path.join(ROOT, "sources", "kenney-space-kit", "Models", "GLTF format")
OY = 50.0                               # screen y of world y=0 (points)
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = next((a.split("=", 1)[1] for a in argv if a.startswith("only=")), None)
SPEC = {}
spec_path = os.path.join(OUT, "env.json")
if os.path.exists(spec_path):
    SPEC = json.load(open(spec_path))


def w2u(p):
    return Vector((p["x"] / U, p["y"] / U, 0))


PATH = [w2u(p) for p in MAP["path"]]
SLOTS = [w2u(s) for s in MAP["slots"]]
SPAWN, BASE = w2u(MAP["spawn"]), w2u(MAP["base"])
PATH_W = MAP["pathWidth"] / U


def dist_to_path(p):
    best = 1e9
    for a, b in zip(PATH, PATH[1:]):
        ab = b - a
        t = max(0, min(1, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
        best = min(best, (a + ab * t - p).length)
    return best


# ---------------------------------------------------------------- materials

def mat(name, base, rough=0.85, noise=None, emission=None):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    lin = lambda c: tuple(rig._lin(x) for x in c) + (1,)
    if noise:
        # Two-tone noise in object space (units = tiles) for organic variation.
        coord = nt.nodes.new("ShaderNodeTexCoord")
        tex = nt.nodes.new("ShaderNodeTexNoise")
        nt.links.new(coord.outputs["Object"], tex.inputs["Vector"])
        tex.inputs["Scale"].default_value = noise[2]
        tex.inputs["Detail"].default_value = 3
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = lin(noise[0])
        ramp.color_ramp.elements[1].color = lin(noise[1])
        ramp.color_ramp.elements[0].position = 0.35
        ramp.color_ramp.elements[1].position = 0.7
        nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = lin(base)
    if emission:
        bsdf.inputs["Emission Color"].default_value = lin(emission[0])
        bsdf.inputs["Emission Strength"].default_value = emission[1]
    return m


def hexc(h):
    return ((h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255)


GRASS = lambda: mat("Grass", None, noise=(hexc(0x4F8634), hexc(0x6FA445), 0.22))
DIRT = lambda: mat("Dirt", None, rough=0.95, noise=(hexc(0x9C7A50), hexc(0xB8946A), 0.9))
DIRT_EDGE = lambda: mat("DirtEdge", hexc(0x6E5A3A), rough=1.0)


# ---------------------------------------------------------------- helpers

def place(path, loc=(0, 0, 0), rot=0.0, scale=1.0):
    root = rig.instance(path)
    objs = [root]
    root.location = loc
    root.rotation_euler.z = rot
    root.scale = (scale, scale, scale)
    return root, objs


def plane(x0, y0, x1, y1, z, material, name="Plane"):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(material)
    return o


def ribbon(points, width, z, material, corner_r=0.5, name="Road"):
    """Flat strip along a polyline with rounded (filleted) corners."""
    pts = [points[0]]
    for a, b, c in zip(points, points[1:], points[2:]):
        d1, d2 = (b - a).normalized(), (c - b).normalized()
        r = min(corner_r, (b - a).length / 2, (c - b).length / 2)
        p0, p1 = b - d1 * r, b + d2 * r
        for i in range(9):          # quadratic Bézier fillet
            t = i / 8
            pts.append(p0 * (1 - t) ** 2 + b * 2 * (1 - t) * t + p1 * t * t)
    pts.append(points[-1])
    clean = [pts[0]]
    for p in pts[1:]:
        if (p - clean[-1]).length > 1e-3:
            clean.append(p)
    pts = clean
    verts, faces = [], []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = Vector((-d.y, d.x, 0))
        verts += [tuple(p + n * width / 2 + Vector((0, 0, z))), tuple(p - n * width / 2 + Vector((0, 0, z)))]
        if i:
            k = 2 * i
            faces.append((k - 2, k - 1, k + 1, k))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(material)
    return o, pts


def nat(name):
    return os.path.join(NAT, name + ".glb")


def free_spot(p, clear_path=1.0, clear_pads=1.0):
    if dist_to_path(p) < PATH_W / 2 + clear_path:
        return False
    if any((p - s).length < clear_pads for s in SLOTS + [SPAWN, BASE]):
        return False
    return True


# ---------------------------------------------------------------- background

TREES = ["tree_default", "tree_oak", "tree_detailed", "tree_fat", "tree_tall", "tree_simple"]
PINES = ["tree_pineRoundA", "tree_pineRoundC", "tree_pineTallA_detailed", "tree_pineDefaultA", "tree_pineRoundE"]


def bake_background():
    s = rig.reset()
    s.cycles.samples = 64
    s.render.film_transparent = False
    w, h = MAP["worldSize"]["width"], MAP["worldSize"]["height"]
    g = plane(-4, -6, w / U + 4, 24, 0, GRASS(), "Ground")
    # Large soft light/dark patches so the meadow isn't one flat colour.
    nt = g.data.materials[0].node_tree
    bsdf = nt.nodes["Principled BSDF"]
    ramp_out = bsdf.inputs["Base Color"].links[0].from_socket
    coord = nt.nodes.new("ShaderNodeTexCoord")
    big = nt.nodes.new("ShaderNodeTexNoise")
    big.inputs["Scale"].default_value = 0.07
    nt.links.new(coord.outputs["Object"], big.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    nt.links.new(big.outputs["Fac"], mix.inputs["Factor"])
    nt.links.new(ramp_out, mix.inputs["A"])
    mix.inputs["B"].default_value = (0.72, 0.8, 0.55, 1)
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    # Same corner radius for both strips (concentric arcs), larger than the half
    # width so the inner edge never folds over itself.
    R = PATH_W / 2 + 0.4
    edge, _ = ribbon(PATH, PATH_W + 0.22, 0.004, DIRT_EDGE(), corner_r=R, name="RoadEdge")
    road, road_pts = ribbon(PATH, PATH_W, 0.008, DIRT(), corner_r=R)
    rng = random.Random(MAP.get("id", "map") + "-env")

    # Road edge detail: small flat stones and grass tufts along both sides.
    for i in range(1, len(road_pts)):
        a, b = road_pts[i - 1], road_pts[i]
        seg = (b - a)
        L = seg.length
        if L < 1e-4:
            continue
        d = seg / L
        n = Vector((-d.y, d.x, 0))
        t = 0.0
        while t < L:
            p = a + d * t
            for side in (-1, 1):
                q = p + n * side * (PATH_W / 2 + rng.uniform(0.02, 0.18))
                r = rng.random()
                if r < 0.35:
                    place(nat(rng.choice(["stone_smallFlatA", "stone_smallFlatB", "rock_smallFlatA", "stone_smallA"])),
                          q, rng.uniform(0, 6.28), rng.uniform(0.35, 0.6))
                elif r < 0.75 and free_spot(q, 0.05, 0.6):
                    place(nat(rng.choice(["grass", "grass_large", "grass_leafs"])), q, rng.uniform(0, 6.28), rng.uniform(0.5, 0.8))
            t += rng.uniform(0.35, 0.7)
        # A few pebbles on the road itself.
        if rng.random() < 0.5:
            q = a + d * rng.uniform(0, L) + n * rng.uniform(-PATH_W * 0.3, PATH_W * 0.3)
            place(nat(rng.choice(["rock_smallA", "rock_smallB", "rock_smallFlatC"])), q, rng.uniform(0, 6.28), 0.25)

    # Map decorations that stay on the ground (trees/pines become sprites).
    for d in MAP["decorations"]:
        p, k, sc = w2u(d), d["kind"], d["scale"]
        if k == "rock":
            place(nat(rng.choice(["rock_smallA", "rock_smallC", "rock_smallE", "stone_smallB", "stone_smallD"])), p, rng.uniform(0, 6.28), 0.9 * sc)
        elif k == "boulder":
            place(nat(rng.choice(["rock_largeA", "rock_largeC", "rock_largeE", "stone_largeB"])), p, rng.uniform(0, 6.28), 0.75 * sc)
        elif k == "bush":
            place(nat(rng.choice(["plant_bush", "plant_bushLarge", "plant_bushDetailed", "plant_bushSmall"])), p, rng.uniform(0, 6.28), 0.9 * sc)
        elif k == "flowers":
            for _ in range(3):
                q = p + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.25, 0.25), 0))
                place(nat(rng.choice(["flower_redA", "flower_yellowA", "flower_purpleA", "flower_yellowB", "flower_redB"])), q, rng.uniform(0, 6.28), 0.7)

    # Extra ground detail: grass tufts, mushrooms, small stones (clear of road/pads).
    for _ in range(420):
        p = Vector((rng.uniform(-0.5, w / U + 0.5), rng.uniform(-1.5, h / U + 0.8), 0))
        if not free_spot(p, 0.35, 0.75):
            continue
        r = rng.random()
        name = (rng.choice(["grass", "grass_large", "grass_leafs", "grass_leafsLarge"]) if r < 0.7 else
                rng.choice(["mushroom_red", "mushroom_tanGroup", "stone_smallC", "rock_smallFlatB", "stump_round"]))
        place(nat(name), p, rng.uniform(0, 6.28), rng.uniform(0.55, 0.9))

    # Filler forest beyond the top edge (always behind gameplay, so it can be baked).
    for _ in range(140):
        p = Vector((rng.uniform(-1.5, w / U + 1.5), rng.uniform(h / U + 0.6, h / U + 4.5), 0))
        place(nat(rng.choice(TREES + PINES + PINES)), p, rng.uniform(0, 6.28), rng.uniform(1.3, 1.8))
    # Low shrubs along the bottom edge (in front, but too low to hide anything).
    for _ in range(70):
        p = Vector((rng.uniform(-1, w / U + 1), rng.uniform(-1.9, -0.9), 0))
        place(nat(rng.choice(["plant_bushLarge", "plant_bush", "rock_largeB", "plant_bushDetailed"])), p, rng.uniform(0, 6.28), rng.uniform(0.8, 1.2))

    rig.frame_camera(w, h, anchor=(0, OY / h), target=(0, 0, 0))
    rig.render_to(os.path.join(OUT, "background.png"))
    SPEC["background"] = {"size": [w, h], "anchor": [0, 0]}


# ---------------------------------------------------------------- sprites

def render_sprite(name, build, w, h, anchor=(0.5, 0.25), samples=48):
    s = rig.reset()
    s.cycles.samples = samples
    rig.shadow_catcher(12)
    build()
    rig.frame_camera(w, h, anchor=anchor, target=(0, 0, 0))
    rig.render_to(os.path.join(OUT, name + ".png"))
    SPEC[name] = {"size": [w, h], "anchor": list(anchor)}


def tree_sprites():
    for kind, models, scale in [("tree", TREES, 1.55), ("pine", PINES, 1.5)]:
        for i, m in enumerate(models):
            render_sprite(f"deco_{kind}_{i}", lambda m=m, scale=scale: place(nat(m), (0, 0, 0), 0.4, scale), 90, 120, (0.5, 0.18))


def slot_sprites():
    def pad(highlight):
        def build():
            bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.62, depth=0.06, location=(0, 0, 0.03))
            bpy.context.active_object.data.materials.append(DIRT())
            rng = random.Random(7)
            for i in range(11):
                a = i / 11 * math.tau + rng.uniform(-0.1, 0.1)
                place(nat(rng.choice(["stone_smallFlatA", "stone_smallFlatB", "stone_smallFlatC"])),
                      (math.cos(a) * 0.6, math.sin(a) * 0.6, 0.02), rng.uniform(0, 6.28), rng.uniform(0.45, 0.6))
            if highlight:
                bpy.ops.mesh.primitive_torus_add(major_radius=0.72, minor_radius=0.035, location=(0, 0, 0.08))
                bpy.context.active_object.data.materials.append(mat("Glow", hexc(0xFFD45A), emission=(hexc(0xFFD45A), 6)))
        return build
    render_sprite("slot", pad(False), 84, 72, (0.5, 0.42))
    render_sprite("slot_highlighted", pad(True), 84, 72, (0.5, 0.42))


def spawn_sprite():
    def build():
        place(nat("cliff_cave_rock"), (-0.25, 0, 0), -math.pi / 2, 1.25)   # opening faces +x (the road)
        for (x, y, m, sc) in [(-0.2, 0.9, "rock_largeB", 0.9), (-0.3, -0.9, "rock_largeD", 0.85), (0.4, 0.95, "rock_tallB", 0.6),
                              (0.35, -0.95, "rock_smallC", 0.8), (-0.8, 0.2, "tree_pineRoundA", 1.3)]:
            place(nat(m), (x, y, 0), 1.3, sc)
    render_sprite("spawn", build, 130, 150, (0.5, 0.32))


def base_sprites():
    def C(n): return os.path.join(CAS, n + ".glb")
    def S(n): return os.path.join(SPC, n + ".glb")

    def primitive():
        for (x, y, m, r, sc) in [(0.05, 0.3, "tent_detailedOpen", -0.4, 0.95), (-0.7, -0.3, "tent_smallClosed", 0.5, 0.85),
                                 (0.65, -0.35, "tent_smallOpen", -1.3, 0.8), (-0.05, -0.55, "campfire_logs", 0, 0.75),
                                 (0.75, 0.55, "log_stack", 1.0, 0.65), (-0.75, 0.6, "tree_pineRoundA", 0, 1.0)]:
            place(nat(m), (x, y, 0), r, sc)
        n = 10
        for i in range(n):                         # palisade ring, gap facing the road (−x)
            a = (i + 0.5) / n * math.tau
            if abs(math.atan2(math.sin(a - math.pi), math.cos(a - math.pi))) < 0.4:
                continue
            place(nat("fence_simpleHigh"), (math.cos(a) * 1.3, math.sin(a) * 1.3, 0), a + math.pi / 2, 0.82)

    def medieval():
        k = 0.72
        for (x, y) in [(-0.85, 0.55), (0.85, 0.55)]:          # corner towers
            place(C("tower-hexagon-base"), (x, y, 0), 0, k)
            place(C("tower-hexagon-mid"), (x, y, 1.0 * k), 0, k)
            place(C("tower-hexagon-roof"), (x, y, 2.0 * k), 0, k)
        place(C("wall"), (0, 0.55, 0), 0, k)                   # back wall
        place(C("tower-square-base"), (0, -0.05, 0), 0, k)    # keep
        place(C("tower-square-mid-windows"), (0, -0.05, 1.0 * k), 0, k)
        place(C("tower-square-top-roof-high"), (0, -0.05, 2.0 * k), 0, k)
        place(C("wall-narrow-gate"), (-0.75, -0.55, 0), math.pi / 2, k)
        place(C("flag-banner-long"), (0.65, -0.6, 0), 0, 0.8)

    def industrial():
        place(C("tower-square-base-color"), (-0.4, 0.25, 0), 0, 0.85)
        place(C("tower-square-mid-color"), (-0.4, 0.25, 0.85), 0, 0.85)
        place(S("chimney_detailed"), (0.55, 0.55, 0), 0, 1.0)
        place(S("chimney"), (0.85, 0.0, 0), 0, 0.9)
        place(S("machine_generatorLarge"), (0.35, -0.6, 0), 0.4, 0.75)
        place(S("barrels"), (-0.85, -0.65, 0), 0.8, 0.8)
        place(S("pipe_straight"), (0.15, 0.2, 0.0), math.pi / 2, 0.6)
        place(TDK and os.path.join(TDK, "detail-rocks.glb"), (-0.95, 0.75, 0), 0, 0.6)

    def futuristic():
        place(S("platform_large"), (0, 0.05, 0), 0, 0.85)
        place(S("hangar_roundGlass"), (0, 0.2, 0.05), 0, 0.62)
        place(S("satelliteDish_large"), (0.85, 0.7, 0), 2.3, 0.9)
        place(S("machine_wireless"), (-0.9, -0.55, 0), 0.3, 0.9)
        place(S("machine_generator"), (0.8, -0.6, 0), -0.4, 0.85)

    for era, build in [("primitive", primitive), ("medieval", medieval), ("industrial", industrial), ("futuristic", futuristic)]:
        if ONLY and ONLY not in ("bases", "base_" + era):
            continue
        render_sprite("base_" + era, build, 170, 190, (0.5, 0.3))


STEPS = {"background": bake_background, "trees": tree_sprites, "slots": slot_sprites, "spawn": spawn_sprite, "bases": base_sprites}
for name, fn in STEPS.items():
    if ONLY and not (ONLY == name or (name == "bases" and ONLY.startswith("base"))):
        continue
    fn()
    json.dump(SPEC, open(spec_path, "w"), indent=1)
print("ENV_DONE", sorted(SPEC))
