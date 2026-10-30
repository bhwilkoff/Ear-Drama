import AppKit
import CoreText
import SwiftUI
import XCTest

// D3-6: the play page, the cast sheet and the recorder in every mode and state, drawn to PNG through
// ImageRenderer so a person can look at them. Skipped unless GRAMMAR_RENDER_DIR is set
// (xcodebuild: TEST_RUNNER_GRAMMAR_RENDER_DIR=<dir>). Nothing here plays or records sound: the audio
// and the device voice are fakes, and every take is a short tone written to a temporary folder.
//
// ImageRenderer cannot draw AppKit-backed controls. The segmented Picker, the Menu button and a List
// are drawn as placeholders (or not at all); the views below that sit in a List or a Picker are
// rendered by their own parts (the head board and the part cards, not the List around them), and the
// native Picker is left as the system draws it, never swapped for a custom control.

nonisolated final class PlaysRenderTests: XCTestCase {
    @MainActor func testPlayPageAndCastSheet() throws {
        let rig = try RenderRig()
        defer { rig.cleanup() }
        try rig.playPageAndCastSheet()
    }

    @MainActor func testShowTileOnTheDramaBoard() throws {
        let rig = try RenderRig()
        defer { rig.cleanup() }
        try rig.showTileOnTheDramaBoard()
    }

    @MainActor func testRecorderEveryModeAndState() async throws {
        let rig = try RenderRig()
        defer { rig.cleanup() }
        try await rig.recorderEveryModeAndState()
    }
}

private final class RenderRig {
    private var out: URL
    private var script: PlayScript
    private var store: ProductionStore
    private var env: (app: AppStore, plays: PlaysLibrary)

    init() throws {
        guard let path = ProcessInfo.processInfo.environment["GRAMMAR_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("GRAMMAR_RENDER_DIR is not set")
        }
        let out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        CTFontManagerRegisterFontsForURL(repo.appending(path: "apple/Resources/Fonts/BigShoulders-Bold.ttf") as CFURL, .process, nil)
        let library = try JSONDecoder().decode(CastableLibrary.self,
                                               from: Data(contentsOf: repo.appending(path: "catalog/plays/castable-scripts.json")))
        self.out = out
        script = try XCTUnwrap(library.scripts.first { $0.id == "gut-28051" })
        let made = ProductionStore(root: FileManager.default.temporaryDirectory.appending(path: "render-\(UUID().uuidString)"))
        store = made
        env = (AppStore(), PlaysLibrary(store: made))
    }

    func cleanup() { try? FileManager.default.removeItem(at: store.root) }

    // MARK: Drawing

    private func render<V: View>(_ name: String, width: CGFloat, height: CGFloat, dark: Bool, @ViewBuilder _ content: () -> V) throws {
        let view = content()
            .environment(env.app)
            .environment(env.plays)
            .tint(Color.brandSecondary)
            .frame(width: width, height: height, alignment: .top)
            .background(Color.brandBackground)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "\(name) did not render")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: out.appending(path: "\(name)-\(Int(width))\(dark ? "-dark" : "").png"))
    }

    private func both<V: View>(_ name: String, widths: [(CGFloat, CGFloat)], @ViewBuilder _ content: () -> V) throws {
        for (width, height) in widths {
            for dark in [false, true] { try render(name, width: width, height: height, dark: dark, content) }
        }
    }

    private let phone: (CGFloat, CGFloat) = (390, 844)
    private let wideMac: (CGFloat, CGFloat) = (1100, 760)

    // MARK: Fixtures

    private func tone(_ seconds: Double, amplitude: Float = 0.2) -> [Float] {
        (0..<Int(seconds * 48_000)).map { i in
            amplitude * Float(sin(2 * .pi * 180 * Double(i) / 48_000)) * (0.4 + 0.6 * Float(abs(sin(Double(i) / 4_000))))
        }
    }

    /// The cast of Caesar Rodney's Ride as the picture shows it: URIAH and FRANKLIN recorded, RODNEY
    /// being recorded by Lou with his first four lines kept.
    private func production() throws -> Production {
        var p = try store.create(script)
        for (name, performer) in [("URIAH", "Pat"), ("FRANKLIN", "Ada")] {
            let part = PartID.role(name)
            p = try Relay.take(part, performer: performer, in: p, script: script)
            for line in script.lines(for: part) { p.add(fakeTake(line, part)) }
            p = try Relay.finish(part, in: p, script: script)
        }
        p = try Relay.take(.role("RODNEY"), performer: "Lou", in: p, script: script)
        for line in script.lines(for: .role("RODNEY")).prefix(4) { p.add(fakeTake(line, .role("RODNEY"))) }
        try store.save(p)
        return p
    }

    private func fakeTake(_ line: ScriptLine, _ part: PartID) -> Take {
        Take(id: "t-\(line.id)", lineID: line.id, part: part, file: "\(line.id).flac", created: .now, frames: 148_000,
             sampleRate: 48_000, capture: .direct, heard: [:], loudness: -18, peak: 0.4, bleed: false)
    }

    private func session(audio: RenderAudio, mode: RecordingSession.Mode, line: Int) async throws -> (RecordingSession, Int) {
        let p = try production()
        let s = RecordingSession(production: p, script: script, part: .role("RODNEY"), store: store, audio: audio,
                                 voice: RenderVoice(), sleep: { _ in }, announce: {})
        await s.begin(echoCancelled: false)
        s.setMode(mode)
        return (s, line)
    }

    private func wait(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<2_000 where !condition() { await Task.yield() }
    }

    private func recorder(_ s: RecordingSession, at index: Int) -> some View {
        RecorderView(session: s, index: .constant(index), showsDone: true, refusal: nil, finish: {})
            .environment(\.recorderScrolls, false)
            .padding(.top, 8)
    }

    // MARK: The play page and the cast sheet

    func playPageAndCastSheet() throws {
        let script = self.script
        try both("play-page", widths: [phone, (900, 1500)]) { PlayPageBody(script: script) }
        let p = try production()
        try both("cast-sheet", widths: [(390, 1560), (900, 1200)]) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                HeadBoard(kicker: "Ear drama", name: script.title, genre: PlayScript.boardGenre, art: nil, first: nil,
                          last: nil, facts: PlayHead.facts(script), credits: script.authorLineWithYears, castScript: script)
                ActionRow {
                    Button { } label: { Label("Listen through", systemImage: "play.fill") }.pageAction(primary: true)
                }
                PartGrid {
                    ForEach(script.castParts) { part in
                        LocalPartCard(production: p, script: script, part: part, open: {}, take: {}, leaveSilent: {}, reopen: {})
                    }
                }
            }
            .padding(Spacing.s4)
            .modifier(ReadableColumn())
        }
    }

    func showTileOnTheDramaBoard() throws {
        let row = SeriesRow(key: script.id, name: script.title, genre: PlayScript.boardGenre, firstDate: nil, lastDate: nil,
                            networks: [], episodeCount: 0)
        try both("play-tile", widths: [(390, 300)]) {
            HStack(alignment: .top) {
                ShowTile(series: row, width: 170, facts: [script.authorLine, "12 parts"], castScript: script)
                ScriptRow(script: script).frame(width: 190)
            }
            .padding()
        }
    }

    // MARK: The recorder

    /// Drives one session to a state, draws it at both widths in both schemes, and ends it. A state
    /// that waits (a cue playing, the microphone open) is left suspended while it is drawn.
    private func capture(_ name: String, mode: RecordingSession.Mode, hold: Bool = false,
                         mic: RenderAudio.Mic = .speaks, waits: Bool = false,
                         drive: (@MainActor (RecordingSession) async -> Void)? = nil,
                         until: (@MainActor (RecordingSession, RenderAudio) -> Bool)? = nil) async throws {
        let audio = RenderAudio()
        audio.hold = hold
        audio.mic = mic
        let (s, at) = try await session(audio: audio, mode: mode, line: 4)
        var task: Task<Void, Never>?
        if let drive {
            if waits {
                task = Task { await drive(s) }
                await wait(until?(s, audio) ?? true)
            } else {
                await drive(s)
            }
        }
        try both(name, widths: [phone, wideMac]) { recorder(s, at: at) }
        s.end()
        audio.release()
        await task?.value
    }

    func recorderEveryModeAndState() async throws {
        let listening: @MainActor (RecordingSession, RenderAudio) -> Bool = { s, a in s.listeningSince != nil && !a.chunks.isEmpty }
        let cueing: @MainActor (RecordingSession, RenderAudio) -> Bool = { _, a in a.waiting }

        try await capture("rec-step-ready", mode: .step)
        try await capture("rec-step-armed", mode: .step, hold: true, waits: true,
                          drive: { await $0.record($0.lines[4].id) }, until: cueing)
        try await capture("rec-step-recording", mode: .step, mic: .holds, waits: true,
                          drive: { await $0.record($0.lines[4].id) }, until: listening)
        try await capture("rec-step-review", mode: .step, drive: {
            await $0.record($0.lines[4].id)
            await $0.record($0.lines[4].id)
        })
        try await capture("rec-run-ready", mode: .run)
        try await capture("rec-run-playing", mode: .run, hold: true, waits: true,
                          drive: { await $0.runThrough(from: $0.lines[4].id) }, until: cueing)
        try await capture("rec-run-recording", mode: .run, mic: .holds, waits: true,
                          drive: { await $0.runThrough(from: $0.lines[4].id) }, until: listening)
        try await capture("rec-run-review", mode: .run, drive: { await $0.runThrough(from: $0.lines[66].id) })
        try await capture("rec-lines", mode: .lines)
        try await capture("rec-lines-recording", mode: .lines, mic: .holds, waits: true,
                          drive: { await $0.record($0.lines[4].id) }, until: listening)
    }
}

// MARK: - Fakes: nothing plays and nothing records

private final class RenderAudio: LiveAudio {
    enum Mic { case speaks, holds }
    var mic = Mic.speaks
    var hold = false
    private(set) var waiting = false
    private(set) var chunks: [Int] = []
    private var captures = 0
    private var captured: [Float] = []
    private var gate: CheckedContinuation<Void, Never>?

    func outputRoute() -> AudioRoute { .headphones }
    func start(echoCancelled: Bool) throws {}
    func stop() { release() }
    func stopPlayback() { release() }

    func release() {
        let g = gate
        gate = nil
        g?.resume()
    }

    func play(_ cue: CueAudio) async {
        guard hold else { return }
        waiting = true
        await withCheckedContinuation { gate = $0 }
        waiting = false
    }

    func beginCapture(_ onChunk: @escaping @MainActor @Sendable ([Float]) -> Void) {
        captures += 1
        var signal: [Float]
        if captures == 1 {
            signal = (0..<48_000).map { _ in Float.random(in: -0.0005...0.0005) }
        } else {
            let voice = (0..<30_000).map { i -> Float in
                0.25 * Float(sin(2 * .pi * 170 * Double(i) / 48_000)) * (0.3 + 0.7 * Float(abs(sin(Double(i) / 2_500))))
            }
            signal = [Float](repeating: 0, count: 9_600) + voice
            if mic == .speaks { signal += [Float](repeating: 0, count: 60_000) }
        }
        captured = signal
        for start in stride(from: 0, to: signal.count, by: 960) {
            let chunk = Array(signal[start..<min(start + 960, signal.count)])
            chunks.append(chunk.count)
            onChunk(chunk)
        }
    }

    func endCapture() -> MicrophoneCapture {
        defer { captured = [] }
        return MicrophoneCapture(samples: captured, sampleRate: 48_000)
    }
}

private final class RenderVoice: StandInVoice {
    func render(_ text: String, part: PartID, rate: Float) async -> StandInAudio? {
        StandInAudio(samples: (0..<4_800).map { 0.1 * Float(sin(Double($0) / 12)) }, sampleRate: 48_000)
    }
}
