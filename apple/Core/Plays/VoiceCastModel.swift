import Foundation
import AVFoundation
import Observation

// What the screens read of the cast (PLAYS-DESIGN §2.8): a thin observable over `VoiceCast`, the picker's
// preview, and the reader's table read. None of it keeps a sound: a device voice is a live stand-in (§5).

/// The cast as a screen shows it. `revision` moves on every change and when the device's voices change
/// (a voice downloaded in Settings appears on return), so a view that reads through here repaints.
@Observable
final class VoiceCastModel {
    let cast: VoiceCast
    private(set) var revision = 0

    init(cast: VoiceCast) { self.cast = cast }

    func refresh() { revision += 1 }

    func resolve(_ part: PartID) -> ResolvedVoice {
        _ = revision
        return cast.resolve(part)
    }

    var voices: [CastVoice] {
        _ = revision
        return cast.voices()
    }

    /// The downloaded (Kokoro) voices: none until the model is here.
    var downloaded: [CastVoice] {
        _ = revision
        return cast.downloadedVoices()
    }

    /// What the part's Default reads now, for the picker's first row.
    func defaultVoiceName(_ part: PartID) -> String? {
        _ = revision
        return cast.defaultEntry(part).flatMap { $0.engine == .none ? nil : $0.name }
    }

    /// Back to the Default: the part's choice is dropped.
    func reset(_ part: PartID) {
        cast.reset(part)
        revision += 1
    }

    func set(_ part: PartID, _ change: (inout VoiceCastEntry) -> Void) {
        cast.set(part, change)
        revision += 1
    }

    func recast() {
        cast.recast()
        revision += 1
    }
}

/// The picker's preview: the part's own first line in the voice tapped, live, never kept.
@MainActor final class VoicePreview: NSObject, AVSpeechSynthesizerDelegate {
    /// The id of the voice being heard; `onChange` fires when it moves.
    private(set) var playing: String? { didSet { onChange?(playing) } }
    var onChange: ((String?) -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var current: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String, voice: CastVoice, rate: Double, pitch: Double, playID: String? = nil) {
        if playing == voice.id {
            stop()
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        #if os(iOS) || os(macOS)
        KokoroLive.shared.stop()
        if voice.engine == .kokoro {
            guard let playID, !DeviceVoices.said(text).isEmpty else {
                playing = nil
                return
            }
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            playing = voice.id
            let id = voice.id
            Task {
                let ok = await KokoroLive.shared.speak(playID, text, voice: id, rate: rate, pitch: pitch, muted: SpeechMute.volume == 0)
                guard self.playing == id else { return }
                // A line Kokoro cannot read is read by the device's own voice, never skipped (PLAYS-DESIGN §2.8 rule 10).
                if !ok, let fallback = DeviceVoices.castable().first {
                    self.speakSystem(text, voice: fallback, rate: rate, pitch: pitch, as: id)
                } else {
                    self.playing = nil
                }
            }
            return
        }
        #endif
        speakSystem(text, voice: voice, rate: rate, pitch: pitch, as: voice.id)
    }

    private func speakSystem(_ text: String, voice: CastVoice, rate: Double, pitch: Double, as id: String) {
        let words = DeviceVoices.said(text)
        guard !words.isEmpty, let av = DeviceVoices.avVoice(voice) else {
            playing = nil
            return
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: words)
        utterance.voice = av
        utterance.pitchMultiplier = Float(pitch)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate))
        utterance.volume = SpeechMute.volume
        current = ObjectIdentifier(utterance)
        playing = id
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        #if os(iOS) || os(macOS)
        KokoroLive.shared.stop()
        #endif
        current = nil
        playing = nil
    }

    private func ended(_ id: ObjectIdentifier) {
        guard current == id else { return }
        current = nil
        playing = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(id) }
    }
}

/// Hear the cast (§2.7, §2.8): the script read from a line to its end, each part in its cast voice, the
/// reader following each line. Directions and sound are skipped until their part has a voice. It holds no
/// store and no network.
@Observable
final class TableRead {
    private(set) var line: ScriptLine?
    private(set) var isPlaying = false

    @ObservationIgnored private let script: PlayScript
    @ObservationIgnored private let speaker: ListenSpeaker
    @ObservationIgnored private let onLine: (String?) -> Void
    @ObservationIgnored private var run = 0

    init(script: PlayScript, speaker: ListenSpeaker, onLine: @escaping (String?) -> Void = { _ in }) {
        self.script = script
        self.speaker = speaker
        self.onLine = onLine
    }

    func play(from index: Int = 0) async {
        run += 1
        let mine = run
        isPlaying = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        var i = max(0, index)
        while i < script.lines.count, mine == run {
            let next = script.lines[i]
            i += 1
            if next.kind != .speech, !speaker.reads(next.part) { continue }
            line = next
            onLine(next.id)
            await speaker.speak(next.spokenText, part: next.part, personalVoice: false)
        }
        if mine == run {
            isPlaying = false
            line = nil
            onLine(nil)
        }
    }

    func stop() {
        run += 1
        isPlaying = false
        line = nil
        speaker.stop()
    }
}
