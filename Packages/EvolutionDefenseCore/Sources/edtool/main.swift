// Developer tool for the asset pipeline and balance work.
//
//   swift run --package-path Packages/EvolutionDefenseCore edtool export-map <out.json>
//   swift run -c release --package-path Packages/EvolutionDefenseCore edtool balance [easy|normal|hard] [seed…]
//   swift run -c release --package-path Packages/EvolutionDefenseCore edtool balance-summary [seed…]
//
// balance: plays every reference strategy (BalancePlayer.profiles) through the
// match and prints, per wave, how far the deepest enemy got (0–99 %, "XX" = a
// leak cost HP, "--" = not reached), so the difficulty curve can be read at a
// glance and re-checked after every config change.
//
// Writes the map's gameplay geometry (path, pads, spawn, base, seeded
// decorations) in world points so the Blender bake places art exactly where
// the game expects it. Read-only: it never changes game data.

import EvolutionDefenseCore
import Foundation

func pt(_ p: CGPoint) -> [String: Double] { ["x": Double(p.x), "y": Double(p.y)] }

let args = CommandLine.arguments
if args.count >= 2, args[1] == "balance-summary" {
    runSummary(Array(args.dropFirst(2)))
    exit(0)
}
if args.count >= 2, args[1] == "balance" {
    runBalance(Array(args.dropFirst(2)))
    exit(0)
}
guard args.count >= 3, args[1] == "export-map" else {
    FileHandle.standardError.write("usage: edtool export-map <out.json> | edtool balance [difficulty] [seed…]\n".data(using: .utf8)!)
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


// MARK: - balance

func runBalance(_ args: [String]) {
    let config = try! GameConfiguration.loadDefault()
    let difficulty = args.compactMap(Difficulty.init(rawValue:)).first ?? .normal
    let seeds = args.compactMap { UInt64($0) }
    let seedList = seeds.isEmpty ? [3, 7, 11] as [UInt64] : seeds
    let waves = config.waves.count
    print("Balance report — difficulty \(difficulty.rawValue), seeds \(seedList.map(String.init).joined(separator: ","))")
    print("Cells: deepest enemy progress along the path in %; XX = HP lost that wave; -- = wave not reached\n")
    var header = String(repeating: " ", count: 36)
    for n in 1...waves { header += String(format: "%3d", n) }
    print(header + "   result")
    for p in BalancePlayer.profiles {
        for seed in seedList {
            let r = p.play(config: config, seed: seed, options: MatchOptions(difficulty: difficulty, randomEvents: false))
            var line = (p.name + " s\(seed)").padding(toLength: 36, withPad: " ", startingAt: 0)
            for n in 1...waves {
                if let w = r.waves.first(where: { $0.number == n }) {
                    line += w.hpLost > 0 ? " XX" : String(format: "%3d", min(99, Int(w.deepestProgress * 100)))
                } else { line += " --" }
            }
            print(line + "   \(r.phase == .victory ? "WIN " : "LOSS") hp=\(r.baseHP) cleared=\(r.wavesCleared)")
        }
    }
    // Detail for one profile (default: the expert): where it hurts, what leaks, how much slack the economy leaves.
    let pick = args.compactMap { $0.hasPrefix("profile=") ? Int($0.dropFirst(8)) : nil }.first ?? 0
    let p = BalancePlayer.profiles[min(max(0, pick), BalancePlayer.profiles.count - 1)]
    let r = p.play(config: config, seed: seedList[0], options: MatchOptions(difficulty: difficulty, randomEvents: false))
    print("\nDetail: \(p.name), seed \(seedList[0])")
    print("  wave  deepest  hpLost  leaks  enemies  goldAtStart  towers  levels  duration  leaked")
    for w in r.waves {
        let leaked = w.leaksByEnemy.sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
        print(String(format: "  %4d    %3d%%    %4d   %4d     %4d         %4d      %2d      %2d     %4.0fs  ",
                     w.number, Int(w.deepestProgress * 100), w.hpLost, w.leaks, w.enemies, w.goldAtStart, w.towers, w.levels, w.duration) + leaked)
    }
}


// MARK: - balance-summary

/// Win rate, average furthest wave and average final HP per strategy and
/// difficulty over several seeds: the numbers in Docs/BALANCE.md.
func runSummary(_ args: [String]) {
    let config = try! GameConfiguration.loadDefault()
    let seeds = args.compactMap { UInt64($0) }
    let seedList = seeds.isEmpty ? [3, 7, 11, 23, 42] as [UInt64] : seeds
    let events = args.contains("events")
    let withSummons = args.contains("summons")
    let only = args.first { $0.hasPrefix("only=") }.map { String($0.dropFirst(5)) }
    if events { print("(random events ON)") }
    if withSummons { print("(players use summon abilities)") }
    print("Strategy                             " + Difficulty.allCases.map { $0.rawValue.padding(toLength: 24, withPad: " ", startingAt: 0) }.joined())
    print("                                     " + Difficulty.allCases.map { _ in "wins  furthest  HP left   " }.joined())
    for var p in BalancePlayer.profiles where only.map({ p.name.hasPrefix($0) }) ?? true {
        p.summons = withSummons
        var line = p.name.padding(toLength: 37, withPad: " ", startingAt: 0)
        for d in Difficulty.allCases {
            let rs = seedList.map { p.play(config: config, seed: $0, options: MatchOptions(difficulty: d, randomEvents: events)) }
            let wins = rs.filter { $0.phase == .victory }.count
            let furthest = Double(rs.map { $0.phase == .victory ? config.waves.count : $0.wavesCleared + 1 }.reduce(0, +)) / Double(rs.count)
            let hp = Double(rs.map(\.baseHP).reduce(0, +)) / Double(rs.count)
            line += String(format: "%d/%d  %5.1f     %4.0f      ", wins, rs.count, furthest, hp)
        }
        print(line)
    }
}
