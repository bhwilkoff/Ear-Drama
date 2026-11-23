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

// The word heard (PLAYS-DESIGN §2.11 rule 3): the golden cases every stack runs
// (catalog/tests/golden/read_along_words.json), and the transport's speed steps (rule 7).

nonisolated private struct WordsGolden: Decodable {
    struct SpokenCase: Decodable {
        let range: [Int]
        let word: [Int]?
    }
    struct SpokenLine: Decodable {
        let line: ScriptLine
        let said: String
        let cases: [SpokenCase]
    }
    struct TextWords: Decodable {
        let said: String
        let words: [[Int]]
    }
    struct Piece: Decodable {
        let symbols: String
        let frames: [Int]
    }
    struct KokoroCase: Decodable {
        let said: String
        let pieces: [Piece]
        let words: [[Int]]?
    }
    let spoken: [SpokenLine]
    let textWords: [TextWords]
    let kokoro: [KokoroCase]

    static func load() throws -> WordsGolden {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(WordsGolden.self, from: Data(contentsOf: root.appendingPathComponent("catalog/tests/golden/read_along_words.json")))
    }
}

struct ReadAlongWordTests {
    @Test func goldenAVoiceRangeLandsOnThePrintedWord() throws {
        let g = try WordsGolden.load()
        #expect(g.spoken.count >= 3)
        for s in g.spoken {
            let spoken = ReadAlong.spoken(s.line)
            #expect(spoken.said == s.said, "\(s.line.id)")
            #expect(spoken.said == DeviceVoices.said(s.line.spokenText), "\(s.line.id) is not the string the voice is given")
            #expect(spoken.toLine.count == spoken.said.utf16.count)
            for c in s.cases {
                let w = ReadAlong.word(spoken, location: c.range[0], length: c.range[1])
                #expect(w.map { [$0.start, $0.end] } == c.word, "\(s.line.id) \(c.range)")
            }
        }
    }

    @Test func goldenPrintedWords() throws {
        for t in try WordsGolden.load().textWords {
            #expect(ReadAlong.textWords(t.said).map { [$0.start, $0.end] } == t.words, "\(t.said)")
        }
    }

    @Test func goldenKokoroWordsComeFromTheDurations() throws {
        let g = try WordsGolden.load()
        #expect(g.kokoro.contains { $0.words == nil })
        for k in g.kokoro {
            let pieces = k.pieces.map { ReadAlong.KokoroPiece(symbols: Array($0.symbols), frames: $0.frames) }
            let got = ReadAlong.kokoroWords(said: k.said, pieces: pieces)
            #expect(got.map { $0.map { [$0.sample, $0.word.start, $0.word.end] } } == k.words, "\(k.said)")
        }
    }

    @Test func aPieceWithTheWrongFrameCountIsRefused() {
        let p = ReadAlong.KokoroPiece(symbols: Array("gˈO."), frames: [1, 1, 1])
        #expect(ReadAlong.kokoroWords(said: "Go.", pieces: [p]) == nil)
    }

    @Test func theWordHeardIsTheLastBegun() {
        let t = [ReadAlong.TimedWord(sample: 100, word: .init(start: 0, end: 2)), ReadAlong.TimedWord(sample: 500, word: .init(start: 3, end: 6))]
        #expect(ReadAlong.word(t, at: 50) == nil)
        #expect(ReadAlong.word(t, at: 100) == .init(start: 0, end: 2))
        #expect(ReadAlong.word(t, at: 499) == .init(start: 0, end: 2))
        #expect(ReadAlong.word(t, at: 9000) == .init(start: 3, end: 6))
    }

    @Test func speedStepsAndLabels() {
        #expect(ReadAlong.speeds == [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2])
        #expect(ReadAlong.speed(nil) == 1)
        #expect(ReadAlong.speed(3) == 2)
        #expect(ReadAlong.speed(0.1) == 0.5)
        #expect(ReadAlong.speed(1.3) == 1.25)
        #expect(ReadAlong.speed(.nan) == 1)
        #expect(ReadAlong.speedLabel(1) == "1\u{00D7}")
        #expect(ReadAlong.speedLabel(1.25) == "1.25\u{00D7}")
        #expect(ReadAlong.speedLabel(0.5) == "0.5\u{00D7}")
        let d = UserDefaults(suiteName: "readalong-speed-test")!
        d.removePersistentDomain(forName: "readalong-speed-test")
        #expect(ReadAlong.savedSpeed(d) == 1)
        ReadAlong.saveSpeed(1.5, d)
        #expect(ReadAlong.savedSpeed(d) == 1.5)
    }
}
