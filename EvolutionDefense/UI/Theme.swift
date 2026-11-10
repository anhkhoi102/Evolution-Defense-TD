import EvolutionDefenseCore
import CoreText
import SwiftUI

enum Theme {
    static let panel = Color(red: 0.10, green: 0.11, blue: 0.13)
    static let panelHigh = Color(red: 0.15, green: 0.16, blue: 0.19)
    static let stroke = Color.white.opacity(0.09)
    static let text = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let textDim = Color(red: 0.94, green: 0.93, blue: 0.90).opacity(0.6)
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.27)
    static let research = Color(red: 0.36, green: 0.82, blue: 0.95)
    static let danger = Color(red: 0.94, green: 0.33, blue: 0.29)
    static let good = Color(red: 0.42, green: 0.82, blue: 0.36)
    static let warn = Color(red: 0.98, green: 0.72, blue: 0.22)

    static func accent(_ a: TowerArchetype) -> Color {
        switch a {
        case .splash: Color(red: 0.94, green: 0.54, blue: 0.14)
        case .sniper: Color(red: 0.37, green: 0.73, blue: 0.31)
        case .heavy: Color(red: 0.85, green: 0.28, blue: 0.23)
        case .rapid: Color(red: 0.24, green: 0.61, blue: 0.88)
        }
    }

    static func color(for status: BaseStatus) -> Color {
        switch status {
        case .normal: good
        case .warning: warn
        case .critical: Color(red: 0.96, green: 0.48, blue: 0.2)
        case .emergency, .destroyed: danger
        }
    }

    static func eraIcon(_ e: Era) -> String {
        switch e {
        case .primitive: "flame.fill"
        case .medieval: "shield.lefthalf.filled"
        case .industrial: "gearshape.2.fill"
        case .futuristic: "cpu.fill"
        }
    }

    static func eraColor(_ e: Era) -> Color {
        switch e {
        case .primitive: Color(red: 0.80, green: 0.55, blue: 0.30)
        case .medieval: Color(red: 0.62, green: 0.66, blue: 0.75)
        case .industrial: Color(red: 0.85, green: 0.62, blue: 0.25)
        case .futuristic: Color(red: 0.30, green: 0.85, blue: 1.0)
        }
    }

    static func hotkey(_ a: TowerArchetype) -> String {
        switch a {
        case .splash: "1"
        case .sniper: "2"
        case .heavy: "3"
        case .rapid: "4"
        }
    }
}

extension Theme {
    /// Display face for titles, numbers and buttons (Lilita One, SIL OFL 1.1).
    static func display(_ size: CGFloat) -> Font { .custom("LilitaOne", size: size) }

    /// Registers the bundled fonts once at launch (no Info.plist entry needed).
    static func registerFonts() {
        for name in ["LilitaOne-Regular"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

/// 9-slice image from the UI skin (Kenney UI Pack – Adventure, CC0).
struct SkinImage: View {
    let name: String
    var inset: CGFloat = 22
    var body: some View {
        Image(name)
            .resizable(capInsets: EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset), resizingMode: .stretch)
    }
}

/// Panel used across the HUD and menus: dark translucent fill (readable text)
/// inside the carved-wood frame of the UI skin.
struct PanelBackground: View {
    var corner: CGFloat = 10
    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.14, blue: 0.12), Color(red: 0.10, green: 0.09, blue: 0.08)],
                                 startPoint: .top, endPoint: .bottom))
            .padding(3)
            .overlay(SkinImage(name: "ui_panel_frame", inset: 20).opacity(0.95))
    }
}

struct KeyCap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.textDim.opacity(0.6)))
    }
}

struct GameButtonStyle: ButtonStyle {
    var tint: Color = Theme.gold
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        GameButtonBody(configuration: configuration, tint: tint, prominent: prominent)
    }
}

/// The button's look and feedback: lifts and brightens on hover, sinks when
/// pressed, and greys out when disabled.
private struct GameButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        // Skin: parchment button (primary), stone-grey (secondary), red (danger).
        let skin = !prominent ? "ui_button_secondary" : (tint == Theme.danger ? "ui_button_danger" : "ui_button_primary")
        let pressed = configuration.isPressed
        let lifted = hovering && isEnabled && !pressed
        configuration.label
            .font(Theme.display(17))
            .foregroundStyle(prominent && tint != Theme.danger ? Color(red: 0.24, green: 0.15, blue: 0.08) : Color.white)
            .shadow(color: .black.opacity(prominent && tint != Theme.danger ? 0 : 0.35), radius: 0, y: 1)
            .padding(.horizontal, 20).padding(.vertical, 11)
            .background(SkinImage(name: skin, inset: 14))
            .brightness(pressed ? -0.08 : lifted ? 0.07 : 0)
            .scaleEffect(pressed ? 0.96 : lifted ? 1.03 : 1)
            .shadow(color: .black.opacity(lifted ? 0.45 : 0.25), radius: lifted ? 8 : 3, y: lifted ? 4 : 2)
            .saturation(isEnabled ? 1 : 0.1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .onHover { hovering = $0 }
    }
}

/// Hover and press feedback for custom (card-like) buttons: a slight lift on
/// hover and a dip when pressed. Use with `.buttonStyle(CardButtonStyle())`.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { CardButtonBody(configuration: configuration) }
}

private struct CardButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        let lifted = hovering && isEnabled && !pressed
        configuration.label
            .brightness(pressed ? -0.05 : lifted ? 0.05 : 0)
            .scaleEffect(pressed ? 0.98 : lifted ? 1.02 : 1)
            .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 10, y: 5)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .onHover { hovering = $0 }
    }
}

/// One to three stars for a match rating. With `animated`, earned stars pop in one after another.
struct StarRow: View {
    let stars: Int
    var size: CGFloat = 16
    var animated = false
    @State private var shown = 0

    var body: some View {
        HStack(spacing: size * 0.12) {
            ForEach(0..<StarRatingConfig.maxStars, id: \.self) { i in
                let earned = i < stars
                let visible = earned && (!animated || i < shown)
                Image(systemName: visible ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(visible ? Theme.gold : Theme.textDim.opacity(0.45))
                    .shadow(color: visible ? Theme.gold.opacity(0.6) : .clear, radius: size * 0.25)
                    .scaleEffect(visible || !animated || !earned ? 1 : 0.4)
            }
        }
        .onAppear {
            guard animated else { return }
            for i in 0..<stars {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.45).delay(0.3 + Double(i) * 0.25)) { shown = i + 1 }
            }
        }
        .accessibilityLabel("\(stars) of \(StarRatingConfig.maxStars) stars")
    }
}
