# Gameplay and balance audit, with proposed changes (Phase 1)

> **Status, 11 November 2026:** Phase 1 (this audit) approved. **Phase 2 (economy and towers) is
> implemented**: see [section 6](#6-phase-2-results). **Phase 3 (enemies and bosses) is implemented**:
> see [section 7](#7-phase-3-results). **Phases 4 and 5 are done**: the final state and what is still
> open are in [section 8](#8-phases-4-and-5-final-state). Where sections disagree, section 8 is current. Sections 1–5 are the original audit and proposal.

All measurements: Grassland, Normal, heroes and militia on, seeds 3/7/11, version 1.4.0.
Commands: `edtool balance normal summons`, `edtool tower-report normal summons`.

## 1. What the audit found

### 1.1 Why the game gets easy from about stage 20

| # | Finding | Evidence |
|---|---|---|
| 1 | **Gold runs out of things to buy.** All 16 pads at level 5 cost 15,700 gold in total. The simulated expert reaches that at stage 27 and then just piles gold up. | Unspent gold at the start of stage 27 / 28 / 29 / 30: 509 / 1,387 / 2,239 / 3,417 |
| 2 | **The defence is finished before the hardest stages start.** Stages 26–30 are fought with every tower already maxed, so nothing is left to decide. | 80 of 80 tower levels from stage 27 |
| 3 | **Technology is all bought.** The 12 technologies cost 63 points; a clean match earns about 80. | 9 of 12 owned at stage 20, 12 of 12 at stage 27, points left over after that |
| 4 | **Research needs no decisions.** Every technology is good for every line-up, none excludes another, and five of the twelve are plain percentage boosts. | Improved Arrows, Gunpowder, Ballistic Research, Automated Weapons, Plasma Technology |
| 5 | **Late enemies scale by health and number only.** Stages 21–30 reuse the stage 6–20 enemies at ×1.9–2.2 health and ×1.5–1.7 count. No new behaviour appears after stage 17. | `game.json` → `progression` |
| 6 | **The expert takes almost no damage.** Only the stage 20 boss costs any base health (6 HP in the whole match). | Final base health 114 of 120 on all three seeds |

### 1.2 Towers

| Tower | Share of gold | Share of damage | Damage per gold | Reading |
|---|---|---|---|---|
| Splash | 25 % | **56 %** | **352** | Far above the others. It hits groups *and* is good against single targets (200 damage, pierce 9 at level 5), and it also slows. |
| Sniper | 22 % | 17 % | 122 | Not the top damage dealer, but it covers almost the whole map (range 380), hits air and cloaked enemies, and has no weak matchup. |
| Heavy | 29 % | 17 % (+4 % enabled) | 115 | Most expensive. Cannot hit air before level 4. |
| Rapid Fire | 25 % | 10 % (+1 % enabled) | 74 | Weakest return even after the armour-shred change. |

Fixed two-tower line-ups (8 towers first, then all pads; never sell), stages cleared of 30:

| Line-up | Stages cleared | Where it breaks |
|---|---|---|
| Sniper + Splash | **29** | Almost wins alone; loses only at the last boss |
| Rapid Fire + Splash | 19 | Stage 20 boss |
| Heavy + Sniper | 16 | Swarms in the third age |
| Heavy + Splash | 8 | Flyers (neither can hit air before Heavy level 4) |
| Rapid Fire + Heavy | 8 | Early swarms; too expensive to get going |
| All four mixed (expert) | 30 | Wins with 114 HP |

So the player's impression is right: **Sniper + Splash is the one pair that carries a match**, and the
other pairs fall far behind. Splash is the damage outlier; Sniper is the coverage outlier.

### 1.3 What already exists and should be kept

* **Towers already have five levels** (Stone Age to Future). "One more tier" therefore means a **sixth** level.
* **Bosses already knock towers out.** The Ancient Dragon (Fire Breath) and the Titan War Machine (EMP Blast), and their Desert and Lakeside versions, disable the 2–4 nearest towers for 2.5–3.5 s. The tower keeps its place, level and settings; nothing is destroyed. What is missing: paying to recover, a countdown on the tower, protection against the same tower being hit again and again, and a cap relative to how many towers the player has.
* **Status effects already exist**: slow, burn, stun, critical hits, Armour Shred (Rapid Fire) and Expose (Heavy), all applied through one routine (`applyStatus`) with boss limits.
* **The star rating is already one rating per campaign** (added in 1.4.0): only a won match is rated, from the total base health lost; thresholds are in `game.json`; stage tiles show no stars.
* The simulation, configuration files, rendering and platform layers are already separate. No rewrite is needed.

## 2. Proposed changes

Numbers marked ≈ are starting values; Phase 5 tunes them against the targets in section 3.

### 2.1 Gold

| Setting | Now | Proposed | Why |
|---|---|---|---|
| Level 1–3 costs | as today | unchanged | Keep the early game as it is |
| Level 4 cost | 215–290 | ≈ +10 % | Slightly slower mid game |
| Level 5 cost | 410–500 | ≈ +20 % | The level-5 jump is cheap for what it gives |
| **Level 6 (new)** | none | ≈ 850–1,000 each | The late gold sink: all 16 would cost about 15,000 more, so a player can afford roughly 5–7 and must choose which |
| Kill reward, stages 21–25 / 26–30 | ×0.50 / ×0.45 | ≈ ×0.45 / ×0.38 | Counts rise ×1.5–1.7, so income per stage still grows |
| Elite reward | ×2.5 | ≈ ×2.0 | Elites are common late |
| Instant tower recovery | none | new cost (section 2.5) | A small, optional sink during boss stages |
| Starting gold, stages 1–10 rewards, sell refund (70 %) | as today | unchanged | |

### 2.2 Technology

| Change | Detail |
|---|---|
| **Doctrines: choose 1 of 2 in each age** (8 new technologies, 4 picks) | Stone Age: *Trappers* (slows last 50 % longer) or *Hunters* (+25 % damage to enemies above 80 % health). Medieval: *Incendiary* (Splash burns without the fire technology, burn spreads on death) or *Cryo shells* (three slows within 4 s freeze the enemy for 0.8 s). Industrial: *Field engineers* (disabled towers recover 40 % sooner, instant recovery at half price) or *Overpressure* (stunned or frozen enemies take +20 %). Future: *Tesla coils* (chain lightning jumps to 2 more targets) or *Target painter* (Expose also applies in a small area) |
| Rework the plain percentage technologies | *Improved Arrows* → Sniper and Rapid Fire deal +20 % to slowed or burning enemies. *Automated Weapons* → towers that have fired at the same target for 3 s attack 20 % faster. *Plasma Technology* → energy weapons ignore half of energy shields, +4 pierce. *Gunpowder* and *Ballistic Research* stay as they are (one simple boost per age is fine) |
| Total cost | 63 → ≈ 95 points, against ≈ 80 earned, so not everything can be bought |
| Perfect-stage point | 1 every stage → ≈ 1 every stage up to 15, then only on boss stages | Stops the surplus late without touching the early game |

### 2.3 Tower roles, changed values and the sixth level

| Tower | Role | Changes to existing levels | New level 6 |
|---|---|---|---|
| **Splash** | Groups. Weak against one big target. | **Blast falloff**: full damage in the inner half of the blast, falling to 60 % at the edge. Pierce at levels 4–5: 5 / 9 → 4 / 6. Damage unchanged. | *Nova Artillery* ≈ 900 gold: leaves burning ground for 3 s (6 % of the hit per second to everything on it), slow 25 % → 30 % |
| **Sniper** | One valuable target at any distance. Poor against crowds. | Levels 4–5 fire slower and hit harder (1.2 → 0.9 per second, damage raised to keep single-target damage the same), so shots are wasted on small enemies. Prefers Exposed targets. | *Quantum Rifle* ≈ 850 gold: **Execute** (+50 % damage to enemies under 30 % health, +25 % on bosses) and 25 % chance of a double-damage critical hit on Exposed targets |
| **Heavy** | Armour and very high health. Sets targets up for the others. | Can hit air from level 3 instead of 4 (so Heavy line-ups are not helpless against flyers). Level 1–2 cost 90 / 100 → ≈ 80 / 90. | *Siege Platform* ≈ 1,000 gold: Expose 25 % → 30 %; **Stagger** (non-boss targets slowed 40 % for 1 s); **Interrupt** (a hit delays a boss's next ability by 1.5 s, at most once every 6 s) |
| **Rapid Fire** | Strips armour, cleans up fast and small enemies, hits air. | Levels 1–2 damage ≈ +10 %. | *Tesla Gatling* ≈ 900 gold: **Chain lightning** (every 5th shot jumps to 3 more enemies within 90 for 60 % damage, and the jumps carry Armour Shred) |

No fifth "support" tower type is proposed: it would need new art and a place in every menu, and the
support roles are covered by effects (Heavy's Expose, Rapid Fire's Shred, Splash's slow).

**Branching choices** (the level-4 fork from the earlier proposal) are left out here. The doctrines give
the either-or decisions with far less new interface; a fork can still be added later.

### 2.4 Status effects

| Effect | Source | Chance | Strength and duration | Stacking | Bosses |
|---|---|---|---|---|---|
| Slow | Splash 4–6, technology | 100 % | 15–30 %, 1–1.5 s | Strongest wins, time refreshes | Half strength |
| Burn | Fire technology, Nova ground | 100 % | 6–8 % of the hit per second, 2.5–3 s, ignores armour, stops regeneration | Strongest wins, refreshes | Normal |
| Armour Shred | Rapid Fire 3–6 | 100 % | −1 armour per hit up to 6 / 10 / 14 / 16, 3 s | Stacks to the cap | Half the cap |
| Expose (mark) | Heavy 3–6 | 100 % | +15 / 20 / 25 / 30 % damage from all sources, 4 s | Never stacks | 2 s |
| Stagger | Heavy 6 | 100 % | 40 % slow, 1 s | Counts as a slow | Immune |
| Stun | Heavy 4–5 (existing) | 100 % | 0.2–0.4 s | Cannot be re-stunned for 4 s after it ends | Immune |
| Freeze | *Cryo shells* doctrine | on the 3rd slow within 4 s | 0.8 s | Immune for 6 s afterwards | Immune |
| Interrupt | Heavy 6 | 100 % | Next boss ability +1.5 s | Once per 6 s per boss | Bosses only |
| Execute | Sniper 6 | under 30 % health | +50 % damage | — | +25 % |
| Chain lightning | Rapid Fire 6 | every 5th shot | 3 jumps, 60 % damage, range 90 | — | Normal |
| Critical hit | Rapid Fire 4–6, Sniper 6 | 8–25 % | ×2–2.5 | — | Normal |

**Control limit:** an enemy can never be stopped (stun or freeze) for more than about 1 second in
any 5. *Paralyzed* is not added separately; stun already is that effect.
**Visuals:** each effect keeps or gets one small marker (the existing blue tint, flame, red ring and
purple diamond; new: ice shard for freeze, yellow arc for chain lightning, skull flash for execute).

### 2.5 Boss tower disable and recovery

| Rule | Now | Proposed |
|---|---|---|
| Duration | 2.5–3.5 s | ≈ 6 s (long enough that paying is a real choice) |
| Time between uses | 5–10 s | ≈ 12 s (10 s when enraged) |
| Towers hit | 2–4 nearest | 2–3 nearest, and **never more than a quarter of the player's towers** (at least 1) |
| Same tower again | possible at once | A recovered tower is **protected for 8 s** |
| Recovery | wait only | **Wait** (free), or **Restart now**: select the tower, the panel shows the price, one click pays and restarts it |
| Price | — | ≈ 8 % of the gold spent on that tower, between 15 and 120 gold |
| On the tower | grey tint | Grey tint, sparks and a **countdown ring with the seconds** above it |
| Technical | `Tower.disabledUntil` in simulation time (already pause-safe) | Unchanged; add `GameWorld.recover(tower)` that checks the tower is still disabled, charges once and clears the state. The tower object is never replaced |

All numbers go in `game.json` → `towerDisable`. Bosses never damage, destroy or remove towers.
The Alpha Beast (summons wolves) and Mutant Titan (regenerates, sheds swarms) keep their own
abilities, so not every boss fight is about disabling.

### 2.6 Enemies and stages 16–30

* **Three late-game traits**, built from existing creatures with a tint and a small badge (no new art):
  *Insulated* (cannot be slowed or frozen), *Plated* (Armour Shred works at half strength),
  *Phase runner* (briefly immune to damage every few seconds, so burst is wasted and steady fire is not).
* **Stages 21–30 rewritten as mixtures** instead of bigger copies: every stage combines at least
  three of air, armour, swarm, cloaked and a trait, so no single tower answers it and none is required.
* Health multipliers for stages 21–30 are raised only as far as needed to match the new level 6
  (expected ≈ +10–15 %); stages 1–15 keep their numbers.

### 2.7 Campaign and stars

Already as requested since 1.4.0. One addition: the victory screen will also show **base health
lost** and **enemies that got through** next to the stars, as the campaign result. Old saves keep loading.

## 3. Targets for Phase 5 (how "balanced" will be judged)

| Measure | Now | Target |
|---|---|---|
| Unspent gold at stage 30 (expert) | 3,417 | under ≈ 600 |
| Towers at top level at stage 30 | 16 of 16 | about 5–7 of 16 at level 6 |
| Technologies owned at the end | 12 of 12, points left over | about 15 of 20, no more than 3 points left |
| Splash share of damage (mixed line-up) | 56 % | ≈ 35–40 % |
| Rapid Fire share including what it enables | 11 % | ≈ 18 % or more |
| Expert, Normal, Grassland | wins, loses 6 HP | wins, loses ≈ 15–35 HP (2 stars typical, 3 possible) |
| Two-tower line-ups that clear stage 30 on Normal | 0 of 5 (best: 29) | at least 3 of 5, each with a visible weakness |
| Single-tower line-ups | all lose by stage 17 | still lose |
| Boss stages while never paying for recovery | — | every winning line-up still wins |
| Any line-up required to sell or swap towers | no | no (the simulated players never sell) |

## 4. Files that will change

| Phase | Files |
|---|---|
| 2 Economy and towers | `towers.json`, `tech.json`, `game.json`; `TowerData.swift`, `TechData`/modifiers, `GameWorld+Combat.swift` (falloff, execute, chain, burning ground), `Entities.swift`; tower sprites for level 6 (the level-5 model with added parts from the existing kits), `TowerPanel.swift` (6 pips), `EntityRenderers.swift`, `EffectsRenderer.swift`; tech panel (doctrine pairs) |
| 3 Enemies and bosses | `enemies.json`, `waves.json`, `map_*.json` rosters, `game.json` (`towerDisable`); `GameWorld+Abilities.swift`, `GameWorld.swift` (recover), `GameController.swift`, `TowerPanel.swift`, tower renderer (countdown) |
| 4 Campaign | `Overlays.swift` (result lines); checkpoint and profile already carry what is needed |
| 5 Validation | `BalancePlayer.swift` (level 6, doctrines, recovery policy), tests, `Docs/BALANCE.md` |

Saved matches from 1.4.0 keep loading: new fields are optional and a level-5 tower stays level 5.

## 5. Risks

| Risk | Control |
|---|---|
| Too many changes at once hide which one broke the balance | One phase at a time; the report in section 1 is re-run after each |
| Level 6 makes the end easier, not harder | Its price and the late reward cuts are tuned together against section 3 |
| Sniper feels bad after the rate change | Single-target damage is kept equal; only overkill on small enemies is lost |
| Doctrines add interface work | They reuse the existing tech panel; a locked partner is shown greyed out |
| Level-6 art | Reuse the level-5 model with extra parts and a glow; if that reads poorly, it is shown before release |
| Heavy hitting air from level 3 removes a weakness | Flyers still out-range it; measured with the Heavy line-ups |

## 6. Phase 2 results

Measured with `edtool balance-summary summons [map=…]` (5 seeds) and `edtool tower-report normal summons`.

### 6.1 What was built

* **Level 6 for every tower**, each with its own ability (table below). It reuses the level-5 model
  with a golden ground ring (`visualLevel` in `towers.json`); it has no model of its own yet.
* **New effects**, all data-driven fields of `HitEffects`: blast falloff, burning ground, Execute,
  critical hits on Exposed targets, Stagger (a slow), Interrupt, chain lightning, and the technology
  effects (bonus against slowed or burning enemies, bonus against healthy enemies, focus fire, shield breaking).
* **Control limit**: after a stun or freeze ends, the enemy cannot be stopped again for 4 s (6 s after a freeze). Bosses are never stunned or frozen.
* **Doctrines**: 8 new technologies in 4 either-or pairs (`group` in `tech.json`). The tech panel
  shows each pair under "Doctrine · choose one" and greys out the one not taken.
* **Three plain percentage technologies reworked**: Improved Arrows, Automated Weapons, Plasma Technology.
* **Research income**: the perfect-stage point is paid every stage up to 20, then on boss stages only.
* **Gold**: late kill rewards and the elite reward cut slightly; level 6 is the late gold sink.
* **Balance tool**: plays the five two-tower line-ups, buys level 6 and picks doctrines, prints research per stage.

### 6.2 Where the build differs from the proposal, and why

| Proposal | Built | Why |
|---|---|---|
| Level 4 and 5 cost +10 % / +20 % | **Unchanged** | With dearer mid levels the expert lost at stage 17. The middle of the game was not the problem, so it keeps its prices; level 6 alone is the sink |
| Kill reward ×0.45 / ×0.38 late | ×0.50 (unchanged) / ×0.42 | Same reason: the late game became a wall |
| Enemy health +10–15 % late | **Lower**: stages 17–20 ×1.6 → 1.5, 21–25 ×1.9 → 1.8, 26–30 ×2.2 → 2.05 | Removing the flat technology boosts took about a fifth of the towers' damage away; less health inflation fits the brief better than putting the boosts back |
| Splash falloff on every level | From level 3 | Falloff at levels 1–2 made stage 5 cost 23 base health |
| Sniper, Heavy, Rapid Fire damage as today | Level 3–6 raised about 8–16 % | Replaces the removed flat technology boosts and moves damage share away from Splash |
| Chain lightning at Rapid Fire level 6 only | Weaker versions from level 4 | Line-ups without Splash had no answer to crowds before stage 27 |
| Perfect-stage point until stage 15 | Until stage 20 | 15 left too few points for the fourth age |
| Stagger: bosses immune | Bosses take half (it is an ordinary slow) | Reuses the existing slow rule |
| Technology total ≈ 95 | 87 with one doctrine per pair, against about 60 earned | About 11 of 16 can be bought |

### 6.3 Towers before and after

| Tower | Level | Before (1.4.0) | After |
|---|---|---|---|
| Splash | 3–5 | no falloff; pierce 3 / 5 / 9 | edge of the blast 60 %; pierce 3 / 4 / 6 |
| Splash | 6 *Nova Artillery* | — | 900 gold, 230 damage, blast 100, slow 30 %, burning ground 3 s |
| Sniper | 3 | 40 damage | 44 |
| Sniper | 4 / 5 | 68 / 115 damage at 1.2 per second | 106 / 178 damage at 0.9 per second |
| Sniper | 6 *Quantum Rifle* | — | 850 gold, 220 damage, range 400, Execute +50 % under 30 % health, 25 % critical ×2 on Exposed |
| Heavy | 1 / 2 | 90 / 100 gold | 80 / 90 gold |
| Heavy | 3 | 190 damage, ground only | 205 damage, hits air |
| Heavy | 4 / 5 | 320 / 560 damage | 378 / 660 |
| Heavy | 6 *Siege Platform* | — | 1,000 gold, 820 damage, Expose 30 %, Stagger 40 % for 1 s, Interrupt 1.5 s |
| Rapid Fire | 1 / 2 | 4.5 / 6.5 damage | 5.0 / 7.2 |
| Rapid Fire | 3 / 4 / 5 | 11 / 16 / 22 damage | 12.5 / 19.5 / 27; chain lightning from level 4 |
| Rapid Fire | 6 *Tesla Gatling* | — | 900 gold, 31 damage at 13 per second, shred cap 16, chain every 4th shot to 3 enemies |

### 6.4 Results against the targets (Grassland, Normal)

| Measure | Before | Target | Now | Met? |
|---|---|---|---|---|
| Splash share of damage | 56 % | 35–40 % | 45 % | Partly |
| Rapid Fire share incl. enabled | 11 % | 18 % or more | 19 % | Yes |
| Expert wins | 5/5, 114 HP left | wins, loses 15–35 HP | 5/5, 103 of 120 HP left on average | Yes |
| Unspent gold at stage 30 (seed 3) | 3,417 | under 600 | about 790 | Close |
| Towers at level 6 at stage 30 | — | 5–7 | 2 | **No** |
| Technologies owned at the end | 12 of 12 | about three quarters | 11 of 16 | Yes |
| Two-tower line-ups that win | 0 of 5 | 3 of 5 | Heavy + Splash 5/5; Sniper + Splash 3/5; Rapid Fire + Splash 2/5; the other two lose at stage 17–18 | **No** |
| Single-tower line-ups | lose | lose | lose on Normal and Hard | Yes |
| Hard, expert | wins | wins | 5/5, 71 HP left | Yes |

Desert, Normal: expert 5/5; Heavy + Splash 5/5; the other pairs lose at stage 17–20.
Lakeside, Normal: expert 5/5; Sniper + Splash, Heavy + Splash and Rapid Fire + Splash all 5/5; the
two pairs without Splash lose at stage 17–18. **"Only Rapid Fire" wins Lakeside on Normal (5/5)**,
which breaks the rule that a single tower type should not win.

### 6.5 Known gaps handed to Phases 3 and 5

1. **Level 6 arrives too late to be a decision.** The simulated expert fills every pad to level 5
   first and can afford only two level-6 upgrades by stage 30. Either level 6 gets cheaper, or the
   late income rises; to be settled together with the stage 21–30 rewrite.
2. **Line-ups without Splash hit a wall at stage 17–18**, where enemy counts jump by half. The
   stage 16–30 rewrite (mixtures instead of bigger copies) is the planned fix.
3. **Splash is still the largest damage dealer** (45 %).
4. **Rapid Fire alone is too strong on Lakeside** (wins Normal) since chain lightning starts at level 4; to be reined in.
   On Easy, "only Sniper" and "only Rapid Fire" win on every map; whether that was already true before was not measured.
5. **Level-6 towers look like level 5 with a ring.** A model of their own is still to do.
6. **The tech panel is taller** and now covers the top bar while it is open.
7. *Field Engineers* (faster recovery, cheaper restart) has no effect until Phase 3 builds the recovery mechanic.

## 7. Phase 3 results

### 7.1 Boss tower disable and recovery

| Rule | Built | Where |
|---|---|---|
| A disabled tower stops attacking and keeps its place, level, targeting and statistics | Yes; it is the same object throughout and can still be upgraded or sold | `Tower.disabledUntil`, `TowerDisableTests` |
| Wait: recovers by itself for free | Yes, with a `towerRecovered(paid: 0)` event | `GameWorld+Combat.swift` |
| Pay: select the tower, see the price, one click restarts it | **Restart now** button in the tower panel (or **R**); the panel shows the price and the seconds left | `GameWorld.recover`, `TowerPanel.swift` |
| Price | 8 % of the gold spent on the tower, between 15 and 120 (half with Field Engineers) | `game.json` → `towerDisable` |
| No double charge | A second click returns `notDisabled` and takes nothing | test `payingRestartsAtOnceAndOnlyOnce` |
| Countdown on the tower | Seconds in a ring above the tower, fading as it runs down; the tower is tinted and sparks | `EntityRenderers.swift` |
| Limit at once | A quarter of the player's towers, at least 1, counting those already out | `maxShare` |
| Not the same tower again | A tower that is out is never picked; one that recovered is protected for 8 s | `protection` |
| Pause | The timer is simulation time, so it stands still while paused | test `countdownStandsStillWhileTheGameIsPaused` |
| Never destroys | Bosses only set the disable timer; a whole dragon fight leaves every tower as it was | test `bossesNeverDamageOrRemoveTowers` |

Boss timings (were 2.5–3.5 s every 5–10 s on up to 4 towers):

| Boss | Ability | Lasts | Every | Towers |
|---|---|---|---|---|
| Ancient Dragon | Fire Breath / Inferno Breath (enraged) | 5 s | 12 s / 10 s | 2 / 3 |
| Titan War Machine | EMP Blast (second phase) | 5 s | 12 s | 3 |
| Desert boss | Sandstorm / Raging Sandstorm | 4.5 s | 12 s / 10 s | 3 |
| Lakeside boss | Ink Cloud / Black Tide | 5.5 s | 12 s / 10 s | 2 / 3 |

Heavy level 6 pushes the next use back by 1.5 s (Interrupt). The simulated players **never pay** for
recovery, so every result below is with free recovery only.

### 7.2 Enemy traits and stages 16–30

* **Three traits** (`"trait"` on a wave group; never on bosses; stages 21–30 only): *Insulated*
  (cannot be slowed or frozen), *Plated* (Armour Shred at half strength), *Phasing* (takes no damage
  for 1.2 s every 5 s). They use the existing creatures with a coloured ground ring and health-bar
  frame (ice blue, steel, violet); a phasing enemy turns see-through while out of reach. The stage
  preview names the trait.
* **Stages 21–29 rewritten** so each mixes at least three of: flyers, armour, swarms, cloaked
  enemies, a trait, elites (checked by a test). Stages 25 and 30 keep their bosses with a trait on the escort.
* **The jump at stage 17 is smaller**: enemy count ×1.5 → ×1.35.
* **Level 6 is cheaper** (650–780 gold instead of 850–1,000) and Rapid Fire's early chain lightning is weaker.

### 7.3 Results (Normal, 5 seeds, free recovery only)

| Line-up | Grassland | Desert | Lakeside |
|---|---|---|---|
| Mixed expert | 5/5 | 5/5 | 5/5 |
| Heavy + Splash | 5/5 | 0/5 (stage 23) | 5/5 |
| Rapid Fire + Splash | 5/5 | 5/5 | 5/5 |
| Sniper + Splash | 4/5 | 0/5 (stage 20) | 5/5 |
| Heavy + Sniper | 0/5 (stage 17) | 0/5 (stage 17) | 0/5 (stage 17) |
| Rapid Fire + Heavy | 0/5 (stage 18) | 0/5 (stage 18) | 0/5 (stage 18) |
| Any single tower type | loses | loses | loses |

Hard: the expert wins 5/5 on all three maps. Splash share of damage on Grassland: 43 %.
Unspent gold at stage 30 (Grassland, seed 3): under 500; three towers reach level 6.

### 7.4 Still open for Phase 5

1. **Line-ups with no Splash still lose at stage 17–18** on every map. They have no answer to crowds.
2. **Desert is harsher on pairs** than the other maps: only Rapid Fire + Splash wins there.
3. **Level 6**: three towers by stage 30, against a target of five to seven.
4. **Splash share** 43 % against a target of 35–40 %.
5. On Easy every single-tower line-up except Splash wins.
6. The simulated players never pay for recovery, so how much paying helps is not measured.
7. Trait rings and the phasing flicker have not been seen in a screenshot; the countdown and Restart button have.

## 8. Phases 4 and 5: final state

### 8.1 Phase 4: campaign result

* The victory screen is now a **campaign result**: "Campaign complete", the stars, **base health lost**
  and **enemies that got through**, and the thresholds for 2 and 3 stars. Stage tiles and the stage
  summary still show no stars. A lost match has no rating.
* **Star thresholds changed** to 20 % (3 stars) and 50 % (2 stars) of the base's maximum health
  (were 10 % and 40 %). The last bosses' missile strikes cannot be avoided: a full top-level defence
  loses about 15 health, so 10 % made 3 stars almost unreachable.
* **Old saves**: a 1.4.0 checkpoint (towers at level 5, technologies by their old names, no
  damage count) loads and plays on; level-5 towers can now be upgraded once more. A 1.4.0 profile keeps
  its stars, stage progress and chosen hero. Both are covered by tests.

### 8.2 Phase 5: changes made while validating

| Change | Why |
|---|---|
| **Sniper piercing shots** from level 4 (1, 2, then 3 more enemies in a straight line behind the target, at 50–60 %) | Gives Sniper a way to hurt a rush on a straight road without making it an area tower |
| **Heavy sees cloaked enemies from level 4** (was 5) | A line-up without Splash or Sniper had nothing that could shoot cloaked robots at stage 17–18 |
| Flyers removed from stages 24 and 27 and thinned in 21, 22, 23, 26 | Every late stage had flyers, which shut out Heavy + Splash on Desert |
| Titan War Machine health 30,000 → 28,000 | Line-ups without Heavy ran out of time on Desert |
| Stage 17–20 enemy count ×1.35 → ×1.42 | With ×1.35 the middle game no longer pressed harder than the opening |
| Hard: enemy health ×1.03 | Hard had stopped being harder than Normal for the expert |
| Rapid Fire chain lightning at levels 4–5 kept weak (every 8th / 6th shot) | With the stronger version "only Rapid Fire" won Desert and Lakeside on Normal |
| A simulated player that pays for every recovery | To measure whether paying is required (it is not) |
| `Scripts/build.sh` rebuilds once when only data files changed | Xcode copied new data into the app without re-signing it |

### 8.3 Final results (Normal, 5 seeds per map, free recovery unless stated)

| Line-up | Grassland | Desert | Lakeside |
|---|---|---|---|
| Mixed expert | 5/5 | 5/5 | 5/5 |
| Mixed expert, pays for every recovery | 5/5 | 5/5 | 5/5 |
| Sniper + Splash | 5/5 | 0/5 (stage 20) | 5/5 |
| Heavy + Splash | 5/5 | 1/5 (stage 29) | 5/5 |
| Rapid Fire + Splash | 5/5 | 5/5 | 5/5 |
| Heavy + Sniper | 0/5 (stage 18) | 0/5 (stage 17) | 0/5 (stage 18) |
| Rapid Fire + Heavy | 0/5 (stage 18) | 0/5 (stage 18) | 0/5 (stage 18) |
| Any single tower type | loses | loses | loses |

| Measure (Grassland, Normal) | Before (1.4.0) | Target | Final | Met? |
|---|---|---|---|---|
| Two-tower line-ups that win | 0 of 5 | 3 of 5 | 3 of 5 | Yes (Desert: 1 of 5) |
| Splash share of damage | 56 % | 35–40 % | 41 % | Nearly |
| Sniper / Heavy / Rapid Fire share (with enabled) | 17 / 21 / 11 % | more even | 24 / 20 / 20 % | Yes |
| Expert's base health lost in a match | 6 | 15–35 | 12–24 depending on seed | Yes |
| Unspent gold at stage 30 | 3,417 | under 600 | about 600 | Yes |
| Towers at level 6 at the end | — | 5–7 | 3–5 | Nearly |
| Technologies owned at the end | 12 of 12 | about three quarters | 11–12 of 16 | Yes |
| Winning without selling or swapping towers | yes | yes | yes (simulated players never sell) | Yes |
| Winning without paying for recovery | — | yes | yes | Yes |
| Hard, mixed expert | wins | wins | wins (3 seeds with random events; 5 seeds measured just before the last small Hard change) | Yes |

Paying for recovery made little difference to the expert's result (within a few health either way),
so it is a convenience, not a requirement.

### 8.4 What is still not right

1. **A line-up with neither Splash nor both of the other crowd tools loses at stage 17–18** on every
   map (Heavy + Sniper, Rapid Fire + Heavy). Piercing shots, earlier cloak detection and thinner rushes
   did not change that. As built, the honest rule is: *a defence needs Splash, or it will be overrun
   when enemy numbers jump at stage 17*. Fixing it properly means giving Heavy or Rapid Fire a real
   crowd tool early, which would blur their roles; that is a design decision, not a tuning one.
2. **Desert is much harsher on pairs** than the other two maps (only Rapid Fire + Splash wins there).
3. **On Easy, single-tower line-ups win** (all but Splash).
4. **Level 6 has no model of its own**: it is the level-5 tower with a golden ring.
5. **Not seen in a screenshot**: trait rings on enemies, the phasing flicker, chain lightning, burning
   ground, piercing shots, freeze. Seen: the tech panel with doctrines, level-6 rings, the countdown
   and Restart button, the stage preview naming traits, the campaign result screen.
6. **The tech panel covers the top bar** while open.
7. The level-4 upgrade fork from the earlier proposal is still not built; doctrines took its place.
