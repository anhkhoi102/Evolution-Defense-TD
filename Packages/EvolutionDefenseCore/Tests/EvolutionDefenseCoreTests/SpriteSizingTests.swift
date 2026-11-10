import SpriteKit
import Testing
@testable import EvolutionDefenseAssets

/// Regression tests for oversized death animations: pooled effect sprites are
/// reused at the scale their previous effect ended at, and SpriteKit's `size`
/// is relative to the current scale.
@Suite("Sprite sizing (pooled nodes)")
@MainActor
struct SpriteSizingTests {
    private var texture: SKTexture { SKTexture(image: NSImage(size: NSSize(width: 64, height: 64))) }
    private let art = CGSize(width: 88, height: 70)   // e.g. the Armored Beast death frame

    @Test("Plain size assignment on a scaled node is wrong (documents the SpriteKit behaviour)")
    func plainAssignmentIsScaleRelative() {
        let n = SKSpriteNode(texture: texture)
        n.setScale(0.2)                  // a level-up spark ends at 0.2
        n.size = art
        n.setScale(1)
        #expect(n.size.width > art.width * 4)    // 5× too big: the reported bug
    }

    @Test("setUnscaledSize gives the right size after any previous scale", arguments: [0.2, 0.55, 1.0, 1.1, 2.3, 4.615])
    func unscaledSizeAfterReuse(previousScale: Double) {
        let n = SKSpriteNode(texture: texture)
        n.setScale(previousScale)
        n.setUnscaledSize(art)
        #expect(abs(n.xScale - previousScale) < 1e-5 && abs(n.yScale - previousScale) < 1e-5)   // scale is preserved
        n.setScale(1)
        #expect(abs(n.size.width - art.width) < 0.001)
        #expect(abs(n.size.height - art.height) < 0.001)
    }

    @Test("Flipped and squashed nodes keep their size too")
    func nonUniformAndFlipped() {
        let n = SKSpriteNode(texture: texture)
        n.xScale = -1; n.yScale = 0.8192          // flipped sprite / flat ground effect
        n.setUnscaledSize(art)
        #expect(abs(n.unscaledSize.width - art.width) < 0.001)
        #expect(abs(n.unscaledSize.height - art.height) < 0.001)
        n.xScale = 1; n.yScale = 1
        #expect(abs(n.size.width - art.width) < 0.001)
    }

    @Test("A pool reused many times never drifts")
    func repeatedReuse() {
        let n = SKSpriteNode(texture: texture)
        for i in 0..<200 {
            let s = [0.2, 4.6, 0.55, 1.25, 3.1][i % 5]
            n.setScale(s)                          // previous effect's final scale
            n.setUnscaledSize(i % 2 == 0 ? art : CGSize(width: 64, height: 64))
            n.setScale(1)
            #expect(abs(n.size.width - (i % 2 == 0 ? art.width : 64)) < 0.001)
        }
    }
}
