import EvolutionDefenseCore
import SwiftUI

struct ToastView: View {
    let toast: Toast
    var body: some View {
        let tint: Color = switch toast.kind {
        case .info: Theme.research
        case .success: Theme.good
        case .warning: Theme.danger
        }
        HStack(spacing: 8) {
            Image(systemName: toast.kind == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill").foregroundStyle(tint)
            Text(toast.text).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.6)))
    }
}

struct BannerView: View {
    let banner: Banner
    var body: some View {
        let tint: Color = switch banner.kind {
        case .wave: Theme.gold
        case .boss, .phase: Theme.danger
        case .era: Theme.eraColor(banner.era)
        }
        VStack(spacing: 4) {
            if banner.kind == .era {
                Image(systemName: Theme.eraIcon(banner.era))
                    .font(.system(size: 34, weight: .bold)).foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.8), radius: 14)
            }
            Text(banner.subtitle)
                .font(Theme.display(15)).tracking(2)
                .foregroundStyle(tint)
            Text(banner.title)
                .font(.system(size: banner.kind == .wave ? 38 : 46, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)
                .shadow(color: tint.opacity(0.6), radius: 12)
        }
        .padding(.horizontal, 36).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.5)))
        )
        .allowsHitTesting(false)
    }
}

/// Full-map colour wash when a new era begins.
struct EraTransitionFlash: View {
    let era: Era
    let trigger: UUID
    @State private var progress = 1.0
    var body: some View {
        let tint = Theme.eraColor(era)
        RadialGradient(colors: [tint.opacity(0.55), tint.opacity(0.15), .clear], center: .center,
                       startRadius: 20, endRadius: 200 + 900 * progress)
            .opacity(1 - progress)
            .allowsHitTesting(false)
            .onAppear { animate() }
            .onChange(of: trigger) { animate() }
    }

    private func animate() {
        progress = 0
        withAnimation(.easeOut(duration: 2.2)) { progress = 1 }
    }
}

/// Big health bar for the boss on the field: name, phase, HP and shield.
struct BossBar: View {
    let boss: BossSnapshot
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: boss.isFinal ? "crown.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                Text(boss.name.uppercased())
                    .font(Theme.display(15)).tracking(1.5).foregroundStyle(Theme.text)
                if let p = boss.phaseName {
                    Text(p.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.danger)).foregroundStyle(.white)
                }
                Spacer()
                Text("\(Int((boss.hpFraction * 100).rounded(.up)))%")
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Theme.text)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.55))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0.85, green: 0.25, blue: 0.95), Color(red: 0.6, green: 0.12, blue: 0.7)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: max(0, g.size.width * boss.hpFraction))
                        .animation(.easeOut(duration: 0.2), value: boss.hpFraction)
                    if boss.shieldFraction > 0 {
                        Capsule().fill(Theme.research.opacity(0.75))
                            .frame(width: g.size.width * boss.shieldFraction, height: 4)
                            .offset(y: -5)
                    }
                    Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1).offset(x: g.size.width * 0.5)
                }
            }
            .frame(height: 12)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
            if !boss.abilities.isEmpty {
                Text(boss.abilities.joined(separator: " · "))
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(width: 460)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.danger.opacity(0.45)))
        .allowsHitTesting(false)
    }
}

/// Technology tree: three techs per era, bought with Research Points.
/// Opening it pauses the preparation countdown.
struct TechPanel: View {
    let controller: GameController

    var body: some View {
        let cards = controller.techCards
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Technology", systemImage: "flask.fill")
                    .font(Theme.display(19)).foregroundStyle(Theme.text)
                Text("Optional upgrades that last the whole match")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.textDim)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "flask.fill").foregroundStyle(Theme.research)
                    Text("\(controller.researchPoints) RP").font(Theme.display(17)).monospacedDigit()
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.research.opacity(0.15)))
                Button { controller.toggleTechPanel() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26) }
                    .buttonStyle(IconButtonStyle())
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(Era.allCases, id: \.self) { era in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: Theme.eraIcon(era)).foregroundStyle(Theme.eraColor(era))
                            Text(era.displayName.uppercased())
                                .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1)
                                .foregroundStyle(era <= controller.era ? Theme.text : Theme.textDim)
                        }
                        ForEach(cards.filter { $0.tech.era == era }) { card in
                            TechCardView(card: card, controller: controller)
                        }
                    }
                    .frame(width: 214)
                }
            }
            Text("Research Points: defeat bosses, finish an era, or clear a wave without damage. Countdown paused · Esc or T to close")
                .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
        }
        .padding(16)
        .fixedSize()
        .background(PanelBackground(corner: 16).opacity(0.98))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 6)
    }
}

private struct TechCardView: View {
    let card: TechCard
    let controller: GameController

    var body: some View {
        let t = card.tech
        let tint = Theme.eraColor(t.era)
        let (label, enabled, highlight): (String, Bool, Bool) = switch card.status {
        case .researched: ("Researched", false, false)
        case .available: ("Research · \(t.cost) RP", true, true)
        case .unaffordable(let n): ("Needs \(n) RP", false, false)
        case .locked(let era): ("Unlocks in \(era.displayName)", false, false)
        }
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: t.icon).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 24, height: 24).background(Circle().fill(tint.opacity(0.16)))
                Text(t.name).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 0)
                if card.status == .researched {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.good)
                } else {
                    Text("\(t.cost)").font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.research)
                }
            }
            Text(t.summary).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true).lineLimit(3)
            Spacer(minLength: 0)
            Button { controller.research(t.id) } label: {
                Text(label).font(.system(size: 11, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                    .foregroundStyle(highlight ? Color.black.opacity(0.85) : (card.status == .researched ? Theme.good : Theme.textDim))
                    .background(RoundedRectangle(cornerRadius: 7).fill(highlight ? AnyShapeStyle(Theme.research) : AnyShapeStyle(Color.white.opacity(0.05))))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
        .padding(10)
        .frame(height: 122)
        .background(RoundedRectangle(cornerRadius: 10).fill(card.status == .researched ? tint.opacity(0.12) : Theme.panelHigh))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(card.status == .researched ? Theme.good.opacity(0.5)
                                                                  : highlight ? Theme.research.opacity(0.6) : Theme.stroke))
        .opacity({ if case .locked = card.status { return 0.55 } else { return 1 } }())
    }
}

/// Red edge flash when the base takes damage.
struct DamageVignette: View {
    let hitCount: Int
    @State private var opacity = 0.0
    var body: some View {
        RadialGradient(colors: [.clear, Theme.danger.opacity(0.55)], center: .center, startRadius: 250, endRadius: 800)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: hitCount) {
                opacity = 1
                withAnimation(.easeOut(duration: 0.6)) { opacity = 0 }
            }
    }
}

struct PauseMenu: View {
    let controller: GameController
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("PAUSED").font(Theme.display(36)).foregroundStyle(Theme.text)
                Text("Stage \(controller.waveNumber) of \(controller.totalWaves) · \(controller.era.displayName) · \(controller.difficultyName)")
                    .font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textDim)
                VStack(spacing: 10) {
                    Button("Resume") { controller.togglePause() }.buttonStyle(GameButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    Button("Settings") { controller.showSettings = true }.buttonStyle(GameButtonStyle(prominent: false))
                    Button("Restart Match") { controller.restart() }.buttonStyle(GameButtonStyle(prominent: false))
                    Button("Save & Main Menu") { controller.exitToMenu() }.buttonStyle(GameButtonStyle(prominent: false))
                }
                .frame(width: 220)
                Text(controller.phase == .preparation ? "Your match is saved at this point." : "Your match resumes from the start of this wave.")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                .padding(.top, 6)
            }
            .padding(32)
            .background(PanelBackground(corner: 18))
            .shadow(radius: 30)
        }
    }
}

struct MatchEndView: View {
    let controller: GameController
    var body: some View {
        let won = controller.phase == .victory
        let tint = won ? Theme.gold : Theme.danger
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: won ? "crown.fill" : "house.lodge.fill")
                    .font(.system(size: 44, weight: .bold)).foregroundStyle(tint)
                Text(won ? "VICTORY" : "DEFEAT")
                    .font(Theme.display(46)).foregroundStyle(Theme.text)
                Text(won ? "Your civilisation outlasted every era." : "The base has fallen in the \(controller.era.displayName).")
                    .font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.textDim)
                if won {
                    StarRow(stars: controller.matchStars, size: 34, animated: true)
                    Text(controller.matchStars == StarRatingConfig.maxStars ? "Perfect defence!" : "Lose less base health to earn more stars.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.gold)
                }
                HStack(spacing: 22) {
                    stat("Stages cleared", "\(controller.stats.wavesCleared)/\(controller.totalWaves)")
                    stat("Enemies defeated", "\(controller.stats.enemiesKilled)")
                    stat("Bosses", "\(controller.stats.bossesDefeated)/\(controller.config.waves.flatMap(\.groups).filter { controller.config.enemies[$0.enemy]?.isBoss == true }.count)")
                    stat("Gold earned", "\(controller.stats.goldEarned)")
                    stat("Tech", "\(controller.stats.techsResearched)")
                    stat("Base HP", "\(controller.baseHP)")
                }
                .padding(.vertical, 8)
                if !controller.heroesUnlockedThisMatch.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill").foregroundStyle(Theme.gold)
                        Text("New hero unlocked: \(controller.heroesUnlockedThisMatch.map(\.unitName).joined(separator: ", ")). Choose it in New Game.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.gold.opacity(0.14)))
                }
                if !controller.unlockedThisMatch.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "medal.fill").foregroundStyle(Theme.gold)
                        let names = controller.unlockedThisMatch.map(\.name)
                        let shown = names.prefix(4).joined(separator: ", ") + (names.count > 4 ? " +\(names.count - 4) more" : "")
                        Text("\(names.count) new achievement\(names.count == 1 ? "" : "s"): \(shown)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.gold.opacity(0.14)))
                }
                HStack(spacing: 10) {
                    Button("Play Again") { controller.restart() }.buttonStyle(GameButtonStyle(tint: tint))
                        .keyboardShortcut(.defaultAction)
                    Button("Main Menu") { controller.exitToMenu() }.buttonStyle(GameButtonStyle(prominent: false))
                }
            }
            .padding(36)
            .background(PanelBackground(corner: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(tint.opacity(0.4)))
            .shadow(radius: 30)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.display(24)).monospacedDigit().foregroundStyle(Theme.text)
            Text(label.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.textDim)
        }
    }
}

/// "New hero unlocked" card, shown between stages until the player closes it.
struct HeroUnlockCard: View {
    let controller: GameController
    let hero: SummonAbilityDefinition
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("NEW HERO UNLOCKED").font(.system(size: 12, weight: .heavy, design: .rounded)).kerning(2).foregroundStyle(Theme.gold)
                Image(decorative: ArtLibrary.shared.summonIcon(hero), scale: 1)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 120, height: 120)
                    .shadow(color: Theme.gold.opacity(0.7), radius: appeared ? 22 : 4)
                    .scaleEffect(appeared ? 1 : 0.5)
                Text(hero.unitName.uppercased()).font(Theme.display(34)).foregroundStyle(Theme.text)
                Text(hero.role ?? "").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
                Text(hero.summary).font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center).frame(maxWidth: 420).fixedSize(horizontal: false, vertical: true)
                Text("Pick this hero on the New Game screen for your next match.")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                Button("Great!") { controller.heroUnlock = nil }.buttonStyle(GameButtonStyle())
                    .keyboardShortcut(.defaultAction).padding(.top, 4)
            }
            .padding(30)
            .background(PanelBackground(corner: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.gold.opacity(0.6), lineWidth: 2))
            .shadow(radius: 30)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { appeared = true } }
    }
}

/// Base repair options (preparation phase only). Opening it pauses the countdown.
struct RepairPanel: View {
    let controller: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Repair base", systemImage: "hammer.fill")
                    .font(Theme.display(16)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(controller.baseHP) / \(controller.maxBaseHP) HP")
                    .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.color(for: controller.baseStatus))
            }
            HStack(spacing: 8) {
                ForEach(controller.repairChoices) { choice in
                    let affordable = controller.gold >= choice.cost
                    let useful = choice.heal > 0
                    Button { controller.repair(option: choice.id) } label: {
                        VStack(spacing: 2) {
                            Text("+\(choice.heal) HP").font(Theme.display(17))
                            HStack(spacing: 3) {
                                Image(systemName: "circle.hexagongrid.circle.fill").font(.system(size: 10))
                                Text("\(choice.cost)").font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                            }
                            .foregroundStyle(affordable ? Theme.gold : Theme.danger)
                            if choice.heal < choice.nominalHP && useful {
                                Text("partial").font(.system(size: 9, design: .rounded)).foregroundStyle(Theme.textDim)
                            }
                        }
                        .foregroundStyle(Theme.text)
                        .frame(width: 96, height: 56)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelHigh))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(affordable ? Theme.good.opacity(0.5) : Theme.danger.opacity(0.4)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!useful)
                    .opacity(useful ? 1 : 0.4)
                }
            }
            Text("Countdown paused · Esc or R to close")
                .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.textDim)
        }
        .padding(14)
        .frame(width: 340)
        .background(PanelBackground(corner: 14).opacity(0.97))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 4)
    }
}

/// A random event happened: what it is and what it does.
struct EventCardView: View {
    let event: EventInfo
    let dismiss: () -> Void

    var body: some View {
        let tint = event.positive ? Theme.good : Theme.warn
        VStack(spacing: 10) {
            Text("RANDOM EVENT").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(2).foregroundStyle(tint)
            Image(systemName: event.icon).font(.system(size: 34, weight: .bold)).foregroundStyle(tint)
                .frame(width: 64, height: 64).background(Circle().fill(tint.opacity(0.15)))
            Text(event.name).font(Theme.display(26)).foregroundStyle(Theme.text)
            Text(event.text).font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button("Got it", action: dismiss).buttonStyle(GameButtonStyle(tint: tint))
        }
        .padding(22)
        .frame(width: 360)
        .background(PanelBackground(corner: 16).opacity(0.97))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.5)))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
    }
}

struct AchievementToastView: View {
    let achievement: AchievementDefinition
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: achievement.icon).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.gold)
                .frame(width: 38, height: 38).background(Circle().fill(Theme.gold.opacity(0.2)))
            VStack(alignment: .leading, spacing: 1) {
                Text("ACHIEVEMENT UNLOCKED").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(1.5).foregroundStyle(Theme.gold)
                Text(achievement.name).font(Theme.display(17)).foregroundStyle(Theme.text)
                Text(achievement.summary).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: 320, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.gold.opacity(0.6)))
    }
}
