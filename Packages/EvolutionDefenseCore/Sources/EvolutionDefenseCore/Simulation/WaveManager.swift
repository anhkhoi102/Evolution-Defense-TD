import Foundation

/// What happened during one wave, shown to the player in the preparation phase.
public struct WaveSummary: Sendable, Equatable, Codable {
    public var number: Int
    public var enemiesDefeated = 0
    public var enemiesLeaked = 0
    public var baseDamageTaken = 0
    public var killGold = 0
    public var clearBonus = 0
    public var perfectBonus = 0
    /// Bonus for starting this wave before the countdown ran out.
    public var earlyStartBonus = 0
    /// Research Points earned by this wave (perfect clear, bosses, era completion).
    public var researchEarned = 0

    public init(number: Int) { self.number = number }

    public var bonusGold: Int { clearBonus + perfectBonus + earlyStartBonus }
    public var totalGold: Int { killGold + bonusGold }
    /// No enemy got through and the base took no damage.
    public var isPerfect: Bool { enemiesLeaked == 0 && baseDamageTaken == 0 }
}

/// Owns the wave sequence: preparation countdown → spawning → completion.
/// Pure state machine; GameWorld feeds it time and reports kills/leaks.
public struct WaveManager: Sendable {
    public let waves: [WaveDefinition]
    public let timing: WaveTimingConfig

    /// Number of the running wave, or of the last finished wave (0 before wave 1).
    public private(set) var waveNumber = 0
    public private(set) var isWaveActive = false
    /// Seconds left before the next wave starts on its own.
    public private(set) var preparationRemaining: Double
    /// Length of the current preparation phase (for progress bars).
    public private(set) var preparationDuration: Double
    /// Running tally for the current wave.
    public private(set) var tally = WaveSummary(number: 0)
    /// Summary of the most recently finished wave.
    public private(set) var lastSummary: WaveSummary?

    private var spawner = EnemySpawner()

    public init(waves: [WaveDefinition], timing: WaveTimingConfig) {
        self.waves = waves
        self.timing = timing
        preparationRemaining = timing.initialPreparationTime
        preparationDuration = timing.initialPreparationTime
    }

    public var totalWaves: Int { waves.count }
    public var hasNextWave: Bool { waveNumber < waves.count }
    public var nextWave: WaveDefinition? { hasNextWave ? waves[waveNumber] : nil }
    public var currentWave: WaveDefinition? { waveNumber > 0 ? waves[waveNumber - 1] : nil }
    public var isLastWave: Bool { waveNumber >= waves.count }
    public var enemiesLeftToSpawn: Int { isWaveActive ? spawner.remaining : 0 }
    public var spawningFinished: Bool { spawner.isFinished }

    /// Counts the preparation timer down unless `held`. Returns true when it expires.
    mutating func tickPreparation(_ dt: Double, held: Bool) -> Bool {
        guard !isWaveActive, hasNextWave else { return false }
        if !held { preparationRemaining = max(0, preparationRemaining - dt) }
        return preparationRemaining <= 0
    }

    /// Starts the next wave. Returns it, or nil if a wave is running / none remain.
    mutating func beginNextWave(earlyStartBonus: Int) -> WaveDefinition? {
        guard !isWaveActive, let wave = nextWave else { return nil }
        waveNumber += 1
        spawner.load(wave)
        isWaveActive = true
        tally = WaveSummary(number: waveNumber)
        tally.earlyStartBonus = earlyStartBonus
        preparationRemaining = 0
        return wave
    }

    mutating func updateSpawns(_ dt: Double, spawn: (EnemySpawner.ScheduledSpawn) -> Void) {
        guard isWaveActive else { return }
        spawner.update(dt, spawn: spawn)
    }

    mutating func recordKill(gold: Int) {
        guard isWaveActive else { return }
        tally.enemiesDefeated += 1
        tally.killGold += gold
    }

    mutating func recordLeak(damage: Int) {
        guard isWaveActive else { return }
        tally.enemiesLeaked += 1
        tally.baseDamageTaken += damage
    }

    /// Ends the running wave with its rewards and starts the next preparation phase.
    /// Base damage that didn't come from a leak (e.g. a missile strike).
    mutating func recordBaseDamage(_ damage: Int) {
        guard isWaveActive else { return }
        tally.baseDamageTaken += damage
    }

    /// Checkpoint restore: `n` waves are done and the next preparation phase starts now.
    mutating func restore(clearedWaves n: Int) {
        isWaveActive = false
        waveNumber = max(0, min(waves.count - 1, n))
        let t = n == 0 ? timing.initialPreparationTime : timing.preparationTime
        preparationRemaining = t
        preparationDuration = t
    }

    /// Tools/tests: pretend `n` waves are already done.
    mutating func debugSkip(to n: Int) {
        guard !isWaveActive else { return }
        waveNumber = max(0, min(waves.count - 1, n))
        preparationRemaining = timing.preparationTime
        preparationDuration = timing.preparationTime
    }

    mutating func recordResearch(_ points: Int) {
        guard isWaveActive else { return }
        tally.researchEarned += points
    }

    mutating func finishWave(clearBonus: Int, perfectBonus: Int, research: Int = 0) -> WaveSummary {
        tally.clearBonus = clearBonus
        tally.perfectBonus = perfectBonus
        tally.researchEarned += research
        isWaveActive = false
        lastSummary = tally
        preparationRemaining = timing.preparationTime
        preparationDuration = timing.preparationTime
        return tally
    }
}
