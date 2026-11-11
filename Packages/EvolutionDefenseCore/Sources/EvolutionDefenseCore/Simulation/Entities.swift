import CoreGraphics

/// A live enemy on the path. Reference type so towers and projectiles can hold
/// it directly; `isActive` tells them when it has died or reached the base.
public final class Enemy {
    public let id: Int
    public let definition: EnemyDefinition
    public let maxHP: Double
    public internal(set) var hp: Double
    public internal(set) var armor: Double
    /// Speed before temporary effects (wave tuning × boss phase).
    public internal(set) var baseSpeed: Double
    /// Current speed including sprint, slow and stun.
    public internal(set) var speed: Double
    /// Distance travelled along the path (world units).
    public internal(set) var distance: CGFloat = 0
    public internal(set) var position: CGPoint = .zero
    /// Facing angle in radians.
    public internal(set) var heading: CGFloat = 0
    /// Sideways offset from the path centre so groups don't walk in single file.
    public let laneOffset: CGFloat
    public internal(set) var isAlive = true
    public internal(set) var reachedBase = false
    /// Simulation time of the last tower hit (renderer uses it for a hit flash).
    public internal(set) var lastHitTime: Double = -100
    /// Last time it took any damage, including burning (pauses regen and shield recharge).
    var lastDamageTime: Double = -100
    /// Wave tuning speed factor, kept so boss phases can rescale speed.
    let speedModifier: Double
    var segmentHint = 0

    // MARK: Abilities (current set, changes with boss phases)
    public internal(set) var abilities: EnemyAbilities
    /// Index into `definition.sortedPhases` of the active phase, −1 = base phase.
    public internal(set) var phaseIndex = -1
    public internal(set) var shieldHP: Double = 0
    public internal(set) var maxShieldHP: Double = 0
    public internal(set) var isCloaked = false
    public internal(set) var isSprinting = false
    var stealthTimer: Double = 0
    var sprintTimer: Double = 0
    var summonTimer: Double = 0
    var healTimer: Double = 0
    /// Last time a healer mended this enemy (heals from several healers don't stack).
    var lastHealedTime: Double = -100
    var disableTimer: Double = 0
    var strikeTimer: Double = 0
    var nextBroodHP: Double = 0
    /// Spawned by another enemy (split / summon / brood).
    public internal(set) var isSpawnedMinion = false
    /// Gold reward multiplier (difficulty, Enemy Mutation event).
    public internal(set) var rewardMultiplier = 1.0
    /// Elite variant (tougher, worth more gold, marked on screen).
    public internal(set) var isElite = false

    // MARK: Status effects (from tower hits)
    public internal(set) var slowAmount: Double = 0
    var slowUntil: Double = 0
    public internal(set) var burnDPS: Double = 0
    var burnUntil: Double = 0
    public internal(set) var stunnedUntil: Double = 0
    /// Armour Shred: armour currently stripped (never more than the armour itself).
    public internal(set) var shredAmount: Double = 0
    var shredCap: Double = 0
    var shredUntil: Double = 0
    /// Expose: extra damage taken from every source (0.2 = +20 %).
    public internal(set) var exposeAmount: Double = 0
    var exposeUntil: Double = 0
    /// Towers that last applied each effect: the extra damage it enables is credited to them.
    weak var shredSource: Tower?
    weak var exposeSource: Tower?
    /// Frozen solid until this time (a stun with its own look).
    public internal(set) var frozenUntil: Double = 0
    /// No new stun or freeze takes hold before this time (limits crowd control).
    var controlImmuneUntil: Double = 0
    /// Slows counted towards a freeze, and when that count started.
    var slowHits = 0
    var slowHitsSince: Double = -100
    /// A boss can next be interrupted at this time.
    var interruptReadyAt: Double = 0

    public var isFrozen: Bool { frozenUntil > 0 }
    /// Late-game trait (insulated, plated, phasing), if any.
    public internal(set) var trait: EnemyTrait?
    /// Phasing: out of reach of damage until this time, and when the next flicker starts.
    public internal(set) var phasedUntil: Double = 0
    var nextPhaseAt: Double = 0

    public var isShredded: Bool { shredAmount > 0 }
    public var isExposed: Bool { exposeAmount > 0 }
    /// Armour after shred.
    public var effectiveArmor: Double { max(0, armor - shredAmount) }

    public var isActive: Bool { isAlive && !reachedBase }
    public var isBoss: Bool { definition.isBoss }
    public var isFlying: Bool { definition.isFlying }
    public var radius: CGFloat { CGFloat(definition.radius) }
    public var hpFraction: Double { max(0, hp / maxHP) }
    public var shieldFraction: Double { maxShieldHP > 0 ? shieldHP / maxShieldHP : 0 }
    public var isBurning: Bool { burnDPS > 0 }
    public var isSlowed: Bool { slowAmount > 0 }
    public var phaseName: String? {
        phaseIndex >= 0 ? definition.sortedPhases[phaseIndex].name : nil
    }

    init(id: Int, definition: EnemyDefinition, modifiers: SpawnModifiers = SpawnModifiers(), laneOffset: CGFloat) {
        self.id = id
        self.definition = definition
        self.maxHP = definition.hp * modifiers.hp
        self.hp = maxHP
        self.armor = definition.armor + modifiers.armorBonus
        self.speedModifier = modifiers.speed
        self.baseSpeed = definition.speed * modifiers.speed
        self.speed = baseSpeed
        self.laneOffset = laneOffset
        self.abilities = definition.baseAbilities
        configureAbilityTimers()
    }

    /// Resets timers after spawning or entering a new phase.
    func configureAbilityTimers() {
        if let s = abilities.shield, maxShieldHP != s.hp {
            maxShieldHP = s.hp
            shieldHP = s.hp
        }
        if let s = abilities.stealth { stealthTimer = s.visible }
        if let s = abilities.sprint { sprintTimer = s.cooldown * 0.5 }
        if let s = abilities.summon { summonTimer = s.interval }
        if let h = abilities.healAura { healTimer = h.interval * 0.5 }
        if let d = abilities.disableTowers { disableTimer = d.interval * 0.6 }
        if let b = abilities.baseStrike { strikeTimer = b.interval * 0.5 }
        if let b = abilities.brood, nextBroodHP == 0 { nextBroodHP = maxHP * (1 - b.everyHPFraction) }
    }
}

public final class Tower {
    public let id: Int
    public let slotID: Int
    public let archetype: TowerArchetype
    public let definition: TowerDefinition
    public let position: CGPoint
    public internal(set) var level: Int = 1
    public var targeting: TargetingPriority
    /// Turret facing (radians). Turns towards the target.
    public internal(set) var aimAngle: CGFloat = .pi / 2
    public internal(set) var target: Enemy?
    public internal(set) var cooldown: Double = 0
    public internal(set) var totalInvested: Int
    public internal(set) var kills = 0
    /// Extra damage other attacks dealt because of this tower's Armour Shred or Expose.
    public internal(set) var assistDamage: Double = 0
    public internal(set) var damageDealt: Double = 0
    /// Simulation time of the last shot (renderer uses it for recoil).
    public internal(set) var lastFireTime: Double = -100
    /// Knocked out (fire breath, EMP) until this simulation time.
    public internal(set) var disabledUntil: Double = -1
    /// How long the current knock-out lasts in all (for the countdown ring).
    public internal(set) var disabledDuration: Double = 0
    /// Cannot be knocked out again before this time (set when it recovers).
    public internal(set) var protectedUntil: Double = -1

    /// Seconds until it works again (0 when it is working).
    public func disableRemaining(at time: Double) -> Double { max(0, disabledUntil - time) }
    /// Allied tower from a Reinforcement event: can't be sold or upgraded, leaves after the wave.
    public internal(set) var isTemporary = false
    /// Attack-speed factor from a Mechanical Breakdown event (1 = normal).
    public internal(set) var eventSpeedFactor = 1.0
    var retargetTimer: Double = 0
    /// Shots fired (chain lightning counts them).
    var shotCount = 0
    /// The target it has been firing at, and since when (focus fire).
    weak var focusTarget: Enemy?
    var focusSince: Double = 0

    /// Effective stats: this level's data with all researched tech applied.
    public internal(set) var stats: TowerLevelStats
    /// This level's stats straight from the data, without tech.
    public var baseStats: TowerLevelStats { definition.stats(level: level) }
    public var name: String { stats.name }
    public var isMaxLevel: Bool { level >= definition.maxLevel }

    public func isDisabled(at time: Double) -> Bool { time < disabledUntil }

    init(id: Int, slotID: Int, definition: TowerDefinition, position: CGPoint, modifiers: TechModifiers) {
        self.id = id
        self.slotID = slotID
        self.archetype = definition.archetype
        self.definition = definition
        self.position = position
        self.targeting = definition.defaultTargeting
        self.totalInvested = definition.buildCost
        self.stats = modifiers.apply(to: definition.stats(level: 1), archetype: definition.archetype)
    }

    func refreshStats(_ modifiers: TechModifiers) {
        stats = modifiers.apply(to: baseStats, archetype: archetype)
        stats.attacksPerSecond *= eventSpeedFactor
    }
}

/// Pooled projectile. The world reuses instances instead of allocating per shot.
public final class Projectile {
    /// Index in the world's projectile pool (stable for the life of the world).
    public let poolIndex: Int
    public internal(set) var isActive = false
    public internal(set) var kind: ProjectileKind = .stone
    /// Visual asset key for the renderer (`projectile.<visual>` in the asset manifest).
    public internal(set) var visual: String = "stone"
    public internal(set) var position: CGPoint = .zero
    public internal(set) var origin: CGPoint = .zero
    public internal(set) var targetPoint: CGPoint = .zero
    public internal(set) var heading: CGFloat = 0
    /// Total flight distance at launch; used for arcing visuals.
    public internal(set) var plannedDistance: CGFloat = 1
    public internal(set) var travelled: CGFloat = 0
    public internal(set) var isCritical = false
    var target: Enemy?
    var speed: CGFloat = 0
    var damage: Double = 0
    var aoeRadius: CGFloat = 0
    var armorPenetration: Double = 0
    var damageType: DamageType = .physical
    var hit = HitEffects()
    var canHitAir = false
    /// Damage at the edge of the blast as a fraction of the centre's.
    var edgeDamage: Double = 1
    /// Share of the damage that reaches bosses.
    var bossDamage: Double = 1
    /// This shot arcs on to more enemies.
    var chains = false
    weak var source: Tower?

    /// 0…1 progress of the flight, for arc height in the renderer.
    public var flightProgress: CGFloat { min(1, travelled / max(plannedDistance, 1)) }

    init(poolIndex: Int) { self.poolIndex = poolIndex }
}

/// A temporary allied unit from a summon ability (minion or hero). It walks to
/// enemies near its post, hits them through the normal damage model, and takes
/// contact damage from enemies touching it. It never blocks enemy movement.
public final class SummonUnit {
    public enum State: Sendable { case idle, moving, attacking }

    public let id: Int
    public let ability: SummonAbilityDefinition
    public let maxHP: Double
    public internal(set) var hp: Double
    public internal(set) var position: CGPoint
    /// Where the unit was placed; it returns here when nothing is in reach.
    public let post: CGPoint
    public internal(set) var heading: CGFloat
    public internal(set) var state: State = .idle
    public let spawnTime: Double
    public let expiresAt: Double
    public internal(set) var isAlive = true
    /// Current target (nil when idle or walking home).
    public internal(set) weak var target: Enemy?
    /// Time of the last attack (drives the attack animation).
    public internal(set) var lastAttackTime: Double = -100
    public internal(set) var lastHitTakenTime: Double = -100
    public internal(set) var damageDealt: Double = 0
    public internal(set) var kills = 0

    var attackCooldown: Double = 0
    var specialTimer: Double
    var retargetTimer: Double = 0

    public var stats: SummonUnitStats { ability.unit }
    public var isHero: Bool { ability.kind == .hero }
    public var hpFraction: Double { max(0, hp / maxHP) }

    init(id: Int, ability: SummonAbilityDefinition, at position: CGPoint, post: CGPoint, time: Double) {
        self.id = id
        self.ability = ability
        self.maxHP = ability.unit.hp
        self.hp = ability.unit.hp
        self.position = position
        self.post = post
        self.heading = -.pi / 2
        self.spawnTime = time
        self.expiresAt = time + ability.duration
        self.specialTimer = (ability.special?.interval ?? 0) * 0.5
    }

    public func remaining(at time: Double) -> Double { max(0, expiresAt - time) }
}
