import AVFoundation
import MediaPlayer
import Observation

/// The one playback engine every Apple platform shares (research 04 §2, §10):
/// AVPlayer over the episode's default recording, the audio session, Now
/// Playing and remote commands, speed, a resume position per episode, the R20
/// sleep timer, the volume leveler (Decision 067), and the queue rule: one
/// episode, then what the person queued, then stop.
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
            onRoomChange()
        }
    }
    /// Listen Together: this device follows a host, so its own transport is
    /// refused and the room drives it (iOS-DESIGN §5.8).
    private(set) var isFollowing = false
    /// Decision 067: a following member paused their own sound. The room plays
    /// on; resuming catches them up to where the host is now.
    private(set) var isHeld = false
    var isMuted = false {
        didSet { player.isMuted = isMuted }
    }
    /// Decision 067: volume leveled on the device as it plays, on unless the
    /// person turned it off (kept on the device).
    var isLeveling: Bool {
        didSet {
            leveler.set(isLeveling)
            UserDefaults.standard.set(isLeveling, forKey: Self.levelingKey)
        }
    }
    static let levelingKey = "player.leveling"

    /// Resolves an episode id to its detail (the catalog lives in the app's
    /// CatalogStore; the player never opens the database itself).
    @ObservationIgnored var resolveDetail: (String) async -> EpisodeDetail? = { _ in nil }
    /// The person's queue, head first (the synced `ListeningQueue`), and how
    /// to take an episode off it once it plays.
    @ObservationIgnored var queuedIDs: () -> [String] = { [] }
    @ObservationIgnored var dequeue: (String) -> Void = { _ in }
    /// A downloaded file for this episode's recording, played instead of the
    /// network copy (iOS and Mac; the TV never downloads).
    @ObservationIgnored var localFile: (String, Recording) -> URL? = { _, _ in nil }
    /// Told of each load, pause, end, sleep, and stop; the live radio listens.
    @ObservationIgnored var onTransport: (TransportEvent) -> Void = { _ in }
    /// Told when this player's episode, play state, position, or speed changes
    /// by its own hand, so a SharePlay host can publish it.
    @ObservationIgnored var onRoomChange: () -> Void = {}
    /// A follower started something of its own (another episode, or the
    /// headphones came out): it leaves the room rather than fight the host.
    @ObservationIgnored var onLeaveRoom: () -> Void = {}
    /// A follower held (true) or released (false) their own sound; the room
    /// catches them up on release.
    @ObservationIgnored var onGuestHold: (Bool) -> Void = { _ in }

    @ObservationIgnored let history: ListeningHistory
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private var commandsInstalled = false
    @ObservationIgnored private let leveler: LevelerSwitch

    init(history: ListeningHistory) {
        self.history = history
        let leveling = UserDefaults.standard.object(forKey: Self.levelingKey) as? Bool ?? true
        isLeveling = leveling
        leveler = LevelerSwitch(leveling)
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
    /// it, with the person's queue behind it. `offset` starts it there instead
    /// (a Radio slot); `queue: false` plays nothing after it.
    func play(_ detail: EpisodeDetail, recording: Recording? = nil, from offset: Double? = nil, queue: Bool = true) {
        if isFollowing { onLeaveRoom() }
        load(detail, recording: recording, from: offset, queue: queue, rate: speed)
    }

    private func load(_ detail: EpisodeDetail, recording: Recording?, from offset: Double?, queue: Bool, rate: Float?) {
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
        player.volume = 1
        level(playerItem)
        if let start = offset ?? history.resumePosition(for: detail.episode.id) {
            elapsed = start
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        player.defaultRate = speed
        if let rate { player.playImmediately(atRate: rate) } else { player.pause() }
        publishNowPlaying()
        onTransport(.loaded(detail.episode.id))
        onRoomChange()

        dequeue(detail.episode.id)
        playsQueue = queue
        refreshUpNext()
    }

    /// Whether this item plays the queue after it (a Radio slot and a room do not).
    @ObservationIgnored private var playsQueue = false

    /// Shows what plays next: the queue's head, resolved for its title.
    func refreshUpNext() {
        guard playsQueue, let current = item,
              let next = PlaybackQueue.next(after: current.episode.id, queued: queuedIDs()) else {
            upNext = []
            return
        }
        let episodeID = current.episode.id
        Task { [weak self] in
            guard let self, let detail = await self.resolveDetail(next),
                  self.item?.episode.id == episodeID else { return }
            self.upNext = [detail.episode]
        }
    }

    /// The tap goes on once the asset's audio track is known; until then, and
    /// wherever a tap cannot be made, the item plays unleveled.
    private func level(_ playerItem: AVPlayerItem) {
        Task { [weak self] in
            guard let track = try? await playerItem.asset.loadTracks(withMediaType: .audio).first,
                  let self, self.player.currentItem === playerItem else { return }
            playerItem.audioMix = VolumeLeveler.mix(for: track, toggle: self.leveler)
        }
    }

    func resume() {
        if isFollowing {
            guard isHeld else { return }
            isHeld = false
            onGuestHold(false)
            return
        }
        guard item != nil else { return }
        // A listener pressing Play after the timer stopped them is awake.
        if sleep.mode == .fired { sleep.cancel() }
        player.volume = 1
        activateSession()
        player.playImmediately(atRate: speed)
    }

    func pause() {
        if isFollowing {
            isHeld = true
            player.pause()
            onGuestHold(true)
            return
        }
        player.pause()
        saveProgress()
        onTransport(.paused)
    }

    func togglePlayPause() {
        if isFollowing { isHeld ? resume() : pause() } else { isPlaying ? pause() : resume() }
    }

    func skip(by seconds: Double) {
        guard !isFollowing else { return }
        let target = max(0, elapsed + seconds)
        seek(to: duration.map { min(target, max(0, $0 - 1)) } ?? target)
    }

    func seek(to seconds: Double) {
        guard !isFollowing else { return }
        seekExactly(to: seconds)
        onRoomChange()
    }

    private func seekExactly(to seconds: Double) {
        elapsed = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        publishNowPlaying()
    }

    // MARK: - Listen Together (the SharePlay room drives these; nothing else does)

    /// Where this player is now, read from AVPlayer rather than the half-second tick.
    var roomReading: PlayerReading {
        let seconds = player.currentTime().seconds
        return PlayerReading(position: seconds.isFinite ? seconds : elapsed, playing: player.rate != 0)
    }

    func setFollowing(_ following: Bool) {
        guard following != isFollowing else { return }
        isFollowing = following
        isHeld = false
        // A drift nudge never outlives the room.
        if !following, player.rate != 0 { player.rate = speed }
    }

    /// Loads the host's copy at the host's place, playing or paused.
    func follow(_ detail: EpisodeDetail, recording: Recording, at position: Double, playing: Bool, rate: Float) {
        if speed != rate { speed = rate }
        load(detail, recording: recording, from: position, queue: false, rate: playing ? rate : nil)
    }

    /// Applies the protocol's drift correction silently.
    func apply(_ correction: Correction, hostRate: Double) {
        let rate = Float(hostRate)
        if speed != rate, PlayerNumbers.speeds.contains(rate) { speed = rate }
        switch correction {
        case .none:
            break
        case .pause(let position):
            player.pause()
            seekExactly(to: position)
        case .seek(let position, let play):
            seekExactly(to: position)
            if play { player.playImmediately(atRate: rate) }
        case .play(let position, let playRate):
            seekExactly(to: position)
            player.playImmediately(atRate: Float(playRate))
        case .rate(let nudged):
            if player.rate != 0 { player.rate = Float(nudged) }
        }
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
        player.volume = 1
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
            player.volume = output.volume
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
        onRoomChange()
    }

    private func itemDidEnd() {
        guard let current = item else { return }
        history.markFinished(current.episode.id, duration: duration)
        // R20: once the timer fires (or it was set for this episode), nothing
        // starts the next one. Decision 067: only what the person queued plays
        // next, whatever its series; with the queue empty, playback stops.
        let mayContinue = sleep.episodeDidEnd()
        onTransport(mayContinue ? .ended : .sleepFired)
        guard mayContinue, playsQueue,
              let next = PlaybackQueue.next(after: current.episode.id, queued: queuedIDs()) else {
            upNext = []
            isPlaying = false
            publishNowPlaying()
            return
        }
        upNext = []
        Task { [weak self] in
            guard let self, let detail = await self.resolveDetail(next) else { return }
            self.load(detail, recording: nil, from: nil, queue: true, rate: self.speed)
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
                guard reason == .oldDeviceUnavailable, let self else { return }
                if self.isFollowing { self.onLeaveRoom() }
                self.pause()
            }
        })
        #endif
    }
}
