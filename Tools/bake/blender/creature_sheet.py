"""Poses each rigged model at the middle of a walk-like action and renders it."""
import bpy, sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
import rig
argv = sys.argv[sys.argv.index("--") + 1:]
out, models = argv[0], argv[1:]
os.makedirs(out, exist_ok=True)
for m in models:
    rig.reset(); rig.shadow_catcher(30)
    root, objs = rig.import_model(m)
    arm = next((o for o in objs if o.type == "ARMATURE"), None)
    acts = list(bpy.data.actions)
    act = next((a for a in acts if re.search(r"walk|run|fly|gallop", a.name, re.I)), acts[0] if acts else None)
    if arm and act:
        arm.animation_data_create(); arm.animation_data.action = act
        try:
            arm.animation_data.action_slot = act.slots[0]
        except Exception: pass
        bpy.context.scene.frame_set(int((act.frame_range[0] + act.frame_range[1]) / 2))
    bpy.context.view_layer.update()
    b = rig.bounds(objs)
    if not b: continue
    mn, mx = b
    # Normalise every creature to ~1.6 units long so the sheet compares shapes.
    span = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
    k = 1.6 / span
    root.scale = (k, k, k)
    root.rotation_euler.z = -0.6
    size = 2.4
    pt = size * rig.PPU
    rig.frame_camera(pt, pt, anchor=(0.5, 0.3))
    bpy.context.scene.render.resolution_x = bpy.context.scene.render.resolution_y = 220
    name = os.path.splitext(os.path.basename(m))[0]
    rig.render_to(os.path.join(out, f"{name}.png"))
    print("CREATURE", name, act.name if act else None)
