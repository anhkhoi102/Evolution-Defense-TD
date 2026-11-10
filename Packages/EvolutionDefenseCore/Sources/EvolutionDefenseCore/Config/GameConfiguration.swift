import Foundation

public struct EconomyConfig: Codable, Sendable {
    public var startingGold: Int
    /// Fraction of everything invested in a tower (build + upgrades) returned on sale.
    public var sellRefundRatio: Double
    /// Extra gold for clearing a wave without any enemy reaching the base.
    public var perfectWaveBonus: Int
    /// Gold per remaining countdown second when the next wave is started early.
    public var earlyStartGoldPerSecond: Double
    /// Wave-clear reward when a wave doesn't define `clearReward`:
    /// default + growth × (waveNumber − 1).
    public var defaultWaveClearReward: Int
    public var waveClearRewardGrowth: Int
}

public struct BaseConfig: Codable, Sendable {
    public var maxHP: Int
    public var startingHP: Int
}

public struct WaveTimingConfig: Codable, Sendable {
    /// Countdown before wave 1 (seconds).
    public var initialPreparationTime: Double
    /// Countdown between waves (seconds).
    public var preparationTime: Double
}

public struct RepairOption: Codable, Sendable, Equatable {
    public var cost: Int
    public var hp: Int
}

public struct RepairConfig: Codable, Sendable {
    /// Purchasable repairs, available during preparation phases only.
    public var options: [RepairOption]
}

/// Global rules from game.json.
public struct RulesConfig: Codable, Sendable {
    public var economy: EconomyConfig
    public var base: BaseConfig
    public var waveTiming: WaveTimingConfig
    public var repair: RepairConfig
    public var research: ResearchConfig
    public var randomEvents: RandomEventSchedule
    /// How often towers re-evaluate their target (seconds). Avoids per-frame scans.
    public var retargetInterval: Double
    /// Random sideways spread of enemies on the path (world units).
    public var laneSpread: Double
    /// Minimum fraction of damage that always gets through armor.
    public var minimumDamageFraction: Double
    /// The difficulty curve: per-phase multipliers (see ProgressionData.swift).
    public var progression: [ProgressionPhase]?
    /// Stats of elite enemies (wave groups with "elite": true).
    public var elite: EliteConfig?
}

public enum ConfigurationError: Error, CustomStringConvertible {
    case missingResource(String)
    case invalid(String)

    public var description: String {
        switch self {
        case .missingResource(let n): "Missing configuration file: \(n)"
        case .invalid(let m): "Invalid configuration: \(m)"
        }
    }
}

/// All balance and content data for a match. Loaded from JSON so balance can
/// be tuned without touching gameplay code.
public struct GameConfiguration: Sendable {
    public var rules: RulesConfig
    public var towers: [TowerArchetype: TowerDefinition]
    public var enemies: [String: EnemyDefinition]
    /// The battlefield in play (the default one until a match selects another).
    public var map: MapDefinition
    /// Every battlefield, in menu order (battlefields.json).
    public var maps: [MapDefinition]
    public var waves: [WaveDefinition]
    public var techs: [TechDefinition]
    public var difficulties: [DifficultyDefinition]
    public var events: [RandomEventDefinition]
    public var achievements: [AchievementDefinition]
    /// Temporary reinforcement abilities (summons.json).
    public var summons: SummonConfig

    public init(rules: RulesConfig, towers: [TowerArchetype: TowerDefinition],
                enemies: [String: EnemyDefinition], map: MapDefinition, waves: [WaveDefinition],
                techs: [TechDefinition] = [], difficulties: [DifficultyDefinition] = [],
                events: [RandomEventDefinition] = [], achievements: [AchievementDefinition] = [],
                summons: SummonConfig = .none) {
        self.rules = rules; self.towers = towers; self.enemies = enemies; self.map = map; self.waves = waves
        self.maps = [map]
        self.techs = techs; self.difficulties = difficulties; self.events = events; self.achievements = achievements
        self.summons = summons
    }

    /// Settings for a difficulty. Falls back to neutral multipliers if missing.
    public func difficulty(_ d: Difficulty) -> DifficultyDefinition {
        difficulties.first { $0.id == d } ?? DifficultyDefinition(
            id: d, name: d.rawValue.capitalized, summary: "", enemyHP: 1, enemySpeed: 1, goldMultiplier: 1,
            startingGold: rules.economy.startingGold, startingResearch: rules.research.startingPoints, preparationTime: nil)
    }

    public func event(_ id: String) -> RandomEventDefinition? { events.first { $0.id == id } }

    public func battlefield(_ id: String) -> MapDefinition? { maps.first { $0.id == id } }

    /// This configuration with `id` as the battlefield in play (unknown ids keep the current one).
    public func selecting(battlefield id: String) -> GameConfiguration {
        guard id != map.id, let m = battlefield(id) else { return self }
        var c = self
        c.map = m
        return c
    }

    public func tech(_ id: String) -> TechDefinition? { techs.first { $0.id == id } }

    public func tower(_ a: TowerArchetype) -> TowerDefinition {
        guard let t = towers[a] else { fatalError("No definition for tower \(a)") }
        return t
    }

    // MARK: Loading

    /// Loads the bundled default configuration.
    public static func loadDefault() throws -> GameConfiguration {
        try load(from: try ConfigLocator.configDirectory())
    }

    public static func load(from directory: URL) throws -> GameConfiguration {
        let decoder = JSONDecoder()
        func read<T: Decodable>(_ name: String, as: T.Type) throws -> T {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { throw ConfigurationError.missingResource(name) }
            do { return try decoder.decode(T.self, from: data) } catch {
                throw ConfigurationError.invalid("\(name): \(error)")
            }
        }
        let rules = try read("game.json", as: RulesConfig.self)
        let towerList = try read("towers.json", as: [TowerDefinition].self)
        let enemyList = try read("enemies.json", as: [EnemyDefinition].self)
        // Battlefields: battlefields.json lists the map files in menu order; the first is the default.
        let mapFiles = (try? read("battlefields.json", as: [String].self)) ?? ["map_meadow.json"]
        let maps = try mapFiles.map { try read($0, as: MapDefinition.self) }
        guard let map = maps.first else { throw ConfigurationError.invalid("battlefields.json lists no maps") }
        let waves = try read("waves.json", as: [WaveDefinition].self)
        let techs = try read("tech.json", as: [TechDefinition].self)
        let difficulties = try read("difficulty.json", as: [DifficultyDefinition].self)
        let events = try read("events.json", as: [RandomEventDefinition].self)
        let achievements = try read("achievements.json", as: [AchievementDefinition].self)
        // Optional: a configuration without summons.json simply has no summon abilities.
        let summons = FileManager.default.fileExists(atPath: directory.appendingPathComponent("summons.json").path)
            ? try read("summons.json", as: SummonConfig.self) : .none

        // Boss phases are stored highest threshold first so the simulation can walk them in order.
        let enemiesSorted = enemyList.map { e -> EnemyDefinition in
            var e = e
            e.phases = e.phases?.sorted { $0.belowHP > $1.belowHP }
            return e
        }
        let config = GameConfiguration(
            rules: rules,
            towers: Dictionary(uniqueKeysWithValues: towerList.map { ($0.archetype, $0) }),
            enemies: Dictionary(uniqueKeysWithValues: enemiesSorted.map { ($0.id, $0) }),
            map: map,
            waves: waves.sorted { $0.number < $1.number },
            techs: techs, difficulties: difficulties, events: events, achievements: achievements,
            summons: summons)
        var withMaps = config
        withMaps.maps = maps
        try withMaps.validate()
        return withMaps
    }

    /// Catches data mistakes at load time instead of mid-game.
    public func validate() throws {
        for a in TowerArchetype.allCases {
            guard let t = towers[a] else { throw ConfigurationError.invalid("missing tower \(a.rawValue)") }
            guard !t.levels.isEmpty else { throw ConfigurationError.invalid("tower \(a.rawValue) has no levels") }
            for (i, l) in t.levels.enumerated() where l.level != i + 1 {
                throw ConfigurationError.invalid("tower \(a.rawValue) level order broken at \(l.level)")
            }
        }
        for w in waves {
            for g in w.groups where enemies[g.enemy] == nil {
                throw ConfigurationError.invalid("wave \(w.number) references unknown enemy '\(g.enemy)'")
            }
        }
        var summonIDs = Set<String>()
        for s in summons.abilities {
            guard summonIDs.insert(s.id).inserted else { throw ConfigurationError.invalid("duplicate summon '\(s.id)'") }
            let u = s.unit
            guard s.count > 0, s.cooldown > 0, s.duration > 0, s.cooldown >= s.duration,
                  u.hp > 0, u.damage > 0, u.attacksPerSecond > 0, u.range > 0, u.moveSpeed > 0 else {
                throw ConfigurationError.invalid("summon '\(s.id)' needs positive stats and a cooldown at least as long as its duration")
            }
        }
        for (i, w) in waves.enumerated() where w.number != i + 1 {
            throw ConfigurationError.invalid("wave numbers must be 1…n without gaps (found \(w.number) at \(i + 1))")
        }
        for (a, b) in zip(waves, waves.dropFirst()) where b.era < a.era {
            throw ConfigurationError.invalid("wave \(b.number) goes back to an earlier era")
        }
        for e in enemies.values {
            let a = e.baseAbilities
            let phaseAbilities = (e.phases ?? []).compactMap(\.abilities)
            for ab in [a] + phaseAbilities {
                for ref in [ab.splitOnDeath?.enemy, ab.summon?.enemy, ab.brood?.enemy].compactMap({ $0 }) {
                    guard let child = enemies[ref] else {
                        throw ConfigurationError.invalid("enemy \(e.id) spawns unknown enemy '\(ref)'")
                    }
                    if child.isBoss { throw ConfigurationError.invalid("enemy \(e.id) may not spawn a boss") }
                    if child.baseAbilities.splitOnDeath != nil && ab.splitOnDeath != nil {
                        throw ConfigurationError.invalid("enemy \(e.id): chained splitting is not allowed")
                    }
                }
            }
            for p in e.phases ?? [] where !(0..<1).contains(p.belowHP) {
                throw ConfigurationError.invalid("enemy \(e.id) phase '\(p.name)' needs belowHP in 0..<1")
            }
            let r = e.resistance
            for t in DamageType.allCases where !(0...0.9).contains(r[t]) {
                throw ConfigurationError.invalid("enemy \(e.id) resistance to \(t) must be 0…0.9")
            }
        }
        if Set(techs.map(\.id)).count != techs.count { throw ConfigurationError.invalid("duplicate tech ids") }
        for d in Difficulty.allCases where !difficulties.contains(where: { $0.id == d }) {
            throw ConfigurationError.invalid("missing difficulty '\(d.rawValue)'")
        }
        for d in difficulties where d.enemyHP <= 0 || d.enemySpeed <= 0 || d.goldMultiplier <= 0 {
            throw ConfigurationError.invalid("difficulty \(d.id) needs positive multipliers")
        }
        if events.contains(where: { $0.weight <= 0 }) { throw ConfigurationError.invalid("event weights must be positive") }
        if Set(achievements.map(\.id)).count != achievements.count { throw ConfigurationError.invalid("duplicate achievement ids") }
        for a in achievements where a.kind == .killBoss && enemies[a.target ?? ""]?.isBoss != true {
            throw ConfigurationError.invalid("achievement \(a.id) targets unknown boss")
        }
        let s = rules.randomEvents
        if s.minGap < 1 || s.maxGap < s.minGap { throw ConfigurationError.invalid("random event gaps") }
        for t in techs where t.cost <= 0 { throw ConfigurationError.invalid("tech \(t.id) needs a positive cost") }
        if !(0...1).contains(rules.economy.sellRefundRatio) { throw ConfigurationError.invalid("sellRefundRatio must be 0…1") }
        if rules.repair.options.contains(where: { $0.cost <= 0 || $0.hp <= 0 }) {
            throw ConfigurationError.invalid("repair options need positive cost and hp")
        }
        if Set(maps.map(\.id)).count != maps.count { throw ConfigurationError.invalid("duplicate battlefield ids") }
        for map in maps {
            let name = "battlefield '\(map.id)'"
            let ids = Set(map.buildSlots.map(\.id))
            if ids.count != map.buildSlots.count { throw ConfigurationError.invalid("\(name): duplicate build slot ids") }
            if map.path.count < 2 { throw ConfigurationError.invalid("\(name): path too short") }
            let geo = map.makePath()
            for s in map.buildSlots {
                // Pads must be on dry land, inside the playfield and clear of the road.
                guard s.x > 0.5, s.y > 0.5, s.x < Double(map.columns) - 0.5, s.y < Double(map.rows) - 0.5 else {
                    throw ConfigurationError.invalid("\(name): pad \(s.id) is outside the playfield")
                }
                if map.isInWater(GridPoint(x: s.x, y: s.y), margin: 0.5) {
                    throw ConfigurationError.invalid("\(name): pad \(s.id) is in water")
                }
                if Double(geo.distanceToPath(from: map.slotPosition(s))) < (map.pathWidth / 2 + 0.55) * map.tileSize {
                    throw ConfigurationError.invalid("\(name): pad \(s.id) is on the road")
                }
            }
            // The road may only cross water on a bridge.
            var d = 0.0
            let total = Double(geo.totalLength)
            while d <= total {
                let p = geo.position(at: CGFloat(d))
                let g = GridPoint(x: Double(p.x) / map.tileSize, y: Double(p.y) / map.tileSize)
                if map.isInWater(g, margin: map.pathWidth / 2), !map.isOnBridge(g) {
                    throw ConfigurationError.invalid("\(name): the road enters water at (\(g.x), \(g.y)) without a bridge")
                }
                d += map.tileSize / 4
            }
        }
    }
}

/// Finds the bundled Config folder both when running package tests
/// and from inside the packaged .app (Contents/Resources).
public enum ConfigLocator {
    static let bundleName = "EvolutionDefenseCore_EvolutionDefenseCore.bundle"

    public static func configDirectory() throws -> URL {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent(bundleName).appendingPathComponent("Config"))
            candidates.append(res.appendingPathComponent(bundleName).appendingPathComponent("Contents/Resources/Config"))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName).appendingPathComponent("Config"))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exe.appendingPathComponent(bundleName).appendingPathComponent("Config"))
        }
        for c in candidates where fm.fileExists(atPath: c.appendingPathComponent("game.json").path) {
            return c
        }
        // Fallback: the generated `Bundle.module` accessor (package tests, Xcode builds).
        if let url = Bundle.module.url(forResource: "Config", withExtension: nil) {
            return url
        }
        throw ConfigurationError.missingResource(bundleName)
    }
}
