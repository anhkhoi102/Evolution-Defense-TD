"""Converts every source texture to graded RGBA PNGs in out/textures/<pack>/…
(Blender can't read Kenney's 8-bit indexed PNGs). Run with system python3."""
import os, sys
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from palette import grade_srgb8
ROOT = os.path.dirname(os.path.abspath(__file__))
SRC, OUT = os.path.join(ROOT, "sources"), os.path.join(ROOT, "out", "textures")
n = 0
for dirpath, _, files in os.walk(SRC):
    for f in files:
        if not f.lower().endswith(".png") or "Textures" not in dirpath:
            continue
        rel = os.path.relpath(os.path.join(dirpath, f), SRC)
        dst = os.path.join(OUT, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        im = Image.open(os.path.join(dirpath, f)).convert("RGBA")
        lut = {}
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                c = px[x, y]
                if c not in lut:
                    lut[c] = grade_srgb8(c)
                px[x, y] = lut[c]
        im.save(dst)
        n += 1
print("prepared", n, "textures")
