// TEMPORARY ART — towers are a static base (material evolves with level) plus
// a rotating "head" (weapon) drawn facing +x.

import CoreGraphics
import EvolutionDefenseCore

enum TowerArt {
    static let size = CGSize(width: 68, height: 68)

    static func accent(_ a: TowerArchetype) -> UInt32 {
        switch a {
        case .splash: 0xF08A24
        case .sniper: 0x5DBB4F
        case .heavy: 0xD9473B
        case .rapid: 0x3E9BE0
        }
    }

    // MARK: Base platform

    static func drawBase(_ ctx: CGContext, archetype: TowerArchetype, level: Int) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r: CGFloat = 28
        ctx.softShadow(CGPoint(x: c.x + 3, y: c.y - 4), r, r * 0.95, alpha: 0.35)
        var rng = ArtRandom(UInt64(level * 31 + archetype.rawValue.count))

        switch level {
        case 1: // Wood platform ringed with field stones
            for i in 0..<12 {
                let a = CGFloat(i) / 12 * 2 * .pi + 0.2
                let p = CGPoint(x: c.x + cos(a) * r * 0.86, y: c.y + sin(a) * r * 0.86)
                ctx.shadedEllipse(p, r * 0.2, r * 0.17, base: mix(0x8C8A82, 0x6E6C66, rng.next()), light: 0xC9C6BC)
            }
            ctx.fillCircle(c, r * 0.72, rgb(0x6B4423))
            for i in -2...2 {
                let y = c.y + CGFloat(i) * r * 0.27
                let half = sqrt(max(0, (r * 0.7) * (r * 0.7) - (y - c.y) * (y - c.y)))
                ctx.fillRoundedRect(CGRect(x: c.x - half, y: y - r * 0.12, width: half * 2, height: r * 0.24),
                                    radius: 2, rgb(mix(0x9A6A3C, 0x87592F, CGFloat(i + 2) / 4)))
            }
        case 2: // Stone fortification
            ctx.fillPolygon(octagon(c, r), rgb(0x6F6B66))
            ctx.fillPolygon(octagon(c, r * 0.84), rgb(0x9C978F))
            ctx.setStrokeColor(rgb(0x6F6B66, 0.7)); ctx.setLineWidth(1)
            for i in 0..<8 { let a = CGFloat(i) / 8 * 2 * .pi + .pi / 8
                ctx.strokeLine(CGPoint(x: c.x + cos(a) * r * 0.5, y: c.y + sin(a) * r * 0.5),
                               CGPoint(x: c.x + cos(a) * r * 0.84, y: c.y + sin(a) * r * 0.84), rgb(0x6F6B66), width: 1) }
            ctx.fillCircle(c, r * 0.5, rgb(0x857F77))
        case 3: // Riveted steel
            ctx.fillCircle(c, r, rgb(0x3D4248))
            ctx.shadedEllipse(c, r * 0.88, r * 0.88, base: 0x5D646C, light: 0x9AA3AD)
            for i in 0..<10 { let a = CGFloat(i) / 10 * 2 * .pi
                ctx.fillCircle(CGPoint(x: c.x + cos(a) * r * 0.76, y: c.y + sin(a) * r * 0.76), 1.6, rgb(0x2C3035)) }
        case 4: // Heavy steel, hazard ring
            ctx.fillCircle(c, r, rgb(0x2A2D31))
            for i in 0..<16 { let a0 = CGFloat(i) / 16 * 2 * .pi
                ctx.setFillColor(rgb(i % 2 == 0 ? 0xE8B92E : 0x1F1F1F))
                ctx.beginPath(); ctx.move(to: c)
                ctx.addArc(center: c, radius: r * 0.95, startAngle: a0, endAngle: a0 + .pi / 8, clockwise: false)
                ctx.closePath(); ctx.fillPath() }
            ctx.shadedEllipse(c, r * 0.78, r * 0.78, base: 0x4B5158, light: 0x8D96A0)
        default: // Futuristic alloy
            ctx.fillPolygon(hexagon(c, r), rgb(0x1E2A36))
            ctx.fillPolygon(hexagon(c, r * 0.88), rgb(0xDCE6EE))
            ctx.radialGlow(c, r * 0.95, 0x3FE0FF, alpha: 0.35)
            ctx.setStrokeColor(rgb(0x3FE0FF)); ctx.setLineWidth(2)
            ctx.addPath(pathOf(hexagon(c, r * 0.7))); ctx.strokePath()
        }
        // Archetype accent markers so towers are identifiable at a glance.
        for i in 0..<4 {
            let a = CGFloat(i) / 4 * 2 * .pi + .pi / 4
            ctx.fillCircle(CGPoint(x: c.x + cos(a) * r * 0.92, y: c.y + sin(a) * r * 0.92), 3.2, rgb(0x1A1A1A, 0.6))
            ctx.fillCircle(CGPoint(x: c.x + cos(a) * r * 0.92, y: c.y + sin(a) * r * 0.92), 2.4, rgb(accent(archetype)))
        }
    }

    // MARK: Weapon heads — one design per archetype per level (L1 primitive → L5 futuristic)

    static func drawHead(_ ctx: CGContext, archetype: TowerArchetype, level: Int) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        switch (archetype, level) {
        case (.splash, ...1): stoneThrower(ctx, c)
        case (.splash, 2): TowerHeadsEvolved.catapult(ctx, c)
        case (.splash, 3): TowerHeadsEvolved.cannon(ctx, c)
        case (.splash, 4): TowerHeadsEvolved.heavyArtillery(ctx, c)
        case (.splash, _): TowerHeadsEvolved.plasmaArtillery(ctx, c)
        case (.sniper, ...1): scoutArcher(ctx, c)
        case (.sniper, 2): TowerHeadsEvolved.longbowArcher(ctx, c)
        case (.sniper, 3): TowerHeadsEvolved.crossbowSniper(ctx, c)
        case (.sniper, 4): TowerHeadsEvolved.precisionRifle(ctx, c)
        case (.sniper, _): TowerHeadsEvolved.railgun(ctx, c)
        case (.heavy, ...1): spearThrower(ctx, c)
        case (.heavy, 2): TowerHeadsEvolved.ballista(ctx, c)
        case (.heavy, 3): TowerHeadsEvolved.heavyCannon(ctx, c)
        case (.heavy, 4): TowerHeadsEvolved.rocketLauncher(ctx, c)
        case (.heavy, _): TowerHeadsEvolved.orbitalUplink(ctx, c)
        case (.rapid, ...1): slingTower(ctx, c)
        case (.rapid, 2): TowerHeadsEvolved.multiArcher(ctx, c)
        case (.rapid, 3): TowerHeadsEvolved.repeatingCrossbow(ctx, c)
        case (.rapid, 4): TowerHeadsEvolved.machineGun(ctx, c)
        case (.rapid, _): TowerHeadsEvolved.laserGatling(ctx, c)
        }
    }

    /// Wooden throwing frame with a sling cup holding a stone.
    private static func stoneThrower(_ ctx: CGContext, _ c: CGPoint) {
        // Side beams
        for side: CGFloat in [-1, 1] {
            ctx.fillRoundedRect(CGRect(x: c.x - 15, y: c.y + side * 9 - 3, width: 28, height: 6), radius: 2, rgb(0x5E3B1E))
            ctx.fillRoundedRect(CGRect(x: c.x - 14, y: c.y + side * 9 - 2, width: 26, height: 3), radius: 1.5, rgb(0x8B5E34))
        }
        // Axle
        ctx.fillRoundedRect(CGRect(x: c.x - 3, y: c.y - 12, width: 6, height: 24), radius: 2, rgb(0x4A2E16))
        // Counterweight (lashed rock)
        ctx.shadedEllipse(CGPoint(x: c.x - 14, y: c.y), 8, 7, base: 0x6E6A62, light: 0xB8B2A6)
        ctx.strokeLine(CGPoint(x: c.x - 14, y: c.y - 7), CGPoint(x: c.x - 14, y: c.y + 7), rgb(0xC9A66B), width: 1.5)
        // Throwing arm
        ctx.fillRoundedRect(CGRect(x: c.x - 8, y: c.y - 2.5, width: 30, height: 5), radius: 2.5, rgb(0x7A4E27))
        // Sling cup + stone
        ctx.fillEllipse(CGPoint(x: c.x + 22, y: c.y), 7, 7.5, rgb(0x6B4A2B))
        ctx.shadedEllipse(CGPoint(x: c.x + 22, y: c.y), 5, 5, base: 0x7D7A73, light: 0xD5D0C6)
    }

    /// Hooded archer seen from above, bow drawn.
    private static func scoutArcher(_ ctx: CGContext, _ c: CGPoint) {
        // Quiver
        ctx.fillRoundedRect(CGRect(x: c.x - 15, y: c.y + 2, width: 12, height: 5), radius: 2, rgb(0x6B4423))
        for i in 0..<3 { ctx.strokeLine(CGPoint(x: c.x - 16, y: c.y + 3 + CGFloat(i) * 1.6),
                                        CGPoint(x: c.x - 20, y: c.y + 3 + CGFloat(i) * 1.6), rgb(0xEDE6D6), width: 1.2) }
        // Shoulders / cloak
        ctx.shadedEllipse(c, 8, 12, base: 0x3F6B35, light: 0x7FB06A)
        // Arms reaching to bow
        ctx.strokeLine(CGPoint(x: c.x + 2, y: c.y + 8), CGPoint(x: c.x + 14, y: c.y + 2), rgb(0xC69C72), width: 3)
        ctx.strokeLine(CGPoint(x: c.x + 2, y: c.y - 8), CGPoint(x: c.x + 6, y: c.y - 1), rgb(0xC69C72), width: 3)
        // Bow
        ctx.setStrokeColor(rgb(0x5A3A1C)); ctx.setLineWidth(2.6)
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: c.x + 6, y: c.y), radius: 13, startAngle: -1.05, endAngle: 1.05, clockwise: false)
        ctx.strokePath()
        ctx.strokeLine(CGPoint(x: c.x + 6 + 13 * cos(1.05), y: c.y + 13 * sin(1.05)),
                       CGPoint(x: c.x + 6 + 13 * cos(1.05), y: c.y - 13 * sin(1.05)), rgb(0xEDE6D6, 0.8), width: 0.8)
        // Nocked arrow
        ctx.strokeLine(CGPoint(x: c.x + 4, y: c.y), CGPoint(x: c.x + 24, y: c.y), rgb(0x8B6A45), width: 1.6)
        ctx.fillPolygon([CGPoint(x: c.x + 27, y: c.y), CGPoint(x: c.x + 23, y: c.y + 2.2), CGPoint(x: c.x + 23, y: c.y - 2.2)], rgb(0x9A9A9A))
        // Hooded head
        ctx.shadedEllipse(CGPoint(x: c.x - 1, y: c.y), 6.5, 6.5, base: 0x2F5229, light: 0x5E8D50)
    }

    /// Strong hunter with a long stone-tipped spear, spare spears on the back.
    private static func spearThrower(_ ctx: CGContext, _ c: CGPoint) {
        // Spare spears
        for i in 0..<3 {
            let y = c.y - 6 + CGFloat(i) * 2.5
            ctx.strokeLine(CGPoint(x: c.x - 22, y: y), CGPoint(x: c.x - 4, y: y + 1), rgb(0x7A5530), width: 1.8)
        }
        // Body (fur tunic)
        ctx.shadedEllipse(c, 9.5, 13, base: 0x7A4B2A, light: 0xB07A4E)
        ctx.fillEllipse(CGPoint(x: c.x - 2, y: c.y), 5, 10, rgb(0x5C381E, 0.6))
        // Throwing arm + spear
        ctx.strokeLine(CGPoint(x: c.x, y: c.y + 9), CGPoint(x: c.x + 8, y: c.y + 4), rgb(0xC69C72), width: 4)
        ctx.strokeLine(CGPoint(x: c.x - 10, y: c.y + 4), CGPoint(x: c.x + 26, y: c.y + 4), rgb(0x8A6036), width: 2.6)
        ctx.fillPolygon([CGPoint(x: c.x + 32, y: c.y + 4), CGPoint(x: c.x + 25, y: c.y + 7.5),
                         CGPoint(x: c.x + 25, y: c.y + 0.5)], rgb(0x55534E))
        ctx.fillPolygon([CGPoint(x: c.x + 30, y: c.y + 4), CGPoint(x: c.x + 26, y: c.y + 6),
                         CGPoint(x: c.x + 26, y: c.y + 2)], rgb(0x8E8B83))
        // Head with hair
        ctx.shadedEllipse(CGPoint(x: c.x + 1, y: c.y - 1), 6.5, 6.5, base: 0x3A2414, light: 0x6B4A30)
        ctx.fillCircle(CGPoint(x: c.x + 4, y: c.y - 1), 2.6, rgb(0xC69C72))
    }

    /// Slinger whirling a sling, pebble pouch at the hip.
    private static func slingTower(_ ctx: CGContext, _ c: CGPoint) {
        // Pebble pile
        var rng = ArtRandom(7)
        for _ in 0..<6 { ctx.shadedEllipse(CGPoint(x: c.x - 14 + rng.range(-4, 4), y: c.y - 10 + rng.range(-3, 3)),
                                           2.4, 2.2, base: 0x6E6A62, light: 0xBDB7AB) }
        // Body
        ctx.shadedEllipse(c, 8, 11.5, base: 0x46607A, light: 0x8BA7C2)
        // Sling whirl (motion arc)
        ctx.setStrokeColor(rgb(0xF3EAD3, 0.55)); ctx.setLineWidth(1.4)
        ctx.beginPath(); ctx.addArc(center: CGPoint(x: c.x + 8, y: c.y + 4), radius: 13, startAngle: -0.4, endAngle: 2.2, clockwise: false); ctx.strokePath()
        // Arm & sling strap
        ctx.strokeLine(CGPoint(x: c.x + 1, y: c.y + 8), CGPoint(x: c.x + 10, y: c.y + 6), rgb(0xC69C72), width: 3)
        ctx.strokeLine(CGPoint(x: c.x + 10, y: c.y + 6), CGPoint(x: c.x + 21, y: c.y + 1), rgb(0x8A6036), width: 1.4)
        ctx.shadedEllipse(CGPoint(x: c.x + 21.5, y: c.y + 0.5), 3, 3, base: 0x5B5852, light: 0xBDB7AB)
        // Head with headband
        ctx.shadedEllipse(CGPoint(x: c.x, y: c.y), 6.2, 6.2, base: 0x4A2F1A, light: 0x7A5638)
        ctx.strokeLine(CGPoint(x: c.x - 3, y: c.y - 5.6), CGPoint(x: c.x - 3, y: c.y + 5.6), rgb(0xC0392B), width: 1.6)
    }

    // MARK: Shapes

    static func octagon(_ c: CGPoint, _ r: CGFloat) -> [CGPoint] {
        (0..<8).map { i in let a = CGFloat(i) / 8 * 2 * .pi + .pi / 8
            return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r) }
    }

    static func hexagon(_ c: CGPoint, _ r: CGFloat) -> [CGPoint] {
        (0..<6).map { i in let a = CGFloat(i) / 6 * 2 * .pi
            return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r) }
    }

    static func pathOf(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath(); return p
    }
}

// MARK: - Projectiles

enum ProjectileArt {
    enum Shape { case ball, streak, arrow, spear, rocket }

    struct Spec {
        var shape: Shape
        var length: CGFloat
        var width: CGFloat
        var color: UInt32
        var glow: UInt32?
        /// Whether it flies in an arc (lobbed) – rendered with height + shadow.
        var lobbed: Bool
    }

    static func spec(_ k: ProjectileKind) -> Spec {
        switch k {
        case .stone: Spec(shape: .ball, length: 9, width: 9, color: 0x77736B, glow: nil, lobbed: true)
        case .boulder: Spec(shape: .ball, length: 12, width: 12, color: 0x6B665E, glow: nil, lobbed: true)
        case .cannonball: Spec(shape: .ball, length: 9, width: 9, color: 0x24262A, glow: nil, lobbed: true)
        case .shell: Spec(shape: .rocket, length: 13, width: 6, color: 0x3C4148, glow: nil, lobbed: true)
        case .plasmaOrb: Spec(shape: .ball, length: 12, width: 12, color: 0x9FF6FF, glow: 0x2FD8FF, lobbed: true)
        case .arrow: Spec(shape: .arrow, length: 20, width: 4, color: 0x8B6A45, glow: nil, lobbed: false)
        case .longArrow: Spec(shape: .arrow, length: 25, width: 4, color: 0x7A5A38, glow: nil, lobbed: false)
        case .bolt: Spec(shape: .arrow, length: 15, width: 5, color: 0x4A3A2A, glow: nil, lobbed: false)
        case .bullet: Spec(shape: .streak, length: 12, width: 2.5, color: 0xFFE08A, glow: 0xFFB020, lobbed: false)
        case .railSlug: Spec(shape: .streak, length: 30, width: 3, color: 0xCFF4FF, glow: 0x3FA9FF, lobbed: false)
        case .spear: Spec(shape: .spear, length: 32, width: 5, color: 0x8A6036, glow: nil, lobbed: false)
        case .ballistaBolt: Spec(shape: .spear, length: 34, width: 6, color: 0x5E4128, glow: nil, lobbed: false)
        case .heavyShell: Spec(shape: .rocket, length: 15, width: 7, color: 0x2C3035, glow: nil, lobbed: false)
        case .rocket: Spec(shape: .rocket, length: 18, width: 6, color: 0xC9CED4, glow: 0xFF8A2A, lobbed: false)
        case .orbitalBeam: Spec(shape: .streak, length: 34, width: 7, color: 0xE6FDFF, glow: 0x3FE0FF, lobbed: false)
        case .pellet: Spec(shape: .ball, length: 5, width: 5, color: 0x55524C, glow: nil, lobbed: false)
        case .laser: Spec(shape: .streak, length: 22, width: 3, color: 0xFFD6D6, glow: 0xFF2D2D, lobbed: false)
        }
    }

    static func canvas(_ s: Spec) -> CGSize {
        let pad: CGFloat = s.glow != nil ? 8 : 3
        return CGSize(width: s.length + pad * 2, height: max(s.width, 4) + pad * 2)
    }

    static func draw(_ ctx: CGContext, _ s: Spec) {
        let size = canvas(s)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let half = s.length / 2
        if let g = s.glow { ctx.radialGlow(c, max(s.length, s.width) * 0.75, g, alpha: 0.75) }
        switch s.shape {
        case .ball:
            ctx.shadedEllipse(c, s.width / 2, s.width / 2, base: s.color, light: mix(s.color, 0xFFFFFF, 0.6))
        case .streak:
            ctx.strokeLine(CGPoint(x: c.x - half, y: c.y), CGPoint(x: c.x + half, y: c.y), rgb(s.color), width: s.width)
        case .arrow:
            ctx.strokeLine(CGPoint(x: c.x - half, y: c.y), CGPoint(x: c.x + half - 3, y: c.y), rgb(s.color), width: 1.6)
            ctx.fillPolygon([CGPoint(x: c.x + half, y: c.y), CGPoint(x: c.x + half - 5, y: c.y + s.width / 2),
                             CGPoint(x: c.x + half - 5, y: c.y - s.width / 2)], rgb(0x9C9C9C))
            ctx.fillPolygon([CGPoint(x: c.x - half, y: c.y), CGPoint(x: c.x - half + 5, y: c.y + s.width / 2),
                             CGPoint(x: c.x - half + 6, y: c.y), CGPoint(x: c.x - half + 5, y: c.y - s.width / 2)], rgb(0xEDE6D6))
        case .spear:
            ctx.strokeLine(CGPoint(x: c.x - half, y: c.y), CGPoint(x: c.x + half - 6, y: c.y), rgb(s.color), width: 2.4)
            ctx.fillPolygon([CGPoint(x: c.x + half, y: c.y), CGPoint(x: c.x + half - 8, y: c.y + s.width / 2),
                             CGPoint(x: c.x + half - 8, y: c.y - s.width / 2)], rgb(0x6A6760))
        case .rocket:
            if s.glow != nil {
                ctx.fillEllipse(CGPoint(x: c.x - half, y: c.y), 4, s.width * 0.4, rgb(0xFFB347))
            }
            ctx.fillRoundedRect(CGRect(x: c.x - half, y: c.y - s.width / 2, width: s.length, height: s.width),
                                radius: s.width / 2, rgb(s.color))
            ctx.fillEllipse(CGPoint(x: c.x + half - s.width / 2, y: c.y), s.width / 2, s.width / 2, rgb(mix(s.color, 0xFFFFFF, 0.3)))
        }
    }
}
