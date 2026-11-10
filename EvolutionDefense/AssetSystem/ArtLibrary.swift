// The single texture provider. Renderers ask for sprites by asset id
// (`AssetID`); the asset manifest (AssetPack/asset_manifest.json, plus an
// optional override pack) decides where each frame comes from:
//
//   image      → asset-catalog image set or bundled PNG (@2x picked automatically)
//   atlas      → frame in a .spriteatlas
//   procedural → code-drawn placeholder (Art/ProceduralArt.swift)
//
// Swapping the whole art style means shipping new images and a manifest —
// gameplay code and renderers stay unchanged. See Docs/ASSETS.md.

import AppKit
import EvolutionDefenseAssets
import EvolutionDefenseCore
import SpriteKit

/// World (top-down simulation) → screen mapping for the art's camera.
/// Gameplay never sees this: it only places sprites. Identity for top-down art;
/// the baked 2.5D pack squashes ground depth and lifts heights.
struct ViewProjection {
    var groundScaleY: CGFloat
    var offsetY: CGFloat
    /// Screen points per point of height above the ground.
    var heightScale: CGFloat
    /// Visual flight height of straight projectiles (points of screen lift).
    var projectileHeight: CGFloat

    var isFlat: Bool { groundScaleY == 1 && offsetY == 0 }

    @inline(__always) func ground(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: offsetY + p.y * groundScaleY) }
    @inline(__always) func world(fromScreen s: CGPoint) -> CGPoint { CGPoint(x: s.x, y: (s.y - offsetY) / groundScaleY) }
    /// Draw-order key inside a layer: nearer the viewer (smaller world y) = higher.
    @inline(__always) func depth(_ p: CGPoint) -> CGFloat { 10 - min(10, max(0, p.y / 100)) }
}

/// A texture plus its on-screen size in points.
struct Art {
    let texture: SKTexture
    let size: CGSize
}

/// One animation of a sprite, ready to play.
struct AnimationClip {
    let frames: [Art]
    let fps: Double?
    let distancePerFrame: CGFloat?
    let loops: Bool
    /// View directions (1 = a single, rotatable view).
    var directions: Int = 1

    var framesPerDirection: Int { max(1, frames.count / max(1, directions)) }
    var duration: Double { Double(framesPerDirection) / max(fps ?? 12, 0.01) }

    /// Frame within one direction set, by time.
    func frameIndex(time t: Double) -> Int {
        let n = framesPerDirection
        guard n > 1 else { return 0 }
        let i = Int(t * (fps ?? 12))
        return loops ? i % n : min(i, n - 1)
    }

    /// Frame within one direction set, by distance travelled.
    func frameIndex(distance d: CGFloat) -> Int {
        let n = framesPerDirection
        guard n > 1, let step = distancePerFrame, step > 0 else { return 0 }
        return Int(d / step) % n
    }

    /// Direction set closest to a heading (radians, 0 = +x, counter-clockwise).
    func direction(for angle: CGFloat) -> Int {
        guard directions > 1 else { return 0 }
        let step = 2 * CGFloat.pi / CGFloat(directions)
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return Int((a / step).rounded()) % directions
    }

    /// Texture for a direction and frame.
    func art(direction: Int, frame: Int) -> Art {
        frames[min(frames.count - 1, direction * framesPerDirection + frame)]
    }
}

/// A resolved manifest entry: size, anchor, facing, animations and metrics.
struct SpriteAsset {
    let id: String
    let size: CGSize
    let anchor: CGPoint
    let facing: SpriteSpec.Facing
    let animations: [String: AnimationClip]
    let metrics: [String: Double]
    let tint: NSColor?
    let motion: SpriteSpec.Motion

    /// First matching animation, else `default`, else any.
    func clip(_ names: String...) -> AnimationClip {
        for n in names { if let c = animations[n] { return c } }
        return animations["default"] ?? animations.values.first!
    }

    var first: Art { clip().frames[0] }

    func metric(_ key: String, _ fallback: CGFloat) -> CGFloat { metrics[key].map { CGFloat($0) } ?? fallback }
}

@MainActor
final class ArtLibrary {
    static let shared = ArtLibrary()

    private(set) var manifest: AssetManifest
    /// The full placeholder pack; frames a replacement pack fails to load fall back to it.
    private var basePack: AssetManifest
    private(set) var issues: [AssetValidator.Issue] = []
    private var config: GameConfiguration?
    private var sprites: [String: SpriteAsset] = [:]
    private var imageCache: [String: CGImage] = [:]
    private var warnedMissing = Set<String>()

    private init() {
        // Layer 1: procedural placeholders for every id (always complete).
        // Layer 2: the shipped art pack (baked 2.5D sprites) on top.
        basePack = Self.loadManifest(named: "asset_manifest.placeholder") ?? AssetManifest(name: "empty", sprites: [:])
        manifest = basePack
        if ProcessInfo.processInfo.environment["EVO_PLACEHOLDER_ART"] == nil,
           let shipped = Self.loadManifest(named: "asset_manifest") {
            manifest = basePack.merged(with: shipped)
            print("Assets: '\(shipped.name)' over '\(basePack.name)'")
        }
        // Optional replacement pack layered on top: EVO_ASSET_PACK=<name> loads
        // asset_manifest.<name>.json from the bundle (see Docs/ASSETS.md).
        if let pack = ProcessInfo.processInfo.environment["EVO_ASSET_PACK"],
           let override = Self.loadManifest(named: "asset_manifest.\(pack)") {
            manifest = manifest.merged(with: override)
            print("Assets: using pack '\(override.name)'")
        }
    }

    /// Called once the game data is loaded: validates coverage and logs problems.
    func prepare(config: GameConfiguration) {
        self.config = config
        issues = AssetValidator.validate(manifest, config: config)
        for i in issues { print("Assets: \(i)") }
    }

    private static func loadManifest(named name: String) -> AssetManifest? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { return nil }
        do {
            return try AssetManifest.decode(try Data(contentsOf: url))
        } catch {
            print("Assets: \(name).json is invalid: \(error)")
            return nil
        }
    }

    var textureScale: CGFloat { CGFloat(manifest.textureScale ?? 2) }

    func layout(_ key: String, _ fallback: CGFloat) -> CGFloat {
        manifest.layout?[key].map { CGFloat($0) } ?? fallback
    }

    /// The camera the art was made for (identity for top-down packs).
    var view: ViewProjection {
        ViewProjection(groundScaleY: layout("view.groundScaleY", 1), offsetY: layout("view.groundOffsetY", 0),
                       heightScale: layout("view.heightScale", 0), projectileHeight: layout("view.projectileHeight", 0))
    }

    // MARK: Sprites

    func sprite(_ id: String) -> SpriteAsset {
        if let s = sprites[id] { return s }
        let s = resolve(id, spec: manifest.sprites[id], allowFallback: true)
        sprites[id] = s
        return s
    }

    private func resolve(_ id: String, spec: SpriteSpec?, allowFallback: Bool) -> SpriteAsset {
        guard let spec else { return missing(id, reason: "not in the manifest") }
        var clips: [String: AnimationClip] = [:]
        var size: CGSize?
        if let s = spec.size { size = CGSize(width: s.width, height: s.height) }
        for (name, anim) in spec.animations {
            var frames: [Art] = []
            for f in anim.frames {
                guard let (tex, native) = load(f) else {
                    // A replacement pack missing a file falls back to the placeholder sprite.
                    if allowFallback, let base = basePack.sprites[id], base != spec {
                        warn(id, "frame \(f) not found — using placeholder")
                        return resolve(id, spec: base, allowFallback: false)
                    }
                    return missing(id, reason: "frame \(f) not found")
                }
                if size == nil { size = native }
                frames.append(Art(texture: tex, size: native))
            }
            clips[name] = AnimationClip(frames: frames, fps: anim.fps, distancePerFrame: anim.distancePerFrame.map { CGFloat($0) },
                                        loops: anim.loops, directions: max(1, anim.directions ?? 1))
        }
        guard let finalSize = size, !clips.isEmpty else { return missing(id, reason: "no frames") }
        // All frames of a sprite share its display size.
        for (k, c) in clips {
            clips[k] = AnimationClip(frames: c.frames.map { Art(texture: $0.texture, size: finalSize) }, fps: c.fps,
                                     distancePerFrame: c.distancePerFrame, loops: c.loops, directions: c.directions)
        }
        return SpriteAsset(id: id, size: finalSize,
                           anchor: CGPoint(x: spec.anchor?.x ?? 0.5, y: spec.anchor?.y ?? 0.5),
                           facing: spec.facing ?? .rotate, animations: clips, metrics: spec.metrics ?? [:],
                           tint: spec.tint.flatMap(AssetValidator.parseHex).map { NSColor(cgColor: rgb($0))! },
                           motion: spec.motion ?? .straight)
    }

    /// Loads one frame. Native size is in points.
    private func load(_ f: FrameSource) -> (SKTexture, CGSize)? {
        switch f {
        case .procedural(let p):
            guard let (img, size) = ProceduralArt.render(p, config: config) else { return nil }
            return (texture(img), size)
        case .image(let name):
            guard let img = NSImage(named: name), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            // Asset-catalog / @2x images report their size in points.
            return (texture(cg), img.size)
        case .atlas(let atlasName, let name):
            let atlas = SKTextureAtlas(named: atlasName)
            guard atlas.textureNames.contains(where: { ($0 as NSString).deletingPathExtension == name || $0 == name }) else { return nil }
            let tex = atlas.textureNamed(name)
            tex.filteringMode = .linear
            return (tex, tex.size())
        }
    }

    private func texture(_ img: CGImage) -> SKTexture {
        let t = SKTexture(cgImage: img)
        t.filteringMode = .linear
        return t
    }

    private func warn(_ id: String, _ msg: String) {
        if warnedMissing.insert(id).inserted { print("Assets: \(id): \(msg)") }
    }

    /// Magenta checkerboard so a missing asset is obvious but never crashes.
    private func missing(_ id: String, reason: String) -> SpriteAsset {
        warn(id, reason)
        let size = CGSize(width: 24, height: 24)
        let img = renderImage(size: size) { ctx in
            for y in 0..<4 { for x in 0..<4 {
                ctx.setFillColor(rgb((x + y) % 2 == 0 ? 0xFF00FF : 0x220022))
                ctx.fill(CGRect(x: x * 6, y: y * 6, width: 6, height: 6))
            } }
        }
        let art = Art(texture: texture(img), size: size)
        return SpriteAsset(id: id, size: size, anchor: CGPoint(x: 0.5, y: 0.5), facing: .fixed,
                           animations: ["default": AnimationClip(frames: [art], fps: nil, distancePerFrame: nil, loops: true)],
                           metrics: [:], tint: nil, motion: .straight)
    }

    /// Whether the active pack defines a sprite (optional extras such as decoration sprites).
    func has(_ id: String) -> Bool { manifest.sprites[id] != nil }

    // MARK: Entity helpers (all go through asset ids)

    func enemy(_ def: EnemyDefinition) -> SpriteAsset { sprite(AssetID.enemy(def.visual)) }
    func summon(_ ability: SummonAbilityDefinition) -> SpriteAsset { sprite(AssetID.summon(ability.visual)) }
    func towerBase(_ def: TowerDefinition, level: Int) -> SpriteAsset { sprite(AssetID.towerBase(def.visualKey, level: level)) }
    func towerHead(_ def: TowerDefinition, level: Int) -> SpriteAsset { sprite(AssetID.towerHead(def.visualKey, level: level)) }
    /// Hot path (every shot): cached by visual key so no id string is built per call.
    func projectile(_ visual: String) -> SpriteAsset {
        if let s = projectileCache[visual] { return s }
        let s = sprite(AssetID.projectile(visual))
        projectileCache[visual] = s
        return s
    }
    private var projectileCache: [String: SpriteAsset] = [:]
    func mapBackground(_ map: MapDefinition) -> SpriteAsset { sprite(AssetID.mapBackground(map.id)) }
    func base(_ era: Era) -> SpriteAsset { sprite(AssetID.base(AssetValidator.eraKey(era))) }
    /// Build pad: the battlefield's own (`map.<id>.slot`) when the pack has one, else the shared pad.
    func slot(highlighted: Bool, map: MapDefinition? = nil) -> SpriteAsset {
        if let map, has(AssetID.slot(map: map.id, highlighted: highlighted)) {
            return sprite(AssetID.slot(map: map.id, highlighted: highlighted))
        }
        return sprite(highlighted ? AssetID.slotHighlighted : AssetID.slot)
    }
    func spawn(map: MapDefinition? = nil) -> SpriteAsset {
        if let map, has(AssetID.spawn(map: map.id)) { return sprite(AssetID.spawn(map: map.id)) }
        return sprite(AssetID.spawn)
    }
    func fx(_ name: String) -> SpriteAsset { sprite(AssetID.fx(name)) }
    func ui(_ name: String) -> SpriteAsset { sprite(AssetID.ui(name)) }

    // MARK: UI images (SwiftUI)

    /// Tower card icon: base + head composited (head at its mount point, aimed up-right).
    func towerIcon(_ def: TowerDefinition, level: Int) -> CGImage {
        let key = "icon.tower.\(def.visualKey).\(level)"
        if let img = imageCache[key] { return img }
        let base = towerBase(def, level: level), head = towerHead(def, level: level)
        let angle = layout("ui.iconHeadAngle", .pi / 4)
        let mount = head.metric("mountY", 0)
        var headArt = head.first
        var headAngle = angle
        if head.facing == .directional {
            let idle = head.clip("idle")
            headArt = idle.art(direction: idle.direction(for: angle), frame: 0)
            headAngle = 0
        }
        // Union of both sprites' rects around the ground point (0,0).
        let bRect = Self.rect(base.size, base.anchor, offsetY: 0)
        let hRect = Self.rect(head.size, head.anchor, offsetY: mount)
        let u = bRect.union(hRect)
        let side = max(u.width, u.height)
        let img = renderImage(size: CGSize(width: side, height: side), scale: 2) { ctx in
            ctx.translateBy(x: -u.minX + (side - u.width) / 2, y: -u.minY + (side - u.height) / 2)
            Self.draw(base.first, in: ctx, center: CGPoint(x: bRect.midX, y: bRect.midY), angle: 0)
            Self.draw(headArt, in: ctx, center: CGPoint(x: hRect.midX, y: hRect.midY), angle: headAngle)
        }.trimmedToSquare()
        imageCache[key] = img
        return img
    }

    private static func rect(_ size: CGSize, _ anchor: CGPoint, offsetY: CGFloat) -> CGRect {
        CGRect(x: -anchor.x * size.width, y: offsetY - anchor.y * size.height, width: size.width, height: size.height)
    }

    /// Enemy portrait: walk frame facing right.
    func enemyIcon(_ def: EnemyDefinition) -> CGImage {
        let key = "icon.enemy.\(def.visual)"
        if let img = imageCache[key] { return img }
        let s = enemy(def)
        let clip = s.clip("walk", "idle")
        let a = clip.art(direction: s.facing == .directional ? clip.direction(for: 0) : 0, frame: 0)
        let img = renderImage(size: s.size, scale: 2) { Self.draw(a, in: $0, center: CGPoint(x: s.size.width / 2, y: s.size.height / 2), angle: 0) }
            .trimmedToSquare()
        imageCache[key] = img
        return img
    }

    /// Ability-button portrait: the summoned unit facing the camera.
    func summonIcon(_ ability: SummonAbilityDefinition) -> CGImage {
        let key = "icon.summon.\(ability.visual)"
        if let img = imageCache[key] { return img }
        let s = summon(ability)
        let clip = s.clip("idle", "walk")
        // Directional art: the view facing down the screen (towards the player).
        let a = clip.art(direction: s.facing == .directional ? clip.direction(for: -.pi / 2) : 0, frame: 0)
        let img = renderImage(size: s.size, scale: 2) { Self.draw(a, in: $0, center: CGPoint(x: s.size.width / 2, y: s.size.height / 2), angle: 0) }
            .trimmedToSquare()
        imageCache[key] = img
        return img
    }

    /// Battlefield preview for the menu (backdrop and selection cards): the
    /// background with its standing decorations, spawn and base composited in,
    /// at 80 % of world size. The full-size background texture isn't kept.
    func backgroundImage(for map: MapDefinition) -> CGImage {
        let key = "menu.\(map.id)"
        if let img = imageCache[key] { return img }
        let k: CGFloat = 0.8
        let size = CGSize(width: map.worldSize.width * k, height: map.worldSize.height * k)
        let view = self.view
        let bgID = AssetID.mapBackground(map.id)
        let wasLoaded = sprites[bgID] != nil
        let bg = mapBackground(map).first
        let img = renderImage(size: size, scale: 1) { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(bg.texture.cgImage(), in: CGRect(origin: .zero, size: size))
            func draw(_ art: Art, anchor: CGPoint, at world: CGPoint, scale: CGFloat = 1) {
                let p = view.ground(world)
                let w = art.size.width * scale * k, h = art.size.height * scale * k
                ctx.draw(art.texture.cgImage(), in: CGRect(x: p.x * k - anchor.x * w, y: p.y * k - anchor.y * h, width: w, height: h))
            }
            var items: [(y: CGFloat, draw: () -> Void)] = []
            for s in map.buildSlots {
                let a = slot(highlighted: false, map: map)
                draw(a.first, anchor: a.anchor, at: map.slotPosition(s))
            }
            for (i, d) in map.resolvedDecorations().enumerated() {
                let id = AssetID.decoration(d.kind.rawValue)
                guard has(id) else { continue }
                let s = sprite(id)
                let variants = s.clip("variants")
                let p = map.world(x: d.x, y: d.y)
                let a = variants.frames[i % variants.frames.count]
                items.append((p.y, { draw(a, anchor: s.anchor, at: p, scale: CGFloat(d.scale) * s.metric("scale", 1)) }))
            }
            let sp = spawn(map: map), b = base(.primitive)
            items.append((map.world(map.spawn).y, { draw(sp.first, anchor: sp.anchor, at: map.world(map.spawn)) }))
            items.append((map.world(map.base).y, { draw(b.first, anchor: b.anchor, at: map.world(map.base)) }))
            for item in items.sorted(by: { $0.y > $1.y }) { item.draw() }      // far to near
        }
        if !wasLoaded { sprites[bgID] = nil }        // 20 MB texture: only the match in play keeps one
        imageCache[key] = img
        return img
    }

    /// Battlefield backgrounds currently held as textures (diagnostics: should be 1 in a match).
    var loadedBattlefieldBackgrounds: [String] {
        sprites.keys.filter { $0.hasPrefix("map.") && $0.hasSuffix(".background") }.sorted()
    }

    /// Drops art that only another battlefield uses (its background, pads, spawn
    /// and decoration sprites), so switching maps doesn't accumulate textures.
    func releaseBattlefieldArt(keeping map: MapDefinition) {
        let kinds = Set(map.resolvedDecorations().map { AssetID.decoration($0.kind.rawValue) })
        let shared: Set<String> = [AssetID.slot, AssetID.slotHighlighted, AssetID.spawn]
        for id in sprites.keys {
            if id.hasPrefix("map."), !id.hasPrefix("map.\(map.id)."), !shared.contains(id) { sprites[id] = nil }
            if id.hasPrefix("deco."), !kinds.contains(id) { sprites[id] = nil }
        }
    }

    private static func draw(_ art: Art, in ctx: CGContext, center: CGPoint, angle: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        ctx.draw(art.texture.cgImage(), in: CGRect(x: -art.size.width / 2, y: -art.size.height / 2,
                                                   width: art.size.width, height: art.size.height))
        ctx.restoreGState()
    }

    /// Pre-loads the sprites the match can show soon so nothing is decoded mid-game.
    /// Enemies are loaded per era: `era` and the one after it. Each era's
    /// enemies live in their own atlas, so this keeps texture memory to two
    /// atlases instead of four. Anything else is still resolved on first use.
    func warmUp(config: GameConfiguration, era: Era? = nil) {
        if self.config == nil { prepare(config: config) }
        releaseBattlefieldArt(keeping: config.map)
        let skip = Set(config.enemies.values.filter { e in
            guard let era else { return false }
            return e.era < era || e.era.rawValue > era.rawValue + 1
        }.map { AssetID.enemy($0.visual) })
        for id in AssetValidator.requiredIDs(for: config) where !skip.contains(id) { _ = sprite(id) }
    }

    /// Era changed: drops enemy sprites of earlier eras (their atlas pages are
    /// freed once no node uses them) and pre-loads the next era's.
    func advance(to era: Era, config: GameConfiguration) {
        for e in config.enemies.values where e.era < era {
            sprites[AssetID.enemy(e.visual)] = nil
        }
        warmUp(config: config, era: era)
    }
}

extension SKSpriteNode {
    convenience init(art: Art) {
        self.init(texture: art.texture, color: .white, size: art.size)
    }

    /// Sets texture and size. The size is applied as the unscaled size: pooled
    /// nodes arrive at whatever scale their last use left them at, and
    /// SpriteKit's `size` is relative to the current scale.
    func apply(_ art: Art) {
        if texture !== art.texture { texture = art.texture }
        setUnscaledSize(art.size)
    }

    /// Applies a sprite's first frame, size and anchor.
    func apply(_ sprite: SpriteAsset) {
        apply(sprite.first)
        anchorPoint = sprite.anchor
    }
}

extension CGImage {
    /// Crops to the opaque content, centred in a square with a small margin.
    /// Pre-rendered sprites keep the padding needed by all their directions;
    /// icons should show just the subject.
    func trimmedToSquare(margin: Int = 4) -> CGImage {
        let w = width, h = height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return self }
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 110 {   // solid pixels only: ignores baked soft shadows
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return self }
        let side = max(maxX - minX, maxY - minY) + 1 + margin * 2
        let out = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Bitmap rows run top-down in memory, CG coordinates bottom-up.
        let cx = CGFloat(minX + maxX + 1) / 2, cy = CGFloat(h) - CGFloat(minY + maxY + 1) / 2
        out.draw(self, in: CGRect(x: CGFloat(side) / 2 - cx, y: CGFloat(side) / 2 - cy, width: CGFloat(w), height: CGFloat(h)))
        return out.makeImage() ?? self
    }
}
