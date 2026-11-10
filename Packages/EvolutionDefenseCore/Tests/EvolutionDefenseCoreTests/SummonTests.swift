import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

/// A world in wave `n` with both abilities unlocked and the countdown held.
private func waveWorld(_ n: Int = 6, seed: UInt64 = 5) -> GameWorld {
    let w = GameWorld(config: config, seed: seed)
    w.holdPreparationCountdown = true
    w.debugSkipToWave(n)
    w.startNextWave()
    return w
}

/// A point on the road `d` points from the spawn.
private func road(_ w: GameWorld, _ d: CGFloat = 900) -> CGPoint { w.path.position(at: d) }

private func run(_ w: GameWorld, _ seconds: Double, events: ((GameEvent) -> Void)? = nil) {
    var t = 0.0
    while t < seconds && !w.phase.isOver {
        w.step(dt); t += dt
        w.drainEvents { e in events?(e) }
    }
}

@Suite("Summons (militia & hero)")
struct SummonTests {
    var militia: SummonAbilityDefinition { config.summons.ability("militia")! }
    var hero: SummonAbilityDefinition { config.summons.ability("hero")! }

    // MARK: Configuration

    @Test func configurationIsWithinTheDesignRanges() {
        #expect(militia.kind == .minion && hero.kind == .hero && hero.archetype == .warrior)
        #expect((3...5).contains(militia.count) && (8...12).contains(militia.duration) && (30...40).contains(militia.cooldown))
        #expect(hero.count == 1 && (15...20).contains(hero.duration) && (50...60).contains(hero.cooldown))
        #expect(hero.unit.hp > militia.unit.hp * 5 && hero.unit.damage > militia.unit.damage * 4)
        #expect(hero.special != nil)
        // Progressive unlock: the opening (waves 1–2) has no summons.
        #expect(militia.unlockWave >= 3 && hero.unlockWave > militia.unlockWave)
    }

    // MARK: Activation rules

    @Test func lockedBeforeItsUnlockWave() {
        let w = waveWorld(2)
        #expect(w.summon("militia", at: road(w)) == .locked(unlockWave: militia.unlockWave))
        #expect(w.summon("hero", at: road(w)) == .locked(unlockWave: hero.unlockWave))
        #expect(w.summons.isEmpty)
    }

    @Test func onlyDuringAWave() {
        let w = GameWorld(config: config, seed: 1)
        w.debugSkipToWave(6)            // preparation for wave 6: unlocked but no fight
        #expect(w.summon("militia", at: road(w)) == .notDuringWave)
    }

    @Test func invalidLocationsAreRejected() {
        let w = waveWorld()
        let size = config.map.worldSize
        #expect(w.summon("militia", at: CGPoint(x: -50, y: 300)) == .invalidLocation, "outside the playfield")
        #expect(w.summon("militia", at: CGPoint(x: size.width / 2, y: size.height + 40)) == .invalidLocation)
        // A build pad far from the road.
        let pad = config.map.slotPosition(config.map.buildSlots.first { $0.id == 6 }!)
        if w.path.distanceToPath(from: pad) > CGFloat(config.summons.maxDeployDistanceFromPath) {
            #expect(w.summon("militia", at: pad) == .invalidLocation)
        }
        #expect(w.summons.isEmpty)
        #expect(w.summonStatus("militia")!.cooldownRemaining == 0, "a rejected placement costs nothing")
        // Just beside the road is fine.
        let beside = road(w) + CGPoint(x: 0, y: 40)
        #expect(w.summon("militia", at: beside) == .success(units: militia.count))
    }

    @Test func deployPlacesTheSquadInFormation() {
        let w = waveWorld()
        var deployed: [SummonUnit] = []
        #expect(w.summon("militia", at: road(w)) == .success(units: militia.count))
        w.drainEvents { if case .summonDeployed(_, let units, _) = $0 { deployed = units } }
        #expect(deployed.count == militia.count && w.summons.count == militia.count)
        for u in deployed {
            #expect(abs(u.position.distance(to: road(w)) - CGFloat(militia.formationRadius)) < 0.01)
            #expect(u.hp == militia.unit.hp && u.expiresAt == w.time + militia.duration)
        }
    }

    @Test func noDuplicateActivationAndIndependentCooldowns() {
        let w = waveWorld()
        #expect(w.summon("militia", at: road(w)) == .success(units: militia.count))
        if case .onCooldown(let r) = w.summon("militia", at: road(w)) {
            #expect(abs(r - militia.cooldown) < 0.01)
        } else { Issue.record("second activation should be refused") }
        #expect(w.summons.count == militia.count)
        // The hero is unaffected by the militia's cooldown.
        #expect(w.summon("hero", at: road(w, 1300)) == .success(units: 1))
        let m = w.summonStatus("militia")!, h = w.summonStatus("hero")!
        #expect(abs(m.cooldownRemaining - militia.cooldown) < 0.01)
        #expect(abs(h.cooldownRemaining - hero.cooldown) < 0.01)
        #expect(!m.isReady && !h.isReady)
    }

    @Test func cooldownResetsAndAnnouncesReady() {
        let w = waveWorld()
        w.drainEvents { _ in }
        _ = w.summon("militia", at: road(w))
        var readies = 0
        w.debugSpawnStream("bear", count: 3, spacing: 30)      // slow bears keep the wave running
        run(w, militia.cooldown + 0.5) { e in if case .summonReady(let a) = e, a.id == "militia" { readies += 1 } }
        #expect(readies == 1, "exactly one 'ready' notice per cooldown")
        #expect(w.summonStatus("militia")!.cooldownRemaining == 0)
        #expect(w.summon("militia", at: road(w)) == .success(units: militia.count))
    }

    // MARK: Lifetime

    @Test func unitsExpireOnTimeAndStopAttacking() {
        let w = waveWorld()
        _ = w.summon("hero", at: road(w))
        let u = w.summons[0]
        var expired = 0, attacksAfter = 0
        var expiredAt = -1.0
        // Enemies keep coming past the hero.
        w.debugSpawnStream("giantWolf", count: 20, spacing: 60)
        run(w, hero.duration + 3) { e in
            switch e {
            case .summonExpired(let x) where x === u: expired += 1; expiredAt = w.time
            case .summonAttacked(let x, _) where x === u && expiredAt >= 0: attacksAfter += 1
            default: break
            }
        }
        #expect(expired == 1)
        #expect(abs(expiredAt - u.expiresAt) < 2 * dt)
        #expect(attacksAfter == 0, "no attacks after expiry")
        #expect(w.summons.isEmpty && !u.isAlive)
        #expect(w.summonStatus("hero")!.aliveUnits == 0 && w.summonStatus("hero")!.activeRemaining == 0)
    }

    @Test func unitsCanBeDefeatedByEnemiesTouchingThem() {
        let w = waveWorld(10)
        // Militia right where a boss walks: contact damage ends them early.
        let at = road(w, 300)
        _ = w.summon("militia", at: at)
        let squad = w.summons
        _ = w.debugSpawn("ancientDragon", atDistance: 200)     // flying: no contact
        for k in 0..<6 { _ = w.debugSpawn("troll", atDistance: 270 + CGFloat(k) * 4) }
        var defeated = 0
        run(w, militia.duration - 1) { e in if case .summonDefeated = e { defeated += 1 } }
        #expect(defeated > 0, "trolls trampling the squad should defeat some of it")
        #expect(squad.allSatisfy { !$0.isAlive || $0.hp < $0.maxHP })
        // The cooldown still runs even though the squad fell early.
        #expect(w.summonStatus("militia")!.cooldownRemaining > 0)
    }

    @Test func everythingIsRemovedWhenTheMatchEnds() {
        let w = waveWorld(6)
        _ = w.summon("militia", at: road(w))
        _ = w.summon("hero", at: road(w, 1300))
        #expect(w.summons.count == militia.count + 1)
        var expired = 0
        w.drainEvents { _ in }
        // Enough bosses at the gate to destroy the base this step.
        for _ in 0..<12 { _ = w.debugSpawn("alphaBeast", atDistance: w.path.totalLength - 0.1) }
        w.step(dt)
        w.drainEvents { if case .summonExpired = $0 { expired += 1 } }
        #expect(w.phase == .defeat)
        #expect(w.summons.isEmpty)
        #expect(expired == militia.count + 1, "every unit is announced as gone so views clean up")
        #expect(w.summon("militia", at: road(w)) == .matchOver)
    }

    // MARK: Combat

    @Test func unitsDamageEnemiesThroughTheDamageModel() {
        let w = waveWorld()
        let at = road(w, 700)
        _ = w.summon("hero", at: at)
        // Armored Monster: 900 HP and 13 armor, so it survives the test and armor matters.
        let target = w.debugSpawn("armoredMonster", atDistance: 690)!
        let hp0 = target.hp
        var hits = 0
        run(w, 1.5) { e in if case .summonAttacked(_, let x) = e, x === target { hits += 1 } }
        #expect(hits >= 1)
        // One hero blow, reduced by armor exactly as for a tower.
        let one = DamageModel.effectiveDamage(raw: hero.unit.damage, armor: target.armor,
                                              penetration: hero.unit.armorPenetration,
                                              minimumFraction: config.rules.minimumDamageFraction,
                                              resistance: target.definition.resistance[hero.unit.damageType])
        #expect(target.isAlive)
        #expect(abs((hp0 - target.hp) - one * Double(hits)) < 0.5, "each blow is exactly the shared damage model's result")
        #expect(w.summons[0].damageDealt > 0)
    }

    @Test func killsPayGoldLikeTowerKills() {
        let w = waveWorld()
        _ = w.summon("hero", at: road(w, 700))
        let wolf = w.debugSpawn("wolf", atDistance: 690)!
        let gold0 = w.gold
        var reward = 0
        run(w, 2) { e in if case .enemyKilled(let x, let r) = e, x === wolf { reward = r } }
        #expect(!wolf.isAlive)
        #expect(reward > 0 && w.gold >= gold0 + reward)
    }

    @Test func heroPrioritisesBossesThenElites() {
        let w = waveWorld(10)
        _ = w.summon("hero", at: road(w, 700))
        let u = w.summons[0]
        let near = w.debugSpawn("wolf", atDistance: 705)!
        let elite = w.debugSpawn("armoredBeast", atDistance: 760, elite: true)!
        w.step(dt)
        #expect(u.target === elite, "an elite beats a nearer normal enemy")
        let boss = w.debugSpawn("alphaBeast", atDistance: 800)!
        for _ in 0..<20 { w.step(dt) }
        #expect(u.target === boss, "a boss beats everything")
        _ = near
    }

    @Test func minionsTakeTheNearestThreat() {
        let w = waveWorld()
        _ = w.summon("militia", at: road(w, 700))
        let close = w.debugSpawn("bear", atDistance: 712)!      // sturdy enough to survive the first blows
        _ = w.debugSpawn("armoredBeast", atDistance: 780, elite: true)
        w.step(dt)
        let nearestUnit = w.summons.min { $0.position.distance(to: close.position) < $1.position.distance(to: close.position) }!
        #expect(close.isActive)
        #expect(nearestUnit.target === close)
    }

    @Test func meleeUnitsIgnoreFlyersAndCloakedEnemies() {
        let w = waveWorld(17)
        _ = w.summon("hero", at: road(w, 700))
        let u = w.summons[0]
        let flyer = w.debugSpawn("flyingMonster", atDistance: 700)!
        w.step(dt)
        #expect(u.target !== flyer)
        let robot = w.debugSpawn("stealthRobot", atDistance: 700)!
        robot.isCloaked = true
        for _ in 0..<20 { w.step(dt); robot.isCloaked = true }
        #expect(u.target !== robot, "no stealth detection without AI Targeting")
    }

    @Test func unitsReturnToTheirPostAndDoNotChaseForever() {
        let w = waveWorld()
        _ = w.summon("hero", at: road(w, 700))
        let u = w.summons[0]
        let runner = w.debugSpawn("wolf", atDistance: 720)!
        run(w, 6)
        #expect(u.position.distance(to: u.post) <= CGFloat(hero.unit.leash) + CGFloat(hero.unit.range) + 40)
        _ = runner
    }

    @Test(arguments: [4, 9, 14])
    func summonsAloneCannotClearAWave(wave: Int) {
        // No towers, both abilities used on the crowd every time they're ready:
        // summons support a defence, they don't replace it.
        let w = waveWorld(wave)
        let bot = BalancePlayer(name: "summons only", plan: [], maxTowers: 0, upgrades: false, repairs: false,
                                research: false)
        var player = bot; player.summons = true
        var spawned = 0, killed = 0, ticks = 0
        while !w.phase.isOver && w.phase == .waveInProgress && w.time < 300 {
            if ticks % 30 == 0 { player.useSummons(w) }
            w.step(dt); ticks += 1
            w.drainEvents { e in
                switch e {
                case .enemySpawned, .bossSpawned: spawned += 1
                case .enemyKilled: killed += 1
                default: break
                }
            }
        }
        print("SUMMON alone wave \(wave): killed \(killed) of \(spawned), summons used \(w.summonsCalled)")
        #expect(w.summonsCalled >= 1)
        #expect(Double(killed) < Double(spawned) * 0.5, "summons alone killed \(killed) of \(spawned)")
    }

    @Test func manyUnitsEnemiesAndTowersStayFast() {
        let w = GameWorld(config: config, seed: 9)
        w.debugSetGold(1_000_000)
        w.debugSkipToWave(16)
        for (i, s) in config.map.buildSlots.enumerated() { _ = w.build([.splash, .sniper, .heavy, .rapid][i % 4], atSlot: s.id) }
        for t in w.towers { while case .success = w.upgrade(t) {} }
        w.startNextWave()
        for i in 0..<300 { _ = w.debugSpawn(["scoutRobot", "assaultRobot", "swarmCreature"][i % 3], atDistance: CGFloat(i) * 7) }
        _ = w.summon("militia", at: road(w, 800))
        _ = w.summon("hero", at: road(w, 1400))
        let clock = ContinuousClock()
        let elapsed = clock.measure { for _ in 0..<300 { w.step(dt); w.drainEvents { _ in } } }
        let perStep = elapsed / 300
        print("SUMMON perf: \(perStep) per step with \(w.enemies.count) enemies, \(w.summons.count) summons")
        #expect(perStep < .milliseconds(4), "simulation step stays well inside a 16 ms frame in debug builds")
    }
}

extension GameWorld {
    /// Test helper: `count` enemies spread along the road from the spawn, so they arrive one after another.
    fileprivate func debugSpawnStream(_ kind: String, count: Int, spacing: CGFloat) {
        for k in 0..<count { _ = debugSpawn(kind, atDistance: CGFloat(k) * spacing) }
    }
}
