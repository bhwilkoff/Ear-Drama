import Foundation
import Testing

/// ReadCore's Swift port held to worker/test/read-golden.json, the file the Worker's own protocol writes and the
/// web and Kotlin ports read. Run the cases of every function a client ports; a snapshot must land a client on the
/// server's own next line. Negative controls (2026-11-19, each seen to fail before it was kept):
///   the harness over a golden copy with one expected value flipped: failures > 0 (goldenHarnessSeesADrift).
///   leaderGone letting a class hand the lead on: the leaderGone goldens failed.
///   assignmentFor ignoring a range's `to`: partsOf/whoReads/nextMine goldens failed.
/// T5 (2026-11-19), the new ports against the same file (98 cases, 22 of them these functions):
///   recordRefusal without the holds check: the recordRefusal goldens failed (recordRefusalNeedsItsHoldsCheck holds that).
///   cleanName keeping a 41 character name: the cleanName goldens failed.
///   receiverOf answering the leader for a class: the receiverOf and joinSnapshot goldens failed.
struct ReadCoreTests {
    private static let golden: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("worker/test/read-golden.json")
        let data = (try? Data(contentsOf: url)) ?? Data()
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }()

    private static func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
    private static func str(_ v: Any?) -> String? { v as? String }

    private static func room(_ o: Any?) -> ReadCore.Room {
        let d = o as? [String: Any] ?? [:]
        func list<T>(_ k: String, _ f: ([String: Any]) -> T) -> [T] { (d[k] as? [[String: Any]] ?? []).map(f) }
        return ReadCore.Room(
            kind: str(d["kind"]) ?? "adult", mode: str(d["mode"]) ?? "read", cursor: str(d["cursor"]) ?? "",
            cursorGen: Int(num(d["cursor_gen"])), generation: Int(num(d["generation"])), leader: str(d["leader"]) ?? "", owner: str(d["owner"]) ?? "", ownerName: str(d["owner_name"]),
            claims: d["claims"] as? [String: String] ?? [:],
            seats: list("seats") { ReadCore.Seat(id: str($0["id"]) ?? "", label: str($0["label"]) ?? "") },
            assignments: list("assignments") { ReadCore.Assignment(part: str($0["part"]) ?? "", seat: str($0["seat"]) ?? "", from: str($0["from"]), to: str($0["to"])) },
            done: d["done"] as? [String] ?? [], locked: d["locked"] as? Bool ?? false, ended: d["ended"] as? Bool ?? false)
    }

    private static func member(_ o: Any?) -> ReadCore.Member? {
        guard let d = o as? [String: Any] else { return nil }
        return ReadCore.Member(id: str(d["id"]) ?? "", role: str(d["role"]) ?? "reader", seat: str(d["seat"]),
                               joinedAt: num(d["joined_at"]), seenAt: num(d["seen_at"]), name: str(d["name"]))
    }

    private static func members(_ o: Any?) -> [ReadCore.Member] { (o as? [Any] ?? []).compactMap(member) }
    private static func cast(_ o: Any?) -> [(String, String)] { (o as? [[String]] ?? []).map { ($0[0], $0[1]) } }

    private static func jsonValue(_ v: Any?) -> Any { v ?? NSNull() }

    private static func range(_ r: ReadCore.PartRange) -> [String: Any] {
        ["part": r.part, "from": jsonValue(r.from), "to": jsonValue(r.to)]
    }

    /// What a ported function answers for a golden case, shaped as the JSON the Worker wrote.
    private static func answer(_ c: [String: Any], recordRefusal: (ReadCore.Room, [(String, String)], ReadCore.Member?, String) -> String? = {
        ReadCore.recordRefusal($0, cast: $1, member: $2, lineID: $3)
    }) -> Any? {
        guard let fn = c["fn"] as? String, let a = c["args"] as? [Any] else { return nil }
        switch fn {
        case "normalizeCode": return jsonValue(ReadCore.normalizeCode(a[0] as? String ?? ""))
        case "codeFromBytes": return ReadCore.codeFromBytes((a[0] as? [NSNumber] ?? []).map(\.intValue))
        case "clockOffset":
            let s = (a[0] as? [[String: Any]] ?? []).map { ReadCore.ClockSample(t0: num($0["t0"]), serverTime: num($0["server_time"]), t1: num($0["t1"])) }
            return jsonValue(ReadCore.clockOffset(s))
        case "canLead": return ReadCore.canLead(room(a[0]), memberID: a[1] as? String)
        case "partsOf": return ReadCore.partsOf(room(a[0]), member: member(a[1])).map(range)
        case "whoReads":
            let r = room(a[0])
            guard let w = ReadCore.whoReads(r, cast: cast(a[1]), members: members(a[2]), lineID: a[3] as? String ?? "", now: num(a[4])) else { return NSNull() }
            var o: [String: Any] = ["part": w.part, "seat": jsonValue(w.seat), "members": w.members]
            if r.kind != "class" { o["holder"] = jsonValue(w.holder) }
            return o
        case "nextMine":
            guard let n = ReadCore.nextMine(room(a[0]), cast: cast(a[1]), member: member(a[2]), cursor: a[3] as? String ?? "") else { return NSNull() }
            return ["line": n.line, "in": n.inLines]
        case "leaderGone":
            let l = ReadCore.leaderGone(room(a[0]), members: members(a[1]), now: num(a[2]))
            return ["leader": l.leader, "waiting": l.waiting]
        case "cleanName":
            switch ReadCore.cleanName(room(a[0]), a[1] as? String) {
            case .none: return NSNull()
            case .refused: return false
            case let .name(n): return n
            }
        case "receiverOf": return ReadCore.receiverOf(room(a[0]))
        case "recordRefusal": return jsonValue(recordRefusal(room(a[0]), cast(a[1]), member(a[2]), a[3] as? String ?? ""))
        case "leaderName": return jsonValue(ReadCore.leaderName(room(a[0]), members: members(a[1])))
        default: return nil
        }
    }

    private static let ported: Set<String> = ["normalizeCode", "codeFromBytes", "clockOffset", "canLead", "partsOf", "whoReads", "nextMine", "leaderGone",
                                          "cleanName", "receiverOf", "recordRefusal", "leaderName"]

    private static func same(_ x: Any?, _ y: Any?) -> Bool {
        guard let x, let y else { return x == nil && y == nil }
        return (x as AnyObject).isEqual(y)
    }

    /// Names of the golden cases the port answers differently from the Worker.
    private static func failures(in cases: [[String: Any]], recordRefusal: ((ReadCore.Room, [(String, String)], ReadCore.Member?, String) -> String?)? = nil) -> [String] {
        var bad: [String] = []
        for c in cases {
            let fn = c["fn"] as? String ?? ""
            if ported.contains(fn) {
                let got = recordRefusal.map { answer(c, recordRefusal: $0) } ?? answer(c)
                if !same(got, c["expect"]) { bad.append("\(fn): \(c["note"] ?? "")") }
            } else if fn == "joinSnapshot", let e = c["expect"] as? [String: Any],
                      let data = try? JSONSerialization.data(withJSONObject: e),
                      let snap = try? JSONDecoder().decode(ReadSnapshot.self, from: data) {
                let a = c["args"] as? [Any] ?? []
                let got = ReadCore.nextMine(snap.room, cast: cast(a[1]), member: snap.meMember, cursor: snap.cursor)
                let want = snap.nextMine
                if got?.line != want?.line || got?.inLines != want?.in { bad.append("snapshot next line: \(c["note"] ?? "")") }
                if let receiver = snap.receiver, ReadCore.receiverOf(snap.room) != receiver { bad.append("snapshot receiver: \(c["note"] ?? "")") }
                if let you = snap.you, you.receives != nil, you.receives != (snap.receiver == you.id) { bad.append("snapshot receives: \(c["note"] ?? "")") }
            }
        }
        return bad
    }

    private var cases: [[String: Any]] { Self.golden["cases"] as? [[String: Any]] ?? [] }

    @Test func everyPortedGoldenCaseHolds() {
        let ran = cases.filter { Self.ported.contains($0["fn"] as? String ?? "") || $0["fn"] as? String == "joinSnapshot" }
        #expect(ran.count >= 30)
        #expect(Self.failures(in: cases).isEmpty, "\(Self.failures(in: cases))")
    }

    @Test func theNewT5FunctionsAreRunOverEveryOfTheirCases() {
        let t5 = ["cleanName", "receiverOf", "recordRefusal", "leaderName"]
        for fn in t5 { #expect(cases.filter { $0["fn"] as? String == fn }.count >= 2, "\(fn) has cases") }
        #expect(cases.filter { t5.contains($0["fn"] as? String ?? "") }.count >= 18)
        #expect(Self.failures(in: cases.filter { t5.contains($0["fn"] as? String ?? "") }).isEmpty)
    }

    /// The control: the same goldens, run through a recordRefusal that skips the holds check, must fail.
    @Test func recordRefusalNeedsItsHoldsCheck() {
        let mutant: (ReadCore.Room, [(String, String)], ReadCore.Member?, String) -> String? = { room, cast, member, line in
            if room.ended { return "room_ended" }
            if room.mode != "record" { return "not_recording" }
            guard let member, member.role == "reader" else { return "readers_only" }
            guard ReadCore.indexOf(cast, line) != nil else { return "no_such_line" }
            if member.id == ReadCore.receiverOf(room) { return "receiver_records_here" }
            return nil
        }
        let bad = Self.failures(in: cases, recordRefusal: mutant)
        #expect(bad.contains { $0.hasPrefix("recordRefusal") }, "\(bad)")
        #expect(Self.failures(in: cases).isEmpty)
    }

    @Test func constantsAreTheProtocols() throws {
        let k = try #require(Self.golden["constants"] as? [String: Any])
        #expect(k["CODE_ALPHABET"] as? String == String(ReadCore.codeAlphabet))
        #expect(Int(Self.num(k["CODE_LENGTH"])) == ReadCore.codeLength)
        #expect(Int(Self.num(k["MAX_MEMBERS"])) == ReadCore.maxMembers)
        #expect(Self.num(k["MEMBER_GONE_MS"]) == ReadCore.memberGoneMS)
        #expect(Self.num(k["LEADER_GONE_MS"]) == ReadCore.leaderGoneMS)
        #expect(Int(Self.num(k["POLL_MS"])) == ReadCore.pollMS)
        #expect(k["MODES"] as? [String] == ReadCore.modes)
    }

    /// The harness is a test only once it is seen to fail: one expected answer flipped must be caught.
    @Test func goldenHarnessSeesADrift() {
        var mutated = cases
        guard let i = mutated.firstIndex(where: { $0["fn"] as? String == "nextMine" }) else { Issue.record("no nextMine case"); return }
        mutated[i]["expect"] = ["line": "zz", "in": 99]
        #expect(!Self.failures(in: mutated).isEmpty)
    }

    @Test func theSnapshotCarriesTheLeadersNameAndReadOpenParts() throws {
        let snaps = cases.filter { $0["fn"] as? String == "joinSnapshot" }.compactMap { $0["expect"] as? [String: Any] }
        let named = try #require(snaps.first { $0["leader_name"] as? String == "Ben" })
        let data = try JSONSerialization.data(withJSONObject: named)
        let snap = try JSONDecoder().decode(ReadSnapshot.self, from: data)
        #expect(ReadCore.waitingFor(snap) == "Ben")
        #expect(snap.readOpen == true)
    }

    @Test func aReaderSaysWhenItsNextLineIsComing() {
        #expect(ReadCore.nextLine(.init(line: "l4", inLines: 3)) == "Next: you, in 3 lines")
        #expect(ReadCore.nextLine(.init(line: "l4", inLines: 1)) == "Next: you, in 1 line")
        #expect(ReadCore.nextLine(.init(line: "l4", inLines: 0)) == "Your line")
        #expect(ReadCore.nextLine(nil) == nil)
    }

    @Test func fillEvenlyIsDeterministicAndKeepsTheCastingMade() {
        let cast: [(String, String)] = [("a", "P1"), ("b", "P2"), ("c", "P1"), ("d", "P3"), ("e", "P2")]
        let words = [10, 4, 10, 2, 4]
        let facts = ReadCore.partFacts(cast: cast, words: words, starts: [0])
        #expect(facts.first { $0.part == "P1" }?.words == 20)
        let seats = [ReadCore.Seat(id: "s1", label: "Ann"), ReadCore.Seat(id: "s2", label: "Bo")]
        let made = [ReadCore.Assignment(part: "P3", seat: "s1")]
        let out = ReadCore.fillEvenly(parts: facts, seats: seats, assignments: made, cast: cast, words: words)
        #expect(out.first == made.first)
        #expect(out.first { $0.part == "P1" }?.seat == "s2")
        #expect(out == ReadCore.fillEvenly(parts: facts, seats: seats, assignments: made, cast: cast, words: words))
        #expect(ReadCore.sceneRanges(cast: cast, part: "P1", starts: [0, 2]).count == 2)
    }
}
