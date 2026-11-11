import Foundation

/// What a technology changes. Each effect is one data entry in tech.json.
public enum TechEffectKind: String, Codable, Sendable {
    /// Tower damage × (1 + value).
    case damage
    /// Tower attacks per second × (1 + value).
    case attackSpeed
    /// Tower range × (1 + value).
    case range
    /// Explosion radius × (1 + value).
    case aoeRadius
    /// Tower armor penetration + value.
    case armorPenetration
    /// Adds on-hit effects (`hit`) to the towers.
    case onHit
    /// Towers see cloaked enemies.
    case stealthDetection
    /// Max base HP + value (also heals by the same amount).
    case maxBaseHP
    /// Damage from enemies reaching the base × (1 − value), minimum 1.
    case leakDamageReduction
    /// Base gets a shield worth `value` HP at the start of each wave.
    case waveShield
    /// Slows last (1 + value) times as long.
    case slowDuration
    /// A burning enemy that dies sets enemies within `value` points on fire.
    case burnSpread
    /// The third slow on an enemy within a few seconds freezes it for `value` seconds (bosses immune).
    case freeze
    /// Boss tower-disables last (1 − value) times as long.
    case disableDuration
    /// Instant tower recovery costs (1 − value) times as much.
    case recoverCost
    /// Stunned or frozen enemies take (1 + value) times the damage.
    case controlledBonus
    /// Chain lightning jumps to `value` more enemies.
    case chainTargets
    /// Expose also marks enemies within `value` points of the target.
    case exposeRadius
    /// Towers that keep firing at one target for 2 s attack (1 + value) times as fast.
    case focusFire
}

public struct TechEffect: Codable, Sendable, Equatable {
    public var kind: TechEffectKind
    /// Towers affected; nil = all towers. Ignored by base effects.
    public var archetypes: [TowerArchetype]?
    public var value: Double?
    public var hit: HitEffects?

    public init(kind: TechEffectKind, archetypes: [TowerArchetype]? = nil, value: Double? = nil, hit: HitEffects? = nil) {
        self.kind = kind; self.archetypes = archetypes; self.value = value; self.hit = hit
    }

    public func applies(to a: TowerArchetype) -> Bool { archetypes?.contains(a) ?? true }
}

public struct TechDefinition: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    /// Available once the match reaches this era.
    public var era: Era
    /// Research Points.
    public var cost: Int
    public var summary: String
    /// SF Symbol name for the UI.
    public var icon: String
    public var effects: [TechEffect]
    /// Doctrine group: only one technology of a group can be researched in a match.
    public var group: String?

    public var isDoctrine: Bool { group != nil }
}

/// Research Point income from game.json.
public struct ResearchConfig: Codable, Sendable {
    public var startingPoints: Int
    /// For clearing a wave without leaks.
    public var perfectWave: Int
    /// For clearing the last wave of an era.
    public var eraCompletion: Int
    /// After this stage, only boss stages pay the perfect-wave point (omitted = every stage pays).
    public var perfectWaveUntil: Int?
    /// Up to that stage, only every n-th stage pays it (omitted = every stage). Boss stages always pay.
    public var perfectWaveEvery: Int?

    public func paysPerfect(stage: Int, isBoss: Bool) -> Bool {
        if isBoss { return true }
        if let limit = perfectWaveUntil, stage > limit { return false }
        if let every = perfectWaveEvery, every > 1 { return stage % every == 0 }
        return true
    }
}

/// Combined effect of every researched technology. Recomputed on purchase only.
public struct TechModifiers: Sendable, Equatable {
    public struct TowerMods: Sendable, Equatable {
        public var damage = 1.0
        public var attackSpeed = 1.0
        public var range = 1.0
        public var aoeRadius = 1.0
        public var armorPenetration = 0.0
        public var hit = HitEffects()
        public var detectsStealth = false
        public var focusFire = 0.0
    }

    public var towers: [TowerArchetype: TowerMods] = [:]
    public var maxBaseHPBonus = 0
    public var leakDamageReduction = 0.0
    public var waveShield = 0
    public var slowDuration = 1.0
    public var burnSpreadRadius = 0.0
    public var freezeSeconds = 0.0
    public var disableDuration = 1.0
    public var recoverCost = 1.0
    public var controlledBonus = 0.0
    public var chainExtraTargets = 0
    public var exposeRadius = 0.0

    public init() {}

    public init(techs: [TechDefinition]) {
        for a in TowerArchetype.allCases { towers[a] = TowerMods() }
        for t in techs {
            for e in t.effects {
                let v = e.value ?? 0
                switch e.kind {
                case .maxBaseHP: maxBaseHPBonus += Int(v)
                case .leakDamageReduction: leakDamageReduction = min(0.9, leakDamageReduction + v)
                case .waveShield: waveShield += Int(v)
                case .slowDuration: slowDuration += v
                case .burnSpread: burnSpreadRadius = max(burnSpreadRadius, v)
                case .freeze: freezeSeconds = max(freezeSeconds, v)
                case .disableDuration: disableDuration = max(0.2, disableDuration - v)
                case .recoverCost: recoverCost = max(0, recoverCost - v)
                case .controlledBonus: controlledBonus += v
                case .chainTargets: chainExtraTargets += Int(v)
                case .exposeRadius: exposeRadius = max(exposeRadius, v)
                default:
                    for a in TowerArchetype.allCases where e.applies(to: a) {
                        var m = towers[a]!
                        switch e.kind {
                        case .damage: m.damage += v
                        case .attackSpeed: m.attackSpeed += v
                        case .range: m.range += v
                        case .aoeRadius: m.aoeRadius += v
                        case .armorPenetration: m.armorPenetration += v
                        case .onHit: if let h = e.hit { m.hit = m.hit.combined(with: h) }
                        case .stealthDetection: m.detectsStealth = true
                        case .focusFire: m.focusFire += v
                        default: break
                        }
                        towers[a] = m
                    }
                }
            }
        }
    }

    public func mods(for a: TowerArchetype) -> TowerMods { towers[a] ?? TowerMods() }

    /// Base stats of a level with all tower modifiers applied.
    public func apply(to s: TowerLevelStats, archetype a: TowerArchetype) -> TowerLevelStats {
        let m = mods(for: a)
        var r = s
        r.damage = s.damage * m.damage
        r.attacksPerSecond = s.attacksPerSecond * m.attackSpeed
        r.range = s.range * m.range
        r.aoeRadius = s.aoeRadius * m.aoeRadius
        r.armorPenetration = s.armorPenetration + m.armorPenetration
        var hit = s.hitEffects.combined(with: m.hit)
        if hit.slow > 0 { hit.slowDuration *= slowDuration }
        if hit.chainEvery > 0 { hit.chainTargets += Double(chainExtraTargets) }
        r.special = hit.isEmpty ? nil : hit
        r.detectsStealth = s.seesStealth || m.detectsStealth
        return r
    }
}
