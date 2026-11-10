// Developer tools that drive the app and screenshot its window. They use AppKit window capture,
// so they exist on macOS only; other platforms get an inert stand-in (end of file).
#if os(macOS)
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
    static let isSummonTest = ProcessInfo.processInfo.environment["EVO_SUMMON_TEST"] != nil
    static let isBattlefieldTest = ProcessInfo.processInfo.environment["EVO_BATTLEFIELD_TEST"] != nil
    static let capturesWindow = isActive || isAssetDemo || isDeathTest || isSummonTest || isBattlefieldTest

    /// Output folder. The app is sandboxed, so images go to the container's
    /// temporary folder and Scripts/snapshot.sh copies them out.
    /// Starts whichever tool the environment asks for (none in normal use).
    static func runAllIfRequested(router: AppRouter) {
        runIfRequested(router: router)
        runBenchmarkIfRequested(router: router)
        runAudioCheckIfRequested()
        runAssetDemoIfRequested(router: router)
        runDeathTestIfRequested(router: router)
        runSummonTestIfRequested(router: router)
        runBattlefieldTestIfRequested(router: router)
    }

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
                // Both summon abilities on the field during the measurement.
                _ = w.summon("militia", at: w.path.position(at: 900))
                _ = w.summon("hero", at: w.path.position(at: 1500))
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

    // MARK: Battlefield check (EVO_BATTLEFIELD_TEST=1)

    /// Menu, battlefield selection and a fight on every battlefield. Fails if a
    /// map doesn't load its own background, towers can't be built on its pads,
    /// enemies don't advance along its road, a summon can't be placed on it, or
    /// another map's background stays in memory after switching.
    static func runBattlefieldTestIfRequested(router: AppRouter) {
        guard isBattlefieldTest else { return }
        Task { @MainActor in
            let out = outputDirectory
            try? FileManager.default.removeItem(at: out)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            await pause(1.2)
            if let w = NSApp.windows.first { w.setContentSize(NSSize(width: 1440, height: 860)); w.center() }
            var failures: [String] = []
            await pause(0.8)
            capture(out.appendingPathComponent("bf-00-menu.png"))
            router.menuPanel = .battlefields
            await pause(0.7)
            capture(out.appendingPathComponent("bf-01-select-\(router.selectedBattlefield?.id ?? "x").png"))
            for (i, map) in router.battlefields.enumerated() {
                router.menuPanel = .battlefields
                router.selectBattlefield(map.id)
                await pause(0.8)
                capture(out.appendingPathComponent("bf-\(i + 1)0-select-\(map.id).png"))
                router.menuPanel = .newGame
                await pause(0.6)
                if i == 0 { capture(out.appendingPathComponent("bf-02-new-game.png")) }
                router.newGame()
                await pause(1.0)
                guard let c = router.game else { failures.append("\(map.id): no game"); continue }
                let w = c.world
                if w.config.map.id != map.id { failures.append("\(map.id): match runs on \(w.config.map.id)") }
                if ArtLibrary.shared.loadedBattlefieldBackgrounds != ["map.\(map.id).background"] {
                    failures.append("\(map.id): backgrounds in memory \(ArtLibrary.shared.loadedBattlefieldBackgrounds)")
                }
                w.debugSetGold(100_000)
                w.debugSkipToWave(7)
                // A real mouse click through the window: pick a tower, click the first pad.
                if let first = w.config.map.buildSlots.first, let win = NSApp.windows.first(where: { $0.isVisible }),
                   let at = c.scene.debugWindowPoint(forWorld: w.config.map.slotPosition(first)) {
                    c.selectBuild(.sniper)
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                            win.sendEvent(e)
                        }
                    }
                    await pause(0.2)
                    if w.tower(atSlot: first.id)?.archetype != .sniper { failures.append("\(map.id): a mouse click on a pad did not build a tower") }
                } else { failures.append("\(map.id): could not aim a mouse click") }
                for (k, s) in w.config.map.buildSlots.enumerated() {
                    _ = w.build([.splash, .sniper, .heavy, .rapid][k % 4], atSlot: s.id)
                }
                let built = w.towers.count
                if built != w.config.map.buildSlots.count { failures.append("\(map.id): built \(built) of \(w.config.map.buildSlots.count) pads") }
                for t in w.towers { for _ in 0..<2 { _ = w.upgrade(t) } }
                c.startNextWave()
                c.scene.fastForward(seconds: 9)
                let lead = w.enemies.filter(\.isActive).map(\.distance).max() ?? 0
                if lead < 200 { failures.append("\(map.id): enemies are not advancing (\(lead))") }
                if case .success = w.summon("militia", at: w.path.position(at: min(lead + 60, w.path.totalLength - 100))) {} else {
                    failures.append("\(map.id): militia could not deploy on the road")
                }
                await pause(1.2)
                capture(out.appendingPathComponent("bf-\(i + 1)1-play-\(map.id).png"))
                c.scene.fastForward(seconds: 40)
                // Finish the stage so its progress is recorded.
                var extra = 0
                while w.phase == .waveInProgress && extra < 20 { c.scene.fastForward(seconds: 10); extra += 1 }
                await pause(0.3)
                if w.phase.isOver && w.phase != .victory { failures.append("\(map.id): lost wave 7 with a full defence") }
                if w.stats.wavesCleared < 1 { failures.append("\(map.id): stage 7 was not cleared") }
                if w.matchStars != 0 { failures.append("\(map.id): an unfinished match was rated") }
                c.onExitToMenu?()
                await pause(0.6)
            }
            router.menuPanel = .campaign
            await pause(0.7)
            capture(out.appendingPathComponent("bf-80-campaign.png"))
            for map in router.battlefields where router.profile.stagesCleared(battlefield: map.id) < 7 {
                failures.append("\(map.id): clearing stage 7 was not recorded")
            }
            router.menuPanel = .credits
            await pause(0.6)
            capture(out.appendingPathComponent("bf-90-credits.png"))
            print("BATTLEFIELDTEST \(failures.isEmpty ? "PASS" : "FAIL: " + failures.joined(separator: "; ")) maps=\(router.battlefields.map(\.id))")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    // MARK: Summon check (EVO_SUMMON_TEST=1)

    /// Both summon abilities on the Dragon wave: preview (valid / invalid),
    /// arrival, fighting, the hero's special, then expiry. Fails if summon
    /// sprites outlive their units or any effect sprite is mis-sized.
    static func runSummonTestIfRequested(router: AppRouter) {
        guard isSummonTest else { return }
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
            var failures: [String] = []
            w.debugSetGold(100_000)
            w.debugSkipToWave(10)
            for (i, s) in w.config.map.buildSlots.prefix(6).enumerated() { w.build([.splash, .sniper, .heavy][i % 3], atSlot: s.id) }
            for t in w.towers { for _ in 0..<2 { _ = w.upgrade(t) } }
            c.startNextWave()
            c.scene.fastForward(seconds: 14)
            capture(out.appendingPathComponent("summon-00-buttons-ready.png"))
            // Preview: valid spot on the road, then an invalid one out in the grass.
            let lead = w.enemies.filter(\.isActive).max { $0.distance < $1.distance }
            let spot = w.path.position(at: min((lead?.distance ?? 400) + 160, w.path.totalLength - 120))
            c.selectSummon("hero")
            c.scene.debugHover(world: spot)
            await pause(0.3)
            capture(out.appendingPathComponent("summon-01-preview-valid.png"))
            // A spot near the first one but far from every stretch of the winding road.
            let grass = [CGPoint(x: 0, y: 160), CGPoint(x: 0, y: -160), CGPoint(x: 160, y: 0), CGPoint(x: -160, y: 0),
                         CGPoint(x: 120, y: 120), CGPoint(x: -120, y: -120), CGPoint(x: 120, y: -120), CGPoint(x: -120, y: 120)]
                .map { CGPoint(x: spot.x + $0.x, y: spot.y + $0.y) }
                .first { w.summonDeployPoint(near: $0) == nil } ?? CGPoint(x: -100, y: -100)
            c.scene.debugHover(world: grass)
            await pause(0.3)
            capture(out.appendingPathComponent("summon-02-preview-invalid.png"))
            c.confirmSummon(at: grass)
            if !w.summons.isEmpty { failures.append("deployed on an invalid spot") }
            c.confirmSummon(at: spot)
            if w.summons.count != 1 { failures.append("hero not deployed") }
            c.selectSummon("militia")
            let spot2 = w.path.position(at: min((lead?.distance ?? 400) + 40, w.path.totalLength - 120))
            c.confirmSummon(at: spot2)
            let units = w.summons.count
            if units != 1 + (w.config.summons.ability("militia")?.count ?? 0) { failures.append("militia not deployed (\(units) units)") }
            await pause(0.15)
            if c.scene.debugSummonNodes != units { failures.append("drawn \(c.scene.debugSummonNodes) of \(units) units") }
            for n in 0..<10 {
                await pause(0.35)
                capture(out.appendingPathComponent(String(format: "summon-%02d-fight.png", 3 + n)))
                if c.scene.debugEffectSizeMismatches > 0 { failures.append("mis-sized effect sprites") }
            }
            // Past both durations: everything must be gone, sprites included.
            c.scene.fastForward(seconds: 20)
            await pause(0.3)
            capture(out.appendingPathComponent("summon-13-after-expiry.png"))
            if !w.summons.isEmpty { failures.append("\(w.summons.count) units outlived their duration") }
            if c.scene.debugSummonNodes != 0 { failures.append("\(c.scene.debugSummonNodes) summon sprites leaked") }
            // The unlockable heroes: each goes into its own match, fights, uses its special and leaves.
            c.onExitToMenu?()
            await pause(0.4)
            router.menuPanel = .newGame
            await pause(0.6)
            capture(out.appendingPathComponent("hero-00-new-game-locked.png"))
            if router.heroes.filter({ router.isUnlocked($0) }).count != 1 { failures.append("a fresh profile should have one hero") }
            for (i, hero) in router.heroes.filter({ $0.requiredStage > 0 }).enumerated() {
                router.newGame(MatchOptions(difficulty: .normal, randomEvents: false, hero: hero.id))
                await pause(0.8)
                guard let hc = router.game else { failures.append("\(hero.id): no game"); continue }
                let hw = hc.world
                if hc.abilities.map(\.id) != ["militia", hero.id] { failures.append("\(hero.id): buttons \(hc.abilities.map(\.id))") }
                hw.debugSetGold(100_000)
                hw.debugSkipToWave(10)
                for (k, s) in hw.config.map.buildSlots.prefix(4).enumerated() { hw.build([.splash, .sniper][k % 2], atSlot: s.id) }
                hc.startNextWave()
                hc.scene.fastForward(seconds: 14)
                let front = hw.enemies.filter { $0.isActive && !$0.isFlying }.max { $0.distance < $1.distance }
                let lead: CGFloat = hero.unit.isRanged ? 150 : 110
                hc.selectSummon(hero.id)
                hc.confirmSummon(at: hw.path.position(at: min((front?.distance ?? 400) + lead, hw.path.totalLength - 120)))
                if hw.summons.count != 1 { failures.append("\(hero.id): not deployed") }
                var specials = 0
                for n in 0..<8 {
                    await pause(0.35)
                    capture(out.appendingPathComponent(String(format: "hero-%d%d-%@.png", i + 1, n, hero.id)))
                    if hc.scene.debugEffectSizeMismatches > 0 { failures.append("\(hero.id): mis-sized effect sprites") }
                    if (hw.summons.first?.damageDealt ?? 0) > 0 { specials += 1 }
                }
                if specials == 0 { failures.append("\(hero.id): dealt no damage") }
                hc.scene.fastForward(seconds: 30)
                await pause(0.3)
                if !hw.summons.isEmpty || hc.scene.debugSummonNodes != 0 { failures.append("\(hero.id): outlived its duration") }
                if i == 0 {
                    hc.heroUnlock = hero
                    await pause(0.8)
                    capture(out.appendingPathComponent("hero-90-unlock-card.png"))
                    hc.heroUnlock = nil
                }
                hc.onExitToMenu?()
                await pause(0.4)
            }
            let st = c.abilities
            print("SUMMONTEST \(failures.isEmpty ? "PASS" : "FAIL: " + failures.joined(separator: "; ")) abilities=\(st.map { "\($0.id):cd\($0.cooldown)" })")
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
#else
@MainActor
enum SnapshotTool {
    static let capturesWindow = false
    static let isBenchmark = false
    static func runAllIfRequested(router: AppRouter) {}
}
#endif
