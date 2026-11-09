import AVFoundation
import EvolutionDefenseAudio
import EvolutionDefenseCore

/// Plays the procedurally generated sound effects and era music with AVAudioEngine.
///
/// - Buffers are synthesized once, off the main thread.
/// - Effects play on a small pool of player nodes (round robin), with a
///   per-sound minimum interval so a dozen Laser Gatlings don't saturate the mix.
/// - Music loops on two nodes and cross-fades when the era changes.
@MainActor
final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private let sfxMixer = AVAudioMixerNode()
    private let musicMixer = AVAudioMixerNode()
    private var sfxNodes: [AVAudioPlayerNode] = []
    private var musicNodes: [AVAudioPlayerNode] = []
    private var activeMusicNode = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1)!

    private var effects: [SoundEffect: AVAudioPCMBuffer] = [:]
    /// Per-effect gain from the audio manifest (recorded sounds are levelled differently).
    private var gains: [SoundEffect: Float] = [:]
    private(set) var recordedCount = 0
    private var music: [MusicLoop: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [SoundEffect: CFTimeInterval] = [:]
    private var nextNode = 0
    private var currentTrack: MusicLoop?
    private var wantedTrack: MusicLoop?
    private var fadeTask: Task<Void, Never>?
    private(set) var isRunning = false

    private var settings = GameSettings()
    /// Muted while the snapshot tool or benchmark drives the app.
    private let silent = ProcessInfo.processInfo.environment["EVO_SNAPSHOT_DIR"] != nil
        || ProcessInfo.processInfo.environment["EVO_MUTE"] != nil

    private init() {
        engine.attach(sfxMixer)
        engine.attach(musicMixer)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: format)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: format)
        for _ in 0..<14 {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: sfxMixer, format: format)
            sfxNodes.append(n)
        }
        for _ in 0..<2 {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: musicMixer, format: format)
            n.volume = 0
            musicNodes.append(n)
        }
        engine.prepare()
    }

    /// Starts the engine and synthesizes all effects in the background.
    func start(settings: GameSettings) {
        apply(settings)
        do {
            try engine.start()
            isRunning = true
        } catch {
            print("Audio: engine failed to start (\(error)); continuing without sound")
            return
        }
        // Recorded sounds from the audio manifest first (AssetPack/audio_manifest.json);
        // everything else is synthesized off the main thread.
        let recorded = loadRecordedEffects()
        Task.detached(priority: .userInitiated) {
            var built: [(SoundEffect, [Float])] = []
            for e in SoundEffect.allCases where !recorded.contains(e) { built.append((e, SoundSynth.effect(e))) }
            await MainActor.run {
                for (e, samples) in built { self.effects[e] = self.buffer(samples) }
            }
        }
    }

    func apply(_ s: GameSettings) {
        settings = s
        engine.mainMixerNode.outputVolume = silent ? 0 : Float(s.masterVolume)
        // 0.6 headroom: many effects can overlap in a big fight.
        sfxMixer.outputVolume = s.effectsEnabled ? Float(s.effectsVolume) * 0.6 : 0
        musicMixer.outputVolume = s.musicEnabled ? Float(s.musicVolume) : 0
    }

    // MARK: Effects

    /// Minimum seconds between two plays of the same sound.
    private func minInterval(_ e: SoundEffect) -> CFTimeInterval {
        switch e {
        case .hit: 0.05
        case .shotBullet, .shotLaser, .shotArrow: 0.07
        case .shotStone, .shotRail, .enemyDeath, .robotDeath: 0.06
        case .explosion, .shotCannon, .shotPlasma, .shotRocket, .shotBeam: 0.09
        default: 0.02
        }
    }

    private struct AudioManifest: Decodable {
        struct Entry: Decodable { var file: String; var gain: Float? }
        var effects: [String: Entry]
    }

    /// Loads recorded effects listed in the audio manifest. Missing files fall back to synthesis.
    private func loadRecordedEffects() -> Set<SoundEffect> {
        guard let url = Bundle.main.url(forResource: "audio_manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(AudioManifest.self, from: data) else { return [] }
        var loaded = Set<SoundEffect>()
        for (id, entry) in manifest.effects {
            guard let effect = SoundEffect(rawValue: id) else { continue }
            let name = (entry.file as NSString).deletingPathExtension, ext = (entry.file as NSString).pathExtension
            guard let fileURL = Bundle.main.url(forResource: name, withExtension: ext),
                  let file = try? AVAudioFile(forReading: fileURL),
                  file.processingFormat.sampleRate == format.sampleRate, file.processingFormat.channelCount == 1,
                  let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buf)) != nil else {
                print("Audio: \(entry.file) unavailable, using synthesized \(id)")
                continue
            }
            effects[effect] = buf
            gains[effect] = entry.gain ?? 1
            loaded.insert(effect)
        }
        recordedCount = loaded.count
        return loaded
    }

    func play(_ e: SoundEffect, volume: Float = 1) {
        guard isRunning, settings.effectsEnabled, let buf = effects[e] else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[e], now - last < minInterval(e) { return }
        lastPlayed[e] = now
        let node = sfxNodes[nextNode]
        nextNode = (nextNode + 1) % sfxNodes.count
        node.volume = volume * (gains[e] ?? 1)
        node.scheduleBuffer(buf, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
    }

    // MARK: Music

    /// Cross-fades to `track` (synthesizing it first if needed).
    func playMusic(_ track: MusicLoop) {
        wantedTrack = track
        guard isRunning, track != currentTrack else { return }
        if let buf = music[track] {
            crossfade(to: buf, track: track)
            return
        }
        Task.detached(priority: .utility) {
            let samples = SoundSynth.music(track)
            await MainActor.run {
                let buf = self.buffer(samples)
                self.music[track] = buf
                if self.wantedTrack == track { self.crossfade(to: buf, track: track) }
            }
        }
    }

    func stopMusic() {
        wantedTrack = nil
        currentTrack = nil
        fadeTask?.cancel()
        for n in musicNodes { n.stop(); n.volume = 0 }
    }

    private func crossfade(to buf: AVAudioPCMBuffer, track: MusicLoop) {
        currentTrack = track
        let old = musicNodes[activeMusicNode]
        activeMusicNode = 1 - activeMusicNode
        let new = musicNodes[activeMusicNode]
        new.stop()
        new.volume = 0
        new.scheduleBuffer(buf, at: nil, options: .loops)
        new.play()
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            let steps = 30
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
                let k = Float(i) / Float(steps)
                new.volume = k
                old.volume = 1 - k
            }
            old.stop()
        }
    }

    static func track(for era: Era) -> MusicLoop {
        switch era {
        case .primitive: .primitive
        case .medieval: .medieval
        case .industrial: .industrial
        case .futuristic: .futuristic
        }
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buf
    }

    // MARK: Self-check (EVO_AUDIO_CHECK)

    /// Plays a few sounds with the output muted and measures the signal on the
    /// effects and music buses, proving the playback path works end to end.
    func selfCheck() async -> String {
        guard isRunning else { return "engine not running" }
        engine.mainMixerNode.outputVolume = 0
        let sfxMeter = PeakMeter(), musicMeter = PeakMeter()
        // Tap blocks run on the audio thread, so they must not be main-actor isolated.
        sfxMixer.installTap(onBus: 0, bufferSize: 4096, format: nil, block: sfxMeter.tapBlock())
        musicMixer.installTap(onBus: 0, bufferSize: 4096, format: nil, block: musicMeter.tapBlock())
        var waited = 0
        while effects.count < SoundEffect.allCases.count && waited < 100 { try? await Task.sleep(for: .milliseconds(100)); waited += 1 }
        let saved = settings
        apply({ var s = saved; s.effectsEnabled = true; s.musicEnabled = true; s.effectsVolume = 1; s.musicVolume = 1; return s }())
        engine.mainMixerNode.outputVolume = 0
        for e in [SoundEffect.explosion, .waveStart, .shotLaser, .achievement] {
            play(e)
            try? await Task.sleep(for: .milliseconds(250))
        }
        playMusic(.futuristic)
        waited = 0
        while musicMeter.peak == 0 && waited < 150 { try? await Task.sleep(for: .milliseconds(100)); waited += 1 }
        sfxMixer.removeTap(onBus: 0)
        musicMixer.removeTap(onBus: 0)
        stopMusic()
        apply(saved)
        return String(format: "effects=%d/%d (recorded %d) sfxPeak=%.3f musicPeak=%.3f", effects.count, SoundEffect.allCases.count, recordedCount,
                      sfxMeter.peak, musicMeter.peak)
    }
}

/// Thread-safe peak level, fed from the audio render thread.
private final class PeakMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    var peak: Float { lock.withLock { value } }
    nonisolated func tapBlock() -> AVAudioNodeTapBlock { { [self] b, _ in self.feed(b) } }
    func feed(_ b: AVAudioPCMBuffer) {
        guard let ch = b.floatChannelData?[0] else { return }
        var p: Float = 0
        for i in 0..<Int(b.frameLength) { p = max(p, abs(ch[i])) }
        lock.withLock { value = max(value, p) }
    }
}
