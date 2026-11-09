import Foundation

// MARK: - Difficulty

/// Difficulty levels. Standard mode runs on any of them; the multipliers live
/// in difficulty.json so new levels (or an Endless mode's scaling) are data.
public enum Difficulty: String, Codable, CaseIterable, Sendable, Identifiable {
    case easy, normal, hard
    public var id: String { rawValue }
}

public struct DifficultyDefinition: Codable, Sendable, Equatable {
    public var id: Difficulty
    public var name: String
    public var summary: String
    /// Enemy max HP multiplier.
    public var enemyHP: Double
    /// Enemy speed multiplier.
    public var enemySpeed: Double
    /// Multiplier on kill gold and wave-clear rewards.
    public var goldMultiplier: Double
    public var startingGold: Int
    public var startingResearch: Int
    /// Countdown between waves (seconds); nil = game.json value.
    public var preparationTime: Double?
}

/// How a match is set up. Saved with checkpoints.
public struct MatchOptions: Codable, Sendable, Equatable {
    public var difficulty: Difficulty
    /// Optional random events every 3–4 waves.
    public var randomEvents: Bool

    public init(difficulty: Difficulty = .normal, randomEvents: Bool = true) {
        self.difficulty = difficulty
        self.randomEvents = randomEvents
    }
}

// MARK: - Random events

public enum RandomEventKind: String, Codable, Sendable {
    /// Immediate gold: value + perWave × wave number.
    case gold
    /// Next technology costs `value` RP less (minimum 1).
    case researchDiscount
    /// Next wave: enemies get +value HP and +speedBonus speed, and pay +goldBonus gold.
    case mutation
    /// A random tower attacks at `value` × speed during the next wave.
    case breakdown
    /// A temporary allied tower (era level + 1) holds a free pad for the next wave.
    case reinforcement
}

public struct RandomEventDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Shown to the player; `{gold}`, `{tower}` and `{rp}` are filled in.
    public var summary: String
    /// SF Symbol name.
    public var icon: String
    public var kind: RandomEventKind
    public var value: Double
    public var perWave: Double?
    public var speedBonus: Double?
    public var goldBonus: Double?
    /// Relative chance of being picked.
    public var weight: Double
    /// Good for the player (green) or a challenge (orange).
    public var isPositive: Bool
}

/// When random events happen (game.json).
public struct RandomEventSchedule: Codable, Sendable {
    /// First event after this wave is cleared.
    public var firstAfterWave: Int
    public var minGap: Int
    public var maxGap: Int
}

// MARK: - Achievements

public enum AchievementKind: String, Codable, Sendable {
    case win
    case killBoss
    case towerLevel
    case allArchetypesAtLevel
    case techsResearched
    case winWithoutTech
    case goldEarned
    case perfectEra
    case winUnderSeconds
    case kills
    case winWithHPAtMost
    case winWithoutLeaks
    case reachEra
}

public struct AchievementDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var icon: String
    public var kind: AchievementKind
    public var value: Double?
    /// Boss id for `killBoss`.
    public var target: String?
    /// Only counts on this difficulty (or harder) when set.
    public var difficulty: Difficulty?
}
