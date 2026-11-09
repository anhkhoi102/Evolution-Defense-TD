import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

private func world(gold: Int? = nil, research: Int? = nil, seed: UInt64 = 5, _ edit: ((inout GameConfiguration) -> Void)? = nil) -> GameWorld {
    var cfg = config
    edit?(&cfg)
    let w = GameWorld(config: cfg, seed: seed)
    w.holdPreparationCountdown = true
    if let gold { w.debugSetGold(gold) }
    if let research { w.debugSetResearch(research) }
    return w
}

/// Path distance closest to a build slot (to park enemies in a tower's range).
private func pathDistance(near slotID: Int, in w: GameWorld) -> CGFloat {
    let p = w.config.map.slotPosition(w.slot(withID: slotID)!)
    var best: CGFloat = 0, bestD = CGFloat.greatestFiniteMagnitude, d: CGFloat = 0
    while d < w.path.totalLength {
        let dd = w.path.position(at: d).distance(to: p)
        if dd < bestD { bestD = dd; best = d }
        d += 4
    }
    return best
}

/// Freezes an enemy in place (speed 0) by stunning it far into the future.
private func pin(_ e: Enemy) { e.stunnedUntil = 1e9; e.speed = 0 }

private func events(_ w: GameWorld) -> [GameEvent] {
    var out: [GameEvent] = []
    w.drainEvents { out.append($0) }
    return out
}

// MARK: - Content

@Suite("Eras & content")
struct EraContentTests {
    @Test func twentyWavesFivePerEraBossesOnEveryFifth() {
        #expect(config.waves.count == 20)
        for era in Era.allCases {
            let waves = config.waves.filter { $0.era == era }
            #expect(waves.count == 5, "\(era) should have 5 waves")
        }
        let expectedBoss = [5: "alphaBeast", 10: "ancientDragon", 15: "mutantTitan", 20: "titanWarMachine"]
        for w in config.waves {
            let bosses = w.groups.filter { config.enemies[$0.enemy]!.isBoss }.map(\.enemy)
            if let b = expectedBoss[w.number] {
                #expect(w.isBossWave)
                #expect(bosses == [b], "wave \(w.number) boss")
                #expect(config.enemies[b]!.era == w.era)
            } else {
                #expect(!w.isBossWave && bosses.isEmpty, "wave \(w.number) should have no boss")
            }
        }
    }

    @Test func everyEraHasItsOwnRoster() {
        for era in Era.allCases {
            let roster = config.enemies.values.filter { $0.era == era && !$0.isBoss }
            #expect(roster.count == (era == .primitive ? 3 : 4), "\(era) regular enemies")
            // Each later wave set actually uses its own era's enemies.
            let used = Set(config.waves.filter { $0.era == era }.flatMap { $0.groups.map(\.enemy) })
            #expect(roster.allSatisfy { used.contains($0.id) }, "\(era) roster unused")
        }
    }

    @Test func laterErasIntroduceNewBehavioursNotJustHP() {
        let e = config.enemies
        #expect(e["giantWolf"]!.baseAbilities.sprint != nil)
        #expect(e["armoredBeast"]!.armor >= 8)
        #expect(e["troll"]!.resistance.physical > 0 && e["troll"]!.baseAbilities.regen != nil)
        #expect(e["flyingMonster"]!.isFlying)
        #expect(e["giantMutant"]!.baseAbilities.splitOnDeath != nil)
        #expect(e["swarmCreature"]!.speed > e["wolf"]!.speed)
        #expect(e["stealthRobot"]!.baseAbilities.stealth != nil)
        #expect(e["assaultRobot"]!.baseAbilities.shield != nil)
        #expect(e["heavyMech"]!.armor > e["armoredMonster"]!.armor)
        #expect(e["titanWarMachine"]!.sortedPhases.count >= 1)
        let p2 = e["titanWarMachine"]!.sortedPhases[0].abilities!
        #expect(p2.disableTowers != nil && p2.baseStrike != nil && p2.summon != nil)
    }

    @Test func techTreeHasThreeTechsPerEra() {
        #expect(config.techs.count == 12)
        for era in Era.allCases { #expect(config.techs.filter { $0.era == era }.count == 3) }
    }

    @Test func eraAdvancesAfterBossWaveAndPaysResearch() {
        let w = world(gold: 0)
        w.debugSkipToWave(5)
        #expect(w.currentEra == .primitive)
        w.startNextWave()
        w.debugSetGold(0)
        // Win the boss wave instantly by killing everything as it spawns.
        var advanced: (Era, Era)?
        var researchEvents: [String] = []
        let rp0 = w.research
        while w.phase == .waveInProgress {
            w.step(dt)
            for e in w.enemies where e.isActive { w.applyDamage(to: e, raw: 1e6, penetration: 1e6, source: nil) }
            for ev in events(w) {
                if case .eraAdvanced(let a, let b) = ev { advanced = (a, b) }
                if case .researchEarned(let n, let why) = ev { researchEvents.append("\(n) \(why)") }
            }
        }
        #expect(w.phase == .preparation)
        #expect(advanced?.0 == .primitive && advanced?.1 == .medieval)
        #expect(w.currentEra == .medieval)
        let rc = config.rules.research
        let boss = config.enemies["alphaBeast"]!.researchReward!
        #expect(w.research == rp0 + boss + rc.perfectWave + rc.eraCompletion, "\(researchEvents)")
        #expect(w.waves.lastSummary?.researchEarned == boss + rc.perfectWave + rc.eraCompletion)
        #expect(w.stats.bossesDefeated == 1)
    }
}

// MARK: - Enemy abilities

@Suite("Enemy abilities")
struct AbilityTests {
    @Test func resistanceReducesMatchingDamageType() {
        let w = world()
        let troll = w.debugSpawn("troll", atDistance: 300)!
        pin(troll)
        let armor = troll.armor
        w.applyDamage(to: troll, raw: 100, penetration: 0, type: .physical, source: nil)
        let physical = troll.maxHP - troll.hp
        #expect(abs(physical - (100 * 0.7 - armor)) < 0.001)
        let hp1 = troll.hp
        w.applyDamage(to: troll, raw: 100, penetration: 0, type: .explosive, source: nil)
        #expect(abs((hp1 - troll.hp) - (100 - armor)) < 0.001)
    }

    @Test func regenerationWaitsForAQuietMoment() {
        let w = world()
        let troll = w.debugSpawn("troll", atDistance: 300)!
        pin(troll)
        let regen = troll.abilities.regen!
        w.applyDamage(to: troll, raw: 300, penetration: 100, source: nil)
        let hurt = troll.hp
        w.simulate(seconds: regen.delayAfterHit * 0.8)
        #expect(troll.hp == hurt, "no regen right after a hit")
        w.simulate(seconds: regen.delayAfterHit * 0.2 + 1.0)
        #expect(troll.hp > hurt)
        w.simulate(seconds: 60)
        #expect(troll.hp == troll.maxHP, "never above max")
    }

    @Test func burningStopsRegeneration() {
        let w = world()
        let beast = w.debugSpawn("mutantBeast", atDistance: 300)!
        pin(beast)
        w.applyDamage(to: beast, raw: 200, penetration: 100, source: nil)
        w.applyStatus(HitEffects(burn: 0.05, burnDuration: 6), rawDamage: 100, to: beast)  // 5 dps for 6 s
        let hp0 = beast.hp
        w.simulate(seconds: 5)
        #expect(beast.hp < hp0, "burn keeps damaging and blocks regen")
        #expect(beast.isBurning)
        w.simulate(seconds: 1.5)
        #expect(!beast.isBurning)
    }

    @Test func sprintTogglesSpeed() {
        let w = world()
        let gw = w.debugSpawn("giantWolf", atDistance: 0)!
        let s = gw.abilities.sprint!
        var speeds = Set<Int>()
        for _ in 0..<Int((s.cooldown + s.duration) * 2 * 60) { w.step(dt); speeds.insert(Int(gw.speed)) }
        #expect(speeds.contains(Int(gw.baseSpeed)))
        #expect(speeds.contains(Int(gw.baseSpeed * s.multiplier)))
    }

    @Test func stealthHidesFromTowersWithoutDetection() {
        let w = world()
        let bot = w.debugSpawn("stealthRobot", atDistance: 400)!
        pin(bot)
        let s = bot.abilities.stealth!
        w.simulate(seconds: s.visible + 0.1)
        #expect(bot.isCloaked)
        let pos = bot.position
        #expect(TargetingSystem.selectTarget(from: w.enemies, towerPosition: pos, range: 100, priority: .first, canTargetAir: true) == nil)
        #expect(TargetingSystem.selectTarget(from: w.enemies, towerPosition: pos, range: 100, priority: .first, canTargetAir: true,
                                             detectsStealth: true) === bot)
        w.simulate(seconds: s.hidden)
        #expect(!bot.isCloaked, "cloak wears off")
    }

    @Test func highLevelSniperAndAITargetingDetectStealth() {
        let w = world(gold: 10_000, research: 50)
        w.build(.sniper, atSlot: 3)
        let t = w.tower(atSlot: 3)!
        #expect(!t.stats.seesStealth)
        while t.level < 4 { w.upgrade(t) }
        #expect(t.stats.seesStealth)
        w.build(.rapid, atSlot: 4)
        let r = w.tower(atSlot: 4)!
        #expect(!r.stats.seesStealth)
        w.debugSkipToWave(16)   // futuristic era unlocks AI Targeting
        #expect(w.research("aiTargeting") == .success(cost: config.tech("aiTargeting")!.cost))
        #expect(r.stats.seesStealth)
    }

    @Test func splashHitsCloakedEnemies() {
        let w = world(gold: 1000)
        let slot = 5
        w.build(.splash, atSlot: slot)
        let d = pathDistance(near: slot, in: w)
        let bot = w.debugSpawn("stealthRobot", atDistance: d)!
        pin(bot)
        let near = w.debugSpawn("wolf", atDistance: d + 4)!
        pin(near)
        bot.isCloaked = true
        bot.stealthTimer = 1e9
        w.simulate(seconds: 4)
        #expect(bot.hp < bot.maxHP, "the blast aimed at the wolf also hits the cloaked robot")
    }

    @Test func shieldAbsorbsFirstAndRecharges() {
        let w = world()
        let r = w.debugSpawn("assaultRobot", atDistance: 300)!
        pin(r)
        let sh = r.abilities.shield!
        #expect(r.shieldHP == sh.hp)
        w.applyDamage(to: r, raw: 100, penetration: 100, type: .physical, source: nil)
        #expect(r.hp == r.maxHP)
        #expect(abs(r.shieldHP - (sh.hp - 100 * 0.8)) < 0.001, "physical resistance applies before the shield")
        // Energy tears through shields 50 % faster.
        let s0 = r.shieldHP
        w.applyDamage(to: r, raw: 100, penetration: 100, type: .energy, source: nil)
        #expect(abs((s0 - r.shieldHP) - 150) < 0.001)
        // Overflow reaches HP.
        w.applyDamage(to: r, raw: 600, penetration: 100, type: .explosive, source: nil)
        #expect(r.shieldHP == 0 && r.hp < r.maxHP && r.isActive)
        let hp = r.hp
        w.simulate(seconds: sh.rechargeDelay + 1)
        #expect(r.shieldHP > 0)
        #expect(r.hp == hp)
    }

    @Test func giantMutantSplitsAndWaveWaitsForTheBrood() {
        let w = world()
        w.debugSkipToWave(13)
        w.startNextWave()
        w.simulate(seconds: 0.1)
        let mutant = w.enemies.first { $0.definition.id == "giantMutant" }!
        let before = w.enemies.count
        w.applyDamage(to: mutant, raw: 1e6, penetration: 1e6, source: nil)
        let evs = events(w)
        #expect(evs.contains { if case .enemySplit(let e, 3) = $0 { return e === mutant } else { return false } })
        let kids = w.enemies.filter { $0.isSpawnedMinion && $0.definition.id == "mutantBeast" }
        #expect(kids.count == 3)
        #expect(w.enemies.count == before + 3)
        #expect(kids.allSatisfy { $0.distance <= mutant.distance })
    }

    @Test func alphaHowlsForWolvesAndEnrages() {
        let w = world()
        let alpha = w.debugSpawn("alphaBeast", atDistance: 400)!
        let summon = alpha.abilities.summon!
        w.simulate(seconds: summon.interval + 0.1)
        let wolves = w.enemies.filter { $0.definition.id == "wolf" && $0.isSpawnedMinion }
        #expect(wolves.count == summon.count)
        let speed0 = alpha.baseSpeed
        w.applyDamage(to: alpha, raw: alpha.maxHP * 0.55 + alpha.armor, penetration: 0, source: nil)
        #expect(alpha.phaseName == "Enraged")
        #expect(abs(alpha.baseSpeed - speed0 * 1.4) < 0.001)
        #expect(events(w).contains { if case .enemyPhaseChanged(_, "Enraged") = $0 { return true } else { return false } })
    }

    @Test func dragonFireBreathKnocksOutNearbyTowers() {
        let w = world(gold: 5000)
        for s in [3, 4, 5] { w.build(.sniper, atSlot: s) }
        let d = pathDistance(near: 4, in: w)
        let dragon = w.debugSpawn("ancientDragon", atDistance: d)!
        pin(dragon)
        let ab = dragon.abilities.disableTowers!
        var disabled: [Tower] = []
        for _ in 0..<Int(ab.interval * 60) + 5 {
            w.step(dt)
            for e in events(w) { if case .towersDisabled(let ts, _, "Fire Breath", _) = e { disabled = ts } }
            if !disabled.isEmpty { break }
        }
        #expect(!disabled.isEmpty && disabled.count <= ab.maxTowers)
        let t = disabled[0]
        #expect(t.isDisabled(at: w.time))
        let lastShot = t.lastFireTime
        w.simulate(seconds: ab.duration - 0.2)
        #expect(t.lastFireTime == lastShot, "a disabled tower doesn't fire")
        w.simulate(seconds: 1.5)
        #expect(!t.isDisabled(at: w.time))
    }

    @Test func mutantTitanSpawnsBroodAsItIsWounded() {
        let w = world()
        let titan = w.debugSpawn("mutantTitan", atDistance: 400)!
        let b = titan.abilities.brood!
        w.applyDamage(to: titan, raw: titan.maxHP * b.everyHPFraction * 1.05, penetration: 100, type: .energy, source: nil)
        let swarm = w.enemies.filter { $0.definition.id == b.enemy }
        #expect(swarm.count == b.count)
    }

    @Test func titanWarMachineSecondPhase() {
        let w = world(gold: 5000)
        for s in [10, 11, 12] { w.build(.heavy, atSlot: s) }
        let d = pathDistance(near: 11, in: w)
        let titan = w.debugSpawn("titanWarMachine", atDistance: d)!
        #expect(titan.abilities.disableTowers == nil && titan.abilities.baseStrike == nil, "phase 1 has no specials")
        let armor1 = titan.armor
        w.applyDamage(to: titan, raw: titan.maxHP * 0.6, penetration: 1000, type: .energy, source: nil)
        #expect(titan.phaseName == "Overdrive")
        #expect(titan.armor < armor1)
        #expect(titan.baseSpeed > titan.definition.speed)
        pin(titan)
        let hp0 = w.baseHP
        var emp = false, missiles = 0, reinforcements = 0, leaks = 0
        for _ in 0..<(60 * 21) {
            w.step(dt)
            for e in events(w) {
                switch e {
                case .towersDisabled(_, _, "EMP Blast", _): emp = true
                case .baseStruck(_, "Missile Strike", let dmg): missiles += dmg
                case .enemiesSummoned(_, "Reinforcements", let n): reinforcements += n
                case .enemyReachedBase(_, let dmg): leaks += dmg
                default: break
                }
            }
        }
        #expect(emp)
        #expect(missiles >= 3)
        #expect(w.baseHP == hp0 - missiles - leaks, "missile damage goes straight to the base")
        #expect(reinforcements >= 2)
    }

    @Test func finalBossReachingTheBaseIsDefeat() {
        let w = world()
        w.debugSetBaseHP(100)
        w.debugSpawn("titanWarMachine", atDistance: w.path.totalLength - 0.1)
        w.step(dt)
        #expect(w.phase == .defeat)
    }

    @Test func slowAndStunAffectMovementButBossesResistThem() {
        let w = world()
        let bear = w.debugSpawn("bear", atDistance: 100)!
        w.applyStatus(HitEffects(slow: 0.5, slowDuration: 2), rawDamage: 10, to: bear)
        w.step(dt)
        #expect(abs(bear.speed - bear.baseSpeed * 0.5) < 0.001)
        w.applyStatus(HitEffects(stun: 1), rawDamage: 10, to: bear)
        let d = bear.distance
        w.simulate(seconds: 0.5)
        #expect(bear.distance == d)
        w.simulate(seconds: 2)
        #expect(bear.speed == bear.baseSpeed)

        let boss = w.debugSpawn("alphaBeast", atDistance: 100)!
        w.applyStatus(HitEffects(slow: 0.5, slowDuration: 2, stun: 1), rawDamage: 10, to: boss)
        w.step(dt)
        #expect(abs(boss.speed - boss.baseSpeed * 0.75) < 0.001, "bosses take half the slow and no stun")
    }

    @Test func rapidFireCriticalHits() {
        let w = world(gold: 10_000)
        w.build(.rapid, atSlot: 12)
        let t = w.tower(atSlot: 12)!
        while case .success = w.upgrade(t) {}
        let chance = t.stats.hitEffects.critChance
        #expect(chance > 0)
        let d = pathDistance(near: 12, in: w)
        let mech = w.debugSpawn("heavyMech", atDistance: d)!
        pin(mech)
        var shots = 0, crits = 0
        for _ in 0..<(60 * 20) {
            w.step(dt)
            for e in events(w) {
                if case .towerFired = e { shots += 1 }
                if case .criticalHit = e { crits += 1 }
            }
            if !mech.isActive { break }
        }
        let rate = Double(crits) / Double(max(1, shots))
        #expect(shots > 100)
        #expect(abs(rate - chance) < 0.05, "crit rate \(rate) vs \(chance)")
    }
}

// MARK: - Research & tech tree

@Suite("Research & technology")
struct ResearchTests {
    @Test func purchaseRules() {
        let w = world(research: 0)
        #expect(w.research == 0)
        #expect(w.research("nope") == .unknownTech)
        let arrows = config.tech("improvedArrows")!
        #expect(w.research("improvedArrows") == .insufficientResearch(needed: arrows.cost, available: 0))
        #expect(w.research("plasmaTechnology") == .eraLocked(requires: .futuristic))
        w.debugSetResearch(arrows.cost)
        #expect(w.techStatus(arrows) == .available)
        #expect(w.research("improvedArrows") == .success(cost: arrows.cost))
        #expect(w.research == 0)
        #expect(w.techStatus(arrows) == .researched)
        #expect(w.research("improvedArrows") == .alreadyResearched)
        #expect(w.stats.techsResearched == 1)
    }

    @Test func startingResearchLetsYouBuyAnEarlyTech() {
        let w = world()
        #expect(w.research == config.rules.research.startingPoints)
        #expect(config.techs.contains { $0.era == .primitive && $0.cost <= w.research })
    }

    @Test func techChangesExistingAndFutureTowers() {
        let w = world(gold: 1000, research: 100)
        w.build(.sniper, atSlot: 3)
        let before = w.tower(atSlot: 3)!
        let base = before.stats.damage
        w.research("improvedArrows")
        #expect(abs(before.stats.damage - base * 1.10) < 0.0001)
        #expect(before.baseStats.damage == base, "data stays untouched")
        w.build(.sniper, atSlot: 4)
        #expect(abs(w.tower(atSlot: 4)!.stats.damage - base * 1.10) < 0.0001)
        // Splash unaffected by Improved Arrows.
        w.build(.splash, atSlot: 5)
        #expect(w.tower(atSlot: 5)!.stats.damage == config.tower(.splash).stats(level: 1).damage)
        // Upgrades keep the bonus.
        w.upgrade(before)
        #expect(abs(before.stats.damage - config.tower(.sniper).stats(level: 2).damage * 1.10) < 0.0001)
        #expect(w.effectiveStats(.sniper, level: 3).damage > config.tower(.sniper).stats(level: 3).damage)
    }

    @Test func researchIsAllowedDuringAWave() {
        let w = world(research: 10)
        w.startNextWave()
        w.simulate(seconds: 1)
        #expect(w.research("advancedTraps") == .success(cost: config.tech("advancedTraps")!.cost))
    }

    @Test func strongerWallsRaisesMaxHPAndHeals() {
        let w = world(research: 10)
        w.debugSetBaseHP(80)
        w.research("strongerWalls")
        #expect(w.maxBaseHP == 120 && w.baseHP == 100)
    }

    @Test func heavyArmorAndEnergyShieldProtectTheBase() {
        let w = world(research: 100)
        w.debugSkipToWave(16)
        w.research("heavyArmor")
        w.research("energyShield")
        w.startNextWave()
        #expect(w.baseShield == 20)
        // Bear (5) → 25 % less = 4, all absorbed by the shield.
        w.debugSpawn("bear", atDistance: w.path.totalLength - 0.1)
        w.step(dt)
        #expect(w.baseHP == 100 && w.baseShield == 16)
        // Alpha (25 → 19): 16 absorbed, 3 to HP.
        w.debugSpawn("alphaBeast", atDistance: w.path.totalLength - 0.1)
        w.step(dt)
        #expect(w.baseShield == 0 && w.baseHP == 97)
        #expect(w.waves.tally.baseDamageTaken == 3)
    }

    @Test func fireTechnologyIgnitesTargets() {
        let w = world(gold: 1000, research: 100)
        w.debugSkipToWave(6)
        w.research("fireTechnology")
        w.build(.heavy, atSlot: 9)
        let t = w.tower(atSlot: 9)!
        #expect(t.stats.hitEffects.burn > 0)
        let d = pathDistance(near: 9, in: w)
        let troll = w.debugSpawn("troll", atDistance: d)!
        pin(troll)
        for _ in 0..<(60 * 6) { w.step(dt); if troll.isBurning { break } }
        #expect(troll.isBurning)
    }
}
