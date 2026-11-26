import CoreText
import Foundation
import Testing

// B29 (owner 2026-11-26, the open Duo): a play-through flipped the first pages back and forth as the parts read. The
// follower turned to the page a line's RANGE begins on, and line 1's range holds the front (title, parts), so it
// asked for the opening page while the word heard sat on the next; every re-layout (the "Device voice" strip and the
// transport coming and going change the page height) sent it back to that page again. The rule: the page the
// read-along turns to holds the words heard, and while lines advance it never goes back.

struct ReaderFollowTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func scripts() throws -> [PlayScript] {
        try JSONDecoder().decode(CastableLibrary.self, from: Data(contentsOf: root.appendingPathComponent("catalog/plays/castable-scripts.json"))).scripts
    }

    /// The open Duo's reader page, the folded Duo's (an iPhone's), and the open Duo's with the strip shown.
    private static let sizes = [CGSize(width: 612, height: 700), CGSize(width: 342, height: 558), CGSize(width: 612, height: 676)]
    private static let style = ReaderStyle(base: 17, scale: 1, leading: 1.55)

    /// The words a voice would mark in line `i`: every printed word, in order.
    private static func words(_ line: ScriptLine) -> [ReadAlong.Word] {
        let text = ScriptReading.lineText(line) as NSString
        var out: [ReadAlong.Word] = []
        var at = 0
        while at < text.length {
            let r = text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted, options: [], range: NSRange(location: at, length: text.length - at))
            guard r.location != NSNotFound else { break }
            var end = r.location
            while end < text.length, let u = UnicodeScalar(text.character(at: end)), !CharacterSet.whitespacesAndNewlines.contains(u) { end += 1 }
            out.append(ReadAlong.Word(start: r.location, end: end))
            at = end
        }
        return out
    }

    /// Plays through the opening lines the way the reader follows them (turn to the line, then the words), and records
    /// each page shown with the line and word that asked for it.
    @Test func thePageHoldsTheWordHeardAndNeverGoesBack() throws {
        let all = try Self.scripts()
        #expect(all.count >= 3)
        var checked = 0
        for s in all {
            let st = ScriptStructure(s)
            let spoken = s.lines.indices.filter { s.lines[$0].kind == .speech }.prefix(40)
            for size in Self.sizes {
                let layout = try ReaderLayout.build(s, structure: st, style: Self.style, pageSize: size)
                var shown = -1
                var last = (line: -1, page: -1)
                for i in spoken {
                    let line = s.lines[i]
                    let turnTo = layout.followPage(i)
                    let firstWord = Self.words(line).first.flatMap { layout.page(ofWord: $0, line: i) }
                    if let firstWord {
                        #expect(turnTo == firstWord, "\(s.id) \(Int(size.width))x\(Int(size.height)) line \(line.id): turns to page \(turnTo + 1), its first word is on \(firstWord + 1)")
                    }
                    shown = turnTo
                    #expect(shown >= last.page, "\(s.id) \(Int(size.width))x\(Int(size.height)): line \(line.id) went back to page \(shown + 1) from \(last.page + 1) (line \(last.line))")
                    last = (i, shown)
                    for w in Self.words(line) {
                        guard let p = layout.page(ofWord: w, line: i) else { continue }
                        if p != shown { shown = p }
                        #expect(shown >= last.page, "\(s.id): a word of \(line.id) went back to page \(shown + 1)")
                        last = (i, shown)
                    }
                    checked += 1
                }
            }
        }
        #expect(checked > 300)
    }

    /// A re-layout while a line is heard (the page height changes when the strip or the transport comes or goes) lands
    /// on the page that holds the word heard, at either height, never on the line's first page or the front.
    @Test func aRelayoutLandsOnTheWordHeard() throws {
        let all = try Self.scripts()
        var checked = 0
        for s in all {
            let st = ScriptStructure(s)
            let spoken = s.lines.indices.filter { s.lines[$0].kind == .speech }.prefix(30)
            let a = try ReaderLayout.build(s, structure: st, style: Self.style, pageSize: Self.sizes[0])
            let b = try ReaderLayout.build(s, structure: st, style: Self.style, pageSize: Self.sizes[2])
            for i in spoken {
                for w in Self.words(s.lines[i]) {
                    for layout in [a, b] {
                        guard let p = layout.page(ofWord: w, line: i) else { continue }
                        let land = layout.landingPage(keep: i, heard: i, word: w)
                        #expect(land == p, "\(s.id) h=\(Int(layout.pageSize.height)) \(s.lines[i].id) word \(w.start): a re-layout lands on page \(land + 1), the word is on \(p + 1)")
                        checked += 1
                    }
                }
                // Nothing marked yet (a take, a voice without word timing): the line's own first page, never the front.
                if let first = Self.words(s.lines[i]).first, let p = a.page(ofWord: first, line: i) {
                    #expect(a.landingPage(keep: i, heard: i, word: nil) == p, "\(s.id) \(s.lines[i].id): lands on \(a.landingPage(keep: i, heard: i, word: nil) + 1), its words begin on \(p + 1)")
                }
            }
            // Not following anything: the kept line's first page, so the play opens on its front.
            #expect(a.landingPage(keep: 0, heard: nil, word: nil) == 0)
        }
        #expect(checked > 1000)
    }
}
