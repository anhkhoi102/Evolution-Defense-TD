import CoreGraphics
import Testing
@testable import EvolutionDefenseCore

@Suite("Configuration & map")
struct ConfigurationTests {
    let config = try! GameConfiguration.loadDefault()

    @Test func loadsAllTowerArchetypesWithFiveLevels() {
        for a in TowerArchetype.allCases {
            let t = config.tower(a)
            #expect(t.levels.count == 5, "\(a) should have 5 levels")
            #expect(t.levels.map(\.level) == [1, 2, 3, 4, 5])
            #expect(t.buildCost > 0)
        }
    }

    @Test func towerIdentitiesDiffer() {
        let splash = config.tower(.splash).stats(level: 1)
        let sniper = config.tower(.sniper).stats(level: 1)
        let heavy = config.tower(.heavy).stats(level: 1)
        let rapid = config.tower(.rapid).stats(level: 1)
        #expect(splash.aoeRadius > 0 && sniper.aoeRadius == 0)
        #expect(sniper.range > splash.range && sniper.range > heavy.range && sniper.range > rapid.range)
        #expect(heavy.damage > splash.damage && heavy.damage > sniper.damage && heavy.damage > rapid.damage)
        #expect(rapid.attacksPerSecond > sniper.attacksPerSecond * 2)
        #expect(heavy.armorPenetration > rapid.armorPenetration)
    }

    @Test func mapHasWindingPathWithEnoughTurns() {
        let path = config.map.makePath()
        let turns = path.turnCount()
        #expect((5...7).contains(turns), "path has \(turns) turns")
        #expect(path.totalLength > config.map.worldSize.width * 1.5, "path should be long and winding")
    }

    @Test func buildSlotsAreStrategicAndOffThePath() {
        let map = config.map
        let path = map.makePath()
        #expect((12...16).contains(map.buildSlots.count))
        let minClearance = map.tileSize * 1.5
        for slot in map.buildSlots {
            let p = map.slotPosition(slot)
            let d = path.distanceToPath(from: p)
            #expect(d >= minClearance, "slot \(slot.id) is \(d) from the path")
            // Must be useful: within reach of the path for a short-range tower.
            #expect(d <= 125, "slot \(slot.id) is too far from the path (\(d))")
            #expect(p.x > 0 && p.y > 0 && p.x < map.worldSize.width && p.y < map.worldSize.height)
        }
        for a in map.buildSlots {
            for b in map.buildSlots where a.id < b.id {
                let d = map.slotPosition(a).distance(to: map.slotPosition(b))
                #expect(d >= map.tileSize * 1.6, "slots \(a.id) and \(b.id) overlap")
            }
        }
    }

    @Test func decorationsAreDeterministicAndClearOfPath() {
        let a = config.map.resolvedDecorations()
        let b = config.map.resolvedDecorations()
        #expect(a.count == b.count)
        #expect(zip(a, b).allSatisfy { $0.x == $1.x && $0.y == $1.y && $0.kind == $1.kind })
        let path = config.map.makePath()
        let scattered = a.dropFirst(config.map.decorations.count)
        #expect(!scattered.isEmpty)
        for d in scattered {
            let p = config.map.world(x: d.x, y: d.y)
            #expect(path.distanceToPath(from: p) >= config.map.scatter.pathClearance * config.map.tileSize - 0.001)
        }
    }

    @Test func wavesReferenceKnownEnemiesAndEndWithBoss() throws {
        try config.validate()
        #expect(!config.waves.isEmpty)
        let last = try #require(config.waves.last)
        #expect(last.isBossWave)
        #expect(last.groups.contains { config.enemies[$0.enemy]?.isBoss == true })
    }

    @Test func pathSamplingEndpoints() {
        let path = config.map.makePath()
        var hint = 0
        let start = path.sample(at: 0, segmentHint: &hint).position
        let end = path.sample(at: path.totalLength, segmentHint: &hint).position
        #expect(start.distance(to: path.points.first!) < 0.001)
        #expect(end.distance(to: path.points.last!) < 0.001)
        // Midpoint of first segment.
        let firstLen = path.cumulative[1]
        let mid = path.position(at: firstLen / 2)
        let expected = (path.points[0] + path.points[1]) * 0.5
        #expect(mid.distance(to: expected) < 0.001)
    }

    @Test func damageModel() {
        #expect(DamageModel.effectiveDamage(raw: 10, armor: 0, penetration: 0, minimumFraction: 0.15) == 10)
        #expect(DamageModel.effectiveDamage(raw: 10, armor: 3, penetration: 0, minimumFraction: 0.15) == 7)
        #expect(DamageModel.effectiveDamage(raw: 10, armor: 3, penetration: 5, minimumFraction: 0.15) == 10)
        #expect(DamageModel.effectiveDamage(raw: 4, armor: 10, penetration: 0, minimumFraction: 0.15) == 0.6)
    }
}
