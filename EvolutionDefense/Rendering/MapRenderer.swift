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
        spawn.apply(art.spawn())
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

        let slotArt = art.slot(highlighted: false)
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
            let id = "deco.\(d.kind.rawValue)"
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
    }

    func setSlotHighlight(_ id: Int?) {
        guard id != highlightedSlot else { return }
        if let old = highlightedSlot { slotNodes[old]?.apply(art.slot(highlighted: false)) }
        if let id { slotNodes[id]?.apply(art.slot(highlighted: true)) }
        highlightedSlot = id
    }

    func setSlotVisible(_ id: Int, _ visible: Bool) {
        slotNodes[id]?.isHidden = !visible
    }

    func baseHit() { baseShake = 0.35 }

    /// Tint colour and strength per era (Primitive = untinted daylight).
    static func tint(for era: Era) -> (NSColor, CGFloat) {
        switch era {
        case .primitive: (NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), 0)
        case .medieval: (NSColor(srgbRed: 0.40, green: 0.46, blue: 0.62, alpha: 1), 0.22)
        case .industrial: (NSColor(srgbRed: 0.55, green: 0.38, blue: 0.16, alpha: 1), 0.34)
        case .futuristic: (NSColor(srgbRed: 0.04, green: 0.10, blue: 0.22, alpha: 1), 0.40)
        }
    }

    /// Switches the map to `era`; animated transitions cross-fade over ~2 s.
    func setEra(_ newEra: Era, animated: Bool) {
        guard newEra != era else { return }
        let (color, strength) = Self.tint(for: newEra)
        era = newEra
        eraTint.removeAllActions()
        if animated {
            oldBaseNode.apply(Art(texture: baseNode.texture!, size: baseNode.size))
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
        guard baseShake > 0 else { return }
        baseShake = max(0, baseShake - dt)
        let k = CGFloat(baseShake / 0.35)
        let home = art.view.ground(map.world(map.base))
        baseNode.position = CGPoint(x: home.x + CGFloat.random(in: -4...4) * k, y: home.y + CGFloat.random(in: -4...4) * k)
        baseNode.colorBlendFactor = 0.55 * k
    }
}
