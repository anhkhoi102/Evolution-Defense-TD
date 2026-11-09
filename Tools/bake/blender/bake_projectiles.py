"""Stage 4 — physical projectiles (wood, stone, metal) baked from the Kenney kits.

Each projectile is rendered lying along +x (tip pointing right), seen from
slightly above, at the same point size as the placeholder art it replaces, so
the game's in-plane rotation keeps working. Energy projectiles (laser, plasma,
rail, beam, bullet tracer) are made from particle textures in package.py.

  out/projectiles/<visual>.png
  out/projectiles/projectiles.json   size (pt) per visual

blender -b --factory-startup -P bake_projectiles.py
"""
import bpy, json, math, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(__file__))
import rig

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "out", "projectiles")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "sources")
TD = os.path.join(SRC, "kenney-tower-defense-kit", "Models", "GLB format")
MINI = os.path.join(SRC, "kenney-mini-characters", "Models", "GLB format")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = next((a.split("=", 1)[1] for a in argv if a.startswith("only=")), None)

# visual: model, length in points along the flight axis, flip (tip points −x in the source), colour override
P = {
    "arrow":        dict(src=os.path.join(MINI, "weapon-arrow.glb"), length=20),
    "longArrow":    dict(src=os.path.join(MINI, "weapon-arrow.glb"), length=25),
    "bolt":         dict(src=os.path.join(TD, "weapon-ammo-arrow.glb"), length=15),
    "ballistaBolt": dict(src=os.path.join(TD, "weapon-ammo-arrow.glb"), length=34),
    "spear":        dict(src=os.path.join(MINI, "weapon-spear.glb"), length=32),
    "stone":        dict(src=os.path.join(TD, "weapon-ammo-boulder.glb"), length=10, color=(0.56, 0.54, 0.50)),
    "boulder":      dict(src=os.path.join(TD, "weapon-ammo-boulder.glb"), length=14, color=(0.50, 0.48, 0.45)),
    "cannonball":   dict(src=os.path.join(TD, "weapon-ammo-cannonball.glb"), length=10, color=(0.20, 0.21, 0.23)),
    "pellet":       dict(src=os.path.join(TD, "weapon-ammo-cannonball.glb"), length=6),
    "shell":        dict(src=os.path.join(TD, "weapon-ammo-bullet.glb"), length=13),
    "heavyShell":   dict(src=os.path.join(TD, "weapon-ammo-bullet.glb"), length=16, color=(0.26, 0.28, 0.31)),
    "rocket":       dict(src=os.path.join(TD, "weapon-ammo-bullet.glb"), length=18, color=(0.78, 0.80, 0.84)),
}
FLIP = {}   # filled after the orientation check (visual → True)
SPEC_PATH = os.path.join(OUT, "projectiles.json")
SPEC = json.load(open(SPEC_PATH)) if os.path.exists(SPEC_PATH) else {}


def bake(visual, spec):
    s = rig.reset()
    s.cycles.samples = 24
    root, objs = rig.import_model(spec["src"])
    b = rig.bounds(objs)
    size = b[1] - b[0]
    # Lay the long axis along x. Upright models (spear, arrow stored vertically) are tipped over.
    if size.z > max(size.x, size.y):
        root.rotation_euler.y = math.pi / 2
    elif size.y > size.x:
        root.rotation_euler.z = math.pi / 2
    if spec.get("flip"):
        root.rotation_euler.z += math.pi
    bpy.context.view_layer.update()
    b = rig.bounds(objs)
    size = b[1] - b[0]
    k = spec["length"] / rig.PPU / max(size.x, 1e-4)
    root.scale = (k, k, k)
    bpy.context.view_layer.update()
    b = rig.bounds(objs)
    c = (b[0] + b[1]) / 2
    root.location -= Vector((c.x, c.y, 0))
    bpy.context.view_layer.update()
    b = rig.bounds(objs)
    for o in objs:
        for sl in getattr(o, "material_slots", []):
            m = sl.material
            bsdf = m and m.node_tree and next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if not bsdf:
                continue
            sock = bsdf.inputs["Base Color"]
            col = spec.get("color")
            if col is None and not sock.is_linked:
                r, g, bl = [rig._srgb(x) for x in sock.default_value[:3]]
                if bl > r + 0.08:          # the kit's lilac "metal" → steel
                    col = (0.70, 0.72, 0.76)
                    bsdf.inputs["Metallic"].default_value = 0.3
            if col is not None:
                for l in list(sock.links):
                    m.node_tree.links.remove(l)
                sock.default_value = tuple(rig._lin(x) for x in col) + (1,)
    w = spec["length"] + 6
    h = max((b[1].y - b[0].y) * rig.PPU, 4) + 6
    w = h = max(w, h)           # square canvas: rotation never clips
    s.render.resolution_x = s.render.resolution_y = int(round(w * rig.PX))
    cam = s.camera
    cam.data.ortho_scale = w / rig.PPU
    cam.rotation_euler = (math.radians(20), 0, 0)      # mostly top-down, a hint of the side
    zc = (b[0].z + b[1].z) / 2
    m = cam.rotation_euler.to_matrix()
    cam.location = Vector((0, 0, zc)) + m.col[2] * 30
    rig.render_to(os.path.join(OUT, visual + ".png"))
    SPEC[visual] = {"size": [w, w], "length": spec["length"]}
    json.dump(SPEC, open(SPEC_PATH, "w"), indent=1)
    print("PROJECTILE", visual, round(k, 3), flush=True)


for v, spec in P.items():
    if ONLY and v != ONLY:
        continue
    bake(v, spec)
print("PROJECTILES_DONE")
