#!/usr/bin/env python3
"""Converts the chosen CC0 music loops (Tools/bake/sources/oga-music/) into mono AAC files
the game can loop, levels them to the same loudness, and adds a "music" section to
EvolutionDefense/AssetPack/audio_manifest.json (track id → file, gain, source, author).
Tracks not listed keep the synthesized loop.

Run with a Python that has `soundfile` + `numpy` (macOS `afconvert` does the encoding):
  python Tools/audio/convert_music.py
"""
import json, os, subprocess, tempfile
import numpy as np
import soundfile as sf

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "Tools", "bake", "sources", "oga-music")
OUT = os.path.join(ROOT, "EvolutionDefense", "AssetPack", "Audio")
MAN = os.path.join(ROOT, "EvolutionDefense", "AssetPack", "audio_manifest.json")
RATE = 44100
TARGET_RMS = 0.11            # about −19 dBFS: music sits under the sound effects

# track id (MusicLoop) → (source file, title, author, page)
TRACKS = {
    "menu":       ("menu_old_tower_inn.wav", "Medieval: The Old Tower Inn (loop)", "RandomMind",
                   "https://opengameart.org/content/medieval-the-old-tower-inn"),
    "primitive":  ("primitive_jungle_battle.ogg", "Jungle Battle Loop", "omfgdude",
                   "https://opengameart.org/content/jungle-battle-loop"),
    "medieval":   ("medieval_market_day.wav", "Medieval: Market Day (loop)", "RandomMind",
                   "https://opengameart.org/content/medieval-market-day"),
    "industrial": ("industrial_determined_pursuit.wav", "Determined Pursuit (epic orchestra loop)", "Emma_MA",
                   "https://opengameart.org/content/determined-pursuit-epic-orchestra-loop"),
    "futuristic": ("futuristic_net_infiltration.wav", "Net Infiltration (loop)", "vitalezzz",
                   "https://opengameart.org/content/net-infiltration"),
}

manifest = json.load(open(MAN))
manifest["music"] = {}
for track, (src, title, author, page) in TRACKS.items():
    data, rate = sf.read(os.path.join(SRC, src), always_2d=True)
    mono = data.mean(axis=1)
    if rate != RATE:
        n = int(len(mono) * RATE / rate)
        mono = np.interp(np.linspace(0, len(mono) - 1, n), np.arange(len(mono)), mono)
    rms = float(np.sqrt(np.mean(mono ** 2))) or 1.0
    mono = mono * (TARGET_RMS / rms)
    peak = float(np.max(np.abs(mono)))
    if peak > 0.95:                                   # keep headroom; note the lower level in the gain
        mono *= 0.95 / peak
    name = f"music_{track}.m4a"
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "t.wav")
        sf.write(wav, mono.astype(np.float32), RATE, subtype="PCM_16")
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "112000", "-q", "127", wav, os.path.join(OUT, name)], check=True)
    manifest["music"][track] = {"file": name, "gain": 1.0, "title": title, "author": author, "license": "CC0 1.0",
                                "source": page, "seconds": round(len(mono) / RATE, 1)}
    print(f"{track:11s} {len(mono) / RATE:6.1f}s  rms {rms:.3f} → {TARGET_RMS}  {os.path.getsize(os.path.join(OUT, name)) // 1024} KB")
json.dump(manifest, open(MAN, "w"), indent=1)
