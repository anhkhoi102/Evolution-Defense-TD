// swift-tools-version: 6.0
//
// EvolutionDefenseCore — the game's pure logic and balance data.
// EvolutionDefenseAudio — procedural (temporary) sound effects and music.
// EvolutionDefenseAssets — the asset manifest: entity → visual asset mapping (see Docs/ASSETS.md).
//
// No SpriteKit, no UI: the simulation (enemies, towers, targeting, projectiles,
// waves, base HP) plus the JSON configuration it runs on. The Xcode app target
// (EvolutionDefense.xcodeproj) depends on this package as a local package.
//
// Test from the command line:  swift test --package-path Packages/EvolutionDefenseCore

import PackageDescription

let package = Package(
    name: "EvolutionDefenseCore",
    platforms: [
        .macOS(.v14), .iOS(.v17)
    ],
    products: [
        .library(name: "EvolutionDefenseCore", targets: ["EvolutionDefenseCore"]),
        // Procedural sound effects and music (pure DSP → sample arrays; playback lives in the app).
        .library(name: "EvolutionDefenseAudio", targets: ["EvolutionDefenseAudio"]),
        // Asset manifest model: maps game entities to replaceable visual assets.
        .library(name: "EvolutionDefenseAssets", targets: ["EvolutionDefenseAssets"])
    ],
    targets: [
        .target(
            name: "EvolutionDefenseCore",
            resources: [
                // Balance data (towers, enemies, waves, map). Editable without
                // touching gameplay code.
                .copy("Resources/Config")
            ]
        ),
        .target(name: "EvolutionDefenseAudio"),
        .target(name: "EvolutionDefenseAssets", dependencies: ["EvolutionDefenseCore"]),
        // Asset-pipeline helper (exports map geometry for the Blender bake).
        .executableTarget(name: "edtool", dependencies: ["EvolutionDefenseCore"]),
        .testTarget(
            name: "EvolutionDefenseCoreTests",
            dependencies: ["EvolutionDefenseCore", "EvolutionDefenseAudio", "EvolutionDefenseAssets"]
        )
    ]
)
