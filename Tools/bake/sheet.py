"""Composes rendered cells into one labelled contact sheet (PIL)."""
import sys, os
from PIL import Image, ImageDraw
d, out = sys.argv[1], sys.argv[2]
files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
cols = 8
cell = 220
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cell, rows * (cell + 16)), (92, 120, 70))
draw = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(os.path.join(d, f)).convert("RGBA")
    x, y = (i % cols) * cell, (i // cols) * (cell + 16)
    sheet.paste(im, (x, y), im)
    draw.text((x + 4, y + cell), f[:-4][:34], fill=(255, 255, 255))
sheet.save(out)
print("sheet", out, len(files))
