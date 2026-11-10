# Heroes: Knight Commander, Iron King and Star Queen

Phase 2 of the campaign expansion. The hero summon (key **E**) now has three heroes to choose from.
One hero is taken into each match; it is picked on the **New Game** screen.

All three (and the militia) are rendered from the CC0 **KayKit Adventurers** character pack with the
pack's own weapons, capes, hats and animations (`Tools/bake/blender/bake_summons.py` only chooses which
gear each unit shows). The Knight Commander is the pack's Knight with sword and shield; the Iron King is
the same armour in dark iron with a greatsword and a gold crown (the crown is the one piece made in the
script, because the pack has none); the Star Queen is the pack's Mage with her staff. None of them
copies another game's characters.

| | Knight Commander | Iron King | Star Queen |
|---|---|---|---|
| Unlock | From the start | Clear **stage 10** | Clear **stage 20** |
| Role | All-round fighter | Tough guard who slows enemies | Long-range magic burst |
| Fights | Melee | Melee | Ranged (250), also hits flyers |
| Health | 1800 | 3600, and ignores half of all contact damage | 800 |
| Attack | 150 × 0.8/s physical | 130 × 0.7/s physical | 240 × 1.0/s energy |
| Special | Whirlwind Cleave: 220 to everything within 85, every 4 s | Royal Slam: 170 to everything within 120 and **50 % slow for 3 s**, every 5 s | Starfall: 700 to the **3 toughest** enemies within 280, every 5 s |
| Stays | 16 s | 22 s | 14 s |
| Cooldown | 60 s | 70 s | 65 s |
| Best at | Bosses and elites in the middle of the road | Holding a choke point while towers work; packs | Flyers, shielded and heavy targets, from a safe spot |
| Weak at | Flyers | Flyers; low damage | Dies quickly if enemies walk over her |

Every number is in `Resources/Config/summons.json`. Bosses take half the King's slow, as with tower slows.

## How it works

* **Data.** Heroes are summon abilities with `"kind": "hero"`. New optional fields:
  `unlockStage` (campaign stage that unlocks the hero), `heroName`, `role`, `unit.damageReduction`,
  `unit.ranged`, and on `special`: `slow`, `slowDuration`, `maxTargets`. The loader checks that one hero
  needs no unlock.
* **One hero per match.** `MatchOptions.hero` names the hero. `GameWorld.summonAbilities` is the militia
  plus that hero; the other heroes cannot be called (`.unknownAbility`). The choice is stored in the
  match checkpoint, so Continue keeps it. Saves from before this phase get the Knight.
* **Unlocks.** `PlayerProfile.isUnlocked(hero)` compares `highestStageCleared` (on any
  battlefield) with `unlockStage`. `PlayerProfile.activeHero(in:)` returns the chosen hero, or the
  Knight if the choice is locked or unknown. The choice lives in `GameSettings.hero`.
* **Specials.** `GameWorld+Summons.swift` runs one special routine: an area hit, optionally with a slow
  (through the same `applyStatus` towers use) or limited to the toughest `maxTargets` enemies.
* **Earlier progress counts.** A profile from before stars existed unlocks heroes from its recorded highest stage.
* **No stage is re-played to unlock.** Progress is written the moment a stage is cleared, so the unlock
  happens right then, even if the match is later lost.

## Screens

* **New Game → Hero**: three cards with portrait, role, health, time on the field and special.
  Locked heroes are greyed out with "Clear stage N to unlock".
* **Unlock card**: when stage 10 or 20 is cleared for the first time, a "New hero unlocked" card shows
  between stages (the countdown waits). The end screen repeats it.
* **Campaign**: shows which heroes are unlocked and what the locked ones need.
* **In the match**: the hero button shows the chosen hero's portrait and name. The Queen's attacks are
  drawn as bolts of light, Starfall drops a star on each target, Royal Slam is a wide icy shockwave.

## Tests

`HeroTests`: roles differ as designed; a match has exactly the chosen hero; choice survives save and
Continue; unlock thresholds; locked or unknown choice falls back; the King outlasts the Knight under the
same pressure; Royal Slam damages and slows only what is in range; the Queen hits flyers from a distance
and holds her ground; Starfall picks the toughest targets; the Queen is the most fragile.
`Scripts/summon-test.sh` also plays the King and the Queen in the real game and screenshots them.
