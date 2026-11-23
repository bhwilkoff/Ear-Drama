import Foundation
import Security

// Relay across time (PLAYS-DESIGN §12.11), the mirror of js/relay-core.js and js/relay-watch.js. A performer's takes are
// written on their device first; this decides when each passes through the Worker to the receiving (teacher's or
// director's) device, which is only when that device is there, and says each take's state in essential words. Nothing is
// kept anywhere but the performer's device. Tests: RelayTests, against a stub Worker and a clock that is turned by hand.

nonisolated enum RelayCore {
    /// Milliseconds between asks while the receiver is away: 5, 10, 20, 40 s, then every 60 (PLAYS-DESIGN §12.11 item 3).
    static let gaps = [5_000, 10_000, 20_000, 40_000, 60_000]
    static func delay(_ failures: Int) -> Int { gaps[min(max(failures, 0), gaps.count - 1)] }

    enum State: Equatable, Sendable { case waiting, sending, sent }

    static func state(_ id: String, sent: Set<String>, sending: String?) -> State {
        if sent.contains(id) { return .sent }
        return sending == id ? .sending : .waiting
    }

    /// "On this device · sends when Ms. Ortiz is in Ear Drama" (a fact, never an explanation).
    static func wording(_ state: State, name: String?, fallback: String = "the director") -> String {
        switch state {
        case .sent: return "Sent"
        case .sending: return "Sending"
        case .waiting:
            let who = name.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            return "On this device \u{00B7} sends when \(who) is in Ear Drama"
        }
    }

    /// Refusals that mean "later": the take stays and the sender backs off.
    static let later: Set<String> = ["nobody_receiving", "one_take_at_a_time", "offline", "error", "rate_limited", "timeout",
                                     "not_configured", "not_delivered", "unauthorized"]
    static func isLater(_ code: String) -> Bool { later.contains(code) }

    static func code(of error: any Error) -> String {
        if let f = error as? ReadFailure { return f.code }
        if let r = error as? PlaysRefusal {
            switch r.kind {
            case .unreachable: return "offline"
            case .unauthorized: return "unauthorized"
            case .notConfigured: return "not_configured"
            case .refused: return r.code ?? (r.status >= 500 || r.status == 429 ? "error" : "refused")
            }
        }
        return "error"
    }

    /// The lines a seat may record: a part, or a scene range of it, from the assignments (the Worker's `covered`).
    static func assignedLines(cast: [(String, String)], assignments: [ReadSnapshot.Assignment]) -> [String] {
        func at(_ id: String) -> Int? { cast.firstIndex { $0.0 == id } }
        var out = Set<String>()
        for a in assignments {
            let lo = a.from.flatMap(at) ?? 0
            let hi = a.to.flatMap(at) ?? cast.count - 1
            guard lo <= hi else { continue }
            for i in lo...hi where cast[i].1 == a.part { out.insert(cast[i].0) }
        }
        return cast.map(\.0).filter(out.contains)
    }

    static func contentType(_ file: String) -> String { file.lowercased().hasSuffix(".wav") ? "audio/wav" : "audio/flac" }

    /// A line's first words, for a row (a label from the script's own data).
    static func excerpt(_ line: ScriptLine) -> String {
        let words = line.spokenText.split(whereSeparator: \.isWhitespace)
        return words.count > 7 ? words.prefix(7).joined(separator: " ") + "\u{2026}" : words.joined(separator: " ")
    }

    /// One row of Your parts: the line, the take's state on this device, and the teacher's review.
    struct Row: Equatable, Identifiable, Sendable {
        var id: String
        var text: String
        var state: String?
        var review: String?
        var again = false
    }

    /// The rows for one part: every line the seat holds, with its take's state. `remote` is what the Worker holds of this seat's takes.
    @MainActor
    static func rows(lines: [ScriptLine], local: Production?, remote: [String: SeatHome.Take], sentHere: Set<String>,
                     refused: [String: String], sending: String?, name: String?, fallback: String = "your teacher") -> [Row] {
        lines.map { l in
            var row = Row(id: l.id, text: excerpt(l))
            let take = local?.chosenTake(for: l.id)
            if let r = remote[l.id], r.chosen == true {
                row.state = wording(.sent, name: name)
                if let rv = r.review {
                    row.review = rv.state == "approved" ? "Approved" : "Again" + ((rv.note?.isEmpty == false) ? " \u{00B7} \(rv.note!)" : "")
                    row.again = rv.state != "approved"
                }
            } else if let take {
                if take.bleed {
                    row.state = PlaysShare.lines["bleed_flagged"]
                } else if let why = refused[take.id] {
                    row.state = PlaysShare.lines[why] ?? "Ear Drama could not send this take."
                } else {
                    row.state = wording(state(take.id, sent: sentHere, sending: sending), name: name, fallback: fallback)
                }
            }
            return row
        }
    }
}

// MARK: - The Worker's side, as the sender sees it

nonisolated struct RelayReceiver: Codable, Equatable, Sendable {
    var receiving: Bool
    var name: String?
}

nonisolated struct SeatHome: Codable, Equatable, Sendable {
    struct Review: Codable, Equatable, Sendable { var state: String; var note: String? }
    struct Take: Codable, Equatable, Sendable { var id: String; var lineID: String; var chosen: Bool?; var review: Review? }
    struct Production: Codable, Equatable, Sendable {
        var id: String
        var title: String
        var scriptID: String
        var scriptRevision: String
        var assignments: [ReadSnapshot.Assignment]
        var takes: [Take]
    }
    struct Seat: Codable, Equatable, Sendable { var id: String; var label: String }
    struct Klass: Codable, Equatable, Sendable { var id: String; var name: String }
    var seat: Seat
    var `class`: Klass
    var productions: [Production]
}

/// A seat's routes (no account: its key in `x-seat-key`).
nonisolated protocol SeatWire: Sendable {
    func home(key: String) async throws -> SeatHome
    func receiver(key: String, pid: String) async throws -> RelayReceiver
    func send(key: String, pid: String, takeID: String, audio: Data, meta: TakeMeta) async throws
}

nonisolated struct WorkerSeat: SeatWire {
    let api: APIClient
    private static let keyHeader = "x-seat-key"
    private static func esc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? s
    }

    private func run(_ method: String, _ path: String, body: Data? = nil, key: String, extra: [String: String] = [:]) async throws -> Data {
        let data: Data
        let status: Int
        do {
            (data, status) = try await api.anonWorkerResponse(method, path: path, body: body, headers: [Self.keyHeader: key].merging(extra) { $1 })
        } catch WorkerError.notConfigured {
            throw ReadFailure(code: "not_configured")
        } catch {
            throw ReadFailure(code: "offline")
        }
        guard 200...299 ~= status else { throw ReadFailure.of(status: status, data: data) }
        return data
    }

    func home(key: String) async throws -> SeatHome {
        let data = try await run("GET", "/v1/plays/seat", key: key)
        do { return try JSONDecoder().decode(SeatHome.self, from: data) } catch { throw ReadFailure(code: "error") }
    }

    func receiver(key: String, pid: String) async throws -> RelayReceiver {
        let data = try await run("GET", "/v1/plays/seat/productions/\(Self.esc(pid))/receiver", key: key)
        do { return try JSONDecoder().decode(RelayReceiver.self, from: data) } catch { throw ReadFailure(code: "error") }
    }

    func send(key: String, pid: String, takeID: String, audio: Data, meta: TakeMeta) async throws {
        let header = String(decoding: try JSONEncoder().encode(meta), as: UTF8.self)
        _ = try await run("PUT", "/v1/plays/seat/productions/\(Self.esc(pid))/takes/\(Self.esc(takeID))", body: audio, key: key,
                          extra: ["x-take": header, "Content-Type": RelayCore.contentType(meta.file)])
    }
}

/// An account member's receiver probe (the director's app is open).
nonisolated protocol MemberReceiverWire: Sendable {
    func receiver(pid: String) async throws -> RelayReceiver
}

nonisolated struct WorkerMemberReceiver: MemberReceiverWire {
    let api: APIClient
    func receiver(pid: String) async throws -> RelayReceiver {
        let esc = pid.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? pid
        let data: Data
        let status: Int
        do { (data, status) = try await api.workerResponse("GET", path: "/v1/plays/productions/\(esc)/receiver", body: nil) } catch { throw ReadFailure(code: "offline") }
        guard 200...299 ~= status else { throw ReadFailure.of(status: status, data: data) }
        do { return try JSONDecoder().decode(RelayReceiver.self, from: data) } catch { throw ReadFailure(code: "error") }
    }
}

/// A seat's key, kept in the Keychain beside its takes (AGENTS.md: secrets never in cleartext on disk). Put there only when
/// a student records at home, never on joining a room (Decision c: a shared class device keeps nothing at rest).
nonisolated protocol SeatKeyVault: Sendable {
    func key(forClass classID: String) -> String?
    func set(_ key: String, forClass classID: String)
    func forget(classID: String)
}

nonisolated struct KeychainSeatVault: SeatKeyVault {
    var service = "app.eardrama.seat"
    private func query(_ classID: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: classID]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }
    func key(forClass classID: String) -> String? {
        var q = query(classID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    func set(_ key: String, forClass classID: String) {
        let update: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query(classID) as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query(classID)
            add.merge(update) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }
    func forget(classID: String) { SecItemDelete(query(classID) as CFDictionary) }
}

nonisolated final class MemorySeatVault: SeatKeyVault, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: String] = [:]
    func key(forClass classID: String) -> String? { lock.withLock { keys[classID] } }
    func set(_ key: String, forClass classID: String) { lock.withLock { keys[classID] = key } }
    func forget(classID: String) { lock.withLock { _ = keys.removeValue(forKey: classID) } }
}

#if os(iOS) || os(macOS)

// MARK: - The queue

/// What a sender needs of one production: the takes still to pass through, whether the receiver is there, and the passing.
@MainActor
protocol RelaySource: AnyObject {
    func pending() async -> [Take]
    func probe() async throws -> RelayReceiver
    func send(_ take: Take) async throws
    func sent(_ take: Take)
    func refused(_ take: Take, code: String)
}

@MainActor @Observable
final class RelaySender {
    private(set) var receiving: Bool?
    private(set) var name: String?
    private(set) var waiting: [String] = []
    private(set) var sending: String?
    private(set) var error: String?
    private(set) var failures = 0
    /// Bumped on every change so a screen reading the sender redraws.
    private(set) var revision = 0

    @ObservationIgnored private let source: any RelaySource
    @ObservationIgnored private let sleep: @Sendable (Int) async -> Void
    @ObservationIgnored private let online: () -> Bool
    @ObservationIgnored private let active: () -> Bool
    @ObservationIgnored private var deferred = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var stopped = false
    @ObservationIgnored var onChange: (() -> Void)?

    init(source: any RelaySource, sleep: @escaping @Sendable (Int) async -> Void = { try? await Task.sleep(for: .milliseconds($0)) },
         online: @escaping () -> Bool = { true }, active: @escaping () -> Bool = { true }) {
        self.source = source
        self.sleep = sleep
        self.online = online
        self.active = active
    }

    private func changed() { revision += 1; onChange?() }

    private func later() {
        timer?.cancel()
        guard !stopped else { timer = nil; return }
        let ms = RelayCore.delay(failures - 1)
        timer = Task { [weak self] in
            await self?.sleep(ms)
            guard !Task.isCancelled else { return }
            await self?.fire()
        }
    }

    /// A backgrounded app asks nothing (each ask is a Worker request on the free account every app shares): the ask that
    /// came due waits, and coming forward runs it at once (PLAYS-DESIGN §12.11). An empty ask sets no timer at all.
    private func fire() async {
        timer = nil
        guard active() else { deferred = true; return }
        await run()
    }

    /// The app came to the front or went away.
    func setActive(_ now: Bool) {
        guard now, deferred else { return }
        deferred = false
        Task { await kick() }
    }

    /// A take was saved, the network came back, or the app came to the front: ask now.
    func kick() async {
        failures = 0
        timer?.cancel()
        timer = nil
        await run()
    }

    func stop() { stopped = true; timer?.cancel(); timer = nil }

    func run() async {
        if running { again = true; return }
        guard !stopped else { return }
        running = true
        defer { running = false }
        repeat {
            again = false
            let todo = await source.pending()
            waiting = todo.map(\.id)
            if todo.isEmpty { failures = 0; error = nil; sending = nil; changed(); break }
            changed()
            guard online() else { failures += 1; error = "offline"; changed(); later(); break }
            let probe: RelayReceiver
            do { probe = try await source.probe() } catch {
                failures += 1; self.error = RelayCore.code(of: error); changed(); later(); break
            }
            receiving = probe.receiving
            if let n = probe.name { name = n }
            if !probe.receiving { failures += 1; error = nil; changed(); later(); break }
            var stuck = false
            for take in todo {
                if stopped { break }
                sending = take.id
                changed()
                do {
                    try await source.send(take)
                    source.sent(take)
                    waiting.removeAll { $0 == take.id }
                    failures = 0
                    error = nil
                } catch {
                    let code = RelayCore.code(of: error)
                    if RelayCore.isLater(code) { failures += 1; self.error = code; stuck = true; break }
                    self.error = code
                    waiting.removeAll { $0 == take.id }
                    source.refused(take, code: code)
                }
            }
            sending = nil
            changed()
            if stuck { later(); break }
        } while again && !stopped
    }
}

// MARK: - Sources: a seat's production, a member's production

@MainActor
final class SeatRelaySource: RelaySource {
    let store: ProductionStore
    let localID: String
    let script: PlayScript
    let wire: any SeatWire
    let vault: any SeatKeyVault

    init(store: ProductionStore, localID: String, script: PlayScript, wire: any SeatWire, vault: any SeatKeyVault) {
        self.store = store; self.localID = localID; self.script = script; self.wire = wire; self.vault = vault
    }

    private var link: ProductionShare? { store.share(localID) }
    private var key: String? { link?.seat.flatMap { vault.key(forClass: $0.classID) } }
    private func patch(_ change: (inout ProductionShare) -> Void) {
        guard var l = link else { return }
        change(&l)
        try? store.setShare(localID, l)
    }

    func pending() async -> [Take] {
        guard let key, let pid = link?.pid else { return [] }
        var remote = Set<String>()
        do {
            let home = try await wire.home(key: key)
            if let p = home.productions.first(where: { $0.id == pid }) {
                remote = Set(p.takes.map(\.id))
                patch { $0.assignments = p.assignments }
            }
        } catch let f as ReadFailure where f.code == "seat_key_required" { return [] } catch {}
        let cast = script.lines.map { ($0.id, $0.part.rawValue) }
        let lines = RelayCore.assignedLines(cast: cast, assignments: link?.assignments ?? [])
        guard let local = store.production(localID) else { return [] }
        let done = Set(link?.sent ?? []).union(remote)
        return lines.compactMap { local.chosenTake(for: $0) }.filter { !$0.bleed && !done.contains($0.id) && link?.refused?[$0.id] == nil }
    }

    func probe() async throws -> RelayReceiver {
        guard let key, let pid = link?.pid else { throw ReadFailure(code: "seat_key_required") }
        return try await wire.receiver(key: key, pid: pid)
    }

    func send(_ take: Take) async throws {
        guard let key, let pid = link?.pid else { throw ReadFailure(code: "seat_key_required") }
        let audio = try store.readTake(localID, file: take.file)
        do { try await wire.send(key: key, pid: pid, takeID: take.id, audio: audio, meta: PlaysShare.metaOf(take)) } catch let f as ReadFailure where f.code == "take_exists" {}
    }

    func sent(_ take: Take) { patch { $0.sent = Array(Set(($0.sent ?? []) + [take.id])).sorted() } }
    func refused(_ take: Take, code: String) { patch { $0.refused = ($0.refused ?? [:]).merging([take.id: code]) { $1 } } }
}

@MainActor
final class MemberRelaySource: RelaySource {
    let store: ProductionStore
    let localID: String
    let script: PlayScript
    let transport: any PlaysTransport
    let receiverWire: any MemberReceiverWire
    let me: () -> String?

    init(store: ProductionStore, localID: String, script: PlayScript, transport: any PlaysTransport, receiver: any MemberReceiverWire, me: @escaping () -> String?) {
        self.store = store; self.localID = localID; self.script = script; self.transport = transport; self.receiverWire = receiver; self.me = me
    }

    private var link: ProductionShare? { store.share(localID) }
    private func patch(_ change: (inout ProductionShare) -> Void) {
        guard var l = link else { return }
        change(&l)
        try? store.setShare(localID, l)
    }

    func pending() async -> [Take] {
        guard let pid = link?.pid, let rec = try? await transport.get(pid), rec.uploads != false, let local = store.production(localID) else { return [] }
        return PlaysShare.chosenOfMine(local, script, rec, me()).filter { !$0.bleed && link?.refused?[$0.id] == nil }
    }

    func probe() async throws -> RelayReceiver {
        guard let pid = link?.pid else { throw ReadFailure(code: "not_found") }
        return try await receiverWire.receiver(pid: pid)
    }

    func send(_ take: Take) async throws {
        guard let pid = link?.pid else { throw ReadFailure(code: "not_found") }
        let audio = try store.readTake(localID, file: take.file)
        do {
            try await transport.upload(pid, takeID: take.id, audio: audio, contentType: PlaysShare.contentType(take.file), meta: PlaysShare.metaOf(take))
        } catch let r as PlaysRefusal where r.code == "take_exists" {}
    }

    func sent(_ take: Take) { patch { $0.sent = Array(Set(($0.sent ?? []) + [take.id])).sorted() } }
    func refused(_ take: Take, code: String) { patch { $0.refused = ($0.refused ?? [:]).merging([take.id: code]) { $1 } } }
}

// MARK: - The receiver's pickup loop

/// The receiver's pickup (mirror of RelayCore.receive in js/relay-core.js): long polls `inbox` one after another, but only while
/// the page is in the foreground, and stops after `idleMs` with no take, calling `onIdle` so the page can offer Keep receiving
/// takes. A held pickup keeps a Durable Object awake and every app shares one free Worker account (2026-11-23), so a
/// backgrounded or forgotten page holds nothing. `inbox` returns whether a take arrived; `stopOn(error)` ends the loop on a refusal.
@MainActor
final class PickupLoop {
    /// A receiver stops holding its pickup after this long with no take (PLAYS-DESIGN §12.11 item 4).
    nonisolated static let idleMs = 30 * 60 * 1000
    nonisolated static let wallClock: @Sendable () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }

    private(set) var stopped = false
    private var active: Bool
    private var wake: CheckedContinuation<Void, Never>?
    private var task: Task<Void, Never>?
    private let now: @Sendable () -> Int
    private let sleep: @Sendable (Int) async -> Void
    private let idleMs: Int
    private let inbox: @MainActor () async throws -> Bool
    private let stopOn: (any Error) -> Bool
    private let onIdle: @MainActor () -> Void

    init(active: Bool = true, now: @escaping @Sendable () -> Int = PickupLoop.wallClock,
         sleep: @escaping @Sendable (Int) async -> Void = { try? await Task.sleep(for: .milliseconds($0)) }, idleMs: Int = PickupLoop.idleMs,
         inbox: @escaping @MainActor () async throws -> Bool, stopOn: @escaping (any Error) -> Bool = { _ in false },
         onIdle: @escaping @MainActor () -> Void = {}) {
        self.active = active; self.now = now; self.sleep = sleep; self.idleMs = idleMs
        self.inbox = inbox; self.stopOn = stopOn; self.onIdle = onIdle
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    func setActive(_ value: Bool) {
        active = value
        if value { rouse() }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        rouse()
        task?.cancel()
    }

    /// Returns when the loop has ended (a test's way to wait).
    func finished() async { await task?.value }

    private func rouse() { if let w = wake { wake = nil; w.resume() } }

    private func run() async {
        var lastTake = now()
        var wait = 0
        while !stopped {
            if !active {
                await withCheckedContinuation { wake = $0 }
                lastTake = now()
                continue
            }
            if now() - lastTake >= idleMs { stop(); onIdle(); return }
            do {
                let got = try await inbox()
                wait = 0
                if stopped { break }
                if got { lastTake = now() }
            } catch {
                if stopped || stopOn(error) { break }
                wait = min(30_000, wait == 0 ? 2_000 : wait * 2)
                await sleep(wait)
            }
        }
        stop()
    }
}

// MARK: - The receiving end: the teacher's class page holds the pickup

/// While the teacher's class page is open and in the foreground, one long poll per class production keeps the teacher's app "there" for the Worker
/// (`GET /productions/:pid/takes/inbox`); each take that passes through is kept in a production on this device and nowhere
/// else (Decision 082). `arrived` counts them so the progress list can refresh.
@MainActor @Observable
final class ClassInbox {
    private(set) var arrived = 0
    /// Thirty minutes passed with no take: the pickups are let go and the page offers Keep receiving takes.
    private(set) var idle = false
    @ObservationIgnored let store: ProductionStore
    @ObservationIgnored let transport: any PlaysTransport
    @ObservationIgnored let script: (String, String) async -> PlayScript?
    @ObservationIgnored private var loops: [String: PickupLoop] = [:]
    @ObservationIgnored private var known: [String: (scriptID: String, revision: String)] = [:]
    @ObservationIgnored private var shown = true
    @ObservationIgnored private let clock: @Sendable () -> Int
    @ObservationIgnored private let sleep: @Sendable (Int) async -> Void
    @ObservationIgnored private let idleMs: Int
    @ObservationIgnored var onArrival: (() -> Void)?

    init(store: ProductionStore, transport: any PlaysTransport = WorkerPlays(api: .shared), script: @escaping (String, String) async -> PlayScript?,
         clock: @escaping @Sendable () -> Int = PickupLoop.wallClock, sleep: @escaping @Sendable (Int) async -> Void = { try? await Task.sleep(for: .milliseconds($0)) },
         idleMs: Int = PickupLoop.idleMs) {
        self.store = store; self.transport = transport; self.script = script
        self.clock = clock; self.sleep = sleep; self.idleMs = idleMs
    }

    var holding: Set<String> { Set(loops.keys) }

    func hold(_ pid: String, scriptID: String, revision: String) {
        known[pid] = (scriptID, revision)
        guard loops[pid] == nil, !idle else { return }
        let loop = PickupLoop(active: shown, now: clock, sleep: sleep, idleMs: idleMs,
            inbox: { [weak self] in
                guard let self, let picked = try await self.transport.nextTake(pid), let s = await self.script(scriptID, revision) else { return false }
                try self.accept(picked, pid: pid, script: s)
                return true
            },
            stopOn: { ["director_only", "not_found", "pass_through_unavailable", "unauthorized", "not_configured"].contains(RelayCore.code(of: $0)) },
            onIdle: { [weak self] in self?.letGo() })
        loops[pid] = loop
        loop.start()
    }

    /// The page is in the foreground (scenePhase active) or not: a hidden page holds no pickup.
    func setActive(_ now: Bool) {
        shown = now
        loops.values.forEach { $0.setActive(now) }
    }

    /// Keep receiving takes: the pickups start again for every production this page holds.
    func keepReceiving() {
        idle = false
        for (pid, k) in known { hold(pid, scriptID: k.scriptID, revision: k.revision) }
    }

    private func letGo() {
        loops.values.forEach { $0.stop() }
        loops.removeAll()
        idle = true
    }

    private func accept(_ picked: PickedTake, pid: String, script: PlayScript) throws {
        let local = try PlaysShare.localFor(store: store, pid: pid, script: script)
        let t = picked.fields
        guard local.take(t.id) == nil else { return }
        let file = PlaysShare.importedFile(t.id, picked.data)
        try store.importTake(local.id, file: file, data: picked.data)
        guard var p = store.production(local.id) else { return }
        p.add(Take(id: t.id, lineID: t.lineID, part: PartID(rawValue: t.part), file: file, created: Date(), frames: t.frames, sampleRate: t.sampleRate,
                   capture: Take.Capture(rawValue: t.capture ?? "") ?? .direct, heard: [:], loudness: nil, peak: 0, bleed: false))
        try store.save(p)
        arrived += 1
        onArrival?()
    }

    func release() { loops.values.forEach { $0.stop() }; loops.removeAll(); known.removeAll() }
}

// MARK: - The one sender per device

/// One RelaySender per linked production, kept alive while the app is open; kicked when a take is saved, the network
/// returns, or the app comes forward.
@MainActor @Observable
final class RelayHub {
    private(set) var revision = 0
    @ObservationIgnored let store: ProductionStore
    @ObservationIgnored let seatWire: any SeatWire
    @ObservationIgnored let transport: any PlaysTransport
    @ObservationIgnored let receiverWire: any MemberReceiverWire
    @ObservationIgnored let vault: any SeatKeyVault
    @ObservationIgnored let me: () -> String?
    @ObservationIgnored private let sleep: @Sendable (Int) async -> Void
    @ObservationIgnored private let online: () -> Bool
    @ObservationIgnored private var senders: [String: RelaySender] = [:]
    @ObservationIgnored private var foreground = true

    init(store: ProductionStore, seatWire: any SeatWire = WorkerSeat(api: .shared), transport: any PlaysTransport = WorkerPlays(api: .shared),
         receiver: any MemberReceiverWire = WorkerMemberReceiver(api: .shared), vault: any SeatKeyVault = KeychainSeatVault(),
         me: @escaping () -> String? = { APIClient.shared.storedSession()?.userId }, sleep: @escaping @Sendable (Int) async -> Void = { try? await Task.sleep(for: .milliseconds($0)) },
         online: @escaping () -> Bool = { true }) {
        self.store = store; self.seatWire = seatWire; self.transport = transport; self.receiverWire = receiver; self.vault = vault
        self.me = me; self.sleep = sleep; self.online = online
    }

    func sender(for localID: String) -> RelaySender? {
        if let s = senders[localID] { return s }
        guard let link = store.share(localID), let local = store.production(localID), let script = store.script(for: local) else { return nil }
        let source: any RelaySource
        if link.seat != nil {
            source = SeatRelaySource(store: store, localID: localID, script: script, wire: seatWire, vault: vault)
        } else {
            source = MemberRelaySource(store: store, localID: localID, script: script, transport: transport, receiver: receiverWire, me: me)
        }
        let s = RelaySender(source: source, sleep: sleep, online: online, active: { [weak self] in self?.foreground ?? true })
        s.onChange = { [weak self] in self?.revision += 1 }
        senders[localID] = s
        return s
    }

    /// Asks now for one production, or for every linked one.
    func kick(_ localID: String? = nil) async {
        let ids = localID.map { [$0] } ?? store.productions.map(\.id).filter { store.share($0)?.seat != nil || store.share($0)?.pid != nil }
        for id in ids { if let s = sender(for: id) { await s.kick() } }
    }

    func stop() { senders.values.forEach { $0.stop() }; senders.removeAll() }

    /// The app came to the front or went to the background: a backgrounded one asks nothing until it is back.
    func setActive(_ now: Bool) {
        foreground = now
        senders.values.forEach { $0.setActive(now) }
    }

    /// One take's state for a screen.
    func state(_ localID: String, _ takeID: String, remote: Set<String> = []) -> (RelayCore.State, name: String?) {
        let sent = Set(store.share(localID)?.sent ?? []).union(remote)
        let s = senders[localID]
        return (RelayCore.state(takeID, sent: sent, sending: s?.sending), s?.name)
    }
}

extension ProductionStore {
    /// Links a production on this device to a seat's, keeping the seat key in the Keychain beside it (never in share.json).
    @MainActor
    func linkSeat(_ localID: String, pid: String, classID: String, label: String, key: String, assignments: [ReadSnapshot.Assignment],
                  vault: any SeatKeyVault) throws {
        vault.set(key, forClass: classID)
        var link = share(localID) ?? ProductionShare(pid: pid)
        link.pid = pid
        link.seat = SeatLink(classID: classID, label: label)
        link.assignments = assignments
        try setShare(localID, link)
    }
}
#endif
