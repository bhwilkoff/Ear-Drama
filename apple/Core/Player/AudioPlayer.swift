import AVFoundation
import MediaPlayer
import Observation

/// The one playback engine every Apple platform shares (research 04 §2, §10):
/// AVPlayer over the episode's default recording, the audio session, Now
/// Playing and remote commands, speed, a resume position per episode, the R20
/// sleep timer, and a queue that never runs into unrelated content.
@Observable
final class AudioPlayer {
    nonisolated enum Skip {
        static let back: Double = 15
        static let forward: Double = 30
    }

    static let speeds = PlayerNumbers.speeds

    struct Item: Equatable {
        let episode: EpisodeRow
        let recording: Recording
    }

    private(set) var item: Item?
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double?
    private(set) var errorMessage: String?
    /// The current item plays from a downloaded file, not the network.
    private(set) var isLocal = false
    private(set) var upNext: [EpisodeRow] = []
    private(set) var sleep = SleepTimer()
    /// Bumps once a second while a sleep countdown runs, so its label redraws.
    private(set) var clock = Date()
    var speed: Float = 1.0 {
        didSet {
            player.defaultRate = speed
            if isPlaying { player.rate = speed }
            publishNowPlaying()
        }
    }
    var isMuted = false {
        didSet { player.isMuted = isMuted }
    }

    /// Resolves an episode id to its detail (the catalog lives in the app's
    /// CatalogStore; the player never opens the database itself).
    @ObservationIgnored var resolveDetail: (String) async -> EpisodeDetail? = { _ in nil }
    /// The series page an episode belongs to, for the queue.
    @ObservationIgnored var resolveSeriesPage: (String) async -> SeriesPage? = { _ in nil }
    /// A downloaded file for this episode's recording, played instead of the
    /// network copy (iOS and Mac; the TV never downloads).
    @ObservationIgnored var localFile: (String, Recording) -> URL? = { _, _ in nil }
    /// Told of each load, pause, end, sleep, and stop; the live radio listens.
    @ObservationIgnored var onTransport: (TransportEvent) -> Void = { _ in }

    @ObservationIgnored let history: ListeningHistory
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private var commandsInstalled = false
    /// The episode's loudness level (DECISIONS 061); the sleep fade scales
    /// from it, and the device's volume stays the listener's.
    @ObservationIgnored private var baseVolume: Float = 1

    init(history: ListeningHistory) {
        self.history = history
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.timeControlChanged(status) }
        }
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let ended = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let current = self.player.currentItem,
                      ended == ObjectIdentifier(current) else { return }
                self.itemDidEnd()
            }
        })
        observeAudioSession()
    }

    // MARK: - Transport

    /// Plays an episode's default recording, resuming where the listener left
    /// it, with the rest of its series queued behind it. `offset` starts it
    /// there instead (a Radio slot); `queue: false` queues nothing behind it.
    func play(_ detail: EpisodeDetail, recording: Recording? = nil, from offset: Double? = nil, queue: Bool = true) {
        guard let recording = recording ?? detail.defaultRecording else {
            errorMessage = "No recording survives for this episode."
            return
        }
        saveProgress()
        activateSession()
        installRemoteCommands()
        errorMessage = nil
        item = Item(episode: detail.episode, recording: recording)
        elapsed = 0
        duration = recording.lengthSeconds ?? detail.episode.lengthSeconds
        upNext = []

        let local = localFile(detail.episode.id, recording)
        isLocal = local != nil
        let playerItem = AVPlayerItem(url: local ?? recording.url)
        playerItem.audioTimePitchAlgorithm = .timeDomain
        itemStatusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] observed, _ in
            let failed = observed.status == .failed
            let message = observed.error?.localizedDescription
            Task { @MainActor in
                guard failed else { return }
                print("[AudioPlayer] item failed: \(message ?? "unknown")")
                self?.errorMessage = "This recording would not play."
                self?.isPlaying = false
            }
        }
        player.replaceCurrentItem(with: playerItem)
        player.isMuted = isMuted
        baseVolume = LoudnessLevel.volume(for: detail.episode, recording: recording)
        player.volume = baseVolume
        if let start = offset ?? history.resumePosition(for: detail.episode.id) {
            elapsed = start
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        player.defaultRate = speed
        player.playImmediately(atRate: speed)
        publishNowPlaying()
        onTransport(.loaded(detail.episode.id))

        guard queue else { return }
        let episodeID = detail.episode.id
        let seriesKey = detail.episode.seriesKey
        Task { [weak self] in
            guard let self, let page = await self.resolveSeriesPage(seriesKey),
                  self.item?.episode.id == episodeID else { return }
            self.upNext = PlaybackQueue.following(episodeID, in: page)
        }
    }

    func resume() {
        guard item != nil else { return }
        // A listener pressing Play after the timer stopped them is awake.
        if sleep.mode == .fired { sleep.cancel() }
        player.volume = baseVolume
        activateSession()
        player.playImmediately(atRate: speed)
    }

    func pause() {
        player.pause()
        saveProgress()
        onTransport(.paused)
    }

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func skip(by seconds: Double) {
        let target = max(0, elapsed + seconds)
        seek(to: duration.map { min(target, max(0, $0 - 1)) } ?? target)
    }

    func seek(to seconds: Double) {
        elapsed = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        publishNowPlaying()
    }

    /// Stops and forgets the current item (the end of a door, or Close).
    func stop() {
        saveProgress()
        player.pause()
        player.replaceCurrentItem(with: nil)
        item = nil
        isLocal = false
        upNext = []
        sleep.cancel()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        onTransport(.stopped)
    }

    // MARK: - Sleep timer

    func setSleep(_ option: SleepTimer.Option) {
        sleep.set(option, now: Date())
        clock = Date()
    }

    func cancelSleep() {
        sleep.cancel()
        player.volume = baseVolume
    }

    // MARK: - Ticks

    private func tick() {
        let now = Date()
        let seconds = player.currentTime().seconds
        if seconds.isFinite { elapsed = seconds }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }

        if sleep.mode != .off {
            clock = now
            let remaining = duration.map { max(0, $0 - elapsed) / Double(max(speed, 0.01)) }
            let output = sleep.tick(now: now, remainingInEpisode: remaining)
            player.volume = baseVolume * output.volume
            if output.shouldPause {
                player.pause()
                saveProgress()
                onTransport(.sleepFired)
            }
        }
        if isPlaying, PlayerNumbers.isSaveDue(lastSaved: lastSaved, now: now) { saveProgress() }
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        isPlaying = status != .paused
        isBuffering = status == .waitingToPlayAtSpecifiedRate
        if status == .paused { saveProgress() }
        publishNowPlaying()
    }

    private func itemDidEnd() {
        guard let current = item else { return }
        history.markFinished(current.episode.id, duration: duration)
        // R20: once the timer fires (or it was set for this episode), nothing
        // starts the next one. R3: the queue holds only this series.
        let mayContinue = sleep.episodeDidEnd()
        onTransport(mayContinue ? .ended : .sleepFired)
        guard mayContinue, let next = upNext.first else {
            isPlaying = false
            publishNowPlaying()
            return
        }
        upNext.removeFirst()
        Task { [weak self] in
            guard let self, let detail = await self.resolveDetail(next.id) else { return }
            self.play(detail)
        }
    }

    private func saveProgress() {
        guard let current = item, elapsed > 0 else { return }
        lastSaved = Date()
        history.record(current.episode.id, position: elapsed, duration: duration)
    }

    // MARK: - Now Playing and remote commands

    private func publishNowPlaying() {
        guard let current = item else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.episode.displayTitle,
            MPMediaItemPropertyAlbumTitle: current.episode.seriesName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(speed),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        // Artist only from data: the network that aired it.
        if let network = current.episode.network { info[MPMediaItemPropertyArtist] = network }
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
    }

    /// Skip intervals, NOT next/previous track: setting both makes CarPlay and
    /// the lock screen pick one arbitrarily (research 04 §2.3).
    private func installRemoteCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Skip.back)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: -Skip.back) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Skip.forward)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: Skip.forward) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { self?.seek(to: position) }
            return .success
        }
        center.changePlaybackRateCommand.supportedPlaybackRates = Self.speeds.map { NSNumber(value: $0) }
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = event.playbackRate
            MainActor.assumeIsolated { self?.speed = rate }
            return .success
        }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    // MARK: - Audio session (iOS, iPadOS, tvOS; macOS has none)

    private func activateSession() {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            print("[AudioPlayer] audio session: \(error.localizedDescription)")
        }
        #endif
    }

    private func observeAudioSession() {
        #if os(iOS) || os(tvOS)
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init) ?? []
            MainActor.assumeIsolated {
                guard let self, type == .ended, options.contains(.shouldResume), self.item != nil else { return }
                // Spoken word: hear the last line again before going on.
                self.skip(by: -PlayerNumbers.interruptionRewindSeconds)
                self.resume()
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                // Headphones unplugged: pause, as every audio app is expected to.
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        })
        #endif
    }
}
