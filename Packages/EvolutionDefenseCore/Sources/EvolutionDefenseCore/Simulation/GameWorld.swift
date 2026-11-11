import CoreGraphics
import Foundation

public enum MatchPhase: Equatable, Sendable {
    /// Between waves: countdown running, player builds / upgrades / repairs.
    case preparation
    case waveInProgress
    case victory
    case defeat

    public var isOver: Bool { self == .victory || self == .defeat }
}

public enum BuildResult: Equatable, Sendable {
    case success(towerID: Int)
    case invalidSlot
    case slotOccupied
    case insufficientGold(needed: Int, available: Int)
    case matchOver
}

public enum UpgradeResult: Equatable, Sendable {
    case success(newLevel: Int, cost: Int)
    case maxLevel
    case insufficientGold(needed: Int, available: Int)
    case unknownTower
    /// Temporary towers (Reinforcement event) can't be upgraded or sold.
    case notAllowed
    case matchOver
}

public enum SellResult: Equatable, Sendable {
    case success(refund: Int)
    case unknownTower
    case notAllowed
    case matchOver
}

public enum RepairResult: Equatable, Sendable {
    case success(healed: Int, cost: Int)
    case notInPreparation
    case baseAtFullHealth
    case insufficientGold(needed: Int, available: Int)
    case invalidOption
    case matchOver
}

public enum StartWaveResult: Equatable, Sendable {
    case started(number: Int, earlyBonus: Int)
    case waveAlreadyRunning
    case noWavesLeft
    case matchOver
}

public enum RecoverResult: Equatable, Sendable {
    case success(cost: Int)
    /// The tower is working (it recovered by itself, or was already restarted).
    case notDisabled
    case insufficientGold(needed: Int, available: Int)
    case unknownTower
    case matchOver
}

public enum ResearchResult: Equatable, Sendable {
    case success(cost: Int)
    case unknownTech
    case alreadyResearched
    case eraLocked(requires: Era)
    case insufficientResearch(needed: Int, available: Int)
    /// Another technology of the same doctrine group was already chosen.
    case excluded(by: String)
    case matchOver
}

public enum TechStatus: Equatable, Sendable {
    case researched
    case available
    case unaffordable(needed: Int)
    case locked(requires: Era)
    /// The other doctrine of its pair was chosen instead.
    case excluded(by: String)
}

/// Things that happened during a step. The renderer/audio/UI drain these each frame.
/// Team effects towers put on enemies (Docs/TOWER_EFFECTS.md).
/// A patch of burning ground: ground enemies on it keep burning.
public struct BurnZone: Sendable {
    public var towerID: Int
    public var position: CGPoint
    public var radius: Double
    public var dps: Double
    public var until: Double
    var nextTick: Double
}

public enum TowerStatus: Sendable { case shred, expose, freeze, execute, interrupt }

public enum GameEvent {
    /// A tower effect took hold on an enemy that did not have it (for markers and sounds).
    case statusApplied(Enemy, TowerStatus)
    /// Chain lightning jumped from the first point through the others.
    case chainLightning([CGPoint])
    /// A piercing shot carried on from its target to the last enemy it went through.
    case piercingShot(from: CGPoint, to: CGPoint)
    /// A blast left burning ground.
    case groundFire(position: CGPoint, radius: Double, duration: Double)
    case enemySpawned(Enemy)
    case bossSpawned(Enemy)
    case enemyKilled(Enemy, reward: Int)
    case enemyReachedBase(Enemy, damage: Int)
    case towerBuilt(Tower)
    case towerUpgraded(Tower, cost: Int)
    case towerSold(Tower, refund: Int)
    case towerFired(Tower, Projectile)
    case projectileImpact(kind: ProjectileKind, position: CGPoint, aoeRadius: CGFloat, hit: Bool)
    case baseDamaged(amount: Int, remaining: Int)
    /// The wave shield (Energy Shield tech) soaked up damage.
    case baseShieldAbsorbed(amount: Int, remaining: Int)
    case baseRepaired(amount: Int, cost: Int)
    case waveStarted(number: Int, earlyBonus: Int)
    case waveCleared(WaveSummary)
    case preparationStarted(seconds: Double)
    case matchEnded(MatchPhase)

    // Phase 3: evolution
    case criticalHit(Enemy, damage: Double)
    case enemyPhaseChanged(Enemy, name: String)
    case enemySplit(Enemy, count: Int)
    case enemiesSummoned(by: Enemy, ability: String, count: Int)
    /// A healer pulsed: `count` nearby enemies were mended.
    case enemiesHealed(by: Enemy, ability: String, count: Int, radius: Double)
    /// Summons: units arrived, hit an enemy, used their special, fell, ran out of time, or the ability is ready again.
    case summonDeployed(SummonAbilityDefinition, units: [SummonUnit], at: CGPoint)
    case summonAttacked(SummonUnit, Enemy)
    case summonSpecial(SummonUnit, name: String, radius: Double, hits: Int, targets: [Enemy])
    case summonDefeated(SummonUnit)
    case summonExpired(SummonUnit)
    case summonReady(SummonAbilityDefinition)
    case towersDisabled([Tower], by: Enemy, ability: String, duration: Double)
    /// A disabled tower works again (`paid` = gold for an instant recovery, 0 = it recovered by itself).
    case towerRecovered(Tower, paid: Int)
    case baseStruck(by: Enemy, ability: String, damage: Int)
    case researchEarned(amount: Int, reason: String)
    case techResearched(TechDefinition)
    /// The last wave of `from` was cleared; the next preparation phase belongs to `to`.
    case eraAdvanced(from: Era, to: Era)

    // Phase 4: random events
    /// A random event happened; `text` is its summary with values filled in.
    case randomEvent(RandomEventDefinition, text: String)
    /// A temporary tower left (Reinforcement ended).
    case towerRemoved(Tower)
}

public struct MatchStats: Sendable, Equatable {
    public var enemiesKilled = 0
    public var enemiesLeaked = 0
    public var goldEarned = 0
    public var goldSpent = 0
    public var wavesCleared = 0
    public var towersBuilt = 0
    public var upgradesBought = 0
    public var hpRepaired = 0
    public var bossesDefeated = 0
    public var researchEarned = 0
    public var techsResearched = 0
    /// Boss ids killed this match.
    public var bossesKilled: [String] = []
    /// Waves cleared with nothing reaching the base, per era (index 0 = Primitive).
    public var perfectWavesByEra: [Int] = [0, 0, 0, 0]
    /// Highest era seen this match (1…4).
    public var highestEra = 1
    public var randomEvents = 0
    public init() {}
}

extension MatchStats: Codable {}

/// The authoritative game simulation. No rendering, no SpriteKit:
/// it is stepped with a fixed timestep and can run headless in tests.
///
/// Split across files: this one holds state, player actions and the step loop;
/// `+Combat` towers/projectiles/damage, `+Abilities` enemy behaviours and status
/// effects, `+Research` the tech tree.
public final class GameWorld {
    public let config: GameConfiguration
    public let path: PathGeometry
    public let options: MatchOptions
    public let difficulty: DifficultyDefinition

    public internal(set) var time: Double = 0
    public internal(set) var enemies: [Enemy] = []
    public internal(set) var towers: [Tower] = []
    public internal(set) var projectiles: [Projectile] = []
    public internal(set) var baseHP: Int
    public internal(set) var maxBaseHP: Int
    /// Temporary shield on the base for the current wave (Energy Shield tech).
    public internal(set) var baseShield = 0
    public internal(set) var phase: MatchPhase = .preparation
    public internal(set) var waves: WaveManager
    public internal(set) var economy: Economy
    public internal(set) var stats = MatchStats()

    /// Research Points available to spend on technology.
    public internal(set) var research: Int
    /// Researched tech ids, in purchase order.
    public internal(set) var researchedTechs: [String] = []
    /// Combined effect of researched tech (towers read it when stats refresh).
    public internal(set) var modifiers = TechModifiers(techs: [])

    /// Set by the UI while the player manages towers/base/tech: the
    /// preparation countdown stops so decisions aren't rushed.
    public var holdPreparationCountdown = false

    public var gold: Int { economy.gold }
    public var waveNumber: Int { waves.waveNumber }
    public var totalWaves: Int { waves.totalWaves }
    public var preparationRemaining: Double { waves.preparationRemaining }
    /// The era being fought, or — between waves — the era of the coming wave.
    public var currentEra: Era {
        (phase == .waveInProgress ? waves.currentWave : (waves.nextWave ?? waves.currentWave))?.era ?? .primitive
    }
    public var enemiesRemainingInWave: Int { waves.enemiesLeftToSpawn + enemies.count }

    /// Gold awarded for starting the next wave right now (0 if not in preparation).
    public var earlyStartBonus: Int {
        guard phase == .preparation, waves.hasNextWave else { return 0 }
        return Int((waves.preparationRemaining * config.rules.economy.earlyStartGoldPerSecond).rounded(.down))
    }

    var events: [GameEvent] = []
    var freeProjectiles: [Int] = []
    var towersBySlot: [Int: Tower] = [:]
    var rng: SeededRandom
    /// Separate stream so random events don't change combat randomness.
    var eventRNG: SeededRandom
    var nextID = 1
    let minDamageFraction: Double
    let retargetInterval: Double
    /// Reused scratch buffer for ability target selection.
    var scratchTowers: [Tower] = []

    // Random events
    /// Wave after whose clear the next random event happens.
    public internal(set) var nextEventWave: Int
    /// Event affecting the coming / running wave, if any.
    public internal(set) var activeEvent: ActiveEvent?
    /// RP discount on the next technology (Technology Boost).
    public internal(set) var researchDiscount = 0
    /// Difficulty-curve phase of the current wave (refreshed every step, before spawning).
    public internal(set) var activePhase = ProgressionPhase.neutral

    // Summon abilities (GameWorld+Summons). Not saved in checkpoints: a resumed
    // match starts with every ability ready.
    /// Allied units currently on the field.
    public internal(set) var summons: [SummonUnit] = []
    /// Simulation time at which each ability is off cooldown (missing = ready).
    var summonReadyAt: [String: Double] = [:]
    /// Abilities whose "ready" event has been sent since their last use.
    var summonReadyAnnounced: Set<String> = []
    /// Summon abilities used this match.
    public internal(set) var summonsCalled = 0
    /// Burning ground left by blasts (one per tower).
    public internal(set) var burnZones: [BurnZone] = []
    /// Base HP lost over the whole match (repairs don't reduce it): what the star rating looks at.
    public internal(set) var baseDamageTaken = 0
    /// The match's star rating: 1–3 once it is won, 0 before that or after a defeat.
    public var matchStars: Int {
        phase == .victory ? (config.rules.stars ?? StarRatingConfig()).stars(damage: baseDamageTaken, maxBaseHP: maxBaseHP) : 0
    }

    /// Tests and tools default to no random events so results are reproducible.
    public init(config: GameConfiguration, options: MatchOptions = MatchOptions(randomEvents: false),
                seed: UInt64 = 0xED_2026) {
        // The match plays on the battlefield named in its options (same rules, different map).
        let config = config.selecting(battlefield: options.battlefield)
        self.config = config
        self.options = options
        let diff = config.difficulty(options.difficulty)
        self.difficulty = diff
        self.path = config.map.makePath()
        self.maxBaseHP = config.rules.base.maxHP
        self.baseHP = min(config.rules.base.startingHP, config.rules.base.maxHP)
        self.economy = Economy(startingGold: diff.startingGold)
        self.research = diff.startingResearch
        var timing = config.rules.waveTiming
        if let p = diff.preparationTime { timing.preparationTime = p }
        self.waves = WaveManager(waves: config.progressionWaves(curve: diff.curve ?? 1), timing: timing)
        self.nextEventWave = config.rules.randomEvents.firstAfterWave
        self.rng = SeededRandom(seed: seed)
        self.eventRNG = SeededRandom(seed: seed ^ 0x5EED_E7E7)
        self.minDamageFraction = config.rules.minimumDamageFraction
        self.retargetInterval = config.rules.retargetInterval
        enemies.reserveCapacity(256)
        events.reserveCapacity(256)
        scratchTowers.reserveCapacity(16)
        growProjectilePool(by: 128)
        activePhase = config.rules.phase(forWave: 1, curve: diff.curve ?? 1)
    }

    // MARK: - Events

    /// Hands every pending event to `body`, then clears the queue (keeping capacity).
    public func drainEvents(_ body: (GameEvent) -> Void) {
        for e in events { body(e) }
        events.removeAll(keepingCapacity: true)
    }

    // MARK: - Queries

    public func tower(atSlot slotID: Int) -> Tower? { towersBySlot[slotID] }
    public func tower(withID id: Int) -> Tower? { towers.first { $0.id == id } }

    public func slot(withID id: Int) -> BuildSlotDefinition? {
        config.map.buildSlots.first { $0.id == id }
    }

    /// Stats an archetype would have at `level` with the current research.
    public func effectiveStats(_ a: TowerArchetype, level: Int) -> TowerLevelStats {
        modifiers.apply(to: config.tower(a).stats(level: level), archetype: a)
    }

    /// Gold needed for the tower's next level, or nil at max level.
    public func upgradeCost(for t: Tower) -> Int? {
        t.isMaxLevel ? nil : t.definition.stats(level: t.level + 1).cost
    }

    /// Gold to restart a disabled tower right now (nil when it is working).
    public func recoverCost(for t: Tower) -> Int? {
        guard t.isDisabled(at: time) else { return nil }
        let c = config.rules.towerDisable ?? TowerDisableConfig()
        let raw = Double(t.totalInvested) * c.recoverCostFraction
        let price = min(Double(c.recoverCostMax), max(Double(c.recoverCostMin), raw)) * modifiers.recoverCost
        return max(1, Int(price.rounded()))
    }

    /// Instant recovery: pays once and puts the same tower back to work. Waiting costs nothing.
    @discardableResult
    public func recover(_ t: Tower) -> RecoverResult {
        if phase.isOver { return .matchOver }
        guard towersBySlot[t.slotID] === t else { return .unknownTower }
        guard let cost = recoverCost(for: t) else { return .notDisabled }
        guard economy.spend(cost) else { return .insufficientGold(needed: cost, available: gold) }
        stats.goldSpent += cost
        endDisable(t)
        events.append(.towerRecovered(t, paid: cost))
        return .success(cost: cost)
    }

    /// Puts a tower back to work and starts its protection against the next disable.
    func endDisable(_ t: Tower) {
        t.disabledUntil = -1
        t.disabledDuration = 0
        t.protectedUntil = time + (config.rules.towerDisable ?? TowerDisableConfig()).protection
        t.retargetTimer = 0
    }

    public func sellValue(for t: Tower) -> Int {
        Int((Double(t.totalInvested) * config.rules.economy.sellRefundRatio).rounded(.down))
    }

    /// Actual HP healed and gold charged for a repair option right now.
    /// Partial repairs (base nearly full) cost proportionally less.
    public func repairQuote(optionIndex i: Int) -> (heal: Int, cost: Int)? {
        let options = config.rules.repair.options
        guard options.indices.contains(i) else { return nil }
        let o = options[i]
        let heal = min(o.hp, maxBaseHP - baseHP)
        guard heal > 0 else { return (0, 0) }
        let cost = Int((Double(o.cost) * Double(heal) / Double(o.hp)).rounded(.up))
        return (heal, cost)
    }

    public var canRepair: Bool { phase == .preparation && baseHP < maxBaseHP }

    // MARK: - Player actions: building

    public func canBuild(_ archetype: TowerArchetype, atSlot slotID: Int) -> BuildResult {
        if phase.isOver { return .matchOver }
        guard slot(withID: slotID) != nil else { return .invalidSlot }
        if towersBySlot[slotID] != nil { return .slotOccupied }
        let cost = config.tower(archetype).buildCost
        if !economy.canAfford(cost) { return .insufficientGold(needed: cost, available: gold) }
        return .success(towerID: 0)
    }

    @discardableResult
    public func build(_ archetype: TowerArchetype, atSlot slotID: Int) -> BuildResult {
        let check = canBuild(archetype, atSlot: slotID)
        guard case .success = check, let slot = slot(withID: slotID) else { return check }
        let def = config.tower(archetype)
        guard economy.spend(def.buildCost) else { return .insufficientGold(needed: def.buildCost, available: gold) }
        stats.goldSpent += def.buildCost
        stats.towersBuilt += 1
        let t = Tower(id: makeID(), slotID: slotID, definition: def, position: config.map.slotPosition(slot),
                      modifiers: modifiers)
        towers.append(t)
        towersBySlot[slotID] = t
        events.append(.towerBuilt(t))
        return .success(towerID: t.id)
    }

    // MARK: Upgrading / selling (allowed at any time during the match)

    @discardableResult
    public func upgrade(_ t: Tower) -> UpgradeResult {
        if phase.isOver { return .matchOver }
        guard towersBySlot[t.slotID] === t else { return .unknownTower }
        if t.isTemporary { return .notAllowed }
        guard let cost = upgradeCost(for: t) else { return .maxLevel }
        guard economy.spend(cost) else { return .insufficientGold(needed: cost, available: gold) }
        t.level += 1
        t.refreshStats(modifiers)
        t.totalInvested += cost
        t.retargetTimer = 0
        stats.goldSpent += cost
        stats.upgradesBought += 1
        events.append(.towerUpgraded(t, cost: cost))
        return .success(newLevel: t.level, cost: cost)
    }

    @discardableResult
    public func sell(_ t: Tower) -> SellResult {
        if phase.isOver { return .matchOver }
        guard towersBySlot[t.slotID] === t else { return .unknownTower }
        if t.isTemporary { return .notAllowed }
        let refund = sellValue(for: t)
        economy.refund(refund)
        towersBySlot[t.slotID] = nil
        towers.removeAll { $0 === t }
        t.target = nil
        events.append(.towerSold(t, refund: refund))
        return .success(refund: refund)
    }

    public func setTargeting(_ priority: TargetingPriority, for tower: Tower) {
        tower.targeting = priority
        tower.retargetTimer = 0
    }

    // MARK: Base repair (preparation phase only)

    @discardableResult
    public func repairBase(optionIndex i: Int) -> RepairResult {
        if phase.isOver { return .matchOver }
        guard phase == .preparation else { return .notInPreparation }
        guard let quote = repairQuote(optionIndex: i) else { return .invalidOption }
        guard quote.heal > 0 else { return .baseAtFullHealth }
        guard economy.spend(quote.cost) else { return .insufficientGold(needed: quote.cost, available: gold) }
        baseHP = min(maxBaseHP, baseHP + quote.heal)
        stats.goldSpent += quote.cost
        stats.hpRepaired += quote.heal
        events.append(.baseRepaired(amount: quote.heal, cost: quote.cost))
        return .success(healed: quote.heal, cost: quote.cost)
    }

    // MARK: Waves

    /// Starts the next wave now. Starting before the countdown ends pays an early bonus.
    @discardableResult
    public func startNextWave() -> StartWaveResult {
        if phase.isOver { return .matchOver }
        guard phase == .preparation else { return .waveAlreadyRunning }
        guard waves.hasNextWave else { return .noWavesLeft }
        let bonus = earlyStartBonus
        return beginWave(earlyBonus: bonus)
    }

    private func beginWave(earlyBonus: Int) -> StartWaveResult {
        guard let wave = waves.beginNextWave(earlyStartBonus: earlyBonus) else { return .noWavesLeft }
        activePhase = config.rules.phase(forWave: wave.number, curve: difficulty.curve ?? 1)
        if earlyBonus > 0 {
            economy.earn(earlyBonus)
            stats.goldEarned += earlyBonus
        }
        baseShield = modifiers.waveShield
        phase = .waveInProgress
        events.append(.waveStarted(number: wave.number, earlyBonus: earlyBonus))
        return .started(number: wave.number, earlyBonus: earlyBonus)
    }

    // MARK: - Simulation

    /// Advances the simulation by `dt` seconds. Call with a fixed timestep.
    public func step(_ dt: Double) {
        guard !phase.isOver else { return }
        time += dt
        activePhase = config.rules.phase(forWave: max(1, waves.waveNumber), curve: difficulty.curve ?? 1)

        switch phase {
        case .preparation:
            if waves.tickPreparation(dt, held: holdPreparationCountdown) {
                _ = beginWave(earlyBonus: 0)
            }
        case .waveInProgress:
            waves.updateSpawns(dt) { s in spawnEnemy(s.enemyID, modifiers: s.modifiers) }
        case .victory, .defeat:
            return
        }
        updateEnemyAbilities(dt)
        updateBurnZones()
        if phase == .defeat { return }
        moveEnemies(dt)
        if phase == .defeat { return }
        updateTowers(dt)
        updateSummons(dt)
        updateProjectiles(dt)
        enemies.removeAll { !$0.isActive }
        checkWaveCompletion()
    }

    /// Convenience for tests/tools: run `seconds` of game time in fixed steps.
    public func simulate(seconds: Double, step dt: Double = 1.0 / 60.0) {
        var t = 0.0
        while t < seconds && !phase.isOver {
            step(dt)
            t += dt
        }
    }

    // MARK: Enemies

    @discardableResult
    func spawnEnemy(_ enemyID: String, atDistance distance: CGFloat = 0,
                    modifiers: SpawnModifiers = SpawnModifiers(), minion: Bool = false) -> Enemy? {
        guard let def = config.enemies[enemyID] else { return nil }
        let spread = CGFloat(config.rules.laneSpread)
        let offset = def.isBoss ? 0 : CGFloat.random(in: -spread...spread, using: &rng)
        var mods = modifiers
        mods.hp *= difficulty.enemyHP
        mods.speed *= difficulty.enemySpeed
        var reward = difficulty.goldMultiplier
        // Difficulty curve: the phase of the running wave (summons and splits included).
        // Bosses are tuned directly in enemies.json, so only regular enemies scale.
        let phase = activePhase
        if !def.isBoss {
            mods.hp *= phase.enemyHP
            mods.speed *= phase.enemySpeed
        }
        reward *= phase.killReward
        if mods.elite, !def.isBoss {
            let el = config.rules.elite ?? EliteConfig()
            mods.hp *= el.hp
            mods.speed *= el.speed
            mods.armorBonus += el.armorBonus
            reward *= el.reward
        }
        if let m = activeMutation {
            mods.hp *= 1 + m.value
            mods.speed *= 1 + (m.speedBonus ?? 0)
            reward *= 1 + (m.goldBonus ?? 0)
        }
        let e = Enemy(id: makeID(), definition: def, modifiers: mods, laneOffset: offset)
        e.rewardMultiplier = reward
        e.isElite = mods.elite && !def.isBoss
        if !def.isBoss, let trait = mods.trait {
            e.trait = trait
            if trait == .phasing { e.nextPhaseAt = time + (config.rules.traits ?? TraitConfig()).phaseInterval * 0.6 }
        }
        e.isSpawnedMinion = minion
        e.distance = max(0, distance)
        let s = path.sample(at: e.distance, segmentHint: &e.segmentHint)
        e.position = s.position + s.direction.perpendicular * offset
        e.heading = s.direction.angle
        enemies.append(e)
        events.append(def.isBoss ? .bossSpawned(e) : .enemySpawned(e))
        return e
    }

    private func moveEnemies(_ dt: Double) {
        let total = path.totalLength
        let smoothing = CGFloat(min(1, dt * 14))
        for e in enemies where e.isActive {
            e.distance += CGFloat(e.speed * dt)
            if e.distance >= total {
                enemyReachedBase(e)
                if phase == .defeat { return }
                continue
            }
            let s = path.sample(at: e.distance, segmentHint: &e.segmentHint)
            let goal = s.position + s.direction.perpendicular * e.laneOffset
            // Ease towards the lane position so corners don't snap.
            let next = e.position + (goal - e.position) * smoothing
            let delta = next - e.position
            if delta.lengthSquared > 0.0001 { e.heading = delta.angle }
            e.position = next
        }
    }

    private func enemyReachedBase(_ e: Enemy) {
        e.reachedBase = true
        stats.enemiesLeaked += 1
        let lost = damageBase(e.definition.baseDamage)
        waves.recordLeak(damage: lost)
        events.append(.enemyReachedBase(e, damage: lost))
    }

    /// Applies damage to the base through Heavy Armor and the wave shield.
    /// Returns the HP actually lost. Ends the match at 0 HP.
    @discardableResult
    func damageBase(_ raw: Int) -> Int {
        guard raw > 0, phase != .defeat else { return 0 }
        var amount = raw
        if modifiers.leakDamageReduction > 0 {
            amount = max(1, Int((Double(raw) * (1 - modifiers.leakDamageReduction)).rounded()))
        }
        if baseShield > 0 {
            let absorbed = min(baseShield, amount)
            baseShield -= absorbed
            amount -= absorbed
            events.append(.baseShieldAbsorbed(amount: absorbed, remaining: baseShield))
        }
        guard amount > 0 else { return 0 }
        baseDamageTaken += min(amount, baseHP)
        baseHP = max(0, baseHP - amount)
        events.append(.baseDamaged(amount: amount, remaining: baseHP))
        if baseHP <= 0 {
            phase = .defeat
            dismissAllSummons()
            events.append(.matchEnded(.defeat))
        }
        return amount
    }

    // MARK: Wave completion

    private func checkWaveCompletion() {
        guard phase == .waveInProgress, waves.spawningFinished, enemies.isEmpty else { return }
        burnZones.removeAll()
        let n = waves.waveNumber
        let econ = config.rules.economy
        let wave = waves.currentWave
        let baseClear = wave?.clearReward ?? (econ.defaultWaveClearReward + econ.waveClearRewardGrowth * (n - 1))
        let clear = Int((Double(baseClear) * difficulty.goldMultiplier * config.rules.phase(forWave: n, curve: difficulty.curve ?? 1).clearReward).rounded())
        let perfect = waves.tally.isPerfect
        let perfectGold = perfect ? econ.perfectWaveBonus : 0
        economy.earn(clear + perfectGold)
        stats.goldEarned += clear + perfectGold
        stats.wavesCleared += 1

        var research = 0
        let rc = config.rules.research
        if perfect && rc.perfectWave > 0 && rc.paysPerfect(stage: n, isBoss: wave?.isBossWave ?? false) {
            research += rc.perfectWave
            events.append(.researchEarned(amount: rc.perfectWave, reason: "Perfect wave"))
        }
        let from = wave?.era ?? .primitive
        if perfect { stats.perfectWavesByEra[from.rawValue - 1] += 1 }
        let advancing = waves.nextWave.map { $0.era > from } ?? false
        if advancing && rc.eraCompletion > 0 {
            research += rc.eraCompletion
            events.append(.researchEarned(amount: rc.eraCompletion, reason: "\(from.displayName) complete"))
        }
        addResearch(research)

        let summary = waves.finishWave(clearBonus: clear, perfectBonus: perfectGold, research: research)
        events.append(.waveCleared(summary))
        if waves.isLastWave {
            phase = .victory
            dismissAllSummons()
            events.append(.matchEnded(.victory))
        } else {
            phase = .preparation
            endWaveEvent()
            if advancing, let to = waves.nextWave?.era {
                stats.highestEra = max(stats.highestEra, to.rawValue)
                events.append(.eraAdvanced(from: from, to: to))
            }
            rollRandomEventIfDue(afterWave: n)
            events.append(.preparationStarted(seconds: waves.preparationRemaining))
        }
    }

    func addResearch(_ points: Int) {
        guard points > 0 else { return }
        research += points
        stats.researchEarned += points
    }

    func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    // MARK: - Test / tool hooks

    /// Spawns an enemy directly (debug tools / tests).
    @discardableResult
    public func debugSpawn(_ enemyID: String, atDistance d: CGFloat = 0, elite: Bool = false) -> Enemy? {
        spawnEnemy(enemyID, atDistance: d, modifiers: SpawnModifiers(elite: elite))
    }

    public func debugSetGold(_ value: Int) { economy.debugSet(value) }

    public func debugSetBaseHP(_ value: Int) { baseHP = max(1, min(maxBaseHP, value)) }

    public func debugSetResearch(_ value: Int) { research = max(0, value) }

    /// Jumps straight to the preparation phase before `waveNumber` (tools, tests, snapshots).
    /// Only valid before the first wave has started.
    public func debugSkipToWave(_ waveNumber: Int) {
        guard phase == .preparation, waves.waveNumber == 0, waveNumber > 1 else { return }
        waves.debugSkip(to: waveNumber - 1)
    }
}
