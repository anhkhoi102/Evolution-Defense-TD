import bpy, sys, os, time, math
sys.path.insert(0, os.path.dirname(__file__))
import rig
SRC = os.path.join(os.path.dirname(__file__), "..", "sources", "kenney-tower-defense-kit", "Models", "GLB format")
OUT = os.path.join(os.path.dirname(__file__), "..", "out", "test")
os.makedirs(OUT, exist_ok=True)
rig.reset()
rig.shadow_catcher()
z = 0
for part in ["tower-round-bottom-a", "tower-round-middle-a", "tower-round-top-a"]:
    root, objs = rig.import_model(os.path.join(SRC, part + ".glb"))
    root.location.z = z
    bpy.context.view_layer.update()
    # Stack parts by their height.
    zs = [ (o.matrix_world @ v.co).z for o in objs if o.type == "MESH" for v in o.data.vertices ]
    z = max(zs) if zs else z + 0.5
root, _ = rig.import_model(os.path.join(SRC, "weapon-cannon.glb"))
root.location.z = z
root.rotation_euler.z = math.radians(30)
rig.frame_camera(80, 110, anchor=(0.5, 0.2))
for i in range(3):
    root.rotation_euler.z = math.radians(30 + i * 45)
    t = time.time()
    rig.render_to(os.path.join(OUT, f"tower{i}.png"))
    print("RENDER_TIME", round(time.time() - t, 2), "top", round(z, 3))
