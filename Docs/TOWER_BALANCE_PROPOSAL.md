# Tower balance proposal: unique effects instead of bigger numbers

Status: **proposal, nothing implemented.** Written 10 November 2026.

## 1. What the data says

Measured with the new `edtool tower-report` (simulated players, Grassland, Normal, 3 seeds, summons on).
The "expert" builds 4 towers of each type and maxes them, so every type gets a fair share of gold.

| Tower | Share of gold | Share of damage | Damage per gold | Kills |
|---|---|---|---|---|
| Splash | 24 % | **57 %** | 360 | 1062 |
| Sniper | 21 % | 17 % | 123 | 481 |
| Heavy | **31 %** | 19 % | 93 | 130 |
| Rapid Fire | 24 % | **8 %** | **48** | 234 |

The same pattern shows for the weaker players (spread, focused, casual): Splash 54–57 % of damage,
Rapid 7–9 %. Playing only one type: Sniper reaches stage 16, Rapid 10, Splash 9, Heavy 9.

### Why each tower ends up where it is

| Tower | Role today | Underlying problem | Needs |
|---|---|---|---|
| **Rapid Fire** | Many small hits; anti-swarm | Armour is subtracted from **every hit**. A level-5 shot does 18 damage; a Heavy Mech has 28 armour, so each shot is cut to the 15 % minimum (2.7). On paper Rapid has the best damage per gold (216 DPS for 965 gold); against armour it drops to about 32 DPS, where a Sniper keeps 126 and a Heavy 279. From the Medieval Age on, most stages contain armour, so the tower fades exactly when the game gets hard. Its swarm job is also done better by Splash. | A tactical role that does not depend on its own hit size |
| **Heavy** | Big single hits, armour penetration, boss killer | Most expensive tower (1230 gold maxed vs 845–975). Fires every 2 s at the strongest target, so against anything but bosses and brutes much of each hit is overkill. Its strength (penetration) only helps itself. Stages with a boss are 6 of 30. | A way to make its hits matter between bosses, and to help the team |
| **Sniper** | Long range, hits flyers and cloaked enemies | No real problem. The only tower that can win alone on Easy, because nothing else covers air and stealth early. Solid but not dominant in mixed play (17 % of damage for 21 % of gold). | Nothing urgent; should gain from team effects, not from more damage |
| **Splash** | Area damage, some slow | Dominant: stages 13–30 multiply enemy counts by up to 1.7, and every extra enemy in a blast is free damage. Also holds the slow (levels 4–5 and a tech) and burn (tech). It crowds out Rapid's job. | No buff. Keep an eye on it; trim only if the other changes make the game too easy |

So the two towers to fix are **Rapid Fire** (weak for its cost in every setting) and **Heavy**
(expensive, narrow). Neither is fixed well by more damage: more Rapid damage still hits the armour
wall, and more Heavy damage is more overkill.

## 2. Proposed changes

### Rapid Fire becomes the armour shredder

* **Armour Shred** (from level 3): each hit removes 1 point of the target's armour for 3 s, stacking.
  Cap: 6 / 10 / 14 points at levels 3 / 4 / 5. Hits refresh the timer.
* Everyone benefits: every tower's hit on that enemy gains the removed armour. Rapid itself gains
  the most (many hits), Sniper next, Heavy and Splash a little.
* Keeps its critical hits (levels 4–5) and its job against fast, light enemies.
* No stat buff planned. If the report still shows it under about 13 % of damage afterwards, a small
  penetration bump at levels 3–5 is the fallback.

### Heavy becomes the breaker

* **Expose** (from level 3): an enemy hit by Heavy takes **+15 / 20 / 25 %** damage from all sources
  for 4 s (levels 3 / 4 / 5). Does not stack; the strongest mark wins and hits refresh it.
* Gives its slow, single shots lasting value: the shot on a brute or elite makes the next 4 seconds
  of everyone's fire count more. On bosses this is the team's biggest lever.
* Keeps its stun (levels 4–5).
* Small cost trim at levels 4 and 5 (320 → 290, 560 → 500; maxed 1230 → 1140) so it is no longer far
  more expensive than the others.

### Sniper: unchanged stats

* Gains from both effects (shredded armour and exposed targets) without any change of its own.
* It already owns air and stealth. Making it stronger would make "only snipers" the best plan.

### Splash: unchanged

* Already has slow (levels 4–5, Advanced Traps) and burn (Fire Technology). It stays the control
  and crowd tower. No new effect, no buff.

### Summary table

| Tower | Current role | Identified problem | Recommended change | New tactical identity |
|---|---|---|---|---|
| Rapid Fire | Fast light shots | Armour wall; 8 % of damage for 24 % of gold | Armour Shred (L3+), no stat buff | Support: strips armour for the whole team |
| Heavy | Big single hits | Costly, overkill, only matters on bosses | Expose mark (L3+), cost −90 total | Breaker: makes a tough target take more from everyone |
| Sniper | Long range, air, stealth | None | None | Finisher that profits from shred and marks |
| Splash | Area damage, slow, burn | Dominant | None (watch) | Crowd control |

## 3. Synergies

| Combination | What happens | Why it is not mandatory |
|---|---|---|
| Rapid + Sniper | Shred turns Sniper's mid-size hits into near-full damage on armour | Sniper still works through its own penetration, as today |
| Rapid + Rapid | Share one shred counter per enemy; a second tower reaches the cap sooner, not higher | Cap is fixed per enemy |
| Heavy + anything | Exposed target takes more from every tower for 4 s | A single multiplier, never stacks with itself |
| Rapid + Heavy | Shred (flat) and Expose (percentage) both apply, once each | One flat and one percentage effect cannot compound further |
| Splash slow + Rapid/Heavy | Slowed enemies stay under fire longer, so stacks and marks get used | Already true today |

Today's balance was tuned with none of this, and the reference player already wins all 30 stages.
The effects add efficiency; no stage will require them.

## 4. Status effect rules

| Rule | Armour Shred | Expose |
|---|---|---|
| Applied by | Rapid Fire L3+ | Heavy L3+ |
| Strength | −1 armour per hit, cap 6 / 10 / 14 | +15 / 20 / 25 % damage taken |
| Duration | 3 s after the last hit | 4 s after the last hit |
| Stacking | One counter per enemy, shared by all Rapid towers; cap = the highest level that hit it | None; strongest wins, refreshed by hits |
| Bosses | Half the cap | Full strength, half the duration (2 s) |
| Elites | Normal | Normal |
| With other effects | Coexists with slow, burn, stun, Expose | Coexists with all; does not increase burn (burn ignores defences) |
| Can never | Push armour below 0 | Exceed +25 % |
| Feedback | Cracked-shield pip over the enemy, light metallic tick | Red target ring under the enemy, short tone on first mark |
| Cost at runtime | Two numbers per enemy, checked when it is hit | Two numbers per enemy |

No new stun or slow is added, so there is no extra crowd control to chain.

## 5. Optional second step: a choice at level 4

The upgrade system is a straight line today (the data format has a note reserving a `branches` field,
but nothing is built). A real choice would be one fork per tower at level 4, kept through level 5:

| Tower | Option A | Option B |
|---|---|---|
| Rapid Fire | **Shredder**: shred cap +4 | **Gatling**: crit chance doubled, no extra shred |
| Heavy | **Breaker**: Expose lasts 6 s | **Mortar**: shots also hit enemies within a small radius for 35 % |
| Sniper | **Marksman**: +40 % damage to enemies below 30 % health | **Spotter**: +15 % range, reveals cloaked enemies to nearby towers |
| Splash | **Frost shells**: slow 35 % | **Incendiary**: burn without needing the tech |

This needs upgrade-panel UI, save-file changes and the simulated players taught to choose, so it is
several times the work of step 1. Recommended only after step 1 has been played.

## 6. Risks and controls

| Risk | Control |
|---|---|
| The whole defence gets stronger and Normal becomes too easy | Re-run `balance-summary` and `tower-report` on all three maps; if the expert's leftover base health on Normal rises by more than about 10, raise enemy health in the "Very Hard" and "Expert" phases rather than weakening towers |
| Shred makes armour meaningless | Caps (max 14, bosses 7) against late armour of 26–28; armoured enemies stay armoured against one or two hits |
| Expose + Starfall or Splash bursts trivialise bosses | Fixed +25 % ceiling, 2 s on bosses, never stacks |
| Rapid becomes mandatory against armour | Heavy and Sniper penetration are untouched; the current all-clear without shred is the proof |
| "Only Rapid" or "only Heavy" jumps too far | Target for single-type runs: still losing on Normal, but later than today (stage 12–15 instead of 9–10) |
| Fixed line-ups lose their way to win | The simulated players never sell or move towers; every mixed line-up that wins today must still win |
| Too many icons on a crowded road | One small pip and one ring, hidden in performance mode like other minor effects |

## 7. How it will be tested (after approval)

* `tower-report` before and after: Rapid's share of damage should rise to roughly 13–18 %, Heavy's
  damage per gold should rise, Splash's share should fall without Splash being changed.
* A new sandbox report: each tower type, at levels 1, 3 and 5, alone and in pairs, against a pack of
  weak enemies, fast enemies, armoured enemies, high-health enemies, elites, a boss, and a mixed group.
* `balance-summary` on Grassland, Desert and Lakeside, all difficulties, including the single-type
  and fixed line-ups.
* Unit tests for every rule in section 4 (caps, refresh, no stacking, boss limits, armour never below 0).
* In the real game: screenshots of the new markers and a frame-rate run with many affected enemies.
