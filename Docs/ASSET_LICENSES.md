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

Downloads: **9 November 2026**, except the two KayKit packs and Ultimate Monsters (**10 November 2026**).

**Attribution and commercial use.** Every pack below is CC0 1.0 (public domain dedication) except the
font (SIL OFL 1.1): commercial use is permitted and no attribution is required. Authors are credited
here and on the in-game Credits screen anyway.

**Made by this project** (not from a pack): the ground, road and water surfaces of the battlefields
(they must follow each map's path), the Iron King's crown (the character pack has none), colour tints
applied to pack models, 8 synthesised sound effects (and synthesised music as a fallback), and the code-drawn fallback art
that is only used if the art pack is missing.

## Shipped in the app

### 3D source models (rendered to 2D sprites with Blender)

| Pack | Author | Licence | Source | Used for |
|---|---|---|---|---|
| Tower Defense Kit 2.1 | Kenney | CC0 1.0 | <https://kenney.nl/assets/tower-defense-kit> | Tower bases (levels 2–5), weapons, projectiles (bolt, boulder, cannonball, shells) |
| Castle Kit | Kenney | CC0 1.0 | <https://kenney.nl/assets/castle-kit> | Tower level 1 base, medieval and industrial bases, siege ballista, environment props |
| Nature Kit | Kenney | CC0 1.0 | <https://kenney.nl/assets/nature-kit> | Map background props, trees, rocks, spawn cave, primitive base (tents, fence); Desert (cacti, palms, statues and columns, stones) and Lakeside (lilies, reeds, canoe) battlefields |
| Graveyard Kit | Kenney | CC0 1.0 | <https://kenney.nl/assets/graveyard-kit> | Desert: gravestones, urns, coffin and broken masonry around the ruins |
| Pirate Kit | Kenney | CC0 1.0 | <https://kenney.nl/assets/pirate-kit> | Lakeside: dock, rowing boats, barrels and crates |
| Space Kit | Kenney | CC0 1.0 | <https://kenney.nl/assets/space-kit> | Futuristic base, level 5 tower weapons |
| Blaster Kit | Kenney | CC0 1.0 | <https://kenney.nl/assets/blaster-kit> | Sniper level 4 weapon |
| Mini Characters | Kenney | CC0 1.0 | <https://kenney.nl/assets/mini-characters> | Tower crews, arrows, spears |
| KayKit Character Pack: Adventurers 1.0 | Kay Lousberg | CC0 1.0 ("free for personal and commercial use, no attribution required", pack README) | <https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0> | The summoned Militia (Barbarian with axe and round shield) and the three heroes: Knight Commander (Knight, sword and shield), Iron King (Knight, greatsword, dark tint) and Star Queen (Mage with staff), with the pack's own animations |
| KayKit Character Pack: Skeletons 1.0 | Kay Lousberg | CC0 1.0 (pack README) | <https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0> | Desert: Bone Runner, Tomb Guard, Grave Stalker, Bone Shaman |
| Ultimate Monsters ("Big" set) | Quaternius | CC0 1.0 (stated on the pack page) | <https://quaternius.com/packs/ultimatemonsters.html> | Desert: Cactoro Chief, Skull Orc, Dune Raptor, Orc Warlord, Dune Tyrant. Lakeside: Marsh Hopper, Reef Brute, Mushroom King, Heron Raider, Bog Lurker, Shell Brute, Deep One, Tide Tyrant |
| Animal Pack vol. 2 | Quaternius | CC0 1.0 | <https://opengameart.org/content/animated-animales-low-poly> | Desert: Vulture (eagle). Lakeside: Mud Piranha |
| Ultimate Animated Animals (July 2021) | Quaternius | CC0 1.0 (stated on the pack page) | <https://quaternius.com/packs/ultimateanimatedanimals.html> | Wolf, bear (recoloured bull without horns), alpha beast, giant wolf, armoured beast, mutant beast |
| Animated Monster Pack | Quaternius | CC0 1.0 | <https://opengameart.org/content/lowpoly-animated-monsters> | Flying monster (bat), ancient dragon, swarm creature (slime) |
| Textured Cute Monster Pack | Quaternius | CC0 1.0 | <https://opengameart.org/content/textured-cute-monster-pack> | Troll (yeti), armoured monster (crab), giant mutant (cyclops), mutant titan (green demon). Desert: Cactling, Sand Wyrm, Stone Skull, Sand Imp. Lakeside: Sporecap, Bogwood, Lake Wisp, Marsh Hornet, Lake Horror |
| Animated Lowpoly Robot | Quaternius | CC0 1.0 | <https://opengameart.org/content/animated-lowpoly-robot> | Scout robot |
| Animated Mech Pack | Quaternius | CC0 1.0 | <https://opengameart.org/content/animated-mech-pack> | Assault robot, heavy mech, stealth robot, titan war machine |
| Boar | Teh_Bucket | CC0 1.0 | <https://opengameart.org/content/boar> | Wild boar |

The **app icon** is rendered the same way (`Tools/bake/blender/render_icon.py`):
the level-5 tower and island props come from the Tower Defense and Nature kits, the
wolf from Ultimate Animated Animals, and the clouds from the Particle Pack.

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
(the id → file mapping is in that script). The other 8 effects are still synthesised in code by
`EvolutionDefenseAudio`.

### Music

Each track's OpenGameArt page states **CC0** as its only licence (checked on the page, 10 November 2026).
No attribution is required; the authors are credited here and on the Credits screen.

| Track in the game | Title | Author | Licence | Source |
|---|---|---|---|---|
| Menu | Medieval: The Old Tower Inn (loop) | RandomMind | CC0 1.0 | <https://opengameart.org/content/medieval-the-old-tower-inn> |
| Primitive Age | Jungle Battle Loop | omfgdude | CC0 1.0 | <https://opengameart.org/content/jungle-battle-loop> |
| Medieval Age | Medieval: Market Day (loop) | RandomMind | CC0 1.0 | <https://opengameart.org/content/medieval-market-day> |
| Industrial Age | Determined Pursuit (epic orchestra loop) | Emma_MA | CC0 1.0 | <https://opengameart.org/content/determined-pursuit-epic-orchestra-loop> |
| Futuristic Age | Net Infiltration (loop) | vitalezzz | CC0 1.0 | <https://opengameart.org/content/net-infiltration> |

`Tools/audio/convert_music.py` mixes each to mono, levels them to the same loudness and encodes them as
AAC (about 6 MB together); the encoded files keep the exact sample count, so they loop without a gap.
If a file is missing the game falls back to the synthesised loop for that track.

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
| 5 Low Poly Animals, Farm Animals (Quaternius, OGA) | CC0 | Ultimate Animated Animals covered the same creatures |
| Ultimate Monsters, sets other than "Big" (Quaternius) | CC0 | The shared-folder download stopped after the "Big" set (16 monsters); those were enough for both rosters |
| White Bear (STKRudy85, OGA) | CC0 | Not rigged; the bear uses a recoloured bull instead |

## Licence files

`ThirdParty/Licenses/`:

- `Kenney-*.txt`: each Kenney pack's own `License.txt` (CC0).
- `CC0-1.0.txt`: the CC0 1.0 legal code, covering the OpenGameArt and Quaternius files.
- `LilitaOne-OFL.txt`: SIL OFL 1.1.

Attribution is not required by CC0, but this file credits every author anyway.
