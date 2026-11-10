import SpriteKit
import SwiftUI

// The SpriteKit view and its input adapter. Each platform turns its own events into the
// three pointer calls the scene understands (GameScene: pointerMoved / pointerPressed /
// pointerCancelled), so the game never sees a mouse or a finger directly.

#if os(macOS)
import AppKit

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
    private func point(_ event: NSEvent) -> CGPoint? { gameScene.map { event.location(in: $0.pointerSpace) } }

    override func mouseMoved(with event: NSEvent) { if let p = point(event) { gameScene?.pointerMoved(to: p) } }
    override func mouseDragged(with event: NSEvent) { if let p = point(event) { gameScene?.pointerMoved(to: p) } }
    override func mouseExited(with event: NSEvent) { gameScene?.pointerLeft() }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let p = point(event) { gameScene?.pointerPressed(at: p) }
    }
    override func rightMouseDown(with event: NSEvent) { gameScene?.pointerCancelled() }
}

struct GameSpriteView: NSViewRepresentable {
    let controller: GameController

    func makeNSView(context: Context) -> GameSKView {
        let v = GameSKView(frame: .zero)
        GameSpriteView.configure(v, controller: controller)
        return v
    }

    func updateNSView(_ v: GameSKView, context: Context) { GameSpriteView.sync(v, controller: controller) }
}
#else
import UIKit

/// SKView subclass that routes touches to the scene: a finger down or moving previews
/// (like hovering), lifting it acts (like a click). Two-finger tap cancels.
final class GameSKView: SKView {
    private var gameScene: GameScene? { scene as? GameScene }
    private func point(_ touches: Set<UITouch>) -> CGPoint? {
        guard let t = touches.first, let s = gameScene else { return nil }
        return t.location(in: s.pointerSpace)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (event?.allTouches?.count ?? 1) > 1 { gameScene?.pointerCancelled(); return }
        if let p = point(touches) { gameScene?.pointerMoved(to: p) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let p = point(touches) { gameScene?.pointerMoved(to: p) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let p = point(touches) { gameScene?.pointerPressed(at: p) }
        gameScene?.pointerLeft()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { gameScene?.pointerLeft() }
}

struct GameSpriteView: UIViewRepresentable {
    let controller: GameController

    func makeUIView(context: Context) -> GameSKView {
        let v = GameSKView(frame: .zero)
        GameSpriteView.configure(v, controller: controller)
        return v
    }

    func updateUIView(_ v: GameSKView, context: Context) { GameSpriteView.sync(v, controller: controller) }
}
#endif

extension GameSpriteView {
    @MainActor static func configure(_ v: SKView, controller: GameController) {
        v.ignoresSiblingOrder = true          // lets SpriteKit batch draws by texture
        v.shouldCullNonVisibleNodes = true
        v.preferredFramesPerSecond = 60
        v.allowsTransparency = false
        v.presentScene(controller.scene)
    }

    @MainActor static func sync(_ v: SKView, controller: GameController) {
        let debug = controller.showsDebugStats
        if v.showsFPS != debug {
            v.showsFPS = debug
            v.showsNodeCount = debug
            v.showsDrawCount = debug
        }
    }
}
