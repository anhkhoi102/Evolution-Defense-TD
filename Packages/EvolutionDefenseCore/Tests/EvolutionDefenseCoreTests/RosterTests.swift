import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

@Suite("Battlefield rosters")
struct RosterTests {
    private func on(_ id: String) -> GameConfiguration { config.selecting(battlefield: id) }

    @Test func grasslandKeepsTheOriginalCreatures() {
        #expect(config.map.id == "meadow" && (config.map.roster ?? [:]).isEmpty)
        #expect(config.waves.map { $0.groups.map(\.enemy) } == config.authoredWaves.map { $0.groups.map(\.enemy) })
        #expect(config.enemiesInPlay.allSatisfy { config.enemies[$0]!.battlefield == nil })
    }

    @Test func desertAndLakesideHaveTheirOwnCreaturesAndBosses() {
        for id in ["desert", "lakeside"] {
            let c = on(id)
            let roster = c.map.roster ?? [:]
            #expect(roster.count == 14, "\(id) replaces every beast, monster and mutant")
            // Everything from the first three ages is this map's own; the robots of the last age are shared.
            for e in c.enemiesInPlay.map({ c.enemies[$0]! }) {
                if e.era == .futuristic { #expect(e.battlefield == nil) } else { #expect(e.battlefield == id, "\(e.id) on \(id)") }
            }
            // Its own bosses on stages 5, 10 and 15.
            let bosses = [5, 10, 15].map { n in c.waves[n - 1].groups.first { c.enemies[$0.enemy]!.isBoss }!.enemy }
            #expect(bosses.allSatisfy { c.enemies[$0]!.battlefield == id } && Set(bosses).count == 3)
            // Names and art are new, not renamed copies.
            let own = roster.values.map { c.enemies[$0]! }
            #expect(Set(own.map(\.displayName)).count == 14 && Set(own.map(\.visual)).count == 14)
            #expect(Set(own.map(\.visual)).isDisjoint(with: roster.keys.map { c.enemies[$0]!.visual }))
        }
        // The two maps share no creature.
        #expect(Set(on("desert").map.roster!.values).isDisjoint(with: on("lakeside").map.roster!.values))
    }

    @Test func aSwapKeepsTheStagePlayableTheSameWay() {
        for id in ["desert", "lakeside"] {
            let c = on(id)
            for (from, to) in c.map.roster! {
                let a = c.enemies[from]!, b = c.enemies[to]!
                #expect(a.isBoss == b.isBoss && a.isFlying == b.isFlying && a.era == b.era, "\(from) → \(to)")
                // Different, but in the same weight class: within 25 % on health and speed.
                #expect(abs(b.hp / a.hp - 1) <= 0.25 && abs(b.speed / a.speed - 1) <= 0.25, "\(to) stats")
                #expect(b.goldReward == a.goldReward)
            }
            // Same stage structure: counts, timing and themes are untouched.
            for (w0, w) in zip(c.authoredWaves, c.waves) {
                #expect(w0.groups.map(\.count) == w.groups.map(\.count) && w0.theme == w.theme && w0.isBossWave == w.isBossWave)
            }
        }
    }

    @Test func creaturesOnlyCallTheirOwnKind() {
        // Summons, splits and broods of a map creature stay on that map.
        for e in config.enemies.values where e.battlefield != nil {
            for a in [e.baseAbilities] + e.sortedPhases.compactMap(\.abilities) {
                for ref in [a.summon?.enemy, a.splitOnDeath?.enemy, a.brood?.enemy].compactMap({ $0 }) {
                    #expect(config.enemies[ref]!.battlefield == e.battlefield, "\(e.id) calls \(ref)")
                }
            }
        }
    }

    @Test func aDesertMatchSpawnsDesertCreatures() {
        var seen = Set<String>()
        for stage in [1, 5] {
            let world = GameWorld(config: config, options: MatchOptions(randomEvents: false, battlefield: "desert"), seed: 4)
            #expect(world.config.map.id == "desert")
            if stage > 1 { world.debugSkipToWave(stage) }
            world.startNextWave()
            for _ in 0..<(60 * 40) {
                world.debugSetBaseHP(100)          // undefended: keep the base standing so the boss arrives
                world.step(dt)
                world.drainEvents {
                    if case .enemySpawned(let e) = $0 { seen.insert(e.definition.id) }
                    if case .bossSpawned(let e) = $0 { seen.insert(e.definition.id) }
                }
            }
        }
        #expect(seen.contains("boneRunner") && seen.contains("cactoroChief"), "\(seen.sorted())")
        #expect(seen.contains("cactling"), "the Cactoro Chief calls cactlings, not wolves")
        #expect(seen.isDisjoint(with: ["wolf", "wildBoar", "bear", "alphaBeast"]))
    }

    @Test func aMapBossCountsForTheBossAchievements() {
        let w = GameWorld(config: config, options: MatchOptions(randomEvents: false, battlefield: "lakeside"), seed: 2)
        w.startNextWave()
        let boss = w.debugSpawn("mushroomKing", atDistance: 300)!
        w.applyDamage(to: boss, raw: 1e9, penetration: 1e9, source: nil, ignoreDefences: true)
        w.step(dt)
        #expect(w.stats.bossesKilled.contains("mushroomKing") && w.stats.bossesKilled.contains("alphaBeast"))
        #expect(w.stats.bossesDefeated == 1)
    }

    @Test func aSavedMatchKeepsItsRoster() throws {
        let w = GameWorld(config: config, options: MatchOptions(randomEvents: false, battlefield: "lakeside"), seed: 9)
        let cp = try #require(w.makeCheckpoint())
        let back = try GameWorld(config: config, checkpoint: try JSONDecoder().decode(MatchCheckpoint.self, from: JSONEncoder().encode(cp)))
        #expect(back.waves.waves[0].groups.allSatisfy { back.config.enemies[$0.enemy]!.battlefield == "lakeside" })
    }

    @Test func aBadRosterIsRejectedAtLoad() throws {
        var c = on("desert")
        var m = c.map
        m.roster?["wolf"] = "vulture"            // a ground enemy swapped for a flyer
        c.maps = c.maps.map { $0.id == m.id ? m : $0 }
        #expect(throws: (any Error).self) { try c.validate() }
        m.roster?["wolf"] = "nobody"
        c.maps = c.maps.map { $0.id == m.id ? m : $0 }
        #expect(throws: (any Error).self) { try c.validate() }
    }
}
