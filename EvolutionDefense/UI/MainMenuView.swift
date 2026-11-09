import EvolutionDefenseCore
import SwiftUI

struct MainMenuView: View {
    let router: AppRouter

    var body: some View {
        ZStack {
            VStack(spacing: 22) {
                Spacer()
                VStack(spacing: 6) {
                    Text("EVOLUTION")
                        .font(Theme.display(66)).tracking(6)
                    Text("DEFENSE")
                        .font(Theme.display(42)).tracking(18)
                        .foregroundStyle(Theme.gold)
                }
                .foregroundStyle(Theme.text)
                .shadow(color: .black.opacity(0.6), radius: 14, y: 4)

                HStack(spacing: 10) {
                    ForEach(Era.allCases, id: \.self) { era in
                        HStack(spacing: 6) {
                            Image(systemName: Theme.eraIcon(era)).foregroundStyle(Theme.eraColor(era))
                            Text(era.displayName).foregroundStyle(Theme.text)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        if era != .futuristic {
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textDim)
                        }
                    }
                }

                Group {
                    switch router.menuPanel {
                    case .none: mainButtons
                    case .newGame: NewGamePanel(router: router)
                    case .settings: SettingsPanel(router: router, onClose: { router.menuPanel = .none })
                    case .achievements: AchievementsPanel(router: router)
                    case .records: RecordsPanel(router: router)
                    }
                }
                .padding(.top, 6)
                .animation(.spring(duration: 0.3), value: router.menuPanel)

                if let err = router.loadError {
                    Text(err).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.danger)
                        .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.6)))
                }
                Spacer()
                Text("Standard Mode · 20 waves · 4 eras · 4 bosses  ·  v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                    .padding(.bottom, 14)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Backdrop as a background so its aspect-fill size never drives the layout.
        .background { backdrop }
        .clipped()
    }

    private var mainButtons: some View {
        VStack(spacing: 12) {
            if let cp = router.checkpoint {
                Button { router.continueGame() } label: {
                    VStack(spacing: 2) {
                        Label("Continue", systemImage: "play.fill")
                        Text("Wave \(cp.waveNumber + 1) · \(cp.era.displayName) · \(router.config?.difficulty(cp.options.difficulty).name ?? "")")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).opacity(0.75)
                    }
                    .frame(width: 240)
                }
                .buttonStyle(GameButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            Button { router.menuPanel = .newGame } label: {
                Label("New Game", systemImage: "flag.fill").frame(width: 240)
            }
            .buttonStyle(GameButtonStyle(prominent: router.checkpoint == nil))
            .disabled(router.loadError != nil)
            HStack(spacing: 10) {
                menuButton("Achievements", "medal.fill") { router.menuPanel = .achievements }
                menuButton("Records", "chart.bar.fill") { router.menuPanel = .records }
                menuButton("Settings", "gearshape.fill") { router.menuPanel = .settings }
            }
            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "xmark").frame(width: 240)
            }
            .buttonStyle(GameButtonStyle(prominent: false))
        }
    }

    private func menuButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(title).font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(width: 92, height: 48)
        }
        .buttonStyle(GameButtonStyle(prominent: false))
    }

    @ViewBuilder private var backdrop: some View {
        if let map = router.config?.map {
            Image(nsImage: NSImage(cgImage: ArtLibrary.shared.backgroundImage(for: map), size: .zero))
                .resizable().aspectRatio(contentMode: .fill)
                .blur(radius: 3)
                .overlay(LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
        } else {
            Theme.panel.ignoresSafeArea()
        }
    }
}

/// Common frame for menu panels with a Back button.
struct MenuCard<Content: View>: View {
    let title: String
    let icon: String
    var width: CGFloat = 560
    let onBack: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: icon).font(Theme.display(20)).foregroundStyle(Theme.text)
                Spacer()
                Button { onBack() } label: { Label("Back", systemImage: "chevron.left").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(GameButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
            }
            content
        }
        .padding(20)
        .frame(width: width)
        .background(PanelBackground(corner: 16).opacity(0.97))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 6)
    }
}

private struct NewGamePanel: View {
    let router: AppRouter

    var body: some View {
        MenuCard(title: "New Game", icon: "flag.fill", onBack: { router.menuPanel = .none }) {
            if router.checkpoint != nil {
                Label("Starting a new game replaces your saved match.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.warn)
            }
            Text("DIFFICULTY").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textDim)
            HStack(spacing: 10) {
                ForEach(router.config?.difficulties ?? [], id: \.id) { d in
                    let selected = router.settings.difficulty == d.id
                    Button { router.updateSettings { $0.difficulty = d.id } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(d.name).font(Theme.display(17))
                                Spacer()
                                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold) }
                            }
                            Text(d.summary).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            let r = router.profile.record(d.id)
                            Text(r.victories > 0 ? "Won \(r.victories)×" : (r.highestWave > 0 ? "Best: wave \(r.highestWave)" : "Not played"))
                                .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(r.victories > 0 ? Theme.gold : Theme.textDim)
                        }
                        .foregroundStyle(Theme.text)
                        .padding(12)
                        .frame(width: 164, height: 132, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.gold.opacity(0.16) : Theme.panelHigh))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Theme.gold : Theme.stroke, lineWidth: selected ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Random events").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                    Text("Every 3–4 waves: supply drops, reinforcements, mutations, breakdowns…")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Toggle("Random events", isOn: Binding(get: { router.settings.randomEvents },
                                                      set: { v in router.updateSettings { $0.randomEvents = v } }))
                    .toggleStyle(.switch).labelsHidden()
            }
            HStack {
                Spacer()
                Button { router.newGame() } label: { Label("Start", systemImage: "play.fill").frame(width: 160) }
                    .buttonStyle(GameButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct SettingsPanel: View {
    let router: AppRouter
    let onClose: () -> Void
    @State private var confirmReset = false

    var body: some View {
        let s = router.settings
        MenuCard(title: "Settings", icon: "gearshape.fill", width: 480, onBack: onClose) {
            section("AUDIO")
            slider("Master volume", s.masterVolume) { v in router.updateSettings { $0.masterVolume = v } }
            toggleRow("Music", s.musicEnabled) { v in router.updateSettings { $0.musicEnabled = v } }
            slider("Music volume", s.musicVolume) { v in router.updateSettings { $0.musicVolume = v } }.disabled(!s.musicEnabled)
            toggleRow("Sound effects", s.effectsEnabled) { v in router.updateSettings { $0.effectsEnabled = v } }
            slider("Effects volume", s.effectsVolume) { v in router.updateSettings { $0.effectsVolume = v } }.disabled(!s.effectsEnabled)
            section("GRAPHICS & PERFORMANCE")
            toggleRow("Performance mode", s.performanceMode,
                      detail: "Fewer particles and floating numbers, no muzzle flashes or shadows. For long sessions on battery.") { v in
                router.updateSettings { $0.performanceMode = v }
            }
            toggleRow("Screen shake", s.screenShake) { v in router.updateSettings { $0.screenShake = v } }
            toggleRow("Show FPS counter", s.showFPS) { v in router.updateSettings { $0.showFPS = v } }
            section("PROGRESS")
            HStack {
                Text("Saves are stored automatically between waves.").font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                Spacer()
                Button(confirmReset ? "Confirm reset" : "Reset progress") {
                    if confirmReset { router.resetProgress(); confirmReset = false } else { confirmReset = true }
                }
                .buttonStyle(GameButtonStyle(tint: Theme.danger, prominent: confirmReset))
                .font(.system(size: 11))
            }
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textDim).padding(.top, 4)
    }

    private func slider(_ label: String, _ value: Double, set: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text).frame(width: 130, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: 0...1)
            Text("\(Int((value * 100).rounded()))%").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.textDim).frame(width: 40, alignment: .trailing)
        }
    }

    private func toggleRow(_ label: String, _ value: Bool, detail: String? = nil, set: @escaping @MainActor @Sendable (Bool) -> Void) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle(label, isOn: Binding(get: { value }, set: set)).toggleStyle(.switch).labelsHidden()
        }
    }
}

private struct AchievementsPanel: View {
    let router: AppRouter

    var body: some View {
        let all = router.config?.achievements ?? []
        let unlocked = router.profile.achievements
        MenuCard(title: "Achievements · \(unlocked.count)/\(all.count)", icon: "medal.fill", width: 720,
                 onBack: { router.menuPanel = .none }) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(all) { a in
                        let date = unlocked[a.id]
                        HStack(spacing: 10) {
                            Image(systemName: a.icon).font(.system(size: 18, weight: .bold))
                                .foregroundStyle(date != nil ? Theme.gold : Theme.textDim)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(date != nil ? Theme.gold.opacity(0.18) : Color.white.opacity(0.05)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(date != nil ? Theme.text : Theme.textDim)
                                Text(a.summary).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim).lineLimit(2)
                                if let date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold.opacity(0.8))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(height: 70)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelHigh))
                        .opacity(date != nil ? 1 : 0.7)
                    }
                }
            }
            .frame(maxHeight: 440)
        }
    }
}

private struct RecordsPanel: View {
    let router: AppRouter

    var body: some View {
        let p = router.profile
        MenuCard(title: "Records", icon: "chart.bar.fill", width: 620, onBack: { router.menuPanel = .none }) {
            HStack(spacing: 10) {
                ForEach(router.config?.difficulties ?? [], id: \.id) { d in
                    let r = p.record(d.id)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(d.name.uppercased()).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                        row("Matches", "\(r.matches)")
                        row("Victories", "\(r.victories)")
                        row("Highest wave", "\(r.highestWave)")
                        row("Fastest win", r.bestTime.map { Self.time($0) } ?? "—")
                        row("Best base HP", r.bestBaseHP.map(String.init) ?? "—")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelHigh))
                }
            }
            HStack(spacing: 18) {
                row("Enemies defeated", "\(p.totalKills)")
                row("Bosses defeated", "\(p.totalBossesDefeated)")
                row("Technologies discovered", "\(p.techsEverResearched.count)/\(router.config?.techs.count ?? 0)")
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.textDim)
            Spacer(minLength: 6)
            Text(v).font(Theme.display(15)).monospacedDigit().foregroundStyle(Theme.text)
        }
    }

    static func time(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}
