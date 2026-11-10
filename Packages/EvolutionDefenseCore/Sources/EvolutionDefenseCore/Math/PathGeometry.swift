import CoreGraphics

/// A polyline enemies walk along. Positions are addressed by distance travelled
/// from the start, which also makes "First"/"Last" targeting trivial.
public struct PathGeometry: Sendable {
    public let points: [CGPoint]
    /// cumulative[i] = path length from points[0] to points[i].
    public let cumulative: [CGFloat]
    public let totalLength: CGFloat

    public init(points: [CGPoint]) {
        precondition(points.count >= 2, "A path needs at least two points")
        self.points = points
        var acc: [CGFloat] = [0]
        acc.reserveCapacity(points.count)
        for i in 1..<points.count {
            acc.append(acc[i - 1] + points[i].distance(to: points[i - 1]))
        }
        cumulative = acc
        totalLength = acc[acc.count - 1]
    }

    public var segmentCount: Int { points.count - 1 }

    /// Position and unit direction at `distance` along the path.
    /// `segmentHint` caches the last segment so walking forward is O(1).
    public func sample(at distance: CGFloat, segmentHint: inout Int) -> (position: CGPoint, direction: CGPoint) {
        let d = max(0, min(distance, totalLength))
        var i = max(0, min(segmentHint, segmentCount - 1))
        while i < segmentCount - 1 && cumulative[i + 1] < d { i += 1 }
        while i > 0 && cumulative[i] > d { i -= 1 }
        segmentHint = i
        let a = points[i], b = points[i + 1]
        let segLen = cumulative[i + 1] - cumulative[i]
        let dir = (b - a).normalized
        guard segLen > 0 else { return (a, dir) }
        let t = (d - cumulative[i]) / segLen
        return (a + (b - a) * t, dir)
    }

    public func position(at distance: CGFloat) -> CGPoint {
        var hint = 0
        return sample(at: distance, segmentHint: &hint).position
    }

    /// Shortest distance from `p` to any segment of the path.
    public func distanceToPath(from p: CGPoint) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<segmentCount {
            best = min(best, distanceFromPoint(p, toSegment: points[i], points[i + 1]))
        }
        return best
    }

    /// The nearest point on the path to `p`, its distance along the path, and how far `p` is from it.
    public func closestPoint(to p: CGPoint) -> (point: CGPoint, alongPath: CGFloat, offset: CGFloat) {
        var best = (point: points[0], alongPath: CGFloat(0), offset: CGFloat.greatestFiniteMagnitude)
        for i in 0..<segmentCount {
            let a = points[i], b = points[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0
            let q = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
            let d = ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot()
            if d < best.offset { best = (q, cumulative[i] + t * len2.squareRoot(), d) }
        }
        return best
    }

    /// Number of direction changes sharper than `minAngleDegrees`.
    public func turnCount(minAngleDegrees: CGFloat = 30) -> Int {
        guard points.count >= 3 else { return 0 }
        var count = 0
        for i in 1..<(points.count - 1) {
            let d1 = (points[i] - points[i - 1]).normalized
            let d2 = (points[i + 1] - points[i]).normalized
            let dot = max(-1, min(1, d1.x * d2.x + d1.y * d2.y))
            if acos(dot) * 180 / .pi >= minAngleDegrees { count += 1 }
        }
        return count
    }
}
