"""Stage 3 — towers. For each archetype × level:

  out/towers/<arch>_<lvl>_base.png                static platform (anchored at the ground point)
  out/towers/<arch>_<lvl>_head_d<dd>_f<f>.png     weapon/crew, 16 aim directions × (idle + 2 fire frames),
                                                  anchored at the mount point
  out/towers/towers.json                          sizes, anchors, mountY (screen points)

Bases share a material language per level (wood → stone → steel → alloy) and
carry the archetype's identity colour on their trim; heads differ per
archetype and level, so every upgrade is visibly distinct.

blender -b --factory-startup -P bake_towers.py [-- only=<arch>[_<lvl>]]
"""
import bpy, json, math, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(__file__))
import rig

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "out", "towers")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "sources")
TDK = os.path.join(SRC, "kenney-tower-defense-kit", "Models", "GLB format")
CAS = os.path.join(SRC, "kenney-castle-kit", "Models", "GLB format")
SPC = os.path.join(SRC, "kenney-space-kit", "Models", "GLTF format")
BLA = os.path.join(SRC, "kenney-blaster-kit", "Models", "GLB format")
MIN = os.path.join(SRC, "kenney-mini-characters", "Models", "GLB format")
NAT = os.path.join(SRC, "kenney-nature-kit", "Models", "GLTF format")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = next((a.split("=", 1)[1] for a in argv if a.startswith("only=")), None)
DIRS = 16
SPEC_PATH = os.path.join(OUT, "towers.json")
SPEC = json.load(open(SPEC_PATH)) if os.path.exists(SPEC_PATH) else {}

ACCENT = {"splash": (0.93, 0.52, 0.16), "sniper": (0.34, 0.68, 0.30), "heavy": (0.80, 0.24, 0.20), "rapid": (0.24, 0.55, 0.85)}


def T(n): return os.path.join(TDK, n + ".glb")
def C(n): return os.path.join(CAS, n + ".glb")
def S(n): return os.path.join(SPC, n + ".glb")
def B(n): return os.path.join(BLA, n + ".glb")
def M(n): return os.path.join(MIN, n + ".glb")
def N(n): return os.path.join(NAT, n + ".glb")


def place(path, loc=(0, 0, 0), rot=0.0, scale=1.0, parent=None):
    root = rig.instance(path)
    root.location = loc
    root.rotation_euler.z = rot
    root.scale = (scale, scale, scale)
    if parent is not None:
        root.parent = parent
    return root


def lin(c): return tuple(rig._lin(x) for x in c) + (1,)


def emissive(name, color, strength=2.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(color)
    b.inputs["Emission Color"].default_value = lin(color)
    b.inputs["Emission Strength"].default_value = strength
    return m


def glow_orb(loc, radius, color, parent=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=loc)
    o = bpy.context.active_object
    o.data.materials.append(emissive("Glow", color))
    if parent is not None:
        o.parent = parent
    return o


def recolor_accent(objs, color):
    """Kenney trims (orange/purple accents) take the archetype colour."""
    for o in objs:
        if o.type != "MESH":
            continue
        for sl in o.material_slots:
            m = sl.material
            if not m or not m.node_tree:
                continue
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE":
                    # Texture-mapped Kenney parts: tint the bright accent texels via a hue-keyed mix.
                    nt = m.node_tree
                    bsdf = next(x for x in nt.nodes if x.type == "BSDF_PRINCIPLED")
                    sep = nt.nodes.new("ShaderNodeSeparateColor"); sep.mode = "HSV"
                    nt.links.new(n.outputs["Color"], sep.inputs["Color"])
                    # mask = saturation > 0.45 (accent colours; stone/wood are less saturated)
                    # Accent texels are both saturated and bright (wood is darker).
                    gt_s = nt.nodes.new("ShaderNodeMath"); gt_s.operation = "GREATER_THAN"; gt_s.inputs[1].default_value = 0.6
                    nt.links.new(sep.outputs["Green"], gt_s.inputs[0])
                    gt_v = nt.nodes.new("ShaderNodeMath"); gt_v.operation = "GREATER_THAN"; gt_v.inputs[1].default_value = 0.62
                    nt.links.new(sep.outputs["Blue"], gt_v.inputs[0])
                    gt = nt.nodes.new("ShaderNodeMath"); gt.operation = "MULTIPLY"
                    nt.links.new(gt_s.outputs[0], gt.inputs[0]); nt.links.new(gt_v.outputs[0], gt.inputs[1])
                    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "COLOR"
                    nt.links.new(gt.outputs[0], mix.inputs["Factor"])
                    nt.links.new(n.outputs["Color"], mix.inputs["A"])
                    mix.inputs["B"].default_value = lin(color)
                    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
                    break


def all_objs(root):
    out = [root]
    for c in root.children_recursive:
        out.append(c)
    return out


def top_of(objs):
    b = rig.bounds(objs)
    return b[1].z if b else 0.0


def stack(parts, x=0, y=0, scale=1.0, rot=0.0):
    """Stacks parts bottom-up; returns (objects, top height)."""
    z = 0.0
    objs = []
    for p in parts:
        r = place(p, (x, y, z), rot, scale)
        bpy.context.view_layer.update()
        o = all_objs(r)
        objs += o
        z = top_of(o)
    return objs, z


# ------------------------------------------------------------------ recipes
# Bases by level: (parts bottom→top, scale)
BASES = {
    1: ([C("tower-hexagon-top-wood")], 0.9),
    2: ([T("tower-round-bottom-a"), C("tower-hexagon-top-wood")], 0.9),
    3: ([T("tower-round-bottom-a"), T("tower-round-top-a")], 0.95),
    4: ([T("tower-square-bottom-b"), T("tower-square-top-b")], 0.95),
    5: ([T("tower-round-bottom-c"), T("tower-round-crystals")], 0.95),
}


def crew(model, weapon, scale=0.62, count=1):
    """Tower crew: Kenney mini characters (≈1.67 units tall at scale 1) holding
    a weapon at chest height, facing +x."""
    def build(parent):
        offsets = [0.0] if count == 1 else [-0.16, 0.16]
        for oy in offsets:
            place(M(model), (0, oy, 0), FACE, scale, parent)
            if weapon:
                place(M(weapon), (0.3 * scale, oy - 0.12 * scale, 0.95 * scale), FACE, scale * 1.6, parent)
    return build


HEAD_SCALE = 1.3
FACE = math.pi / 2     # Kenney weapons point along −y; this turns them to +x (game angle 0)


def single(path, scale=1.0, rot=FACE, z=0.0, orb=None):
    def build(parent):
        r = place(path, (0, 0, z), rot, scale * HEAD_SCALE, parent)
        if orb:
            glow_orb(tuple(v * HEAD_SCALE for v in orb[0]), orb[1] * HEAD_SCALE, orb[2], parent)
        return r
    return build


def double(path, scale=1.0, gap=0.28, rot=FACE):
    def build(parent):
        place(path, (0, gap / 2 * HEAD_SCALE, 0), rot, scale * HEAD_SCALE, parent)
        place(path, (0, -gap / 2 * HEAD_SCALE, 0), rot, scale * HEAD_SCALE, parent)
    return build


CYAN, RED, AMBER = (0.35, 0.9, 1.0), (1.0, 0.25, 0.2), (1.0, 0.7, 0.25)
# Kenney TD weapons point along −y in model space, so heads rotate −90° to face +x (game angle 0).
HEADS = {
    ("splash", 1): single(T("weapon-catapult"), 0.7),
    ("splash", 2): single(T("weapon-catapult"), 0.95),
    ("splash", 3): single(T("weapon-cannon"), 1.0),
    ("splash", 4): double(T("weapon-cannon"), 0.85, 0.36),
    ("splash", 5): single(S("turret_double"), 0.9, orb=((0.28, 0, 0.32), 0.1, CYAN)),
    ("sniper", 1): crew("character-male-a", "weapon-bow"),
    ("sniper", 2): crew("character-male-c", "weapon-bow", 0.7),
    ("sniper", 3): single(T("weapon-ballista"), 0.9),
    ("sniper", 4): single(B("blaster-k"), 1.6, z=0.12),
    ("sniper", 5): single(S("weapon_rifle"), 1.5, z=0.1, orb=((0.5, 0, 0.18), 0.06, CYAN)),
    ("heavy", 1): single(T("weapon-ballista"), 0.7),
    ("heavy", 2): single(C("siege-ballista"), 0.55),
    ("heavy", 3): single(T("weapon-cannon"), 1.3),
    ("heavy", 4): single(S("turret_double"), 1.0),
    ("heavy", 5): single(S("satelliteDish_detailed"), 0.6, rot=0, orb=((0, 0, 0.62), 0.08, CYAN)),
    ("rapid", 1): crew("character-male-b", "weapon-spear", 0.55, count=2),
    ("rapid", 2): crew("character-soldier", "weapon-bow", 0.6, count=2),
    ("rapid", 3): single(T("weapon-turret"), 0.85),
    ("rapid", 4): double(T("weapon-turret"), 0.7, 0.3),
    ("rapid", 5): single(S("turret_single"), 1.0, orb=((0.3, 0, 0.3), 0.07, RED)),
}

BASE_W, BASE_H, BASE_ANCHOR = 96, 130, (0.5, 0.18)
HEAD_W, HEAD_H = 96, 96


def bake(arch, lvl):
    name = f"{arch}_{lvl}"
    # ---- base
    s = rig.reset()
    s.cycles.samples = 32
    rig.shadow_catcher(10)
    parts, sc = BASES[lvl]
    objs, top = stack(parts, scale=sc)
    recolor_accent([o for o in objs if "tower-" in (o.name + (o.parent.name if o.parent else "")) and "hexagon" not in o.name], ACCENT[arch])
    rig.frame_camera(BASE_W, BASE_H, anchor=BASE_ANCHOR, target=(0, 0, 0))
    rig.render_to(os.path.join(OUT, name + "_base.png"))
    mount_z = top
    # ---- head (16 directions × idle + 2 fire frames), with the base hidden but
    # still casting its shadow-free context: only the weapon is rendered.
    s = rig.reset()
    s.cycles.samples = 24
    pivot = bpy.data.objects.new("Pivot", None)
    s.collection.objects.link(pivot)
    pivot.location = (0, 0, mount_z)
    HEADS[(arch, lvl)](pivot)
    bpy.context.view_layer.update()
    rig.frame_camera(HEAD_W, HEAD_H, anchor=(0.5, 0.45), target=(0, 0, mount_z))
    for d in range(DIRS):
        a = d / DIRS * math.tau
        for f, (back, pitch) in enumerate([(0, 0), (0.07, 0.12), (0.035, 0.05)]):
            pivot.rotation_euler = (0, pitch, a)
            pivot.location = (-math.cos(a) * back, -math.sin(a) * back, mount_z)
            rig.render_to(os.path.join(OUT, f"{name}_head_d{d:02d}_f{f}.png"))
    SPEC[name] = {
        "base": {"size": [BASE_W, BASE_H], "anchor": list(BASE_ANCHOR)},
        "head": {"size": [HEAD_W, HEAD_H], "anchor": [0.5, 0.45]},
        # Screen offset of the mount point above the tower's ground point.
        "mountY": round(mount_z * rig.PPU * rig.HEIGHT_SY, 2),
        "muzzleDistance": 22,
    }
    json.dump(SPEC, open(SPEC_PATH, "w"), indent=1)
    print("TOWER", name, "mountZ", round(mount_z, 3), flush=True)


for arch in ["splash", "sniper", "heavy", "rapid"]:
    for lvl in range(1, 6):
        key = f"{arch}_{lvl}"
        if ONLY and not (ONLY == arch or ONLY == key):
            continue
        bake(arch, lvl)
print("TOWERS_DONE")
