import Foundation
import Testing

/// Leaving and removing in a read room (PLAYS-DESIGN §12.13; App Store guideline 1.2), the Android rule on Apple:
/// `leave` is sent by a person's act only, a pause never says it, and a device the room no longer holds says so and stops.
///
/// Broken controls, each seen to fail before the fix was kept:
///   leave() sending nothing: leaveTellsTheRoomOnce failed.
///   pause() sending the goodbye too: aPauseNeverLeaves failed.
///   canRemove letting a class's leading student remove: removeFollowsTheGoldenRulesAndNamesWhoIsHere failed.
///   a not_a_member answer left as a refusal (the transport kept asking): aRemovedDeviceStops failed.
@MainActor
struct ReadLeaveTests {
    nonisolated private final class Wire: ReadWire, @unchecked Sendable {
        private let lock = NSLock()
        private var sentMessages: [String] = []
        private var asks = 0
        var answer: ReadFailure?
        var sent: [String] { lock.withLock { sentMessages } }
        var polls: Int { lock.withLock { asks } }
        let joined: ReadJoined
        init(_ joined: ReadJoined) { self.joined = joined }
        func create(body: Data, teacher: Bool) async throws -> ReadJoined { joined }
        func join(code: String, body: Data) async throws -> ReadJoined { joined }
        func poll(code: String, key: String) async throws -> ReadSnapshot {
            lock.withLock { asks += 1 }
            try await Task.sleep(for: .seconds(30))
            throw ReadFailure(code: "offline")
        }
        func send(code: String, key: String, message: Data) async throws -> ReadSnapshot? {
            lock.withLock { sentMessages.append(String(decoding: message, as: UTF8.self)) }
            if let answer { throw answer }
            return nil
        }
        func socket(code: String) -> (any ReadSocket)? { nil }
        func sendTake(code: String, key: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws {}
        func inbox(code: String, key: String) async throws -> PickedTake? { nil }
        func pair() async throws -> ReadPairing { throw ReadFailure(code: "error") }
        func pairWait(_ pairing: ReadPairing) async throws -> ReadJoined? { nil }
        func attachScreen(code: String, key: String, pairCode: String) async throws {}
    }

    private static func snap(you: String, leads: Bool, owner: Bool, kind: String = "adult", leader: String = "host") throws -> ReadSnapshot {
        let o: [String: Any] = [
            "type": "snapshot", "code": "ABC123", "kind": kind, "mode": "read", "script_id": "gut-1", "script_revision": "r1",
            "cursor": "l1", "cursor_gen": 1, "generation": 1, "locked": false, "ended": false, "leader": leader,
            "waiting_for_leader": false, "present": 3, "claims": [String: String](),
            "seats": [["id": "s1", "label": "Lucy"]], "assignments": [], "done": [], "server_time": 1000, "read_open": false,
            "you": ["id": you, "role": "reader", "name": "Me", "leads": leads, "owner": owner],
            "members": [["id": "host", "role": "reader", "name": "Ben", "live": true], ["id": "ann", "role": "reader", "name": "", "live": false],
                        ["id": "s", "role": "reader", "seat": "s1", "live": true], ["id": "tv", "role": "screen", "live": true]],
        ]
        return try JSONDecoder().decode(ReadSnapshot.self, from: JSONSerialization.data(withJSONObject: o))
    }

    private func room(_ answer: ReadFailure? = nil) async throws -> (ReadSession, Wire) {
        let wire = Wire(ReadJoined(snapshot: try Self.snap(you: "ann", leads: false, owner: false), key: "key", transport: "poll"))
        wire.answer = answer
        let session = ReadSession(wire: wire)
        try await session.join(code: "ABC123")
        return (session, wire)
    }

    private func settle(_ wire: Wire, sent n: Int) async {
        for _ in 0..<300 where wire.sent.count < n { try? await Task.sleep(for: .milliseconds(10)) }
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test func leaveTellsTheRoomOnce() async throws {
        let (session, wire) = try await room()
        session.leave()
        await settle(wire, sent: 1)
        #expect(wire.sent == [#"{"type":"leave"}"#], "\(wire.sent)")
        #expect(session.snapshot == nil && session.code == nil, "the key and the room are dropped")
        session.leave()
        await settle(wire, sent: 2)
        #expect(wire.sent.count == 1, "a second Close says nothing: there is no room")
    }

    @Test func aPauseNeverLeaves() async throws {
        let (session, wire) = try await room()
        session.pause()
        await settle(wire, sent: 1)
        #expect(wire.sent.isEmpty, "a rotation, a background or a screen going away keeps the key and says nothing")
        #expect(session.code == "ABC123" && session.snapshot != nil, "the seat is kept")
    }

    @Test func aRemovedDeviceStops() async throws {
        let (session, wire) = try await room(ReadFailure(code: "not_a_member"))
        try? await session.send(["type": "cursor", "line": "l2", "base": 1])
        #expect(session.ended == "not_a_member")
        #expect(ReadCore.refusal("not_a_member") == "You are no longer in this reading.")
        #expect(session.code == nil || session.ended != nil, "the room is over for this device, and its transport is stopped")
        await #expect(throws: ReadFailure.self) { try await session.send(["type": "cursor", "line": "l3", "base": 1]) }
        #expect(wire.sent.count == 1, "and nothing more is sent")
    }

    @Test func removeFollowsTheGoldenRulesAndNamesWhoIsHere() throws {
        let host = try Self.snap(you: "host", leads: true, owner: true)
        let rows = ReadCore.removable(host)
        #expect(rows.map(\.label) == ["A reader", "Lucy", "A screen"], "\(rows)")
        #expect(rows.map(\.id) == ["ann", "s", "tv"], "never oneself")
        #expect(rows.first { $0.id == "ann" }?.live == false)
        #expect(ReadCore.removable(try Self.snap(you: "ann", leads: false, owner: false)).isEmpty, "a plain reader may remove nobody")
        #expect(ReadCore.removable(try Self.snap(you: "ann", leads: true, owner: false)).count == 3, "an adult room's leader may")
        #expect(ReadCore.removable(try Self.snap(you: "kid", leads: true, owner: false, kind: "class", leader: "kid")).isEmpty, "a class's leading student may not")
        #expect(ReadCore.removable(try Self.snap(you: "teacher", leads: false, owner: true, kind: "class")).count == 4, "a class's teacher may remove every member, a screen too")
        #expect(ReadCore.removable(nil).isEmpty)
    }
}
