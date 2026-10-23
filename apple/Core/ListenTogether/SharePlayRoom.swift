import Combine
import Foundation
import GroupActivities
import Observation

/// The SharePlay activity: the episode and the HOST'S COPY (Archive Watch
/// Decision 143), so every member plays the same recording.
nonisolated struct ListenTogether: GroupActivity {
    static let activityIdentifier = "app.eardrama.listen-together"

    let episodeID: String
    let title: String
    let series: String
    let copy: HostCopy

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = title
        meta.subtitle = series
        meta.type = .listenTogether
        meta.fallbackURL = SiteLinks.episode(episodeID)
        return meta
    }
}

/// The host's roster, in its arrival order: what every member hands off by.
nonisolated struct RoomRoster: Codable, Equatable, Sendable {
    var v = RoomProtocol.version
    var host: String
    var members: [RoomMember]
}

/// One clock sample, asked of the host (Cristian's algorithm needs a round trip).
nonisolated struct ClockProbe: Codable, Equatable, Sendable {
    var v = RoomProtocol.version
    var t0: Double
}

nonisolated struct ClockReply: Codable, Equatable, Sendable {
    var v = RoomProtocol.version
    var t0: Double
    var serverTime: Double

    enum CodingKeys: String, CodingKey {
        case v, t0
        case serverTime = "server_time"
    }
}

extension HostCopy {
    /// The copy inside an archive.org download address, or nil for any other address.
    nonisolated init?(downloadURL url: URL) {
        let parts = url.pathComponents
        guard url.host == "archive.org", parts.count >= 4, parts[1] == "download",
              let copy = RoomProtocol.cleanCopy(archiveID: parts[2], file: parts[3...].joined(separator: "/"))
        else { return nil }
        self = copy
    }

    /// Every member builds the address itself (docs/WORKER.md "The host's copy, always").
    nonisolated var downloadURL: URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let segments = ([archiveID] + file.split(separator: "/").map(String.init))
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
        return URL(string: "https://archive.org/download/" + segments.joined(separator: "/"))
    }
}

/// Listen Together on Apple devices: a thin SharePlay transport over
/// RoomProtocol (iOS-DESIGN §5.8). The room message, the roster, and the clock
/// samples ride a reliable GroupSessionMessenger; the host's device is the
/// room's clock, as the Worker is for the web and Android.
///
/// Why not AVPlayer's playbackCoordinator: it lets every participant drive,
/// suspends the whole group for one stalled member, and syncs whatever item
/// each player holds. The protocol says the opposite on all three: only the
/// host drives, a stalled member catches up while the room plays on, and
/// every member plays the host's copy.
@Observable
final class SharePlayRoom {
    enum ShareOutcome { case started, needsCall, cancelled }

    /// A FaceTime call or Messages group is live, so SharePlay can start without a sheet.
    private(set) var isEligible = false
    private(set) var isActive = false
    private(set) var isHost = false
    private(set) var memberCount = 0

    @ObservationIgnored private let player: AudioPlayer
    @ObservationIgnored private let resolveDetail: (String) async -> EpisodeDetail?
    @ObservationIgnored private let observer = GroupStateObserver()
    @ObservationIgnored private var listeners: [Task<Void, Never>] = []
    @ObservationIgnored private var session: GroupSession<ListenTogether>?
    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var sessionTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var participants: Set<Participant> = []
    @ObservationIgnored private var localID: String?
    @ObservationIgnored private var ledger = RoomLedger()
    /// This device started an activity for this episode at this time; the
    /// session that comes back for it makes this device the host.
    @ObservationIgnored private var startedHere: (episodeID: String, at: Date)?
    @ObservationIgnored private var samples: [ClockSample] = []
    @ObservationIgnored private var roughOffset: Double?
    @ObservationIgnored private var loadedCopy: RoomState?
    @ObservationIgnored private var loading = false

    init(player: AudioPlayer, resolveDetail: @escaping (String) async -> EpisodeDetail?) {
        self.player = player
        self.resolveDetail = resolveDetail
        player.onRoomChange = { [weak self] in self?.hostPlayerChanged() }
        player.onLeaveRoom = { [weak self] in self?.leave() }
    }

    private static func now() -> Double { Date().timeIntervalSince1970 * 1000 }

    /// Called at launch, never from a view: "Move to Apple TV" cold-launches
    /// the app and hands the session over before any data has loaded.
    func start() {
        guard listeners.isEmpty else { return }
        listeners.append(Task { [weak self] in
            for await session in ListenTogether.sessions() { self?.configure(session) }
        })
        listeners.append(Task { [weak self, observer] in
            for await eligible in observer.$isEligibleForGroupSession.values { self?.isEligible = eligible }
        })
    }

    // MARK: - Starting

    private func activity() -> ListenTogether? {
        guard let item = player.item, let copy = HostCopy(downloadURL: item.recording.url) else { return nil }
        return ListenTogether(episodeID: item.episode.id, title: item.episode.displayTitle,
                              series: item.episode.seriesName, copy: copy)
    }

    /// Starts SharePlay in a live call. Outside one this is `.needsCall`, an
    /// ordinary answer: the caller offers the system's sheet, which places the
    /// call. Nothing here ever plays alone in place of starting.
    func share() async -> ShareOutcome {
        guard let activity = activity() else { return .cancelled }
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            startedHere = (activity.episodeID, Date())
            do {
                _ = try await activity.activate()
                return .started
            } catch {
                print("[SharePlay] activate failed: \(error.localizedDescription)")
                startedHere = nil
                return .cancelled
            }
        case .activationDisabled:
            return .needsCall
        case .cancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// The activity for the system's sharing sheet, marking this device as the
    /// one that started it.
    func activityForSheet() -> ListenTogether? {
        guard let activity = activity() else { return nil }
        startedHere = (activity.episodeID, Date())
        return activity
    }

    func sheetDidNotShare() { startedHere = nil }

    // MARK: - The session

    private func configure(_ newSession: GroupSession<ListenTogether>) {
        cleanUp()
        let messenger = GroupSessionMessenger(session: newSession, deliveryMode: .reliable)
        session = newSession
        self.messenger = messenger
        localID = newSession.localParticipant.id.uuidString
        ledger = RoomLedger()
        if let started = startedHere, started.episodeID == newSession.activity.episodeID,
           Date().timeIntervalSince(started.at) < 300 {
            ledger.host = localID
        }
        startedHere = nil
        isActive = true
        refreshRoles()

        sessionTasks = [
            Task { [weak self] in
                for await state in newSession.$state.values {
                    if case .invalidated = state { self?.cleanUp() }
                }
            },
            Task { [weak self] in
                for await present in newSession.$activeParticipants.values { self?.presenceChanged(present) }
            },
            Task { [weak self] in
                for await (message, context) in messenger.messages(of: RoomSnapshot.self) {
                    self?.received(message, from: context.source)
                }
            },
            Task { [weak self] in
                for await (message, context) in messenger.messages(of: RoomRoster.self) {
                    self?.received(message, from: context.source)
                }
            },
            Task { [weak self] in
                for await (message, context) in messenger.messages(of: ClockProbe.self) {
                    self?.received(message, from: context.source)
                }
            },
            Task { [weak self] in
                for await (message, _) in messenger.messages(of: ClockReply.self) {
                    self?.received(message)
                }
            },
            // Once a second: a member corrects its drift; the host republishes
            // when its own player has wandered from what it last said (a
            // stall, or a resume position that landed after the first write).
            Task { [weak self] in
                while !Task.isCancelled {
                    guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
                    guard let self else { return }
                    if self.isHost { self.hostPlayerChanged() } else { self.follow() }
                }
            },
        ]
        newSession.join()
    }

    /// Leaves the room; the others carry on, and the next host takes over.
    func leave() {
        session?.leave()
        cleanUp()
    }

    private func cleanUp() {
        sessionTasks.forEach { $0.cancel() }
        sessionTasks = []
        session = nil
        messenger = nil
        participants = []
        ledger = RoomLedger()
        samples = []
        roughOffset = nil
        loadedCopy = nil
        loading = false
        isActive = false
        memberCount = 0
        refreshRoles()
    }

    private func refreshRoles() {
        isHost = isActive && ledger.host != nil && ledger.host == localID
        player.setFollowing(isActive && !isHost)
    }

    private func participant(_ id: String?) -> Participant? {
        participants.first { $0.id.uuidString == id }
    }

    private func presenceChanged(_ present: Set<Participant>) {
        participants = present
        memberCount = present.count
        let ids = Set(present.map { $0.id.uuidString })
        if let newHost = ledger.presenceChanged(present: ids, now: Self.now(), admitting: isHost) {
            // Handoff: the new host's device is the room's clock from now on.
            samples = []
            roughOffset = nil
            if newHost == localID { takeOver() }
        }
        refreshRoles()
        if isHost {
            sendRoster()
            sendSnapshot()
        }
    }

    /// This device became host: the room goes on from where its player is.
    private func takeOver() {
        guard let id = localID else { return }
        refreshRoles()
        let reading = player.roomReading
        _ = ledger.propose(StateInput(position: reading.position, playing: ledger.state?.playing ?? reading.playing),
                           from: id, now: Self.now())
        if player.isPlaying != (ledger.state?.playing ?? false) {
            player.togglePlayPause()
        }
    }

    // MARK: - Host

    private func hostPlayerChanged() {
        guard isHost, let id = localID, let item = player.item,
              let copy = HostCopy(downloadURL: item.recording.url) else { return }
        let reading = player.roomReading
        let rate = Double(player.speed)
        if let state = ledger.state, state.episodeID == item.episode.id, state.archiveID == copy.archiveID,
           state.file == copy.file, state.playing == reading.playing, state.rate == rate,
           abs(RoomProtocol.expectedPosition(state.publicState, now: Self.now()) - reading.position) < 0.5 {
            return
        }
        let episodeChanged = ledger.state?.episodeID != item.episode.id
        let input = StateInput(episodeID: item.episode.id, archiveID: copy.archiveID, file: copy.file,
                               position: reading.position, playing: reading.playing, rate: rate)
        guard case .success = ledger.propose(input, from: id, now: Self.now()) else { return }
        if episodeChanged, let activity = activity() { session?.activity = activity }
        sendSnapshot()
    }

    private func sendSnapshot() {
        guard isHost, let messenger, let state = ledger.state else { return }
        let snapshot = RoomSnapshot(code: "", role: "guest", members: memberCount, state: state, serverTime: Self.now())
        Task { try? await messenger.send(snapshot, to: .all) }
    }

    private func sendRoster() {
        guard isHost, let messenger, let host = ledger.host else { return }
        let roster = RoomRoster(host: host, members: ledger.members)
        Task { try? await messenger.send(roster, to: .all) }
    }

    private func received(_ probe: ClockProbe, from source: Participant) {
        guard isHost, let messenger else { return }
        let reply = ClockReply(t0: probe.t0, serverTime: Self.now())
        Task { try? await messenger.send(reply, to: .only(source)) }
    }

    // MARK: - Member

    private func received(_ roster: RoomRoster, from source: Participant) {
        let sender = source.id.uuidString
        // A host no longer here cannot hold the room against its successor.
        if let host = ledger.host, participant(host) == nil { ledger.host = nil }
        guard roster.v == RoomProtocol.version,
              ledger.receive(roster: roster.members, host: roster.host, from: sender) else { return }
        refreshRoles()
        if samples.isEmpty { askTheClock() }
    }

    private func received(_ snapshot: RoomSnapshot, from source: Participant) {
        guard !isHost, ledger.receive(snapshot, from: source.id.uuidString) else { return }
        if samples.isEmpty { roughOffset = snapshot.serverTime - Self.now() }
        if samples.count < 4 { askTheClock() }
        follow()
    }

    private func received(_ reply: ClockReply) {
        guard !isHost, reply.v == RoomProtocol.version else { return }
        samples.append(ClockSample(t0: reply.t0, serverTime: reply.serverTime, t1: Self.now()))
        samples = Array(samples.suffix(8))
    }

    private func askTheClock() {
        guard let messenger, let host = participant(ledger.host) else { return }
        let probe = ClockProbe(t0: Self.now())
        Task { try? await messenger.send(probe, to: .only(host)) }
    }

    private var serverNow: Double {
        Self.now() + (RoomProtocol.clockOffset(samples) ?? roughOffset ?? 0)
    }

    /// Plays the host's copy where the host is, then keeps it there by the
    /// protocol's correction. A stalled member is left to buffer, then catches up.
    private func follow() {
        guard isActive, !isHost, let state = ledger.state?.publicState else { return }
        if loadedCopy?.episodeID != state.episodeID || loadedCopy?.copy != state.copy {
            load(state)
            return
        }
        guard !loading, !player.isBuffering, player.item != nil else { return }
        player.apply(RoomProtocol.correction(state, serverNow: serverNow, player: player.roomReading),
                     hostRate: state.rate)
    }

    private func load(_ state: RoomState) {
        guard !loading else { return }
        loading = true
        loadedCopy = state
        Task { [weak self] in
            guard let self else { return }
            defer { self.loading = false }
            guard let detail = await self.resolveDetail(state.episodeID), let url = state.copy.downloadURL else {
                print("[SharePlay] the host's episode \(state.episodeID) is not in this catalog")
                return
            }
            guard self.isActive, !self.isHost else { return }
            let recording = detail.recordings.first { HostCopy(downloadURL: $0.url) == state.copy }
                ?? Recording(rank: 0, archiveID: state.archiveID, url: url, format: nil, kbps: nil,
                             lengthSeconds: nil, variant: nil, partial: false)
            let current = self.ledger.state?.publicState ?? state
            self.player.follow(detail, recording: recording,
                               at: RoomProtocol.expectedPosition(current, now: self.serverNow),
                               playing: current.playing, rate: Float(current.rate))
        }
    }
}
