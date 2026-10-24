import AVFoundation
import Foundation
import Testing

// Plays phase 1 (docs/PLAYS-DESIGN.md) on fixtures: the relay order, that no
// synthesized audio ever reaches a file, take replacement, and the mix's
// timeline. Nothing here plays or records sound: the live audio is a fake.
//
// Broken controls, 2026-10-22, each against a mutated copy of Core/Plays:
//   Relay.take without the "another part is recording" guard: relay test fails.
//   Production.add appending without moving `chosen`: take-replacement test fails.
//   MixTimeline.build without the gap: timeline test fails.
// Broken control, 2026-10-23: Production.usableTake ignoring `bleed` fails the
//   flagged-take test (the play reads complete and mixes the device voice).
//   RecordingSession keeping the whole capture as the take (no window): the
//   stand-in test fails on the take length.
//   RecordingSession writing the cue's stand-in as the take: the stand-in test
//   fails (the scan finds it in every take and in the mix).
// Broken control, 2026-10-24: SyntheticAudio.refuse made a no-op: the take,
//   room-tone, mix, and export guard tests fail (9 issues), each writer
//   having written the stand-in's samples.
// The stand-in scan carries its own control (`leakyCaptureIsCaught`): when the
// microphone hears the stand-in, the scan must find it in the take.

// MARK: - Fixtures

private func line(_ id: String, _ role: String?, _ kind: ScriptLine.Kind = .speech, _ text: String = "words")
    -> ScriptLine {
    kind == .speech
        ? ScriptLine(id: id, kind: .speech, role: role, parts: [.say(text)])
        : ScriptLine(id: id, kind: kind, source: text)
}

/// MOLLY 5 lines, FIBBER 3, DOC 1, one sound cue, one direction.
private func fixtureScript() -> PlayScript {
    let lines = [
        line("L0001", nil, .direction, "(A kitchen.)"),
        line("L0002", "FIBBER", .speech, "Well, Molly."),
        line("L0003", "MOLLY", .speech, "Yes, dearie?"),
        line("L0004", nil, .sound, "SOUND: DOOR OPENS"),
        line("L0005", "DOC", .speech, "Anybody home?"),
        line("L0006", "MOLLY", .speech, "Come in."),
        line("L0007", "MOLLY", .speech, "Sit down."),
        line("L0008", "FIBBER", .speech, "Doc!"),
        line("L0009", "MOLLY", .speech, "Tea?"),
        line("L0010", "FIBBER", .speech, "Not for me."),
        line("L0011", "MOLLY", .speech, "Good night."),
    ]
    let roles = ["MOLLY", "FIBBER", "DOC"].map { name in
        PlayScript.Role(name: name, lines: lines.filter { $0.role == name }.count, words: 2)
    }
    return PlayScript(id: "gut-0", revision: "r1", kind: "radio", title: "Good Grammar", authors: [],
                      source: .init(name: "Fixture", url: "https://example.org"),
                      rights: .init(bucket: "script_source_cleared", evidence: []), roles: roles, lines: lines)
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "plays-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private func tone(_ hz: [Double], seconds: Double, amplitude: Float = 0.3, rate: Double = 48_000) -> [Float] {
    (0..<Int(seconds * rate)).map { i in
        let t = Double(i) / rate
        return amplitude * Float(hz.map { sin(2 * .pi * $0 * t) }.reduce(0, +) / Double(hz.count))
    }
}

private func take(_ id: String, line: String, part: PartID, frames: Int, loudness: Double? = -16,
                  peak: Float = 0.5, bleed: Bool = false) -> Take {
    Take(id: id, lineID: line, part: part, file: "\(id).flac", created: .now, frames: frames, sampleRate: 48_000,
         capture: .direct, heard: [:], loudness: loudness, peak: peak, bleed: bleed)
}

/// Every speaking line of the fixture given one take of `frames`.
private func completeProduction(_ script: PlayScript, frames: Int = 4_800) -> Production {
    var p = Production(script: script)
    for l in script.lines where l.kind == .speech {
        p.add(take("t-\(l.id)", line: l.id, part: l.part, frames: frames))
    }
    return p
}

// MARK: - Relay order

struct RelayTests {
    @Test func anyOpenPartCanBeTakenOneAtATimeTheLargestSuggested() throws {
        let script = fixtureScript()
        #expect(Relay.order(script) == [.role("MOLLY"), .role("FIBBER"), .role("DOC"), .sound, .directions])
        var p = Production(script: script)
        #expect(Relay.next(p, script) == .role("MOLLY"), "the largest open part is suggested")

        let doc = try Relay.take(.role("DOC"), performer: nil, in: p, script: script)
        #expect(doc.state(of: .role("DOC")).status == .recording, "any open part, in any order (C7)")
        #expect(throws: Relay.Refusal.anotherPartIsRecording(.role("DOC"))) {
            try Relay.take(.role("MOLLY"), performer: nil, in: doc, script: script)
        }
        let silent = try Relay.leaveSilent(.directions, in: p, script: script)
        #expect(silent.state(of: .directions).status == .silent, "any open non-speaking part may be left silent")
        #expect(throws: Relay.Refusal.notOpen) {
            try Relay.take(.directions, performer: nil, in: silent, script: script)
        }
        #expect(throws: Relay.Refusal.notOpen) {
            try Relay.reopen(.role("MOLLY"), in: p, script: script)
        }
        p = try Relay.take(.role("MOLLY"), performer: "  Ada ", in: p, script: script)
        #expect(p.state(of: .role("MOLLY")) == PartState(status: .recording, performer: "Ada"))
        #expect(Relay.next(p, script) == nil, "nothing is offered while a part records")
        #expect(throws: Relay.Refusal.anotherPartIsRecording(.role("MOLLY"))) {
            try Relay.take(.role("FIBBER"), performer: nil, in: p, script: script)
        }

        let molly = script.lines(for: .role("MOLLY")).map(\.id)
        #expect(throws: Relay.Refusal.linesMissing(molly)) {
            try Relay.finish(.role("MOLLY"), in: p, script: script)
        }
        for id in molly { p.add(take("t-\(id)", line: id, part: .role("MOLLY"), frames: 100)) }
        p = try Relay.finish(.role("MOLLY"), in: p, script: script)
        #expect(Relay.next(p, script) == .role("FIBBER"), "the device passes to the next largest part")

        #expect(throws: Relay.Refusal.speakingPartCannotBeSilent) {
            try Relay.leaveSilent(.role("FIBBER"), in: p, script: script)
        }
        for part in [PartID.role("FIBBER"), .role("DOC")] {
            p = try Relay.take(part, performer: nil, in: p, script: script)
            for l in script.lines(for: part) { p.add(take("t-\(l.id)", line: l.id, part: part, frames: 100)) }
            p = try Relay.finish(part, in: p, script: script)
        }
        #expect(Relay.isComplete(p, script), "every speaking line has a human take")
        #expect(Relay.next(p, script) == .sound)
        p = try Relay.leaveSilent(.sound, in: p, script: script)
        #expect(Relay.next(p, script) == .directions)

        p = try Relay.reopen(.role("DOC"), in: p, script: script)
        #expect(Relay.current(p, script) == .role("DOC"))
        #expect(throws: Relay.Refusal.anotherPartIsRecording(.role("DOC"))) {
            try Relay.reopen(.role("MOLLY"), in: p, script: script)
        }
    }

    @Test func theCueIsTheLineBeforeWhenSomeoneElseSpeaksIt() {
        let script = fixtureScript()
        #expect(Relay.cueLines(before: "L0003", in: script, runUp: false).map(\.id) == ["L0002"])
        #expect(Relay.cueLines(before: "L0007", in: script, runUp: false).isEmpty, "my own line before: no cue")
        #expect(Relay.cueLines(before: "L0006", in: script, runUp: false).map(\.id) == ["L0005"],
                "the sound cue between is not voiced")
        #expect(Relay.cueLines(before: "L0007", in: script, runUp: true).map(\.id) == ["L0005", "L0006"])
        #expect(Relay.cueLines(before: "L0002", in: script, runUp: true).isEmpty, "the first speech has no cue")
    }
}

// MARK: - Takes

struct TakeReplacementTests {
    @Test func aRetakeIsChosenAndTheOldTakeStaysUntilDiscarded() throws {
        let script = fixtureScript()
        let store = ProductionStore(root: temporaryRoot())
        defer { try? FileManager.default.removeItem(at: store.root) }
        var p = try store.create(script)
        let capture = MicrophoneCapture(samples: tone([200], seconds: 0.2), sampleRate: 48_000)

        let first = try store.writeTake(capture, production: p, lineID: "L0003")
        let second = try store.writeTake(capture, production: p, lineID: "L0003")
        #expect(first != second, "a take file is never overwritten")

        let a = Take(id: "a", lineID: "L0003", part: .role("MOLLY"), file: first, created: .now, frames: 9_600,
                     sampleRate: 48_000, capture: .direct, heard: ["L0002": Take.standIn], loudness: -20, peak: 0.3,
                     bleed: false)
        let b = Take(id: "b", lineID: "L0003", part: .role("MOLLY"), file: second, created: .now, frames: 9_600,
                     sampleRate: 48_000, capture: .direct, heard: ["L0002": Take.standIn], loudness: -20, peak: 0.3,
                     bleed: false)
        p.add(a)
        p.add(b)
        #expect(p.chosen["L0003"] == "b", "the re-take becomes the line's take")
        #expect(p.takes(for: "L0003").map(\.id) == ["a", "b"], "choosing never deletes the old take")
        p.choose("a")
        #expect(p.chosenTake(for: "L0003")?.id == "a")
        try store.save(p)

        try store.discardUnusedTakes(p.id)
        let kept = try #require(store.production(p.id))
        #expect(kept.takes.map(\.id) == ["a"])
        let files = try FileManager.default.contentsOfDirectory(atPath: store.takesFolder(p.id).path)
        #expect(files == [first], "only the unused take's file is removed")

        // The record survives a reload from disk.
        let reloaded = ProductionStore(root: store.root)
        #expect(reloaded.production(p.id) == kept)
        #expect(reloaded.script(for: kept)?.lines.count == script.lines.count, "the script as cast is stored")

        try reloaded.delete(p.id)
        #expect(!FileManager.default.fileExists(atPath: reloaded.folder(p.id).path), "delete removes the folder")
        #expect(reloaded.productions.isEmpty)
    }

    @Test func aTakeIsTheLineWindowOnly() {
        let rate = 48_000.0
        let capture = [Float](repeating: 0, count: 48_000) + tone([180], seconds: 0.5) + [Float](repeating: 0, count: 72_000)
        var detector = LineEndDetector(sampleRate: rate, roomToneRMS: 0.0005)
        var events: [LineEndDetector.Event] = []
        for start in stride(from: 0, to: capture.count, by: 960) {
            if let e = detector.feed(Array(capture[start..<min(start + 960, capture.count)])) { events.append(e) }
        }
        #expect(events.count == 2)
        let window = LineEndDetector.window(onset: detector.onset, end: detector.end, total: capture.count,
                                            sampleRate: rate)
        #expect(abs(window.lowerBound - 36_000) <= 960, "onset less 250 ms")
        #expect(abs(window.upperBound - 84_000) <= 960, "end plus 250 ms")
    }
}

// MARK: - The mix's timeline

struct MixTimelineTests {
    @Test func linesFollowInScriptOrderWithAGapAndARetakeRipples() throws {
        let script = fixtureScript()
        var p = completeProduction(script, frames: 4_800)
        let gap = Int(MixTimeline.defaultGap * 48_000)
        let timeline = try MixTimeline.build(script: script, production: p)
        #expect(timeline.placements.map(\.lineID) == script.speechLineIDs, "silent cues are left out")
        #expect(timeline.placements.map(\.start) == (0..<9).map { $0 * (4_800 + gap) })
        #expect(timeline.totalFrames == 9 * 4_800 + 8 * gap)

        p.add(take("long", line: "L0003", part: .role("MOLLY"), frames: 4_800 + 24_000))
        let rippled = try MixTimeline.build(script: script, production: p)
        #expect(rippled.placements[0].start == 0)
        #expect(rippled.placements[1].takeID == "long")
        #expect(zip(timeline.placements.dropFirst(2), rippled.placements.dropFirst(2)).allSatisfy {
            $1.start - $0.start == 24_000
        }, "a longer re-take moves every later line")

        p.add(take("door", line: "L0004", part: .sound, frames: 1_000))
        let withSound = try MixTimeline.build(script: script, production: p)
        #expect(withSound.placements.map(\.lineID).contains("L0004"), "a recorded sound cue is placed")
    }

    @Test func aPartialPlayHasNoTimeline() {
        let script = fixtureScript()
        var p = completeProduction(script)
        p.chosen["L0005"] = nil
        #expect(throws: MixTimeline.Failure.incomplete(missing: ["L0005"])) {
            try MixTimeline.build(script: script, production: p)
        }
    }

    @Test func theGainReachesMinus16HeldUnderTheCeiling() {
        #expect(abs(MixTimeline.gain(loudness: -26, peak: 0.1) - Float(pow(10, 10.0 / 20))) < 1e-4)
        let clamped = MixTimeline.gain(loudness: -26, peak: 0.5)
        #expect(abs(20 * log10(Double(clamped * 0.5)) - -1) < 1e-3, "the peak lands at -1 dBFS")
        #expect(MixTimeline.gain(loudness: nil, peak: 0.5) == 1)
    }

    @Test func theRenderPutsEachTakeWhereTheTimelineSays() throws {
        let script = fixtureScript()
        let store = ProductionStore(root: temporaryRoot())
        defer { try? FileManager.default.removeItem(at: store.root) }
        var p = try store.create(script)
        let samples = tone([440], seconds: 0.3)
        for l in script.lines where l.kind == .speech {
            let file = try store.writeTake(MicrophoneCapture(samples: samples, sampleRate: 48_000), production: p,
                                           lineID: l.id)
            p.add(Take(id: "t-\(l.id)", lineID: l.id, part: l.part, file: file, created: .now, frames: samples.count,
                       sampleRate: 48_000, capture: .direct, heard: [:],
                       loudness: BS1770.integratedLoudness(samples, sampleRate: 48_000),
                       peak: BS1770.samplePeak(samples), bleed: false))
        }
        try store.save(p)
        let timeline = try MixTimeline.build(script: script, production: p)
        let url = store.mixURL(p.id)
        try MixRenderer.render(timeline, takesFolder: store.takesFolder(p.id), to: url)

        let mix = try TakeAudio.read(url).samples
        #expect(abs(mix.count - timeline.totalFrames) < 4_096, "the mix is as long as its timeline")
        func rms(_ center: Int) -> Float {
            LineEndDetector.rms(Array(mix[max(0, center - 2_400)..<min(mix.count, center + 2_400)]))
        }
        for (i, placement) in timeline.placements.enumerated() {
            #expect(rms(placement.start + placement.frames / 2) > 0.05, "take \(i) sounds where it is placed")
            if i + 1 < timeline.placements.count {
                let gapCenter = (placement.start + placement.frames + timeline.placements[i + 1].start) / 2
                #expect(rms(gapCenter) < 0.01, "the gap after take \(i) is quiet")
            }
        }
    }
}

// MARK: - A flagged take never reaches the mix

/// §5 rule 2 and §8 rule 3: a take the bleed check flags is kept on disk, but the
/// line still needs a re-take, and the mix refuses it.
struct FlaggedTakeTests {
    @Test func aFlaggedTakeLeavesItsLineToReTakeAndTheMixRefusesIt() throws {
        let script = fixtureScript()
        var p = completeProduction(script)
        p.takes.removeAll { $0.lineID == "L0005" }
        p.chosen["L0005"] = nil
        p.add(take("leaky", line: "L0005", part: .role("DOC"), frames: 4_800, bleed: true))
        #expect(p.chosen["L0005"] == "leaky", "the flagged take is kept and chosen")
        #expect(!Relay.isComplete(p, script), "a flagged take does not complete its line")
        #expect(Relay.missingSpeech(p, script) == ["L0005"])
        #expect(Relay.needsRetake(p, script) == ["L0005"])
        #expect(Relay.missingLines(.role("DOC"), in: p, script: script) == ["L0005"])
        #expect(throws: MixTimeline.Failure.incomplete(missing: ["L0005"])) {
            try MixTimeline.build(script: script, production: p)
        }

        let good = try MixTimeline.build(script: script, production: completeProduction(script))
        var placements = good.placements
        let first = placements[0]
        placements[0] = MixTimeline.Placement(lineID: first.lineID, takeID: "leaky", file: first.file,
                                              start: first.start, inFrame: first.inFrame,
                                              outFrame: first.outFrame, gain: first.gain, bleed: true)
        let leaky = MixTimeline(sampleRate: good.sampleRate, placements: placements, totalFrames: good.totalFrames)
        let folder = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "mix.m4a")
        #expect(throws: MixRenderer.Failure.self) {
            try MixRenderer.render(leaky, takesFolder: folder, to: url)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path), "nothing is written")

        p.add(take("clean", line: "L0005", part: .role("DOC"), frames: 4_800))
        #expect(Relay.isComplete(p, script), "a later unflagged take completes the line")
        #expect(p.takes(for: "L0005").map(\.id) == ["leaky", "clean"], "the flagged take stays on disk")
        let timeline = try MixTimeline.build(script: script, production: p)
        #expect(timeline.placements.first { $0.lineID == "L0005" }?.takeID == "clean")
        let flaggedPlaced = timeline.placements.filter(\.bleed)
        #expect(flaggedPlaced.isEmpty)

        p.add(take("door", line: "L0004", part: .sound, frames: 1_000, bleed: true))
        #expect(!Relay.isComplete(p, script), "a flagged sound cue is not mixed either")
        #expect(throws: MixTimeline.Failure.bleed(lines: ["L0004"])) {
            try MixTimeline.build(script: script, production: p)
        }
    }
}

// MARK: - No synthesized audio reaches a file

/// A stand-in whose every line is a chirp, so its signal can be looked for.
private final class SignatureVoice: StandInVoice {
    private(set) var rendered: [StandInAudio] = []

    func render(_ text: String, part: PartID, rate: Float) async -> StandInAudio? {
        let n = 24_000
        let f0 = 500.0 + Double(abs(text.hashValue % 300))
        let samples = (0..<n).map { i -> Float in
            let t = Double(i) / 48_000
            return 0.3 * Float(sin(2 * .pi * (f0 * t + 2_500 * t * t)))
        }
        let audio = StandInAudio(samples: samples, sampleRate: 48_000)
        rendered.append(audio)
        return audio
    }
}

/// Plays nothing and records nothing: the "microphone" is a performer signal
/// (or, when `leaky`, the last stand-in played, as a speaker would bleed it).
private final class FakeLiveAudio: LiveAudio {
    let leaky: Bool
    private var lastPlayed: [Float] = []
    private var captured: [Float] = []
    private var captures = 0
    private(set) var played: [CueAudio] = []

    init(leaky: Bool) { self.leaky = leaky }

    func outputRoute() -> AudioRoute { .headphones }
    func start(echoCancelled: Bool) throws {}
    func stop() {}

    func play(_ cue: CueAudio) async {
        played.append(cue)
        if case let .standIn(audio) = cue { lastPlayed = audio.samples }
    }

    func beginCapture(_ onChunk: @escaping @MainActor @Sendable ([Float]) -> Void) {
        captures += 1
        let signal: [Float]
        if captures == 1 {
            signal = (0..<48_000).map { _ in Float.random(in: -0.0005...0.0005) }  // room tone
        } else {
            let voice = leaky && !lastPlayed.isEmpty ? lastPlayed : tone([150, 175], seconds: 0.6)
            signal = [Float](repeating: 0, count: 9_600) + voice + [Float](repeating: 0, count: 60_000)
        }
        captured = signal
        for start in stride(from: 0, to: signal.count, by: 960) {
            onChunk(Array(signal[start..<min(start + 960, signal.count)]))
        }
    }

    func endCapture() -> MicrophoneCapture {
        defer { captured = [] }
        return MicrophoneCapture(samples: captured, sampleRate: 48_000)
    }
}

/// Every file a production folder holds that matches a stand-in that played,
/// plus any file of a kind §6 does not list.
private func standInFindings(in folder: URL, signatures: [StandInAudio]) throws -> [String] {
    var findings: [String] = []
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])!
    for case let url as URL in files {
        guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
        switch url.pathExtension {
        case "json": continue
        case "flac", "m4a":
            let audio = try TakeAudio.read(url)
            for signature in signatures
            where BleedCheck.score(signal: audio.samples, reference: signature.samples, sampleRate: audio.sampleRate)
                >= BleedCheck.threshold {
                findings.append(url.lastPathComponent)
            }
        default:
            findings.append("unexpected file \(url.lastPathComponent)")
        }
    }
    return findings
}

struct StandInNeverStoredTests {
    private func recordWholePlay(leaky: Bool) async throws -> (findings: [String], signatures: Int, takes: [Take]) {
        let script = fixtureScript()
        let store = ProductionStore(root: temporaryRoot())
        defer { try? FileManager.default.removeItem(at: store.root) }
        var production = try store.create(script)
        let voice = SignatureVoice()
        for part in Relay.order(script) where part.isSpeaking {
            production = try Relay.take(part, performer: nil, in: production, script: script)
            try store.save(production)
            let session = RecordingSession(production: production, script: script, part: part, store: store,
                                           audio: FakeLiveAudio(leaky: leaky), voice: voice,
                                           sleep: { _ in }, announce: {})
            await session.begin(echoCancelled: false)
            for l in session.lines { await session.record(l.id) }
            session.end()
            if leaky {
                let recorded = try #require(store.production(production.id))
                #expect(throws: Relay.Refusal.self, "a part whose takes are flagged is not done") {
                    try Relay.finish(part, in: recorded, script: script)
                }
                production = recorded
                break
            }
            production = try Relay.finish(part, in: try #require(store.production(production.id)), script: script)
            try store.save(production)
        }
        if leaky {
            #expect(!Relay.isComplete(production, script), "flagged takes leave the play unfinished")
        } else {
            #expect(Relay.isComplete(production, script))
            _ = try await store.renderMix(production.id)
            #expect(FileManager.default.fileExists(atPath: store.mixURL(production.id).path))
        }
        let findings = try standInFindings(in: store.folder(production.id), signatures: voice.rendered)
        return (findings, voice.rendered.count, try #require(store.production(production.id)).takes)
    }

    @Test func noFileHoldsAStandIn() async throws {
        let run = try await recordWholePlay(leaky: false)
        #expect(run.signatures > 0, "the first parts were cued by the device voice")
        #expect(run.findings.isEmpty, "no take, room tone, or mix holds a stand-in: \(run.findings)")
        #expect(run.takes.allSatisfy { !$0.bleed })
        #expect(run.takes.allSatisfy { $0.frames < 60_000 }, "a take is the line window, not the whole capture")
        #expect(run.takes.contains { $0.heard.values.contains(Take.standIn) })
        #expect(run.takes.contains { $0.heard.values.contains { $0 != Take.standIn } },
                "later parts heard the earlier performers' takes")
    }

    /// The control: if the microphone hears the stand-in, the scan finds it in
    /// the take, and the session's own bleed check flags the take.
    @Test func leakyCaptureIsCaught() async throws {
        let run = try await recordWholePlay(leaky: true)
        #expect(!run.findings.isEmpty, "the scan must catch a stand-in in a file")
        #expect(run.takes.contains { $0.bleed }, "the bleed check flags the take")
    }

    /// Only the take and mix writers may open an audio file for writing, and
    /// the stand-in source touches no file at all.
    @Test func onlyTheTakeAndMixWritersWriteAudio() throws {
        let apple = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: apple, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" && url.lastPathComponent != "PlaysTests.swift" {
            offenders += Self.writeViolations(file: url.lastPathComponent, source: try String(contentsOf: url, encoding: .utf8))
        }
        #expect(offenders.isEmpty, "\(offenders)")
        #expect(Self.writeViolations(file: "StandIn.swift", source: "let f = try AVAudioFile(forWriting: url)") ==
                ["StandIn.swift"], "the guard's control: a writer in the stand-in source is caught")
        #expect(Self.writeViolations(file: "Other.swift", source: "AVAudioFile(forWriting: u)") == ["Other.swift"])
    }

    private static let writers: Set = ["PlayFiles.swift", "MixRenderer.swift"]

    static func writeViolations(file: String, source: String) -> [String] {
        if source.contains("AVAudioFile(forWriting"), !writers.contains(file) { return [file] }
        if file == "StandIn.swift",
           ["AVAudioFile(", "FileManager", ".write(to", "Data("].contains(where: source.contains) { return [file] }
        return []
    }
}

// MARK: - Listen through, any time

private final class FakeSpeaker: ListenSpeaker {
    private(set) var spoken: [String] = []
    var onSpeak: (() -> Void)?
    func speak(_ text: String, part: PartID, personalVoice: Bool) async {
        spoken.append(text)
        onSpeak?()
    }
    func stop() {}
}

private final class FakeTakePlayer: ListenTakePlayer {
    private(set) var played: [URL] = []
    func play(_ url: URL) async { played.append(url) }
    func stop() {}
}

/// Any value inside `value` that is audio: samples, a buffer, a stand-in, data.
private func audioInside(_ value: Any) -> [String] {
    switch value {
    case is [Float], is Data, is StandInAudio, is MicrophoneCapture, is AVAudioBuffer:
        return [String(describing: type(of: value))]
    default:
        return Mirror(reflecting: value).children.flatMap { audioInside($0.value) }
    }
}

struct ListenPlanTests {
    @Test func thePlanIsTakesAndWordsInScriptOrder() {
        let script = fixtureScript()
        var p = Production(script: script)
        p.add(take("t3", line: "L0003", part: .role("MOLLY"), frames: 100))
        p.add(take("t4", line: "L0004", part: .sound, frames: 100))
        p.add(take("leaky", line: "L0005", part: .role("DOC"), frames: 100, bleed: true))
        let plan = Relay.listenPlan(p, script)
        #expect(plan.map(\.lineID) == ["L0002", "L0003", "L0004", "L0005", "L0006", "L0007", "L0008", "L0009",
                                       "L0010", "L0011"], "the unrecorded direction is skipped")
        #expect(plan[1] == .take(lineID: "L0003", part: .role("MOLLY"), take: p.take("t3")!))
        #expect(plan[2] == .take(lineID: "L0004", part: .sound, take: p.take("t4")!), "a recorded cue plays")
        #expect(plan[0] == .voice(lineID: "L0002", part: .role("FIBBER"), text: "Well, Molly."))
        #expect(plan[3] == .voice(lineID: "L0005", part: .role("DOC"), text: "Anybody home?"),
                "a flagged take is read live instead")
        #expect(audioInside(plan).isEmpty, "no plan entry holds audio: \(audioInside(plan))")
        #expect(audioInside([ListenEntry.voice(lineID: "x", part: .sound, text: "y")] as [Any]
            + [StandInAudio(samples: [0.1], sampleRate: 48_000)]) == ["StandInAudio"],
                "the scan's control: a stand-in is found")
        #expect(Relay.listenPlan(completeProduction(script), script).allSatisfy { !$0.isDeviceVoice })
    }

    @Test func aLiveListenThroughWritesNothingAndFinishesNothing() async throws {
        let script = fixtureScript()
        let store = ProductionStore(root: temporaryRoot())
        defer { try? FileManager.default.removeItem(at: store.root) }
        var p = try store.create(script)
        let file = try store.writeTake(MicrophoneCapture(samples: tone([200], seconds: 0.1), sampleRate: 48_000),
                                       production: p, lineID: "L0003")
        p.add(Take(id: "t3", lineID: "L0003", part: .role("MOLLY"), file: file, created: .now, frames: 4_800,
                   sampleRate: 48_000, capture: .direct, heard: [:], loudness: nil, peak: 0.3, bleed: false))
        try store.save(p)
        let before = try FileManager.default.subpathsOfDirectory(atPath: store.folder(p.id).path).sorted()
        let speaker = FakeSpeaker()
        let player = FakeTakePlayer()
        let live = LiveListenThrough(speaker: speaker, player: player)
        let recorded = p
        await live.run(Relay.listenPlan(recorded, script)) { store.takeURL(recorded, $0) }
        #expect(player.played == [store.takeURL(p, p.take("t3")!)])
        #expect(speaker.spoken.count == 8, "the other eight speeches are read live")
        #expect(!live.isRunning && live.current == nil)
        let after = try FileManager.default.subpathsOfDirectory(atPath: store.folder(p.id).path).sorted()
        #expect(after == before, "nothing is written")
        #expect(ProductionStore(root: store.root).production(p.id)?.listenedThrough == false)

        let stopping = FakeSpeaker()
        let stopped = LiveListenThrough(speaker: stopping, player: FakeTakePlayer())
        stopping.onSpeak = { stopped.stop() }
        await stopped.run(Relay.listenPlan(recorded, script)) { store.takeURL(recorded, $0) }
        #expect(stopping.spoken.count == 1, "Stop ends the listen-through")
    }
}

// MARK: - A synthetic buffer reaches no writer

/// §5 rule 3: every writer refuses samples a device voice made, even copied
/// out of `StandInAudio` into the types the writers accept.
struct SyntheticBufferGuardTests {
    private func standIn() -> StandInAudio {
        StandInAudio(samples: tone([330, 415], seconds: 0.3), sampleRate: 48_000)
    }

    @Test func theTakeAndRoomToneWritersRefuseIt() throws {
        let script = fixtureScript()
        let store = ProductionStore(root: temporaryRoot())
        defer { try? FileManager.default.removeItem(at: store.root) }
        let p = try store.create(script)
        let synthetic = standIn()
        let copied = MicrophoneCapture(samples: synthetic.samples, sampleRate: synthetic.sampleRate)
        #expect(throws: SyntheticAudio.Refusal.synthetic) { try store.writeTake(copied, production: p, lineID: "L0003") }
        #expect(throws: SyntheticAudio.Refusal.synthetic) { try store.writeRoomTone(copied, production: p) }
        let cut = copied.slice(0..<(copied.samples.count - 64))
        #expect(throws: SyntheticAudio.Refusal.synthetic, "a copy cut short is still known") {
            try store.writeTake(cut, production: p, lineID: "L0003")
        }
        #expect(throws: SyntheticAudio.Refusal.synthetic) {
            try TakeAudio.write(copied, to: store.takesFolder(p.id).appending(path: "direct.flac"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.takesFolder(p.id).path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.roomToneFolder(p.id).path).isEmpty)
        let human = MicrophoneCapture(samples: tone([331, 415], seconds: 0.3), sampleRate: 48_000)
        _ = try store.writeTake(human, production: p, lineID: "L0003")
    }

    /// A take file holding a stand-in's samples, written behind the writers'
    /// backs: the mix and the export still refuse it.
    @Test func theMixAndTheExportRefuseIt() async throws {
        let script = fixtureScript()
        let store = ProductionStore(root: temporaryRoot())
        defer { try? FileManager.default.removeItem(at: store.root) }
        var p = try store.create(script)
        let synthetic = standIn()
        let human = tone([220], seconds: 0.3)
        for l in script.lines where l.kind == .speech {
            let name = "\(l.id).wav"
            let samples = l.id == "L0005" ? synthetic.samples : human
            let file = try AVAudioFile(forWriting: store.takesFolder(p.id).appending(path: name),
                                       settings: TakeAudio.format.settings, commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            try file.write(from: try #require(TakeAudio.buffer(samples, format: TakeAudio.format)))
            file.close()
            p.add(Take(id: "t-\(l.id)", lineID: l.id, part: l.part, file: name, created: .now, frames: samples.count,
                       sampleRate: 48_000, capture: .direct, heard: [:], loudness: nil, peak: 0.3, bleed: false))
        }
        try store.save(p)
        let timeline = try MixTimeline.build(script: script, production: p)
        let url = store.mixURL(p.id)
        #expect(throws: SyntheticAudio.Refusal.synthetic) {
            try MixRenderer.render(timeline, takesFolder: store.takesFolder(p.id), to: url)
        }
        let id = p.id
        await #expect(throws: SyntheticAudio.Refusal.synthetic) { try await store.exportMix(id) }
        #expect(!FileManager.default.fileExists(atPath: url.path), "no mix is written")
        let humanOnly = MixTimeline(sampleRate: 48_000, placements: timeline.placements.filter { $0.lineID != "L0005" },
                                    totalFrames: timeline.totalFrames)
        try MixRenderer.render(humanOnly, takesFolder: store.takesFolder(p.id), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path), "the control: the human take files are mixed")
    }

    @Test func exportWaitsOnlyForACompletePlay() async throws {
        let script = fixtureScript()
        let store = ProductionStore(root: temporaryRoot())
        defer { try? FileManager.default.removeItem(at: store.root) }
        var p = try store.create(script)
        let samples = tone([440], seconds: 0.2)
        for l in script.lines where l.kind == .speech {
            let file = try store.writeTake(MicrophoneCapture(samples: samples, sampleRate: 48_000), production: p,
                                           lineID: l.id)
            p.add(Take(id: "t-\(l.id)", lineID: l.id, part: l.part, file: file, created: .now, frames: samples.count,
                       sampleRate: 48_000, capture: .direct, heard: [:], loudness: nil, peak: 0.3, bleed: false))
        }
        var partial = p
        partial.chosen["L0005"] = nil
        try store.save(partial)
        let id = p.id
        await #expect(throws: MixTimeline.Failure.incomplete(missing: ["L0005"])) { try await store.exportMix(id) }
        try store.save(p)
        #expect(!p.listenedThrough)
        let url = try await store.exportMix(id)
        #expect(FileManager.default.fileExists(atPath: url.path), "export renders the mix before any listen")
    }
}

struct PlayFactsTests {
    @Test func aPlayIsMarkedOnlyByItsRecordsFacts() {
        let base = fixtureScript()
        let script = PlayScript(id: base.id, revision: base.revision, kind: base.kind, title: base.title,
                                authors: [.init(name: "Carlton, Henry Fisk", born: 1893, died: 1973),
                                          .init(name: "Ann Other", born: nil, died: nil)],
                                year: 1931, source: base.source, rights: base.rights, roles: base.roles,
                                lines: base.lines)
        #expect(script.authorLineWithYears == "Henry Fisk Carlton (1893–1973), Ann Other")
        #expect(script.lengthLine == "3 parts · 11 lines")
        #expect(script.year == 1931)
        #expect(base.year == nil)
    }
}

// MARK: - Loudness and data

struct PlayLoudnessTests {
    @Test func aFullScaleSineReadsMinus3LUFS() throws {
        let full = tone([1_000], seconds: 3, amplitude: 1)
        let loud = try #require(BS1770.integratedLoudness(full, sampleRate: 48_000))
        #expect(abs(loud - -3.01) < 0.05)
        let quiet = try #require(BS1770.integratedLoudness(full.map { $0 * 0.1 }, sampleRate: 48_000))
        #expect(abs(quiet - -23.01) < 0.05)
        #expect(BS1770.integratedLoudness([Float](repeating: 0, count: 48_000), sampleRate: 48_000) == nil)
    }
}

struct CastableScriptsFileTests {
    @Test func theBundledFileDecodesAndEveryScriptCanBeCast() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "catalog/plays/castable-scripts.json")
        let library = try JSONDecoder().decode(CastableLibrary.self, from: Data(contentsOf: url))
        #expect(library.format == 1)
        #expect(!library.scripts.isEmpty)
        let castable: Set = ["script_gov_work", "script_pd_published_age", "script_registered_age",
                             "script_source_cleared", "script_registered_not_renewed", "script_author_died"]
        for script in library.scripts {
            #expect(castable.contains(script.rights.bucket), "\(script.id) is castable")
            #expect(script.castParts.filter { $0.id.isSpeaking }.count >= 2, "\(script.id) has parts")
            #expect(Set(script.lines.map(\.id)).count == script.lines.count, "\(script.id) line ids are unique")
        }
    }
}
