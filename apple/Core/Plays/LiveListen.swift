#if os(iOS) || os(macOS)
import AVFoundation
import Foundation

/// Reads a listen-through's device-voice lines aloud, live (PLAYS-DESIGN §2.6).
/// The app's speaks through `AVSpeechSynthesizer.speak`, which makes no buffer
/// the app can hold; the tests' is a fake that speaks nothing.
protocol ListenSpeaker: AnyObject {
    func speak(_ text: String, part: PartID, personalVoice: Bool) async
    func stop()
}

/// Plays one human take from its file, to its end.
protocol ListenTakePlayer: AnyObject {
    func play(_ url: URL) async
    func stop()
}

/// A listen-through of a play that is not yet complete: the plan run in
/// order, live. It writes nothing and never marks the play listened through.
@Observable
final class LiveListenThrough {
    private(set) var current: ListenEntry?
    private(set) var isRunning = false
    var usesPersonalVoice = false

    @ObservationIgnored private let speaker: ListenSpeaker
    @ObservationIgnored private let player: ListenTakePlayer
    @ObservationIgnored private var stopped = false

    init(speaker: ListenSpeaker, player: ListenTakePlayer) {
        self.speaker = speaker
        self.player = player
    }

    static func system() -> LiveListenThrough {
        LiveListenThrough(speaker: SystemListenSpeaker(), player: SystemTakePlayer())
    }

    func run(_ plan: [ListenEntry], takeURL: (Take) -> URL) async {
        guard !isRunning else { return }
        isRunning = true
        stopped = false
        defer {
            isRunning = false
            current = nil
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        for entry in plan {
            guard !stopped else { break }
            current = entry
            switch entry {
            case let .take(_, _, take): await player.play(takeURL(take))
            case let .voice(_, part, text): await speaker.speak(text, part: part, personalVoice: usesPersonalVoice)
            }
        }
    }

    func stop() {
        stopped = true
        speaker.stop()
        player.stop()
    }
}

/// The device's voices, spoken aloud. A Personal Voice is used only here and
/// only through `speak` (§5 rule 6): never `write(_:toBufferCallback:)`, a
/// file, a recording cue, or the mix.
final class SystemListenSpeaker: NSObject, ListenSpeaker, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var finished: CheckedContinuation<Void, Never>?
    private var speaking: ObjectIdentifier?
    private var assigned: [PartID: Int] = [:]
    private lazy var voices = SystemStandInVoice.castableVoices()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    static var personalVoiceStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus {
        AVSpeechSynthesizer.personalVoiceAuthorizationStatus
    }

    static func personalVoice() -> AVSpeechSynthesisVoice? {
        guard personalVoiceStatus == .authorized else { return nil }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.voiceTraits.contains(.isPersonalVoice) }
    }

    func speak(_ text: String, part: PartID, personalVoice: Bool) async {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: words)
        if personalVoice, let mine = Self.personalVoice() {
            utterance.voice = mine
        } else if !voices.isEmpty {
            let index = assigned[part] ?? {
                let next = assigned.count
                assigned[part] = next
                return next
            }()
            utterance.voice = voices[index % voices.count]
            utterance.pitchMultiplier = SystemStandInVoice.pitches[(index / voices.count)
                % SystemStandInVoice.pitches.count]
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            finished = done
            speaking = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        resume(nil)
    }

    private func resume(_ utterance: ObjectIdentifier?) {
        guard utterance == nil || utterance == speaking else { return }
        let done = finished
        finished = nil
        speaking = nil
        done?.resume()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.resume(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.resume(id) }
    }
}

/// One take file at a time, to its end or until stopped.
final class SystemTakePlayer: NSObject, ListenTakePlayer, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var finished: CheckedContinuation<Void, Never>?

    func play(_ url: URL) async {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        self.player = player
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            finished = done
            if !player.play() { resume() }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        resume()
    }

    private func resume() {
        let done = finished
        finished = nil
        done?.resume()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resume() }
    }
}
#endif
