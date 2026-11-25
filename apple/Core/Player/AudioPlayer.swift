import AVFoundation
import ImageIO
import MediaPlayer
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Observation

/// The one playback engine every Apple platform shares (research 04 §2, §10):
/// AVPlayer over the episode's default recording, the audio session, Now
/// Playing and remote commands, speed, a resume position per episode, the R20
/// sleep timer, the volume leveler (Decision 067), and the queue rule: a
/// story arc's next part, else what the person queued, then stop; at an arc's
/// end the next story is offered, never started (`PlaybackQueue`).
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
        /// The episode's face, else its series' (Decision 069): Now Playing's picture.
        var face: Face? = nil
    }

    private(set) var item: Item?
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double?
    private(set) var errorMessage: String?
    /// APP_PLAYBACK_DIAG only: the engine's state each tick, drawn on the player.
    private(set) var diagLine: String?
    /// The current item plays from a downloaded file, not the network.
    private(set) var isLocal = false
    private(set) var upNext: [EpisodeRow] = []
    /// The current episode's place in its story arc, once read.
    private(set) var arc: ArcPosition?
    /// On an arc's last part: the series' next story, for the person to start.
    private(set) var nextStory: EpisodeRow?
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
    /// Resolves an episode id to its place in a story arc (CatalogStore.arc).
    @ObservationIgnored var resolveArc: (String) async -> ArcPosition? = { _ in nil }
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
    /// The episode's own label as an image (Decision 081), for an episode with no picture;
    /// drawn by the app (SwiftUI), since the player knows no views.
    @ObservationIgnored var cardImage: (EpisodeRow) async -> CGImage? = { _ in nil }
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
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

    #if os(macOS)
    /// The Mac has no audio session, so its AirPlay picker routes this player itself (macOS-DESIGN §5.2).
    var routedPlayer: AVPlayer { player }
    #endif

    init(history: ListeningHistory) {
        self.history = history
        let leveling = UserDefaults.standard.object(forKey: Self.levelingKey) as? Bool ?? true
        isLeveling = leveling
        leveler = LevelerSwitch(leveling)
        player.automaticallyWaitsToMinimizeStalling = true
        // AirPlay: the route picker hands this player to a speaker or an Apple TV (Decision 051: the origin URL).
        player.allowsExternalPlayback = true
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] player, _ in
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

    // MARK: - Held for casting by ear (PLAYS-DESIGN §13 item 10, iOS-DESIGN §4.22)

    /// The person's own speed, and whether the queue goes on, kept while a casting holds the player.
    @ObservationIgnored private var held: (speed: Float, queue: Bool)?
    var isCasting: Bool { held != nil }

    /// The player plays at the page's speed, never the person's, only the copy it is given, and nothing after its end.
    func hold(speed page: Float) {
        if held == nil { held = (speed, playsQueue) }
        playsQueue = false
        upNext = []
        if speed != page { speed = page }
    }

    /// Lets go: the person's own speed, and the queue as it was. What is playing plays on.
    func release() {
        guard let own = held else { return }
        held = nil
        if speed != own.speed { speed = own.speed }
        guard let current = item, own.queue else { return }
        playsQueue = true
        refreshUpNext()
        if arc == nil { readArc(current.episode.id) }
    }

    /// Where the audio is, read from AVPlayer rather than the half-second tick; nil while a load, its timing check or a
    /// seek has not landed, when the clock is not yet the person's place.
    var settledSeconds: Double? {
        guard let current = player.currentItem, current.status == .readyToPlay, timingCheck == nil, seeksInFlight == 0 else { return nil }
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : nil
    }

    /// Counts every move of the place by hand (a seek, a skip, a load), so a casting knows the lines between were not heard.
    @ObservationIgnored private(set) var jumps = 0

    // MARK: - Transport

    /// Plays an episode's default recording, resuming where the listener left
    /// it, with the person's queue behind it. `offset` starts it there instead
    /// (a Radio slot); `queue: false` plays nothing after it.
    func play(_ detail: EpisodeDetail, recording: Recording? = nil, from offset: Double? = nil, queue: Bool = true) {
        if isFollowing { onLeaveRoom() }
        // The episode already on the player: Play resumes it where it stands, never reloads it.
        if offset == nil, let current = item, current.episode.id == detail.episode.id,
           recording == nil || recording == current.recording, player.currentItem != nil, !isAtEnd {
            playsQueue = queue && held == nil
            resume()
            return
        }
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
        item = Item(episode: detail.episode, recording: recording, face: detail.face)
        loadArtwork(for: item)
        elapsed = 0
        duration = recording.lengthSeconds ?? detail.episode.lengthSeconds
        upNext = []
        arc = nil
        nextStory = nil
        arcRead = nil

        loadToken += 1
        // A casting's times are this copy's: no other is tried.
        recovery = LoadRecovery(chosen: recording, among: held == nil ? detail.recordings : [recording])
        loadContext = LoadContext(detail: detail, rate: rate)
        open(recording, detail: detail, start: offset ?? history.resumePosition(for: detail.episode.id, length: duration), rate: rate)
        publishNowPlaying()
        onTransport(.loaded(detail.episode.id))
        onRoomChange()

        dequeue(detail.episode.id)
        if held != nil { held?.queue = true }
        playsQueue = queue && held == nil
        refreshUpNext()
        if playsQueue { readArc(detail.episode.id) }
    }

    /// What a recovery needs to reload the same episode.
    private struct LoadContext {
        let detail: EpisodeDetail
        let rate: Float?
    }
    @ObservationIgnored private var recovery: LoadRecovery?
    @ObservationIgnored private var loadContext: LoadContext?
    @ObservationIgnored private var stallWatch = StallWatchdog()
    /// Seeks started and not yet finished or cancelled; the watchdog does not count while any is in flight.
    @ObservationIgnored private var seeksInFlight = 0
    /// Bumps on every load and stop, so a late retry for an older item does nothing.
    @ObservationIgnored private var loadToken = 0
    /// Whether the person wants the current item playing. A retry after a failure keeps it: a load
    /// that fails while paused comes back paused.
    @ObservationIgnored private var wantsPlay = false
    /// A network copy not yet timed, opened without precise timing and held paused until it is
    /// ready and its first frames have been read (`StartTiming`).
    private struct TimingCheck {
        let item: ObjectIdentifier
        let url: URL
        let recording: Recording
        let detail: EpisodeDetail
        let length: Double?
        var ready = false
        var frames: StartTiming.Frames?
    }
    @ObservationIgnored private var timingCheck: TimingCheck?
    /// Each network copy timed this session: true when it needs precise timing.
    @ObservationIgnored private var preciseByURL: [URL: Bool] = [:]
    /// Reads a byte range of a recording; the shared client by default, a fake in tests.
    @ObservationIgnored var readBytes: @Sendable (URL, ClosedRange<Int>) async -> Data? = { url, range in
        try? await APIClient.shared.bytes(of: url, range: range)
    }

    /// Puts one recording on the player, at `start`, playing at `rate` (nil: paused).
    private func open(_ recording: Recording, detail: EpisodeDetail, start: Double?, rate: Float?) {
        let source = Self.source(episodeID: detail.episode.id, recording: recording, localFile: localFile)
        isLocal = source.isLocal
        jumps += 1
        // Archive VBR MP3s often lack a Xing/VBRI table, so AVFoundation's quick
        // estimate scales the first frame's bitrate: a 23-minute file read as an
        // hour, and a seek past its real end stalled (iPhone 12, 2026-10-27).
        // Precise timing fixes that by reading the whole file before the first
        // sound, so only such a file gets it (`StartTiming`); a download reads
        // locally and keeps it.
        let known: Bool? = source.isLocal ? true : preciseByURL[source.url]
        let precise = known == true
        let asset = AVURLAsset(url: source.url, options: precise ? [AVURLAssetPreferPreciseDurationAndTimingKey: true] : [:])
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.audioTimePitchAlgorithm = .timeDomain
        let serial = ObjectIdentifier(playerItem).hashValue & 0xFFF
        diag("open #\(serial) \(source.isLocal ? "local" : "net")\(precise ? " precise" : "") rank \(recording.rank) start \(start.map { Int($0) } ?? -1) rate \(rate ?? 0)")
        itemStatusObservation = playerItem.observe(\.status, options: [.new]) { @Sendable [weak self] observed, _ in
            let status = observed.status.rawValue
            let detail = Self.diagnoses && observed.status == .failed ? Self.diagnosis(observed) : ""
            Task { @MainActor in self?.diag("status #\(serial) \(status) \(detail)") }
            let failed = observed.status == .failed
            let message = observed.error?.localizedDescription
            var problem = Connectivity.playerProblem(observed.error)
            if failed, Self.diagnoses { problem += " " + Self.diagnosis(observed) }
            let ready = observed.status == .readyToPlay
            let observedID = ObjectIdentifier(observed)
            Task { @MainActor in
                // A late report from an item a retry already replaced must not replace the retry.
                guard let current = self?.player.currentItem, ObjectIdentifier(current) == observedID else { return }
                if ready {
                    self?.recovery?.loaded()
                    self?.timingChecked(current)
                }
                guard failed else { return }
                print("[AudioPlayer] item failed: \(message ?? "unknown")")
                self?.itemFailed(problem)
            }
        }
        stallWatch.reset()
        seeksInFlight = 0
        wantsPlay = rate != nil
        timingCheck = known != nil ? nil : TimingCheck(
            item: ObjectIdentifier(playerItem), url: source.url, recording: recording, detail: detail,
            length: recording.lengthSeconds ?? detail.episode.lengthSeconds)
        if timingCheck != nil { readFrames(source.url, item: ObjectIdentifier(playerItem)) }
        player.replaceCurrentItem(with: playerItem)
        player.isMuted = isMuted
        player.volume = 1
        level(playerItem)
        if let start {
            elapsed = start
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        player.defaultRate = speed
        if let rate, timingCheck == nil { player.playImmediately(atRate: rate) } else { player.pause() }
        showTransport()
    }

    /// Reads the held copy's first frames alongside AVPlayer's own load.
    private func readFrames(_ url: URL, item: ObjectIdentifier) {
        let read = readBytes
        Task { [weak self] in
            let frames = await StartTiming.sniff(url, read: read)
            guard let self, self.timingCheck?.item == item else { return }
            self.timingCheck?.frames = frames
            self.decideTiming()
        }
    }

    /// The held item is ready to play.
    private func timingChecked(_ playerItem: AVPlayerItem) {
        guard timingCheck?.item == ObjectIdentifier(playerItem) else { return }
        timingCheck?.ready = true
        decideTiming()
    }

    /// Once the held item is ready and its frames are read: a constant-bitrate file or one with a
    /// table plays as it is; a variable-bitrate file with no table opens again with precise timing
    /// at the same place (unreadable frames fall back to the catalog length).
    private func decideTiming() {
        guard let check = timingCheck, check.ready, let frames = check.frames,
              let playerItem = player.currentItem, ObjectIdentifier(playerItem) == check.item else { return }
        timingCheck = nil
        let estimate = playerItem.duration.seconds
        let precise = StartTiming.needsPrecise(frames, estimated: estimate, catalog: check.length)
        preciseByURL[check.url] = precise
        diag("timing \(frames) estimate \(Self.whole(estimate)) of \(Self.whole(check.length ?? -1))\(precise ? ": precise" : "")")
        if precise {
            open(check.recording, detail: check.detail, start: elapsed > 0 ? elapsed : nil, rate: wantsPlay ? speed : nil)
            return
        }
        if wantsPlay { player.playImmediately(atRate: speed) }
        showTransport()
    }

    /// Whether the item stopped at its end (nothing followed it).
    private var isAtEnd: Bool {
        guard let current = player.currentItem else { return false }
        let end = current.duration.seconds
        return end.isFinite && end > 0 && player.currentTime().seconds >= end - 0.5
    }

    /// One retry after a jittered wait, then the next recording in rank order, then the error.
    private func itemFailed(_ problem: String, prematureEnd: Bool = false) {
        isPlaying = false
        guard var plan = recovery, let context = loadContext else {
            errorMessage = problem
            return
        }
        let step = prematureEnd ? plan.endedTooSoon(jitter: Double.random(in: 0.5...1.5)) : plan.failed(jitter: Double.random(in: 0.5...1.5))
        recovery = plan
        diag("step \(step) elapsed \(Self.whole(elapsed))")
        let token = loadToken
        switch step {
        case .giveUp:
            errorMessage = problem
        case .retry(let delay):
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, token == self.loadToken else { return }
                self.open(plan.current, detail: context.detail, start: self.elapsed > 0 ? self.elapsed : nil, rate: self.retryRate(context))
            }
        case .fallback(let next):
            item = Item(episode: context.detail.episode, recording: next, face: context.detail.face)
            duration = next.lengthSeconds ?? context.detail.episode.lengthSeconds
            open(next, detail: context.detail, start: elapsed > 0 ? elapsed : nil, rate: retryRate(context))
            publishNowPlaying()
        }
    }

    /// A retry plays only if the person still wants it playing, at the load's rate.
    private func retryRate(_ context: LoadContext) -> Float? {
        wantsPlay ? (context.rate ?? speed) : nil
    }

    /// Whether this item plays the queue after it (a Radio slot and a room do not).
    @ObservationIgnored private var playsQueue = false
    /// The arc read in flight for the current item, awaited at its end.
    @ObservationIgnored private var arcRead: Task<ArcPosition?, Never>?

    private func readArc(_ episodeID: String) {
        let read = Task { [weak self] () -> ArcPosition? in
            guard let self else { return nil }
            return await self.resolveArc(episodeID)
        }
        arcRead = read
        Task { [weak self] in
            let found = await read.value
            guard let self, self.item?.episode.id == episodeID else { return }
            self.arc = found
            self.refreshUpNext()
            guard let offer = PlaybackQueue.offer(found), let detail = await self.resolveDetail(offer),
                  self.item?.episode.id == episodeID else { return }
            self.nextStory = detail.episode
        }
    }

    /// Shows what plays next: the arc's next part, else the queue's head, resolved for its title.
    func refreshUpNext() {
        guard playsQueue, let current = item,
              let next = PlaybackQueue.after(current.episode.id, arc: arc, queued: queuedIDs()) else {
            upNext = []
            return
        }
        let episodeID = current.episode.id
        Task { [weak self] in
            guard let self, let detail = await self.resolveDetail(next.episodeID),
                  self.item?.episode.id == episodeID else { return }
            self.upNext = [detail.episode]
        }
    }

    /// Starts the next story the last part offers (Decision 067: offered, never started by itself).
    func playNextStory() {
        guard let story = nextStory else { return }
        Task { [weak self] in
            guard let self, let detail = await self.resolveDetail(story.id) else { return }
            self.play(detail)
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
        guard let current = item else { return }
        // A listener pressing Play after the timer stopped them is awake.
        if sleep.mode == .fired { sleep.cancel() }
        player.volume = 1
        activateSession()
        wantsPlay = true
        if timingCheck != nil {
            showTransport()
            return
        }
        // A load that failed for good (or was torn down) opens again at its place.
        if player.currentItem == nil || player.currentItem?.status == .failed, let context = loadContext {
            let recording = recovery?.current ?? current.recording
            errorMessage = nil
            recovery = LoadRecovery(chosen: recording, among: held == nil ? context.detail.recordings : [recording])
            open(recording, detail: context.detail, start: elapsed > 0 ? elapsed : nil, rate: speed)
            return
        }
        if isAtEnd { player.seek(to: .zero) }
        player.playImmediately(atRate: speed)
    }

    func pause() {
        wantsPlay = false
        if isFollowing {
            isHeld = true
            player.pause()
            onGuestHold(true)
            return
        }
        player.pause()
        showTransport()
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
        jumps += 1
        seeksInFlight += 1
        diag("seek \(Self.whole(seconds)) item \(player.currentItem?.status.rawValue ?? -1)")
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { @Sendable [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                self.seeksInFlight = max(0, self.seeksInFlight - 1)
                guard Self.diagnoses else { return }
                let now = self.player.currentTime().seconds
                self.diag("seeked \(Self.whole(seconds)) finished \(finished) now \(Self.whole(now))")
            }
        }
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
            wantsPlay = false
            player.pause()
            seekExactly(to: position)
        case .seek(let position, let play):
            seekExactly(to: position)
            if play {
                wantsPlay = true
                player.playImmediately(atRate: rate)
            }
        case .play(let position, let playRate):
            wantsPlay = true
            seekExactly(to: position)
            player.playImmediately(atRate: Float(playRate))
        case .rate(let nudged):
            if player.rate != 0 { player.rate = Float(nudged) }
        }
    }

    /// Stops and forgets the current item (the end of a door, or Close).
    func stop() {
        loadToken += 1
        recovery = nil
        wantsPlay = false
        timingCheck = nil
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
        elapsed = LoadRecovery.clock(reading: seconds, itemFailed: player.currentItem?.status == .failed, shown: elapsed)
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        if Self.diagnoses {
            diagLine = diagnosisLine()
            if Int(now.timeIntervalSince1970) % 5 == 0 { print("[PlaybackDiag] clock \(Self.whole(seconds)) \(diagLine ?? "")") }
        }
        watchForStall(now: now)

        if sleep.mode != .off {
            clock = now
            let remaining = duration.map { max(0, $0 - elapsed) / Double(max(speed, 0.01)) }
            let output = sleep.tick(now: now, remainingInEpisode: remaining)
            player.volume = output.volume
            if output.shouldPause {
                wantsPlay = false
                player.pause()
                saveProgress()
                onTransport(.sleepFired)
            }
        }
        if isPlaying, PlayerNumbers.isSaveDue(lastSaved: lastSaved, now: now) { saveProgress() }
    }

    /// A load that wants data, gains no bytes, and does not move for `StallWatchdog.limit` is a failed load.
    /// Signals: `loadedTimeRanges` and the access log's bytes (growth), `timeControlStatus` (wanting data).
    private func watchForStall(now: Date) {
        guard let current = player.currentItem, !isLocal, current.status != .failed else {
            stallWatch.reset()
            return
        }
        let loaded = current.loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        let transferred = current.accessLog()?.events.reduce(0.0) { $0 + Double(max($1.numberOfBytesTransferred, 0)) } ?? 0
        let verdict = stallWatch.observe(
            now: now.timeIntervalSinceReferenceDate, wantsData: player.timeControlStatus != .paused || holdsStart,
            bytes: loaded + transferred, position: elapsed, seeking: seeksInFlight > 0)
        guard verdict == .stalled else { return }
        if Self.diagnoses { print("[AudioPlayer] watchdog: stalled \(Int(StallWatchdog.limit)) s, no bytes, no movement; recovering. \(diagnosisLine()) bytes \(Int(transferred))") }
        diag("watchdog stalled, recovering")
        stallWatch.reset()
        player.pause()
        itemFailed(Connectivity.playerProblem(nil))
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        diag("tcs \(status.rawValue) \(player.reasonForWaitingToPlay?.rawValue ?? "")")
        if status == .paused, !holdsStart { saveProgress() }
        showTransport()
        onRoomChange()
    }

    /// A network item held for its timing check while the person wants it playing: it shows as
    /// starting, not paused.
    private var holdsStart: Bool { timingCheck != nil && wantsPlay }

    /// The play and buffering state the views and Now Playing show.
    private func showTransport() {
        let status = player.timeControlStatus
        isPlaying = status != .paused || holdsStart
        isBuffering = status == .waitingToPlayAtSpecifiedRate || holdsStart
        publishNowPlaying()
    }

    private func itemDidEnd() {
        guard let current = item else { return }
        diag("ended at \(Self.whole(player.currentTime().seconds)) of \(Self.whole(player.currentItem?.duration.seconds ?? -1))")
        let known = recovery?.current.lengthSeconds ?? loadContext?.detail.episode.lengthSeconds
        if LoadRecovery.endedTooSoon(position: player.currentTime().seconds, expected: known) {
            itemFailed(Connectivity.playerProblem(nil), prematureEnd: true)
            return
        }
        history.markFinished(current.episode.id, duration: duration)
        // R20: once the timer fires (or it was set for this episode), nothing
        // starts the next one. Decision 067: an arc's next part plays next;
        // otherwise only what the person queued, whatever its series; with
        // nothing up next, playback stops (the next story stays offered).
        let mayContinue = sleep.episodeDidEnd()
        onTransport(mayContinue ? .ended : .sleepFired)
        let episodeID = current.episode.id
        guard mayContinue, playsQueue else {
            stopAtEnd()
            return
        }
        let read = arcRead
        Task { [weak self] in
            let found = await read?.value
            guard let self, self.item?.episode.id == episodeID else { return }
            guard let next = PlaybackQueue.after(episodeID, arc: found, queued: self.queuedIDs()),
                  let detail = await self.resolveDetail(next.episodeID),
                  self.item?.episode.id == episodeID else {
                self.stopAtEnd()
                return
            }
            self.load(detail, recording: nil, from: nil, queue: true, rate: self.speed)
        }
    }

    private func stopAtEnd() {
        upNext = []
        isPlaying = false
        publishNowPlaying()
    }

    private func saveProgress() {
        guard let current = item, elapsed > 0 else { return }
        lastSaved = Date()
        history.record(current.episode.id, position: elapsed, duration: duration)
    }

    /// APP_PLAYBACK_DIAG=1 (DEBUG only): a failed item's errors go on screen,
    /// so a device screenshot carries what the console cannot.
    nonisolated static let diagnoses: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["APP_PLAYBACK_DIAG"] == "1"
        #else
        false
        #endif
    }()

    @ObservationIgnored private var diagEvents: [String] = []
    private func diag(_ event: String) {
        guard Self.diagnoses else { return }
        let line = String(format: "%.1f ", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)) + event
        print("[PlaybackDiag] \(line)")
        diagEvents.append(line)
        if diagEvents.count > 10 { diagEvents.removeFirst() }
    }

    private func diagnosisLine() -> String {
        let status: String
        switch player.timeControlStatus {
        case .paused: status = "paused"
        case .playing: status = "playing"
        case .waitingToPlayAtSpecifiedRate: status = "waiting(\(player.reasonForWaitingToPlay?.rawValue ?? "-"))"
        @unknown default: status = "?"
        }
        guard let item = player.currentItem else { return "diag \(status) no item" }
        let ranges = item.loadedTimeRanges.map { r -> String in
            let t = r.timeRangeValue
            return "\(Self.whole(t.start.seconds))+\(Self.whole(t.duration.seconds))"
        }.joined(separator: ",")
        return diagEvents.joined(separator: " | ") + " || diag \(status) rate \(player.rate) item \(item.status.rawValue) keepUp \(item.isPlaybackLikelyToKeepUp) empty \(item.isPlaybackBufferEmpty) t \(Self.whole(item.currentTime().seconds)) dur \(Self.whole(item.duration.seconds)) loaded [\(ranges)]"
    }

    /// A clock reading for a diagnostic line: an unknown time (NaN, indefinite) is -1, never a trap.
    nonisolated static func whole(_ seconds: Double) -> Int { seconds.isFinite ? Int(seconds) : -1 }

    nonisolated static func diagnosis(_ item: AVPlayerItem) -> String {
        var parts: [String] = []
        var next = item.error as NSError?
        while let e = next {
            parts.append("\(e.domain) \(e.code)")
            next = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        if let event = item.errorLog()?.events.last {
            parts.append("log \(event.errorDomain) \(event.errorStatusCode) \(event.errorComment ?? "") \(event.uri ?? "")")
        }
        parts.append("at \(whole(item.currentTime().seconds))s")
        return "[" + parts.joined(separator: "; ") + "]"
    }

    /// What the player opens: the finished download of this recording when
    /// the device has one, else the network copy.
    nonisolated static func source(episodeID: String, recording: Recording,
                                   localFile: (String, Recording) -> URL?) -> (url: URL, isLocal: Bool) {
        if let local = localFile(episodeID, recording) { return (local, true) }
        return (recording.url, false)
    }

    // MARK: - Now Playing and remote commands

    /// The lock screen's picture is the one Now Playing draws (Decision 069, D3-4):
    /// the show's picture, else its star's, at Commons' 500 step, else the episode's own label.
    private func loadArtwork(for item: Item?) {
        artwork = nil
        guard let item else { return }
        let id = item.episode.id
        Task { [weak self] in
            var image: CGImage?
            if let art = item.episode.seriesWindowArt ?? item.face?.art,
               let (data, response) = try? await URLSession.shared.data(from: art.url(pixels: 500)),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let source = CGImageSourceCreateWithData(data as CFData, nil) {
                image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                // The system shows a square: hand it the one centered on the published face (R11a).
                if let whole = image, let cut = art.squareCrop(width: whole.width, height: whole.height) {
                    image = whole.cropping(to: CGRect(x: cut.x, y: cut.y, width: cut.side, height: cut.side)) ?? whole
                }
            }
            guard let self, self.item?.episode.id == id else { return }
            let drawn: CGImage? = if let image { image } else { await self.cardImage(item.episode) }
            guard let image = drawn else { return }
            self.artwork = Self.mediaArtwork(image)
            self.publishNowPlaying()
        }
    }

    /// MediaPlayer calls the handler on its own queue: a main-actor closure
    /// traps there (the 1.0.67 crash on play), so neither may be isolated.
    nonisolated private static func mediaArtwork(_ cg: CGImage) -> MPMediaItemArtwork {
        let size = CGSize(width: cg.width, height: cg.height)
        #if os(macOS)
        let image = NSImage(cgImage: cg, size: size)
        #else
        let image = UIImage(cgImage: cg)
        #endif
        return MPMediaItemArtwork(boundsSize: size) { @Sendable _ in image }
    }

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
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
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
