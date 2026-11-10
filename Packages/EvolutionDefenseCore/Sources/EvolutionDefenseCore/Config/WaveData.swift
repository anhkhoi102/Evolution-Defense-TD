import Foundation

/// A batch of identical enemies inside a wave.
public struct SpawnGroup: Codable, Sendable {
    public var enemy: String
    public var count: Int
    /// Seconds between enemies in this group.
    public var interval: Double
    /// Seconds after wave start before the first enemy of this group.
    public var delay: Double
    /// Per-wave tuning of this group (nil = 1 / 1 / 0).
    public var hpMultiplier: Double?
    public var speedMultiplier: Double?
    public var armorBonus: Double?
    /// Elite group: stats from game.json → "elite", marked on screen.
    public var elite: Bool?

    public init(enemy: String, count: Int, interval: Double, delay: Double,
                hpMultiplier: Double? = nil, speedMultiplier: Double? = nil, armorBonus: Double? = nil, elite: Bool? = nil) {
        self.enemy = enemy; self.count = count; self.interval = interval; self.delay = delay
        self.hpMultiplier = hpMultiplier; self.speedMultiplier = speedMultiplier; self.armorBonus = armorBonus
        self.elite = elite
    }
}

/// Stat adjustments applied to one spawned enemy (wave tuning, future difficulty modes).
public struct SpawnModifiers: Sendable, Equatable {
    public var hp: Double = 1
    public var speed: Double = 1
    public var armorBonus: Double = 0
    public var elite = false
    public init(hp: Double = 1, speed: Double = 1, armorBonus: Double = 0, elite: Bool = false) {
        self.hp = hp; self.speed = speed; self.armorBonus = armorBonus; self.elite = elite
    }
}

public struct WaveDefinition: Codable, Sendable {
    public var number: Int
    public var era: Era
    public var groups: [SpawnGroup]

    public var isBossWave: Bool = false
    /// Gold for clearing this wave. nil = use the economy formula.
    public var clearReward: Int?
    /// What the wave tests (Swarm, Speed, Air, Armored, Tank, Elite, Stealth, Mixed, Boss…), shown in the wave intel.
    public var theme: String?

    enum CodingKeys: String, CodingKey { case number, era, groups, isBossWave, clearReward, theme }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        era = try c.decode(Era.self, forKey: .era)
        groups = try c.decode([SpawnGroup].self, forKey: .groups)
        isBossWave = try c.decodeIfPresent(Bool.self, forKey: .isBossWave) ?? false
        clearReward = try c.decodeIfPresent(Int.self, forKey: .clearReward)
        theme = try c.decodeIfPresent(String.self, forKey: .theme)
    }

    public init(number: Int, era: Era, groups: [SpawnGroup], isBossWave: Bool = false, clearReward: Int? = nil) {
        self.number = number; self.era = era; self.groups = groups; self.isBossWave = isBossWave
        self.clearReward = clearReward
    }

    public var totalEnemies: Int { groups.reduce(0) { $0 + $1.count } }
}
