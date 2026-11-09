// TEMPORARY ART — terrain, path, decorations, build pads, base, spawn and FX.
// The static terrain (grass, path, trees, rocks) is baked into ONE texture so
// the whole map costs a single draw call.

import CoreGraphics
import EvolutionDefenseCore

enum MapArt {

    // MARK: Background

    static func drawBackground(_ ctx: CGContext, map: MapDefinition) {
        let size = map.worldSize
        let path = map.makePath()
        var rng = ArtRandom(map.scatter.seed)

        // Grass base with soft tonal patches.
        ctx.setFillColor(rgb(0x6DA046)); ctx.fill(CGRect(origin: .zero, size: size))
        for _ in 0..<160 {
            let p = CGPoint(x: rng.range(-40, size.width + 40), y: rng.range(-40, size.height + 40))
            let r = rng.range(30, 110)
            let tone: UInt32 = rng.next() < 0.5 ? 0x5E9140 : 0x82B455
            ctx.radialGlow(p, r, tone, alpha: rng.range(0.25, 0.5))
        }
        // Grass blades
        for _ in 0..<5200 {
            let p = CGPoint(x: rng.range(0, size.width), y: rng.range(0, size.height))
            let len = rng.range(2.5, 6)
            let tone: UInt32 = rng.next() < 0.55 ? 0x4F8434 : 0x9CC86A
            ctx.strokeLine(p, CGPoint(x: p.x + rng.range(-1.5, 1.5), y: p.y + len), rgb(tone, rng.range(0.35, 0.7)), width: 1)
        }

        // Path: dark edge, dirt body, lighter worn centre, pebbles.
        let pw = map.pathWidth * map.tileSize
        let cg = CGMutablePath()
        cg.addLines(between: path.points)
        func strokePath(_ color: CGColor, _ width: CGFloat) {
            ctx.addPath(cg); ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.strokePath()
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: rgb(0x000000, 0.35))
        strokePath(rgb(0x6B5433), pw + 10)
        ctx.restoreGState()
        strokePath(rgb(0x8F7148), pw + 4)
        strokePath(rgb(0xC4A06A), pw)
        strokePath(rgb(0xD6B987, 0.55), pw * 0.5)
        // Pebbles & ruts along the path
        let total = path.totalLength
        var hint = 0
        var d: CGFloat = 0
        while d < total {
            let s = path.sample(at: d, segmentHint: &hint)
            let off = rng.range(-pw * 0.42, pw * 0.42)
            let p = s.position + s.direction.perpendicular * off
            let r = rng.range(1, 2.8)
            ctx.fillEllipse(p, r * 1.2, r, rgb(rng.next() < 0.5 ? 0x9C8461 : 0xE3CDA4, 0.8))
            d += rng.range(4, 12)
        }
        // Grass tufts overhanging the path edges
        d = 0; hint = 0
        while d < total {
            let s = path.sample(at: d, segmentHint: &hint)
            for side: CGFloat in [-1, 1] {
                let base = s.position + s.direction.perpendicular * (side * (pw * 0.5 + 3))
                for _ in 0..<3 {
                    let b = base + CGPoint(x: rng.range(-3, 3), y: rng.range(-3, 3))
                    let tip = b + s.direction.perpendicular * (-side * rng.range(3, 8)) + CGPoint(x: rng.range(-2, 2), y: rng.range(-2, 2))
                    ctx.strokeLine(b, tip, rgb(0x5C9139, 0.9), width: 1.4)
                }
            }
            d += rng.range(6, 14)
        }

        // Decorations, back-to-front (higher y first so lower ones overlap).
        let decos = map.resolvedDecorations().sorted { $0.y > $1.y }
        for deco in decos {
            let p = map.world(x: deco.x, y: deco.y)
            let s = CGFloat(deco.scale)
            var local = ArtRandom(UInt64(abs(deco.x * 1000 + deco.y * 7)))
            switch deco.kind {
            case .tree: drawTree(ctx, p, s, &local)
            case .pine: drawPine(ctx, p, s, &local)
            case .rock: drawRock(ctx, p, s * 0.7, &local)
            case .boulder: drawRock(ctx, p, s * 1.25, &local)
            case .bush: drawBush(ctx, p, s, &local)
            case .flowers: drawFlowers(ctx, p, s, &local)
            }
        }

        // Gentle vignette for focus.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let g = CGGradient(colorsSpace: space, colors: [rgb(0x000000, 0), rgb(0x000000, 0.28)] as CFArray, locations: [0.55, 1]) {
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.saveGState()
            ctx.scaleBy(x: 1, y: size.height / size.width)
            let cc = CGPoint(x: c.x, y: c.y * size.width / size.height)
            ctx.drawRadialGradient(g, startCenter: cc, startRadius: 0, endCenter: cc, endRadius: size.width * 0.62, options: [.drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }

    static func drawTree(_ ctx: CGContext, _ p: CGPoint, _ s: CGFloat, _ rng: inout ArtRandom) {
        let r = 24 * s
        ctx.softShadow(CGPoint(x: p.x + r * 0.35, y: p.y - r * 0.4), r * 1.05, r * 0.85, alpha: 0.35)
        let tones: [UInt32] = [0x2F6B2A, 0x3D8233, 0x4F9A3D, 0x6DB451]
        for (i, t) in tones.enumerated() {
            let k = CGFloat(i)
            let n = 5 - i
            for j in 0..<n {
                let a = CGFloat(j) / CGFloat(n) * 2 * .pi + rng.range(0, 1)
                let rr = r * (0.75 - k * 0.14)
                let off = r * (0.32 - k * 0.07)
                ctx.fillCircle(CGPoint(x: p.x + cos(a) * off - k * r * 0.06, y: p.y + sin(a) * off + k * r * 0.07), rr * rng.range(0.85, 1.05), rgb(t))
            }
        }
        ctx.fillCircle(CGPoint(x: p.x - r * 0.25, y: p.y + r * 0.3), r * 0.16, rgb(0x9BD27A, 0.6))
    }

    static func drawPine(_ ctx: CGContext, _ p: CGPoint, _ s: CGFloat, _ rng: inout ArtRandom) {
        let r = 22 * s
        ctx.softShadow(CGPoint(x: p.x + r * 0.4, y: p.y - r * 0.45), r * 0.95, r * 0.8, alpha: 0.35)
        let tones: [UInt32] = [0x1F4D2B, 0x2B6236, 0x3A7A43, 0x4E9354]
        for (i, t) in tones.enumerated() {
            let rr = r * (1 - CGFloat(i) * 0.22)
            let pts = (0..<16).map { j -> CGPoint in
                let a = CGFloat(j) / 16 * 2 * .pi
                let rad = j % 2 == 0 ? rr : rr * 0.68
                return CGPoint(x: p.x + cos(a) * rad - CGFloat(i) * 1.2, y: p.y + sin(a) * rad + CGFloat(i) * 1.4)
            }
            ctx.fillPolygon(pts, rgb(t))
        }
        ctx.fillCircle(CGPoint(x: p.x - 4, y: p.y + 5), r * 0.12, rgb(0x6FB26A, 0.7))
    }

    static func drawRock(_ ctx: CGContext, _ p: CGPoint, _ s: CGFloat, _ rng: inout ArtRandom) {
        let r = 15 * s
        ctx.softShadow(CGPoint(x: p.x + r * 0.3, y: p.y - r * 0.35), r * 1.05, r * 0.8, alpha: 0.35)
        let n = 7
        let pts = (0..<n).map { i -> CGPoint in
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi + rng.range(-0.2, 0.2)
            let rad = r * rng.range(0.75, 1.05)
            return CGPoint(x: p.x + cos(a) * rad, y: p.y + sin(a) * rad * 0.82)
        }
        ctx.fillPolygon(pts, rgb(0x6F6C66))
        let inner = pts.map { CGPoint(x: p.x + ($0.x - p.x) * 0.7 - r * 0.12, y: p.y + ($0.y - p.y) * 0.7 + r * 0.14) }
        ctx.fillPolygon(inner, rgb(0x9A968D))
        ctx.fillCircle(CGPoint(x: p.x - r * 0.3, y: p.y + r * 0.3), r * 0.18, rgb(0xC4C0B6, 0.8))
        if rng.next() < 0.5 { ctx.fillEllipse(CGPoint(x: p.x + r * 0.2, y: p.y - r * 0.35), r * 0.35, r * 0.18, rgb(0x5E8F3E, 0.75)) }
    }

    static func drawBush(_ ctx: CGContext, _ p: CGPoint, _ s: CGFloat, _ rng: inout ArtRandom) {
        let r = 10 * s
        ctx.softShadow(CGPoint(x: p.x + 3, y: p.y - 4), r * 1.3, r * 0.9, alpha: 0.3)
        for _ in 0..<5 {
            ctx.fillCircle(CGPoint(x: p.x + rng.range(-r * 0.7, r * 0.7), y: p.y + rng.range(-r * 0.5, r * 0.5)), r * rng.range(0.5, 0.75), rgb(0x3F7D30))
        }
        for _ in 0..<3 {
            ctx.fillCircle(CGPoint(x: p.x + rng.range(-r * 0.5, r * 0.3), y: p.y + rng.range(0, r * 0.5)), r * 0.35, rgb(0x5FA246))
        }
        if rng.next() < 0.4 { for _ in 0..<3 {
            ctx.fillCircle(CGPoint(x: p.x + rng.range(-r * 0.6, r * 0.6), y: p.y + rng.range(-r * 0.4, r * 0.4)), 1.6, rgb(0xD9363E)) } }
    }

    static func drawFlowers(_ ctx: CGContext, _ p: CGPoint, _ s: CGFloat, _ rng: inout ArtRandom) {
        let colors: [UInt32] = [0xFFFFFF, 0xF7E36A, 0xF29BC1, 0xB9A4F5]
        let col = colors[Int(rng.next() * CGFloat(colors.count)) % colors.count]
        for _ in 0..<Int(5 * s + 2) {
            let q = CGPoint(x: p.x + rng.range(-12, 12), y: p.y + rng.range(-8, 8))
            ctx.fillCircle(q, 1.8, rgb(col, 0.95))
            ctx.fillCircle(q, 0.7, rgb(0xF2B32A))
        }
    }

    // MARK: Build pad

    static let slotSize = CGSize(width: 72, height: 72)

    static func drawSlot(_ ctx: CGContext, highlighted: Bool) {
        let c = CGPoint(x: slotSize.width / 2, y: slotSize.height / 2)
        let r: CGFloat = 29
        if highlighted { ctx.radialGlow(c, r + 7, 0xFFE27A, alpha: 0.85) }
        ctx.softShadow(CGPoint(x: c.x + 2, y: c.y - 3), r, r * 0.9, alpha: 0.3)
        ctx.fillCircle(c, r, rgb(0x5D564C))
        // Flagstones
        var rng = ArtRandom(99)
        for i in 0..<9 {
            let a0 = CGFloat(i) / 9 * 2 * .pi
            let a1 = a0 + 2 * .pi / 9 - 0.08
            ctx.setFillColor(rgb(mix(0x9D968A, 0xB8B1A3, rng.next())))
            ctx.beginPath()
            ctx.addArc(center: c, radius: r - 2.5, startAngle: a0, endAngle: a1, clockwise: false)
            ctx.addArc(center: c, radius: r * 0.55, startAngle: a1, endAngle: a0, clockwise: true)
            ctx.closePath(); ctx.fillPath()
        }
        ctx.fillCircle(c, r * 0.5, rgb(0x7E6E58))
        ctx.fillCircle(c, r * 0.42, rgb(0x917F66))
        // Build marker "+"
        let markColor = highlighted ? rgb(0xFFF3C4) : rgb(0xE9DFC9, 0.75)
        ctx.strokeLine(CGPoint(x: c.x - 6, y: c.y), CGPoint(x: c.x + 6, y: c.y), markColor, width: 2.4)
        ctx.strokeLine(CGPoint(x: c.x, y: c.y - 6), CGPoint(x: c.x, y: c.y + 6), markColor, width: 2.4)
        if highlighted { ctx.strokeCircle(c, r + 1, rgb(0xFFE27A), width: 2.5) }
    }

    // MARK: Base (evolves with the era)

    static let baseSize = CGSize(width: 150, height: 150)

    static func drawBase(_ ctx: CGContext, era: Era) {
        switch era {
        case .primitive: drawVillage(ctx)
        case .medieval: drawKeep(ctx)
        case .industrial: drawFactory(ctx)
        case .futuristic: drawCitadel(ctx)
        }
    }

    /// Medieval: stone curtain wall, four round towers, central keep with banners.
    private static func drawKeep(_ ctx: CGContext) {
        let c = CGPoint(x: baseSize.width / 2, y: baseSize.height / 2)
        let r: CGFloat = 56
        ctx.softShadow(CGPoint(x: c.x + 4, y: c.y - 6), r + 8, r + 2, alpha: 0.45)
        ctx.fillCircle(c, r, rgb(0x7E7A72))
        ctx.fillCircle(c, r - 9, rgb(0x9C9A8E))
        // Wall blocks
        let blocks = 28
        for i in 0..<blocks {
            let a = CGFloat(i) / CGFloat(blocks) * 2 * .pi
            if abs(a - .pi) < 0.2 { continue }
            let p = CGPoint(x: c.x + cos(a) * (r - 4), y: c.y + sin(a) * (r - 4))
            ctx.fillRoundedRect(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8), radius: 1.5, rgb(i % 2 == 0 ? 0xB5B1A4 : 0xA19D90))
        }
        // Gate (towards the path, left)
        ctx.fillRoundedRect(CGRect(x: c.x - r - 2, y: c.y - 9, width: 14, height: 18), radius: 2, rgb(0x5A3A1C))
        ctx.strokeLine(CGPoint(x: c.x - r + 2, y: c.y - 8), CGPoint(x: c.x - r + 2, y: c.y + 8), rgb(0x2A2A2A), width: 1.5)
        // Corner towers
        for a in stride(from: CGFloat.pi / 4, to: 2 * .pi, by: .pi / 2) {
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            ctx.softShadow(CGPoint(x: p.x + 2, y: p.y - 3), 13, 12, alpha: 0.4)
            ctx.shadedEllipse(p, 12, 12, base: 0x8E8A7E, light: 0xD2CEC0)
            for k in 0..<8 { let b = CGFloat(k) / 8 * 2 * .pi
                ctx.fillCircle(CGPoint(x: p.x + cos(b) * 9, y: p.y + sin(b) * 9), 2.2, rgb(0x6E6A60)) }
            ctx.fillCircle(p, 4, rgb(0x5E5A52))
        }
        // Keep
        let keep = CGRect(x: c.x - 22, y: c.y - 22, width: 44, height: 44)
        ctx.fillRoundedRect(keep.offsetBy(dx: 3, dy: -4), radius: 4, rgb(0x000000, 0.35))
        ctx.fillRoundedRect(keep, radius: 4, rgb(0x8A867A))
        ctx.fillRoundedRect(keep.insetBy(dx: 6, dy: 6), radius: 3, rgb(0xB9B5A8))
        ctx.fillRoundedRect(keep.insetBy(dx: 15, dy: 15), radius: 2, rgb(0x6A4A2A))
        // Banners
        for (o, col) in [(CGPoint(x: 14, y: 14), UInt32(0x2E5BBA)), (CGPoint(x: -14, y: -14), 0xC0392B)] {
            let p = c + o
            ctx.fillCircle(p, 2.2, rgb(0x3A2A1A))
            ctx.fillPolygon([p, p + CGPoint(x: 15, y: 4), p + CGPoint(x: 12, y: -3), p + CGPoint(x: 1, y: -3)], rgb(col))
        }
    }

    /// Industrial: brick works with smokestacks behind a steel fence.
    private static func drawFactory(_ ctx: CGContext) {
        let c = CGPoint(x: baseSize.width / 2, y: baseSize.height / 2)
        let r: CGFloat = 58
        ctx.softShadow(CGPoint(x: c.x + 4, y: c.y - 6), r + 6, r, alpha: 0.45)
        ctx.fillRoundedRect(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), radius: 10, rgb(0x5E5A55))
        ctx.fillRoundedRect(CGRect(x: c.x - r + 5, y: c.y - r + 5, width: r * 2 - 10, height: r * 2 - 10), radius: 8, rgb(0x77726A))
        // Fence posts
        var x = c.x - r + 3
        while x < c.x + r - 2 {
            ctx.fillCircle(CGPoint(x: x, y: c.y + r - 3), 2, rgb(0x3A3F46))
            ctx.fillCircle(CGPoint(x: x, y: c.y - r + 3), 2, rgb(0x3A3F46))
            x += 9
        }
        // Main hall (brick) with sawtooth roof
        let hall = CGRect(x: c.x - 34, y: c.y - 26, width: 62, height: 46)
        ctx.fillRoundedRect(hall.offsetBy(dx: 3, dy: -4), radius: 3, rgb(0x000000, 0.35))
        ctx.fillRoundedRect(hall, radius: 3, rgb(0x9A4B32))
        for i in 0..<5 {
            let rx = hall.minX + CGFloat(i) * hall.width / 5
            ctx.fillPolygon([CGPoint(x: rx, y: hall.minY + 3), CGPoint(x: rx + hall.width / 5, y: hall.minY + 3),
                             CGPoint(x: rx + hall.width / 5, y: hall.maxY - 3)], rgb(0xB8634A))
            ctx.strokeLine(CGPoint(x: rx + hall.width / 5 - 2, y: hall.minY + 5), CGPoint(x: rx + hall.width / 5 - 2, y: hall.maxY - 6),
                           rgb(0x8FC6E8, 0.7), width: 2)
        }
        // Smokestacks with smoke
        for (o, h) in [(CGPoint(x: 36, y: 22), CGFloat(1)), (CGPoint(x: 38, y: -12), 0.8)] {
            let p = c + o
            ctx.softShadow(CGPoint(x: p.x + 3, y: p.y - 4), 9, 9, alpha: 0.4)
            ctx.shadedEllipse(p, 8 * h, 8 * h, base: 0x7A3A26, light: 0xC0705A)
            ctx.fillCircle(p, 5 * h, rgb(0x1E1E1E))
            ctx.fillCircle(p + CGPoint(x: -6, y: 8), 7, rgb(0x9A9A9A, 0.45))
            ctx.fillCircle(p + CGPoint(x: -12, y: 15), 9, rgb(0xB0B0B0, 0.3))
        }
        // Gear emblem
        let g = c + CGPoint(x: -36, y: 32)
        for k in 0..<8 { let a = CGFloat(k) / 8 * 2 * .pi
            ctx.fillCircle(CGPoint(x: g.x + cos(a) * 8, y: g.y + sin(a) * 8), 3, rgb(0xC9A33A)) }
        ctx.fillCircle(g, 7, rgb(0xC9A33A)); ctx.fillCircle(g, 3, rgb(0x5E5A55))
    }

    /// Futuristic: alloy citadel under an energy dome.
    private static func drawCitadel(_ ctx: CGContext) {
        let c = CGPoint(x: baseSize.width / 2, y: baseSize.height / 2)
        let r: CGFloat = 58
        ctx.radialGlow(c, r + 14, 0x3FE0FF, alpha: 0.35)
        ctx.softShadow(CGPoint(x: c.x + 4, y: c.y - 6), r + 4, r, alpha: 0.45)
        let hex = (0..<6).map { i -> CGPoint in
            let a = CGFloat(i) / 6 * 2 * .pi + .pi / 6
            return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        }
        ctx.fillPolygon(hex, rgb(0x3A4250))
        ctx.fillPolygon(hex.map { CGPoint(x: c.x + ($0.x - c.x) * 0.88, y: c.y + ($0.y - c.y) * 0.88) }, rgb(0x5A6474))
        // Glowing seams
        for p in hex { ctx.strokeLine(c, p, rgb(0x3FE0FF, 0.45), width: 1.5) }
        // Pylons at the corners
        for p in hex {
            ctx.shadedEllipse(p, 7, 7, base: 0x6C7686, light: 0xD8E2EE)
            ctx.radialGlow(p, 8, 0x3FE0FF, alpha: 0.8)
            ctx.fillCircle(p, 2.2, rgb(0xE8FCFF))
        }
        // Core tower + dome
        ctx.shadedEllipse(c, 26, 26, base: 0x8A96A8, light: 0xF0F6FF)
        ctx.strokeCircle(c, 26, rgb(0x3FE0FF, 0.9), width: 2)
        ctx.strokeCircle(c, 17, rgb(0x3FE0FF, 0.5), width: 1.5)
        ctx.radialGlow(c, 14, 0x7FF0FF, alpha: 0.95)
        ctx.fillCircle(c, 5, rgb(0xFFFFFF))
        ctx.strokeCircle(c, r + 2, rgb(0x7FF0FF, 0.35), width: 2)
        ctx.fillEllipse(CGPoint(x: c.x - 18, y: c.y + 26), 18, 8, rgb(0xFFFFFF, 0.12))
    }

    /// Primitive: palisade village with huts and a fire pit.
    private static func drawVillage(_ ctx: CGContext) {
        let c = CGPoint(x: baseSize.width / 2, y: baseSize.height / 2)
        let r: CGFloat = 56
        ctx.softShadow(CGPoint(x: c.x + 4, y: c.y - 6), r + 6, r, alpha: 0.4)
        ctx.fillCircle(c, r - 2, rgb(0x8C7350))   // packed earth
        ctx.fillCircle(c, r - 12, rgb(0x9E8660))
        // Palisade of sharpened stakes
        let stakes = 34
        for i in 0..<stakes {
            let a = CGFloat(i) / CGFloat(stakes) * 2 * .pi
            // Leave a gate facing the path (left side).
            if abs(a - .pi) < 0.22 { continue }
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            ctx.shadedEllipse(p, 5.2, 5.2, base: 0x6E4523, light: 0xB07B4B)
            ctx.fillCircle(p, 1.6, rgb(0xD9B98C))
        }
        // Huts
        for (o, hr) in [(CGPoint(x: 12, y: 12), CGFloat(22)), (CGPoint(x: -20, y: -16), 14), (CGPoint(x: 20, y: -24), 12)] {
            let hc = c + o
            ctx.softShadow(CGPoint(x: hc.x + 3, y: hc.y - 4), hr, hr * 0.9, alpha: 0.35)
            ctx.fillCircle(hc, hr, rgb(0xB8913F))
            for k in 0..<3 { ctx.strokeCircle(hc, hr * (0.35 + CGFloat(k) * 0.22), rgb(0x8E6A28, 0.8), width: 1.2) }
            for k in 0..<12 { let a = CGFloat(k) / 12 * 2 * .pi
                ctx.strokeLine(hc, CGPoint(x: hc.x + cos(a) * hr, y: hc.y + sin(a) * hr), rgb(0x9C7730, 0.6), width: 0.8) }
            ctx.fillCircle(hc, hr * 0.18, rgb(0x5C4318))
        }
        // Fire pit
        let fire = c + CGPoint(x: -18, y: 16)
        for k in 0..<8 { let a = CGFloat(k) / 8 * 2 * .pi
            ctx.fillCircle(CGPoint(x: fire.x + cos(a) * 7, y: fire.y + sin(a) * 7), 2.4, rgb(0x6F6C66)) }
        ctx.radialGlow(fire, 14, 0xFF9A2E, alpha: 0.85)
        ctx.fillCircle(fire, 3.5, rgb(0xFFE08A))
        // Totem with banner
        let totem = c + CGPoint(x: 30, y: 30)
        ctx.fillCircle(totem, 4.5, rgb(0x5A3A1C))
        ctx.fillPolygon([totem, totem + CGPoint(x: 16, y: 4), totem + CGPoint(x: 13, y: -4), totem + CGPoint(x: 2, y: -3)], rgb(0xC0392B))
    }

    // MARK: Spawn (cave mouth at the map edge)

    static let spawnSize = CGSize(width: 110, height: 130)

    static func drawSpawn(_ ctx: CGContext) {
        let c = CGPoint(x: spawnSize.width / 2, y: spawnSize.height / 2)
        var rng = ArtRandom(5)
        // Dark burrow
        ctx.radialGlow(c, 52, 0x000000, alpha: 0.85)
        ctx.fillEllipse(c, 26, 34, rgb(0x15110D))
        ctx.radialGlow(CGPoint(x: c.x + 4, y: c.y), 20, 0x7A2E1A, alpha: 0.35)
        // Ring of jagged rocks around the opening (open towards +x)
        for i in 0..<14 {
            let a = CGFloat(i) / 14 * 2 * .pi
            if abs(a) < 0.55 || abs(a - 2 * .pi) < 0.55 { continue }
            let p = CGPoint(x: c.x + cos(a) * 36, y: c.y + sin(a) * 44)
            drawRock(ctx, p, rng.range(0.55, 0.85), &rng)
        }
        // Claw marks
        for k in 0..<3 {
            let x = c.x + 34 + CGFloat(k) * 5
            ctx.strokeLine(CGPoint(x: x, y: c.y - 8), CGPoint(x: x + 6, y: c.y + 8), rgb(0x5B4630, 0.6), width: 1.4)
        }
    }

    // MARK: Effects

    static func drawExplosion(_ ctx: CGContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = size.width / 2
        ctx.radialGlow(c, r, 0xFF7A1A, alpha: 0.85)
        ctx.radialGlow(c, r * 0.65, 0xFFC04A, alpha: 0.95)
        ctx.radialGlow(c, r * 0.3, 0xFFF4D0, alpha: 1)
    }

    static func drawPuff(_ ctx: CGContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        var rng = ArtRandom(3)
        for _ in 0..<7 {
            let p = CGPoint(x: c.x + rng.range(-size.width * 0.22, size.width * 0.22), y: c.y + rng.range(-size.height * 0.22, size.height * 0.22))
            ctx.radialGlow(p, size.width * 0.3, 0xE8DCC6, alpha: 0.7)
        }
    }

    static func drawSpark(_ ctx: CGContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        ctx.radialGlow(c, size.width / 2, 0xFFF1C2, alpha: 1)
        for i in 0..<6 { let a = CGFloat(i) / 6 * 2 * .pi
            ctx.strokeLine(c, CGPoint(x: c.x + cos(a) * size.width * 0.45, y: c.y + sin(a) * size.width * 0.45), rgb(0xFFFFFF, 0.8), width: 1.2) }
    }

    static func drawRing(_ ctx: CGContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        ctx.strokeCircle(c, size.width / 2 - 3, rgb(0xFFFFFF), width: 3)
    }
}
