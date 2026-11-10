"""Summoned allies (Docs/SUMMONS.md, Docs/HEROES.md): the militia and the three
heroes, rendered from the KayKit Adventurers character pack (Kay Lousberg, CC0).
The characters ship with their own weapons, shields, capes, hats and animations;
this script only chooses which of them each unit shows. The one thing built here
is the Iron King's crown (the pack has none).

  out/summons/<visual>_<clip>_d<d>_f<f>.png   8 directions × clips (idle, walk, attack, death)
  out/summons/summons.json                    size, anchor, frame counts, health-bar offset

blender -b --factory-startup -P bake_summons.py [-- only=<visual>] [-- test]
  test: one frame per clip, facing the camera and facing right, into out/summons_test/
"""
import bpy, json, math, os, sys
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(__file__))
import rig

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = next((a.split("=", 1)[1] for a in argv if a.startswith("only=")), None)
TEST = "test" in argv
OUT = os.path.join(ROOT, "out", "summons_test" if TEST else "summons")
os.makedirs(OUT, exist_ok=True)
KAYKIT = os.path.join(ROOT, "sources", "kaykit-adventures", "addons", "kaykit_character_pack_adventures",
                      "Characters", "gltf")
DIRS = 8
FACE = math.pi / 2          # KayKit characters face −y; this turns them to +x (direction 0)

# visual: character file, which of its gear meshes to show (everything else bone-parented is hidden),
# height (units), canvas (points), animation per clip, optional outfit tint and crown colour.
SUMMONS = {
    "militia": dict(character="Barbarian", gear=["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"], height=0.86, canvas=108,
                    clips=dict(idle="Idle", walk="Running_A", attack="1H_Melee_Attack_Chop", death="Death_A")),
    "knight": dict(character="Knight", gear=["1H_Sword", "Rectangle_Shield", "Knight_Helmet", "Knight_Cape"], height=1.22, canvas=152,
                   clips=dict(idle="Idle", walk="Running_A", attack="1H_Melee_Attack_Slice_Diagonal", death="Death_A")),
    # Iron King: the same armour in dark iron, a two-handed greatsword and a gold crown. The biggest unit.
    "king": dict(character="Knight", gear=["2H_Sword", "Knight_Helmet", "Knight_Cape"], height=1.5, canvas=172,
                 tint=(0.5, 0.56, 0.74), metal=0.55, crown=(1.0, 0.72, 0.15),
                 clips=dict(idle="2H_Melee_Idle", walk="Walking_A", attack="2H_Melee_Attack_Chop", death="Death_B")),
    # Star Queen: the pack's mage with her staff. She casts instead of swinging.
    "queen": dict(character="Mage", gear=["2H_Staff", "Mage_Hat", "Mage_Cape"], height=1.2, canvas=136,
                  clips=dict(idle="Idle", walk="Walking_A", attack="Spellcast_Shoot", death="Death_A")),
}
# clip: frames, loops
CLIPS = [("idle", 6, True), ("walk", 8, True), ("attack", 6, False), ("death", 6, False)]
SPEC_PATH = os.path.join(OUT, "summons.json")
SPEC = json.load(open(SPEC_PATH)) if os.path.exists(SPEC_PATH) else {}


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


def tint_outfit(objs, color, metal):
    """Shifts a character's colours (texture detail kept): dark iron for the King."""
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
            b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if not b:
                continue
            sock = b.inputs["Base Color"]
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs["B"].default_value = (*color, 1)
            if sock.is_linked:
                nt.links.new(sock.links[0].from_socket, mix.inputs["A"])
            else:
                mix.inputs["A"].default_value = sock.default_value
            nt.links.new(mix.outputs["Result"], sock)
            b.inputs["Metallic"].default_value = metal
            b.inputs["Roughness"].default_value = 0.45


def add_crown(arm, helmet, color):
    """The King's crown: a ring with five points on top of the helmet, following the head bone."""
    b = rig.bounds([helmet])
    cx, cy, top = (b[0].x + b[1].x) / 2, (b[0].y + b[1].y) / 2, b[1].z
    r = (b[1].x - b[0].x) * 0.3
    m = bpy.data.materials.new("crown")
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Metallic"].default_value = 0.8
    p.inputs["Roughness"].default_value = 0.35
    p.inputs["Emission Color"].default_value = (*color, 1)
    p.inputs["Emission Strength"].default_value = 0.08
    parts = []
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=r, depth=r * 0.35, location=(0, 0, r * 0.17))
    parts.append(bpy.context.active_object)
    for k in range(5):
        a = k / 5 * math.tau - math.pi / 2
        bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=r * 0.24, depth=r * 0.6,
                                        location=(math.cos(a) * r * 0.86, math.sin(a) * r * 0.86, r * 0.6))
        parts.append(bpy.context.active_object)
    pivot = bpy.data.objects.new("crown", None)
    bpy.context.scene.collection.objects.link(pivot)
    for o in parts:
        o.data.materials.append(m)
        o.parent = pivot
    pb = arm.pose.bones["head"]
    parent = arm.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0))
    pivot.parent = arm
    pivot.parent_type = "BONE"
    pivot.parent_bone = "head"
    pivot.matrix_parent_inverse = parent.inverted()
    pivot.matrix_basis = Matrix.Translation((cx, cy, top - r * 0.25))
    return parts + [pivot]


def bake(visual, spec):
    s = rig.reset()
    s.cycles.samples = 20
    rig.shadow_catcher(20)
    root, objs = rig.import_model(os.path.join(KAYKIT, spec["character"] + ".glb"))
    arm = next(o for o in objs if o.type == "ARMATURE")
    bpy.context.view_layer.update()
    # The pack attaches every weapon and accessory to the hands, head and chest at once: keep only this unit's gear.
    for o in objs:
        if o.type == "MESH" and o.parent_type == "BONE" and o.name not in spec["gear"]:
            o.hide_render = True
            o.hide_viewport = True
    missing = [g for g in spec["gear"] if g not in {o.name for o in objs}]
    if missing:
        raise RuntimeError(f"{visual}: gear {missing} not in {spec['character']}")
    if spec.get("tint"):
        tint_outfit(objs, spec["tint"], spec.get("metal", 0.4))
    if spec.get("crown"):
        objs += add_crown(arm, next(o for o in objs if o.name.endswith("_Helmet")), spec["crown"])
    body = [o for o in objs if o.type == "MESH" and o.parent_type != "BONE"]
    b = rig.bounds(body)
    k = spec["height"] / max((b[1] - b[0]).z, 1e-3)
    root.scale = (k, k, k)
    bpy.context.view_layer.update()
    W = H = spec["canvas"]
    anchor = (0.5, 0.3)
    rig.frame_camera(W, H, anchor=anchor, target=(0, 0, 0))
    counts = {}
    for name, n, loop in CLIPS:
        act = bpy.data.actions.get(spec["clips"][name])
        if act is None:
            raise RuntimeError(f"{visual}: action {spec['clips'][name]} missing")
        f0, f1 = act.frame_range
        frames = [f0 + (f1 - f0) * (i / n if loop else i / (n - 1)) for i in range(n)]
        dirs = [0, 6] if TEST else range(DIRS)
        for d in dirs:
            root.rotation_euler.z = FACE + d / DIRS * math.tau
            for i, fr in enumerate(frames):
                if TEST and i != n // 2:
                    continue
                set_action(arm, act, fr)
                rig.render_to(os.path.join(OUT, f"{visual}_{name}_d{d}_f{i}.png"))
        counts[name] = n
    if not TEST:
        SPEC[visual] = {"size": [W, H], "anchor": list(anchor), "frames": counts, "directions": DIRS,
                        "healthBarOffsetY": round(spec["height"] * rig.PPU * rig.HEIGHT_SY + 10, 1)}
        json.dump(SPEC, open(SPEC_PATH, "w"), indent=1)
    print("SUMMON", visual, "scale", round(k, 3), flush=True)


for v, spec in SUMMONS.items():
    if ONLY and v != ONLY:
        continue
    bake(v, spec)
print("SUMMONS_DONE")
