"""Renders a list of models (one per cell) for choosing parts.
blender -b -P contact_sheet.py -- out_dir model1.glb model2.glb ..."""
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import rig
argv = sys.argv[sys.argv.index("--") + 1:]
out, models = argv[0], argv[1:]
os.makedirs(out, exist_ok=True)
for m in models:
    rig.reset()
    rig.shadow_catcher(8)
    root, objs = rig.import_model(m)
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in objs if o.type == "MESH" for v in o.data.vertices]
    size = max(max(p.x for p in pts) - min(p.x for p in pts), max(p.y for p in pts) - min(p.y for p in pts),
               (max(p.z for p in pts)) * 1.2, 0.5)
    pt = size * rig.PPU * 1.35
    rig.frame_camera(pt, pt, anchor=(0.5, 0.3))
    rig.bpy.context.scene.render.resolution_x = 220
    rig.bpy.context.scene.render.resolution_y = 220
    rig.render_to(os.path.join(out, os.path.splitext(os.path.basename(m))[0] + ".png"))
