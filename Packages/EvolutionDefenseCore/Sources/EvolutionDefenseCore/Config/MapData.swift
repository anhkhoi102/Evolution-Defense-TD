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
                // Avoid stacking large decorations on top of each other.
                if kind == .tree || kind == .pine || kind == .boulder,
                   result.contains(where: { ($0.kind == .tree || $0.kind == .pine || $0.kind == .boulder)
                       && world(x: $0.x, y: $0.y).distance(to: p) < tileSize * 0.9 }) { continue }
                let scale = Double.random(in: 0.8...1.25, using: &rng)
                result.append(DecorationDefinition(kind: kind, x: x, y: y, scale: scale))
                placed += 1
            }
        }
        return result
    }
}
