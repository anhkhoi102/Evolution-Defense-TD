import AppKit
import EvolutionDefenseAudio
import EvolutionDefenseCore
import Observation

/// Read-only view of a tower for the selection / upgrade panel.
struct TowerSnapshot: Equatable {
    struct LevelStats: Equatable {
        var name: String
        var damage: Double
        var attacksPerSecond: Double
        var range: Double
        var aoeRadius: Double
        var armorPenetration: Double
        var canTargetAir: Bool
        var damageType: DamageType
        var detectsStealth: Bool
        var effects: [String]
        var dps: Double { damage * attacksPerSecond }

        init(_ s: TowerLevelStats) {
            name = s.name; damage = s.damage; attacksPerSecond = s.attacksPerSecond; range = s.range
            aoeRadius = s.aoeRadius; armorPenetration = s.armorPenetration; canTargetAir = s.canTargetAir
            damageType = s.type; detectsStealth = s.seesStealth; effects = s.hitEffects.labels
        }
    }

    var id: Int
    var archetype: TowerArchetype
    var typeName: String
    var level: Int
    var maxLevel: Int
    var current: LevelStats
    var next: LevelStats?
    var upgradeCost: Int?
    var sellValue: Int
    var targeting: TargetingPriority
    var kills: Int
    var damageDealt: Int
    var disabled: Bool
    /// Reinforcement tower: can't be upgraded or sold.
    var isTemporary: Bool
    var brokenDown: Bool

    var name: String { current.name }

    init(_ t: Tower, world: GameWorld) {
        id = t.id; archetype = t.archetype; typeName = t.definition.displayName
        level = t.level; maxLevel = t.definition.maxLevel
        current = LevelStats(t.stats)
        next = t.isMaxLevel ? nil : LevelStats(world.effectiveStats(t.archetype, level: t.level + 1))
        upgradeCost = world.upgradeCost(for: t)
        sellValue = world.sellValue(for: t)
        targeting = t.targeting; kills = t.kills; damageDealt = Int(t.damageDealt.rounded())
        disabled = t.isDisabled(at: world.time)
        isTemporary = t.isTemporary
        brokenDown = t.eventSpeedFactor < 1
    }
}

/// The boss currently on the field, for the big boss health bar.
struct BossSnapshot: Equatable {
    var id: Int
    var name: String
    /// Rounded to 0.5 % so SwiftUI isn't redrawn every frame.
    var hpFraction: Double
    var shieldFraction: Double
    var phaseName: String?
    var abilities: [String]
    var isFinal: Bool
}

/// One enemy type in the next wave (wave intel).
struct EnemyIntel: Identifiable, Equatable {
    var id: String
    var name: String
    var count: Int
    var isBoss: Bool
    var isFlying: Bool
    var traits: [String]
    var definition: EnemyDefinition

    static func == (a: EnemyIntel, b: EnemyIntel) -> Bool { a.id == b.id && a.count == b.count }

    init(_ d: EnemyDefinition, count: Int, elites: Int = 0) {
        id = d.id; name = d.displayName; self.count = count; isBoss = d.isBoss; isFlying = d.isFlying
        definition = d
        var t: [String] = []
        if elites > 0 { t.append(elites == count ? "Elite" : "\(elites) elite") }
        if d.isFlying { t.append("Flying") }
        if d.armor >= 8 { t.append("Armored") }
        let r = d.resistance
        for type in DamageType.allCases where r[type] > 0 { t.append("Resists \(type.displayName.lowercased())") }
        t += d.baseAbilities.labels
        traits = t
    }
}

/// A technology as shown in the tech panel.
struct TechCard: Identifiable, Equatable {
    var tech: TechDefinition
    var status: TechStatus
    var id: String { tech.id }
}

struct Toast: Equatable, Identifiable {
    enum Kind { case info, success, warning }
    let id = UUID()
    var text: String
    var kind: Kind
}

struct Banner: Equatable, Identifiable {
    enum Kind { case wave, boss, era, phase }
    let id = UUID()
    var title: String
    var subtitle: String
    var kind: Kind
    var era: Era = .primitive
}

enum BaseStatus {
    case normal, warning, critical, emergency, destroyed

    init(hp: Int) {
        switch hp {
        case 70...: self = .normal
        case 40..<70: self = .warning
        case 20..<40: self = .critical
        case 1..<20: self = .emergency
        default: self = .destroyed
        }
    }

    var label: String {
        switch self {
        case .normal: "NORMAL"
        case .warning: "WARNING"
        case .critical: "CRITICAL"
        case .emergency: "EMERGENCY"
        case .destroyed: "DESTROYED"
        }
    }
}

/// A random event as shown in the event card / HUD chip.
struct EventInfo: Equatable, Identifiable {
    var id: String
    var name: String
    var text: String
    var icon: String
    var positive: Bool
}

/// One purchasable repair as shown in the repair panel.
struct RepairChoice: Equatable, Identifiable {
    var id: Int
    var heal: Int
    var cost: Int
    var nominalHP: Int
}

/// Bridges the simulation/scene with SwiftUI. Owns the match.
@MainActor
@Observable
final class GameController {
    @ObservationIgnored let config: GameConfiguration
    @ObservationIgnored let world: GameWorld
    @ObservationIgnored private(set) var scene: GameScene!
    @ObservationIgnored var onExitToMenu: (@MainActor () -> Void)?
    @ObservationIgnored var onRestart: (@MainActor () -> Void)?
    /// Persistence hooks (set by AppRouter).
    @ObservationIgnored var onCheckpoint: (@MainActor (GameWorld) -> Void)?
    @ObservationIgnored var onMatchEnded: (@MainActor (GameWorld) -> Void)?
    @ObservationIgnored var onCheckAchievements: (@MainActor (GameWorld) -> [AchievementDefinition])?
    @ObservationIgnored private(set) var settings: GameSettings
    @ObservationIgnored private var audio: AudioManager { .shared }

    // HUD
    private(set) var gold = 0
    private(set) var baseHP = 100
    private(set) var maxBaseHP = 100
    private(set) var waveNumber = 0
    private(set) var totalWaves = 0
    private(set) var era: Era = .primitive
    private(set) var phase: MatchPhase = .preparation
    private(set) var enemiesRemaining = 0
    private(set) var researchPoints = 0
    private(set) var baseShield = 0
    private(set) var stats = MatchStats()
    private(set) var boss: BossSnapshot?
    /// Tech ids researched (drives the tech panel).
    private(set) var researchedTechs: [String] = []

    // Preparation phase
    /// Whole seconds left on the countdown (rounded up) – coarse so SwiftUI isn't redrawn every frame.
    private(set) var countdownSeconds = 0
    private(set) var countdownFraction = 1.0
    private(set) var earlyStartBonus = 0
    /// True while the countdown is frozen because a management panel is open.
    private(set) var countdownHeld = false
    private(set) var lastSummary: WaveSummary?
    var showSummary = false

    // Interaction state
    var buildSelection: TowerArchetype?
    private(set) var selectedTower: TowerSnapshot?
    /// Tower id whose Sell button was pressed once (press again to confirm).
    private(set) var sellArmedFor: Int?
    private(set) var isRepairPanelOpen = false
    private(set) var isTechPanelOpen = false
    @ObservationIgnored private var seenEnemies: Set<String> = []
    var isPaused = false
    private(set) var speed: Double = 1
    private(set) var toast: Toast?
    private(set) var banner: Banner?
    private(set) var baseHitCount = 0
    private(set) var upgradeCount = 0
    var showsDebugStats = false
    /// Random event affecting the coming / running wave.
    private(set) var activeEvent: EventInfo?
    /// Big card shown when an event happens (dismissed by the player or the next wave).
    var eventCard: EventInfo?
    /// Achievement unlocked just now (shown as a medal toast).
    private(set) var achievementToast: AchievementDefinition?
    @ObservationIgnored private var achievementQueue: [AchievementDefinition] = []
    /// Achievements unlocked during this match (listed on the end screen).
    private(set) var unlockedThisMatch: [AchievementDefinition] = []
    var showSettings = false

    init(world: GameWorld, settings: GameSettings = GameSettings()) {
        self.config = world.config
        self.world = world
        self.settings = settings
        self.totalWaves = config.waves.count
        self.maxBaseHP = world.maxBaseHP
        self.scene = GameScene(world: world, art: .shared)
        scene.controller = self
        apply(settings)
        refreshHUD()
        audio.playMusic(AudioManager.track(for: world.currentEra))
    }

    convenience init(config: GameConfiguration, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.init(world: GameWorld(config: config, seed: seed))
    }

    var difficultyName: String { world.difficulty.name }

    func apply(_ s: GameSettings) {
        settings = s
        showsDebugStats = s.showFPS
        scene.applySettings(performanceMode: s.performanceMode, screenShake: s.screenShake)
    }

    var baseStatus: BaseStatus { BaseStatus(hp: baseHP) }
    var canStartWave: Bool { phase == .preparation && waveNumber < totalWaves }
    var isOver: Bool { phase.isOver }
    /// The waves as this match plays them (counts and intervals scaled by the difficulty curve).
    var plannedWaves: [WaveDefinition] { world.waves.waves }
    var nextWave: WaveDefinition? { plannedWaves.indices.contains(waveNumber) ? plannedWaves[waveNumber] : nil }
    /// The running wave, or the next one between waves.
    var intelWave: WaveDefinition? { phase == .waveInProgress ? plannedWaves[safe: waveNumber - 1] : nextWave }
    var canRepair: Bool { phase == .preparation && baseHP < maxBaseHP }

    /// Management UI is open → the preparation countdown must wait for the player.
    var isManaging: Bool { selectedTower != nil || isRepairPanelOpen || isTechPanelOpen }

    /// Enemy types in the coming wave (or the running one), biggest threats first.
    var waveIntel: [EnemyIntel] {
        guard let wave = intelWave else { return [] }
        var counts: [String: Int] = [:]
        var elites: [String: Int] = [:]
        var order: [String] = []
        for g in wave.groups {
            if counts[g.enemy] == nil { order.append(g.enemy) }
            counts[g.enemy, default: 0] += g.count
            if g.elite == true { elites[g.enemy, default: 0] += g.count }
        }
        return order.compactMap { id in config.enemies[id].map { EnemyIntel($0, count: counts[id]!, elites: elites[id] ?? 0) } }
            .sorted { ($0.isBoss ? 1 : 0, $0.definition.hp) > ($1.isBoss ? 1 : 0, $1.definition.hp) }
    }

    var techCards: [TechCard] { config.techs.map { TechCard(tech: $0, status: world.techStatus($0)) } }

    func cost(of a: TowerArchetype) -> Int { config.tower(a).buildCost }

    var repairChoices: [RepairChoice] {
        config.rules.repair.options.indices.compactMap { i in
            guard let q = world.repairQuote(optionIndex: i) else { return nil }
            return RepairChoice(id: i, heal: q.heal, cost: q.cost, nominalHP: config.rules.repair.options[i].hp)
        }
    }

    // MARK: HUD sync (called every frame by the scene; only writes on change)

    func refreshHUD() {
        world.holdPreparationCountdown = isManaging
        set(\.gold, world.gold)
        set(\.baseHP, world.baseHP)
        set(\.maxBaseHP, world.maxBaseHP)
        set(\.researchPoints, world.research)
        set(\.baseShield, world.baseShield)
        set(\.researchedTechs, world.researchedTechs)
        set(\.waveNumber, world.waveNumber)
        set(\.era, world.currentEra)
        set(\.phase, world.phase)
        set(\.enemiesRemaining, world.enemiesRemainingInWave)
        set(\.stats, world.stats)
        set(\.countdownSeconds, Int(world.preparationRemaining.rounded(.up)))
        let dur = max(0.01, world.waves.preparationDuration)
        set(\.countdownFraction, (world.preparationRemaining / dur * 50).rounded() / 50)
        set(\.earlyStartBonus, world.earlyStartBonus)
        set(\.countdownHeld, phase == .preparation && isManaging)
        if let id = selectedTower?.id {
            if let t = world.tower(withID: id) {
                let snap = TowerSnapshot(t, world: world)
                if snap != selectedTower { selectedTower = snap }
            } else {
                selectedTower = nil
            }
        }
        if isRepairPanelOpen && phase != .preparation { isRepairPanelOpen = false }
        set(\.boss, currentBoss())
        set(\.activeEvent, world.activeEventDefinition.map { d in
            EventInfo(id: d.id, name: d.name, text: world.activeEvent?.text ?? d.summary, icon: d.icon, positive: d.isPositive)
        })
    }

    private func currentBoss() -> BossSnapshot? {
        guard let e = world.enemies.first(where: { $0.isBoss && $0.isActive }) else { return nil }
        return BossSnapshot(id: e.id, name: e.definition.displayName,
                            hpFraction: (e.hpFraction * 200).rounded(.up) / 200,
                            shieldFraction: (e.shieldFraction * 50).rounded() / 50,
                            phaseName: e.phaseName, abilities: e.abilities.labels,
                            isFinal: e.definition.baseDamage >= maxBaseHP)
    }

    private func set<T: Equatable>(_ kp: ReferenceWritableKeyPath<GameController, T>, _ v: T) {
        if self[keyPath: kp] != v { self[keyPath: kp] = v }
    }

    // MARK: Building & selection

    func selectBuild(_ a: TowerArchetype) {
        guard !isOver else { return }
        selectedTower = nil
        sellArmedFor = nil
        buildSelection = (buildSelection == a) ? nil : a
        if let a = buildSelection, world.gold < cost(of: a) {
            showToast("Not enough gold for \(config.tower(a).displayName) (\(cost(of: a)))", .warning)
        }
    }

    func cancelInteraction() {
        buildSelection = nil
        selectedTower = nil
        sellArmedFor = nil
        isRepairPanelOpen = false
        isTechPanelOpen = false
        refreshHUD()
    }

    func clickSlot(_ slotID: Int) {
        sellArmedFor = nil
        if let t = world.tower(atSlot: slotID) {
            buildSelection = nil
            isRepairPanelOpen = false
            isTechPanelOpen = false
            selectedTower = TowerSnapshot(t, world: world)
            refreshHUD()
            return
        }
        guard let a = buildSelection else {
            selectedTower = nil
            showToast("Pick a tower below (keys 1–4), then click a stone pad", .info)
            refreshHUD()
            return
        }
        switch world.build(a, atSlot: slotID) {
        case .success:
            buildSelection = nil
        case .insufficientGold(let need, let have):
            showToast("Not enough gold — need \(need), have \(have)", .warning)
            audio.play(.error)
        case .slotOccupied:
            showToast("That pad is already occupied", .warning)
        case .invalidSlot, .matchOver:
            break
        }
        refreshHUD()
    }

    func clickEmpty() {
        sellArmedFor = nil
        if buildSelection != nil { buildSelection = nil } else { selectedTower = nil }
        refreshHUD()
    }

    func setTargeting(_ p: TargetingPriority) {
        guard let id = selectedTower?.id, let t = world.tower(withID: id) else { return }
        world.setTargeting(p, for: t)
        refreshHUD()
    }

    // MARK: Upgrade / sell

    func upgradeSelected() {
        guard let id = selectedTower?.id, let t = world.tower(withID: id) else { return }
        sellArmedFor = nil
        switch world.upgrade(t) {
        case .success(let level, _):
            upgradeCount += 1
            showToast("Evolved to \(t.definition.stats(level: level).name)", .success)
        case .insufficientGold(let need, let have):
            showToast("Not enough gold to upgrade — need \(need), have \(have)", .warning)
            audio.play(.error)
        case .maxLevel:
            showToast("\(t.name) is fully evolved", .info)
        case .notAllowed:
            showToast("Allied reinforcements can't be upgraded", .info)
        case .unknownTower, .matchOver:
            break
        }
        refreshHUD()
    }

    /// First press arms the button, second press sells (prevents accidental sales).
    func sellSelected() {
        guard let id = selectedTower?.id, let t = world.tower(withID: id) else { return }
        guard sellArmedFor == id else { sellArmedFor = id; return }
        sellArmedFor = nil
        if case .success(let refund) = world.sell(t) {
            showToast("Sold \(t.name) for \(refund) gold", .info)
            selectedTower = nil
        }
        refreshHUD()
    }

    // MARK: Base repair

    func toggleRepairPanel() {
        guard !isOver else { return }
        if isRepairPanelOpen { isRepairPanelOpen = false; refreshHUD(); return }
        guard phase == .preparation else {
            showToast("Repairs are only possible between waves", .info)
            return
        }
        selectedTower = nil
        buildSelection = nil
        isTechPanelOpen = false
        isRepairPanelOpen = true
        refreshHUD()
    }

    // MARK: Technology

    func toggleTechPanel() {
        guard !isOver else { return }
        if isTechPanelOpen { isTechPanelOpen = false; refreshHUD(); return }
        selectedTower = nil
        buildSelection = nil
        isRepairPanelOpen = false
        isTechPanelOpen = true
        refreshHUD()
    }

    func research(_ id: String) {
        switch world.research(id) {
        case .success:
            if let t = config.tech(id) { showToast("Researched \(t.name)", .success) }
        case .insufficientResearch(let need, let have):
            showToast("Not enough Research Points — need \(need), have \(have)", .warning)
            audio.play(.error)
        case .eraLocked(let era):
            showToast("Available in the \(era.displayName)", .info)
        case .alreadyResearched, .unknownTech, .matchOver:
            break
        }
        refreshHUD()
    }

    func repair(option i: Int) {
        switch world.repairBase(optionIndex: i) {
        case .success(let healed, let cost):
            showToast("Base repaired +\(healed) HP for \(cost) gold", .success)
        case .insufficientGold(let need, let have):
            showToast("Not enough gold to repair — need \(need), have \(have)", .warning)
            audio.play(.error)
        case .baseAtFullHealth:
            showToast("The base is already at full health", .info)
        case .notInPreparation:
            showToast("Repairs are only possible between waves", .info)
        case .invalidOption, .matchOver:
            break
        }
        refreshHUD()
        if baseHP >= maxBaseHP { isRepairPanelOpen = false; refreshHUD() }
    }

    // MARK: Waves & time

    func startNextWave() {
        guard canStartWave else { return }
        isRepairPanelOpen = false
        world.startNextWave()
        isPaused = false
        refreshHUD()
    }

    func togglePause() {
        guard !isOver else { return }
        isPaused.toggle()
    }

    func toggleSpeed() { speed = speed == 1 ? 2 : 1 }

    func restart() { onRestart?() }
    func exitToMenu() { onExitToMenu?() }

    /// Keyboard shortcuts. Returns true if the key was handled.
    func handleKey(keyCode: UInt16, characters: String) -> Bool {
        switch keyCode {
        case 53: // Escape
            if buildSelection != nil || selectedTower != nil || isRepairPanelOpen || isTechPanelOpen { cancelInteraction() } else { togglePause() }
            return true
        case 49: // Space
            togglePause(); return true
        case 51, 117: // Delete / Forward delete
            guard !isPaused, selectedTower != nil else { return false }
            sellSelected(); return true
        default: break
        }
        guard !isPaused else { return false }
        switch characters.lowercased() {
        case "1": selectBuild(.splash)
        case "2": selectBuild(.sniper)
        case "3": selectBuild(.heavy)
        case "4": selectBuild(.rapid)
        case "u": upgradeSelected()
        case "r": toggleRepairPanel()
        case "t": toggleTechPanel()
        case "n", "\r": startNextWave()
        case "f": toggleSpeed()
        case "d": showsDebugStats.toggle()
        default: return false
        }
        return true
    }

    // MARK: Feedback from simulation events

    func handle(_ event: GameEvent) {
        switch event {
        case .waveStarted(let n, let bonus):
            showSummary = false
            eventCard = nil
            audio.play(.waveStart)
            let wave = config.waves[n - 1]
            if !wave.isBossWave {
                showBanner(Banner(title: "WAVE \(n)", subtitle: "\(wave.era.displayName) · \(wave.totalEnemies) enemies", kind: .wave))
            }
            if bonus > 0 { showToast("Early start bonus +\(bonus) gold", .success) }
        case .enemySpawned(let e):
            if !e.isSpawnedMinion && seenEnemies.insert(e.definition.id).inserted && e.definition.era > .primitive {
                let traits = EnemyIntel(e.definition, count: 1).traits.prefix(2).joined(separator: ", ")
                showToast("New enemy: \(e.definition.displayName)" + (traits.isEmpty ? "" : " — \(traits)"), .info)
            }
        case .bossSpawned(let e):
            seenEnemies.insert(e.definition.id)
            let final = e.definition.baseDamage >= maxBaseHP
            showBanner(Banner(title: e.definition.displayName.uppercased(),
                              subtitle: final ? "FINAL BOSS APPROACHING" : "BOSS APPROACHING", kind: .boss))
        case .enemyPhaseChanged(let e, let name) where e.isBoss:
            showBanner(Banner(title: name.uppercased(), subtitle: e.definition.displayName.uppercased() + " · NEW PHASE", kind: .phase))
        case .towersDisabled(let ts, _, let ability, let duration):
            showToast("\(ability)! \(ts.count) tower\(ts.count == 1 ? "" : "s") knocked out for \(Int(duration))s", .warning)
        case .baseStruck(_, let ability, let dmg):
            baseHitCount += 1
            if dmg > 0 { showToast("\(ability) hit the base (−\(dmg) HP)", .warning) }
        case .waveCleared(let summary):
            lastSummary = summary
            showSummary = summary.number < totalWaves
            if summary.number < totalWaves { audio.play(.waveClear) }
            checkAchievements()
        case .preparationStarted:
            onCheckpoint?(world)
        case .randomEvent(let def, let text):
            let info = EventInfo(id: def.id, name: def.name, text: text, icon: def.icon, positive: def.isPositive)
            eventCard = info
            audio.play(def.isPositive ? .eventGood : .eventBad)
        case .towerUpgraded:
            checkAchievements()
        case .techResearched:
            audio.play(.research)
            checkAchievements()
        case .enemyKilled(let e, _) where e.isBoss:
            checkAchievements()
        case .researchEarned(let n, let why):
            showToast("+\(n) Research Point\(n == 1 ? "" : "s") · \(why)", .info)
        case .eraAdvanced(_, let to):
            showBanner(Banner(title: to.displayName.uppercased(), subtitle: "A NEW ERA BEGINS · NEW TECHNOLOGY AVAILABLE",
                              kind: .era, era: to), duration: 3.6)
            audio.play(.eraAdvance)
            audio.playMusic(AudioManager.track(for: to))
            checkAchievements()
        case .baseDamaged:
            baseHitCount += 1
        case .matchEnded(let result):
            audio.stopMusic()
            audio.play(result == .victory ? .victory : .defeat)
            onMatchEnded?(world)
            checkAchievements()
            buildSelection = nil
            selectedTower = nil
            isRepairPanelOpen = false
            isTechPanelOpen = false
            showSummary = false
            isPaused = false
        default:
            break
        }
    }

    private func checkAchievements() {
        guard let new = onCheckAchievements?(world), !new.isEmpty else { return }
        achievementQueue += new
        unlockedThisMatch += new
        if achievementToast == nil { showNextAchievement() }
    }

    private func showNextAchievement() {
        guard !achievementQueue.isEmpty else { achievementToast = nil; return }
        let a = achievementQueue.removeFirst()
        achievementToast = a
        audio.play(.achievement)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.4))
            guard let self, self.achievementToast?.id == a.id else { return }
            self.showNextAchievement()
        }
    }

    func showToast(_ text: String, _ kind: Toast.Kind) {
        let t = Toast(text: text, kind: kind)
        toast = t
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }

    private func showBanner(_ b: Banner, duration: Double = 2.6) {
        banner = b
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            if self?.banner?.id == b.id { self?.banner = nil }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
