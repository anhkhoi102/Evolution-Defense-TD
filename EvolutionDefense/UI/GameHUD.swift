import EvolutionDefenseCore
import SwiftUI

/// Top bar: era, wave, base HP, gold, research, speed and pause.
struct GameHUD: View {
    @Bindable var controller: GameController

    var body: some View {
        HStack(spacing: 14) {
            EraBadge(era: controller.era)
            WaveBlock(controller: controller)
            if let e = controller.activeEvent {
                Button { controller.eventCard = e } label: {
                    Image(systemName: e.icon).font(.system(size: 14, weight: .bold))
                        .foregroundStyle(e.positive ? Theme.good : Theme.warn)
                        .frame(width: 34, height: 40)
                }
                .buttonStyle(IconButtonStyle())
                .help("\(e.name): \(e.text)")
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                BaseHPBar(hp: controller.baseHP, maxHP: controller.maxBaseHP, hitCount: controller.baseHitCount,
                          shield: controller.baseShield)
                    .frame(width: 330)
                Button { controller.toggleRepairPanel() } label: {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 40)
                }
                .buttonStyle(IconButtonStyle(active: controller.isRepairPanelOpen))
                .disabled(!controller.canRepair && !controller.isRepairPanelOpen)
                .opacity(controller.canRepair || controller.isRepairPanelOpen ? 1 : 0.45)
                .help(controller.canRepair ? "Repair the base (R)" : "Repairs are available between waves when the base is damaged")
            }
            Spacer(minLength: 8)
            ResourcePill(icon: "circle.hexagongrid.circle.fill", value: controller.gold, tint: Theme.gold, label: "Gold")
            Button { controller.toggleTechPanel() } label: {
                ResourcePill(icon: "flask.fill", value: controller.researchPoints, tint: Theme.research, label: "Research Points — open technology (T)")
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.research, lineWidth: controller.isTechPanelOpen ? 2 : 0))
            }
            .buttonStyle(.plain)
            Button { controller.toggleSpeed() } label: {
                Text(controller.speed == 1 ? "1×" : "2×")
                    .font(Theme.display(15))
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(IconButtonStyle(active: controller.speed > 1))
            .help("Game speed (F)")
            Button { controller.togglePause() } label: {
                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(IconButtonStyle(active: controller.isPaused))
            .help("Pause (Space / Esc)")
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(
            LinearGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.17), Theme.panel], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1) }
        )
    }
}

struct IconButtonStyle: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? Color.black.opacity(0.85) : Theme.text)
            .background(RoundedRectangle(cornerRadius: 8).fill(active ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Theme.panelHigh)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct EraBadge: View {
    let era: Era
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Theme.eraIcon(era))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.eraColor(era))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.eraColor(era).opacity(0.18)))
            VStack(alignment: .leading, spacing: 0) {
                Text("ERA \(era.rawValue)")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.textDim)
                Text(era.displayName)
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(PanelBackground())
    }
}

private struct WaveBlock: View {
    let controller: GameController
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STAGE · \(controller.difficultyName.uppercased())").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(max(controller.waveNumber, 0)) / \(controller.totalWaves)")
                    .font(Theme.display(18)).monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text(statusText).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(PanelBackground())
    }

    private var statusText: String {
        switch controller.phase {
        case .waveInProgress: controller.enemiesRemaining == 1 ? "1 enemy left" : "\(controller.enemiesRemaining) enemies left"
        case .preparation:
            controller.countdownHeld ? "Countdown paused" : "Next in \(controller.countdownSeconds)s"
        case .victory: "Victory"
        case .defeat: "Defeat"
        }
    }
}

struct BaseHPBar: View {
    let hp: Int
    let maxHP: Int
    let hitCount: Int
    var shield = 0
    @State private var flash = false

    var body: some View {
        let status = BaseStatus(hp: hp)
        let tint = Theme.color(for: status)
        VStack(spacing: 3) {
            HStack {
                Label("BASE", systemImage: "house.lodge.fill")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                Text(status.label)
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(tint)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(tint.opacity(0.16)))
                Spacer()
                if shield > 0 {
                    Label("\(shield)", systemImage: "bolt.shield.fill")
                        .font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.research)
                        .help("Energy Shield absorbs the next \(shield) damage this wave")
                }
                Text("\(hp) / \(maxHP)")
                    .font(Theme.display(15)).monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.45))
                    Capsule()
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(0, g.size.width * CGFloat(hp) / CGFloat(max(1, maxHP))))
                        .animation(.easeOut(duration: 0.25), value: hp)
                    // Status thresholds at 70 / 40 / 20 HP
                    ForEach([70, 40, 20], id: \.self) { t in
                        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1)
                            .offset(x: g.size.width * CGFloat(t) / CGFloat(max(1, maxHP)))
                    }
                }
            }
            .frame(height: 10)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(PanelBackground())
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.danger, lineWidth: 2).opacity(flash ? 1 : 0))
        .scaleEffect(flash ? 1.03 : 1)
        .onChange(of: hitCount) {
            flash = true
            withAnimation(.easeOut(duration: 0.45)) { flash = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Base health \(hp) of \(maxHP), \(status.label)")
    }
}

private struct ResourcePill: View {
    let icon: String
    let value: Int
    let tint: Color
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
            Text("\(value)")
                .font(Theme.display(18)).monospacedDigit()
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(PanelBackground())
        .help(label)
        .accessibilityLabel("\(label) \(value)")
    }
}
