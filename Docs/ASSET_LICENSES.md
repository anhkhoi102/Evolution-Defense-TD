# Asset licences and attribution

Every third-party file used to make the shipped art, audio and fonts is listed
here, with where it came from, its licence, when it was downloaded and what it
is used for. Licence texts are kept in [`ThirdParty/Licenses/`](../ThirdParty/Licenses).

**Rules this project follows**

- Only assets whose licence allows commercial use in a game, verified on the
  source page before download.
- Nothing extracted from commercial games. Kingdom Rush, Bad North and Iron
  Marines were used only as visual references for the style.
- Raw source packs are **not** committed. `Tools/bake/fetch-sources.sh`
  downloads them into `Tools/bake/sources/`, which is git-ignored. Only the
  rendered sprites, converted sounds and the font ship in the app.
- Each downloaded pack folder records `.source-url`, `.downloaded` (date), and,
  for OpenGameArt files, `.license`.

All downloads: **9 November 2026**.

## Shipped in the app

### 3D source models (rendered to 2D sprites with Blender)

| Pack | Author | Licence | Source | Used for |
|---|---|---|---|---|
| Tower Defense Kit 2.1 | Kenney | CC0 1.0 | <https://kenney.nl/assets/tower-defense-kit> | Tower bases (levels 2–5), weapons, projectiles (bolt, boulder, cannonball, shells) |
| Castle Kit | Kenney | CC0 1.0 | <https://kenney.nl/assets/castle-kit> | Tower level 1 base, medieval and industrial bases, siege ballista, environment props |
| Nature Kit | Kenney | CC0 1.0 | <https://kenney.nl/assets/nature-kit> | Map background props, trees, rocks, spawn cave, primitive base (tents, fence) |
| Space Kit | Kenney | CC0 1.0 | <https://kenney.nl/assets/space-kit> | Futuristic base, level 5 tower weapons |
| Blaster Kit | Kenney | CC0 1.0 | <https://kenney.nl/assets/blaster-kit> | Sniper level 4 weapon |
| Mini Characters | Kenney | CC0 1.0 | <https://kenney.nl/assets/mini-characters> | Tower crews, arrows, spears |
| Ultimate Animated Animals (July 2021) | Quaternius | CC0 1.0 (stated on the pack page) | <https://quaternius.com/packs/ultimateanimatedanimals.html> | Wolf, bear (recoloured bull without horns), alpha beast, giant wolf, armoured beast, mutant beast |
| Animated Monster Pack | Quaternius | CC0 1.0 | <https://opengameart.org/content/lowpoly-animated-monsters> | Flying monster (bat), ancient dragon, swarm creature (slime) |
| Textured Cute Monster Pack | Quaternius | CC0 1.0 | <https://opengameart.org/content/textured-cute-monster-pack> | Troll (yeti), armoured monster (crab), giant mutant (cyclops), mutant titan (green demon) |
| Animated Lowpoly Robot | Quaternius | CC0 1.0 | <https://opengameart.org/content/animated-lowpoly-robot> | Scout robot |
| Animated Mech Pack | Quaternius | CC0 1.0 | <https://opengameart.org/content/animated-mech-pack> | Assault robot, heavy mech, stealth robot, titan war machine |
| Boar | Teh_Bucket | CC0 1.0 | <https://opengameart.org/content/boar> | Wild boar |

All models were recoloured with a shared palette grade
(`Tools/bake/palette.py`) so that the packs read as one consistent style.

**Note on Quaternius licensing.** Quaternius now also publishes the
"Quaternius Asset License" (QAL v1.0, dated 28 Aug 2026). It applies to future
releases and is not retroactive. The packs above were obtained under CC0. Even
under the QAL, using the models in a game, including rendered sprites, is
allowed. What the QAL forbids is redistributing the raw models as assets,
which this repository does not do, because the sources are git-ignored.

### 2D textures

| Pack | Author | Licence | Source | Used for |
|---|---|---|---|---|
| Particle Pack | Kenney | CC0 1.0 | <https://kenney.nl/assets/particle-pack> | Explosion, smoke, sparks, embers, rings, shield, muzzle flash, scorch marks, energy projectiles (laser, rail, beam, plasma, tracer), rocket exhaust |
| UI Pack – Adventure | Kenney | CC0 1.0 | <https://kenney.nl/assets/ui-pack-adventure> | 9-slice panel frame and buttons (`Assets.xcassets/UI/`) |

### Audio

| Pack | Author | Licence | Source | Used for |
|---|---|---|---|---|
| Interface Sounds | Kenney | CC0 1.0 | <https://kenney.nl/assets/interface-sounds> | Arrow shot, click, upgrade, research, error, good/bad events, achievement |
| Impact Sounds | Kenney | CC0 1.0 | <https://kenney.nl/assets/impact-sounds> | Stone and bullet shots, hits, enemy and robot deaths, base hit, build, repair |
| Sci-fi Sounds | Kenney | CC0 1.0 | <https://kenney.nl/assets/sci-fi-sounds> | Cannon, rocket, laser, plasma, rail and beam shots, explosions, boss death, EMP, missile |
| RPG Audio | Kenney | CC0 1.0 | <https://kenney.nl/assets/rpg-audio> | Sell (coins) |

27 sound effects were converted to 44.1 kHz mono WAV by `Tools/audio/convert.py`
(the id → file mapping is in that script). Music and the other 8 effects are
still synthesised in code by `EvolutionDefenseAudio`.

### Font

| Font | Author | Licence | Source | Used for |
|---|---|---|---|---|
| Lilita One | Juan Montoreano | SIL Open Font License 1.1 | <https://fonts.google.com/specimen/Lilita+One> | Titles, numbers, buttons (`Theme.display`) |

The OFL text ships next to the font in the app bundle
(`AssetPack/Fonts/LilitaOne-OFL.txt`), as the licence requires.

## Downloaded for evaluation, not shipped

| Pack | Licence | Why it was not used |
|---|---|---|
| Lowpoly Steampunk Turrets (Quaternius, OGA) | CC0 | Materials and style didn't match the Kenney kits |
| Animal Pack vol. 2, 5 Low Poly Animals, Farm Animals (Quaternius, OGA) | CC0 | Ultimate Animated Animals covered the same creatures |
| White Bear (STKRudy85, OGA) | CC0 | Not rigged; the bear uses a recoloured bull instead |

## Licence files

`ThirdParty/Licenses/`:

- `Kenney-*.txt`: each Kenney pack's own `License.txt` (CC0).
- `CC0-1.0.txt`: the CC0 1.0 legal code, covering the OpenGameArt and Quaternius files.
- `LilitaOne-OFL.txt`: SIL OFL 1.1.

Attribution is not required by CC0, but this file credits every author anyway.
