import Foundation
import Testing
@testable import EvolutionDefenseAudio

@Suite("Procedural audio")
struct AudioSynthTests {
    private func check(_ s: [Float], name: String) {
        #expect(!s.isEmpty, "\(name) empty")
        #expect(s.allSatisfy { $0.isFinite }, "\(name) has NaN/inf")
        let peak = s.reduce(Float(0)) { max($0, abs($1)) }
        #expect(peak <= 1.0 && peak > 0.05, "\(name) peak \(peak)")
        let rms = sqrt(s.reduce(Float(0)) { $0 + $1 * $1 } / Float(s.count))
        #expect(rms > 0.003, "\(name) is nearly silent (rms \(rms))")
    }

    @Test func everyEffectIsAudibleAndSafe() {
        for e in SoundEffect.allCases {
            let s = SoundSynth.effect(e)
            check(s, name: e.rawValue)
            #expect(Double(s.count) / SoundSynth.sampleRate <= 3, "\(e) too long")
        }
    }

    @Test func musicLoopsAreSeamlessAndDistinct() {
        var lengths: [Int] = []
        for t in MusicLoop.allCases {
            let start = Date()
            let s = SoundSynth.music(t)
            print("AUDIO music \(t): \(String(format: "%.1f", Double(s.count) / SoundSynth.sampleRate)) s, built in \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
            check(s, name: "music \(t)")
            #expect(Double(s.count) / SoundSynth.sampleRate > 10)
            // Seamless loop: the jump from the last to the first sample is small.
            #expect(abs(s[s.count - 1] - s[0]) < 0.25)
            lengths.append(s.count)
        }
        #expect(Set(lengths).count > 1, "eras should differ in tempo")
    }

    @Test func synthesisIsDeterministic() {
        #expect(SoundSynth.effect(.explosion) == SoundSynth.effect(.explosion))
        #expect(SoundSynth.music(.medieval) == SoundSynth.music(.medieval))
    }
}
