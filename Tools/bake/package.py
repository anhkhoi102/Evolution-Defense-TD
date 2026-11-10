#!/usr/bin/env python3
"""Packages baked renders into the app:

  * trims transparent margins (anchor and size are corrected),
  * writes .spriteatlas folders (SKTextureAtlas) into EvolutionDefense/Assets.xcassets/Baked/,
  * writes the baked asset pack EvolutionDefense/AssetPack/asset_manifest.json.

Sprites the bake hasn't produced yet fall back to the procedural placeholder
pack (asset_manifest.placeholder.json) at runtime.

Input: out/<group>/*.png plus out/<group>/<group>.json (size/anchor per name and
optional per-sprite manifest extras written by the Blender scripts).
"""
import json, math, os, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(ROOT, "..", ".."))
OUT = os.path.join(ROOT, "out")
CATALOG = os.path.join(REPO, "EvolutionDefense", "Assets.xcassets", "Baked")
MANIFEST = os.path.join(REPO, "EvolutionDefense", "AssetPack", "asset_manifest.json")
VIEW = json.load(open(os.path.join(ROOT, "view.json")))
PX = VIEW["pixelScale"]
ENEMY_PX = 1.5   # stored resolution of enemy frames (pixels per point)
E = math.radians(VIEW["elevationDegrees"])

os.makedirs(CATALOG, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}},
          open(os.path.join(CATALOG, "Contents.json"), "w"))


def write_imageset(folder, name, im):
    d = os.path.join(folder, name + ".imageset")
    os.makedirs(d, exist_ok=True)
    im.save(os.path.join(d, name + "@2x.png"), optimize=True)
    json.dump({"images": [{"idiom": "universal", "scale": "1x"},
                          {"filename": name + "@2x.png", "idiom": "universal", "scale": "2x"},
                          {"idiom": "universal", "scale": "3x"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"))


def new_atlas(name):
    d = os.path.join(CATALOG, name + ".spriteatlas")
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(d)
    json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"))
    return d


def trim(path, size_pt, anchor, pad=2):
    """Crops transparent margins. Returns (image, size_pt, anchor) with the
    anchor recomputed so the ground point stays exactly where it was."""
    im = soften(Image.open(path).convert("RGBA"))
    bbox = im.getchannel("A").point(lambda a: 255 if a > 3 else 0).getbbox()
    if not bbox:
        return im, size_pt, anchor
    l, t, r, b = bbox
    l, t = max(0, l - pad), max(0, t - pad)
    r, b = min(im.width, r + pad), min(im.height, b + pad)
    # Even pixel dimensions so @2x maps to whole points.
    if (r - l) % 2:
        r, l = (r + 1, l) if r < im.width else (r, l - 1)
    if (b - t) % 2:
        b, t = (b + 1, t) if b < im.height else (b, t - 1)
    ax_px, ay_px = anchor[0] * im.width, (1 - anchor[1]) * im.height    # anchor in pixels from top-left
    crop = im.crop((l, t, r, b))
    new_anchor = [(ax_px - l) / crop.width, 1 - (ay_px - t) / crop.height]
    return crop, [crop.width / PX, crop.height / PX], new_anchor


def frame(atlas, name):
    return {"atlas": atlas, "name": name}


def union_trim(paths, size_pt, anchor, pad=2):
    """Crops a set of frames to their union bbox (one anchor for all)."""
    ims = [soften(Image.open(p).convert("RGBA")) for p in paths]
    W, H = ims[0].size
    box = None
    for im in ims:
        bb = im.getchannel("A").point(lambda a: 255 if a > 6 else 0).getbbox()
        if bb:
            box = bb if box is None else (min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]), max(box[3], bb[3]))
    if box is None:
        return ims, size_pt, anchor
    l, t, r, b = max(0, box[0] - pad), max(0, box[1] - pad), min(W, box[2] + pad), min(H, box[3] + pad)
    if (r - l) % 2:
        r, l = (r + 1, l) if r < W else (r, l - 1)
    if (b - t) % 2:
        b, t = (b + 1, t) if b < H else (b, t - 1)
    ax, ay = anchor[0] * W, (1 - anchor[1]) * H
    out = [clean_alpha(im.crop((l, t, r, b))) for im in ims]
    return out, [(r - l) / PX, (b - t) / PX], [(ax - l) / (r - l), 1 - (ay - t) / (b - t)]


def soften(im, feather=0.14):
    """Shadow clean-up on a raw render, before trimming:
    * removes the shadow catcher's faint haze (alpha below ~10), and
    * fades semi-transparent pixels (cast shadows) towards the canvas border,
      so a long shadow that runs off the canvas never ends in a hard straight
      edge. Opaque pixels (the model itself) are left alone."""
    import numpy as np
    a = np.asarray(im.getchannel("A"), dtype=np.float32)
    h, w = a.shape
    f = max(4.0, feather * min(w, h))
    ys = np.minimum(np.arange(h), np.arange(h)[::-1])[:, None]
    xs = np.minimum(np.arange(w), np.arange(w)[::-1])[None, :]
    ramp = np.clip(np.minimum(xs, ys) / f, 0, 1)
    ramp = ramp * ramp * (3 - 2 * ramp)                       # smoothstep
    shadow = a < 235
    out = np.where(shadow, np.clip((a - 10) * (255 / 245), 0, 255) * ramp, a)
    im = im.copy()
    im.putalpha(Image.fromarray(out.astype(np.uint8)))
    return im


def clean_alpha(im):
    """Drops the shadow catcher's near-zero alpha haze (visible as faint boxes)."""
    a = im.getchannel("A").point(lambda v: 0 if v < 10 else v)
    im.putalpha(a)
    return im


def sprite_entry(size, anchor, facing, animations, metrics=None):
    d = {"size": {"width": round(size[0], 2), "height": round(size[1], 2)},
         "anchor": {"x": round(anchor[0], 4), "y": round(anchor[1], 4)}, "facing": facing, "animations": animations}
    if metrics:
        d["metrics"] = metrics
    return d


sprites = {}
layout = {
    "view.groundScaleY": round(math.sin(E), 4),
    "view.groundOffsetY": 50,
    "view.heightScale": round(math.cos(E), 4),
    "view.projectileHeight": 22,
}

# ------------------------------------------------------------ environment
env_dir = os.path.join(OUT, "env")
if os.path.exists(os.path.join(env_dir, "env.json")):
    spec = json.load(open(os.path.join(env_dir, "env.json")))
    atlas_dir = new_atlas("Environment")
    # The background is one big image: its own image set, not in an atlas.
    bg = Image.open(os.path.join(env_dir, "background.png")).convert("RGB")
    write_imageset(CATALOG, "env_meadow_background", bg)
    sprites["map.meadow.background"] = {"anchor": {"x": 0, "y": 0}, "facing": "fixed",
                                        "size": {"width": spec["background"]["size"][0], "height": spec["background"]["size"][1]},
                                        "animations": {"default": {"frames": ["env_meadow_background"]}}}

    def env_sprite(file, sid, extra=None):
        s = spec[file]
        im, size, anchor = trim(os.path.join(env_dir, file + ".png"), s["size"], s["anchor"])
        write_imageset(atlas_dir, "env_" + file, clean_alpha(im))
        d = {"size": {"width": size[0], "height": size[1]}, "anchor": {"x": round(anchor[0], 4), "y": round(anchor[1], 4)},
             "facing": "fixed", "animations": {"default": {"frames": [frame("Environment", "env_" + file)]}}}
        if extra:
            d.update(extra)
        if sid:
            sprites[sid] = d
        return d

    env_sprite("slot", "map.slot")
    env_sprite("slot_highlighted", "map.slot.highlighted")
    env_sprite("spawn", "map.spawn")
    for era in ["primitive", "medieval", "industrial", "futuristic"]:
        env_sprite("base_" + era, "base." + era)
    # Trees: one sprite per kind, variants as frames. Frames share a canvas so
    # one anchor works for all (no trimming).
    for kind in ["tree", "pine"]:
        names = sorted(n for n in spec if n.startswith(f"deco_{kind}_"))
        if not names:
            continue
        s = spec[names[0]]
        for n in names:
            write_imageset(atlas_dir, "env_" + n, clean_alpha(soften(Image.open(os.path.join(env_dir, n + ".png")).convert("RGBA"))))
        sprites["deco." + kind] = {"size": {"width": s["size"][0], "height": s["size"][1]},
                                   "anchor": {"x": s["anchor"][0], "y": s["anchor"][1]}, "facing": "fixed",
                                   "animations": {"variants": {"frames": [frame("Environment", "env_" + n) for n in names]}},
                                   "metrics": {"scale": 0.95}}

# ------------------------------------------------------------ towers
tow_dir = os.path.join(OUT, "towers")
if os.path.exists(os.path.join(tow_dir, "towers.json")):
    spec = json.load(open(os.path.join(tow_dir, "towers.json")))
    atlas_dir = new_atlas("Towers")
    for name, t in sorted(spec.items()):
        arch, lvl = name.split("_")
        ims, size, anchor = union_trim([os.path.join(tow_dir, f"{name}_base.png")], t["base"]["size"], t["base"]["anchor"])
        write_imageset(atlas_dir, f"tower_{name}_base", ims[0])
        sprites[f"tower.{arch}.{lvl}.base"] = sprite_entry(size, anchor, "fixed",
                                                            {"default": {"frames": [frame("Towers", f"tower_{name}_base")]}})
        files, names = [], []
        for d in range(16):
            for f in range(3):
                files.append(os.path.join(tow_dir, f"{name}_head_d{d:02d}_f{f}.png"))
                names.append(f"tower_{name}_head_d{d:02d}_f{f}")
        ims, size, anchor = union_trim(files, t["head"]["size"], t["head"]["anchor"])
        for n, im in zip(names, ims):
            write_imageset(atlas_dir, n, im)
        idle = [frame("Towers", f"tower_{name}_head_d{d:02d}_f0") for d in range(16)]
        fire = [frame("Towers", f"tower_{name}_head_d{d:02d}_f{f}") for d in range(16) for f in (1, 2)]
        sprites[f"tower.{arch}.{lvl}.head"] = sprite_entry(size, anchor, "directional", {
            "idle": {"frames": idle, "directions": 16},
            "fire": {"frames": fire, "directions": 16, "fps": 18, "loop": False}},
            {"mountY": t["mountY"], "muzzleDistance": t["muzzleDistance"], "recoil": 0})
    layout.update({"tower.pips.offsetY": -30, "tower.disabledMark.offsetY": 52})

# ------------------------------------------------------------ enemies
en_dir = os.path.join(OUT, "enemies")
if os.path.exists(os.path.join(en_dir, "enemies.json")):
    spec = json.load(open(os.path.join(en_dir, "enemies.json")))
    game = {e["visual"]: e for e in json.load(open(os.path.join(REPO, "Packages", "EvolutionDefenseCore", "Sources",
                                                                 "EvolutionDefenseCore", "Resources", "Config", "enemies.json")))}
    fresh = set()
    for visual, e in sorted(spec.items()):
        era = game.get(visual, {}).get("era", 1)
        atlas = f"Enemies{era}"
        atlas_dir = os.path.join(CATALOG, atlas + ".spriteatlas")
        if atlas not in fresh:
            new_atlas(atlas)
            fresh.add(atlas)
        files, names, anims = [], [], {}
        for clip, n in e["frames"].items():
            for d in range(e["directions"]):
                for f in range(n):
                    files.append(os.path.join(en_dir, f"{visual}_{clip}_d{d}_f{f}.png"))
                    names.append(f"enemy_{visual}_{clip}_d{d}_f{f}")
        ims, size, anchor = union_trim(files, e["size"], e["anchor"])
        # Enemy frames are stored at ENEMY_PX pixels per point (the manifest's
        # size sets the display size). The playfield is shown at ~1.4–1.8 px per
        # point, so @1.5 loses nothing visible and saves ~44 % texture memory.
        k = ENEMY_PX / PX
        for n, im in zip(names, ims):
            if k != 1:
                im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
            write_imageset(atlas_dir, n, im)
        for clip, n in e["frames"].items():
            fr = [frame(atlas, f"enemy_{visual}_{clip}_d{d}_f{f}") for d in range(e["directions"]) for f in range(n)]
            a = {"frames": fr, "directions": e["directions"]}
            if clip == "walk":
                a["distancePerFrame"] = e["walkDistance"]
            else:
                a.update({"fps": 12, "loop": False})
            anims[clip] = a
        r = game.get(visual, {}).get("radius", 16)
        boss = game.get(visual, {}).get("isBoss", False)
        sprites[f"enemy.{visual}"] = sprite_entry(size, anchor, "directional", anims, {
            "healthBarOffsetY": e["healthBarOffsetY"], "healthBarWidth": 70 if boss else round(max(24, r * 1.9), 1),
            "shieldDiameter": round(r * 2.8, 1), "shieldOffsetY": round(e["healthBarOffsetY"] * 0.45, 1)})

# ------------------------------------------------------------ summoned allies (Docs/SUMMONS.md)
su_dir = os.path.join(OUT, "summons")
if os.path.exists(os.path.join(su_dir, "summons.json")):
    spec = json.load(open(os.path.join(su_dir, "summons.json")))
    atlas_dir = new_atlas("Summons")
    # clip → (fps, loops). Walk is time-based: summons move at their own pace.
    CLIP_TIMING = {"idle": (6, True), "walk": (10, True), "attack": (14, False), "death": (12, False)}
    for visual, e in sorted(spec.items()):
        files, names = [], []
        for clip, n in e["frames"].items():
            for d in range(e["directions"]):
                for f in range(n):
                    files.append(os.path.join(su_dir, f"{visual}_{clip}_d{d}_f{f}.png"))
                    names.append(f"summon_{visual}_{clip}_d{d}_f{f}")
        ims, size, anchor = union_trim(files, e["size"], e["anchor"])
        k = ENEMY_PX / PX
        for n, im in zip(names, ims):
            if k != 1:
                im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
            write_imageset(atlas_dir, n, im)
        anims = {}
        for clip, n in e["frames"].items():
            fps, loops = CLIP_TIMING.get(clip, (10, True))
            anims[clip] = {"frames": [frame("Summons", f"summon_{visual}_{clip}_d{d}_f{f}")
                                      for d in range(e["directions"]) for f in range(n)],
                           "directions": e["directions"], "fps": fps, "loop": loops}
        sprites[f"summon.{visual}"] = sprite_entry(size, anchor, "directional", anims, {
            "healthBarOffsetY": e["healthBarOffsetY"], "healthBarWidth": 34 if visual == "knight" else 22})

# ------------------------------------------------------------ combat: projectiles + effects
PART = os.path.join(ROOT, "sources", "kenney-particle-pack", "PNG (Transparent)")
pr_dir = os.path.join(OUT, "projectiles")


def particle(name, size_pt, ramp, rotate=0, squash=None, gain=1.0):
    """Kenney particle texture → RGBA sprite of `size_pt` points. `ramp` maps the
    texture's brightness to colour (dark → bright stops, sRGB 0-255); the
    texture's own alpha × brightness becomes the alpha."""
    im = Image.open(os.path.join(PART, name + ".png")).convert("LA")
    if rotate:
        im = im.rotate(rotate, expand=True)
    w, h = int(round(size_pt[0] * PX)), int(round(size_pt[1] * PX))
    if squash:   # fit a long thin texture into a streak canvas
        bb = im.getbbox()
        im = im.crop(bb)
    im = im.resize((w, h), Image.LANCZOS)
    L, A = im.split()
    lum = L.load(); al = A.load()
    out = Image.new("RGBA", (w, h))
    px = out.load()
    stops = ramp
    for y in range(h):
        for x in range(w):
            v = lum[x, y] / 255
            a = al[x, y] / 255 * v * gain
            if a <= 0.004:
                continue
            t = min(1.0, v) * (len(stops) - 1)
            i = min(int(t), len(stops) - 2)
            f = t - i
            c = [stops[i][k] + (stops[i + 1][k] - stops[i][k]) * f for k in range(3)]
            px[x, y] = (int(c[0]), int(c[1]), int(c[2]), int(min(1.0, a) * 255))
    return out


def fx_entry(atlas, name, size, anchor=(0.5, 0.5), facing="fixed", motion=None, tint=None, metrics=None):
    d = sprite_entry(size, anchor, facing, {"default" if facing == "fixed" else "flight": {"frames": [frame(atlas, name)]}}, metrics)
    if motion:
        d["motion"] = motion
    if tint:
        d["tint"] = tint
    return d


if os.path.exists(os.path.join(pr_dir, "projectiles.json")) and os.path.isdir(PART):
    atlas_dir = new_atlas("Combat")
    pspec = json.load(open(os.path.join(pr_dir, "projectiles.json")))
    WHITE = [(150, 150, 150), (255, 255, 255)]
    WARM = [(255, 120, 30), (255, 200, 90), (255, 250, 220)]
    FIRE = [(120, 30, 10), (240, 90, 20), (255, 180, 60), (255, 245, 200)]
    SMOKE = [(70, 66, 60), (150, 142, 130), (205, 198, 186)]
    CYAN = [(20, 120, 220), (90, 220, 255), (235, 255, 255)]
    RED = [(200, 20, 20), (255, 90, 80), (255, 235, 230)]
    BLUE = [(30, 90, 230), (110, 190, 255), (240, 250, 255)]
    GREEN = [(40, 160, 60), (140, 240, 120), (240, 255, 235)]

    # --- effects (sizes match the placeholder art so the effect code's scales still hold)
    fxs = {
        "explosion": ("fire_01", (64, 64), FIRE, 0, 1.6),
        "puff":      ("smoke_04", (48, 48), SMOKE, 0, 1.3),
        "spark":     ("star_06", (20, 20), [(255, 230, 170), (255, 255, 255)], 0, 1.4),
        "ring":      ("circle_02", (128, 128), WHITE, 0, 1.2),
        "shield":    ("light_03", (64, 64), CYAN, 0, 1.0),
        "muzzle":    ("muzzle_02", (22, 22), [(255, 210, 120), (255, 255, 255)], -90, 1.5),
        "ember":     ("star_04", (12, 12), [(255, 200, 120), (255, 255, 255)], 0, 1.6),
        "smoke":     ("smoke_07", (32, 32), SMOKE, 0, 1.0),
        "scorch":    ("scorch_02", (56, 56), [(20, 16, 12), (50, 42, 34)], 0, 1.4),
    }
    for key, (src, size, ramp, rot, gain) in fxs.items():
        im = particle(src, size, ramp, rotate=rot, gain=gain)
        write_imageset(atlas_dir, "fx_" + key, im)
        sprites["fx." + key] = fx_entry("Combat", "fx_" + key, size)

    # --- physical projectiles (baked); the kit's lilac steel → neutral steel
    def steel(im):
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                r, g, b, a = px[x, y]
                if a and b > r + 18 and b > g + 8:
                    v = (r + g + b) // 3 + 12
                    px[x, y] = (v, v + 2, v + 6, a)
        return im
    lobbed = {"stone", "boulder", "cannonball", "shell"}
    warm_tint = {"cannonball", "shell", "heavyShell", "rocket"}
    for visual, p in pspec.items():
        im = steel(Image.open(os.path.join(pr_dir, visual + ".png")).convert("RGBA"))
        im = clean_alpha(im)
        if visual == "rocket":   # exhaust flame behind the body
            flame = particle("muzzle_02", (20, 12), FIRE, rotate=90, squash=True, gain=1.6)
            pad = flame.width
            base = Image.new("RGBA", (im.width + 2 * pad, im.height))
            cx, cy = base.width // 2, base.height // 2
            body_left = cx - int(p["length"] / 2 * PX)
            base.paste(flame, (body_left - flame.width + 16, cy - flame.height // 2), flame)
            base.alpha_composite(im, (pad, 0))
            im = base
        bb = im.getbbox()
        # keep the canvas centred on the flight axis so rotation pivots correctly
        hw = max(bb[2] - im.width // 2, im.width // 2 - bb[0]) + 2
        hh = max(bb[3] - im.height // 2, im.height // 2 - bb[1]) + 2
        im = im.crop((im.width // 2 - hw, im.height // 2 - hh, im.width // 2 + hw, im.height // 2 + hh))
        write_imageset(atlas_dir, "projectile_" + visual, im)
        metrics = {"spinPerSecond": 15} if visual in ("stone", "boulder") else None
        sprites["projectile." + visual] = fx_entry("Combat", "projectile_" + visual, (im.width / PX, im.height / PX),
                                                   facing="rotate", motion="arc" if visual in lobbed else "straight",
                                                   tint="#FFBF59" if visual in warm_tint else None, metrics=metrics)

    # --- energy projectiles (particle textures); (length, width) in points like the placeholders + glow pad
    energy = {
        "laser":       ("trace_01", (36, 10), RED, "#FF5A50"),
        "railSlug":    ("trace_06", (44, 12), BLUE, "#80C8FF"),
        "orbitalBeam": ("spark_07", (48, 18), CYAN, "#80E6FF"),
        "bullet":      ("trace_02", (20, 8), WARM, "#FFBF59"),
        "plasmaOrb":   ("magic_05", (24, 24), CYAN, "#80E6FF"),
    }
    for visual, (src, size, ramp, tint) in energy.items():
        rot = 90 if src.startswith("trace") else 0
        im = particle(src, size, ramp, rotate=rot, squash=src.startswith("trace") or src == "spark_07",
                      gain=3.0 if src.startswith("trace") else 1.8)
        write_imageset(atlas_dir, "projectile_" + visual, im)
        sprites["projectile." + visual] = fx_entry("Combat", "projectile_" + visual, size, facing="rotate",
                                                   motion="arc" if visual == "plasmaOrb" else "straight", tint=tint,
                                                   metrics={"spinPerSecond": 15} if visual == "plasmaOrb" else None)
    # boss missile reuses the rocket art at twice the size
    if "projectile.rocket" in sprites:
        m = json.loads(json.dumps(sprites["projectile.rocket"]))
        m["size"] = {"width": m["size"]["width"] * 1.8, "height": m["size"]["height"] * 1.8}
        m["facing"] = "fixed"; m.pop("motion", None); m.pop("tint", None)
        m["animations"] = {"default": m["animations"]["flight"]}
        sprites["fx.missile"] = m

# Groups baked later (projectiles, fx) drop their own
# manifest fragments here.
for frag in sorted(f for f in os.listdir(OUT) if f.endswith(".manifest.json")):
    data = json.load(open(os.path.join(OUT, frag)))
    sprites.update(data.get("sprites", {}))
    layout.update(data.get("layout", {}))

manifest = {"version": 1, "name": "Evolution Defense 2.5D (baked from CC0 kits)", "textureScale": PX,
            "layout": layout, "sprites": dict(sorted(sprites.items()))}
json.dump(manifest, open(MANIFEST, "w"), indent=1)
print(f"packaged {len(sprites)} sprites → {os.path.relpath(MANIFEST, REPO)}")
