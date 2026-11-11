import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

private func heldWorld(gold: Int? = nil) -> GameWorld {
    let w = GameWorld(config: config, seed: 11)
    w.holdPreparationCountdown = true
    if let gold { w.debugSetGold(gold) }
    return w
}

/// Runs until the current wave ends (or the match ends).
private func finishWave(_ w: GameWorld, limit: Double = 240) {
    var t = 0.0
    while w.phase == .waveInProgress && t < limit { w.step(dt); t += dt }
}

@Suite("Economy")
struct EconomyTests {
    @Test func spendingNeverGoesNegative() {
        var e = Economy(startingGold: 100)
        let tooMuch = e.spend(101)
        #expect(!tooMuch)
        #expect(e.gold == 100 && e.totalSpent == 0)
        let exact = e.spend(100)
        #expect(exact)
        #expect(e.gold == 0 && e.totalSpent == 100)
        let broke = e.spend(1)
        #expect(!broke)
        e.earn(25); e.refund(10)
        #expect(e.gold == 35 && e.totalEarned == 25 && e.totalRefunded == 10)
        e.earn(-5)
        #expect(e.gold == 35)
    }
}

@Suite("Wave manager & preparation phase")
struct PreparationTests {
    @Test func countdownStartsFirstWaveAutomatically() {
        let w = GameWorld(config: config, seed: 1)
        #expect(w.phase == .preparation)
        #expect(w.preparationRemaining == config.rules.waveTiming.initialPreparationTime)
        w.simulate(seconds: config.rules.waveTiming.initialPreparationTime - 0.5)
        #expect(w.phase == .preparation)
        w.simulate(seconds: 1)
        #expect(w.phase == .waveInProgress)
        #expect(w.waveNumber == 1)
    }

    @Test func heldCountdownDoesNotTick() {
        let w = heldWorld()
        w.simulate(seconds: 120)
        #expect(w.phase == .preparation)
        #expect(w.preparationRemaining == config.rules.waveTiming.initialPreparationTime)
        w.holdPreparationCountdown = false
        w.simulate(seconds: 5)
        #expect(abs(w.preparationRemaining - (config.rules.waveTiming.initialPreparationTime - 5)) < 0.05)
    }

    @Test func earlyStartPaysForRemainingTime() {
        let w = heldWorld()
        w.holdPreparationCountdown = false
        w.simulate(seconds: 10.5)                      // 19.5 s left
        let gold0 = w.gold
        let expected = Int((w.preparationRemaining * config.rules.economy.earlyStartGoldPerSecond).rounded(.down))
        #expect(w.earlyStartBonus == expected)
        #expect(w.startNextWave() == .started(number: 1, earlyBonus: expected))
        #expect(w.gold == gold0 + expected)
        #expect(w.waves.tally.earlyStartBonus == expected)
        #expect(w.earlyStartBonus == 0, "no bonus while a wave runs")
    }

    @Test func clearedWaveSummaryAndRewards() {
        let w = heldWorld(gold: 2000)
        for s in config.map.buildSlots.prefix(8) { w.build(.sniper, atSlot: s.id) }
        w.startNextWave()
        let goldAtStart = w.gold
        var summary: WaveSummary?
        var prepEvent = false
        var t = 0.0
        while summary == nil && t < 200 {
            w.step(dt); t += dt
            w.drainEvents {
                if case .waveCleared(let s) = $0 { summary = s }
                if case .preparationStarted = $0 { prepEvent = true }
            }
        }
        let s = try! #require(summary)
        let wave = config.waves[0]
        #expect(s.number == 1)
        #expect(s.enemiesDefeated == wave.totalEnemies)
        #expect(s.isPerfect && s.perfectBonus == config.rules.economy.perfectWaveBonus)
        #expect(s.clearBonus == (wave.clearReward ?? config.rules.economy.defaultWaveClearReward))
        #expect(s.killGold == wave.groups.reduce(0) { $0 + $1.count * config.enemies[$1.enemy]!.goldReward })
        #expect(w.gold == goldAtStart + s.killGold + s.clearBonus + s.perfectBonus)
        #expect(w.phase == .preparation && prepEvent)
        #expect(w.preparationRemaining == config.rules.waveTiming.preparationTime)
        #expect(w.waves.lastSummary == s)
    }

    @Test func leakedWaveHasNoPerfectBonus() {
        let w = heldWorld()
        w.startNextWave()
        finishWave(w)
        let s = try! #require(w.waves.lastSummary)
        #expect(s.enemiesLeaked == config.waves[0].totalEnemies)
        #expect(s.perfectBonus == 0)
        #expect(s.baseDamageTaken == 100 - w.baseHP)
    }

    @Test func bossSpawnsWhileOtherEnemiesAreAlive() {
        let w = heldWorld(gold: 0)
        // Jump to the boss wave by playing the earlier ones undefended is too lossy;
        // instead feed the boss wave definition directly.
        var mgr = WaveManager(waves: [config.waves[4]], timing: config.rules.waveTiming)
        _ = mgr.beginNextWave(earlyStartBonus: 0)
        var spawned: [String] = []
        mgr.updateSpawns(30) { spawned.append($0.enemyID) }
        let bossIndex = try! #require(spawned.firstIndex(of: "alphaBeast"))
        #expect(bossIndex > 0 && bossIndex < spawned.count - 1, "boss arrives mid-wave with escorts")
        _ = w
    }
}

@Suite("Upgrades, selling, repair")
struct ManagementTests {
    @Test func upgradeThroughAllLevels() {
        let w = heldWorld(gold: 10_000)
        w.build(.splash, atSlot: 5)
        let t = try! #require(w.tower(atSlot: 5))
        var invested = config.tower(.splash).buildCost
        var lastDamage = t.stats.damage
        for level in 2...config.tower(.splash).maxLevel {
            let cost = config.tower(.splash).stats(level: level).cost
            let gold0 = w.gold
            #expect(w.upgradeCost(for: t) == cost)
            #expect(w.upgrade(t) == .success(newLevel: level, cost: cost))
            invested += cost
            #expect(t.level == level)
            #expect(w.gold == gold0 - cost)
            #expect(t.totalInvested == invested)
            #expect(t.stats.damage > lastDamage, "each level must be stronger")
            #expect(t.name == config.tower(.splash).stats(level: level).name)
            lastDamage = t.stats.damage
        }
        #expect(w.upgradeCost(for: t) == nil)
        #expect(w.upgrade(t) == .maxLevel)
        #expect(w.stats.upgradesBought == 5)
    }

    @Test func upgradeWithoutEnoughGoldChangesNothing() {
        let w = heldWorld(gold: 100)
        w.build(.heavy, atSlot: 3)
        let t = try! #require(w.tower(atSlot: 3))
        let gold0 = w.gold
        let need = config.tower(.heavy).stats(level: 2).cost
        #expect(w.upgrade(t) == .insufficientGold(needed: need, available: gold0))
        #expect(t.level == 1 && w.gold == gold0 && t.totalInvested == config.tower(.heavy).buildCost)
    }

    @Test func upgradeIsAllowedDuringAWave() {
        let w = heldWorld(gold: 1000)
        w.build(.rapid, atSlot: 3)
        w.startNextWave()
        w.simulate(seconds: 3)
        #expect(w.phase == .waveInProgress)
        let t = w.tower(atSlot: 3)!
        #expect(w.upgrade(t) == .success(newLevel: 2, cost: config.tower(.rapid).stats(level: 2).cost))
    }

    @Test func archetypesScaleDifferently() {
        // Upgrades must preserve each archetype's identity, not apply one formula.
        func growth(_ a: TowerArchetype, _ key: KeyPath<TowerLevelStats, Double>) -> Double {
            let d = config.tower(a)
            return d.stats(level: 5)[keyPath: key] / max(0.0001, d.stats(level: 1)[keyPath: key])
        }
        #expect(growth(.rapid, \.attacksPerSecond) > growth(.heavy, \.attacksPerSecond))
        #expect(growth(.sniper, \.range) > growth(.rapid, \.range))
        #expect(growth(.heavy, \.armorPenetration) > 1)
        #expect(config.tower(.splash).stats(level: 5).aoeRadius > config.tower(.splash).stats(level: 1).aoeRadius)
        let dmgGrowths = TowerArchetype.allCases.map { growth($0, \.damage) }
        #expect(Set(dmgGrowths.map { ($0 * 100).rounded() }).count > 1)
    }

    @Test func sellRefundsAndFreesSlot() {
        let w = heldWorld(gold: 1000)
        w.build(.sniper, atSlot: 7)
        let t = w.tower(atSlot: 7)!
        w.upgrade(t)
        let invested = t.totalInvested
        let gold0 = w.gold
        let expected = Int((Double(invested) * config.rules.economy.sellRefundRatio).rounded(.down))
        #expect(w.sellValue(for: t) == expected)
        #expect(w.sell(t) == .success(refund: expected))
        #expect(w.gold == gold0 + expected)
        #expect(w.tower(atSlot: 7) == nil && w.towers.isEmpty)
        #expect(w.sell(t) == .unknownTower, "can't sell twice")
        #expect(w.upgrade(t) == .unknownTower)
        if case .success = w.build(.heavy, atSlot: 7) {} else { Issue.record("slot should be free again") }
    }

    @Test func sellingTowerWithProjectilesInFlightIsSafe() {
        let w = heldWorld(gold: 1000)
        let slot = config.map.buildSlots.min { w.path.distanceToPath(from: config.map.slotPosition($0)) < w.path.distanceToPath(from: config.map.slotPosition($1)) }!
        w.build(.heavy, atSlot: slot.id)
        let t = w.tower(atSlot: slot.id)!
        let p = w.path
        // Put a bear right next to the tower so it fires immediately.
        var best: CGFloat = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        var d: CGFloat = 0
        while d < p.totalLength { let dd = p.position(at: d).distance(to: t.position); if dd < bestDist { bestDist = dd; best = d }; d += 5 }
        w.debugSpawn("bear", atDistance: best)
        for _ in 0..<30 where !w.projectiles.contains(where: { $0.isActive }) { w.step(dt) }
        #expect(w.projectiles.contains { $0.isActive })
        w.sell(t)
        w.simulate(seconds: 2)
        #expect(w.towers.isEmpty)
    }

    @Test func repairRules() {
        let w = heldWorld(gold: 1000)
        #expect(w.repairBase(optionIndex: 0) == .baseAtFullHealth)
        // Take damage by leaking wave 1.
        w.startNextWave()
        w.simulate(seconds: 2)
        #expect(w.repairBase(optionIndex: 0) == .notInPreparation, "repairs only between waves")
        finishWave(w)
        #expect(w.phase == .preparation)
        let hp0 = w.baseHP
        #expect(hp0 < 100)
        let o = config.rules.repair.options[0]
        let heal = min(o.hp, 100 - hp0)
        let cost = Int((Double(o.cost) * Double(heal) / Double(o.hp)).rounded(.up))
        let gold0 = w.gold
        #expect(w.repairBase(optionIndex: 0) == .success(healed: heal, cost: cost))
        #expect(w.baseHP == hp0 + heal && w.gold == gold0 - cost)
        #expect(w.repairBase(optionIndex: 99) == .invalidOption)
        // Never above max HP.
        while w.baseHP < 100 { _ = w.repairBase(optionIndex: 1) }
        #expect(w.baseHP == 100)
        #expect(w.repairBase(optionIndex: 1) == .baseAtFullHealth)
    }

    @Test func partialRepairCostsLess() {
        let w = heldWorld(gold: 1000)
        w.startNextWave()
        finishWave(w)
        // Heal up to 97 HP, then the 10 HP option only heals 3 and costs 3/10 of the price.
        while w.baseHP < 97 { _ = w.repairBase(optionIndex: 0); if w.baseHP > 97 { break } }
        guard w.baseHP <= 97 else { return }   // already high enough; nothing to assert
        let missing = 100 - w.baseHP
        let q = try! #require(w.repairQuote(optionIndex: 0))
        #expect(q.heal == min(10, missing))
        #expect(q.cost == Int((100.0 * Double(q.heal) / 10).rounded(.up)))
    }

    @Test func repairWithoutGoldFails() {
        let w = heldWorld(gold: 0)
        w.startNextWave()
        finishWave(w)
        w.debugSetGold(5)
        if case .insufficientGold = w.repairBase(optionIndex: 0) {} else { Issue.record("expected insufficient gold") }
        #expect(w.gold == 5)
    }

    @Test func noActionsAfterMatchEnds() {
        let w = heldWorld(gold: 5000)
        w.build(.rapid, atSlot: 1)
        for _ in 0..<10 { w.debugSpawn("alphaBeast", atDistance: w.path.totalLength - 0.1) }
        w.step(dt)
        #expect(w.phase == .defeat)
        let t = w.tower(atSlot: 1)!
        #expect(w.upgrade(t) == .matchOver)
        #expect(w.sell(t) == .matchOver)
        #expect(w.build(.heavy, atSlot: 2) == .matchOver)
        #expect(w.repairBase(optionIndex: 0) == .matchOver)
        #expect(w.startNextWave() == .matchOver)
    }
}

// MARK: - Balance simulations
//
// The difficulty curve (Docs/BALANCE.md) checked with the scripted players in
// BalancePlayer: who survives which phase, on which difficulty. `edtool
// balance` / `balance-summary` print the same runs in full.

private func player(_ prefix: String) -> BalancePlayer {
    BalancePlayer.profiles.first { $0.name.hasPrefix(prefix) }!
}

private func play(_ prefix: String, seed: UInt64 = 3, _ difficulty: Difficulty = .normal,
                  events: Bool = false) -> BalancePlayer.Result {
    player(prefix).play(config: config, seed: seed, options: MatchOptions(difficulty: difficulty, randomEvents: events))
}

/// Mean deepest progress (0…1) over a range of waves.
private func pressure(_ r: BalancePlayer.Result, _ waves: ClosedRange<Int>) -> Double {
    let w = r.waves.filter { waves.contains($0.number) }
    return w.isEmpty ? 1 : w.map(\.deepestProgress).reduce(0, +) / Double(w.count)
}

@Suite("Balance (difficulty curve)")
struct BalanceTests {
    /// A full match: 30 stages of roughly 45–130 s plus preparation.
    static let maxMatchSeconds = 50.0 * 60

    @Test(arguments: [3, 7, 11] as [UInt64])
    func optimisedDefenceWinsNormal(seed: UInt64) {
        let r = play("expert", seed: seed)
        print("BALANCE expert seed \(seed): \(r)")
        #expect(r.phase == .victory)
        #expect(r.bossesDefeated == config.waves.flatMap(\.groups).filter { config.enemies[$0.enemy]!.isBoss }.count)
        #expect(r.baseHP >= 40, "the intended strategy should win with a margin")
        #expect(r.time < Self.maxMatchSeconds)
    }

    @Test(arguments: ["expert", "spread", "focused, no tech", "casual"])
    func openingIsAccessible(profile: String) {
        // Phase 1 (waves 1–4): every reasonable defence holds without losing HP.
        for seed in [3, 7] as [UInt64] {
            let r = play(profile, seed: seed)
            let lost = r.waves.filter { $0.number <= 4 }.map(\.hpLost).reduce(0, +)
            #expect(lost == 0, "\(profile) seed \(seed) lost \(lost) HP in the opening")
        }
    }

    @Test func pressureRisesAfterTheOpening() {
        // For the optimised player the endgame pushes enemies much deeper than the opening.
        let r = play("expert")
        let opening = pressure(r, 1...4), endgame = pressure(r, 17...19), veryHard = pressure(r, 21...25), expert = pressure(r, 26...29)
        print("BALANCE expert pressure: opening \(opening) endgame \(endgame) very hard \(veryHard) expert \(expert)")
        #expect(endgame > opening + 0.1)
        #expect(endgame >= 0.7, "the endgame should push even an optimised defence")
        // Stages 21–30: the last five press harder than the five before them.
        #expect(expert > veryHard + 0.08)
        #expect(expert >= 0.75)
    }

    @Test func averagePlayersFallInTheHardPhases() {
        // Casual and no-tech players get through phases 1–3 and fall in phase 4–5 (waves 13–20);
        // nobody falls before wave 12 or exactly at a phase boundary by accident.
        for prefix in ["casual", "focused, no tech", "spread"] {
            for seed in [3, 7] as [UInt64] {
                let r = play(prefix, seed: seed)
                print("BALANCE \(prefix) seed \(seed): \(r)")
                #expect(r.phase == .defeat, "\(prefix) should not win Normal")
                #expect(r.wavesCleared >= 12, "\(prefix) seed \(seed) fell too early: \(r)")
            }
        }
        // Spreading thin with tech still gets into phase 4's end.
        #expect(play("spread").wavesCleared >= 15)
    }

    @Test func technologyMatters() {
        let tech = play("expert"), noTech = play("focused, no tech")
        print("BALANCE tech \(tech) | no tech \(noTech)")
        #expect(tech.phase == .victory)
        #expect(noTech.phase == .defeat)
        #expect(tech.techs >= 8)
    }

    @Test func noSingleTowerTypeWins() {
        for t in TowerArchetype.allCases {
            let r = BalancePlayer(name: "mono", plan: BalancePlayer.monoPlan(t), maxTowers: 8).play(config: config)
            print("BALANCE only \(t): \(r)")
            #expect(r.phase == .defeat, "a defence of only \(t) towers should not win Normal")
        }
        // Without flying-capable towers, ground-only defences fall as soon as the air waves start.
        let splash = BalancePlayer(name: "mono", plan: BalancePlayer.monoPlan(.splash), maxTowers: 8).play(config: config)
        #expect(splash.wavesCleared <= 9)
    }

    @Test func passivePlayerLoses() {
        let r = play("passive")
        print("BALANCE passive: \(r)")
        #expect(r.phase == .defeat)
        #expect(r.wavesCleared < 5)
    }

    @Test func upgradesAreWorthBuying() {
        // The same 4 towers get much further when evolved.
        let noUp = BalancePlayer(name: "4 no upgrades", plan: BalancePlayer.goodPlan, maxTowers: 4, upgrades: false,
                                 repairs: false, research: false).play(config: config)
        let up = BalancePlayer(name: "4 upgrades", plan: BalancePlayer.goodPlan, maxTowers: 4, repairs: false,
                               research: false).play(config: config)
        print("BALANCE 4 towers: no upgrades \(noUp) | upgrades \(up)")
        #expect(noUp.phase == .defeat)
        #expect(up.wavesCleared >= noUp.wavesCleared + 4)
    }

    @Test func levelOneSpamCannotWin() {
        let r = play("L1 spam")
        print("BALANCE L1 spam: \(r)")
        #expect(r.phase == .defeat)
        #expect(r.wavesCleared <= 10)
    }

    @Test func easyLetsLearnersFinish() {
        for prefix in ["casual", "focused, no tech", "spread"] {
            let r = play(prefix, .easy)
            print("BALANCE easy \(prefix): \(r)")
            #expect(r.phase == .victory, "\(prefix) should be able to finish Easy")
        }
    }

    @Test func hardIsHarderButBeatable() {
        let normal = play("expert"), hard = play("expert", .hard)
        print("BALANCE expert normal \(normal) | hard \(hard)")
        #expect(hard.phase == .victory, "an optimised defence can win Hard")
        // Base health lost over the match (end health alone misleads: Stronger Walls raises the maximum).
        let lostNormal = normal.waves.map(\.hpLost).reduce(0, +), lostHard = hard.waves.map(\.hpLost).reduce(0, +)
        print("BALANCE expert base health lost: normal \(lostNormal) | hard \(lostHard)")
        #expect(lostHard >= lostNormal)
        #expect(play("casual", .hard).wavesCleared <= play("casual").wavesCleared)
    }

    @Test(arguments: [Difficulty.easy, .normal, .hard])
    func randomEventsNeverCauseAnUnavoidableLoss(difficulty: Difficulty) {
        // With events on, the optimised player still wins on every difficulty and seed tried.
        for seed in [5, 13, 29] as [UInt64] {
            let r = play("expert", seed: seed, difficulty, events: true)
            #expect(r.phase == .victory, "\(difficulty) seed \(seed): \(r)")
        }
    }
}
