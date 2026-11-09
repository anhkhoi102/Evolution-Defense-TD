// Draws the Evolution Defense app icon into an .iconset folder for `iconutil`.
// Usage: swift Scripts/make-icon.swift <output.iconset>
import AppKit

guard CommandLine.arguments.count == 2 else { print("usage: make-icon.swift <out.iconset>"); exit(1) }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let g = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.22, cornerHeight: rect.width * 0.22, transform: nil)
    // Background: era gradient (primitive amber → futuristic cyan)
    g.saveGState(); g.addPath(path); g.clip()
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c(0x2B1A10), c(0x3A2414), c(0x0E2E3A), c(0x07141C)] as CFArray, locations: [0, 0.35, 0.7, 1])!
    g.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    // Winding path
    g.setLineCap(.round); g.setLineJoin(.round)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.75))
    p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.75))
    p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.3))
    p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.7, y: rect.minY + rect.height * 0.3))
    p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.7, y: rect.minY + rect.height * 0.62))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.62))
    g.addPath(p); g.setStrokeColor(c(0xC4A06A, 0.85)); g.setLineWidth(rect.width * 0.09); g.strokePath()
    g.restoreGState()
    // Tower: shield-like emblem in the centre
    let cx = s / 2, cy = s * 0.5
    let r = rect.width * 0.2
    g.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: c(0x000000, 0.6))
    g.setFillColor(c(0x8C8A82)); g.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    g.setShadow(offset: .zero, blur: 0, color: nil)
    g.setFillColor(c(0xFFCC45)); g.fillEllipse(in: CGRect(x: cx - r * 0.72, y: cy - r * 0.72, width: r * 1.44, height: r * 1.44))
    g.setFillColor(c(0x3FE0FF)); g.fillEllipse(in: CGRect(x: cx - r * 0.34, y: cy - r * 0.34, width: r * 0.68, height: r * 0.68))
    g.setStrokeColor(c(0xFFFFFF, 0.18)); g.setLineWidth(s * 0.006); g.addPath(path); g.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
