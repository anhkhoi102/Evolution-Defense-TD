import AppKit
import EvolutionDefenseAudio
import EvolutionDefenseCore
import Observation
import SwiftUI

/// Top-level navigation, the player profile (settings, achievements, records)
/// and the match checkpoint used by Continue.
@MainActor
@Observable
final class AppRouter {
    enum Screen { case menu, game }
    enum MenuPanel { case none, newGame, battlefields, settings, achievements, records, credits }

    private(set) var screen: Screen = .menu
    private(set) var game: GameController?
    private(set) var loadError: String?
    @ObservationIgnored private(set) var config: GameConfiguration?

    var menuPanel: MenuPanel = .none
    private(set) var profile: PlayerProfile
    /// Saved match to continue (taken at the start of every preparation phase).
    private(set) var checkpoint: MatchCheckpoint?
    @ObservationIgnored let store: ProfileStore
    @ObservationIgnored private var quitObserver: NSObjectProtocol?

    var settings: GameSettings { profile.settings }

    /// Every battlefield, in menu order.
    var battlefields: [MapDefinition] { config?.maps ?? [] }
    /// The battlefield chosen in the menu (falls back to the default if a saved id no longer exists).
    var selectedBattlefield: MapDefinition? { config?.battlefield(settings.battlefield) ?? config?.map }
    func selectBattlefield(_ id: String) {
        guard config?.battlefield(id) != nil, id != settings.battlefield else { return }
        updateSettings { $0.battlefield = id }
    }

    init() {
        // Tools get a throw-away profile so they never touch the player's saves.
        if SnapshotTool.capturesWindow || SnapshotTool.isBenchmark {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("evo-tool-profile", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            store = ProfileStore(directory: dir)
        } else {
            store = ProfileStore(directory: ProfileStore.defaultDirectory())
        }
        profile = store.loadProfile()
        do {
            config = try GameConfiguration.loadDefault()
            ArtLibrary.shared.prepare(config: config!)
        } catch {
            loadError = "Could not load game data: \(error)"
        }
        if let cp = store.loadCheckpoint(), let config, (try? GameWorld(config: config, checkpoint: cp)) != nil {
            checkpoint = cp
        }
        AudioManager.shared.start(settings: profile.settings)
        AudioManager.shared.playMusic(.menu)
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                              object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveCurrentMatch() }
        }
    }

    // MARK: Matches

    func newGame(_ options: MatchOptions? = nil) {
        guard let config else { return }
        let opts = options ?? MatchOptions(difficulty: settings.difficulty, randomEvents: settings.randomEvents,
                                           battlefield: selectedBattlefield?.id ?? MatchOptions.defaultBattlefield)
        store.deleteCheckpoint()
        checkpoint = nil
        start(GameWorld(config: config, options: opts, seed: UInt64.random(in: 1...UInt64.max)))
    }

    func continueGame() {
        guard let config, let cp = checkpoint else { return }
        do {
            start(try GameWorld(config: config, checkpoint: cp))
        } catch {
            store.deleteCheckpoint()
            checkpoint = nil
        }
    }

    private func start(_ world: GameWorld) {
        menuPanel = .none
        let c = GameController(world: world, settings: settings)
        c.onExitToMenu = { [weak self] in self?.exitToMenu() }
        c.onRestart = { [weak self, weak c] in self?.newGame(c?.world.options) }
        c.onCheckpoint = { [weak self] w in self?.saveCheckpoint(w) }
        c.onMatchEnded = { [weak self] w in self?.matchEnded(w) }
        c.onCheckAchievements = { [weak self] w in self?.checkAchievements(w) ?? [] }
        game = c
        screen = .game
        saveCheckpoint(world)
    }

    func exitToMenu() {
        saveCurrentMatch()
        game = nil
        screen = .menu
        AudioManager.shared.playMusic(.menu)
    }

    /// Keeps the newest possible checkpoint: the current state if between
    /// waves, otherwise the one from the start of this wave's preparation.
    func saveCurrentMatch() {
        guard let w = game?.world, !w.phase.isOver else { return }
        saveCheckpoint(w)
        saveProfile()
    }

    private func saveCheckpoint(_ w: GameWorld) {
        guard let cp = w.makeCheckpoint() else { return }
        do {
            try store.save(cp)
            checkpoint = cp
        } catch {
            print("Save: checkpoint failed: \(error)")
        }
        profile.noteProgress(w)
        saveProfile()
    }

    private func matchEnded(_ w: GameWorld) {
        store.deleteCheckpoint()
        checkpoint = nil
        profile.recordMatchEnd(w)
        saveProfile()
    }

    private func checkAchievements(_ w: GameWorld) -> [AchievementDefinition] {
        let new = profile.unlockAchievements(in: w)
        if !new.isEmpty { saveProfile() }
        return new
    }

    // MARK: Profile

    func updateSettings(_ change: (inout GameSettings) -> Void) {
        change(&profile.settings)
        AudioManager.shared.apply(profile.settings)
        game?.apply(profile.settings)
        saveProfile()
    }

    func resetProgress() {
        let s = profile.settings
        profile = PlayerProfile()
        profile.settings = s
        saveProfile()
    }

    private func saveProfile() {
        do { try store.save(profile) } catch { print("Save: profile failed: \(error)") }
    }
}
