import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

/// A world with gold and research to spare and every technology available from the start.
private func world(seed: UInt64 = 3) -> GameWorld {
    var c = config
    for i in c.techs.indices { c.techs[i].era = .primitive }
    let w = GameWorld(config: c, options: MatchOptions(randomEvents: false), seed: seed)
    w.holdPreparationCountdown = true
    w.debugSetGold(100_000)
    w.debugSetResearch(500)
    return w
}

private func level(_ a: TowerArchetype, _ n: Int) -> TowerLevelStats { config.tower(a).levels[n - 1] }

/// Builds a tower on the pad nearest the road point `distance` along the path and raises it to `level`.
@discardableResult
private func tower(_ w: GameWorld, _ a: TowerArchetype, level: Int, nearDistance d: CGFloat = 300) -> Tower {
    let p = w.path.position(at: d)
    let slot = w.config.map.buildSlots.filter { w.tower(atSlot: $0.id) == nil }
        .min { w.config.map.slotPosition($0).distance(to: p) < w.config.map.slotPosition($1).distance(to: p) }!
    w.build(a, atSlot: slot.id)
    let t = w.tower(atSlot: slot.id)!
    while t.level < level { w.upgrade(t) }
    return t
}

private func run(_ w: GameWorld, _ seconds: Double, until stop: (GameEvent) -> Bool = { _ in false }) -> [GameEvent] {
    var seen: [GameEvent] = []
    var done = false
    for _ in 0..<Int(seconds / dt) where !done {
        w.step(dt)
        w.drainEvents { e in seen.append(e); if stop(e) { done = true } }
    }
    return seen
}

@Suite("Tower mastery (level 6), new effects and doctrines")
struct TowerMasteryTests {
    // MARK: Data

    @Test func everyTowerHasASixthLevelWithItsOwnAbility() {
        for a in TowerArchetype.allCases {
            let t = config.tower(a)
            #expect(t.maxLevel == 6)
            let top = t.stats(level: 6), below = t.stats(level: 5)
            #expect(top.cost > below.cost && top.damage > below.damage)
            #expect(top.artLevel == 5, "level 6 reuses the level-5 model until it has its own")
            #expect(top.hitEffects != below.hitEffects, "\(a): level 6 adds an effect, not just numbers")
        }
        #expect(level(.splash, 6).hitEffects.groundBurn > 0)
        #expect(level(.sniper, 6).hitEffects.execute > 0 && level(.sniper, 6).hitEffects.exposedCritChance > 0)
        #expect(level(.heavy, 6).hitEffects.interrupt > 0 && level(.heavy, 6).hitEffects.slow > 0)
        #expect(level(.rapid, 6).hitEffects.chainEvery > 0)
        // Effects are named in the upgrade panel.
        #expect(level(.splash, 6).hitEffects.labels.contains("Burning ground"))
        #expect(level(.rapid, 6).hitEffects.labels.contains { $0.contains("Chain lightning") })
        #expect(level(.sniper, 6).hitEffects.labels.contains { $0.contains("Execute") })
        #expect(level(.heavy, 6).hitEffects.labels.contains("Interrupts bosses"))
    }

    @Test func rolesShowInTheData() {
        // Splash: falloff from level 3, and less armour piercing than the single-target towers.
        #expect((1...6).map { level(.splash, $0).aoeEdgeDamage != nil } == [false, false, true, true, true, true])
        for l in 4...6 { #expect(level(.splash, l).armorPenetration < level(.sniper, l).armorPenetration) }
        // Sniper: slow, hard shots at high levels.
        #expect(level(.sniper, 5).attacksPerSecond < level(.sniper, 3).attacksPerSecond)
        // Heavy reaches flyers from level 3.
        #expect((1...6).map { level(.heavy, $0).canTargetAir } == [false, false, true, true, true, true])
        // Old saves: a level-5 tower stays level 5 and still has stats.
        #expect(config.tower(.rapid).stats(level: 5).name == "Laser Gatling")
    }

    // MARK: Splash

    @Test func blastsHitTheEdgeForLessThanTheCentre() {
        let w = world()
        let t = tower(w, .splash, level: 3, nearDistance: 300)
        w.startNextWave()
        let near = w.debugSpawn("bear", atDistance: 300)!
        let far = w.debugSpawn("bear", atDistance: 300 - 55)!     // inside the blast (radius 70), outside its inner half
        _ = run(w, 6) { if case .projectileImpact = $0 { return true } else { return false } }
        let a = near.maxHP - near.hp, b = far.maxHP - far.hp
        #expect(t.target === near || t.target === far)
        #expect(max(a, b) > 0 && min(a, b) > 0, "both were in the blast")
        #expect(min(a, b) < max(a, b), "the one away from the centre took less")
        #expect(min(a, b) >= max(a, b) * 0.5, "but never less than the edge share")
    }

    @Test func novaArtilleryLeavesOneBurningGroundPerTower() {
        let w = world()
        let t = tower(w, .splash, level: 6, nearDistance: 300)
        w.startNextWave()
        let e = w.debugSpawn("heavyMech", atDistance: 300)!
        let events = run(w, 5) { if case .groundFire = $0 { return true } else { return false } }
        #expect(events.contains { if case .groundFire = $0 { return true } else { return false } })
        #expect(w.burnZones.count == 1 && w.burnZones[0].towerID == t.id)
        _ = run(w, 0.6)
        #expect(e.isBurning, "enemies standing in the fire burn")
        _ = run(w, 8)
        #expect(w.burnZones.count <= 1, "a new shot moves the fire instead of adding one")
        // A fire never outlasts its duration.
        let h = level(.splash, 6).hitEffects
        #expect(w.burnZones.allSatisfy { $0.until <= w.time + h.groundDuration + 0.01 })
    }

    // MARK: Sniper

    @Test func executeHitsWoundedEnemiesHarderAndBossesForHalf() {
        let w = world()
        let h = level(.sniper, 6).hitEffects
        let e = w.debugSpawn("heavyMech", atDistance: 300)!
        #expect(w.conditionalDamage(h, base: 100, on: e).damage == 100)
        w.applyDamage(to: e, raw: e.maxHP * 0.75, penetration: 1e9, source: nil, ignoreDefences: true)
        #expect(e.hpFraction < h.executeThreshold)
        #expect(abs(w.conditionalDamage(h, base: 100, on: e).damage - 100 * (1 + h.execute)) < 1e-9)
        let boss = w.debugSpawn("alphaBeast", atDistance: 300)!
        w.applyDamage(to: boss, raw: boss.maxHP * 0.8, penetration: 1e9, source: nil, ignoreDefences: true)
        #expect(abs(w.conditionalDamage(h, base: 100, on: boss).damage - 100 * (1 + h.execute / 2)) < 1e-9)
    }

    @Test func criticalHitsOnlyComeOnExposedTargets() {
        let w = world()
        let h = level(.sniper, 6).hitEffects
        let e = w.debugSpawn("heavyMech", atDistance: 300)!
        #expect((0..<200).allSatisfy { _ in !w.conditionalDamage(h, base: 100, on: e).critical })
        w.applyStatus(level(.heavy, 5).hitEffects, rawDamage: 100, to: e)
        let crits = (0..<400).filter { _ in w.conditionalDamage(h, base: 100, on: e).critical }.count
        #expect(crits > 400 / 8 && crits < 400 / 2, "about a quarter: \(crits) of 400")
    }

    // MARK: Heavy

    @Test func interruptDelaysABossAbilityButNotAgainRightAway() {
        let w = world()
        let dragon = w.debugSpawn("ancientDragon", atDistance: 300)!
        let h = level(.heavy, 6).hitEffects
        let before = dragon.disableTimer
        w.applyStatus(h, rawDamage: 100, to: dragon)
        #expect(abs(dragon.disableTimer - (before + h.interrupt)) < 1e-9)
        w.applyStatus(h, rawDamage: 100, to: dragon)
        #expect(abs(dragon.disableTimer - (before + h.interrupt)) < 1e-9, "once per cooldown")
        // Bosses are slowed by half and never stunned.
        #expect(dragon.slowAmount == h.slow / 2 && dragon.stunnedUntil <= w.time)
        // Ordinary enemies are not "interrupted".
        let mech = w.debugSpawn("heavyMech", atDistance: 300)!
        w.applyStatus(h, rawDamage: 100, to: mech)
        #expect(mech.interruptReadyAt == 0 && mech.slowAmount == h.slow)
    }

    @Test func anEnemyCannotBeStunnedBackToBack() {
        let w = world()
        let e = w.debugSpawn("heavyMech", atDistance: 300)!
        let h = level(.heavy, 5).hitEffects
        w.applyStatus(h, rawDamage: 100, to: e)
        let end = e.stunnedUntil
        #expect(end > w.time)
        for _ in 0..<Int(1.0 / dt) { w.step(dt); w.applyStatus(h, rawDamage: 100, to: e) }
        #expect(e.stunnedUntil == end, "hits during the immunity do not stun again")
        for _ in 0..<Int((GameWorld.controlImmunity + 0.2) / dt) { w.step(dt) }
        w.applyStatus(h, rawDamage: 100, to: e)
        #expect(e.stunnedUntil > end)
    }

    // MARK: Rapid Fire

    @Test func chainLightningJumpsToNearbyEnemiesWithTheShotsEffects() {
        let w = world()
        tower(w, .rapid, level: 6, nearDistance: 300)
        w.startNextWave()
        let mechs = (0..<4).map { w.debugSpawn("heavyMech", atDistance: 300 - CGFloat($0) * 30)! }
        var chain: [CGPoint] = []
        _ = run(w, 4) { if case .chainLightning(let p) = $0 { chain = p; return true } else { return false } }
        let h = level(.rapid, 6).hitEffects
        #expect(chain.count >= 2 && chain.count <= Int(h.chainTargets) + 1)
        #expect(mechs.filter { $0.hp < $0.maxHP }.count >= 2, "more than the target was hurt")
        #expect(mechs.filter(\.isShredded).count >= 2, "the jumps carry Armour Shred")
    }

    // MARK: Doctrines

    @Test func onlyOneDoctrineOfAPairCanBeResearched() {
        let w = world()
        let trappers = w.config.tech("trappers")!, hunters = w.config.tech("hunters")!
        #expect(trappers.group != nil && trappers.group == hunters.group)
        #expect(w.techStatus(hunters) == .available)
        #expect(w.research("trappers") == .success(cost: trappers.cost))
        #expect(w.techStatus(hunters) == .excluded(by: trappers.name))
        let rp = w.research
        #expect(w.research("hunters") == .excluded(by: trappers.name))
        #expect(w.research == rp && !w.isResearched("hunters"))
        // Other pairs and ordinary technologies are unaffected.
        #expect(w.techStatus(w.config.tech("cryoShells")!) == .available)
        #expect(w.techStatus(w.config.tech("gunpowder")!) == .available)
    }

    @Test func notEverythingCanBeBought() {
        // One doctrine per pair plus the twelve technologies costs more than a clean match earns.
        let doctrineCost = Dictionary(grouping: config.techs.filter(\.isDoctrine), by: { $0.group! }).values
            .map { $0.map(\.cost).min()! }.reduce(0, +)
        let total = config.techs.filter { !$0.isDoctrine }.map(\.cost).reduce(0, +) + doctrineCost
        let rc = config.rules.research
        let perfect = config.waves.filter { rc.paysPerfect(stage: $0.number, isBoss: $0.isBossWave) }.count * rc.perfectWave
        let bosses = config.waves.dropLast().flatMap(\.groups).compactMap { config.enemies[$0.enemy]?.researchReward }.reduce(0, +)
        let earned = rc.startingPoints + perfect + rc.eraCompletion * 3 + bosses
        #expect(total > earned, "cost \(total) vs earned at best \(earned)")
        #expect(earned >= total * 6 / 10, "but most of it is within reach")
        #expect(rc.paysPerfect(stage: 20, isBoss: true) && !rc.paysPerfect(stage: 21, isBoss: false) && rc.paysPerfect(stage: 25, isBoss: true))
    }

    @Test func trappersMakeSlowsLastLonger() {
        let w = world()
        let t = tower(w, .splash, level: 4)
        let before = t.stats.hitEffects.slowDuration
        w.research("trappers")
        #expect(abs(t.stats.hitEffects.slowDuration - before * 1.5) < 1e-9)
    }

    @Test func cryoShellsFreezeOnTheThirdSlowAndThenGiveARest() {
        let w = world()
        w.research("cryoShells")
        let slow = HitEffects(slow: 0.2, slowDuration: 1)
        let e = w.debugSpawn("heavyMech", atDistance: 300)!
        w.applyStatus(slow, rawDamage: 10, to: e); w.applyStatus(slow, rawDamage: 10, to: e)
        #expect(!e.isFrozen)
        w.applyStatus(slow, rawDamage: 10, to: e)
        #expect(e.isFrozen && e.stunnedUntil >= e.frozenUntil)
        let thawsAt = e.frozenUntil
        for _ in 0..<Int(1.0 / dt) { w.step(dt) }
        #expect(!e.isFrozen)
        for _ in 0..<6 { w.applyStatus(slow, rawDamage: 10, to: e) }
        #expect(!e.isFrozen && e.stunnedUntil == thawsAt, "no second freeze during the immunity")
        // Bosses never freeze.
        let boss = w.debugSpawn("alphaBeast", atDistance: 300)!
        for _ in 0..<6 { w.applyStatus(slow, rawDamage: 10, to: boss) }
        #expect(!boss.isFrozen)
        // Without the doctrine nothing freezes.
        let plain = world()
        let p = plain.debugSpawn("heavyMech", atDistance: 300)!
        for _ in 0..<6 { plain.applyStatus(slow, rawDamage: 10, to: p) }
        #expect(!p.isFrozen)
    }

    @Test func incendiarySpreadsFireWhenABurningEnemyDies() {
        let w = world()
        w.research("incendiary")
        let a = w.debugSpawn("bear", atDistance: 300)!, b = w.debugSpawn("bear", atDistance: 320)!
        let far = w.debugSpawn("bear", atDistance: 600)!
        w.applyStatus(HitEffects(burn: 0.1, burnDuration: 3), rawDamage: 100, to: a)
        w.applyDamage(to: a, raw: 1e9, penetration: 1e9, source: nil, ignoreDefences: true)
        #expect(!a.isActive && b.isBurning && !far.isBurning)
    }

    @Test func overpressureAndTargetPainterChangeWhatAHitDoes() {
        let w = world()
        let e = w.debugSpawn("heavyMech", atDistance: 300)!, twin = w.debugSpawn("heavyMech", atDistance: 300)!
        w.research("overpressure")
        w.applyStatus(HitEffects(stun: 1), rawDamage: 0, to: e)
        w.applyDamage(to: e, raw: 1000, penetration: 1e9, source: nil)
        w.applyDamage(to: twin, raw: 1000, penetration: 1e9, source: nil)
        let hurt = e.maxHP - e.hp, plain = twin.maxHP - twin.hp
        #expect(abs(hurt - plain * 1.2) < 1e-6, "stunned enemies take 20 % more")
    }

    @Test func improvedArrowsRewardSettingTargetsUp() {
        let w = world()
        w.research("improvedArrows")
        let t = tower(w, .sniper, level: 1)
        let h = t.stats.hitEffects
        #expect(h.afflictedBonus > 0)
        let e = w.debugSpawn("heavyMech", atDistance: 300)!
        #expect(w.conditionalDamage(h, base: 100, on: e).damage == 100)
        w.applyStatus(HitEffects(slow: 0.2, slowDuration: 2), rawDamage: 0, to: e)
        #expect(abs(w.conditionalDamage(h, base: 100, on: e).damage - 100 * (1 + h.afflictedBonus)) < 1e-9)
        // Splash is not part of it.
        #expect(tower(w, .splash, level: 1, nearDistance: 500).stats.hitEffects.afflictedBonus == 0)
    }

    // MARK: Economy

    @Test func theTopLevelIsTheLateGoldSink() {
        let full = TowerArchetype.allCases.map { config.tower($0).levels.map(\.cost).reduce(0, +) }
        let toFive = TowerArchetype.allCases.map { config.tower($0).levels.prefix(5).map(\.cost).reduce(0, +) }
        // Level 6 alone costs well over half of everything before it.
        for (f, five) in zip(full, toFive) { #expect(f - five >= five * 6 / 10) }
        // Early levels are no dearer than before the rebalance.
        #expect(config.tower(.splash).buildCost == 70 && config.tower(.sniper).buildCost == 60)
        #expect(config.tower(.heavy).buildCost <= 90 && config.tower(.rapid).buildCost == 65)
    }
}
