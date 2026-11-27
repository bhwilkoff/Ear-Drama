#if DEBUG && (os(iOS) || os(macOS))
import AVFoundation
import Foundation

/// The objective half of the listening pass: the rendered export's duck depth, attack and release, voice-to-cue level,
/// loudness and clipping, from the real renderer's float output and the decoded m4a. DEBUG only.
enum SoundPassMeasure {
    static let win = 480

    static func rmsDb(_ x: ArraySlice<Float>) -> Double {
        guard !x.isEmpty else { return -200 }
        var s = 0.0
        for v in x { s += Double(v) * Double(v) }
        return 10 * log10(max(1e-20, s / Double(x.count)))
    }

    static func report(timeline: MixTimeline, takes: URL, sources: SoundSources, mix: URL) {
        let load: MixRenderer.Loader = { source in
            switch source {
            case let .voice(p): return try TakeAudio.read(takes.appending(path: p.file)).samples
            case let .sound(x): return try sources.samples(x.src)
            }
        }
        let n = timeline.totalFrames
        var tv = timeline; tv.sounds = []
        let ts = MixTimeline(sampleRate: timeline.sampleRate, placements: [], totalFrames: n, sounds: timeline.sounds, voice: timeline.voice)
        guard let voice = try? MixRenderer.mixChunk(tv, from: 0, count: n, load: load),
              let sound = try? MixRenderer.mixChunk(ts, from: 0, count: n, load: load) else { return SoundPass.log("measure: stems failed") }
        SoundPass.log(String(format: "MEASURE voice spans %d (merged, hold %.0f ms), %.1f s total", timeline.voice.count, SoundMix.holdMs,
                             Double(n) / timeline.sampleRate))
        SoundPass.log("MEASURE spans s: " + timeline.voice.map { String(format: "%.2f-%.2f", Double($0.start) / timeline.sampleRate, Double($0.end) / timeline.sampleRate) }.joined(separator: " "))
        SoundPass.log("MEASURE sounds s: " + timeline.sounds.map { String(format: "%@ %.2f-%.2f", $0.src.name, Double($0.start) / timeline.sampleRate, Double($0.start + $0.frames) / timeline.sampleRate) }.joined(separator: "; "))
        var inVoice = 0.0, inSound = 0.0, count = 0
        for s in timeline.voice {
            let r = max(0, s.start)..<min(n, s.end)
            guard r.count > 480 else { continue }
            inVoice += rmsDb(voice[r]); inSound += rmsDb(sound[r]); count += 1
        }
        if count > 0 {
            SoundPass.log(String(format: "MEASURE voice-minus-sound in voiced spans (ducked sounds, all together): %+.1f dB (voice %.1f, sound %.1f dBFS rms)",
                                 (inVoice - inSound) / Double(count), inVoice / Double(count), inSound / Double(count)))
        }
        for x in timeline.sounds {
            var t1 = ts; t1.sounds = [x]
            t1.voice = timeline.voice
            let off = SoundPlacement(slotID: x.slotID, soundID: x.soundID, lineID: x.lineID, at: x.at, src: x.src, file: x.file,
                                     lane: x.lane, start: x.start, frames: x.frames, inFrame: x.inFrame, outFrame: x.outFrame,
                                     loop: x.loop, gain: x.gain, fadeIn: x.fadeIn, fadeOut: x.fadeOut, duck: 0)
            var t0 = ts; t0.sounds = [off]
            guard let a = try? MixRenderer.mixChunk(t1, from: 0, count: n, load: load),
                  let b = try? MixRenderer.mixChunk(t0, from: 0, count: n, load: load) else { continue }
            var gain = [Double](repeating: .nan, count: n / win)
            for i in 0..<gain.count {
                let ub = rmsDb(b[(i * win)..<((i + 1) * win)])
                if ub > -80 { gain[i] = rmsDb(a[(i * win)..<((i + 1) * win)]) - ub }
            }
            let label = "\(x.at) \(x.lineID) \(x.src.name) lane=\(x.lane) target=\(x.duck) dB"
            let ext = (x.start / win)..<min(gain.count, (x.start + x.frames) / win)
            var line = "MEASURE sound \(label):"
            var parts: [String] = []
            let ms = { (w: Int) in Double(w * self.win) / timeline.sampleRate * 1000 }
            func first(_ from: Int, _ to: Int, _ test: (Double) -> Bool) -> Int? {
                guard max(from, 0) < min(to, gain.count) else { return nil }
                return (max(from, 0)..<min(to, gain.count)).first { !gain[$0].isNaN && test(gain[$0]) }
            }
            var depthSeen = false
            for s in timeline.voice {
                let s0 = s.start / win, s1 = s.end / win
                let lo = max(s0 + 5, ext.lowerBound), hi = min(s1 - 5, ext.upperBound)
                guard hi - lo > 3 else { continue }
                let core = lo..<hi
                let depths = core.compactMap { gain[$0].isNaN ? nil : gain[$0] }.sorted()
                guard !depths.isEmpty else { continue }
                let depth = depths[depths.count / 2]
                if !depthSeen { parts.append(String(format: "depth %.2f dB inside the voice", depth)); depthSeen = true }
                if s0 - 40 >= ext.lowerBound, let a10 = first(s0 - 40, s1, { $0 <= depth * 0.1 }), let a90 = first(s0 - 40, s1, { $0 <= depth * 0.9 }) {
                    parts.append(String(format: "attack 10-90%% %.0f ms, 10%% point %.0f ms before the voice", ms(a90 - a10), ms(s0) - ms(a10)))
                }
                if s1 + 130 <= ext.upperBound, let r10 = first(s1, s1 + 130, { $0 >= depth * 0.9 }), let r90 = first(s1, s1 + 130, { $0 >= depth * 0.1 }) {
                    parts.append(String(format: "release 10-90%% %.0f ms, back to full %.0f ms after the voice", ms(r90 - r10), ms(r90) - ms(s1)))
                }
            }
            line += parts.isEmpty ? " no voiced span inside this sound" : " " + parts.joined(separator: "; ")
            SoundPass.log(line)
        }
        guard let file = try? AVAudioFile(forReading: mix) else { return }
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil, let ch = buf.floatChannelData else { return }
        let dec = Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
        let rate = file.processingFormat.sampleRate
        let clips = dec.filter { abs($0) >= 0.999 }.count
        let vL = BS1770.integratedLoudness(voice, sampleRate: timeline.sampleRate)
        let mL = BS1770.integratedLoudness(dec, sampleRate: rate)
        SoundPass.log(String(format: "MEASURE loudness: voice stem %.1f LUFS (target -16), decoded mix %.1f LUFS, mix sample peak %.2f dBFS (ceiling -1), samples at full scale %d",
                             vL ?? .nan, mL ?? .nan, 20 * log10(Double(BS1770.samplePeak(dec))), clips))
    }
}

private extension SoundSource {
    var name: String {
        switch self {
        case let .own(_, n): n ?? "own"
        case let .pack(_, c): c
        case .take: "take"
        }
    }
}
#endif
