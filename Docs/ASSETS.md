# Evolution Defense — Asset Guide

How the game finds its visuals, and how to replace them, partly or completely,
without touching gameplay code.

## 1. Architecture

```
Game data (Packages/…/Config/*.json)        Asset manifest (EvolutionDefense/AssetPack/*.json)      Files
────────────────────────────────────        ──────────────────────────────────────────────────      ─────
enemies.json   "visual": "wolf"      ─────► "enemy.wolf"            → frames, size, anchor, metrics ─► PNG / atlas / placeholder
towers.json    "visual" (default =          "tower.splash.3.base"
               archetype)            ─────► "tower.splash.3.head"
               "projectileVisual"           "projectile.cannonball"
               (default = projectile)
map_meadow.json "id": "meadow"       ─────► "map.meadow.background", "map.slot", "map.spawn"
eras                                 ─────► "base.primitive" … "base.futuristic"
renderer effects / UI                ─────► "fx.explosion" …, "ui.levelPip.on" …
```

The layers:

| Layer | Knows about | Never knows about |
|---|---|---|
| **Simulation** (`EvolutionDefenseCore`) | HP, speed, armor, range, damage, **hit radius**, a short `visual` key | textures, sprite sizes, file names |
| **Asset manifest** (`EvolutionDefenseAssets` + JSON) | asset ids → frames, size, anchor, facing, animations, metrics | gameplay numbers |
| **Asset library** (`AssetSystem/ArtLibrary.swift`) | loading frames from images, atlases or placeholder generators; caching; fallbacks | gameplay rules |
| **Renderers** (`Rendering/*`) | where entities are, which asset id to ask for | file names, hard-coded sizes |

Gameplay values are never derived from art. An enemy's collision radius
(`radius` in `enemies.json`) and a tower's range are pure data. Draw a wolf at
200 px and it still has a 14-unit hit radius. Health-bar placement, shield
bubble size and muzzle position come from the sprite's `metrics` in the
manifest.

## 2. Asset ids (naming convention)

| Entity | Id | Required animations | Notes |
|---|---|---|---|
| Enemy | `enemy.<visual>` | `walk` (or `idle`) | optional `death` (one-shot) |
| Summoned ally | `summon.<visual>` (`militia`, `knight`) | `idle`, `walk`, `attack` (one-shot), `death` | from `summons.json → visual`; baked by `blender/bake_summons.py` |
| Tower base | `tower.<visual>.<level>.base` | `default` | one per level 1–5 (upgrade variants) |
| Tower weapon | `tower.<visual>.<level>.head` | `idle` | optional `fire` (one-shot after each shot) |
| Projectile | `projectile.<visual>` | `flight` (or `default`) | |
| Map background | `map.<mapId>.background` | `default` | stretched to the playfield |
| Build pad | `map.slot`, `map.slot.highlighted` | `default` | |
| Enemy spawn | `map.spawn` | `default` | |
| Player base | `base.primitive`, `base.medieval`, `base.industrial`, `base.futuristic` | `default` | swaps when the era changes |
| Effects | `fx.explosion`, `fx.puff`, `fx.spark`, `fx.ring`, `fx.shadow`, `fx.shield`, `fx.disabled`, `fx.missile` | `default` | |
| Optional effects | `fx.muzzle` (directional flash), `fx.scorch` (ground mark), `fx.ember` + `fx.smoke` (particle-emitter textures) | `default` | used only when the pack has them |
| Map decorations | `deco.<kind>` (e.g. `deco.tree`, `deco.pine`) | any; frames are variants | optional; drawn as depth-sorted sprites instead of being baked into the background |
| UI | `ui.levelPip.on`, `ui.levelPip.off` | `default` | |

`<visual>` comes from the game data: `enemies.json → visual`, `towers.json →
visual` (default: archetype name) and `projectileVisual` (default: projectile
family). A new look for an existing entity, such as a different projectile for
Heavy level 4, is **data only**: set the key in the game data and add the
sprite to the manifest.

`AssetValidator.requiredIDs(for:)` lists every id the current game data needs.
The test suite fails if the shipped manifest misses one, and the app logs
missing ids at launch (`Assets: <id>: missing sprite`).

## 3. Manifest format

```jsonc
{
  "version": 1,
  "name": "Studio pack v1",
  "textureScale": 2,                 // pixels per point for images without "size" (2 = @2x art)
  "layout": {                        // global visual tuning (optional, partial overrides allowed)
    "tower.pips.spacing": 9, "tower.pips.offsetY": -31, "tower.pips.curve": 0.12,
    "tower.disabledMark.offsetY": 22,
    "projectile.arc.maxHeight": 70, "projectile.arc.distanceFactor": 0.35, "projectile.arc.scalePerPoint": 0.0111,
    "enemy.bossBreathing": 0.035, "ui.iconHeadAngle": 0.785
  },
  "sprites": {
    "enemy.wolf": {
      "size":   { "width": 60, "height": 44 },     // points; omit = native size of the first frame
      "anchor": { "x": 0.5, "y": 0.5 },            // 0…1; default centre
      "facing": "flip",                            // rotate | fixed | flip (see below)
      "animations": {
        "walk":  { "distancePerFrame": 9, "frames": [ { "atlas": "Enemies", "name": "wolf_walk_0" }, … ] },
        "death": { "fps": 10, "loop": false, "frames": [ … ] }
      },
      "metrics": { "healthBarOffsetY": 26, "healthBarWidth": 30, "shieldDiameter": 56 }
    }
  }
}
```

### Frame sources

| Form | Meaning |
|---|---|
| `"wolf_walk_0"` or `{ "image": "wolf_walk_0" }` | Image by name: an asset-catalog image set or a PNG in the app bundle. No extension; `@2x` is picked automatically. |
| `{ "atlas": "Enemies", "name": "wolf_walk_0" }` | A frame in a sprite atlas (`Enemies.spriteatlas` in `Assets.xcassets`). |
| `{ "procedural": "creature", "key": "wolf", "radius": 14, "frame": 0 }` | Code-drawn placeholder. Generators: `creature`, `towerBase`, `towerHead`, `projectile`, `mapBackground`, `slot`, `spawn`, `base`, `fx`, `ui`. |

### Facing

| Value | Use for | Behaviour |
|---|---|---|
| `rotate` (default) | top-down art | Art faces **right (+x)** and rotates to the movement or aim direction. |
| `fixed` | props, bases, pads, isometric art | Never rotates. |
| `flip` | side-view characters | Art faces **right** and is mirrored when moving or aiming left. |
| `directional` | pre-rendered 2.5D art | The clip holds `directions` sets of frames (direction 0 = facing right, then counter-clockwise). The renderer picks the set nearest to the heading or aim and never rotates the sprite. `frames` must be a multiple of `directions`. |

### Animations

* **Time-based:** set `fps`. **Distance-based:** set `distancePerFrame` (world
  units travelled per frame). Walk cycles then match movement speed, including
  sprints, slows and stuns.
* `loop` defaults to `true`. One-shot clips (`fire`, `death`) set `false`.
* All frames of a sprite share the sprite's display size.

### Metrics (points, sprite-local)

| Sprite | Metric | Default if omitted |
|---|---|---|
| enemy | `healthBarOffsetY` | half the sprite height + 6 |
| enemy | `healthBarWidth` | 70 for bosses, otherwise 60 % of the sprite width |
| enemy | `shieldDiameter` | 110 % of the larger sprite side |
| tower head | `muzzleDistance` | 35 % of the sprite width |
| tower head | `recoil` | 4 (0 disables it) |
| projectile | `spinPerSecond` | 0 (radians per second, `arc` motion only) |

Projectile extras: `"motion": "arc" | "straight"`, plus `"tint": "#RRGGBB"` for
the muzzle-flash colour (omit it for no flash, e.g. bows).

## 4. Art specifications

| Asset | Recommended size (points) | Anchor | Orientation |
|---|---|---|---|
| Map background | 1600 × 800 (the playfield; any aspect is stretched to it) | bottom-left `(0, 0)` | — |
| Build pad | 72 × 72 | centre | — |
| Player base | 150–180 square | centre | — |
| Spawn | ≈ 110 × 130 | centre | opening faces right |
| Tower base / head | 68–72 square | centre = rotation pivot | head points right |
| Enemy | about 3–4 × the hit radius wide | centre (the body) | faces right |
| Boss | 120–180 wide | centre | faces right |
| Projectile | 8–40 long | centre | points right |
| Effects | explosion 64, ring 128, others 16–64 | centre | — |

* **Resolution:** deliver **@2x** PNGs (pixels = 2 × points) with straight
  alpha, sRGB. Keep each image at or below 2048 px.
* **Drop shadows:** paint them into ground sprites. Lobbed projectiles get a
  separate `fx.shadow`.
* **Naming:** images are looked up by name across the whole bundle, so names
  must be unique. Use the prefix scheme `<category>_<visual>_<variant>_<frame>`,
  for example `enemy_wolf_walk_0`, `tower_splash_3_head`, `proj_cannonball`, `base_medieval`.

### Texture atlases

* Group frames that are drawn together into one `.spriteatlas` in
  `Assets.xcassets`, for example `Enemies_Era1`, `Towers`, `Projectiles`, `FX`.
  SpriteKit then batches them into a single draw call.
* Each frame is an image set with a `@2x` image. The frame name is the image
  set name (as in `EvolutionDefense/Assets.xcassets/SampleCreatures.spriteatlas`).
* Keep each atlas at or below 4096 × 4096 after packing (M1 / 8 GB target).
  Put the map background in its own image set, not in an atlas.

## 5. Replacing assets

**Partial replacement (override pack).** Ship `asset_manifest.<pack>.json`
next to the default manifest with only the sprites you replace. It is layered
on top of the default pack, and anything it doesn't name keeps the placeholder.
Select it with `EVO_ASSET_PACK=<pack>`; a settings toggle can set the same
value later.

**Full replacement.** Replace `asset_manifest.json` itself. Every id from section
2 must be present: the tests and the launch log list anything missing.

**Robustness.**
* If a frame in an override can't be loaded, the library logs a warning and
  uses the placeholder for that sprite.
* An id missing from every pack renders as a magenta checkerboard, so it is
  easy to spot and never crashes.

**Workflow:**
1. Add images or atlases to `EvolutionDefense/Assets.xcassets`, or PNGs to
   `EvolutionDefense/AssetPack/`. Xcode picks them up automatically.
2. Write the manifest entries.
3. Run `swift test --package-path Packages/EvolutionDefenseCore --filter AssetManifestTests`.
4. Run `Scripts/asset-demo.sh <pack>` to render the same scene with the
   placeholders and with your pack (`snapshots/asset-pack-*.png`).

### Sample pack

`asset_manifest.sample.json` replaces the wolf (a side-view, `flip`-facing
atlas with `walk` and `death` clips), the level-1 Splash tower (loose PNGs, a
different muzzle and recoil), the stone projectile and the Primitive base (a
different size). The images are made by `swift Scripts/make-sample-pack.swift`.
It exists to prove the replacement path end to end. It isn't production art.

## 6. Placeholder pack

`asset_manifest.placeholder.json` maps every id to a procedural generator in
`EvolutionDefense/Art/` (CoreGraphics drawing at launch). Regenerate it after
adding enemies, tower levels or projectiles:

```bash
Scripts/generate-placeholder-manifest.py
```

The placeholder pack is always loaded first. The shipped pack
(`asset_manifest.json`) and any `EVO_ASSET_PACK` override are layered on top,
so an id missing from them still draws something. Set `EVO_PLACEHOLDER_ART=1`
to run with the placeholders only.

## 7. The shipped 2.5D pack and how it is made

`asset_manifest.json` is **generated**. Don't edit it by hand. Re-run the
pipeline instead. Everything comes from free, commercially usable kits (CC0, plus
the OFL font); see [ASSET_LICENSES.md](ASSET_LICENSES.md).

### View

A 3/4 "tabletop" view: an orthographic camera at 55° elevation, 1 world tile
(50 pt) = 1 Blender unit, rendered at @2x. The game projects the flat
simulation onto that view with `ViewProjection` (`AssetSystem/ArtLibrary.swift`),
configured by the pack's layout keys:

| Layout key | Value | Meaning |
|---|---|---|
| `view.groundScaleY` | 0.8192 (sin 55°) | world y → screen y squash |
| `view.groundOffsetY` | 50 | screen offset of world y = 0 |
| `view.heightScale` | 0.5736 (cos 55°) | screen points per point of height |
| `view.projectileHeight` | 22 | flight height of straight projectiles |

The projection only changes **where things are drawn**. Positions, ranges,
hit radii and paths in the simulation are untouched. Mouse input is
unprojected back to world space, and range circles are drawn as ellipses.
Towers, enemies and trees share one z band sorted by ground depth (flyers sit
above it). The placeholder pack has no `view.*` keys, so for it the projection
is the identity and it looks exactly as before.

### Pipeline (`Tools/bake/`)

```bash
Tools/bake/fetch-sources.sh                                    # 1. download Kenney + OpenGameArt packs (one manual pack: see the end of the script)
python3 Tools/bake/prepare_textures.py                         # 2. palette-graded RGBA copies of the kit textures
swift run --package-path Packages/EvolutionDefenseCore edtool export-map ../../Tools/bake/map.json   # 3. map geometry
B=/Applications/Blender.app/Contents/MacOS/Blender
$B -b --factory-startup -P Tools/bake/blender/bake_env.py          # 4. background, trees, pads, spawn, bases
$B -b --factory-startup -P Tools/bake/blender/bake_towers.py       #    20 tower bases + 16-direction heads
$B -b --factory-startup -P Tools/bake/blender/bake_enemies.py      #    19 enemies × 8 directions (walk + death)
$B -b --factory-startup -P Tools/bake/blender/bake_projectiles.py  #    physical projectiles
python3 Tools/bake/package.py                                  # 5. trim, build atlases, write asset_manifest.json
```

Each Blender script accepts `-- only=<name>` to re-bake one item.
`bake_enemies.py -- facetest` renders one frame per creature to check facing.

| Script | Output |
|---|---|
| `blender/rig.py` | Shared scene: Cycles (Metal GPU), sun at 135°/52° plus sky fill, shadow catcher, camera framing, model import with material clean-up and palette grade |
| `palette.py` | The shared colour grade (teal → leaf green, pale blue → stone grey, salmon → brown) that makes the kits read as one style |
| `package.py` | Trims frames to a shared box per sprite (anchors recomputed), removes shadow-catcher haze, writes `.spriteatlas` folders under `Assets.xcassets/Baked/`, and composes effect and energy-projectile sprites from the Kenney Particle Pack |

### What the pack contains

| Group | Atlas | Sprites |
|---|---|---|
| Environment | `Baked/Environment.spriteatlas` + `env_meadow_background` image set | background (1600 × 800 pt), build pad (normal and highlighted), spawn cave, 4 era bases, 6 tree and 5 pine variants |
| Towers | `Baked/Towers.spriteatlas` | 20 bases (`fixed`) and 20 heads (`directional`, 16 directions; `idle` plus a 2-frame recoil `fire`) |
| Enemies | `Baked/Enemies1…4.spriteatlas` (one per era) | 19 enemies, `directional`, 8 directions; `walk` (8 frames, distance-driven) and `death` (6 frames, played once, then dissolved) |
| Combat | `Baked/Combat.spriteatlas` | 17 projectiles and 9 effect images (`fx.missile` reuses the rocket) |
| UI | `UI/` image sets | Kenney UI Adventure 9-slice panel and buttons (used by `Theme`) |

### Rendering features

* **Status shader** (`Rendering/Shaders.swift`): enemies mix towards a colour
  instead of multiplying, so the hit flash is really white. Stun, burn, frost
  (slow) and boss enrage use the same shader. The value is a per-sprite
  `SKAttribute`, so batching is kept, and it is only written when it changes.
* **Dissolve shader:** death animations hold their last frame and dissolve
  with an ember rim.
* **Particle emitters:** explosions and boss deaths throw pooled
  `SKEmitterNode` bursts (embers and smoke). At most 14 run at once, and none
  in performance mode.
* **Ground effects:** blast rings, summon rings and scorch marks are squashed
  onto the ground plane. Muzzle flashes are directional and sit at the weapon's
  mount height.

### Memory and performance

* **Era-scoped enemy atlases.** Each era's enemies live in their own atlas
  (`Enemies1…4`). `ArtLibrary.warmUp(config:era:)` pre-loads the current and
  next era. When the era changes, `ArtLibrary.advance(to:)` drops the earlier
  eras' sprites, and their atlas pages are freed. Anything not pre-loaded is
  still resolved on first use, so nothing can go missing.
* **Enemy frames are stored at 1.5 px per point** (`ENEMY_PX` in
  `package.py`). The playfield is shown at about 1.4–1.8 px per point, so this
  is visually lossless and saves about 44 %. Towers, props and effects stay at @2x.
* **Shadow clean-up before trimming** (`soften` in `package.py`): removes the
  shadow catcher's faint haze and feathers cast shadows at the canvas edge.
  This avoids visible boxes and lets Xcode's atlas packer trim frames tightly.
* Measured on an M1 MacBook Air (8 GB), release build, with `Scripts/benchmark.sh`
  (16 level-5 towers, all tech, about 300 Futuristic enemies plus the final boss):

| | Placeholder art | Baked 2.5D pack |
|---|---|---|
| Average FPS (normal / performance mode) | 60.0 / 59.6 | 60.0 / 60.0 |
| p99 frame time | 17.7 ms | 17.6 ms |
| Frames over 20 ms (about 500 frames) | 0 / 3 | 0 / 0 |
| Process footprint | 241 MB | 501 MB |
| GPU textures (IOSurface) | 48 MB | 177 MB |
| App bundle | — | 44 MB |
