// Developer tool for the asset pipeline and balance work.
//
//   swift run --package-path Packages/EvolutionDefenseCore edtool export-map <out.json> [battlefield id]
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
if args.count >= 2, args[1] == "tower-sandbox" {
    runTowerSandbox(Array(args.dropFirst(2)))
    exit(0)
}
if args.count >= 2, args[1] == "tower-report" {
    runTowerReport(Array(args.dropFirst(2)))
    exit(0)
}
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
let map = config.battlefield(args.count >= 4 ? args[3] : MatchOptions.defaultBattlefield) ?? config.map
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
if let t = map.theme {
    var theme: [String: Any] = ["environment": t.environment, "ground": t.ground, "groundAlt": t.groundAlt, "road": t.road,
                                "roadEdge": t.roadEdge, "accent": t.accent]
    if let w = t.water { theme["water"] = w }
    out["theme"] = theme
}
out["water"] = (map.water ?? []).map { $0.points.map { pt(map.world($0)) } }
out["bridges"] = (map.bridges ?? []).map { b -> [String: Any] in
    ["x": b.x * map.tileSize, "y": b.y * map.tileSize, "rotation": b.rotation, "length": b.length * map.tileSize]
}
let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]): \(path.points.count) path points, \(map.buildSlots.count) pads, \((out["decorations"] as! [Any]).count) decorations")


/// `hero=<id>` argument (default: the starting hero).
func heroArg(_ args: [String]) -> String? { args.first { $0.hasPrefix("hero=") }.map { String($0.dropFirst(5)) } }
/// `map=<id>` argument (default: Grassland).
func battlefieldArg(_ args: [String]) -> String {
    args.first { $0.hasPrefix("map=") }.map { String($0.dropFirst(4)) } ?? MatchOptions.defaultBattlefield
}

// MARK: - balance

func runBalance(_ args: [String]) {
    let config = try! GameConfiguration.loadDefault()
    let difficulty = args.compactMap(Difficulty.init(rawValue:)).first ?? .normal
    let mapID = battlefieldArg(args)
    let profiles = BalancePlayer.profiles(for: config.battlefield(mapID) ?? config.map, automaticPlan: args.contains("autoplan"))
    let seeds = args.compactMap { UInt64($0) }
    let seedList = seeds.isEmpty ? [3, 7, 11] as [UInt64] : seeds
    let waves = config.waves.count
    print("Balance report — battlefield \(mapID), difficulty \(difficulty.rawValue), seeds \(seedList.map(String.init).joined(separator: ","))")
    print("Cells: deepest enemy progress along the path in %; XX = HP lost that wave; -- = wave not reached\n")
    var header = String(repeating: " ", count: 36)
    for n in 1...waves { header += String(format: "%3d", n) }
    print(header + "   result")
    for p in profiles {
        for seed in seedList {
            let r = p.play(config: config, seed: seed, options: MatchOptions(difficulty: difficulty, randomEvents: false, battlefield: mapID, hero: heroArg(args)))
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
    let p = profiles[min(max(0, pick), profiles.count - 1)]
    let r = p.play(config: config, seed: seedList[0], options: MatchOptions(difficulty: difficulty, randomEvents: false, battlefield: mapID, hero: heroArg(args)))
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
    let mapID = battlefieldArg(args)
    print("Battlefield: \(mapID)")
    let withSummons = args.contains("summons")
    let only = args.first { $0.hasPrefix("only=") }.map { String($0.dropFirst(5)) }
    if events { print("(random events ON)") }
    if withSummons { print("(players use summon abilities)") }
    print("Strategy                             " + Difficulty.allCases.map { $0.rawValue.padding(toLength: 24, withPad: " ", startingAt: 0) }.joined())
    print("                                     " + Difficulty.allCases.map { _ in "wins  furthest  HP left   " }.joined())
    for var p in BalancePlayer.profiles(for: config.battlefield(mapID) ?? config.map, automaticPlan: args.contains("autoplan")) where only.map({ p.name.hasPrefix($0) }) ?? true {
        p.summons = withSummons
        var line = p.name.padding(toLength: 37, withPad: " ", startingAt: 0)
        for d in Difficulty.allCases {
            let rs = seedList.map { p.play(config: config, seed: $0, options: MatchOptions(difficulty: d, randomEvents: events, battlefield: mapID, hero: heroArg(args))) }
            let wins = rs.filter { $0.phase == .victory }.count
            let furthest = Double(rs.map { $0.phase == .victory ? config.waves.count : $0.wavesCleared + 1 }.reduce(0, +)) / Double(rs.count)
            let hp = Double(rs.map(\.baseHP).reduce(0, +)) / Double(rs.count)
            line += String(format: "%d/%d  %5.1f     %4.0f      ", wins, rs.count, furthest, hp)
        }
        print(line)
    }
}


// MARK: - tower-report

/// What each tower type contributes for each strategy: share of all damage, share of
/// gold spent, damage per gold and kills (averaged over seeds). The basis for tower balance.
///   edtool tower-report [difficulty] [seed…] [map=<id>]
func runTowerReport(_ args: [String]) {
    let config = try! GameConfiguration.loadDefault()
    let difficulty = args.compactMap(Difficulty.init(rawValue:)).first ?? .normal
    let seeds = args.compactMap { UInt64($0) }
    let seedList = seeds.isEmpty ? [3, 7, 11] as [UInt64] : seeds
    let mapID = battlefieldArg(args)
    print("Tower report: battlefield \(mapID), difficulty \(difficulty.rawValue), seeds \(seedList.map(String.init).joined(separator: ","))")
    print("per type: towers, avg level, % of gold spent, % of damage dealt, % of all damage its effects enabled,\n          (own + enabled) damage per gold, kills\n")
    for var p in BalancePlayer.profiles(for: config.battlefield(mapID) ?? config.map, automaticPlan: args.contains("autoplan")) {
        p.summons = true
        let rs = seedList.map { p.play(config: config, seed: $0, options: MatchOptions(difficulty: difficulty, randomEvents: false, battlefield: mapID)) }
        let cleared = Double(rs.reduce(0) { $0 + $1.wavesCleared }) / Double(rs.count)
        print("\(p.name): cleared \(String(format: "%.1f", cleared)) stages")
        var total = (gold: 0.0, damage: 0.0)
        var by: [TowerArchetype: BalancePlayer.TowerStat] = [:]
        for r in rs {
            for (a, st) in r.towerStats {
                var x = by[a] ?? BalancePlayer.TowerStat()
                x.count += st.count; x.levels += st.levels; x.invested += st.invested; x.damage += st.damage; x.kills += st.kills; x.assist += st.assist
                by[a] = x
                total.gold += Double(st.invested); total.damage += st.damage
            }
        }
        for a in TowerArchetype.allCases {
            guard let st = by[a], st.count > 0 else { continue }
            let n = Double(rs.count)
            print(String(format: "   %-7@ %4.1f towers  L%.1f   gold %4.0f%%   damage %4.0f%%   enabled %4.0f%%   %6.1f dmg/gold   %5.0f kills",
                         a.rawValue as NSString, Double(st.count) / n, Double(st.levels) / Double(st.count),
                         100 * Double(st.invested) / max(total.gold, 1), 100 * st.damage / max(total.damage, 1),
                         100 * st.assist / max(total.damage, 1),
                         (st.damage + st.assist) / Double(max(st.invested, 1)), Double(st.kills) / n))
        }
    }
}


// MARK: - tower-sandbox

/// Each tower type against set-piece groups (see TowerSandbox in the core library).
func runTowerSandbox(_ args: [String]) {
    print(TowerSandbox.report(config: try! GameConfiguration.loadDefault()))
}
