import AppKit
import EvolutionDefenseCore
import SwiftUI

/// The in-match screen: HUD on top, map in the middle, controls at the bottom.
struct GameView: View {
    let controller: GameController
    let router: AppRouter
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            GameHUD(controller: controller)
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11).opacity(SnapshotTool.capturesWindow ? 0 : 1)
                GameSpriteView(controller: controller)
                DamageVignette(hitCount: controller.baseHitCount)
                if let b = controller.banner, b.kind == .era {
                    EraTransitionFlash(era: b.era, trigger: b.id)
                }
                if let boss = controller.boss, !controller.isOver {
                    VStack {
                        BossBar(boss: boss).padding(.top, controller.toast == nil ? 10 : 52)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                VStack {
                    if let t = controller.toast {
                        ToastView(toast: t).transition(.move(edge: .top).combined(with: .opacity)).id(t.id)
                    }
                    Spacer()
                }
                .padding(.top, 12)
                .animation(.spring(duration: 0.3), value: controller.toast)
                .allowsHitTesting(false)
                if controller.isRepairPanelOpen {
                    VStack {
                        RepairPanel(controller: controller).padding(.top, 10)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let e = controller.eventCard, !controller.isOver {
                    EventCardView(event: e) { controller.eventCard = nil }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                if let a = controller.achievementToast {
                    VStack {
                        HStack { Spacer(); AchievementToastView(achievement: a).padding(14) }
                        Spacer()
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
                if controller.isTechPanelOpen {
                    TechPanel(controller: controller)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
                if let b = controller.banner {
                    BannerView(banner: b).transition(.scale(scale: 0.85).combined(with: .opacity)).id(b.id)
                }
                if controller.isPaused && !controller.isOver {
                    if controller.showSettings {
                        ZStack {
                            Color.black.opacity(0.55).ignoresSafeArea()
                            SettingsPanel(router: router, onClose: { controller.showSettings = false })
                        }
                        .transition(.opacity)
                    } else {
                        PauseMenu(controller: controller).transition(.opacity)
                    }
                }
                if controller.isOver {
                    MatchEndView(controller: controller).transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: controller.banner)
            .animation(.easeOut(duration: 0.2), value: controller.isPaused)
            .animation(.easeOut(duration: 0.4), value: controller.isOver)
            .animation(.spring(duration: 0.25), value: controller.isRepairPanelOpen)
            .animation(.spring(duration: 0.25), value: controller.isTechPanelOpen)
            .animation(.spring(duration: 0.3), value: controller.eventCard)
            .animation(.spring(duration: 0.35), value: controller.achievementToast)
            .animation(.easeOut(duration: 0.2), value: controller.showSettings)
            .animation(.easeOut(duration: 0.3), value: controller.boss?.id)
            .clipped()
            BottomPanel(controller: controller)
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        let controller = self.controller
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Leave command shortcuts (⌘Q, ⌘W, ⌃⌘F…) to the system.
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
            let code = event.keyCode
            let chars = event.charactersIgnoringModifiers ?? ""
            let handled = MainActor.assumeIsolated { controller.handleKey(keyCode: code, characters: chars) }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }
}
