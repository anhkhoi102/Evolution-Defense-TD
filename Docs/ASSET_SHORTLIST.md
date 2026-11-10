# Asset shortlist

> **Status, 10 November 2026:** approved and carried out for map creatures and heroes. KayKit Adventurers and Skeletons and Quaternius Ultimate Monsters ("Big" set) were downloaded and are in use; see [ROSTERS.md](ROSTERS.md), [HEROES.md](HEROES.md) and [ASSET_LICENSES.md](ASSET_LICENSES.md). The scenery kits (Graveyard, Pirate) and CC0 music followed the same day. Only the icon pack is not done. The text below is the original proposal.

Written 10 November 2026 in response to the "use existing asset packs first" requirement.
Nothing in this list has been downloaded or integrated yet.

## 1. Where the art comes from today

The game already follows the "packs first" approach. Every tower, enemy, boss, tree, rock, building,
projectile, effect, panel, sound and font is a third-party CC0 / OFL asset
(full inventory with authors, licences and usage: [ASSET_LICENSES.md](ASSET_LICENSES.md)).
The 3D packs are rendered to 2D sprite atlases with Blender so that everything shares one camera
angle, one light and one colour grade. That render step is what keeps packs from different authors
looking like one game.

What is **made by this project** rather than taken from a pack:

| Custom-made item | Why | Could a pack replace it? |
|---|---|---|
| Ground, road and water surfaces of the three battlefields | The road has to follow each map's path exactly | Partly: pack textures could be used on the surfaces; the shapes must stay generated |
| Iron King and Star Queen: crown, cape, war hammer, star staff (added this session) | The Kenney Mini Characters pack has no royal or mage figures | **Yes**: KayKit Adventurers (below) has ready-made fighters and a mage with weapons |
| Tints that turn one model into several enemies (e.g. giant wolf, mutant beast) | Too few distinct creature models | **Yes**: more creature packs (below) |
| Music and 8 of the 35 sound effects (synthesised in code) | No music pack was chosen | **Yes**: a CC0 music pack |
| HUD icons | Apple's built-in SF Symbols | Optional: a game icon pack |
| Code-drawn fallback art | Only used if the art pack is missing; never shown in the shipped game | Not needed |

## 2. Visual gaps

1. **Desert and Lakeside enemies and bosses** (next phase): no creatures yet that belong to those maps.
2. **Heroes**: three heroes built from one small character pack plus home-made props.
3. **Enemy variety**: several enemies are recolours of the same model.
4. **Music**: synthesised, the weakest part of the presentation.
5. **Icons**: system symbols rather than game-styled icons (minor).

## 3. Shortlist

Style rule used for every candidate: low-poly 3D with flat colours, so it can go through the same
render step as the current art. 2D sprite-sheet packs (CraftPix, most of GameDev Market and itch.io
tower-defence packs) were ruled out as a group: each has its own perspective, outline style and
proportions, so mixing them with the current art would break the consistent look, and replacing
everything with one of them would mean redoing all towers, enemies and maps.

### A. Already on disk, unused (no download needed)

| Pack | Author | Licence | Unused models that fit | Use |
|---|---|---|---|---|
| Textured Cute Monster Pack | Quaternius | CC0 | Cactus, Skull, Bee, Mushroom, Ghost, Cthulhu, Alien, YellowDragon, Demon | Desert: cactus creature, skull, bee swarm. Lakeside: mushroom, ghost, **Cthulhu as the lake boss** |
| Animated Monster Pack | Quaternius | CC0 | Skeleton | Desert: skeleton warriors |
| Animal Pack vol. 2 | Quaternius | CC0 | Piranha, Eagle | Lakeside: leaping piranha. Desert: eagle/vulture flyer |
| Animals Pack | Quaternius | CC0 | Fish, Whale | Lakeside ambience or a large water creature |

Sources and licences are already recorded in ASSET_LICENSES.md. These need a test render to confirm
each model's animations are good enough (some of the older animal packs have fewer clips).

### B. New packs to download (all free)

| # | Pack | Author | Licence | Link | What it has | What it would improve | Status |
|---|---|---|---|---|---|---|---|
| 1 | Ultimate Monsters | Quaternius | CC0 (stated on the pack page) | <https://quaternius.com/packs/ultimatemonsters.html> | 50 animated, textured monsters; FBX / OBJ / Blend / glTF | Main source for map-specific enemies and bosses; ends the recolour reuse | Licence and count checked on the page. Exact monster list not shown there: must be inspected after download. An earlier download attempt in this project failed, so this needs a retry |
| 2 | Animated Easy Enemies | Quaternius | CC0 (per search listing) | <https://quaternius.itch.io/animated-easy-enemies> | Small enemies with move, attack, jump and death clips; listing tags include frog, snake, spider | Lakeside frogs, desert snakes and spiders | Page could not be opened from here; licence and contents to be confirmed on the page before download |
| 3 | KayKit Character Pack: Adventurers | Kay Lousberg | CC0 (Godot asset library listing) | <https://kaylousberg.itch.io/kaykit-adventurers> | 4 rigged stylised characters with 25+ weapons and accessories; glTF / FBX | Replace the three heroes with purpose-made hero figures (fighter, heavy fighter, mage) and drop the home-made props | Character list and licence to be confirmed on the page; one listing mentions "attribution", which conflicts with CC0 and must be cleared up |
| 4 | KayKit Character Animations | Kay Lousberg | CC0 (OpenGameArt listing) | <https://opengameart.org/content/kaykit-character-animations> | Extra attack, cast and death animations for KayKit characters | Proper spell-cast and hammer-swing animations for heroes | Needed only if pack 3 is taken |
| 5 | KayKit Character Pack: Skeletons | Kay Lousberg | CC0 (Godot asset library listing) | <https://kaylousberg.itch.io/kaykit-skeletons> | 4 skeletons (warrior, mage, rogue, minion), 90+ animations, 10+ accessories | Desert tomb enemies in the same style as the heroes | Alternative to the Quaternius skeleton in list A |
| 6 | Graveyard Kit | Kenney | CC0 | <https://kenney.nl/assets/graveyard-kit> | About 80 models, some animated | Desert ruins and tomb decoration | Same author and style as the current scenery |
| 7 | Pirate Kit | Kenney | CC0 | <https://opengameart.org/content/pirate-kit> | About 70 models | Lakeside docks, boats, barrels | Same author and style as the current scenery |
| 8 | CC0 Cinematic Music (collection) | Various | CC0 per collection title | <https://opengameart.org/content/cc0-cinematic-music> | Orchestral loops and battle pieces | Replace synthesised music with one track per age plus menu | Page could not be opened from here; each track's licence must be checked individually |
| 9 | Game Icons | Kenney | CC0 | <https://kenney.nl/assets/game-icons> | 105 interface icons | HUD icons in a game style | Optional; lowest priority |

### Considered and not recommended

| Source | Why not |
|---|---|
| CraftPix, GameDev Market 2D tower-defence packs | Mostly paid; side-view or their own isometric angle; would not match the current art |
| CGTrader / Fab / TurboSquid creature models (e.g. scorpions) | Paid, realistic style, per-model licences |
| A CC0 low-poly scorpion | None found. If a scorpion is wanted, this is the one case where a custom model (or a recoloured crab from list A's pack) would be justified |

## 4. Recommendation

1. **Map enemies and bosses:** list A first (already here, zero cost), then packs 1 and 2 for whatever is
   still missing. Test-render each candidate next to the current enemies before committing to it.
2. **Heroes:** take packs 3 and 4 and re-render the Knight, King and Queen from them, keeping the
   gameplay unchanged. The home-made crown, cape, hammer and staff would be removed if the pack's own
   gear looks better in a side-by-side test.
3. **Scenery:** packs 6 and 7 for Desert and Lakeside dressing.
4. **Music:** pack 8, after checking each chosen track's licence.
5. **Icons:** leave as they are unless there is time.

## 5. Integration rules (unchanged, already in place)

* One asset manifest (`AssetPack/asset_manifest.json`) names every sprite; code never refers to files.
* Sprites are packed into texture atlases per age / per map, so only what a match needs is in memory.
* Sizes, anchors and health-bar positions come from the manifest; hit areas, speed, health and damage
  come from the game data and never from the picture.
* Raw packs stay out of the repository; only rendered sprites ship. Each pack gets a row in
  ASSET_LICENSES.md (name, source, author, licence, attribution, commercial use, where used).
