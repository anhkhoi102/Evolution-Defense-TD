#!/usr/bin/env python3
"""Converts the chosen Kenney CC0 sounds (OGG) into short mono WAVs that
AVFoundation can load, and writes EvolutionDefense/AssetPack/audio_manifest.json
(effect id → file, gain). Effects not listed keep the synthesized sound.

Run with a Python that has `soundfile` + `numpy`:
  python Tools/audio/convert.py
"""
import json, os
import numpy as np
import soundfile as sf

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "Tools", "bake", "sources")
OUT = os.path.join(ROOT, "EvolutionDefense", "AssetPack", "Audio")
MAN = os.path.join(ROOT, "EvolutionDefense", "AssetPack", "audio_manifest.json")
RATE = 44100

# effect id → (pack, file stem, gain, max seconds)
CHOICES = {
    "shotStone":  ("kenney-impact-sounds", "impactPlank_medium_000", 0.8, 0.4),
    "shotArrow":  ("kenney-interface-sounds", "pluck_001", 0.7, 0.35),
    "shotCannon": ("kenney-sci-fi-sounds", "lowFrequency_explosion_000", 0.75, 0.7),
    "shotBullet": ("kenney-impact-sounds", "impactTin_medium_000", 0.45, 0.25),
    "shotRocket": ("kenney-sci-fi-sounds", "thrusterFire_000", 0.6, 0.8),
    "shotLaser":  ("kenney-sci-fi-sounds", "laserSmall_000", 0.5, 0.4),
    "shotPlasma": ("kenney-sci-fi-sounds", "laserLarge_000", 0.6, 0.6),
    "shotRail":   ("kenney-sci-fi-sounds", "laserRetro_000", 0.6, 0.5),
    "shotBeam":   ("kenney-sci-fi-sounds", "laserLarge_002", 0.8, 0.9),
    "hit":        ("kenney-impact-sounds", "impactSoft_medium_000", 0.45, 0.25),
    "explosion":  ("kenney-sci-fi-sounds", "explosionCrunch_000", 0.8, 0.9),
    "enemyDeath": ("kenney-impact-sounds", "impactSoft_heavy_000", 0.6, 0.4),
    "robotDeath": ("kenney-impact-sounds", "impactMetal_heavy_000", 0.6, 0.6),
    "bossDeath":  ("kenney-sci-fi-sounds", "lowFrequency_explosion_001", 1.0, 1.6),
    "empBlast":   ("kenney-sci-fi-sounds", "forceField_000", 0.8, 1.0),
    "missile":    ("kenney-sci-fi-sounds", "thrusterFire_001", 0.6, 0.9),
    "baseHit":    ("kenney-impact-sounds", "impactWood_heavy_000", 0.9, 0.5),
    "build":      ("kenney-impact-sounds", "impactPlank_medium_002", 0.8, 0.5),
    "upgrade":    ("kenney-interface-sounds", "confirmation_001", 0.7, 0.8),
    "sell":       ("kenney-rpg-audio", "handleCoins", 0.8, 0.8),
    "repair":     ("kenney-impact-sounds", "impactMetal_medium_000", 0.7, 0.6),
    "research":   ("kenney-interface-sounds", "maximize_006", 0.7, 0.7),
    "error":      ("kenney-interface-sounds", "error_004", 0.7, 0.5),
    "click":      ("kenney-interface-sounds", "click_002", 0.6, 0.2),
    "eventGood":  ("kenney-interface-sounds", "confirmation_002", 0.7, 0.9),
    "eventBad":   ("kenney-interface-sounds", "glitch_001", 0.6, 0.8),
    "achievement": ("kenney-interface-sounds", "confirmation_004", 0.8, 1.2),
}


def find(pack, stem):
    for dp, _, fs in os.walk(os.path.join(SRC, pack)):
        for f in fs:
            if f == stem + ".ogg":
                return os.path.join(dp, f)
    raise FileNotFoundError(f"{pack}/{stem}.ogg")


os.makedirs(OUT, exist_ok=True)
manifest = {"version": 1, "name": "Kenney CC0 sound effects (synth fallback for the rest)", "effects": {}}
for effect, (pack, stem, gain, max_s) in sorted(CHOICES.items()):
    data, rate = sf.read(find(pack, stem), always_2d=True)
    mono = data.mean(axis=1)
    if rate != RATE:                                   # linear resample (short UI/FX sounds)
        n = int(len(mono) * RATE / rate)
        mono = np.interp(np.linspace(0, len(mono) - 1, n), np.arange(len(mono)), mono)
    mono = mono[: int(max_s * RATE)]
    fade = min(len(mono), int(0.01 * RATE))
    mono[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(mono)) or 1.0
    mono = mono / peak * 0.9
    name = f"sfx_{effect}.wav"
    sf.write(os.path.join(OUT, name), mono.astype(np.float32), RATE, subtype="PCM_16")
    manifest["effects"][effect] = {"file": name, "gain": gain, "source": f"{pack}/{stem}.ogg"}
json.dump(manifest, open(MAN, "w"), indent=1, sort_keys=True)
print(f"converted {len(CHOICES)} effects → {os.path.relpath(OUT, ROOT)}")
