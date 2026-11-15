import Foundation
import Testing

// Marks in the script reader (Decision 076 S5), held to the web's js/marks.test.js case for case: the golden cases
// every stack runs (catalog/tests/golden/marks_anchor.json), the offsets every drawn run keeps into the line's
// words (through PlayPage.layoutOf, with verse, emphasis and run-in speakers), the overlap rules, groups, storage
// under the script id, and the export rows. Offsets are UTF-16 units.
//
// Seen to fail: before MarksCore.swift existed (nothing compiled); then against mutated copies of it, as the
// web's were: place() without the evidence floor (the short word guessed into another line), bestIn() without the
// context score (the second "no" lands on the first), add() without the touching rule (`<` for `<=`), remove()
// ignoring the group, and PlayPage.layoutOf's verse rows without `at += lead` (the verse offsets case).

nonisolated private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

nonisolated private func bundled() throws -> [PlayScript] {
    let data = try Data(contentsOf: root.appendingPathComponent("catalog/plays/castable-scripts.json"))
    return try JSONDecoder().decode(CastableLibrary.self, from: data).scripts
}

nonisolated private func script(_ id: String = "s", revision: String = "r1", title: String = "T", lines: [ScriptLine],
                                roles: [PlayScript.Role] = []) -> PlayScript {
    PlayScript(id: id, revision: revision, kind: "stage", title: title, authors: [], source: .init(name: "S", url: "https://example.org"),
               rights: .init(bucket: "script_source_cleared", evidence: []), roles: roles, lines: lines, sections: nil)
}

nonisolated private func speech(_ id: String, _ role: String = "A", _ say: String) -> ScriptLine {
    ScriptLine(id: id, kind: .speech, role: role, parts: [.say(say)])
}

nonisolated private func lt(_ line: ScriptLine) -> String { ScriptReading.lineText(line) }

nonisolated private func tmp() -> URL {
    URL.temporaryDirectory.appending(path: "marks-test-\(UUID().uuidString)", directoryHint: .isDirectory)
}

nonisolated private struct Golden: Decodable {
    struct Snap: Decodable { let text: String; let start: Int; let end: Int; let want: [Int]? }
    struct Point: Decodable { let text: String; let end: Int; let want: Int }
    struct Doc: Decodable { let revision: String; let lines: [ScriptLine] }
    struct MarkSpec: Decodable { let line: String; let start: Int; let end: Int; let kind: String }
    struct Anchor: Decodable {
        let name: String
        let before: Doc
        let after: Doc
        let mark: MarkSpec
        let want: Want
    }
    /// `["L0001", 16, 26]` or `"lost"`.
    enum Want: Decodable {
        case lost
        case at(String, Int, Int)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self), s == "lost" { self = .lost; return }
            var u = try decoder.unkeyedContainer()
            self = .at(try u.decode(String.self), try u.decode(Int.self), try u.decode(Int.self))
        }
    }
    let snap: [Snap]
    let point: [Point]
    let anchor: [Anchor]
}

struct MarksTests {
    private static func golden() throws -> Golden {
        try JSONDecoder().decode(Golden.self, from: Data(contentsOf: root.appendingPathComponent("catalog/tests/golden/marks_anchor.json")))
    }

    // MARK: The golden cases (every stack)

    @Test func goldenASelectionGrowsToWholeWordsAndSpaceAloneIsNothing() throws {
        let g = try Self.golden()
        #expect(g.snap.count >= 6)
        for c in g.snap {
            let w = MarksCore.snapWords(c.text, c.start, c.end)
            #expect(w.map { [$0.start, $0.end] } == c.want, "snap \(c.text.debugDescription) [\(c.start), \(c.end))")
        }
    }

    @Test func goldenAPointMarkGoesAfterItsWordAndThePunctuationThatFollows() throws {
        for c in try Self.golden().point {
            #expect(MarksCore.pointAfter(c.text, c.end) == c.want, "point \(c.text.debugDescription) at \(c.end)")
        }
    }

    @Test func goldenReAnchoringARevision() throws {
        let g = try Self.golden()
        #expect(g.anchor.count >= 8)
        for c in g.anchor {
            let before = script(revision: c.before.revision, lines: c.before.lines)
            let after = script(revision: c.after.revision, lines: c.after.lines)
            let kind = try #require(MarkKind(rawValue: c.mark.kind))
            let m = try #require(MarksCore.make(before, c.mark.line, c.mark.start, c.mark.end, kind, now: 1000), Comment(rawValue: c.name))
            let r = MarksCore.place(after, [m])
            switch c.want {
            case .lost:
                #expect(r.placed.isEmpty, "\(c.name): not placed")
                #expect(r.lost == [m], "\(c.name): kept exactly as stored")
            case let .at(line, start, end):
                #expect(r.lost.isEmpty, "\(c.name): placed")
                guard let p = r.placed.first else { continue }
                #expect([p.line, "\(p.start)", "\(p.end)"] == [line, "\(start)", "\(end)"], "\(c.name)")
                let words = after.lines.first { $0.id == p.line }.map { Array(lt($0).utf16) } ?? []
                #expect(String(decoding: words[p.start..<p.end], as: UTF16.self) == m.text, "\(c.name): still the same words")
                #expect(p.revision == after.revision, "\(c.name): takes the new revision")
            }
        }
    }

    // MARK: Offsets: every drawn run maps back into lineText

    private static func same(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String { s.map { $0.isWhitespace ? " " : String($0) }.joined() }
        return norm(a) == norm(b)
    }

    /// Every run `layoutOf` draws, with the line's words it claims.
    private static func drawn(_ line: ScriptLine, _ roles: [String]) -> [PageRun] {
        let lay = PlayPage.layoutOf(line, roles: roles)
        if line.kind != .speech || line.parts == nil { return lay.rows.flatMap(\.runs) }
        return lay.speeches.flatMap { s in (s.name.map { [$0] } ?? []) + s.rows.flatMap(\.runs) }
    }

    @discardableResult
    private static func checkOffsets(_ s: PlayScript, _ tag: String) -> Int {
        let roles = s.roles.map(\.name)
        var runs = 0
        for line in s.lines {
            let units = Array(lt(line).utf16)
            for r in drawn(line, roles) {
                runs += 1
                let n = r.text.utf16.count
                let claimed = r.at >= 0 && r.at + n <= units.count ? String(decoding: units[r.at..<(r.at + n)], as: UTF16.self) : "<out of range>"
                #expect(same(claimed, r.text), "\(tag) \(line.id): a run at \(r.at) draws \(r.text.debugDescription) but the line holds \(claimed.debugDescription)")
            }
        }
        return runs
    }

    @Test func offsetsEveryRunLayoutOfDrawsOverEveryBundledScriptMapsBackIntoLineText() throws {
        var n = 0
        for s in try bundled() { n += Self.checkOffsets(s, s.id) }
        #expect(n > 5000, "runs checked (\(n))")
    }

    @Test func offsetsVerseRowsKeepTheirOffsetsAndTheIndentIsKeptAsARow() throws {
        let text = "Doubtful it stood;\nAs two spent swimmers, that do cling together\n    And choke their art."
        let fixture = script("v", lines: [speech("L0001", "CAPTAIN", text)], roles: [PlayScript.Role(name: "CAPTAIN", lines: 1, words: 12)])
        let lay = PlayPage.layoutOf(fixture.lines[0], roles: ["CAPTAIN"])
        #expect(lay.verse)
        Self.checkOffsets(fixture, "fixture")
        #expect(lay.speeches[0].rows.map(\.indent) == [false, false, true])
        var checked = 0
        for s in try bundled() {
            for l in s.lines where l.kind == .speech && PlayPage.layoutOf(l, roles: []).verse && checked < 200 {
                checked += 1
                Self.checkOffsets(script(s.id, lines: [l], roles: s.roles), s.id)
            }
        }
        #expect(checked > 0, "the bundle holds verse")
    }

    @Test func offsetsEmphasisAndARunInSpeaker() {
        let roles = [PlayScript.Role(name: "CHARTERIS", lines: 3, words: 30), PlayScript.Role(name: "GRACE", lines: 1, words: 5)]
        let s = script("e", lines: [
            ScriptLine(id: "L0001", kind: .speech, role: "CHARTERIS",
                       parts: [.say("It is the first in which"), .direction("I"), .say("have been serious.")]),
            ScriptLine(id: "L0002", kind: .speech, role: "CHARTERIS",
                       parts: [.say("I believe it"), .say("is"), .say("a very pleasant state.")], em: [1]),
            ScriptLine(id: "L0003", kind: .speech, role: "CHARTERIS",
                       parts: [.say("Of course. Why not?\nGRACE"), .direction("reflecting"), .say(". Never mind _why_.")]),
        ], roles: roles)
        Self.checkOffsets(s, "fixture")
        let names = ["CHARTERIS", "GRACE"]
        let l3 = PlayPage.layoutOf(s.lines[2], roles: names)
        #expect(l3.speeches.map(\.role) == ["CHARTERIS", "GRACE"])
        let em = Self.drawn(s.lines[2], names).first { $0.kind == .em }
        if let em {
            let units = Array(lt(s.lines[2]).utf16)
            #expect(String(decoding: units[em.at..<(em.at + em.text.utf16.count)], as: UTF16.self) == "why")
        } else {
            Issue.record("no em run in the run-in line")
        }
    }

    // MARK: Making marks from a selection

    private static let play = script("gut-test", lines: [
        speech("L0001", "A", "Yes--the first thing tomorrow morning, and then we go."),
        ScriptLine(id: "L0002", kind: .direction, source: "[He crosses to the window.]"),
        speech("L0003", "B", "It is cold out there."),
    ])
    private static let t1 = lt(play.lines[0])

    private static func sub(_ s: String, _ a: Int, _ b: Int) -> String {
        String(decoding: Array(s.utf16)[a..<b], as: UTF16.self)
    }

    @Test func aSelectionSpanMarksGrowToWordsAPointMarkGoesAfterTheLastWordANoteAnchorsToItsFirstLine() throws {
        let p = Self.play
        let h = try #require(MarksCore.fromSelection(p, [MarkPiece(line: "L0001", start: 11, end: 17)], .highlight, MarkExtra(hue: "green"), now: 5).first)
        #expect([h.start, h.end] == [9, 20] && h.text == "first thing" && h.hue == "green" && h.revision == "r1")
        #expect(h.prefix == "Yes--the ")
        #expect(h.suffix == Self.sub(Self.t1, 20, 52))
        let b = try #require(MarksCore.fromSelection(p, [MarkPiece(line: "L0001", start: 30, end: 33)], .breath, now: 5).first)
        #expect([b.start, b.end] == [38, 38] && b.text == "")
        let across = [MarkPiece(line: "L0001", start: 47, end: Self.t1.utf16.count), MarkPiece(line: "L0002", start: 0, end: 10),
                      MarkPiece(line: "L0003", start: 0, end: 5)]
        let hs = MarksCore.fromSelection(p, across, .underline, now: 5)
        #expect(hs.map(\.line) == ["L0001", "L0002", "L0003"], "one mark per line")
        #expect(hs[0].group != nil && hs.allSatisfy { $0.group == hs[0].group }, "one group")
        let ns = MarksCore.fromSelection(p, across, .note, MarkExtra(note: "warm"), now: 5)
        #expect(ns.map(\.line) == ["L0001"] && ns[0].note == "warm" && ns[0].group == nil, "a note: its first line, no group")
        let pause = try #require(MarksCore.fromSelection(p, across, .pause, now: 5).first)
        #expect(pause.line == "L0003" && pause.start == 5)
        let beat = try #require(MarksCore.fromSelection(p, [MarkPiece(line: "L0003", start: 0, end: 2)], .beat,
                                                         MarkExtra(label: "  the turn, a long label past the limit "), now: 5).first)
        #expect(beat.label == "the turn, a long label p", "a beat label trimmed to 24 characters")
        #expect(MarksCore.fromSelection(p, [MarkPiece(line: "L0001", start: 8, end: 9)], .highlight).isEmpty, "a space alone makes nothing")
        #expect(MarksCore.fromSelection(p, [MarkPiece(line: "L9999", start: 0, end: 3)], .highlight).isEmpty)
    }

    @Test func offsetsAreUTF16SoACurlyQuoteOrAnEmojiNeverShiftsAMark() throws {
        let line = speech("L0001", "A", "\u{201C}Why\u{201D}\u{2014}not \u{1F600} then, my dear friend.")
        let s = script("u", lines: [line])
        let units = Array(lt(line).utf16)
        let start = units.count - 12
        let m = try #require(MarksCore.fromSelection(s, [MarkPiece(line: "L0001", start: start, end: units.count)], .highlight).first)
        #expect(m.text == "my dear friend.".prefix(12) || m.text.hasSuffix("friend."))
        #expect(Self.sub(lt(line), m.start, m.end) == m.text)
        let r = MarksCore.place(script("u", revision: "r2", lines: [line]), [m])
        #expect(r.lost.isEmpty && r.placed.first.map { $0.start == m.start } == true)
    }

    // MARK: Overlap

    @Test func overlapHighlightsMergeOverlappingOrTouchingIntoOneInTheNewHueNotesNeverMerge() throws {
        let p = Self.play
        func hl(_ a: Int, _ b: Int, _ hue: String) -> Mark? { MarksCore.make(p, "L0001", a, b, .highlight, MarkExtra(hue: hue)) }
        var ms: [Mark] = []
        ms = MarksCore.add(p, ms, hl(9, 14, "yellow"))
        ms = MarksCore.add(p, ms, hl(21, 29, "blue"))
        ms = MarksCore.add(p, ms, hl(12, 20, "pink"))
        func hls() -> [[String]] {
            MarksCore.order(p, ms).filter { $0.kind == .highlight }.map { ["\($0.start)", "\($0.end)", $0.hue ?? ""] }
        }
        #expect(hls() == [["9", "20", "pink"], ["21", "29", "blue"]], "the overlap merged; the separate one stayed")
        #expect(ms.first { $0.hue == "pink" }?.text == Self.sub(Self.t1, 9, 20), "the merged quote is re-read")
        ms = MarksCore.add(p, ms, hl(20, 21, "green"))
        #expect(hls() == [["9", "29", "green"]], "touching both: one highlight over all, in the new hue")
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0001", 9, 14, .underline))
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0001", 14, 20, .underline))
        #expect(ms.filter { $0.kind == .underline }.map { [$0.start, $0.end] } == [[9, 20]], "touching underlines merge")
        #expect(ms.filter { $0.kind == .highlight }.count == 1, "a highlight and an underline share words")
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0001", 9, 14, .note, MarkExtra(note: "a")))
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0001", 9, 14, .note, MarkExtra(note: "b")))
        #expect(ms.filter { $0.kind == .note }.count == 2, "two notes on the same words stay two")
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0003", 0, 2, .highlight))
        #expect(ms.filter { $0.kind == .highlight }.count == 2, "another line never merges")
    }

    @Test func overlapOnePointMarkAPlace() {
        let p = Self.play
        var ms: [Mark] = []
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0001", 38, 38, .breath))
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0001", 47, 47, .breath))
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0001", 9, 20, .highlight))
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0001", 38, 38, .pause))
        #expect(ms.filter { !$0.isSpan }.map { "\($0.kind.rawValue)\($0.start)" }.sorted() == ["breath47", "pause38"], "replaced in place")
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0001", 38, 38, .beat, MarkExtra(label: "turn")))
        #expect(ms.filter { $0.start == 38 && !$0.isSpan }.map { "\($0.kind.rawValue)/\($0.label ?? "")" } == ["beat/turn"], "a beat replaces the pause")
        #expect(ms.filter { $0.kind == .highlight }.count == 1, "span marks untouched")
    }

    @Test func removeAndUpdateAGroupGoesTogetherAHueChangesForTheGroup() throws {
        let p = Self.play
        let across = [MarkPiece(line: "L0001", start: 47, end: Self.t1.utf16.count), MarkPiece(line: "L0003", start: 0, end: 5)]
        var ms = MarksCore.fromSelection(p, across, .highlight, MarkExtra(hue: "yellow")).reduce([Mark]()) { MarksCore.add(p, $0, $1) }
        ms = MarksCore.add(p, ms, MarksCore.make(p, "L0002", 1, 3, .highlight))
        ms = MarksCore.update(ms, ms[0].id, MarkPatch(hue: "blue"))
        #expect(ms.map { $0.hue ?? "" } == ["blue", "blue", "yellow"], "the group took the hue; the other did not")
        let r = MarksCore.remove(ms, ms[1].id)
        #expect(r.marks.count == 1, "both of the group removed")
        #expect(r.removed.count == 2, "what was removed is returned, for Undo")
        #expect(r.marks.count + r.removed.count == 3, "undo puts them back")
        var n = [try #require(MarksCore.make(p, "L0003", 0, 2, .note, MarkExtra(note: "x"))),
                 try #require(MarksCore.make(p, "L0003", 0, 2, .beat, MarkExtra(label: "a")))]
        n = MarksCore.update(n, n[0].id, MarkPatch(note: "cold, say it cold"))
        n = MarksCore.update(n, n[1].id, MarkPatch(label: "shift"))
        #expect(n.map { $0.note ?? $0.label ?? "" } == ["cold, say it cold", "shift"])
    }

    @Test func aTapOnWordsTheNarrowestSpanMarkUnderTheOffsetANoteFirst() throws {
        let p = Self.play
        let ms = [MarksCore.make(p, "L0001", 0, 40, .highlight), MarksCore.make(p, "L0001", 9, 20, .underline),
                  MarksCore.make(p, "L0001", 9, 20, .note), MarksCore.make(p, "L0001", 38, 38, .breath)].compactMap { $0 }
        #expect(MarksCore.at(ms, "L0001", 10).map(\.kind) == [.note, .underline, .highlight])
        #expect(MarksCore.at(ms, "L0001", 38).map(\.kind) == [.highlight], "a point mark is not a span")
        #expect(MarksCore.at(ms, "L0003", 1).isEmpty)
    }

    @Test func theNotebookOrderIsScriptOrderAndLostMarksAreKeptApart() {
        let p = Self.play
        let ms = [MarksCore.make(p, "L0003", 3, 5, .underline), MarksCore.make(p, "L0001", 38, 38, .breath),
                  MarksCore.make(p, "L0001", 9, 20, .highlight), MarksCore.make(p, "L0002", 1, 3, .note)].compactMap { $0 }
        #expect(MarksCore.order(p, ms).map { "\($0.line):\($0.start)" } == ["L0001:9", "L0001:38", "L0002:1", "L0003:3"])
        let next = script("gut-test", revision: "r2", lines: [p.lines[0], speech("L0003", "B", "Warm in here.")])
        let r = MarksCore.place(next, ms)
        #expect(r.placed.map(\.kind.rawValue).sorted() == ["breath", "highlight"], "the first line's marks placed")
        #expect(r.lost.map(\.line).sorted() == ["L0002", "L0003"], "the others kept as not placed, untouched")
        #expect(r.changed, "the placed marks took the new revision")
        let again = MarksCore.place(next, r.placed)
        #expect(!again.changed && again.lost.isEmpty, "placing again changes nothing")
    }

    @Test func reAnchoringOverARealScriptMarksSurviveANewRevisionAndASplitLine() throws {
        let s = try #require(try bundled().first { $0.lines.count > 300 })
        var ms: [Mark] = []
        var i = 5
        while i < s.lines.count {
            let text = lt(s.lines[i]), n = text.utf16.count
            if let w = MarksCore.snapWords(text, n / 3, n / 3 + 6), let m = MarksCore.make(s, s.lines[i].id, w.start, w.end, .highlight) { ms.append(m) }
            i += 37
        }
        #expect(ms.count > 5, "marks made (\(ms.count))")
        let next = script(s.id, revision: s.revision + "-next", lines: s.lines)
        let r = MarksCore.place(next, ms)
        #expect(r.lost.isEmpty, "none lost when only the revision changed")
        #expect(r.placed.map { "\($0.line):\($0.start)" } == ms.map { "\($0.line):\($0.start)" }, "each where it was")
        // Split one marked line in two (the run-in fix's shape): its words move to the new `a` id.
        let target = ms[2]
        let k = try #require(s.lines.firstIndex { $0.id == target.line })
        let units = Array(lt(s.lines[k]).utf16)
        let head = String(decoding: units[0..<target.start], as: UTF16.self).trimmingCharacters(in: .whitespaces)
        let tail = String(decoding: units[target.start...], as: UTF16.self)
        var lines = Array(s.lines[..<k])
        lines.append(ScriptLine(id: target.line, kind: .direction, source: head.isEmpty ? "[...]" : head))
        lines.append(ScriptLine(id: target.line + "a", kind: .direction, source: tail))
        lines += s.lines[(k + 1)...]
        let r2 = MarksCore.place(script(s.id, revision: "split", lines: lines), [target])
        #expect(r2.placed.map { "\($0.line):\($0.start):\($0.text)" } == ["\(target.line)a:0:\(target.text)"], "followed its words to the split id")
    }

    // MARK: On the device

    @Test func storageOnePerScriptUnreadableReadsAsNoneUnknownKindDroppedNoMarksRemovesTheFile() throws {
        let dir = tmp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MarkStore(root: dir)
        let p = Self.play
        let ms = [try #require(MarksCore.make(p, "L0001", 9, 20, .highlight, MarkExtra(hue: "blue"), now: 1_700_000_000_000)),
                  try #require(MarksCore.make(p, "L0003", 0, 2, .note, MarkExtra(note: "cold"), now: 1_700_000_000_000))]
        try store.save(scriptID: p.id, title: p.title, ms)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "gut-test.json").path), "under Marks/<script id>.json")
        #expect(store.load("gut-test") == ms, "loaded back")
        #expect(store.load("other").isEmpty, "another script has none")
        try Data("{not json".utf8).write(to: dir.appending(path: "bad.json"))
        #expect(store.load("bad").isEmpty, "unreadable: none")
        let good = try JSONEncoder().encode(ms[0])
        let json = "{\"marks\":[{\"id\":\"x\",\"kind\":\"scribble\",\"line\":\"L1\",\"start\":0,\"end\":1,\"text\":\"a\"}," + String(decoding: good, as: UTF8.self) + "],\"script\":\"junk\",\"format\":1}"
        try Data(json.utf8).write(to: dir.appending(path: "junk.json"))
        #expect(store.load("junk").count == 1, "a mark of an unknown kind is dropped on read")
        try store.save(scriptID: p.id, title: p.title, [])
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "gut-test.json").path), "no marks: the file is removed")
    }

    @Test func storageAFailedWriteIsReportedNeverSwallowed() throws {
        let file = tmp()
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = MarkStore(root: file)
        let m = try #require(MarksCore.make(Self.play, "L0001", 9, 20, .highlight))
        #expect(throws: (any Error).self) { try store.save(scriptID: "s", title: nil, [m]) }
    }

    @Test func storageTheWebsKeysAndPrefs() throws {
        let dir = tmp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MarkStore(root: dir)
        let m = try #require(MarksCore.make(Self.play, "L0001", 9, 20, .highlight, MarkExtra(hue: "pink"), now: 5))
        try store.save(scriptID: "gut-test", title: "Test", [m])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appending(path: "gut-test.json"))) as? [String: Any])
        #expect(object["format"] as? Int == 1 && object["script"] as? String == "gut-test" && object["title"] as? String == "Test")
        let row = try #require((object["marks"] as? [[String: Any]])?.first)
        for key in ["id", "kind", "line", "start", "end", "text", "prefix", "suffix", "revision", "created", "updated", "hue"] {
            #expect(row[key] != nil, "key \(key)")
        }
        let defaults = UserDefaults(suiteName: "marks-test-\(UUID().uuidString)")!
        #expect(MarkStore.prefs(defaults) == (true, "yellow"), "prefs default: shown, yellow")
        MarkStore.savePrefs(show: false, hue: "pink", defaults)
        #expect(MarkStore.prefs(defaults) == (false, "pink"), "prefs kept")
    }

    @Test func exportRowsEveryPlaysMarksSortedByScriptNeverThePrefs() throws {
        let dir = tmp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MarkStore(root: dir)
        let t = Int64(1_794_052_800_000)
        let p = Self.play
        try store.save(scriptID: "gut-test", title: "Test", [try #require(MarksCore.make(p, "L0001", 9, 20, .highlight, MarkExtra(hue: "blue"), now: t))])
        let two = script("gut-2", title: "Two", lines: p.lines)
        try store.save(scriptID: "gut-2", title: "Two", [try #require(MarksCore.make(two, "L0003", 0, 2, .note, MarkExtra(note: "cold"), now: t))])
        let rows = store.exportRows()
        #expect(rows.map { [$0.script, $0.title ?? "", $0.kind, $0.text, $0.hue ?? "-", $0.note ?? "-"] }
                == [["gut-2", "Two", "note", "It", "-", "cold"], ["gut-test", "Test", "highlight", "first thing", "blue", "-"]])
        let export = DataExport(exportedAt: .now, history: [], following: [], queue: [], takes: [], marks: rows)
        let object = try #require(try JSONSerialization.jsonObject(with: export.json()) as? [String: Any])
        let first = try #require((object["marks"] as? [[String: Any]])?.first)
        #expect(first["created"] as? String == Date(timeIntervalSince1970: Double(t) / 1000).formatted(.iso8601))
        #expect(first["hue"] is NSNull && first["label"] is NSNull)
    }
}
