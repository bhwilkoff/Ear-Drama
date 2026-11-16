import AVFoundation
import Foundation
import Testing

// Decision 080 (owner 2026-11-16, Q4: "Keep recording"): closing the iPhone Duo during a take keeps recording.
// The fold cannot be performed in a test, so these hold the two things it does to a take: the microphone's
// hardware format changes under an open capture (the engine reconfigures and its tap comes back in the new format),
// and the studio's views are rebuilt around a session that must not notice. Nothing here plays or records sound.
//
// Broken controls, 2026-11-16, each against a mutated copy and seen to fail: CaptureSink.receive dropping a buffer
// whose format the converter was not made for (the old behavior, before `retarget`): both tests fail, the take
// holding only the voice from before the fold.

private func fixture() -> PlayScript {
    func speech(_ id: String, _ role: String) -> ScriptLine {
        ScriptLine(id: id, kind: .speech, role: role, parts: [.say("words")])
    }
    let lines = [speech("L0001", "FIBBER"), speech("L0002", "MOLLY"), speech("L0003", "FIBBER")]
    let roles = ["MOLLY", "FIBBER"].map { name in
        PlayScript.Role(name: name, lines: lines.filter { $0.role == name }.count, words: 1)
    }
    return PlayScript(id: "gut-fold", revision: "r1", kind: "radio", title: "Fold", authors: [],
                      source: .init(name: "Fixture", url: "https://example.org"),
                      rights: .init(bucket: "script_source_cleared", evidence: []), roles: roles, lines: lines)
}

private func sine(_ hz: Double, seconds: Double, rate: Double, amplitude: Float = 0.3) -> [Float] {
    (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / rate)) }
}

/// The open Duo's microphone before the fold, and after it: a different rate and channel count, as a
/// reconfigured engine's input can report.
private let before = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
private let after = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!

/// Mono samples as the hardware delivers them: 1024-frame buffers in `format`, each channel the same.
private func buffers(_ samples: [Float], _ format: AVAudioFormat) -> [AVAudioPCMBuffer] {
    stride(from: 0, to: samples.count, by: 1024).map { start in
        let slice = samples[start..<min(start + 1024, samples.count)]
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(slice.count))!
        buffer.frameLength = AVAudioFrameCount(slice.count)
        for channel in 0..<Int(format.channelCount) {
            for (i, s) in slice.enumerated() { buffer.floatChannelData![channel][i] = s }
        }
        return buffer
    }
}

/// The span of a signal louder than the room, in seconds at the take rate.
private func loudSeconds(_ samples: [Float]) -> Double {
    guard let first = samples.firstIndex(where: { abs($0) > 0.05 }),
          let last = samples.lastIndex(where: { abs($0) > 0.05 }) else { return 0 }
    return Double(last - first) / TakeAudio.sampleRate
}

/// The engine seam with the app's real capture inside it: every buffer goes through `CaptureSink`, as the tap's do,
/// and `fold()` is what `EngineLiveAudio` does when the engine reconfigures under a take.
private final class FoldingLiveAudio: LiveAudio {
    private var sink: CaptureSink?
    private var format = before
    private(set) var captures = 0

    var isListening: Bool { sink != nil && captures > 1 }

    func outputRoute() -> AudioRoute { .headphones }
    func start(echoCancelled: Bool) throws {}
    func play(_ cue: CueAudio) async {}
    func stop() {}

    func beginCapture(_ onChunk: @escaping @MainActor @Sendable ([Float]) -> Void) {
        captures += 1
        sink = CaptureSink(from: format, onChunk: onChunk)
        if captures == 1 {
            feed((0..<Int(format.sampleRate)).map { _ in Float.random(in: -0.0005...0.0005) })  // room tone
        }
    }

    func endCapture() -> MicrophoneCapture {
        let samples = sink?.drain() ?? []
        sink = nil
        return MicrophoneCapture(samples: samples, sampleRate: TakeAudio.sampleRate)
    }

    func feed(_ samples: [Float]) {
        for buffer in buffers(samples, format) { sink?.receive(buffer) }
    }

    func fold() {
        format = after
        sink?.retarget(from: after)
    }
}

/// Lets the main actor deliver the capture's chunks (the tap hands them over in a Task) until `done` holds.
@MainActor private func settle(until done: () -> Bool) async throws {
    for _ in 0..<300 where !done() { try await Task.sleep(for: .milliseconds(10)) }
}

private final class NoVoice: StandInVoice {
    func render(_ text: String, part: PartID, rate: Float) async -> StandInAudio? { nil }
}

struct FoldContinuityTests {
    @Test func aCaptureKeepsEverySampleWhenTheMicrophonesFormatChangesUnderIt() throws {
        let sink = CaptureSink(from: before) { _ in }
        for b in buffers(sine(220, seconds: 0.5, rate: 48_000), before) { sink.receive(b) }
        sink.retarget(from: after)
        for b in buffers(sine(330, seconds: 0.5, rate: 44_100), after) { sink.receive(b) }
        // A buffer in a third format with no retarget first: the capture adapts rather than dropping it.
        let mono48 = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        for b in buffers(sine(440, seconds: 0.5, rate: 48_000), mono48) { sink.receive(b) }
        let samples = sink.drain()
        let seconds = Double(samples.count) / TakeAudio.sampleRate
        #expect(abs(seconds - 1.5) < 0.03, "1.5 s heard in three formats, \(seconds) s kept")
        #expect(loudSeconds(samples) > 1.45, "no stretch of the take went quiet")

        let url = FileManager.default.temporaryDirectory.appending(path: "fold-\(UUID().uuidString).flac")
        defer { try? FileManager.default.removeItem(at: url) }
        try TakeAudio.write(MicrophoneCapture(samples: samples, sampleRate: TakeAudio.sampleRate), to: url)
        let read = try TakeAudio.read(url)
        #expect(read.samples.count == samples.count, "the file holds every sample")
    }

    @Test func aTakeRecordingThroughAFoldKeepsListeningAndItsFileHoldsBothSides() async throws {
        let script = fixture()
        let store = ProductionStore(root: FileManager.default.temporaryDirectory
            .appending(path: "fold-tests-\(UUID().uuidString)", directoryHint: .isDirectory))
        defer { try? FileManager.default.removeItem(at: store.root) }
        var production = try store.create(script)
        production = try Relay.take(.role("MOLLY"), performer: nil, in: production, script: script)
        try store.save(production)
        let audio = FoldingLiveAudio()
        let session = RecordingSession(production: production, script: script, part: .role("MOLLY"), store: store,
                                       audio: audio, voice: NoVoice(), sleep: { _ in }, announce: {})
        await session.begin(echoCancelled: false)
        let recording = Task { await session.record("L0002") }
        try await settle { audio.isListening }
        #expect(session.phase == .listening(lineID: "L0002"))

        audio.feed(sine(220, seconds: 0.5, rate: 48_000))
        try await settle { session.levels.count > 10 }
        audio.fold()
        #expect(session.phase == .listening(lineID: "L0002"), "the fold does not end the line")
        audio.feed(sine(330, seconds: 0.5, rate: 44_100))
        audio.feed([Float](repeating: 0, count: 66_150))  // 1.5 s of silence ends the line
        try await settle { !audio.isListening }
        // Unheard silence never ends the line, so a capture that lost the fold would wait forever: end it and fail.
        #expect(!audio.isListening, "the silence after the fold was heard and ended the line")
        if audio.isListening { session.end() }
        await recording.value

        let kept = try #require(store.production(production.id))
        let take = try #require(kept.takes.last { $0.lineID == "L0002" })
        let file = try TakeAudio.read(store.takeURL(kept, take))
        #expect(file.samples.count == take.frames)
        #expect(loudSeconds(file.samples) > 0.95, "the voice before the fold and after it are both in the take")
        session.end()
    }
}
