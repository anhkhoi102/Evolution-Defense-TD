import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

@Suite("Difficulty curve & new enemy mechanics")
struct DifficultyCurveTests {

    // MARK: Progression table

    @Test func progressionTableIsWellFormed() {
        let phases = config.rules.progression ?? []
        #expect(phases.count == 5, "five phases: learning, strategic, tactical, advanced, endgame")
        #expect(phases.first?.fromWave == 1)
        #expect(phases.map(\.fromWave) == phases.map(\.fromWave).sorted(), "phases are in wave order")
        // Phase 1 is the authored baseline: the opening plays exactly what enemies.json / waves.json say.
        #expect(phases.first == ProgressionPhase(name: phases.first!.name, fromWave: 1))
        // Later phases only get tougher and pay less.
        for (a, b) in zip(phases, phases.dropFirst()) {
            #expect(b.enemyHP >= a.enemyHP)
            #expect(b.killReward <= a.killReward && b.clearReward <= a.clearReward)
        }
        for p in phases {
            for m in [p.enemyHP, p.enemySpeed, p.spawnInterval, p.enemyCount, p.killReward, p.clearReward] { #expect(m > 0) }
        }
    }

    @Test func phaseLookupAndCurveStrength() {
        let rules = config.rules
        #expect(rules.phase(forWave: 1).name == "Learning")
        #expect(rules.phase(forWave: 4).name == "Learning")
        #expect(rules.phase(forWave: 5).name == "Strategic")
        #expect(rules.phase(forWave: 13).name == "Advanced")
        #expect(rules.phase(forWave: 20).name == "Endgame")
        let full = rules.phase(forWave: 20), half = rules.phase(forWave: 20, curve: 0.5)
        #expect(abs((half.enemyHP - 1) - (full.enemyHP - 1) / 2) < 1e-9)
        #expect(abs((half.killReward - 1) - (full.killReward - 1) / 2) < 1e-9)
        #expect(rules.phase(forWave: 20, curve: 0) == ProgressionPhase(name: full.name, fromWave: full.fromWave))
    }

    @Test func waveCountsScaleButBossesStayAlone() {
        let planned = config.progressionWaves()
        #expect(planned.count == config.waves.count)
        for (raw, w) in zip(config.waves, planned) {
            let p = config.rules.phase(forWave: raw.number)
            for (g0, g) in zip(raw.groups, w.groups) {
                if config.enemies[g0.enemy]!.isBoss {
                    #expect(g.count == g0.count, "bosses are never multiplied")
                } else {
                    #expect(g.count == max(1, Int((Double(g0.count) * p.enemyCount).rounded())))
                }
                #expect(abs(g.interval - g0.interval * p.spawnInterval) < 1e-9)
            }
        }
    }

    @Test func laterPhasesScaleRegularEnemiesNotBosses() {
        let w = GameWorld(config: config, seed: 1)
        w.debugSkipToWave(18)
        w.startNextWave()
        w.step(dt)
        let p = config.rules.phase(forWave: 18)
        #expect(w.activePhase.name == "Endgame")
        let scout = w.debugSpawn("scoutRobot")!
        #expect(abs(scout.maxHP - config.enemies["scoutRobot"]!.hp * p.enemyHP) < 1e-6)
        let boss = w.debugSpawn("titanWarMachine")!
        #expect(boss.maxHP == config.enemies["titanWarMachine"]!.hp)
    }

    @Test func difficultyModesScaleTheCurve() {
        #expect(config.difficulty(.easy).curve! < 1)
        #expect((config.difficulty(.normal).curve ?? 1) == 1)
        let easy = GameWorld(config: config, options: MatchOptions(difficulty: .easy, randomEvents: false))
        let normal = GameWorld(config: config, options: MatchOptions(difficulty: .normal, randomEvents: false))
        // Wave 20's scout group is smaller on Easy (gentler curve).
        let scouts = { (w: GameWorld) in w.waves.waves[19].groups.first { $0.enemy == "scoutRobot" }!.count }
        #expect(scouts(easy) < scouts(normal))
    }

    // MARK: Elites

    @Test func elitesAreToughWorthMoreAndMarked() {
        let w = GameWorld(config: config, seed: 2)
        let el = config.rules.elite!
        let normal = w.debugSpawn("armoredBeast")!
        let elite = w.spawnEnemy("armoredBeast", modifiers: SpawnModifiers(elite: true))!
        #expect(!normal.isElite && elite.isElite)
        #expect(abs(elite.maxHP - normal.maxHP * el.hp) < 1e-6)
        #expect(abs(elite.armor - (normal.armor + el.armorBonus)) < 1e-9)
        #expect(abs(elite.baseSpeed - normal.baseSpeed * el.speed) < 1e-9)
        #expect(abs(elite.rewardMultiplier - normal.rewardMultiplier * el.reward) < 1e-9)
        // Bosses ignore the elite flag.
        let boss = w.spawnEnemy("alphaBeast", modifiers: SpawnModifiers(elite: true))!
        #expect(!boss.isElite && boss.maxHP == config.enemies["alphaBeast"]!.hp)
    }

    @Test func eliteGroupsSpawnElites() {
        // Wave 6 has an elite Giant Wolf group: elites appear during the wave.
        #expect(config.waves[5].groups.contains { $0.elite == true })
        let w = GameWorld(config: config, seed: 4)
        w.debugSkipToWave(6)
        w.startNextWave()
        var elites = 0
        for _ in 0..<(60 * 30) {
            w.step(dt)
            w.drainEvents { e in if case .enemySpawned(let x) = e, x.isElite { elites += 1 } }
        }
        #expect(elites == w.waves.waves[5].groups.filter { $0.elite == true }.reduce(0) { $0 + $1.count })
    }

    // MARK: Healer

    private func healerSetup() -> (GameWorld, Enemy, HealAuraAbility) {
        let w = GameWorld(config: config, seed: 9)
        w.holdPreparationCountdown = true
        let troll = w.debugSpawn("troll", atDistance: 600)!
        return (w, troll, config.enemies["troll"]!.baseAbilities.healAura!)
    }

    private func wound(_ e: Enemy, to fraction: Double) { e.hp = e.maxHP * fraction }

    @Test func trollHealsNearbyAlliesNotItself() {
        let (w, troll, h) = healerSetup()
        let near = w.debugSpawn("armoredBeast", atDistance: 600)!
        let far = w.debugSpawn("armoredBeast", atDistance: 600 + CGFloat(h.radius) * 3)!
        w.step(dt)
        wound(near, to: 0.5); wound(far, to: 0.5); wound(troll, to: 0.5)
        troll.lastDamageTime = 0        // keep the troll's own regeneration out of the picture
        var pulses = 0
        for _ in 0..<Int(h.interval / dt * 1.1) {
            w.step(dt)
            w.drainEvents { e in if case .enemiesHealed(let by, _, let n, _) = e, by === troll { pulses += 1; #expect(n >= 1) } }
            troll.lastDamageTime = w.time
        }
        #expect(pulses >= 1)
        #expect(near.hp > near.maxHP * 0.5)
        #expect(far.hp == far.maxHP * 0.5, "out of range")
        #expect(troll.hp == troll.maxHP * 0.5, "a healer never heals itself")
    }

    @Test func burningEnemiesAndBossesCannotBeHealed() {
        let (w, troll, h) = healerSetup()
        let burning = w.debugSpawn("armoredBeast", atDistance: 600)!
        let boss = w.debugSpawn("alphaBeast", atDistance: 600)!
        w.step(dt)
        wound(burning, to: 0.5); wound(boss, to: 0.5)
        for _ in 0..<Int(h.interval / dt * 1.1) {
            burning.burnDPS = 0.0001; burning.burnUntil = w.time + 1
            w.step(dt)
            troll.lastDamageTime = w.time
        }
        #expect(burning.hp <= burning.maxHP * 0.5 + 1e-6, "fire stops healing")
        #expect(boss.hp <= boss.maxHP * 0.5 + 1e-6, "bosses are never healed")
    }

    @Test func healsFromSeveralHealersDoNotStack() {
        let (w, _, h) = healerSetup()
        _ = w.debugSpawn("troll", atDistance: 600)       // a second healer on the same spot
        let target = w.debugSpawn("armoredBeast", atDistance: 600)!
        w.step(dt)
        wound(target, to: 0.2)
        for _ in 0..<Int(h.interval / dt * 1.05) { w.step(dt) }
        let gained = target.hp / target.maxHP - 0.2
        #expect(gained > 0)
        #expect(gained <= h.fraction + 1e-6, "two healers in range still heal once per interval (gained \(gained))")
    }
}
