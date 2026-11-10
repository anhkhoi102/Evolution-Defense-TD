# Campaign: 30 stages and a star rating

Phase 1 of the campaign expansion. A match is still one continuous run on one battlefield; it now
lasts **30 stages** (a stage is one wave of enemies) instead of 20, and a won match is rated with
**1 to 3 stars**.

## Stages

| Stages | Era | Difficulty phase |
|---|---|---|
| 1–4 | Primitive | Learning |
| 5–8 | Primitive → Medieval | Strategic |
| 9–12 | Medieval → Industrial | Tactical |
| 13–16 | Industrial → Futuristic | Advanced |
| 17–20 | Futuristic | Endgame |
| 21–25 | Futuristic | Very Hard |
| 26–30 | Futuristic | Expert |

Stages 1–20 are unchanged apart from stage 20 no longer ending the match (its clear reward is now a
normal one). Stages 21–30 are new designs, each built around a theme rather than more health:

| Stage | Theme | Line-up (before the phase's count multiplier) |
|---|---|---|
| 21 | Swarm | 50× swarmCreature, 12× stealthRobot, 5× elite scoutRobot, 40× swarmCreature |
| 22 | Air | 14× flyingMonster, 8× assaultRobot, 3× troll, 6× elite flyingMonster |
| 23 | Armored | 5× heavyMech, 5× elite armoredMonster, 3× troll, 8× assaultRobot |
| 24 | Elite | 3× elite giantMutant, 26× scoutRobot, 2× elite heavyMech, 12× stealthRobot |
| 25 | Boss | 20× giantWolf, 1× ancientDragon, 12× flyingMonster, 1× mutantTitan, 6× armoredMonster |
| 26 | Speed | 34× scoutRobot, 16× elite giantWolf, 8× elite scoutRobot, 18× mutantBeast |
| 27 | Stealth | 20× stealthRobot, 10× assaultRobot, 6× elite stealthRobot, 4× elite assaultRobot |
| 28 | Tank | 7× heavyMech, 4× elite troll, 10× armoredMonster, 4× giantMutant |
| 29 | Mixed | 5× heavyMech, 14× flyingMonster, 14× stealthRobot, 6× elite assaultRobot, 30× scoutRobot, 2× elite heavyMech |
| 30 | Boss | 24× scoutRobot, 8× assaultRobot, 1× mutantTitan, 1× ancientDragon, 1× titanWarMachine, 3× heavyMech, 12× stealthRobot, 4× elite assaultRobot |

Bosses are never multiplied by the phase. The stage 25 and 30 bosses come back with a health
multiplier set on their spawn group in `waves.json`.

### Difficulty phases (`game.json` → `progression`)

| Phase | From stage | Enemy HP | Speed | Count | Spawn interval | Kill gold | Clear gold |
|---|---|---|---|---|---|---|---|
| Learning | 1+ | ×1 | ×1 | ×1 | ×1 | ×1 | ×1 |
| Strategic | 5+ | ×1 | ×1 | ×1 | ×1 | ×1 | ×1 |
| Tactical | 9+ | ×1.05 | ×1 | ×1 | ×0.95 | ×0.85 | ×0.8 |
| Advanced | 13+ | ×1.15 | ×1.03 | ×1.05 | ×0.9 | ×0.75 | ×0.7 |
| Endgame | 17+ | ×1.6 | ×1.05 | ×1.5 | ×0.75 | ×0.6 | ×0.5 |
| Very Hard | 21+ | ×1.9 | ×1.06 | ×1.5 | ×0.75 | ×0.5 | ×0.45 |
| Expert | 26+ | ×2.2 | ×1.1 | ×1.7 | ×0.7 | ×0.45 | ×0.4 |

Easy and Hard scale the whole table through `curve` in `difficulty.json`, as before.

### Balance check (Grassland, 5 seeds each, `edtool balance`)

| Player model | Easy | Normal | Hard |
|---|---|---|---|
| Expert (full plan, upgrades, tech, summons) | wins 5/5 | wins 5/5, about 107 base HP left | wins 5/5 |
| Spread builder | — | falls around stage 17 | — |
| Casual | — | falls around stage 14 | — |
| Snipers only | wins | falls around stage 17 | — |

Expert pressure (share of the road the front enemy reaches) is 55–84 % on stages 21–25 and
77–91 % on stages 26–30, so the last five stages press clearly harder than the five before.

## Star rating

A match is rated **once, when it is won**. Stages are not rated. The rating looks at all the base HP
lost during the match, as a share of the base's maximum HP; repairing does not undo it.

| Stars | Rule | Setting (`game.json` → `stars`) |
|---|---|---|
| 3 | Lost no more than `threeStarMaxDamageFraction` of the base's maximum HP | `0.1` |
| 2 | Lost no more than `twoStarMaxDamageFraction` | `0.4` |
| 1 | Match won | — |
| 0 | Match lost or not finished | — |

* `StarRatingConfig.stars(damage:maxBaseHP:)` is the only place the rule lives.
* `GameWorld.baseDamageTaken` counts the HP lost; it is saved in the match checkpoint
  (`MatchCheckpoint.damageTaken`), so Continue keeps it. `GameWorld.matchStars` is 0 until the match is won.
* `PlayerProfile.matchStars` keeps the **best** rating per battlefield (`recordMatchStars` only ever
  raises it), so there are 3 stars to earn per battlefield, 9 in all.
* `PlayerProfile.stagesCleared` keeps the highest stage cleared per battlefield, written the moment a
  stage is cleared. `highestStageCleared` drives the hero unlocks (King after stage 10, Queen after 20).
* Older profiles and checkpoints still load. Development builds that rated every stage keep their
  stage progress; those per-stage ratings are dropped.

## Screens

* **Main menu → Campaign**: all 30 stages of the chosen battlefield (cleared, next, locked), the best
  rating of each battlefield on its tab, and the overall total (out of 9).
  It is a progress map: stages are played in order inside one match, not picked one at a time.
* **Stage summary** (between stages): no stars.
* **End screen** (victory): the match's stars pop in one by one with a tick sound.

## Tests

`StarRatingTests` (thresholds, only a won match is rated, all damage counts and repairs do not help,
best-only merging, profile and checkpoint round-trips, old saves), `EvolutionTests.thirtyStagesWithABossOnEveryFifth`, the updated
`DifficultyCurveTests`, and the full-match tests in `SimulationTests` / `GameplayLoopTests`
(an optimised defence wins all 30 stages on Normal; stages 26–29 press harder than 21–25).
`Scripts/battlefield-test.sh` also checks that a cleared stage is rated and stored on every battlefield.

## Not in this phase

The King and Queen heroes arrived in phase 2 ([HEROES.md](HEROES.md)). Map-specific enemies and bosses
arrived in phase 3 ([ROSTERS.md](ROSTERS.md)). The tower tier review and the iOS groundwork are still to come.
