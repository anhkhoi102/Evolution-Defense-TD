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
    /// Blast falloff: damage at the edge of the blast as a fraction of the centre's (the inner half
    /// of the radius takes full damage). Omitted = no falloff.
    public var aoeEdgeDamage: Double?
    /// Level whose base and weapon art this level uses (omitted = its own). A top level without
    /// its own model reuses the one below it; the renderer marks it with a glow.
    public var visualLevel: Int?
    /// Blind spot: enemies closer than this cannot be targeted (omitted = none).
    public var minRange: Double?
    /// Share of the damage that reaches bosses (omitted = all of it).
    public var bossDamage: Double?

    public var artLevel: Int { visualLevel ?? level }
    /// What this level cannot do, for the tower panel (shown with the effect labels).
    public var limitLabels: [String] {
        var l: [String] = []
        if let m = minRange, m > 0 { l.append("Blind spot \(Int(m))") }
        if let b = bossDamage, b < 1 { l.append("\(Int((b * 100).rounded()))% vs bosses") }
        return l
    }

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
    /// Seconds the target is stunned (bosses are immune; no new stun for a while afterwards).
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
    /// Execute: this much more damage (0.5 = +50 %) to targets below `executeThreshold` health
    /// (bosses: half the bonus).
    public var execute: Double
    public var executeThreshold: Double
    /// Chance of a critical hit (×`critMultiplier`) when the target is Exposed.
    public var exposedCritChance: Double
    /// Interrupt: seconds added to a boss's ability timers (each boss at most once per `interruptCooldown`).
    public var interrupt: Double
    /// Chain lightning: every `chainEvery`-th shot jumps to `chainTargets` more enemies within
    /// `chainRange` of the target for `chainDamage` × the hit, carrying this hit's other effects.
    public var chainEvery: Double
    public var chainTargets: Double
    public var chainRange: Double
    public var chainDamage: Double
    /// Burning ground: the blast leaves a fire for `groundDuration` seconds that burns ground enemies
    /// on it for this fraction of the hit per second. One fire per tower.
    public var groundBurn: Double
    public var groundDuration: Double
    /// More damage (0.2 = +20 %) to enemies that are slowed or burning.
    public var afflictedBonus: Double
    /// More damage to enemies above 80 % health.
    public var healthyBonus: Double
    /// Extra multiplier against energy shields for energy weapons (0.5 = shields break 50 % faster still).
    public var shieldBonus: Double
    /// Piercing shot: the shot carries on in a straight line through up to `pierceTargets` more
    /// enemies behind the target (within `pierceLength`), each for `pierceDamage` × the hit.
    public var pierceTargets: Double
    public var pierceDamage: Double
    public var pierceLength: Double

    public init(slow: Double = 0, slowDuration: Double = 0, burn: Double = 0, burnDuration: Double = 0, stun: Double = 0, critChance: Double = 0, critMultiplier: Double = 1, shred: Double = 0, shredCap: Double = 0, shredDuration: Double = 0, expose: Double = 0, exposeDuration: Double = 0, execute: Double = 0, executeThreshold: Double = 0, exposedCritChance: Double = 0, interrupt: Double = 0, chainEvery: Double = 0, chainTargets: Double = 0, chainRange: Double = 0, chainDamage: Double = 0, groundBurn: Double = 0, groundDuration: Double = 0, afflictedBonus: Double = 0, healthyBonus: Double = 0, shieldBonus: Double = 0, pierceTargets: Double = 0, pierceDamage: Double = 0, pierceLength: Double = 0) {
        self.slow = slow
        self.slowDuration = slowDuration
        self.burn = burn
        self.burnDuration = burnDuration
        self.stun = stun
        self.critChance = critChance
        self.critMultiplier = critMultiplier
        self.shred = shred
        self.shredCap = shredCap
        self.shredDuration = shredDuration
        self.expose = expose
        self.exposeDuration = exposeDuration
        self.execute = execute
        self.executeThreshold = executeThreshold
        self.exposedCritChance = exposedCritChance
        self.interrupt = interrupt
        self.chainEvery = chainEvery
        self.chainTargets = chainTargets
        self.chainRange = chainRange
        self.chainDamage = chainDamage
        self.groundBurn = groundBurn
        self.groundDuration = groundDuration
        self.afflictedBonus = afflictedBonus
        self.healthyBonus = healthyBonus
        self.shieldBonus = shieldBonus
        self.pierceTargets = pierceTargets
        self.pierceDamage = pierceDamage
        self.pierceLength = pierceLength
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
        execute = try c.decodeIfPresent(Double.self, forKey: .execute) ?? 0
        executeThreshold = try c.decodeIfPresent(Double.self, forKey: .executeThreshold) ?? 0
        exposedCritChance = try c.decodeIfPresent(Double.self, forKey: .exposedCritChance) ?? 0
        interrupt = try c.decodeIfPresent(Double.self, forKey: .interrupt) ?? 0
        chainEvery = try c.decodeIfPresent(Double.self, forKey: .chainEvery) ?? 0
        chainTargets = try c.decodeIfPresent(Double.self, forKey: .chainTargets) ?? 0
        chainRange = try c.decodeIfPresent(Double.self, forKey: .chainRange) ?? 0
        chainDamage = try c.decodeIfPresent(Double.self, forKey: .chainDamage) ?? 0
        groundBurn = try c.decodeIfPresent(Double.self, forKey: .groundBurn) ?? 0
        groundDuration = try c.decodeIfPresent(Double.self, forKey: .groundDuration) ?? 0
        afflictedBonus = try c.decodeIfPresent(Double.self, forKey: .afflictedBonus) ?? 0
        healthyBonus = try c.decodeIfPresent(Double.self, forKey: .healthyBonus) ?? 0
        shieldBonus = try c.decodeIfPresent(Double.self, forKey: .shieldBonus) ?? 0
        pierceTargets = try c.decodeIfPresent(Double.self, forKey: .pierceTargets) ?? 0
        pierceDamage = try c.decodeIfPresent(Double.self, forKey: .pierceDamage) ?? 0
        pierceLength = try c.decodeIfPresent(Double.self, forKey: .pierceLength) ?? 0
    }

    public var isEmpty: Bool { self == HitEffects() }

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
        r.execute = max(r.execute, o.execute)
        r.executeThreshold = max(r.executeThreshold, o.executeThreshold)
        r.exposedCritChance = max(r.exposedCritChance, o.exposedCritChance)
        r.interrupt = max(r.interrupt, o.interrupt)
        if o.chainEvery > 0 && (r.chainEvery == 0 || o.chainEvery < r.chainEvery) { r.chainEvery = o.chainEvery }
        r.chainTargets = max(r.chainTargets, o.chainTargets)
        r.chainRange = max(r.chainRange, o.chainRange)
        r.chainDamage = max(r.chainDamage, o.chainDamage)
        r.groundBurn = max(r.groundBurn, o.groundBurn)
        r.groundDuration = max(r.groundDuration, o.groundDuration)
        r.afflictedBonus = max(r.afflictedBonus, o.afflictedBonus)
        r.healthyBonus = max(r.healthyBonus, o.healthyBonus)
        r.shieldBonus = max(r.shieldBonus, o.shieldBonus)
        r.pierceTargets = max(r.pierceTargets, o.pierceTargets)
        r.pierceDamage = max(r.pierceDamage, o.pierceDamage)
        r.pierceLength = max(r.pierceLength, o.pierceLength)
        return r
    }

    /// Short labels for the UI.
    public var labels: [String] {
        var l: [String] = []
        func pct(_ v: Double) -> Int { Int((v * 100).rounded()) }
        if slow > 0 { l.append("Slows \(pct(slow))%") }
        if burn > 0 { l.append("Burns") }
        if groundBurn > 0 { l.append("Burning ground") }
        if stun > 0 { l.append("Stuns \(String(format: "%.1f", stun))s") }
        if critChance > 0 { l.append("\(pct(critChance))% crit ×\(String(format: "%.1f", critMultiplier))") }
        if shred > 0 { l.append("Shreds armour (up to −\(Int(shredCap)))") }
        if expose > 0 { l.append("Exposes +\(pct(expose))% damage") }
        if execute > 0 { l.append("Execute +\(pct(execute))% under \(pct(executeThreshold))% health") }
        if exposedCritChance > 0 { l.append("\(pct(exposedCritChance))% crit on Exposed") }
        if chainEvery > 0 { l.append("Chain lightning ×\(Int(chainTargets))") }
        if pierceTargets > 0 { l.append("Pierces \(Int(pierceTargets)) more in line") }
        if interrupt > 0 { l.append("Interrupts bosses") }
        if afflictedBonus > 0 { l.append("+\(pct(afflictedBonus))% vs slowed or burning") }
        if healthyBonus > 0 { l.append("+\(pct(healthyBonus))% vs healthy") }
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
    /// Linear upgrade path (level 1…6). The array form leaves room for
    /// branching upgrades later (e.g. a `branches` field per level).
    public var levels: [TowerLevelStats]

    public var maxLevel: Int { levels.count }

    public func stats(level: Int) -> TowerLevelStats {
        levels[max(0, min(levels.count - 1, level - 1))]
    }

    public var buildCost: Int { levels[0].cost }
    public var visualKey: String { visual ?? archetype.rawValue }
}
