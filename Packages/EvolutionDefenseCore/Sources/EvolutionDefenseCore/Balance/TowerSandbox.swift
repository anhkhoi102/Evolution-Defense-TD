import CoreGraphics
import Foundation

/// Set-piece tests for tower balance: four towers of one type (or two and two for a pair) on the
/// four best pads, no tech, no summons, against a group sent down the road. The number is the share
/// of the group's health destroyed before it reaches the base. Levels 1, 3 and 5 face enemies of
/// the age where that level is normal. Used by `edtool tower-sandbox` (Docs/TOWER_EFFECTS.md).
public enum TowerSandbox {
    public static func report(config: GameConfiguration) -> String {
        var out: [String] = []

        struct Scenario { var name: String; var groups: [[(String, Int, Bool)]] }   // per tier: (enemy, count, elite)
        let scenarios: [Scenario] = [
            Scenario(name: "weak pack", groups: [[("wolf", 20, false)], [("swarmCreature", 30, false)], [("scoutRobot", 24, false)]]),
            Scenario(name: "fast", groups: [[("wolf", 12, false)], [("giantWolf", 12, false)], [("scoutRobot", 14, false)]]),
            Scenario(name: "armoured", groups: [[("bear", 6, false)], [("armoredMonster", 6, false)], [("heavyMech", 5, false)]]),
            Scenario(name: "high health", groups: [[("bear", 5, false)], [("troll", 5, false)], [("giantMutant", 4, false)]]),
            Scenario(name: "elites", groups: [[("wildBoar", 5, true)], [("armoredBeast", 5, true)], [("assaultRobot", 5, true)]]),
            Scenario(name: "boss", groups: [[("alphaBeast", 1, false)], [("mutantTitan", 1, false)], [("titanWarMachine", 1, false)]]),
            Scenario(name: "mixed", groups: [[("wolf", 10, false), ("wildBoar", 5, false), ("bear", 2, false)],
                                              [("giantWolf", 8, false), ("armoredBeast", 4, false), ("troll", 2, false)],
                                              [("scoutRobot", 10, false), ("assaultRobot", 4, false), ("heavyMech", 2, false)]]),
        ]
        let pads = BalancePlayer.goodPlan.prefix(4).map(\.slot)
        func run(_ types: [TowerArchetype], level: Int, tier: Int, _ sc: Scenario) -> Double {
            let w = GameWorld(config: config, options: MatchOptions(randomEvents: false), seed: 5)
            w.holdPreparationCountdown = true
            w.debugSetGold(1_000_000)
            for (i, pad) in pads.enumerated() {
                guard case .success = w.build(types[i % types.count], atSlot: pad) else { continue }
                let t = w.towers[w.towers.count - 1]
                for _ in 1..<level { _ = w.upgrade(t) }
            }
            w.debugSkipToWave(2)
            w.startNextWave()
            // Clear the stage's own enemies, then send the group in a column.
            var total = 0.0
            var spawned: [Enemy] = []
            var queue = sc.groups[tier].flatMap { g in Array(repeating: (g.0, g.2), count: g.1) }
            var t = 0.0, next = 0.0
            let dt = 1.0 / 60.0
            while t < 240 {
                for e in w.enemies where e.isActive && !spawned.contains(where: { $0 === e }) {
                    w.applyDamage(to: e, raw: 1e12, penetration: 1e9, source: nil, ignoreDefences: true)
                }
                if t >= next, let (id, elite) = queue.first {
                    queue.removeFirst()
                    if let e = w.debugSpawn(id, elite: elite) { spawned.append(e); total += e.maxHP }
                    next = t + 0.7
                }
                w.debugSetBaseHP(100)
                w.step(dt); t += dt
                w.drainEvents { _ in }
                if queue.isEmpty && spawned.allSatisfy({ !$0.isActive }) { break }
            }
            let left = spawned.reduce(0.0) { $0 + ($1.reachedBase || $1.isActive ? max(0, $1.hp) : 0) }
            return total > 0 ? 1 - left / total : 0
        }
        out.append("Tower sandbox: share of the group's health destroyed (4 towers, no tech). 100 = nothing got through.\n")
        for (tier, level) in [1, 3, 5].enumerated() {
            out.append("Level \(level) towers vs \(["Primitive", "Medieval/Industrial", "Futuristic"][tier]) enemies")
            out.append("  " + "line-up".padding(toLength: 18, withPad: " ", startingAt: 0) + scenarios.map { $0.name.padding(toLength: 13, withPad: " ", startingAt: 0) }.joined())
            var lineups: [(String, [TowerArchetype])] = TowerArchetype.allCases.map { ($0.rawValue, [$0]) }
            if level >= 3 {
                lineups += [("rapid+sniper", [.rapid, .sniper]), ("heavy+sniper", [.heavy, .sniper]), ("rapid+heavy", [.rapid, .heavy]),
                            ("splash+rapid", [.splash, .rapid]), ("splash+sniper", [.splash, .sniper])]
            }
            for (name, types) in lineups {
                var line = "  " + name.padding(toLength: 18, withPad: " ", startingAt: 0)
                for sc in scenarios { line += String(format: "%3.0f", 100 * run(types, level: level, tier: tier, sc)).padding(toLength: 13, withPad: " ", startingAt: 0) }
                out.append(line)
            }
            out.append("")
        }

        return out.joined(separator: "\n")
    }
}
