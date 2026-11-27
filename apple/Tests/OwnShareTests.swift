import CryptoKit
import Foundation
import Testing

/// Own scripts shared (PLAYS-DESIGN §13 items 11 to 16; R4-5 on Apple), the Swift twin of js/own-share.test.js: the text sent once
/// and as it was hashed, owed and tried again, a share undone when it can never pass, the one resolver at every door and what it
/// refuses to draw, the freeze and Edit a Copy, and the words. A stub Worker answers as worker/src/plays-own.js does.
///
/// Broken controls (apple/Tests/OwnShareMutants.py), each seen to fail before the rule was kept:
///   canonicalLines sending the lines unsorted / pretty: shareSendsTheLinesOnce failed.
///   passes() treating 4xx as passing: aSendingThatCanNeverPassUndoesTheShare failed.
///   passes() treating a network error as final: aSendingThatMayPassLeavesItOwed failed.
///   sendOrUndo not freezing after a passing failure: aSendingThatMayPassLeavesItOwed failed.
///   arrived skipping the digest: whatDidNotArriveWholeIsNeverDrawn failed.
///   arrived skipping the canonical-form check: whatDidNotArriveWholeIsNeverDrawn failed.
///   arrived skipping the core's refusalOf: whatDidNotArriveWholeIsNeverDrawn failed.
///   arrived skipping x-script's id or revision: whatDidNotArriveWholeIsNeverDrawn failed.
///   arrived skipping the fit: theLinesMatchTheCastSheetAsEachDoorKnowsIt failed.
///   Fit.invite ignoring a part's line count: theLinesMatchTheCastSheetAsEachDoorKnowsIt failed.
///   Fit.room ignoring the claims: theLinesMatchTheCastSheetAsEachDoorKnowsIt failed.
///   Fit.seat ignoring `to`: theLinesMatchTheCastSheetAsEachDoorKnowsIt failed.
///   scriptOf trying the Worker before the production's copy: whatIsHereComesFirst failed.
///   scriptOf not remembering what it fetched: aScriptIsFetchedOnceAPage failed.
///   Who.room asking the member's route: eachDoorAsksItsOwnRoute failed.
///   publishable() true for every record: publishIsAbsentWhereTheRecordSaysSo failed.
///   freeze not kept by keep(): sharingFreezesTheScript failed.
///   copy() keeping the shared mark: editACopyIsANewScriptOfTheSameText failed.
///   state() reading `held` from any removal: theTextsStateIsHeldMine failed.
///   OwnJSON.parse reading a boolean as a number: parseKeepsKinds failed.
@MainActor
struct OwnShareTests {
    // MARK: Fixtures

    private static let text = """
    A LITTLE PLAY

    ANNA: Who is there? D\u{E9}j\u{E0} vu.
    BEN: Only me.

    Somebody knocks.

    ANNA: Come in.
    SOUND: DOOR CLOSES
    BEN: Thank you.
    """

    private struct Env {
        let root = FileManager.default.temporaryDirectory.appending(path: "OwnShareTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let plays: ProductionStore
        let own: OwnScripts
        init() {
            plays = ProductionStore(root: root.appending(path: "Plays", directoryHint: .isDirectory))
            own = OwnScripts(root: root.appending(path: "Scripts", directoryHint: .isDirectory), plays: plays)
        }

        func made(_ title: String = "A Little Play", episode: String? = nil) async throws -> PlayScript {
            var rec = try await own.create(title: title, text: OwnShareTests.text)
            rec.doc = OwnScript.done(rec.doc)
            rec.done = true
            if let episode { rec.episode = OwnRecord.Episode(id: episode, url: "https://eardrama.org/episode/\(episode)") }
            #expect(try await own.keep(rec) == nil)
            return try #require(own.script(rec.id))
        }

        func clean() { try? FileManager.default.removeItem(at: root) }

        func reopenedFrozen(_ id: String) -> Bool { OwnScripts(root: own.root, plays: plays).frozen(id) }
    }

    nonisolated private final class Worker: PlaysTransport, @unchecked Sendable {
        private let lock = NSLock()
        var calls: [String] = []
        var failPut: [any Error] = []
        var failCreate: [any Error] = []
        var bodies: [OwnShare.MakeBody] = []
        var sent: [String: Data] = [:]
        var deleted: [String] = []
        var n = 0

        private func note(_ s: String) { lock.withLock { calls.append(s) } }
        func count(_ s: String) -> Int { lock.withLock { calls.filter { $0 == s }.count } }

        func createOwn(_ body: OwnShare.MakeBody, displayName: String?) async throws -> SharedRecord {
            note("create")
            if let e = lock.withLock({ failCreate.isEmpty ? nil : failCreate.removeFirst() }) { throw e }
            n += 1
            bodies.append(body)
            var rec = SharedRecord(id: "P\(n)", scriptID: body.scriptID, scriptRevision: body.revision, title: body.title ?? "", parts: [:], director: "me")
            rec.publishable = false
            rec.ownScript = OwnShare.Own(state: "owed", by: "me", episodeID: body.episodeID)
            return rec
        }
        func putScript(_ pid: String, bytes: Data) async throws {
            note("put")
            if let e = lock.withLock({ failPut.isEmpty ? nil : failPut.removeFirst() }) { throw e }
            sent[pid] = bytes
        }
        func deleteProduction(_ pid: String) async throws { note("delete"); deleted.append(pid) }

        func consent() async throws -> PlaysConsent { throw PlaysRefusal.code("unused") }
        func create(scriptID: String, revision: String, cast: [PlaysShare.CastLine], range: ProductionRange?, heading: String?, displayName: String?) async throws -> SharedRecord { throw PlaysRefusal.code("unused") }
        func list() async throws -> [RemoteProduction] { [] }
        func get(_ pid: String) async throws -> SharedRecord { throw PlaysRefusal.code("unused") }
        func invite(_ pid: String) async throws -> MadeInvite { throw PlaysRefusal.code("unused") }
        func viewInvite(_ token: String) async throws -> InviteView { throw PlaysRefusal.code("unused") }
        func joinByInvite(_ token: String, part: PartID, displayName: String?) async throws -> SharedRecord { throw PlaysRefusal.code("unused") }
        func claim(_ pid: String, part: PartID) async throws -> SharedRecord { throw PlaysRefusal.code("unused") }
        func partAction(_ pid: String, part: PartID, action: String) async throws -> SharedRecord { throw PlaysRefusal.code("unused") }
        func agree(_ pid: String, version: String) async throws {}
        func upload(_ pid: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws {}
        func nextTake(_ pid: String) async throws -> PickedTake? { nil }
        func choose(_ pid: String, takeID: String) async throws -> SharedRecord { throw PlaysRefusal.code("unused") }
        func publish(_ pid: String) async throws -> PublishJob { throw PlaysRefusal.code("unused") }
        func removeLine(_ pid: String, lineID: String, reason: String) async throws {}
        func report(_ pid: String, takeID: String?, userID: String?, reason: ReportReason, note: String?) async throws {}
        func block(_ userID: String) async throws {}
        func classes() async throws -> PlayClasses { throw PlaysRefusal.code("unused") }
        func createClass(name: String, under13: Bool) async throws -> PlayClass { throw PlaysRefusal.code("unused") }
        func joinClass(code: String, displayName: String?) async throws -> PlayClass { throw PlaysRefusal.code("unused") }
    }

    nonisolated private final class Reads: OwnScriptReads, @unchecked Sendable {
        private let lock = NSLock()
        var calls: [OwnShare.Who] = []
        var answer: @Sendable () throws -> OwnShare.Arrival
        init(_ answer: @escaping @Sendable () throws -> OwnShare.Arrival) { self.answer = answer }
        func read(_ who: OwnShare.Who) async throws -> OwnShare.Arrival {
            lock.withLock { calls.append(who) }
            return try answer()
        }
        var count: Int { lock.withLock { calls.count } }
    }

    nonisolated private static func revision(_ bytes: Data) -> String { SHA256.hash(data: bytes).prefix(6).map { String(format: "%02x", $0) }.joined() }

    nonisolated private static func arrival(_ script: PlayScript, bytes: Data? = nil, meta: OwnShare.Meta?? = nil) throws -> OwnShare.Arrival {
        let data = try bytes ?? #require(OwnShare.canonicalLines(script))
        let m: OwnShare.Meta? = meta ?? OwnShare.Meta(id: script.id, revision: script.revision, title: script.title, episodeID: script.episode)
        return OwnShare.Arrival(bytes: data, meta: m)
    }

    private func ask(_ script: PlayScript, _ who: OwnShare.Who, reads: Reads, fit: (PlayScript) -> Bool = { _ in true },
                     local: OwnShare.Local = .init(), fetched: OwnShare.Fetched = .init()) async throws -> PlayScript {
        try await OwnShare.scriptOf(id: script.id, revision: script.revision, who: who, fit: fit, local: local, reads: reads, fetched: fetched,
                                    link: { "https://eardrama.org/episode/\($0)" })
    }

    private func refused(_ code: String, _ name: String, _ body: () async throws -> some Any) async {
        do { _ = try await body(); Issue.record("\(name): resolved") } catch {
            #expect(PlaysRefusal.from(error).code == code, "\(name): \(PlaysRefusal.from(error).code ?? "none")")
        }
    }

    private func problem(_ status: Int, _ code: String, detail: String? = nil) -> PlaysRefusal {
        PlaysRefusal(kind: .refused, status: status, code: code, detail: detail)
    }

    private func sharedScript(_ env: Env, _ worker: Worker, episode: String? = nil) async throws -> (PlayScript, SharedRecord, Production) {
        let script = try await env.made(episode: episode)
        let local = try env.plays.create(script)
        let made = try await PlaysShare.share(api: worker, store: env.plays, local: local, script: script, displayName: nil,
                                              freeze: { try? await env.own.freeze(script.id) })
        return (script, made.record, local)
    }

    // MARK: Sharing

    @Test func shareSendsTheLinesOnce() async throws {
        let env = Env(), worker = Worker()
        defer { env.clean() }
        let (script, rec, local) = try await sharedScript(env, worker)
        let body = try #require(worker.bodies.first)
        #expect(body.own && body.title == "A Little Play" && body.scriptID == script.id && body.revision == script.revision)
        #expect(body.cast == PlaysShare.castSheet(script), "every line in order")
        #expect(body.episodeID == nil, "no episode for a script that was pasted")
        let bytes = try #require(worker.sent[rec.id])
        #expect(String(decoding: bytes, as: UTF8.self).hasPrefix("[{"), "the canonical lines")
        #expect(Self.revision(bytes) == script.revision, "as they were hashed")
        #expect(worker.count("put") == 1, "once")
        #expect(env.plays.share(local.id)?.pid == rec.id, "linked here")
        #expect(env.own.frozen(script.id), "and frozen")
        let catalog = PlayScript(id: "gut-1", revision: "r", kind: "radio", title: "T", authors: [], source: .init(name: "s", url: ""), rights: .init(bucket: "b", evidence: []), roles: [], lines: [])
        let plain = OwnShare.makeBody(catalog)
        #expect(!plain.own && plain.title == nil && plain.episodeID == nil, "a catalog play sends no text and no title")
        let ear = try await env.made("Cast", episode: "ep-1")
        #expect(OwnShare.makeBody(ear).episodeID == "ep-1", "a cast transcript names its episode, so a take-down finds it")
    }

    @Test func aTextAlreadyThereIsTheSameText() async throws {
        let env = Env(), worker = Worker()
        defer { env.clean() }
        worker.failPut = [problem(409, "already_there")]
        let script = try await env.made()
        let made = try await PlaysShare.share(api: worker, store: env.plays, local: try env.plays.create(script), script: script, displayName: nil)
        #expect(made.unsent == nil, "409 already_there")
    }

    @Test func aSendingThatMayPassLeavesItOwed() async throws {
        let errors: [any Error] = [PlaysRefusal(kind: .unreachable), problem(503, "scripts_full"), problem(429, "rate_limited"),
                                   PlaysRefusal(kind: .unauthorized, status: 401), PlaysRefusal(kind: .refused, status: 500, code: "error")]
        for e in errors {
            let env = Env(), worker = Worker()
            defer { env.clean() }
            worker.failPut = [e]
            let script = try await env.made()
            let local = try env.plays.create(script)
            let made = try await PlaysShare.share(api: worker, store: env.plays, local: local, script: script, displayName: nil,
                                                  freeze: { try? await env.own.freeze(script.id) })
            #expect(made.unsent != nil, "owed after \(e)")
            #expect(worker.count("delete") == 0 && env.plays.share(local.id)?.pid == made.record.id, "the share stands")
            #expect(env.own.frozen(script.id), "and what is owed is what will be sent")
            let again = await OwnShare.sendOrUndo(worker, pid: made.record.id, script: script, freeze: {})
            #expect(again == nil && worker.sent[made.record.id] != nil, "sent by Try Again")
        }
    }

    @Test func aSendingThatCanNeverPassUndoesTheShare() async throws {
        for (status, code) in [(413, "script_too_long"), (422, "revision_mismatch"), (410, "script_removed"), (400, "bad_request")] {
            let env = Env(), worker = Worker()
            defer { env.clean() }
            worker.failPut = [problem(status, code)]
            let script = try await env.made()
            let local = try env.plays.create(script)
            await refused(code, code) {
                try await PlaysShare.share(api: worker, store: env.plays, local: local, script: script, displayName: nil, freeze: { try? await env.own.freeze(script.id) })
            }
            #expect(worker.count("delete") == 1 && env.plays.share(local.id) == nil, "nothing is left shared")
            #expect(!FileManager.default.fileExists(atPath: env.plays.shareURL(local.id).path), "on disk too")
            #expect(!env.own.frozen(script.id), "and nothing is frozen")
        }
        let env = Env(), worker = Worker()
        defer { env.clean() }
        worker.failCreate = [problem(422, "bad_name", detail: "title")]
        let script = try await env.made()
        let local = try env.plays.create(script)
        await refused("bad_name", "a title the filter refuses") {
            try await PlaysShare.share(api: worker, store: env.plays, local: local, script: script, displayName: nil)
        }
        #expect(worker.count("put") == 0 && env.plays.share(local.id) == nil, "no text was sent")
        #expect(PlaysShare.line(problem(422, "bad_name", detail: "title")) == "The title is not allowed.")
        #expect(PlaysShare.line(problem(422, "bad_name", detail: "role:ANNA")) == "The part name ANNA is not allowed.")
    }

    // MARK: The one resolver

    @Test func eachDoorAsksItsOwnRoute() async throws {
        let env = Env()
        defer { env.clean() }
        let script = try await env.made()
        for who: OwnShare.Who in [.member(pid: "P1"), .invite(token: "t"), .seat(key: "key", pid: "P1"), .room(code: "ABC123", key: "mk")] {
            let reads = Reads { try Self.arrival(script) }
            let got = try await ask(script, who, reads: reads)
            #expect(reads.calls == [who], "\(who)")
            #expect(got.lines == script.lines && got.kind == "own" && got.title == script.title && got.revision == script.revision)
            #expect(got.castParts.map(\.id) == script.castParts.map(\.id), "and casts it")
            #expect(got.roles == script.roles, "the roles are counted here")
            #expect(got.rights.bucket == "own")
        }
    }

    @Test func whatIsHereComesFirst() async throws {
        let env = Env()
        defer { env.clean() }
        let script = try await env.made()
        let reads = Reads { throw PlaysRefusal.code("must_not_ask") }
        let kept = OwnShare.Local(kept: { _ in script })
        #expect(try await ask(script, .member(pid: "P1"), reads: reads, local: kept).lines == script.lines, "the production's")
        let mine = OwnShare.Local(mine: { _ in script })
        #expect(try await ask(script, .member(pid: "P1"), reads: reads, local: mine).lines == script.lines, "the device's")
        #expect(reads.count == 0, "nothing was asked")
        await refused("script_damaged", "another revision is not what is here") {
            try await OwnShare.scriptOf(id: script.id, revision: "000000000000", who: .member(pid: "P1"), local: mine, reads: Reads { try Self.arrival(script) },
                                        link: { $0 })
        }
        await refused("not_on_device", "a door with no way to ask") {
            try await OwnShare.scriptOf(id: script.id, revision: script.revision, who: nil, local: .init(), reads: reads, link: { $0 })
        }
    }

    @Test func aScriptIsFetchedOnceAPage() async throws {
        let env = Env()
        defer { env.clean() }
        let script = try await env.made()
        let reads = Reads { try Self.arrival(script) }
        let page = OwnShare.Fetched()
        _ = try await ask(script, .member(pid: "P1"), reads: reads, fetched: page)
        _ = try await ask(script, .member(pid: "P1"), reads: reads, fetched: page)
        #expect(reads.count == 1, "once")
    }

    @Test func whatDidNotArriveWholeIsNeverDrawn() async throws {
        let env = Env()
        defer { env.clean() }
        let script = try await env.made()
        let good = try #require(OwnShare.canonicalLines(script))
        let text = String(decoding: good, as: UTF8.self)
        func serve(_ data: Data, revision: String? = nil, meta: OwnShare.Meta?? = nil) async throws -> PlayScript {
            let rev = revision ?? Self.revision(data)
            let m: OwnShare.Meta? = meta ?? OwnShare.Meta(id: script.id, revision: rev, title: "T", episodeID: nil)
            let reads = Reads { OwnShare.Arrival(bytes: data, meta: m) }
            return try await OwnShare.scriptOf(id: script.id, revision: rev, who: .member(pid: "P1"), local: .init(), reads: reads, fetched: .init(), link: { $0 })
        }
        _ = try await serve(good)
        await refused("script_damaged", "cut short") { try await serve(Data(good.dropLast(1)), revision: script.revision) }
        await refused("script_damaged", "one word changed") { try await serve(Data(text.replacingOccurrences(of: "Come in", with: "Come on").utf8), revision: script.revision) }
        await refused("script_damaged", "not canonical") {
            let pretty = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: good), options: [.prettyPrinted, .sortedKeys])
            return try await serve(pretty)
        }
        await refused("script_damaged", "not lines") { try await serve(Data(#"{"lines":[]}"#.utf8)) }
        await refused("script_damaged", "not JSON") { try await serve(Data("not json".utf8)) }
        await refused("script_damaged", "not UTF-8") { try await serve(Data([0x5b, 0xff, 0x5d])) }
        await refused("script_damaged", "a byte order mark") { try await serve(Data([0xef, 0xbb, 0xbf]) + good) }
        await refused("script_damaged", "a kind no core knows") { try await serve(Data(text.replacingOccurrences(of: #""kind":"sound""#, with: #""kind":"song""#).utf8)) }
        await refused("script_damaged", "a line id twice") {
            guard case .array(var all)? = OwnJSON.parse(good) else { throw PlaysRefusal.code("fixture") }
            all.append(all[0])
            return try await serve(Data(OwnScript.canonicalBytes(.array(all))))
        }
        await refused("script_damaged", "no x-script") { try await serve(good, meta: .some(nil)) }
        await refused("script_damaged", "another script's name") {
            try await serve(good, meta: .some(OwnShare.Meta(id: "own-00000000-0000-4000-8000-000000000000", revision: script.revision, title: "T", episodeID: nil)))
        }
        await refused("script_damaged", "another revision's name") {
            try await serve(good, meta: .some(OwnShare.Meta(id: script.id, revision: "000000000000", title: "T", episodeID: nil)))
        }
        await refused("script_damaged", "no title") {
            try await serve(good, meta: .some(OwnShare.Meta(id: script.id, revision: script.revision, title: "", episodeID: nil)))
        }
    }

    @Test func theLinesMatchTheCastSheetAsEachDoorKnowsIt() async throws {
        let env = Env()
        defer { env.clean() }
        let script = try await env.made()
        let reads = Reads { try Self.arrival(script) }
        func at(_ fit: @escaping (PlayScript) -> Bool) async throws -> PlayScript { try await ask(script, .member(pid: "P1"), reads: reads, fit: fit) }
        let parts = script.castParts.map { InviteView.Part(id: $0.id.rawValue, lineCount: $0.lineCount, status: .open) }
        func invite(_ ps: [InviteView.Part]) -> (PlayScript) -> Bool {
            OwnShare.Fit.invite(InviteView(id: "P1", scriptID: script.id, scriptRevision: script.revision, title: "", parts: ps, member: false))
        }
        _ = try await at(invite(parts))
        await refused("script_damaged", "a part the sheet does not have") { try await at(invite(Array(parts.dropFirst()))) }
        await refused("script_damaged", "a part the lines do not have") { try await at(invite(parts + [.init(id: "role:ZED", lineCount: 1, status: .open)])) }
        await refused("script_damaged", "a part with other lines") {
            var other = parts
            other[0].lineCount += 1
            return try await at(invite(other))
        }
        func record(parts ids: [String], take line: String? = nil) -> SharedRecord {
            var rec = SharedRecord(id: "P1", scriptID: script.id, scriptRevision: script.revision, title: "", parts: Dictionary(uniqueKeysWithValues: ids.map { ($0, SharedRecord.Part(status: .open)) }))
            if let line { rec.takes = [SharedRecord.Take(id: "t", lineID: line, part: ids[0], frames: 1, sampleRate: 1)] }
            return rec
        }
        let ids = script.castParts.map(\.id.rawValue)
        _ = try await at(OwnShare.Fit.record(record(parts: ids)))
        await refused("script_damaged", "a record of other parts") { try await at(OwnShare.Fit.record(record(parts: ["role:ANNA"]))) }
        await refused("script_damaged", "a take of a line it does not have") { try await at(OwnShare.Fit.record(record(parts: ids, take: "L9999"))) }
        func room(_ cursor: String, _ claims: [String: String]) throws -> ReadSnapshot {
            let o: [String: Any] = ["type": "snapshot", "code": "ABC123", "kind": "adult", "mode": "read", "cursor": cursor, "cursor_gen": 1, "generation": 1,
                                    "locked": false, "ended": false, "leader": "h", "waiting_for_leader": false, "present": 1, "claims": claims, "seats": [],
                                    "assignments": [], "done": [], "server_time": 1, "members": []]
            return try JSONDecoder().decode(ReadSnapshot.self, from: JSONSerialization.data(withJSONObject: o))
        }
        _ = try await at(OwnShare.Fit.room(try room("L0001", ["role:BEN": "m1"])))
        await refused("script_damaged", "a cursor on no line") { try await at(OwnShare.Fit.room(try room("L9999", [:]))) }
        await refused("script_damaged", "a claim of no part") { try await at(OwnShare.Fit.room(try room("L0001", ["role:ZED": "m1"]))) }
        _ = try await at(OwnShare.Fit.seat([ReadSnapshot.Assignment(part: "role:ANNA", seat: "s1", from: "L0001", to: nil)]))
        await refused("script_damaged", "cast to no part") { try await at(OwnShare.Fit.seat([ReadSnapshot.Assignment(part: "role:ZED", seat: "s1")])) }
        await refused("script_damaged", "cast from no line") { try await at(OwnShare.Fit.seat([ReadSnapshot.Assignment(part: "role:ANNA", seat: "s1", from: "L9999")])) }
        await refused("script_damaged", "cast to no line") { try await at(OwnShare.Fit.seat([ReadSnapshot.Assignment(part: "role:ANNA", seat: "s1", from: "L0001", to: "L9999")])) }
    }

    @Test func theWorkersRefusalsPassThroughByTheirCodes() async throws {
        let env = Env()
        defer { env.clean() }
        let script = try await env.made()
        for code in ["script_removed", "no_script", "script_reported", "not_a_member"] {
            let reads = Reads { throw PlaysRefusal.code(code, status: 410) }
            await refused(code, code) { try await ask(script, .member(pid: "P1"), reads: reads) }
        }
    }

    @Test func aCastTranscriptKeepsItsSource() async throws {
        let env = Env()
        defer { env.clean() }
        let script = try await env.made(episode: "ep-9")
        let got = try await ask(script, .member(pid: "P1"), reads: Reads { try Self.arrival(script) })
        #expect(got.episode == "ep-9")
        #expect(got.source.name == "Automatic transcript" && got.source.url == "https://eardrama.org/episode/ep-9")
    }

    @Test func aCatalogPlayIsTheLibrarysAtTheRecordedRevisionElseTheBundlesElseARefusal() async throws {
        func play(_ revision: String) -> PlayScript {
            PlayScript(id: "gut-1", revision: revision, kind: "radio", title: "T", authors: [], source: .init(name: "s", url: ""), rights: .init(bucket: "b", evidence: []), roles: [], lines: [])
        }
        let local = OwnShare.Local(catalog: { _, revision in revision == "b" ? play("b") : revision == "a" ? play("a") : nil })
        let reads = Reads { throw PlaysRefusal.code("must_not_ask") }
        func at(_ revision: String) async throws -> PlayScript {
            try await OwnShare.scriptOf(id: "gut-1", revision: revision, local: local, reads: reads, link: { $0 })
        }
        #expect(try await at("b").revision == "b")
        #expect(try await at("a").revision == "a")
        await refused("revision_mismatch", "neither") { try await at("c") }
        #expect(reads.count == 0, "a catalog play is never asked of the Worker's script routes")
    }

    @Test func aPersonWhoJoinsKeepsTheScriptInTheirProduction() async throws {
        let env = Env(), other = Env()
        defer { env.clean(); other.clean() }
        let script = try await env.made()
        let got = try await ask(script, .invite(token: "t"), reads: Reads { try Self.arrival(script) })
        let local = try PlaysShare.localFor(store: other.plays, pid: "P1", script: got)
        let kept = try #require(other.plays.script(for: local))
        #expect(kept.lines == script.lines && local.scriptID == script.id && local.scriptRevision == script.revision, "kept whole")
        let again = try await OwnShare.scriptOf(id: script.id, revision: script.revision, who: .member(pid: "P1"),
                                                local: .init(kept: { pid in other.plays.findShared(pid).flatMap { other.plays.script(for: $0) } }),
                                                reads: Reads { throw PlaysRefusal.code("must_not_ask") }, fetched: .init(), link: { $0 })
        #expect(again.lines == script.lines, "read from the production, with no Worker")
        #expect(other.own.rows.isEmpty, "and it is not one of their own scripts")
    }

    // MARK: Frozen, and Edit a Copy

    @Test func sharingFreezesTheScript() async throws {
        let env = Env(), worker = Worker()
        defer { env.clean() }
        let script = try await env.made()
        #expect(!env.own.frozen(script.id))
        var rec = try #require(try env.own.get(script.id))
        _ = try await PlaysShare.share(api: worker, store: env.plays, local: try env.plays.create(script), script: script, displayName: nil,
                                       freeze: { try? await env.own.freeze(script.id) })
        #expect(env.own.frozen(script.id), "frozen once shared")
        #expect(env.own.row(script.id)?.shared != nil)
        rec.title = "Changed"
        await #expect(throws: OwnKeepFailure.self) { try await env.own.keep(rec) }
        #expect(env.own.row(script.id)?.title == "A Little Play", "what people were sent is what it stays")
        #expect(env.reopenedFrozen(script.id), "and it stays frozen after a relaunch")
        #expect(OwnText.notKept(OwnKeepFailure.shared) == "This script is shared.")
    }

    @Test func editACopyIsANewScriptOfTheSameText() async throws {
        let env = Env(), worker = Worker()
        defer { env.clean() }
        let script = try await env.made()
        _ = try await PlaysShare.share(api: worker, store: env.plays, local: try env.plays.create(script), script: script, displayName: nil,
                                       freeze: { try? await env.own.freeze(script.id) })
        let copy = try await env.own.copy(script)
        #expect(copy.id != script.id && OwnScript.isOwnID(copy.id))
        #expect(copy.title == "A Little Play (copy)" && copy.shared == nil && copy.done, "not frozen")
        let made = try #require(env.own.script(copy.id))
        #expect(made.lines.map(\.id) == script.lines.map(\.id), "its lines' ids kept")
        #expect(made.lines == script.lines && made.revision == script.revision, "the same text")
        #expect(env.plays.productions(of: copy.id).isEmpty, "no takes, no productions")
        #expect(!env.own.frozen(copy.id) && env.own.frozen(script.id), "the original stays what was sent")
        #expect(OwnScripts.copyTitle(String(repeating: "x", count: 400)).count == OwnScript.maxTitle)
    }

    // MARK: What the record says

    @Test func theTextsStateIsHeldMine() {
        let owed = OwnShare.state(.init(state: "owed", by: "me", episodeID: nil), me: "me")
        #expect(owed == .init(state: "owed", held: false, mine: true, by: "me"))
        let removed = OwnShare.state(.init(state: "removed", by: "ann", episodeID: nil), me: "me")
        #expect(removed?.held == true && removed?.mine == false, "held when the owner removed it")
        let gone = OwnShare.state(.init(state: "removed", by: nil, episodeID: nil), me: "me")
        #expect(gone?.held == false, "gone with the account that brought it")
        #expect(OwnShare.state(nil, me: "me") == nil, "a catalog play has none")
        let kept = OwnShare.state(.init(state: "kept", by: "me", episodeID: nil), me: nil)
        #expect(kept?.mine == false, "signed out, nothing is mine")
    }

    @Test func publishIsAbsentWhereTheRecordSaysSo() {
        var own = SharedRecord(id: "P", scriptID: "own-00000000-0000-4000-8000-000000000000", scriptRevision: "r", title: "T", parts: [:], director: "me")
        own.publishable = false
        #expect(!OwnShare.publishable(own) && OwnShare.neverPublishes(own) == "This script can\u{2019}t be published.")
        var catalog = own
        catalog.scriptID = "gut-1"
        #expect(OwnShare.neverPublishes(catalog) == PlaysShare.line(PlaysRefusal.code("script_not_publishable")))
        catalog.publishable = true
        #expect(OwnShare.neverPublishes(catalog) == nil)
        var old = catalog
        old.publishable = nil
        #expect(OwnShare.publishable(old), "a record from before says nothing, and a catalog play may publish")
        let script = PlayScript(id: own.scriptID, revision: "r", kind: "own", title: "T", authors: [], source: .init(name: "s", url: ""), rights: .init(bucket: "own", evidence: []), roles: [], lines: [])
        #expect(!PlaysShare.canPublish(own, script, "me"), "never offered for an own script, whatever else is complete")
        #expect(!PlaysShare.needsMyConsent(own, script, "ann"))
    }

    @Test func everyRefusalHasItsWords() {
        for code in ["script_too_long", "scripts_full", "script_removed", "script_reported", "script_damaged", "no_script", "bad_script_id", "not_on_device", "needs_account"] {
            #expect(!OwnShare.scriptLine(PlaysRefusal.code(code)).isEmpty, "\(code)")
        }
        #expect(OwnShare.scriptLine(PlaysRefusal.code("revision_mismatch")) == "This play has changed since it was cast.")
        #expect(OwnShare.scriptLine(PlaysRefusal.code("take_exists")).isEmpty, "any other code is left to its own screen's words")
        #expect(OwnShare.scriptLine(problem(422, "bad_name", detail: "title")) == "The title is not allowed.")
        #expect(OwnShare.scriptLine(problem(409, "too_many_scripts", detail: "20")).hasPrefix("You have shared"))
        #expect(ReadCore.refusal("not_a_member") == "You are no longer in this reading.")
        let rec = SharedRecord(id: "P", scriptID: "own-x", scriptRevision: "r", title: "", parts: [:], director: "me")
        #expect(OwnShare.readersLine(rec, me: "me") == "Only people you invite can read this script.")
        #expect(OwnShare.readersLine(rec, me: "ann") == "Only people invited can read this script.")
        var cls = rec
        cls.classID = "C1"
        #expect(OwnShare.readersLine(cls, me: "me") == "Only this class can read this script.")
        #expect(ReportReason.forScript.first == .copyright && !ReportReason.forTakes.contains(.copyright), "copyright first, and only for a script")
    }

    @Test func parseKeepsKinds() throws {
        let tree = try #require(OwnJSON.parse(Data(#"{"a":true,"b":1,"c":null,"d":["x"]}"#.utf8)))
        #expect(tree["a"] == .bool(true) && tree["b"] == .int(1) && tree["c"] == .null && tree["d"] == .array([.string("x")]))
        #expect(OwnJSON.parse(Data("1.5".utf8)) == nil, "no fractions in a script")
        #expect(OwnJSON.parse(Data("not json".utf8)) == nil)
    }

    @Test func theMetaHeaderIsReadWhole() {
        let ok = WorkerOwnScripts.meta(#"{"id":"own-x","revision":"abc","title":"T","episode_id":"ep-1"}"#)
        #expect(ok == OwnShare.Meta(id: "own-x", revision: "abc", title: "T", episodeID: "ep-1"))
        #expect(WorkerOwnScripts.meta(nil) == nil && WorkerOwnScripts.meta("nope") == nil && WorkerOwnScripts.meta(#"{"id":"x"}"#) == nil)
    }
}
