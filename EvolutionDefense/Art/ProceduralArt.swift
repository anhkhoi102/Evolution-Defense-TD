// TEMPORARY ART — the "procedural" asset source.
//
// The asset manifest can point any frame at a named generator instead of an
// image file. This file maps generator names to the CoreGraphics drawing code
// in this folder. Production art doesn't need any of it: replace the manifest
// entries with image/atlas frames and these generators are never called.

import CoreGraphics
import EvolutionDefenseAssets
import EvolutionDefenseCore

enum ProceduralArt {
    /// Renders one frame. Returns nil for an unknown generator or key
    /// (the library then falls back to its "missing asset" marker).
    static func render(_ p: ProceduralSource, config: GameConfiguration?) -> (image: CGImage, size: CGSize)? {
        let key = p.key ?? ""
        func draw(_ size: CGSize, scale: CGFloat = 2, _ body: (CGContext) -> Void) -> (CGImage, CGSize) {
            (renderImage(size: size, scale: scale, body), size)
        }
        switch p.procedural {
        case "creature":
            let r = CGFloat(p.radius ?? 16)
            let frame = p.frame ?? 0
            if let family = CreatureArt.family(for: key) {
                let size = CreatureArt.canvasSize(radius: r, family: family)
                return draw(size) { CreatureArt.drawFrame($0, size: size, radius: r, family: family, frame: frame) }
            }
            let style = EnemyArt.style(for: key)
            let size = EnemyArt.canvasSize(radius: r, style: style)
            return draw(size) { EnemyArt.drawFrame($0, size: size, radius: r, style: style, frame: frame) }
        case "towerBase", "towerHead":
            guard let a = TowerArchetype(rawValue: key) else { return nil }
            let level = p.level ?? 1
            let base = p.procedural == "towerBase"
            return draw(TowerArt.size) {
                if base { TowerArt.drawBase($0, archetype: a, level: level) } else { TowerArt.drawHead($0, archetype: a, level: level) }
            }
        case "projectile":
            guard let k = ProjectileKind(rawValue: key) else { return nil }
            let spec = ProjectileArt.spec(k)
            return draw(ProjectileArt.canvas(spec)) { ProjectileArt.draw($0, spec) }
        case "mapBackground":
            guard let map = config?.battlefield(key) else { return nil }
            return draw(map.worldSize) { MapArt.drawBackground($0, map: map) }
        case "slot":
            return draw(MapArt.slotSize) { MapArt.drawSlot($0, highlighted: key == "highlighted") }
        case "spawn":
            return draw(MapArt.spawnSize) { MapArt.drawSpawn($0) }
        case "base":
            guard let era = Era.allCases.first(where: { AssetValidator.eraKey($0) == key }) else { return nil }
            return draw(MapArt.baseSize) { MapArt.drawBase($0, era: era) }
        case "fx":
            return fx(key).map { size, body in draw(size, body) }
        case "ui":
            switch key {
            case "levelPip.on", "levelPip.off":
                let lit = key == "levelPip.on"
                return draw(CGSize(width: 9, height: 9)) { ctx in
                    let c = CGPoint(x: 4.5, y: 4.5)
                    ctx.fillCircle(c, 4.2, rgb(0x14161A, 0.85))
                    if lit { ctx.shadedEllipse(c, 3, 3, base: 0xE8A92E, light: 0xFFF0B8) } else { ctx.fillCircle(c, 2.6, rgb(0x4A4F57)) }
                }
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func fx(_ key: String) -> (CGSize, (CGContext) -> Void)? {
        switch key {
        case "explosion":
            let s = CGSize(width: 64, height: 64); return (s, { MapArt.drawExplosion($0, size: s) })
        case "puff":
            let s = CGSize(width: 48, height: 48); return (s, { MapArt.drawPuff($0, size: s) })
        case "spark":
            let s = CGSize(width: 20, height: 20); return (s, { MapArt.drawSpark($0, size: s) })
        case "ring":
            let s = CGSize(width: 128, height: 128); return (s, { MapArt.drawRing($0, size: s) })
        case "shadow":
            return (CGSize(width: 16, height: 10), { $0.fillEllipse(CGPoint(x: 8, y: 5), 7, 4, rgb(0x000000, 0.3)) })
        case "shield":
            return (CGSize(width: 64, height: 64), { ctx in
                let c = CGPoint(x: 32, y: 32)
                ctx.radialGlow(c, 31, 0x4FD8FF, alpha: 0.18)
                ctx.strokeCircle(c, 29, rgb(0x8FE8FF, 0.75), width: 2)
                ctx.strokeCircle(c, 25, rgb(0x4FD8FF, 0.25), width: 1)
                ctx.fillEllipse(CGPoint(x: 22, y: 42), 8, 5, rgb(0xFFFFFF, 0.25))
            })
        case "disabled":
            return (CGSize(width: 26, height: 26), { ctx in
                ctx.fillCircle(CGPoint(x: 13, y: 13), 12, rgb(0x14161A, 0.85))
                ctx.strokeCircle(CGPoint(x: 13, y: 13), 11.5, rgb(0x6FD2FF), width: 1.5)
                ctx.fillPolygon([CGPoint(x: 15, y: 22), CGPoint(x: 8, y: 12), CGPoint(x: 12.5, y: 12),
                                 CGPoint(x: 10, y: 4), CGPoint(x: 18, y: 15), CGPoint(x: 13.5, y: 15)], rgb(0xFFE14A))
            })
        case "missile":
            return (CGSize(width: 34, height: 12), { ctx in
                ctx.radialGlow(CGPoint(x: 6, y: 6), 7, 0xFF8A2A, alpha: 0.9)
                ctx.fillRoundedRect(CGRect(x: 6, y: 3, width: 22, height: 6), radius: 3, rgb(0xC9CDD4))
                ctx.fillPolygon([CGPoint(x: 28, y: 3), CGPoint(x: 34, y: 6), CGPoint(x: 28, y: 9)], rgb(0xE8452A))
                ctx.fillPolygon([CGPoint(x: 8, y: 3), CGPoint(x: 4, y: 0), CGPoint(x: 12, y: 3)], rgb(0x6A707A))
                ctx.fillPolygon([CGPoint(x: 8, y: 9), CGPoint(x: 4, y: 12), CGPoint(x: 12, y: 9)], rgb(0x6A707A))
            })
        default:
            return nil
        }
    }
}
