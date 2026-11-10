import CoreGraphics
import Foundation

/// A point in map tile units. World position = tile coordinate × tileSize.
public struct GridPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum PlacementHint: String, Codable, Sendable {
    case corner, straight, narrow, choke, entrance, lastLine
}

public struct BuildSlotDefinition: Codable, Sendable, Identifiable {
    public var id: Int
    public var x: Double
    public var y: Double
    /// Designer note on what this spot is good for (shown in UI later).
    public var hint: PlacementHint
}

public enum DecorationKind: String, Codable, Sendable, CaseIterable {
    case tree, pine, rock, boulder, bush, flowers
    // Added after the first six: the seeded scatter visits kinds in this order,
    // so appending keeps existing battlefields identical.
    case cactus, palm, ruin

    /// Tall objects that are drawn as depth-sorted sprites and kept apart from each other.
    var isTall: Bool { self == .tree || self == .pine || self == .boulder || self == .cactus || self == .palm || self == .ruin }
}

/// Colours and look of a battlefield (hex "#RRGGBB"). Used by the art bake,
/// the code-drawn fallback art and the menu.
public struct BattlefieldTheme: Codable, Sendable, Equatable {
    /// Which environment builder the art pipeline uses: "grassland", "desert" or "lakeside".
    public var environment: String
    public var ground: String
    public var groundAlt: String
    public var road: String
    public var roadEdge: String
    public var water: String?
    /// Accent colour for menu cards.
    public var accent: String
}

/// A body of water (visual only): a closed outline in tile units. Nothing can
/// be built or deployed in it, and decorations are kept out of it.
public struct WaterArea: Codable, Sendable, Equatable {
    public var points: [GridPoint]
}

/// A bridge carrying the road over water (visual; lets the path cross a water area).
public struct BridgeDefinition: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    /// Direction of travel in degrees (0 = along +x).
    public var rotation: Double
    public var length: Double
}

public struct DecorationDefinition: Codable, Sendable {
    public var kind: DecorationKind
    public var x: Double
    public var y: Double
    public var scale: Double
    public init(kind: DecorationKind, x: Double, y: Double, scale: Double) {
        self.kind = kind; self.x = x; self.y = y; self.scale = scale
    }
}

/// Procedural scattering of decorations, seeded so the map is identical every run.
public struct ScatterDefinition: Codable, Sendable {
    public var seed: UInt64
    public var counts: [String: Int]
    /// Minimum distance (tiles) from the path centre line.
    public var pathClearance: Double
    /// Minimum distance (tiles) from build slots, base and spawn.
    public var objectClearance: Double
}

public struct MapDefinition: Codable, Sendable {
    public var id: String
    public var name: String
    public var tileSize: Double
    public var columns: Int
    public var rows: Int
    /// Path width in tiles (visual + placement clearance).
    public var pathWidth: Double
    public var path: [GridPoint]
    public var spawn: GridPoint
    public var base: GridPoint
    public var buildSlots: [BuildSlotDefinition]
    public var decorations: [DecorationDefinition]
    public var scatter: ScatterDefinition
    /// One-line description for the battlefield selection screen.
    public var summary: String?
    public var theme: BattlefieldTheme?
    public var water: [WaterArea]?
    public var bridges: [BridgeDefinition]?
    /// Ambient visual effects, e.g. "dust", "waterSparkle" (see MapRenderer).
    public var ambient: [String]?

    /// Whether `p` (tile units) is in water, or within `margin` tiles of its shore.
    public func isInWater(_ p: GridPoint, margin: Double = 0) -> Bool {
        for area in water ?? [] where area.points.count >= 3 {
            let pts = area.points
            var inside = false
            var j = pts.count - 1
            var nearest = Double.greatestFiniteMagnitude
            for i in 0..<pts.count {
                let a = pts[i], b = pts[j]
                if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                let dx = b.x - a.x, dy = b.y - a.y
                let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / max(dx * dx + dy * dy, 1e-9)))
                let qx = a.x + dx * t - p.x, qy = a.y + dy * t - p.y
                nearest = min(nearest, (qx * qx + qy * qy).squareRoot())
                j = i
            }
            if inside || nearest < margin { return true }
        }
        return false
    }

    /// Whether `p` (tile units) is on a bridge deck (where the road may cross water).
    public func isOnBridge(_ p: GridPoint, margin: Double = 0.6) -> Bool {
        (bridges ?? []).contains { b in
            let a = b.rotation * .pi / 180
            let dx = p.x - b.x, dy = p.y - b.y
            let along = dx * cos(a) + dy * sin(a), across = -dx * sin(a) + dy * cos(a)
            return abs(along) <= b.length / 2 + margin && abs(across) <= pathWidth / 2 + margin
        }
    }

    public var worldSize: CGSize { CGSize(width: Double(columns) * tileSize, height: Double(rows) * tileSize) }

    public func world(_ p: GridPoint) -> CGPoint { CGPoint(x: p.x * tileSize, y: p.y * tileSize) }
    public func world(x: Double, y: Double) -> CGPoint { CGPoint(x: x * tileSize, y: y * tileSize) }

    public func makePath() -> PathGeometry { PathGeometry(points: path.map(world)) }

    public func slotPosition(_ slot: BuildSlotDefinition) -> CGPoint { world(x: slot.x, y: slot.y) }

    /// Hand-placed decorations plus the seeded scatter, kept clear of the path,
    /// build slots, base and spawn. Deterministic for a given seed.
    public func resolvedDecorations() -> [DecorationDefinition] {
        var result = decorations
        let pathGeo = makePath()
        var rng = SeededRandom(seed: scatter.seed)
        let pathClear = scatter.pathClearance * tileSize
        let objClear = scatter.objectClearance * tileSize
        let keepOut: [CGPoint] = buildSlots.map(slotPosition) + [world(base), world(spawn)]

        // Stable order so results don't depend on dictionary iteration.
        for kind in DecorationKind.allCases {
            let count = scatter.counts[kind.rawValue] ?? 0
            var placed = 0
            var attempts = 0
            while placed < count && attempts < count * 40 {
                attempts += 1
                let x = Double.random(in: 0.3...(Double(columns) - 0.3), using: &rng)
                let y = Double.random(in: 0.3...(Double(rows) - 0.3), using: &rng)
                let p = world(x: x, y: y)
                if pathGeo.distanceToPath(from: p) < pathClear { continue }
                if keepOut.contains(where: { $0.distance(to: p) < objClear }) { continue }
                if water != nil, isInWater(GridPoint(x: x, y: y), margin: 0.45) { continue }
                // Avoid stacking large decorations on top of each other.
                if kind.isTall,
                   result.contains(where: { $0.kind.isTall
                       && world(x: $0.x, y: $0.y).distance(to: p) < tileSize * 0.9 }) { continue }
                let scale = Double.random(in: 0.8...1.25, using: &rng)
                result.append(DecorationDefinition(kind: kind, x: x, y: y, scale: scale))
                placed += 1
            }
        }
        return result
    }
}
