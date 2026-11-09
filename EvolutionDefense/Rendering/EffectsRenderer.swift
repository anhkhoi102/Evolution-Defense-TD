import EvolutionDefenseCore
import SpriteKit

/// Short-lived visual effects, animated manually (no SKAction allocation per
/// effect) from pooled nodes. A hard cap keeps big fights cheap.
@MainActor
final class EffectsRenderer {
    private struct Effect {
        var node: SKSpriteNode
        var age: Double
        var life: Double
        var startScale: CGFloat
        var endScale: CGFloat
        var startAlpha: CGFloat
        var rise: CGFloat
        var origin: CGPoint
        /// When set, the effect travels from `origin` to here (missiles).
        var target: CGPoint?
        /// Frame-by-frame animation (death clips); nil = a single texture.
        var clip: AnimationClip?
        var direction = 0
        /// Lies on the ground: squashed by the view's ground scale (rings, scorch marks).
        var flat = false
        /// Seconds of dissolve at the end of the life (dissolve shader); 0 = plain fade.
        var dissolve: Double = 0
    }

    private struct Emitter {
        var node: SKEmitterNode
        var age: Double
        var life: Double
        var kind: Int
    }

    private struct FloatingText {
        var node: SKLabelNode
        var age: Double
        var life: Double
        var origin: CGPoint
    }

    let groundLayer = SKNode()
    let airLayer = SKNode()
    let textLayer = SKNode()
    private var effects: [Effect] = []
    private var spritePool: [SKSpriteNode] = []
    private var texts: [FloatingText] = []
    private var labelPool: [SKLabelNode] = []
    private let art: ArtLibrary
    /// Lower in performance mode.
    var maxEffects = 160
    /// Performance mode: fewer simultaneous effects, no cosmetic extras.
    var lightweight = false {
        didSet { maxEffects = lightweight ? 60 : 160 }
    }

    init(art: ArtLibrary) {
        self.art = art
        groundLayer.zPosition = Layer.groundFX
        airLayer.zPosition = Layer.airFX
        textLayer.zPosition = Layer.floatingText
        effects.reserveCapacity(maxEffects)
    }

    // MARK: Spawning

    func explosion(at p: CGPoint, radius: CGFloat) {
        let d = max(30, radius * 2)
        spawn(fx("explosion"), at: p, layer: airLayer, life: 0.32, from: d / fxWidth("explosion") * 0.35, to: d / fxWidth("explosion"), alpha: 0.95, blend: .add)
        spawn(fx("ring"), at: p, layer: groundLayer, life: 0.3, from: d / fxWidth("ring") * 0.4, to: d / fxWidth("ring"), alpha: 0.5, flat: true)
        guard !lightweight else { return }
        if hasScorch, effects.count < maxEffects - 40 {
            spawn(fx("scorch"), at: p, layer: groundLayer, life: 2.2, from: d / fxWidth("scorch") * 0.9, to: d / fxWidth("scorch"),
                  alpha: 0.55, flat: true)
        }
        emit(0, at: p, count: Int(min(22, 8 + radius / 5)), spread: d)   // embers
        emit(1, at: p, count: radius > 40 ? 6 : 4, spread: d)            // smoke
    }

    func hit(at p: CGPoint) {
        spawn(fx("spark"), at: p, layer: airLayer, life: 0.12, from: 0.6, to: 1.2, alpha: 0.9, blend: .add,
              lift: view.projectileHeight)
    }

    func death(at p: CGPoint, big: Bool) {
        spawn(fx("puff"), at: p, layer: airLayer, life: big ? 0.8 : 0.45, from: big ? 1.2 : 0.5, to: big ? 3.2 : 1.2, alpha: 0.85, rise: 10)
        if big && !lightweight {
            emit(0, at: p, count: 30, spread: 90)
            emit(1, at: p, count: 10, spread: 90)
        }
    }

    /// Tower evolved: golden ring burst, sparks and a level label.
    func levelUp(at p: CGPoint, level: Int) {
        let gold = NSColor(srgbRed: 1, green: 0.82, blue: 0.3, alpha: 1)
        spawn(fx("ring"), at: p, layer: airLayer, life: 0.5, from: 0.35, to: 1.1, alpha: 0.95, tint: gold)
        spawn(fx("explosion"), at: p, layer: airLayer, life: 0.35, from: 0.4, to: 1.3, alpha: 0.6, blend: .add)
        for k in 0..<6 {
            let a = CGFloat(k) / 6 * 2 * .pi
            spawn(fx("spark"), at: CGPoint(x: p.x + cos(a) * 22, y: p.y + sin(a) * 22), layer: airLayer,
                  life: 0.4, from: 0.8, to: 0.2, alpha: 1, rise: 12, blend: .add)
        }
        text("LEVEL \(level)", at: CGPoint(x: p.x, y: p.y + 30), color: gold, size: 16)
    }

    func sold(at p: CGPoint, refund: Int) {
        spawn(fx("puff"), at: p, layer: airLayer, life: 0.5, from: 0.8, to: 1.8, alpha: 0.8, rise: 6)
        gold(refund, at: CGPoint(x: p.x, y: p.y + 20))
    }

    func heal(_ amount: Int, at p: CGPoint) {
        let green = NSColor(srgbRed: 0.45, green: 0.95, blue: 0.45, alpha: 1)
        spawn(fx("ring"), at: p, layer: airLayer, life: 0.6, from: 0.5, to: 1.4, alpha: 0.9, tint: green)
        text("+\(amount) HP", at: CGPoint(x: p.x, y: p.y + 50), color: green, size: 17)
    }

    // MARK: Phase 3 effects

    /// Boss changes phase: red shockwave and the phase name.
    func bossPhase(_ name: String, at p: CGPoint) {
        let red = NSColor(srgbRed: 1, green: 0.25, blue: 0.2, alpha: 1)
        spawn(fx("ring"), at: p, layer: airLayer, life: 0.9, from: 0.4, to: 3.2, alpha: 1, tint: red)
        spawn(fx("explosion"), at: p, layer: airLayer, life: 0.5, from: 0.8, to: 2.4, alpha: 0.7, blend: .add)
        text(name.uppercased(), at: CGPoint(x: p.x, y: p.y + 60), color: red, size: 22, life: 1.6)
    }

    /// Reinforcements / brood: a coloured ring where they appear.
    func summon(at p: CGPoint, color: NSColor) {
        spawn(fx("ring"), at: p, layer: groundLayer, life: 0.6, from: 0.3, to: 1.4, alpha: 0.9, tint: color, flat: true)
        spawn(fx("puff"), at: p, layer: airLayer, life: 0.5, from: 0.6, to: 1.5, alpha: 0.6, tint: color)
    }

    /// Fire breath / EMP hitting towers.
    func towerDisabled(at p: CGPoint, emp: Bool) {
        if emp {
            let cyan = NSColor(srgbRed: 0.45, green: 0.88, blue: 1, alpha: 1)
            spawn(fx("ring"), at: p, layer: airLayer, life: 0.45, from: 0.2, to: 0.8, alpha: 1, tint: cyan)
            spawn(fx("spark"), at: p, layer: airLayer, life: 0.3, from: 1.5, to: 2.5, alpha: 1, blend: .add, tint: cyan)
        } else {
            spawn(fx("explosion"), at: p, layer: airLayer, life: 0.6, from: 0.5, to: 1.2, alpha: 0.9, blend: .add)
            spawn(fx("puff"), at: p, layer: airLayer, life: 0.9, from: 0.6, to: 1.4, alpha: 0.7, rise: 18,
                  tint: NSColor(srgbRed: 0.25, green: 0.22, blue: 0.2, alpha: 1))
        }
    }

    /// Big pulse from the boss when it uses a tower-disabling ability.
    func shockwave(at p: CGPoint, radius: CGFloat, emp: Bool) {
        let color = emp ? NSColor(srgbRed: 0.45, green: 0.88, blue: 1, alpha: 1) : NSColor(srgbRed: 1, green: 0.5, blue: 0.15, alpha: 1)
        spawn(fx("ring"), at: p, layer: groundLayer, life: 0.55, from: 0.3, to: radius * 2 / fxWidth("ring"), alpha: 0.85, tint: color, flat: true)
    }

    /// Missile flying from the boss to the base, exploding on arrival.
    func missile(from a: CGPoint, to b: CGPoint) {
        let life = 0.7
        spawn(fx("missile"), at: a, layer: airLayer, life: life, from: 1.4, to: 1.4, alpha: 1, target: b, rotation: (b - a).angle)
        pendingBlasts.append((b, life))
    }

    func shieldAbsorbed(at p: CGPoint) {
        let cyan = NSColor(srgbRed: 0.45, green: 0.88, blue: 1, alpha: 1)
        spawn(fx("ring"), at: p, layer: airLayer, life: 0.5, from: 0.9, to: 1.3, alpha: 0.9, tint: cyan)
    }

    func critical(at p: CGPoint) {
        guard !lightweight, texts.count < 24 else { return }
        text("CRIT", at: CGPoint(x: p.x + 10, y: p.y + 14), color: NSColor(srgbRed: 1, green: 0.55, blue: 0.2, alpha: 1), size: 12, life: 0.5)
    }

    /// Short flash at the muzzle when a tower fires.
    /// Muzzle flash; the colour comes from the projectile sprite's `tint` (none = no flash)
    /// and the distance from the tower head's `muzzleDistance` metric.
    /// `lift` is the weapon's height above the ground on screen (the head's `mountY`).
    func muzzleFlash(at towerPos: CGPoint, angle: CGFloat, tint: NSColor?, distance: CGFloat, lift: CGFloat = 0) {
        guard let tint, effects.count < maxEffects - 40 else { return }    // never crowd out impacts
        // Offset along the aim as seen on screen (depth is squashed by the view).
        let dx = cos(angle) * distance, dy = sin(angle) * distance * view.groundScaleY
        let base = view.ground(towerPos)
        let p = CGPoint(x: base.x + dx, y: base.y + dy + lift)
        if hasMuzzle {
            spawnScreen(fx("muzzle"), at: p, life: 0.09, from: 0.8, to: 1.25, alpha: 1, blend: .add, tint: tint,
                        rotation: atan2(dy, dx))
        } else {
            spawnScreen(fx("spark"), at: p, life: 0.08, from: 1.0, to: 1.6, alpha: 0.95, blend: .add, tint: tint, rotation: nil)
        }
    }

    /// Dying enemy: its last frame shrinks and fades instead of vanishing.
    func corpse(_ a: Art, at p: CGPoint, rotation: CGFloat, size: CGSize) {
        guard !lightweight, effects.count < maxEffects - 20 else { return }
        spawn(a, at: p, layer: groundLayer, life: 0.45, from: 1, to: 0.55, alpha: 0.85, rotation: rotation)
        effects[effects.count - 1].node.size = size
        effects[effects.count - 1].node.color = .black
        effects[effects.count - 1].node.colorBlendFactor = 0.45
    }

    /// How long a death animation holds its last frame while it dissolves.
    private let dissolveTime = 0.55

    /// Plays a one-shot sprite animation (e.g. an enemy's "death" clip from the manifest).
    func play(_ clip: AnimationClip, direction: Int = 0, at p: CGPoint, rotation: CGFloat, flipped: Bool) {
        guard !lightweight, !clip.frames.isEmpty, effects.count < maxEffects - 20 else { return }
        spawn(clip.art(direction: direction, frame: 0), at: p, layer: groundLayer, life: clip.duration + dissolveTime, from: 1, to: 1,
              alpha: 1, rotation: rotation, frames: clip)
        let e = effects.count - 1
        effects[e].direction = direction
        effects[e].dissolve = dissolveTime
        effects[e].node.shader = Shaders.dissolve
        Shaders.setDissolve(effects[e].node, 0)
        // Death frames sort with the units at their ground depth (the corpse
        // stays behind enemies further down the screen).
        effects[e].node.zPosition = Layer.units - Layer.groundFX + view.depth(p) - 0.01
        if flipped { effects[e].node.xScale = -1 }
    }

    func researched(at p: CGPoint) {
        let blue = NSColor(srgbRed: 0.36, green: 0.82, blue: 0.95, alpha: 1)
        spawn(fx("ring"), at: p, layer: airLayer, life: 0.5, from: 0.3, to: 0.9, alpha: 0.9, tint: blue)
    }

    func gold(_ amount: Int, at p: CGPoint) {
        text("+\(amount)", at: p, color: NSColor(srgbRed: 1, green: 0.86, blue: 0.3, alpha: 1), size: 15)
    }

    private func text(_ string: String, at p: CGPoint, color: NSColor, size: CGFloat, life: Double = 0.9) {
        guard texts.count < (lightweight ? 12 : 40) else { return }
        let l = labelPool.popLast() ?? {
            // Display face registered by Theme.registerFonts(); system heavy font otherwise.
            let n = SKLabelNode(fontNamed: NSFont(name: "LilitaOne", size: 12) != nil ? "LilitaOne" : "AvenirNext-Heavy")
            n.verticalAlignmentMode = .center
            return n
        }()
        l.fontSize = size
        l.fontColor = color
        l.text = string
        let p = view.ground(p)
        l.position = p
        l.alpha = 1
        textLayer.addChild(l)
        texts.append(FloatingText(node: l, age: 0, life: life, origin: p))
    }

    private func fx(_ name: String) -> Art { art.fx(name).first }
    private lazy var hasMuzzle = art.has("fx.muzzle")
    private lazy var hasScorch = art.has("fx.scorch")
    private lazy var hasParticles = art.has("fx.ember") && art.has("fx.smoke")
    /// Effects receive world positions and project them for the art's camera.
    private lazy var view = art.view
    private func fxWidth(_ name: String) -> CGFloat { max(1, art.fx(name).size.width) }

    private func spawn(_ a: Art, at p: CGPoint, layer: SKNode, life: Double, from: CGFloat, to: CGFloat,
                       alpha: CGFloat, rise: CGFloat = 0, blend: SKBlendMode = .alpha, tint: NSColor? = nil,
                       target: CGPoint? = nil, rotation: CGFloat? = nil, frames clip: AnimationClip? = nil,
                       lift: CGFloat = 0, flat: Bool = false) {
        guard effects.count < maxEffects else { return }
        let n = spritePool.popLast() ?? SKSpriteNode()
        n.apply(a)
        n.shader = nil
        n.zPosition = 0
        n.blendMode = blend
        n.color = tint ?? .white
        n.colorBlendFactor = tint == nil ? 0 : 1
        var p = view.ground(p)
        p.y += lift
        let target = target.map { view.ground($0) }
        n.position = p
        n.setScale(from)
        n.alpha = alpha
        n.zRotation = flat ? 0 : rotation ?? CGFloat.random(in: 0...(2 * .pi))
        if flat { n.yScale = from * view.groundScaleY }
        layer.addChild(n)
        effects.append(Effect(node: n, age: 0, life: life, startScale: from, endScale: to, startAlpha: alpha, rise: rise,
                              origin: p, target: target, clip: clip, flat: flat))
    }

    /// Spawns at a screen position (already projected), in the air layer.
    private func spawnScreen(_ a: Art, at p: CGPoint, life: Double, from: CGFloat, to: CGFloat, alpha: CGFloat,
                             blend: SKBlendMode, tint: NSColor?, rotation: CGFloat?) {
        guard effects.count < maxEffects else { return }
        let n = spritePool.popLast() ?? SKSpriteNode()
        n.apply(a)
        n.shader = nil
        n.zPosition = 0
        n.blendMode = blend
        n.color = tint ?? .white
        n.colorBlendFactor = tint == nil ? 0 : 1
        n.position = p
        n.setScale(from)
        n.alpha = alpha
        n.zRotation = rotation ?? CGFloat.random(in: 0...(2 * .pi))
        airLayer.addChild(n)
        effects.append(Effect(node: n, age: 0, life: life, startScale: from, endScale: to, startAlpha: alpha, rise: 0,
                              origin: p, target: nil, clip: nil))
    }

    // MARK: Particle emitters (pooled SKEmitterNodes)

    private var emitters: [Emitter] = []
    private var emitterPool: [[SKEmitterNode]] = [[], []]
    /// Simultaneous emitters; each is a short burst.
    private let maxEmitters = 14

    /// kind 0 = embers (additive sparks thrown out and falling), 1 = smoke (rises, grows, fades).
    private func emit(_ kind: Int, at world: CGPoint, count: Int, spread: CGFloat) {
        guard hasParticles, !lightweight, emitters.count < maxEmitters else { return }
        let e = emitterPool[kind].popLast() ?? makeEmitter(kind)
        e.resetSimulation()
        e.numParticlesToEmit = count
        e.particleBirthRate = CGFloat(count) * 40
        e.particlePositionRange = CGVector(dx: spread * 0.3, dy: spread * 0.3 * view.groundScaleY)
        var p = view.ground(world)
        p.y += kind == 0 ? 6 : 10
        e.position = p
        airLayer.addChild(e)
        emitters.append(Emitter(node: e, age: 0, life: kind == 0 ? 0.8 : 1.4, kind: kind))
    }

    private func makeEmitter(_ kind: Int) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleZPosition = 0
        if kind == 0 {
            e.particleTexture = fx("ember").texture
            e.particleBlendMode = .add
            e.particleLifetime = 0.55; e.particleLifetimeRange = 0.25
            e.particleSpeed = 110; e.particleSpeedRange = 70
            e.emissionAngle = .pi / 2; e.emissionAngleRange = .pi * 1.4
            e.yAcceleration = -260
            e.particleScale = 0.9; e.particleScaleRange = 0.4; e.particleScaleSpeed = -1.2
            e.particleAlpha = 1; e.particleAlphaSpeed = -1.4
            e.particleColorBlendFactor = 1
            e.particleColorSequence = SKKeyframeSequence(
                keyframeValues: [NSColor(srgbRed: 1, green: 0.95, blue: 0.7, alpha: 1),
                                 NSColor(srgbRed: 1, green: 0.55, blue: 0.15, alpha: 1),
                                 NSColor(srgbRed: 0.7, green: 0.15, blue: 0.05, alpha: 1)],
                times: [0, 0.4, 1])
        } else {
            e.particleTexture = fx("smoke").texture
            e.particleBlendMode = .alpha
            e.particleLifetime = 1.1; e.particleLifetimeRange = 0.3
            e.particleSpeed = 18; e.particleSpeedRange = 10
            e.emissionAngle = .pi / 2; e.emissionAngleRange = .pi
            e.yAcceleration = 22
            e.particleScale = 0.7; e.particleScaleRange = 0.3; e.particleScaleSpeed = 0.8
            e.particleAlpha = 0.7; e.particleAlphaRange = 0.15; e.particleAlphaSpeed = -0.6
            e.particleRotationRange = 2 * .pi; e.particleRotationSpeed = 0.6
        }
        return e
    }

    // MARK: Update

    private var pendingBlasts: [(CGPoint, Double)] = []

    func update(dt: Double) {
        var k = 0
        while k < pendingBlasts.count {
            pendingBlasts[k].1 -= dt
            if pendingBlasts[k].1 <= 0 {
                explosion(at: pendingBlasts[k].0, radius: 50)
                pendingBlasts.swapAt(k, pendingBlasts.count - 1)
                pendingBlasts.removeLast()
            } else { k += 1 }
        }
        var i = 0
        while i < effects.count {
            effects[i].age += dt
            let e = effects[i]
            let t = CGFloat(min(1, e.age / e.life))
            if t >= 1 {
                e.node.removeFromParent()
                spritePool.append(e.node)
                effects.swapAt(i, effects.count - 1)
                effects.removeLast()
                continue
            }
            if let clip = e.clip {
                // Animated effect: step through the frames (holding the last), then dissolve.
                e.node.texture = clip.art(direction: e.direction, frame: clip.frameIndex(time: e.age)).texture
                if e.dissolve > 0 {
                    let d = (e.age - (e.life - e.dissolve)) / e.dissolve
                    if d > 0 { Shaders.setDissolve(e.node, Float(min(1, d))) }
                }
                i += 1
                continue
            }
            let ease = 1 - (1 - t) * (1 - t)
            let sc = e.startScale + (e.endScale - e.startScale) * ease
            if e.flat {
                e.node.xScale = sc; e.node.yScale = sc * view.groundScaleY
            } else {
                e.node.setScale(sc)
            }
            if let target = e.target {
                // Travelling effect: accelerate towards the target, stay opaque.
                let k = t * t
                e.node.position = CGPoint(x: e.origin.x + (target.x - e.origin.x) * k, y: e.origin.y + (target.y - e.origin.y) * k)
            } else {
                e.node.alpha = e.startAlpha * (1 - t)
                if e.rise != 0 { e.node.position = CGPoint(x: e.origin.x, y: e.origin.y + e.rise * t) }
            }
            i += 1
        }
        i = 0
        while i < emitters.count {
            emitters[i].age += dt
            if emitters[i].age >= emitters[i].life {
                let e = emitters[i]
                e.node.removeFromParent()
                emitterPool[e.kind].append(e.node)
                emitters.swapAt(i, emitters.count - 1)
                emitters.removeLast()
                continue
            }
            i += 1
        }
        i = 0
        while i < texts.count {
            texts[i].age += dt
            let f = texts[i]
            let t = CGFloat(min(1, f.age / f.life))
            if t >= 1 {
                f.node.removeFromParent()
                labelPool.append(f.node)
                texts.swapAt(i, texts.count - 1)
                texts.removeLast()
                continue
            }
            f.node.position = CGPoint(x: f.origin.x, y: f.origin.y + 26 * t)
            f.node.alpha = t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4
            i += 1
        }
    }

    var activeCount: Int { effects.count + texts.count + emitters.count }
}
