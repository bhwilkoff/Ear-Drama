#if os(iOS) || os(macOS)
import AVFoundation
import Foundation
import SwiftUI

/// One performer recording one part, line by line (PLAYS-DESIGN §2.3-2.4):
/// five seconds of room tone, then for each line the cue before it (a human
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
        case failed(String)
    }

    private(set) var phase: Phase = .idle
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

    /// Plays the cue, then listens for the performer's line and keeps it as a
    /// new take (the line's chosen one; older takes stay).
    func record(_ lineID: String, runUp: Bool = false) async {
        guard started, !isBusy else { return }
        var heard: [String: String] = [:]
        heldStandIns = []
        for cue in Relay.cueLines(before: lineID, in: script, runUp: runUp) {
            if let take = production.chosenTake(for: cue.id) {
                phase = .cue(lineID: cue.id, deviceVoice: false)
                await audio.play(.take(store.takeURL(production, take)))
                heard[cue.id] = take.id
            } else if let line = await voice.render(cue.spokenText, part: cue.part, rate: standInRate) {
                phase = .cue(lineID: cue.id, deviceVoice: true)
                heldStandIns.append(line)
                await audio.play(.standIn(line))
                heard[cue.id] = Take.standIn
            }
        }
        await announce()
        phase = .listening(lineID: lineID)
        detector = LineEndDetector(sampleRate: TakeAudio.sampleRate, roomToneRMS: roomToneRMS)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            listening = done
            audio.beginCapture { [weak self] chunk in self?.hear(chunk) }
        }
        let capture = audio.endCapture()
        let window = LineEndDetector.window(onset: detector?.onset, end: detector?.end,
                                            total: capture.samples.count, sampleRate: capture.sampleRate)
        detector = nil
        let kept = capture.slice(window)
        let bleed = heldStandIns.contains {
            BleedCheck.score(signal: kept.samples, reference: $0.samples, sampleRate: kept.sampleRate)
                >= BleedCheck.threshold
        }
        heldStandIns = []
        guard !kept.samples.isEmpty else {
            phase = .idle
            return
        }
        do {
            let file = try store.writeTake(kept, production: production, lineID: lineID)
            let take = Take(id: UUID().uuidString, lineID: lineID, part: part, file: file, created: .now,
                            frames: kept.samples.count, sampleRate: kept.sampleRate,
                            capture: echoCancelled ? .aec : .direct, heard: heard,
                            loudness: BS1770.integratedLoudness(kept.samples, sampleRate: kept.sampleRate),
                            peak: BS1770.samplePeak(kept.samples), bleed: bleed)
            mutate { $0.add(take) }
            lastTakeBleed = bleed
            phase = .review(lineID: lineID)
        } catch {
            phase = .failed(error.localizedDescription)
        }
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
        phase = .cue(lineID: take.lineID, deviceVoice: false)
        await audio.play(.take(store.takeURL(production, take)))
        phase = .review(lineID: take.lineID)
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
        finishListening()
        audio.stop()
        started = false
        phase = .idle
    }

    private func hear(_ chunk: [Float]) {
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
