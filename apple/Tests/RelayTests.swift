import Foundation
import Testing

/// Relay across time (PLAYS-DESIGN §12.11), the mirror of js/relay.test.js: the sender's queue and its states, a seat's
/// source over a stub Worker, and the consent rule's list. Nothing is recorded aloud or sent anywhere; the clock is a
/// closure the test turns by hand. Each rule's break, seen to fail (2026-11-19):
///   `RelayCore.delay` returning `gaps[0]`: backoffGrowsThenHolds failed.
///   `RelaySender.run` taking `probe.receiving` as true: nothingIsSentWhileTheReceiverIsAway failed.
///   `later` without "nobody_receiving": aTakeTheReceiverWasNotThereForStays failed.
///   `assignedLines` ignoring `to`: aSceneRange failed.
///   `SeatRelaySource.pending` without the assigned-lines filter: onlyAssignedLines failed.
///   `SeatRelaySource.pending` without `!$0.bleed`: aFlaggedTakeNeverLeaves failed.
///   `performers` without credits: aCreditedMakerBlocksPublish failed.

private let lucyWhole = [ReadSnapshot.Assignment(part: "role:LUCY", seat: "s1", from: nil, to: nil)]

@MainActor
private final class StubSeat: SeatWire, @unchecked Sendable {
    var receiving = false
    var name: String? = "Ms. Ortiz"
    var assignments: [ReadSnapshot.Assignment] = lucyWhole
    var taken: [String] = []
    var sends: [String] = []
    var probes = 0
    var failWith: String?

    nonisolated func home(key: String) async throws -> SeatHome {
        await MainActor.run {
            SeatHome(seat: .init(id: "s1", label: "Lucy"), class: .init(id: "c1", name: "Room 7"),
                     productions: [.init(id: "pid-1", title: "The Lost Lady", scriptID: "gut-1", scriptRevision: "r1", assignments: assignments,
                                         takes: taken.map { SeatHome.Take(id: $0, lineID: "x", chosen: true, review: nil) })])
        }
    }

    nonisolated func receiver(key: String, pid: String) async throws -> RelayReceiver {
        await MainActor.run { probes += 1; return RelayReceiver(receiving: receiving, name: name) }
    }

    nonisolated func send(key: String, pid: String, takeID: String, audio: Data, meta: TakeMeta) async throws {
        let failure: String? = await MainActor.run { sends.append(meta.lineID); return failWith }
        if let failure { throw ReadFailure(code: failure) }
        let ok = await MainActor.run { receiving }
        guard ok else { throw ReadFailure(code: "nobody_receiving") }
        await MainActor.run { taken.append(takeID) }
    }
}

private func line(_ id: String, _ role: String?, _ kind: ScriptLine.Kind = .speech) -> ScriptLine {
    kind == .speech ? ScriptLine(id: id, kind: .speech, role: role, parts: [.say("Words of \(id) and a few more besides these.")]) : ScriptLine(id: id, kind: kind, source: "(\(id))")
}

private func play() -> PlayScript {
    let lines = [line("l1", nil, .direction), line("l2", "LUCY"), line("l3", "TOM"), line("l4", "LUCY"), line("l5", nil, .sound),
                 line("l6", "TOM"), line("l7", "NURSE"), line("l8", "LUCY")]
    let roles = ["LUCY", "TOM", "NURSE"].map { n in PlayScript.Role(name: n, lines: lines.filter { $0.role == n }.count, words: 3) }
    return PlayScript(id: "gut-1", revision: "r1", kind: "radio", title: "The Lost Lady", authors: [],
                      source: .init(name: "Fixture", url: "https://example.org"),
                      rights: .init(bucket: "script_source_cleared", evidence: []), roles: roles, lines: lines)
}

/// A production on this device linked to a seat, with a (silent) take for each of `lineIDs`.
@MainActor
private func seatRig(_ lineIDs: [String], flagged: [String] = [], assignments: [ReadSnapshot.Assignment] = lucyWhole,
                     wire: StubSeat) throws -> (store: ProductionStore, id: String, hub: RelayHub, vault: MemorySeatVault) {
    let store = ProductionStore(root: FileManager.default.temporaryDirectory.appending(path: "relay-tests-\(UUID().uuidString)"))
    let script = play()
    var p = try store.create(script)
    let vault = MemorySeatVault()
    try store.linkSeat(p.id, pid: "pid-1", classID: "c1", label: "Lucy", key: String(repeating: "k", count: 24), assignments: assignments, vault: vault)
    for id in lineIDs {
        let capture = MicrophoneCapture(samples: [Float](repeating: 0.01, count: 4_800), sampleRate: 48_000)
        let file = try store.writeTake(capture, production: p, lineID: id)
        let part = script.lines.first { $0.id == id }!.part
        p.add(Take(id: "T-\(id)", lineID: id, part: part, file: file, created: Date(), frames: 4_800, sampleRate: 48_000, capture: .direct, heard: [:],
                   loudness: nil, peak: 0.1, bleed: flagged.contains(id)))
    }
    try store.save(p)
    let hub = RelayHub(store: store, seatWire: wire, vault: vault, sleep: { _ in })
    return (store, p.id, hub, vault)
}

@MainActor
struct RelayAcrossTimeTests {
    @Test func theWordsAreOneFactPerState() {
        #expect(RelayCore.wording(.waiting, name: "Ms. Ortiz") == "On this device \u{00B7} sends when Ms. Ortiz is in Ear Drama")
        #expect(RelayCore.wording(.waiting, name: nil, fallback: "your teacher") == "On this device \u{00B7} sends when your teacher is in Ear Drama")
        #expect(RelayCore.wording(.sent, name: "x") == "Sent")
        #expect(RelayCore.wording(.sending, name: "x") == "Sending")
        #expect(RelayCore.state("a", sent: ["a"], sending: "a") == .sent)
        #expect(RelayCore.state("b", sent: ["a"], sending: "b") == .sending)
        #expect(RelayCore.state("c", sent: ["a"], sending: "b") == .waiting)
    }

    @Test func backoffGrowsThenHolds() {
        #expect([0, 1, 2, 3, 4, 5, 20].map(RelayCore.delay) == [5_000, 10_000, 20_000, 40_000, 60_000, 60_000, 60_000])
    }

    @Test func aSceneRange() {
        let cast = play().lines.map { ($0.id, $0.part.rawValue) }
        #expect(RelayCore.assignedLines(cast: cast, assignments: [.init(part: "role:LUCY", seat: "s1", from: "l2", to: "l4")]) == ["l2", "l4"])
        #expect(RelayCore.assignedLines(cast: cast, assignments: lucyWhole) == ["l2", "l4", "l8"])
        #expect(RelayCore.assignedLines(cast: cast, assignments: []).isEmpty)
    }

    @Test func nothingIsSentWhileTheReceiverIsAway() async throws {
        let wire = StubSeat()
        let r = try seatRig(["l2", "l4"], wire: wire)
        await r.hub.kick(r.id)
        #expect(wire.sends.isEmpty)
        #expect(wire.probes == 1)
        let sender = try #require(r.hub.sender(for: r.id))
        #expect(sender.failures == 1)
        #expect(r.hub.state(r.id, "T-l2").0 == .waiting)
        #expect(sender.name == "Ms. Ortiz")
        wire.receiving = true
        await r.hub.kick(r.id)
        #expect(wire.sends == ["l2", "l4"])
        #expect(r.hub.state(r.id, "T-l2").0 == .sent)
        #expect(r.store.share(r.id)?.sent == ["T-l2", "T-l4"])
        let takeFile = try #require(r.store.production(r.id)?.takes.first?.file)
        #expect(try r.store.readTake(r.id, file: takeFile).count > 44)
    }

    @Test func aTakeTheReceiverWasNotThereForStays() async throws {
        let wire = StubSeat()
        wire.receiving = true
        let r = try seatRig(["l2"], wire: wire)
        wire.failWith = "nobody_receiving"
        await r.hub.kick(r.id)
        #expect(wire.sends == ["l2"])
        #expect(r.hub.state(r.id, "T-l2").0 == .waiting)
        #expect(r.store.share(r.id)?.sent == nil)
        #expect(r.hub.sender(for: r.id)?.failures == 1)
    }

    @Test func aFinalRefusalLeavesTheQueueOnceAndStaysOnTheDevice() async throws {
        let wire = StubSeat()
        wire.receiving = true
        wire.failWith = "not_assigned"
        let r = try seatRig(["l2"], wire: wire)
        await r.hub.kick(r.id)
        #expect(r.store.share(r.id)?.refused?["T-l2"] == "not_assigned")
        await r.hub.kick(r.id)
        #expect(wire.sends.count == 1)
        #expect(r.store.production(r.id)?.takes.count == 1)
    }

    @Test func onlyAssignedLines() async throws {
        let wire = StubSeat()
        wire.receiving = true
        wire.assignments = [.init(part: "role:LUCY", seat: "s1", from: "l4", to: "l4")]
        let r = try seatRig(["l2", "l4"], assignments: wire.assignments, wire: wire)
        await r.hub.kick(r.id)
        #expect(wire.sends == ["l4"])
    }

    @Test func aTakeTheWorkerHoldsIsNotSentAgainAndAFlaggedTakeNeverLeaves() async throws {
        let wire = StubSeat()
        wire.receiving = true
        wire.taken = ["T-l2"]
        let r = try seatRig(["l2", "l4", "l8"], flagged: ["l8"], wire: wire)
        await r.hub.kick(r.id)
        #expect(wire.sends == ["l4"])
    }

    @Test func theSeatKeyIsInTheKeychainNeverInShareJSON() throws {
        let wire = StubSeat()
        let r = try seatRig(["l2"], wire: wire)
        let raw = try String(contentsOf: r.store.shareURL(r.id), encoding: .utf8)
        #expect(!raw.contains(String(repeating: "k", count: 24)))
        #expect(r.vault.key(forClass: "c1") == String(repeating: "k", count: 24))
    }

    @Test func rowsCarryTheStateOfEachLine() throws {
        let wire = StubSeat()
        let r = try seatRig(["l2", "l4"], wire: wire)
        let script = play()
        let lines = script.lines.filter { $0.part.rawValue == "role:LUCY" }
        let remote = ["l2": SeatHome.Take(id: "T-l2", lineID: "l2", chosen: true, review: .init(state: "again", note: "Slower."))]
        let rows = RelayCore.rows(lines: lines, local: r.store.production(r.id), remote: remote, sentHere: [], refused: [:], sending: nil, name: "Ms. Ortiz")
        #expect(rows[0].state == "Sent")
        #expect(rows[0].review == "Again \u{00B7} Slower.")
        #expect(rows[0].again)
        #expect(rows[1].state == "On this device \u{00B7} sends when Ms. Ortiz is in Ear Drama")
        #expect(rows[2].state == nil)
    }

    @Test func aCreditedMakerBlocksPublish() {
        let rec = SharedRecord(id: "p", scriptID: "gut-1", scriptRevision: "r1", title: "T", parts: [:], director: "dee",
                               members: [.init(userID: "dee", displayName: "Dee", director: true, performer: false, consented: true)])
        var withCredit = rec
        withCredit.credits = [.init(name: "Ann", lines: 2, consented: false)]
        #expect(PlaysShare.performers(withCredit).map(\.displayName) == ["Ann"])
        #expect(PlaysShare.waitingOn(withCredit).map(\.displayName) == ["Ann"])
        #expect(PlaysShare.waitingOn(rec).isEmpty)
        let json = #"{"id":"p","scriptID":"gut-1","scriptRevision":"r1","title":"T","parts":{},"credits":[{"name":"Ann","lines":2,"consented":false}]}"#
        #expect((try? JSONDecoder().decode(SharedRecord.self, from: Data(json.utf8)))?.credits.first?.name == "Ann")
    }
}
