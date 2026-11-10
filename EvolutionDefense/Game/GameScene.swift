import EvolutionDefenseAudio
import EvolutionDefenseCore
import SpriteKit

/// Thin SpriteKit scene: steps the simulation on a fixed timestep, forwards
/// events, and asks the renderers to mirror state. No gameplay rules live here.
@MainActor
final class GameScene: SKScene {
    static let fixedStep = 1.0 / 60.0

    weak var controller: GameController?
    let world: GameWorld
    let art: ArtLibrary

    private let mapRenderer: MapRenderer
    private let enemyRenderer: EnemyRenderer
    private let summonRenderer: SummonRenderer
    private let towerRenderer: TowerRenderer
    private let projectileRenderer: ProjectileRenderer
    private let effects: EffectsRenderer

    private let rangeIndicator = SKShapeNode()
    private let aoeIndicator = SKShapeNode()
    private let ghost = SKSpriteNode()
    private let ghostHead = SKSpriteNode()
    /// Summon deployment preview: footprint ellipse and ghost units in formation.
    private let deployIndicator = SKShapeNode()
    private var deployGhosts: [SKSpriteNode] = []
    private var deployIndicatorRadius: CGFloat = -1
    /// Mouse position in world coordinates (nil when outside the playfield).
    private var hoverWorld: CGPoint?
    private var rangeRadius: CGFloat = -1
    private var aoeRadius: CGFloat = -1

    /// Everything in the world lives under this node so the camera can shake.
    private let worldRoot = SKNode()
    private var shake: Double = 0
    private var shakeStrength: CGFloat = 0
    private var screenShakeEnabled = true
    private(set) var performanceMode = false
    private var audio: AudioManager { .shared }

    private var lastTime: TimeInterval?
    private var accumulator = 0.0
    private var hoverSlot: Int?
    private var isSetUp = false
    /// Era whose enemy atlases are loaded (see ArtLibrary.advance).
    private var loadedEra: Era = .primitive

    init(world: GameWorld, art: ArtLibrary) {
        self.world = world
        self.art = art
        art.warmUp(config: world.config, era: world.currentEra)
        loadedEra = world.currentEra
        mapRenderer = MapRenderer(map: world.config.map, art: art)
        enemyRenderer = EnemyRenderer(art: art)
        summonRenderer = SummonRenderer(art: art)
        towerRenderer = TowerRenderer(art: art)
        projectileRenderer = ProjectileRenderer(art: art)
        effects = EffectsRenderer(art: art)
        super.init(size: world.config.map.worldSize)
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)
        setUpNodes()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func setUpNodes() {
        guard !isSetUp else { return }
        isSetUp = true
        addChild(worldRoot)
        worldRoot.addChild(mapRenderer.root)
        worldRoot.addChild(effects.groundLayer)
        worldRoot.addChild(projectileRenderer.shadowLayer)
        worldRoot.addChild(enemyRenderer.layer)
        worldRoot.addChild(summonRenderer.layer)
        worldRoot.addChild(towerRenderer.layer)
        worldRoot.addChild(projectileRenderer.layer)
        worldRoot.addChild(enemyRenderer.barLayer)
        worldRoot.addChild(summonRenderer.barLayer)
        worldRoot.addChild(effects.airLayer)
        worldRoot.addChild(effects.textLayer)

        for n in [rangeIndicator, aoeIndicator] {
            n.zPosition = Layer.overlay
            n.isHidden = true
            n.isAntialiased = true
            worldRoot.addChild(n)
        }
        rangeIndicator.fillColor = NSColor(white: 1, alpha: 0.07)
        rangeIndicator.strokeColor = NSColor(white: 1, alpha: 0.55)
        rangeIndicator.lineWidth = 2
        aoeIndicator.fillColor = NSColor(srgbRed: 1, green: 0.55, blue: 0.15, alpha: 0.12)
        aoeIndicator.strokeColor = NSColor(srgbRed: 1, green: 0.6, blue: 0.2, alpha: 0.8)
        aoeIndicator.lineWidth = 1.5

        ghost.zPosition = Layer.overlay + 1
        ghost.alpha = 0.6
        ghost.isHidden = true
        ghostHead.zPosition = 1
        ghostHead.zRotation = .pi / 4
        ghost.addChild(ghostHead)
        worldRoot.addChild(ghost)

        deployIndicator.zPosition = Layer.overlay
        deployIndicator.isHidden = true
        deployIndicator.isAntialiased = true
        deployIndicator.lineWidth = 2.5
        worldRoot.addChild(deployIndicator)
        for _ in 0..<6 {
            let g = SKSpriteNode()
            g.alpha = 0.6
            g.zPosition = Layer.overlay + 1
            g.isHidden = true
            deployGhosts.append(g)
            worldRoot.addChild(g)
        }
    }

    /// Performance mode: fewer effects, no floating texts or muzzle flashes,
    /// no projectile shadows. Screen shake can be turned off separately.
    func applySettings(performanceMode: Bool, screenShake: Bool) {
        self.performanceMode = performanceMode
        screenShakeEnabled = screenShake
        effects.lightweight = performanceMode
        projectileRenderer.drawsShadows = !performanceMode
        enemyRenderer.lightweight = performanceMode
        summonRenderer.lightweight = performanceMode
        mapRenderer.ambientEnabled = !performanceMode
    }

    private func addShake(_ strength: CGFloat, _ duration: Double) {
        guard screenShakeEnabled else { return }
        shakeStrength = max(shakeStrength * CGFloat(shake > 0 ? 1 : 0), strength)
        shake = max(shake, duration)
    }

    private func updateShake(_ dt: Double) {
        guard shake > 0 else { return }
        shake = max(0, shake - dt)
        if shake == 0 { worldRoot.position = .zero; shakeStrength = 0; return }
        let k = shakeStrength * CGFloat(min(1, shake * 3))
        worldRoot.position = CGPoint(x: CGFloat.random(in: -k...k), y: CGFloat.random(in: -k...k))
    }

    // MARK: Frame loop

    /// Recent frame intervals (benchmark / diagnostics).
    private(set) var frameTimes: [Double] = []

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime.map { min(0.1, max(0, currentTime - $0)) } ?? 0
        if lastTime != nil {
            if frameTimes.count >= 1200 { frameTimes.removeFirst(600) }
            frameTimes.append(currentTime - lastTime!)
        }
        lastTime = currentTime
        guard let c = controller else { return }
        // Keep only the current and next era's enemy art resident (also covers
        // loaded saves and debug skips, which jump eras without an event).
        if world.currentEra != loadedEra {
            loadedEra = world.currentEra
            art.advance(to: loadedEra, config: world.config)
            enemyRenderer.dropPooledSprites()
        }

        let running = !c.isPaused && !world.phase.isOver
        if running {
            accumulator += dt * c.speed
            var steps = 0
            while accumulator >= Self.fixedStep && steps < 8 {
                world.step(Self.fixedStep)
                accumulator -= Self.fixedStep
                steps += 1
            }
            if steps == 8 { accumulator = 0 }   // never spiral after a hitch
        }
        world.drainEvents { handle($0) }
        if mapRenderer.era != world.currentEra { mapRenderer.setEra(world.currentEra, animated: false) }

        let visualDt = running ? dt * c.speed : 0
        enemyRenderer.sync(world: world)
        summonRenderer.sync(world: world)
        towerRenderer.sync(world: world, dt: visualDt)
        projectileRenderer.sync(world: world)
        effects.update(dt: visualDt)
        mapRenderer.update(dt: dt)   // decorative; keeps decaying after the match ends
        updateShake(dt)
        updateOverlay()
        c.refreshHUD()
    }

    /// Advances the simulation without real time passing (snapshot tool).
    func fastForward(seconds: Double) {
        world.simulate(seconds: seconds, step: Self.fixedStep)
        world.drainEvents { handle($0) }
        if mapRenderer.era != world.currentEra { mapRenderer.setEra(world.currentEra, animated: false) }
        enemyRenderer.sync(world: world)
        summonRenderer.sync(world: world)
        towerRenderer.sync(world: world, dt: 1)
        projectileRenderer.sync(world: world)
        effects.update(dt: 0.05)
        controller?.refreshHUD()
    }

    private func handle(_ e: GameEvent) {
        switch e {
        case .towerBuilt(let t):
            towerRenderer.add(t)
            mapRenderer.setSlotVisible(t.slotID, false)
            if t.isTemporary { effects.summon(at: t.position, color: NSColor(srgbRed: 0.45, green: 0.95, blue: 0.5, alpha: 1)) }
            audio.play(.build)
        case .towerRemoved(let t):
            towerRenderer.remove(t)
            mapRenderer.setSlotVisible(t.slotID, true)
            effects.sold(at: t.position, refund: 0)
        case .towerFired(let t, let p):
            audio.play(Self.shotSound(p.kind), volume: t.archetype == .rapid ? 0.45 : 0.75)
            if !performanceMode {
                let head = towerRenderer.headSprite(for: t.id)
                effects.muzzleFlash(at: t.position, angle: t.aimAngle, tint: art.projectile(p.visual).tint,
                                    distance: head.map { $0.metric("muzzleDistance", $0.size.width * 0.35) } ?? 24,
                                    lift: head.map { $0.metric("mountY", 0) } ?? 0)
            }
        case .projectileImpact(_, let p, let r, let hit):
            if r > 0 {
                effects.explosion(at: p, radius: r)
                audio.play(.explosion, volume: 0.6)
            } else if hit {
                effects.hit(at: p)
                audio.play(.hit, volume: 0.5)
            }
        case .enemyKilled(let enemy, let reward):
            effects.death(at: enemy.position, big: enemy.isBoss)
            enemyRenderer.leaveCorpse(of: enemy, effects: effects)
            if !performanceMode || enemy.isBoss {
                effects.gold(reward, at: CGPoint(x: enemy.position.x, y: enemy.position.y + enemy.radius))
            }
            if enemy.isBoss {
                audio.play(.bossDeath)
                addShake(9, 0.8)
            } else {
                audio.play(enemy.definition.category == "Robot" ? .robotDeath : .enemyDeath, volume: 0.6)
            }
        case .bossSpawned:
            audio.play(.bossRoar)
            addShake(5, 0.6)
        case .baseDamaged:
            mapRenderer.baseHit()
            audio.play(.baseHit)
            addShake(4, 0.3)
        case .towerUpgraded(let t, _):
            towerRenderer.upgraded(t)
            effects.levelUp(at: t.position, level: t.level)
            audio.play(.upgrade)
        case .towerSold(let t, let refund):
            towerRenderer.remove(t)
            mapRenderer.setSlotVisible(t.slotID, true)
            effects.sold(at: t.position, refund: refund)
            audio.play(.sell)
        case .baseRepaired(let amount, _):
            effects.heal(amount, at: basePosition)
            audio.play(.repair)
        case .criticalHit(let enemy, _):
            effects.critical(at: enemy.position)
        case .enemyPhaseChanged(let enemy, let name):
            effects.bossPhase(name, at: enemy.position)
            if enemy.isBoss {
                audio.play(.bossPhase)
                addShake(8, 0.7)
            }
        case .enemySplit(let enemy, _):
            effects.summon(at: enemy.position, color: NSColor(srgbRed: 0.7, green: 1, blue: 0.2, alpha: 1))
        case .enemiesSummoned(let enemy, _, _):
            effects.summon(at: enemy.position, color: enemy.definition.era == .futuristic
                           ? NSColor(srgbRed: 1, green: 0.35, blue: 0.25, alpha: 1)
                           : NSColor(srgbRed: 0.75, green: 0.45, blue: 1, alpha: 1))
        case .towersDisabled(let towers, let enemy, _, _):
            let emp = enemy.definition.era == .futuristic
            let r = enemy.abilities.disableTowers.map { CGFloat($0.radius) } ?? 150
            effects.shockwave(at: enemy.position, radius: r, emp: emp)
            for t in towers { effects.towerDisabled(at: t.position, emp: emp) }
            audio.play(emp ? .empBlast : .fireBreath)
            addShake(emp ? 6 : 4, 0.4)
        case .baseStruck(let enemy, _, _):
            effects.missile(from: enemy.position, to: basePosition)
            mapRenderer.baseHit()
            audio.play(.missile)
        case .summonDeployed(let ability, let units, let at):
            effects.summonArrive(at: units.map(\.position), centre: at, hero: ability.kind == .hero)
            audio.play(ability.kind == .hero ? .eventGood : .build)
            if ability.kind == .hero { addShake(3, 0.2) }
        case .summonAttacked(let u, let target):
            effects.summonHit(at: target.position, hero: u.isHero)
            audio.play(.hit, volume: u.isHero ? 0.6 : 0.35)
        case .summonSpecial(let u, _, let radius, _):
            effects.heroSpecial(at: u.position, radius: CGFloat(radius))
            audio.play(.explosion, volume: 0.45)
            addShake(2.5, 0.15)
        case .summonDefeated(let u):
            let sprite = art.summon(u.ability)
            if let death = sprite.animations["death"] {
                effects.play(death, direction: death.direction(for: u.heading), at: u.position, rotation: 0,
                             flipped: false, anchor: sprite.anchor)
            }
            audio.play(.enemyDeath, volume: 0.6)
        case .summonExpired(let u):
            if let a = summonRenderer.currentArt(of: u) {
                effects.summonVanish(a.art, at: u.position, size: a.size, anchor: a.anchor, hero: u.isHero)
            }
        case .enemiesHealed(let healer, _, let count, let radius):
            effects.healPulse(at: healer.position, radius: CGFloat(radius), healed: count)
        case .baseShieldAbsorbed:
            effects.shieldAbsorbed(at: basePosition)
        case .eraAdvanced(_, let to):
            mapRenderer.setEra(to, animated: true)
        case .techResearched:
            for t in world.towers { effects.researched(at: t.position) }
        default:
            break
        }
        controller?.handle(e)
    }

    private var basePosition: CGPoint { world.config.map.world(world.config.map.base) }
    private lazy var proj = art.view

    static func shotSound(_ k: ProjectileKind) -> SoundEffect {
        switch k {
        case .stone, .boulder: .shotStone
        case .arrow, .longArrow, .bolt, .spear, .ballistaBolt: .shotArrow
        case .cannonball, .shell, .heavyShell: .shotCannon
        case .bullet, .pellet: .shotBullet
        case .rocket: .shotRocket
        case .laser: .shotLaser
        case .plasmaOrb: .shotPlasma
        case .railSlug: .shotRail
        case .orbitalBeam: .shotBeam
        }
    }

    // MARK: Overlays (range / AoE / build ghost)

    /// Summon deployment preview under the mouse: the units' engagement area and
    /// ghost units in formation, blue/gold where allowed and red where not.
    private func updateDeployPreview(_ c: GameController) {
        guard let id = c.summonSelection, let a = world.config.summons.ability(id), let p = hoverWorld else {
            deployIndicator.isHidden = true
            for g in deployGhosts { g.isHidden = true }
            return
        }
        let valid = world.summonDeployPoint(near: p) != nil
        let r = CGFloat(a.unit.aggroRange)
        if r != deployIndicatorRadius {
            deployIndicatorRadius = r
            let ry = r * proj.groundScaleY
            deployIndicator.path = CGPath(ellipseIn: CGRect(x: -r, y: -ry, width: 2 * r, height: 2 * ry), transform: nil)
        }
        let ok = a.kind == .hero ? NSColor(srgbRed: 1, green: 0.82, blue: 0.4, alpha: 1)
                                 : NSColor(srgbRed: 0.45, green: 0.78, blue: 1, alpha: 1)
        let bad = NSColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1)
        let color = valid ? ok : bad
        deployIndicator.strokeColor = color.withAlphaComponent(0.85)
        deployIndicator.fillColor = color.withAlphaComponent(0.1)
        deployIndicator.position = proj.ground(p)
        deployIndicator.isHidden = false
        // Ghost units where they will stand, facing the player.
        let sprite = art.summon(a)
        let idle = sprite.clip("idle", "walk")
        let frame = idle.art(direction: sprite.facing == .directional ? idle.direction(for: -.pi / 2) : 0, frame: 0)
        for (k, g) in deployGhosts.enumerated() {
            guard k < a.count else { g.isHidden = true; continue }
            var pos = p
            if a.count > 1 {
                let ang = CGFloat(k) / CGFloat(a.count) * 2 * .pi + .pi / 4
                pos = CGPoint(x: p.x + cos(ang) * CGFloat(a.formationRadius), y: p.y + sin(ang) * CGFloat(a.formationRadius))
            }
            g.apply(frame)
            g.anchorPoint = sprite.anchor
            g.position = proj.ground(pos)
            g.zPosition = Layer.overlay + 1 + proj.depth(pos) * 0.01
            g.color = bad
            g.colorBlendFactor = valid ? 0 : 0.6
            g.isHidden = false
        }
    }

    private func updateOverlay() {
        guard let c = controller else { return }
        updateDeployPreview(c)
        var showRange = false
        var showAoe = false
        ghost.isHidden = true

        if let a = c.buildSelection, let slotID = hoverSlot, world.tower(atSlot: slotID) == nil,
           let slot = world.slot(withID: slotID) {
            let pos = world.config.map.slotPosition(slot)
            let stats = world.effectiveStats(a, level: 1)
            setRange(CGFloat(stats.range), at: proj.ground(pos))
            showRange = true
            ghost.apply(art.towerBase(world.config.tower(a), level: 1))
            let head = art.towerHead(world.config.tower(a), level: 1)
            ghostHead.apply(head)
            ghostHead.position = CGPoint(x: 0, y: head.metric("mountY", 0))
            if head.facing == .directional {
                // Pre-rendered weapon: show the view aimed up-right instead of rotating it.
                let idle = head.clip("idle")
                ghostHead.zRotation = 0
                ghostHead.texture = idle.art(direction: idle.direction(for: .pi / 4), frame: 0).texture
            } else {
                ghostHead.zRotation = .pi / 4
            }
            ghost.position = proj.ground(pos)
            ghost.isHidden = false
            let affordable = world.gold >= stats.cost
            rangeIndicator.strokeColor = affordable ? NSColor(white: 1, alpha: 0.6) : NSColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 0.8)
            mapRenderer.setSlotHighlight(slotID)
        } else {
            mapRenderer.setSlotHighlight(nil)
            if let snap = c.selectedTower, let t = world.tower(withID: snap.id) {
                rangeIndicator.strokeColor = NSColor(white: 1, alpha: 0.55)
                setRange(CGFloat(t.stats.range), at: proj.ground(t.position))
                showRange = true
                if t.stats.aoeRadius > 0, let target = t.target, target.isActive {
                    setAoe(CGFloat(t.stats.aoeRadius), at: proj.ground(target.position))
                    showAoe = true
                }
            }
        }
        rangeIndicator.isHidden = !showRange
        aoeIndicator.isHidden = !showAoe
    }

    private func setRange(_ r: CGFloat, at p: CGPoint) {
        if r != rangeRadius {
            rangeRadius = r
            // A circle on the ground: an ellipse under the 3/4 camera.
            let ry = r * proj.groundScaleY
            rangeIndicator.path = CGPath(ellipseIn: CGRect(x: -r, y: -ry, width: r * 2, height: ry * 2), transform: nil)
        }
        rangeIndicator.position = p
    }

    private func setAoe(_ r: CGFloat, at p: CGPoint) {
        if r != aoeRadius {
            aoeRadius = r
            let ry = r * proj.groundScaleY
            aoeIndicator.path = CGPath(ellipseIn: CGRect(x: -r, y: -ry, width: r * 2, height: ry * 2), transform: nil)
        }
        aoeIndicator.position = p
    }

    // MARK: Input (forwarded from GameSKView)

    func slot(at p: CGPoint) -> Int? {
        let map = world.config.map
        var best: (Int, CGFloat)?
        for s in map.buildSlots {
            let d = map.slotPosition(s).distance(to: p)
            if d <= 36 && d < (best?.1 ?? .greatestFiniteMagnitude) { best = (s.id, d) }
        }
        return best?.0
    }

    func handleMouseMoved(_ event: NSEvent) {
        let p = proj.world(fromScreen: event.location(in: worldRoot))
        hoverWorld = p
        hoverSlot = slot(at: p)
    }

    func handleMouseExited() { hoverSlot = nil; hoverWorld = nil }

    func handleMouseDown(_ event: NSEvent) {
        guard let c = controller, !c.isPaused, !world.phase.isOver else { return }
        let p = proj.world(fromScreen: event.location(in: worldRoot))
        if c.summonSelection != nil {
            // Deployment mode: the click places the summon (or explains why it can't go there).
            hoverWorld = p
            c.confirmSummon(at: p)
            return
        }
        hoverSlot = slot(at: p)
        if let s = hoverSlot { c.clickSlot(s) } else { c.clickEmpty() }
    }

    func handleRightMouseDown(_ event: NSEvent) {
        controller?.cancelInteraction()
    }

    // MARK: Diagnostics

    func resetFrameTimes() { frameTimes.removeAll(keepingCapacity: true) }

    var debugCounts: (enemies: Int, effects: Int) { (enemyRenderer.visibleCount, effects.activeCount) }
    /// Summoned units currently drawn (leak checks).
    var debugSummonNodes: Int { summonRenderer.visibleCount }
    /// Effect sprites drawn at the wrong size (should always be 0).
    var debugEffectSizeMismatches: Int { effects.sizeMismatches }

    /// Test hook used by the snapshot tool to emulate hovering a slot.
    func debugHover(slot: Int?) { hoverSlot = slot }
    /// Test hook: emulate the mouse at a world point (deployment preview).
    func debugHover(world p: CGPoint?) { hoverWorld = p }
}
