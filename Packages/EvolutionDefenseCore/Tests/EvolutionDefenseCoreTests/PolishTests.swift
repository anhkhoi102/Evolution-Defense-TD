import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

private func world(_ options: MatchOptions = MatchOptions(randomEvents: false), seed: UInt64 = 21) -> GameWorld {
    let w = GameWorld(config: config, options: options, seed: seed)
    w.holdPreparationCountdown = true
    return w
}

/// Clears the running wave instantly (kills everything as it spawns).
private func clearWave(_ w: GameWorld) {
    while w.phase == .waveInProgress {
        w.step(dt)
        for e in w.enemies where e.isActive { w.applyDamage(to: e, raw: 1e7, penetration: 1e6, source: nil) }
    }
}

private func drain(_ w: GameWorld) -> [GameEvent] { var o: [GameEvent] = []; w.drainEvents { o.append($0) }; return o }

// MARK: - Difficulty

@Suite("Difficulty")
struct DifficultyTests {
    @Test func multipliersApply() {
        let easy = world(MatchOptions(difficulty: .easy, randomEvents: false))
        let hard = world(MatchOptions(difficulty: .hard, randomEvents: false))
        let de = config.difficulty(.easy), dh = config.difficulty(.hard)
        #expect(easy.gold == de.startingGold && hard.gold == dh.startingGold)
        #expect(easy.research == de.startingResearch)
        let a = easy.debugSpawn("bear", atDistance: 100)!, b = hard.debugSpawn("bear", atDistance: 100)!
        #expect(abs(a.maxHP - a.definition.hp * de.enemyHP) < 0.001)
        #expect(abs(b.maxHP - b.definition.hp * dh.enemyHP) < 0.001)
        #expect(abs(a.baseSpeed - 40 * de.enemySpeed) < 0.001)
        let g0 = easy.gold
        easy.applyDamage(to: a, raw: 1e6, penetration: 1e6, source: nil)
        #expect(easy.gold == g0 + Int((14 * de.goldMultiplier).rounded()))
        if let p = de.preparationTime {
            easy.startNextWave(); clearWave(easy)
            #expect(easy.preparationRemaining == p)
        }
    }

    @Test func everyDifficultyIsDefined() {
        for d in Difficulty.allCases { #expect(config.difficulties.contains { $0.id == d }) }
        #expect(Difficulty.easy < .normal && .normal < .hard)
    }
}

// MARK: - Random events

@Suite("Random events")
struct RandomEventTests {
    @Test func noEventsWhenDisabled() {
        let w = world()
        for _ in 0..<8 { w.startNextWave(); clearWave(w) }
        #expect(w.stats.randomEvents == 0 && w.activeEvent == nil)
    }

    @Test func eventsEveryThreeToFourWaves() {
        let w = world(MatchOptions(randomEvents: true))
        w.debugSetGold(100_000)
        for s in config.map.buildSlots.prefix(6) { w.build(.sniper, atSlot: s.id) }
        var eventWaves: [Int] = []
        while w.waveNumber < config.waves.count - 1 {
            w.startNextWave(); clearWave(w)
            for e in drain(w) { if case .randomEvent = e { eventWaves.append(w.waveNumber) } }
        }
        #expect(eventWaves.first == config.rules.randomEvents.firstAfterWave)
        for (a, b) in zip(eventWaves, eventWaves.dropFirst()) { #expect((3...4).contains(b - a), "\(eventWaves)") }
        #expect(eventWaves.count >= 4)
        #expect(!eventWaves.contains(config.waves.count), "no event after the last wave")
    }

    @Test func eventsAreReproducibleForASeed() {
        func sequence() -> [String] {
            let w = world(MatchOptions(randomEvents: true), seed: 99)
            w.debugSetGold(100_000)
            for s in config.map.buildSlots.prefix(4) { w.build(.heavy, atSlot: s.id) }
            var ids: [String] = []
            for _ in 0..<15 { w.startNextWave(); clearWave(w); for e in drain(w) { if case .randomEvent(let d, _) = e { ids.append(d.id) } } }
            return ids
        }
        #expect(sequence() == sequence())
    }

    @Test func resourceBonusAndTechnologyBoost() {
        let w = world()
        let g0 = w.gold
        #expect(w.debugTriggerEvent("resourceBonus"))
        let def = config.event("resourceBonus")!
        #expect(w.gold == g0 + Int(def.value + (def.perWave ?? 0) * 1))
        #expect(w.debugTriggerEvent("technologyBoost"))
        let arrows = config.tech("improvedArrows")!
        #expect(w.researchCost(arrows) == max(1, arrows.cost - Int(config.event("technologyBoost")!.value)))
        w.debugSetResearch(10)
        #expect(w.research("improvedArrows") == .success(cost: w.researchCost(arrows) == 0 ? 1 : max(1, arrows.cost - 2)))
        #expect(w.researchDiscount == 0, "discount is used up")
        #expect(w.research == 10 - max(1, arrows.cost - 2))
    }

    @Test func mutationBuffsNextWaveOnly() {
        let w = world()
        #expect(w.debugTriggerEvent("enemyMutation"))
        let m = config.event("enemyMutation")!
        w.startNextWave()
        w.step(dt)
        let e = w.enemies.first!
        #expect(abs(e.maxHP - e.definition.hp * (1 + m.value)) < 0.001)
        #expect(abs(e.rewardMultiplier - (1 + m.goldBonus!)) < 0.001)
        clearWave(w)
        #expect(w.activeEvent == nil)
        w.startNextWave(); w.step(dt)
        let e2 = w.enemies.first!
        #expect(e2.maxHP == e2.definition.hp, "mutation lasted one wave")
    }

    @Test func breakdownSlowsOneTowerForOneWave() {
        let w = world()
        w.debugSetGold(1000)
        w.build(.rapid, atSlot: 4)
        let t = w.tower(atSlot: 4)!
        let aps = t.stats.attacksPerSecond
        #expect(w.debugTriggerEvent("mechanicalBreakdown"))
        #expect(abs(t.stats.attacksPerSecond - aps * 0.5) < 0.0001)
        w.upgrade(t)
        #expect(abs(t.stats.attacksPerSecond - config.tower(.rapid).stats(level: 2).attacksPerSecond * 0.5) < 0.0001,
                "still broken after an upgrade")
        w.startNextWave(); clearWave(w)
        #expect(abs(t.stats.attacksPerSecond - config.tower(.rapid).stats(level: 2).attacksPerSecond) < 0.0001)
    }

    @Test func breakdownNeedsATower() {
        let w = world()
        #expect(!w.debugTriggerEvent("mechanicalBreakdown"), "no towers → event can't happen")
    }

    @Test func reinforcementIsTemporary() {
        let w = world()
        w.debugSkipToWave(6)
        #expect(w.debugTriggerEvent("reinforcement"))
        let t = try! #require(w.towers.first { $0.isTemporary })
        #expect(t.level == min(5, w.currentEra.rawValue + 1))
        #expect(w.sell(t) == .notAllowed && w.upgrade(t) == .notAllowed)
        #expect(w.build(.splash, atSlot: t.slotID) == .slotOccupied)
        _ = drain(w)
        w.startNextWave(); clearWave(w)
        #expect(!w.towers.contains { $0 === t })
        #expect(w.tower(atSlot: t.slotID) == nil)
        #expect(drain(w).contains { if case .towerRemoved(let r) = $0 { return r === t } else { return false } })
    }
}

// MARK: - Achievements

@Suite("Achievements")
struct AchievementTests {
    @Test func progressAchievements() {
        let w = world()
        w.debugSetGold(100_000)
        var unlocked = Set<String>()
        func check() -> [String] {
            let n = AchievementEvaluator.newlyMet(in: w, unlocked: unlocked).map(\.id)
            unlocked.formUnion(n); return n
        }
        #expect(check().isEmpty)
        w.build(.sniper, atSlot: 3)
        let t = w.tower(atSlot: 3)!
        while case .success = w.upgrade(t) {}
        #expect(check() == ["fullyEvolved"])
        for (a, s) in [(TowerArchetype.splash, 5), (.heavy, 9), (.rapid, 12)] {
            w.build(a, atSlot: s); let x = w.tower(atSlot: s)!; while case .success = w.upgrade(x) {}
        }
        #expect(check() == ["arsenal"])
        #expect(check().isEmpty, "never reported twice")
    }

    @Test func winAchievementsRespectDifficulty() {
        let w = world(MatchOptions(difficulty: .easy, randomEvents: false))
        w.debugSkipToWave(w.totalWaves)
        w.startNextWave(); clearWave(w)
        #expect(w.phase == .victory)
        let met = Set(AchievementEvaluator.newlyMet(in: w, unlocked: []).map(\.id))
        #expect(met.contains("survivor"))
        #expect(!met.contains("veteran") && !met.contains("againstAllOdds"))
        #expect(met.contains("oldWays") && met.contains("unbreached") && met.contains("machineBreaker"))
    }
}

// MARK: - Checkpoints & profile

@Suite("Save system")
struct SaveTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("evo-test-\(UUID().uuidString)", isDirectory: true)
    }

    /// Plays a few waves with a fixed defence and returns the world in preparation.
    private func playedWorld(_ options: MatchOptions) -> GameWorld {
        let w = GameWorld(config: config, options: options, seed: 77)
        w.holdPreparationCountdown = true
        w.debugSetGold(20_000)
        for (s, a) in [(5, TowerArchetype.splash), (3, .sniper), (9, .heavy), (12, .rapid), (4, .rapid), (10, .sniper)] {
            w.build(a, atSlot: s)
            let t = w.tower(atSlot: s)!
            while t.level < 3, case .success = w.upgrade(t) {}
        }
        w.setTargeting(.weakest, for: w.tower(atSlot: 3)!)
        w.debugSetResearch(10)
        w.research("improvedArrows")
        for _ in 0..<6 {
            w.startNextWave()
            while w.phase == .waveInProgress { w.step(dt) }
        }
        return w
    }

    @Test func checkpointRoundTripsThroughJSON() throws {
        let w = playedWorld(MatchOptions(difficulty: .hard, randomEvents: true))
        #expect(w.phase == .preparation)
        let cp = try #require(w.makeCheckpoint(now: Date(timeIntervalSince1970: 1_000_000)))
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(MatchCheckpoint.self, from: try enc.encode(cp))
        #expect(back == cp)

        let r = try GameWorld(config: config, checkpoint: back)
        #expect(r.phase == .preparation)
        #expect(r.options == w.options)
        #expect(r.waveNumber == w.waveNumber && r.gold == w.gold && r.research == w.research)
        #expect(r.baseHP == w.baseHP && r.maxBaseHP == w.maxBaseHP)
        #expect(r.stats == w.stats && r.researchedTechs == w.researchedTechs)
        #expect(r.towers.count == w.towers.count)
        for t in w.towers {
            let rt = try #require(r.tower(atSlot: t.slotID))
            #expect(rt.level == t.level && rt.targeting == t.targeting && rt.totalInvested == t.totalInvested)
            #expect(rt.stats == t.stats, "tech bonuses re-applied")
        }
        #expect(r.preparationRemaining == config.difficulty(.hard).preparationTime)
        #expect(r.activeEvent == w.activeEvent && r.nextEventWave == w.nextEventWave)
    }

    @Test func resumedMatchPlaysOutIdentically() throws {
        let opts = MatchOptions(difficulty: .normal, randomEvents: true)
        let a = playedWorld(opts)
        let b = try GameWorld(config: config, checkpoint: a.makeCheckpoint()!)
        b.holdPreparationCountdown = true
        for w in [a, b] {
            for _ in 0..<5 where !w.phase.isOver {
                w.startNextWave()
                while w.phase == .waveInProgress { w.step(dt) }
            }
        }
        #expect(a.waveNumber == b.waveNumber)
        #expect(a.gold == b.gold && a.baseHP == b.baseHP && a.stats == b.stats)
    }

    @Test func checkpointOnlyBetweenWaves() {
        let w = world()
        #expect(w.makeCheckpoint() != nil)
        w.startNextWave()
        #expect(w.makeCheckpoint() == nil)
    }

    @Test func rejectsBadCheckpoints() throws {
        var cp = world().makeCheckpoint()!
        cp.version = 99
        #expect(throws: CheckpointError.unsupportedVersion(99)) { try GameWorld(config: config, checkpoint: cp) }
        cp.version = MatchCheckpoint.currentVersion
        cp.waveNumber = 500
        #expect(throws: CheckpointError.self) { try GameWorld(config: config, checkpoint: cp) }
    }

    @Test func profileStoreSavesLoadsAndSurvivesCorruption() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        #expect(store.loadProfile() == PlayerProfile(), "missing file → defaults")
        var p = PlayerProfile()
        p.settings.musicVolume = 0.3
        p.settings.difficulty = .hard
        p.achievements["survivor"] = Date(timeIntervalSince1970: 1_700_000_000)
        try store.save(p)
        #expect(store.loadProfile() == p)

        let w = playedWorld(MatchOptions())
        try store.save(w.makeCheckpoint()!)
        #expect(store.loadCheckpoint()?.waveNumber == w.waveNumber)
        store.deleteCheckpoint()
        #expect(store.loadCheckpoint() == nil)

        try Data("{ not json".utf8).write(to: store.profileURL)
        #expect(store.loadProfile() == PlayerProfile())
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("profile.corrupt.json").path))
    }

    @Test func olderProfilesFillInDefaults() throws {
        let json = #"{ "settings": { "musicVolume": 0.2 }, "totalKills": 12 }"#
        let p = try JSONDecoder().decode(PlayerProfile.self, from: Data(json.utf8))
        #expect(p.settings.musicVolume == 0.2)
        #expect(p.settings.effectsVolume == GameSettings().effectsVolume)
        #expect(p.totalKills == 12 && p.achievements.isEmpty)
    }

    @Test func recordsTrackBestResults() {
        var p = PlayerProfile()
        let w = world(MatchOptions(difficulty: .hard, randomEvents: false))
        w.debugSkipToWave(w.totalWaves)
        w.startNextWave(); clearWave(w)
        p.recordMatchEnd(w)
        let r = p.record(.hard)
        #expect(r.matches == 1 && r.victories == 1 && r.bestBaseHP == w.baseHP && r.bestTime == w.time)
        #expect(p.record(.easy).matches == 0)
        let new = p.unlockAchievements(in: w)
        #expect(new.contains { $0.id == "againstAllOdds" })
        #expect(p.unlockAchievements(in: w).isEmpty)
    }
}
