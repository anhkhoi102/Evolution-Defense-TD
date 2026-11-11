import Foundation

public enum Era: Int, Codable, CaseIterable, Sendable, Comparable {
    case primitive = 1, medieval, industrial, futuristic

    public var displayName: String {
        switch self {
        case .primitive: "Primitive Age"
        case .medieval: "Medieval Age"
        case .industrial: "Industrial Age"
        case .futuristic: "Futuristic Age"
        }
    }

    public var next: Era? { Era(rawValue: rawValue + 1) }

    public static func < (a: Era, b: Era) -> Bool { a.rawValue < b.rawValue }
}

/// What a hit is made of. Enemies can resist each type separately.
public enum DamageType: String, Codable, CaseIterable, Sendable {
    /// Stones, arrows, bolts, bullets.
    case physical
    /// Cannonballs, shells, rockets.
    case explosive
    /// Plasma, lasers, rail slugs. Strips energy shields faster.
    case energy

    public var displayName: String {
        switch self {
        case .physical: "Physical"
        case .explosive: "Explosive"
        case .energy: "Energy"
        }
    }
}

/// Fraction of each damage type an enemy ignores (0 = none, 0.3 = 30 % less).
/// Applied before armor.
public struct Resistances: Codable, Sendable, Equatable {
    public var physical: Double
    public var explosive: Double
    public var energy: Double

    public init(physical: Double = 0, explosive: Double = 0, energy: Double = 0) {
        self.physical = physical; self.explosive = explosive; self.energy = energy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        physical = try c.decodeIfPresent(Double.self, forKey: .physical) ?? 0
        explosive = try c.decodeIfPresent(Double.self, forKey: .explosive) ?? 0
        energy = try c.decodeIfPresent(Double.self, forKey: .energy) ?? 0
    }

    public subscript(type: DamageType) -> Double {
        switch type {
        case .physical: physical
        case .explosive: explosive
        case .energy: energy
        }
    }

    public var isEmpty: Bool { physical == 0 && explosive == 0 && energy == 0 }
}

// MARK: - Abilities

/// Heals over time once it hasn't been hit for a moment.
public struct RegenAbility: Codable, Sendable, Equatable {
    public var perSecond: Double
    /// Seconds without taking damage before regeneration starts.
    public var delayAfterHit: Double
}

/// Periodic bursts of speed.
public struct SprintAbility: Codable, Sendable, Equatable {
    public var multiplier: Double
    public var duration: Double
    public var cooldown: Double
}

/// Cycles between visible and cloaked. Cloaked enemies can't be targeted
/// (splash still hits them) unless a tower detects stealth.
public struct StealthAbility: Codable, Sendable, Equatable {
    public var visible: Double
    public var hidden: Double
}

/// Absorbs damage before HP; recharges after a quiet period.
public struct ShieldAbility: Codable, Sendable, Equatable {
    public var hp: Double
    public var rechargeDelay: Double
    public var rechargePerSecond: Double
}

/// Enemies released when this one dies.
public struct SplitAbility: Codable, Sendable, Equatable {
    public var enemy: String
    public var count: Int
}

/// Support enemy: every `interval` seconds it heals other non-boss enemies
/// within `radius` by `fraction` of their max HP. Burning enemies can't be
/// healed (Fire Technology is the counter), and it never heals itself.
public struct HealAuraAbility: Codable, Sendable, Equatable {
    public var name: String
    public var radius: Double
    public var fraction: Double
    public var interval: Double
}

/// Calls reinforcements on a timer.
public struct SummonAbility: Codable, Sendable, Equatable {
    public var name: String
    public var enemy: String
    public var count: Int
    public var interval: Double
}

/// Releases enemies each time it loses another slice of its max HP.
public struct BroodAbility: Codable, Sendable, Equatable {
    public var name: String
    public var enemy: String
    public var count: Int
    /// e.g. 0.12 → spawns at 88 %, 76 %, 64 % … HP.
    public var everyHPFraction: Double
}

/// Knocks out nearby towers for a while (fire breath, EMP).
/// Rules every boss tower-disable follows, from game.json → "towerDisable". Bosses only ever switch
/// towers off for a while: nothing here (or anywhere) damages, destroys or removes a tower.
public struct TowerDisableConfig: Codable, Sendable, Equatable {
    /// Most towers that may be disabled at the same time, as a share of the player's towers (at least 1).
    public var maxShare: Double
    /// Seconds a tower cannot be disabled again after it recovers (either way).
    public var protection: Double
    /// Instant recovery price: this share of the gold spent on the tower, kept between the two limits.
    public var recoverCostFraction: Double
    public var recoverCostMin: Int
    public var recoverCostMax: Int

    public init(maxShare: Double = 0.25, protection: Double = 8, recoverCostFraction: Double = 0.08,
                recoverCostMin: Int = 15, recoverCostMax: Int = 120) {
        self.maxShare = maxShare; self.protection = protection; self.recoverCostFraction = recoverCostFraction
        self.recoverCostMin = recoverCostMin; self.recoverCostMax = recoverCostMax
    }
}

public struct DisableTowersAbility: Codable, Sendable, Equatable {
    public var name: String
    public var radius: Double
    public var duration: Double
    public var interval: Double
    public var maxTowers: Int
}

/// Damages the base directly from range (missile strike).
public struct BaseStrikeAbility: Codable, Sendable, Equatable {
    public var name: String
    public var damage: Int
    public var interval: Double
    /// The strike only fires once the enemy is this far along the road (0…1). A defence that holds
    /// it back takes no damage from it. Omitted = fires anywhere.
    public var minProgress: Double?
}

/// Optional behaviours. All fields are optional so new abilities can be
/// added to the data without touching existing enemies.
public struct EnemyAbilities: Codable, Sendable, Equatable {
    public var regen: RegenAbility?
    public var sprint: SprintAbility?
    public var stealth: StealthAbility?
    public var shield: ShieldAbility?
    public var splitOnDeath: SplitAbility?
    public var summon: SummonAbility?
    public var brood: BroodAbility?
    public var disableTowers: DisableTowersAbility?
    public var baseStrike: BaseStrikeAbility?
    public var healAura: HealAuraAbility?

    public init() {}

    /// `other`'s abilities replace these where present (boss phases).
    public func merged(with other: EnemyAbilities?) -> EnemyAbilities {
        guard let o = other else { return self }
        var r = self
        if let v = o.regen { r.regen = v }
        if let v = o.sprint { r.sprint = v }
        if let v = o.stealth { r.stealth = v }
        if let v = o.shield { r.shield = v }
        if let v = o.splitOnDeath { r.splitOnDeath = v }
        if let v = o.summon { r.summon = v }
        if let v = o.brood { r.brood = v }
        if let v = o.disableTowers { r.disableTowers = v }
        if let v = o.baseStrike { r.baseStrike = v }
        if let v = o.healAura { r.healAura = v }
        return r
    }

    /// Short labels for the UI.
    public var labels: [String] {
        var l: [String] = []
        if let h = healAura { l.append("Heals allies (\(h.name))") }   // support role first: it changes target priority
        if regen != nil { l.append("Regenerates") }
        if sprint != nil { l.append("Sprints") }
        if stealth != nil { l.append("Stealth") }
        if shield != nil { l.append("Energy shield") }
        if let s = splitOnDeath { l.append("Splits into \(s.count)") }
        if let s = summon { l.append(s.name) }
        if let b = brood { l.append(b.name) }
        if let d = disableTowers { l.append(d.name) }
        if let b = baseStrike { l.append(b.name) }
        return l
    }
}

/// A boss phase entered once HP drops below `belowHP` (fraction of max).
public struct BossPhase: Codable, Sendable, Equatable {
    public var belowHP: Double
    public var name: String
    /// Multiplies the base speed while in this phase.
    public var speedMultiplier: Double?
    /// Replaces the armor value (e.g. plating blown off).
    public var armor: Double?
    /// Abilities gained or replaced in this phase.
    public var abilities: EnemyAbilities?
}

public struct EnemyDefinition: Codable, Sendable, Identifiable {
    /// Stable identifier used by wave data, e.g. "wolf".
    public var id: String
    public var displayName: String
    public var era: Era
    public var hp: Double
    /// World units per second.
    public var speed: Double
    /// Flat damage reduction per hit (reduced by tower armor penetration).
    public var armor: Double
    /// Base HP lost when this enemy reaches the base.
    public var baseDamage: Int
    public var goldReward: Int
    public var isBoss: Bool
    public var isFlying: Bool
    /// Hit radius in world units (also drives sprite size).
    public var radius: Double
    /// Art key the renderer uses to pick textures.
    public var visual: String

    /// Enemy type label ("Beast", "Monster", "Mutant", "Robot").
    public var category: String?
    /// One-line description for intel cards.
    public var summary: String?
    public var resistances: Resistances?
    public var abilities: EnemyAbilities?
    /// Boss phases, any order in the file (sorted by threshold at load).
    public var phases: [BossPhase]?
    /// Research Points awarded when killed (bosses).
    public var researchReward: Int?
    /// The battlefield this creature belongs to (map id); nil = the shared campaign roster.
    /// Its art lives in that battlefield's atlas, so other maps never load it.
    public var battlefield: String?

    public var resistance: Resistances { resistances ?? Resistances() }
    public var baseAbilities: EnemyAbilities { abilities ?? EnemyAbilities() }
    /// Phases, highest threshold first (the loader sorts them; no allocation here).
    public var sortedPhases: [BossPhase] { phases ?? [] }
}
