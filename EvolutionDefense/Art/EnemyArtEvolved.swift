// TEMPORARY ART — eras 2–4 creatures that aren't four-legged animals:
// bipeds (troll, mutants), winged flyers (flying monster, dragon), insect
// swarms and robots. Top-down, facing +x, 4 animation frames each.

import CoreGraphics
import EvolutionDefenseCore

enum CreatureFamily {
    case biped(BipedStyle)
    case winged(WingedStyle)
    case insect
    case robot(RobotKind)
}

struct BipedStyle {
    var skin: UInt32
    var light: UInt32
    var dark: UInt32
    var eye: UInt32 = 0x111111
    var eyeGlow = false
    var club = false
    var glowSpots: UInt32? = nil
    var aura: UInt32? = nil
    var horns = false
    var extraArms = false
}

struct WingedStyle {
    var body: UInt32
    var light: UInt32
    var membrane: UInt32
    var dark: UInt32
    var eye: UInt32
    var dragon = false
}

enum RobotKind { case scout, assault, heavy, stealth, titan }

enum CreatureArt {
    static func family(for visual: String) -> CreatureFamily? {
        switch visual {
        case "troll":
            return .biped(BipedStyle(skin: 0x6B7A55, light: 0xA2B283, dark: 0x3A4430, club: true))
        case "giantMutant":
            return .biped(BipedStyle(skin: 0x6E5A7A, light: 0xA88BB6, dark: 0x392C42, eye: 0xD6FF3A, eyeGlow: true,
                                     glowSpots: 0xB6FF2E))
        case "mutantTitan":
            return .biped(BipedStyle(skin: 0x55406A, light: 0x9C7CBF, dark: 0x2A1E36, eye: 0xFF3B30, eyeGlow: true,
                                     glowSpots: 0xB6FF2E, aura: 0x8CFF3A, horns: true, extraArms: true))
        case "flyingMonster":
            return .winged(WingedStyle(body: 0x4B3A5C, light: 0x8A70A6, membrane: 0x6E4F87, dark: 0x251C2E, eye: 0xFFD23A))
        case "ancientDragon":
            return .winged(WingedStyle(body: 0x7A2A22, light: 0xD2603F, membrane: 0x9C3A2A, dark: 0x3A120E, eye: 0xFFE14A,
                                       dragon: true))
        case "swarmCreature": return .insect
        case "scoutRobot": return .robot(.scout)
        case "assaultRobot": return .robot(.assault)
        case "heavyMech": return .robot(.heavy)
        case "stealthRobot": return .robot(.stealth)
        case "titanWarMachine": return .robot(.titan)
        default: return nil
        }
    }

    static func canvasSize(radius r: CGFloat, family: CreatureFamily) -> CGSize {
        switch family {
        case .biped(let s): return CGSize(width: (r * 2.6).rounded(.up) + 10, height: (r * (s.aura != nil ? 3.4 : 3.0)).rounded(.up) + 10)
        case .winged(let w): return CGSize(width: (r * (w.dragon ? 4.2 : 3.0)).rounded(.up) + 10, height: (r * 4.4).rounded(.up) + 16)
        case .insect: return CGSize(width: (r * 3.4).rounded(.up) + 8, height: (r * 3.0).rounded(.up) + 8)
        case .robot(let k): return CGSize(width: (r * (k == .titan ? 3.4 : 2.8)).rounded(.up) + 10, height: (r * (k == .titan ? 3.4 : 2.8)).rounded(.up) + 10)
        }
    }

    static func drawFrame(_ ctx: CGContext, size: CGSize, radius r: CGFloat, family: CreatureFamily, frame: Int) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let phase = CGFloat(frame) / 4 * 2 * .pi
        switch family {
        case .biped(let s): drawBiped(ctx, c, r, s, phase)
        case .winged(let w): drawWinged(ctx, c, r, w, phase)
        case .insect: drawInsect(ctx, c, r, phase)
        case .robot(let k): drawRobot(ctx, c, r, k, phase)
        }
    }

    // MARK: Bipeds

    private static func drawBiped(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ s: BipedStyle, _ phase: CGFloat) {
        let swing = sin(phase) * r * 0.32
        if let aura = s.aura { ctx.radialGlow(c, r * 1.6, aura, alpha: 0.4) }
        ctx.softShadow(CGPoint(x: c.x + 3, y: c.y - 4), r * 0.95, r * 1.15, alpha: 0.35)
        // Feet, alternating
        for (side, sw) in [(CGFloat(1), swing), (-1, -swing)] {
            ctx.fillEllipse(CGPoint(x: c.x + sw * 0.7, y: c.y + side * r * 0.42), r * 0.3, r * 0.2, rgb(s.dark))
        }
        // Arms (swing opposite the feet)
        let armPairs: [CGFloat] = s.extraArms ? [1, -1, 0.6, -0.6] : [1, -1]
        for side in armPairs {
            let sw = (side > 0 ? -swing : swing) * (abs(side) < 1 ? 0.6 : 1)
            let shoulder = CGPoint(x: c.x + (abs(side) < 1 ? -r * 0.2 : 0), y: c.y + side * r * 0.82)
            let hand = CGPoint(x: shoulder.x + r * 0.45 + sw, y: shoulder.y + side * r * 0.12)
            ctx.strokeLine(shoulder, hand, rgb(s.dark), width: r * 0.36)
            ctx.strokeLine(shoulder, hand, rgb(s.skin), width: r * 0.26)
            ctx.fillCircle(hand, r * 0.2, rgb(s.light))
            if s.club && side > 0 {
                let tip = CGPoint(x: hand.x + r * 0.9, y: hand.y + r * 0.25)
                ctx.strokeLine(hand, tip, rgb(0x5A3A1C), width: r * 0.22)
                ctx.fillEllipse(tip, r * 0.3, r * 0.26, rgb(0x6E4523))
                ctx.fillCircle(CGPoint(x: tip.x + r * 0.08, y: tip.y + r * 0.12), r * 0.07, rgb(0xC9C2B0))
            }
        }
        // Torso (wide shoulders across y)
        ctx.shadedEllipse(c, r * 0.72, r * 0.98, base: s.skin, light: s.light)
        ctx.fillEllipse(CGPoint(x: c.x - r * 0.18, y: c.y), r * 0.3, r * 0.6, rgb(s.dark, 0.35))
        if let glow = s.glowSpots {
            var rng = ArtRandom(UInt64(s.skin))
            for _ in 0..<7 {
                let p = CGPoint(x: c.x + rng.range(-r * 0.5, r * 0.4), y: c.y + rng.range(-r * 0.75, r * 0.75))
                let pr = rng.range(r * 0.06, r * 0.12)
                ctx.radialGlow(p, pr * 2.5, glow, alpha: 0.6)
                ctx.fillCircle(p, pr, rgb(mix(glow, 0xFFFFFF, 0.3)))
            }
        }
        // Head (forward, small, hunched)
        let head = CGPoint(x: c.x + r * 0.5, y: c.y + sin(phase * 2) * r * 0.03)
        if s.horns {
            for side: CGFloat in [-1, 1] {
                ctx.fillPolygon([CGPoint(x: head.x - r * 0.05, y: head.y + side * r * 0.2),
                                 CGPoint(x: head.x - r * 0.35, y: head.y + side * r * 0.62),
                                 CGPoint(x: head.x + r * 0.12, y: head.y + side * r * 0.32)], rgb(0xE8E0CC))
            }
        }
        ctx.shadedEllipse(head, r * 0.32, r * 0.34, base: s.skin, light: s.light)
        for side: CGFloat in [-1, 1] {
            let e = CGPoint(x: head.x + r * 0.16, y: head.y + side * r * 0.13)
            if s.eyeGlow { ctx.radialGlow(e, r * 0.16, s.eye, alpha: 0.9) }
            ctx.fillCircle(e, max(1.2, r * 0.055), rgb(s.eye))
        }
    }

    // MARK: Flyers

    private static func drawWinged(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ w: WingedStyle, _ phase: CGFloat) {
        let flap = 0.65 + 0.35 * sin(phase)           // wing span factor
        // Shadow far below: the creature is airborne.
        ctx.softShadow(CGPoint(x: c.x + r * 0.5, y: c.y - r * 1.3), r * (w.dragon ? 1.3 : 0.9), r * 0.9 * flap, alpha: 0.22)
        if w.dragon { ctx.radialGlow(c, r * 1.9, 0xFF6A2A, alpha: 0.3) }
        // Wings: membrane between "finger" bones.
        for side: CGFloat in [-1, 1] {
            let root = CGPoint(x: c.x + r * 0.1, y: c.y + side * r * 0.25)
            let span = r * (w.dragon ? 2.0 : 1.75) * flap
            let tip = CGPoint(x: c.x - r * 0.35, y: c.y + side * span)
            let front = CGPoint(x: c.x + r * 0.45, y: c.y + side * span * 0.72)
            let back1 = CGPoint(x: c.x - r * 0.95, y: c.y + side * span * 0.7)
            let back2 = CGPoint(x: c.x - r * 0.7, y: c.y + side * span * 0.35)
            ctx.fillPolygon([root, front, tip, back1, back2], rgb(w.membrane, 0.92))
            ctx.fillPolygon([root, front, tip], rgb(mix(w.membrane, 0xFFFFFF, 0.12), 0.9))
            for bone in [front, tip, back1] { ctx.strokeLine(root, bone, rgb(w.dark), width: max(1.2, r * 0.07)) }
        }
        // Tail
        let tailLen = r * (w.dragon ? 1.9 : 1.1)
        let wag = sin(phase) * r * 0.25
        ctx.setStrokeColor(rgb(w.body)); ctx.setLineWidth(r * (w.dragon ? 0.3 : 0.16))
        ctx.beginPath(); ctx.move(to: CGPoint(x: c.x - r * 0.4, y: c.y))
        ctx.addQuadCurve(to: CGPoint(x: c.x - r * 0.4 - tailLen, y: c.y + wag),
                         control: CGPoint(x: c.x - r * 0.4 - tailLen * 0.5, y: c.y - wag))
        ctx.strokePath()
        if w.dragon {
            let t = CGPoint(x: c.x - r * 0.4 - tailLen, y: c.y + wag)
            ctx.fillPolygon([t, CGPoint(x: t.x - r * 0.35, y: t.y + r * 0.2), CGPoint(x: t.x - r * 0.35, y: t.y - r * 0.2)], rgb(w.dark))
        }
        // Body
        ctx.shadedEllipse(c, r * (w.dragon ? 0.8 : 0.6), r * 0.42, base: w.body, light: w.light)
        if w.dragon {
            for i in 0..<5 {
                let x = c.x - r * 0.55 + CGFloat(i) * r * 0.28
                ctx.fillPolygon([CGPoint(x: x - r * 0.08, y: c.y - r * 0.07), CGPoint(x: x + r * 0.14, y: c.y),
                                 CGPoint(x: x - r * 0.08, y: c.y + r * 0.07)], rgb(0xF2C14E))
            }
        }
        // Neck + head
        let neck = w.dragon ? r * 0.75 : r * 0.35
        let head = CGPoint(x: c.x + r * 0.55 + neck, y: c.y + sin(phase * 2) * r * 0.05)
        if w.dragon { ctx.strokeLine(CGPoint(x: c.x + r * 0.5, y: c.y), head, rgb(w.body), width: r * 0.3) }
        let hr = r * (w.dragon ? 0.34 : 0.3)
        if w.dragon {
            for side: CGFloat in [-1, 1] {
                ctx.fillPolygon([CGPoint(x: head.x - hr * 0.3, y: head.y + side * hr * 0.4),
                                 CGPoint(x: head.x - hr * 1.6, y: head.y + side * hr * 1.0),
                                 CGPoint(x: head.x - hr * 0.1, y: head.y + side * hr * 0.75)], rgb(0xE8DCC0))
            }
        } else {
            for side: CGFloat in [-1, 1] {
                ctx.fillPolygon([CGPoint(x: head.x - hr * 0.2, y: head.y + side * hr * 0.5),
                                 CGPoint(x: head.x - hr * 0.9, y: head.y + side * hr * 1.3),
                                 CGPoint(x: head.x + hr * 0.2, y: head.y + side * hr * 0.9)], rgb(w.dark))
            }
        }
        ctx.shadedEllipse(head, hr * (w.dragon ? 1.4 : 1), hr, base: w.body, light: w.light)
        for side: CGFloat in [-1, 1] {
            let e = CGPoint(x: head.x + hr * 0.35, y: head.y + side * hr * 0.42)
            ctx.radialGlow(e, hr * 0.5, w.eye, alpha: 0.8)
            ctx.fillCircle(e, max(1.1, hr * 0.15), rgb(w.eye))
        }
    }

    // MARK: Swarm insect

    private static func drawInsect(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ phase: CGFloat) {
        ctx.softShadow(CGPoint(x: c.x + 2, y: c.y - 2), r * 1.2, r * 0.8, alpha: 0.3)
        let legSwing = sin(phase) * r * 0.35
        for i in 0..<3 {
            let x = c.x + r * (0.35 - CGFloat(i) * 0.45)
            for side: CGFloat in [-1, 1] {
                let sw = (i % 2 == 0 ? legSwing : -legSwing) * side
                ctx.strokeLine(CGPoint(x: x, y: c.y + side * r * 0.3),
                               CGPoint(x: x + sw, y: c.y + side * r * 1.15), rgb(0x2B2A10), width: max(1, r * 0.13))
            }
        }
        ctx.shadedEllipse(CGPoint(x: c.x - r * 0.75, y: c.y), r * 0.7, r * 0.55, base: 0x8C8F1E, light: 0xE3E86A)
        for k in 0..<3 {
            ctx.strokeLine(CGPoint(x: c.x - r * (0.45 + CGFloat(k) * 0.25), y: c.y - r * 0.45),
                           CGPoint(x: c.x - r * (0.45 + CGFloat(k) * 0.25), y: c.y + r * 0.45), rgb(0x3D3F0A, 0.7), width: 1)
        }
        ctx.shadedEllipse(c, r * 0.45, r * 0.4, base: 0x6E7314, light: 0xC2C84A)
        let head = CGPoint(x: c.x + r * 0.55, y: c.y)
        ctx.shadedEllipse(head, r * 0.32, r * 0.34, base: 0x4D500C, light: 0x9EA332)
        for side: CGFloat in [-1, 1] {
            ctx.strokeLine(CGPoint(x: head.x + r * 0.2, y: head.y + side * r * 0.12),
                           CGPoint(x: head.x + r * 0.55, y: head.y + side * r * 0.05), rgb(0xE8D9A0), width: max(1, r * 0.1))
            ctx.fillCircle(CGPoint(x: head.x + r * 0.08, y: head.y + side * r * 0.2), max(1, r * 0.1), rgb(0xFF4A2A))
        }
    }

    // MARK: Robots

    private static func drawRobot(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ k: RobotKind, _ phase: CGFloat) {
        switch k {
        case .scout: drawScout(ctx, c, r, phase)
        case .assault: drawAssault(ctx, c, r, phase)
        case .heavy: drawHeavyMech(ctx, c, r, phase)
        case .stealth: drawStealth(ctx, c, r, phase)
        case .titan: drawTitan(ctx, c, r, phase)
        }
    }

    private static func rect(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    }

    private static func plate(_ ctx: CGContext, _ r: CGRect, _ base: UInt32, corner: CGFloat) {
        ctx.fillRoundedRect(r.offsetBy(dx: 1, dy: -1.5), radius: corner, rgb(0x000000, 0.35))
        ctx.fillRoundedRect(r, radius: corner, rgb(base))
        ctx.fillRoundedRect(r.insetBy(dx: r.width * 0.12, dy: r.height * 0.12).offsetBy(dx: -r.width * 0.05, dy: r.height * 0.05),
                            radius: corner * 0.7, rgb(mix(base, 0xFFFFFF, 0.28)))
    }

    private static func drawScout(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ phase: CGFloat) {
        ctx.softShadow(CGPoint(x: c.x + 2, y: c.y - 3), r * 1.1, r * 0.9, alpha: 0.3)
        // Four spider legs, scuttling
        for (i, (lx, side)) in [(CGFloat(0.4), CGFloat(1)), (0.4, -1), (-0.4, 1), (-0.4, -1)].enumerated() {
            let sw = sin(phase + CGFloat(i) * .pi / 2) * r * 0.25
            let hip = CGPoint(x: c.x + lx * r, y: c.y + side * r * 0.4)
            let foot = CGPoint(x: hip.x + sw + lx * r * 0.5, y: hip.y + side * r * 0.65)
            ctx.strokeLine(hip, foot, rgb(0x3A4048), width: max(1.4, r * 0.14))
            ctx.fillCircle(foot, r * 0.1, rgb(0x20242A))
        }
        let hex = (0..<6).map { i -> CGPoint in
            let a = CGFloat(i) / 6 * 2 * .pi
            return CGPoint(x: c.x + cos(a) * r * 0.72, y: c.y + sin(a) * r * 0.62)
        }
        ctx.fillPolygon(hex, rgb(0xB8C0C8))
        ctx.fillPolygon(hex.map { CGPoint(x: c.x + ($0.x - c.x) * 0.7 - 1, y: c.y + ($0.y - c.y) * 0.7 + 1) }, rgb(0xDDE3E8))
        ctx.fillRoundedRect(rect(CGPoint(x: c.x - r * 0.2, y: c.y), r * 0.5, r * 0.18), radius: 2, rgb(0x2FB8E8, 0.9))
        let eye = CGPoint(x: c.x + r * 0.55, y: c.y)
        ctx.radialGlow(eye, r * 0.45, 0x3FE0FF, alpha: 0.9)
        ctx.fillCircle(eye, r * 0.16, rgb(0xE8FCFF))
    }

    private static func drawAssault(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ phase: CGFloat) {
        let step = sin(phase) * r * 0.3
        ctx.softShadow(CGPoint(x: c.x + 3, y: c.y - 4), r * 0.95, r * 1.05, alpha: 0.35)
        for (side, sw) in [(CGFloat(1), step), (-1, -step)] {
            ctx.fillRoundedRect(rect(CGPoint(x: c.x + sw, y: c.y + side * r * 0.45), r * 0.6, r * 0.32), radius: 3, rgb(0x2E3440))
        }
        // Gun arms
        for side: CGFloat in [-1, 1] {
            let shoulder = CGPoint(x: c.x + r * 0.05, y: c.y + side * r * 0.78)
            plate(ctx, rect(shoulder, r * 0.55, r * 0.42), 0x5A6472, corner: 4)
            ctx.fillRoundedRect(CGRect(x: shoulder.x, y: shoulder.y - r * 0.09, width: r * 0.95, height: r * 0.18), radius: 2, rgb(0x1E2228))
            ctx.fillCircle(CGPoint(x: shoulder.x + r * 0.95, y: shoulder.y), r * 0.07, rgb(0xFF5A3A))
        }
        plate(ctx, rect(c, r * 1.05, r * 1.25), 0x7A8696, corner: 6)
        ctx.fillRoundedRect(rect(CGPoint(x: c.x - r * 0.15, y: c.y), r * 0.12, r * 0.8), radius: 2, rgb(0xE85A2A, 0.85))
        // Head + visor
        let head = CGPoint(x: c.x + r * 0.42, y: c.y)
        plate(ctx, rect(head, r * 0.42, r * 0.5), 0x9AA6B5, corner: 5)
        ctx.fillRoundedRect(rect(CGPoint(x: head.x + r * 0.12, y: head.y), r * 0.12, r * 0.38), radius: 2, rgb(0xFF6A2A))
        ctx.radialGlow(CGPoint(x: head.x + r * 0.14, y: head.y), r * 0.3, 0xFF6A2A, alpha: 0.6)
    }

    private static func drawHeavyMech(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ phase: CGFloat) {
        ctx.softShadow(CGPoint(x: c.x + 3, y: c.y - 5), r * 1.15, r * 1.0, alpha: 0.4)
        // Treads with moving links
        for side: CGFloat in [-1, 1] {
            let tr = rect(CGPoint(x: c.x, y: c.y + side * r * 0.72), r * 2.0, r * 0.46)
            ctx.fillRoundedRect(tr, radius: r * 0.2, rgb(0x23272C))
            let offset = (phase / (2 * .pi)) * r * 0.3
            var x = tr.minX + offset.truncatingRemainder(dividingBy: r * 0.3)
            while x < tr.maxX - 2 {
                ctx.strokeLine(CGPoint(x: x, y: tr.minY + 2), CGPoint(x: x, y: tr.maxY - 2), rgb(0x4A5058), width: 1.5)
                x += r * 0.3
            }
        }
        plate(ctx, rect(c, r * 1.6, r * 1.15), 0x6A6E58, corner: 6)
        // Hazard stripes on the front
        for i in 0..<4 {
            let y = c.y - r * 0.45 + CGFloat(i) * r * 0.3
            ctx.fillPolygon([CGPoint(x: c.x + r * 0.62, y: y), CGPoint(x: c.x + r * 0.78, y: y + r * 0.15),
                             CGPoint(x: c.x + r * 0.78, y: y + r * 0.27), CGPoint(x: c.x + r * 0.62, y: y + r * 0.12)], rgb(0xE8B82A))
        }
        // Turret with twin cannons
        ctx.fillCircle(CGPoint(x: c.x - r * 0.05, y: c.y - r * 0.04), r * 0.5, rgb(0x000000, 0.3))
        ctx.shadedEllipse(c, r * 0.48, r * 0.48, base: 0x585C49, light: 0x9EA286)
        for side: CGFloat in [-1, 1] {
            ctx.fillRoundedRect(CGRect(x: c.x + r * 0.2, y: c.y + side * r * 0.17 - r * 0.09, width: r * 1.05, height: r * 0.18),
                                radius: 2, rgb(0x2C2F28))
        }
        ctx.fillCircle(CGPoint(x: c.x - r * 0.15, y: c.y + r * 0.18), r * 0.08, rgb(0xFF4A2A))
    }

    private static func drawStealth(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ phase: CGFloat) {
        ctx.softShadow(CGPoint(x: c.x + 2, y: c.y - 3), r * 1.0, r * 0.8, alpha: 0.28)
        let pulse = 0.55 + 0.45 * sin(phase)
        let shape = [CGPoint(x: c.x + r * 1.05, y: c.y), CGPoint(x: c.x - r * 0.3, y: c.y + r * 0.95),
                     CGPoint(x: c.x - r * 0.85, y: c.y + r * 0.35), CGPoint(x: c.x - r * 0.6, y: c.y),
                     CGPoint(x: c.x - r * 0.85, y: c.y - r * 0.35), CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.95)]
        ctx.fillPolygon(shape, rgb(0x1E1F2E))
        ctx.fillPolygon(shape.map { CGPoint(x: c.x + ($0.x - c.x) * 0.72, y: c.y + ($0.y - c.y) * 0.72 + 1) }, rgb(0x34364E))
        // Glowing circuit lines
        ctx.strokeLine(CGPoint(x: c.x - r * 0.5, y: c.y), CGPoint(x: c.x + r * 0.7, y: c.y), rgb(0xB65CFF, 0.5 + 0.5 * pulse), width: 1.5)
        for side: CGFloat in [-1, 1] {
            ctx.strokeLine(CGPoint(x: c.x, y: c.y), CGPoint(x: c.x - r * 0.3, y: c.y + side * r * 0.75),
                           rgb(0xB65CFF, 0.4 + 0.5 * pulse), width: 1.2)
        }
        ctx.radialGlow(CGPoint(x: c.x + r * 0.55, y: c.y), r * 0.4, 0xC77DFF, alpha: 0.5 + 0.4 * pulse)
        ctx.fillCircle(CGPoint(x: c.x + r * 0.55, y: c.y), r * 0.1, rgb(0xF2E6FF))
    }

    private static func drawTitan(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ phase: CGFloat) {
        ctx.radialGlow(c, r * 1.6, 0xFF3020, alpha: 0.28)
        ctx.softShadow(CGPoint(x: c.x + 5, y: c.y - 7), r * 1.25, r * 1.15, alpha: 0.45)
        // Four walker legs, diagonal pairs
        let legs: [(CGFloat, CGFloat)] = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        for (i, (sx, sy)) in legs.enumerated() {
            let sw = sin(phase + (i == 0 || i == 3 ? 0 : .pi)) * r * 0.18
            let hip = CGPoint(x: c.x + sx * r * 0.45, y: c.y + sy * r * 0.45)
            let knee = CGPoint(x: c.x + sx * r * 0.85 + sw, y: c.y + sy * r * 0.95)
            let foot = CGPoint(x: c.x + sx * r * 0.95 + sw * 1.4, y: c.y + sy * r * 1.25)
            ctx.strokeLine(hip, knee, rgb(0x2A2E35), width: r * 0.22)
            ctx.strokeLine(knee, foot, rgb(0x3A3F48), width: r * 0.16)
            ctx.fillEllipse(foot, r * 0.18, r * 0.14, rgb(0x1A1D22))
            ctx.fillCircle(knee, r * 0.1, rgb(0x5A606B))
        }
        // Hull
        let hull = [CGPoint(x: c.x + r * 0.95, y: c.y), CGPoint(x: c.x + r * 0.55, y: c.y + r * 0.75),
                    CGPoint(x: c.x - r * 0.7, y: c.y + r * 0.7), CGPoint(x: c.x - r * 0.95, y: c.y),
                    CGPoint(x: c.x - r * 0.7, y: c.y - r * 0.7), CGPoint(x: c.x + r * 0.55, y: c.y - r * 0.75)]
        ctx.fillPolygon(hull.map { $0 + CGPoint(x: 2, y: -3) }, rgb(0x000000, 0.35))
        ctx.fillPolygon(hull, rgb(0x4A4F5A))
        ctx.fillPolygon(hull.map { CGPoint(x: c.x + ($0.x - c.x) * 0.78 - 2, y: c.y + ($0.y - c.y) * 0.78 + 2) }, rgb(0x6C7380))
        // Armor seams and hazard band
        ctx.strokeLine(CGPoint(x: c.x - r * 0.5, y: c.y - r * 0.55), CGPoint(x: c.x - r * 0.5, y: c.y + r * 0.55), rgb(0x2A2E35), width: 2)
        for i in 0..<5 {
            let y = c.y - r * 0.5 + CGFloat(i) * r * 0.22
            ctx.fillPolygon([CGPoint(x: c.x - r * 0.72, y: y), CGPoint(x: c.x - r * 0.6, y: y + r * 0.1),
                             CGPoint(x: c.x - r * 0.6, y: y + r * 0.18), CGPoint(x: c.x - r * 0.72, y: y + r * 0.08)], rgb(0xE8B82A))
        }
        // Missile pods
        for side: CGFloat in [-1, 1] {
            let pod = rect(CGPoint(x: c.x - r * 0.1, y: c.y + side * r * 0.48), r * 0.55, r * 0.3)
            ctx.fillRoundedRect(pod, radius: 3, rgb(0x30343C))
            for k in 0..<3 { ctx.fillCircle(CGPoint(x: pod.minX + pod.width * (0.22 + CGFloat(k) * 0.28), y: pod.midY), r * 0.06, rgb(0xFF5A3A)) }
        }
        // Main cannon
        ctx.fillRoundedRect(CGRect(x: c.x + r * 0.2, y: c.y - r * 0.13, width: r * 1.15, height: r * 0.26), radius: 3, rgb(0x23262C))
        ctx.fillRoundedRect(CGRect(x: c.x + r * 1.15, y: c.y - r * 0.17, width: r * 0.2, height: r * 0.34), radius: 2, rgb(0x3A3F48))
        // Reactor core
        ctx.radialGlow(CGPoint(x: c.x + r * 0.05, y: c.y), r * 0.45, 0xFF3A2A, alpha: 0.85)
        ctx.fillCircle(CGPoint(x: c.x + r * 0.05, y: c.y), r * 0.14, rgb(0xFFE0C0))
    }
}
