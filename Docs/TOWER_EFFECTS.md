# Tower effects: Armour Shred and Expose

Implemented 10 November 2026 from [TOWER_BALANCE_PROPOSAL.md](TOWER_BALANCE_PROPOSAL.md) (step 1).
The level-4 upgrade choice (step 2 of the proposal) is **not** built.

## What changed

| Tower | Change | Where |
|---|---|---|
| Rapid Fire | **Armour Shred** at levels 3–5: each hit strips 1 armour for 3 s, cap 6 / 10 / 14 | `towers.json` → `special.shred`, `shredCap`, `shredDuration` |
| Rapid Fire | Armour penetration 0 → 1 / 2 at levels 1–2; damage 9 / 13 / 18 → 11 / 16 / 22 and range 170 / 180 / 190 → 180 / 195 / 205 at levels 3–5 | `towers.json` |
| Heavy | **Expose** at levels 3–5: target takes +15 / 20 / 25 % damage from everything for 4 s | `special.expose`, `exposeDuration` |
| Heavy | Cost of level 4: 320 → 290, level 5: 560 → 500 (maxed 1230 → 1140) | `towers.json` |
| Sniper, Splash | Unchanged | |

### Difference from the proposal

The proposal planned no stat change for Rapid Fire, with a small penetration bump as the fallback. After
Armour Shred alone, measurements showed Rapid Fire still at 8 % of damage: at high levels its limit is
short range and low damage per gold, not only armour, and at levels 1–2 (before it can shred) its 4.5-damage
shots barely scratch a 3-armour bear. So the fallback became a modest stat bump (listed above) rather than
penetration at high levels.

## Rules

| Rule | Armour Shred | Expose |
|---|---|---|
| Applied by | Rapid Fire level 3+ | Heavy level 3+ |
| Strength | −1 armour per hit, cap 6 / 10 / 14 | +15 / 20 / 25 % damage taken |
| Duration | 3 s after the last hit | 4 s after the last hit |
| Stacking | One counter per enemy shared by all Rapid towers; the cap is the highest that has hit it | Never stacks; the strongest wins, hits refresh it |
| Bosses | Half the cap | Full strength, half the duration |
| Limits | Never below 0 armour | Never above +25 % |
| Burning | Unaffected (burn ignores defences) | Unaffected |
| Together | Shred is flat, Expose is one percentage: `(damage − reduced armour) × (1 + expose)` | |

Code: `HitEffects` (`Config/TowerData.swift`), `applyStatus` and `applyDamage` (`Simulation/GameWorld+Combat.swift`),
expiry in `GameWorld+Abilities.swift`. Both effects flow through the same `HitEffects` as slow, burn and stun,
so technologies could grant them later without new code.

## In the game

* Exposed enemies stand on a pulsing **red target ring**; shredded enemies show a **purple diamond**
  beside their health bar that grows with the armour stripped.
* The upgrade panel lists "Shreds armour (up to −N)" and "Exposes +N % damage".
* A selected tower shows **Enabled**: the extra damage the team dealt because of its effect
  (`Tower.assistDamage`), next to its own damage and kills.

## Measured results

`edtool tower-report normal` (Grassland, expert player, 4 maxed towers of each type):

| Tower | Share of gold | Share of damage | Enabled for others | Damage per gold (own + enabled) | Before |
|---|---|---|---|---|---|
| Splash | 25 % | 56 % | 0 % | 353 | 360 |
| Sniper | 22 % | 17 % | 0 % | 122 | 123 |
| Heavy | 29 % | 17 % | 4 % | 115 | 93 |
| Rapid Fire | 25 % | 10 % | 1 % | 74 | 48 |

Rapid Fire's value per gold is up about 55 % and Heavy's about 25 %. Splash is still the biggest damage
dealer in a mixed defence; it was deliberately not changed.

`edtool balance-summary summons` (Grassland, 5 seeds; furthest stage, wins):

| Player | Normal before | Normal after | Hard before | Hard after |
|---|---|---|---|---|
| Expert (8 mixed, tech) | 5/5, 113 HP | 5/5, 114 HP | 5/5, 105 HP | 5/5, 114 HP |
| Spread (12 mixed, tech) | 0/5, stage 18 | **5/5, 71 HP** | 0/5, stage 17 | 0/5, stage 18 |
| Focused, no tech | stage 17 | stage 18 | stage 16 | stage 17 |
| Casual, no tech | stage 17 | stage 17 | stage 15 | stage 17 |
| Only Rapid | stage 10 | stage 18 | stage 11 | stage 18 |
| Only Heavy | stage 10 | stage 10 | stage 10 | stage 10 |
| Only Sniper | stage 17 | stage 17 | stage 17 | stage 17 |
| Only Splash | stage 10 | stage 10 | stage 9 | stage 9 |

* No single tower type wins Normal or Hard. Only Rapid now gets as far as only Sniper.
* A full mixed line-up with research (the "spread" player) now wins Normal; before, only the tightly
  optimised expert did. Players without research still fall around stage 17.
* The simulated players never sell or move towers.
* Only Heavy and only Splash still stop at stage 10: neither can hit flyers early, which is unchanged.

### Sandbox (`edtool tower-sandbox`)

Share of a group's health destroyed by four towers of one type, or two and two for a pair; no tech.

```
Level 1 towers vs Primitive enemies
  line-up           weak pack    fast         armoured     high health  elites       boss         mixed        
  splash             96          100           83           85           68           17          100          
  sniper            100          100           74           86           68           62          100          
  heavy             100          100           92          100           89           68          100          
  rapid             100          100           24           27           16            5           79          

Level 3 towers vs Medieval/Industrial enemies
  line-up           weak pack    fast         armoured     high health  elites       boss         mixed        
  splash            100          100           66           60           81            0           79          
  sniper            100          100           64           78          100           20          100          
  heavy             100          100           70            4          100           21          100          
  rapid             100          100           21           22           38            0           87          
  rapid+sniper      100          100           46           50           76            9          100          
  heavy+sniper      100          100           72           36          100           24          100          
  rapid+heavy       100          100           41            6           81            5          100          
  splash+rapid      100          100           42           27           60            0           72          
  splash+sniper     100          100           65           70           93           10          100          

Level 5 towers vs Futuristic enemies
  line-up           weak pack    fast         armoured     high health  elites       boss         mixed        
  splash            100          100          100          100          100           33          100          
  sniper            100          100           86          100           70           79          100          
  heavy             100          100          100          100           58           98          100          
  rapid             100          100           63          100           73           41          100          
  rapid+sniper      100          100           84          100           80           68          100          
  heavy+sniper      100          100          100          100           93          100          100          
  rapid+heavy       100          100           89          100           76           68          100          
  splash+rapid      100          100          100          100          100           35          100          
  splash+sniper     100          100          100          100          100           62          100
```

Reading it:

* **Pairs beat the average of their parts where an effect applies.** Level 5 against elites: Heavy 58,
  Sniper 70, Heavy + Sniper **93**. Against armour: Rapid 63, Sniper 86, Rapid + Sniper 84 with half the snipers.
* **No pair is required.** Every scenario at level 5 is fully cleared by at least one single type, except the boss.
* Rapid Fire at level 1 is still the weakest against armour (24) by design: it is the cheap anti-swarm
  tower early and becomes the shredder at level 3.
* Level 3 Heavy against high-health Trolls (4) is a known gap: Trolls heal each other faster than four
  slow Heavies can hurt them. Fire Technology (burn stops healing) is the intended answer and is not part
  of this sandbox.

## Tests

`TowerEffectTests`: which levels have which effect; shred stacks per hit to its cap and wears off; several
towers share one counter and the highest cap wins; armour never goes below 0; bosses lose half; Expose is a
fixed share that never stacks; its duration and the halved boss duration; burn ignores both; shred and
Expose combine once each; a real Rapid tower shreds in a fight, is announced once, and is credited for
enabled damage. The full-match tests (an optimised defence wins all 30 stages) still pass.

## Other battlefields

`edtool balance-summary summons map=<id>`: the expert wins 5/5 on Easy, Normal and Hard on Desert (88 base
HP left on Hard) and Lakeside (108). The mixed 12-tower player wins Normal on both. Players without
research fall around stage 17–18 on Normal.

## Still open

* Step 2 of the proposal (a real choice at level 4) is undecided.
* Splash still deals more than half of all damage in a mixed defence.
