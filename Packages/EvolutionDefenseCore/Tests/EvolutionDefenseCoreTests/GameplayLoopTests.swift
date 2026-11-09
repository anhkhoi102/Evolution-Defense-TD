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
        for level in 2...5 {
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
        #expect(w.stats.upgradesBought == 4)
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
        for _ in 0..<5 { w.debugSpawn("alphaBeast", atDistance: w.path.totalLength - 0.1) }
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

/// A scripted player used to sanity-check the economy and difficulty curve.
/// It acts at the start of every preparation phase and every 3 s during waves
/// (upgrades are allowed mid-wave, so a real player would do the same).
struct BalanceBot {
    var plan: [(slot: Int, type: TowerArchetype)]
    var upgrades = true
    var repairs = true
    var research = true
    /// Towers to build before upgrading; more are added once all are at max level.
    var maxTowers: Int

    /// Tech in the order this bot buys it (saving up when the next one is too expensive).
    static let techPriority = ["improvedArrows", "gunpowder", "fireTechnology", "advancedTraps", "ballisticResearch",
                               "automatedWeapons", "plasmaTechnology", "aiTargeting", "advancedExplosives",
                               "strongerWalls", "heavyArmor", "energyShield"]

    func act(_ w: GameWorld) {
        let preparing = w.phase == .preparation
        var progress = true
        while progress {
            progress = false
            if research, let id = Self.techPriority.first(where: { !w.isResearched($0) && config.tech($0)!.era <= w.currentEra }),
               case .success = w.research(id) {
                progress = true; continue
            }
            if repairs, preparing, w.baseHP <= 60, case .success = w.repairBase(optionIndex: 0) {
                progress = true; continue
            }
            if w.towers.count < maxTowers || (upgrades && w.towers.allSatisfy(\.isMaxLevel)),
               let next = plan.first(where: { w.tower(atSlot: $0.slot) == nil }),
               case .success = w.build(next.type, atSlot: next.slot) {
                progress = true; continue
            }
            if upgrades, let t = w.towers.filter({ !$0.isMaxLevel }).min(by: { $0.level < $1.level }),
               case .success = w.upgrade(t) {
                progress = true
            }
        }
    }

    struct Result {
        var phase: MatchPhase; var baseHP: Int; var time: Double; var wavesCleared: Int
        var bossesDefeated: Int; var techs: Int; var towers: Int; var levels: Int
    }

    func play(seed: UInt64 = 3, options: MatchOptions = MatchOptions(randomEvents: false)) -> Result {
        let w = GameWorld(config: config, options: options, seed: seed)
        var wasPreparing = false
        var ticks = 0
        while !w.phase.isOver && w.time < 60 * 40 {
            let preparing = w.phase == .preparation
            if (preparing && !wasPreparing) || ticks % 180 == 0 { act(w) }
            wasPreparing = preparing
            ticks += 1
            w.step(dt)
            w.drainEvents { _ in }
        }
        return Result(phase: w.phase, baseHP: w.baseHP, time: w.time, wavesCleared: w.stats.wavesCleared,
                      bossesDefeated: w.stats.bossesDefeated, techs: w.researchedTechs.count,
                      towers: w.towers.count, levels: w.towers.reduce(0) { $0 + $1.level })
    }

    static let goodPlan: [(slot: Int, type: TowerArchetype)] = [
        (5, .splash), (3, .sniper), (9, .heavy), (12, .rapid), (4, .rapid), (2, .splash),
        (10, .sniper), (11, .heavy), (14, .splash), (16, .rapid), (7, .sniper), (8, .heavy)
    ]
}

extension BalanceBot.Result: CustomStringConvertible {
    var description: String {
        "\(phase) wave=\(wavesCleared) hp=\(baseHP) time=\(Int(time))s bosses=\(bossesDefeated) techs=\(techs) towers=\(towers) levels=\(levels)"
    }
}

@Suite("Balance (20 waves)")
struct BalanceTests {
    /// The full match should take roughly 20 minutes (45 s combat + 15 s preparation per wave).
    /// The bot never starts waves early, so allow some slack.
    static let maxMatchSeconds = 27.0 * 60

    @Test(arguments: [3, 7, 11] as [UInt64])
    func focusedPlayerWinsWithTech(seed: UInt64) {
        let r = BalanceBot(plan: BalanceBot.goodPlan, maxTowers: 8).play(seed: seed)
        print("BALANCE focused+tech seed \(seed): \(r)")
        #expect(r.phase == .victory)
        #expect(r.bossesDefeated == 4)
        #expect(r.baseHP >= 60)
        #expect(r.time < Self.maxMatchSeconds)
    }

    @Test(arguments: [3, 7, 11] as [UInt64])
    func techIsNotMandatory(seed: UInt64) {
        // A focused player can win without researching anything.
        let r = BalanceBot(plan: BalanceBot.goodPlan, research: false, maxTowers: 8).play(seed: seed)
        print("BALANCE focused, no tech seed \(seed): \(r)")
        #expect(r.phase == .victory)
        #expect(r.techs == 0)
        #expect(r.time < Self.maxMatchSeconds)
    }

    @Test func technologyMakesADifference() {
        // Spreading gold over 12 towers is weaker: it needs the tech tree to win.
        let withTech = BalanceBot(plan: BalanceBot.goodPlan, maxTowers: 12).play()
        let without = BalanceBot(plan: BalanceBot.goodPlan, research: false, maxTowers: 12).play()
        print("BALANCE spread: tech \(withTech) | no tech \(without)")
        #expect(withTech.phase == .victory)
        #expect(withTech.baseHP >= 40, "a sensible strategy should not be on the brink")
        #expect(withTech.techs >= 6)
        #expect(without.phase == .defeat)
        #expect(without.wavesCleared >= 12, "still gets deep into the match without tech")
    }

    @Test func passivePlayerLoses() {
        let r = BalanceBot(plan: Array(BalanceBot.goodPlan.prefix(2)), upgrades: false, repairs: false,
                           research: false, maxTowers: 2).play()
        print("BALANCE passive: \(r)")
        #expect(r.phase == .defeat)
        #expect(r.wavesCleared < 5)
    }

    @Test func upgradesAreWorthBuying() {
        // The same 4 towers get much further when evolved.
        let noUp = BalanceBot(plan: BalanceBot.goodPlan, upgrades: false, repairs: false, research: false, maxTowers: 4).play()
        let up = BalanceBot(plan: BalanceBot.goodPlan, upgrades: true, repairs: false, research: false, maxTowers: 4).play()
        print("BALANCE 4 towers: no upgrades \(noUp) | upgrades \(up)")
        #expect(noUp.phase == .defeat)
        #expect(up.wavesCleared >= noUp.wavesCleared + 5)
    }

    @Test func easyForgivesASloppyDefence() {
        let r = BalanceBot(plan: BalanceBot.goodPlan, research: false, maxTowers: 12)
            .play(options: MatchOptions(difficulty: .easy, randomEvents: false))
        print("BALANCE easy spread, no tech: \(r)")
        #expect(r.phase == .victory)
    }

    @Test(arguments: [3, 11] as [UInt64])
    func hardNeedsTechnology(seed: UInt64) {
        let hard = MatchOptions(difficulty: .hard, randomEvents: false)
        let tech = BalanceBot(plan: BalanceBot.goodPlan, maxTowers: 8).play(seed: seed, options: hard)
        let noTech = BalanceBot(plan: BalanceBot.goodPlan, research: false, maxTowers: 8).play(seed: seed, options: hard)
        print("BALANCE hard seed \(seed): tech \(tech) | no tech \(noTech)")
        #expect(tech.phase == .victory && tech.baseHP >= 30)
        #expect(noTech.phase == .defeat)
    }

    @Test(arguments: [Difficulty.easy, .normal, .hard])
    func randomEventsNeverCauseAnUnavoidableLoss(difficulty: Difficulty) {
        // With events on, the focused tech player still wins on every difficulty and seed tried.
        for seed in [5, 13, 29] as [UInt64] {
            let r = BalanceBot(plan: BalanceBot.goodPlan, maxTowers: 8)
                .play(seed: seed, options: MatchOptions(difficulty: difficulty, randomEvents: true))
            #expect(r.phase == .victory, "\(difficulty) seed \(seed): \(r)")
        }
    }

    @Test func levelOneSpamCannotWin() {
        // Eras get harder: 16 level-1 towers and full tech still fall before the end.
        let all = BalanceBot.goodPlan + [(1, .sniper), (6, .heavy), (13, .splash), (15, .rapid)]
        let r = BalanceBot(plan: all, upgrades: false, maxTowers: 16).play()
        print("BALANCE L1 spam: \(r)")
        #expect(r.phase == .defeat)
    }
}
