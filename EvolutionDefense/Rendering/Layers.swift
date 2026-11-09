import CoreGraphics

/// Draw order. The SKView uses `ignoresSiblingOrder = true` for batching,
/// so every node's depth is decided by these z values.
enum Layer {
    static let terrain: CGFloat = 0
    static let slots: CGFloat = 5
    static let spawnAndBase: CGFloat = 8
    static let groundFX: CGFloat = 10
    static let shadows: CGFloat = 12
    /// Towers, enemies and tall decorations share one band and are ordered by
    /// ground depth inside it (0…10), flyers +10, so 2.5D art overlaps correctly.
    static let units: CGFloat = 20
    static let enemies: CGFloat = units
    static let towers: CGFloat = units
    static let flyingOffset: CGFloat = 10
    static let projectiles: CGFloat = 40
    static let healthBars: CGFloat = 45
    static let airFX: CGFloat = 50
    static let overlay: CGFloat = 60
    static let floatingText: CGFloat = 70
}
