#if os(iOS) || os(macOS)
import AVFoundation
import Foundation

/// A Kokoro line read aloud once, live (PLAYS-DESIGN §5: a scene partner, never a performer): each render is scheduled
/// on an `AVAudioPlayerNode` as it is made, so the next piece renders while one plays, and dropped once played. Pitch is
/// the playback rate and the model's speed carries the tempo (`Kokoro.speedFor`), as on Android and the web. Each piece
/// is scheduled at a known sample of the node's timeline, so the word heard (`onWord`, PLAYS-DESIGN §2.11 rule 3) is
/// read from the node's own clock against the duration model's word starts. Muted (the test door), nothing reaches an
/// output: each piece takes its real length on a wall clock, so the words still move. Writes nothing.
@MainActor
final class KokoroLive {
    static let shared = KokoroLive()

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var run = 0
    private var pending = 0
    private var drained: CheckedContinuation<Void, Never>?
    /// Where the next piece goes on the node's timeline; each scheduled piece's place and timing.
    private var cursor: AVAudioFramePosition = 0
    private var placed: [AVAudioFramePosition] = []
    private var timings: [ReadAlong.KokoroPiece?] = []
    /// The line's printed words, paired with the phoneme words only when the whole line's counts agree.
    private var printed: [ReadAlong.Word] = []
    private var pairs = false
    private var words: [(at: AVAudioFramePosition, word: ReadAlong.Word)] = []
    private var mutedEpoch: Date?
    private var clock: Task<Void, Never>?

    init() { engine.attach(node) }

    /// True when Kokoro read the line; false when it cannot (the caller then reads it with the system voice).
    /// `onWord` hears each word of `DeviceVoices.said(text)` as it is heard (a range of that string), nil at the end.
    func speak(_ playID: String, _ text: String, voice: String, rate: Double, pitch: Double, muted: Bool,
               onWord: ((ReadAlong.Word?) -> Void)? = nil) async -> Bool {
        stop()
        run += 1
        let mine = run
        let speed = Kokoro.speedFor(rate: rate, pitch: pitch)
        let playRate = Kokoro.sampleRate * pitch
        printed = ReadAlong.textWords(DeviceVoices.said(text))
        if let onWord { startClock(run: mine, rate: playRate, muted: muted, onWord: onWord) }
        let read = await KokoroReader.shared.renderPieces(playID, text, voice: voice, speed: speed, onTiming: { [weak self] t, line in
            await self?.timed(t, line: line, run: mine)
        }) { [weak self] piece in
            await self?.schedule(piece, rate: playRate, muted: muted, run: mine)
        }
        if read, mine == run { await drain() }
        if mine == run {
            clock?.cancel()
            clock = nil
            onWord?(nil)
        }
        return read
    }

    private func timed(_ t: ReadAlong.KokoroPiece?, line: String, run mine: Int) {
        guard mine == run else { return }
        if timings.isEmpty { pairs = !printed.isEmpty && ReadAlong.phonemeWordCount(line) == printed.count }
        timings.append(t)
    }

    /// The words of the pieces scheduled so far, on the node's timeline (rule 3: none when a piece has no timing or
    /// the line's words do not pair).
    private func layOut() {
        guard pairs, placed.count <= timings.count else { return }
        var out: [(AVAudioFramePosition, ReadAlong.Word)] = []
        for (k, at) in placed.enumerated() {
            guard let t = timings[k], let starts = ReadAlong.phonemeWordStarts([t]) else {
                words = []
                pairs = false
                return
            }
            for s in starts where out.count < printed.count { out.append((at + AVAudioFramePosition(s), printed[out.count])) }
        }
        words = out.map { (at: $0.0, word: $0.1) }
    }

    private func startClock(run mine: Int, rate: Double, muted: Bool, onWord: @escaping (ReadAlong.Word?) -> Void) {
        clock = Task { [weak self] in
            var last: ReadAlong.Word?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, mine == self.run else { return }
                guard let now = self.nowSample(rate: rate, muted: muted) else { continue }
                let heard = self.words.last { $0.at <= now }?.word
                if heard != last {
                    last = heard
                    onWord(heard)
                }
            }
        }
    }

    private func nowSample(rate: Double, muted: Bool) -> AVAudioFramePosition? {
        if muted {
            guard let e = mutedEpoch else { return nil }
            return AVAudioFramePosition(Date().timeIntervalSince(e) * rate)
        }
        guard node.isPlaying, let t = node.lastRenderTime, let p = node.playerTime(forNodeTime: t) else { return nil }
        return p.sampleTime
    }

    private func schedule(_ samples: [Float], rate: Double, muted: Bool, run mine: Int) async {
        guard mine == run else { return }
        if muted {
            if mutedEpoch == nil { mutedEpoch = Date() }
            let now = nowSample(rate: rate, muted: true) ?? 0
            let at = max(cursor, now)
            cursor = at + AVAudioFramePosition(samples.count)
            placed.append(at)
            layOut()
            pending += 1
            let wait = Double(cursor - now) / rate
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                self?.played(mine)
            }
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
        if !node.isPlaying { node.play() }
        // A little ahead of the node's clock, so a piece that renders late starts cleanly and its words stay true.
        let now = nowSample(rate: rate, muted: false) ?? 0
        let at = max(cursor, now + AVAudioFramePosition(rate * 0.05))
        cursor = at + AVAudioFramePosition(samples.count)
        placed.append(at)
        layOut()
        pending += 1
        node.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: at, atRate: rate), options: [],
                            completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.played(mine) }
        }
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
        clock?.cancel()
        clock = nil
        cursor = 0
        placed = []
        timings = []
        words = []
        pairs = false
        mutedEpoch = nil
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
