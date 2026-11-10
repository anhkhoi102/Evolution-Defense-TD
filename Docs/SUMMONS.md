# Evolution Defense: Summon Abilities (Militia & Hero)

> The hero slot now has three heroes to choose from (Knight Commander, Iron King, Star Queen): see [HEROES.md](HEROES.md).

Two temporary tactical abilities: **Call Militia** (a squad of minions) and
**Summon Hero** (one powerful Knight Commander). Both use the existing
simulation, combat, targeting, art pipeline and UI.

## 1. Architecture assessment

| System | What exists | How summons use it |
|---|---|---|
| Update loop | `GameWorld.step(dt)`: fixed 60 Hz step, events drained by `GameScene` | One more pass, `updateSummons(dt)`, after the towers act |
| Combat | `applyDamage(to:raw:penetration:type:source:)`: resistances, armor, shields, kill gold, boss rewards, splits, phases | Every summon hit goes through it. No second damage model |
| Targeting | `TargetingSystem.isValid` (range, flying, stealth) | Reused. Summons add their own priority: nearest threat (militia), or bosses then elites (hero) |
| Enemies | Walk the path, damage the base on arrival, never attack | Unchanged. Summons take **contact damage** from enemies touching them, derived from each enemy's `baseDamage`; computed by the summon system. Enemies are not blocked or slowed |
| Map | Path polyline, build pads, world ↔ screen projection, unprojected mouse input | Deployment must be on or beside the road (distance to the path centreline), inside the playfield |
| Rendering | Pooled renderers per entity type, directional atlas sprites, status shader, effects renderer | A pooled `SummonRenderer` with the same pattern, plus new spawn, hit, special and expiry effects |
| Art | Blender bake → atlases → generated manifest | New `bake_summons.py` using the animated Kenney Mini Characters |
| Abilities | None existed | New: cooldown and duration state per ability inside `GameWorld` |

## 2. Design

* **Data** (`summons.json`): every number lives here. Each ability has a kind
  (`minion` / `hero`), unlock wave, cooldown, duration, unit count, deployment
  spread, and unit stats: HP, damage, rate, range, aggro range, speed, armor
  penetration, damage type and air targeting. Heroes add an archetype and an
  optional special attack. Global settings: contact damage and deploy distance.
* **Core** (`EvolutionDefenseCore`, no SpriteKit):
  * `SummonUnit`: an allied entity with HP, position, home, expiry, target,
    attack timer and animation state.
  * `GameWorld+Summons.swift`: `summon(_:at:)`, validation, cooldowns,
    behaviour, contact damage, expiry and cleanup, events.
  * Future archetypes (Mage, Ranger, Paladin) are new data plus, at most, a
    new `special` case. The loop doesn't change.
* **App:**
  * `SummonRenderer`: pooled sprites, directional walk, attack and death clips,
    an ally ring and health bar.
  * New effects: summon flash, hits, the hero's special, and a fade when time
    runs out.
  * Ability buttons in the bottom panel (keys **Q** / **E**) and a deployment
    preview in the scene.

### Rules

| Topic | Rule |
|---|---|
| When | Only during a wave (no enemies to fight otherwise). Unlocks: Militia from wave 3, Hero from wave 5 (the first boss) |
| Where | Click a point on or beside the road (within 70 points of the path centre). Units appear in formation there. The preview turns red elsewhere |
| Cooldown | Starts on activation; independent per ability. Both cooldown and duration use simulation time (pause and 2× speed apply) |
| Duration | Units vanish at expiry. If all die early, the ability is still on cooldown. No re-activation while on cooldown |
| Combat | Units walk to the best target within their aggro range, attack within their range, and return to their post when nothing is near. They never hurt allies or towers and don't change tower targeting |
| Defeat | Enemies touching a unit deal `baseDamage × 6` per second (capped at 120/s each), so bosses hit hard |
| Statuses | Summons aren't affected by enemy statuses (enemies have no attacks that apply them). Flying enemies are out of reach of melee units. Cloaked enemies need detection, as for towers |
| Cleanup | All summons are removed when the match ends; a new match is a new world. Summons and cooldowns aren't saved in checkpoints: Continue starts with both abilities ready |

## 3. Configuration (`summons.json`)

| | Call Militia (minion) | Summon Hero (warrior) |
|---|---|---|
| Unlock | wave 3 | wave 5 (the first boss) |
| Units | 4, in a ring of 26 points | 1 |
| Duration / cooldown | **9 s / 40 s** | **16 s / 60 s** |
| HP | 150 each | 1,800 |
| Damage / rate | 22 × 1.0/s each (88/s for the squad) | 150 × 0.8/s (120/s) |
| Special | — | **Whirlwind Cleave**: 220 to every ground enemy within 85 points every 4 s while fighting |
| Range / aggro / leash | 26 / 130 / 150 | 30 / 230 / 280 |
| Speed / armor penetration | 95 / 2 | 115 / 8 |
| Targets | nearest threat; ground only | bosses, then elites, then nearest; ground only |
| Hotkey | Q | E |

Global: contact damage `baseDamage × 6` per second per touching enemy (max
120/s), and deployment within 70 points of the road's centre line.

For scale, a level-5 Heavy tower deals about 280/s to one target forever. The
Militia squad deals 88/s for 9 s out of every 40, and the Hero about 175/s
(with the cleave) for 16 s out of every 60.

## 4. Files

**New:**

| File | What |
|---|---|
| `Packages/…/Config/SummonData.swift` | Summon data model (abilities, unit stats, specials, archetypes) |
| `Packages/…/Resources/Config/summons.json` | All summon balance |
| `Packages/…/Simulation/GameWorld+Summons.swift` | Activation, validation, cooldowns, behaviour, contact damage, cleanup, events |
| `Packages/…/Tests/…/SummonTests.swift` | 18 tests (see § 7) |
| `EvolutionDefense/Rendering/SummonRenderer.swift` | Pooled unit sprites, ally rings, health bars, hurt flash, end-of-life blink |
| `Tools/bake/blender/bake_summons.py` | Bakes the Militia and the Knight from the animated Kenney Mini Characters |
| `Scripts/summon-test.sh` | In-game check (see § 7) |

**Modified:**

| File | Change |
|---|---|
| `Packages/…/Simulation/Entities.swift` | `SummonUnit` |
| `Packages/…/Simulation/GameWorld.swift` | Summon state, 6 events, `updateSummons` in the step, cleanup at match end |
| `Packages/…/Config/GameConfiguration.swift` | Loads and validates `summons.json` |
| `Packages/…/Math/PathGeometry.swift` | `closestPoint(to:)` for deployment checks |
| `Packages/…/Balance/BalancePlayer.swift`, `edtool` | Scripted players can use summons; `balance-summary summons` |
| `Packages/…/EvolutionDefenseAssets` | `AssetID.summon`; summons are required sprites |
| `EvolutionDefense/Game/GameController.swift` | Deployment mode, Q / E, "ready" and "new ability" notices, button state |
| `EvolutionDefense/Game/GameScene.swift` | Renderer, deployment preview, click to deploy, event effects and sounds |
| `EvolutionDefense/Rendering/EffectsRenderer.swift` | Arrival, hit, cleave and vanish effects; effects keep the art's anchor |
| `EvolutionDefense/UI/TowerPanel.swift` | Two ability buttons |
| `EvolutionDefense/AssetSystem/ArtLibrary.swift` | Summon sprites and button portraits |
| `Tools/bake/package.py`, `Scripts/generate-placeholder-manifest.py` | Summons atlas; fallback entries |

## 5. UI and feedback

* **Buttons** sit next to Tech: **Militia (Q)** and **Hero (E)**. Each shows:
  * the unit's portrait;
  * a radial cooldown wedge with the seconds left;
  * "Ready" with a pulsing green border when available, "N s left" while units
    are out, "Recharging", or "Wave N" with a padlock before unlock.
  * The tooltip has the full description.
* **Deployment:** click the button or press the key, then hover. The engagement
  area shows as an ellipse on the ground, with ghost units in formation: blue
  (Militia) or gold (Hero) where allowed, red where not. Click to place;
  right-click or Esc cancels. A refused spot keeps the ability ready.
* **On the field:**
  * a blue ring under each militia and a gold ring under the hero;
  * blue / gold health bars;
  * a red flash when enemies hit a unit, and a blink in its last 2 s.
* **Effects and sounds:**
  * Arrival: a burst of light, puffs and sparks, with screen shake for the hero.
  * Hits: sparks on each blow.
  * Cleave: a golden shockwave with embers.
  * Death: the death animation, which then dissolves.
  * Time running out: the unit fades upward in a shimmer.
  * Sounds reuse the existing set (build, good event, hit, explosion, death,
    research chime for "ready").
* **Notices:** "New ability: Call Militia (Q)" when unlocked, then "… is ready"
  each time the cooldown ends.

## 6. Assets

Both units are rendered from the CC0 Kenney Mini Characters (already in the
licence inventory) with `blender/bake_summons.py`: 8 directions × idle (6),
walk (8), attack (6) and death (6) frames. The weapon and shield are parented
to the arm bones so they follow every animation. The knight is tinted gold.
They are packed into `Assets.xcassets/Baked/Summons.spriteatlas` and the
generated manifest. The code-drawn fallback pack uses its robot drawings for
summons, since it has no people.

No other assets are needed. Future heroes (Mage, Ranger, Paladin) need a bake
entry each, and a projectile or effect for ranged and area specials.

## 7. Testing

| Scenario | How | Result |
|---|---|---|
| Militia in a normal wave | `SummonTests`: squad in formation, attacks the nearest threat | ✅ |
| Hero in a difficult wave | Hero picks a boss over elites, and an elite over normal enemies; Dragon wave in `summon-test.sh` | ✅ |
| Both in the same wave | Both deployed together; in-game scenario | ✅ |
| Independent cooldowns | Each refuses re-activation; the other is unaffected; exactly one "ready" event per cooldown | ✅ |
| Duration expiry | Expires on the right frame; no attacks after expiry; status clears | ✅ |
| Units can be defeated | Trolls trampling the squad kill some; the cooldown keeps running | ✅ |
| Attacks use the combat system | Each blow equals `DamageModel` for that armor; kills pay gold like tower kills | ✅ |
| Bosses can be targeted | Hero prefers bosses; flying bosses and cloaked enemies need range or detection, as for towers | ✅ |
| Invalid deployment rejected | Off-map, far from the road, before unlock, between waves: refused, nothing spent | ✅ |
| Cleanup on match end / restart | Everything removed with events at defeat or victory; a new match is a new world; sprite count back to 0 after expiry (in-game) | ✅ |
| Stress | 300 enemies, 16 maxed towers, both summons: 0.45 ms per simulation step (debug); in game **60 fps**, 0 frames over 20 ms | ✅ |
| Summons can't win alone | No towers, both used whenever ready: 12/36 kills on wave 4, 11/46 on wave 9, 0/82 on wave 14 | ✅ |
| No node leaks, no mis-sized sprites | `summon-test.sh`, `death-test.sh` | ✅ |

The Xcode suite has 145 tests and all pass.

## 8. Balance impact

Five seeds per strategy; scripted players with summons use the militia on
crowds and the hero on bosses and elites:

| Strategy (Normal) | Without summons | With summons |
|---|---|---|
| Expert (8 mixed, tech) | wins, 107 HP | wins, 113 HP |
| Spread (12 mixed, tech) | falls ~wave 16.6 | ~17.8 |
| Focused, no tech | ~14.8 | ~16.8 |
| Casual | ~13.8 | ~17.0 |
| Single tower types, L1 spam | waves 8–9 (snipers 17) | waves 9–10 (snipers 17) |
| Hard, expert | wins, 86 HP | wins, 105 HP |

* The opening is unchanged: nothing unlocks before wave 3, and no reasonable
  strategy lost HP there anyway.
* Nobody who lost Normal before wins it now. Average players get about 2–3
  waves further (into phase 5), and the endgame still decides the match.
* Single-type defences still fail. Summons don't rescue a bad tower plan.

**Remaining concerns:**
* Summons help average players a lot (+2–3 waves). If playtests show Normal
  becoming too forgiving, raise the cooldowns first (Hero to 70 s, Militia to
  45 s), or move the Hero's unlock to wave 6.
* The bots deploy perfectly (just ahead of the boss, every time). Humans will
  get less out of the Hero, which partly offsets the point above.
* Contact damage scales with `baseDamage`. If a future enemy's base damage
  needs to be large for the base, it will also shred summons; the per-enemy
  cap (120/s) limits this.
* Checkpoints don't store cooldowns: Continue gives you both abilities ready.
