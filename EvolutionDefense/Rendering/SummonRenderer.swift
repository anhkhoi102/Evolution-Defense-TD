import EvolutionDefenseAssets
import EvolutionDefenseCore
import SpriteKit

// Summoned allies (militia, hero). Mirrors GameWorld.summons into pooled nodes,
// like EnemyRenderer: art and sizes come from the manifest (`summon.<visual>`),
// gameplay (position, state, timers) from the simulation. Deaths and expiries
// are drawn by the effects layer from the simulation's events.

@MainActor
final class SummonVisual {
    let body = SKSpriteNode()
    /// Blue ring on the ground: "this one is on your side".
    let ring = SKSpriteNode()
    let barBack = SKSpriteNode(color: PlatformColor(white: 0, alpha: 0.65), size: CGSize(width: 24, height: 4))
    let barFill = SKSpriteNode(color: .cyan, size: CGSize(width: 22, height: 2))
    var sprite: SpriteAsset?
    var stamp = 0
    var frameKey = -1
    var barWidth: CGFloat = 22
    var barOffsetY: CGFloat = 30
    var tint = SIMD4<Float>(-1, 0, 0, 0)

    init() {
        barFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        body.shader = Shaders.status
    }
}

@MainActor
final class SummonRenderer {
    let layer = SKNode()
    let barLayer = SKNode()
    var lightweight = false
    private var active: [Int: SummonVisual] = [:]
    private var pool: [SummonVisual] = []
    private var stamp = 0
    private let art: ArtLibrary
    private lazy var view = art.view
    private static let allyBlue = PlatformColor(srgbRed: 0.35, green: 0.7, blue: 1, alpha: 1)
    private static let heroGold = PlatformColor(srgbRed: 1, green: 0.8, blue: 0.35, alpha: 1)

    init(art: ArtLibrary) {
        self.art = art
        layer.zPosition = Layer.units
        barLayer.zPosition = Layer.healthBars
    }

    /// Visible summoned units (diagnostics / leak checks).
    var visibleCount: Int { active.count }

    func sync(world: GameWorld) {
        stamp &+= 1
        let now = world.time
        for u in world.summons where u.isAlive {
            let v = active[u.id] ?? attach(u)
            v.stamp = stamp
            guard let sprite = v.sprite else { continue }
            let screen = view.ground(u.position)
            v.body.position = screen
            v.body.zPosition = view.depth(u.position) + 0.003
            v.ring.position = screen
            v.ring.zPosition = v.body.zPosition - 0.002

            // Animation: attack (one-shot after each blow) > walk > idle.
            let sinceAttack = now - u.lastAttackTime
            let clip: AnimationClip
            let clipIndex: Int
            var t = now - u.spawnTime
            if let attack = sprite.animations["attack"], sinceAttack < attack.duration {
                clip = attack; clipIndex = 2; t = sinceAttack
            } else if u.state == .moving, let walk = sprite.animations["walk"] {
                clip = walk; clipIndex = 1
            } else {
                clip = sprite.clip("idle", "walk"); clipIndex = 0
            }
            let dir = sprite.facing == .directional ? clip.direction(for: u.heading) : 0
            let f = clip.frameIndex(time: t)
            let key = clipIndex * 1_000_000 + dir * 1000 + f
            if key != v.frameKey {
                v.frameKey = key
                v.body.texture = clip.art(direction: dir, frame: f).texture
            }
            if sprite.facing == .rotate { v.body.zRotation = u.heading }

            // Hurt flash (red) when enemies are hitting it; blink in the last two seconds.
            let hurt = now - u.lastHitTakenTime < 0.12
            let tint: SIMD4<Float> = hurt ? SIMD4(1, 0.25, 0.2, 0.45) : SIMD4(0, 0, 0, 0)
            if tint != v.tint { v.tint = tint; Shaders.setTint(v.body, tint) }
            let left = u.remaining(at: now)
            v.body.alpha = left < 2 && !lightweight ? 0.55 + 0.45 * CGFloat(abs(sin(now * 9))) : 1
            v.ring.alpha = (lightweight ? 0.6 : 0.5 + 0.25 * CGFloat(sin(now * 3 + Double(u.id)))) * v.body.alpha

            // Health bar (always shown: summons are few and their HP matters).
            let top = CGPoint(x: screen.x, y: screen.y + v.barOffsetY)
            v.barBack.position = top
            v.barFill.position = CGPoint(x: top.x - v.barWidth / 2, y: top.y)
            v.barFill.size.width = max(0.5, v.barWidth * CGFloat(u.hpFraction))
        }
        guard active.count > world.summons.count || active.values.contains(where: { $0.stamp != stamp }) else { return }
        for (id, v) in active where v.stamp != stamp {
            active.removeValue(forKey: id)
            v.body.removeFromParent(); v.ring.removeFromParent()
            v.barBack.removeFromParent(); v.barFill.removeFromParent()
            v.sprite = nil
            pool.append(v)
        }
    }

    /// The unit's current frame, for death and expiry effects.
    func currentArt(of u: SummonUnit) -> (art: Art, size: CGSize, anchor: CGPoint)? {
        guard let v = active[u.id], let s = v.sprite, let tex = v.body.texture else { return nil }
        return (Art(texture: tex, size: s.size), s.size, s.anchor)
    }

    private func attach(_ u: SummonUnit) -> SummonVisual {
        let v = pool.popLast() ?? SummonVisual()
        let sprite = art.summon(u.ability)
        v.sprite = sprite
        v.frameKey = -1
        v.tint = SIMD4(-1, 0, 0, 0)
        v.body.setScale(1)
        v.body.apply(sprite)
        v.body.alpha = 1
        v.ring.apply(art.fx("ring"))
        v.ring.color = u.isHero ? Self.heroGold : Self.allyBlue
        v.ring.colorBlendFactor = 1
        v.ring.blendMode = .add
        v.ring.setScale(1)
        let w = max(CGFloat(u.stats.radius) * (u.isHero ? 4.4 : 3.6), sprite.size.width * (u.isHero ? 0.8 : 0.7))
        v.ring.setUnscaledSize(CGSize(width: w, height: w * view.groundScaleY))
        v.barWidth = sprite.metric("healthBarWidth", u.isHero ? 34 : 22)
        v.barOffsetY = sprite.metric("healthBarOffsetY", sprite.size.height * 0.6)
        v.barBack.size = CGSize(width: v.barWidth + 2, height: u.isHero ? 5 : 4)
        v.barFill.size = CGSize(width: v.barWidth, height: u.isHero ? 3 : 2)
        v.barFill.color = u.isHero ? Self.heroGold : Self.allyBlue
        layer.addChild(v.ring)
        layer.addChild(v.body)
        barLayer.addChild(v.barBack)
        barLayer.addChild(v.barFill)
        v.barFill.zPosition = 1
        active[u.id] = v
        return v
    }
}
