import Foundation
import Testing

/// Listen Together's Swift port held to worker/src/room-protocol.js's own
/// answers: Fixtures/listen-together-golden.json is written BY the JS
/// (Fixtures/make-listen-together-golden.mjs), so a rule changed on one side
/// fails here until both agree.
///
/// Broken controls, 2026-10-23, each seen to fail before the fix was kept:
///   Drift.seekAbove 2 -> 3: the constants and golden correction cases fail.
///   the nudge's sign flipped: the golden correction cases fail.
///   nextHost sorting by id before joined_at: the handoff ledger test fails.
///   RoomLedger.propose without the host check: participantCannotDrive fails.
///   applyHostState keeping the old copy for a new episode: the golden arbiter cases fail.
///   an `import Foundation` added to RoomProtocol.swift: protocolFileImportsNothing fails.
struct RoomProtocolTests {
    private static let golden: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/listen-together-golden.json")
        let data = (try? Data(contentsOf: url)) ?? Data()
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }()

    private func cases(_ key: String) -> [[String: Any]] { Self.golden[key] as? [[String: Any]] ?? [] }

    private func roomState(_ o: [String: Any]) -> RoomState {
        RoomState(episodeID: o["episode_id"] as? String ?? "", archiveID: o["archive_id"] as? String ?? "",
                  file: o["file"] as? String ?? "", position: num(o["position"]), playing: o["playing"] as? Bool ?? false,
                  rate: num(o["rate"]), updatedAt: num(o["updated_at"]))
    }

    private func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? .nan }

    private func correction(_ o: [String: Any]) -> Correction? {
        switch o["action"] as? String {
        case "none": Correction.none
        case "pause": .pause(position: num(o["position"]))
        case "seek": .seek(position: num(o["position"]), play: o["play"] as? Bool ?? false)
        case "play": .play(position: num(o["position"]), rate: num(o["rate"]))
        case "rate": .rate(num(o["rate"]))
        default: nil
        }
    }

    @Test func constantsMatchTheWorker() throws {
        let drift = try #require(Self.golden["drift"] as? [String: Any])
        #expect(num(drift["ignore_below"]) == RoomProtocol.Drift.ignoreBelow)
        #expect(num(drift["seek_above"]) == RoomProtocol.Drift.seekAbove)
        #expect(num(drift["nudge"]) == RoomProtocol.Drift.nudge)
        #expect(num(Self.golden["member_gone_ms"]) == RoomProtocol.memberGoneMS)
        #expect(Self.golden["max_members"] as? Int == RoomProtocol.maxMembers)
        #expect((Self.golden["speeds"] as? [NSNumber])?.map(\.doubleValue) == RoomProtocol.speeds)
    }

    @Test func driftCorrectionMatchesTheWorker() {
        let all = cases("correction")
        #expect(all.count >= 18)
        for c in all {
            let state = roomState(c["state"] as? [String: Any] ?? [:])
            let p = c["player"] as? [String: Any] ?? [:]
            let player = PlayerReading(position: num(p["position"]), playing: p["playing"] as? Bool ?? false)
            let got = RoomProtocol.correction(state, serverNow: num(c["server_now"]), player: player)
            #expect(got == correction(c["expect"] as? [String: Any] ?? [:]), "\(p) against \(state)")
        }
    }

    @Test func handoffOrderMatchesTheWorker() {
        let all = cases("handoff")
        #expect(all.count >= 6)
        for c in all {
            let members = (c["members"] as? [[String: Any]] ?? []).map {
                RoomMember(id: $0["id"] as? String ?? "", joinedAt: num($0["joined_at"]), seenAt: num($0["seen_at"]))
            }
            let got = RoomProtocol.nextHost(members, leaving: c["leaving"] as? String, now: num(c["now"]))
            #expect(got == c["expect"] as? String, "\(members.map(\.id))")
        }
    }

    @Test func arbiterMatchesTheWorker() {
        let all = cases("arbiter")
        #expect(all.count >= 17)
        for c in all {
            let current = (c["current"] as? [String: Any]).map { o in
                HostState(episodeID: o["episode_id"] as? String, archiveID: o["archive_id"] as? String,
                          file: o["file"] as? String, position: num(o["position"]), playing: o["playing"] as? Bool ?? false,
                          rate: num(o["rate"]), updatedAt: num(o["updated_at"]), generation: o["generation"] as? Int ?? 0)
            }
            let i = c["input"] as? [String: Any] ?? [:]
            let input = StateInput(episodeID: i["episode_id"] as? String, archiveID: i["archive_id"] as? String,
                                   file: i["file"] as? String, position: (i["position"] as? NSNumber)?.doubleValue,
                                   playing: i["playing"] as? Bool, rate: (i["rate"] as? NSNumber)?.doubleValue)
            let expect = c["expect"] as? [String: Any] ?? [:]
            switch RoomProtocol.applyHostState(current, input, now: num(c["now"])) {
            case .success(let s):
                let e = expect["state"] as? [String: Any] ?? [:]
                #expect(expect["error"] == nil, "\(i) was refused by the Worker")
                #expect(s.publicState == roomState(e), "\(i)")
                #expect(s.generation == e["generation"] as? Int, "\(i)")
            case .failure(let refusal):
                #expect(refusal.message == expect["error"] as? String, "\(i)")
            }
        }
    }

    @Test func copiesMatchTheWorker() {
        let all = cases("copies")
        #expect(all.count >= 13)
        for c in all {
            let got = RoomProtocol.cleanCopy(archiveID: c["archive_id"] as? String ?? "", file: c["file"] as? String ?? "")
            let e = c["expect"] as? [String: Any]
            #expect(got == e.map { HostCopy(archiveID: $0["archive_id"] as? String ?? "", file: $0["file"] as? String ?? "") },
                    "\(c["file"] ?? "")")
        }
    }

    @Test func clockMatchesTheWorker() {
        for c in cases("clocks") {
            let samples = (c["samples"] as? [[String: Any]] ?? []).map {
                ClockSample(t0: num($0["t0"]), serverTime: num($0["server_time"]), t1: num($0["t1"]))
            }
            #expect(RoomProtocol.clockOffset(samples) == (c["expect"] as? NSNumber)?.doubleValue)
        }
    }

    // MARK: - The ledger: what SharePlay adds on top of the Worker's rules

    private let copy = StateInput(episodeID: "suspense|1948-03-11", archiveID: "OTRR_Suspense", file: "a.mp3",
                                  position: 0, playing: true, rate: 1)

    @Test func participantCannotDrive() {
        var room = RoomLedger(host: "host")
        let opened = room.propose(copy, from: "host", now: 0)
        #expect((try? opened.get()) != nil)
        let before = room
        let refused = room.propose(StateInput(playing: false), from: "guest", now: 5)
        #expect(refused == .failure(RoomRefusal("host_only")))
        #expect(room == before)

        // A guest's ledger takes the host's snapshot and refuses anyone else's.
        var guest = RoomLedger(host: "host")
        let snap = RoomSnapshot(code: "", role: "guest", members: 2, state: room.state!, serverTime: 0)
        var forged = snap
        forged.generation += 1
        forged.state.playing = false
        let tookForged = guest.receive(forged, from: "guest2")
        let tookHosts = guest.receive(snap, from: "host")
        let tookAgain = guest.receive(snap, from: "host")
        #expect(!tookForged)
        #expect(tookHosts)
        #expect(!tookAgain, "an old generation is not news")
        #expect(guest.state?.playing == true)
    }

    @Test func rosterComesOnlyFromTheHostItNames() {
        var guest = RoomLedger()
        let roster = [RoomMember(id: "host", joinedAt: 0, seenAt: 0)]
        let impostor = guest.receive(roster: roster, host: "host", from: "mallory")
        let fromHost = guest.receive(roster: roster, host: "host", from: "host")
        let takeover = guest.receive(roster: [], host: "mallory", from: "mallory")
        #expect(!impostor)
        #expect(fromHost)
        #expect(!takeover)
        #expect(guest.host == "host")
    }

    @Test func hostLeavingHandsOffToTheLongestPresent() {
        var room = RoomLedger(host: "host")
        _ = room.presenceChanged(present: ["host"], now: 0, admitting: true)
        _ = room.presenceChanged(present: ["host", "b"], now: 10, admitting: true)
        _ = room.presenceChanged(present: ["host", "b", "a"], now: 20, admitting: true)
        #expect(room.members.map(\.id) == ["host", "b", "a"])
        let hostStays = room.presenceChanged(present: ["host", "a", "b"], now: 30)
        #expect(hostStays == nil)
        let handoff = room.presenceChanged(present: ["a", "b"], now: 40)
        #expect(handoff == "b")
        #expect(room.host == "b")
        let empty = room.presenceChanged(present: [], now: 50)
        #expect(empty == nil)
        #expect(room.host == nil)
    }

    @Test func roomMessageKeepsTheWorkersFieldNames() throws {
        let state = try RoomProtocol.applyHostState(nil, copy, now: 7).get()
        let data = try JSONEncoder().encode(RoomSnapshot(code: "", role: "guest", members: 2, state: state, serverTime: 9))
        let o = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(o.keys) == ["v", "code", "role", "members", "generation", "state", "server_time"])
        let s = try #require(o["state"] as? [String: Any])
        #expect(Set(s.keys) == ["episode_id", "archive_id", "file", "position", "playing", "rate", "updated_at"])
    }

    @Test func protocolFileImportsNothing() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Core/ListenTogether/RoomProtocol.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.isEmpty)
        #expect(source.range(of: #"(?m)^\s*(@\w+\s+)?import\s"#, options: .regularExpression) == nil)
        for name in ["URLSession", "GroupSession", "Date(", "AVPlayer"] { #expect(!source.contains(name), "\(name)") }
    }
}
