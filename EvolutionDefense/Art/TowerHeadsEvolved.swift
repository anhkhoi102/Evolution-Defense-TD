// TEMPORARY ART — weapon heads for tower levels 2–5, drawn facing +x.
// Materials follow the era progression: wood → iron/bronze → steel → alloy + energy.

import CoreGraphics

enum TowerHeadsEvolved {

    // MARK: Shared parts

    /// A barrel/tube from `x0` (relative to centre) pointing +x.
    static func barrel(_ ctx: CGContext, _ c: CGPoint, x0: CGFloat, length: CGFloat, width w: CGFloat, y: CGFloat = 0,
                       base: UInt32, light: UInt32, muzzle: UInt32? = nil) {
        let r = CGRect(x: c.x + x0, y: c.y + y - w / 2, width: length, height: w)
        ctx.fillRoundedRect(r, radius: w * 0.3, rgb(base))
        ctx.fillRoundedRect(CGRect(x: r.minX + 1, y: r.midY + w * 0.08, width: length - 2, height: w * 0.22),
                            radius: w * 0.1, rgb(light, 0.75))
        let m = muzzle ?? mix(base, 0x000000, 0.35)
        ctx.fillRoundedRect(CGRect(x: r.maxX - 3, y: r.minY - 0.8, width: 3.5, height: w + 1.6), radius: 1, rgb(m))
    }

    static func band(_ ctx: CGContext, _ c: CGPoint, x: CGFloat, width w: CGFloat, y: CGFloat = 0, color: UInt32) {
        ctx.fillRoundedRect(CGRect(x: c.x + x, y: c.y + y - w / 2 - 0.8, width: 2.6, height: w + 1.6), radius: 1, rgb(color))
    }

    /// Top-down figure: shoulders + head (optionally helmeted).
    static func figure(_ ctx: CGContext, _ p: CGPoint, scale s: CGFloat = 1, body: UInt32, bodyLight: UInt32,
                       head: UInt32, headLight: UInt32) {
        ctx.shadedEllipse(p, 7.5 * s, 11 * s, base: body, light: bodyLight)
        ctx.shadedEllipse(CGPoint(x: p.x - 0.5 * s, y: p.y), 5.8 * s, 5.8 * s, base: head, light: headLight)
    }

    static func wheel(_ ctx: CGContext, _ p: CGPoint, w: CGFloat = 9, h: CGFloat = 4) {
        ctx.fillRoundedRect(CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), radius: 1.5, rgb(0x2B1D12))
        ctx.strokeLine(CGPoint(x: p.x - w / 2 + 1.5, y: p.y), CGPoint(x: p.x + w / 2 - 1.5, y: p.y), rgb(0x6B4A2B), width: 1)
    }

    // MARK: Splash: Catapult → Cannon → Heavy Artillery → Plasma Artillery

    static func catapult(_ ctx: CGContext, _ c: CGPoint) {
        for side: CGFloat in [-1, 1] {
            wheel(ctx, CGPoint(x: c.x - 11, y: c.y + side * 15))
            wheel(ctx, CGPoint(x: c.x + 9, y: c.y + side * 15))
            ctx.fillRoundedRect(CGRect(x: c.x - 20, y: c.y + side * 11 - 3, width: 36, height: 6), radius: 2, rgb(0x5A381C))
            ctx.fillRoundedRect(CGRect(x: c.x - 19, y: c.y + side * 11 - 1.5, width: 34, height: 2.5), radius: 1, rgb(0x8E6136))
        }
        for x: CGFloat in [-14, 8] {
            ctx.fillRoundedRect(CGRect(x: c.x + x - 2.5, y: c.y - 12, width: 5, height: 24), radius: 1.5, rgb(0x4A2E16))
        }
        ctx.fillRoundedRect(CGRect(x: c.x - 8, y: c.y - 3, width: 31, height: 6), radius: 3, rgb(0x7A4E27))
        ctx.fillEllipse(CGPoint(x: c.x + 23, y: c.y), 8.5, 9, rgb(0x5B3A1F))
        ctx.shadedEllipse(CGPoint(x: c.x + 23, y: c.y), 6.5, 6.5, base: 0x6E6A62, light: 0xCFC9BD)
    }

    static func cannon(_ ctx: CGContext, _ c: CGPoint) {
        for side: CGFloat in [-1, 1] { wheel(ctx, CGPoint(x: c.x - 5, y: c.y + side * 13), w: 13, h: 5) }
        ctx.fillRoundedRect(CGRect(x: c.x - 18, y: c.y - 10, width: 24, height: 20), radius: 3, rgb(0x6B4423))
        ctx.fillRoundedRect(CGRect(x: c.x - 16, y: c.y - 7, width: 20, height: 14), radius: 2, rgb(0x8B5A2B))
        barrel(ctx, c, x0: -12, length: 36, width: 12, base: 0x2E3135, light: 0x7C838C)
        band(ctx, c, x: -6, width: 12, color: 0xB8863B)
        band(ctx, c, x: 14, width: 12, color: 0xB8863B)
        ctx.fillCircle(CGPoint(x: c.x - 13, y: c.y), 4, rgb(0xB8863B))
    }

    static func heavyArtillery(_ ctx: CGContext, _ c: CGPoint) {
        for side: CGFloat in [-1, 1] {
            barrel(ctx, c, x0: 2, length: 28, width: 7.5, y: side * 5.5, base: 0x3A4047, light: 0x9AA3AD, muzzle: 0x1E2226)
        }
        ctx.shadedEllipse(c, 15, 15, base: 0x56606A, light: 0xA9B3BD)
        ctx.fillRoundedRect(CGRect(x: c.x - 16, y: c.y - 6, width: 6, height: 12), radius: 1.5, rgb(0x1F1F1F))
        for i in 0..<3 {
            ctx.setFillColor(rgb(0xE8B92E)); ctx.fill(CGRect(x: c.x - 16, y: c.y - 6 + CGFloat(i) * 4.5, width: 6, height: 2.2))
        }
        ctx.fillCircle(CGPoint(x: c.x + 3, y: c.y), 4, rgb(0x2C3035))
    }

    static func plasmaArtillery(_ ctx: CGContext, _ c: CGPoint) {
        ctx.radialGlow(CGPoint(x: c.x + 28, y: c.y), 12, 0x2FD8FF, alpha: 0.8)
        barrel(ctx, c, x0: 2, length: 26, width: 14, base: 0x26313B, light: 0x6E8396, muzzle: 0x3FE0FF)
        ctx.fillRoundedRect(CGRect(x: c.x + 6, y: c.y - 2, width: 20, height: 4), radius: 2, rgb(0x7FF6FF))
        ctx.fillPolygon(TowerArt.hexagon(c, 15), rgb(0xD5DFE7))
        ctx.fillPolygon(TowerArt.hexagon(c, 12), rgb(0xEEF4F8))
        ctx.radialGlow(c, 10, 0x3FE0FF, alpha: 0.9)
        ctx.fillCircle(c, 4, rgb(0xE6FDFF))
    }

    // MARK: Sniper: Longbow → Crossbow → Precision Rifle → Railgun

    static func longbowArcher(_ ctx: CGContext, _ c: CGPoint) {
        // Quiver
        ctx.fillRoundedRect(CGRect(x: c.x - 17, y: c.y + 2, width: 13, height: 5), radius: 2, rgb(0x5A3A1C))
        figure(ctx, c, body: 0x7A3B2A, bodyLight: 0xC0715A, head: 0x4E2A1C, headLight: 0x8A5A42)
        ctx.strokeLine(CGPoint(x: c.x + 2, y: c.y + 8), CGPoint(x: c.x + 14, y: c.y + 2), rgb(0xC69C72), width: 3)
        ctx.setStrokeColor(rgb(0x4A2E14)); ctx.setLineWidth(3)
        ctx.beginPath(); ctx.addArc(center: CGPoint(x: c.x + 4, y: c.y), radius: 18, startAngle: -1.0, endAngle: 1.0, clockwise: false); ctx.strokePath()
        let tip = CGPoint(x: c.x + 4 + 18 * cos(1.0), y: c.y + 18 * sin(1.0))
        ctx.strokeLine(tip, CGPoint(x: tip.x, y: c.y - 18 * sin(1.0)), rgb(0xEDE6D6, 0.8), width: 0.8)
        ctx.strokeLine(CGPoint(x: c.x, y: c.y), CGPoint(x: c.x + 27, y: c.y), rgb(0x8B6A45), width: 1.6)
        ctx.fillPolygon([CGPoint(x: c.x + 30, y: c.y), CGPoint(x: c.x + 26, y: c.y + 2.2), CGPoint(x: c.x + 26, y: c.y - 2.2)], rgb(0x9A9A9A))
    }

    static func crossbowSniper(_ ctx: CGContext, _ c: CGPoint) {
        figure(ctx, CGPoint(x: c.x - 4, y: c.y), body: 0x3F4E63, bodyLight: 0x7B8DA6, head: 0x8C949E, headLight: 0xD0D6DD)
        // Stock
        ctx.fillRoundedRect(CGRect(x: c.x - 2, y: c.y - 2, width: 26, height: 4), radius: 1.5, rgb(0x5A3A1C))
        // Steel prod (bow)
        ctx.setStrokeColor(rgb(0x7C838C)); ctx.setLineWidth(2.6)
        ctx.beginPath(); ctx.move(to: CGPoint(x: c.x + 16, y: c.y - 12))
        ctx.addQuadCurve(to: CGPoint(x: c.x + 16, y: c.y + 12), control: CGPoint(x: c.x + 24, y: c.y)); ctx.strokePath()
        ctx.strokeLine(CGPoint(x: c.x + 16, y: c.y - 12), CGPoint(x: c.x + 10, y: c.y), rgb(0xEDE6D6, 0.7), width: 0.8)
        ctx.strokeLine(CGPoint(x: c.x + 16, y: c.y + 12), CGPoint(x: c.x + 10, y: c.y), rgb(0xEDE6D6, 0.7), width: 0.8)
        ctx.fillPolygon([CGPoint(x: c.x + 29, y: c.y), CGPoint(x: c.x + 25, y: c.y + 2), CGPoint(x: c.x + 25, y: c.y - 2)], rgb(0x55534E))
    }

    static func precisionRifle(_ ctx: CGContext, _ c: CGPoint) {
        barrel(ctx, c, x0: 4, length: 28, width: 4.2, base: 0x2A2D31, light: 0x7C838C, muzzle: 0x111214)
        ctx.shadedEllipse(c, 11, 11, base: 0x4B5A42, light: 0x8DA07E)
        // Scope (offset to the side, seen from above)
        ctx.fillRoundedRect(CGRect(x: c.x - 2, y: c.y + 5, width: 16, height: 4), radius: 2, rgb(0x1E2124))
        ctx.fillCircle(CGPoint(x: c.x + 14, y: c.y + 7), 2.3, rgb(0x4FB3FF))
        ctx.fillRoundedRect(CGRect(x: c.x - 13, y: c.y - 3, width: 8, height: 6), radius: 2, rgb(0x3A4433))
    }

    static func railgun(_ ctx: CGContext, _ c: CGPoint) {
        ctx.radialGlow(CGPoint(x: c.x + 20, y: c.y), 14, 0x3FA9FF, alpha: 0.6)
        ctx.fillRoundedRect(CGRect(x: c.x + 6, y: c.y - 2, width: 28, height: 4), radius: 2, rgb(0x8FE2FF, 0.9))
        for side: CGFloat in [-1, 1] {
            ctx.fillRoundedRect(CGRect(x: c.x + 4, y: c.y + side * 4.5 - 1.6, width: 31, height: 3.2), radius: 1, rgb(0x8A96A3))
        }
        ctx.fillRoundedRect(CGRect(x: c.x - 13, y: c.y - 9, width: 22, height: 18), radius: 7, rgb(0xC9D3DC))
        ctx.fillRoundedRect(CGRect(x: c.x - 11, y: c.y - 7, width: 18, height: 14), radius: 6, rgb(0xEEF3F7))
        ctx.radialGlow(CGPoint(x: c.x - 2, y: c.y), 7, 0x3FA9FF, alpha: 0.9)
        ctx.fillCircle(CGPoint(x: c.x - 2, y: c.y), 2.5, rgb(0xE6F6FF))
    }

    // MARK: Heavy: Ballista → Heavy Cannon → Rocket Launcher → Orbital Strike

    static func ballista(_ ctx: CGContext, _ c: CGPoint) {
        ctx.fillRoundedRect(CGRect(x: c.x - 18, y: c.y - 5, width: 28, height: 10), radius: 2, rgb(0x6B4423))
        ctx.setStrokeColor(rgb(0x4A2E14)); ctx.setLineWidth(4.5)
        ctx.beginPath(); ctx.addArc(center: CGPoint(x: c.x - 2, y: c.y), radius: 19, startAngle: -1.15, endAngle: 1.15, clockwise: false); ctx.strokePath()
        let a: CGFloat = 1.15
        let top = CGPoint(x: c.x - 2 + 19 * cos(a), y: c.y + 19 * sin(a))
        let bot = CGPoint(x: top.x, y: c.y - 19 * sin(a))
        ctx.strokeLine(top, CGPoint(x: c.x - 10, y: c.y), rgb(0xEDE6D6, 0.85), width: 1)
        ctx.strokeLine(bot, CGPoint(x: c.x - 10, y: c.y), rgb(0xEDE6D6, 0.85), width: 1)
        ctx.strokeLine(CGPoint(x: c.x - 12, y: c.y), CGPoint(x: c.x + 24, y: c.y), rgb(0x5E4128), width: 3.2)
        ctx.fillPolygon([CGPoint(x: c.x + 31, y: c.y), CGPoint(x: c.x + 23, y: c.y + 4), CGPoint(x: c.x + 23, y: c.y - 4)], rgb(0x5B5852))
    }

    static func heavyCannon(_ ctx: CGContext, _ c: CGPoint) {
        ctx.fillRoundedRect(CGRect(x: c.x - 16, y: c.y - 13, width: 22, height: 26), radius: 3, rgb(0x3D4248))
        barrel(ctx, c, x0: -14, length: 46, width: 14, base: 0x34383D, light: 0x8C949C, muzzle: 0x1C1F22)
        band(ctx, c, x: 0, width: 14, color: 0x5E666F)
        band(ctx, c, x: 18, width: 14, color: 0x5E666F)
        ctx.shadedEllipse(CGPoint(x: c.x - 14, y: c.y), 8, 8, base: 0x4B5158, light: 0x9AA3AD)
    }

    static func rocketLauncher(_ ctx: CGContext, _ c: CGPoint) {
        ctx.fillRoundedRect(CGRect(x: c.x - 15, y: c.y - 14, width: 34, height: 28), radius: 4, rgb(0x4E5A3A))
        ctx.fillRoundedRect(CGRect(x: c.x - 13, y: c.y - 12, width: 30, height: 24), radius: 3, rgb(0x6B7A50))
        for y: CGFloat in [-8.5, -2.8, 2.8, 8.5] {
            ctx.fillRoundedRect(CGRect(x: c.x - 8, y: c.y + y - 2.3, width: 27, height: 4.6), radius: 2, rgb(0x2E3426))
            ctx.fillEllipse(CGPoint(x: c.x + 19, y: c.y + y), 2.6, 2.2, rgb(0xD9473B))
        }
        ctx.fillRoundedRect(CGRect(x: c.x - 15, y: c.y - 3, width: 5, height: 6), radius: 1, rgb(0xE8B92E))
    }

    static func orbitalUplink(_ ctx: CGContext, _ c: CGPoint) {
        ctx.radialGlow(CGPoint(x: c.x + 22, y: c.y), 10, 0x3FE0FF, alpha: 0.85)
        ctx.shadedEllipse(c, 18, 18, base: 0xC9D3DC, light: 0xF4F8FB)
        for r: CGFloat in [14, 10, 6] { ctx.strokeCircle(c, r, rgb(0x93A3B2), width: 1) }
        for k in 0..<3 {
            let a = CGFloat(k) / 3 * 2 * .pi + .pi / 3
            ctx.strokeLine(CGPoint(x: c.x + cos(a) * 17, y: c.y + sin(a) * 17), CGPoint(x: c.x + 14, y: c.y), rgb(0x6E7F8F), width: 1.4)
        }
        ctx.fillRoundedRect(CGRect(x: c.x + 10, y: c.y - 3, width: 13, height: 6), radius: 3, rgb(0x26313B))
        ctx.fillCircle(CGPoint(x: c.x + 23, y: c.y), 3.2, rgb(0xE6FDFF))
        ctx.radialGlow(c, 6, 0x3FE0FF, alpha: 0.9)
    }

    // MARK: Rapid: Multi-Archer → Repeating Crossbow → Machine Gun → Laser Gatling

    static func multiArcher(_ ctx: CGContext, _ c: CGPoint) {
        for (dx, dy) in [(CGFloat(-7), CGFloat(-11)), (-7, 11), (0, 0)] {
            let p = CGPoint(x: c.x + dx, y: c.y + dy)
            ctx.setStrokeColor(rgb(0x5A3A1C)); ctx.setLineWidth(1.8)
            ctx.beginPath(); ctx.addArc(center: CGPoint(x: p.x + 3, y: p.y), radius: 8, startAngle: -1.1, endAngle: 1.1, clockwise: false); ctx.strokePath()
            figure(ctx, p, scale: 0.62, body: 0x3E6E8C, bodyLight: 0x7EB0CF, head: 0x2F4A5C, headLight: 0x5E8197)
            ctx.strokeLine(CGPoint(x: p.x + 2, y: p.y), CGPoint(x: p.x + 14, y: p.y), rgb(0x8B6A45), width: 1.2)
        }
    }

    static func repeatingCrossbow(_ ctx: CGContext, _ c: CGPoint) {
        ctx.fillRoundedRect(CGRect(x: c.x - 12, y: c.y - 3, width: 36, height: 6), radius: 2, rgb(0x6B4423))
        ctx.setStrokeColor(rgb(0x5A3A1C)); ctx.setLineWidth(3)
        ctx.beginPath(); ctx.move(to: CGPoint(x: c.x + 16, y: c.y - 13))
        ctx.addQuadCurve(to: CGPoint(x: c.x + 16, y: c.y + 13), control: CGPoint(x: c.x + 25, y: c.y)); ctx.strokePath()
        // Box magazine
        ctx.fillRoundedRect(CGRect(x: c.x - 2, y: c.y - 6, width: 14, height: 12), radius: 2, rgb(0xA0703F))
        for k in 0..<4 { ctx.strokeLine(CGPoint(x: c.x + CGFloat(k) * 3.2, y: c.y - 5), CGPoint(x: c.x + CGFloat(k) * 3.2, y: c.y + 5), rgb(0x6B4423), width: 0.8) }
        // Crank
        ctx.strokeLine(CGPoint(x: c.x - 8, y: c.y - 3), CGPoint(x: c.x - 11, y: c.y - 11), rgb(0x7C838C), width: 2)
        ctx.fillCircle(CGPoint(x: c.x - 11, y: c.y - 11), 2, rgb(0x5A3A1C))
        ctx.fillPolygon([CGPoint(x: c.x + 28, y: c.y), CGPoint(x: c.x + 24, y: c.y + 2), CGPoint(x: c.x + 24, y: c.y - 2)], rgb(0x55534E))
    }

    static func machineGun(_ ctx: CGContext, _ c: CGPoint) {
        for side: CGFloat in [-1, 1] {
            barrel(ctx, c, x0: 6, length: 23, width: 3.4, y: side * 3.4, base: 0x24272B, light: 0x6E757D, muzzle: 0x111214)
        }
        ctx.fillRoundedRect(CGRect(x: c.x - 13, y: c.y - 9, width: 22, height: 18), radius: 4, rgb(0x3A4047))
        ctx.fillRoundedRect(CGRect(x: c.x - 11, y: c.y - 7, width: 18, height: 14), radius: 3, rgb(0x5A626B))
        ctx.fillRoundedRect(CGRect(x: c.x - 9, y: c.y - 17, width: 12, height: 7), radius: 1.5, rgb(0x5E6B45))
        for k in 0..<5 { ctx.fillCircle(CGPoint(x: c.x - 6 + CGFloat(k) * 2.4, y: c.y - 9.5), 1, rgb(0xD9A43B)) }
    }

    static func laserGatling(_ ctx: CGContext, _ c: CGPoint) {
        ctx.radialGlow(CGPoint(x: c.x + 30, y: c.y), 10, 0xFF2D2D, alpha: 0.8)
        ctx.fillRoundedRect(CGRect(x: c.x + 4, y: c.y - 7.5, width: 27, height: 15), radius: 4, rgb(0x2B2F36))
        for y: CGFloat in [-4.5, 0, 4.5] {
            ctx.fillRoundedRect(CGRect(x: c.x + 6, y: c.y + y - 1.4, width: 25, height: 2.8), radius: 1.4, rgb(0x5A626B))
            ctx.fillCircle(CGPoint(x: c.x + 31, y: c.y + y), 1.6, rgb(0xFF6B6B))
        }
        ctx.fillRoundedRect(CGRect(x: c.x + 14, y: c.y - 8.5, width: 3, height: 17), radius: 1, rgb(0xFF3B3B, 0.85))
        ctx.shadedEllipse(c, 12, 12, base: 0x30353D, light: 0x7A8390)
        ctx.radialGlow(c, 7, 0xFF2D2D, alpha: 0.7)
        ctx.fillCircle(c, 2.5, rgb(0xFFD6D6))
    }
}
