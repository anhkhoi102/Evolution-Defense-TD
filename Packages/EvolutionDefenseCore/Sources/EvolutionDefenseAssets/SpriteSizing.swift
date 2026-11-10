import SpriteKit

extension SKSpriteNode {
    /// Sets the sprite's size as it should appear at scale 1, whatever its
    /// current `xScale` / `yScale`.
    ///
    /// SpriteKit's `size` is the *scaled* size: assigning it while a node is
    /// scaled stores `size ÷ scale`, so when the scale is later reset the
    /// sprite comes out too large or too small. Pooled nodes are reused at
    /// whatever scale their previous effect ended at (a spark shrinks to 0.2,
    /// an explosion grows to 4×), so every size assignment on a reused node
    /// must go through this.
    public func setUnscaledSize(_ s: CGSize) {
        let sx = xScale, sy = yScale
        guard sx != 1 || sy != 1 else { size = s; return }
        xScale = 1; yScale = 1
        size = s
        xScale = sx; yScale = sy
    }

    /// The sprite's size at scale 1.
    public var unscaledSize: CGSize {
        CGSize(width: xScale == 0 ? 0 : abs(size.width / xScale), height: yScale == 0 ? 0 : abs(size.height / yScale))
    }
}
