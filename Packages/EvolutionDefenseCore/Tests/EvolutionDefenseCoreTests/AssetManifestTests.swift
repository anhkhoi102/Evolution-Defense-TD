import Foundation
import Testing
@testable import EvolutionDefenseAssets
@testable import EvolutionDefenseCore

private let config = try! GameConfiguration.loadDefault()
/// The app's asset pack folder (the manifests ship in the app bundle).
private let packDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("EvolutionDefense/AssetPack")
private let catalogDir = packDir.deletingLastPathComponent().appendingPathComponent("Assets.xcassets")

private func manifest(_ name: String) throws -> AssetManifest {
    try AssetManifest.decode(Data(contentsOf: packDir.appendingPathComponent(name)))
}

@Suite("Asset manifest")
struct AssetManifestTests {
    @Test func placeholderPackCoversEveryEntity() throws {
        let m = try manifest("asset_manifest.placeholder.json")
        let issues = AssetValidator.validate(m, config: config)
        #expect(issues.isEmpty, "\(issues)")
        // Every tower level has its own base + head (upgrade variants).
        for a in TowerArchetype.allCases {
            for l in 1...config.tower(a).maxLevel {
                #expect(m.sprites[AssetID.towerBase(config.tower(a).visualKey, level: l)] != nil)
            }
        }
    }

    @Test func gameplayDataOnlyHoldsVisualKeys() {
        // Hit radius is gameplay; sprite size/shape live only in the manifest.
        for e in config.enemies.values { #expect(!e.visual.isEmpty) }
        for a in TowerArchetype.allCases {
            #expect(config.tower(a).visualKey == a.rawValue)
            for l in config.tower(a).levels { #expect(l.projectileAsset == l.projectile.rawValue) }
        }
    }

    @Test func shippedPackIsValidOnTopOfPlaceholders() throws {
        let merged = try manifest("asset_manifest.placeholder.json").merged(with: manifest("asset_manifest.json"))
        #expect(AssetValidator.validate(merged, config: config).isEmpty)
        let shipped = try manifest("asset_manifest.json")
        for (id, spec) in shipped.sprites { #expect(AssetValidator.check(spec, id: id).isEmpty, "\(id)") }
        // Every atlas frame / image the shipped pack names exists in the asset catalog.
        let refs = AssetValidator.referencedImages(shipped)
        let baked = catalogDir.appendingPathComponent("Baked")
        for ref in refs.atlasFrames {
            let parts = ref.split(separator: "/")
            #expect(FileManager.default.fileExists(atPath: baked.appendingPathComponent("\(parts[0]).spriteatlas/\(parts[1]).imageset").path), "\(ref)")
        }
        for name in refs.images {
            #expect(FileManager.default.fileExists(atPath: baked.appendingPathComponent("\(name).imageset").path), "\(name)")
        }
    }

    @Test func samplePackIsValidAndOnlyReplacesWhatItNames() throws {
        let base = try manifest("asset_manifest.placeholder.json")
        let sample = try manifest("asset_manifest.sample.json")
        for (id, spec) in sample.sprites { #expect(AssetValidator.check(spec, id: id).isEmpty, "\(id)") }
        let merged = base.merged(with: sample)
        #expect(AssetValidator.validate(merged, config: config).isEmpty)
        #expect(merged.sprites.count == base.sprites.count, "an override adds no new ids here")
        #expect(merged.sprites["enemy.wolf"] == sample.sprites["enemy.wolf"])
        #expect(merged.sprites["enemy.bear"] == base.sprites["enemy.bear"])
        #expect(merged.layoutValue("tower.pips.offsetY", default: 0) == -38)
        #expect(merged.layoutValue("tower.pips.spacing", default: 0) == base.layoutValue("tower.pips.spacing", default: 1))
        #expect(merged.name == "Sample replacement pack")
    }

    @Test func samplePackFilesShip() throws {
        let refs = AssetValidator.referencedImages(try manifest("asset_manifest.sample.json"))
        #expect(!refs.images.isEmpty && !refs.atlasFrames.isEmpty, "sample shows both loose images and an atlas")
        for name in refs.images {
            let loose = packDir.appendingPathComponent("Samples/\(name)@2x.png")
            #expect(FileManager.default.fileExists(atPath: loose.path), "missing \(loose.lastPathComponent)")
        }
        for ref in refs.atlasFrames {
            let parts = ref.split(separator: "/")
            let set = catalogDir.appendingPathComponent("\(parts[0]).spriteatlas/\(parts[1]).imageset")
            #expect(FileManager.default.fileExists(atPath: set.path), "missing atlas frame \(ref)")
        }
    }

    @Test func frameSourceForms() throws {
        let json = #"""
        { "frames": [ "plain_name",
                      { "image": "named" },
                      { "atlas": "A", "name": "f0" },
                      { "procedural": "fx", "key": "ring" } ],
          "fps": 8, "loop": false }
        """#
        let a = try JSONDecoder().decode(AnimationSpec.self, from: Data(json.utf8))
        #expect(a.frames == [.image("plain_name"), .image("named"), .atlas(atlas: "A", name: "f0"),
                             .procedural(ProceduralSource("fx", key: "ring"))])
        #expect(!a.loops && a.fps == 8)
        let round = try JSONDecoder().decode(AnimationSpec.self, from: JSONEncoder().encode(a))
        #expect(round == a)
    }

    @Test func validatorCatchesMistakes() {
        var m = AssetManifest(name: "broken", sprites: [:])
        m.sprites["enemy.wolf"] = SpriteSpec(anchor: SpritePoint(x: 2, y: 0.5),
                                             animations: ["walk": AnimationSpec(frames: [], fps: -1)], tint: "red")
        m.sprites["fx.ring"] = SpriteSpec(animations: ["default": AnimationSpec(frames: [.procedural(ProceduralSource("nope"))])])
        let text = AssetValidator.validate(m, config: config).map(\.description).joined(separator: "\n")
        #expect(text.contains("enemy.bear: missing sprite"))
        #expect(text.contains("no frames") && text.contains("fps must be > 0"))
        #expect(text.contains("anchor") && text.contains("tint"))
        #expect(text.contains("unknown procedural generator 'nope'"))
    }

    @Test func newVisualKeysNeedNoCode() throws {
        // A data-only change: point a tower level at a new projectile look.
        var cfg = config
        var splash = cfg.towers[.splash]!
        splash.levels[0].projectileVisual = "glowingRock"
        splash.visual = "fancySplash"
        cfg.towers[.splash] = splash
        let ids = AssetValidator.requiredIDs(for: cfg)
        #expect(ids.contains("projectile.glowingRock") && ids.contains("tower.fancySplash.1.base"))
        let w = GameWorld(config: cfg, seed: 1)
        w.debugSetGold(1000)
        w.build(.splash, atSlot: 5)
        w.debugSpawn("bear", atDistance: 600)
        w.holdPreparationCountdown = true
        var visual: String?
        for _ in 0..<600 where visual == nil {
            w.step(1.0 / 60)
            visual = w.projectiles.first { $0.isActive }?.visual
        }
        #expect(visual == "glowingRock", "the simulation carries the visual key to the renderer")
    }
}
