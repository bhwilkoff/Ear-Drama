import CoreText
import Foundation
import Testing

// Marks on the Core Text page (R2-marks-port-brief §2): a point mark takes room after its word (figure spaces in the
// page string, never in the text), a span mark takes none; a mark maps to a range of the page string and a selection
// of the page string maps back to line pieces. (A kern on the word's last character was tried first: Core Text
// ignores it once the whole script is one string, 300 thousand characters, so the room is real glyphs.)

nonisolated private func pageScript(_ lines: [ScriptLine]) -> PlayScript {
    PlayScript(id: "pg", revision: "r1", kind: "stage", title: "T", authors: [], source: .init(name: "S", url: "https://example.org"),
               rights: .init(bucket: "script_source_cleared", evidence: []),
               roles: [PlayScript.Role(name: "A", lines: 1, words: 17), PlayScript.Role(name: "B", lines: 1, words: 5)],
               lines: lines, sections: nil)
}

struct MarkPageTests {
    private static let play = pageScript([
        ScriptLine(id: "L0001", kind: .speech, role: "A",
                   parts: [.say("Yes, the very first thing tomorrow morning, and then we go to the sea and look about us.")]),
        ScriptLine(id: "L0002", kind: .speech, role: "B", parts: [.say("It is cold out there.")]),
    ])

    private static func layout(_ s: PlayScript, points: [Mark] = []) throws -> ReaderLayout {
        try ReaderLayout.build(s, structure: ScriptStructure(s), style: ReaderStyle(base: 17, scale: 1, leading: 1.55),
                               pageSize: CGSize(width: 340, height: 600), points: points)
    }

    /// The x of the character at `loc` on its frame line.
    private static func x(_ l: ReaderLayout, _ loc: Int) -> CGFloat {
        let lines = CTFrameGetLines(l.frame(l.page(containing: loc))) as! [CTLine]
        let line = lines.first { CTLineGetStringRange($0).location <= loc && loc < CTLineGetStringRange($0).location + CTLineGetStringRange($0).length }!
        return CTLineGetOffsetForStringIndex(line, loc, nil)
    }

    @Test func aPointMarkTakesRoomAfterItsWordASpanMarkTakesNone() throws {
        let p = Self.play
        let plain = try Self.layout(p)
        let breath = try #require(MarksCore.fromSelection(p, [MarkPiece(line: "L0001", start: 5, end: 8)], .breath).first)
        let marked = try Self.layout(p, points: [breath])
        let gap = try #require(marked.gapRange(of: breath, line: 0), "the page made a gap for the breath")
        #expect(marked.string.length == plain.string.length + gap.length)
        let ns = marked.string.string as NSString
        #expect(ns.substring(with: NSRange(location: gap.location - 3, length: 3)) == "the", "right after its word")
        #expect(ns.substring(with: gap).allSatisfy { $0 == "\u{2007}" })
        // The words after it are pushed along, and the words are still the script's.
        let after = gap.location + gap.length + 1
        #expect(Self.x(marked, after) - Self.x(plain, gap.location + 1) > 5)
        let index = ["L0001": 0, "L0002": 1]
        let whole = marked.pieces(for: NSRange(location: 0, length: marked.string.length), ids: ["L0001", "L0002"])
        #expect(whole.map { "\($0.line):\($0.start):\($0.end)" } == ["L0001:0:\(ScriptReading.lineText(p.lines[0]).utf16.count)",
                                                                     "L0002:0:\(ScriptReading.lineText(p.lines[1]).utf16.count)"], "the gap is never a word")
        let spans = marked.spans(of: breath, page: 0, index: index)
        #expect(spans.count == 1 && spans[0].x1 - spans[0].x0 >= 8, "the mark's room measured on the page")
        let span = try #require(MarksCore.fromSelection(p, [MarkPiece(line: "L0001", start: 5, end: 8)], .highlight).first)
        let withSpan = try Self.layout(p, points: [span])
        #expect(withSpan.string.isEqual(to: plain.string), "a span mark leaves the page alone")
    }

    @Test func pointMarksTakeRoomOverARealScript() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let all = try JSONDecoder().decode(CastableLibrary.self, from: Data(contentsOf: root.appendingPathComponent("catalog/plays/castable-scripts.json"))).scripts
        let s = try #require(all.first { $0.lines.count > 300 })
        let st = ScriptStructure(s)
        var marks: [Mark] = []
        var i = 5
        while i < s.lines.count {
            let n = ScriptReading.lineText(s.lines[i]).utf16.count
            if n > 30, let m = MarksCore.fromSelection(s, [MarkPiece(line: s.lines[i].id, start: n / 3, end: n / 3 + 4)], .pause).first { marks.append(m) }
            i += 41
        }
        #expect(marks.count > 5)
        let style = ReaderStyle(base: 17, scale: 1, leading: 1.55)
        let plain = try ReaderLayout.build(s, structure: st, style: style, pageSize: CGSize(width: 340, height: 600))
        let marked = try ReaderLayout.build(s, structure: st, style: style, pageSize: CGSize(width: 340, height: 600), points: marks)
        for m in marks {
            let li = try #require(st.indexByID[m.line])
            let gap = try #require(marked.gapRange(of: m, line: li), "a gap for the mark on \(m.line)")
            #expect(gap.length >= 1)
        }
        #expect(marked.pageCount >= plain.pageCount, "room taken, never given")
        let ids = s.lines.map(\.id)
        let a = plain.pieces(for: NSRange(location: 0, length: plain.string.length), ids: ids)
        let b = marked.pieces(for: NSRange(location: 0, length: marked.string.length), ids: ids)
        #expect(a == b, "the same words under the same offsets, with or without the room")
    }

    @Test func aMarkMapsToThePageStringAndASelectionMapsBack() throws {
        let p = Self.play
        let l = try Self.layout(p)
        let index = ["L0001": 0, "L0002": 1]
        let m = try #require(MarksCore.fromSelection(p, [MarkPiece(line: "L0001", start: 5, end: 14)], .highlight).first)
        let r = try #require(l.range(of: m, index: index))
        #expect((l.string.string as NSString).substring(with: r) == m.text, "the range reads the marked words")
        let back = l.pieces(for: r, ids: ["L0001", "L0002"])
        #expect(back == [MarkPiece(line: "L0001", start: m.start, end: m.end)], "and back to the same offsets")
        let word = try #require(l.wordRange(at: r.location + 2))
        #expect((l.string.string as NSString).substring(with: word) == "the")
    }
}
