#if os(iOS) || os(macOS)
import AVFoundation
import Foundation
import SwiftUI

/// One performer recording one part (PLAYS-DESIGN §2.3-2.4) in one of the three
/// modes of owner ruling 4 (Run through, Line by line, Step), the mirror of
/// js/plays-session.js: five seconds of room tone, then for each line the cue before it (a human
/// take where one exists, the device voice live where not), then the device
/// listens until the performer stops. Only the microphone window is kept.
@Observable
final class RecordingSession {
    enum Phase: Equatable {
        case idle
        case roomTone(secondsLeft: Int)
        /// A cue line is playing; `deviceVoice` labels a stand-in on screen (§5 rule 3).
        case cue(lineID: String, deviceVoice: Bool)
        case listening(lineID: String)
        case review(lineID: String)
        /// A run through has ended: its takes wait for Keep or Discard.
        case runReview
        case failed(String)
    }

    /// The three recording modes (owner ruling 4, 2026-10-29); only what follows a take differs.
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case run, lines, step
        var id: String { rawValue }
        var title: String {
            switch self {
            case .run: "Run through"
            case .lines: "Line by line"
            case .step: "Step"
            }
        }

        static let key = "recorder.mode"

        /// The person's last mode on this device; Run through the first time.
        static func remembered(in defaults: UserDefaults = .standard) -> Mode {
            defaults.string(forKey: key).flatMap(Mode.init(rawValue:)) ?? .run
        }

        func remember(in defaults: UserDefaults = .standard) {
            defaults.set(rawValue, forKey: Self.key)
        }
    }

    /// The run on screen (Run through): the line it started at and what it took.
    struct Run: Equatable {
        let from: String
        var takes: [RunNote]
    }

    private(set) var phase: Phase = .idle
    private(set) var mode: Mode = .step
    private(set) var run: Run?
    /// The microphone's recent loudness (0...1), newest last, for the level meter while a line records.
    private(set) var levels: [Float] = []
    private(set) var listeningSince: Date?
    private(set) var production: Production
    let script: PlayScript
    let part: PartID
    /// The stand-in's speed, adjustable (§7).
    var standInRate: Float = 1
    private(set) var started = false
    private(set) var echoCancelled = false
    private(set) var lastTakeBleed = false

    @ObservationIgnored private let store: ProductionStore
    @ObservationIgnored private let audio: LiveAudio
    @ObservationIgnored private let voice: StandInVoice
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private let announce: () async -> Void
    @ObservationIgnored private var detector: LineEndDetector?
    @ObservationIgnored private var roomToneRMS: Float = 0
    @ObservationIgnored private var listening: CheckedContinuation<Void, Never>?
    /// The stand-ins played for the line being taken, held only until the bleed
    /// check has read them, then released (§5 rules 1-2).
    @ObservationIgnored private var runToken = 0
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var ended = false
    @ObservationIgnored private var heldStandIns: [StandInAudio] = []

    static let roomToneSeconds = 5

    init(production: Production, script: PlayScript, part: PartID, store: ProductionStore,
         audio: LiveAudio, voice: StandInVoice,
         sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         announce: @escaping () async -> Void = RecordingSession.announceYourLine) {
        self.production = production
        self.script = script
        self.part = part
        self.store = store
        self.audio = audio
        self.voice = voice
        self.sleep = sleep
        self.announce = announce
    }

    var lines: [ScriptLine] { script.lines(for: part) }

    var isBusy: Bool {
        switch phase {
        case .roomTone, .cue, .listening: true
        default: false
        }
    }

    func begin(echoCancelled: Bool) async {
        guard !started else { return }
        do {
            try audio.start(echoCancelled: echoCancelled)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        self.echoCancelled = echoCancelled
        started = true
        audio.beginCapture { _ in }
        for second in stride(from: Self.roomToneSeconds, to: 0, by: -1) {
            phase = .roomTone(secondsLeft: second)
            await sleep(.seconds(1))
        }
        let tone = audio.endCapture()
        roomToneRMS = LineEndDetector.rms(tone.samples)
        if !tone.samples.isEmpty, let name = try? store.writeRoomTone(tone, production: production) {
            mutate { $0.roomTone.append(name) }
        }
        phase = .idle
    }

    /// Plays cue lines (a usable human take where one exists, the device voice live where not) and
    /// says what each was. A stand-in is held in `heldStandIns` only until the bleed check has read it.
    private func playCues(_ cues: [ScriptLine], live: () -> Bool) async -> [String: String] {
        var heard: [String: String] = [:]
        for cue in cues {
            guard live() else { break }
            if let take = production.usableTake(for: cue.id) {
                phase = .cue(lineID: cue.id, deviceVoice: false)
                await audio.play(.take(store.takeURL(production, take)))
                heard[cue.id] = take.id
            } else if let line = await voice.render(cue.spokenText, part: cue.part, rate: standInRate), live() {
                phase = .cue(lineID: cue.id, deviceVoice: true)
                heldStandIns.append(line)
                await audio.play(.standIn(line))
                heard[cue.id] = Take.standIn
            }
        }
        return heard
    }

    /// Opens the microphone on a line until it ends (or Stop) and keeps the line window as a new take.
    /// The stand-ins held for the bleed check are released here, win or lose.
    private func listenAndKeep(_ lineID: String, heard: [String: String]) async -> Take? {
        await announce()
        guard !ended else { heldStandIns = []; return nil }
        phase = .listening(lineID: lineID)
        levels = []
        listeningSince = .now
        detector = LineEndDetector(sampleRate: TakeAudio.sampleRate, roomToneRMS: roomToneRMS)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            listening = done
            audio.beginCapture { [weak self] chunk in self?.hear(chunk) }
        }
        let capture = audio.endCapture()
        listeningSince = nil
        let window = LineEndDetector.window(onset: detector?.onset, end: detector?.end,
                                            total: capture.samples.count, sampleRate: capture.sampleRate)
        detector = nil
        let kept = capture.slice(window)
        let bleed = heldStandIns.contains {
            BleedCheck.score(signal: kept.samples, reference: $0.samples, sampleRate: kept.sampleRate)
                >= BleedCheck.threshold
        }
        heldStandIns = []
        guard !ended, !kept.samples.isEmpty else { return nil }
        do {
            let file = try store.writeTake(kept, production: production, lineID: lineID)
            let take = Take(id: UUID().uuidString, lineID: lineID, part: part, file: file, created: .now,
                            frames: kept.samples.count, sampleRate: kept.sampleRate,
                            capture: echoCancelled ? .aec : .direct, heard: heard,
                            loudness: BS1770.integratedLoudness(kept.samples, sampleRate: kept.sampleRate),
                            peak: BS1770.samplePeak(kept.samples), bleed: bleed)
            mutate { $0.add(take) }
            lastTakeBleed = bleed
            return take
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Remembers a take the run made, with the take its line had before, for Discard the run.
    private func noteRun(_ lineID: String, _ take: Take, prior: String?) {
        guard var current = run else { return }
        if let at = current.takes.firstIndex(where: { $0.lineID == lineID }) {
            current.takes[at].takes.append(take.id)
        } else {
            current.takes.append(RunNote(lineID: lineID, prior: prior, takes: [take.id]))
        }
        run = current
    }

    private var failed: Bool { if case .failed = phase { true } else { false } }

    /// Step and Line by line: plays the cue, then listens for the line and keeps it as a new take (the
    /// line's chosen one; older takes stay). Step ends on the take's review, Line by line on the line,
    /// ready; Again in a run's review returns to the review.
    func record(_ lineID: String, runUp: Bool = false) async {
        guard started, !isBusy, !ended else { return }
        let prior = production.chosen[lineID]
        heldStandIns = []
        cancelled = false
        let heard = await playCues(Relay.cueLines(before: lineID, in: script, runUp: runUp), live: { !ended && !cancelled })
        guard !ended else { heldStandIns = []; return }
        guard !cancelled else {
            heldStandIns = []
            phase = run == nil ? .idle : .runReview
            return
        }
        let take = await listenAndKeep(lineID, heard: heard)
        guard !ended, !failed else { return }
        if run != nil {
            if let take { noteRun(lineID, take, prior: prior) }
            phase = .runReview
        } else if take == nil {
            phase = .idle
        } else {
            phase = mode == .step ? .review(lineID: lineID) : .idle
        }
    }

    /// Run through (owner ruling 4): the play runs straight through from the line's cue, other parts in
    /// their human takes or the device voice live, and the microphone opens on each of this part's lines
    /// as it comes; the line-end detector closes it and the play goes on. The run ends after the part's
    /// last line or at Pause, and opens its review.
    func runThrough(from lineID: String) async {
        guard started, !isBusy, !ended, run == nil else { return }
        runToken += 1
        let mine = runToken
        run = Run(from: lineID, takes: [])
        let live = { [self] in !ended && mine == runToken }
        var heard: [String: String] = [:]
        heldStandIns = []
        for step in Relay.runPlan(production, script, part: part, from: lineID) {
            guard live() else { break }
            guard let line = script.lines.first(where: { $0.id == step.lineID }) else { continue }
            if step.isMine {
                let prior = production.chosen[line.id]
                let take = await listenAndKeep(line.id, heard: heard)
                guard !ended, !failed else { return }
                if let take { noteRun(line.id, take, prior: prior) }
                heard = [:]
            } else {
                heard.merge(await playCues([line], live: live)) { $1 }
            }
        }
        heldStandIns = []
        guard !ended else { return }
        if let run, !run.takes.isEmpty {
            phase = .runReview
        } else {
            run = nil
            phase = .idle
        }
    }

    /// Pause ends a run; a line being recorded is kept as far as it went.
    func pause() {
        guard run != nil, phase != .runReview else { return }
        runToken += 1
        if case .listening = phase { finishListening() } else { audio.stopPlayback() }
    }

    /// Cancel while a cue plays outside a run: the cue stops and nothing is recorded.
    func cancel() {
        guard case .cue = phase, run == nil else { return }
        cancelled = true
        audio.stopPlayback()
    }

    /// Keep N takes: the run's takes stay their lines' chosen ones.
    func keepRun() {
        guard run != nil, phase == .runReview else { return }
        run = nil
        phase = .idle
    }

    /// Discard the run: its takes are deleted and each line goes back to the take it had.
    func discardRun() {
        guard let current = run, phase == .runReview else { return }
        run = nil
        try? store.discardRun(production.id, current.takes)
        production = store.production(production.id) ?? production
        phase = .idle
    }

    /// The takes the run on screen made, in script order, each its line's latest.
    var runTakes: [Take] {
        (run?.takes ?? []).compactMap { $0.takes.last.flatMap { production.take($0) } }
    }

    /// Keep in Step: the take stays the line's chosen one and the next line is ready, its cue not played.
    func dismissReview() {
        if case .review = phase { phase = .idle }
    }

    /// After a playback, back to where it started (a cue or listening phase is never the place to return to).
    private func settle(_ back: Phase) {
        guard !ended else { return }
        switch back {
        case .cue, .listening: phase = .idle
        default: phase = back
        }
    }

    /// The cue alone, heard before recording a line (Line by line's Cue). Writes nothing.
    func playCue(_ lineID: String) async {
        guard started, !isBusy else { return }
        let back = phase
        heldStandIns = []
        cancelled = false
        _ = await playCues(Relay.cueLines(before: lineID, in: script, runUp: false), live: { !ended && !cancelled })
        heldStandIns = []
        settle(back)
    }

    /// A take heard after its cue, as it will sit in the play (Step's With cue, the run's review).
    func playWithCue(_ take: Take) async {
        guard started, !isBusy else { return }
        let back = phase
        heldStandIns = []
        cancelled = false
        _ = await playCues(Relay.cueLines(before: take.lineID, in: script, runUp: false), live: { !ended && !cancelled })
        heldStandIns = []
        guard !ended, !cancelled else { settle(back); return }
        phase = .cue(lineID: take.lineID, deviceVoice: false)
        await audio.play(.take(store.takeURL(production, take)))
        settle(back)
    }

    /// The mode control: refused while the microphone is armed or open, and during a run.
    @discardableResult
    func setMode(_ new: Mode) -> Bool {
        guard !isBusy, run == nil else { return false }
        mode = new
        if case .review = phase { phase = .idle }
        return true
    }

    /// The one control's second press: stop listening now.
    func stopListening() {
        guard case .listening = phase else { return }
        finishListening()
    }

    /// "Hear it read": the device voice reads the performer's own line once, on
    /// request, as a rehearsal aid (research 08a §5.2). Never kept.
    func hearItRead(_ lineID: String) async {
        guard started, !isBusy, let line = script.lines.first(where: { $0.id == lineID }),
              let audioLine = await voice.render(line.spokenText, part: line.part, rate: standInRate) else { return }
        phase = .cue(lineID: lineID, deviceVoice: true)
        await audio.play(.standIn(audioLine))
        phase = .idle
    }

    func playTake(_ take: Take) async {
        guard started, !isBusy else { return }
        let back = phase
        phase = .cue(lineID: take.lineID, deviceVoice: false)
        await audio.play(.take(store.takeURL(production, take)))
        settle(back)
    }

    func choose(_ take: Take) {
        mutate { $0.choose(take.id) }
    }

    /// Changes the store's current record, never a stale copy: the cast sheet
    /// may have moved the relay on while this session was open.
    private func mutate(_ change: (inout Production) -> Void) {
        var latest = store.production(production.id) ?? production
        change(&latest)
        store.update(latest)
        production = latest
    }

    func end() {
        ended = true
        runToken += 1
        finishListening()
        audio.stop()
        started = false
        phase = .idle
    }

    private func hear(_ chunk: [Float]) {
        levels.append(min(1, LineEndDetector.rms(chunk) * 12))
        if levels.count > 48 { levels.removeFirst(levels.count - 48) }
        guard listening != nil, var d = detector else { return }
        let event = d.feed(chunk)
        detector = d
        if case .end = event { finishListening() }
    }

    private func finishListening() {
        let done = listening
        listening = nil
        done?.resume()
    }

    /// VoiceOver speaks through the speaker the microphone hears, so it says
    /// "Your line" before listening starts and nothing while it listens (§7).
    static func announceYourLine() async {
        #if os(iOS)
        let running = UIAccessibility.isVoiceOverRunning
        #else
        let running = NSWorkspace.shared.isVoiceOverEnabled
        #endif
        guard running else { return }
        AccessibilityNotification.Announcement("Your line").post()
        try? await Task.sleep(for: .seconds(1.2))
    }
}
#endif
