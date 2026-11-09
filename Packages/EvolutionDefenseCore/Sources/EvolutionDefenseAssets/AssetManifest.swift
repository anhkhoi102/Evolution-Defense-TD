// The asset manifest: the ONLY place that connects game entities to their
// visuals. Gameplay data (towers.json, enemies.json…) carries short visual keys;
// this manifest says which image, atlas frame or procedural placeholder to use
// for each key, at what size, anchor and animation speed.
//
// Replacing the art = shipping new images + a new (or override) manifest.
// See Docs/ASSETS.md for conventions.

import Foundation

public struct AssetManifest: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    /// Human-readable pack name ("Procedural placeholders", "Studio pack v2"…).
    public var name: String
    /// Pixels per point for image sources without an explicit size (2 = @2x art).
    public var textureScale: Double?
    /// Every sprite, keyed by asset id (see `AssetID`).
    public var sprites: [String: SpriteSpec]
    /// Global visual tuning that isn't tied to one sprite (pip spacing, arc height…).
    public var layout: [String: Double]?

    public init(version: Int = currentVersion, name: String, textureScale: Double? = 2,
                sprites: [String: SpriteSpec], layout: [String: Double]? = nil) {
        self.version = version; self.name = name; self.textureScale = textureScale
        self.sprites = sprites; self.layout = layout
    }

    /// `other` replaces whole sprites and individual layout values. Used to
    /// layer a partial replacement pack on top of the full placeholder pack.
    public func merged(with other: AssetManifest) -> AssetManifest {
        var r = self
        r.name = other.name
        if let s = other.textureScale { r.textureScale = s }
        for (k, v) in other.sprites { r.sprites[k] = v }
        if let l = other.layout { r.layout = (r.layout ?? [:]).merging(l) { $1 } }
        return r
    }

    public func layoutValue(_ key: String, default d: Double) -> Double { layout?[key] ?? d }

    public static func decode(_ data: Data) throws -> AssetManifest {
        try JSONDecoder().decode(AssetManifest.self, from: data)
    }
}

/// How a sprite is drawn.
public struct SpriteSpec: Codable, Sendable, Equatable {
    /// On-screen size in points. nil = native size of the first frame
    /// (image pixels ÷ textureScale, or the procedural generator's size).
    public var size: SpriteSize?
    /// 0…1 anchor inside the sprite; default centre (0.5, 0.5).
    public var anchor: SpritePoint?
    /// How the sprite follows the entity's direction.
    public var facing: Facing?
    /// Animation sets by name (`default`, `walk`, `idle`, `fire`, `death`, `flight`…).
    /// Every sprite needs at least one.
    public var animations: [String: AnimationSpec]
    /// Named visual measurements in points (health-bar offset, muzzle distance…).
    public var metrics: [String: Double]?
    /// Optional colour (hex "#RRGGBB"), e.g. the muzzle-flash tint of a projectile.
    public var tint: String?
    /// Projectiles: "arc" (lobbed, with shadow) or "straight".
    public var motion: Motion?

    public init(size: SpriteSize? = nil, anchor: SpritePoint? = nil, facing: Facing? = nil,
                animations: [String: AnimationSpec], metrics: [String: Double]? = nil,
                tint: String? = nil, motion: Motion? = nil) {
        self.size = size; self.anchor = anchor; self.facing = facing; self.animations = animations
        self.metrics = metrics; self.tint = tint; self.motion = motion
    }

    public enum Facing: String, Codable, Sendable {
        /// Art faces +x (right) and rotates with the movement / aim direction.
        case rotate
        /// Never rotates (top-down props, side-view art that shouldn't turn).
        case fixed
        /// Side-view art facing right; mirrored when moving left.
        case flip
        /// Pre-rendered views: the animation holds `directions` sets of frames
        /// (direction-major, starting at +x/east, counter-clockwise); the
        /// renderer picks the set closest to the entity's heading. For 2.5D art.
        case directional
    }

    public enum Motion: String, Codable, Sendable { case arc, straight }

    public func metric(_ key: String) -> Double? { metrics?[key] }

    /// Preferred animation from a list of names, falling back to `default`, then any.
    public func animation(_ names: String...) -> AnimationSpec? {
        for n in names { if let a = animations[n] { return a } }
        return animations["default"] ?? animations.values.first
    }
}

public struct SpriteSize: Codable, Sendable, Equatable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct SpritePoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct AnimationSpec: Codable, Sendable, Equatable {
    public var frames: [FrameSource]
    /// Time-based playback (frames per second).
    public var fps: Double?
    /// Movement-based playback: world units travelled per frame (walk cycles).
    public var distancePerFrame: Double?
    /// Loops by default; one-shot animations (fire, death) set false.
    public var loop: Bool?
    /// Number of view directions in `frames` (facing `directional`); nil = 1.
    public var directions: Int?

    public init(frames: [FrameSource], fps: Double? = nil, distancePerFrame: Double? = nil, loop: Bool? = nil,
                directions: Int? = nil) {
        self.frames = frames; self.fps = fps; self.distancePerFrame = distancePerFrame; self.loop = loop
        self.directions = directions
    }

    public var loops: Bool { loop ?? true }
}

/// Where one frame's pixels come from.
public enum FrameSource: Codable, Sendable, Equatable {
    /// An image by name: asset-catalog image set or a PNG in the app bundle
    /// (`name` without extension; `@2x` variants are picked automatically).
    case image(String)
    /// A frame inside a sprite atlas (`.spriteatlas` in the asset catalog).
    case atlas(atlas: String, name: String)
    /// A placeholder drawn in code by a named generator.
    case procedural(ProceduralSource)

    private enum CodingKeys: String, CodingKey { case image, atlas, name, procedural }

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            self = .image(s)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let img = try c.decodeIfPresent(String.self, forKey: .image) {
            self = .image(img)
        } else if let atlas = try c.decodeIfPresent(String.self, forKey: .atlas) {
            self = .atlas(atlas: atlas, name: try c.decode(String.self, forKey: .name))
        } else if c.contains(.procedural) {
            self = .procedural(try ProceduralSource(from: decoder))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "frame needs \"image\", \"atlas\"+\"name\" or \"procedural\""))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .image(let n):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(n, forKey: .image)
        case .atlas(let a, let n):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(a, forKey: .atlas)
            try c.encode(n, forKey: .name)
        case .procedural(let p):
            try p.encode(to: encoder)
        }
    }
}

/// Parameters for a code-drawn placeholder. `procedural` names the generator.
public struct ProceduralSource: Codable, Sendable, Equatable {
    public var procedural: String
    public var key: String?
    public var level: Int?
    /// Art scale parameter for creature generators (NOT the gameplay hit radius).
    public var radius: Double?
    public var frame: Int?

    public init(_ generator: String, key: String? = nil, level: Int? = nil, radius: Double? = nil, frame: Int? = nil) {
        procedural = generator; self.key = key; self.level = level; self.radius = radius; self.frame = frame
    }

    /// Generators the app's placeholder renderer implements.
    public static let generators: Set<String> = [
        "creature", "towerBase", "towerHead", "projectile", "mapBackground", "slot", "spawn", "base", "fx", "ui"
    ]
}

/// Asset id conventions. Gameplay never builds these strings itself; renderers
/// ask `AssetID` so the naming scheme lives in one place.
public enum AssetID {
    public static func enemy(_ visual: String) -> String { "enemy.\(visual)" }
    public static func towerBase(_ visual: String, level: Int) -> String { "tower.\(visual).\(level).base" }
    public static func towerHead(_ visual: String, level: Int) -> String { "tower.\(visual).\(level).head" }
    public static func projectile(_ visual: String) -> String { "projectile.\(visual)" }
    public static func mapBackground(_ mapID: String) -> String { "map.\(mapID).background" }
    public static func base(_ eraName: String) -> String { "base.\(eraName)" }
    public static let slot = "map.slot"
    public static let slotHighlighted = "map.slot.highlighted"
    public static let spawn = "map.spawn"
    public static func fx(_ name: String) -> String { "fx.\(name)" }
    public static func ui(_ name: String) -> String { "ui.\(name)" }

    /// Effects and UI sprites the renderers use.
    public static let effects = ["explosion", "puff", "spark", "ring", "shadow", "shield", "disabled", "missile"]
    public static let uiSprites = ["levelPip.on", "levelPip.off"]
}
