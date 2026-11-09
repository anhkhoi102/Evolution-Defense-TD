"""Composites base + head (direction d) for quick review of baked towers."""
import json, sys, os
from PIL import Image, ImageDraw
OUT = "out/towers"; spec = json.load(open(f"{OUT}/towers.json"))
names = sys.argv[1:] or sorted(spec)
dirs = [0, 2, 4, 6, 10, 13]
cellw, cellh = 192, 260
sheet = Image.new("RGB", (cellw * len(dirs), cellh * len(names)), (96, 150, 70))
for r, n in enumerate(names):
    s = spec[n]
    base = Image.open(f"{OUT}/{n}_base.png").convert("RGBA")
    for c, d in enumerate(dirs):
        head = Image.open(f"{OUT}/{n}_head_d{d:02d}_f0.png").convert("RGBA")
        canvas = Image.new("RGBA", (cellw, cellh))
        gx, gy = cellw // 2, cellh - 40                       # ground point
        bx = gx - int(s["base"]["anchor"][0] * base.width); by = gy - int((1 - s["base"]["anchor"][1]) * base.height)
        canvas.alpha_composite(base, (bx, by))
        my = gy - int(s["mountY"] * 2)
        hx = gx - int(s["head"]["anchor"][0] * head.width); hy = my - int((1 - s["head"]["anchor"][1]) * head.height)
        canvas.alpha_composite(head, (hx, max(0, hy)))
        sheet.paste(canvas, (c * cellw, r * cellh), canvas)
    ImageDraw.Draw(sheet).text((4, r * cellh + 4), n, fill=(255, 255, 255))
sheet.save("out/towers_preview.png"); print(sheet.size)
