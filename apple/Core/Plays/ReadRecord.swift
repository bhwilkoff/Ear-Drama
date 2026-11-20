#if os(iOS) || os(macOS)
import Foundation
import Observation

// Record in the room on this device (PLAYS-DESIGN §12.10), the mirror of js/read-record.js: no view. The room's rules
// are ReadCore's; the take engine is the studio's `RecordingSession.recordInRoom` (no cue played); the takes live in a
// local production kept for this room (`room: CODE`) in the same store as every production, so Listen Through, Export
// and Publish work on it as on any other. Tests: ReadRecordTests, against a fake link and a fake microphone.

/// What the recorder needs of the room (`ReadSession` in the app, a fake in tests).
@MainActor
protocol ReadRoomLink: AnyObject {
    var snapshot: ReadSnapshot? { get }
    var ended: String? { get }
    func send(_ message: [String: Any]) async throws
    func sendTake(takeID: String, audio: Data, meta: TakeMeta) async throws
    func pickup() async throws -> PickedTake?
}

extension ReadSession: ReadRoomLink {}

/// The routes Publish under my name and the class review use (WorkerPlays in the app, a fake in tests).
protocol RoomPublishing {
    func consent() async throws -> PlaysConsent
    func agree(_ pid: String, version: String) async throws
    func publish(_ pid: String, creditName: String) async throws -> PublishJob
    func sendFile(_ pid: String, lineID: String, audio: Data, contentType: String) async throws
    func review(_ pid: String, takeID: String, state: String, note: String?) async throws
    func upload(_ pid: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws
    func under13(classID: String) async throws -> Bool
}

@Observable
final class ReadRoomRecorder {
    /// Refusals that mean "try again later": the take stays in the outbox.
    nonisolated static let later: Set<String> = ["nobody_receiving", "one_take_at_a_time", "offline", "error", "rate_limited", "timeout",
                                                 "not_configured", "not_delivered"]

    private(set) var armed = false
    /// The line this device's microphone is open on.
    /// Settable so a render can show the Recording state without a microphone.
    var recording: String?
    private(set) var justDid: String?
    private(set) var outbox: [String] = []
    private(set) var receiving = false
    private(set) var arrived = 0
    private(set) var lastError: String?
    /// Why Start Recording did not start (the microphone was refused, or the engine failed).
    private(set) var failed: String?
    private(set) var oneMic = false
    private(set) var localID: String?
    private(set) var engine: RecordingSession?

    let script: PlayScript
    let cast: [(String, String)]
    @ObservationIgnored let store: ProductionStore
    @ObservationIgnored private let link: any ReadRoomLink
    @ObservationIgnored private let publishing: (any RoomPublishing)?
    @ObservationIgnored private let makeSession: (Production, PartID) -> RecordingSession
    @ObservationIgnored private let retry: Duration
    @ObservationIgnored private var sending = false
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var pickupTask: Task<Void, Never>?

    init(link: any ReadRoomLink, store: ProductionStore, script: PlayScript, publishing: (any RoomPublishing)? = nil,
         retry: Duration = .seconds(5), makeSession: @escaping (Production, PartID) -> RecordingSession) {
        self.link = link
        self.store = store
        self.script = script
        self.publishing = publishing
        self.retry = retry
        self.makeSession = makeSession
        cast = script.lines.map { ($0.id, $0.part.rawValue) }
    }

    private func partOf(_ line: String) -> String? { cast.first { $0.0 == line }?.1 }

    var production: Production? { localID.flatMap { store.production($0) } }

    /// Lines with a take on this device.
    var arrivedLines: Set<String> { Set(production?.chosen.keys.map { $0 } ?? []) }

    // MARK: The room's local production

    /// Made on the first take or arrival; its outbox is kept with it.
    @discardableResult
    private func ensureProduction() throws -> Production {
        if let id = localID, let p = store.production(id) { return p }
        guard let code = link.snapshot?.code else { throw ReadFailure(code: "not_a_member") }
        if let found = store.productions.first(where: { $0.room == code }) {
            localID = found.id
            outbox = found.roomOutbox ?? []
            return found
        }
        var made = try store.create(script)
        made.room = code
        made.roomPid = link.snapshot?.productionID
        made.roomOutbox = []
        try store.save(made)
        localID = made.id
        return made
    }

    private func saveOutbox() {
        guard let id = localID, var p = store.production(id) else { return }
        p.roomOutbox = outbox
        store.update(p)
    }

    /// Loads this room's production and its outbox when one exists already: a relaunch keeps waiting takes.
    func resume() {
        if let code = link.snapshot?.code, let found = store.productions.first(where: { $0.room == code }) {
            localID = found.id
            outbox = found.roomOutbox ?? []
        }
        if !outbox.isEmpty { Task { await flush() } }
    }

    private func engineFor() throws -> RecordingSession {
        if let engine { return engine }
        let p = try ensureProduction()
        let part = link.snapshot.flatMap { partOf($0.cursor) } ?? cast.first?.1 ?? PartID.directions.rawValue
        let made = makeSession(p, PartID(rawValue: part))
        engine = made
        return made
    }

    // MARK: Start recording, Stop

    /// Start Recording: the one tap a reader gives before the first take (the permission and room tone, no headphones gate).
    func arm(permission: () async -> Bool) async {
        guard await permission() else { failed = "microphone"; return }
        do {
            let e = try engineFor()
            await e.begin(echoCancelled: false)
            if case let .failed(reason) = e.phase { failed = reason; armed = false } else { armed = e.started; failed = armed ? nil : "start" }
        } catch {
            failed = "start"
            return
        }
        if armed { onSnapshot() }
    }

    /// Stop: the reader's tap ends the take now (the line-end detector ends it on its silence otherwise).
    func stop() { engine?.stopListening() }

    func setOneMic(_ on: Bool) {
        oneMic = on
        onSnapshot()
    }

    // MARK: Recording a line

    private func startRecording(_ line: String, credit: Bool) {
        recording = line
        justDid = line
        #if DEBUG
        if ProcessInfo.processInfo.environment["APP_READ_DIAG"] == "1" {
            print("[readdiag] rec \(line) at \(Date().timeIntervalSince1970 * 1000) offset \((link as? ReadSession)?.clockOffsetMS ?? .nan)")
        }
        #endif
        Task { await record(line, credit: credit) }
    }

    private func record(_ line: String, credit: Bool) async {
        guard let part = partOf(line), let e = try? engineFor() else { recording = nil; justDid = nil; return }
        let take = await e.recordInRoom(line, part: PartID(rawValue: part))
        recording = nil
        if stopped { return }
        guard let take else { justDid = nil; return }
        let now = link.snapshot
        if credit {
            await creditOwn(take, snap: now)
            if let next = ReadCore.step(cast, cursor: line, delta: 1), let now, now.cursor == line {
                try? await link.send(["type": "cursor", "line": next, "base": now.cursorGen])
            }
        } else {
            outbox.append(take.id)
            saveOutbox()
            if let now, now.cursor == line { try? await link.send(["type": "line-done", "line": line, "base": now.cursorGen]) }
            await flush()
        }
    }

    /// One microphone: the take is already here. A room with a production writes it there as the director's own take.
    private func creditOwn(_ take: Take, snap: ReadSnapshot?) async {
        guard let snap, let pid = snap.productionID, let publishing, let id = localID,
              let bytes = try? store.readTake(id, file: take.file) else { return }
        var meta = PlaysShare.metaOf(take)
        let members = snap.members.map { ReadCore.Member(id: $0.id, role: $0.role, seat: $0.seat, joinedAt: 0, seenAt: 0, name: $0.name) }
        meta.seat = ReadCore.whoReads(snap.room, cast: cast, members: members, lineID: take.lineID, now: 0)?.seat
        do { try await publishing.upload(pid, takeID: take.id, audio: bytes, contentType: PlaysShare.contentType(take.file), meta: meta) } catch {
            lastError = (error as? PlaysRefusal)?.code ?? "error"
        }
    }

    // MARK: The outbox

    /// Sends the outbox one take at a time; a "later" refusal stops and waits, any other refusal takes the take out of the
    /// outbox (it stays on this device).
    func flush() async {
        guard !sending, !stopped, !outbox.isEmpty, link.snapshot != nil, link.ended == nil else { return }
        sending = true
        defer { sending = false }
        while let id = outbox.first, !stopped {
            guard let local = localID, let p = store.production(local), let take = p.take(id),
                  let bytes = try? store.readTake(local, file: take.file) else { outbox.removeFirst(); continue }
            do {
                try await link.sendTake(takeID: take.id, audio: bytes, meta: PlaysShare.metaOf(take))
                outbox.removeFirst()
                lastError = nil
            } catch let f as ReadFailure {
                lastError = f.code
                if Self.later.contains(f.code) { break }
                outbox.removeFirst()
            } catch {
                lastError = "error"
                break
            }
            saveOutbox()
        }
        saveOutbox()
        if !outbox.isEmpty, !stopped { scheduleRetry() }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self, retry] in
            try? await Task.sleep(for: retry)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    // MARK: The receiver's pickup

    private func holdPickup() {
        guard pickupTask == nil else { return }
        receiving = true
        pickupTask = Task { [weak self] in
            var wait = 0
            while !Task.isCancelled {
                guard let self, !self.stopped, self.link.snapshot != nil, self.link.ended == nil else { break }
                do {
                    let got = try await self.link.pickup()
                    wait = 0
                    if let got, !Task.isCancelled { self.accept(got) }
                } catch let f as ReadFailure {
                    if ["receivers_only", "not_a_member", "room_ended", "no_such_room"].contains(f.code) { break }
                    wait = min(30, wait == 0 ? 2 : wait * 2)
                    try? await Task.sleep(for: .seconds(wait))
                } catch { break }
            }
            self?.receiving = false
            self?.pickupTask = nil
        }
    }

    private func dropPickup() {
        pickupTask?.cancel()
        pickupTask = nil
        receiving = false
    }

    /// A take that arrived: written once under its own id, the line's chosen take (the newest wins, as on the Worker).
    func accept(_ got: PickedTake) {
        guard let p = try? ensureProduction(), p.take(got.fields.id) == nil else { return }
        let ext = got.fields.file.map { ($0 as NSString).pathExtension }.flatMap { $0.isEmpty ? nil : $0 } ?? "wav"
        let file = "r-\(got.fields.id).\(ext)"
        guard (try? store.importTake(p.id, file: file, data: got.data)) != nil else { return }
        let take = Take(id: got.fields.id, lineID: got.fields.lineID, part: PartID(rawValue: got.fields.part), file: file, created: .now,
                        frames: got.fields.frames, sampleRate: got.fields.sampleRate, capture: .room, heard: [:], loudness: nil,
                        peak: 0, bleed: false)
        guard var latest = store.production(p.id) else { return }
        latest.add(take)
        store.update(latest)
        arrived += 1
    }

    // MARK: Every snapshot

    /// Settles `justDid`, opens the microphone when it is this device's line, holds or drops the pickup, sends the outbox.
    func onSnapshot() {
        guard !stopped, let s = link.snapshot else { return }
        justDid = ReadCore.settleJustDid(s, justDid)
        if s.ended { dropPickup(); return }
        let isRecordMode = s.mode == "record"
        if isRecordMode, s.you?.receives == true { holdPickup() } else if pickupTask != nil { dropPickup() }
        if armed, recording == nil {
            if oneMic, s.you?.leads == true, isRecordMode {
                if let part = partOf(s.cursor), PartID(rawValue: part).isSpeaking, !s.done.contains(s.cursor), justDid != s.cursor {
                    startRecording(s.cursor, credit: true)
                }
            } else if ReadCore.shouldRecord(s, cast: cast, justDid: justDid) {
                startRecording(s.cursor, credit: false)
            }
        }
        if !outbox.isEmpty { Task { await flush() } }
    }

    func detach() {
        stopped = true
        dropPickup()
        retryTask?.cancel()
        engine?.end()
    }

    // MARK: Publish under my name (PLAYS-DESIGN §12.10 item 5)

    /// The credit name and CC0 consent, then each line's chosen take to archive.org one at a time, the Worker answering
    /// `not_ready` until the cron has laid the item out. Returns the refusal's code, or nil when every line went.
    func publish(creditName: String, pid: String, waitBetween: Duration = .seconds(60), tries: Int = 30) async -> String? {
        guard let publishing, let id = localID else { return "error" }
        do {
            let consent = try await publishing.consent()
            try await publishing.agree(pid, version: consent.version)
            _ = try await publishing.publish(pid, creditName: creditName)
        } catch {
            return (error as? PlaysRefusal)?.code ?? "error"
        }
        for line in script.lines {
            guard let p = store.production(id), let take = p.chosenTake(for: line.id),
                  let bytes = try? store.readTake(id, file: take.file) else { continue }
            var sent = false
            for _ in 0..<tries where !sent {
                do {
                    try await publishing.sendFile(pid, lineID: line.id, audio: bytes, contentType: PlaysShare.contentType(take.file))
                    sent = true
                } catch let r as PlaysRefusal {
                    if r.code == "already_sent" { sent = true; break }
                    if r.code == "not_ready" || r.status == 503 { try? await Task.sleep(for: waitBetween); continue }
                    return r.code ?? "error"
                } catch { return "error" }
            }
            if !sent { return "not_ready" }
        }
        return nil
    }
}

extension WorkerPlays: RoomPublishing {
    func publish(_ pid: String, creditName: String) async throws -> PublishJob {
        try await publishWithCredit(pid, creditName: creditName)
    }

    func sendFile(_ pid: String, lineID: String, audio: Data, contentType: String) async throws {
        try await archiveFile(pid, lineID: lineID, audio: audio, contentType: contentType)
    }

    func review(_ pid: String, takeID: String, state: String, note: String?) async throws {
        try await reviewTake(pid, takeID: takeID, state: state, note: note)
    }

    func under13(classID: String) async throws -> Bool {
        try await classes().teaching.first { $0.id == classID }?.under13 ?? true
    }
}
#endif
