import EvolutionDefenseCore
import Foundation

/// Checks that a manifest covers every visual the game data refers to, and
/// that each entry is well formed. Run by the tests and logged by the app at
/// launch, so a replacement pack with a missing sprite is caught immediately.
public enum AssetValidator {
    public struct Issue: Sendable, Equatable, CustomStringConvertible {
        public var id: String
        public var message: String
        public var description: String { "\(id): \(message)" }
    }

    public static func eraKey(_ e: Era) -> String { String(describing: e) }

    /// Every asset id the current game configuration needs.
    public static func requiredIDs(for config: GameConfiguration) -> [String] {
        var ids: [String] = []
        for e in config.enemies.values.sorted(by: { $0.id < $1.id }) { ids.append(AssetID.enemy(e.visual)) }
        for s in config.summons.abilities { ids.append(AssetID.summon(s.visual)) }
        for a in TowerArchetype.allCases {
            let t = config.tower(a)
            for l in t.levels {
                ids.append(AssetID.towerBase(t.visualKey, level: l.level))
                ids.append(AssetID.towerHead(t.visualKey, level: l.level))
                ids.append(AssetID.projectile(l.projectileAsset))
            }
        }
        ids.append(AssetID.mapBackground(config.map.id))
        ids += [AssetID.slot, AssetID.slotHighlighted, AssetID.spawn]
        for e in Era.allCases { ids.append(AssetID.base(eraKey(e))) }
        ids += AssetID.effects.map(AssetID.fx) + AssetID.uiSprites.map(AssetID.ui)
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    public static func validate(_ m: AssetManifest, config: GameConfiguration) -> [Issue] {
        var issues: [Issue] = []
        if m.version != AssetManifest.currentVersion {
            issues.append(Issue(id: "manifest", message: "version \(m.version), expected \(AssetManifest.currentVersion)"))
        }
        // The battlefield in play plus every other battlefield's background.
        let ids = requiredIDs(for: config) + config.maps.map { AssetID.mapBackground($0.id) }
        for id in Set(ids).sorted() where m.sprites[id] == nil {
            issues.append(Issue(id: id, message: "missing sprite"))
        }
        for (id, s) in m.sprites { issues += check(s, id: id) }
        if let ts = m.textureScale, ts <= 0 { issues.append(Issue(id: "manifest", message: "textureScale must be > 0")) }
        return issues.sorted { $0.id < $1.id }
    }

    public static func check(_ s: SpriteSpec, id: String) -> [Issue] {
        var issues: [Issue] = []
        func bad(_ m: String) { issues.append(Issue(id: id, message: m)) }
        if s.animations.isEmpty { bad("no animations") }
        for (name, a) in s.animations {
            if a.frames.isEmpty { bad("animation '\(name)' has no frames") }
            if let f = a.fps, f <= 0 { bad("animation '\(name)' fps must be > 0") }
            if let d = a.distancePerFrame, d <= 0 { bad("animation '\(name)' distancePerFrame must be > 0") }
            if let n = a.directions, n < 1 || a.frames.count % n != 0 {
                bad("animation '\(name)' has \(a.frames.count) frames, not a multiple of \(n) directions")
            }
            for f in a.frames {
                switch f {
                case .procedural(let p) where !ProceduralSource.generators.contains(p.procedural):
                    bad("unknown procedural generator '\(p.procedural)'")
                case .image(let n) where n.isEmpty, .atlas(_, let n) where n.isEmpty:
                    bad("empty image name in '\(name)'")
                default: break
                }
            }
        }
        if let z = s.size, z.width <= 0 || z.height <= 0 { bad("size must be positive") }
        if let a = s.anchor, !(0...1).contains(a.x) || !(0...1).contains(a.y) { bad("anchor must be within 0…1") }
        if let t = s.tint, parseHex(t) == nil { bad("tint '\(t)' is not #RRGGBB") }
        return issues
    }

    /// "#RRGGBB" → 0xRRGGBB.
    public static func parseHex(_ s: String) -> UInt32? {
        var t = s
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return v
    }

    /// Image and atlas names a manifest references (for checking that files ship).
    public static func referencedImages(_ m: AssetManifest) -> (images: Set<String>, atlasFrames: Set<String>) {
        var images = Set<String>(), atlas = Set<String>()
        for s in m.sprites.values {
            for a in s.animations.values {
                for f in a.frames {
                    switch f {
                    case .image(let n): images.insert(n)
                    case .atlas(let at, let n): atlas.insert("\(at)/\(n)")
                    case .procedural: break
                    }
                }
            }
        }
        return (images, atlas)
    }
}
