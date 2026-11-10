import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

@Suite("Battlefields")
struct BattlefieldTests {
    @Test func threeBattlefieldsWithGrasslandAsDefault() {
        #expect(config.maps.map(\.id) == ["meadow", "desert", "lakeside"])
        #expect(config.map.id == MatchOptions.defaultBattlefield)
        for m in config.maps {
            #expect(!m.name.isEmpty && !(m.summary ?? "").isEmpty && m.theme != nil, "\(m.id) needs a name, summary and theme")
        }
        #expect(Set(config.maps.compactMap { $0.theme?.environment }).count == 3, "each battlefield has its own environment")
    }

    @Test func layoutsAreComparable() {
        // Same playfield, same number of pads, road length within 6 % of Grassland:
        // the battlefields differ in shape, not in size.
        let base = config.map
        let baseLength = base.makePath().totalLength
        for m in config.maps {
            #expect(m.columns == base.columns && m.rows == base.rows && m.tileSize == base.tileSize)
            #expect(m.buildSlots.count == base.buildSlots.count)
            #expect(abs(m.makePath().totalLength - baseLength) / baseLength < 0.06, "\(m.id) road length \(m.makePath().totalLength)")
        }
        #expect(Set(config.maps.map { $0.path.map { "\($0.x),\($0.y)" }.joined() }).count == 3, "three different roads")
    }

    @Test func padsAndDecorationsAreOnValidGround() {
        for m in config.maps {
            let path = m.makePath()
            for s in m.buildSlots {
                #expect(!m.isInWater(GridPoint(x: s.x, y: s.y), margin: 0.5), "\(m.id) pad \(s.id) in water")
                #expect(path.distanceToPath(from: m.slotPosition(s)) > CGFloat((m.pathWidth / 2 + 0.5) * m.tileSize), "\(m.id) pad \(s.id) on the road")
            }
            for d in m.resolvedDecorations() {
                #expect(!m.isInWater(GridPoint(x: d.x, y: d.y)), "\(m.id): \(d.kind) in water")
            }
        }
    }

    @Test func roadOnlyCrossesWaterOnABridge() {
        let lake = config.battlefield("lakeside")!
        #expect(!(lake.water ?? []).isEmpty && lake.bridges?.count == 1)
        // The configuration loader enforces this; a road through the lake is rejected.
        var broken = config
        var m = lake
        m.bridges = []
        broken.maps = [m]
        broken.map = m
        #expect(throws: (any Error).self) { try broken.validate() }
        var padInLake = lake
        padInLake.buildSlots[0].x = 26; padInLake.buildSlots[0].y = 11
        broken.maps = [padInLake]; broken.map = padInLake
        #expect(throws: (any Error).self) { try broken.validate() }
    }

    @Test func grasslandIsUnchanged() {
        // The original battlefield keeps its exact road, pads and seeded decorations.
        let m = config.battlefield("meadow")!
        #expect(m.path.map(\.x) == [-1.5, 7, 7, 14, 14, 22, 22, 29.4])
        #expect(m.buildSlots.count == 16 && m.buildSlots[4].x == 10.5 && m.buildSlots[4].y == 5.2)
        let decos = m.resolvedDecorations()
        #expect(decos.count == 169)
        #expect(decos.filter { $0.kind == .tree }.count == 26 && decos.filter { $0.kind == .cactus }.isEmpty)
    }

    @Test(arguments: ["meadow", "desert", "lakeside"])
    func matchRunsOnTheChosenBattlefield(id: String) {
        let w = GameWorld(config: config, options: MatchOptions(randomEvents: false, battlefield: id), seed: 4)
        #expect(w.config.map.id == id)
        #expect(w.path.totalLength == config.battlefield(id)!.makePath().totalLength)
        // Every pad can be built on, enemies walk the whole road, summons deploy on it.
        w.debugSetGold(100_000)
        for s in w.config.map.buildSlots {
            if case .success = w.build(.rapid, atSlot: s.id) {} else { Issue.record("\(id): pad \(s.id) refused") }
        }
        let fresh = GameWorld(config: config, options: MatchOptions(randomEvents: false, battlefield: id), seed: 4)
        fresh.startNextWave()
        let e = fresh.debugSpawn("wolf")!
        var reached = false
        for _ in 0..<(60 * 60) {
            fresh.step(dt)
            fresh.drainEvents { if case .enemyReachedBase(let x, _) = $0, x === e { reached = true } }
            if reached { break }
        }
        #expect(reached, "\(id): an enemy can walk from the spawn to the base")
        let w3 = GameWorld(config: config, options: MatchOptions(randomEvents: false, battlefield: id), seed: 4)
        w3.debugSkipToWave(6); w3.startNextWave()
        #expect(w3.summon("militia", at: w3.path.position(at: w3.path.totalLength / 2)) == .success(units: 4))
    }

    @Test func unknownBattlefieldFallsBackToTheDefault() {
        let w = GameWorld(config: config, options: MatchOptions(randomEvents: false, battlefield: "atlantis"))
        #expect(w.config.map.id == "meadow")
    }

    @Test func oldSavesAndSettingsStillLoad() throws {
        // Saved before battlefields existed: no "battlefield" key.
        let o = try JSONDecoder().decode(MatchOptions.self, from: Data(#"{"difficulty":"hard","randomEvents":true}"#.utf8))
        #expect(o.battlefield == "meadow" && o.difficulty == .hard)
        let s = try JSONDecoder().decode(GameSettings.self, from: Data(#"{"masterVolume":0.5}"#.utf8))
        #expect(s.battlefield == "meadow")
    }

    @Test func checkpointsRememberTheBattlefield() throws {
        let w = GameWorld(config: config, options: MatchOptions(randomEvents: false, battlefield: "desert"), seed: 2)
        w.debugSetGold(5000)
        _ = w.build(.splash, atSlot: 3)
        let cp = try #require(w.makeCheckpoint())
        let data = try JSONEncoder().encode(cp)
        let restored = try GameWorld(config: config, checkpoint: try JSONDecoder().decode(MatchCheckpoint.self, from: data))
        #expect(restored.config.map.id == "desert")
        #expect(restored.tower(atSlot: 3)?.position == w.tower(atSlot: 3)?.position)
    }

    @Test(arguments: ["desert", "lakeside"])
    func difficultyCarriesOverToNewBattlefields(id: String) {
        // Same pattern as Grassland on Normal: the optimised defence wins, a casual one doesn't.
        let map = config.battlefield(id)!
        let players = BalancePlayer.profiles(for: map)
        let options = MatchOptions(randomEvents: false, battlefield: id)
        let expert = players.first { $0.name.hasPrefix("expert") }!.play(config: config, seed: 7, options: options)
        let casual = players.first { $0.name.hasPrefix("casual") }!.play(config: config, seed: 7, options: options)
        let spam = players.first { $0.name.hasPrefix("L1 spam") }!.play(config: config, seed: 7, options: options)
        print("BATTLEFIELD \(id): expert \(expert) | casual \(casual) | L1 spam \(spam)")
        #expect(expert.phase == .victory)
        #expect(casual.phase == .defeat && casual.wavesCleared >= 12)
        #expect(spam.phase == .defeat && spam.wavesCleared <= 12)
        let opening = expert.waves.filter { $0.number <= 4 }.map(\.hpLost).reduce(0, +)
        #expect(opening == 0, "the opening stays accessible")
    }
}
