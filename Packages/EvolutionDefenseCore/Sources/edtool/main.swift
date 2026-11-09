// Developer tool for the asset pipeline.
//
//   swift run --package-path Packages/EvolutionDefenseCore edtool export-map <out.json>
//
// Writes the map's gameplay geometry (path, pads, spawn, base, seeded
// decorations) in world points so the Blender bake places art exactly where
// the game expects it. Read-only: it never changes game data.

import EvolutionDefenseCore
import Foundation

func pt(_ p: CGPoint) -> [String: Double] { ["x": Double(p.x), "y": Double(p.y)] }

let args = CommandLine.arguments
guard args.count >= 3, args[1] == "export-map" else {
    FileHandle.standardError.write("usage: edtool export-map <out.json>\n".data(using: .utf8)!)
    exit(2)
}
let config = try GameConfiguration.loadDefault()
let map = config.map
let path = map.makePath()
var out: [String: Any] = [
    "id": map.id,
    "tileSize": map.tileSize,
    "worldSize": ["width": Double(map.worldSize.width), "height": Double(map.worldSize.height)],
    "pathWidth": map.pathWidth * map.tileSize,
    "path": path.points.map(pt),
    "spawn": pt(map.world(map.spawn)),
    "base": pt(map.world(map.base)),
    "slots": map.buildSlots.map { ["id": $0.id, "x": Double(map.slotPosition($0).x), "y": Double(map.slotPosition($0).y)] },
]
out["decorations"] = map.resolvedDecorations().map { d -> [String: Any] in
    let p = map.world(x: d.x, y: d.y)
    return ["kind": d.kind.rawValue, "x": Double(p.x), "y": Double(p.y), "scale": d.scale]
}
let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]): \(path.points.count) path points, \(map.buildSlots.count) pads, \((out["decorations"] as! [Any]).count) decorations")
