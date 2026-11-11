import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

private func world(towers n: Int, level: Int = 3) -> GameWorld {
    var c = config
    for i in c.techs.indices { c.techs[i].era = .primitive }
    let w = GameWorld(config: c, options: MatchOptions(randomEvents: false), seed: 3)
    w.holdPreparationCountdown = true
    w.debugSetGold(1_000_000)
    w.debugSetResearch(500)
    for (i, s) in w.config.map.buildSlots.prefix(n).enumerated() {
        w.build(TowerArchetype.allCases[i % 4], atSlot: s.id)
        if let t = w.tower(atSlot: s.id) { while t.level < level { w.upgrade(t) } }
    }
    w.debugSetGold(1000)
    return w
}

/// A dragon parked in the middle of the map whose breath is due now. Returns the towers it knocks out.
@discardableResult
private func breathe(_ w: GameWorld, _ dragon: Enemy) -> [Tower] {
    dragon.disableTimer = 0
    var hit: [Tower] = []
    w.step(dt)
    w.drainEvents { if case .towersDisabled(let ts, _, _, _) = $0 { hit += ts } }
    return hit
}

private func dragon(_ w: GameWorld) -> Enemy {
    w.startNextWave()
    // Park it next to the pad with the most towers in reach and stop it there.
    let ability = config.enemies["ancientDragon"]!.baseAbilities.disableTowers!
    var best: CGFloat = 0, bestCount = -1
    var d: CGFloat = 0
    while d < w.path.totalLength {
        let p = w.path.position(at: d)
        let n = w.towers.filter { $0.position.distance(to: p) <= CGFloat(ability.radius) }.count
        if n > bestCount { bestCount = n; best = d }
        d += 20
    }
    let e = w.debugSpawn("ancientDragon", atDistance: best)!
    e.baseSpeed = 0
    return e
}

@Suite("Boss tower disable and recovery")
struct TowerDisableTests {
    let rules = config.rules.towerDisable!

    @Test func rulesComeFromConfiguration() {
        #expect(rules.maxShare > 0 && rules.maxShare <= 0.34, "never a large part of the defence")
        #expect(rules.protection >= 5)
        #expect(rules.recoverCostMin > 0 && rules.recoverCostMax <= 150, "restarting is never ruinous")
        // Every boss disable is long enough to make paying a real choice, and leaves gaps.
        for e in config.enemies.values {
            for a in [e.baseAbilities] + e.sortedPhases.compactMap(\.abilities) {
                guard let d = a.disableTowers else { continue }
                #expect(d.duration >= 4 && d.duration <= 8, "\(e.id) \(d.name)")
                #expect(d.interval >= d.duration + 4, "\(e.id) \(d.name): time to respond between uses")
                #expect(d.maxTowers <= 3)
            }
        }
    }

    @Test func aDisabledTowerStopsFiringButKeepsEverything() {
        let w = world(towers: 12)
        let boss = dragon(w)
        let hit = breathe(w, boss)
        let t = try! #require(hit.first)
        let (id, slot, level, invested, targeting, kills) = (t.id, t.slotID, t.level, t.totalInvested, t.targeting, t.kills)
        #expect(t.isDisabled(at: w.time) && t.disableRemaining(at: w.time) > 4)
        let shot = t.lastFireTime
        for _ in 0..<Int(2 / dt) { w.step(dt) }
        #expect(t.lastFireTime == shot, "it does not attack while disabled")
        // Same object, same place, same upgrades; never removed.
        #expect(w.tower(atSlot: slot) === t && w.towers.contains { $0 === t })
        #expect(t.id == id && t.level == level && t.totalInvested == invested && t.targeting == targeting && t.kills == kills)
        // It can still be upgraded and sold like any other tower.
        w.debugSetGold(5000)
        #expect(w.upgrade(t) == .success(newLevel: level + 1, cost: t.definition.stats(level: level + 1).cost))
        #expect(t.isDisabled(at: w.time), "upgrading does not cancel the knock-out")
    }

    @Test func waitingRecoversForFree() {
        let w = world(towers: 12)
        let boss = dragon(w)
        let t = try! #require(breathe(w, boss).first)
        let gold = w.gold
        var recovered = false
        let until = t.disabledUntil
        while w.time < until + 0.2 {
            w.step(dt)
            w.drainEvents { if case .towerRecovered(let x, let paid) = $0, x === t { recovered = true; #expect(paid == 0) } }
        }
        #expect(recovered && !t.isDisabled(at: w.time))
        #expect(w.gold >= gold, "no gold was taken")
        #expect(w.recoverCost(for: t) == nil)
    }

    @Test func payingRestartsAtOnceAndOnlyOnce() {
        let w = world(towers: 12)
        let boss = dragon(w)
        let t = try! #require(breathe(w, boss).first)
        let cost = try! #require(w.recoverCost(for: t))
        let expected = min(Double(rules.recoverCostMax), max(Double(rules.recoverCostMin), Double(t.totalInvested) * rules.recoverCostFraction))
        #expect(cost == Int(expected.rounded()))
        let gold = w.gold
        #expect(w.recover(t) == .success(cost: cost))
        #expect(w.gold == gold - cost && !t.isDisabled(at: w.time))
        // A second click (or a double click) charges nothing more.
        #expect(w.recover(t) == .notDisabled)
        #expect(w.gold == gold - cost)
        // It fires again.
        let shot = t.lastFireTime
        _ = w.debugSpawn("heavyMech", atDistance: w.path.totalLength * 0.5)
        for _ in 0..<Int(3 / dt) { w.step(dt) }
        #expect(w.towers.contains { $0.lastFireTime > shot })
    }

    @Test func notEnoughGoldMeansWaiting() {
        let w = world(towers: 12)
        let boss = dragon(w)
        let t = try! #require(breathe(w, boss).first)
        w.debugSetGold(0)
        let cost = w.recoverCost(for: t)!
        #expect(w.recover(t) == .insufficientGold(needed: cost, available: 0))
        #expect(t.isDisabled(at: w.time) && w.gold == 0)
    }

    @Test func neverMoreThanAShareOfTheTowersAtOnce() {
        for n in [1, 3, 4, 8, 12, 16] {
            let w = world(towers: n)
            let boss = dragon(w)
            let cap = max(1, Int(Double(n) * rules.maxShare))
            for _ in 0..<6 {
                breathe(w, boss)
                let out = w.towers.filter { $0.isDisabled(at: w.time) }.count
                #expect(out <= cap, "\(n) towers: \(out) disabled, cap \(cap)")
                #expect(out < max(n, 2), "never the whole defence")
            }
        }
    }

    @Test func aRecoveredTowerIsProtectedFromTheNextDisable() {
        let w = world(towers: 12)
        let boss = dragon(w)
        let first = breathe(w, boss)
        #expect(!first.isEmpty)
        for t in first { w.debugSetGold(5000); let c = w.recoverCost(for: t)!; #expect(w.recover(t) == .success(cost: c)) }
        // The very next breath cannot pick the same towers.
        let second = breathe(w, boss)
        #expect(second.allSatisfy { s in !first.contains { $0 === s } })
        #expect(first.allSatisfy { !$0.isDisabled(at: w.time) && $0.protectedUntil > w.time })
        // Protection ends.
        for _ in 0..<Int((rules.protection + 6) / dt) { w.step(dt); w.drainEvents { _ in } }
        #expect(first.allSatisfy { $0.protectedUntil <= w.time })
    }

    @Test func countdownStandsStillWhileTheGameIsPaused() {
        let w = world(towers: 12)
        let boss = dragon(w)
        let t = try! #require(breathe(w, boss).first)
        let left = t.disableRemaining(at: w.time)
        // Paused = the simulation is not stepped; wall-clock time plays no part.
        #expect(t.disableRemaining(at: w.time) == left)
        for _ in 0..<60 { w.step(dt) }
        #expect(abs(t.disableRemaining(at: w.time) - (left - 1)) < 0.02)
    }

    @Test func fieldEngineersShortenDisablesAndHalveThePrice() {
        let plain = world(towers: 12), eng = world(towers: 12)
        eng.research("fieldEngineers")
        let a = try! #require(breathe(plain, dragon(plain)).first), b = try! #require(breathe(eng, dragon(eng)).first)
        #expect(abs(b.disableRemaining(at: eng.time) - a.disableRemaining(at: plain.time) * 0.6) < 0.05)
        #expect(eng.recoverCost(for: b)! <= (plain.recoverCost(for: a)! + 1) / 2 + 1)
    }

    @Test func bossesNeverDamageOrRemoveTowers() {
        // A long boss fight: the towers at the end are the towers at the start.
        let w = world(towers: 16, level: 4)
        let before = w.towers.map { ($0.id, $0.slotID, $0.level, $0.totalInvested) }
        w.debugSkipToWave(10)
        w.startNextWave()
        var disables = 0
        while w.phase == .waveInProgress && w.time < 600 {
            w.step(dt)
            w.drainEvents { if case .towersDisabled = $0 { disables += 1 } }
        }
        #expect(disables > 0, "the dragon used its breath")
        let after = w.towers.map { ($0.id, $0.slotID, $0.level, $0.totalInvested) }
        #expect(before.count == after.count)
        for (a, b) in zip(before, after) { #expect(a == b) }
    }
}

@Suite("Late-game enemy traits")
struct EnemyTraitTests {
    private func spawn(_ w: GameWorld, _ id: String, _ trait: EnemyTrait?) -> Enemy {
        w.spawnEnemy(id, atDistance: 300, modifiers: SpawnModifiers(trait: trait))!
    }

    @Test func insulatedEnemiesCannotBeSlowedOrFrozen() {
        let w = world(towers: 0)
        w.research("cryoShells")
        let e = spawn(w, "scoutRobot", .insulated), plain = spawn(w, "scoutRobot", nil)
        let slow = HitEffects(slow: 0.3, slowDuration: 2)
        for _ in 0..<5 { w.applyStatus(slow, rawDamage: 10, to: e); w.applyStatus(slow, rawDamage: 10, to: plain) }
        #expect(!e.isSlowed && !e.isFrozen)
        #expect(plain.isSlowed && plain.isFrozen)
        // Everything else still works on it.
        w.applyStatus(HitEffects(burn: 0.1, burnDuration: 2, expose: 0.2, exposeDuration: 2), rawDamage: 100, to: e)
        #expect(e.isBurning && e.isExposed)
    }

    @Test func platedEnemiesLoseHalfAsMuchArmourToShred() {
        let w = world(towers: 0)
        let e = spawn(w, "heavyMech", .plated), plain = spawn(w, "heavyMech", nil)
        let h = config.tower(.rapid).levels[4].hitEffects
        for _ in 0..<40 { w.applyStatus(h, rawDamage: 10, to: e); w.applyStatus(h, rawDamage: 10, to: plain) }
        #expect(plain.shredAmount == h.shredCap && e.shredAmount == h.shredCap / 2)
    }

    @Test func phasingEnemiesShrugOffDamageOnlyWhileFlickeredOut() {
        let w = world(towers: 0)
        let t = config.rules.traits!
        let e = spawn(w, "heavyMech", .phasing)
        var immune = 0.0, total = 0.0
        for _ in 0..<Int(20 / dt) {
            w.step(dt)
            let before = e.hp
            w.applyDamage(to: e, raw: 1, penetration: 1e9, source: nil, ignoreDefences: true)
            total += dt
            if e.hp == before { immune += dt }
        }
        let share = t.phaseDuration / t.phaseInterval
        #expect(immune > 0 && abs(immune / total - share) < 0.08, "out of reach about \(Int(share * 100)) % of the time, was \(immune / total)")
        #expect(immune / total < 0.35, "most of the time it can be hurt")
    }

    @Test func traitsAppearOnlyInTheLateStagesAndNeverOnBosses() {
        for wave in config.authoredWaves {
            for g in wave.groups where g.trait != nil {
                #expect(wave.number >= 21, "stage \(wave.number)")
                #expect(config.enemies[g.enemy]?.isBoss == false)
            }
        }
        #expect(Set(config.authoredWaves.flatMap(\.groups).compactMap(\.trait)) == Set(EnemyTrait.allCases))
        // A trait asked for on a boss is ignored.
        let w = world(towers: 0)
        #expect(w.spawnEnemy("alphaBeast", atDistance: 100, modifiers: SpawnModifiers(trait: .insulated))!.trait == nil)
    }

    @Test func lateStagesAreMixturesNotBiggerCopies() {
        // Stages 21–29: each one mixes at least three kinds of problem, so no single tower answers it.
        for wave in config.authoredWaves where (21...29).contains(wave.number) {
            var kinds = Set<String>()
            for g in wave.groups {
                guard let e = config.enemies[g.enemy] else { continue }
                if e.isFlying { kinds.insert("air") }
                if e.armor >= 8 { kinds.insert("armour") }
                if e.hp <= 150 || g.count >= 20 { kinds.insert("swarm") }
                if e.baseAbilities.stealth != nil { kinds.insert("cloaked") }
                if g.trait != nil { kinds.insert("trait") }
                if g.elite == true { kinds.insert("elite") }
            }
            #expect(kinds.count >= 3, "stage \(wave.number): \(kinds.sorted())")
        }
    }

    @Test func rostersKeepTheTraits() {
        for id in ["desert", "lakeside"] {
            let c = config.selecting(battlefield: id)
            #expect(Set(c.waves.flatMap(\.groups).compactMap(\.trait)) == Set(EnemyTrait.allCases), "\(id)")
        }
    }
}
