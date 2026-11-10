import Foundation

/// A tower as stored in a checkpoint.
public struct SavedTower: Codable, Sendable, Equatable {
    public var slot: Int
    public var archetype: TowerArchetype
    public var level: Int
    public var targeting: TargetingPriority
    public var invested: Int
    public var kills: Int
    public var damageDealt: Double
    public var isTemporary: Bool
    public var eventSpeedFactor: Double
}

/// Everything needed to resume a match from the start of a preparation phase.
/// Taken automatically between waves; mid-wave progress isn't saved (enemies
/// and projectiles in flight would make saves large and fragile).
public struct MatchCheckpoint: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version = MatchCheckpoint.currentVersion
    public var savedAt: Date
    public var options: MatchOptions
    /// Waves already cleared.
    public var waveNumber: Int
    /// Era of the coming wave (for the Continue button).
    public var era: Era
    public var economy: Economy
    public var research: Int
    public var researchDiscount: Int
    public var researchedTechs: [String]
    public var baseHP: Int
    public var maxBaseHP: Int
    public var stats: MatchStats
    public var towers: [SavedTower]
    public var activeEvent: ActiveEvent?
    public var nextEventWave: Int
    public var rng: SeededRandom
    public var eventRNG: SeededRandom
    public var time: Double
    /// Base HP lost so far in this match, for the final star rating (optional: older saves don't have it).
    public var damageTaken: Int?
}

public enum CheckpointError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalid(String)
}

extension GameWorld {

    /// A checkpoint of the current state, or nil outside the preparation phase.
    public func makeCheckpoint(now: Date = Date()) -> MatchCheckpoint? {
        guard phase == .preparation else { return nil }
        return MatchCheckpoint(
            savedAt: now, options: options, waveNumber: waveNumber, era: currentEra, economy: economy,
            research: research, researchDiscount: researchDiscount, researchedTechs: researchedTechs,
            baseHP: baseHP, maxBaseHP: maxBaseHP, stats: stats,
            towers: towers.map {
                SavedTower(slot: $0.slotID, archetype: $0.archetype, level: $0.level, targeting: $0.targeting,
                           invested: $0.totalInvested, kills: $0.kills, damageDealt: $0.damageDealt,
                           isTemporary: $0.isTemporary, eventSpeedFactor: $0.eventSpeedFactor)
            },
            activeEvent: activeEvent, nextEventWave: nextEventWave, rng: rng, eventRNG: eventRNG, time: time,
            damageTaken: baseDamageTaken)
    }

    /// Restores a match at the start of the preparation phase it was saved in.
    public convenience init(config: GameConfiguration, checkpoint c: MatchCheckpoint) throws {
        guard c.version == MatchCheckpoint.currentVersion else { throw CheckpointError.unsupportedVersion(c.version) }
        guard (0..<config.waves.count).contains(c.waveNumber) else { throw CheckpointError.invalid("wave \(c.waveNumber)") }
        guard c.baseHP > 0, c.maxBaseHP > 0 else { throw CheckpointError.invalid("base HP") }
        self.init(config: config, options: c.options, seed: 0)
        economy = c.economy
        research = c.research
        researchDiscount = c.researchDiscount
        researchedTechs = c.researchedTechs.filter { config.tech($0) != nil }
        modifiers = TechModifiers(techs: researchedTechs.compactMap { config.tech($0) })
        maxBaseHP = c.maxBaseHP
        baseHP = min(c.baseHP, c.maxBaseHP)
        stats = c.stats
        if stats.perfectWavesByEra.count != Era.allCases.count { stats.perfectWavesByEra = [0, 0, 0, 0] }
        waves.restore(clearedWaves: c.waveNumber)
        activeEvent = c.activeEvent
        nextEventWave = c.nextEventWave
        rng = c.rng
        eventRNG = c.eventRNG
        time = c.time
        // An older save has no count: what is missing from the base now is the best estimate.
        baseDamageTaken = c.damageTaken ?? max(0, c.maxBaseHP - c.baseHP)
        for s in c.towers {
            guard let slot = slot(withID: s.slot), towersBySlot[s.slot] == nil, let def = config.towers[s.archetype] else { continue }
            let t = Tower(id: makeID(), slotID: s.slot, definition: def, position: config.map.slotPosition(slot), modifiers: modifiers)
            t.level = max(1, min(def.maxLevel, s.level))
            t.targeting = s.targeting
            t.totalInvested = s.invested
            t.kills = s.kills
            t.damageDealt = s.damageDealt
            t.isTemporary = s.isTemporary
            t.eventSpeedFactor = s.eventSpeedFactor
            t.refreshStats(modifiers)
            towers.append(t)
            towersBySlot[s.slot] = t
            events.append(.towerBuilt(t))
        }
    }
}
