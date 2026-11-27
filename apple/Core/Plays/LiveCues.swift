#if os(iOS) || os(macOS) || os(tvOS)
import AVFoundation
import Foundation

/// The Sound part's cues in a live listen (B32 §4.4: close, not sample-exact), the mirror of the web's `liveCues`: each
/// sound starts as its entry comes, loops for Under-to-the-end and beds, and drops by its duck while a voice sounds. The
/// export is the computed mix (`MixRenderer`); this is only what a listen hears. A sound with no file here plays nothing.
protocol ListenCuePlayer: AnyObject {
    /// Starts a cue; nil when its file is not on this device.
    func start(_ cue: SoundBoard.LiveCue, url: URL?) -> LiveCueHandle?
    func stopAll()
}

/// One sounding cue.
protocol LiveCueHandle: AnyObject {
    var soundID: String { get }
    var isBed: Bool { get }
    func duck(_ on: Bool)
    func stop()
    /// Returns when the cue has played out (a loop only when stopped).
    func done() async
}

/// The cues a listen plays: what each plan entry holds, and where each sound's file is.
struct ListenCues {
    let entries: [SoundBoard.EntryCues]
    let url: (SoundSource) -> URL?
    let player: ListenCuePlayer
}

/// AVAudioPlayer per cue: the level in amplitude from the cue's gain, fades and the duck as volume ramps.
final class SystemCuePlayer: ListenCuePlayer {
    private var playing: [SystemCueHandle] = []

    func start(_ cue: SoundBoard.LiveCue, url: URL?) -> LiveCueHandle? {
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        let x = cue.sound
        let music = x.at == "bed"
        let duckDb = x.duckDb ?? (music ? SoundMix.musicDuckDb : SoundMix.effectsDuckDb)
        let level = Float(pow(10, SoundMix.clamp(x.gainDb, SoundMix.gainMinDb, SoundMix.gainMaxDb, 0) / 20)) * SpeechMute.volume
        let handle = SystemCueHandle(player: player, soundID: x.id, isBed: music || x.loop, level: level, duckDb: duckDb,
                                     fadeOut: x.fadeOutMs / 1000)
        player.numberOfLoops = x.loop ? -1 : 0
        player.volume = x.fadeInMs > 0 ? 0 : level
        player.prepareToPlay()
        let delay = max(0, x.startMs / 1000)
        player.play(atTime: player.deviceCurrentTime + delay)
        if x.fadeInMs > 0 { player.setVolume(level, fadeDuration: x.fadeInMs / 1000) }
        playing.removeAll { !$0.alive }
        playing.append(handle)
        return handle
    }

    func stopAll() {
        playing.forEach { $0.stop() }
        playing = []
    }
}

final class SystemCueHandle: NSObject, LiveCueHandle, AVAudioPlayerDelegate {
    let soundID: String
    let isBed: Bool
    private let player: AVAudioPlayer
    private let level: Float
    private let duckDb: Double
    private let fadeOut: Double
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var alive = true

    init(player: AVAudioPlayer, soundID: String, isBed: Bool, level: Float, duckDb: Double, fadeOut: Double) {
        self.player = player
        self.soundID = soundID
        self.isBed = isBed
        self.level = level
        self.duckDb = duckDb
        self.fadeOut = fadeOut
        super.init()
        player.delegate = self
    }

    func duck(_ on: Bool) {
        guard alive, duckDb < 0 else { return }
        let to = on ? level * Float(pow(10, duckDb / 20)) : level
        player.setVolume(to, fadeDuration: (on ? SoundMix.attackMs : SoundMix.releaseMs) / 1000)
    }

    func stop() {
        guard alive else { return }
        if fadeOut > 0, player.isPlaying {
            player.setVolume(0, fadeDuration: fadeOut)
            let p = player
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(self?.fadeOut ?? 0))
                p.stop()
                self?.finish()
            }
        } else {
            player.stop()
            finish()
        }
    }

    func done() async {
        guard alive else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func finish() {
        alive = false
        let w = waiting
        waiting = []
        w.forEach { $0.resume() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in self.finish() }
    }
}
#endif
