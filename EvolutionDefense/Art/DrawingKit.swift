// TEMPORARY ART — procedural drawing helpers.
//
// Everything under Art/ draws stylized placeholder assets in code with
// CoreGraphics at launch. It is deliberately isolated: production PNG assets
// can replace it by changing ArtLibrary only, with no gameplay changes.

import AppKit
import CoreGraphics

@inline(__always)
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func mix(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UInt32 {
    func ch(_ v: UInt32, _ s: UInt32) -> CGFloat { CGFloat((v >> s) & 0xFF) }
    func m(_ s: UInt32) -> UInt32 { UInt32(max(0, min(255, ch(a, s) + (ch(b, s) - ch(a, s)) * t))) }
    return (m(16) << 16) | (m(8) << 8) | m(0)
}

/// Renders a bitmap at `scale`× (Retina) using a y-up coordinate system that
/// matches SpriteKit. `size` is in points.
func renderImage(size: CGSize, scale: CGFloat = 2, _ draw: (CGContext) -> Void) -> CGImage {
    let w = max(1, Int((size.width * scale).rounded(.up)))
    let h = max(1, Int((size.height * scale).rounded(.up)))
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

extension CGContext {
    func fillEllipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ color: CGColor) {
        setFillColor(color)
        fillEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    func fillCircle(_ c: CGPoint, _ r: CGFloat, _ color: CGColor) { fillEllipse(c, r, r, color) }

    func strokeCircle(_ c: CGPoint, _ r: CGFloat, _ color: CGColor, width: CGFloat) {
        setStrokeColor(color)
        setLineWidth(width)
        strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    func fillPolygon(_ pts: [CGPoint], _ color: CGColor) {
        guard let first = pts.first else { return }
        setFillColor(color)
        beginPath(); move(to: first)
        for p in pts.dropFirst() { addLine(to: p) }
        closePath(); fillPath()
    }

    func strokeLine(_ a: CGPoint, _ b: CGPoint, _ color: CGColor, width: CGFloat) {
        setStrokeColor(color); setLineWidth(width)
        beginPath(); move(to: a); addLine(to: b); strokePath()
    }

    func fillRoundedRect(_ r: CGRect, radius: CGFloat, _ color: CGColor) {
        setFillColor(color)
        addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        fillPath()
    }

    /// Radial glow: `color` at the centre fading to transparent at `r`.
    func radialGlow(_ c: CGPoint, _ r: CGFloat, _ hex: UInt32, alpha: CGFloat) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [rgb(hex, alpha), rgb(hex, 0)] as CFArray
        guard let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
        drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }

    /// Soft drop shadow ellipse.
    func softShadow(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, alpha: CGFloat = 0.28) {
        saveGState()
        setShadow(offset: .zero, blur: min(rx, ry) * 0.6, color: rgb(0x000000, alpha))
        fillEllipse(c, rx * 0.85, ry * 0.85, rgb(0x000000, alpha))
        restoreGState()
    }

    /// Ellipse shaded from a lighter top-left to the base colour.
    func shadedEllipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, base: UInt32, light: UInt32) {
        fillEllipse(c, rx, ry, rgb(base))
        saveGState()
        addEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
        clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [rgb(light, 0.85), rgb(light, 0)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            let hc = CGPoint(x: c.x - rx * 0.25, y: c.y + ry * 0.35)
            drawRadialGradient(g, startCenter: hc, startRadius: 0, endCenter: hc, endRadius: max(rx, ry) * 1.1, options: [])
        }
        restoreGState()
    }
}

/// Deterministic RNG for repeatable art.
struct ArtRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}
