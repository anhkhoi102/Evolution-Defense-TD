"""Stage 3 — enemies. For each enemy visual:

  out/enemies/<visual>_walk_d<d>_f<f>.png    8 directions × WALK frames (distance-driven walk cycle)
  out/enemies/<visual>_death_d<d>_f<f>.png   8 directions × DEATH frames (one-shot)
  out/enemies/enemies.json                   size, anchor, frame counts, health-bar offset

Directions start at +x (east) and go counter-clockwise, matching the game's
heading angle. Models are posed from their own rigged animations.

blender -b --factory-startup -P bake_enemies.py [-- only=<visual>]
"""
import bpy, json, math, os, re, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(__file__))
import rig

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "out", "enemies")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "sources")
UAA = os.path.join(SRC, "quaternius-ultimateanimatedanimals", "Ultimate Animated Animals - July 2021", "glTF")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = next((a.split("=", 1)[1] for a in argv if a.startswith("only=")), None)
FACETEST = "facetest" in argv   # renders direction 0, walk frame 0 only, into out/facetest/
DIRS, WALK, DEATH = 8, 8, 6
SPEC_PATH = os.path.join(OUT, "enemies.json")
SPEC = json.load(open(SPEC_PATH)) if os.path.exists(SPEC_PATH) else {}
GAME = json.load(open(os.path.join(ROOT, "..", "..", "Packages", "EvolutionDefenseCore", "Sources",
                                   "EvolutionDefenseCore", "Resources", "Config", "enemies.json")))
RADIUS = {e["visual"]: e["radius"] for e in GAME}


def blend(pack, name):
    for dp, _, fs in os.walk(os.path.join(SRC, pack)):
        if name + ".blend" in fs:
            return os.path.join(dp, name + ".blend")
    raise FileNotFoundError(pack + "/" + name)


def U(n): return os.path.join(UAA, n + ".gltf")


# visual: source, walk regex, death regex, size (units: "length" along the body or "height"),
# colours (material-name regex → (r,g,b) sRGB) or tint, flying altitude, model forward axis.
ENEMIES = {
    "wolf":           dict(src=U("Wolf"), walk="Walk", death="Death", length=0.95),
    "boar":           dict(src=os.path.join(SRC, "oga-boar", "boar_0.blend"), walk="walk", death=None, length=0.95,
                           colors={".*": (0.30, 0.22, 0.17)}),
    "bear":           dict(src=U("Bull"), walk="Walk", death="Death", length=1.3, drop=["Horns"],
                           colors={"^Main$": (0.27, 0.17, 0.11), "Main_Light": (0.40, 0.28, 0.18), "Muzzle": (0.20, 0.14, 0.10)}),
    "alphaBeast":     dict(src=U("Wolf"), walk="Walk", death="Death", length=1.9,
                           colors={"^Main$": (0.20, 0.15, 0.27), "Main_Light": (0.38, 0.30, 0.50), "Eyes": (1.0, 0.2, 0.15)},
                           glow={"Eyes": (1.0, 0.2, 0.15)}),
    "giantWolf":      dict(src=U("Husky"), walk="Walk", death="Death", length=1.15,
                           colors={"^Main$": (0.22, 0.23, 0.26), "Main_Light": (0.48, 0.50, 0.54)}),
    "armoredBeast":   dict(src=U("Bull"), walk="Walk", death="Death", length=1.2,
                           colors={"^Main$": (0.42, 0.44, 0.48), "Main_Light": (0.62, 0.64, 0.68), "Horns": (0.85, 0.82, 0.70)}),
    "troll":          dict(src=blend("oga-quaternius-cute-monsters", "Yeti"), walk="Walk", death="Death", height=1.35,
                           tint=((0.36, 0.48, 0.30), 0.75), face=math.pi / 2),
    "flyingMonster":  dict(src=blend("oga-quaternius-animated-monster-pack", "Bat"), walk="Flying", death="Death", length=1.0,
                           fly=0.9, face=math.pi / 2),
    "ancientDragon":  dict(src=blend("oga-quaternius-animated-monster-pack", "Dragon"), walk="Flying", death="Death", length=2.4,
                           fly=1.2, face=math.pi / 2),
    "mutantBeast":    dict(src=U("Stag"), walk="Walk", death="Death", length=1.05,
                           tint=((0.45, 0.85, 0.25), 0.55)),
    "armoredMonster": dict(src=blend("oga-quaternius-cute-monsters", "Crab"), walk="Walk", death="Death", length=1.25,
                           tint=((0.38, 0.42, 0.36), 0.6), face=math.pi / 2),
    "giantMutant":    dict(src=blend("oga-quaternius-cute-monsters", "Cyclops"), walk="Walk", death="Death", height=1.55,
                           tint=((0.50, 0.30, 0.62), 0.6), face=math.pi / 2),
    "swarmCreature":  dict(src=blend("oga-quaternius-animated-monster-pack", "Slime"), walk="Walk", death="Death", length=0.6,
                           tint=((0.55, 0.85, 0.20), 0.4), face=0.0),
    "mutantTitan":    dict(src=blend("oga-quaternius-cute-monsters", "GreenDemon"), walk="Walk", death="Death", height=2.3,
                           tint=((0.40, 0.70, 0.25), 0.5), face=math.pi / 2),
    "scoutRobot":     dict(src=blend("oga-quaternius-animated-robot", "Robot"), walk="Running", death="Death", height=0.95, face=math.pi / 2),
    "assaultRobot":   dict(src=blend("oga-quaternius-animated-mech-pack", "George"), walk="^Walk$", death="Death", height=1.3),
    "heavyMech":      dict(src=blend("oga-quaternius-animated-mech-pack", "Stan"), walk="^Walk$", death="Death", height=1.7),
    "stealthRobot":   dict(src=blend("oga-quaternius-animated-mech-pack", "Leela"), walk="^Walk$", death="Death", height=1.15,
                           tint=((0.32, 0.25, 0.48), 0.5)),
    "titanWarMachine": dict(src=blend("oga-quaternius-animated-mech-pack", "Mike"), walk="^Walk$", death="Death", height=2.8,
                            tint=((0.45, 0.20, 0.18), 0.35)),
}


# ---- Battlefield rosters (Docs/ROSTERS.md): creatures that only appear on one map.
def UM(n): return os.path.join(SRC, "quaternius-ultimatemonsters", "Ultimate Monsters", "Big", "glTF", n + ".gltf")
def KS(n): return os.path.join(SRC, "kaykit-skeletons", "addons", "kaykit_character_pack_skeletons", "Characters", "gltf", n + ".glb")
def CUTE(n): return blend("oga-quaternius-cute-monsters", n)
def ANI2(n): return blend("oga-quaternius-animal-pack-vol2", n)


ENEMIES.update({
    # Desert: the dead of the tombs, cactus folk and orcs.
    "boneRunner":   dict(src=KS("Skeleton_Minion"), walk="^Running_A$", death="^Death_A$", height=0.8),
    "cactling":     dict(src=CUTE("Cactus"), walk="Walk", death="Death", height=0.8, face=math.pi / 2),
    "tombGuard":    dict(src=KS("Skeleton_Warrior"), walk="^Walking_A$", death="^Death_A$", height=1.15),
    "cactoroChief": dict(src=UM("Cactoro"), walk="^Walk$", death="Death", height=2.0),
    "graveStalker": dict(src=KS("Skeleton_Rogue"), walk="^Running_B$", death="^Death_B$", height=1.0),
    "skullOrc":     dict(src=UM("Orc_Skull"), walk="^Walk$", death="Death", height=1.2),
    "boneShaman":   dict(src=KS("Skeleton_Mage"), walk="^Walking_A$", death="^Death_A$", height=1.15),
    "vulture":      dict(src=ANI2("Eagle"), walk="Flying", death=None, length=1.15, fly=0.9, face=math.pi / 2,
                         tint=((0.35, 0.24, 0.18), 0.5)),
    "sandWyrm":     dict(src=CUTE("YellowDragon"), walk="Flying", death="Death", length=2.4, fly=1.2, face=math.pi / 2),
    "duneRaptor":   dict(src=UM("Dino"), walk="^Run$", death="Death", height=1.1, tint=((0.85, 0.62, 0.30), 0.6)),
    "stoneSkull":   dict(src=CUTE("Skull"), walk="Walk", death="Death", height=1.0, face=math.pi / 2),
    "orcWarlord":   dict(src=UM("Orc"), walk="^Walk$", death="Death", height=1.7),
    "sandImp":      dict(src=CUTE("Demon"), walk="Walk", death="Death", height=0.6, face=math.pi / 2),
    "duneTyrant":   dict(src=UM("Demon"), walk="^Walk$", death="Death", height=2.5),
    # Lakeside: marsh creatures, mushrooms and things from the deep.
    "marshHopper":  dict(src=UM("Frog"), walk="^Run$", death="Death", height=0.8),
    "sporecap":     dict(src=CUTE("Mushroom"), walk="Walk", death="Death", height=0.8, face=math.pi / 2),
    "reefBrute":    dict(src=UM("Fish"), walk="^Walk$", death="Death", height=1.3),
    "mushroomKing": dict(src=UM("MushroomKing"), walk="^Walk$", death="Death", height=2.0),
    "heronRaider":  dict(src=UM("Birb"), walk="^Run$", death="Death", height=1.05),
    "bogwood":      dict(src=CUTE("Tree"), walk="Walk", death="Death", height=1.15, face=math.pi / 2),
    "lakeWisp":     dict(src=CUTE("Ghost"), walk="Walk", death="Death", height=1.0, face=math.pi / 2),
    "marshHornet":  dict(src=CUTE("Bee"), walk="Flying", death="Death", length=1.0, fly=0.9, face=math.pi / 2),
    "lakeHorror":   dict(src=CUTE("Cthulhu"), walk="Flying", death="Death", length=2.4, fly=1.2, face=math.pi / 2),
    "bogLurker":    dict(src=UM("Monkroose"), walk="^Run$", death="Death", height=1.1),
    "shellBrute":   dict(src=UM("Yeti"), walk="^Walk$", death="Death", height=1.3, tint=((0.20, 0.55, 0.55), 0.55)),
    "deepOne":      dict(src=UM("Alien"), walk="^Walk$", death="Death", height=1.65),
    "mudPiranha":   dict(src=ANI2("Piranha"), walk="Swimming", death=None, length=0.7, face=math.pi / 2),
    "tideTyrant":   dict(src=UM("BlueDemon"), walk="^Walk$", death="Death", height=2.5),
})
MAP_OF = {e["visual"]: e.get("battlefield") for e in GAME}


def lin(c): return tuple(rig._lin(x) for x in c) + (1,)


def apply_colors(objs, colors, glow):
    for o in objs:
        if o.type != "MESH":
            continue
        for sl in o.material_slots:
            m = sl.material
            if not m:
                continue
            for pat, col in colors.items():
                if re.search(pat, m.name):
                    m.use_nodes = True
                    nt = m.node_tree
                    bs = [n for n in nt.nodes if n.type in ("BSDF_PRINCIPLED", "BSDF_DIFFUSE")]
                    if not bs:
                        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
                        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
                        nt.links.new(b.outputs[0], out.inputs["Surface"])
                        bs = [b]
                    for b in bs:   # some sources carry several outputs/BSDFs; colour them all
                        sock = b.inputs["Color"] if b.type == "BSDF_DIFFUSE" else b.inputs["Base Color"]
                        for l in list(sock.links):
                            nt.links.remove(l)
                        sock.default_value = lin(col)
                        b.inputs["Roughness"].default_value = 0.75
            for pat, col in (glow or {}).items():
                if re.search(pat, m.name):
                    b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                    if b:
                        b.inputs["Emission Color"].default_value = lin(col)
                        b.inputs["Emission Strength"].default_value = 4


def apply_tint(objs, color, amount):
    """Shifts a textured model towards `color` (keeps its shading detail)."""
    seen = set()
    for o in objs:
        if o.type != "MESH":
            continue
        for sl in o.material_slots:
            m = sl.material
            if not m or m.name in seen or not m.node_tree:
                continue
            seen.add(m.name)
            nt = m.node_tree
            for b in [n for n in nt.nodes if n.type in ("BSDF_PRINCIPLED", "BSDF_DIFFUSE")]:
                sock = b.inputs["Color"] if b.type == "BSDF_DIFFUSE" else b.inputs["Base Color"]
                mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "COLOR"
                mix.inputs["Factor"].default_value = amount
                mix.inputs["B"].default_value = lin(color)
                if sock.is_linked:
                    nt.links.new(sock.links[0].from_socket, mix.inputs["A"])
                else:
                    mix.inputs["A"].default_value = sock.default_value
                nt.links.new(mix.outputs["Result"], sock)


def drop_faces(objs, materials):
    import bmesh
    for o in objs:
        if o.type != "MESH":
            continue
        idx = {i for i, sl in enumerate(o.material_slots) if sl.material and sl.material.name in materials}
        if not idx:
            continue
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in idx], context="FACES")
        bm.to_mesh(o.data); bm.free()


def find_action(rx):
    if not rx:
        return None
    acts = [a for a in bpy.data.actions if re.search(rx, a.name.split("|")[-1], re.I)]
    acts.sort(key=lambda a: len(a.name))
    return acts[0] if acts else None


def set_action(arm, act, frame):
    arm.animation_data_create()
    arm.animation_data.action = act
    try:
        if act.slots:
            arm.animation_data.action_slot = act.slots[0]
    except Exception:
        pass
    bpy.context.scene.frame_set(int(round(frame)))
    bpy.context.view_layer.update()


def forward_axis(objs):
    """Quaternius/Kenney rigs face −y or +y; the longer horizontal extent is the body axis."""
    b = rig.bounds(objs)
    return b


def bake(visual, spec):
    s = rig.reset()
    s.cycles.samples = 20
    rig.shadow_catcher(30)
    root, objs = rig.import_model(spec["src"])
    if spec.get("drop"):
        drop_faces(objs, set(spec["drop"]))
    if spec.get("colors"):
        apply_colors(objs, spec["colors"], spec.get("glow"))
    if spec.get("tint"):
        apply_tint(objs, *spec["tint"])
    arm = next((o for o in objs if o.type == "ARMATURE"), None)
    walk = find_action(spec["walk"])
    death = find_action(spec.get("death"))
    if arm and walk:
        set_action(arm, walk, walk.frame_range[0])
    b = rig.bounds(objs)
    size = b[1] - b[0]
    if "height" in spec:
        k = spec["height"] / max(size.z, 1e-3)
    else:
        k = spec["length"] / max(size.x, size.y, 1e-3)
    root.scale = (k, k, k)
    bpy.context.view_layer.update()
    # Facing: models whose body is longer along y face ±y. Quaternius faces +y in
    # Blend files and −y after glTF import; detect from the head side (more mass ahead).
    face = spec.get("face")
    if face is None:
        face = -math.pi / 2 if spec["src"].endswith(".blend") else math.pi / 2
    alt = spec.get("fly", 0.0)
    r = RADIUS.get(visual, 16)
    canvas = max(70, r * 5.0 + alt * 30)
    if MAP_OF.get(visual):
        # Roster creatures carry weapons, hats and wings well outside their hit radius:
        # size the canvas from the model so nothing is cut off (hit radius is unaffected).
        reach = max(size.x, size.y, size.z) * k * rig.PPU
        canvas = max(canvas, round(reach * 1.7 + 24 + alt * 30))
    W = H = canvas
    anchor = (0.5, 0.26 if not alt else 0.16)
    rig.frame_camera(W, H, anchor=anchor, target=(0, 0, 0))
    clips = [("walk", walk, WALK, True)]
    if death:
        clips.append(("death", death, DEATH, False))
    if FACETEST:
        os.makedirs(os.path.join(ROOT, "out", "facetest"), exist_ok=True)
        root.rotation_euler.z = face; root.location = (0, 0, alt)
        rig.render_to(os.path.join(ROOT, "out", "facetest", visual + ".png"))
        print("FACE", visual, round(k, 3), walk.name if walk else None, death.name if death else None, flush=True)
        return
    counts = {}
    for name, act, n, loop in clips:
        f0, f1 = act.frame_range
        frames = [f0 + (f1 - f0) * (i / n if loop else i / (n - 1)) for i in range(n)]
        for d in range(DIRS):
            root.rotation_euler.z = face + d / DIRS * math.tau
            root.location = (0, 0, alt)
            for i, fr in enumerate(frames):
                if arm:
                    set_action(arm, act, fr)
                if "speconly" not in argv:
                    rig.render_to(os.path.join(OUT, f"{visual}_{name}_d{d}_f{i}.png"))
        counts[name] = n
    if os.path.exists(SPEC_PATH):                # another bake may be running: merge, don't overwrite
        SPEC.update({k: v for k, v in json.load(open(SPEC_PATH)).items() if k != visual})
    SPEC[visual] = {"size": [W, H], "anchor": list(anchor), "frames": counts, "directions": DIRS,
                    "walkDistance": round(max(6.0, r * 0.9), 1), "altitude": alt,
                    "healthBarOffsetY": round((size.z * k + alt) * rig.PPU * rig.HEIGHT_SY + 10, 1)}
    json.dump(SPEC, open(SPEC_PATH, "w"), indent=1)
    print("ENEMY", visual, "scale", round(k, 3), "walk", walk.name if walk else None, "death", death.name if death else None, flush=True)


for visual, spec in ENEMIES.items():
    if ONLY and ONLY not in (visual,) and not (ONLY == "era1" and visual in ("wolf", "boar", "bear", "alphaBeast")) \
            and not (ONLY == "rosters" and MAP_OF.get(visual)) and ONLY != MAP_OF.get(visual):
        continue
    if "resume" in argv and visual in SPEC:      # pick up an interrupted run
        continue
    bake(visual, spec)
print("ENEMIES_DONE")
