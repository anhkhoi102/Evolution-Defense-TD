import AppKit
import EvolutionDefenseCore
import SpriteKit

/// Developer tool: when EVO_SNAPSHOT_DIR is set, the app drives itself through
/// the menu and a short scripted match, saves PNGs of the window, then quits.
/// Used to verify rendering without manual play (see Scripts/snapshot.sh).
@MainActor
enum SnapshotTool {
    /// True while the snapshot tool drives the app: map backgrounds become
    /// transparent so the SpriteKit image can be composited *under* SwiftUI overlays.
    static let isActive = ProcessInfo.processInfo.environment["EVO_SNAPSHOT_DIR"] != nil
    static let isBenchmark = ProcessInfo.processInfo.environment["EVO_BENCHMARK"] != nil
    static let isAssetDemo = ProcessInfo.processInfo.environment["EVO_ASSET_DEMO"] != nil
    /// A tool will screenshot the window: map backgrounds go transparent so the
    /// SpriteKit image can be composited under the SwiftUI layer.
    static let isDeathTest = ProcessInfo.processInfo.environment["EVO_DEATH_TEST"] != nil
    static let capturesWindow = isActive || isAssetDemo || isDeathTest

    /// Output folder. The app is sandboxed, so images go to the container's
    /// temporary folder and Scripts/snapshot.sh copies them out.
    static var outputDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("snapshots", isDirectory: true)
    }

    static func runIfRequested(router: AppRouter) {
        guard isActive else { return }
        let out = outputDirectory
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        print("SNAPSHOT dir \(out.path)")
        Task { @MainActor in
            await run(router: router, out: out)
            NSApp.terminate(nil)
        }
    }

    private static func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    private static func run(router: AppRouter, out: URL) async {
        await pause(1.2)
        if let w = NSApp.windows.first { w.setContentSize(NSSize(width: 1440, height: 860)); w.center() }
        await pause(0.8)
        capture(out.appendingPathComponent("01-menu.png"))
        router.menuPanel = .newGame
        await pause(0.6)
        capture(out.appendingPathComponent("01b-new-game.png"))
        router.menuPanel = .settings
        await pause(0.6)
        capture(out.appendingPathComponent("01c-settings.png"))
        router.menuPanel = .none

        router.newGame(MatchOptions(difficulty: .normal, randomEvents: true))
        await pause(1.5)
        guard var c = router.game else { return }
        c.scene.fastForward(seconds: 4)          // countdown visibly running
        await pause(0.4)
        capture(out.appendingPathComponent("02-preparation.png"))

        // Build ghost preview on a free pad.
        c.selectBuild(.splash)
        c.scene.debugHover(slot: 5)
        await pause(0.4)
        capture(out.appendingPathComponent("03-build-preview.png"))
        c.clickSlot(5)

        // Scripted defence: one of each archetype on key spots, then start early.
        c.world.debugSetGold(1000)
        for (a, slot) in [(TowerArchetype.sniper, 3), (.rapid, 4), (.heavy, 9), (.splash, 12), (.sniper, 10), (.rapid, 14)] {
            c.selectBuild(a); c.clickSlot(slot)
        }
        c.cancelInteraction()
        c.scene.debugHover(slot: nil)
        c.startNextWave()
        await pause(0.2)
        c.scene.fastForward(seconds: 9)
        await pause(0.6)
        capture(out.appendingPathComponent("04-combat.png"))

        // Finish wave 1 → preparation phase with the wave summary.
        while c.world.phase == .waveInProgress { c.scene.fastForward(seconds: 1) }
        c.scene.fastForward(seconds: 2)
        await pause(0.8)
        capture(out.appendingPathComponent("05-wave-summary.png"))

        // Save & quit to the menu, then Continue: the match resumes from the checkpoint.
        let goldBefore = c.world.gold, towersBefore = c.world.towers.count
        c.exitToMenu()
        await pause(0.7)
        capture(out.appendingPathComponent("05b-menu-continue.png"))
        router.continueGame()
        await pause(1.0)
        guard let resumed = router.game else { return }
        c = resumed
        print("SNAPSHOT resume gold \(goldBefore)→\(c.world.gold) towers \(towersBefore)→\(c.world.towers.count) wave \(c.world.waveNumber)")

        // Upgrade panel: selecting a tower pauses the countdown.
        c.clickSlot(5)
        c.upgradeSelected()
        c.scene.fastForward(seconds: 0.3)
        await pause(0.6)
        capture(out.appendingPathComponent("06-upgrade-panel.png"))

        // Gallery of every evolution level.
        c.world.debugSetGold(50_000)
        let plan: [(Int, TowerArchetype, Int)] = [
            (3, .sniper, 5), (4, .rapid, 5), (9, .heavy, 5), (12, .splash, 5), (10, .sniper, 3), (14, .rapid, 3), (5, .splash, 3),
            (1, .heavy, 2), (2, .splash, 2), (6, .sniper, 4), (7, .rapid, 2), (8, .heavy, 4), (11, .splash, 4),
            (13, .rapid, 4), (15, .sniper, 2), (16, .heavy, 3)]
        for (slot, a, level) in plan {
            if c.world.tower(atSlot: slot) == nil { c.selectBuild(a); c.clickSlot(slot) }
            if let t = c.world.tower(atSlot: slot) { while t.level < level { c.world.upgrade(t) } }
        }
        c.cancelInteraction()
        c.scene.fastForward(seconds: 0.6)
        await pause(0.8)
        capture(out.appendingPathComponent("07-tower-levels.png"))

        // Repair panel (base damaged first).
        c.world.debugSetBaseHP(62)
        c.world.debugSetGold(150)
        c.refreshHUD()
        c.toggleRepairPanel()
        await pause(0.6)
        capture(out.appendingPathComponent("08-repair-panel.png"))
        c.repair(option: 0)
        c.cancelInteraction()
        c.world.debugSetGold(2000)

        // Replace the gallery with a realistic defence that evolves era by era.
        for t in c.world.towers { c.world.sell(t) }
        c.world.debugSetGold(100_000)
        for (slot, a) in [(5, TowerArchetype.splash), (3, .sniper), (9, .heavy), (12, .rapid), (4, .rapid), (2, .splash),
                          (10, .sniper), (11, .heavy), (14, .splash), (16, .rapid)] {
            c.world.build(a, atSlot: slot)
        }
        evolve(c, to: 2)

        // A random event card (Reinforcement: an allied tower on a free pad).
        c.world.debugTriggerEvent("reinforcement")
        c.scene.fastForward(seconds: 0.1)
        await pause(0.7)
        capture(out.appendingPathComponent("08b-random-event.png"))
        c.eventCard = nil

        // Technology panel (pauses the countdown).
        c.world.debugSetResearch(6)
        c.refreshHUD()
        c.toggleTechPanel()
        c.research("improvedArrows")
        await pause(0.7)
        capture(out.appendingPathComponent("09-tech-panel.png"))
        c.cancelInteraction()

        // Era 1 boss with the boss bar.
        await runWaves(c, until: 5)
        await waitFor(c, 60) { $0.world.enemies.contains { $0.isBoss && $0.distance > 700 } }
        await pause(0.6)
        capture(out.appendingPathComponent("10-boss-alpha.png"))

        // Era transition right after the boss wave.
        await waitFor(c, 200) { $0.world.phase == .preparation }
        await pause(1.1)
        capture(out.appendingPathComponent("11-era-transition.png"))
        await pause(2.8)

        // Medieval: flyers, trolls, armored beasts.
        evolve(c, to: 3)
        await runWaves(c, until: 9)
        await waitFor(c, 40) { $0.world.enemies.contains { $0.definition.id == "troll" } && $0.world.enemies.count > 14 }
        await pause(0.6)
        capture(out.appendingPathComponent("12-medieval-wave.png"))
        c.clickSlot(3)
        await pause(0.5)
        capture(out.appendingPathComponent("13-wave-intel-and-tower.png"))
        c.cancelInteraction()

        // Dragon breathing fire on towers.
        await runWaves(c, until: 10)
        await waitFor(c, 90) { c in c.world.towers.contains { $0.isDisabled(at: c.world.time) } && c.world.enemies.contains { $0.isBoss } }
        c.scene.fastForward(seconds: 0.15)
        await pause(0.5)
        capture(out.appendingPathComponent("14-dragon-fire-breath.png"))

        // Industrial: mutants and swarms.
        evolve(c, to: 4)
        await runWaves(c, until: 14)
        await waitFor(c, 40) { $0.world.enemies.contains { $0.definition.id == "giantMutant" } && $0.world.enemies.count > 20 }
        await pause(0.6)
        capture(out.appendingPathComponent("15-industrial-wave.png"))
        await runWaves(c, until: 15)
        await waitFor(c, 90) { $0.world.enemies.contains { $0.isBoss && $0.distance > 900 } }
        await pause(0.6)
        capture(out.appendingPathComponent("16-mutant-titan.png"))

        // Futuristic: stealth, shields, heavy mechs.
        evolve(c, to: 5)
        c.world.debugSetResearch(40)
        for t in c.config.techs { c.world.research(t.id) }
        await runWaves(c, until: 19)
        await waitFor(c, 40) { c in c.world.enemies.contains { $0.isCloaked } && c.world.enemies.contains { $0.maxShieldHP > 0 } }
        await pause(0.6)
        capture(out.appendingPathComponent("17-futuristic-wave.png"))

        // Final boss, second phase.
        await runWaves(c, until: 20)
        await waitFor(c, 200) { c in c.world.enemies.contains { $0.isBoss && $0.phaseIndex >= 0 } && c.world.towers.contains { $0.isDisabled(at: c.world.time) } }
        await pause(0.5)
        capture(out.appendingPathComponent("18-titan-overdrive.png"))

        c.togglePause()
        await pause(0.5)
        capture(out.appendingPathComponent("19-paused.png"))
        c.togglePause()

        while !c.world.phase.isOver && c.world.time < 60 * 40 {
            c.scene.fastForward(seconds: 5)
            if c.world.phase == .preparation { c.startNextWave() }
        }
        await pause(1.0)
        capture(out.appendingPathComponent("20-match-end.png"))
        c.exitToMenu()
        await pause(0.4)
        router.menuPanel = .achievements
        await pause(0.7)
        capture(out.appendingPathComponent("21-achievements.png"))
        router.menuPanel = .records
        await pause(0.6)
        capture(out.appendingPathComponent("22-records.png"))
        router.menuPanel = .none
        print("SNAPSHOT phase=\(c.world.phase) wave=\(c.world.waveNumber)/\(c.world.totalWaves) baseHP=\(c.world.baseHP) kills=\(c.world.stats.enemiesKilled) leaked=\(c.world.stats.enemiesLeaked) bosses=\(c.world.stats.bossesDefeated) techs=\(c.world.researchedTechs.count) time=\(Int(c.world.time))s")
    }

    /// Plays (fast) until wave `n` has started.
    private static func runWaves(_ c: GameController, until n: Int) async {
        while c.world.waveNumber < n && !c.world.phase.isOver {
            if c.world.phase == .preparation {
                c.world.debugSetGold(max(c.world.gold, 3000))
                c.startNextWave()
            } else {
                c.scene.fastForward(seconds: 1)
            }
        }
        await pause(0.1)
    }

    private static func waitFor(_ c: GameController, _ maxSeconds: Double, _ cond: (GameController) -> Bool) async {
        var t = 0.0
        while !cond(c) && t < maxSeconds && !c.world.phase.isOver {
            c.scene.fastForward(seconds: 0.25)
            t += 0.25
        }
    }

    /// Upgrades every tower to at least `level` (the scripted defence keeps up with the eras).
    private static func evolve(_ c: GameController, to level: Int) {
        c.world.debugSetGold(100_000)
        for t in c.world.towers { while t.level < level, case .success = c.world.upgrade(t) {} }
        c.world.debugSetGold(2000)
        c.scene.fastForward(seconds: 0.05)
    }

    // MARK: Benchmark (EVO_BENCHMARK=1)

    /// Worst realistic load: all 16 pads with level-5 towers, every tech, 300
    /// Futuristic enemies with shields/stealth plus a boss. Measures real frame
    /// intervals of the running SKView, normal and performance mode.
    static func runBenchmarkIfRequested(router: AppRouter) {
        guard isBenchmark else { return }
        Task { @MainActor in
            await pause(1.0)
            if let w = NSApp.windows.first { w.setContentSize(NSSize(width: 1440, height: 860)); w.center() }
            for perf in [false, true] {
                router.newGame(MatchOptions(difficulty: .normal, randomEvents: false))
                await pause(1.0)
                guard let c = router.game else { break }
                c.apply({ var s = GameSettings(); s.performanceMode = perf; return s }())
                let w = c.world
                w.debugSetGold(1_000_000)
                w.debugSetResearch(1000)
                w.debugSkipToWave(16)
                for t in w.config.techs { w.research(t.id) }
                let types: [TowerArchetype] = [.rapid, .splash, .sniper, .heavy]
                for (i, s) in w.config.map.buildSlots.enumerated() { w.build(types[i % 4], atSlot: s.id) }
                for t in w.towers { while case .success = w.upgrade(t) {} }
                w.startNextWave()
                let mix = ["stealthRobot", "assaultRobot", "scoutRobot", "heavyMech", "swarmCreature", "mutantBeast"]
                for i in 0..<300 { w.debugSpawn(mix[i % mix.count], atDistance: CGFloat(i) * 7) }
                w.debugSpawn("titanWarMachine", atDistance: 400)
                await pause(1.0)
                c.scene.resetFrameTimes()
                var peakEnemies = 0
                for _ in 0..<16 { await pause(0.5); peakEnemies = max(peakEnemies, w.enemies.count) }
                let ft = c.scene.frameTimes.sorted()
                guard !ft.isEmpty else { continue }
                let avg = ft.reduce(0, +) / Double(ft.count)
                let p95 = ft[Int(Double(ft.count) * 0.95)]
                let p99 = ft[Int(Double(ft.count) * 0.99)]
                let slow = ft.filter { $0 > 1.0 / 50 }.count
                print(String(format: "BENCHMARK performanceMode=%@ frames=%d avgFPS=%.1f p95=%.1fms p99=%.1fms worst=%.1fms framesOver20ms=%d enemiesAtStart=%d",
                             perf ? "on" : "off", ft.count, 1 / avg, p95 * 1000, p99 * 1000, (ft.last ?? 0) * 1000, slow, peakEnemies))
                router.exitToMenu()
            }
            NSApp.terminate(nil)
        }
    }

    // MARK: Asset pack demo (EVO_ASSET_DEMO=1, usually with EVO_ASSET_PACK=sample)

    /// One screenshot with wolves, Splash towers and the base on screen, so a
    /// replacement pack can be compared with the placeholders side by side.
    static func runAssetDemoIfRequested(router: AppRouter) {
        guard isAssetDemo else { return }
        Task { @MainActor in
            let out = outputDirectory
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            await pause(1.0)
            if let w = NSApp.windows.first { w.setContentSize(NSSize(width: 1440, height: 860)); w.center() }
            router.newGame(MatchOptions(difficulty: .normal, randomEvents: false))
            await pause(1.0)
            guard let c = router.game else { NSApp.terminate(nil); return }
            c.world.debugSetGold(5000)
            for slot in [5, 2, 14] { c.world.build(.splash, atSlot: slot) }
            c.world.build(.sniper, atSlot: 3)
            c.startNextWave()
            c.scene.fastForward(seconds: 7)
            for i in 0..<5 { c.world.debugSpawn("wolf", atDistance: 700 + CGFloat(i) * 40) }
            c.scene.fastForward(seconds: 0.6)
            await pause(0.8)
            let pack = ProcessInfo.processInfo.environment["EVO_ASSET_PACK"] ?? "default"
            capture(out.appendingPathComponent("asset-pack-\(pack).png"))
            print("ASSETDEMO pack=\(ArtLibrary.shared.manifest.name) issues=\(ArtLibrary.shared.issues.count)")
            NSApp.terminate(nil)
        }
    }

    // MARK: Mass-death check (EVO_DEATH_TEST=1)

    /// Many large enemies dying at the same moment (wave 7 / 8 packs under
    /// strong splash fire). Captures frames through the death animations so
    /// corpse size and dissolve can be inspected: snapshots/death-NN.png.
    static func runDeathTestIfRequested(router: AppRouter) {
        guard ProcessInfo.processInfo.environment["EVO_DEATH_TEST"] != nil else { return }
        Task { @MainActor in
            let out = outputDirectory
            try? FileManager.default.removeItem(at: out)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            await pause(1.0)
            if let w = NSApp.windows.first { w.setContentSize(NSSize(width: 1440, height: 860)); w.center() }
            router.newGame(MatchOptions(difficulty: .normal, randomEvents: false))
            await pause(1.0)
            guard let c = router.game else { NSApp.terminate(nil); return }
            let w = c.world
            w.debugSetGold(1_000_000)
            w.debugSkipToWave(7)
            for (i, s) in w.config.map.buildSlots.prefix(8).enumerated() { w.build(i % 2 == 0 ? .splash : .heavy, atSlot: s.id) }
            for t in w.towers { while case .success = w.upgrade(t) {} }
            c.startNextWave()
            let kinds = ["giantWolf", "armoredBeast", "troll", "giantWolf"]
            let free = Array(w.config.map.buildSlots.dropFirst(8))
            var n = 0, worst = 0, checks = 0
            // Three packs, each dying together under maxed splash fire. Between
            // packs, new towers are built and evolved: their level-up sparks
            // shrink to 0.2 and go back to the effect pool, which is what made
            // later death animations come out 5× too big.
            for round in 0..<3 {
                for i in 0..<24 { w.debugSpawn(kinds[(i + round) % kinds.count], atDistance: 200 + CGFloat(i % 6) * 6, elite: i % 4 == 0) }
                for i in 0..<24 { w.debugSpawn(kinds[(i + round + 1) % kinds.count], atDistance: 520 + CGFloat(i % 6) * 6) }
                for _ in 0..<20 {
                    await pause(0.12)
                    worst = max(worst, c.scene.debugEffectSizeMismatches); checks += 1
                    if round == 0 || n < 60 { capture(out.appendingPathComponent(String(format: "death-%02d.png", n))) }
                    n += 1
                }
                if round < free.count {
                    _ = w.build(.splash, atSlot: free[round].id)
                    for t in w.towers { while case .success = w.upgrade(t) {} }
                }
            }
            for _ in 0..<15 { await pause(0.1); worst = max(worst, c.scene.debugEffectSizeMismatches); checks += 1 }
            print("DEATHTEST \(worst == 0 ? "PASS" : "FAIL") frames=\(n) checks=\(checks) worstMismatchedSprites=\(worst)")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    // MARK: Audio check (EVO_AUDIO_CHECK=1)

    static func runAudioCheckIfRequested() {
        guard ProcessInfo.processInfo.environment["EVO_AUDIO_CHECK"] != nil else { return }
        Task { @MainActor in
            await pause(0.5)
            let result = await AudioManager.shared.selfCheck()
            print("AUDIOCHECK \(result)")
            NSApp.terminate(nil)
        }
    }

    /// Renders the window's SwiftUI content, then paints the SpriteKit view's
    /// Metal content into its frame (cacheDisplay can't read Metal layers).
    private static func capture(_ url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let root = window.contentView else { return }
        guard let ui = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: ui)
        guard let out = root.bitmapImageRepForCachingDisplay(in: root.bounds),
              let uiImage = ui.cgImage else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        let ctx = NSGraphicsContext.current!.cgContext
        let full = CGRect(x: 0, y: 0, width: root.bounds.width, height: root.bounds.height)
        ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1))
        ctx.fill(full)
        // 1) SpriteKit content (Metal) where the SKView sits, letterboxed like .aspectFit.
        if let sk = findSKView(in: root), let scene = sk.scene, let tex = sk.texture(from: scene) {
            let frame = sk.convert(sk.bounds, to: nil)   // window coords, y-up
            let s = min(frame.width / scene.size.width, frame.height / scene.size.height)
            let w = scene.size.width * s, h = scene.size.height * s
            ctx.draw(tex.cgImage(), in: CGRect(x: frame.midX - w / 2, y: frame.midY - h / 2, width: w, height: h))
        }
        // 2) SwiftUI chrome and overlays on top (map area is transparent in snapshot mode).
        ctx.draw(uiImage, in: full)
        NSGraphicsContext.restoreGraphicsState()
        if let data = out.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            print("SNAPSHOT saved \(url.lastPathComponent)")
        }
    }

    private static func findSKView(in v: NSView) -> SKView? {
        if let s = v as? SKView { return s }
        for sub in v.subviews { if let s = findSKView(in: sub) { return s } }
        return nil
    }
}
