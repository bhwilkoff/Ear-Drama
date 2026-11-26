#if os(iOS) || os(macOS)
import AVFoundation
import Foundation

/// Renders a finished play's timeline into `mix.m4a` (PLAYS-DESIGN §4.1, B32 §8): an arithmetic chunk mixer feeding
/// the AAC writer. Each chunk is the voice placements times their stored gain, plus every sound placement through
/// `SoundMix.renderSound` (looped, ducked under the voice, faded). A timeline with sound renders twice: the first
/// pass measures the float sum's sample peak, the second writes every sample times one scalar (§4.3, no limiter).
/// It reads only take files named by the timeline, and a timeline holds only human takes, so a stand-in cannot reach
/// the mix (§5 rule 3), and it refuses any take whose samples are marked synthetic. A take the bleed check flagged
/// is refused, never mixed (§8 rule 3).
nonisolated enum MixRenderer {
    enum Failure: Error { case engine(String), bleed(lineID: String) }

    /// What the mixer asks its loader for: a voice take, or one sound placement's source.
    enum Source {
        case voice(MixTimeline.Placement)
        case sound(SoundPlacement)

        var key: String {
            switch self {
            case let .voice(p): "f:\(p.file)"
            case let .sound(x):
                if case .take = x.src, let file = x.file { "f:\(file)" } else { "s:\(x.soundID)" }
            }
        }
    }

    typealias Loader = (Source) throws -> [Float]

    static let chunkSeconds = 10.0

    /// Frames [from, from + count) of the timeline as the float sum, before any scalar. A loader returns a source's
    /// whole samples; this takes each placement's window of them.
    static func mixChunk(_ timeline: MixTimeline, from: Int, count: Int, load: Loader) throws -> [Float] {
        var out = [Float](repeating: 0, count: count)
        let to = from + count
        for p in timeline.placements {
            if p.start + p.frames <= from || p.start >= to { continue }
            let samples = try load(.voice(p))
            let window = samples[min(p.inFrame, samples.count)..<min(p.outFrame, samples.count)]
            let a = max(from, p.start), b = min(to, p.start + window.count)
            guard a < b else { continue }
            if p.inFrame > 0 { try SyntheticAudio.refuse(Array(window)) }
            let g = Double(p.gain)
            for f in a..<b {
                out[f - from] = Float(Double(out[f - from]) + Double(window[window.startIndex + f - p.start]) * g)
            }
        }
        if !timeline.sounds.isEmpty {
            var bed = [Float](repeating: 0, count: count)
            var envelopes: [Double: [DuckPoint]] = [:]
            for x in timeline.sounds {
                if x.start + x.frames <= from || x.start >= to { continue }
                if envelopes[x.duck] == nil {
                    envelopes[x.duck] = SoundMix.duckEnvelope(timeline.voice, depthDb: x.duck, sampleRate: timeline.sampleRate)
                }
                SoundMix.renderSound(x, samples: try load(.sound(x)), points: envelopes[x.duck] ?? [], from: from,
                                     count: count, into: &bed)
            }
            for i in 0..<count { out[i] = Float(Double(out[i]) + Double(bed[i])) }
        }
        return out
    }

    /// The first pass: the sample peak of the float sum, as the one scalar that holds it at -1 dBFS. A voice-only
    /// timeline is one pass and keeps its level (1).
    static func scalar(for timeline: MixTimeline, chunk: Int, load: Loader, evict: (Int) -> Void = { _ in }) throws -> Double {
        guard !timeline.sounds.isEmpty else { return 1 }
        var peak = 0.0
        var c0 = 0
        while c0 < timeline.totalFrames {
            let c1 = min(timeline.totalFrames, c0 + chunk)
            for v in try mixChunk(timeline, from: c0, count: c1 - c0, load: load) { peak = max(peak, Double(abs(v))) }
            evict(c1)
            c0 = c1
        }
        return SoundMix.mixScalar(peak)
    }

    static func scale(_ samples: [Float], by scalar: Double) -> [Float] {
        scalar == 1 ? samples : samples.map { Float(Double($0) * scalar) }
    }

    /// The writing pass: every chunk of the timeline, every sample times `scalar`.
    static func finalChunks(_ timeline: MixTimeline, chunk: Int, scalar: Double, load: Loader, evict: (Int) -> Void = { _ in },
                            sink: ([Float]) throws -> Void) throws {
        var c0 = 0
        while c0 < timeline.totalFrames {
            let c1 = min(timeline.totalFrames, c0 + chunk)
            try sink(scale(try mixChunk(timeline, from: c0, count: c1 - c0, load: load), by: scalar))
            evict(c1)
            c0 = c1
        }
    }

    /// `loadSound` returns the samples of a pack or own cue; without it a timeline that holds one cannot be mixed.
    static func render(_ timeline: MixTimeline, takesFolder: URL, to destination: URL,
                       loadSound: (@Sendable (SoundSource) throws -> [Float])? = nil) throws {
        if let flagged = timeline.placements.first(where: \.bleed) { throw Failure.bleed(lineID: flagged.lineID) }
        if loadSound == nil {
            let unreachable = timeline.sounds.filter { if case .take = $0.src { false } else { true } }.map(\.soundID)
            if !unreachable.isEmpty { throw MixTimeline.Failure.missingSounds(unreachable) }
        }
        let rate = timeline.sampleRate
        let chunk = max(1, Int(chunkSeconds * rate))

        var lastUse: [String: Int] = [:]
        for p in timeline.placements { lastUse[Source.voice(p).key] = max(lastUse[Source.voice(p).key] ?? 0, p.start + p.frames) }
        for x in timeline.sounds { lastUse[Source.sound(x).key] = max(lastUse[Source.sound(x).key] ?? 0, x.start + x.frames) }
        var cache: [String: [Float]] = [:]
        let load: Loader = { source in
            if let hit = cache[source.key] { return hit }
            let samples: [Float]
            switch source {
            case let .voice(p): samples = try readTake(takesFolder.appending(path: p.file))
            case let .sound(x):
                if case .take = x.src, let file = x.file {
                    samples = try readTake(takesFolder.appending(path: file))
                } else if let loadSound {
                    samples = try loadSound(x.src)
                    try SyntheticAudio.refuse(samples)
                } else {
                    throw MixTimeline.Failure.missingSounds([x.soundID])
                }
            }
            cache[source.key] = samples
            return samples
        }
        func evict(_ end: Int) {
            for (key, last) in lastUse where last <= end { cache[key] = nil }
        }

        let scalar = try MixRenderer.scalar(for: timeline, chunk: chunk, load: load, evict: evict)
        cache = [:]

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let partial = destination.deletingLastPathComponent()
            .appending(path: ".mix-\(UUID().uuidString.prefix(8)).m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000]
        do {
            let output = try AVAudioFile(forWriting: partial, settings: settings, commonFormat: .pcmFormatFloat32,
                                         interleaved: false)
            try finalChunks(timeline, chunk: chunk, scalar: scalar, load: load, evict: evict) { samples in
                if let buffer = TakeAudio.buffer(samples, format: format) { try output.write(from: buffer) }
            }
            output.close()
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: destination)
        }
    }

    private static func readTake(_ url: URL) throws -> [Float] {
        let audio = try TakeAudio.read(url)
        try SyntheticAudio.refuse(audio.samples)
        return audio.samples
    }
}
#endif
