import CoreGraphics
import Foundation
import Testing
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
private let dt = 1.0 / 60.0

private func world() -> GameWorld {
    let w = GameWorld(config: config, options: MatchOptions(randomEvents: false), seed: 3)
    w.holdPreparationCountdown = true
    return w
}

private func level(_ a: TowerArchetype, _ n: Int) -> TowerLevelStats { config.tower(a).levels[n - 1] }

@Suite("Tower effects: Armour Shred and Expose")
struct TowerEffectTests {
    // MARK: Data

    @Test func onlyRapidShredsAndOnlyHeavyExposes() {
        for a in TowerArchetype.allCases {
            for l in config.tower(a).levels {
                let h = l.hitEffects
                #expect((h.shred > 0) == (a == .rapid && l.level >= 3), "\(a) L\(l.level) shred")
                #expect((h.expose > 0) == (a == .heavy && l.level >= 3), "\(a) L\(l.level) expose")
            }
        }
        #expect((3...5).map { level(.rapid, $0).hitEffects.shredCap } == [6, 10, 14])
        #expect((3...5).map { level(.heavy, $0).hitEffects.expose } == [0.15, 0.2, 0.25])
        #expect(level(.heavy, 5).hitEffects.expose <= 0.25, "Expose never exceeds +25 %")
        // Effects show up in the upgrade panel.
        #expect(level(.rapid, 3).hitEffects.labels.contains { $0.contains("Shreds") })
        #expect(level(.heavy, 3).hitEffects.labels.contains { $0.contains("Exposes") })
    }

    // MARK: Armour Shred

    @Test func shredStacksPerHitUpToTheCapAndWearsOff() {
        let w = world()
        let e = w.debugSpawn("heavyMech", atDistance: 300)!          // 28 armour
        let h = level(.rapid, 4).hitEffects                           // cap 10
        for n in 1...25 {
            w.applyStatus(h, rawDamage: 10, to: e)
            #expect(e.shredAmount == min(Double(n), h.shredCap))
        }
        #expect(e.effectiveArmor == e.armor - 10)
        // Wears off 3 s after the last hit.
        for _ in 0..<Int((h.shredDuration - 0.2) / dt) { w.step(dt) }
        #expect(e.isShredded)
        for _ in 0..<Int(0.5 / dt) { w.step(dt) }
        #expect(!e.isShredded && e.effectiveArmor == e.armor)
    }

    @Test func severalTowersShareOneCounterAndTheHighestCapWins() {
        let w = world()
        let e = w.debugSpawn("heavyMech", atDistance: 300)!
        for _ in 0..<40 { w.applyStatus(level(.rapid, 3).hitEffects, rawDamage: 9, to: e) }
        #expect(e.shredAmount == 6, "two level-3 towers still stop at 6")
        for _ in 0..<40 { w.applyStatus(level(.rapid, 5).hitEffects, rawDamage: 18, to: e) }
        #expect(e.shredAmount == 14)
        // A weaker tower joining in does not lower or raise it.
        for _ in 0..<40 { w.applyStatus(level(.rapid, 3).hitEffects, rawDamage: 9, to: e) }
        #expect(e.shredAmount == 14)
    }

    @Test func shredNeverTakesArmourBelowZeroAndBossesLoseHalf() {
        let w = world()
        let light = w.debugSpawn("scoutRobot", atDistance: 300)!      // 4 armour
        let boss = w.debugSpawn("titanWarMachine", atDistance: 300)!  // 26 armour
        let h = level(.rapid, 5).hitEffects
        for _ in 0..<60 { w.applyStatus(h, rawDamage: 18, to: light); w.applyStatus(h, rawDamage: 18, to: boss) }
        #expect(light.shredAmount == light.armor && light.effectiveArmor == 0)
        #expect(boss.shredAmount == h.shredCap / 2)
    }

    @Test func shredLetsSmallHitsThroughArmour() {
        let w = world()
        let e = w.debugSpawn("heavyMech", atDistance: 300)!
        let l = level(.rapid, 5)
        func hit() -> Double {
            let before = e.hp
            w.applyDamage(to: e, raw: l.damage, penetration: l.armorPenetration, type: l.type, source: nil)
            return before - e.hp
        }
        let plain = hit()
        for _ in 0..<60 { w.applyStatus(l.hitEffects, rawDamage: l.damage, to: e) }
        let shredded = hit()
        #expect(shredded > plain * 2, "plain \(plain) → shredded \(shredded)")
    }

    // MARK: Expose

    @Test func exposeAddsAFixedShareAndNeverStacks() {
        let w = world()
        let e = w.debugSpawn("troll", atDistance: 300)!
        func hit() -> Double {
            e.hp = e.maxHP
            w.applyDamage(to: e, raw: 100, penetration: 100, type: .energy, source: nil)
            return e.maxHP - e.hp
        }
        let plain = hit()
        let h = level(.heavy, 5).hitEffects
        w.applyStatus(h, rawDamage: 560, to: e)
        #expect(abs(hit() - plain * 1.25) < 1e-6)
        for _ in 0..<10 { w.applyStatus(h, rawDamage: 560, to: e) }
        #expect(abs(hit() - plain * 1.25) < 1e-6, "ten marks are still +25 %")
        // A weaker mark does not lower a stronger one.
        w.applyStatus(level(.heavy, 3).hitEffects, rawDamage: 190, to: e)
        #expect(e.exposeAmount == 0.25)
    }

    @Test func exposeLastsFourSecondsAndHalfThatOnBosses() {
        let w = world()
        let e = w.debugSpawn("troll", atDistance: 200)!
        let boss = w.debugSpawn("titanWarMachine", atDistance: 200)!
        let h = level(.heavy, 4).hitEffects
        w.applyStatus(h, rawDamage: 320, to: e)
        w.applyStatus(h, rawDamage: 320, to: boss)
        for _ in 0..<Int((h.exposeDuration / 2 + 0.3) / dt) { w.step(dt) }
        #expect(e.isExposed && !boss.isExposed)
        for _ in 0..<Int((h.exposeDuration / 2) / dt) { w.step(dt) }
        #expect(!e.isExposed)
    }

    @Test func burningIgnoresBothEffects() {
        let w = world()
        let e = w.debugSpawn("heavyMech", atDistance: 300)!
        w.applyStatus(level(.heavy, 5).hitEffects, rawDamage: 560, to: e)
        for _ in 0..<60 { w.applyStatus(level(.rapid, 5).hitEffects, rawDamage: 18, to: e) }
        let before = e.hp
        w.applyDamage(to: e, raw: 50, penetration: 0, source: nil, ignoreDefences: true)
        #expect(before - e.hp == 50)
    }

    @Test func shredAndExposeCombineOnceEach() {
        let w = world()
        let e = w.debugSpawn("heavyMech", atDistance: 300)!          // 28 armour, 20 % physical resistance
        let rapid = level(.rapid, 5).hitEffects
        for _ in 0..<60 { w.applyStatus(rapid, rawDamage: 18, to: e) }
        w.applyStatus(level(.heavy, 5).hitEffects, rawDamage: 560, to: e)
        e.hp = e.maxHP
        w.applyDamage(to: e, raw: 100, penetration: 0, type: .energy, source: nil)
        // (100 − (28 − 14)) × 1.25: one flat effect, one percentage, nothing compounding.
        #expect(abs((e.maxHP - e.hp) - (100 - 14) * 1.25) < 1e-6)
    }

    // MARK: In a fight

    @Test func aRapidTowerShredsAndIsCreditedForWhatItEnables() {
        let w = world()
        w.debugSetGold(100_000)
        let slot = config.map.buildSlots.min { a, b in
            w.path.distanceToPath(from: config.map.slotPosition(a)) < w.path.distanceToPath(from: config.map.slotPosition(b))
        }!
        guard case .success = w.build(.rapid, atSlot: slot.id) else { Issue.record("build failed"); return }
        let tower = w.towers[0]
        for _ in 0..<4 { _ = w.upgrade(tower) }
        w.startNextWave()
        let at = w.path.closestPoint(to: tower.position).alongPath
        var applied = 0
        let e = w.debugSpawn("heavyMech", atDistance: at)!
        for _ in 0..<Int(3 / dt) {
            e.hp = e.maxHP
            e.distance = at
            w.step(dt)
            w.drainEvents { if case .statusApplied(let x, .shred) = $0, x === e { applied += 1 } }
        }
        #expect(e.shredAmount == 14)
        #expect(applied == 1, "announced once when it takes hold, not on every hit")
        #expect(tower.assistDamage > 0)
    }
}
