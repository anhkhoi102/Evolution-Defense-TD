# Difficulty and combat balance: audit and proposal (Phases 1–2)

> **Status:** the proposal was approved and is **implemented and validated**: see
> [section 5](#5-implementation-and-results). Sections 1–4 are the original audit and proposal;
> where they disagree with section 5, section 5 is what is in the game.

All measurements: version 1.5.0, Grassland, heroes and militia on, seed 3 unless a count of five is
given. Commands: `edtool balance <normal|hard> summons 3 [profile=N]`, `edtool tower-report`,
`edtool tower-sandbox`. "Expert" is the simulated mixed player; a person who pauses, places towers
by eye and times heroes plays better than it does.

## 1. What the audit found

### 1.1 Root causes

| # | Cause | Evidence |
|---|---|---|
| 1 | **Hard is Normal with three small numbers changed.** Enemy health +3 %, gold −5 %, a 12 s countdown instead of 15 s. No difference in what attacks, how fast, or how bosses behave. | `difficulty.json`. Stage by stage the expert's enemies get exactly as far on Hard as on Normal until stage 26 |
| 2 | **Only boss stages ever hurt a good defence.** In a whole match the expert loses base health in stages 18, 20 and 30 on Normal, and nowhere else. The other 27 stages are won without a scratch. | Per-stage health lost: 12 / 6 / 6, everything else 0 |
| 3 | **The curve has dead stages.** The total health of a stage does not rise steadily: stage 16 has less than stage 15, stage 21 a third of stage 20, stage 25 less than stage 24. In those stages enemies die in the first half of the road. | Total enemy health (thousands): 15 → 55, 16 → 36; 20 → 147, 21 → 52; 24 → 137, 25 → 102. Furthest enemy: stage 11 27 %, 12 31 %, 16 43 %, 21 46 %, 25 49 % |
| 4 | **Then a cliff at stage 17.** Health per stage more than doubles from 16 to 17 (36 → 85 thousand) and again by 19 (169). Weaker play dies there while strong play is untouched. | The "no tech" and "12 towers" players lose at stage 16–17; the expert loses nothing until 18 |
| 5 | **Strong play snowballs.** A clean stage pays extra gold and a research point, an early start pays gold, so a player who is ahead gets further ahead; a player who leaks falls behind. This is why the game is "easy" for a good player and a wall for a weak one. | Expert: 9 technologies at stage 20. "No tech" player: dead at 17 |
| 6 | **Everything can be afforded.** A match pays about 17,500 gold from kills and stage rewards (plus starting gold and bonuses). Sixteen pads at level 5 cost 15,600. By stage 27 every pad is level 5, so there is never a real choice between more towers and better towers. | 79 of 80 levels at stage 27 |
| 7 | **Upgrading costs no efficiency.** Damage per gold spent is almost the same at level 5 as at level 1, and each level also adds range and effects. Pouring gold into a few towers is never a worse deal than spreading it. | Damage per 100 gold, level 1 → 5: Heavy 34 → 30, Rapid Fire 31 → 34, Sniper 26 → 19, Splash 19 → 14 (per target; it hits several) |
| 8 | **One unavoidable hit.** The Titan War Machine's Missile Strike takes 3 base health every 10 s whatever the player does. It is the main reason a perfect defence still loses 12–15 health. | `baseStrike` in `enemies.json`; a full level-6 defence lost 15 |

### 1.2 Why Sniper + Splash is still dominant

Measured: on Normal this pair wins 5 of 5 with **97 of 120 health left, better than most mixed
line-ups**; in stages 1–14 its enemies die at **20–45 % of the road**, against 60–80 % for the mixed
expert. Version 1.5.0 made this worse: the Sniper got more damage and piercing shots.

| Reason | Detail |
|---|---|
| **Range** | Sniper reaches 260 at level 1 and 400 at level 6; the others reach 140–240. A Sniper covers two to three times as much road, so its real output is far above its listed damage. It is also the **cheapest** tower (60 gold) |
| **No gap between them** | Splash: crowds, cloaked enemies caught in a blast. Sniper: flyers, cloaked enemies (level 4), armour (pierce 3–14), bosses (Execute), and since 1.5.0 lines of enemies. Between them every enemy type has an answer |
| **No bad matchup in the sandbox** | Four Snipers alone stop every level-1 test group and are the best single tower at level 3; Splash + Sniper at level 5 stops everything except a boss |
| **Nothing gets close** | Both out-range the enemies' own threats, and neither has a blind spot near the tower |
| **Boss stages** | The pair's only losses (stage 20 on Hard) are against the Titan, where Splash contributes little |

So the pair is not dominant because either tower hits too hard; it is dominant because **together
they have no weakness, and the Sniper's reach lets them start killing before anything else can**.

### 1.3 What is working and should stay

Roles of Heavy (armour, marks, bosses) and Rapid Fire (shred, flyers, chains); the doctrines; boss
tower disables with free or paid recovery; traits; the campaign-wide star rating; no single tower
type winning on Normal; nothing requiring towers to be sold.

## 2. Proposed design

### 2.1 Targets (how the result will be judged, 5 seeds per map)

| Measure | Now | Normal target | Hard target |
|---|---|---|---|
| Expert wins | 5/5 | 4–5 of 5 | 2–4 of 5 |
| Expert's base health lost | 24 | 35–60 | 60 or more when it wins |
| Stages (not boss) where the expert loses health | 1 | 4 or more | 8 or more |
| Stage where weaker simulated players die | 16–17 | 20 or later | 14–18 |
| Pads at level 5 or more at stage 30 | 16 of 16 | 10–12 | 7–9 |
| Sniper + Splash | 5/5, 97 left | wins at most 3 of 5 and never beats the mixed expert | loses |
| Heavy + Splash, Rapid Fire + Splash | 5/5 | each wins 3 of 5 or more | at least one wins sometimes |
| Any single tower type | loses | loses | loses |
| Unavoidable base damage | 12–15 per match | none | none |

### 2.2 Normal against Hard

| Aspect | Normal (proposed) | Hard (proposed) | Hard now |
|---|---|---|---|
| Enemy health | ×1.0 | ×1.12 | ×1.03 |
| Enemy speed | ×1.0 | ×1.06 | ×1.0 |
| Enemy armour | as listed | +2 from stage 11 | — |
| Elites | as written in the stages | one extra elite group in every stage from 6 | — |
| Traits (insulated, plated, phasing) | from stage 16 | from stage 11 | 21 |
| Bosses | as today | abilities 20 % more often; up to a third of the towers disabled at once (Normal: a quarter) | same as Normal |
| Gold | ×1.0 | ×0.88, starting gold 230 | ×0.95, 240 |
| Research | 2 points at the start | 1 point at the start | 2 |
| Countdown between stages | 15 s | 10 s | 12 s |
| Repairs, selling | as today | repairs 25 % dearer, selling returns 60 % (Normal 70 %) | same as Normal |

Every Hard value is a field in `difficulty.json`; none of it is health alone.

### 2.3 Sniper and Splash

| Tower | Change | Why |
|---|---|---|
| **Sniper** | **Range down by about a fifth**: 260 / 285 / 310 / 345 / 380 / 400 → 215 / 230 / 250 / 275 / 300 / 320 (still the longest) | Its reach is the root of the pair's head start |
| | **Blind spot**: cannot shoot enemies closer than 70 | A real weakness: fast enemies that slip inside are safe from it, so placement matters and it needs a partner |
| | **Slower, harder shots at levels 1–3 too**: 1.1 per second → 0.8, damage raised to keep single-target damage | Shots are wasted on small enemies; it stops clearing early crowds alone |
| | **Piercing only at levels 5–6** (not 4), 1 and 2 extra targets | Undoes the part of 1.5.0 that helped the pair most |
| | Cost 60 / 60 → 75 / 70 for levels 1–2 | It was the cheapest tower with the longest reach |
| | Unchanged: flyers, cloak detection at level 4, armour piercing, Execute, critical hits on marked targets | Its identity as the big-target specialist |
| **Splash** | **70 % damage to bosses** | Keeps it the crowd tower; a boss needs Sniper, Heavy or Rapid Fire |
| | Level 5–6 damage 200 / 230 → 180 / 205; blast edge 60 % → 50 % | Its late scaling is the steepest of the four |
| | Unchanged: no flyers, slows, burning ground, blast size | |
| **The pair's intended weaknesses** | **Flocks**: many small flyers (Splash cannot hit them, a slow Sniper wastes shots); **fast rushes** that get inside the Sniper's blind spot; **bosses**, where Splash is at 70 % | Rapid Fire answers flocks and rushes, Heavy answers bosses: the reasons to bring them |

### 2.4 Enemies and stages

* **No dead stages, no cliff.** Total stage health should rise by 15–35 % a stage instead of
  −35 % to +140 %. The difficulty phases become a ramp: a new step at stage 15, a smaller one at 17.
* **Fill stages 11–13, 16, 21, 23 and 25** with mixtures instead of raising health: add a second
  enemy kind and an elite group to each.
* **Flocks** from stage 7: existing flyers at half health in double numbers (no new art).
* **Rushes** from stage 9: existing fast enemies in tight groups that arrive while the towers are busy with a tank.
* **Traits earlier** (stage 16 on Normal).
* **Missile Strike becomes avoidable**: the Titan only fires once it is past 60 % of the road, so a
  defence that holds it back takes nothing. Boss stages stay the hardest, but no damage is forced.

### 2.5 Towers, upgrades and economy

| Setting | Now | Proposed | Why |
|---|---|---|---|
| Level 4 cost | 215–290 | +15 % | Upgrading should cost some efficiency |
| Level 5 cost | 410–500 | +25 % | Same |
| Level 6 cost | 650–780 | unchanged | Already the sink |
| Gold from a stage with no leaks | +15 | +8 | Less snowball |
| Research point for a clean stage | every stage to 20, then boss stages | every **second** stage to 20, then boss stages | Less snowball; technology stops arriving all at once |
| Early-start bonus | 1 gold per second | 0.5 | Less snowball |
| Kill and stage rewards | as today | unchanged on Normal | Income stays; costs rise |
| Total | income ≈ 115 % of "everything at level 5" | ≈ 75 % on Normal, ≈ 60 % on Hard | A real choice between more towers and better towers |

Version 1.5.0 tried dearer level 4–5 towers and dropped them because the expert then lost at
stage 17. That was the cliff, not the prices: with the cliff smoothed (2.4) the two changes go together.

### 2.6 What will not change

Tower buying and selling stay optional; no enemy or boss requires one tower type; the campaign and
save files stay compatible (new difficulty fields are optional); stars are still awarded once,
after stage 30; Easy keeps its numbers.

## 3. How it will be validated (Phase 4)

* `balance-summary` on Grassland, Desert and Lakeside, Easy / Normal / Hard, 5 seeds: wins, health lost,
  stage reached, for the mixed expert, the paying expert, the five pairs, the four single types and the weak players.
* Per-stage tables (furthest enemy, health lost, gold unspent, tower levels) for Normal and Hard side by side.
* `tower-report`: damage share and damage per gold per tower; `tower-sandbox` for each line-up against flocks and rushes (two new columns).
* Unit tests for the blind spot, boss damage share, flocks, the Hard-only fields and the avoidable Missile Strike.
* The app built, all existing tests run, and the in-game checks.

## 4. Risks

| Risk | Control |
|---|---|
| Normal becomes too hard for ordinary play | The weak simulated players must get **further** than today (stage 20 or later), not less far |
| Sniper feels bad | Single-target damage is kept; only reach, crowd clearing and price change. The blind spot is shown as an inner ring when placing or selecting it |
| Hard becomes a health sponge | Health is only +12 %; the rest is speed, elites, traits, bosses and gold |
| Too many changes at once | Order: curve and economy first, then Sniper and Splash, then Hard; measured after each |
| Simulated players are not people | Targets are set so the simulated expert struggles more than a person would; the first real match may still call for a correction |

## 5. Implementation and results

Measured on version 1.5.0 plus these changes, 5 seeds per map, heroes and militia on, simulated
players that never sell towers and (except "payer") never pay to restart one.

### 5.1 What changed

**Sniper**

| Level | Before: cost / damage / shots per s / range | After |
|---|---|---|
| 1 | 60 / 14 / 1.1 / 260 | 75 / 19 / 0.8 / 215 |
| 2 | 60 / 24 / 1.15 / 285 | 70 / 34 / 0.8 / 230 |
| 3 | 100 / 44 / 1.15 / 310 | 100 / 63 / 0.8 / 250 |
| 4 | 215 / 106 / 0.9 / 345, pierces 1 | 236 / 106 / 0.9 / 275, no piercing |
| 5 | 410 / 178 / 0.9 / 380, pierces 2 | 492 / 178 / 0.9 / 300, pierces 1 |
| 6 | 650 / 220 / 0.9 / 400, pierces 3 | 650 / 220 / 0.9 / 320, pierces 2 |

Every level has a **blind spot of 120**: nothing closer can be shot. (The proposal said 70. Pads sit
100 from the middle of the road, so 70 never reached the road and did nothing; 120 takes out the
stretch of road right beside the tower.) Selecting or placing a Sniper shows the blind spot as a red
inner ring, and the panel lists it.

**Splash**: 80 % damage to bosses at every level (proposal: 70 %; at 70 % no line-up without Heavy
could kill the stage-20 boss). Blast edge 60 % → 50 %. Level 5–6 damage 200 / 230 → 180 / 205.
Level 4–5 cost 240 / 460 → 264 / 552.

**Heavy** level 4–5 cost 290 / 500 → 319 / 600. **Rapid Fire** level 4–5 cost 250 / 460 → 275 / 552.
(+10 % and +20 %; the proposed +15 % and +25 % starved the mixed defence.)

**Enemies and stages**

* All enemy health −6 % (this is the Normal easing; Hard adds its own +6 % back).
* Difficulty phases are a ramp: a new "Late" step at stage 16, smaller steps at 17, 21 and 26.
  Stage health now rises every stage (a test fails if a stage has less than 90 % or more than 160 %
  of the stage before it).
* Flocks of small flyers in stages 9, 14, 19 and 27; fast rushes in stages 8, 11, 13, 16 and 25;
  second and third enemy kinds added to stages 11, 12, 13, 16, 21, 25 and 27; traits written into stages 11–20.
* Titan War Machine: health 28,000 → 22,600, first-phase armour 26 → 16, second phase 18 → 12, and
  reaching the base costs 45 health instead of ending the match. Its Missile Strike fires only once
  it is past 60 % of the road.
* Mutant Titan and its two map versions: health −7 %.

**Economy**: bonus for a stage with no leaks 15 → 8; early-start bonus halved; the research point
for a clean stage only every second stage (boss stages always). Late kill rewards as before.

**Normal against Hard**

| | Normal | Hard (was) |
|---|---|---|
| Enemy health | ×1.0 | ×1.06 (×1.03) |
| Enemy speed | ×1.0 | ×1.02 (×1.0) |
| Armour | as listed | +1 from stage 18 (none) |
| Extra elite group | no | every stage from 14 (none) |
| Traits from stage | 16 | 13 (21) |
| Towers a boss may disable at once | a quarter | a third (a quarter) |
| Gold | ×1.0 | ×0.99 (×0.95) |
| Countdown | 15 s | 10 s (12 s) |
| Repairs / selling | normal / 70 % back | 25 % dearer / 60 % back (same as Normal) |

Hard ended up **much milder than proposed** (health +6 % instead of +12 %, gold almost unchanged,
elites and armour later, boss abilities at normal speed). With the proposed values the simulated
expert lost base health in stage 1 and died at stage 8.

**Base health display**: the status word is gone; bar, colour and number are unchanged.

### 5.2 Results

Wins out of 5 and, in brackets, average stage reached when not all won.

| Line-up | Grassland Normal | Grassland Hard | Desert Normal | Desert Hard | Lakeside Normal | Lakeside Hard |
|---|---|---|---|---|---|---|
| Mixed expert | 5 | 0 (27) | 5 | 5 | 5 | 0 (25) |
| Mixed, 12 towers first | 4 (28) | 0 (18) | 5 | 4 (28) | 1 (22) | 0 (20) |
| Mixed, no technology | 0 (22) | 0 (18) | 0 (20) | 0 (19) | 0 (20) | 0 (19) |
| Sniper + Splash | 0 (20) | 0 (19) | 0 (20) | 0 (19) | 0 (26) | 0 (20) |
| Heavy + Splash | 5 | 1 (25) | 0 (22) | 0 (22) | 5 | 2 (29) |
| Rapid Fire + Splash | 5 | 1 (23) | 5 | 0 (22) | 5 | 2 (24) |
| Heavy + Sniper | 0 (18) | 0 (17) | 0 (18) | 0 (17) | 0 (18) | 0 (17) |
| Rapid Fire + Heavy | 0 (19) | 0 (18) | 0 (19) | 0 (18) | 0 (19) | 0 (19) |
| Any single tower type | loses | loses | loses | loses | loses | loses |

Mixed expert on Grassland, Normal against Hard (seed 3), furthest enemy and health lost:

| Stages | Normal | Hard |
|---|---|---|
| 1–10 | 59–81 %, loses 2 | 62–83 %, loses 19 |
| 11–15 | 35–86 %, loses 0 | 34–99 %, loses 20 |
| 16–20 | 72–87 %, loses 6 | 80–99 %, loses 40 |
| 21–30 | 77–99 %, loses 27 | dies in stage 22 |

Damage share in the mixed defence: Splash 39 %, Heavy 22 % (+4 % enabled), Sniper 21 %,
Rapid Fire 19 % (+2 %). In 1.5.0: 41 / 20 / 24 / 20; in 1.4.0: 56 / 21 / 17 / 11.

### 5.3 Against the targets

| Target | Result | Met? |
|---|---|---|
| Normal: expert wins 4–5 of 5 | 5 of 5 on every map | Yes |
| Normal: expert loses 35–60 health | about 35 on Grassland and Lakeside, less on Desert | Partly |
| Normal: 4 or more ordinary stages cost the expert health | 1 (stage 26); enemies get to 77–99 % of the road in every stage from 15 | **No** |
| Normal: weaker players die at stage 20 or later | no-technology player: stage 20–22 (was 16); casual player: 17–20 (was 16) | Mostly |
| Hard: expert wins 2–4 of 5 | Desert 5, Grassland 0, Lakeside 0 (reaching stage 25–27) | Uneven |
| Hard clearly harder than Normal | yes: health lost by stage 20 is 66 against 8 | Yes |
| Sniper + Splash wins at most 3 of 5 on Normal | 0 of 5 everywhere (stage 20–26) | Yes, overshot |
| Heavy + Splash and Rapid Fire + Splash each win 3 of 5 on Normal | Rapid Fire + Splash 5 on every map; Heavy + Splash 5 / 0 / 5 | Mostly |
| Single tower types lose on Normal and Hard | yes | Yes |
| No unavoidable damage | the Titan's missiles only fire past 60 % of the road, but the expert still lets it get there and loses 6 in stages 20 and 30 | Avoidable, not avoided |
| 10–12 pads at level 5 by stage 30 | about 15 of 16 | **No** |
| No tower selling required | simulated players never sell | Yes |

### 5.4 What is still not right

1. **Sniper + Splash went from always winning to never winning on Normal.** It stays healthy until
   about stage 15 and loses to bosses and the stage 17–20 mixtures. If it should win sometimes, the
   quickest lever is the Sniper's range or level 1–2 price.
2. **Hard is uneven across maps**: the expert always wins it on Desert and never on Grassland or Lakeside.
3. **Ordinary stages still rarely cost a good defence health.** Pressure is high (enemies nearly
   reach the base) but leaks are rare; only bosses and one rush stage take health.
4. **Gold still buys nearly every pad to level 5** by the last stages. The price rises that would
   prevent it starved the middle of the game.
5. **Line-ups without Splash still lose at stage 18–19** on every difficulty.
6. **Desert punishes Heavy + Splash** (flyers): it loses there on Normal.
7. **Easy is very easy**: every single-tower line-up except Splash wins.
8. All of this is measured with simulated players. A spending-freely variant was tried as a better
   stand-in for a person and did far worse than the rigid expert, so the expert remains the yardstick.
