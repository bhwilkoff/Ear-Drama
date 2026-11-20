import Foundation
import Observation

// A device's seat in a read room (PLAYS-DESIGN §12, Decision 082): the socket first, with the member key in a first
// "hello" and never in a URL, falling back to polling the same messages every second, and trying the socket again
// as the web's js/read-session.js does. Every rule is ReadCore's; this is the transport and the state a screen reads.
// Keys live in memory for the app run only (owner, 2026-11-19: a shared device keeps no seat key at rest).

/// A Worker refusal or a transport failure, by the Worker's own code (`ReadCore.refusal` words it).
nonisolated struct ReadFailure: Error, Equatable, Sendable {
    var code: String
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
    func send(code: String, key: String, message: Data) async throws -> ReadSnapshot?
    func socket(code: String) -> (any ReadSocket)?
}

nonisolated struct WorkerReadWire: ReadWire {
    let api: APIClient
    private static let keyHeader = "x-read-key"

    private static func at(_ code: String) -> String {
        "/v1/read/" + (code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code)
    }

    private func failure(_ status: Int, _ data: Data) -> ReadFailure {
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let code = o?["error"] as? String { return ReadFailure(code: code) }
        return ReadFailure(code: status == 429 ? "rate_limited" : "error")
    }

    private func run(_ method: String, _ path: String, body: Data? = nil, key: String? = nil, bearer: Bool = false) async throws -> Data {
        let headers = key.map { [Self.keyHeader: $0] } ?? [:]
        let data: Data
        let status: Int
        do {
            (data, status) = bearer
                ? try await api.workerResponse(method, path: path, body: body, headers: headers)
                : try await api.anonWorkerResponse(method, path: path, body: body, headers: headers)
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

    func send(code: String, key: String, message: Data) async throws -> ReadSnapshot? {
        try? JSONDecoder().decode(ReadSnapshot.self, from: try await run("POST", Self.at(code) + "/send", body: message, key: key))
    }

    func socket(code: String) -> (any ReadSocket)? {
        guard let url = api.workerSocketURL(path: Self.at(code) + "/socket") else { return nil }
        return URLSessionReadSocket(url: url)
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
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var samples: [ReadCore.ClockSample] = []
    @ObservationIgnored private var lastOK: Double = 0
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private let diag = ProcessInfo.processInfo.environment["APP_READ_DIAG"] == "1"

    static let gone: Set<String> = ["no_such_room", "room_ended", "not_a_member", "seat_key_required"]
    static let retryMS: [UInt64] = [2000, 5000, 15000, 30000]
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

    // MARK: - State

    private func apply(_ snap: ReadSnapshot) {
        guard ReadCore.newer(prev: snapshot, snap: snap) else { return }
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
        guard runID == mine, ended == nil, let code, let key else { return }
        let t0 = now()
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                let snap = try await self.wire.poll(code: code, key: key)
                guard self.runID == mine else { return }
                self.apply(snap)
                let took = self.now() - t0
                let isSlow = took > ReadCore.slowMS
                if isSlow != self.slow { self.slow = isSlow }
            } catch let f as ReadFailure {
                guard self.runID == mine else { return }
                self.failed(f)
                if !self.slow && self.now() - self.lastOK > ReadCore.slowMS { self.slow = true }
            } catch {}
            if self.runID == mine, self.ended == nil, self.transport == "poll" {
                self.later(UInt64(ReadCore.pollMS), mine) { [weak self] in self?.poll(mine) }
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
        let sock = forcePoll ? nil : wire.socket(code: code ?? "")
        schedulePing(mine)
        guard let sock, let key else { startPolling(mine); return }
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
        later(wait, mine) { [weak self] in self?.connect() }
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
            guard let self, let code = self.code, let key = self.key else { return }
            let t0 = self.now()
            if self.socketOpen, let socket = self.socket {
                try? await socket.send(String(decoding: Self.json(["type": "ping", "t0": t0]), as: UTF8.self))
            } else if let snap = try? await self.wire.send(code: code, key: key, message: Self.json(["type": "ping", "t0": t0])) {
                self.apply(snap)
                self.sample(t0: t0, serverTime: snap.serverTime, t1: self.now())
            }
            self.schedulePing(mine)
        }
    }
}
