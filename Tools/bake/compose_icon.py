"""Composes the macOS app icon from the Blender island render.

  input:  out/icon/island.png (blender/render_icon.py)
  output: EvolutionDefense/Assets.xcassets/AppIcon.appiconset/icon_*.png + Contents.json
          out/icon/icon_1024.png (preview)

Layout follows the macOS icon grid: a 824 × 824 continuous-corner square
centred on a 1024 canvas with a soft drop shadow. The background runs from a
warm primitive-age dusk (top left) to a futuristic teal night (bottom right),
with a glow behind the tower crown and clouds under the island.
"""
import json, math, os
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(ROOT, "..", ".."))
OUT = os.path.join(ROOT, "out", "icon")
DEST = os.path.join(REPO, "EvolutionDefense", "Assets.xcassets", "AppIcon.appiconset")
PART = os.path.join(ROOT, "sources", "kenney-particle-pack", "PNG (Transparent)")
S = 2048                     # work at 2× and downsample
BODY = 824 * 2               # icon body size
OFF = (S - BODY) // 2


def squircle_mask(size, radius=0.225, n=2.6, ss=4):
    """macOS icon shape: straight sides with continuous (superelliptic) corners.
    Corners are superellipse quarter-curves of exponent `n` over `radius` × 1.25
    of the side, which matches Apple's grid closely. Antialiased by supersampling."""
    big = size * ss
    r = radius * 1.25 * big
    y, x = np.mgrid[0:big, 0:big].astype(np.float64) + 0.5
    dx = np.maximum(0, np.maximum(r - x, x - (big - r))) / r
    dy = np.maximum(0, np.maximum(r - y, y - (big - r))) / r
    inside = dx ** n + dy ** n <= 1
    m = Image.fromarray((inside * 255).astype(np.uint8))
    return m.resize((size, size), Image.LANCZOS)


def gradient(size, stops, angle_deg):
    """Linear gradient across the square at `angle_deg` (0 = left→right, 90 = top→bottom)."""
    a = math.radians(angle_deg)
    y, x = np.mgrid[0:size, 0:size] / (size - 1)
    t = (x - 0.5) * math.cos(a) + (y - 0.5) * math.sin(a)
    t = (t - t.min()) / (t.max() - t.min())
    out = np.zeros((size, size, 3))
    pos = [p for p, _ in stops]
    for ch in range(3):
        out[..., ch] = np.interp(t, pos, [c[ch] for _, c in stops])
    return Image.fromarray(out.astype(np.uint8), "RGB").convert("RGBA")


def radial(size, center, radius, color, alpha):
    y, x = np.mgrid[0:size, 0:size]
    d = np.sqrt((x - center[0]) ** 2 + (y - center[1]) ** 2) / radius
    a = np.clip(1 - d, 0, 1) ** 2 * alpha
    img = np.zeros((size, size, 4), np.uint8)
    img[..., :3] = color
    img[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(img, "RGBA")


def cloud(name, size, alpha):
    im = Image.open(os.path.join(PART, name + ".png")).convert("LA").resize(size, Image.LANCZOS)
    L, A = im.split()
    a = ImageChops.multiply(L, A).point(lambda v: min(255, int(v * alpha * 1.6)))
    c = Image.new("RGBA", size, (255, 250, 244, 0))
    c.putalpha(a)
    return c


# ---- body background
body = gradient(BODY, [(0.0, (252, 186, 104)), (0.36, (226, 120, 98)), (0.66, (46, 112, 140)), (1.0, (16, 56, 78))], 62)
island = Image.open(os.path.join(OUT, "island.png")).convert("RGBA")
bb = island.getbbox()
island = island.crop(bb)
k = (BODY * 0.86) / max(island.width, island.height)
island = island.resize((round(island.width * k), round(island.height * k)), Image.LANCZOS)
ix = (BODY - island.width) // 2
iy = round(BODY * 0.53 - island.height / 2)
# Glow behind the crystal crown (upper middle of the island).
crown = (ix + island.width * 0.52, iy + island.height * 0.13)
body.alpha_composite(radial(BODY, crown, BODY * 0.46, (255, 226, 176), 0.70))
body.alpha_composite(radial(BODY, crown, BODY * 0.22, (214, 176, 255), 0.60))
# Clouds drifting under the floating island.
if os.path.isdir(PART):
    for name, (cx, cy), w, a in [("smoke_07", (0.20, 0.86), 0.55, 0.55), ("smoke_08", (0.80, 0.84), 0.6, 0.5),
                                 ("smoke_07", (0.52, 0.95), 0.7, 0.45), ("smoke_04", (0.10, 0.62), 0.35, 0.25),
                                 ("smoke_08", (0.92, 0.55), 0.35, 0.22)]:
        size = (round(BODY * w), round(BODY * w * 0.55))
        c = cloud(name, size, a)
        body.alpha_composite(c, (round(BODY * cx - size[0] / 2), round(BODY * cy - size[1] / 2)))
# Island shadow-free; a faint contact glow under it ties it to the sky.
body.alpha_composite(island, (ix, iy))
# Soft inner vignette and a top highlight for depth.
vign = Image.new("L", (BODY, BODY), 0)
ImageDraw.Draw(vign).rectangle((0, 0, BODY, BODY), outline=255, width=BODY // 18)
vign = vign.filter(ImageFilter.GaussianBlur(BODY / 22))
shade = Image.new("RGBA", (BODY, BODY), (8, 16, 28, 0)); shade.putalpha(vign.point(lambda v: int(v * 0.28)))
body.alpha_composite(shade)
mask = squircle_mask(BODY)
body.putalpha(ImageChops.multiply(body.getchannel("A"), mask))
# Thin rim: light at the top edge, darker at the bottom.
edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(5)))
rim_light = gradient(BODY, [(0, (255, 240, 220)), (1, (10, 20, 30))], 90)
rim_light.putalpha(edge.point(lambda v: int(v * 0.35)))
body.alpha_composite(rim_light)

# ---- canvas with drop shadow
canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sh_mask = Image.new("L", (S, S), 0)
sh_mask.paste(mask, (OFF, OFF + 20))
sh.putalpha(sh_mask.filter(ImageFilter.GaussianBlur(28)).point(lambda v: int(v * 0.42)))
canvas.alpha_composite(sh)
canvas.alpha_composite(body, (OFF, OFF))

os.makedirs(OUT, exist_ok=True)
canvas.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "icon_1024.png"))
os.makedirs(DEST, exist_ok=True)
images = []
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        img = canvas.resize((px, px), Image.LANCZOS)
        if px <= 64:   # small sizes: a touch of sharpening keeps the tower readable
            img = img.filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))
        img.save(os.path.join(DEST, name), optimize=True)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(os.path.join(DEST, "Contents.json"), "w"), indent=2)
print("icon written:", os.path.relpath(DEST, REPO))
