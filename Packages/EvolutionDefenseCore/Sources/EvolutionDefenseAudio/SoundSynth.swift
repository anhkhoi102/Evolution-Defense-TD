// TEMPORARY AUDIO — every sound effect and music loop is synthesized in code
// at launch (no audio files ship yet). Production audio can replace this by
// loading files in the app's AudioManager; nothing else depends on it.

import Foundation

/// Every sound effect the game plays.
public enum SoundEffect: String, CaseIterable, Sendable {
    // Tower shots
    case shotStone, shotArrow, shotCannon, shotBullet, shotRocket, shotLaser, shotPlasma, shotRail, shotBeam
    // Combat
    case hit, explosion, enemyDeath, robotDeath, bossRoar, bossDeath, bossPhase
    case fireBreath, empBlast, missile, baseHit
    // Flow
    case waveStart, waveClear, eraAdvance, victory, defeat
    // Player actions & UI
    case build, upgrade, sell, repair, research, error, click, eventGood, eventBad, achievement
}

/// Background music: one loop per era plus the menu.
public enum MusicLoop: Int, CaseIterable, Sendable {
    case menu = 0, primitive, medieval, industrial, futuristic
}

public enum SoundSynth {
    public static let sampleRate = 44_100.0

    // MARK: - Effects

    public static func effect(_ e: SoundEffect) -> [Float] {
        var m = Mixer(seconds: duration(e))
        switch e {
        case .shotStone:
            m.add(noise(0.14, decay: 22, lowpass: 900), gain: 0.8)
            m.add(tone(150, to: 70, 0.12, .sine, decay: 25), gain: 0.7)
        case .shotArrow:
            m.add(pluck(880, 0.16), gain: 0.5)
            m.add(noise(0.09, decay: 40, lowpass: 7000, highpass: 2500), gain: 0.35)
        case .shotCannon:
            m.add(kick(95, to: 32, 0.4), gain: 1.0)
            m.add(noise(0.35, decay: 12, lowpass: 700), gain: 0.7)
        case .shotBullet:
            m.add(noise(0.07, decay: 60, lowpass: 9000, highpass: 1200), gain: 0.7)
            m.add(tone(1100, to: 600, 0.025, .square, decay: 90), gain: 0.25)
        case .shotRocket:
            m.add(noise(0.5, attack: 0.05, decay: 6, lowpass: 2600, highpass: 300), gain: 0.6)
            m.add(tone(180, to: 620, 0.45, .saw, attack: 0.03, decay: 7, lowpass: 1500), gain: 0.25)
        case .shotLaser:
            m.add(tone(1500, to: 450, 0.13, .square, decay: 22, lowpass: 4000), gain: 0.35)
            m.add(tone(3000, to: 900, 0.1, .sine, decay: 30), gain: 0.2)
        case .shotPlasma:
            m.add(tone(320, to: 110, 0.32, .sine, decay: 9, vibrato: (32, 0.12)), gain: 0.8)
            m.add(tone(160, to: 60, 0.3, .saw, decay: 10, lowpass: 900), gain: 0.3)
        case .shotRail:
            m.add(tone(220, to: 2400, 0.2, .saw, decay: 12, lowpass: 6000), gain: 0.35)
            m.add(noise(0.08, decay: 50, lowpass: 12000, highpass: 3000), gain: 0.45, at: 0.02)
        case .shotBeam:
            m.add(tone(2200, to: 160, 0.55, .sine, decay: 6), gain: 0.5)
            m.add(kick(70, to: 28, 0.5), gain: 0.8, at: 0.05)
            m.add(noise(0.5, decay: 8, lowpass: 1500), gain: 0.4, at: 0.05)
        case .hit:
            m.add(noise(0.035, decay: 90, lowpass: 8000, highpass: 2500), gain: 0.35)
        case .explosion:
            m.add(kick(80, to: 28, 0.5), gain: 0.9)
            m.add(noise(0.6, decay: 7, lowpass: 900), gain: 0.85)
        case .enemyDeath:
            m.add(tone(420, to: 140, 0.16, .triangle, decay: 18), gain: 0.5)
            m.add(noise(0.07, decay: 50, lowpass: 2500), gain: 0.3)
        case .robotDeath:
            m.add(metal(560, 0.35), gain: 0.5)
            m.add(noise(0.25, decay: 14, lowpass: 5000, highpass: 800), gain: 0.4)
        case .bossRoar:
            m.add(tone(78, to: 52, 1.7, .saw, attack: 0.18, decay: 1.6, lowpass: 650, vibrato: (6, 0.06)), gain: 0.9)
            m.add(noise(1.6, attack: 0.2, decay: 1.8, lowpass: 450), gain: 0.6)
        case .bossDeath:
            m.add(kick(70, to: 25, 0.9), gain: 1.0)
            m.add(noise(1.6, decay: 2.5, lowpass: 1100), gain: 0.9)
            m.add(tone(300, to: 60, 1.4, .saw, decay: 2.2, lowpass: 900), gain: 0.35, at: 0.1)
        case .bossPhase:
            m.add(kick(60, to: 30, 0.6), gain: 1.0)
            m.add(tone(110, to: 70, 1.0, .saw, attack: 0.05, decay: 3, lowpass: 800, vibrato: (9, 0.08)), gain: 0.6, at: 0.05)
        case .fireBreath:
            m.add(noise(1.0, attack: 0.12, decay: 2.6, lowpass: 1600, highpass: 150, tremolo: 14), gain: 0.8)
        case .empBlast:
            m.add(tone(1300, to: 70, 0.8, .sine, decay: 4, tremolo: 22), gain: 0.6)
            m.add(noise(0.5, decay: 8, lowpass: 3000, highpass: 600), gain: 0.4)
        case .missile:
            m.add(noise(0.7, attack: 0.5, decay: 1, lowpass: 3000, highpass: 400), gain: 0.5)
            m.add(tone(500, to: 1400, 0.6, .saw, attack: 0.3, decay: 2, lowpass: 2000), gain: 0.15)
        case .baseHit:
            m.add(kick(65, to: 35, 0.35), gain: 0.9)
            m.add(noise(0.3, decay: 14, lowpass: 380), gain: 0.7)
        case .waveStart:
            for f in [220.0, 329.6] { m.add(tone(f, 0.95, .saw, attack: 0.08, decay: 2.4, lowpass: 1300, vibrato: (5, 0.004)), gain: 0.35) }
        case .waveClear:
            for (i, f) in [523.3, 659.3, 784.0, 1046.5].enumerated() {
                m.add(tone(f, 0.5, .triangle, decay: 6), gain: 0.35, at: Double(i) * 0.08)
            }
        case .eraAdvance:
            for (i, f) in [196.0, 293.7, 392.0, 493.9, 587.3].enumerated() {
                m.add(tone(f, 1.9 - Double(i) * 0.12, .saw, attack: 0.06, decay: 1.6, lowpass: 1800), gain: 0.22, at: Double(i) * 0.12)
            }
            m.add(kick(70, to: 40, 0.6), gain: 0.6)
        case .victory:
            for (i, f) in [392.0, 523.3, 659.3, 784.0].enumerated() {
                m.add(tone(f, 0.35, .square, decay: 6, lowpass: 2500), gain: 0.22, at: Double(i) * 0.14)
            }
            for f in [523.3, 659.3, 784.0, 1046.5] { m.add(tone(f, 1.8, .saw, attack: 0.04, decay: 1.4, lowpass: 2200), gain: 0.16, at: 0.6) }
        case .defeat:
            for (i, f) in [392.0, 349.2, 311.1, 261.6].enumerated() {
                m.add(tone(f, 0.6, .triangle, attack: 0.02, decay: 3), gain: 0.35, at: Double(i) * 0.38)
            }
            m.add(tone(130.8, 1.6, .saw, attack: 0.1, decay: 1.4, lowpass: 600), gain: 0.3, at: 1.1)
        case .build:
            m.add(pluck(196, 0.25), gain: 0.5)
            m.add(noise(0.09, decay: 40, lowpass: 1300), gain: 0.5)
        case .upgrade:
            for (i, f) in [587.3, 740.0, 880.0, 1174.7].enumerated() {
                m.add(tone(f, 0.25, .triangle, decay: 10), gain: 0.3, at: Double(i) * 0.05)
            }
            m.add(noise(0.4, attack: 0.05, decay: 6, lowpass: 12000, highpass: 6000), gain: 0.12)
        case .sell:
            m.add(tone(1800, 0.12, .sine, decay: 25), gain: 0.35)
            m.add(tone(2400, 0.2, .sine, decay: 18), gain: 0.35, at: 0.07)
        case .repair:
            m.add(metal(1150, 0.18), gain: 0.4)
            m.add(metal(1150, 0.18), gain: 0.35, at: 0.16)
        case .research:
            m.add(tone(500, to: 950, 0.18, .sine, decay: 10), gain: 0.4)
            m.add(tone(1600, 0.35, .sine, decay: 9), gain: 0.2, at: 0.12)
        case .error:
            m.add(tone(170, 0.09, .square, decay: 6, lowpass: 1200), gain: 0.3)
            m.add(tone(150, 0.11, .square, decay: 6, lowpass: 1200), gain: 0.3, at: 0.12)
        case .click:
            m.add(tone(1100, 0.03, .sine, decay: 120), gain: 0.25)
        case .eventGood:
            m.add(tone(659.3, 0.3, .triangle, decay: 8), gain: 0.35)
            m.add(tone(987.8, 0.45, .triangle, decay: 6), gain: 0.35, at: 0.12)
        case .eventBad:
            m.add(tone(493.9, 0.3, .triangle, decay: 8), gain: 0.35)
            m.add(tone(349.2, 0.5, .triangle, decay: 5), gain: 0.35, at: 0.14)
        case .achievement:
            m.add(tone(1318.5, 1.0, .sine, decay: 4), gain: 0.3)
            m.add(tone(1760.0, 1.0, .sine, decay: 4), gain: 0.25, at: 0.09)
            m.add(tone(2637.0, 0.8, .sine, decay: 5), gain: 0.12, at: 0.18)
        }
        return m.finish(peak: 0.9)
    }

    static func duration(_ e: SoundEffect) -> Double {
        switch e {
        case .hit, .click: 0.06
        case .shotBullet, .shotArrow, .shotStone, .shotLaser, .enemyDeath, .sell: 0.3
        case .shotRail, .shotPlasma, .shotCannon, .build, .research, .error, .repair, .baseHit, .upgrade, .robotDeath: 0.55
        case .shotRocket, .shotBeam, .explosion, .eventGood, .eventBad, .empBlast, .missile, .waveClear: 0.9
        case .bossPhase, .fireBreath, .waveStart, .achievement: 1.3
        case .bossRoar, .bossDeath, .defeat: 2.0
        case .eraAdvance, .victory: 2.6
        }
    }

    // MARK: - Music

    public static func music(_ track: MusicLoop) -> [Float] {
        let style = MusicStyle.for(track)
        let beat = 60.0 / style.bpm
        let loopBeats = 32
        let length = Double(loopBeats) * beat
        var m = Mixer(seconds: length, loops: true)
        var rng = LCG(seed: UInt64(17 + track.rawValue * 101))

        for (bar2, chord) in style.progression.enumerated() {
            let start = Double(bar2 * 8) * beat
            // Pad: sustained chord.
            for (i, semis) in chord.enumerated() {
                let f = style.root * pow(2, Double(semis) / 12)
                m.add(tone(f, beat * 8.2, style.pad, attack: beat * 1.5, decay: 0.25, lowpass: style.padCutoff,
                           vibrato: (4.5 + Double(i), 0.003)), gain: style.padGain, at: start)
            }
            // Bass on beats 1 and 3.
            for b in stride(from: 0, to: 8, by: 2) {
                let f = style.root / 2 * pow(2, Double(chord[0]) / 12)
                m.add(tone(f, beat * 1.6, style.bassWave, attack: 0.01, decay: 2.5, lowpass: 500), gain: style.bassGain,
                      at: start + Double(b) * beat)
            }
            // Arpeggio / plucked accompaniment.
            if style.arpGain > 0 {
                for k in 0..<16 {
                    let semis = chord[k % chord.count] + 12
                    let f = style.root * pow(2, Double(semis) / 12)
                    let voice = style.pluckArp ? pluck(f, beat * 0.9) : tone(f, beat * 0.45, .square, decay: 9, lowpass: 2400)
                    m.add(voice, gain: style.arpGain, at: start + Double(k) * beat * 0.5)
                }
            }
        }
        // Melody: a stepwise walk on the scale over the second half of the loop.
        var degree = 2
        var t = Double(loopBeats / 2) * beat
        while t < length - beat {
            let dur = [0.5, 1.0, 1.0, 1.5, 2.0][Int(rng.next() * 5) % 5] * beat
            if rng.next() > 0.18 {
                degree = max(0, min(style.scale.count - 1, degree + [-2, -1, -1, 1, 1, 2][Int(rng.next() * 6) % 6]))
                let f = style.root * 2 * pow(2, Double(style.scale[degree]) / 12)
                m.add(tone(f, dur * 1.1, style.lead, attack: 0.04, decay: 1.2 / dur, lowpass: 3200, vibrato: (5.5, 0.006)),
                      gain: style.leadGain, at: t)
            }
            t += dur
        }
        // Percussion.
        for b in 0..<loopBeats {
            let at = Double(b) * beat
            switch style.drums {
            case .tribal:
                if b % 2 == 0 { m.add(kick(110, to: 70, 0.3), gain: 0.5, at: at) }
                if b % 4 == 3 { m.add(kick(170, to: 120, 0.18), gain: 0.35, at: at + beat * 0.5) }
                m.add(noise(0.05, decay: 60, lowpass: 9000, highpass: 4000), gain: 0.08, at: at + beat * 0.5)
            case .frame:
                if b % 4 == 0 { m.add(kick(90, to: 60, 0.35), gain: 0.45, at: at) }
                if b % 4 == 2 { m.add(noise(0.12, decay: 25, lowpass: 3500, highpass: 500), gain: 0.18, at: at) }
            case .machine:
                m.add(kick(85, to: 40, 0.25), gain: 0.55, at: at)
                m.add(noise(0.04, decay: 80, lowpass: 12000, highpass: 6000), gain: 0.1, at: at + beat * 0.5)
                if b % 4 == 2 { m.add(metal(700, 0.25), gain: 0.15, at: at) }
            case .electro:
                m.add(kick(70, to: 35, 0.28), gain: 0.6, at: at)
                if b % 2 == 1 { m.add(noise(0.16, decay: 20, lowpass: 6000, highpass: 1200), gain: 0.22, at: at) }
                for s in 0..<2 { m.add(noise(0.03, decay: 100, lowpass: 14000, highpass: 8000), gain: 0.07, at: at + Double(s) * beat * 0.5 + beat * 0.25) }
            case .none:
                break
            }
        }
        return m.finish(peak: 0.6)
    }

    // MARK: - Voices

    enum Wave { case sine, square, saw, triangle }

    static func tone(_ f0: Double, to f1: Double? = nil, _ dur: Double, _ wave: Wave, attack: Double = 0.003,
                     decay: Double = 4, lowpass: Double? = nil, vibrato: (Double, Double)? = nil,
                     tremolo: Double? = nil) -> [Float] {
        let n = Int(dur * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var lp = OnePole(cutoff: lowpass)
        let target = f1 ?? f0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let k = Double(i) / Double(max(1, n - 1))
            var f = f0 * pow(target / f0, k)                // exponential sweep
            if let (rate, depth) = vibrato { f *= 1 + depth * sin(2 * .pi * rate * t) }
            phase += f / sampleRate
            phase -= floor(phase)
            var s: Double
            switch wave {
            case .sine: s = sin(2 * .pi * phase)
            case .square: s = phase < 0.5 ? 0.8 : -0.8
            case .saw: s = 2 * phase - 1
            case .triangle: s = 4 * abs(phase - 0.5) - 1
            }
            var env = min(1, t / max(attack, 0.0005)) * exp(-decay * max(0, t - attack))
            env *= min(1, Double(n - i) / (sampleRate * 0.004))   // de-click tail
            if let trem = tremolo { env *= 0.6 + 0.4 * sin(2 * .pi * trem * t) }
            s *= env
            out[i] = Float(lp.process(s))
        }
        return out
    }

    static func noise(_ dur: Double, attack: Double = 0.001, decay: Double = 10, lowpass: Double? = nil,
                      highpass: Double? = nil, tremolo: Double? = nil, seed: UInt64 = 7) -> [Float] {
        let n = Int(dur * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var rng = LCG(seed: seed &+ UInt64(n))
        var lp = OnePole(cutoff: lowpass)
        var hpState = OnePole(cutoff: highpass)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            var s = rng.next() * 2 - 1
            s = lp.process(s)
            if highpass != nil { s -= hpState.process(s) }
            var env = min(1, t / max(attack, 0.0005)) * exp(-decay * max(0, t - attack))
            env *= min(1, Double(n - i) / (sampleRate * 0.004))
            if let trem = tremolo { env *= 0.55 + 0.45 * sin(2 * .pi * trem * t) }
            out[i] = Float(s * env)
        }
        return out
    }

    /// Pitch-dropping sine thump.
    static func kick(_ f0: Double, to f1: Double, _ dur: Double) -> [Float] {
        tone(f0, to: f1, dur, .sine, attack: 0.002, decay: 9 / max(dur, 0.05) * 0.5)
    }

    /// Karplus–Strong plucked string.
    static func pluck(_ f: Double, _ dur: Double) -> [Float] {
        let n = Int(dur * sampleRate)
        let period = max(2, Int(sampleRate / f))
        var rng = LCG(seed: UInt64(f * 13))
        var line = (0..<period).map { _ in rng.next() * 2 - 1 }
        var out = [Float](repeating: 0, count: n)
        var idx = 0
        for i in 0..<n {
            let next = (idx + 1) % period
            let v = (line[idx] + line[next]) * 0.4985
            out[i] = Float(line[idx]) * Float(min(1, Double(n - i) / (sampleRate * 0.01)))
            line[idx] = v
            idx = next
        }
        return out
    }

    /// Inharmonic partials: anvil / metal clank.
    static func metal(_ f: Double, _ dur: Double) -> [Float] {
        var m = Mixer(seconds: dur)
        for (ratio, g) in [(1.0, 0.5), (2.76, 0.3), (5.4, 0.2), (8.93, 0.12)] {
            m.add(tone(f * ratio, dur, .sine, decay: 9 + ratio), gain: g)
        }
        m.add(noise(0.02, decay: 150, lowpass: 9000), gain: 0.2)
        return m.samples
    }
}

// MARK: - Helpers

/// Accumulates voices into one buffer. Looping buffers wrap tails around to the start.
struct Mixer {
    var samples: [Float]
    let loops: Bool

    init(seconds: Double, loops: Bool = false) {
        samples = [Float](repeating: 0, count: max(1, Int(seconds * SoundSynth.sampleRate)))
        self.loops = loops
    }

    mutating func add(_ voice: [Float], gain: Double, at time: Double = 0) {
        let start = Int(time * SoundSynth.sampleRate)
        let g = Float(gain)
        let n = samples.count
        samples.withUnsafeMutableBufferPointer { out in
            for (i, v) in voice.enumerated() {
                var j = start + i
                if j >= n {
                    guard loops else { break }
                    j %= n
                }
                out[j] += v * g
            }
        }
    }

    /// Normalizes to `peak` and soft-clips.
    func finish(peak: Float) -> [Float] {
        let maxAbs = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard maxAbs > 0 else { return samples }
        let k = peak / maxAbs
        return samples.map { tanhf($0 * k * 1.1) / tanhf(1.1) * 0.999 }
    }
}

struct OnePole {
    private var y = 0.0
    private let a: Double?
    init(cutoff: Double?) {
        a = cutoff.map { 1 - exp(-2 * .pi * $0 / SoundSynth.sampleRate) }
    }
    mutating func process(_ x: Double) -> Double {
        guard let a else { return x }
        y += a * (x - y)
        return y
    }
}

struct LCG {
    private var s: UInt64
    init(seed: UInt64) { s = seed &* 6364136223846793005 &+ 1 }
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 11) & 0xFFFFF) / Double(0xFFFFF)
    }
}

/// Instrumentation per era (menu borrows the medieval feel, slower).
struct MusicStyle {
    enum Drums { case tribal, frame, machine, electro, none }
    var bpm: Double
    var root: Double
    var progression: [[Int]]
    var scale: [Int]
    var pad: SoundSynth.Wave
    var padCutoff: Double
    var padGain: Double
    var bassWave: SoundSynth.Wave
    var bassGain: Double
    var arpGain: Double
    var pluckArp: Bool
    var lead: SoundSynth.Wave
    var leadGain: Double
    var drums: Drums

    static func `for`(_ t: MusicLoop) -> MusicStyle {
        switch t {
        case .menu:
            MusicStyle(bpm: 76, root: 146.8, progression: [[0, 3, 7], [-4, 0, 3], [-2, 2, 5], [-5, -1, 2]],
                       scale: [0, 2, 3, 5, 7, 8, 10, 12], pad: .triangle, padCutoff: 1400, padGain: 0.16,
                       bassWave: .sine, bassGain: 0.3, arpGain: 0.08, pluckArp: true, lead: .sine, leadGain: 0.12, drums: .none)
        case .primitive:
            MusicStyle(bpm: 92, root: 146.8, progression: [[0, 7, 12], [-2, 5, 10], [-4, 3, 8], [-2, 5, 10]],
                       scale: [0, 3, 5, 7, 10, 12, 15], pad: .sine, padCutoff: 900, padGain: 0.14,
                       bassWave: .sine, bassGain: 0.35, arpGain: 0, pluckArp: false, lead: .sine, leadGain: 0.16, drums: .tribal)
        case .medieval:
            MusicStyle(bpm: 100, root: 220.0, progression: [[0, 3, 7], [-2, 2, 5], [-4, 0, 3], [-5, -1, 2]],
                       scale: [0, 2, 3, 5, 7, 9, 10, 12], pad: .triangle, padCutoff: 1200, padGain: 0.12,
                       bassWave: .triangle, bassGain: 0.3, arpGain: 0.14, pluckArp: true, lead: .triangle, leadGain: 0.14, drums: .frame)
        case .industrial:
            MusicStyle(bpm: 108, root: 164.8, progression: [[0, 3, 7], [1, 5, 8], [-2, 2, 5], [0, 3, 7]],
                       scale: [0, 1, 3, 5, 7, 8, 10, 12], pad: .saw, padCutoff: 700, padGain: 0.12,
                       bassWave: .saw, bassGain: 0.28, arpGain: 0.06, pluckArp: false, lead: .square, leadGain: 0.08, drums: .machine)
        case .futuristic:
            MusicStyle(bpm: 118, root: 130.8, progression: [[0, 3, 7, 10], [-4, 0, 3, 7], [-7, -3, 0, 3], [-2, 2, 5, 9]],
                       scale: [0, 2, 3, 5, 7, 8, 10, 12], pad: .saw, padCutoff: 1600, padGain: 0.1,
                       bassWave: .square, bassGain: 0.22, arpGain: 0.1, pluckArp: false, lead: .saw, leadGain: 0.08, drums: .electro)
        }
    }
}
