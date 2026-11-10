import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

/// A world in stage `n` with the given hero, abilities unlocked, countdown held.
private func heroWorld(_ hero: String?, stage n: Int = 6, seed: UInt64 = 5) -> GameWorld {
    let w = GameWorld(config: config, options: MatchOptions(randomEvents: false, hero: hero), seed: seed)
    w.holdPreparationCountdown = true
    w.debugSkipToWave(n)
    w.startNextWave()
    return w
}

private func road(_ w: GameWorld, _ d: CGFloat = 900) -> CGPoint { w.path.position(at: d) }

private func run(_ w: GameWorld, _ seconds: Double, events: ((GameEvent) -> Void)? = nil) {
    var t = 0.0
    while t < seconds && !w.phase.isOver {
        w.step(dt); t += dt
        w.drainEvents { e in events?(e) }
    }
}

/// Removes the stage's own enemies so a test controls exactly what is on the road.
private func clearRoad(_ w: GameWorld) {
    w.step(dt)
    for e in w.enemies where e.isActive { w.applyDamage(to: e, raw: 1e9, penetration: 1e9, source: nil, ignoreDefences: true) }
}

@Suite("Heroes: Knight, King and Queen")
struct HeroTests {
    var knight: SummonAbilityDefinition { config.summons.ability("hero")! }
    var king: SummonAbilityDefinition { config.summons.ability("king")! }
    var queen: SummonAbilityDefinition { config.summons.ability("queen")! }

    // MARK: Configuration

    @Test func threeHeroesWithDifferentRoles() {
        #expect(config.summons.heroes.map(\.id) == ["hero", "king", "queen"])
        #expect(config.summons.defaultHero?.id == "hero")
        #expect(knight.requiredStage == 0 && king.requiredStage == 10 && queen.requiredStage == 20)
        // The King is the durable one: most health, takes reduced damage, stays longest, melee.
        #expect(king.unit.hp > knight.unit.hp * 1.5 && (king.unit.damageReduction ?? 0) >= 0.3)
        #expect(king.duration > knight.duration && !king.unit.isRanged && king.unit.range < 60)
        #expect((king.special?.slow ?? 0) > 0)
        // The Queen is the ranged burst one: fragile, long reach, hits flyers, highest damage per second.
        #expect(queen.unit.isRanged && queen.unit.range > 200 && queen.unit.canTargetAir)
        #expect(queen.unit.hp < knight.unit.hp / 2)
        let dps = { (a: SummonAbilityDefinition) in a.unit.damage * a.unit.attacksPerSecond }
        #expect(dps(queen) > dps(knight) * 1.5 && dps(king) < dps(knight))
        #expect(queen.special?.maxTargets != nil)
        // All three share the hero key and unlock in the same stage of a match.
        #expect(Set(config.summons.heroes.map(\.hotkey)) == ["E"])
        #expect(Set(config.summons.heroes.map(\.unlockWave)).count == 1)
        #expect(Set(config.summons.heroes.map(\.visual)).count == 3)
    }

    // MARK: One hero per match

    @Test func aMatchHasExactlyTheChosenHero() {
        for id in ["hero", "king", "queen"] {
            let w = heroWorld(id)
            #expect(w.matchHero?.id == id)
            #expect(w.summonAbilities.map(\.id) == ["militia", id])
            for other in ["hero", "king", "queen"] where other != id {
                #expect(w.summonStatus(other) == nil)
                #expect(w.summon(other, at: road(w)) == .unknownAbility)
            }
            #expect(w.summon(id, at: road(w)) == .success(units: 1))
        }
        // No choice, or an id that does not exist: the starting hero.
        #expect(heroWorld(nil).matchHero?.id == "hero")
        #expect(heroWorld("dragonlord").matchHero?.id == "hero")
    }

    @Test func theChosenHeroSurvivesSaveAndContinue() throws {
        let w = GameWorld(config: config, options: MatchOptions(randomEvents: false, hero: "queen"), seed: 2)
        let cp = try #require(w.makeCheckpoint())
        let back = try GameWorld(config: config, checkpoint: try JSONDecoder().decode(MatchCheckpoint.self, from: JSONEncoder().encode(cp)))
        #expect(back.matchHero?.id == "queen")
        // A save from before heroes could be chosen.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cp)) as! [String: Any]
        var opts = json["options"] as! [String: Any]
        opts["hero"] = nil
        json["options"] = opts
        let old = try JSONDecoder().decode(MatchCheckpoint.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(try GameWorld(config: config, checkpoint: old).matchHero?.id == "hero")
    }

    // MARK: Unlocks

    @Test func heroesUnlockByClearingStages() {
        var p = PlayerProfile()
        #expect(p.isUnlocked(knight) && !p.isUnlocked(king) && !p.isUnlocked(queen))
        p.recordStagesCleared(9, battlefield: "meadow")
        #expect(!p.isUnlocked(king))
        p.recordStagesCleared(10, battlefield: "meadow")
        #expect(p.isUnlocked(king) && !p.isUnlocked(queen))
        // Progress on any battlefield counts.
        p.recordStagesCleared(20, battlefield: "desert")
        #expect(p.isUnlocked(queen))
    }

    @Test func progressFromBeforeStarsExistedStillUnlocksHeroes() throws {
        // A profile from an older version: no stars, but a record of reaching stage 12.
        let old = try JSONDecoder().decode(PlayerProfile.self,
                                           from: Data(#"{"version":1,"records":{"normal":{"matches":3,"victories":0,"highestWave":12}}}"#.utf8))
        #expect(old.stagesCleared.isEmpty && old.highestStageCleared == 12)
        #expect(old.isUnlocked(king) && !old.isUnlocked(queen))
    }

    @Test func aLockedOrUnknownChoiceFallsBackToTheStartingHero() throws {
        var p = PlayerProfile()
        p.settings.hero = "queen"
        #expect(p.activeHero(in: config.summons)?.id == "hero")
        p.recordStagesCleared(20, battlefield: "meadow")
        #expect(p.activeHero(in: config.summons)?.id == "queen")
        p.settings.hero = "nobody"
        #expect(p.activeHero(in: config.summons)?.id == "hero")
        // The choice is saved with the settings; old settings load without it.
        p.settings.hero = "king"
        let back = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(p))
        #expect(back.settings.hero == "king")
        #expect(try JSONDecoder().decode(GameSettings.self, from: Data("{}".utf8)).hero == nil)
    }

    // MARK: King

    @Test func theKingOutlastsTheKnightUnderTheSamePressure() {
        func survival(_ id: String) -> Double {
            let w = heroWorld(id, stage: 12)
            clearRoad(w)
            #expect(w.summon(id, at: road(w)) == .success(units: 1))
            let u = w.summons[0]
            var t = 0.0
            // Keep a pack of brutes standing on the hero.
            while u.isAlive && t < 30 {
                for e in w.enemies where e.isActive { e.hp = e.maxHP }
                while w.enemies.filter(\.isActive).count < 6 { _ = w.debugSpawn("armoredBeast", atDistance: 900) }
                for e in w.enemies where e.isActive { e.distance = 900 }
                w.step(dt); t += dt
            }
            return t
        }
        let knightTime = survival("hero"), kingTime = survival("king")
        #expect(kingTime > knightTime * 2, "king \(kingTime)s vs knight \(knightTime)s")
    }

    @Test func royalSlamDamagesAndSlowsEverythingAround() {
        let w = heroWorld("king")
        clearRoad(w)
        w.summon("king", at: road(w))
        let sp = king.special!
        let near = (0..<4).map { _ in w.debugSpawn("armoredBeast", atDistance: 900)! }
        let far = w.debugSpawn("armoredBeast", atDistance: 900 + CGFloat(sp.radius) * 2.5)!
        var slams = 0
        var t = 0.0
        while slams == 0 && t < sp.interval * 1.5 {
            for e in near { e.hp = e.maxHP }
            w.step(dt); t += dt
            w.drainEvents { if case .summonSpecial(_, let name, _, let hits, _) = $0 { slams += 1; #expect(name == sp.name && hits >= near.count) } }
        }
        #expect(slams == 1)
        #expect(near.allSatisfy { $0.isSlowed && abs($0.slowAmount - sp.slow!) < 1e-9 })
        #expect(!far.isSlowed)
        // The slow wears off.
        run(w, sp.slowDuration! + 0.2)
        #expect(near.filter(\.isActive).allSatisfy { !$0.isSlowed || w.time - t < sp.interval })
    }

    // MARK: Queen

    @Test func theQueenFightsFromADistanceAndHitsFlyers() {
        let w = heroWorld("queen", stage: 8)
        clearRoad(w)
        w.summon("queen", at: road(w))
        let u = w.summons[0]
        let post = u.position
        let flyer = w.debugSpawn("flyingMonster", atDistance: 900 + CGFloat(queen.unit.range) * 0.8)!
        let before = flyer.hp
        run(w, 1.5)
        #expect(flyer.hp < before, "her bolts reach a flyer well outside melee range")
        #expect(u.position.distance(to: post) < 40, "she holds her ground instead of running in")
        // The Knight cannot touch the same flyer.
        let k = heroWorld("hero", stage: 8)
        clearRoad(k)
        k.summon("hero", at: road(k))
        let f2 = k.debugSpawn("flyingMonster", atDistance: 900 + 200)!
        let hp = f2.hp
        run(k, 1.5)
        #expect(f2.hp == hp)
    }

    @Test func starfallStrikesOnlyTheToughestFew() {
        let w = heroWorld("queen", stage: 8)
        clearRoad(w)
        w.summon("queen", at: road(w))
        let sp = queen.special!
        let small = (0..<5).map { _ in w.debugSpawn("wolf", atDistance: 1000)! }
        let big = (0..<sp.maxTargets!).map { _ in w.debugSpawn("troll", atDistance: 1000)! }
        var struck: [Int] = []
        var t = 0.0
        while struck.isEmpty && t < sp.interval * 1.5 {
            for e in small + big { e.hp = e.maxHP; e.distance = 1000 }
            w.step(dt); t += dt
            w.drainEvents { if case .summonSpecial(_, _, _, _, let targets) = $0 { struck = targets.map(\.id) } }
        }
        #expect(Set(struck) == Set(big.map(\.id)), "Starfall picks the enemies with the most health")
    }

    @Test func theQueenIsFragile() {
        func hpLeft(_ id: String) -> Double {
            let w = heroWorld(id, stage: 12)
            clearRoad(w)
            w.summon(id, at: road(w))
            let u = w.summons[0]
            var t = 0.0
            while u.isAlive && t < 3 {
                for e in w.enemies where e.isActive { e.hp = e.maxHP }
                while w.enemies.filter(\.isActive).count < 4 { _ = w.debugSpawn("armoredBeast", atDistance: 900) }
                for e in w.enemies where e.isActive { e.distance = 900 }
                w.step(dt); t += dt
            }
            return u.hpFraction
        }
        #expect(hpLeft("queen") < hpLeft("hero") && hpLeft("hero") < hpLeft("king"))
    }
}
