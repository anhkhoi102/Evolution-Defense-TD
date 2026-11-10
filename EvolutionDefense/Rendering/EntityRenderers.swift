import EvolutionDefenseAssets
import EvolutionDefenseCore
import SpriteKit

// Renderers mirror simulation state into SpriteKit nodes each frame. Nodes are
// pooled and reused, so steady-state gameplay allocates no new nodes.
//
// Every visual property (textures, sizes, anchors, animation speed, bar
// offsets, muzzle positions…) comes from the asset manifest via ArtLibrary.
// Gameplay values (hit radius, range, speed) are never derived from sprites.

// MARK: - Enemies

@MainActor
final class EnemyVisual {
    let body = SKSpriteNode()
    let barBack = SKSpriteNode(color: PlatformColor(white: 0, alpha: 0.65), size: CGSize(width: 30, height: 5))
    let barFill = SKSpriteNode(color: .green, size: CGSize(width: 28, height: 3))
    /// Energy shield: bubble around the body plus a cyan bar above the HP bar.
    let shield = SKSpriteNode()
    let shieldBar = SKSpriteNode(color: PlatformColor(srgbRed: 0.45, green: 0.88, blue: 1, alpha: 1), size: CGSize(width: 28, height: 2))
    var sprite: SpriteAsset?
    var walk: AnimationClip?
    var currentFrame = -1
    var stamp = 0
    var barWidth: CGFloat = 28
    var barOffsetY: CGFloat = 20
    var shieldLift: CGFloat = 0
    var hasShield = false
    /// Last status tint sent to the shader (avoids per-frame attribute writes).
    var tint = SIMD4<Float>(-1, 0, 0, 0)
    /// Gold ring on the ground under elite enemies.
    let eliteRing = SKSpriteNode()
    var isElite = false
    /// Expose (Heavy): a red target ring on the ground. Armour Shred (Rapid Fire): a purple
    /// diamond beside the health bar that grows with the armour stripped.
    let markRing = SKSpriteNode()
    var hasMark = false
    let shredPip = SKSpriteNode(color: PlatformColor(srgbRed: 0.78, green: 0.5, blue: 1, alpha: 1), size: CGSize(width: 6, height: 6))
    var hasShred = false

    init() {
        barFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        shieldBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        body.color = .white
        body.shader = Shaders.status
        shield.zPosition = 6
        shredPip.zRotation = .pi / 4
        shredPip.zPosition = 2
    }
}

@MainActor
final class EnemyRenderer {
    let layer = SKNode()
    let barLayer = SKNode()
    /// Performance mode: static status tints, no shimmer or boss breathing.
    var lightweight = false
    private var active: [Int: EnemyVisual] = [:]
    private var pool: [EnemyVisual] = []
    private var stamp = 0
    private let art: ArtLibrary

    init(art: ArtLibrary) {
        self.art = art
        layer.zPosition = Layer.enemies
        barLayer.zPosition = Layer.healthBars
    }

    func sync(world: GameWorld) {
        stamp &+= 1
        let now = world.time
        for e in world.enemies where e.isActive {
            let v = active[e.id] ?? attach(e)
            v.stamp = stamp
            let screen = view.ground(e.position)
            v.body.position = screen
            v.body.zPosition = view.depth(e.position) + (e.isFlying ? Layer.flyingOffset : 0) + (e.isBoss ? 0.005 : 0.002)
            if v.isElite {
                v.eliteRing.position = screen
                v.eliteRing.zPosition = v.body.zPosition - 0.001
                v.eliteRing.alpha = lightweight ? 0.7 : 0.55 + 0.3 * CGFloat(sin(now * 4 + Double(e.id)))
                v.eliteRing.isHidden = e.isCloaked
            }
            guard let sprite = v.sprite, let walk = v.walk else { continue }
            var dir = 0
            switch sprite.facing {
            case .rotate: v.body.zRotation = e.heading
            case .fixed: v.body.zRotation = 0
            case .flip: v.body.zRotation = 0; v.body.xScale = abs(v.body.xScale) * (cos(e.heading) < 0 ? -1 : 1)
            case .directional: v.body.zRotation = 0; dir = walk.direction(for: e.heading)
            }
            // Walk cycle: by distance (gait matches speed) or by time, as the manifest says.
            let f = walk.distancePerFrame != nil ? walk.frameIndex(distance: e.distance) : walk.frameIndex(time: now)
            let key = dir * 1000 + f
            if key != v.currentFrame {
                v.currentFrame = key
                v.body.texture = walk.art(direction: dir, frame: f).texture
            }
            // Status colour (status shader): hit flash > stun > burn > slow > boss phase.
            // Pulses are quantised so the attribute only changes a few times a second.
            var tint = SIMD4<Float>(0, 0, 0, 0)
            if (now - e.lastHitTime) < 0.07 {
                tint = Self.flashTint
            } else if now < e.stunnedUntil {
                tint = Self.stunTint
            } else if e.isBurning {
                tint = Self.burnTint; tint.w = lightweight ? 0.32 : 0.24 + 0.16 * Self.pulse(now * 18)
            } else if e.isSlowed {
                tint = Self.slowTint
            } else if e.phaseIndex >= 0 {
                tint = Self.enrageTint; tint.w = 0.16 + 0.12 * Self.pulse(now * 6)
            } else if e.isElite {
                // Elites glow gold (their ground ring can hide under big sprites).
                tint = Self.eliteTint; tint.w = lightweight ? 0.22 : 0.12 + 0.16 * Self.pulse(now * 3 + Double(e.id))
            }
            if tint != v.tint {
                v.tint = tint
                Shaders.setTint(v.body, tint)
            }
            // Cloaked enemies are barely visible shimmer.
            v.body.alpha = e.isCloaked ? (lightweight ? 0.25 : 0.22 + 0.08 * CGFloat(sin(now * 10 + Double(e.id)))) : 1
            // Bosses "breathe" so they read as alive even when slowed.
            if e.isBoss && !lightweight {
                let s = 1 + bossBreathing * CGFloat(sin(now * 3.2))
                v.body.yScale = s
                v.body.xScale = (v.body.xScale < 0 ? -s : s)
            }

            let shielded = e.maxShieldHP > 0
            if shielded != v.hasShield {
                v.hasShield = shielded
                if shielded { layer.addChild(v.shield); barLayer.addChild(v.shieldBar) } else { v.shield.removeFromParent(); v.shieldBar.removeFromParent() }
            }
            if shielded {
                let frac = CGFloat(e.shieldFraction)
                v.shield.isHidden = frac <= 0.01 || e.isCloaked
                v.shield.position = CGPoint(x: screen.x, y: screen.y + v.shieldLift)
                v.shield.zPosition = v.body.zPosition + 0.001
                v.shield.alpha = 0.35 + 0.65 * frac
            }

            // Tower team effects (Docs/TOWER_EFFECTS.md).
            let marked = e.isExposed && !e.isCloaked
            if marked != v.hasMark {
                v.hasMark = marked
                if marked {
                    if v.markRing.texture == nil {
                        v.markRing.apply(art.fx("ring"))
                        v.markRing.color = Self.exposeRed
                        v.markRing.colorBlendFactor = 1
                        v.markRing.blendMode = .add
                    }
                    let w = max(e.radius * 2.6, 30)
                    v.markRing.setScale(1)
                    v.markRing.setUnscaledSize(CGSize(width: w, height: w * view.groundScaleY))
                    layer.addChild(v.markRing)
                } else {
                    v.markRing.removeFromParent()
                }
            }
            if marked {
                v.markRing.position = screen
                v.markRing.zPosition = v.body.zPosition - 0.0015
                v.markRing.alpha = lightweight ? 0.8 : 0.65 + 0.3 * CGFloat(sin(now * 9))
            }
            let shredded = e.isShredded && !e.isCloaked
            if shredded != v.hasShred {
                v.hasShred = shredded
                if shredded { barLayer.addChild(v.shredPip) } else { v.shredPip.removeFromParent() }
            }
            if shredded {
                v.shredPip.position = CGPoint(x: screen.x - v.barWidth / 2 - 7, y: screen.y + v.barOffsetY)
                v.shredPip.setScale(0.7 + 0.6 * CGFloat(min(1, e.shredAmount / 14)))
            }

            let showBar = !e.isCloaked && (e.isBoss || e.hp < e.maxHP || (shielded && e.shieldHP < e.maxShieldHP))
            v.barBack.isHidden = !showBar
            v.barFill.isHidden = !showBar
            v.shieldBar.isHidden = !(showBar && shielded && e.shieldHP > 0)
            if showBar {
                let top = CGPoint(x: screen.x, y: screen.y + v.barOffsetY)
                v.barBack.position = top
                v.barFill.position = CGPoint(x: top.x - v.barWidth / 2, y: top.y)
                let frac = CGFloat(e.hpFraction)
                v.barFill.size.width = max(0.5, v.barWidth * frac)
                v.barFill.color = e.isBoss ? PlatformColor(srgbRed: 0.85, green: 0.25, blue: 0.95, alpha: 1)
                    : frac > 0.6 ? PlatformColor(srgbRed: 0.35, green: 0.85, blue: 0.3, alpha: 1)
                    : frac > 0.3 ? PlatformColor(srgbRed: 0.98, green: 0.78, blue: 0.2, alpha: 1)
                    : PlatformColor(srgbRed: 0.95, green: 0.3, blue: 0.25, alpha: 1)
                if shielded {
                    v.shieldBar.position = CGPoint(x: top.x - v.barWidth / 2, y: top.y + 4)
                    v.shieldBar.size.width = max(0.5, v.barWidth * CGFloat(e.shieldFraction))
                }
            }
        }
        // Recycle visuals whose enemy is gone (killed / reached base).
        guard active.count > world.enemies.count else { return }
        stale.removeAll(keepingCapacity: true)
        for (id, v) in active where v.stamp != stamp { stale.append(id) }
        for id in stale {
            guard let v = active.removeValue(forKey: id) else { continue }
            v.body.removeFromParent(); v.barBack.removeFromParent(); v.barFill.removeFromParent()
            v.eliteRing.removeFromParent()
            v.markRing.removeFromParent(); v.hasMark = false
            v.shredPip.removeFromParent(); v.hasShred = false
            v.shield.removeFromParent(); v.shieldBar.removeFromParent(); v.hasShield = false
            pool.append(v)
        }
    }

    private var stale: [Int] = []

    /// Pooled visuals forget their sprite so an earlier era's textures can be freed.
    func dropPooledSprites() {
        for v in pool { v.sprite = nil; v.walk = nil; v.body.texture = nil }
    }
    // rgb = colour (sRGB, premultiplied by the shader), w = mix amount.
    private static let flashTint = SIMD4<Float>(1, 1, 1, 0.7)
    private static let stunTint = SIMD4<Float>(1, 0.95, 0.45, 0.45)
    private static let burnTint = SIMD4<Float>(1, 0.42, 0.08, 0.3)
    private static let slowTint = SIMD4<Float>(0.62, 0.86, 1, 0.42)
    private static let enrageTint = SIMD4<Float>(1, 0.15, 0.1, 0.2)
    private static let eliteTint = SIMD4<Float>(1, 0.8, 0.3, 0.2)
    /// 0…1 pulse, quantised to 6 steps.
    private static func pulse(_ x: Double) -> Float { ((Float(sin(x)) * 0.5 + 0.5) * 6).rounded() / 6 }

    private lazy var bossBreathing = art.layout("enemy.bossBreathing", 0.035)
    /// Elite body scale (visual only), from the pack's layout.
    private lazy var eliteScale = art.layout("enemy.eliteScale", 1.12)
    private static let eliteGold = PlatformColor(srgbRed: 1, green: 0.78, blue: 0.25, alpha: 1)
    private static let exposeRed = PlatformColor(srgbRed: 1, green: 0.25, blue: 0.2, alpha: 1)
    private lazy var view = art.view

    private func attach(_ e: Enemy) -> EnemyVisual {
        let v = pool.popLast() ?? EnemyVisual()
        let sprite = art.enemy(e.definition)
        v.sprite = sprite
        v.walk = sprite.clip("walk", "idle")
        v.body.setScale(1)
        v.body.apply(sprite)
        v.shield.apply(art.fx("shield"))
        let d = sprite.metric("shieldDiameter", max(sprite.size.width, sprite.size.height) * 1.1)
        v.shield.size = CGSize(width: d, height: d)
        let barWidth = sprite.metric("healthBarWidth", e.isBoss ? 70 : max(24, sprite.size.width * 0.6))
        v.barOffsetY = sprite.metric("healthBarOffsetY", sprite.size.height * 0.5 + 6)
        v.shieldLift = sprite.metric("shieldOffsetY", 0)
        v.shieldBar.size = CGSize(width: barWidth, height: 2)
        v.currentFrame = -1
        v.tint = SIMD4<Float>(-1, 0, 0, 0)
        v.body.alpha = 1
        v.barWidth = barWidth
        v.barBack.size = CGSize(width: v.barWidth + 2, height: e.isBoss ? 7 : 5)
        v.barFill.size = CGSize(width: v.barWidth, height: e.isBoss ? 5 : 3)
        // Elites: a pulsing gold ring on the ground, a slightly larger body and a
        // gold health-bar frame. Visual only: the hit radius stays the same.
        v.isElite = e.isElite
        v.barBack.color = e.isElite ? Self.eliteGold.withAlphaComponent(0.9) : PlatformColor(white: 0, alpha: 0.65)
        if e.isElite {
            v.body.setScale(eliteScale)
            v.eliteRing.apply(art.fx("ring"))
            v.eliteRing.color = Self.eliteGold
            v.eliteRing.colorBlendFactor = 1
            v.eliteRing.blendMode = .add
            let w = max(e.radius * 3.4, sprite.size.width * 0.95)   // visible around big sprites too
            v.eliteRing.setScale(1)
            v.eliteRing.setUnscaledSize(CGSize(width: w, height: w * view.groundScaleY))
            layer.addChild(v.eliteRing)
        }
        layer.addChild(v.body)
        barLayer.addChild(v.barBack)
        barLayer.addChild(v.barFill)
        v.barFill.zPosition = 1
        v.shieldBar.zPosition = 1
        active[e.id] = v
        return v
    }

    var visibleCount: Int { active.count }

    /// Hands the dying enemy's current frame to the effects layer to fade out.
    func leaveCorpse(of e: Enemy, effects: EffectsRenderer) {
        guard let v = active[e.id], let sprite = v.sprite, let walk = v.walk, v.currentFrame >= 0 else { return }
        let rotation = sprite.facing == .rotate ? e.heading : 0
        if let death = sprite.animations["death"] {
            let dir = sprite.facing == .directional ? death.direction(for: e.heading) : 0
            effects.play(death, direction: dir, at: e.position, rotation: rotation, flipped: v.body.xScale < 0,
                         anchor: sprite.anchor)
        } else {
            let dir = sprite.facing == .directional ? walk.direction(for: e.heading) : 0
            effects.corpse(walk.art(direction: dir, frame: v.currentFrame % 1000), at: e.position, rotation: rotation,
                           size: sprite.size, anchor: sprite.anchor)
        }
    }
}

// MARK: - Towers

@MainActor
final class TowerVisual {
    let root = SKNode()
    let base = SKSpriteNode()
    let head = SKSpriteNode()
    let disabledMark = SKSpriteNode()
    var pips: [SKSpriteNode] = []
    var level = 0
    var displayedAngle: CGFloat = .pi / 2
    var showsDisabled = false
    var headSprite: SpriteAsset?
    /// Optional one-shot "fire" animation on the weapon.
    var fireClip: AnimationClip?
    var idleClip: AnimationClip?
    var headFrame = -1
    var mountY: CGFloat = 0

    init() {
        root.addChild(base)
        head.zPosition = 1
        root.addChild(head)
        disabledMark.zPosition = 3
        disabledMark.isHidden = true
        root.addChild(disabledMark)
    }
}

@MainActor
final class TowerRenderer {
    let layer = SKNode()
    private var visuals: [Int: TowerVisual] = [:]
    private let art: ArtLibrary

    init(art: ArtLibrary) {
        self.art = art
        layer.zPosition = Layer.towers
    }

    func add(_ t: Tower) {
        let v = TowerVisual()
        v.root.position = view.ground(t.position)
        v.root.zPosition = view.depth(t.position)
        v.disabledMark.apply(art.fx("disabled"))
        v.disabledMark.position = CGPoint(x: 0, y: art.layout("tower.disabledMark.offsetY", 22))
        // Level pips in a shallow arc under the tower (spacing/offset from the manifest layout).
        let count = t.definition.maxLevel
        let spacing = art.layout("tower.pips.spacing", 9)
        let offsetY = art.layout("tower.pips.offsetY", -31)
        let curve = art.layout("tower.pips.curve", 0.12)
        for i in 0..<count {
            let pip = SKSpriteNode()
            pip.apply(art.ui("levelPip.off"))
            let x = (CGFloat(i) - CGFloat(count - 1) / 2) * spacing
            pip.position = CGPoint(x: x, y: offsetY + abs(x) * curve)
            pip.zPosition = 2
            v.root.addChild(pip)
            v.pips.append(pip)
        }
        layer.addChild(v.root)
        visuals[t.id] = v
        refreshArt(t, v)
        // Small "construction" pop.
        v.root.setScale(0.5)
        v.root.alpha = 0.3
        v.root.run(.group([.scale(to: 1, duration: 0.18), .fadeIn(withDuration: 0.12)]))
    }

    func remove(_ t: Tower) {
        guard let v = visuals.removeValue(forKey: t.id) else { return }
        v.root.removeAllActions()
        v.root.run(.sequence([.group([.scale(to: 0.4, duration: 0.15), .fadeOut(withDuration: 0.15)]), .removeFromParent()]))
    }

    func upgraded(_ t: Tower) {
        guard let v = visuals[t.id] else { return }
        refreshArt(t, v)
        // Cancel any running build/upgrade animation and restore a clean state first,
        // otherwise an upgrade right after building leaves the tower half-faded.
        v.root.removeAllActions()
        v.root.setScale(1)
        v.root.alpha = 1
        v.root.run(.sequence([.scale(to: 1.22, duration: 0.09), .scale(to: 1, duration: 0.16)]))
    }

    private func refreshArt(_ t: Tower, _ v: TowerVisual) {
        v.level = t.level
        v.base.apply(art.towerBase(t.definition, level: t.level))
        let head = art.towerHead(t.definition, level: t.level)
        v.head.apply(head)
        v.headSprite = head
        v.mountY = head.metric("mountY", 0)
        v.idleClip = head.clip("idle")
        v.fireClip = head.animations["fire"]
        v.headFrame = -1
        for (i, pip) in v.pips.enumerated() { pip.apply(art.ui(i < t.level ? "levelPip.on" : "levelPip.off")) }
    }

    func sync(world: GameWorld, dt: Double) {
        let turn = CGFloat(min(1, dt * 16))
        for t in world.towers {
            guard let v = visuals[t.id] else { continue }
            if v.level != t.level { refreshArt(t, v) }
            let disabled = t.isDisabled(at: world.time)
            if disabled != v.showsDisabled {
                v.showsDisabled = disabled
                v.disabledMark.isHidden = !disabled
                for n in [v.base, v.head] {
                    n.color = PlatformColor(srgbRed: 0.25, green: 0.35, blue: 0.55, alpha: 1)
                    n.colorBlendFactor = disabled ? 0.55 : 0
                }
            }
            if disabled {
                v.disabledMark.setScale(1 + 0.12 * CGFloat(sin(world.time * 12)))
                continue
            }
            // Smoothly rotate the weapon towards the aim angle (shortest way).
            var delta = t.aimAngle - v.displayedAngle
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            v.displayedAngle += delta * turn
            let facing = v.headSprite?.facing ?? .rotate
            var dir = 0
            switch facing {
            case .rotate: v.head.zRotation = v.displayedAngle
            case .fixed: v.head.zRotation = 0
            case .flip: v.head.zRotation = 0; v.head.xScale = cos(v.displayedAngle) < 0 ? -1 : 1
            case .directional: v.head.zRotation = 0; dir = (v.idleClip ?? v.fireClip)?.direction(for: v.displayedAngle) ?? 0
            }
            let since = world.time - t.lastFireTime
            // Weapon animation: one-shot "fire" clip after a shot, otherwise "idle".
            if let fire = v.fireClip, since < fire.duration {
                setHeadFrame(v, fire, dir, fire.frameIndex(time: since), oneShot: true)
            } else if let idle = v.idleClip {
                setHeadFrame(v, idle, dir, idle.frameIndex(time: world.time), oneShot: false)
            }
            // Recoil kick right after firing (distance from the manifest; 0 disables it).
            let recoil = v.headSprite?.metric("recoil", 4) ?? 4
            let kick: CGFloat = since < 0.09 ? CGFloat(1 - since / 0.09) * recoil : 0
            v.head.position = CGPoint(x: -cos(v.displayedAngle) * kick,
                                      y: v.mountY - sin(v.displayedAngle) * kick * view.groundScaleY)
        }
    }

    func node(for towerID: Int) -> SKNode? { visuals[towerID]?.root }
    private lazy var view = art.view

    /// The weapon sprite currently shown for a tower (muzzle metrics).
    func headSprite(for towerID: Int) -> SpriteAsset? { visuals[towerID]?.headSprite }

    private func setHeadFrame(_ v: TowerVisual, _ clip: AnimationClip, _ dir: Int, _ index: Int, oneShot: Bool) {
        guard clip.frames.count > 1 || v.headFrame == -1 else { return }
        let key = dir * 10_000 + index + (oneShot ? 1000 : 0)
        guard key != v.headFrame else { return }
        v.headFrame = key
        v.head.texture = clip.art(direction: dir, frame: index).texture
    }
}

// MARK: - Projectiles

@MainActor
final class ProjectileRenderer {
    let layer = SKNode()
    let shadowLayer = SKNode()
    private var nodes: [SKSpriteNode] = []
    private var shadows: [SKSpriteNode] = []
    private var visuals: [String?] = []
    private var sprites: [SpriteAsset?] = []
    private let art: ArtLibrary
    var drawsShadows = true
    private lazy var arcMax = art.layout("projectile.arc.maxHeight", 70)
    private lazy var view = art.view
    private lazy var arcFactor = art.layout("projectile.arc.distanceFactor", 0.35)
    private lazy var arcScale = art.layout("projectile.arc.scalePerPoint", 1.0 / 90)

    init(art: ArtLibrary) {
        self.art = art
        layer.zPosition = Layer.projectiles
        shadowLayer.zPosition = Layer.shadows
    }

    func sync(world: GameWorld) {
        let ps = world.projectiles
        while nodes.count < ps.count {
            let n = SKSpriteNode(); n.isHidden = true
            let s = SKSpriteNode(); s.apply(art.fx("shadow")); s.isHidden = true
            layer.addChild(n); shadowLayer.addChild(s)
            nodes.append(n); shadows.append(s); visuals.append(nil); sprites.append(nil)
        }
        for (i, p) in ps.enumerated() {
            let n = nodes[i]
            guard p.isActive else {
                if !n.isHidden { n.isHidden = true; shadows[i].isHidden = true }
                continue
            }
            if visuals[i] != p.visual {
                visuals[i] = p.visual
                let sprite = art.projectile(p.visual)
                sprites[i] = sprite
                n.apply(sprite)
            }
            n.isHidden = false
            guard let sprite = sprites[i] else { continue }
            let flight = sprite.clip("flight")
            if flight.frames.count > 1 {
                n.texture = flight.frames[flight.frameIndex(time: world.time)].texture
            }
            if sprite.motion == .arc {
                // Lobbed: height follows a sine arc; the shadow stays on the ground.
                let h = sin(p.flightProgress * .pi) * min(arcMax, p.plannedDistance * arcFactor)
                let g = view.ground(p.position)
                n.position = CGPoint(x: g.x, y: g.y + h + view.projectileHeight)
                n.setScale(1 + h * arcScale)
                n.zRotation += CGFloat(sprite.metric("spinPerSecond", 0)) / 60
                shadows[i].isHidden = !drawsShadows
                shadows[i].position = g
            } else {
                let g = view.ground(p.position)
                n.position = CGPoint(x: g.x, y: g.y + view.projectileHeight)
                // Heading on screen: the ground squash flattens vertical travel.
                n.zRotation = sprite.facing == .rotate ? atan2(sin(p.heading) * view.groundScaleY, cos(p.heading)) : 0
                n.setScale(1)
                shadows[i].isHidden = true
            }
        }
    }
}
