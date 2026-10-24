import Foundation
import Observation

/// What the player tells whoever listens live (WEB-DESIGN §4.9, R14).
nonisolated enum TransportEvent: Equatable, Sendable {
    /// An episode was loaded, by anyone.
    case loaded(String)
    /// The listener paused.
    case paused
    /// The recording played to its end and nothing stopped it.
    case ended
    /// The sleep timer fired, by its clock or at the episode's end.
    case sleepFired
    /// The player was stopped and emptied.
    case stopped
}

/// Listening live as a state machine, the web's `liveTick` and its
/// `Player.onChange` handler: the slot on the air plays from where the clock
/// stands; when its recording ends, the next surviving slot plays when its own
/// time comes. A pause, another episode, or the sleep timer ends it, and so
/// does the evening's last slot: nothing plays after (R14).
nonisolated struct LiveListening: Sendable {
    enum Action: Equatable, Sendable {
        case none
        case play(episodeID: String, at: Double)
        case stop
    }

    let slots: [RadioSlot]
    /// Episodes the catalog resolved, with their default copy's length. A slot
    /// whose episode is absent here never plays.
    let lengths: [String: Double?]
    /// The `utcStart` of the slot loaded, nil until one is.
    private(set) var playing: Date?
    /// True until a slot is loaded, and again once its recording ends.
    private(set) var waiting = true
    private(set) var episodeID: String?
    private(set) var isOver = false

    init(slots: [RadioSlot], lengths: [String: Double?]) {
        self.slots = slots
        self.lengths = lengths
    }

    /// Called once a second while live.
    mutating func tick(now: Date) -> Action {
        guard !isOver else { return .none }
        let where_ = RadioClock.onAir(slots, at: now)
        if where_.phase == .after { return end() }
        guard let index = where_.index else { return .none }
        let slot = slots[index]
        guard let episode = slot.playableEpisode, let length = lengths[episode.id] else { return .none }
        if playing == slot.utcStart { return .none }
        if playing != nil && !waiting { return .none }   // the slot before is still playing
        guard let at = RadioClock.liveOffset(slot, recordingLength: length, at: now) else { return .none }
        playing = slot.utcStart
        waiting = false
        episodeID = episode.id
        return .play(episodeID: episode.id, at: at)
    }

    /// Called with each transport event. Returns `.stop` when listening ends.
    mutating func handle(_ event: TransportEvent) -> Action {
        guard !isOver, playing != nil else { return .none }
        switch event {
        case let .loaded(id): return id == episodeID ? .none : end()
        case .ended:
            waiting = true
            return .none
        case .paused, .sleepFired, .stopped: return end()
        }
    }

    private mutating func end() -> Action {
        isOver = true
        return .stop
    }
}

/// The app's one live listener: owns the clock loop and drives the one
/// `AudioPlayer` through `LiveListening`. Views read `day` to mark Listening live.
@Observable
final class LiveRadio {
    /// The evening listened to live, nil when not listening to one.
    private(set) var day: TonightDay?
    /// The genre station listened to live (its genre), nil when not.
    private(set) var station: String?

    @ObservationIgnored private var listening: LiveListening?
    @ObservationIgnored private var details: [String: EpisodeDetail] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let player: AudioPlayer
    @ObservationIgnored var now: () -> Date = Date.init

    init(player: AudioPlayer) {
        self.player = player
    }

    func tuneIn(_ day: TonightDay, details: [String: EpisodeDetail]) {
        stop()
        self.day = day
        start(day.slots, details: details)
    }

    /// A genre station: the slot on now and those within the next hours
    /// (`StationClock.ahead`), on the same clock and rules as an evening.
    func tuneIn(station: Station, slots: [RadioSlot], details: [String: EpisodeDetail]) {
        stop()
        self.station = station.genre
        start(slots, details: details)
    }

    private func start(_ slots: [RadioSlot], details: [String: EpisodeDetail]) {
        self.details = details
        listening = LiveListening(slots: slots, lengths: details.mapValues {
            $0.defaultRecording?.lengthSeconds ?? $0.episode.lengthSeconds
        })
        tick()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
                self?.tick()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        listening = nil
        day = nil
        station = nil
    }

    func handle(_ event: TransportEvent) {
        guard var state = listening else { return }
        let action = state.handle(event)
        listening = state
        apply(action)
    }

    private func tick() {
        guard var state = listening else { return }
        let action = state.tick(now: now())
        listening = state
        apply(action)
    }

    private func apply(_ action: LiveListening.Action) {
        switch action {
        case .none: break
        case .stop: stop()
        case let .play(id, at):
            guard let detail = details[id] else { return }
            player.play(detail, from: at, queue: false)
        }
    }
}
