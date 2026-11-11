import CoreGraphics
import Testing
@testable import EvolutionDefenseCore

private let baseConfig = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

private func makeWorld(gold: Int? = nil) -> GameWorld {
    let w = GameWorld(config: baseConfig, seed: 42)
    // Keep waves from auto-starting so tests control spawning explicitly.
    w.holdPreparationCountdown = true
    if let gold { w.debugSetGold(gold) }
    return w
}

/// Slot whose position is closest to the given path distance.
private func slotNear(_ w: GameWorld, distance: CGFloat) -> BuildSlotDefinition {
    let p = w.path.position(at: distance)
    return w.config.map.buildSlots.min {
        w.config.map.slotPosition($0).distance(to: p) < w.config.map.slotPosition($1).distance(to: p)
    }!
}

@Suite("Enemy movement & base damage")
struct MovementTests {
    @Test func wolfWalksWholePathAndDamagesBase() {
        let w = makeWorld()
        let wolf = w.debugSpawn("wolf")!
        let expectedTime = Double(w.path.totalLength) / wolf.speed
        w.simulate(seconds: expectedTime * 0.95)
        #expect(wolf.isActive, "wolf should still be walking")
        #expect(wolf.distance > w.path.totalLength * 0.9)
        #expect(w.baseHP == 100)
        w.simulate(seconds: expectedTime * 0.1)
        #expect(wolf.reachedBase)
        #expect(w.baseHP == 100 - wolf.definition.baseDamage)
        #expect(w.enemies.isEmpty)
        #expect(w.stats.enemiesLeaked == 1)
    }

    @Test func enemiesStayNearThePath() {
        let w = makeWorld()
        let e = w.debugSpawn("bear")!
        var worst: CGFloat = 0
        for _ in 0..<(60 * 40) {
            w.step(dt)
            guard e.isActive else { break }
            worst = max(worst, w.path.distanceToPath(from: e.position))
        }
        #expect(worst <= CGFloat(baseConfig.rules.laneSpread) + 12, "enemy strayed \(worst) from path")
    }

    @Test func simultaneousLeaksAreAllCountedAndDefeatFiresOnce() {
        let w = makeWorld()
        let near = w.path.totalLength - 0.1
        // One more boss than it takes to destroy the base, all arriving in the same step.
        let hit = baseConfig.enemies["alphaBeast"]!.baseDamage
        let needed = (w.baseHP + hit - 1) / hit
        for _ in 0...needed { w.debugSpawn("alphaBeast", atDistance: near) }
        var defeatEvents = 0
        var baseDamageEvents = 0
        w.step(dt)
        w.drainEvents { e in
            if case .matchEnded(.defeat) = e { defeatEvents += 1 }
            if case .baseDamaged = e { baseDamageEvents += 1 }
        }
        #expect(w.baseHP == 0)
        #expect(w.phase == .defeat)
        #expect(defeatEvents == 1)
        #expect(baseDamageEvents == needed, "simulation stops processing after defeat")
        // Further steps do nothing once the match is over.
        w.step(dt)
        #expect(w.phase == .defeat)
    }
}

@Suite("Targeting")
struct TargetingTests {
    private func setup() -> (GameWorld, [Enemy]) {
        let w = makeWorld()
        // Three enemies spread along the first straight.
        let a = w.debugSpawn("wolf", atDistance: 100)!
        let b = w.debugSpawn("bear", atDistance: 200)!
        let c = w.debugSpawn("wildBoar", atDistance: 300)!
        return (w, [a, b, c])
    }

    @Test func priorities() {
        let (w, es) = setup()
        let center = w.path.position(at: 200)
        func pick(_ p: TargetingPriority, air: Bool = false) -> Enemy? {
            TargetingSystem.selectTarget(from: w.enemies, towerPosition: center, range: 1000, priority: p, canTargetAir: air)
        }
        #expect(pick(.first) === es[2])
        #expect(pick(.last) === es[0])
        #expect(pick(.strongest) === es[1])   // bear 240 HP
        #expect(pick(.weakest) === es[0])     // wolf 38 HP
        #expect(pick(.closest) === es[1])
        #expect(pick(.boss) === es[2], "no boss → behaves like First")
        let boss = w.debugSpawn("alphaBeast", atDistance: 50)!
        #expect(pick(.boss) === boss)
    }

    @Test func respectsRangeAndIgnoresDeadEnemies() {
        let (w, es) = setup()
        let towerPos = w.path.position(at: 100) + CGPoint(x: 0, y: 60)
        let t = TargetingSystem.selectTarget(from: w.enemies, towerPosition: towerPos, range: 80, priority: .first, canTargetAir: true)
        #expect(t === es[0])
        es[0].isAlive = false
        let t2 = TargetingSystem.selectTarget(from: w.enemies, towerPosition: towerPos, range: 80, priority: .first, canTargetAir: true)
        #expect(t2 == nil)
    }

    @Test func groundTowersIgnoreFlyingEnemies() {
        var flyer = baseConfig.enemies["wolf"]!
        flyer.id = "testFlyer"; flyer.isFlying = true
        var cfg = baseConfig
        cfg.enemies[flyer.id] = flyer
        let w = GameWorld(config: cfg, seed: 1)
        w.holdPreparationCountdown = true
        let f = w.debugSpawn("testFlyer", atDistance: 100)!
        let pos = f.position
        #expect(TargetingSystem.selectTarget(from: w.enemies, towerPosition: pos, range: 50, priority: .first, canTargetAir: false) == nil)
        #expect(TargetingSystem.selectTarget(from: w.enemies, towerPosition: pos, range: 50, priority: .first, canTargetAir: true) === f)
    }
}

@Suite("Building & combat")
struct CombatTests {
    @Test func buildRules() {
        let w = makeWorld(gold: 100)
        let slot = w.config.map.buildSlots[0].id
        let result = w.build(.heavy, atSlot: slot)
        #expect(result == .success(towerID: w.towers[0].id))
        #expect(w.gold == 100 - baseConfig.tower(.heavy).buildCost)
        #expect(w.build(.rapid, atSlot: slot) == .slotOccupied)
        #expect(w.build(.rapid, atSlot: 999) == .invalidSlot)
        let goldBefore = w.gold
        if case .insufficientGold(let need, let have) = w.build(.splash, atSlot: w.config.map.buildSlots[1].id) {
            #expect(need == baseConfig.tower(.splash).buildCost)
            #expect(have == goldBefore)
        } else {
            Issue.record("expected insufficient gold")
        }
        #expect(w.gold == goldBefore, "failed build must not spend gold")
        #expect(w.towers.count == 1)
    }

    @Test func sniperKillsWolfAndEarnsGold() {
        let w = makeWorld(gold: 1000)
        let slot = slotNear(w, distance: 300)
        w.build(.sniper, atSlot: slot.id)
        let goldAfterBuild = w.gold
        let wolf = w.debugSpawn("wolf")!
        w.simulate(seconds: 15)
        #expect(!wolf.isAlive)
        #expect(w.gold == goldAfterBuild + wolf.definition.goldReward)
        #expect(w.stats.enemiesKilled == 1)
        #expect(w.towers[0].kills == 1)
        #expect(w.baseHP == 100)
    }

    @Test func projectileFizzlesWhenTargetDiesInFlight() {
        let w = makeWorld(gold: 1000)
        let slot = slotNear(w, distance: 400)
        w.build(.heavy, atSlot: slot.id)
        let tower = w.towers[0]
        let victim = w.debugSpawn("bear", atDistance: 400)!
        let bystander = w.debugSpawn("bear", atDistance: 401)!
        // Step until the tower fires once.
        var fired = false
        for _ in 0..<120 where !fired {
            w.step(dt)
            fired = w.projectiles.contains { $0.isActive }
        }
        #expect(fired)
        // Kill the targeted enemy externally while the spear is in flight.
        let targeted = tower.target!
        w.applyDamage(to: targeted, raw: 10_000, penetration: 100, source: nil)
        let other = targeted === victim ? bystander : victim
        let hpBefore = other.hp
        for _ in 0..<60 { w.step(dt); if !w.projectiles.contains(where: { $0.isActive }) { break } }
        // The spear must not crash or hit the other bear; the tower may fire again later.
        #expect(other.hp == hpBefore || tower.target === other)
        #expect(!targeted.isAlive)
    }

    @Test func splashDamagesAllEnemiesInRadius() {
        let w = makeWorld(gold: 1000)
        let slot = slotNear(w, distance: 600)
        w.build(.splash, atSlot: slot.id)
        let cluster = (0..<4).map { i in w.debugSpawn("bear", atDistance: 600 + CGFloat(i) * 6)! }
        let far = w.debugSpawn("bear", atDistance: 1400)!
        var impacts = 0
        for _ in 0..<(60 * 3) {
            w.step(dt)
            w.drainEvents { if case .projectileImpact(_, _, let r, let hit) = $0, r > 0, hit { impacts += 1 } }
            if impacts > 0 { break }
        }
        #expect(impacts == 1)
        let damaged = cluster.filter { $0.hp < $0.maxHP }.count
        #expect(damaged >= 3, "AoE should hit most of the cluster (hit \(damaged))")
        #expect(far.hp == far.maxHP)
    }

    @Test func simultaneousExplosionsRewardKillOnce() {
        let w = makeWorld()
        let e = w.debugSpawn("wolf", atDistance: 500)!
        let gold0 = w.gold
        w.applyDamage(to: e, raw: 1000, penetration: 0, source: nil)
        w.applyDamage(to: e, raw: 1000, penetration: 0, source: nil)
        #expect(w.gold == gold0 + e.definition.goldReward)
        #expect(w.stats.enemiesKilled == 1)
    }

    @Test func projectilePoolIsReused() {
        let w = makeWorld(gold: 5000)
        for s in w.config.map.buildSlots.prefix(6) { w.build(.rapid, atSlot: s.id) }
        let initialPool = w.projectiles.count
        w.startNextWave()
        w.simulate(seconds: 40)
        #expect(w.projectiles.count <= initialPool + 64, "pool grew to \(w.projectiles.count)")
    }
}

@Suite("Waves & match flow")
struct WaveTests {
    @Test func spawnerSchedulesAllEnemiesInOrder() {
        var s = EnemySpawner()
        s.load(WaveDefinition(number: 1, era: .primitive, groups: [
            SpawnGroup(enemy: "wolf", count: 3, interval: 1, delay: 0),
            SpawnGroup(enemy: "bear", count: 2, interval: 2, delay: 0.5)
        ]))
        #expect(s.schedule.map(\.time) == [0, 0.5, 1, 2, 2.5])
        var spawned: [String] = []
        s.update(1.0) { spawned.append($0.enemyID) }
        #expect(spawned == ["wolf", "bear", "wolf"])
        s.update(5) { spawned.append($0.enemyID) }
        #expect(spawned.count == 5)
        #expect(s.isFinished)
    }

    @Test func waveLifecycle() {
        let w = makeWorld(gold: 5000)
        for s in w.config.map.buildSlots { w.build(s.id % 2 == 0 ? .sniper : .rapid, atSlot: s.id) }
        #expect(w.phase == .preparation)
        // Countdown is held at its full 30 s, so starting now pays the full early bonus (half a gold per second).
        #expect(w.startNextWave() == .started(number: 1, earlyBonus: 15))
        #expect(w.startNextWave() == .waveAlreadyRunning, "cannot start a wave while one is running")
        #expect(w.phase == .waveInProgress)
        w.simulate(seconds: 90)
        #expect(w.phase == .preparation)
        #expect(w.waveNumber == 1)
        #expect(w.stats.wavesCleared == 1)
        #expect(w.stats.enemiesKilled + w.stats.enemiesLeaked == baseConfig.waves[0].totalEnemies)
    }

    @Test func maxedDefenceWinsAllTwentyWaves() {
        // Every wave and boss is beatable by a complete defence: all pads at max
        // level plus each technology as soon as its era unlocks it.
        let w = makeWorld(gold: 100_000)
        w.debugSetResearch(1000)
        let types: [TowerArchetype] = [.sniper, .splash, .heavy, .rapid]
        for (i, s) in w.config.map.buildSlots.enumerated() { w.build(types[i % 4], atSlot: s.id) }
        for t in w.towers { while case .success = w.upgrade(t) {} }
        var bossesSeen = 0
        while !w.phase.isOver {
            if w.phase == .preparation {
                for t in w.config.techs where !w.isResearched(t.id) { _ = w.research(t.id) }
                w.startNextWave()
            }
            w.step(dt)
            w.drainEvents { if case .bossSpawned = $0 { bossesSeen += 1 } }
            if w.time > 60 * 70 { break }
        }
        let bosses = baseConfig.waves.flatMap(\.groups).filter { baseConfig.enemies[$0.enemy]!.isBoss }.count
        #expect(bossesSeen == bosses)
        #expect(w.stats.bossesDefeated == bosses)
        #expect(w.phase == .victory)
        #expect(w.waveNumber == w.totalWaves)
        #expect(w.baseHP > 0)
    }

    @Test func undefendedBaseFalls() {
        let w = makeWorld()
        while !w.phase.isOver && w.time < 60 * 20 {
            if w.phase == .preparation { w.startNextWave() }
            w.step(dt)
        }
        #expect(w.phase == .defeat)
        #expect(w.baseHP == 0)
    }
}
