import Foundation
import Testing

// The read-along's follow logic (PLAYS-DESIGN §2.11): the line heard comes from the listen plan, a mix finds its line
// by time, the reader turns itself while following, holds still after a turn-away, and returns. The same cases as
// js/reader.test.js.

struct ReadAlongTests {
    private static func entries(_ ids: [String]) -> [ListenEntry] {
        ids.map { .voice(lineID: $0, part: PartID(rawValue: "role:A"), text: "x") }
    }

    @Test func lineComesFromThePlan() {
        let plan = Self.entries(["L1", "L3", "L4"])
        #expect([ReadAlong.line(plan, at: 0), ReadAlong.line(plan, at: 1), ReadAlong.line(plan, at: 2)] == ["L1", "L3", "L4"])
        #expect(ReadAlong.line(plan, at: 3) == nil)
        #expect(ReadAlong.line(plan, at: -1) == nil)
        #expect(ReadAlong.line([], at: 0) == nil)
    }

    @Test func mixFindsItsLineByTime() {
        let spans = [ReadAlong.Span(lineID: "L1", start: 0, frames: 100), ReadAlong.Span(lineID: "L2", start: 150, frames: 100)]
        func at(_ s: Double) -> String? { ReadAlong.line(spans, rate: 100, seconds: s) }
        #expect(at(0) == "L1")
        #expect(at(0.99) == "L1")
        #expect(at(1.2) == "L1")
        #expect(at(1.5) == "L2")
        #expect(at(2.49) == "L2")
        #expect(at(2.6) == nil)
        #expect(ReadAlong.line([], rate: 100, seconds: 1) == nil)
    }

    @Test func turnsWhileFollowingAndHoldsAfterTurningAway() {
        var f = ReadAlong.Follow()
        #expect(f.line("L1") == .init(turn: true, back: false))
        f.away()
        #expect(f.line("L2") == .init(turn: false, back: true))
        #expect(f.line("L3") == .init(turn: false, back: true))
        #expect(f.back() == "L3")
        #expect(f.line("L4") == .init(turn: true, back: false))
        f.away()
        _ = f.line(nil)
        #expect(f.back() == nil)
        f.away()
        #expect(f.line(nil) == .init(turn: false, back: false))
    }

    @Test func panelShowsTheLineHeardAndOneEachSide() {
        let lines = (0..<3).map { ScriptLine(id: "L\($0)", kind: .speech, role: "A", parts: [.say("w\($0)")]) }
        func ids(_ id: String) -> [String?] {
            let p = ReadAlong.panel(lines, around: id)
            return [p.before?.id, p.current?.id, p.after?.id]
        }
        #expect(ids("L1") == ["L0", "L1", "L2"])
        #expect(ids("L0") == [nil, "L0", "L1"])
        #expect(ids("L2") == ["L1", "L2", nil])
        #expect(ids("nope") == [nil, nil, nil])
    }
}
