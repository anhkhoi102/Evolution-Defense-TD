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
}

public enum SummonKind: String, Codable, Sendable {
    /// A small squad of short-lived units (good against groups of weaker enemies).
    case minion
    /// One powerful unit that goes after elites and bosses.
    case hero
}

/// Hero archetypes. Only `warrior` is implemented; the others are reserved so
/// data can name them without changing the format.
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
}

/// A periodic area attack (e.g. the warrior's Whirlwind Cleave).
public struct SummonSpecial: Codable, Sendable, Equatable {
    public var name: String
    public var interval: Double
    public var damage: Double
    public var radius: Double
}
