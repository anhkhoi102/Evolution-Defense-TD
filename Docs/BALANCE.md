# Evolution Defense: Difficulty Rebalancing

> Later changes: 30 stages and stars ([CAMPAIGN.md](CAMPAIGN.md)), per-map creatures ([ROSTERS.md](ROSTERS.md)), and the tower effects Armour Shred and Expose with their measurements ([TOWER_EFFECTS.md](TOWER_EFFECTS.md)). Tower numbers quoted below predate those.

This covers the audit of the original difficulty system, the problems found,
the new difficulty curve, and how it was tested. Every number comes from
`edtool balance`, which plays scripted strategies through the whole match
(see [§ 6](#6-how-to-measure-and-retune)).

## 1. Audit: the original game

| Area | What exists |
|---|---|
| Length | 30 stages (waves): 5 per era for the first three eras, 15 in the Futuristic Age; a boss on stages 5, 10, 15 and 20, boss gauntlets on 25 and 30 (see [CAMPAIGN.md](CAMPAIGN.md)) |
| Enemies | 19: 15 regular + 4 bosses. Abilities: sprint, regenerate, stealth, energy shield, split on death, summon, brood, tower-disabling breath and EMP, base strike, flying, damage resistances, flat armor |
| Towers | 4 archetypes × 5 levels. Splash (area, ground only), Sniper (very long range, anti-air, sees stealth from L4), Heavy (big hits, armor penetration, anti-air from L4), Rapid (fast, weak vs armor) |
| Damage model | Resistance % first, then flat armor minus penetration, with at least 15 % of the hit always getting through |
| Waves | Fixed groups in `waves.json` (enemy, count, interval, delay, optional HP / speed / armor tuning) |
| Economy | 220 starting gold, kill gold per enemy, clear reward per wave, +15 for a perfect wave, early-start bonus, 70 % sell refund, repairs |
| Tech | 12 technologies, 3 per era, paid with Research Points from bosses, eras and perfect waves |
| Difficulty modes | Easy / Normal / Hard: one HP, speed and gold multiplier for the whole match |

### Measured difficulty (Normal, before)

How far the deepest enemy got along the path in each wave, as a percentage
(**XX** = base HP was lost):

```
wave                      1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20   result
expert (8 mixed, tech)   XX 87 71 61 78 37 66 59 56 79 26 29 56 39 57 26 27 27 31 XX   WIN  hp=112
spread (12 mixed, tech)  XX 87 71 68 XX 55 64 81 79 XX 45 57 74 77 XX 43 40 49 50 XX   WIN  hp=54
focused, no tech         XX XX 71 63 82 54 79 75 62 87 28 52 67 57 88 29 30 51 51 XX   WIN  hp=72
only sniper              33 38 65 52 58 51 45 31 52 39 43 49 51 55 54 19 47 57 53 XX   WIN  hp=116
only splash / heavy / rapid  lose on wave 7–8
```

## 2. Why the game was too easy

1. **The curve was upside down.** Wave 1 was the hardest wave of the match for
   a good player. From era 3 on, pressure fell to 26–40 % of the path, and
   era 4 was a walk-over.
2. **The economy snowballed.** Late clear rewards (130–220) plus kill gold grew
   faster than costs. A good player sat on 100–240 unspent gold before late
   waves, with almost every tower at level 5 by wave 16.
3. **One tower beat everything.** Snipers alone won with *more* HP than a mixed
   defence. Their 290–440 range covers a huge part of the 2,745-point path,
   they hit air, and they see stealth from level 4. Mixing towers wasn't needed.
4. **Late enemies didn't keep up with maxed towers.** Era-4 waves were small
   (20–59 enemies), and the bot's level-5 defence killed them a third of the way
   down the path.
5. **Waves had no theme.** Most waves mixed a bit of everything, so no single
   wave asked a specific question (air, armor, speed, swarm).
6. **Missing archetypes:** no healer or support enemy, and no elite variants,
   so there was no reason to change targeting priorities.

## 3. The new difficulty curve

| Phase | Waves | Target experience | Pressure target (expert) |
|---|---|---|---|
| 1 Learning | 1–4 | Learn towers and upgrades. Gentle groups, generous gold | Enemies reach 50–80 % of the path, no HP lost |
| 2 Strategic | 5–8 | Alpha boss, era-2 speed and air waves: one tower type is no longer enough | 70–95 %, rare small leaks |
| 3 Tactical | 9–12 | Armored and swarm waves, healers, first elites: placement and upgrade timing matter | Deep pushes, occasional leaks |
| 4 Advanced | 13–16 | Combined formations, elites with support, Mutant Titan | Leaks likely for weak setups |
| 5 Endgame | 17–20 | Stealth, shields, heavy mechs and elites together; final boss | An optimised defence wins with HP to spare; others don't |

Implemented with:

* **A central progression table** (`game.json → progression`) that scales every
  phase's enemy HP, speed, spawn interval, enemy count, kill gold and clear
  reward. This sits on top of the Easy / Normal / Hard multipliers and the
  per-group tuning in `waves.json`.
* **Themed waves** (swarm, speed, air, armored, elite, mixed, boss), so each
  wave asks a different question.
* **Two new mechanics built on existing systems:**
  * **Elite** enemies: a wave group can be marked `"elite": true`. Elites get
    more HP and armor, move a little faster and give more gold (stats set
    centrally in `game.json → elite`). On screen they show a gold ring and are
    drawn slightly larger.
  * **Healer** (the `healAura` ability): the Troll mends nearby monsters every
    few seconds and shows a green pulse when it does. Counterplay: kill it
    first (Heavy towers, *Strongest* targeting), or set its allies on fire,
    since burning enemies can't be healed.
* **Tower specialisation:** Sniper range and fire rate are reduced so it is the
  long-range anti-air and anti-stealth specialist, not the best tower against
  everything.
* **Economy:** a little more starting gold, and gold rewards that shrink in the
  later phases, so the late game is about choosing what to build and upgrade.

## 4. What changed

### Difficulty curve (`game.json → progression`)

Multipliers on top of the authored data. Phase 1 is the baseline, so the
opening plays exactly what `enemies.json` and `waves.json` say. Bosses are
tuned in `enemies.json` and are not scaled by the table.

| Phase | Waves | Enemy HP | Speed | Spawn interval | Count | Kill gold | Clear gold |
|---|---|---|---|---|---|---|---|
| Learning | 1–4 | 1 | 1 | 1 | 1 | 1 | 1 |
| Strategic | 5–8 | 1 | 1 | 1 | 1 | 1 | 1 |
| Tactical | 9–12 | 1.05 | 1 | 0.95 | 1 | 0.85 | 0.8 |
| Advanced | 13–16 | 1.15 | 1.03 | 0.9 | 1.05 | 0.75 | 0.7 |
| Endgame | 17–20 | 1.6 | 1.05 | 0.75 | 1.5 | 0.6 | 0.5 |

Phase 2 is harder because of its *content* (era-2 enemies, the first elites,
healers and air waves), not because of multipliers. Phases 3–5 add pressure
and cut income, so the late game is about choosing what to spend on. Phase 5
sits just inside an optimised defence's limit: at 1.7× HP and 1.6× count the
expert collapses on wave 18.

Each **difficulty mode** scales how strongly this table applies
(`difficulty.json → curve`):

| Mode | Curve | Other changes |
|---|---|---|
| Easy | 0.5 | Unchanged: 0.75× enemy HP, 0.95× speed, 1.15× gold, 280 gold, 20 s countdown |
| Normal | 1.0 | Starting gold 220 → **250** |
| Hard | 1.0 | Enemy HP 1.08× → **1.0×**, gold **0.95×**, starting gold 210 → **240**, 12 s countdown. Hard is now about a tighter economy and less time, not tougher enemies |

### New mechanics (built on existing systems)

| Mechanic | Where | Purpose | Counterplay | On screen |
|---|---|---|---|---|
| **Elite** | `"elite": true` on a wave group; stats in `game.json → elite` (2.2× HP, +3 armor, 1.08× speed, 2.5× gold) | A strong enemy inside a weaker group: target priority matters | Heavy towers, *Strongest* targeting, armor penetration | Pulsing gold ring on the ground, gold glow on the body, slightly larger sprite, gold health-bar frame. "N elite" in the wave intel |
| **Healer** (`healAura`) | The Troll: every 4 s it heals other enemies within 120 points by 5 % of their max HP | Tanks that protect their escort | Kill it first; burning enemies (Fire Technology) can't be healed; it never heals itself or bosses; one heal per target per interval however many healers | Green ring sweeping out to the healing radius. "Heals allies" in the wave intel |
| **Wave themes** | `waves.json → theme` | Each wave asks one question | — | "· Swarm wave" etc. in the wave intel, with a tooltip saying what it tests |

### Enemies and bosses

| Enemy | Change | Why |
|---|---|---|
| Troll | + Mending Chant (heal aura) | Tank and support archetype |
| Mutant Beast | Regeneration 16 → 12 HP/s | Elite regenerating packs were a wall for non-fire defences |
| Alpha Beast | Base damage 25 → 15 | The first boss shouldn't cost a quarter of the base |
| Ancient Dragon | HP 4,200 → 4,600, armor 3 → 4, base damage 25 → 20 | Bigger mid-game check |
| Mutant Titan | HP 18,000 → 21,000; Brood Burst 5 swarm every 15 % → 7 every 12 % | Phase-4 boss with multiple simultaneous threats |
| Titan War Machine | HP 28,000 → 30,000 | Slightly longer final fight |

### Towers

| Tower | Change | Why |
|---|---|---|
| Sniper L1–L5 | Range 290/330/360/400/440 → **260/285/310/345/380**; fire rate 1.3–1.5 → **1.1–1.2/s**; damage 12/20/34/58/100 → **14/24/40/68/115** | Snipers alone won every difficulty. Now the long-range anti-air and anti-stealth specialist, weaker against swarms |
| Level 4 upgrades | Splash 210 → 240, Sniper 190 → 215, Heavy 280 → 320, Rapid 220 → 250 | Upgrading stays valuable, but maxing everything is a choice |
| Level 5 upgrades | Splash 360 → 460, Sniper 320 → 410, Heavy 450 → 560, Rapid 360 → 460 | Same; it targets strong defences specifically |

### Economy

* Starting gold 220 → 250 (Normal); clear rewards for waves 1–4 +10 % (30/40/50/60 → 33/44/55/66).
* Kill and clear gold shrink from phase 3 (see the table above). An optimised
  player used to bank 150–2,300 unspent gold late; now spending decisions
  matter until the end.
* Unchanged: 70 % sell refund, perfect-wave bonus, early-start bonus, repairs.

### Waves

All 20 waves were redesigned around a theme:

| Waves | Themes |
|---|---|
| 1–4 | Learning, Learning, Speed (boars and wolves, first bears), Tank (bears) |
| 5 | **Boss**: Alpha Beast with its pack |
| 6–9 | Speed (sprinting Giant Wolves, first elites), Air (flying monsters), Armored (armored beasts with Troll healers), Elite (elite armored beasts escorted by healers, wolves and flyers) |
| 10 | **Boss**: Ancient Dragon with flying escort and healers |
| 11–14 | Swarm (85 swarm creatures), Armored (armored monsters, elite mutants), Tank (giant mutants with healers, elite flyers), Elite (everything, with elite armored monsters) |
| 15 | **Boss**: Mutant Titan with brood, armored monsters and giant mutants |
| 16–19 | Speed (scout robots, elite scouts, shields), Stealth (cloaking robots, elite assault robots), Armored (heavy mechs with shields and stealth), Mixed (everything, elite heavy mech) |
| 20 | **Boss**: Titan War Machine with a full escort |

## 5. Results

### Before and after (5 seeds each: 3, 7, 11, 23, 42)

Wins, average furthest wave (20 = won) and average HP left.

| Strategy | Before: Normal | **After: Normal** | Before: Hard | **After: Hard** | **After: Easy** |
|---|---|---|---|---|---|
| Expert (8 mixed, tech) | 5/5 · 20 · 110 HP | **5/5 · 20 · 107 HP** | 5/5 · 56 HP | **5/5 · 86 HP** | 5/5 · 114 HP |
| Spread (12 mixed, tech) | 5/5 · 20 · 56 HP | **0/5 · 16.6** | 5/5 · 58 HP | **0/5 · 15.4** | 5/5 · 94 HP |
| Focused, no tech | 5/5 · 20 · 72 HP | **0/5 · 14.8** | 0/5 · 9.2 | **0/5 · 13.2** | 5/5 · 91 HP |
| Casual (between waves, no tech) | 1/5 · 20 · 5 HP | **0/5 · 13.8** | 0/5 · 9.0 | **0/5 · 13.0** | 5/5 · 91 HP |
| Only sniper | **5/5 · 116 HP** | **0/5 · 17.0** | 5/5 · 116 HP | **0/5 · 17.0** | 5/5 · 76 HP |
| Only splash / heavy / rapid | lose wave 8–9 | lose wave 8–9 | lose wave 6–9 | lose wave 8–9 | lose wave 10–18 |
| Level-1 spam (16 towers) | 0/5 · 9.0 | 0/5 · 9.0 | 0/5 · 9.0 | 0/5 · 9.0 | 0/5 · 12.0 |
| Passive (2 towers) | 0/5 · 3.0 | 0/5 · 4.0 | 0/5 · 3.0 | 0/5 · 4.0 | 0/5 · 4.0 |

With random events on, the expert also wins every seed tried on every
difficulty (Normal 100 HP, Hard 89 HP on average).

### Per-wave pressure (Normal, after)

```
wave                      1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20   result
expert (8 mixed, tech)   65 81 45 61 78 61 70 79 76 79 27 36 58 55 83 33 78 77 92 XX   WIN  hp=111
spread (12 mixed, tech)  65 81 45 63 XX 65 81 81 XX XX 57 61 84 XX XX XX XX -- -- --   LOSS (wave 17)
focused, no tech         65 82 57 61 XX 68 84 86 XX XX 74 88 XX XX -- -- -- -- -- --   LOSS (wave 14)
casual                   65 82 62 70 XX 63 84 86 XX XX 74 88 XX XX -- -- -- -- -- --   LOSS (wave 14)
only sniper              29 36 76 55 69 63 53 47 67 52 74 77 70 XX XX 79 XX -- -- --   LOSS (wave 17)
```

### Phase by phase

| Phase | Check | Result |
|---|---|---|
| 1 (0–20 %) Accessible? | No reasonable strategy loses HP on waves 1–4 (test `openingIsAccessible`). Only "do nothing" (2 towers, no upgrades) fails | ✅ Accessible, not trivial: enemies still reach 45–82 % of the path |
| 2 (20–40 %) Meaningful decisions? | Splash-only, heavy-only, rapid-only and level-1 spam all fall on waves 7–9 (air, armor and elite waves). Non-experts start leaking at the Alpha boss | ✅ One tower type or skipping upgrades no longer works |
| 3 (40–60 %) Combos and upgrades matter? | Non-experts leak on waves 9–10 (flyers, armored elites, the Dragon). Without the tech tree, regenerating mutants and healers can't be answered | ✅ |
| 4 (60–80 %) Challenges experienced players? | Casual and no-tech players fall on waves 13–15; snipers-only and spread-thin defences on 16–17 | ✅ No cliff: losses spread over the phase, and wave 13's healer stacking was removed |
| 5 (80–100 %) Satisfying endgame? | Only the optimised strategy survives; it is pushed to 75–92 % of the path, sometimes takes damage, and still wins every seed. At 1.7× HP it would collapse, so the endgame is close to its limit but beatable | ✅ |

Spikes and dips checked: the deepest moments are the boss waves (5, 10, 15,
20). Waves 11 and 16 are deliberate breathers after a boss, while the new era's
enemies are introduced. The steepest *regular* step is wave 13, the first
phase-4 wave: players without tech go from a clean wave 12 to losing HP there.
It used to wipe them out in one wave (stacked healers); after the fix it costs
part of their base and they fall one or two waves later.

## 6. How to measure and retune

```bash
# Per-wave pressure for every strategy (seeds optional), plus a detailed leak breakdown for one:
swift run -c release --package-path Packages/EvolutionDefenseCore edtool balance normal 3 7 profile=1
# Win rate / furthest wave / HP left for every strategy on every difficulty (5 seeds):
swift run -c release --package-path Packages/EvolutionDefenseCore edtool balance-summary [events]
```

* The curve is the `progression` table in `game.json`. Elite stats are
  `game.json → elite`, mode strength is `difficulty.json → curve`, and wave
  content is `waves.json`. No gameplay code holds balance numbers.
* The scripted strategies are `BalancePlayer.profiles`
  (`Packages/EvolutionDefenseCore/Sources/EvolutionDefenseCore/Balance/`).
* The `Balance (difficulty curve)` and `Difficulty curve & new enemy mechanics`
  test suites fail if the curve drifts: opening HP loss, phase reached by each
  strategy, monoculture wins, Easy / Hard relations, healer and elite rules.

## 7. Remaining concerns

* **The bots don't adapt.** Real players can sell, re-spec, change targeting
  and read the wave intel, so an average human should do better than the
  "casual" bot. The Normal curve may feel a little easier than these numbers
  suggest. Playtest feedback should be checked against the casual and spread
  rows.
* **Phase 5 is close to the optimum.** It is tuned near the expert bot's limit.
  Raising phase-5 HP or count by about 10 % flips wins to losses, so tune
  that row in small steps.
* **Hard is narrow.** The expert wins every seed tried, but with little
  margin on some.
* **Easy lets snipers alone win.** That's acceptable for a learning mode, but
  it is the one place a single tower type still works.
* **Ancient Dragon and Mutant Titan** still cost non-experts a lot when they
  get through (20 and 25 HP).
