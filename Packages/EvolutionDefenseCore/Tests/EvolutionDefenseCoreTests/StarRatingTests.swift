import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

/// Clears the running stage instantly (kills everything as it spawns).
private func clearStage(_ w: GameWorld) {
    var guardTicks = 0
    while w.phase == .waveInProgress && guardTicks < 60 * 400 {
        for e in w.enemies where e.isActive { w.applyDamage(to: e, raw: 1e9, penetration: 1e9, source: nil, ignoreDefences: true) }
        w.step(dt); guardTicks += 1
    }
}

/// A short campaign (the first `stages` stages) so a whole match can be won in a test.
private func shortConfig(stages: Int = 3) -> GameConfiguration {
    var c = config
    c.waves = Array(c.waves.prefix(stages))
    return c
}

/// Plays a short match to victory, letting `leaks` (enemy ids) reach the base in stage 1.
private func winMatch(leaks: [String] = [], seed: UInt64 = 3) -> GameWorld {
    let w = GameWorld(config: shortConfig(), options: MatchOptions(randomEvents: false), seed: seed)
    var first = true
    while !w.phase.isOver {
        w.startNextWave()
        if first { for id in leaks { _ = w.debugSpawn(id, atDistance: w.path.totalLength - 0.1) }; w.step(dt); first = false }
        clearStage(w)
    }
    return w
}

@Suite("Star rating & campaign progress")
struct StarRatingTests {
    @Test func thresholdsComeFromConfiguration() {
        let s = config.rules.stars!
        let three = Int(100 * s.threeStarMaxDamageFraction), two = Int(100 * s.twoStarMaxDamageFraction)
        #expect(three < two)
        #expect(s.stars(damage: 0, maxBaseHP: 100) == 3 && s.stars(damage: three, maxBaseHP: 100) == 3)
        #expect(s.stars(damage: three + 1, maxBaseHP: 100) == 2 && s.stars(damage: two, maxBaseHP: 100) == 2)
        #expect(s.stars(damage: two + 1, maxBaseHP: 100) == 1 && s.stars(damage: 99, maxBaseHP: 100) == 1)
        // Custom thresholds are honoured.
        let strict = StarRatingConfig(threeStarMaxDamageFraction: 0, twoStarMaxDamageFraction: 0.05)
        #expect(strict.stars(damage: 0, maxBaseHP: 100) == 3 && strict.stars(damage: 5, maxBaseHP: 100) == 2 && strict.stars(damage: 6, maxBaseHP: 100) == 1)
    }

    @Test func onlyAWonMatchIsRatedAndStagesAreNot() {
        let w = GameWorld(config: shortConfig(), seed: 3)
        #expect(w.matchStars == 0)
        w.startNextWave(); clearStage(w)
        // A cleared stage carries no rating; the match is not rated until it is won.
        #expect(w.phase == .preparation && w.matchStars == 0)
        w.startNextWave(); clearStage(w)
        w.startNextWave(); clearStage(w)
        #expect(w.phase == .victory && w.baseDamageTaken == 0 && w.matchStars == 3)
    }

    @Test func theRatingCountsAllBaseDamageInTheMatch() {
        // Alpha Beast: 15 damage each. Thresholds: 20 and 50 of 100.
        let three = winMatch(leaks: ["alphaBeast"])
        #expect(three.baseDamageTaken == 15 && three.matchStars == 3)
        let two = winMatch(leaks: ["alphaBeast", "alphaBeast", "alphaBeast"])
        #expect(two.baseDamageTaken == 45 && two.matchStars == 2)
        let one = winMatch(leaks: ["alphaBeast", "alphaBeast", "alphaBeast", "alphaBeast"])
        #expect(one.baseDamageTaken == 60 && one.matchStars == 1)
    }

    @Test func repairingDoesNotImproveTheRating() {
        let w = GameWorld(config: shortConfig(), seed: 3)
        w.startNextWave()
        for _ in 0..<4 { _ = w.debugSpawn("alphaBeast", atDistance: w.path.totalLength - 0.1) }
        w.step(dt); clearStage(w)
        w.debugSetGold(100_000)
        _ = w.repairBase(optionIndex: config.rules.repair.options.count - 1)
        #expect(w.baseHP > 40)
        while !w.phase.isOver { w.startNextWave(); clearStage(w) }
        #expect(w.baseDamageTaken == 60 && w.matchStars == 1)
    }

    @Test func aLostMatchHasNoStars() {
        let w = GameWorld(config: shortConfig(), seed: 3)
        w.startNextWave()
        _ = w.damageBase(10_000)
        #expect(w.phase == .defeat && w.matchStars == 0 && w.baseDamageTaken == 100)
        var p = PlayerProfile()
        p.recordMatchEnd(w)
        #expect(p.totalStars == 0 && p.matchStars.isEmpty)
    }

    @Test func theBestRatingPerBattlefieldOnlyEverImproves() {
        var p = PlayerProfile()
        let first = p.recordMatchStars(2, battlefield: "meadow")
        let worse = p.recordMatchStars(1, battlefield: "meadow")
        #expect(first && !worse && p.bestStars(battlefield: "meadow") == 2)
        let better = p.recordMatchStars(3, battlefield: "meadow")
        #expect(better && p.bestStars(battlefield: "meadow") == 3)
        // Battlefields are tracked separately.
        p.recordMatchStars(1, battlefield: "desert")
        #expect(p.bestStars(battlefield: "desert") == 1 && p.bestStars(battlefield: "lakeside") == 0 && p.totalStars == 4)
    }

    @Test func aWonMatchRecordsItsRatingAndProgress() {
        var p = PlayerProfile()
        let map = config.map.id
        p.recordMatchEnd(winMatch(leaks: ["alphaBeast", "alphaBeast", "alphaBeast"]))
        #expect(p.bestStars(battlefield: map) == 2 && p.stagesCleared(battlefield: map) == 3)
        // A better win raises it, a worse one does not lower it.
        p.recordMatchEnd(winMatch())
        p.recordMatchEnd(winMatch(leaks: ["alphaBeast", "alphaBeast", "alphaBeast", "alphaBeast"]))
        #expect(p.bestStars(battlefield: map) == 3 && p.totalStars == 3)
    }

    @Test func progressAndStarsPersistAndOldProfilesLoad() throws {
        var p = PlayerProfile()
        p.recordStagesCleared(12, battlefield: "lakeside")
        p.recordMatchStars(2, battlefield: "meadow")
        let back = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(p))
        #expect(back.stagesCleared == ["lakeside": 12] && back.matchStars == ["meadow": 2] && back.highestStageCleared == 12)
        // A profile saved before stars existed.
        let old = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"version":1,"totalKills":7}"#.utf8))
        #expect(old.matchStars.isEmpty && old.totalKills == 7 && old.highestStageCleared == 0)
        // A development profile that rated every stage keeps its progress, not those ratings.
        let dev = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"version":1,"stageStars":{"desert":[3,2,1,0]}}"#.utf8))
        #expect(dev.stagesCleared == ["desert": 3] && dev.totalStars == 0)
    }

    @Test func damageTakenSurvivesContinue() throws {
        let w = GameWorld(config: config, options: MatchOptions(randomEvents: false, battlefield: "desert"), seed: 5)
        w.startNextWave(); _ = w.debugSpawn("alphaBeast", atDistance: w.path.totalLength - 0.1); w.step(dt); clearStage(w)
        var p = PlayerProfile()
        p.noteProgress(w)
        #expect(p.stagesCleared(battlefield: "desert") == 1 && p.totalStars == 0)
        let cp = try #require(w.makeCheckpoint())
        let restored = try GameWorld(config: config, checkpoint: try JSONDecoder().decode(MatchCheckpoint.self, from: JSONEncoder().encode(cp)))
        #expect(restored.baseDamageTaken == 15)
        // A checkpoint from before the count existed: the missing base HP is used.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cp)) as! [String: Any]
        json["damageTaken"] = nil
        let older = try JSONDecoder().decode(MatchCheckpoint.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(try GameWorld(config: config, checkpoint: older).baseDamageTaken == 15)
    }

    // MARK: Saves from version 1.4.0

    @Test func aSaveFromBeforeTheRebalanceStillLoads() throws {
        // A 1.4.0 checkpoint: towers at level 5, no doctrines, no disable or trait data.
        let w = GameWorld(config: config, options: MatchOptions(randomEvents: false), seed: 5)
        w.debugSetGold(50_000)
        for (i, s) in w.config.map.buildSlots.prefix(4).enumerated() {
            w.build(TowerArchetype.allCases[i], atSlot: s.id)
            let t = w.tower(atSlot: s.id)!
            while t.level < 5 { w.upgrade(t) }
        }
        w.startNextWave(); clearStage(w)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try #require(w.makeCheckpoint()))) as! [String: Any]
        json["damageTaken"] = nil
        json["researchedTechs"] = ["improvedArrows", "strongerWalls", "automatedWeapons", "plasmaTechnology", "noLongerExists"]
        let old = try JSONDecoder().decode(MatchCheckpoint.self, from: JSONSerialization.data(withJSONObject: json))
        let back = try GameWorld(config: config, checkpoint: old)
        // Towers keep their level (5 is no longer the top, so they can now go one further).
        #expect(back.towers.count == 4 && back.towers.allSatisfy { $0.level == 5 && !$0.isMaxLevel })
        #expect(back.towers.allSatisfy { back.upgradeCost(for: $0) != nil })
        // Technologies that still exist are kept with their new effects; unknown ones are dropped.
        #expect(back.researchedTechs == ["improvedArrows", "strongerWalls", "automatedWeapons", "plasmaTechnology"])
        #expect(back.phase == .preparation && back.waveNumber == 1)
        // And it plays on.
        back.startNextWave(); clearStage(back)
        #expect(back.stats.wavesCleared == 2)
    }

    @Test func aProfileFromBeforeTheRebalanceKeepsItsProgress() throws {
        let json = #"{"version":1,"totalKills":900,"matchStars":{"meadow":2},"stagesCleared":{"meadow":30,"desert":12},"records":{"normal":{"matches":4,"victories":1,"highestWave":30}},"settings":{"hero":"queen"}}"#
        let p = try JSONDecoder().decode(PlayerProfile.self, from: Data(json.utf8))
        #expect(p.bestStars(battlefield: "meadow") == 2 && p.stagesCleared(battlefield: "desert") == 12)
        #expect(p.highestStageCleared == 30 && p.activeHero(in: config.summons)?.id == "queen")
    }
}
