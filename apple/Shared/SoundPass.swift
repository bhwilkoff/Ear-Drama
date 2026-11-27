#if DEBUG && (os(iOS) || os(macOS))
import AVFoundation
import Foundation
#if os(iOS)
import MediaPlayer
import UIKit
#endif

/// APP_SOUND_PASS=1 (DEBUG only, never shipped): the B32 listening pass, aloud. Reads real sounds from
/// `<dir>/pack/*.wav` and outside-made voice files from `<dir>/voices/L000n.flac` (scratch fixtures only; the app never
/// stores a stand-in), builds a short two-voice scene with cues before, under and after lines and one bed, then plays
/// a live Listen Through with the cues, Hear It in Place for two cues, and an export rendered and played back, logging
/// Mountain-time stamps, and measures the export. APP_SOUND_PASS_STEPS picks from live,place,export,measure.
enum SoundPass {
    static let asked = ProcessInfo.processInfo.environment["APP_SOUND_PASS"] == "1"
    nonisolated(unsafe) private static var logURL: URL?

    static func stamp() -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/Denver")
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: .now)
    }

    static func log(_ s: String) {
        let line = "[SOUNDPASS \(stamp())] \(s)"
        print(line)
        guard let url = logURL, let data = (line + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    // MARK: The scene

    private static func say(_ id: String, _ role: String, _ text: String) -> ScriptLine {
        ScriptLine(id: id, kind: .speech, role: role, parts: [.say(text)])
    }

    static let script = PlayScript(
        id: "sound-pass", revision: "r1", kind: "radio", title: "Sound pass", authors: [],
        source: .init(name: "Fixture", url: "https://example.org"),
        rights: .init(bucket: "script_source_cleared", evidence: []),
        roles: [.init(name: "RODNEY", lines: 4, words: 30), .init(name: "URIAH", lines: 4, words: 30)],
        lines: [
            say("L0001", "URIAH", "We have got to make it, rain or no rain."),
            say("L0002", "RODNEY", "It is only sprinkling, Uriah. Keep your head down."),
            say("L0003", "URIAH", "I felt it. There is thunder close behind us."),
            say("L0004", "RODNEY", "I guess it is on us, then."),
            say("L0005", "URIAH", "Here, draw up your horse! Whoa, boy!"),
            ScriptLine(id: "L0006", kind: .direction, source: "They ride off."),
            say("L0007", "RODNEY", "Giddap! The vote is waiting in Philadelphia."),
            say("L0008", "URIAH", "Then ride!"),
        ])

    struct Built { var production: Production; var sources: SoundSources; var own: OwnSoundStore }

    @MainActor
    static func build(dir: URL, withTakes: Bool) throws -> Built {
        let own = OwnSoundStore(root: URL.temporaryDirectory.appending(path: "SoundPassOwn-\(UUID().uuidString.prefix(6))"))
        var ids: [String: OwnSound] = [:]
        let packDir = dir.appending(path: "pack")
        for f in (try FileManager.default.contentsOfDirectory(atPath: packDir.path)).sorted() where f.hasSuffix(".wav") {
            let s = try own.bring(packDir.appending(path: f))
            ids[String(f.dropLast(4))] = s
        }
        var p = Production(script: script)
        func put(_ line: String, _ name: String, at: String, kind: String = "effect", _ patch: SoundBoard.Patch = .init()) {
            guard let s = ids[name] else { return log("missing sound \(name)") }
            let slot = SoundBoard.addSlot(p, line: line)
            p = slot.production
            let added = SoundBoard.addSound(p, script, slotID: slot.id, src: .own(s.id, name: s.name), kind: kind)
            p = added.production
            guard let sid = added.id else { return }
            var patch = patch
            patch.at = at
            p = SoundBoard.updateSound(p, slotID: slot.id, soundID: sid, patch)
        }
        put("L0001", "piano-bed", at: "bed", kind: "music", .init(gainDb: -3, fadeInMs: 2000, fadeOutMs: 3000, loop: true, until: "L0007"))
        put("L0002", "wood-knock", at: "before")
        put("L0003", "thunder-rain", at: "under", .init(gainDb: -3, fadeOutMs: 1500))
        put("L0004", "rain-bed", at: "under", .init(gainDb: -9, fadeInMs: 800, fadeOutMs: 1500, loop: true))
        put("L0005", "horse-trot", at: "under", .init(gainDb: -6, fadeOutMs: 800))
        put("L0006", "footstep-a", at: "before")
        put("L0008", "door-creak", at: "after", .init(gainDb: -3))
        if withTakes {
            for l in script.lines where l.kind == .speech {
                let file = "\(l.id).flac"
                let read = try TakeAudio.read(dir.appending(path: "voices").appending(path: file))
                let t = Take(id: "t-\(l.id)", lineID: l.id, part: .role(l.role ?? "X"), file: file, created: .now,
                             frames: read.samples.count, sampleRate: read.sampleRate, capture: .direct, heard: [:],
                             loudness: BS1770.integratedLoudness(read.samples, sampleRate: read.sampleRate),
                             peak: BS1770.samplePeak(read.samples), bleed: false)
                p.add(t)
            }
        }
        let pack = SoundPackStore(manifestURL: nil, root: URL.temporaryDirectory.appending(path: "SoundPassPack"))
        return Built(production: p, sources: SoundSources(own: own, pack: pack), own: own)
    }

    // MARK: Entry

    @MainActor
    static func run() async {
        let env = ProcessInfo.processInfo.environment
        let dir = env["APP_SOUND_PASS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? URL.cachesDirectory.appending(path: "soundpass")
        logURL = dir.appending(path: "pass.log")
        try? FileManager.default.removeItem(at: logURL!)
        let steps = Set((env["APP_SOUND_PASS_STEPS"] ?? "live,place,export,measure").split(separator: ",").map(String.init))
        log("start steps=\(steps.sorted()) dir=\(dir.path) volume=\(SpeechMute.volume)")
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let other = session.isOtherAudioPlaying
        log("outputVolume=\(session.outputVolume) otherAudioPlaying=\(other) route=\(session.currentRoute.outputs.map(\.portType.rawValue))")
        if other, env["APP_SOUND_PASS_FORCE"] != "1" { return log("other audio is playing: stopped") }
        let before = session.outputVolume
        let want = env["APP_SOUND_PASS_VOLUME"].flatMap(Float.init)
        let back = env["APP_SOUND_PASS_RESTORE"].flatMap(Float.init) ?? before
        if let want, abs(before - want) > 0.01 {
            await setVolume(want)
            log("volume set \(before) -> \(session.outputVolume)")
        }
        defer { if want != nil { Task { @MainActor in await setVolume(back); log("volume restored to \(back), now \(session.outputVolume)") } } }
        if steps.isEmpty || steps == ["none"] { return }
        #endif
        do {
            if steps.contains("live") || steps.contains("place") {
                let live = try build(dir: dir, withTakes: false)
                let plan = Relay.listenPlan(live.production, script)
                let cues = ListenCues(entries: SoundBoard.listenCues(script, live.production, plan: plan),
                                      url: { live.sources.url($0) }, player: SystemCuePlayer())
                if steps.contains("live") {
                    let speaker = PassSpeaker()
                    let listen = LiveListenThrough(speaker: speaker, player: SystemTakePlayer())
                    log("LIVE listen-through with cues BEGIN")
                    await listen.run(plan, takeURL: { _ in dir }, cues: cues)
                    log("LIVE listen-through END")
                    speaker.report()
                }
                if steps.contains("place") {
                    try? await Task.sleep(for: .seconds(2))
                    for line in ["L0003", "L0002"] {
                        guard let range = SoundBoard.inPlace(script, plan: plan, line: line) else { continue }
                        let listen = LiveListenThrough(speaker: PassSpeaker(), player: SystemTakePlayer())
                        log("PLACE hear-it-in-place at \(line) BEGIN range=\(range)")
                        await listen.run(plan, takeURL: { _ in dir }, cues: cues, range: range)
                        log("PLACE at \(line) END")
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                }
            }
            if steps.contains("export") || steps.contains("measure") {
                let built = try build(dir: dir, withTakes: true)
                let timeline = try MixTimeline.build(script: script, production: built.production,
                                                      resolveSound: built.sources.resolver)
                let out = dir.appending(path: "mix.m4a")
                log("EXPORT render BEGIN frames=\(timeline.totalFrames) sounds=\(timeline.sounds.count)")
                let sources = built.sources
                try MixRenderer.render(timeline, takesFolder: dir.appending(path: "voices"), to: out,
                                       loadSound: { try sources.samples($0) })
                log("EXPORT render END \(out.lastPathComponent)")
                if steps.contains("measure") {
                    SoundPassMeasure.report(timeline: timeline, takes: dir.appending(path: "voices"), sources: sources, mix: out)
                }
                if steps.contains("export") {
                    try? await Task.sleep(for: .seconds(1))
                    #if os(iOS)
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                    try? AVAudioSession.sharedInstance().setActive(true)
                    #endif
                    log("EXPORT playback BEGIN")
                    await playOut(out)
                    log("EXPORT playback END")
                }
            }
        } catch {
            log("FAILED \(error)")
        }
        log("done")
    }

    #if os(iOS)
    @MainActor
    static func setVolume(_ v: Float) async {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first else {
            return log("no window for the volume view")
        }
        let view = MPVolumeView(frame: CGRect(x: 20, y: 120, width: 240, height: 44))
        view.alpha = 0.02
        window.addSubview(view)
        try? await Task.sleep(for: .milliseconds(1200))
        let slider = view.subviews.compactMap { $0 as? UISlider }.first
        log("volume view: slider=\(slider != nil) windows=\(window.windowScene?.activationState.rawValue ?? -1)")
        slider?.value = v
        slider?.sendActions(for: .valueChanged)
        try? await Task.sleep(for: .milliseconds(1200))
        view.removeFromSuperview()
    }
    #endif

    @MainActor
    static func playOut(_ url: URL) async {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return log("cannot open mix") }
        player.prepareToPlay()
        player.play()
        while player.isPlaying { try? await Task.sleep(for: .milliseconds(200)) }
    }
}

/// Two system voices, one per role, each line's start and end stamped.
final class PassSpeaker: NSObject, ListenSpeaker, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var done: CheckedContinuation<Void, Never>?
    private var marks: [(text: String, start: Date, end: Date)] = []
    private var begun = Date()
    private let voices: [AVSpeechSynthesisVoice]

    override init() {
        let en = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        voices = en.sorted { $0.quality.rawValue > $1.quality.rawValue }
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, part: PartID, personalVoice: Bool) async {
        let u = AVSpeechUtterance(string: text)
        let i = part == .role("RODNEY") ? 0 : min(1, max(0, voices.count - 1))
        if i < voices.count { u.voice = voices[i] }
        u.volume = SpeechMute.volume
        begun = .now
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            done = c
            synth.speak(u)
        }
        marks.append((text, begun, .now))
        SoundPass.log("voice \(part) \"\(text.prefix(24))\" \(String(format: "%.2f", Date().timeIntervalSince(begun))) s")
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        let c = done; done = nil; c?.resume()
    }

    func report() {
        for (a, b) in zip(marks, marks.dropFirst()) {
            SoundPass.log(String(format: "gap after \"%@\": %.0f ms", String(a.text.prefix(20)), b.start.timeIntervalSince(a.end) * 1000))
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in let c = self.done; self.done = nil; c?.resume() }
    }
}
#endif
