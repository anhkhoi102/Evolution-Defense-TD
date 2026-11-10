import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct EvolutionDefenseApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var router = AppRouter()

    init() {
        // Before the first view renders, so the menu uses the display face too.
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup("Evolution Defense") {
            ContentView(router: router)
                #if os(macOS)
                .frame(minWidth: 1100, minHeight: 700)
                #endif
                .preferredColorScheme(.dark)
                .task { SnapshotTool.runAllIfRequested(router: router) }
        }
        #if os(macOS)
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Game") { router.newGame() }.keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensures a normal Dock app with focus even when the binary is launched
        // directly from Terminal (e.g. Scripts/snapshot.sh).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif

struct ContentView: View {
    let router: AppRouter

    var body: some View {
        Group {
            switch router.screen {
            case .menu:
                MainMenuView(router: router)
            case .game:
                if let g = router.game {
                    GameView(controller: g, router: router).id(ObjectIdentifier(g))
                }
            }
        }
        .background(SnapshotTool.capturesWindow ? Color.clear : Theme.panel)
    }
}
