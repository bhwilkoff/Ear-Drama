import Foundation
import Observation

// A device's seat in a read room (PLAYS-DESIGN §12, Decision 082): the socket first, with the member key in a first
// "hello" and never in a URL, falling back to long-polling the same messages (the room answers on a change or after
// 20 s, so a quiet room costs three requests a minute), and trying the socket again less often each time, as the
// web's js/read-session.js does. Every rule is ReadCore's; this is the transport and the state a screen reads.
// Keys live in memory for the app run only (owner, 2026-11-19: a shared device keeps no seat key at rest).

/// A Worker refusal or a transport failure, by the Worker's own code (`ReadCore.refusal` words it).
nonisolated struct ReadFailure: Error, Equatable, Sendable {
    var code: String

    /// A refusal as the Worker wrote it. The Worker's own `error` code wins; a body without one (a route the Worker
    /// does not know, a proxy's page) reads by its status, so an unknown room is "No reading with that code." and
    /// never "could not be reached" (PLAYS-DESIGN §12.10 item 8).
    static func of(status: Int, data: Data) -> ReadFailure {
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let code = o?["error"] as? String, code != "not_found" { return ReadFailure(code: code) }
        switch status {
        case 404: return ReadFailure(code: "no_such_room")
        case 410: return ReadFailure(code: "room_ended")
        case 429: return ReadFailure(code: "rate_limited")
        default: return ReadFailure(code: "error")
        }
    }
}

/// The code a TV shows and the key it waits with (`POST /v1/read/pair`).
nonisolated struct ReadPairing: Equatable, Sendable {
    var code: String
    var key: String
    var expiresAt: Double
}

nonisolated struct ReadJoined: Sendable {
    var snapshot: ReadSnapshot
    var key: String
    /// `socket` or `poll`: the Worker's own say on whether it can hold a socket.
    var transport: String
}

/// One socket to a room, as the session needs it (URLSessionWebSocketTask below; a fake in tests).
nonisolated protocol ReadSocket: AnyObject, Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

/// The Worker's read routes, so the session never touches the network itself (AGENTS.md: one shared client).
nonisolated protocol ReadWire: Sendable {
    func create(body: Data, teacher: Bool) async throws -> ReadJoined
    func join(code: String, body: Data) async throws -> ReadJoined
    func poll(code: String, key: String) async throws -> ReadSnapshot
    /// A long poll: the room answers when its generation moves past `gen`, or after 20 s.
    func poll(code: String, key: String, gen: Int) async throws -> ReadSnapshot
    func send(code: String, key: String, message: Data) async throws -> ReadSnapshot?
    func socket(code: String) -> (any ReadSocket)?
    /// A reader's take of a line it holds, passing through to the room's receiver (`PUT /v1/read/{code}/takes/{id}`).
    func sendTake(code: String, key: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws
    /// The receiver's pickup: the next take, or nil after the Worker's 25 second wait.
    func inbox(code: String, key: String) async throws -> PickedTake?
    /// A TV asks for a pairing code, then waits; a leader attaches it to a room.
    func pair() async throws -> ReadPairing
    func pairWait(_ pairing: ReadPairing) async throws -> ReadJoined?
    func attachScreen(code: String, key: String, pairCode: String) async throws
}

extension ReadWire {
    func poll(code: String, key: String, gen: Int) async throws -> ReadSnapshot { try await poll(code: code, key: key) }

    /// Whether a room answers to `code` before anyone joins: a keyless poll, which the Worker answers `no_such_room` or `room_ended`
    /// for a room that is not there and a membership refusal for one that is. Returns the gone code, else nil.
    func gone(code: String) async -> String? {
        do { _ = try await poll(code: code, key: "-"); return nil } catch let f as ReadFailure {
            return ["no_such_room", "room_ended"].contains(f.code) ? f.code : nil
        } catch { return nil }
    }
}

nonisolated struct WorkerReadWire: ReadWire {
    let api: APIClient
    private static let keyHeader = "x-read-key"

    private static func at(_ code: String) -> String {
        "/v1/read/" + (code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code)
    }

    private func failure(_ status: Int, _ data: Data) -> ReadFailure { ReadFailure.of(status: status, data: data) }

    private func run(_ method: String, _ path: String, body: Data? = nil, key: String? = nil, keyHeader: String = WorkerReadWire.keyHeader,
                     bearer: Bool = false, timeout: TimeInterval? = nil) async throws -> Data {
        let headers = key.map { [keyHeader: $0] } ?? [:]
        let data: Data
        let status: Int
        do {
            (data, status) = bearer
                ? try await api.workerResponse(method, path: path, body: body, headers: headers)
                : try await api.anonWorkerResponse(method, path: path, body: body, headers: headers, timeout: timeout)
        } catch WorkerError.notConfigured {
            throw ReadFailure(code: "not_configured")
        } catch {
            throw ReadFailure(code: "offline")
        }
        guard 200...299 ~= status else { throw failure(status, data) }
        return data
    }

    private func joined(_ data: Data) throws -> ReadJoined {
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let snap = try? JSONDecoder().decode(ReadSnapshot.self, from: data), let key = o?["member_key"] as? String else {
            throw ReadFailure(code: "error")
        }
        return ReadJoined(snapshot: snap, key: key, transport: o?["transport"] as? String ?? "socket")
    }

    func create(body: Data, teacher: Bool) async throws -> ReadJoined {
        try joined(await run("POST", "/v1/read", body: body, bearer: teacher))
    }

    func join(code: String, body: Data) async throws -> ReadJoined {
        try joined(await run("POST", Self.at(code) + "/join", body: body))
    }

    func poll(code: String, key: String) async throws -> ReadSnapshot {
        guard let s = try? JSONDecoder().decode(ReadSnapshot.self, from: try await run("GET", Self.at(code), key: key)) else {
            throw ReadFailure(code: "error")
        }
        return s
    }

    func poll(code: String, key: String, gen: Int) async throws -> ReadSnapshot {
        guard let s = try? JSONDecoder().decode(ReadSnapshot.self, from: try await run("GET", Self.at(code) + "?gen=\(gen)", key: key, timeout: 35)) else {
            throw ReadFailure(code: "error")
        }
        return s
    }

    func send(code: String, key: String, message: Data) async throws -> ReadSnapshot? {
        try? JSONDecoder().decode(ReadSnapshot.self, from: try await run("POST", Self.at(code) + "/send", body: message, key: key))
    }

    func socket(code: String) -> (any ReadSocket)? {
        guard let url = api.workerSocketURL(path: Self.at(code) + "/socket") else { return nil }
        return URLSessionReadSocket(url: url)
    }

    func sendTake(code: String, key: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws {
        let header = String(decoding: try JSONEncoder().encode(meta), as: UTF8.self)
        let data: Data
        let status: Int
        do {
            (data, status) = try await api.anonWorkerResponse("PUT", path: Self.at(code) + "/takes/" + Self.escape(takeID), body: audio,
                                                             headers: [Self.keyHeader: key, "x-take": header, "Content-Type": contentType])
        } catch WorkerError.notConfigured {
            throw ReadFailure(code: "not_configured")
        } catch {
            throw ReadFailure(code: "offline")
        }
        guard 200...299 ~= status else { throw failure(status, data) }
    }

    func inbox(code: String, key: String) async throws -> PickedTake? {
        let data: Data
        let status: Int
        let header: String?
        do {
            (data, status, header) = try await api.anonInboxResponse(path: Self.at(code) + "/takes/inbox", headers: [Self.keyHeader: key])
        } catch {
            throw ReadFailure(code: "offline")
        }
        if status == 204 { return nil }
        guard 200...299 ~= status else { throw failure(status, data) }
        guard let header, let fields = try? JSONDecoder().decode(PickedTake.Fields.self, from: Data(header.utf8)) else {
            throw ReadFailure(code: "error")
        }
        return PickedTake(fields: fields, data: data)
    }

    func pair() async throws -> ReadPairing {
        let data = try await run("POST", "/v1/read/pair", body: Data("{}".utf8))
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let code = o["pair_code"] as? String, let key = o["pair_key"] as? String else { throw ReadFailure(code: "error") }
        return ReadPairing(code: code, key: key, expiresAt: (o["expires_at"] as? NSNumber)?.doubleValue ?? 0)
    }

    func pairWait(_ pairing: ReadPairing) async throws -> ReadJoined? {
        let data = try await run("GET", "/v1/read/pair/" + Self.escape(pairing.code), key: pairing.key, keyHeader: "x-pair-key")
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if o?["paired"] as? Bool == false { return nil }
        return try joined(data)
    }

    func attachScreen(code: String, key: String, pairCode: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["code": pairCode])
        _ = try await run("POST", Self.at(code) + "/pair", body: body, key: key)
    }

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? s
    }
}

nonisolated final class URLSessionReadSocket: ReadSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(url: URL) {
        task = URLSession.shared.webSocketTask(with: url)
        task.resume()
    }

    func send(_ text: String) async throws { try await task.send(.string(text)) }

    func receive() async throws -> String {
        switch try await task.receive() {
        case let .string(s): return s
        case let .data(d): return String(decoding: d, as: UTF8.self)
        @unknown default: return ""
        }
    }

    func close() { task.cancel(with: .goingAway, reason: nil) }
}

/// Seat keys held for this app run only (decision c): a class device shared by students keeps nothing at rest.
@MainActor
enum ReadSeatKeys {
    private static var keys: [String: String] = [:]
    static func key(forSeat seat: String) -> String? { keys[seat] }
    static func set(_ key: String, forSeat seat: String) { keys[seat] = key }
    static func forget() { keys.removeAll() }
}

@MainActor @Observable
final class ReadSession {
    private(set) var snapshot: ReadSnapshot?
    private(set) var transport: String?
    private(set) var slow = false
    private(set) var offline = false
    /// The Worker's code once the room is over for this device (`room_ended`, `no_such_room`, `not_a_member`).
    private(set) var ended: String?
    private(set) var refusal: String?
    /// Seconds-free clock offset in ms (server minus this device), from the smallest round trip.
    private(set) var clockOffsetMS: Double?
    private(set) var code: String?

    @ObservationIgnored private let wire: any ReadWire
    @ObservationIgnored private let now: @Sendable () -> Double
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var forcePoll = false
    @ObservationIgnored private var socket: (any ReadSocket)?
    @ObservationIgnored private var socketOpen = false
    @ObservationIgnored private var polling = false
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var samples: [ReadCore.ClockSample] = []
    @ObservationIgnored private var lastOK: Double = 0
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private let diag = ProcessInfo.processInfo.environment["APP_READ_DIAG"] == "1"

    static let gone: Set<String> = ["no_such_room", "room_ended", "not_a_member", "seat_key_required"]
    static let retryMS: [UInt64] = [2000, 5000, 15000, 30000, 60000, 300_000]
    static let pollErrorMS: UInt64 = 5000
    static let pingMS: UInt64 = 10_000
    static let openWaitMS: UInt64 = 5000

    init(wire: any ReadWire, now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 * 1000 }) {
        self.wire = wire
        self.now = now
    }

    static func system() -> ReadSession { ReadSession(wire: WorkerReadWire(api: .shared)) }

    private func said(_ s: @autoclosure () -> String) { if diag { print("[readdiag] \(s())") } }

    // MARK: - Entering and leaving

    /// Opens a room; the creator leads. A class room is the signed-in teacher's.
    func open(_ body: [String: Any], teacher: Bool) async throws {
        enter(try await wire.create(body: Self.json(body), teacher: teacher))
    }

    func join(code: String, _ want: [String: Any] = [:]) async throws {
        enter(try await wire.join(code: code, body: Self.json(want)))
    }

    /// A TV that was paired becomes this room's screen with the snapshot and key the pairing answered with.
    func adopt(_ joined: ReadJoined) { enter(joined) }

    func leave() {
        stopTransport()
        key = nil; code = nil; snapshot = nil; ended = nil
    }

    func pause() { stopTransport() }

    private static func json(_ o: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8) }

    private func enter(_ joined: ReadJoined) {
        stopTransport()
        code = joined.snapshot.code
        key = joined.key
        forcePoll = joined.transport == "poll"
        ended = nil
        snapshot = nil
        apply(joined.snapshot)
        connect()
    }

    // MARK: - Messages

    /// One message to the room. On a socket the answer is the next snapshot; over HTTP the snapshot comes back
    /// or the refusal is thrown (the Worker's code).
    func send(_ message: [String: Any]) async throws {
        guard let code, let key, ended == nil else { throw ReadFailure(code: ended ?? "not_a_member") }
        let data = Self.json(message)
        if socketOpen, let socket {
            try await socket.send(String(decoding: data, as: UTF8.self))
            return
        }
        do {
            if let s = try await wire.send(code: code, key: key, message: data) { apply(s) }
            refusal = nil
        } catch let f as ReadFailure {
            if f.code == "stale", let s = try? await wire.poll(code: code, key: key) { apply(s) }
            else if Self.gone.contains(f.code) { end(f.code) }
            else { refusal = f.code }
            throw f
        }
    }

    // MARK: - Takes and screens (PLAYS-DESIGN §12.10)

    /// A reader's take of a line it holds, to the room's receiver. The Worker's refusal is thrown with its code; a room
    /// that is gone ends the session.
    func sendTake(takeID: String, audio: Data, meta: TakeMeta) async throws {
        guard let code, let key, ended == nil else { throw ReadFailure(code: ended ?? "not_a_member") }
        do {
            try await wire.sendTake(code: code, key: key, takeID: takeID, audio: audio, contentType: meta.file.lowercased().hasSuffix(".wav") ? "audio/wav" : "audio/flac", meta: meta)
        } catch let f as ReadFailure {
            if Self.gone.contains(f.code) { end(f.code) }
            throw f
        }
    }

    /// The receiver's pickup (a long poll): the next take, or nil when none came.
    func pickup() async throws -> PickedTake? {
        guard let code, let key, ended == nil else { throw ReadFailure(code: ended ?? "not_a_member") }
        return try await wire.inbox(code: code, key: key)
    }

    /// The leader's Add a Screen: the code a TV shows, typed here.
    func attachScreen(pairCode: String) async throws {
        guard let code, let key, ended == nil else { throw ReadFailure(code: ended ?? "not_a_member") }
        try await wire.attachScreen(code: code, key: key, pairCode: pairCode)
    }

    // MARK: - State

    private func apply(_ snap: ReadSnapshot) {
        guard ReadCore.newer(prev: snapshot, snap: snap) else { return }
        if diag, snapshot?.cursor != snap.cursor { said("lit \(snap.cursor) gen \(snap.cursorGen) at \(now()) offset \(clockOffsetMS ?? .nan)") }
        snapshot = snap
        lastOK = now()
        if slow { slow = false }
        if offline { offline = false }
        refusal = nil
        if snap.ended { end("room_ended") }
    }

    private func end(_ code: String) {
        guard ended == nil else { return }
        ended = code
        stopTransport()
        key = nil
    }

    private func stopTransport() {
        runID += 1
        tasks.forEach { $0.cancel() }
        tasks = []
        socket?.close()
        socket = nil
        socketOpen = false
        polling = false
    }

    private func later(_ ms: UInt64, _ mine: Int, _ body: @escaping @MainActor () async -> Void) {
        tasks.append(Task { [weak self] in
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
            guard !Task.isCancelled, let self, self.runID == mine, self.ended == nil else { return }
            await body()
        })
    }

    // MARK: - Polling

    private func poll(_ mine: Int) {
        guard runID == mine, ended == nil, !polling, let code, let key else { return }
        polling = true
        let t0 = now()
        let gen = snapshot?.generation
        tasks.append(Task { [weak self] in
            guard let self else { return }
            var wait = UInt64(ReadCore.pollMS)
            do {
                let snap: ReadSnapshot
                if let gen { snap = try await self.wire.poll(code: code, key: key, gen: gen) } else { snap = try await self.wire.poll(code: code, key: key) }
                guard self.runID == mine else { return }
                let took = self.now() - t0
                let held = snap.heldMS ?? 0
                // Every answer is a clock sample, with the time it waited in the room taken out.
                self.sample(t0: t0 + held, serverTime: snap.serverTime, t1: self.now())
                self.apply(snap)
                let isSlow = took - held > ReadCore.slowMS
                if isSlow != self.slow { self.slow = isSlow }
                wait = UInt64(max(0, Double(ReadCore.pollMS) - took))
            } catch let f as ReadFailure {
                guard self.runID == mine else { return }
                self.failed(f)
                if !self.slow && self.now() - self.lastOK > ReadCore.slowMS { self.slow = true }
                wait = Self.pollErrorMS
            } catch {}
            guard self.runID == mine else { return }
            self.polling = false
            if self.ended == nil, self.transport == "poll" {
                self.later(wait, mine) { [weak self] in self?.poll(mine) }
            }
        })
    }

    private func failed(_ f: ReadFailure) {
        if Self.gone.contains(f.code) { end(f.code) }
        else if f.code == "offline" { offline = true }
        else if f.code == "rate_limited" { refusal = f.code }
    }

    private func startPolling(_ mine: Int) {
        if transport != "poll" { transport = "poll"; said("transport poll") }
        poll(mine)
    }

    // MARK: - The socket

    private func connect() {
        stopTransport()
        let mine = runID
        schedulePing(mine)
        if forcePoll || !openSocket(mine) { startPolling(mine) }
    }

    /// A socket alongside a poll in flight: polling stops only once the socket is open.
    private func openSocket(_ mine: Int) -> Bool {
        guard let sock = wire.socket(code: code ?? ""), let key else { return false }
        socket = sock
        later(Self.openWaitMS, mine) { [weak self] in
            guard let self, !self.socketOpen else { return }
            self.fallBack(mine)
        }
        tasks.append(Task { [weak self] in
            do {
                try await sock.send(String(decoding: Self.json(["type": "hello", "key": key]), as: UTF8.self))
                guard let self, self.runID == mine else { return }
                self.socketOpen = true
                self.retries = 0
                self.transport = "socket"
                self.said("transport socket")
                while !Task.isCancelled {
                    let text = try await sock.receive()
                    guard self.runID == mine else { return }
                    self.handle(text)
                }
            } catch {
                guard let self, self.runID == mine, self.ended == nil else { return }
                self.fallBack(mine)
            }
        })
        return true
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = o["type"] as? String else { return }
        switch type {
        case "snapshot":
            if let s = try? JSONDecoder().decode(ReadSnapshot.self, from: data) { apply(s) }
        case "pong":
            if let t0 = (o["t0"] as? NSNumber)?.doubleValue, let st = (o["server_time"] as? NSNumber)?.doubleValue {
                sample(t0: t0, serverTime: st, t1: now())
            }
        case "error":
            let code = o["error"] as? String ?? "error"
            if Self.gone.contains(code) { end(code) } else { refusal = code }
        default: break
        }
    }

    private func fallBack(_ mine: Int) {
        guard runID == mine, ended == nil else { return }
        socket?.close()
        socket = nil
        socketOpen = false
        startPolling(mine)
        let wait = Self.retryMS[min(retries, Self.retryMS.count - 1)]
        retries += 1
        later(wait, mine) { [weak self] in _ = self?.openSocket(mine) }
    }

    // MARK: - The clock

    private func sample(t0: Double, serverTime: Double, t1: Double) {
        samples.append(.init(t0: t0, serverTime: serverTime, t1: t1))
        if samples.count > 8 { samples.removeFirst() }
        clockOffsetMS = ReadCore.clockOffset(samples)
        said("clock offset \(clockOffsetMS ?? .nan) samples \(samples.count)")
    }

    private func schedulePing(_ mine: Int) {
        later(Self.pingMS, mine) { [weak self] in
            guard let self else { return }
            // Polling sends no ping: every poll answer is a clock sample.
            if self.socketOpen, let socket = self.socket {
                try? await socket.send(String(decoding: Self.json(["type": "ping", "t0": self.now()]), as: UTF8.self))
            }
            self.schedulePing(mine)
        }
    }
}
