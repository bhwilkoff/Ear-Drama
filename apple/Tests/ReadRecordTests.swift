import Foundation
import Testing

/// Record in the room (PLAYS-DESIGN §12.10), the mirror of the Record tests in js/read.test.js, over a fake room link
/// and a fake microphone: nothing is recorded aloud or sent anywhere. Each rule's break, seen to fail (2026-11-19, all
/// three broken in one run, 7 issues, then restored byte for byte):
///   "not_your_line" added to the refusals that wait in the outbox: anyOtherRefusalLeavesTheOutbox... failed.
///   `settleJustDid` never clearing: againReArms and settleJustDidClears... failed.
///   `shouldRecord` without the receiver check: aReceiverNeverRecordsItsOwnReaderLine and shouldRecordOnly... failed.
/// The snapshot's `receiver` missing from its coding keys was caught by the golden harness (ReadCoreTests, "snapshot receives").

@MainActor
private final class FakeLink: ReadRoomLink {
    var snapshot: ReadSnapshot?
    var ended: String?
    var sent: [[String: Any]] = []
    var takes: [(id: String, bytes: Data, meta: TakeMeta)] = []
    var refusals: [String] = []
    var arrivals: [PickedTake] = []

    func send(_ message: [String: Any]) async throws { sent.append(message) }

    func sendTake(takeID: String, audio: Data, meta: TakeMeta) async throws {
        if !refusals.isEmpty { throw ReadFailure(code: refusals.removeFirst()) }
        takes.append((takeID, audio, meta))
    }

    func pickup() async throws -> PickedTake? {
        if !arrivals.isEmpty { return arrivals.removeFirst() }
        try? await Task.sleep(for: .seconds(3600))
        return nil
    }
}

/// A microphone that hears room tone first, then one short voiced line each time it is opened; it plays nothing.
@MainActor
private final class FakeMic: LiveAudio {
    private var captures = 0
    private var captured: [Float] = []
    private(set) var played = 0

    func outputRoute() -> AudioRoute { .speaker }
    func start(echoCancelled: Bool) throws {}
    func stop() {}
    func play(_ cue: CueAudio) async { played += 1 }

    func beginCapture(_ onChunk: @escaping @MainActor @Sendable ([Float]) -> Void) {
        captures += 1
        let signal: [Float]
        if captures == 1 {
            signal = (0..<48_000).map { _ in Float.random(in: -0.0005...0.0005) }
        } else {
            let voice = (0..<28_800).map { i -> Float in
                let t = Double(i) / 48_000
                return 0.3 * Float((sin(2 * .pi * 150 * t) + sin(2 * .pi * 175 * t)) / 2)
            }
            signal = [Float](repeating: 0, count: 9_600) + voice + [Float](repeating: 0, count: 60_000)
        }
        captured = signal
        for start in stride(from: 0, to: signal.count, by: 960) {
            onChunk(Array(signal[start..<min(start + 960, signal.count)]))
        }
    }

    func endCapture() -> MicrophoneCapture {
        defer { captured = [] }
        return MicrophoneCapture(samples: captured, sampleRate: 48_000)
    }
}

@MainActor
private final class FakePublishing: RoomPublishing {
    var calls: [String] = []
    var credit: String?
    var fileRefusals: [String: [PlaysRefusal]] = [:]
    var files: [String] = []
    var reviews: [String] = []
    var uploads: [(String, TakeMeta)] = []

    func consent() async throws -> PlaysConsent { PlaysConsent(version: "v1", text: "CC0", uploads: true, publishes: true) }
    func agree(_ pid: String, version: String) async throws { calls.append("agree:\(version)") }
    func publish(_ pid: String, creditName: String) async throws -> PublishJob { calls.append("publish"); credit = creditName; return PublishJob(status: "queued") }
    func sendFile(_ pid: String, lineID: String, audio: Data, contentType: String) async throws {
        if var queue = fileRefusals[lineID], !queue.isEmpty { let r = queue.removeFirst(); fileRefusals[lineID] = queue; throw r }
        files.append(lineID)
    }
    func review(_ pid: String, takeID: String, state: String, note: String?) async throws { reviews.append("\(takeID):\(state):\(note ?? "")") }
    func upload(_ pid: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws { uploads.append((takeID, meta)) }
    func under13(classID: String) async throws -> Bool { false }
}

private func line(_ id: String, _ role: String?, _ kind: ScriptLine.Kind = .speech) -> ScriptLine {
    kind == .speech ? ScriptLine(id: id, kind: .speech, role: role, parts: [.say("Words of \(id).")]) : ScriptLine(id: id, kind: kind, source: "(\(id))")
}

/// The golden file's play: directions, LUCY, TOM, LUCY, sound, TOM, NURSE, LUCY.
private func play() -> PlayScript {
    let lines = [line("l1", nil, .direction), line("l2", "LUCY"), line("l3", "TOM"), line("l4", "LUCY"), line("l5", nil, .sound),
                 line("l6", "TOM"), line("l7", "NURSE"), line("l8", "LUCY")]
    let roles = ["LUCY", "TOM", "NURSE"].map { n in PlayScript.Role(name: n, lines: lines.filter { $0.role == n }.count, words: 3) }
    return PlayScript(id: "gut-1", revision: "r1", kind: "radio", title: "The Lost Lady", authors: [],
                      source: .init(name: "Fixture", url: "https://example.org"),
                      rights: .init(bucket: "script_source_cleared", evidence: []), roles: roles, lines: lines)
}

private func snapshot(_ you: String = "ann", mode: String = "record", cursor: String = "l2", done: [String] = [], receives: Bool = false,
                      leads: Bool = false, kind: String = "adult", claims: [String: String] = ["role:LUCY": "ann", "role:TOM": "host"],
                      role: String = "reader", production: String? = nil, generation: Int = 1) throws -> ReadSnapshot {
    var o: [String: Any] = [
        "type": "snapshot", "code": "ABC123", "kind": kind, "mode": mode, "script_id": "gut-1", "script_revision": "r1",
        "cursor": cursor, "cursor_gen": generation, "generation": generation, "locked": false, "ended": false, "leader": "host",
        "waiting_for_leader": false, "present": 3, "claims": claims, "seats": [], "assignments": [], "done": done,
        "server_time": Double(generation) * 1000, "receiver": "host", "read_open": false,
        "you": ["id": you, "role": role, "name": "Ann", "leads": leads, "owner": false, "receives": receives],
        "members": [["id": "host", "role": "reader", "name": "Ben", "live": true], ["id": "ann", "role": "reader", "name": "Ann", "live": true],
                    ["id": "bob", "role": "reader", "name": "Bob", "live": true]],
    ]
    if let production { o["production_id"] = production }
    return try JSONDecoder().decode(ReadSnapshot.self, from: JSONSerialization.data(withJSONObject: o))
}

private func until(_ done: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<500 {
        if done() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return done()
}

@MainActor
struct ReadRecordTests {
    private struct Rig {
        let link: FakeLink
        let store: ProductionStore
        let recorder: ReadRoomRecorder
        let mic: FakeMic
        let publishing: FakePublishing
    }

    private func rig(_ first: ReadSnapshot, store: ProductionStore? = nil) throws -> Rig {
        let link = FakeLink()
        link.snapshot = first
        let store = store ?? ProductionStore(root: FileManager.default.temporaryDirectory.appending(path: "room-tests-\(UUID().uuidString)"))
        let mic = FakeMic()
        let publishing = FakePublishing()
        let script = play()
        let recorder = ReadRoomRecorder(link: link, store: store, script: script, publishing: publishing, retry: .seconds(3600)) { p, part in
            RecordingSession(production: p, script: script, part: part, store: store, audio: mic, voice: NoVoice(), sleep: { _ in }, announce: {})
        }
        return Rig(link: link, store: store, recorder: recorder, mic: mic, publishing: publishing)
    }

    @MainActor private final class NoVoice: StandInVoice {
        func render(_ text: String, part: PartID, rate: Float) async -> StandInAudio? { nil }
    }

    private func arm(_ r: Rig) async {
        await r.recorder.arm { true }
        #expect(r.recorder.armed)
    }

    @Test func aHoldersDeviceRecordsItsLineSendsLineDoneAndTheTakeGoesToTheReceiver() async throws {
        let r = try rig(snapshot())
        await arm(r)
        r.recorder.onSnapshot()
        #expect(await until { r.link.takes.count == 1 })
        let sent = try #require(r.link.takes.first)
        #expect(sent.meta.capture == "room" && sent.meta.part == "role:LUCY" && sent.meta.lineID == "l2")
        #expect(r.link.sent.contains { $0["type"] as? String == "line-done" && $0["line"] as? String == "l2" })
        #expect(r.recorder.outbox.isEmpty)
        let p = try #require(r.recorder.production)
        #expect(p.room == "ABC123" && p.takes.count == 1 && p.chosenTake(for: "l2")?.capture == .room)
        #expect(p.roomOutbox == [])
        r.recorder.onSnapshot()
        try await Task.sleep(for: .milliseconds(50))
        #expect(r.link.takes.count == 1, "the line is not recorded twice for one arming")
    }

    /// T7c: the leader's press raced a take; the take ended with the cursor elsewhere and its line was never marked done,
    /// so the cursor coming back opened the microphone again. The line-done goes out whatever the cursor is now.
    @Test func aTakeThatEndsAfterTheCursorMovedStillSendsItsLineDone() async throws {
        let r = try rig(snapshot())
        await arm(r)
        r.recorder.onSnapshot()
        #expect(r.recorder.recording == "l2")
        r.link.snapshot = try snapshot(cursor: "l1", generation: 2)
        r.recorder.onSnapshot()
        #expect(await until { r.link.takes.count == 1 })
        let done = r.link.sent.first { $0["type"] as? String == "line-done" }
        #expect(done?["line"] as? String == "l2", "the take's line is done although the leader moved the cursor")
        #expect(done?["base"] as? Int == 2)
        r.link.snapshot = try snapshot(cursor: "l2", done: ["l2"], generation: 3)
        r.recorder.onSnapshot()
        try await Task.sleep(for: .milliseconds(50))
        #expect(r.link.takes.count == 1, "the cursor back on the done line opens no second microphone")
    }

    @Test func aNoCueIsPlayedInTheRoom() async throws {
        let r = try rig(snapshot())
        await arm(r)
        r.recorder.onSnapshot()
        #expect(await until { r.link.takes.count == 1 })
        #expect(r.mic.played == 0)
    }

    @Test func outboxWaitsOnNobodyReceivingAndSendsLater() async throws {
        let r = try rig(snapshot())
        r.link.refusals = ["nobody_receiving"]
        await arm(r)
        r.recorder.onSnapshot()
        #expect(await until { r.recorder.lastError == "nobody_receiving" })
        #expect(r.link.takes.isEmpty && r.recorder.outbox.count == 1)
        #expect(r.recorder.production?.roomOutbox == r.recorder.outbox, "the outbox is kept with the room's production")
        #expect(r.link.sent.contains { $0["type"] as? String == "line-done" }, "the cursor still moves on while the take waits")
        await r.recorder.flush()
        #expect(r.link.takes.count == 1 && r.recorder.outbox.isEmpty && r.recorder.lastError == nil)
        #expect(r.recorder.production?.roomOutbox == [])
    }

    @Test func theOutboxSurvivesARelaunch() async throws {
        let r = try rig(snapshot())
        r.link.refusals = ["offline"]
        await arm(r)
        r.recorder.onSnapshot()
        #expect(await until { r.recorder.outbox.count == 1 })
        let waiting = r.recorder.outbox
        let again = try rig(snapshot(), store: r.store)
        again.recorder.resume()
        #expect(again.recorder.outbox == waiting)
        #expect(await until { again.link.takes.count == 1 })
        #expect(again.recorder.outbox.isEmpty)
    }

    @Test func anyOtherRefusalLeavesTheOutboxButKeepsTheTakeOnTheDevice() async throws {
        let r = try rig(snapshot())
        r.link.refusals = ["not_your_line"]
        await arm(r)
        r.recorder.onSnapshot()
        #expect(await until { r.recorder.lastError == "not_your_line" })
        #expect(r.recorder.outbox.isEmpty && r.link.takes.isEmpty)
        #expect(r.recorder.production?.takes.count == 1)
    }

    @Test func againReArms() async throws {
        let r = try rig(snapshot())
        await arm(r)
        r.recorder.onSnapshot()
        #expect(await until { r.link.takes.count == 1 })
        r.link.snapshot = try snapshot(done: ["l2"], generation: 2)
        r.recorder.onSnapshot()
        try await Task.sleep(for: .milliseconds(30))
        #expect(r.link.takes.count == 1, "a done line is not recorded")
        r.link.snapshot = try snapshot(done: [], generation: 3)
        r.recorder.onSnapshot()
        #expect(await until { r.link.takes.count == 2 })
        let p = try #require(r.recorder.production)
        #expect(p.takes(for: "l2").count == 2 && p.chosen["l2"] == r.link.takes.last?.id, "the newest take is the chosen one")
    }

    @Test func aReceiverNeverRecordsItsOwnReaderLine() async throws {
        let r = try rig(snapshot("host", cursor: "l3", receives: true, leads: true))
        await arm(r)
        r.recorder.onSnapshot()
        try await Task.sleep(for: .milliseconds(50))
        #expect(r.recorder.recording == nil && r.recorder.production?.takes.isEmpty != false)
    }

    @Test func oneMicrophoneCreditsThePartAndMovesOn() async throws {
        let r = try rig(snapshot("host", cursor: "l2", receives: true, leads: true, production: "P1"))
        r.recorder.setOneMic(true)
        await arm(r)
        r.recorder.onSnapshot()
        #expect(await until { r.link.sent.contains { $0["type"] as? String == "cursor" } })
        let p = try #require(r.recorder.production)
        #expect(p.chosenTake(for: "l2")?.part == .role("LUCY"), "LUCY's line, though the leader's device recorded it")
        #expect(p.chosenTake(for: "l2")?.capture == .room)
        #expect(r.link.takes.isEmpty, "the take stays here")
        let move = try #require(r.link.sent.first { $0["type"] as? String == "cursor" })
        #expect(move["line"] as? String == "l3")
        #expect(await until { r.publishing.uploads.count == 1 }, "a room with a production writes the director's own take")
        #expect(r.publishing.uploads.first?.1.capture == "room")
    }

    @Test func theReceiverImportsArrivalsAsTheLinesChosenTakes() async throws {
        let r = try rig(snapshot("host", cursor: "l2", receives: true, leads: true))
        func arrival(_ id: String, line: String = "l2") -> PickedTake {
            PickedTake(fields: .init(id: id, lineID: line, part: "role:LUCY", frames: 4_800, sampleRate: 48_000, capture: "room", seat: nil,
                                     file: "x.wav", member: "ann"), data: Data([1, 2, 3]))
        }
        r.link.arrivals = [arrival("a1"), arrival("a2"), arrival("a2"), arrival("b1", line: "l4")]
        r.recorder.onSnapshot()
        #expect(await until { r.recorder.production?.takes.count == 3 })
        let p = try #require(r.recorder.production)
        #expect(p.chosen["l2"] == "a2" && p.chosen["l4"] == "b1", "the newest take of a line is its chosen one; the same id is imported once")
        #expect(r.recorder.arrivedLines == ["l2", "l4"])
        #expect(r.recorder.receiving)
        #expect(p.takes.allSatisfy { $0.file.hasPrefix("r-") && $0.file.hasSuffix(".wav") })
        r.link.snapshot = try snapshot("host", mode: "read", cursor: "l2", receives: true, leads: true, generation: 2)
        r.recorder.onSnapshot()
        #expect(!r.recorder.receiving, "the pickup is held only while the room records")
        r.recorder.detach()
    }

    @Test func publishSendsEachChosenTakeAndWaitsOutNotReady() async throws {
        let r = try rig(snapshot("host", cursor: "l2", receives: true, leads: true, kind: "class", production: "P1"))
        func arrival(_ id: String, line: String) -> PickedTake {
            PickedTake(fields: .init(id: id, lineID: line, part: "role:LUCY", frames: 4_800, sampleRate: 48_000, capture: "room", seat: nil,
                                     file: "x.flac", member: nil), data: Data([9]))
        }
        r.recorder.accept(arrival("a1", line: "l2"))
        r.recorder.accept(arrival("a2", line: "l3"))
        r.publishing.fileRefusals["l2"] = [PlaysRefusal.code("not_ready"), PlaysRefusal.code("not_ready")]
        r.publishing.fileRefusals["l3"] = [PlaysRefusal.code("already_sent")]
        let failure = await r.recorder.publish(creditName: "Ms. Ortiz", pid: "P1", waitBetween: .milliseconds(1))
        #expect(failure == nil)
        #expect(r.publishing.credit == "Ms. Ortiz" && r.publishing.calls == ["agree:v1", "publish"])
        #expect(r.publishing.files == ["l2"], "not_ready waited and retried; already_sent was skipped")
        r.publishing.fileRefusals["l2"] = [PlaysRefusal.code("not_a_director", status: 403)]
        r.publishing.files = []
        let refused = await r.recorder.publish(creditName: "Ms. Ortiz", pid: "P1", waitBetween: .milliseconds(1))
        #expect(refused == "not_a_director")
    }

    @Test func recordInRoomIsTheStudiosEngineWithNoCue() async throws {
        let script = play()
        let store = ProductionStore(root: FileManager.default.temporaryDirectory.appending(path: "room-tests-\(UUID().uuidString)"))
        let production = try store.create(script)
        let mic = FakeMic()
        let session = RecordingSession(production: production, script: script, part: .role("TOM"), store: store, audio: mic, voice: NoVoice(),
                                       sleep: { _ in }, announce: {})
        await session.begin(echoCancelled: false)
        let take = try #require(await session.recordInRoom("l2", part: .role("LUCY")))
        #expect(take.part == .role("LUCY") && take.capture == .room && take.lineID == "l2")
        #expect(mic.played == 0 && session.phase == .idle)
        #expect(session.production.chosen["l2"] == take.id)
    }

    @Test func aProductionWrittenBeforeRoomsDecodesAndAStudioNeverPicksARoomProduction() throws {
        let script = play()
        var p = Production(script: script)
        let old = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(Production.self, from: old).room == nil)
        p.room = "ABC123"
        p.roomOutbox = ["t1"]
        #expect(try JSONDecoder().decode(Production.self, from: JSONEncoder().encode(p)).roomOutbox == ["t1"])
        #expect(StudioCore.productionFor([p], isShared: { _ in false }, script: script, part: .role("LUCY")) == .make)
        #expect(StudioCore.reusableEmpty([p], isShared: { _ in false }, scriptID: script.id) == nil)
    }
}

// MARK: - The rules, pure

@MainActor
struct ReadRoomRulesTests {
    private func lines() -> [(String, String)] {
        [("l1", "directions"), ("l2", "role:LUCY"), ("l3", "role:TOM"), ("l4", "role:LUCY"), ("l5", "sound"), ("l6", "role:TOM"),
         ("l7", "role:NURSE"), ("l8", "role:LUCY")]
    }

    @Test func shouldRecordOnlyForAHeldLineAtTheCursorInRecordMode() throws {
        let cast = lines()
        #expect(ReadCore.shouldRecord(try snapshot(cursor: "l2"), cast: cast, justDid: nil))
        #expect(!ReadCore.shouldRecord(try snapshot(cursor: "l3"), cast: cast, justDid: nil), "another part's line")
        #expect(!ReadCore.shouldRecord(try snapshot(mode: "read", cursor: "l2"), cast: cast, justDid: nil))
        #expect(!ReadCore.shouldRecord(try snapshot(cursor: "l2", done: ["l2"]), cast: cast, justDid: nil))
        #expect(!ReadCore.shouldRecord(try snapshot(cursor: "l2"), cast: cast, justDid: "l2"), "not twice for one arming")
        #expect(!ReadCore.shouldRecord(try snapshot(cursor: "l2", receives: true), cast: cast, justDid: nil), "the receiver records only in One microphone")
        #expect(!ReadCore.shouldRecord(try snapshot(cursor: "l2", role: "screen"), cast: cast, justDid: nil))
        #expect(!ReadCore.shouldRecord(nil, cast: cast, justDid: nil))
    }

    @Test func settleJustDidClearsOnceTheLineIsDoneOrTheCursorMoves() throws {
        #expect(ReadCore.settleJustDid(try snapshot(cursor: "l2"), "l2") == "l2")
        #expect(ReadCore.settleJustDid(try snapshot(cursor: "l2", done: ["l2"]), "l2") == nil)
        #expect(ReadCore.settleJustDid(try snapshot(cursor: "l4"), "l2") == nil)
        #expect(ReadCore.settleJustDid(try snapshot(), nil) == nil)
    }

    @Test func takeRowsCountPerReaderWithEachLinesState() throws {
        let snap = try snapshot("host", cursor: "l4", done: ["l4"], receives: true, claims: ["role:LUCY": "ann", "role:TOM": "bob"])
        let table = ReadCore.takeRows(snap, cast: lines(), arrived: ["l2"]) { $0.hasPrefix("role:") }
        #expect(table.rows.map(\.line) == ["l2", "l3", "l4", "l6", "l7", "l8"], "speaking lines in script order")
        #expect(table.rows.map(\.state) == [.recorded, .waiting, .away, .waiting, .open, .waiting])
        let ann = try #require(table.counts.first { $0.holder == "ann" })
        #expect(ann.lines == 3 && ann.recorded == 1, "counts per reader, never a ranking")
        #expect(table.counts.count == 2, "an open line belongs to no one")
    }

    @Test func aReadersNameIsTheNameTheyGaveAndTheLeadersNameIsTheOwnersFirst() throws {
        let snap = try snapshot("bob", cursor: "l2")
        let reads = ReadSnapshot.ReadsNow(part: "role:LUCY", seat: nil, holder: "ann", members: ["ann"])
        #expect(ReadCore.readerName(snap, reads) == "Ann")
        #expect(ReadCore.readerName(snap, .init(part: "role:LUCY", seat: nil, holder: nil, members: [])) == nil)
        #expect(RoomText.line(snap, status: "Slow connection") == "Slow connection", "a warning comes first")
    }

    @Test func theRefusalsHaveTheirOwnWordsAndNeverCouldNotBeReachedForAMissingRoom() {
        #expect(ReadCore.refusal("no_such_room") == "No reading with that code.")
        #expect(ReadCore.refusal("room_ended") == "This reading has ended.")
        #expect(ReadCore.refusal("bad_name") == "That name is not allowed.")
        #expect(ReadCore.refusal("no_such_pair") == "No screen shows that code.")
        #expect(ReadCore.refusal("pair_expired") == "That code has expired.")
        func code(_ status: Int, _ body: String) -> String { ReadFailure.of(status: status, data: Data(body.utf8)).code }
        #expect(code(404, "{\"error\":\"no_such_room\"}") == "no_such_room")
        #expect(code(410, "{\"error\":\"room_ended\"}") == "room_ended")
        #expect(code(404, "{\"error\":\"not_found\"}") == "no_such_room", "a route the Worker does not know reads by its status")
        #expect(code(404, "<html>Not found</html>") == "no_such_room")
        #expect(code(410, "") == "room_ended")
        #expect(code(429, "{}") == "rate_limited")
        #expect(code(422, "{\"error\":\"bad_name\"}") == "bad_name")
        #expect(ReadCore.refusal(code(500, "")) == "Ear Drama could not be reached.", "only a real failure says so")
    }

    @Test func theScreensVoiceSpeaksOnlyAnOpenLineWhileReadOpenIsOnAndStopsWhenTheCursorMoves() throws {
        func open(_ cursor: String, on: Bool, held: Bool = false) throws -> ReadSnapshot {
            var o = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try snapshot(cursor: cursor))) as! [String: Any]
            o["read_open"] = on
            o["reads_now"] = ["part": "role:LUCY", "holder": held ? "ann" : NSNull(), "members": held ? ["ann"] : []] as [String: Any]
            return try JSONDecoder().decode(ReadSnapshot.self, from: JSONSerialization.data(withJSONObject: o))
        }
        let a = ReadScreenVoice.step(try open("l2", on: true), spokenAt: nil)
        #expect(a.speak == "l2" && !a.cancel)
        #expect(ReadScreenVoice.step(try open("l2", on: true), spokenAt: a.spokenAt).speak == nil, "a line is read once")
        let moved = ReadScreenVoice.step(try open("l4", on: true), spokenAt: "l2")
        #expect(moved.cancel && moved.speak == "l4", "the voice stops the moment the cursor moves")
        #expect(ReadScreenVoice.step(try open("l2", on: false), spokenAt: nil).speak == nil, "never while Read Open Parts is off")
        #expect(ReadScreenVoice.step(try open("l2", on: true, held: true), spokenAt: nil).speak == nil, "never a line someone holds")
        let off = ReadScreenVoice.step(try open("l2", on: false), spokenAt: "l2")
        #expect(off.cancel && off.speak == nil)
    }
}

// MARK: - Pairing a TV

@MainActor
struct ReadPairingTests {
    nonisolated private final class Wire: ReadWire, @unchecked Sendable {
        var codes = ["ABC123", "DEF456"]
        var waits: [Result<ReadJoined?, ReadFailure>] = []
        var asked = 0
        func create(body: Data, teacher: Bool) async throws -> ReadJoined { throw ReadFailure(code: "error") }
        func join(code: String, body: Data) async throws -> ReadJoined { throw ReadFailure(code: "error") }
        var polls: [String: String] = [:]
        func poll(code: String, key: String) async throws -> ReadSnapshot { throw ReadFailure(code: polls[code] ?? "not_a_member") }
        func send(code: String, key: String, message: Data) async throws -> ReadSnapshot? { nil }
        func socket(code: String) -> (any ReadSocket)? { nil }
        func sendTake(code: String, key: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws {}
        func inbox(code: String, key: String) async throws -> PickedTake? { nil }
        func pair() async throws -> ReadPairing { asked += 1; return ReadPairing(code: codes.removeFirst(), key: "k", expiresAt: 1) }
        func pairWait(_ pairing: ReadPairing) async throws -> ReadJoined? {
            guard !waits.isEmpty else { return nil }
            return try waits.removeFirst().get()
        }
        func attachScreen(code: String, key: String, pairCode: String) async throws {}
    }

    private func joined() throws -> ReadJoined {
        ReadJoined(snapshot: try snapshot("tv", mode: "read", role: "screen"), key: "member-key", transport: "poll")
    }

    @Test func aRoomIsCheckedBeforeTheJoinFormShowsAMissingOrEndedOneNamesItself() async {
        let wire = Wire()
        wire.polls = ["ZZZZZZ": "no_such_room", "ENDED1": "room_ended"]
        #expect(await wire.gone(code: "ZZZZZZ") == "no_such_room")
        #expect(await wire.gone(code: "ENDED1") == "room_ended")
        #expect(await wire.gone(code: "LIVE01") == nil, "a live room refuses a keyless poll as a member check and shows its form")
    }

    @Test func theTVAsksForACodeThenPollsUntilALeaderAttachesIt() async throws {
        let wire = Wire()
        wire.waits = [.success(nil), .success(nil), .success(try joined())]
        let model = ReadPairingModel(wire: wire, sleep: { _ in })
        await model.run()
        #expect(model.pairing?.code == "ABC123" && wire.asked == 1, "one code, kept while waiting")
        #expect(model.joined?.key == "member-key" && model.joined?.snapshot.you?.role == "screen")
        #expect(model.status.isEmpty)
    }

    @Test func anExpiredCodeIsReplacedWithoutAWord() async throws {
        let wire = Wire()
        wire.waits = [.failure(ReadFailure(code: "pair_expired")), .success(try joined())]
        let model = ReadPairingModel(wire: wire, sleep: { _ in })
        await model.run()
        #expect(wire.asked == 2 && model.pairing?.code == "DEF456" && model.status.isEmpty)
        #expect(model.joined != nil)
    }

    @Test func aRefusalWorthShowingIsShownAndTheCodeIsKept() async throws {
        let wire = Wire()
        wire.waits = [.failure(ReadFailure(code: "offline"))]
        let model = ReadPairingModel(wire: wire, sleep: { _ in })
        await model.step()
        await model.step()
        #expect(model.status == "You are offline." && model.pairing?.code == "ABC123")
    }

    @Test func theCodeShowsSplitThreeAndThree() {
        #expect(ReadScreenText.grouped("ABC123") == "ABC 123")
        #expect(ReadPairView.codeSize >= 76)
    }
}
