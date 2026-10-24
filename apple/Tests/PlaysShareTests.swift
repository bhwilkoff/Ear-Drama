import Foundation
import Testing

// Shared plays, phase 2 (PLAYS-DESIGN §11.7), against a stub Worker: what is
// uploaded, when the consent is asked, the owner's switch, how the Worker's
// parts land on this device, invite links, Library's rows, and the one line
// each refusal shows. Nothing here reaches a network or plays a sound.
//
// Broken controls, 2026-10-24, one run with all seven mutations in Core; each
// failed its own test and no other (7 failed of 157, 18 issues):
//   PlaysShare.pending keeping flagged takes: the pending test fails.
//   PlaysShare.upload without the uploads guards (record and GET /consent):
//     the owner's-switch test fails (4 issues: consent read, take sent).
//   upload asking only when `consented` is nil: the consent test fails (v2 never asked).
//   mirror keeping another person's claim as recording: the mirror test fails.
//   DeepLink.isToken without its length: the invite-link test fails.
//   libraryRows listing a remote production already here: the Library test fails.
//   line() losing the singular "1 line still needs a take.": the line test fails.

// MARK: - Fixtures

private func shareLine(_ id: String, _ role: String?, _ kind: ScriptLine.Kind = .speech) -> ScriptLine {
    kind == .speech
        ? ScriptLine(id: id, kind: .speech, role: role, parts: [.say("words")])
        : ScriptLine(id: id, kind: kind, source: "SOUND: DOOR")
}

/// MOLLY 3 lines, FIBBER 2, one sound cue.
private func shareScript() -> PlayScript {
    let lines = [
        shareLine("L1", "MOLLY"), shareLine("L2", "FIBBER"), shareLine("L3", nil, .sound),
        shareLine("L4", "MOLLY"), shareLine("L5", "FIBBER"), shareLine("L6", "MOLLY"),
    ]
    return PlayScript(id: "gut-share", revision: "r1", kind: "radio", title: "Shared Fixture", authors: [],
                      source: .init(name: "Fixture", url: "https://example.org"),
                      rights: .init(bucket: "script_source_cleared", evidence: []),
                      roles: [.init(name: "MOLLY", lines: 3, words: 3), .init(name: "FIBBER", lines: 2, words: 2)],
                      lines: lines)
}

private let me = "user-me"
private let molly = PartID.role("MOLLY")
private let fibber = PartID.role("FIBBER")

private func sharedTake(_ id: String, line: String, part: PartID, bleed: Bool = false) -> Take {
    Take(id: id, lineID: line, part: part, file: "\(id).flac", created: Date(timeIntervalSinceReferenceDate: 100),
         frames: 4_800, sampleRate: 48_000, capture: .direct, heard: [:], loudness: -16, peak: 0.5, bleed: bleed)
}

private func record(parts: [String: SharedRecord.Part], takes: [SharedRecord.Take] = [], chosen: [String: String] = [:],
                    uploads: Bool? = true) -> SharedRecord {
    SharedRecord(id: "P1", scriptID: "gut-share", scriptRevision: "r1", title: "Shared Fixture", parts: parts,
                 takes: takes, chosen: chosen, director: me, uploads: uploads)
}

private func serverTake(_ id: String, line: String, part: PartID, user: String) -> SharedRecord.Take {
    SharedRecord.Take(id: id, lineID: line, part: part.rawValue, created: 100, frames: 4_800, sampleRate: 48_000,
                      capture: "direct", heard: [:], loudness: -18, peak: 0.4, userID: user)
}

/// Mine: MOLLY recording. FIBBER open, the sound cue open.
private func mollyIsMine(takes: [SharedRecord.Take] = [], uploads: Bool? = true) -> SharedRecord {
    record(parts: [molly.rawValue: .init(status: .recording, performer: "Me", userID: me),
                   fibber.rawValue: .init(status: .open), "sound": .init(status: .open)],
           takes: takes, uploads: uploads)
}

private func temporaryStore() -> ProductionStore {
    ProductionStore(root: FileManager.default.temporaryDirectory
        .appending(path: "share-tests-\(UUID().uuidString)", directoryHint: .isDirectory))
}

/// A shared production on disk with the given takes, each with a file.
private func sharedProduction(_ store: ProductionStore, _ script: PlayScript, _ takes: [Take]) throws -> Production {
    var p = try store.create(script)
    for t in takes {
        p.add(t)
        try Data("fLaC-\(t.id)".utf8).write(to: store.takesFolder(p.id).appending(path: t.file))
    }
    try store.save(p)
    try store.setShare(p.id, ProductionShare(pid: "P1"))
    return p
}

private final class StubWorker: PlaysTransport {
    var rec: SharedRecord
    var consentAnswer = PlaysConsent(version: "v1", text: "OWNER: placeholder words", uploads: true)
    var consentCalls = 0
    var agreed: [String] = []
    var uploaded: [String] = []
    var audioFetched: [String] = []
    var audio: [String: Data] = [:]

    init(_ rec: SharedRecord) { self.rec = rec }

    func consent() async throws -> PlaysConsent {
        consentCalls += 1
        return consentAnswer
    }
    func get(_ pid: String) async throws -> SharedRecord { rec }
    func agree(_ pid: String, version: String) async throws { agreed.append(version) }
    func upload(_ pid: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws {
        uploaded.append(takeID)
    }
    func audio(_ pid: String, takeID: String) async throws -> Data {
        audioFetched.append(takeID)
        return audio[takeID] ?? Data("RIFF....WAVE".utf8)
    }
    func choose(_ pid: String, takeID: String) async throws -> SharedRecord { rec }

    private var unused: PlaysRefusal { .code("unused_in_test") }
    func create(scriptID: String, revision: String, cast: [PlaysShare.CastLine], displayName: String?) async throws -> SharedRecord { rec }
    func list() async throws -> [RemoteProduction] { [] }
    func invite(_ pid: String) async throws -> MadeInvite { throw unused }
    func viewInvite(_ token: String) async throws -> InviteView { throw unused }
    func joinByInvite(_ token: String, part: PartID, displayName: String?) async throws -> SharedRecord { rec }
    func claim(_ pid: String, part: PartID) async throws -> SharedRecord { rec }
    func partAction(_ pid: String, part: PartID, action: String) async throws -> SharedRecord { rec }
    func publish(_ pid: String) async throws -> PublishJob { throw unused }
    func report(_ pid: String, takeID: String?, userID: String?, reason: ReportReason, note: String?) async throws {}
    func block(_ userID: String) async throws {}
    func classes() async throws -> PlayClasses { throw unused }
    func createClass(name: String, under13: Bool) async throws -> PlayClass { throw unused }
    func joinClass(code: String, displayName: String?) async throws -> PlayClass { throw unused }
}

// MARK: - What is uploaded

struct PlaysSharePendingTests {
    @Test func pendingIsMyChosenUnflaggedTakesTheWorkerLacks() throws {
        let script = shareScript()
        let store = temporaryStore()
        let local = try sharedProduction(store, script, [
            sharedTake("t-up", line: "L1", part: molly),            // already on the Worker
            sharedTake("t-new", line: "L4", part: molly),           // pending
            sharedTake("t-bleed", line: "L6", part: molly, bleed: true), // flagged: never sent
            sharedTake("t-fib", line: "L2", part: fibber),          // not my part
        ])
        let rec = mollyIsMine(takes: [serverTake("t-up", line: "L1", part: molly, user: me)])
        #expect(PlaysShare.pending(local, script, rec, me).map(\.id) == ["t-new"])
        #expect(PlaysShare.flagged(local, script, rec, me) == 1)
        // Nobody signed in holds nothing.
        #expect(PlaysShare.pending(local, script, rec, nil).isEmpty)
    }

    @Test func theOwnersSwitchStopsUploadsBeforeTheConsentOrAnyUpload() async throws {
        let script = shareScript()
        let store = temporaryStore()
        let local = try sharedProduction(store, script, [sharedTake("t-new", line: "L4", part: molly)])
        let off = StubWorker(mollyIsMine(uploads: false))
        var asked = 0
        let result = await PlaysShare.upload(api: off, store: store, local: local, script: script, rec: off.rec, me: me) { _ in
            asked += 1
            return true
        }
        #expect(result.stopped == .uploadsOff)
        #expect(off.uploaded.isEmpty && off.consentCalls == 0 && asked == 0)
        #expect(!PlaysShare.uploadsOpen(off.rec))

        // GET /consent carries the switch too.
        let consentOff = StubWorker(mollyIsMine())
        consentOff.consentAnswer.uploads = false
        let second = await PlaysShare.upload(api: consentOff, store: store, local: local, script: script, rec: consentOff.rec,
                                             me: me) { _ in true }
        #expect(second.stopped == .uploadsOff)
        #expect(consentOff.uploaded.isEmpty && consentOff.agreed.isEmpty)
    }

    @Test func theConsentIsAskedBeforeTheFirstUploadAndAgainWhenItsVersionChanges() async throws {
        let script = shareScript()
        let store = temporaryStore()
        var local = try sharedProduction(store, script, [sharedTake("t-a", line: "L1", part: molly)])
        let api = StubWorker(mollyIsMine())
        var asked: [String] = []

        // Not now: nothing goes, nothing is recorded as agreed.
        let declined = await PlaysShare.upload(api: api, store: store, local: local, script: script, rec: api.rec, me: me) {
            asked.append($0.version)
            return false
        }
        #expect(declined.stopped == .consent && api.uploaded.isEmpty && api.agreed.isEmpty)
        #expect(store.share(local.id)?.consented == nil)

        // I agree: its version goes to the Worker and into share.json, then the take.
        let first = await PlaysShare.upload(api: api, store: store, local: local, script: script, rec: api.rec, me: me) {
            asked.append($0.version)
            return $0.text == "OWNER: placeholder words"
        }
        #expect(first.sent == 1 && api.uploaded == ["t-a"] && api.agreed == ["v1"])
        #expect(store.share(local.id)?.consented == "v1")
        let reread = ProductionStore(root: store.root)
        #expect(reread.share(local.id) == ProductionShare(pid: "P1", consented: "v1"))

        // The same version: not asked again.
        api.rec.takes = [serverTake("t-a", line: "L1", part: molly, user: me)]
        local.add(sharedTake("t-b", line: "L4", part: molly))
        try Data("fLaC".utf8).write(to: store.takesFolder(local.id).appending(path: "t-b.flac"))
        try store.save(local)
        _ = await PlaysShare.upload(api: api, store: store, local: local, script: script, rec: api.rec, me: me) {
            asked.append($0.version)
            return true
        }
        #expect(api.uploaded == ["t-a", "t-b"])
        #expect(asked == ["v1", "v1"])

        // New words: asked again before the next upload.
        api.rec.takes.append(serverTake("t-b", line: "L4", part: molly, user: me))
        api.consentAnswer = PlaysConsent(version: "v2", text: "OWNER: new words", uploads: true)
        local.add(sharedTake("t-c", line: "L6", part: molly))
        try Data("fLaC".utf8).write(to: store.takesFolder(local.id).appending(path: "t-c.flac"))
        try store.save(local)
        _ = await PlaysShare.upload(api: api, store: store, local: local, script: script, rec: api.rec, me: me) {
            asked.append($0.version)
            return true
        }
        #expect(asked == ["v1", "v1", "v2"])
        #expect(api.agreed == ["v1", "v2"] && api.uploaded == ["t-a", "t-b", "t-c"])
        #expect(store.share(local.id)?.consented == "v2")
    }

    @Test func theTakesFieldsGoAsTheWorkerReadsThem() throws {
        let t = sharedTake("t-a", line: "L1", part: molly)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaysShare.metaOf(t))) as! [String: Any]
        #expect(json["lineID"] as? String == "L1" && json["part"] as? String == "role:MOLLY")
        #expect(json["sampleRate"] as? Double == 48_000 && json["created"] as? Double == 100)
        #expect(json["bleed"] as? Bool == false && json["capture"] as? String == "direct")
        #expect(PlaysShare.contentType("x.flac") == "audio/flac" && PlaysShare.contentType("m-x.wav") == "audio/wav")
    }
}

// MARK: - The Worker's parts on this device

struct PlaysShareMirrorTests {
    @Test func anotherPersonsClaimIsOpenHereAndMineRecords() throws {
        let script = shareScript()
        let local = Production(script: script)
        let rec = record(parts: [
            molly.rawValue: .init(status: .recording, performer: "Ann", userID: "user-ann"),
            fibber.rawValue: .init(status: .done, performer: "Bo", userID: "user-bo"),
            "sound": .init(status: .silent, userID: "user-bo"),
        ])
        let here = PlaysShare.mirror(local, rec, me)
        #expect(here.state(of: molly) == PartState(status: .open, performer: nil))
        #expect(here.state(of: fibber) == PartState(status: .done, performer: "Bo"))
        #expect(here.state(of: .sound).status == .silent)
        #expect(Relay.current(here, script) == nil)

        let ann = PlaysShare.mirror(local, rec, "user-ann")
        #expect(ann.state(of: molly) == PartState(status: .recording, performer: "Ann"))
        // Signed out, nobody's claim records here.
        #expect(PlaysShare.mirror(local, rec, nil).state(of: molly).status == .open)
        #expect(!PlaysShare.canClaim(rec, fibber) && PlaysShare.recordingPart(rec) == molly)
    }

    @Test func otherMembersTakesArriveAsNewFilesAndTheirChoicesFollow() async throws {
        let script = shareScript()
        let store = temporaryStore()
        let local = try sharedProduction(store, script, [sharedTake("t-mine", line: "L1", part: molly)])
        var rec = mollyIsMine(takes: [serverTake("t-fib", line: "L2", part: fibber, user: "user-bo")])
        rec.chosen = ["L2": "t-fib", "L1": "t-older"]
        let api = StubWorker(rec)
        let existing = store.takesFolder(local.id).appending(path: "m-t-fib.wav")
        try Data("RIFF-kept".utf8).write(to: existing)

        let arrived = try await PlaysShare.bringHome(api: api, store: store, localID: local.id, rec: rec, script: script, me: me)
        #expect(arrived == 1 && api.audioFetched == ["t-fib"])
        let after = try #require(store.production(local.id))
        #expect(after.take("t-fib")?.file == "m-t-fib.wav")
        // A file already there is never overwritten.
        #expect(try Data(contentsOf: existing) == Data("RIFF-kept".utf8))
        // My own choice stands on my part; the Worker's on everyone else's.
        #expect(after.chosen == ["L1": "t-mine", "L2": "t-fib"])
        #expect(PlaysShare.inStep(after, script, rec, me))
    }
}

// MARK: - Invite links

struct PlaysShareInviteTests {
    private let token = String(repeating: "Ab0_-", count: 8) + "xyz"

    @Test func bothShapesCarryTheTokenAndBadOnesAreRefused() throws {
        #expect(token.count == 43)
        let https = try #require(URL(string: "https://eardrama.org/invite#\(token)"))
        let scheme = try #require(URL(string: "eardrama://invite#\(token)"))
        let forwarded = try #require(URL(string: "https://eardrama.org/?view=library&tab=dramas#invite=\(token)"))
        #expect(PlaysShare.inviteToken(https) == token)
        #expect(PlaysShare.inviteToken(scheme) == token)
        #expect(PlaysShare.inviteToken(forwarded) == token)
        #expect(PlaysShare.inviteLink(token) == https)
        #expect(DeepLink.parse(https) == .invite(token))
        #expect(DeepLink.parse(scheme) == .invite(token))

        let short = String(token.dropLast())
        for bad in ["https://eardrama.org/invite#\(short)", "eardrama://invite#\(short)x+",
                    "https://example.org/invite#\(token)", "https://eardrama.org/series/x#\(token)",
                    "eardrama://invite", "https://eardrama.org/invite"] {
            let url = try #require(URL(string: bad))
            #expect(PlaysShare.inviteToken(url) == nil, "\(bad)")
        }
        // A broken invite opens nothing; it is never read as an item named "invite".
        #expect(DeepLink.parse(URL(string: "eardrama://invite#nope")!) == nil)
        #expect(DeepLink.parse(URL(string: "https://eardrama.org/invite#nope")!) == nil)
        #expect(DeepLink.parse(URL(string: "eardrama://episode/abc%7C1")!) == .item("abc|1"))
        #expect(DeepLink.parse(URL(string: "https://eardrama.org/series/fibber")!) == .item("fibber"))
    }

    @Test func anInviteOpensLibraryAndIsHeldUntilDropped() {
        let app = AppStore()
        app.selectedTab = .home
        app.post(.invite(token))
        #expect(app.drainInbox().isEmpty)
        #expect(app.selectedTab == .library && app.pendingInvite == token)
    }

    @Test func aClassCodeIsTwoGroupsOfFourAndAnInviteSaysHowLongItWorks() {
        #expect(SharedPlays.grouped("ABCD2345") == "ABCD 2345")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let week = MadeInvite(id: "i", token: token, expiresAt: (now.timeIntervalSince1970 * 1000 + 7 * 86_400_000).rounded().int64)
        #expect(PlaysShare.inviteDays(week, now: now) == 7)
    }
}

private extension Double {
    var int64: Int64 { Int64(self) }
}

// MARK: - Library's Ear dramas

struct PlaysShareLibraryTests {
    @Test func remoteProductionsNotOnThisDeviceJoinTheLocalOnesNewestFirst() throws {
        let script = shareScript()
        let store = temporaryStore()
        let shared = try sharedProduction(store, script, [])
        let plain = try store.create(script)
        let remote = [
            RemoteProduction(id: "P1", title: "Here already", scriptID: "gut-share", director: me, updatedAt: 0),
            RemoteProduction(id: "P2", title: "Not here", scriptID: "gut-share", director: "user-bo",
                             updatedAt: Int64((Date.now.timeIntervalSince1970 + 3_600) * 1000)),
            RemoteProduction(id: "P3", title: "Old", scriptID: "gut-share", director: "user-bo", updatedAt: 1_000),
        ]
        let rows = PlaysShare.libraryRows(store, remote: remote)
        #expect(rows.count == 4)
        #expect(rows.first?.pid == "P2" && rows.first?.local == nil)
        #expect(rows.last?.pid == "P3")
        #expect(Set(rows.compactMap(\.local?.id)) == [shared.id, plain.id])
        #expect(rows.first { $0.local?.id == shared.id }?.pid == "P1")
        #expect(!rows.contains { $0.remote?.id == "P1" })
    }

    @Test func aSharedProductionIsMadeHereOnceAndOnlyAtItsRevision() throws {
        let script = shareScript()
        let store = temporaryStore()
        #expect(PlaysShare.scriptFor([script], id: "gut-share", revision: "r2") == nil)
        #expect(throws: PlaysRefusal.code("revision_mismatch")) {
            try PlaysShare.localFor(store: store, pid: "P9", script: nil)
        }
        let made = try PlaysShare.localFor(store: store, pid: "P9", script: script)
        let again = try PlaysShare.localFor(store: store, pid: "P9", script: script)
        #expect(made.id == again.id && store.productions.count == 1)
    }
}

// MARK: - One line per refusal

struct PlaysShareLineTests {
    @Test func eachRefusalIsTheWebsLine() {
        #expect(PlaysShare.line(PlaysRefusal.code("storage_not_configured")) == "Uploads are off.")
        #expect(PlaysShare.line(PlaysRefusal.code("not_open")) == "This part is taken.")
        #expect(PlaysShare.line(PlaysRefusal.code("another_part_is_recording", detail: "role:MOLLY")) == "MOLLY is still recording.")
        #expect(PlaysShare.line(PlaysRefusal.code("another_part_is_recording", detail: "sound")) == "Sound effects is still recording.")
        #expect(PlaysShare.line(PlaysRefusal.code("lines_missing", count: 1)) == "1 line still needs a take.")
        #expect(PlaysShare.line(PlaysRefusal.code("lines_missing", count: 3)) == "3 lines still need a take.")
        #expect(PlaysShare.line(PlaysRefusal.code("invite_not_found", status: 404)) == "This invite does not work.")
        #expect(PlaysShare.line(PlaysRefusal.code("not_found", status: 404)) == "This production is not shared with you.")
        #expect(PlaysShare.line(PlaysRefusal.code("consent_version_mismatch")) == "The consent changed. Read it again.")
        #expect(PlaysShare.line(PlaysRefusal.code("something_new", status: 500)) == "Ear Drama could not be reached.")
        #expect(PlaysShare.line(PlaysRefusal(status: 429)) == "Too many tries. Try again in a minute.")
        #expect(PlaysShare.line(WorkerError.signedOut) == "Sign in again.")
        #expect(PlaysShare.line(WorkerError.notConfigured) == "Not available yet.")
        #expect(PlaysShare.line(WorkerError.transport) == "Ear Drama could not be reached.")
        #expect(PlaysShare.line(nil) == "")
    }

    @Test func theWorkersProblemIsReadWithItsDetail() {
        let missing = WorkerPlays.refusal(409, Data(#"{"error":"lines_missing","detail":["L1","L4"]}"#.utf8))
        #expect(missing.code == "lines_missing" && missing.detailCount == 2)
        #expect(PlaysShare.line(missing) == "2 lines still need a take.")
        let busy = WorkerPlays.refusal(409, Data(#"{"error":"another_part_is_recording","detail":"role:FIBBER"}"#.utf8))
        #expect(PlaysShare.line(busy) == "FIBBER is still recording.")
        #expect(WorkerPlays.refusal(401, Data()).kind == .unauthorized)
        #expect(WorkerPlays.refusal(429, Data()).code == "rate_limited")
    }

    @Test func theRecordDecodesWithTheWorkersOwnFields() throws {
        let json = #"""
        {"id":"P1","scriptID":"gut-share","scriptRevision":"r1","title":"T","created":1,
         "parts":{"role:MOLLY":{"status":"recording","performer":"Ann","user_id":"u1","claim_expires_at":5},
                  "sound":{"status":"open"}},
         "takes":[{"id":"t1","lineID":"L1","part":"role:MOLLY","file":"a.flac","created":2,"frames":10,
                   "sampleRate":48000,"capture":"direct","heard":{},"loudness":null,"peak":0.1,"bleed":false,
                   "user_id":"u1","audio":"/v1/x"}],
         "chosen":{"L1":"t1"},"roomTone":[],"listenedThrough":false,"director":"u1",
         "members":[{"user_id":"u1","display_name":null,"director":true}],
         "next":null,"hidden_takes":2,"archive":null,"uploads":false,"server_time":9}
        """#
        let rec = try JSONDecoder().decode(SharedRecord.self, from: Data(json.utf8))
        #expect(rec.part(molly).userID == "u1" && rec.part(.sound).status == .open)
        #expect(rec.takes.first?.userID == "u1" && rec.hiddenTakes == 2 && rec.uploads == false)
        #expect(rec.members.first?.director == true && rec.members.first?.displayName == nil)
        #expect(!PlaysShare.uploadsOpen(rec) && !PlaysShare.uploadsOpen(nil))
    }
}
