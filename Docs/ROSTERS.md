# Battlefield rosters: each map's own creatures and bosses

Phase 3 of the campaign expansion. Grassland keeps the original forest beasts. **Desert** and
**Lakeside** each replace all 14 beasts, monsters and mutants of the first three ages, including the
bosses of stages 5, 10 and 15, with creatures of their own. The robots of the Futuristic Age (and the
Titan War Machine) invade every battlefield.

All 28 creatures are existing CC0 models rendered through the game's bake pipeline; none was modelled
for this project (sources in the last column, licences in [ASSET_LICENSES.md](ASSET_LICENSES.md)).

## How it works

* `map_<id>.json` → `"roster"`: campaign enemy id → this battlefield's enemy id, e.g. `"wolf": "boneRunner"`.
* The stages in `waves.json` are written once. `GameConfiguration.selecting(battlefield:)` applies the
  roster, so `config.waves`, the wave intel, checkpoints and the simulation all see the map's creatures.
* Each creature is a full entry in `enemies.json` (`"battlefield": "<map id>"`), with its own name,
  description, stats and abilities. Summons, splits and broods name creatures of the same map.
* The loader rejects a roster whose swap changes era, boss or flying, or names an unknown enemy, so
  every stage keeps its shape (anti-air still matters where it did, bosses stay bosses).
* A map boss also counts as the campaign boss it replaces for the boss achievements.
* Art: a map's creatures are packed into `Enemies<Map><age>` atlases. `ArtLibrary.warmUp` loads only
  `config.enemiesInPlay`, so a Grassland match never decodes Desert or Lakeside sprites.
* Hit radius, health, speed and rewards come from `enemies.json`; the sprite's canvas is sized from the
  model so weapons and wings are not cut off, without touching gameplay.

## Desert

HP / speed / armour, with the Grassland creature's values in brackets.

| Replaces | Desert creature | HP / speed / armour | What it does | Model |
|---|---|---|---|---|
| Wolf | **Bone Runner** | 32 / 99 / 0 (was 38 / 92 / 0) | Brittle but quick skeleton scout. | Skeleton Minion, KayKit Skeletons |
| Wild Boar | **Cactling** | 90 / 63 / 2 (was 75 / 70 / 1) | Tough little cactus. Slow, with a prickly hide. | Cactus, Textured Cute Monster Pack |
| Bear | **Tomb Guard** | 215 / 40 / 5 (was 240 / 40 / 3) | Armoured skeleton warrior. Shrugs off light hits. | Skeleton Warrior, KayKit Skeletons |
| Alpha Beast | **Cactoro Chief** (boss) | 1430 / 34 / 5 (was 1300 / 36 / 5) | Boss. Calls cactlings out of the sand. | Cactoro, Ultimate Monsters |
| Giant Wolf | **Grave Stalker** | 135 / 92 / 1 (was 150 / 88 / 1) | Hooded skeleton that dashes forward. | Skeleton Rogue, KayKit Skeletons |
| Armored Beast | **Skull Orc** | 290 / 55 / 8 (was 260 / 55 / 9) | Orc in bone armour. Heavy but less plated than it looks. | Orc Skull, Ultimate Monsters |
| Troll | **Bone Shaman** | 595 / 40 / 4 (was 700 / 40 / 4) | Skeleton mage that mends the dead around it. | Skeleton Mage, KayKit Skeletons |
| Flying Monster | **Vulture** | 155 / 74 / 0 (was 140 / 78 / 0) | Circling flyer. Tougher than a bat, a little slower. | Eagle (darkened), Animal Pack vol. 2 |
| Ancient Dragon | **Sand Wyrm** (boss) | 4370 / 32 / 4 (was 4600 / 32 / 4) | Flying boss. Its sandstorm blinds more towers for a shorter time. | Yellow Dragon, Textured Cute Monster Pack |
| Mutant Beast | **Dune Raptor** | 400 / 86 / 3 (was 420 / 82 / 3) | Fast raptor that heals when left alone. | Dino (sand tint), Ultimate Monsters |
| Armored Monster | **Stone Skull** | 810 / 48 / 15 (was 900 / 48 / 13) | Living stone. Very heavy armour. | Skull, Textured Cute Monster Pack |
| Giant Mutant | **Orc Warlord** | 2200 / 37 / 6 (was 2200 / 37 / 6) | Huge orc. Raptors leap out when it falls. | Orc, Ultimate Monsters |
| Swarm Creature | **Sand Imp** | 66 / 106 / 0 (was 60 / 112 / 0) | Tiny imps that come in swarms. | Demon, Textured Cute Monster Pack |
| Mutant Titan | **Dune Tyrant** (boss) | 21000 / 27 / 12 (was 21000 / 27 / 12) | Boss. Regenerates and scatters imps as it is hurt. | Demon, Ultimate Monsters |

## Lakeside

| Replaces | Lakeside creature | HP / speed / armour | What it does | Model |
|---|---|---|---|---|
| Wolf | **Marsh Hopper** | 42 / 87 / 0 (was 38 / 92 / 0) | Hopping frog raider. A bit sturdier than a wolf. | Frog, Ultimate Monsters |
| Wild Boar | **Sporecap** | 68 / 74 / 1 (was 75 / 70 / 1) | Walking mushroom. Lighter and quicker than a boar. | Mushroom, Textured Cute Monster Pack |
| Bear | **Reef Brute** | 270 / 40 / 2 (was 240 / 40 / 3) | Big fish-man. Lots of health, thin scales. | Fish, Ultimate Monsters |
| Alpha Beast | **Mushroom King** (boss) | 1235 / 36 / 5 (was 1300 / 36 / 5) | Boss. Sprouts sporecaps in threes. | Mushroom King, Ultimate Monsters |
| Giant Wolf | **Heron Raider** | 150 / 88 / 1 (was 150 / 88 / 1) | Long-legged bird that sprints in bursts. | Birb, Ultimate Monsters |
| Armored Beast | **Bogwood** | 300 / 50 / 9 (was 260 / 55 / 9) | Walking stump. Slow and very solid. | Tree, Textured Cute Monster Pack |
| Troll | **Lake Wisp** | 630 / 40 / 4 (was 700 / 40 / 4) | Ghost that heals a wide area a little at a time. | Ghost, Textured Cute Monster Pack |
| Flying Monster | **Marsh Hornet** | 125 / 84 / 0 (was 140 / 78 / 0) | Quick flyer with little health. | Bee, Textured Cute Monster Pack |
| Ancient Dragon | **Lake Horror** (boss) | 4830 / 32 / 4 (was 4600 / 32 / 4) | Flying boss. Its ink cloud silences a few towers for longer. | Cthulhu, Textured Cute Monster Pack |
| Mutant Beast | **Bog Lurker** | 420 / 82 / 3 (was 420 / 82 / 3) | Swamp beast that heals when left alone. | Monkroose, Ultimate Monsters |
| Armored Monster | **Shell Brute** | 900 / 48 / 13 (was 900 / 48 / 13) | Shelled giant. Explosions bounce off. | Yeti (teal tint), Ultimate Monsters |
| Giant Mutant | **Deep One** | 2200 / 37 / 6 (was 2200 / 37 / 6) | Towering lake dweller. Lurkers crawl out when it falls. | Alien, Ultimate Monsters |
| Swarm Creature | **Mud Piranha** | 54 / 119 / 0 (was 60 / 112 / 0) | Flopping piranhas in huge numbers. Fast and frail. | Piranha, Animal Pack vol. 2 |
| Mutant Titan | **Tide Tyrant** (boss) | 21000 / 27 / 12 (was 21000 / 27 / 12) | Boss. Regenerates and spills piranhas as it is hurt. | Blue Demon, Ultimate Monsters |

Stats stay within 25 % of the creature they replace, and gold rewards are identical, so a battlefield
changes how a stage feels (what is fast, what is armoured, what the boss does) without changing its
overall weight.

## Balance check

`edtool balance-summary summons only=expert map=<id>` (5 seeds), expert player, base HP left:

| Battlefield | Easy | Normal | Hard |
|---|---|---|---|
| Desert, with roster | 5/5, 114 | 5/5, 94 | 3/5 |
| Desert, before (campaign creatures) | 5/5, 115 | 5/5, 86 | 4/5 |
| Lakeside, with roster | 5/5, 116 | 5/5, 100 | 4/5 |
| Lakeside, before | 5/5, 116 | 5/5, 93 | 4/5 |

The rosters leave difficulty about where it was (table above: measured before the tower effects).

With the tower effects of [TOWER_EFFECTS.md](TOWER_EFFECTS.md) in place, the same run gives:

| Battlefield | Easy | Normal | Hard |
|---|---|---|---|
| Desert | 5/5, 114 | 5/5, 114 | 5/5, 88 |
| Lakeside | 5/5, 117 | 5/5, 110 | 5/5, 108 |

so Hard on Desert and Lakeside, which the simulated expert did not always win after the 30-stage
extension, is now won every time. Players without research still fall around stage 17–18 on Normal on
both maps.

## Tests

`RosterTests`: Grassland unchanged; Desert and Lakeside each have 14 own creatures and 3 own bosses with
new names and art; swaps keep era / boss / flying and stay in the same weight class; creatures only call
their own kind; a Desert match really spawns Desert creatures; saved matches keep their roster; map
bosses count for achievements; a bad roster is rejected at load.
