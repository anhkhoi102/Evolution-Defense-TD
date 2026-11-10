import EvolutionDefenseCore
import SwiftUI

struct MainMenuView: View {
    let router: AppRouter
    @State private var appeared = false

    var body: some View {
        let compact = router.menuPanel != .none
        ZStack {
            VStack(spacing: compact ? 12 : 20) {
                Spacer(minLength: 0)
                MenuLogo(compact: compact)
                if !compact { eraStrip.transition(.opacity) }

                ZStack {
                    switch router.menuPanel {
                    case .none: mainButtons
                    case .newGame: NewGamePanel(router: router)
                    case .battlefields: BattlefieldPanel(router: router)
                    case .settings: SettingsPanel(router: router, onClose: { router.menuPanel = .none })
                    case .achievements: AchievementsPanel(router: router)
                    case .records: RecordsPanel(router: router)
                    case .credits: CreditsPanel(router: router)
                    }
                }
                // Each screen slides up and fades in; the old one fades out.
                .id(router.menuPanel)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)).combined(with: .scale(scale: 0.98)),
                                        removal: .opacity))

                if let err = router.loadError {
                    Text(err).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.danger)
                        .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.6)))
                }
                Spacer(minLength: 0)
                Text("20 waves · 4 ages · 4 bosses · 3 battlefields  ·  v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                    .padding(.bottom, 12)
            }
            .padding()
            .animation(.easeInOut(duration: 0.28), value: router.menuPanel)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Backdrop as a background so its aspect-fill size never drives the layout.
        .background { backdrop }
        .clipped()
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }

    private var eraStrip: some View {
        HStack(spacing: 10) {
            ForEach(Era.allCases, id: \.self) { era in
                HStack(spacing: 6) {
                    Image(systemName: Theme.eraIcon(era)).foregroundStyle(Theme.eraColor(era))
                    Text(era.displayName).foregroundStyle(Theme.text)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .overlay(Capsule().strokeBorder(Theme.eraColor(era).opacity(0.35)))
                if era != .futuristic {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private var mainButtons: some View {
        VStack(spacing: 11) {
            if let cp = router.checkpoint {
                Button { router.continueGame() } label: {
                    VStack(spacing: 2) {
                        Label("Continue", systemImage: "play.fill")
                        Text("Wave \(cp.waveNumber + 1) · \(router.config?.battlefield(cp.options.battlefield)?.name ?? "") · \(router.config?.difficulty(cp.options.difficulty).name ?? "")")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).opacity(0.75)
                    }
                    .frame(width: 280)
                }
                .buttonStyle(GameButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            Button { router.menuPanel = .newGame } label: {
                Label(router.checkpoint == nil ? "Play" : "New Game", systemImage: "flag.fill")
                    .font(Theme.display(router.checkpoint == nil ? 21 : 17))
                    .frame(width: 280).padding(.vertical, router.checkpoint == nil ? 4 : 0)
            }
            .buttonStyle(GameButtonStyle(prominent: router.checkpoint == nil))
            .disabled(router.loadError != nil)

            // Battlefield: shows the current choice and opens the selection screen.
            Button { router.menuPanel = .battlefields } label: {
                HStack(spacing: 10) {
                    if let map = router.selectedBattlefield {
                        Image(nsImage: NSImage(cgImage: ArtLibrary.shared.backgroundImage(for: map), size: .zero))
                            .resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 32).clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.5)))
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Battlefield").font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.75)
                        Text(router.selectedBattlefield?.name ?? "").font(Theme.display(16))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).opacity(0.8)
                }
                .frame(width: 280)
            }
            .buttonStyle(GameButtonStyle(prominent: false))
            .disabled(router.loadError != nil)

            HStack(spacing: 6) {
                menuButton("Awards", "medal.fill") { router.menuPanel = .achievements }
                menuButton("Records", "chart.bar.fill") { router.menuPanel = .records }
                menuButton("Settings", "gearshape.fill") { router.menuPanel = .settings }
                menuButton("Credits", "heart.fill") { router.menuPanel = .credits }
            }
            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "xmark").font(Theme.display(14)).frame(width: 120)
            }
            .buttonStyle(GameButtonStyle(prominent: false))
            .padding(.top, 2)
        }
    }

    private func menuButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(title).font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(width: 60, height: 46)
        }
        .buttonStyle(GameButtonStyle(prominent: false))
    }

    /// The selected battlefield, softly blurred and darkened; cross-fades when the choice changes.
    @ViewBuilder private var backdrop: some View {
        if let map = router.selectedBattlefield {
            ZStack {
                Image(nsImage: NSImage(cgImage: ArtLibrary.shared.backgroundImage(for: map), size: .zero))
                    .resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: 2.5)
                    .id(map.id)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.5), value: map.id)
            .overlay(LinearGradient(colors: [Color.black.opacity(0.42), Color.black.opacity(0.25), Color.black.opacity(0.78)],
                                    startPoint: .top, endPoint: .bottom))
            .overlay(RadialGradient(colors: [.clear, Color.black.opacity(0.55)], center: .center, startRadius: 280, endRadius: 900))
            .ignoresSafeArea()
        } else {
            Theme.panel.ignoresSafeArea()
        }
    }
}

/// Title lockup: the game's emblem above a gold title. Shrinks to a single
/// line while a menu screen is open.
private struct MenuLogo: View {
    let compact: Bool

    private var gold: LinearGradient {
        LinearGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.66), Color(red: 1.0, green: 0.76, blue: 0.24), Color(red: 0.86, green: 0.52, blue: 0.10)],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            if !compact {
                // From the app's own asset catalog (the system icon cache can lag behind).
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 128, height: 128)
                    .shadow(color: Color(red: 1, green: 0.8, blue: 0.4).opacity(0.35), radius: 26)
                    .padding(.bottom, -8)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            Text("EVOLUTION")
                .font(Theme.display(compact ? 30 : 68)).tracking(compact ? 3 : 6)
                .foregroundStyle(gold)
                .shadow(color: Color(red: 0.35, green: 0.16, blue: 0.02), radius: 0, x: 0, y: compact ? 2 : 4)
                .shadow(color: .black.opacity(0.65), radius: 12, y: 6)
            HStack(spacing: 12) {
                ornament
                Text("DEFENSE")
                    .font(Theme.display(compact ? 15 : 30)).tracking(compact ? 8 : 16)
                    .foregroundStyle(Theme.text)
                    .shadow(color: .black.opacity(0.7), radius: 6, y: 2)
                ornament.scaleEffect(x: -1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Evolution Defense")
    }

    private var ornament: some View {
        HStack(spacing: 4) {
            Capsule().fill(LinearGradient(colors: [.clear, Theme.gold], startPoint: .leading, endPoint: .trailing))
                .frame(width: compact ? 40 : 90, height: 2)
            Image(systemName: "diamond.fill").font(.system(size: compact ? 5 : 8)).foregroundStyle(Theme.gold)
        }
    }
}

/// Battlefield selection: three cards with a preview, name and description.
private struct BattlefieldPanel: View {
    let router: AppRouter

    var body: some View {
        let selected = router.selectedBattlefield?.id
        MenuCard(title: "Choose a Battlefield", icon: "map.fill", width: 940, onBack: { router.menuPanel = .none }) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(router.battlefields, id: \.id) { map in
                    BattlefieldCard(map: map, selected: map.id == selected) {
                        withAnimation(.easeInOut(duration: 0.2)) { router.selectBattlefield(map.id) }
                    }
                }
            }
            HStack {
                Label("Same towers, enemies and waves on every battlefield. Only the land and the road change.",
                      systemImage: "info.circle")
                    .font(.system(size: 11.5, design: .rounded)).foregroundStyle(Theme.textDim)
                Spacer()
                Button { router.menuPanel = .newGame } label: {
                    Label("Play", systemImage: "play.fill").frame(width: 150)
                }
                .buttonStyle(GameButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct BattlefieldCard: View {
    let map: MapDefinition
    let selected: Bool
    let action: () -> Void

    private var accent: Color {
        guard let hex = map.theme?.accent, let v = UInt32(hex.dropFirst(), radix: 16) else { return Theme.gold }
        return Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(nsImage: NSImage(cgImage: ArtLibrary.shared.backgroundImage(for: map), size: .zero))
                    .resizable().aspectRatio(2, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Label("Selected", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black.opacity(0.85))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(accent))
                                .padding(7)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.black.opacity(0.35)))
                HStack(spacing: 7) {
                    Circle().fill(accent).frame(width: 9, height: 9)
                    Text(map.name).font(Theme.display(21)).foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(selected ? accent : Theme.textDim)
                }
                Text(map.summary ?? "")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? accent.opacity(0.16) : Theme.panelHigh))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? accent : Theme.stroke, lineWidth: selected ? 2.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
        .help("\(map.name): \(map.summary ?? "")")
        .accessibilityLabel("\(map.name)\(selected ? ", selected" : "")")
    }
}

/// Who made the art, sounds and font (all free-licence; see Docs/ASSET_LICENSES.md).
private struct CreditsPanel: View {
    let router: AppRouter

    private static let credits: [(String, [(String, String)])] = [
        ("ART · 3D models rendered to sprites", [
            ("Kenney (kenney.nl)", "Tower Defense Kit, Castle Kit, Nature Kit, Space Kit, Blaster Kit, Mini Characters, Particle Pack, UI Pack Adventure · CC0"),
            ("Quaternius (quaternius.com)", "Ultimate Animated Animals, Animated Monster Pack, Cute Monster Pack, Animated Robot, Animated Mech Pack · CC0"),
            ("Teh_Bucket (OpenGameArt)", "Boar · CC0"),
        ]),
        ("SOUND", [
            ("Kenney (kenney.nl)", "Interface Sounds, Impact Sounds, Sci-fi Sounds, RPG Audio · CC0"),
            ("In-game synthesizer", "Music for every age and the remaining effects"),
        ]),
        ("FONT", [
            ("Lilita One", "Juan Montoreano · SIL Open Font License 1.1"),
        ]),
        ("MADE WITH", [
            ("Swift · SwiftUI · SpriteKit", "Game, interface and rendering"),
            ("Blender", "Art pipeline: every sprite is rendered from 3D"),
        ]),
    ]

    var body: some View {
        MenuCard(title: "Credits", icon: "heart.fill", width: 620, onBack: { router.menuPanel = .none }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Self.credits, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.0).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                            ForEach(section.1, id: \.0) { row in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.0).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                                    Text(row.1).font(.system(size: 11.5, design: .rounded)).foregroundStyle(Theme.textDim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelHigh))
                    }
                    Text("Thank you to everyone who shares their work freely. The full list with links and licences is in the project's ASSET_LICENSES document.")
                        .font(.system(size: 11.5, design: .rounded)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: 400)
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
            if let map = router.selectedBattlefield {
                Text("BATTLEFIELD").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textDim)
                HStack(spacing: 12) {
                    Image(nsImage: NSImage(cgImage: ArtLibrary.shared.backgroundImage(for: map), size: .zero))
                        .resizable().aspectRatio(2, contentMode: .fit)
                        .frame(height: 54).clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.black.opacity(0.35)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(map.name).font(Theme.display(18)).foregroundStyle(Theme.text)
                        Text(map.summary ?? "").font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button { router.menuPanel = .battlefields } label: {
                        Label("Change", systemImage: "map.fill").font(Theme.display(13))
                    }
                    .buttonStyle(GameButtonStyle(prominent: false))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelHigh))
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
                    .buttonStyle(CardButtonStyle())
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
