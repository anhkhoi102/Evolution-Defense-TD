import Foundation

/// A scripted player for measuring the difficulty curve. Used by the balance
/// tests and by `edtool balance`, which prints a per-wave pressure report.
///
/// It acts at the start of every preparation phase and every 3 s during waves
/// (upgrades are allowed mid-wave, so a real player would do the same): buy
/// tech, repair when low, build the next tower of its plan, otherwise upgrade
/// its lowest-level tower.
public struct BalancePlayer: Sendable {
    public var name: String
    public var plan: [Slot]
    public var upgrades = true
    public var repairs = true
    public var research = true
    /// Towers to build before upgrading; more are added once all are at max level.
    public var maxTowers: Int
    /// Upgrade only between waves (a less attentive player).
    public var upgradeOnlyBetweenWaves = false
    /// Highest level the player will upgrade to (5 = all).
    public var maxLevel = 5
    /// Uses the summon abilities (militia on crowds, hero on bosses / elites).
    public var summons = false

    public struct Slot: Sendable {
        public var slot: Int
        public var type: TowerArchetype
        public init(_ slot: Int, _ type: TowerArchetype) { self.slot = slot; self.type = type }
    }

    public init(name: String, plan: [Slot], maxTowers: Int, upgrades: Bool = true, repairs: Bool = true,
                research: Bool = true, upgradeOnlyBetweenWaves: Bool = false, maxLevel: Int = 5) {
        self.name = name; self.plan = plan; self.maxTowers = maxTowers; self.upgrades = upgrades
        self.repairs = repairs; self.research = research
        self.upgradeOnlyBetweenWaves = upgradeOnlyBetweenWaves; self.maxLevel = maxLevel
    }

    /// Tech in the order the player buys it (saving up when the next one is too expensive).
    public static let techPriority = ["improvedArrows", "gunpowder", "fireTechnology", "advancedTraps", "ballisticResearch",
                                      "automatedWeapons", "plasmaTechnology", "aiTargeting", "advancedExplosives",
                                      "strongerWalls", "heavyArmor", "energyShield"]

    /// A mixed defence on the strongest pads: the reference "good" plan.
    public static let goodPlan: [Slot] = [
        Slot(5, .splash), Slot(3, .sniper), Slot(9, .heavy), Slot(12, .rapid), Slot(4, .rapid), Slot(2, .splash),
        Slot(10, .sniper), Slot(11, .heavy), Slot(14, .splash), Slot(16, .rapid), Slot(7, .sniper), Slot(8, .heavy)
    ]

    /// The good plan's pads, every tower of one type (tests single-type strategies).
    public static func monoPlan(_ t: TowerArchetype) -> [Slot] { goodPlan.map { Slot($0.slot, t) } }

    /// Summon decisions, checked every half second during waves.
    func useSummons(_ w: GameWorld) {
        guard summons, w.phase == .waveInProgress else { return }
        let live = w.enemies.filter { $0.isActive && !$0.isFlying }
        guard !live.isEmpty else { return }
        // Where the crowd is thickest: the enemy with the most ground neighbours within 120 points.
        func crowd() -> (Enemy, Int)? {
            live.map { e in (e, live.filter { $0.position.distanceSquared(to: e.position) < 120 * 120 }.count) }
                .max { $0.1 < $1.1 }
        }
        // Deploy a little ahead of a moving enemy so the units meet it.
        func ahead(_ e: Enemy, _ by: CGFloat) -> CGPoint { w.path.position(at: min(e.distance + by, w.path.totalLength - 60)) }
        if w.summonStatus("hero")?.isReady == true {
            if let big = live.filter({ $0.isBoss || $0.isElite }).max(by: { $0.distance < $1.distance }) {
                w.summon("hero", at: ahead(big, 90))
            } else if let (e, n) = crowd(), n >= 8 {
                w.summon("hero", at: ahead(e, 70))
            }
        }
        if w.summonStatus("militia")?.isReady == true, let (e, n) = crowd(), n >= 5 {
            w.summon("militia", at: ahead(e, 60))
        }
    }

    func act(_ w: GameWorld, config: GameConfiguration) {
        let preparing = w.phase == .preparation
        var progress = true
        while progress {
            progress = false
            if research, let id = Self.techPriority.first(where: { !w.isResearched($0) && (config.tech($0)?.era ?? .futuristic) <= w.currentEra }),
               case .success = w.research(id) {
                progress = true; continue
            }
            if repairs, preparing, w.baseHP <= w.maxBaseHP * 6 / 10, case .success = w.repairBase(optionIndex: 0) {
                progress = true; continue
            }
            let canUpgrade = upgrades && (preparing || !upgradeOnlyBetweenWaves)
            let allMaxed = w.towers.allSatisfy { $0.isMaxLevel || $0.level >= maxLevel }
            if w.towers.count < maxTowers || (canUpgrade && allMaxed),
               let next = plan.first(where: { w.tower(atSlot: $0.slot) == nil }),
               case .success = w.build(next.type, atSlot: next.slot) {
                progress = true; continue
            }
            if canUpgrade, let t = w.towers.filter({ !$0.isMaxLevel && $0.level < maxLevel }).min(by: { $0.level < $1.level }),
               case .success = w.upgrade(t) {
                progress = true
            }
        }
    }

    // MARK: Results

    /// What one wave was like for this player.
    public struct WaveReport: Sendable {
        public var number: Int
        /// Furthest any enemy got along the path, 0…1 (1 = reached the base).
        public var deepestProgress: Double = 0
        public var hpLost = 0
        public var leaks = 0
        public var enemies = 0
        /// Gold unspent when the wave started (slack in the economy).
        public var goldAtStart = 0
        public var towers = 0
        public var levels = 0
        public var duration: Double = 0
        /// Which enemies got through (enemy id → count); the first thing to read when a wave is too hard.
        public var leaksByEnemy: [String: Int] = [:]
    }

    public struct Result: Sendable, CustomStringConvertible {
        public var phase: MatchPhase
        public var baseHP: Int
        public var time: Double
        public var wavesCleared: Int
        public var bossesDefeated: Int
        public var techs: Int
        public var towers: Int
        public var levels: Int
        public var waves: [WaveReport]

        public var description: String {
            "\(phase) wave=\(wavesCleared) hp=\(baseHP) time=\(Int(time))s bosses=\(bossesDefeated) techs=\(techs) towers=\(towers) levels=\(levels)"
        }
    }

    public func play(config: GameConfiguration, seed: UInt64 = 3,
                     options: MatchOptions = MatchOptions(randomEvents: false)) -> Result {
        let dt = 1.0 / 60.0
        let w = GameWorld(config: config, options: options, seed: seed)
        var wasPreparing = false
        var ticks = 0
        var reports: [WaveReport] = []
        var current: WaveReport?
        var hpAtStart = w.baseHP
        var startTime = 0.0
        let pathLength = Double(w.path.totalLength)
        while !w.phase.isOver && w.time < 60 * 45 {
            let preparing = w.phase == .preparation
            if (preparing && !wasPreparing) || ticks % 180 == 0 { act(w, config: config) }
            if ticks % 30 == 0 { useSummons(w) }
            wasPreparing = preparing
            ticks += 1
            w.step(dt)
            w.drainEvents { e in
                switch e {
                case .waveStarted(let n, _):
                    current = WaveReport(number: n, goldAtStart: w.gold, towers: w.towers.count,
                                         levels: w.towers.reduce(0) { $0 + $1.level })
                    hpAtStart = w.baseHP; startTime = w.time
                case .enemyReachedBase(let enemy, _):
                    current?.leaks += 1
                    current?.leaksByEnemy[enemy.definition.id, default: 0] += 1
                case .enemySpawned, .bossSpawned:
                    current?.enemies += 1
                case .waveCleared:
                    if var r = current {
                        r.hpLost = max(0, hpAtStart - w.baseHP); r.duration = w.time - startTime
                        reports.append(r); current = nil
                    }
                default: break
                }
            }
            if current != nil {
                for e in w.enemies where e.isActive {
                    current!.deepestProgress = max(current!.deepestProgress, Double(e.distance) / pathLength)
                }
            }
        }
        if var r = current {   // the wave the match ended on
            r.hpLost = max(0, hpAtStart - w.baseHP); r.duration = w.time - startTime
            if w.phase == .defeat { r.deepestProgress = 1 }
            reports.append(r)
        }
        return Result(phase: w.phase, baseHP: w.baseHP, time: w.time, wavesCleared: w.stats.wavesCleared,
                      bossesDefeated: w.stats.bossesDefeated, techs: w.researchedTechs.count,
                      towers: w.towers.count, levels: w.towers.reduce(0) { $0 + $1.level }, waves: reports)
    }
}

extension BalancePlayer {
    /// The reference strategies on the default battlefield (Grassland).
    public static let profiles: [BalancePlayer] = profiles(plan: goodPlan,
        extra: [Slot(1, .sniper), Slot(6, .heavy), Slot(13, .splash), Slot(15, .rapid)])

    /// The same strategies on any battlefield. Grassland keeps its hand-made
    /// plan; other maps get one built the same way: the pads that cover the
    /// most road first, with the same order of tower types.
    public static func profiles(for map: MapDefinition, automaticPlan: Bool = false) -> [BalancePlayer] {
        if map.id == MatchOptions.defaultBattlefield && !automaticPlan { return profiles }
        let path = map.makePath()
        let reach: CGFloat = 170
        func coverage(_ s: BuildSlotDefinition) -> Int {
            let p = map.slotPosition(s)
            var n = 0
            var d: CGFloat = 0
            while d <= path.totalLength {
                if path.position(at: d).distance(to: p) <= reach { n += 1 }
                d += 10
            }
            return n
        }
        let ranked = map.buildSlots.map { ($0, coverage($0)) }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }.map(\.0)
        let types = goodPlan.map(\.type)
        let plan = zip(ranked, types).map { Slot($0.id, $1) }
        let rest = ranked.dropFirst(types.count)
        let extra = zip(rest, [TowerArchetype.sniper, .heavy, .splash, .rapid]).map { Slot($0.id, $1) }
        return profiles(plan: plan, extra: extra)
    }

    static func profiles(plan goodPlan: [Slot], extra: [Slot]) -> [BalancePlayer] {
        func monoPlan(_ t: TowerArchetype) -> [Slot] { goodPlan.map { Slot($0.slot, t) } }
        return [
        BalancePlayer(name: "expert (8 mixed, tech)", plan: goodPlan, maxTowers: 8),
        BalancePlayer(name: "spread (12 mixed, tech)", plan: goodPlan, maxTowers: 12),
        BalancePlayer(name: "focused, no tech", plan: goodPlan, maxTowers: 8, research: false),
        BalancePlayer(name: "casual (between waves, no tech)", plan: goodPlan, maxTowers: 8, research: false,
                      upgradeOnlyBetweenWaves: true),
        BalancePlayer(name: "only splash", plan: monoPlan(.splash), maxTowers: 8),
        BalancePlayer(name: "only sniper", plan: monoPlan(.sniper), maxTowers: 8),
        BalancePlayer(name: "only heavy", plan: monoPlan(.heavy), maxTowers: 8),
        BalancePlayer(name: "only rapid", plan: monoPlan(.rapid), maxTowers: 8),
        BalancePlayer(name: "L1 spam (16 towers, no upgrades)", plan: goodPlan + extra,
                      maxTowers: 16, upgrades: false),
        BalancePlayer(name: "passive (2 towers)", plan: Array(goodPlan.prefix(2)), maxTowers: 2, upgrades: false,
                      repairs: false, research: false),
        ]
    }
}
