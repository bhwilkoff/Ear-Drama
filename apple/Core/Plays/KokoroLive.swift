#if os(iOS) || os(macOS)
import AVFoundation
import Foundation

/// A Kokoro line read aloud once, live (PLAYS-DESIGN §5: a scene partner, never a performer): each render is scheduled
/// on an `AVAudioPlayerNode` as it is made, so the next piece renders while one plays, and dropped once played. Pitch is
/// the playback rate and the model's speed carries the tempo (`Kokoro.speedFor`), as on Android and the web. Muted (the
/// test door), nothing reaches an output: the line is rendered and passes in a moment. Writes nothing.
@MainActor
final class KokoroLive {
    static let shared = KokoroLive()

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var run = 0
    private var pending = 0
    private var drained: CheckedContinuation<Void, Never>?

    init() { engine.attach(node) }

    /// True when Kokoro read the line; false when it cannot (the caller then reads it with the system voice).
    func speak(_ playID: String, _ text: String, voice: String, rate: Double, pitch: Double, muted: Bool) async -> Bool {
        stop()
        run += 1
        let mine = run
        let speed = Kokoro.speedFor(rate: rate, pitch: pitch)
        let playRate = Kokoro.sampleRate * pitch
        let read = await KokoroReader.shared.renderPieces(playID, text, voice: voice, speed: speed) { [weak self] piece in
            await self?.schedule(piece, rate: playRate, muted: muted, run: mine)
        }
        if read, mine == run { await drain() }
        return read
    }

    private func schedule(_ samples: [Float], rate: Double, muted: Bool, run mine: Int) async {
        guard mine == run else { return }
        if muted {
            try? await Task.sleep(for: .milliseconds(300))
            return
        }
        if format?.sampleRate != rate {
            node.stop()
            engine.stop()
            let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: f)
            format = f
        }
        guard let format, let buffer = TakeAudio.buffer(samples, format: format) else { return }
        if !engine.isRunning { try? engine.start() }
        pending += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.played(mine) }
        }
        if !node.isPlaying { node.play() }
    }

    private func played(_ mine: Int) {
        guard mine == run else { return }
        pending = max(0, pending - 1)
        if pending == 0 { finish() }
    }

    private func drain() async {
        guard pending > 0 else { return }
        await withCheckedContinuation { drained = $0 }
    }

    private func finish() {
        let d = drained
        drained = nil
        d?.resume()
    }

    /// Stops the line now; the next `speak` starts clean.
    func stop() {
        run += 1
        pending = 0
        node.stop()
        finish()
    }
}

/// The recorder's cue in a downloaded voice (PLAYS-DESIGN §2.8 engine `kokoro`, §5): a part cast to a Kokoro voice is
/// rendered by `render` (KokoroReader, from the play's published phonemes) into a `StandInAudio` in memory, marked
/// synthetic, played by the cue path and released like any stand-in. A line Kokoro cannot read, and every part on a
/// system voice, goes to `system` (which reads a Kokoro part in its auto-cast system voice). No file is touched here.
final class KokoroStandInVoice: StandInVoice {
    typealias Render = @Sendable (_ text: String, _ voice: String, _ speed: Float) async -> [Float]?

    private let cast: VoiceCast
    private let system: StandInVoice
    private let render: Render

    init(cast: VoiceCast, system: StandInVoice, render: @escaping Render) {
        self.cast = cast
        self.system = system
        self.render = render
    }

    /// The app's: the production's cast, the system voice, and the shared reader for the cast's play.
    static func app(cast: VoiceCast) -> StandInVoice {
        let play = cast.playID
        return KokoroStandInVoice(cast: cast, system: SystemStandInVoice(cast: cast)) { text, voice, speed in
            guard let play else { return nil }
            return await KokoroReader.shared.render(play, text, voice: voice, speed: speed)
        }
    }

    func render(_ text: String, part: PartID, rate: Float) async -> StandInAudio? {
        let r = cast.resolve(part)
        if r.read, let v = r.voice, v.engine == .kokoro {
            let speed = Kokoro.speedFor(rate: r.rate * Double(rate), pitch: r.pitch)
            if let samples = await render(text, v.id, speed), !samples.isEmpty {
                return StandInAudio(samples: Resample.toTakeRate(samples, from: Kokoro.sampleRate * r.pitch),
                                    sampleRate: TakeAudio.sampleRate)
            }
        }
        return await system.render(text, part: part, rate: rate)
    }
}
#endif
