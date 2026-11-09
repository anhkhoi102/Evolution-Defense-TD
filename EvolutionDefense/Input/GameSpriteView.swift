import SpriteKit
import SwiftUI

/// SKView subclass that routes mouse input (including hover) to the scene.
final class GameSKView: SKView {
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    private var gameScene: GameScene? { scene as? GameScene }

    override func mouseMoved(with event: NSEvent) { gameScene?.handleMouseMoved(event) }
    override func mouseDragged(with event: NSEvent) { gameScene?.handleMouseMoved(event) }
    override func mouseExited(with event: NSEvent) { gameScene?.handleMouseExited() }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        gameScene?.handleMouseDown(event)
    }
    override func rightMouseDown(with event: NSEvent) { gameScene?.handleRightMouseDown(event) }
}

struct GameSpriteView: NSViewRepresentable {
    let controller: GameController

    func makeNSView(context: Context) -> GameSKView {
        let v = GameSKView(frame: .zero)
        v.ignoresSiblingOrder = true          // lets SpriteKit batch draws by texture
        v.shouldCullNonVisibleNodes = true
        v.preferredFramesPerSecond = 60
        v.allowsTransparency = false
        v.presentScene(controller.scene)
        return v
    }

    func updateNSView(_ v: GameSKView, context: Context) {
        let debug = controller.showsDebugStats
        if v.showsFPS != debug {
            v.showsFPS = debug
            v.showsNodeCount = debug
            v.showsDrawCount = debug
        }
    }
}
