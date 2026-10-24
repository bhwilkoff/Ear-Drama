#if os(iOS) || os(macOS)
import AVFoundation
import Foundation

/// A device voice reading one line, in memory only (PLAYS-DESIGN §5). It is a
/// scene partner, never a performer: it is played, measured by the bleed check,
/// and released. It has no Codable conformance and no path to a file, and no
/// file writer in the app accepts it (`TakeAudio.write` takes only a
/// `MicrophoneCapture`), and its samples are marked synthetic when it is made,
/// so a writer refuses them even copied into another type (`SyntheticAudio`).
nonisolated struct StandInAudio: Sendable {
    /// Mono, at `sampleRate` (48 kHz once resampled).
    let samples: [Float]
    let sampleRate: Double

    init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
        SyntheticAudio.mark(samples)
    }
}

/// Where stand-in lines come from. The app's is the system voice; the tests'
/// is a signal they can look for in every file a session writes.
protocol StandInVoice: AnyObject {
    func render(_ text: String, part: PartID, rate: Float) async -> StandInAudio?
}

/// The system voices through `AVSpeechSynthesizer.write(_:toBufferCallback:)`
/// into memory (research 08a §1.2). Only on-device voices are offered, never a
/// novelty voice and never a Personal Voice: a Personal Voice is offered only
/// in a live listen-through, through `speak` (C10, §5 rule 6; `ListenSpeaker`).
final class SystemStandInVoice: StandInVoice {
    private let synthesizer = AVSpeechSynthesizer()
    private var assigned: [PartID: Int] = [:]
    private lazy var voices = Self.castableVoices()

    init() {
        #if os(iOS)
        synthesizer.usesApplicationAudioSession = true
        #endif
    }

    static func castableVoices() -> [AVSpeechSynthesisVoice] {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en")
                && !$0.voiceTraits.contains(.isPersonalVoice)
                && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        return english.sorted {
            if ($0.language == language) != ($1.language == language) { return $0.language == language }
            if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
            return $0.identifier < $1.identifier
        }
    }

    /// Voices repeat on a device with few of them; pitch tells two parts on one
    /// voice apart, and the character's name on screen does the identifying.
    static let pitches: [Float] = [1.0, 0.86, 1.14, 0.93, 1.07]

    func render(_ text: String, part: PartID, rate: Float) async -> StandInAudio? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        let index = assigned[part] ?? {
            let next = assigned.count
            assigned[part] = next
            return next
        }()
        let utterance = AVSpeechUtterance(string: words)
        if !voices.isEmpty {
            utterance.voice = voices[index % voices.count]
            utterance.pitchMultiplier = Self.pitches[(index / voices.count) % Self.pitches.count]
        }
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rate)
        let collector = SpeechCollector()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            collector.done = done
            synthesizer.write(utterance, toBufferCallback: collector.callback)
        }
        return collector.audio()
    }
}

/// Gathers the synthesizer's buffers on whatever thread it calls back on.
private nonisolated final class SpeechCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rate: Double = 22_050
    private var finished = false
    var done: CheckedContinuation<Void, Never>?

    var callback: @Sendable (AVAudioBuffer) -> Void {
        { @Sendable [self] buffer in self.receive(buffer) }
    }

    private func receive(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
            finished = true
            done?.resume()
            done = nil
            return
        }
        rate = pcm.format.sampleRate
        let n = Int(pcm.frameLength)
        if let floats = pcm.floatChannelData {
            samples += UnsafeBufferPointer(start: floats[0], count: n)
        } else if let ints = pcm.int16ChannelData {
            samples += UnsafeBufferPointer(start: ints[0], count: n).map { Float($0) / 32_768 }
        }
    }

    func audio() -> StandInAudio? {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else { return nil }
        return StandInAudio(samples: Resample.toTakeRate(samples, from: rate), sampleRate: TakeAudio.sampleRate)
    }
}

nonisolated enum Resample {
    /// Mono float samples at any rate to the take rate, in memory.
    static func toTakeRate(_ samples: [Float], from rate: Double) -> [Float] {
        guard rate != TakeAudio.sampleRate, !samples.isEmpty else { return samples }
        let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let outFormat = TakeAudio.format
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let input = TakeAudio.buffer(samples, format: inFormat),
              let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(
                Double(samples.count) * outFormat.sampleRate / rate) + 1024) else { return [] }
        let feed = OneShotInput(input)
        var error: NSError?
        converter.convert(to: output, error: &error, withInputFrom: feed.block)
        guard error == nil else { return [] }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}

/// Hands a converter one buffer, then the end of the stream.
private nonisolated final class OneShotInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    var block: AVAudioConverterInputBlock {
        { @Sendable [self] _, status in
            if let buffer = self.buffer {
                self.buffer = nil
                status.pointee = .haveData
                return buffer
            }
            status.pointee = .endOfStream
            return nil
        }
    }
}
#endif
