#if os(iOS) || os(macOS)
import AVFoundation
import Foundation

extension ProductionStore {
    /// Renders `mix.m4a` from the chosen takes when every speaking line has one
    /// (PLAYS-DESIGN §2.7), off the main actor, and records which takes it was
    /// made from. A partial play throws `.incomplete` and writes nothing.
    func renderMix(_ id: String) async throws -> URL {
        guard let production = production(id), let script = script(for: production) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let url = mixURL(id)
        if production.mixedFrom == production.chosenFingerprint, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let timeline = try MixTimeline.build(script: script, production: production)
        let folder = takesFolder(id)
        try await Task.detached(priority: .userInitiated) {
            try MixRenderer.render(timeline, takesFolder: folder, to: url)
        }.value
        if var latest = self.production(id) {
            latest.mixedFrom = production.chosenFingerprint
            update(latest)
        }
        return url
    }

    /// Someone listened from the top to the end: the play is finished (§2.7).
    func markListenedThrough(_ id: String, fingerprint: String) {
        guard var p = production(id), p.chosenFingerprint == fingerprint else { return }
        p.listenedThrough = true
        update(p)
    }
}

/// Plays a rendered mix on this device. AirPlay and the share sheet are the
/// system's, so the finished play reaches a television from here (§2.2).
@Observable
final class MixPlayback: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var reachedEnd = false
    private(set) var duration: TimeInterval = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    /// A seek forward means the listen was not all the way through.
    @ObservationIgnored private(set) var skipped = false

    var currentTime: TimeInterval { player?.currentTime ?? 0 }

    func load(_ url: URL) throws {
        stop()
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        duration = player.duration
        reachedEnd = false
        skipped = false
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            reachedEnd = false
            player.play()
        }
        isPlaying = player.isPlaying
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        if time > player.currentTime + 1 { skipped = true }
        player.currentTime = min(max(0, time), duration)
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        duration = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.reachedEnd = flag
        }
    }
}
#endif
