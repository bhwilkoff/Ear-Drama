// Listen Together's protocol and arbiter, ported from worker/src/room-protocol.js.
//
// PURE, like the file it ports: no import, no network, no clock, no store.
// Every function takes `now` (milliseconds on the room's clock) and returns a
// value. SharePlay (SharePlayRoom.swift) is one transport over it; the
// Worker's rooms are another, and every rule lives here and there, never in a
// transport. RoomProtocolTests holds both to the same golden cases
// (apple/Tests/Fixtures/listen-together-golden.json, made from the JS).
//
// Not ported: the six-character codes and the poll interval, which belong to
// the polling transport. A SharePlay session is found through the call and
// pushes its messages, so it has neither.

nonisolated enum RoomProtocol {
    static let version = 1
    static let maxMembers = 20
    /// A member not heard from for this long has left.
    static let memberGoneMS: Double = 2 * 60 * 1000
    static let maxPositionS: Double = 7 * 86400

    /// Decision 062's speeds; a room carries the host's chosen speed, never a nudge.
    static var speeds: [Double] { PlayerNumbers.speeds.map(Double.init) }

    /// Drift correction (Archive Watch SHAREPLAY §11.3). Seconds.
    enum Drift {
        static let ignoreBelow = 0.15
        static let seekAbove = 2.0
        static let nudge = 0.03
    }

    // MARK: - Validation

    /// The catalog's episode ids: printable, bounded.
    static func cleanEpisodeID(_ v: String) -> String? {
        guard (1...200).contains(v.utf16.count), !v.unicodeScalars.contains(where: isControl) else { return nil }
        return v
    }

    /// THE HOST'S COPY: an archive.org identifier and a file inside it, never a
    /// URL, so a room can never point a member's player at another host.
    static func cleanCopy(archiveID: String, file: String) -> HostCopy? {
        guard (1...100).contains(archiveID.utf16.count),
              archiveID.unicodeScalars.allSatisfy(isArchiveIDScalar) else { return nil }
        guard (1...400).contains(file.utf16.count), !file.hasPrefix("/"), !file.contains("\\"),
              !file.unicodeScalars.contains(where: isControl) else { return nil }
        let parts = file.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { return nil }
        return HostCopy(archiveID: archiveID, file: file)
    }

    private static func isControl(_ s: Unicode.Scalar) -> Bool { s.value < 0x20 || s.value == 0x7f }

    private static func isArchiveIDScalar(_ s: Unicode.Scalar) -> Bool {
        switch s {
        case "A"..."Z", "a"..."z", "0"..."9", ".", "_", "-": true
        default: false
        }
    }

    private static func position(_ v: Double) -> Double? {
        v.isFinite && v >= 0 && v <= maxPositionS ? v : nil
    }

    // MARK: - The arbiter

    /// The host proposes; this returns the next state or a refusal (the JS
    /// `applyHostState`, with its refusal words). `updatedAt` is the room
    /// clock's `now`, never a member's, and the generation is bumped here.
    /// A new episode must name its copy. `current` is nil for a new room.
    static func applyHostState(_ current: HostState?, _ input: StateInput, now: Double) -> Result<HostState, RoomRefusal> {
        var next = current ?? HostState(episodeID: nil, archiveID: nil, file: nil, position: 0,
                                        playing: false, rate: 1, updatedAt: 0, generation: 0)
        if let raw = input.episodeID {
            guard let id = cleanEpisodeID(raw) else { return .failure(.init("bad episode_id")) }
            if id != next.episodeID && (input.archiveID == nil || input.file == nil) {
                return .failure(.init("a new episode needs its archive_id and file"))
            }
            next.episodeID = id
        }
        if input.archiveID != nil || input.file != nil {
            guard let archiveID = input.archiveID, let file = input.file,
                  let copy = cleanCopy(archiveID: archiveID, file: file) else { return .failure(.init("bad copy")) }
            next.archiveID = copy.archiveID
            next.file = copy.file
        }
        guard next.episodeID != nil, next.archiveID != nil else {
            return .failure(.init("episode_id, archive_id and file are required"))
        }
        if let raw = input.position {
            guard let p = position(raw) else { return .failure(.init("bad position")) }
            next.position = p
        } else if let current {
            next.position = expectedPosition(current.publicState, now: now)
        }
        if let playing = input.playing { next.playing = playing }
        if let rate = input.rate {
            guard speeds.contains(rate) else { return .failure(.init("rate must be one of 0.75, 1, 1.25, 1.5, 2")) }
            next.rate = rate
        }
        next.updatedAt = now
        next.generation = (current?.generation ?? 0) + 1
        return .success(next)
    }

    /// Where the host's player is at room time `now`, extrapolated from the last state.
    static func expectedPosition(_ state: RoomState, now: Double) -> Double {
        guard state.playing else { return state.position }
        return min(maxPositionS, state.position + (now - state.updatedAt) / 1000 * state.rate)
    }

    // MARK: - Members and handoff

    static func liveMembers(_ members: [RoomMember], now: Double) -> [RoomMember] {
        members.filter { now - $0.seenAt <= memberGoneMS }
    }

    /// HOST HANDOFF: the live member in the room longest takes over, ties by
    /// id (code-unit order, as JS compares strings), so every device picks the
    /// same one. Nil means nobody is left.
    static func nextHost(_ members: [RoomMember], leaving: String?, now: Double) -> String? {
        liveMembers(members, now: now)
            .filter { $0.id != leaving }
            .sorted { a, b in
                a.joinedAt != b.joinedAt ? a.joinedAt < b.joinedAt : Array(a.id.utf16).lexicographicallyPrecedes(b.id.utf16)
            }
            .first?.id
    }

    // MARK: - Clock and drift

    /// Cristian's algorithm: the sample with the smallest round trip wins; an
    /// average would throw the bound away. The offset to ADD to the local clock.
    static func clockOffset(_ samples: [ClockSample]) -> Double? {
        var best: (rtt: Double, offset: Double)?
        for s in samples {
            let rtt = s.t1 - s.t0
            guard rtt >= 0 else { continue }
            if best == nil || rtt < best!.rtt { best = (rtt, s.serverTime - (s.t0 + s.t1) / 2) }
        }
        return best?.offset
    }

    /// DRIFT CORRECTION, as a value the player applies silently:
    /// play/pause follows the host at once; under 150 ms nothing; 150 ms to
    /// 2 s the host's rate x 0.97 or 1.03; over 2 s a seek. A stalled member
    /// catches up; the room never waits.
    static func correction(_ state: RoomState, serverNow: Double, player: PlayerReading) -> Correction {
        let target = expectedPosition(state, now: serverNow)
        guard state.playing else {
            if player.playing { return .pause(position: target) }
            return abs(player.position - target) > Drift.ignoreBelow ? .seek(position: target, play: false) : .none
        }
        let off = player.position - target
        let far = abs(off)
        if far > Drift.seekAbove { return .seek(position: target, play: true) }
        if !player.playing { return .play(position: target, rate: state.rate) }
        if far < Drift.ignoreBelow { return .rate(state.rate) }
        return .rate(state.rate * (off > 0 ? 1 - Drift.nudge : 1 + Drift.nudge))
    }
}

// MARK: - The room's values, in the room message's own field names

nonisolated struct HostCopy: Codable, Equatable, Sendable {
    let archiveID: String
    let file: String

    enum CodingKeys: String, CodingKey {
        case archiveID = "archive_id"
        case file
    }
}

/// What a host proposes; a nil field keeps the current value.
nonisolated struct StateInput: Equatable, Sendable {
    var episodeID: String?
    var archiveID: String?
    var file: String?
    var position: Double?
    var playing: Bool?
    var rate: Double?
}

nonisolated struct RoomRefusal: Error, Equatable, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
}

/// The arbiter's state: the public state plus the generation.
nonisolated struct HostState: Equatable, Sendable {
    var episodeID: String?
    var archiveID: String?
    var file: String?
    var position: Double
    var playing: Bool
    var rate: Double
    var updatedAt: Double
    var generation: Int

    var publicState: RoomState {
        RoomState(episodeID: episodeID ?? "", archiveID: archiveID ?? "", file: file ?? "",
                  position: position, playing: playing, rate: rate, updatedAt: updatedAt)
    }
}

/// `state` in the room message (docs/WORKER.md "The room message").
nonisolated struct RoomState: Codable, Equatable, Sendable {
    var episodeID: String
    var archiveID: String
    var file: String
    var position: Double
    var playing: Bool
    var rate: Double
    var updatedAt: Double

    var copy: HostCopy { HostCopy(archiveID: archiveID, file: file) }

    enum CodingKeys: String, CodingKey {
        case episodeID = "episode_id"
        case archiveID = "archive_id"
        case file, position, playing, rate
        case updatedAt = "updated_at"
    }
}

/// The room message: what a Worker read answers and what SharePlay carries.
nonisolated struct RoomSnapshot: Codable, Equatable, Sendable {
    var v: Int
    var code: String
    var role: String
    var members: Int
    var generation: Int
    var state: RoomState
    var serverTime: Double

    enum CodingKeys: String, CodingKey {
        case v, code, role, members, generation, state
        case serverTime = "server_time"
    }

    init(code: String, role: String, members: Int, state: HostState, serverTime: Double) {
        self.v = RoomProtocol.version
        self.code = code
        self.role = role
        self.members = members
        self.generation = state.generation
        self.state = state.publicState
        self.serverTime = serverTime
    }
}

/// A member is `{ id, joined_at, seen_at }`, as in the Worker.
nonisolated struct RoomMember: Codable, Equatable, Sendable {
    var id: String
    var joinedAt: Double
    var seenAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case joinedAt = "joined_at"
        case seenAt = "seen_at"
    }
}

nonisolated struct ClockSample: Equatable, Sendable {
    let t0: Double
    let serverTime: Double
    let t1: Double
}

/// The member's own player: `{ position, playing }`.
nonisolated struct PlayerReading: Equatable, Sendable {
    let position: Double
    let playing: Bool
}

/// The JS correction's actions: none, pause, seek (with `play` while the host plays), play, rate.
nonisolated enum Correction: Equatable, Sendable {
    case none
    case pause(position: Double)
    case seek(position: Double, play: Bool)
    case play(position: Double, rate: Double)
    case rate(Double)
}

/// A room as one member holds it: who hosts, who is here, and the last state.
/// Only the host's word moves it: a member who is not the host cannot drive.
nonisolated struct RoomLedger: Equatable, Sendable {
    var host: String?
    var members: [RoomMember] = []
    var state: HostState?

    /// The host's own write, through the arbiter. Anyone else is refused.
    mutating func propose(_ input: StateInput, from sender: String, now: Double) -> Result<HostState, RoomRefusal> {
        guard sender == host else { return .failure(.init("host_only")) }
        let result = RoomProtocol.applyHostState(state, input, now: now)
        if case .success(let next) = result { state = next }
        return result
    }

    /// A snapshot that reached this member. Only the host's counts, and only a
    /// newer generation; returns whether it was taken.
    mutating func receive(_ snapshot: RoomSnapshot, from sender: String) -> Bool {
        guard sender == host, snapshot.v == RoomProtocol.version,
              snapshot.generation > (state?.generation ?? 0) else { return false }
        let s = snapshot.state
        state = HostState(episodeID: s.episodeID, archiveID: s.archiveID, file: s.file, position: s.position,
                          playing: s.playing, rate: s.rate, updatedAt: s.updatedAt, generation: snapshot.generation)
        return true
    }

    /// The host's roster, taken only from the host it names (the first one a
    /// new member hears sets the host).
    mutating func receive(roster: [RoomMember], host named: String, from sender: String) -> Bool {
        guard sender == named, host == nil || host == sender else { return false }
        host = named
        members = Array(roster.prefix(RoomProtocol.maxMembers))
        return true
    }

    /// The members present changed. The host (`admitting`) enters newcomers in
    /// the order they arrived, the roster every member hands off by. When the
    /// host is gone, the live member in the room longest takes over; returns
    /// the new host when it changed.
    mutating func presenceChanged(present: Set<String>, now: Double, admitting: Bool = false) -> String? {
        for i in members.indices where present.contains(members[i].id) { members[i].seenAt = now }
        members.removeAll { !present.contains($0.id) }
        if admitting {
            let known = Set(members.map(\.id))
            for id in present.subtracting(known).sorted() where members.count < RoomProtocol.maxMembers {
                members.append(RoomMember(id: id, joinedAt: now, seenAt: now))
            }
        }
        guard let current = host, !present.contains(current) else { return nil }
        host = RoomProtocol.nextHost(members, leaving: current, now: now)
        return host
    }
}
