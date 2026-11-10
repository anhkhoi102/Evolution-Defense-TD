"""Summoned allies (Docs/SUMMONS.md): the militia minion and the Knight hero,
from the animated Kenney Mini Characters, with weapons and shields parented
to the arm bones so they follow the animations.

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
MINI = os.path.join(ROOT, "sources", "kenney-mini-characters", "Models", "GLB format")
DIRS = 8
FACE = math.pi / 2          # Kenney characters face −y; this turns them to +x (direction 0)


def M(n): return os.path.join(MINI, n + ".glb")


# visual: character, right-hand weapon, left-hand shield, height (units), tint, glow
SUMMONS = {
    "militia": dict(character="character-soldier", weapon="weapon-spear", shield="shield-round", height=0.82,
                    weapon_scale=1.45, shield_scale=0.75, grip=0.2, canvas=84),
    "knight": dict(character="character-knight", weapon="weapon-sword", shield="shield-rectangle", height=1.2,
                   weapon_scale=1.35, shield_scale=0.9, grip=0.08, canvas=112, gold=True),
}
# clip: action name in the Kenney rig, frames, loops
CLIPS = [("idle", "idle", 6, True), ("walk", "walk", 8, True), ("attack", "attack-melee-right", 6, False),
         ("death", "die", 6, False)]
SPEC_PATH = os.path.join(OUT, "summons.json")
SPEC = json.load(open(SPEC_PATH)) if os.path.exists(SPEC_PATH) else {}


def find_action(name):
    for a in bpy.data.actions:
        if a.name.split("|")[-1] == name or a.name == name:
            return a
    return None


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


def hand_position(objs, arm, bone):
    """World position of a hand at rest: the lowest vertices skinned to the arm bone."""
    pts = []
    for o in objs:
        if o.type != "MESH" or bone not in o.vertex_groups:
            continue
        gi = o.vertex_groups[bone].index
        for v in o.data.vertices:
            if any(g.group == gi and g.weight > 0.5 for g in v.groups):
                pts.append(o.matrix_world @ v.co)
    pts.sort(key=lambda p: p.z)
    low = pts[:max(1, len(pts) // 5)]
    return sum(low, Vector()) / len(low)


def attach(objs, arm, bone, model, scale, grip, tilt, outward, forward=0.02):
    """Places a prop at the hand (world space, rest pose) and binds it to the arm
    bone, so it follows the arm through every animation.
    grip: how far below the hand the prop's base sits; tilt: lean forward (rad);
    outward: sideways push away from the body (shields)."""
    hand = hand_position(objs, arm, bone)
    pivot, pobjs = rig.import_model(M(model))
    side = 1 if hand.x > 0 else -1
    world = (Matrix.Translation(hand + Vector((side * outward, -forward, -grip)))
             @ Matrix.Rotation(-tilt, 4, "X")
             @ Matrix.Diagonal((scale, scale, scale, 1)))
    pb = arm.pose.bones[bone]
    parent = arm.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0))
    pivot.parent = arm
    pivot.parent_type = "BONE"
    pivot.parent_bone = bone
    pivot.matrix_parent_inverse = parent.inverted()
    pivot.matrix_basis = world
    return pobjs


def gold_trim(objs):
    """The hero's armour is tinted towards polished gold (texture detail kept),
    with a touch of emission so it reads at small sizes."""
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
            # Multiply: near-white armour becomes gold, dark details stay dark.
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs["B"].default_value = (1.0, 0.6, 0.16, 1)      # gold (linear)
            if sock.is_linked:
                nt.links.new(sock.links[0].from_socket, mix.inputs["A"])
            else:
                mix.inputs["A"].default_value = sock.default_value
            nt.links.new(mix.outputs["Result"], sock)
            b.inputs["Metallic"].default_value = 0.45
            b.inputs["Roughness"].default_value = 0.45
            b.inputs["Emission Color"].default_value = (1.0, 0.62, 0.18, 1)
            b.inputs["Emission Strength"].default_value = 0.06


def bake(visual, spec):
    s = rig.reset()
    s.cycles.samples = 20
    rig.shadow_catcher(20)
    root, objs = rig.import_model(M(spec["character"]))
    arm = next(o for o in objs if o.type == "ARMATURE")
    bpy.context.view_layer.update()
    if spec.get("gold"):
        gold_trim(objs)          # the knight only; weapon and shield stay steel and wood
    # Props are placed in the rest pose, then the animations move the arms.
    # Weapon upright in the right hand, leaning forward; shield on the left hand, facing front.
    objs += attach(objs, arm, "arm-right", spec["weapon"], spec["weapon_scale"],
                   grip=spec.get("grip", 0.12), tilt=math.radians(20), outward=0.02, forward=0.06)
    # Shields sit in front of the (blocky) forearm, not inside it.
    objs += attach(objs, arm, "arm-left", spec["shield"], spec["shield_scale"],
                   grip=spec.get("shield_drop", 0.1), tilt=0.0, outward=0.03, forward=0.15)
    bpy.context.view_layer.update()
    b = rig.bounds([o for o in objs if o.type == "MESH" and o.parent and o.parent.type == "ARMATURE"] or objs)
    k = spec["height"] / max((b[1] - b[0]).z, 1e-3)
    root.scale = (k, k, k)
    bpy.context.view_layer.update()
    W = H = spec["canvas"]
    anchor = (0.5, 0.24)
    rig.frame_camera(W, H, anchor=anchor, target=(0, 0, 0))
    counts = {}
    for name, action, n, loop in CLIPS:
        act = find_action(action)
        if act is None:
            raise RuntimeError(f"{visual}: action {action} missing")
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
                        "healthBarOffsetY": round(spec["height"] * rig.PPU * rig.HEIGHT_SY + 8, 1)}
        json.dump(SPEC, open(SPEC_PATH, "w"), indent=1)
    print("SUMMON", visual, "scale", round(k, 3), flush=True)


for v, spec in SUMMONS.items():
    if ONLY and v != ONLY:
        continue
    bake(v, spec)
print("SUMMONS_DONE")
