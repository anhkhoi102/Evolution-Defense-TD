import Foundation

/// summons.json: the temporary-reinforcement abilities and their balance.
/// Every number for minions and heroes lives here (Docs/SUMMONS.md).
public struct SummonConfig: Codable, Sendable, Equatable {
    /// Enemies touching a summoned unit hurt it by `baseDamage × perBaseDamage`
    /// per second, at most `maxPerEnemy` (enemies themselves are unchanged).
    public var contactDamage: ContactDamage
    /// How far from the road's centre line a summon may be placed (world points).
    public var maxDeployDistanceFromPath: Double
    public var abilities: [SummonAbilityDefinition]

    public struct ContactDamage: Codable, Sendable, Equatable {
        public var perBaseDamage: Double
        public var maxPerEnemy: Double
        public init(perBaseDamage: Double, maxPerEnemy: Double) {
            self.perBaseDamage = perBaseDamage; self.maxPerEnemy = maxPerEnemy
        }
    }

    public init(contactDamage: ContactDamage, maxDeployDistanceFromPath: Double, abilities: [SummonAbilityDefinition]) {
        self.contactDamage = contactDamage; self.maxDeployDistanceFromPath = maxDeployDistanceFromPath
        self.abilities = abilities
    }

    /// No summons (configurations without summons.json).
    public static let none = SummonConfig(contactDamage: ContactDamage(perBaseDamage: 0, maxPerEnemy: 0),
                                          maxDeployDistanceFromPath: 0, abilities: [])

    public func ability(_ id: String) -> SummonAbilityDefinition? { abilities.first { $0.id == id } }

    /// Every hero the player can choose from, in menu order. One hero is taken into a match.
    public var heroes: [SummonAbilityDefinition] { abilities.filter { $0.kind == .hero } }
    /// The hero everyone starts with (the first one that needs no campaign progress).
    public var defaultHero: SummonAbilityDefinition? { heroes.first { $0.requiredStage == 0 } ?? heroes.first }
    /// The hero for `id`, or the default when the id is unknown.
    public func hero(_ id: String?) -> SummonAbilityDefinition? { heroes.first { $0.id == id } ?? defaultHero }
}

public enum SummonKind: String, Codable, Sendable {
    /// A small squad of short-lived units (good against groups of weaker enemies).
    case minion
    /// One powerful unit that goes after elites and bosses.
    case hero
}

/// Hero archetypes (a label for data and UI; behaviour comes from the unit's stats and special).
public enum HeroArchetype: String, Codable, Sendable {
    case warrior, mage, ranger, paladin
}

public struct SummonAbilityDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: SummonKind
    public var summary: String
    /// First wave in which the ability can be used (progressive unlock).
    public var unlockWave: Int
    public var cooldown: Double
    /// Seconds the units stay before vanishing.
    public var duration: Double
    public var count: Int
    /// Units are placed on a ring of this radius around the deployment point.
    public var formationRadius: Double
    public var unit: SummonUnitStats
    public var archetype: HeroArchetype?
    public var special: SummonSpecial?
    /// Key into the asset manifest (`summon.<visual>`).
    public var visual: String
    /// Keyboard shortcut shown in the UI.
    public var hotkey: String?
    /// Heroes: campaign stage that must have been cleared (on any battlefield) to unlock. Nil = always available.
    public var unlockStage: Int?
    /// Heroes: the unit's own name ("Iron King") and a short role line ("Tough melee guard").
    public var heroName: String?
    public var role: String?

    public var requiredStage: Int { unlockStage ?? 0 }
    /// Name of the summoned unit (falls back to the ability name).
    public var unitName: String { heroName ?? name }
}

public struct SummonUnitStats: Codable, Sendable, Equatable {
    public var hp: Double
    public var damage: Double
    public var attacksPerSecond: Double
    /// Reach of an attack (world points, between unit centre and enemy edge).
    public var range: Double
    /// Enemies closer than this to the unit's post are engaged.
    public var aggroRange: Double
    /// How far the unit will chase from its post before giving up.
    public var leash: Double
    public var moveSpeed: Double
    public var armorPenetration: Double
    public var damageType: DamageType
    public var canTargetAir: Bool
    /// Body radius for contact with enemies.
    public var radius: Double
    /// Share of contact damage ignored (0…1). Tough units such as the King.
    public var damageReduction: Double?
    /// Attacks are thrown or cast from a distance (drawn as a bolt).
    public var ranged: Bool?

    public var isRanged: Bool { ranged ?? false }
}

/// A periodic special attack while fighting.
///  * area (default): everything within `radius` is hit (Whirlwind Cleave, Royal Slam);
///    `slow`/`slowDuration` also slows what it hits.
///  * with `maxTargets`: only the toughest few enemies within `radius` are hit (Starfall).
public struct SummonSpecial: Codable, Sendable, Equatable {
    public var name: String
    public var interval: Double
    public var damage: Double
    public var radius: Double
    /// Slow applied to enemies hit (0…1) and for how long. Bosses take half, as with towers.
    public var slow: Double?
    public var slowDuration: Double?
    /// Hit only the `maxTargets` enemies with the most health in range.
    public var maxTargets: Int?
}
