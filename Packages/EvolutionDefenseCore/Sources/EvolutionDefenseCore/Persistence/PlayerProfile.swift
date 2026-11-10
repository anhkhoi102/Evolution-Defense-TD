import Foundation

/// Player preferences. Every field has a default so older save files still load.
public struct GameSettings: Codable, Sendable, Equatable {
    public var masterVolume = 0.8
    public var musicVolume = 0.55
    public var effectsVolume = 0.8
    public var musicEnabled = true
    public var effectsEnabled = true
    /// Fewer effects and texts for older/hot machines.
    public var performanceMode = false
    public var showFPS = false
    public var screenShake = true
    public var difficulty: Difficulty = .normal
    public var randomEvents = true
    /// Battlefield chosen in the menu (map id).
    public var battlefield = MatchOptions.defaultBattlefield
    /// Hero chosen in the menu (summon ability id); nil = the default hero.
    public var hero: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameSettings()
        masterVolume = try c.decodeIfPresent(Double.self, forKey: .masterVolume) ?? d.masterVolume
        musicVolume = try c.decodeIfPresent(Double.self, forKey: .musicVolume) ?? d.musicVolume
        effectsVolume = try c.decodeIfPresent(Double.self, forKey: .effectsVolume) ?? d.effectsVolume
        musicEnabled = try c.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? d.musicEnabled
        effectsEnabled = try c.decodeIfPresent(Bool.self, forKey: .effectsEnabled) ?? d.effectsEnabled
        performanceMode = try c.decodeIfPresent(Bool.self, forKey: .performanceMode) ?? d.performanceMode
        showFPS = try c.decodeIfPresent(Bool.self, forKey: .showFPS) ?? d.showFPS
        screenShake = try c.decodeIfPresent(Bool.self, forKey: .screenShake) ?? d.screenShake
        difficulty = (try? c.decodeIfPresent(Difficulty.self, forKey: .difficulty)) ?? nil ?? d.difficulty
        randomEvents = try c.decodeIfPresent(Bool.self, forKey: .randomEvents) ?? d.randomEvents
        battlefield = try c.decodeIfPresent(String.self, forKey: .battlefield) ?? d.battlefield
        hero = try c.decodeIfPresent(String.self, forKey: .hero)
    }
}

/// Best results on one difficulty.
public struct DifficultyRecord: Codable, Sendable, Equatable {
    public var matches = 0
    public var victories = 0
    public var highestWave = 0
    /// Fastest victory (game seconds).
    public var bestTime: Double?
    /// Most base HP left at a victory.
    public var bestBaseHP: Int?

    public init() {}
}

/// Everything that persists between launches (except the match checkpoint).
public struct PlayerProfile: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version = PlayerProfile.currentVersion
    public var settings = GameSettings()
    /// Achievement id → when it was unlocked.
    public var achievements: [String: Date] = [:]
    /// Difficulty raw value → record.
    public var records: [String: DifficultyRecord] = [:]
    /// Every technology ever researched (shown in the menu's records).
    public var techsEverResearched: [String] = []
    public var totalKills = 0
    public var totalBossesDefeated = 0
    /// Highest stage ever cleared, per battlefield (map id → stage number).
    public var stagesCleared: [String: Int] = [:]
    /// Best star rating of a won match, per battlefield (map id → 1…3).
    /// Only ever raised: winning again with a worse result keeps the better one.
    public var matchStars: [String: Int] = [:]

    public init() {}

    /// Highest stage cleared on a battlefield (0 = none).
    public func stagesCleared(battlefield: String) -> Int { stagesCleared[battlefield] ?? 0 }

    /// Best rating on a battlefield (0 = never won) / stars on all battlefields.
    public func bestStars(battlefield: String) -> Int { matchStars[battlefield] ?? 0 }
    public var totalStars: Int { matchStars.values.reduce(0, +) }

    /// Highest stage ever cleared on any battlefield (drives unlocks).
    public var highestStageCleared: Int {
        // Progress made before per-battlefield progress existed (the records' highest stage) counts too.
        max(stagesCleared.values.max() ?? 0, records.values.map(\.highestWave).max() ?? 0)
    }

    /// A hero is unlocked once its stage has been cleared on any battlefield.
    public func isUnlocked(_ hero: SummonAbilityDefinition) -> Bool { highestStageCleared >= hero.requiredStage }

    /// The hero to take into a match: the chosen one if it is unlocked, otherwise the default.
    public func activeHero(in summons: SummonConfig) -> SummonAbilityDefinition? {
        if let h = summons.heroes.first(where: { $0.id == settings.hero }), isUnlocked(h) { return h }
        return summons.defaultHero
    }

    /// Notes that stages 1…`stage` were cleared on a battlefield. Returns true if that is new progress.
    @discardableResult
    public mutating func recordStagesCleared(_ stage: Int, battlefield: String) -> Bool {
        guard stage > stagesCleared(battlefield: battlefield) else { return false }
        stagesCleared[battlefield] = stage
        return true
    }

    /// Keeps a won match's rating if it beats the best one. Returns true if it did.
    @discardableResult
    public mutating func recordMatchStars(_ stars: Int, battlefield: String) -> Bool {
        let s = min(stars, StarRatingConfig.maxStars)
        guard s > bestStars(battlefield: battlefield) else { return false }
        matchStars[battlefield] = s
        return true
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        settings = (try? c.decodeIfPresent(GameSettings.self, forKey: .settings)) ?? nil ?? GameSettings()
        achievements = (try? c.decodeIfPresent([String: Date].self, forKey: .achievements)) ?? nil ?? [:]
        records = (try? c.decodeIfPresent([String: DifficultyRecord].self, forKey: .records)) ?? nil ?? [:]
        techsEverResearched = (try? c.decodeIfPresent([String].self, forKey: .techsEverResearched)) ?? nil ?? []
        totalKills = try c.decodeIfPresent(Int.self, forKey: .totalKills) ?? 0
        totalBossesDefeated = try c.decodeIfPresent(Int.self, forKey: .totalBossesDefeated) ?? 0
        stagesCleared = (try? c.decodeIfPresent([String: Int].self, forKey: .stagesCleared)) ?? nil ?? [:]
        matchStars = (try? c.decodeIfPresent([String: Int].self, forKey: .matchStars)) ?? nil ?? [:]
        // Development builds rated every stage ("stageStars"): keep the progress, drop those ratings.
        if let old = try? decoder.container(keyedBy: LegacyKey.self).decodeIfPresent([String: [Int]].self, forKey: LegacyKey(stringValue: "stageStars")) {
            for (map, stars) in old { recordStagesCleared((stars.lastIndex { $0 > 0 } ?? -1) + 1, battlefield: map) }
        }
    }

    public func record(_ d: Difficulty) -> DifficultyRecord { records[d.rawValue] ?? DifficultyRecord() }

    public var unlockedAchievements: Set<String> { Set(achievements.keys) }

    /// Unlocks newly met achievements. Returns the new ones.
    public mutating func unlockAchievements(in w: GameWorld, now: Date = Date()) -> [AchievementDefinition] {
        let new = AchievementEvaluator.newlyMet(in: w, unlocked: unlockedAchievements)
        for a in new { achievements[a.id] = now }
        return new
    }

    /// Progress during a match (highest wave, tech ever researched).
    public mutating func noteProgress(_ w: GameWorld) {
        var r = record(w.options.difficulty)
        r.highestWave = max(r.highestWave, w.stats.wavesCleared)
        records[w.options.difficulty.rawValue] = r
        for t in w.researchedTechs where !techsEverResearched.contains(t) { techsEverResearched.append(t) }
        recordStagesCleared(max(w.stats.wavesCleared, w.waves.lastSummary?.number ?? 0), battlefield: w.config.map.id)
    }

    /// Final result of a finished match.
    public mutating func recordMatchEnd(_ w: GameWorld) {
        noteProgress(w)
        var r = record(w.options.difficulty)
        r.matches += 1
        if w.phase == .victory {
            recordMatchStars(w.matchStars, battlefield: w.config.map.id)
            r.victories += 1
            r.bestTime = min(r.bestTime ?? .infinity, w.time)
            r.bestBaseHP = max(r.bestBaseHP ?? 0, w.baseHP)
        }
        records[w.options.difficulty.rawValue] = r
        totalKills += w.stats.enemiesKilled
        totalBossesDefeated += w.stats.bossesDefeated
    }
}

private struct LegacyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Reads and writes the profile and the match checkpoint as JSON files in one
/// directory (the app passes its sandbox container's Application Support folder).
/// Writes are atomic; a corrupt file is moved aside instead of crashing.
public final class ProfileStore: @unchecked Sendable {
    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public var profileURL: URL { directory.appendingPathComponent("profile.json") }
    public var checkpointURL: URL { directory.appendingPathComponent("checkpoint.json") }

    public init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// `~/Library/Application Support/EvolutionDefense` — inside the sandbox
    /// container when App Sandbox is on.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("EvolutionDefense", isDirectory: true)
    }

    public func loadProfile() -> PlayerProfile {
        load(PlayerProfile.self, from: profileURL) ?? PlayerProfile()
    }

    public func save(_ profile: PlayerProfile) throws {
        try write(profile, to: profileURL)
    }

    public func loadCheckpoint() -> MatchCheckpoint? {
        guard let c = load(MatchCheckpoint.self, from: checkpointURL) else { return nil }
        return c.version == MatchCheckpoint.currentVersion ? c : nil
    }

    public func save(_ checkpoint: MatchCheckpoint) throws {
        try write(checkpoint, to: checkpointURL)
    }

    public func deleteCheckpoint() {
        try? FileManager.default.removeItem(at: checkpointURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Keep the broken file for inspection and start fresh.
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }
}
