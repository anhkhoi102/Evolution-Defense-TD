"""Stage 2 — environment bake.

Renders, with the shared 3/4 camera and light rig:
  out/env/background.png      the playfield diorama (ground, road, ground props, filler forest)
  out/env/deco_<kind>_<n>.png  depth-sorted decoration sprites (trees/pines in front of gameplay)
  out/env/slot*.png, spawn.png, base_<era>.png
  out/env/env.json            sizes + anchors for the manifest

Gameplay geometry comes from Tools/bake/map.json (exported by `edtool export-map`),
so the road, pads, spawn and base sit exactly where the simulation expects.

Other battlefields (Docs/BATTLEFIELDS.md): `-- map=<id>` reads map.<id>.json
(`edtool export-map map.<id>.json <id>`) and writes to out/env/<id>/. The map's
theme picks the environment builder: desert (sand, dunes, rocks, cacti, palms,
ruins; its own pads, spawn and decoration sprites) or lakeside (lakes, shore,
reeds, lilies, a plank bridge; it reuses the grassland sprites).

blender -b --factory-startup -P bake_env.py [-- only=<name>] [map=<id>]
"""
import bpy, bmesh, json, math, os, random, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(__file__))
import rig

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
_argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
MAP_ID = next((a.split("=", 1)[1] for a in _argv if a.startswith("map=")), None)
OUT = os.path.join(ROOT, "out", "env", MAP_ID) if MAP_ID else os.path.join(ROOT, "out", "env")
os.makedirs(OUT, exist_ok=True)
MAP = json.load(open(os.path.join(ROOT, f"map.{MAP_ID}.json" if MAP_ID else "map.json")))
THEME = MAP.get("theme", {})
ENVIRONMENT = THEME.get("environment", "grassland") if MAP_ID else "grassland"
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


# ================================================================ other battlefields

def hexs(h):
    return hexc(int(h.lstrip("#"), 16))


def road_details(road_pts, rng, stones, tufts, tuft_chance=0.4):
    """Small stones and tufts along both road edges, a few pebbles on the road."""
    for i in range(1, len(road_pts)):
        a, b = road_pts[i - 1], road_pts[i]
        seg = b - a
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
                if in_water(q, 0.25):
                    continue
                r = rng.random()
                if r < 0.4:
                    place(nat(rng.choice(stones)), q, rng.uniform(0, 6.28), rng.uniform(0.35, 0.6))
                elif r < 0.4 + tuft_chance and tufts and free_spot(q, 0.05, 0.6):
                    place(nat(rng.choice(tufts)), q, rng.uniform(0, 6.28), rng.uniform(0.5, 0.8))
            t += rng.uniform(0.35, 0.7)
        if rng.random() < 0.5:
            q = a + d * rng.uniform(0, L) + n * rng.uniform(-PATH_W * 0.3, PATH_W * 0.3)
            if not in_water(q, 0.3):
                place(nat(rng.choice(["rock_smallA", "rock_smallB", "rock_smallFlatC"])), q, rng.uniform(0, 6.28), 0.25)


def themed_ground(c1, c2, scale, patch, bump=0.0, name="Ground"):
    w, h = MAP["worldSize"]["width"], MAP["worldSize"]["height"]
    g = plane(-4, -6, w / U + 4, 24, 0, mat(name, None, noise=(c1, c2, scale)), name)
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
    mix.inputs["B"].default_value = patch + (1,)
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    if bump > 0:
        # Soft relief (wind-blown sand): two noise scales into a bump map.
        n1 = nt.nodes.new("ShaderNodeTexNoise"); n1.inputs["Scale"].default_value = 0.55; n1.inputs["Detail"].default_value = 2
        nt.links.new(coord.outputs["Object"], n1.inputs["Vector"])
        wave = nt.nodes.new("ShaderNodeTexWave"); wave.inputs["Scale"].default_value = 1.6
        wave.inputs["Distortion"].default_value = 6; wave.inputs["Detail"].default_value = 1
        nt.links.new(coord.outputs["Object"], wave.inputs["Vector"])
        add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"
        scale_w = nt.nodes.new("ShaderNodeMath"); scale_w.operation = "MULTIPLY"; scale_w.inputs[1].default_value = 0.18
        nt.links.new(wave.outputs["Fac"], scale_w.inputs[0])
        nt.links.new(n1.outputs["Fac"], add.inputs[0]); nt.links.new(scale_w.outputs[0], add.inputs[1])
        bmp = nt.nodes.new("ShaderNodeBump"); bmp.inputs["Strength"].default_value = bump; bmp.inputs["Distance"].default_value = 0.6
        nt.links.new(add.outputs[0], bmp.inputs["Height"])
        nt.links.new(bmp.outputs["Normal"], bsdf.inputs["Normal"])
    return g


# ---- water (lakeside)

def smooth_closed(pts, sub=6):
    """Catmull-Rom subdivision of a closed outline."""
    out = []
    n = len(pts)
    for i in range(n):
        p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        for k in range(sub):
            t = k / sub
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return out


WATER = [smooth_closed([w2u(p) for p in poly]) for poly in MAP.get("water", [])]


def _poly_dist(p, poly):
    inside = False
    best = 1e9
    j = len(poly) - 1
    for i in range(len(poly)):
        a, b = poly[i], poly[j]
        if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
            inside = not inside
        ab = b - a
        t = max(0, min(1, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
        best = min(best, (a + ab * t - p).length)
        j = i
    return -best if inside else best


def water_distance(p):
    """Signed distance to the nearest water (negative inside)."""
    return min((_poly_dist(p, poly) for poly in WATER), default=1e9)


def in_water(p, margin=0.0):
    return water_distance(p) < margin


def offset_poly(poly, d):
    """Moves every vertex along its outward normal by d (negative = inward)."""
    n = len(poly)
    area = sum(poly[i].x * poly[(i + 1) % n].y - poly[(i + 1) % n].x * poly[i].y for i in range(n))
    sign = 1 if area > 0 else -1
    out = []
    for i in range(n):
        a, b, c = poly[(i - 1) % n], poly[i], poly[(i + 1) % n]
        t = (c - a)
        if t.length < 1e-6:
            out.append(b.copy()); continue
        t.normalize()
        out.append(b + Vector((t.y, -t.x, 0)) * d * sign)
    return out


def poly_mesh(poly, z, material, name):
    bm = bmesh.new()
    vs = [bm.verts.new((p.x, p.y, z)) for p in poly]
    f = bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=[f])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(material)
    return o


def water_material(name, color, rough=0.12):
    m = mat(name, color, rough=rough)
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.6
    # Gentle ripples so the sky reflection breaks up.
    coord = nt.nodes.new("ShaderNodeTexCoord")
    n = nt.nodes.new("ShaderNodeTexNoise"); n.inputs["Scale"].default_value = 3.0; n.inputs["Detail"].default_value = 2
    nt.links.new(coord.outputs["Object"], n.inputs["Vector"])
    bmp = nt.nodes.new("ShaderNodeBump"); bmp.inputs["Strength"].default_value = 0.12; bmp.inputs["Distance"].default_value = 0.3
    nt.links.new(n.outputs["Fac"], bmp.inputs["Height"])
    nt.links.new(bmp.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def build_water(rng):
    base = hexs(THEME.get("water", "#3FA7C9"))
    shallow = tuple(min(1, c * 1.14 + 0.05) for c in base)
    deep = tuple(c * 0.72 for c in base)
    sand = mat("Shore", None, rough=0.95, noise=(hexc(0xD8C38C), hexc(0xE6D6A6), 1.2))

    def toward_centre(poly, inset):
        """Shrinks an outline towards its centroid by about `inset` tiles (never folds)."""
        c = sum(poly, Vector()) / len(poly)
        r = sum((p - c).length for p in poly) / len(poly)
        f = max(0.2, 1 - inset / r)
        return [c + (p - c) * f for p in poly]

    for k, poly in enumerate(WATER):
        xs = [p.x for p in poly]; ys = [p.y for p in poly]
        thin = min(max(xs) - min(xs), max(ys) - min(ys)) < 2.5      # a stream: one colour, no depth bands
        if thin:
            # A stream's banks: widen sideways only (a normal offset folds at its narrow ends).
            c = sum(poly, Vector()) / len(poly)
            wide_x = (max(xs) - min(xs)) < (max(ys) - min(ys))
            bank = [Vector((p.x + (0.26 if p.x > c.x else -0.26), p.y, 0)) if wide_x
                    else Vector((p.x, p.y + (0.26 if p.y > c.y else -0.26), 0)) for p in poly]
            poly_mesh(bank, 0.004, sand, f"Shore{k}")
        else:
            poly_mesh(offset_poly(poly, 0.26), 0.004, sand, f"Shore{k}")
        poly_mesh(poly, 0.010 + k * 1e-4, water_material("WaterShallow", shallow), f"Water{k}a")
        if not thin:
            poly_mesh(toward_centre(poly, 0.55), 0.012 + k * 1e-4, water_material("Water", base), f"Water{k}b")
            poly_mesh(toward_centre(poly, 1.5), 0.014 + k * 1e-4, water_material("WaterDeep", deep), f"Water{k}c")
        # Shoreline life: reeds on the bank, lilies on the water, rocks at the edge.
        for i in range(0, len(poly), 2):
            p = poly[i]
            r = rng.random()
            if not (-0.6 < p.x < MAP["worldSize"]["width"] / U + 0.6 and -1.6 < p.y < MAP["worldSize"]["height"] / U + 1.0):
                continue
            out = offset_poly(poly, 0.14)[i]
            inn = offset_poly(poly, -0.5)[i]
            if dist_to_path(out) < PATH_W / 2 + 0.5:
                continue
            if r < 0.30:
                for _ in range(2):
                    q = out + Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 0))
                    place(nat(rng.choice(["crops_bambooStageA", "crops_bambooStageB", "plant_flatTall"])), q, rng.uniform(0, 6.28), rng.uniform(0.55, 0.85))
            elif r < 0.48:
                place(nat(rng.choice(["rock_smallA", "rock_smallC", "stone_smallB", "rock_smallFlatA"])), out, rng.uniform(0, 6.28), rng.uniform(0.6, 1.0))
            elif r < 0.66 and not thin:
                q = inn + Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 0.016))
                place(nat(rng.choice(["lily_large", "lily_small", "lily_small"])), q, rng.uniform(0, 6.28), rng.uniform(0.7, 1.1))


def build_bridges():
    wood = mat("BridgeWood", None, rough=0.9, noise=(hexc(0x8A6540), hexc(0xA47C52), 2.5))
    dark = mat("BridgeDark", hexc(0x5E4429), rough=0.95)

    def box(cx, cy, cz, sx, sy, sz, rot, m):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(cx, cy, cz))
        o = bpy.context.active_object
        o.scale = (sx, sy, sz)
        o.rotation_euler.z = rot
        o.data.materials.append(m)

    for b in MAP.get("bridges", []):
        c = Vector((b["x"] / U, b["y"] / U, 0))
        a = math.radians(b["rotation"])
        d = Vector((math.cos(a), math.sin(a), 0))
        n = Vector((-d.y, d.x, 0))
        L = b["length"] / U + 0.5
        Wd = PATH_W + 0.3
        k = int(L / 0.24)
        for i in range(k):                                   # deck planks
            p = c + d * (-L / 2 + (i + 0.5) * L / k)
            box(p.x, p.y, 0.05, L / k * 0.86, Wd, 0.05, a, wood)
        for side in (-1, 1):                                 # side beams and posts
            p = c + n * side * (Wd / 2 - 0.04)
            box(p.x, p.y, 0.11, L, 0.09, 0.08, a, dark)
            for e in (-1, 1):
                q = p + d * e * (L / 2 - 0.08)
                box(q.x, q.y, 0.2, 0.13, 0.13, 0.4, a, dark)


def scatter_ground_decorations(rng, table):
    """Bakes the map's ground decorations (kinds drawn as sprites are skipped)."""
    for d in MAP["decorations"]:
        entry = table.get(d["kind"])
        if not entry:
            continue
        models, scale, count, spread = entry
        p = w2u(d)
        for _ in range(count):
            q = p + Vector((rng.uniform(-spread, spread), rng.uniform(-spread, spread), 0)) if count > 1 else p
            place(nat(rng.choice(models)), q, rng.uniform(0, 6.28), scale * d["scale"])


def stroke_road(points, width, z, material, name="Road"):
    """Road as a stroke with round joins: a rectangle per segment plus a disc at
    every bend. Unlike the filleted ribbon it never folds at sharp corners, and
    it always contains the gameplay path (which turns exactly at the vertices)."""
    verts, faces = [], []
    for k, (a, b) in enumerate(zip(points, points[1:])):
        d = (b - a).normalized()
        n = Vector((-d.y, d.x, 0)) * (width / 2)
        zz = z + k * 2e-4                      # tiny steps: overlapping pieces never z-fight
        i = len(verts)
        verts += [tuple(a + n + Vector((0, 0, zz))), tuple(a - n + Vector((0, 0, zz))),
                  tuple(b - n + Vector((0, 0, zz))), tuple(b + n + Vector((0, 0, zz)))]
        faces.append((i, i + 1, i + 2, i + 3))
    for k, c in enumerate(points[1:-1]):
        zz = z + (k + 0.5) * 2e-4
        i = len(verts)
        ring = 40
        verts.append((c.x, c.y, zz))
        for j in range(ring):
            ang = j / ring * math.tau
            verts.append((c.x + math.cos(ang) * width / 2, c.y + math.sin(ang) * width / 2, zz))
        for j in range(ring):
            faces.append((i, i + 1 + j, i + 1 + (j + 1) % ring))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(material)
    # Samples along the centre line (for edge details).
    pts = []
    for a, b in zip(points, points[1:]):
        L = (b - a).length
        steps = max(1, int(L / 0.5))
        pts += [a + (b - a) * (j / steps) for j in range(steps)]
    pts.append(points[-1])
    return o, pts


def world_coords(material):
    """Textures follow world position instead of object space, so separate
    objects sharing the material (ground and dunes) line up seamlessly."""
    nt = material.node_tree
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    for link in list(nt.links):
        if link.from_node.type == "TEX_COORD" and link.from_socket.name == "Object":
            to = link.to_socket
            nt.links.remove(link)
            nt.links.new(geo.outputs["Position"], to)


# ---- desert

def bake_desert_background():
    s = rig.reset()
    s.cycles.samples = 64
    s.render.film_transparent = False
    w, h = MAP["worldSize"]["width"], MAP["worldSize"]["height"]
    rng = random.Random(MAP["id"] + "-env")
    sand = themed_ground(hexs(THEME["ground"]), hexs(THEME["groundAlt"]), 0.3, (0.90, 0.80, 0.62), bump=0.35, name="Sand")
    world_coords(sand.data.materials[0])
    # Low dunes away from the road and pads: real relief for light and shadow.
    # Only the cap of a sunk, flattened sphere shows, so the rim meets the ground gently.
    placed = []
    for _ in range(400):
        if len(placed) >= 18:
            break
        p = Vector((rng.uniform(0.5, w / U - 0.5), rng.uniform(-0.5, h / U + 0.5), 0))
        if not free_spot(p, 2.1, 2.0) or any((p - q).length < 3.0 for q in placed):
            continue
        placed.append(p)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=1, location=(p.x, p.y, -0.40))
        o = bpy.context.active_object
        o.scale = (rng.uniform(3.2, 4.6), rng.uniform(2.2, 3.2), rng.uniform(0.5, 0.56))
        o.rotation_euler.z = rng.uniform(-0.5, 0.5)
        bpy.ops.object.shade_smooth()
        o.data.materials.append(sand.data.materials[0])
    R = PATH_W / 2 + 0.4
    paved = mat("Paved", None, rough=0.9, noise=(hexs(THEME["road"]), tuple(min(1, c * 1.12) for c in hexs(THEME["road"])), 1.4))
    stroke_road(PATH, PATH_W + 0.24, 0.004, mat("PavedEdge", hexs(THEME["roadEdge"]), rough=1.0), name="RoadEdge")
    road, road_pts = stroke_road(PATH, PATH_W, 0.008, paved)
    road_details(road_pts, rng, ["stone_smallFlatA", "stone_smallFlatB", "stone_smallFlatC", "rock_smallFlatA", "stone_smallA", "stone_smallC"],
                 ["plant_flatShort"], tuft_chance=0.06)
    scatter_ground_decorations(rng, {
        "rock": (["stone_smallA", "stone_smallC", "stone_smallE", "stone_smallB", "stone_smallD", "stone_smallF"], 0.95, 1, 0),
        "boulder": (["stone_largeA", "stone_largeC", "stone_largeE", "stone_largeB", "stone_largeD", "stone_tallC"], 0.8, 1, 0),
        "bush": (["plant_flatShort", "plant_flatTall", "plant_flatShort", "cactus_short"], 0.6, 1, 0),
    })
    # Scattered pebbles, dry tufts, a few bones-white stones and pots near the ruins.
    for _ in range(360):
        p = Vector((rng.uniform(-0.5, w / U + 0.5), rng.uniform(-1.5, h / U + 0.8), 0))
        if not free_spot(p, 0.35, 0.75):
            continue
        r = rng.random()
        name = (rng.choice(["stone_smallA", "stone_smallC", "stone_smallE", "stone_smallFlatB", "stone_smallB", "stone_smallFlatA"]) if r < 0.8 else
                rng.choice(["plant_flatShort", "stump_old", "log"]))
        place(nat(name), p, rng.uniform(0, 6.28), rng.uniform(0.45, 0.85))
    for d in MAP["decorations"]:
        if d["kind"] == "ruin":          # broken masonry and pots around each ruin sprite
            p = w2u(d)
            for _ in range(3):
                q = p + Vector((rng.uniform(-0.8, 0.8), rng.uniform(-0.6, 0.6), 0))
                if free_spot(q, 0.4, 0.8) and (q - p).length > 0.45:
                    place(nat(rng.choice(["statue_block", "pot_large", "pot_small", "stone_smallD", "statue_block"])), q, rng.uniform(0, 6.28), rng.uniform(0.6, 0.9))
    # Rocky mesa beyond the top edge, low rocks along the bottom edge.
    for _ in range(90):
        p = Vector((rng.uniform(-1.5, w / U + 1.5), rng.uniform(h / U + 0.7, h / U + 4.5), 0))
        place(nat(rng.choice(["stone_tallA", "stone_tallC", "stone_tallE", "stone_tallG", "stone_tallI", "stone_tallB", "stone_tallD",
                              "stone_largeB", "stone_largeD", "stone_tallF", "tree_palmTall", "cactus_tall"])),
              p, rng.uniform(0, 6.28), rng.uniform(1.2, 1.9))
    for _ in range(60):
        p = Vector((rng.uniform(-1, w / U + 1), rng.uniform(-1.9, -0.9), 0))
        place(nat(rng.choice(["stone_largeB", "stone_largeF", "stone_largeA", "stone_smallE", "cactus_short"])), p, rng.uniform(0, 6.28), rng.uniform(0.8, 1.2))
    rig.frame_camera(w, h, anchor=(0, OY / h), target=(0, 0, 0))
    rig.render_to(os.path.join(OUT, "background.png"))
    SPEC["background"] = {"size": [w, h], "anchor": [0, 0]}


def desert_deco_sprites():
    groups = [("cactus", ["cactus_tall", "cactus_short", "cactus_tall"], [1.35, 1.5, 1.15], 80, 100),
              ("palm", ["tree_palmTall", "tree_palmDetailedTall", "tree_palmBend", "tree_palmShort"], [1.5, 1.5, 1.5, 1.55], 110, 150),
              ("ruin", ["statue_column", "statue_columnDamaged", "statue_obelisk", "statue_head"], [1.25, 1.25, 1.2, 1.2], 80, 110)]
    for kind, models, scales, cw, ch in groups:
        for i, (m, sc) in enumerate(zip(models, scales)):
            render_sprite(f"deco_{kind}_{i}", lambda m=m, sc=sc, i=i: place(nat(m), (0, 0, 0), 0.4 + i * 1.3, sc), cw, ch, (0.5, 0.18))


def desert_slot_sprites():
    def pad(highlight):
        def build():
            bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.62, depth=0.07, location=(0, 0, 0.035))
            bpy.context.active_object.data.materials.append(mat("PadStone", None, rough=0.9, noise=(hexc(0x8C7A66), hexc(0xA49078), 3.0)))
            rng = random.Random(11)
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


def desert_spawn_sprite():
    def build():
        place(nat("cliff_cave_stone"), (-0.25, 0, 0), -math.pi / 2, 1.25)
        for (x, y, m, sc) in [(-0.2, 0.9, "stone_largeB", 0.9), (-0.3, -0.9, "stone_largeD", 0.85), (0.4, 0.95, "stone_tallB", 0.6),
                              (0.35, -0.95, "stone_smallC", 0.8), (-0.8, 0.25, "cactus_tall", 1.1)]:
            place(nat(m), (x, y, 0), 1.3, sc)
    render_sprite("spawn", build, 130, 150, (0.5, 0.32))


# ---- lakeside

def bake_lakeside_background():
    s = rig.reset()
    s.cycles.samples = 64
    s.render.film_transparent = False
    w, h = MAP["worldSize"]["width"], MAP["worldSize"]["height"]
    rng = random.Random(MAP["id"] + "-env")
    themed_ground(hexs(THEME["ground"]), hexs(THEME["groundAlt"]), 0.22, (0.74, 0.82, 0.58), name="Meadow")
    R = PATH_W / 2 + 0.4
    ribbon(PATH, PATH_W + 0.22, 0.006, mat("RoadEdgeL", hexs(THEME["roadEdge"]), rough=1.0), corner_r=R, name="RoadEdge")
    road, road_pts = ribbon(PATH, PATH_W, 0.008, mat("RoadL", None, rough=0.95, noise=(hexs(THEME["road"]), tuple(min(1, c * 1.1) for c in hexs(THEME["road"])), 0.9)), corner_r=R)
    build_water(rng)
    build_bridges()
    road_details(road_pts, rng, ["stone_smallFlatA", "stone_smallFlatB", "rock_smallFlatA", "stone_smallA"], ["grass", "grass_large", "grass_leafs"])
    scatter_ground_decorations(rng, {
        "rock": (["rock_smallA", "rock_smallC", "rock_smallE", "stone_smallB", "stone_smallD"], 0.9, 1, 0),
        "boulder": (["rock_largeA", "rock_largeC", "rock_largeE", "stone_largeB"], 0.75, 1, 0),
        "bush": (["plant_bush", "plant_bushLarge", "plant_bushDetailed", "plant_bushSmall"], 0.9, 1, 0),
        "flowers": (["flower_redA", "flower_yellowA", "flower_purpleA", "flower_yellowB", "flower_purpleB"], 0.7, 3, 0.3),
    })
    for _ in range(420):
        p = Vector((rng.uniform(-0.5, w / U + 0.5), rng.uniform(-1.5, h / U + 0.8), 0))
        if not free_spot(p, 0.35, 0.75) or in_water(p, 0.35):
            continue
        r = rng.random()
        name = (rng.choice(["grass", "grass_large", "grass_leafs", "grass_leafsLarge"]) if r < 0.72 else
                rng.choice(["mushroom_red", "mushroom_tanGroup", "stone_smallC", "rock_smallFlatB", "flower_yellowA", "flower_purpleA"]))
        place(nat(name), p, rng.uniform(0, 6.28), rng.uniform(0.55, 0.9))
    # A canoe pulled up on the pond's shore.
    if len(WATER) > 1:
        pond = WATER[1]
        c = sum(pond, Vector()) / len(pond)
        place(nat("canoe"), c + Vector((0.6, -0.3, 0.02)), 0.5, 0.9)
        place(nat("canoe_paddle"), c + Vector((0.75, -0.2, 0.08)), 0.6, 0.9)
    for _ in range(150):
        p = Vector((rng.uniform(-1.5, w / U + 1.5), rng.uniform(h / U + 0.6, h / U + 4.5), 0))
        if in_water(p, 0.6):
            continue
        place(nat(rng.choice(TREES + TREES + PINES)), p, rng.uniform(0, 6.28), rng.uniform(1.3, 1.8))
    for _ in range(70):
        p = Vector((rng.uniform(-1, w / U + 1), rng.uniform(-1.9, -0.9), 0))
        if in_water(p, 0.4):
            continue
        place(nat(rng.choice(["plant_bushLarge", "plant_bush", "rock_largeB", "plant_bushDetailed"])), p, rng.uniform(0, 6.28), rng.uniform(0.8, 1.2))
    rig.frame_camera(w, h, anchor=(0, OY / h), target=(0, 0, 0))
    rig.render_to(os.path.join(OUT, "background.png"))
    SPEC["background"] = {"size": [w, h], "anchor": [0, 0]}


if ENVIRONMENT == "desert":
    STEPS = {"background": bake_desert_background, "decos": desert_deco_sprites, "slots": desert_slot_sprites, "spawn": desert_spawn_sprite}
elif ENVIRONMENT == "lakeside":
    STEPS = {"background": bake_lakeside_background}
else:
    STEPS = {"background": bake_background, "trees": tree_sprites, "slots": slot_sprites, "spawn": spawn_sprite, "bases": base_sprites}
for name, fn in STEPS.items():
    if ONLY and not (ONLY == name or (name == "bases" and ONLY.startswith("base"))):
        continue
    fn()
    json.dump(SPEC, open(spec_path, "w"), indent=1)
print("ENV_DONE", sorted(SPEC))
