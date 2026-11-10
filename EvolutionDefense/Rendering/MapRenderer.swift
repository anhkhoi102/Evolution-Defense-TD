import EvolutionDefenseAssets
import EvolutionDefenseCore
import SpriteKit

/// Static map visuals: baked terrain, build pads, spawn and base.
/// Eras re-tint the whole map with one full-screen quad (no re-baking) and
/// swap the base sprite; transitions cross-fade both.
@MainActor
final class MapRenderer {
    let root = SKNode()
    private(set) var slotNodes: [Int: SKSpriteNode] = [:]
    let baseNode: SKSpriteNode
    /// Previous-era base, faded out during a transition.
    private let oldBaseNode = SKSpriteNode()
    /// Full-map tint for the current era.
    private let eraTint: SKSpriteNode
    private(set) var era: Era = .primitive
    private let art: ArtLibrary
    private let map: MapDefinition
    private var highlightedSlot: Int?
    private var baseShake: Double = 0

    init(map: MapDefinition, art: ArtLibrary) {
        self.art = art
        self.map = map

        let bgSprite = art.mapBackground(map)
        let bg = SKSpriteNode(art: bgSprite.first)
        // Background is stretched to the playfield and placed by its anchor.
        bg.size = map.worldSize
        bg.anchorPoint = bgSprite.anchor
        bg.position = CGPoint(x: map.worldSize.width * bgSprite.anchor.x, y: map.worldSize.height * bgSprite.anchor.y)
        bg.zPosition = Layer.terrain
        bg.blendMode = .replace          // opaque: cheapest possible fill
        root.addChild(bg)

        eraTint = SKSpriteNode(color: .white, size: map.worldSize)
        eraTint.anchorPoint = .zero
        eraTint.zPosition = Layer.terrain + 1
        eraTint.alpha = 0
        root.addChild(eraTint)

        let view = art.view
        let spawn = SKSpriteNode()
        spawn.apply(art.spawn(map: map))
        spawn.position = view.ground(map.world(map.spawn))
        spawn.zPosition = view.isFlat ? Layer.spawnAndBase : Layer.units + view.depth(map.world(map.spawn))
        root.addChild(spawn)

        baseNode = SKSpriteNode()
        baseNode.apply(art.base(.primitive))
        baseNode.position = view.ground(map.world(map.base))
        baseNode.zPosition = view.isFlat ? Layer.spawnAndBase : Layer.units + view.depth(map.world(map.base)) - 0.01
        baseNode.colorBlendFactor = 0
        baseNode.color = .red
        root.addChild(baseNode)
        oldBaseNode.position = baseNode.position
        oldBaseNode.zPosition = baseNode.zPosition + 0.005
        oldBaseNode.isHidden = true
        root.addChild(oldBaseNode)

        let slotArt = art.slot(highlighted: false, map: map)
        for slot in map.buildSlots {
            let n = SKSpriteNode()
            n.apply(slotArt)
            n.position = view.ground(map.slotPosition(slot))
            n.zPosition = Layer.slots
            root.addChild(n)
            slotNodes[slot.id] = n
        }

        // Tall decorations (trees) as depth-sorted sprites, when the pack has them,
        // so units walking behind a tree are hidden by it. Placement comes from the
        // map's seeded decoration list — the same one the gameplay keep-out uses.
        for (i, d) in map.resolvedDecorations().enumerated() {
            let id = AssetID.decoration(d.kind.rawValue)
            guard art.has(id) else { continue }
            let s = art.sprite(id)
            let variants = s.clip("variants")
            let n = SKSpriteNode()
            n.apply(variants.frames[i % variants.frames.count])
            n.anchorPoint = s.anchor
            n.setScale(CGFloat(d.scale) * s.metric("scale", 1))
            let p = map.world(x: d.x, y: d.y)
            n.position = view.ground(p)
            n.zPosition = Layer.units + view.depth(p) - 0.001
            root.addChild(n)
        }
        setUpAmbient()
    }

    // MARK: Ambient effects (map.ambient): purely visual, off in performance mode

    private struct Sparkle {
        var node: SKSpriteNode
        var age: Double
        var life: Double
    }
    private var sparkles: [Sparkle] = []
    private var dust: SKEmitterNode?
    /// Performance mode hides ambient effects.
    var ambientEnabled = true {
        didSet {
            guard ambientEnabled != oldValue else { return }
            dust?.isHidden = !ambientEnabled
            dust?.particleBirthRate = ambientEnabled ? dustRate : 0
            for s in sparkles { s.node.isHidden = !ambientEnabled }
        }
    }
    private let dustRate: CGFloat = 5

    private func setUpAmbient() {
        let view = art.view
        guard !view.isFlat else { return }          // made for the 2.5D pack
        for kind in map.ambient ?? [] {
            switch kind {
            case "dust" where art.has("fx.smoke"):
                // Wind-blown sand drifting across the whole battlefield.
                let e = SKEmitterNode()
                e.particleTexture = art.fx("smoke").first.texture
                e.particleBirthRate = dustRate
                e.particleLifetime = 9; e.particleLifetimeRange = 3
                e.particlePositionRange = CGVector(dx: 80, dy: map.worldSize.height)
                e.position = CGPoint(x: -40, y: map.worldSize.height * 0.5)
                e.emissionAngle = 0.06; e.emissionAngleRange = 0.25
                e.particleSpeed = 150; e.particleSpeedRange = 60
                e.particleAlpha = 0; e.particleAlphaSpeed = 0
                e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.16, 0.12, 0], times: [0, 0.15, 0.8, 1])
                e.particleScale = 1.6; e.particleScaleRange = 0.9; e.particleScaleSpeed = 0.12
                e.particleRotationRange = 2 * .pi; e.particleRotationSpeed = 0.2
                e.particleColor = PlatformColor(srgbRed: 0.95, green: 0.84, blue: 0.62, alpha: 1)
                e.particleColorBlendFactor = 1
                e.zPosition = Layer.projectiles - 1
                e.advanceSimulationTime(10)          // already drifting when the match opens
                root.addChild(e)
                dust = e
            case "waterSparkle" where art.has("fx.spark") && !(map.water ?? []).isEmpty:
                // Glints of sunlight on the water.
                for i in 0..<14 {
                    let n = SKSpriteNode()
                    n.apply(art.fx("spark").first)
                    n.blendMode = .add
                    n.alpha = 0
                    n.zPosition = Layer.terrain + 2
                    root.addChild(n)
                    sparkles.append(Sparkle(node: n, age: 0, life: 0.2 + Double(i) * 0.19))   // staggered start
                }
            default:
                break
            }
        }
    }

    /// A random on-screen point in the map's water, in world coordinates.
    private func randomWaterPoint() -> CGPoint? {
        for _ in 0..<40 {
            let g = GridPoint(x: Double.random(in: 0.5...(Double(map.columns) - 0.5)),
                              y: Double.random(in: 0.5...(Double(map.rows) - 0.5)))
            if map.isInWater(g), !isNearShore(g) { return map.world(g) }
        }
        return nil
    }

    /// Keeps sparkles off the shoreline and bridges.
    private func isNearShore(_ g: GridPoint) -> Bool {
        if map.isOnBridge(g, margin: 0.4) { return true }
        for (dx, dy) in [(0.45, 0.0), (-0.45, 0.0), (0.0, 0.45), (0.0, -0.45)] where !map.isInWater(GridPoint(x: g.x + dx, y: g.y + dy)) {
            return true
        }
        return false
    }

    private func updateAmbient(dt: Double) {
        guard ambientEnabled, !sparkles.isEmpty else { return }
        for i in sparkles.indices {
            sparkles[i].age += dt
            let s = sparkles[i]
            if s.age >= s.life {
                sparkles[i].age = 0
                sparkles[i].life = Double.random(in: 1.0...2.2)
                if let p = randomWaterPoint() {
                    s.node.position = art.view.ground(p)
                    s.node.setScale(CGFloat.random(in: 0.45...0.95))
                    s.node.zRotation = CGFloat.random(in: 0...(.pi / 2))
                }
                s.node.alpha = 0
            } else {
                let t = s.age / s.life
                s.node.alpha = CGFloat(sin(t * .pi)) * 0.75        // fade in and out
            }
        }
    }

    func setSlotHighlight(_ id: Int?) {
        guard id != highlightedSlot else { return }
        if let old = highlightedSlot { slotNodes[old]?.apply(art.slot(highlighted: false, map: map)) }
        if let id { slotNodes[id]?.apply(art.slot(highlighted: true, map: map)) }
        highlightedSlot = id
    }

    func setSlotVisible(_ id: Int, _ visible: Bool) {
        slotNodes[id]?.isHidden = !visible
    }

    func baseHit() { baseShake = 0.35 }

    /// Tint colour and strength per era (Primitive = untinted daylight).
    static func tint(for era: Era) -> (PlatformColor, CGFloat) {
        switch era {
        case .primitive: (PlatformColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), 0)
        case .medieval: (PlatformColor(srgbRed: 0.40, green: 0.46, blue: 0.62, alpha: 1), 0.22)
        case .industrial: (PlatformColor(srgbRed: 0.55, green: 0.38, blue: 0.16, alpha: 1), 0.34)
        case .futuristic: (PlatformColor(srgbRed: 0.04, green: 0.10, blue: 0.22, alpha: 1), 0.40)
        }
    }

    /// Switches the map to `era`; animated transitions cross-fade over ~2 s.
    func setEra(_ newEra: Era, animated: Bool) {
        guard newEra != era else { return }
        let (color, strength) = Self.tint(for: newEra)
        era = newEra
        eraTint.removeAllActions()
        if animated {
            oldBaseNode.apply(Art(texture: baseNode.texture!, size: baseNode.unscaledSize))
            oldBaseNode.anchorPoint = baseNode.anchorPoint
            oldBaseNode.alpha = 1
            oldBaseNode.isHidden = false
            oldBaseNode.removeAllActions()
            oldBaseNode.run(.sequence([.fadeOut(withDuration: 1.6), .hide()]))
            baseNode.apply(art.base(newEra))
            baseNode.setScale(0.6)
            baseNode.run(.sequence([.wait(forDuration: 0.4), .scale(to: 1.08, duration: 0.5), .scale(to: 1, duration: 0.25)]))
            eraTint.run(.group([.colorize(with: color, colorBlendFactor: 1, duration: 2.0), .fadeAlpha(to: strength, duration: 2.0)]))
        } else {
            baseNode.apply(art.base(newEra))
            eraTint.color = color
            eraTint.alpha = strength
        }
    }

    func update(dt: Double) {
        updateAmbient(dt: dt)
        guard baseShake > 0 else { return }
        baseShake = max(0, baseShake - dt)
        let k = CGFloat(baseShake / 0.35)
        let home = art.view.ground(map.world(map.base))
        baseNode.position = CGPoint(x: home.x + CGFloat.random(in: -4...4) * k, y: home.y + CGFloat.random(in: -4...4) * k)
        baseNode.colorBlendFactor = 0.55 * k
    }
}
