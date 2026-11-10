import AppKit
import SwiftUI

@main
struct EvolutionDefenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = AppRouter()

    init() {
        // Before the first view renders, so the menu uses the display face too.
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup("Evolution Defense") {
            ContentView(router: router)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
                .task { SnapshotTool.runIfRequested(router: router) }
                .task { SnapshotTool.runBenchmarkIfRequested(router: router) }
                .task { SnapshotTool.runAudioCheckIfRequested() }
                .task { SnapshotTool.runAssetDemoIfRequested(router: router) }
                .task { SnapshotTool.runDeathTestIfRequested(router: router) }
                .task { SnapshotTool.runSummonTestIfRequested(router: router) }
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Game") { router.newGame() }.keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

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
