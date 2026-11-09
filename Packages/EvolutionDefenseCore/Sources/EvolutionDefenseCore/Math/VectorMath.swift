import CoreGraphics

// Small CGPoint vector helpers. CGPoint is used throughout because SpriteKit
// uses it natively, so the renderer never has to convert coordinates.

public extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func += (a: inout CGPoint, b: CGPoint) { a = a + b }

    var length: CGFloat { (x * x + y * y).squareRoot() }
    var lengthSquared: CGFloat { x * x + y * y }

    func distance(to p: CGPoint) -> CGFloat { (self - p).length }
    func distanceSquared(to p: CGPoint) -> CGFloat { (self - p).lengthSquared }

    var normalized: CGPoint {
        let l = length
        return l > 0 ? CGPoint(x: x / l, y: y / l) : .zero
    }

    /// Angle in radians, measured counter-clockwise from +x (SpriteKit's zRotation convention).
    var angle: CGFloat { atan2(y, x) }

    /// Perpendicular vector rotated 90° counter-clockwise.
    var perpendicular: CGPoint { CGPoint(x: -y, y: x) }
}

/// Distance from point `p` to the segment `a`–`b`.
public func distanceFromPoint(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let ab = b - a
    let lenSq = ab.lengthSquared
    guard lenSq > 0 else { return p.distance(to: a) }
    let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lenSq))
    return p.distance(to: a + ab * t)
}

/// Deterministic, allocation-free pseudo random generator (SplitMix64).
/// Used so simulations and map decoration are reproducible (and testable).
public struct SeededRandom: RandomNumberGenerator, Sendable, Codable, Equatable {
    /// Exposed so the generator can be saved and restored with a checkpoint.
    public private(set) var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
