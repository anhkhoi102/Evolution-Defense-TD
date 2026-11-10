import Foundation

/// The four permanent tower archetypes. They are available all game long;
/// eras never unlock new archetypes — each tower evolves through its own levels.
public enum TowerArchetype: String, Codable, CaseIterable, Sendable, Identifiable {
    case splash, sniper, heavy, rapid
    public var id: String { rawValue }
}

public enum TargetingPriority: String, Codable, CaseIterable, Sendable, Identifiable {
    case first, last, strongest, weakest, closest, boss
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .first: "First"
        case .last: "Last"
        case .strongest: "Strongest"
        case .weakest: "Weakest"
        case .closest: "Closest"
        case .boss: "Boss"
        }
    }
}

/// Visual/behavioural projectile family. The renderer picks art by this key.
public enum ProjectileKind: String, Codable, Sendable, CaseIterable {
    // Splash line
    case stone, boulder, cannonball, shell, plasmaOrb
    // Sniper line
    case arrow, longArrow, bolt, bullet, railSlug
    // Heavy line
    case spear, ballistaBolt, heavyShell, rocket, orbitalBeam
    // Rapid line
    case pellet, laser
}

/// Stats for one evolution level of one archetype. Every value is data-driven.
public struct TowerLevelStats: Codable, Sendable, Equatable {
    public var level: Int
    public var name: String
    /// Gold to reach this level. For level 1 this is the build cost.
    public var cost: Int
    public var damage: Double
    public var attacksPerSecond: Double
    public var range: Double
    public var projectileSpeed: Double
    /// Explosion radius. 0 = single target.
    public var aoeRadius: Double
    /// Armor ignored by each hit.
    public var armorPenetration: Double
    public var canTargetAir: Bool
    public var projectile: ProjectileKind
    /// Physical if omitted.
    public var damageType: DamageType?
    /// Visual asset key of the projectile (`projectile.<key>` in the asset manifest).
    /// Defaults to the projectile family name, so new looks need no code.
    public var projectileVisual: String?
    /// Built-in on-hit specials at this level (slow, stun, crits…). Tech adds to these.
    public var special: HitEffects?
    /// Sees cloaked enemies.
    public var detectsStealth: Bool?

    public var attackInterval: Double { 1.0 / max(attacksPerSecond, 0.01) }
    public var damagePerSecond: Double { damage * attacksPerSecond }
    public var type: DamageType { damageType ?? .physical }
    public var projectileAsset: String { projectileVisual ?? projectile.rawValue }
    public var hitEffects: HitEffects { special ?? HitEffects() }
    public var seesStealth: Bool { detectsStealth ?? false }
}

/// Extra effects a hit applies on top of damage. Every field defaults to "none".
public struct HitEffects: Codable, Sendable, Equatable {
    /// Fraction of speed removed (0.25 = 25 % slower).
    public var slow: Double
    public var slowDuration: Double
    /// Burn damage per second as a fraction of the hit's raw damage. Ignores armor.
    public var burn: Double
    public var burnDuration: Double
    /// Seconds the target is stunned (bosses are immune).
    public var stun: Double
    public var critChance: Double
    /// Damage multiplier on a critical hit.
    public var critMultiplier: Double
    /// Armour Shred: armour removed from the target per hit, stacking up to `shredCap`
    /// (bosses: half the cap) for `shredDuration` seconds after the last hit.
    public var shred: Double
    public var shredCap: Double
    public var shredDuration: Double
    /// Expose: the target takes this much more damage from every source (0.2 = +20 %)
    /// for `exposeDuration` seconds (bosses: half as long). Never stacks.
    public var expose: Double
    public var exposeDuration: Double

    public init(slow: Double = 0, slowDuration: Double = 0, burn: Double = 0, burnDuration: Double = 0,
                stun: Double = 0, critChance: Double = 0, critMultiplier: Double = 1,
                shred: Double = 0, shredCap: Double = 0, shredDuration: Double = 0,
                expose: Double = 0, exposeDuration: Double = 0) {
        self.slow = slow; self.slowDuration = slowDuration; self.burn = burn; self.burnDuration = burnDuration
        self.stun = stun; self.critChance = critChance; self.critMultiplier = critMultiplier
        self.shred = shred; self.shredCap = shredCap; self.shredDuration = shredDuration
        self.expose = expose; self.exposeDuration = exposeDuration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slow = try c.decodeIfPresent(Double.self, forKey: .slow) ?? 0
        slowDuration = try c.decodeIfPresent(Double.self, forKey: .slowDuration) ?? 0
        burn = try c.decodeIfPresent(Double.self, forKey: .burn) ?? 0
        burnDuration = try c.decodeIfPresent(Double.self, forKey: .burnDuration) ?? 0
        stun = try c.decodeIfPresent(Double.self, forKey: .stun) ?? 0
        critChance = try c.decodeIfPresent(Double.self, forKey: .critChance) ?? 0
        critMultiplier = try c.decodeIfPresent(Double.self, forKey: .critMultiplier) ?? 1
        shred = try c.decodeIfPresent(Double.self, forKey: .shred) ?? 0
        shredCap = try c.decodeIfPresent(Double.self, forKey: .shredCap) ?? 0
        shredDuration = try c.decodeIfPresent(Double.self, forKey: .shredDuration) ?? 0
        expose = try c.decodeIfPresent(Double.self, forKey: .expose) ?? 0
        exposeDuration = try c.decodeIfPresent(Double.self, forKey: .exposeDuration) ?? 0
    }

    public var isEmpty: Bool { slow == 0 && burn == 0 && stun == 0 && critChance == 0 && shred == 0 && expose == 0 }

    /// Strongest of each effect (effects from levels and tech don't stack additively).
    public func combined(with o: HitEffects) -> HitEffects {
        var r = self
        if o.slow > r.slow { r.slow = o.slow }
        r.slowDuration = max(r.slowDuration, o.slowDuration)
        if o.burn > r.burn { r.burn = o.burn }
        r.burnDuration = max(r.burnDuration, o.burnDuration)
        r.stun = max(r.stun, o.stun)
        r.critChance = min(1, r.critChance + o.critChance)
        r.critMultiplier = max(r.critMultiplier, o.critMultiplier)
        r.shred = max(r.shred, o.shred)
        r.shredCap = max(r.shredCap, o.shredCap)
        r.shredDuration = max(r.shredDuration, o.shredDuration)
        r.expose = max(r.expose, o.expose)
        r.exposeDuration = max(r.exposeDuration, o.exposeDuration)
        return r
    }

    /// Short labels for the UI.
    public var labels: [String] {
        var l: [String] = []
        if slow > 0 { l.append("Slows \(Int((slow * 100).rounded()))%") }
        if burn > 0 { l.append("Burns") }
        if stun > 0 { l.append("Stuns \(String(format: "%.1f", stun))s") }
        if critChance > 0 { l.append("\(Int((critChance * 100).rounded()))% crit ×\(String(format: "%.1f", critMultiplier))") }
        if shred > 0 { l.append("Shreds armour (up to −\(Int(shredCap)))") }
        if expose > 0 { l.append("Exposes +\(Int((expose * 100).rounded()))% damage") }
        return l
    }
}

public struct TowerDefinition: Codable, Sendable {
    public var archetype: TowerArchetype
    public var displayName: String
    public var role: String
    public var defaultTargeting: TargetingPriority
    /// Visual asset key (`tower.<key>.<level>.base/head` in the asset manifest).
    /// Defaults to the archetype name.
    public var visual: String?
    /// Linear upgrade path (level 1…5). The array form leaves room for
    /// branching upgrades later (e.g. a `branches` field per level).
    public var levels: [TowerLevelStats]

    public var maxLevel: Int { levels.count }

    public func stats(level: Int) -> TowerLevelStats {
        levels[max(0, min(levels.count - 1, level - 1))]
    }

    public var buildCost: Int { levels[0].cost }
    public var visualKey: String { visual ?? archetype.rawValue }
}
