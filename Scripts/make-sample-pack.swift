// Generates the SAMPLE replacement art pack used to prove that the game's
// visuals can be swapped without code changes (see Docs/ASSETS.md).
//
//   swift Scripts/make-sample-pack.swift
//
// Writes:
//   EvolutionDefense/Assets.xcassets/SampleCreatures.spriteatlas/…  (atlas frames: wolf walk + death)
//   EvolutionDefense/AssetPack/Samples/*.png                         (loose @2x images: tower, projectile, base)
// The matching manifest is EvolutionDefense/AssetPack/asset_manifest.sample.json.
// Deliberately a different style (flat, outlined, side view) from the placeholders.

import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let looseDir = root.appendingPathComponent("EvolutionDefense/AssetPack/Samples")
let atlasDir = root.appendingPathComponent("EvolutionDefense/Assets.xcassets/SampleCreatures.spriteatlas")
try? FileManager.default.createDirectory(at: looseDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: atlasDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Draws at 2× and returns PNG data. `size` in points.
func png(_ size: CGSize, _ draw: (CGContext) -> Void) -> Data {
    let w = Int(size.width * 2), h = Int(size.height * 2)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: 2, y: 2)
    ctx.setLineJoin(.round); ctx.setLineCap(.round)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func outlined(_ ctx: CGContext, _ path: CGPath, fill: UInt32, line: CGFloat = 2.5) {
    ctx.addPath(path); ctx.setFillColor(color(fill)); ctx.fillPath()
    ctx.addPath(path); ctx.setStrokeColor(color(0x1B1530)); ctx.setLineWidth(line); ctx.strokePath()
}

func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2), transform: nil)
}

// MARK: Wolf — side view, facing right, 4 walk frames + 3 death frames (atlas)

let wolfSize = CGSize(width: 60, height: 44)
func wolf(_ ctx: CGContext, legPhase: CGFloat, fall: CGFloat = 0, alpha: CGFloat = 1) {
    ctx.setAlpha(alpha)
    ctx.translateBy(x: 30, y: 20)
    ctx.rotate(by: -fall * .pi / 2)
    ctx.translateBy(x: -30, y: -20)
    ctx.setFillColor(color(0x000000, 0.18)); ctx.fillEllipse(in: CGRect(x: 10, y: 2, width: 40, height: 7))
    for (i, x) in [18.0, 24.0, 38.0, 44.0].enumerated() {
        let swing = sin(legPhase + (i % 2 == 0 ? 0 : .pi)) * 5
        let leg = CGMutablePath()
        leg.move(to: CGPoint(x: x, y: 18)); leg.addLine(to: CGPoint(x: x + swing, y: 6))
        ctx.addPath(leg); ctx.setStrokeColor(color(0x1B1530)); ctx.setLineWidth(5); ctx.strokePath()
        ctx.addPath(leg); ctx.setStrokeColor(color(0x6C7AE0)); ctx.setLineWidth(2.6); ctx.strokePath()
    }
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 13, y: 22)); tail.addQuadCurve(to: CGPoint(x: 2, y: 30 + sin(legPhase) * 3), control: CGPoint(x: 4, y: 20))
    ctx.addPath(tail); ctx.setStrokeColor(color(0x1B1530)); ctx.setLineWidth(6); ctx.strokePath()
    ctx.addPath(tail); ctx.setStrokeColor(color(0x8FA0FF)); ctx.setLineWidth(3.5); ctx.strokePath()
    outlined(ctx, ellipse(CGPoint(x: 30, y: 22), 19, 9), fill: 0x8FA0FF)
    outlined(ctx, ellipse(CGPoint(x: 48, y: 28), 9, 8), fill: 0x8FA0FF)
    let snout = CGMutablePath()
    snout.move(to: CGPoint(x: 52, y: 31)); snout.addLine(to: CGPoint(x: 60, y: 26)); snout.addLine(to: CGPoint(x: 52, y: 23)); snout.closeSubpath()
    outlined(ctx, snout, fill: 0xB8C2FF, line: 2)
    let ear = CGMutablePath()
    ear.move(to: CGPoint(x: 43, y: 33)); ear.addLine(to: CGPoint(x: 45, y: 42)); ear.addLine(to: CGPoint(x: 49, y: 35)); ear.closeSubpath()
    outlined(ctx, ear, fill: 0x6C7AE0, line: 2)
    ctx.setFillColor(color(0xFFE14A)); ctx.fillEllipse(in: CGRect(x: 49, y: 28, width: 4, height: 4))
}

func writeAtlasFrame(_ name: String, _ data: Data) {
    let set = atlasDir.appendingPathComponent("\(name).imageset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    try! data.write(to: set.appendingPathComponent("\(name)@2x.png"))
    let contents = """
    { "images" : [ { "idiom" : "universal", "scale" : "1x" },
                   { "filename" : "\(name)@2x.png", "idiom" : "universal", "scale" : "2x" },
                   { "idiom" : "universal", "scale" : "3x" } ],
      "info" : { "author" : "xcode", "version" : 1 } }
    """
    try! contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

try! """
{ "info" : { "author" : "xcode", "version" : 1 } }
""".write(to: atlasDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
for i in 0..<4 {
    writeAtlasFrame("sample_wolf_walk_\(i)", png(wolfSize) { wolf($0, legPhase: CGFloat(i) / 4 * 2 * .pi) })
}
for i in 0..<3 {
    let k = CGFloat(i + 1) / 3
    writeAtlasFrame("sample_wolf_death_\(i)", png(wolfSize) { wolf($0, legPhase: 0, fall: k * 0.5, alpha: 1 - k * 0.7) })
}

// MARK: Splash tower level 1 — loose @2x PNGs (base + rotating head)

let towerSize = CGSize(width: 72, height: 72)
try! png(towerSize) { ctx in
    let c = CGPoint(x: 36, y: 36)
    ctx.setFillColor(color(0x000000, 0.2)); ctx.fillEllipse(in: CGRect(x: 8, y: 4, width: 60, height: 58))
    outlined(ctx, CGPath(roundedRect: CGRect(x: 8, y: 8, width: 56, height: 56), cornerWidth: 14, cornerHeight: 14, transform: nil), fill: 0xF4B860, line: 3)
    outlined(ctx, ellipse(c, 18, 18), fill: 0xE08A3C)
    for k in 0..<4 {
        let a = CGFloat(k) * .pi / 2 + .pi / 4
        outlined(ctx, ellipse(CGPoint(x: c.x + cos(a) * 24, y: c.y + sin(a) * 24), 4, 4), fill: 0xFFF1C9, line: 2)
    }
}.write(to: looseDir.appendingPathComponent("sample_tower_splash_1_base@2x.png"))
try! png(towerSize) { ctx in
    // Head faces +x: a chunky mortar tube.
    outlined(ctx, CGPath(roundedRect: CGRect(x: 30, y: 28, width: 32, height: 16), cornerWidth: 6, cornerHeight: 6, transform: nil), fill: 0x5B4FC9, line: 3)
    outlined(ctx, ellipse(CGPoint(x: 36, y: 36), 12, 12), fill: 0x8678FF)
    outlined(ctx, ellipse(CGPoint(x: 60, y: 36), 4, 9), fill: 0x2E2770, line: 2)
}.write(to: looseDir.appendingPathComponent("sample_tower_splash_1_head@2x.png"))

// MARK: Stone projectile and the Primitive-era base

try! png(CGSize(width: 16, height: 16)) { ctx in
    outlined(ctx, ellipse(CGPoint(x: 8, y: 8), 5.5, 5.5), fill: 0xFFD166, line: 2)
}.write(to: looseDir.appendingPathComponent("sample_projectile_stone@2x.png"))

try! png(CGSize(width: 180, height: 180)) { ctx in
    let c = CGPoint(x: 90, y: 90)
    ctx.setFillColor(color(0x000000, 0.2)); ctx.fillEllipse(in: CGRect(x: 14, y: 6, width: 156, height: 150))
    outlined(ctx, ellipse(c, 72, 72), fill: 0xC9F2C7, line: 4)
    for k in 0..<3 {
        let a = CGFloat(k) / 3 * 2 * .pi + 0.4
        let p = CGPoint(x: c.x + cos(a) * 34, y: c.y + sin(a) * 34)
        let roof = CGMutablePath()
        roof.move(to: CGPoint(x: p.x - 20, y: p.y - 12)); roof.addLine(to: CGPoint(x: p.x, y: p.y + 20))
        roof.addLine(to: CGPoint(x: p.x + 20, y: p.y - 12)); roof.closeSubpath()
        outlined(ctx, roof, fill: [0xFF7B7B, 0x7BC4FF, 0xFFD166][k], line: 3)
    }
    outlined(ctx, ellipse(c, 12, 12), fill: 0xFFF1C9, line: 3)
}.write(to: looseDir.appendingPathComponent("sample_base_primitive@2x.png"))

print("Sample pack written to \(looseDir.path) and \(atlasDir.path)")
