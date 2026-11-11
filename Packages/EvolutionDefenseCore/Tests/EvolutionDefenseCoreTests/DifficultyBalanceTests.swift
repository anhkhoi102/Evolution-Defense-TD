import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

private func world(_ d: Difficulty = .normal) -> GameWorld {
    let w = GameWorld(config: config, options: MatchOptions(difficulty: d, randomEvents: false), seed: 3)
    w.holdPreparationCountdown = true
    w.debugSetGold(100_000)
    return w
}

private func level(_ a: TowerArchetype, _ n: Int) -> TowerLevelStats { config.tower(a).levels[n - 1] }

/// Total health of a stage as it is played on a difficulty (thousands), bosses included.
private func stageHealth(_ wave: WaveDefinition, _ d: DifficultyDefinition) -> Double {
    let phase = config.rules.phase(forWave: wave.number, curve: d.curve ?? 1)
    let elite = config.rules.elite ?? EliteConfig()
    return wave.groups.reduce(0.0) { sum, g in
        let e = config.enemies[g.enemy]!
        let hp = e.hp * (g.hpMultiplier ?? 1) * d.enemyHP * (e.isBoss ? 1 : phase.enemyHP) * (g.elite == true && !e.isBoss ? elite.hp : 1)
        return sum + hp * Double(g.count)
    } / 1000
}

@Suite("Difficulty and combat balance")
struct DifficultyBalanceTests {
    let normal = config.difficulty(.normal), hard = config.difficulty(.hard), easy = config.difficulty(.easy)

    // MARK: Sniper and Splash

    @Test func sniperHasABlindSpotAndTheLongestReach() {
        for l in 1...6 {
            let s = level(.sniper, l)
            #expect((s.minRange ?? 0) >= 50, "level \(l) has a blind spot")
            for other in [TowerArchetype.splash, .heavy, .rapid] {
                #expect(s.range > level(other, l).range, "still out-ranges \(other) at level \(l)")
                #expect(level(other, l).minRange == nil)
            }
            #expect(s.range <= 320, "but no longer covers half the map")
        }
        // Piercing shots only at the top two levels.
        #expect((1...6).map { level(.sniper, $0).hitEffects.pierceTargets > 0 } == [false, false, false, false, true, true])
    }

    @Test func aSniperCannotShootWhatIsInsideItsBlindSpot() {
        let w = world()
        // The pad closest to the road, so part of the road is inside the blind spot.
        func roadDistance(_ s: BuildSlotDefinition) -> CGFloat {
            var best = CGFloat.greatestFiniteMagnitude, d: CGFloat = 0
            while d < w.path.totalLength { best = min(best, w.path.position(at: d).distance(to: w.config.map.slotPosition(s))); d += 5 }
            return best
        }
        let slot = w.config.map.buildSlots.min { roadDistance($0) < roadDistance($1) }!
        w.build(.sniper, atSlot: slot.id)
        let t = w.tower(atSlot: slot.id)!
        let blind = CGFloat(t.stats.minRange!)
        #expect(roadDistance(slot) < blind - 12, "the blind spot reaches the road: pad at \(roadDistance(slot)), blind spot \(blind)")
        w.startNextWave()
        // Find road points inside and outside the blind spot (but inside the range).
        var inside: CGFloat?, outside: CGFloat?
        var d: CGFloat = 0
        while d < w.path.totalLength {
            let r = w.path.position(at: d).distance(to: t.position)
            if r < blind - 12 { inside = inside ?? d }
            if r > blind + 25 && r < CGFloat(t.stats.range) - 25 { outside = outside ?? d }
            d += 5
        }
        guard let inside, let outside else { return }
        let near = w.debugSpawn("heavyMech", atDistance: inside)!
        near.baseSpeed = 0
        for e in w.enemies where e !== near { w.applyDamage(to: e, raw: 1e9, penetration: 1e9, source: nil, ignoreDefences: true) }
        let shots = t.shotCount
        for _ in 0..<Int(4 / dt) {
            w.step(dt)
            for e in w.enemies where e !== near && e.isActive { w.applyDamage(to: e, raw: 1e9, penetration: 1e9, source: nil, ignoreDefences: true) }
        }
        #expect(t.shotCount == shots && near.hp == near.maxHP, "nothing inside the blind spot is shot")
        let far = w.debugSpawn("heavyMech", atDistance: outside)!
        far.baseSpeed = 0
        for _ in 0..<Int(4 / dt) {
            w.step(dt)
            for e in w.enemies where e !== near && e !== far && e.isActive { w.applyDamage(to: e, raw: 1e9, penetration: 1e9, source: nil, ignoreDefences: true) }
        }
        #expect(t.shotCount > shots && far.hp < far.maxHP && near.hp == near.maxHP)
    }

    @Test func splashDoesLessToBosses() {
        for l in 1...6 {
            let share = try! #require(level(.splash, l).bossDamage)
            #expect(share < 1 && share >= 0.6)
        }
        for a in [TowerArchetype.sniper, .heavy, .rapid] { for l in 1...6 { #expect(level(a, l).bossDamage == nil) } }
        // Measured: the same blast on a boss and on an ordinary enemy with the same armour.
        func firstHit(_ id: String) -> Double {
            let w = world()
            let slot = w.config.map.buildSlots[0]
            w.build(.splash, atSlot: slot.id)
            let t = w.tower(atSlot: slot.id)!
            w.startNextWave()
            var d: CGFloat = 0, at: CGFloat = 0, best = CGFloat.greatestFiniteMagnitude
            while d < w.path.totalLength { let r = w.path.position(at: d).distance(to: t.position); if r < best { best = r; at = d }; d += 5 }
            let e = w.debugSpawn(id, atDistance: at)!
            e.baseSpeed = 0
            e.armor = 0
            for _ in 0..<Int(6 / dt) where e.hp == e.maxHP {
                w.step(dt)
                for o in w.enemies where o !== e && o.isActive { w.applyDamage(to: o, raw: 1e9, penetration: 1e9, source: nil, ignoreDefences: true) }
            }
            return e.maxHP - e.hp
        }
        let onBoss = firstHit("alphaBeast"), onOrdinary = firstHit("bear")
        #expect(onOrdinary > 0 && abs(onBoss - onOrdinary * level(.splash, 1).bossDamage!) < 0.01)
    }

    // MARK: Normal against Hard

    @Test func hardDiffersInKindNotJustInHealth() {
        #expect(hard.enemyHP > normal.enemyHP && hard.enemyHP <= 1.15, "only a little more health")
        #expect(hard.enemySpeed > normal.enemySpeed)
        #expect(hard.goldMultiplier < normal.goldMultiplier)
        #expect((hard.preparationTime ?? 99) < config.rules.waveTiming.preparationTime)
        #expect((hard.enemyArmorBonus ?? 0) > 0 && normal.enemyArmorBonus == nil)
        #expect(hard.extraElitesFromStage != nil && normal.extraElitesFromStage == nil)
        #expect(try! #require(hard.traitsFromStage) < (try! #require(normal.traitsFromStage)))
        #expect(try! #require(normal.traitsFromStage) < (try! #require(easy.traitsFromStage)))
        #expect((hard.disableMaxShare ?? 0) > (config.rules.towerDisable?.maxShare ?? 1))
        #expect((hard.repairCostMultiplier ?? 1) > 1 && (hard.sellRefundRatio ?? 1) < config.rules.economy.sellRefundRatio)
    }

    @Test func traitsStartAtEachDifficultysOwnStage() {
        for d in [easy, normal, hard] {
            let from = try! #require(d.traitsFromStage)
            let waves = config.matchWaves(d)
            #expect(waves.filter { $0.number < from }.allSatisfy { $0.groups.allSatisfy { $0.trait == nil } }, "\(d.id)")
            #expect(waves.contains { $0.number >= from && $0.groups.contains { $0.trait != nil } }, "\(d.id)")
        }
        let firstNormal = config.matchWaves(normal).first { $0.groups.contains { $0.trait != nil } }!.number
        let firstHard = config.matchWaves(hard).first { $0.groups.contains { $0.trait != nil } }!.number
        #expect(firstHard < firstNormal)
    }

    @Test func hardAddsAnEliteGroupToEveryLaterStage() {
        let from = try! #require(hard.extraElitesFromStage)
        let n = config.matchWaves(normal), h = config.matchWaves(hard)
        for (a, b) in zip(n, h) {
            let elitesA = a.groups.filter { $0.elite == true }.map(\.count).reduce(0, +)
            let elitesB = b.groups.filter { $0.elite == true }.map(\.count).reduce(0, +)
            if a.number >= from { #expect(elitesB > elitesA, "stage \(a.number)") } else { #expect(elitesB == elitesA, "stage \(a.number)") }
            // Never an elite boss, and bosses still come alone.
            #expect(b.groups.filter { config.enemies[$0.enemy]!.isBoss }.allSatisfy { $0.elite != true && $0.count == 1 })
        }
    }

    @Test func hardArmoursLateEnemiesAndMakesRepairsAndSellingWorse() {
        let from = try! #require(hard.armorFromStage)
        let late = world(.hard)
        late.debugSkipToWave(from)
        late.startNextWave()
        let base = config.enemies["scoutRobot"]!.armor
        #expect(late.debugSpawn("scoutRobot", atDistance: 100)!.armor == base + hard.enemyArmorBonus!)
        #expect(late.debugSpawn("titanWarMachine", atDistance: 100)!.armor == config.enemies["titanWarMachine"]!.armor, "bosses are not armoured further")
        let early = world(.hard)
        early.startNextWave()
        #expect(early.debugSpawn("scoutRobot", atDistance: 100)!.armor == base)
        // Selling and repairing.
        let n = world(.normal), h = world(.hard)
        for w in [n, h] { w.build(.heavy, atSlot: w.config.map.buildSlots[0].id) }
        #expect(h.sellValue(for: h.towers[0]) < n.sellValue(for: n.towers[0]))
        n.debugSetBaseHP(50); h.debugSetBaseHP(50)
        #expect(h.repairQuote(optionIndex: 0)!.cost > n.repairQuote(optionIndex: 0)!.cost)
        #expect(h.repairQuote(optionIndex: 0)!.heal == n.repairQuote(optionIndex: 0)!.heal)
    }

    // MARK: No unavoidable damage

    @Test func theTitansMissilesOnlyFireOnceItIsFarAlongTheRoad() {
        func missiles(atProgress p: CGFloat) -> Int {
            let w = world()
            w.startNextWave()
            let titan = w.debugSpawn("titanWarMachine", atDistance: w.path.totalLength * p)!
            w.applyDamage(to: titan, raw: titan.maxHP * 0.55, penetration: 1e9, source: nil, ignoreDefences: true)   // into its second phase
            titan.baseSpeed = 0
            var n = 0
            for _ in 0..<Int(40 / dt) {
                w.step(dt)
                w.drainEvents { if case .baseStruck = $0 { n += 1 } }
                for o in w.enemies where o !== titan && o.isActive { w.applyDamage(to: o, raw: 1e9, penetration: 1e9, source: nil, ignoreDefences: true) }
            }
            return n
        }
        let limits: [Double] = config.enemies["titanWarMachine"]!.sortedPhases.compactMap { $0.abilities?.baseStrike?.minProgress }
        let limit = limits[0]
        #expect(limit >= 0.5)
        #expect(missiles(atProgress: CGFloat(limit) - 0.2) == 0, "held back: it never fires")
        #expect(missiles(atProgress: CGFloat(limit) + 0.1) >= 2, "allowed forward: it does")
    }

    // MARK: Curve and economy

    @Test func stageHealthRisesSteadilyWithoutDeadStagesOrCliffs() {
        let waves = config.matchWaves(normal).filter { !$0.isBossWave && $0.number >= 9 }
        for (a, b) in zip(waves, waves.dropFirst()) {
            let ratio = stageHealth(b, normal) / stageHealth(a, normal)
            #expect(ratio >= 0.9, "stage \(b.number) is a dead stage after \(a.number): ×\(ratio)")
            #expect(ratio <= 1.6, "stage \(b.number) is a cliff after \(a.number): ×\(ratio)")
        }
        // Boss stages are never lighter than the stage before them.
        let all = config.matchWaves(normal)
        for b in all where b.isBossWave && b.number > 5 {
            #expect(stageHealth(b, normal) >= stageHealth(all[b.number - 2], normal) * 0.95, "boss stage \(b.number)")
        }
    }

    @Test func upgradingCostsEfficiency() {
        // Damage per gold spent falls as a tower is upgraded: spreading and concentrating both have a price.
        for a in TowerArchetype.allCases {
            let levels = config.tower(a).levels
            func perGold(_ n: Int) -> Double { levels[n - 1].damagePerSecond / Double(levels.prefix(n).map(\.cost).reduce(0, +)) }
            #expect(perGold(5) < perGold(3), "\(a)")
            #expect(perGold(6) < perGold(5), "\(a)")
            #expect(levels[3].cost * 10 >= levels[2].cost * 19 && levels[4].cost > levels[3].cost, "\(a): the last levels are a real investment")
        }
    }

    @Test func cleanPlaySnowballsLess() {
        let rc = config.rules.research
        // Research for a clean stage: every second stage up to the limit, boss stages always.
        let paying = config.waves.filter { rc.paysPerfect(stage: $0.number, isBoss: $0.isBossWave) }.map(\.number)
        #expect(paying.count <= 14, "was 22: \(paying)")
        #expect(paying.contains(2) && !paying.contains(3) && paying.contains(5) && paying.contains(25) && !paying.contains(21))
        #expect(config.rules.economy.perfectWaveBonus <= 10)
        #expect(config.rules.economy.earlyStartGoldPerSecond <= 0.5)
    }

    @Test func notEverythingCanBeAfforded() {
        // Gold from kills and stage rewards on Normal against the price of every pad at level 5.
        var income = Double(normal.startingGold)
        for w in config.matchWaves(normal) {
            let phase = config.rules.phase(forWave: w.number)
            let elite = config.rules.elite ?? EliteConfig()
            for g in w.groups {
                let e = config.enemies[g.enemy]!
                income += Double(g.count) * Double(e.goldReward) * phase.killReward * (g.elite == true && !e.isBoss ? elite.reward : 1)
            }
            income += Double(w.clearReward ?? 0) * phase.clearReward
        }
        let pads = config.map.buildSlots.count
        let perTower = TowerArchetype.allCases.map { config.tower($0).levels.prefix(5).map(\.cost).reduce(0, +) }.reduce(0, +) / 4
        let everything = Double(perTower * pads)
        #expect(income < everything, "income \(Int(income)) against \(Int(everything)) for every pad at level 5")
        #expect(income > everything * 0.6, "but enough for a strong defence")
    }
}
