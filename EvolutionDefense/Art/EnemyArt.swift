// TEMPORARY ART — top-down stylized creatures, drawn facing +x (right).
// Each creature has 4 walk frames (legs swing); the renderer picks a frame
// from distance travelled so the gait matches movement speed.

import CoreGraphics

struct QuadrupedStyle {
    var body: UInt32
    var bodyLight: UInt32
    var dark: UInt32
    var belly: UInt32
    var snout: UInt32
    var nose: UInt32 = 0x1A1414
    var eye: UInt32 = 0x111111
    var eyeGlow = false
    var lengthFactor: CGFloat = 2.6      // body length / radius
    var widthFactor: CGFloat = 1.25      // body width / radius
    var headFactor: CGFloat = 0.5        // head radius / body width
    var ears: Ears = .pointed
    var tail: Tail = .bushy
    var spikes = 0
    var spikeColor: UInt32 = 0xD8CDB4
    var tusks = false
    var aura: UInt32? = nil
    /// Armor plates over the back (Armored Beast / Monster).
    var plates: UInt32? = nil
    /// Glowing mutation spots.
    var glowSpots: UInt32? = nil

    enum Ears { case pointed, round, small }
    enum Tail { case bushy, thin, stub }
}

enum EnemyArt {
    static func style(for visual: String) -> QuadrupedStyle {
        switch visual {
        case "wolf":
            return QuadrupedStyle(body: 0x7D838D, bodyLight: 0xC5CAD2, dark: 0x4D525B, belly: 0xA9AEB6,
                                  snout: 0x9DA2AA, lengthFactor: 2.7, widthFactor: 1.05, headFactor: 0.52)
        case "boar":
            return QuadrupedStyle(body: 0x6E4B33, bodyLight: 0xA67C5B, dark: 0x3B271A, belly: 0x8A6448,
                                  snout: 0xC98D7C, lengthFactor: 2.3, widthFactor: 1.35, headFactor: 0.5,
                                  ears: .small, tail: .thin, spikes: 5, spikeColor: 0x2A1B12, tusks: true)
        case "bear":
            return QuadrupedStyle(body: 0x5B3B23, bodyLight: 0x8F6544, dark: 0x352214, belly: 0x6E4A2E,
                                  snout: 0xB08860, lengthFactor: 2.25, widthFactor: 1.45, headFactor: 0.46,
                                  ears: .round, tail: .stub)
        case "alphaBeast":
            return QuadrupedStyle(body: 0x3B2E4D, bodyLight: 0x7A5F9C, dark: 0x1E1729, belly: 0x51406A,
                                  snout: 0x5C4A74, eye: 0xFF3B30, eyeGlow: true,
                                  lengthFactor: 2.6, widthFactor: 1.2, headFactor: 0.5,
                                  ears: .pointed, tail: .bushy, spikes: 6, spikeColor: 0xE3D9C2,
                                  aura: 0xB04BFF)
        case "giantWolf":
            return QuadrupedStyle(body: 0x3C3F47, bodyLight: 0x7C818C, dark: 0x1F2126, belly: 0x5A5E67,
                                  snout: 0x60646D, eye: 0xFFB020, eyeGlow: true,
                                  lengthFactor: 2.8, widthFactor: 1.1, headFactor: 0.52, spikes: 4, spikeColor: 0x9AA0AA)
        case "armoredBeast":
            return QuadrupedStyle(body: 0x5E5342, bodyLight: 0x93846C, dark: 0x2E271D, belly: 0x786A54,
                                  snout: 0x8C7B62, lengthFactor: 2.35, widthFactor: 1.4, headFactor: 0.46,
                                  ears: .small, tail: .stub, tusks: true, plates: 0x8D949E)
        case "mutantBeast":
            return QuadrupedStyle(body: 0x4F6B2C, bodyLight: 0x8FB04E, dark: 0x2A3A14, belly: 0x6A8A3A,
                                  snout: 0x7A9446, eye: 0xD6FF3A, eyeGlow: true,
                                  lengthFactor: 2.6, widthFactor: 1.2, headFactor: 0.5, ears: .small, tail: .thin,
                                  spikes: 5, spikeColor: 0xC9E86A, glowSpots: 0xB6FF2E)
        case "armoredMonster":
            return QuadrupedStyle(body: 0x3E4A3A, bodyLight: 0x6E8065, dark: 0x1D241B, belly: 0x55644F,
                                  snout: 0x66775E, eye: 0xFF6A2A, eyeGlow: true,
                                  lengthFactor: 2.3, widthFactor: 1.5, headFactor: 0.44, ears: .small, tail: .stub,
                                  plates: 0x6B6F75, glowSpots: 0x9BE53A)
        default:
            return QuadrupedStyle(body: 0x888888, bodyLight: 0xCCCCCC, dark: 0x444444, belly: 0x999999, snout: 0xAAAAAA)
        }
    }

    /// Canvas size (points) for a creature of hit radius `r`.
    static func canvasSize(radius r: CGFloat, style s: QuadrupedStyle) -> CGSize {
        CGSize(width: (r * s.lengthFactor * 1.55).rounded(.up) + 8,
               height: (r * s.widthFactor * 2.3).rounded(.up) + 8)
    }

    static func drawFrame(_ ctx: CGContext, size: CGSize, radius r: CGFloat, style s: QuadrupedStyle, frame: Int) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let L = r * s.lengthFactor        // body length
        let W = r * s.widthFactor         // body width
        let phase = CGFloat(frame) / 4 * 2 * .pi
        let swing = sin(phase) * L * 0.11

        if let aura = s.aura {
            ctx.radialGlow(c, max(L, W) * 0.75, aura, alpha: 0.45)
        }
        // Shadow
        ctx.softShadow(CGPoint(x: c.x + 2, y: c.y - 3), L * 0.55, W * 0.62, alpha: 0.32)

        // Legs (paws peeking out under the body), diagonal pairs move together.
        let legR = W * 0.2
        let legs: [(CGFloat, CGFloat, CGFloat)] = [
            (L * 0.26, W * 0.46, swing), (L * 0.26, -W * 0.46, -swing),
            (-L * 0.24, W * 0.46, -swing), (-L * 0.24, -W * 0.46, swing)
        ]
        for (lx, ly, sw) in legs {
            ctx.fillEllipse(CGPoint(x: c.x + lx + sw, y: c.y + ly), legR * 1.25, legR, rgb(s.dark))
        }

        // Tail
        let tailBase = CGPoint(x: c.x - L * 0.46, y: c.y)
        let tailWag = sin(phase) * W * 0.18
        switch s.tail {
        case .bushy:
            ctx.fillEllipse(CGPoint(x: tailBase.x - L * 0.14, y: tailBase.y + tailWag), L * 0.2, W * 0.19, rgb(s.dark))
            ctx.fillEllipse(CGPoint(x: tailBase.x - L * 0.2, y: tailBase.y + tailWag), L * 0.09, W * 0.12, rgb(s.bodyLight, 0.6))
        case .thin:
            ctx.strokeLine(tailBase, CGPoint(x: tailBase.x - L * 0.18, y: tailBase.y + tailWag), rgb(s.dark), width: 2)
        case .stub:
            ctx.fillCircle(CGPoint(x: tailBase.x - L * 0.02, y: tailBase.y), W * 0.14, rgb(s.dark))
        }

        // Body
        ctx.shadedEllipse(c, L * 0.5, W * 0.5, base: s.body, light: s.bodyLight)
        // Back stripe / mane
        ctx.fillEllipse(CGPoint(x: c.x + L * 0.05, y: c.y), L * 0.36, W * 0.16, rgb(s.dark, 0.55))

        if let plateColor = s.plates {
            // Overlapping armor plates along the back.
            for i in 0..<4 {
                let x = c.x - L * 0.3 + CGFloat(i) * L * 0.19
                let pc = CGPoint(x: x, y: c.y)
                ctx.fillEllipse(CGPoint(x: pc.x - 1, y: pc.y - 1.5), L * 0.13, W * 0.42, rgb(0x000000, 0.3))
                ctx.shadedEllipse(pc, L * 0.12, W * 0.4, base: plateColor, light: mix(plateColor, 0xFFFFFF, 0.5))
                ctx.fillCircle(CGPoint(x: pc.x, y: pc.y + W * 0.28), max(1, W * 0.04), rgb(0x2A2A2A, 0.8))
                ctx.fillCircle(CGPoint(x: pc.x, y: pc.y - W * 0.28), max(1, W * 0.04), rgb(0x2A2A2A, 0.8))
            }
        }
        if let glow = s.glowSpots {
            var rng = ArtRandom(UInt64(s.body))
            for _ in 0..<6 {
                let p = CGPoint(x: c.x + rng.range(-L * 0.35, L * 0.3), y: c.y + rng.range(-W * 0.32, W * 0.32))
                let r = rng.range(W * 0.06, W * 0.11)
                ctx.radialGlow(p, r * 2.4, glow, alpha: 0.55)
                ctx.fillCircle(p, r, rgb(mix(glow, 0xFFFFFF, 0.3)))
            }
        }

        // Spikes / bristles along the spine
        if s.spikes > 0 {
            for i in 0..<s.spikes {
                let t = CGFloat(i) / CGFloat(max(1, s.spikes - 1))
                let x = c.x - L * 0.32 + t * L * 0.6
                let h = W * (0.2 + 0.12 * sin(t * .pi))
                ctx.fillPolygon([CGPoint(x: x - W * 0.09, y: c.y - h * 0.4), CGPoint(x: x + W * 0.16, y: c.y),
                                 CGPoint(x: x - W * 0.09, y: c.y + h * 0.4)], rgb(s.spikeColor))
            }
        }

        // Head
        let headR = W * s.headFactor
        let head = CGPoint(x: c.x + L * 0.47, y: c.y + sin(phase * 2) * 0.6)
        // Ears (behind head)
        switch s.ears {
        case .pointed:
            for side: CGFloat in [-1, 1] {
                ctx.fillPolygon([CGPoint(x: head.x - headR * 0.55, y: head.y + side * headR * 0.35),
                                 CGPoint(x: head.x - headR * 1.1, y: head.y + side * headR * 1.05),
                                 CGPoint(x: head.x + headR * 0.05, y: head.y + side * headR * 0.85)], rgb(s.dark))
            }
        case .round:
            for side: CGFloat in [-1, 1] {
                ctx.fillCircle(CGPoint(x: head.x - headR * 0.35, y: head.y + side * headR * 0.85), headR * 0.36, rgb(s.dark))
            }
        case .small:
            for side: CGFloat in [-1, 1] {
                ctx.fillPolygon([CGPoint(x: head.x - headR * 0.3, y: head.y + side * headR * 0.5),
                                 CGPoint(x: head.x - headR * 0.85, y: head.y + side * headR * 1.0),
                                 CGPoint(x: head.x + headR * 0.1, y: head.y + side * headR * 0.8)], rgb(s.dark))
            }
        }
        ctx.shadedEllipse(head, headR, headR * 0.92, base: s.body, light: s.bodyLight)
        // Snout
        let snout = CGPoint(x: head.x + headR * 0.85, y: head.y)
        ctx.fillEllipse(snout, headR * 0.6, headR * 0.45, rgb(s.snout))
        ctx.fillEllipse(CGPoint(x: snout.x + headR * 0.45, y: snout.y), headR * 0.18, headR * 0.2, rgb(s.nose))
        if s.tusks {
            for side: CGFloat in [-1, 1] {
                ctx.setStrokeColor(rgb(0xF4EEDC)); ctx.setLineWidth(max(1.5, headR * 0.16))
                ctx.beginPath()
                ctx.move(to: CGPoint(x: snout.x + headR * 0.1, y: snout.y + side * headR * 0.38))
                ctx.addQuadCurve(to: CGPoint(x: snout.x + headR * 0.55, y: snout.y + side * headR * 0.75),
                                 control: CGPoint(x: snout.x + headR * 0.45, y: snout.y + side * headR * 0.4))
                ctx.strokePath()
            }
        }
        // Eyes
        for side: CGFloat in [-1, 1] {
            let e = CGPoint(x: head.x + headR * 0.3, y: head.y + side * headR * 0.42)
            if s.eyeGlow { ctx.radialGlow(e, headR * 0.5, s.eye, alpha: 0.9) }
            ctx.fillCircle(e, max(1.1, headR * 0.13), rgb(s.eye))
        }
    }
}
