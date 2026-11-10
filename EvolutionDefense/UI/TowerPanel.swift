import EvolutionDefenseCore
import SwiftUI

/// Bottom panel: build cards, selection details, next-wave button.
struct BottomPanel: View {
    @Bindable var controller: GameController

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(TowerArchetype.allCases) { a in
                    TowerCard(archetype: a, controller: controller)
                }
            }
            InfoPanel(controller: controller)
                .frame(maxWidth: .infinity)
            ForEach(controller.abilities) { ab in
                AbilityButton(ability: ab, selected: controller.summonSelection == ab.id) { controller.selectSummon(ab.id) }
            }
            TechButton(controller: controller)
            NextWaveButton(controller: controller)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(height: 132)
        .background(
            LinearGradient(colors: [Theme.panel, Color(red: 0.07, green: 0.08, blue: 0.09)], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1) }
        )
    }
}

private struct TowerCard: View {
    let archetype: TowerArchetype
    let controller: GameController

    var body: some View {
        let def = controller.config.tower(archetype)
        let cost = def.buildCost
        let affordable = controller.gold >= cost
        let selected = controller.buildSelection == archetype
        let accent = Theme.accent(archetype)

        Button { controller.selectBuild(archetype) } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: NSImage(cgImage: ArtLibrary.shared.towerIcon(controller.config.tower(archetype), level: 1),
                                           size: NSSize(width: 68, height: 68)))
                        .resizable().interpolation(.high)
                        .frame(width: 54, height: 54)
                        .saturation(affordable ? 1 : 0.2)
                    KeyCap(key: Theme.hotkey(archetype)).offset(x: 14, y: -2)
                }
                Text(def.displayName.replacingOccurrences(of: " Tower", with: ""))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "circle.hexagongrid.circle.fill").font(.system(size: 10))
                    Text("\(cost)").font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(affordable ? Theme.gold : Theme.danger)
            }
            .frame(width: 92, height: 108)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? accent.opacity(0.28) : Theme.panelHigh)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? accent : Theme.stroke, lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .top) {
                Capsule().fill(accent).frame(width: 28, height: 3).padding(.top, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controller.isOver)
        .help("\(def.displayName) — \(def.role)")
        .accessibilityLabel("Build \(def.displayName), costs \(cost) gold")
    }
}

private struct InfoPanel: View {
    let controller: GameController

    var body: some View {
        Group {
            if let t = controller.selectedTower {
                SelectedTowerInfo(tower: t, controller: controller)
            } else if let a = controller.buildSelection {
                BuildPreviewInfo(archetype: a, controller: controller)
            } else if controller.showSummary, controller.phase == .preparation, let summary = controller.lastSummary {
                WaveSummaryInfo(summary: summary, controller: controller)
            } else if controller.isOver {
                Text(controller.phase == .victory ? "Every era survived." : "The base has fallen.")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.textDim)
            } else if controller.waveNumber == 0 && controller.phase == .preparation {
                HintInfo(controller: controller)
            } else {
                WaveIntelInfo(controller: controller)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelBackground(corner: 12))
    }
}

private struct HintInfo: View {
    let controller: GameController
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Defend the village").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
            Text("Choose a tower (1–4), then click a stone pad next to the path. Click a tower to upgrade, sell or retarget it — the wave countdown waits while you do.")
                .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                shortcut("N", "Next wave"); shortcut("U", "Upgrade"); shortcut("R", "Repair"); shortcut("T", "Tech")
                shortcut("Space", "Pause"); shortcut("F", "Speed"); shortcut("Esc", "Cancel")
            }
            IntelStrip(intel: controller.waveIntel, label: "Wave 1:")
        }
    }

    private func shortcut(_ k: String, _ label: String) -> some View {
        HStack(spacing: 4) { KeyCap(key: k); Text(label).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim) }
    }
}

private struct StatCell: View {
    let label: String
    let value: String
    var next: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Theme.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.display(16)).monospacedDigit().foregroundStyle(Theme.text)
                    .fixedSize()          // never "0.6…": the number is the point
                if let next, next != value {
                    Text("→ \(next)").font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.good)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .frame(minWidth: 54, alignment: .leading)
    }
}

/// Up to two decimals, trailing zeros trimmed (0.65 → "0.65", 4.5 → "4.5", 12 → "12").
private func fmt(_ v: Double) -> String {
    if v == v.rounded() { return String(Int(v)) }
    var t = String(format: "%.2f", v)
    while t.hasSuffix("0") { t.removeLast() }
    return t
}

private func specials(aoe: Double, pen: Double, air: Bool, type: DamageType = .physical,
                      stealth: Bool = false, effects: [String] = []) -> [String] {
    var s: [String] = [type.displayName]
    if aoe > 0 { s.append("Blast \(fmt(aoe))") }
    if pen > 0 { s.append("Pierce \(fmt1(pen))") }
    s.append(air ? "Hits air" : "Ground only")
    if stealth { s.append("Detects stealth") }
    return s + effects
}

private struct SelectedTowerInfo: View {
    let tower: TowerSnapshot
    let controller: GameController

    var body: some View {
        let accent = Theme.accent(tower.archetype)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 8, height: 8)
                    Text(tower.name).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                    LevelPips(level: tower.level, maxLevel: tower.maxLevel, tint: accent)
                    Text(tower.typeName).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
                }
                HStack(spacing: 12) {
                    StatCell(label: "Damage", value: fmt1(tower.current.damage), next: tower.next.map { fmt1($0.damage) })
                    StatCell(label: "Rate", value: "\(fmt(tower.current.attacksPerSecond))/s", next: tower.next.map { "\(fmt($0.attacksPerSecond))/s" })
                    StatCell(label: "Range", value: fmt1(tower.current.range), next: tower.next.map { fmt1($0.range) })
                    StatCell(label: "DPS", value: fmt1(tower.current.dps), next: tower.next.map { fmt1($0.dps) })
                }
                Text(specials(aoe: tower.current.aoeRadius, pen: tower.current.armorPenetration, air: tower.current.canTargetAir,
                              type: tower.current.damageType, stealth: tower.current.detectsStealth,
                              effects: tower.current.effects).joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(accent)
                    .lineLimit(1).truncationMode(.tail)
                if tower.brokenDown {
                    Label("Mechanical breakdown — 50% slower this wave", systemImage: "wrench.and.screwdriver.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.warn)
                }
                if tower.disabled {
                    Label("Knocked out — recovering", systemImage: "bolt.slash.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.research)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Target").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textDim)
                    Picker("Target", selection: Binding(get: { tower.targeting }, set: { controller.setTargeting($0) })) {
                        ForEach(TargetingPriority.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 118)
                }
                Text("Kills \(tower.kills) · Damage \(tower.damageDealt)")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim).monospacedDigit()
                Spacer(minLength: 0)
                if tower.isTemporary {
                    Label("Allied reinforcement · leaves after this wave", systemImage: "person.3.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.good)
                        .padding(.horizontal, 10).frame(minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.good.opacity(0.5)))
                } else {
                    HStack(spacing: 6) {
                        sellButton
                        upgradeButton
                    }
                }
            }
        }
    }

    @ViewBuilder private var upgradeButton: some View {
        if let cost = tower.upgradeCost, let next = tower.next {
            let affordable = controller.gold >= cost
            Button { controller.upgradeSelected() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Evolve: \(next.name)").font(.system(size: 11, weight: .heavy, design: .rounded)).lineLimit(1)
                        HStack(spacing: 3) {
                            Image(systemName: "circle.hexagongrid.circle.fill").font(.system(size: 9))
                            Text("\(cost)").font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit()
                        }
                        .foregroundStyle(affordable ? Color.black.opacity(0.75) : Theme.danger)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .frame(minWidth: 170, alignment: .leading)
                .foregroundStyle(affordable ? Color.black.opacity(0.85) : Theme.textDim)
                .background(RoundedRectangle(cornerRadius: 9).fill(affordable ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Theme.panelHigh)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(affordable ? Color.white.opacity(0.25) : Theme.danger.opacity(0.5)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(affordable ? "Upgrade to \(next.name) (U)" : "Not enough gold")
        } else {
            Text("FULLY EVOLVED")
                .font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                .padding(.horizontal, 10).frame(minWidth: 170, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.gold.opacity(0.5)))
        }
    }

    private var sellButton: some View {
        let armed = controller.sellArmedFor == tower.id
        return Button { controller.sellSelected() } label: {
            VStack(spacing: 0) {
                Text(armed ? "Confirm?" : "Sell").font(.system(size: 11, weight: .heavy, design: .rounded))
                Text("+\(tower.sellValue)").font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .foregroundStyle(armed ? Color.white : Theme.text)
            .frame(width: 70, height: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(armed ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.panelHigh)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.danger.opacity(armed ? 0.9 : 0.4)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sell for \(tower.sellValue) gold (press twice, or Delete twice)")
    }
}

private struct LevelPips: View {
    let level: Int
    let maxLevel: Int
    let tint: Color
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...max(1, maxLevel), id: \.self) { i in
                Circle().fill(i <= level ? Theme.gold : Color.white.opacity(0.15)).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.18)))
        .accessibilityLabel("Level \(level) of \(maxLevel)")
    }
}

private func fmt1(_ v: Double) -> String { fmt((v * 10).rounded() / 10) }

/// Wave completion report, shown in the info panel during the preparation phase.
private struct WaveSummaryInfo: View {
    let summary: WaveSummary
    let controller: GameController

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: summary.isPerfect ? "star.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(summary.isPerfect ? Theme.gold : Theme.good)
                    Text("WAVE \(summary.number) CLEARED")
                        .font(Theme.display(17)).foregroundStyle(Theme.text)
                    if summary.isPerfect {
                        Text("PERFECT").font(.system(size: 9, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.gold.opacity(0.25))).foregroundStyle(Theme.gold)
                    }
                }
                Text(defeatedLine).font(.system(size: 12, design: .rounded))
                    .foregroundStyle(summary.enemiesLeaked > 0 ? Theme.danger : Theme.textDim)
                IntelStrip(intel: controller.waveIntel,
                           label: controller.countdownHeld ? "Next (paused):" : "Next in \(controller.countdownSeconds)s:", compact: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                chip("Kills", summary.killGold)
                chip("Wave clear", summary.clearBonus)
                if summary.perfectBonus > 0 { chip("Perfect", summary.perfectBonus) }
                if summary.earlyStartBonus > 0 { chip("Early start", summary.earlyStartBonus) }
                if summary.researchEarned > 0 {
                    VStack(spacing: 1) {
                        Text("+\(summary.researchEarned)").font(Theme.display(15)).monospacedDigit()
                            .foregroundStyle(Theme.research)
                        Text("RESEARCH").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(Theme.textDim)
                    }
                    .frame(minWidth: 58).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.research.opacity(0.1)))
                }
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text("GOLD EARNED").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Theme.textDim)
                Text("+\(summary.totalGold)").font(Theme.display(26)).monospacedDigit()
                    .foregroundStyle(Theme.gold)
            }
        }
    }

    private var defeatedLine: String {
        var s = "\(summary.enemiesDefeated) enemies defeated"
        if summary.enemiesLeaked > 0 { s += " · \(summary.enemiesLeaked) reached the base (−\(summary.baseDamageTaken) HP)" }
        return s
    }

    private func chip(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("+\(value)").font(Theme.display(15)).monospacedDigit().foregroundStyle(Theme.text)
            Text(label.uppercased()).font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(Theme.textDim)
        }
        .frame(minWidth: 58)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
    }
}

private struct BuildPreviewInfo: View {
    let archetype: TowerArchetype
    let controller: GameController

    var body: some View {
        let def = controller.config.tower(archetype)
        let s = controller.world.effectiveStats(archetype, level: 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(Theme.accent(archetype)).frame(width: 8, height: 8)
                Text("Build \(s.name)").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text("\(def.displayName) · evolves to \(def.levels.last?.name ?? "")")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim)
            }
            Text(def.role).font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.textDim).lineLimit(2)
            HStack(spacing: 12) {
                StatCell(label: "Damage", value: fmt1(s.damage))
                StatCell(label: "Rate", value: "\(fmt(s.attacksPerSecond))/s")
                StatCell(label: "Range", value: fmt(s.range))
                StatCell(label: "Cost", value: "\(s.cost)")
                Text(specials(aoe: s.aoeRadius, pen: s.armorPenetration, air: s.canTargetAir, type: s.type,
                              stealth: s.seesStealth, effects: s.hitEffects.labels).joined(separator: " · "))
                    .lineLimit(1)
                    .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Theme.accent(archetype))
            }
        }
    }
}

private struct NextWaveButton: View {
    let controller: GameController

    var body: some View {
        let next = controller.waveNumber + 1
        let isBoss = controller.nextWave?.isBossWave == true
        let ready = controller.canStartWave
        let tint = isBoss ? Theme.danger : Theme.gold
        Button { controller.startNextWave() } label: {
            VStack(spacing: 3) {
                Image(systemName: ready ? (isBoss ? "crown.fill" : "play.fill") : "hourglass")
                    .font(.system(size: 17, weight: .bold))
                Text(ready ? "START WAVE \(next)" : (controller.isOver ? "MATCH OVER" : "WAVE \(controller.waveNumber)"))
                    .font(Theme.display(16))
                Text(subtitle(ready: ready, isBoss: isBoss))
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).opacity(0.8).monospacedDigit()
                if ready {
                    // Countdown progress bar
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.2))
                            Capsule().fill(Color.black.opacity(0.55))
                                .frame(width: g.size.width * controller.countdownFraction)
                                .animation(.linear(duration: 0.2), value: controller.countdownFraction)
                        }
                    }
                    .frame(width: 110, height: 4)
                }
            }
            .frame(width: 150, height: 108)
            .foregroundStyle(ready ? Color.black.opacity(0.85) : Theme.textDim)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ready ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Theme.panelHigh))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .help(ready ? "Start now for +\(controller.earlyStartBonus) gold (N)" : "")
    }

    private func subtitle(ready: Bool, isBoss: Bool) -> String {
        guard ready else { return controller.isOver ? " " : "in progress" }
        if controller.countdownHeld { return "Countdown paused" }
        let bonus = controller.earlyStartBonus > 0 ? " · +\(controller.earlyStartBonus) gold" : ""
        return (isBoss ? "Boss · " : "") + "in \(controller.countdownSeconds)s" + bonus
    }
}

// MARK: - Wave intel & technology

/// Row of enemy portraits with counts for a wave.
private struct IntelStrip: View {
    let intel: [EnemyIntel]
    var label: String
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textDim)
            ForEach(intel) { e in
                HStack(spacing: 3) {
                    Image(nsImage: NSImage(cgImage: ArtLibrary.shared.enemyIcon(e.definition), size: .zero))
                        .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: compact ? 22 : 26, height: compact ? 18 : 22)
                    Text(e.isBoss ? "BOSS" : "×\(e.count)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(e.isBoss ? Theme.danger : Theme.text)
                    if e.isFlying { Image(systemName: "bird.fill").font(.system(size: 9)).foregroundStyle(Theme.research) }
                }
                .help("\(e.name): " + (e.definition.summary ?? "") + (e.traits.isEmpty ? "" : " (\(e.traits.joined(separator: ", ")))"))
            }
        }
        .lineLimit(1)
    }
}

/// Upcoming (or current) wave with enemy types and their traits.
private struct WaveIntelInfo: View {
    let controller: GameController

    /// What each wave theme asks of the player (tooltip on the theme label).
    static let themeHelp: [String: String] = [
        "Speed": "Fast enemies: cover the path and bring attack speed (Rapid Fire, Sniper).",
        "Swarm": "Huge numbers of weak enemies: area damage (Splash) and Rapid Fire.",
        "Air": "Flying enemies: only Sniper, Rapid Fire and Heavy from level 4 can hit them.",
        "Armored": "Thick armor: armor penetration (Heavy, high-level Sniper) and upgrades.",
        "Tank": "Big HP pools, some protected by healers: focus fire and burn.",
        "Elite": "Elite enemies (gold ring) with an escort: target priorities matter.",
        "Stealth": "Cloaking robots: Sniper from level 4, splash, or AI Targeting.",
        "Mixed": "A bit of everything: a balanced defence holds.",
    ]

    var body: some View {
        let intel = controller.waveIntel
        let inWave = controller.phase == .waveInProgress
        let number = inWave ? controller.waveNumber : controller.waveNumber + 1
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(inWave ? "WAVE \(number)" : "NEXT · WAVE \(number)")
                    .font(Theme.display(15)).foregroundStyle(Theme.text)
                if let era = controller.config.waves[safe: number - 1]?.era {
                    Text(era.displayName).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.eraColor(era))
                }
                if let theme = controller.intelWave?.theme, theme != "Boss", theme != "Learning" {
                    Text("· \(theme) wave").font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                        .help(Self.themeHelp[theme] ?? "")
                }
                Spacer()
                if !inWave {
                    Text(controller.countdownHeld ? "Countdown paused" : "Starts in \(controller.countdownSeconds)s")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textDim).monospacedDigit()
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(intel.prefix(5)) { e in
                    HStack(alignment: .top, spacing: 6) {
                        Image(nsImage: NSImage(cgImage: ArtLibrary.shared.enemyIcon(e.definition), size: .zero))
                            .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .frame(width: 34, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.isBoss ? "\(e.name)" : "\(e.name) ×\(e.count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(e.isBoss ? Theme.danger : Theme.text).lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(e.traits.isEmpty ? (e.definition.category ?? "") : e.traits.prefix(2).joined(separator: " · "))
                                .font(.system(size: 9.5, design: .rounded)).foregroundStyle(Theme.textDim).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: 175, alignment: .leading)
                    .help(e.definition.summary ?? e.name)
                }
            }
        }
    }
}

/// Summon ability (Call Militia / Summon Hero): portrait, radial cooldown,
/// time left while the units are out, unlock wave while locked, hotkey.
private struct AbilityButton: View {
    let ability: AbilitySnapshot
    let selected: Bool
    let action: () -> Void
    @State private var pulse = false

    private var accent: Color { ability.kind == .hero ? Theme.gold : Color(red: 0.45, green: 0.78, blue: 1) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Image(nsImage: NSImage(cgImage: ArtLibrary.shared.summonIcon(ability.ability), size: .zero))
                        .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .saturation(ability.isUnlocked ? 1 : 0)
                        .opacity(ability.isUnlocked ? 1 : 0.45)
                    if ability.isUnlocked && ability.cooldown > 0 {
                        // Radial cooldown: the dark wedge shrinks as the ability recharges.
                        CooldownWedge(fraction: ability.cooldownFraction)
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 46, height: 46)
                        Text("\(Int(ability.cooldown.rounded(.up)))")
                            .font(Theme.display(17)).foregroundStyle(.white)
                            .shadow(color: .black, radius: 2)
                    }
                    if !ability.isUnlocked {
                        Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    }
                }
                .frame(width: 48, height: 46)
                Text(ability.kind == .hero ? "Hero" : "Militia")
                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Group {
                    if !ability.isUnlocked {
                        Text("Wave \(ability.unlockWave)").foregroundStyle(Theme.textDim)
                    } else if ability.aliveUnits > 0 {
                        Text("\(Int(ability.activeRemaining.rounded(.up)))s left").foregroundStyle(accent)
                    } else if ability.cooldown > 0 {
                        Text("Recharging").foregroundStyle(Theme.textDim)
                    } else if ability.isReady {
                        Text("Ready").foregroundStyle(Theme.good)
                    } else {
                        Text("In waves").foregroundStyle(Theme.textDim)
                    }
                }
                .font(.system(size: 10.5, weight: .heavy, design: .rounded)).monospacedDigit()
                KeyCap(key: ability.hotkey ?? "")
            }
            .frame(width: 66, height: 108)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? accent.opacity(0.28) : ability.aliveUnits > 0 ? accent.opacity(0.14) : Theme.panelHigh))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: selected || ability.isReady ? 2 : 1))
            .shadow(color: ability.isReady ? Theme.good.opacity(pulse ? 0.55 : 0.15) : .clear, radius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(ability.name) (\(ability.hotkey ?? "")): \(ability.ability.summary)")
        .onChange(of: ability.isReady) { _, ready in
            // A short glow when the ability becomes available again.
            pulse = false
            if ready { withAnimation(.easeInOut(duration: 0.6).repeatCount(3, autoreverses: true)) { pulse = true } }
        }
    }

    private var borderColor: Color {
        if selected { return accent }
        if ability.isReady { return Theme.good.opacity(0.85) }
        if ability.aliveUnits > 0 { return accent.opacity(0.7) }
        return Theme.stroke
    }
}

/// Pie wedge covering the part of the cooldown still to go (starts at 12 o'clock).
private struct CooldownWedge: Shape {
    var fraction: Double
    var animatableData: Double { get { fraction } set { fraction = newValue } }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addArc(center: c, radius: min(rect.width, rect.height) / 2, startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Opens the technology tree. Glows when something can be researched.
private struct TechButton: View {
    let controller: GameController

    var body: some View {
        let available = controller.techCards.contains { $0.status == .available }
        Button { controller.toggleTechPanel() } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "flask.fill").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.research)
                        .frame(width: 44, height: 34)
                    if available {
                        Circle().fill(Theme.research).frame(width: 9, height: 9).offset(x: 2, y: 0)
                    }
                }
                Text("Tech").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text("\(controller.researchPoints) RP").font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.research)
                KeyCap(key: "T")
            }
            .frame(width: 70, height: 108)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(controller.isTechPanelOpen ? Theme.research.opacity(0.25) : Theme.panelHigh))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(available || controller.isTechPanelOpen ? Theme.research.opacity(0.8) : Theme.stroke,
                              lineWidth: controller.isTechPanelOpen ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controller.isOver)
        .help("Technology tree (T)")
    }
}
