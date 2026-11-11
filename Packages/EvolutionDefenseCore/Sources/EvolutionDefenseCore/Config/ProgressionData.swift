import Foundation

/// One phase of the difficulty curve (game.json → "progression").
///
/// Every value is a multiplier applied to the waves in the phase, on top of the
/// difficulty mode (Easy / Normal / Hard) and the per-group tuning in
/// waves.json. This keeps the shape of the whole curve in one table:
/// tune it here, never in gameplay code. Docs/BALANCE.md has the targets.
public struct ProgressionPhase: Codable, Sendable, Equatable {
    public var name: String
    /// First wave of this phase. A phase lasts until the next one starts.
    public var fromWave: Int
    public var enemyHP: Double = 1
    public var enemySpeed: Double = 1
    /// Multiplies the seconds between spawns (below 1 = denser waves).
    public var spawnInterval: Double = 1
    /// Multiplies every group's enemy count (rounded, at least 1).
    public var enemyCount: Double = 1
    /// Multiplies gold per kill.
    public var killReward: Double = 1
    /// Multiplies the wave-clear reward.
    public var clearReward: Double = 1

    public init(name: String, fromWave: Int, enemyHP: Double = 1, enemySpeed: Double = 1, spawnInterval: Double = 1,
                enemyCount: Double = 1, killReward: Double = 1, clearReward: Double = 1) {
        self.name = name; self.fromWave = fromWave; self.enemyHP = enemyHP; self.enemySpeed = enemySpeed
        self.spawnInterval = spawnInterval; self.enemyCount = enemyCount; self.killReward = killReward
        self.clearReward = clearReward
    }

    enum CodingKeys: String, CodingKey {
        case name, fromWave, enemyHP, enemySpeed, spawnInterval, enemyCount, killReward, clearReward
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        fromWave = try c.decode(Int.self, forKey: .fromWave)
        enemyHP = try c.decodeIfPresent(Double.self, forKey: .enemyHP) ?? 1
        enemySpeed = try c.decodeIfPresent(Double.self, forKey: .enemySpeed) ?? 1
        spawnInterval = try c.decodeIfPresent(Double.self, forKey: .spawnInterval) ?? 1
        enemyCount = try c.decodeIfPresent(Double.self, forKey: .enemyCount) ?? 1
        killReward = try c.decodeIfPresent(Double.self, forKey: .killReward) ?? 1
        clearReward = try c.decodeIfPresent(Double.self, forKey: .clearReward) ?? 1
    }

    public static let neutral = ProgressionPhase(name: "Default", fromWave: 1)

    /// The phase with its effect scaled by `strength` (each multiplier m → 1 + (m − 1) × strength).
    /// Difficulty modes use this to make the same curve gentler or steeper.
    public func scaled(by strength: Double) -> ProgressionPhase {
        guard strength != 1 else { return self }
        func f(_ m: Double) -> Double { max(0.05, 1 + (m - 1) * strength) }
        return ProgressionPhase(name: name, fromWave: fromWave, enemyHP: f(enemyHP), enemySpeed: f(enemySpeed),
                                spawnInterval: f(spawnInterval), enemyCount: f(enemyCount),
                                killReward: f(killReward), clearReward: f(clearReward))
    }
}

/// What being an elite means (game.json → "elite"). Wave groups opt in with
/// `"elite": true`; the renderer marks elites so players can prioritise them.
public struct EliteConfig: Codable, Sendable, Equatable {
    public var hp: Double
    public var armorBonus: Double
    public var speed: Double
    public var reward: Double

    public init(hp: Double = 2, armorBonus: Double = 2, speed: Double = 1.05, reward: Double = 2.5) {
        self.hp = hp; self.armorBonus = armorBonus; self.speed = speed; self.reward = reward
    }
}

extension RulesConfig {
    /// The phase that wave `n` belongs to (neutral if no table is configured),
    /// at the given curve strength (the difficulty mode's `curve`).
    public func phase(forWave n: Int, curve: Double = 1) -> ProgressionPhase {
        let p = (progression ?? []).filter { $0.fromWave <= max(1, n) }.max { $0.fromWave < $1.fromWave } ?? .neutral
        return p.scaled(by: curve)
    }
}

extension GameConfiguration {
    /// The waves as the match plays them: each group's count and spawn interval
    /// scaled by its progression phase. The wave intel UI reads these too
    /// (through GameWorld.waves).
    public func progressionWaves(curve: Double = 1) -> [WaveDefinition] {
        waves.map { w in
            let p = rules.phase(forWave: w.number, curve: curve)
            guard p.enemyCount != 1 || p.spawnInterval != 1 else { return w }
            var scaled = w
            scaled.groups = w.groups.map { g in
                var s = g
                if !(config(isBoss: g.enemy)) {   // bosses always come alone
                    s.count = max(1, Int((Double(g.count) * p.enemyCount).rounded()))
                }
                s.interval = g.interval * p.spawnInterval
                return s
            }
            return scaled
        }
    }

    private func config(isBoss id: String) -> Bool { enemies[id]?.isBoss ?? false }

    /// The waves of a match on a difficulty: the progression curve, then what the difficulty adds
    /// or leaves out (traits only from its own stage, extra elite groups).
    public func matchWaves(_ d: DifficultyDefinition) -> [WaveDefinition] {
        progressionWaves(curve: d.curve ?? 1).map { w in
            var w = w
            if let from = d.traitsFromStage, w.number < from {
                w.groups = w.groups.map { g in var g = g; g.trait = nil; return g }
            }
            if let from = d.extraElitesFromStage, w.number >= from, let share = d.extraEliteShare, share > 0,
               let big = w.groups.filter({ !config(isBoss: $0.enemy) && $0.elite != true }).max(by: { $0.count < $1.count }) {
                var extra = big
                extra.count = max(1, Int((Double(big.count) * share).rounded()))
                extra.elite = true
                extra.interval = max(big.interval * 2, 1.2)
                extra.delay = big.delay + Double(big.count) * big.interval * 0.5
                w.groups.append(extra)
            }
            return w
        }
    }
}
