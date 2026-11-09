import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

@Suite("Performance budget")
struct PerformanceTests {
    /// 16 towers vs. a 300-enemy horde. One simulation step must stay far
    /// below the 16.7 ms frame budget (measured in debug, so release is faster).
    @Test func largeWaveStepCost() {
        let config = try! GameConfiguration.loadDefault()
        let w = GameWorld(config: config, seed: 7)
        w.holdPreparationCountdown = true
        w.debugSetGold(100_000)
        let types: [TowerArchetype] = [.rapid, .splash, .sniper, .heavy]
        for (i, s) in config.map.buildSlots.enumerated() { w.build(types[i % 4], atSlot: s.id) }
        for i in 0..<300 { w.debugSpawn(i % 3 == 0 ? "bear" : "wildBoar", atDistance: CGFloat(i) * 6) }
        let steps = 600
        let start = Date()
        for _ in 0..<steps { w.step(1.0 / 60.0); w.drainEvents { _ in } }
        let msPerStep = Date().timeIntervalSince(start) * 1000 / Double(steps)
        print("PERF: \(String(format: "%.3f", msPerStep)) ms/step, enemies left \(w.enemies.count), projectiles pool \(w.projectiles.count)")
        #expect(msPerStep < 4.0)
    }

    /// Same budget with Phase 3 enemies: abilities, shields, stealth, burning
    /// and slowing hits, and every tech researched.
    @Test func abilityHeavyWaveStepCost() {
        let config = try! GameConfiguration.loadDefault()
        let w = GameWorld(config: config, seed: 9)
        w.holdPreparationCountdown = true
        w.debugSetGold(1_000_000)
        w.debugSetResearch(1000)
        w.debugSkipToWave(16)
        for t in config.techs { w.research(t.id) }
        let types: [TowerArchetype] = [.rapid, .splash, .sniper, .heavy]
        for (i, s) in config.map.buildSlots.enumerated() { w.build(types[i % 4], atSlot: s.id) }
        for t in w.towers { while case .success = w.upgrade(t) {} }
        let mix = ["stealthRobot", "assaultRobot", "mutantBeast", "troll", "giantWolf", "swarmCreature"]
        for i in 0..<300 { w.debugSpawn(mix[i % mix.count], atDistance: CGFloat(i) * 6) }
        w.debugSpawn("mutantTitan", atDistance: 900)
        let steps = 600
        let start = Date()
        for _ in 0..<steps { w.step(1.0 / 60.0); w.drainEvents { _ in } }
        let msPerStep = Date().timeIntervalSince(start) * 1000 / Double(steps)
        print("PERF abilities: \(String(format: "%.3f", msPerStep)) ms/step, enemies \(w.enemies.count), pool \(w.projectiles.count)")
        #expect(msPerStep < 4.0)
    }
}
