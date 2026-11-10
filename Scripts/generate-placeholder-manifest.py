#!/usr/bin/env python3
"""Writes EvolutionDefense/AssetPack/asset_manifest.json: the default asset pack,
which maps every game entity to a procedural (code-drawn) placeholder.

Run again after adding enemies, tower levels or projectiles to the game data.
A replacement art pack doesn't edit this file: it ships an override manifest
(see Docs/ASSETS.md)."""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = os.path.join(ROOT, "Packages/EvolutionDefenseCore/Sources/EvolutionDefenseCore/Resources/Config")
OUT = os.path.join(ROOT, "EvolutionDefense/AssetPack/asset_manifest.placeholder.json")

def proc(gen, **kw):
    d = {"procedural": gen}
    d.update({k: v for k, v in kw.items() if v is not None})
    return d

sprites = {}

# Enemies: 4-frame walk cycle advanced by distance travelled.
for e in json.load(open(os.path.join(CFG, "enemies.json"))):
    r = e["radius"]
    sprites[f"enemy.{e['visual']}"] = {
        "facing": "rotate",
        "animations": {"walk": {"frames": [proc("creature", key=e["visual"], radius=r, frame=i) for i in range(4)],
                                "distancePerFrame": round(max(6, r * 0.75), 2)}},
        "metrics": {"healthBarOffsetY": r + 9,
                    "healthBarWidth": 70 if e["isBoss"] else round(max(24, r * 1.9), 1),
                    "shieldDiameter": round(r * 2.6, 1)},
    }

# Summoned allies: the placeholder art has no people, so they borrow the humanoid
# robot drawings (a fallback only; the shipped pack has baked soldiers).
SUMMON_STAND_IN = {"militia": ("scoutRobot", 12), "knight": ("assaultRobot", 17)}
summons_path = os.path.join(CFG, "summons.json")
if os.path.exists(summons_path):
    for a in json.load(open(summons_path))["abilities"]:
        key, r = SUMMON_STAND_IN.get(a["visual"], ("scoutRobot", 12))
        walk = [proc("creature", key=key, radius=r, frame=i) for i in range(4)]
        sprites[f"summon.{a['visual']}"] = {
            "facing": "rotate",
            "animations": {"walk": {"frames": walk, "fps": 8}, "idle": {"frames": walk[:1]},
                           "attack": {"frames": walk[1:3], "fps": 8, "loop": False}},
            "metrics": {"healthBarOffsetY": r + 9, "healthBarWidth": round(max(22, r * 2.2), 1)},
        }

# Towers: static base + rotating head per level; projectiles per level.
LOBBED = {"stone", "boulder", "cannonball", "shell", "plasmaOrb"}
ENERGY = {"laser", "railSlug", "orbitalBeam", "plasmaOrb"}
QUIET = {"arrow", "longArrow", "bolt", "spear", "ballistaBolt", "stone", "boulder", "pellet"}
for t in json.load(open(os.path.join(CFG, "towers.json"))):
    a = t["archetype"]
    vis = t.get("visual", a)
    for lvl in t["levels"]:
        n = lvl["level"]
        sprites[f"tower.{vis}.{n}.base"] = {"facing": "fixed",
                                            "animations": {"default": {"frames": [proc("towerBase", key=a, level=n)]}}}
        sprites[f"tower.{vis}.{n}.head"] = {"facing": "rotate",
                                            "animations": {"idle": {"frames": [proc("towerHead", key=a, level=n)]}},
                                            "metrics": {"muzzleDistance": 24, "recoil": 4}}
        pk = lvl["projectile"]
        pv = lvl.get("projectileVisual", pk)
        spec = {"facing": "rotate", "motion": "arc" if pk in LOBBED else "straight",
                "animations": {"flight": {"frames": [proc("projectile", key=pk)]}}}
        if pk in LOBBED:
            spec["metrics"] = {"spinPerSecond": 15}
        if pk not in QUIET:
            spec["tint"] = "#80E6FF" if pk in ENERGY else "#FFBF59"
        sprites[f"projectile.{pv}"] = spec

mapdef = json.load(open(os.path.join(CFG, "map_meadow.json")))
sprites[f"map.{mapdef['id']}.background"] = {"anchor": {"x": 0, "y": 0}, "facing": "fixed",
                                             "animations": {"default": {"frames": [proc("mapBackground", key=mapdef["id"])]}}}
sprites["map.slot"] = {"facing": "fixed", "animations": {"default": {"frames": [proc("slot", key="normal")]}}}
sprites["map.slot.highlighted"] = {"facing": "fixed", "animations": {"default": {"frames": [proc("slot", key="highlighted")]}}}
sprites["map.spawn"] = {"facing": "fixed", "animations": {"default": {"frames": [proc("spawn")]}}}
for era in ["primitive", "medieval", "industrial", "futuristic"]:
    sprites[f"base.{era}"] = {"facing": "fixed", "animations": {"default": {"frames": [proc("base", key=era)]}}}
for fx in ["explosion", "puff", "spark", "ring", "shadow", "shield", "disabled", "missile"]:
    sprites[f"fx.{fx}"] = {"animations": {"default": {"frames": [proc("fx", key=fx)]}}}
for ui in ["levelPip.on", "levelPip.off"]:
    sprites[f"ui.{ui}"] = {"facing": "fixed", "animations": {"default": {"frames": [proc("ui", key=ui)]}}}

manifest = {
    "version": 1,
    "name": "Procedural placeholders",
    "textureScale": 2,
    "layout": {
        "tower.pips.spacing": 9, "tower.pips.offsetY": -31, "tower.pips.curve": 0.12,
        "tower.disabledMark.offsetY": 22,
        "projectile.arc.maxHeight": 70, "projectile.arc.distanceFactor": 0.35, "projectile.arc.scalePerPoint": 0.0111,
        "enemy.bossBreathing": 0.035,
        "ui.iconHeadAngle": 0.785
    },
    "sprites": dict(sorted(sprites.items())),
}
with open(OUT, "w") as f:
    json.dump(manifest, f, indent=1)
    f.write("\n")
print(f"wrote {len(sprites)} sprites to {os.path.relpath(OUT, ROOT)}")
