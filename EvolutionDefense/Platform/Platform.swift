import SpriteKit
import SwiftUI

// The only place that knows which Apple platform the game runs on (Docs/IOS_READINESS.md).
// Everything else uses these names, so rendering, UI and game code compile unchanged on
// macOS and iOS. Adding iOS means adding cases here, not editing the game.

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#else
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont

extension UIColor {
    /// Same spelling as AppKit, so colour literals in the renderers work on both platforms.
    convenience init(srgbRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) {
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
#endif

@MainActor
enum Platform {
    /// A Mac app has a Quit button; an iOS app never quits itself.
    static var canQuit: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static func quit() {
        #if os(macOS)
        NSApp.terminate(nil)
        #endif
    }

    /// Posted when the match should be saved because the app is going away
    /// (quit on the Mac; sent to the background on iOS, where it may never come back).
    static var shouldSaveNotification: Notification.Name {
        #if os(macOS)
        NSApplication.willTerminateNotification
        #else
        UIApplication.willResignActiveNotification
        #endif
    }

    /// The app icon for the menu logo.
    static var appIcon: Image {
        #if os(macOS)
        Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
        #else
        Image("MenuIcon")
        #endif
    }

    /// A catalog image and its size in points (art pack frames stored as image sets).
    static func catalogImage(named name: String) -> (CGImage, CGSize)? {
        #if os(macOS)
        guard let img = NSImage(named: name), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return (cg, img.size)
        #else
        guard let img = UIImage(named: name), let cg = img.cgImage else { return nil }
        return (cg, img.size)
        #endif
    }

    static func color(_ cg: CGColor) -> PlatformColor {
        #if os(macOS)
        NSColor(cgColor: cg) ?? .white
        #else
        UIColor(cgColor: cg)
        #endif
    }

    static func fontExists(_ name: String) -> Bool { PlatformFont(name: name, size: 12) != nil }
}

/// Keyboard shortcuts during a match. Mac: a local key monitor. iOS: nothing yet
/// (a hardware keyboard could be wired here later); every action also has an on-screen control.
@MainActor
final class KeyboardMonitor {
    private var token: Any?

    /// `handler` returns true when it used the key.
    func start(_ handler: @escaping @MainActor (_ keyCode: UInt16, _ characters: String) -> Bool) {
        stop()
        #if os(macOS)
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Leave command shortcuts (⌘Q, ⌘W, ⌃⌘F…) to the system.
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
            let code = event.keyCode
            let chars = event.charactersIgnoringModifiers ?? ""
            let handled = MainActor.assumeIsolated { handler(code, chars) }
            return handled ? nil : event
        }
        #endif
    }

    func stop() {
        #if os(macOS)
        if let t = token { NSEvent.removeMonitor(t) }
        #endif
        token = nil
    }
}
