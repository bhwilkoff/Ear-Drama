import CoreText
import Foundation
import PencilKit
import Testing

// Pencil ink anchored to script lines (PLAYS-DESIGN §2.10 rule 1, iOS-DESIGN §4.15 "Marks"; Decision 076 S5): a
// line's strokes live in its block's coordinates, so they move with the line through a new text width, scale with
// the column, follow a line onto the next page, survive a revision only with the line's words, and are stored
// per script beside the marks and exported as a count and the drawing.
//
// Seen to fail against mutated copies of InkCore.swift: `factor` returning 1 (ink stops scaling with the column),
// `transform` ignoring the block's `stack` (ink on a speech's second page lands a page too low), and `place`
// without the words check (ink stays on a line whose words changed).

#if canImport(UIKit)
import UIKit
nonisolated private let black = UIColor.black
#else
import AppKit
nonisolated private let black = NSColor.black
#endif

nonisolated private func inkScript(id: String = "ink", revision: String = "r1", _ lines: [ScriptLine]) -> PlayScript {
    PlayScript(id: id, revision: revision, kind: "stage", title: "T", authors: [], source: .init(name: "S", url: "https://example.org"),
               rights: .init(bucket: "script_source_cleared", evidence: []),
               roles: [PlayScript.Role(name: "A", lines: 1, words: 17), PlayScript.Role(name: "B", lines: 1, words: 5)],
               lines: lines, sections: nil)
}

nonisolated private func said(_ id: String, _ role: String = "A", _ text: String) -> ScriptLine {
    ScriptLine(id: id, kind: .speech, role: role, parts: [.say(text)])
}

nonisolated private func stroke(_ points: [CGPoint], at date: Date = Date(timeIntervalSince1970: 1_000)) -> PKStroke {
    let cps = points.enumerated().map { i, p in
        PKStrokePoint(location: p, timeOffset: Double(i) * 0.01, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
    }
    return PKStroke(ink: PKInk(.pen, color: black), path: PKStrokePath(controlPoints: cps, creationDate: date), transform: .identity, mask: nil)
}

nonisolated private func tmpRoot() -> URL {
    URL.temporaryDirectory.appending(path: "ink-test-\(UUID().uuidString)", directoryHint: .isDirectory)
}

struct InkTests {
    private static let sentence = "Yes, the very first thing tomorrow morning, and then we go to the sea and look about us all day long."
    private static let play = inkScript([
        said("L0001", "A", sentence),
        said("L0002", "B", "It is cold out there."),
        said("L0003", "A", "Then we shall wear coats."),
    ])

    private static func layout(_ s: PlayScript, width: CGFloat = 340, height: CGFloat = 600, base: CGFloat = 17) throws -> ReaderLayout {
        try ReaderLayout.build(s, structure: ScriptStructure(s), style: ReaderStyle(base: base, scale: 1, leading: 1.55),
                               pageSize: CGSize(width: width, height: height))
    }

    private static func inkOf(_ s: PlayScript, line: String, _ strokes: [PKStroke], width: CGFloat) -> LineInk {
        let text = ScriptReading.lineText(s.lines.first { $0.id == line }!)
        return LineInk(line: line, hash: InkCore.hash(text), text: InkCore.preview(text), width: Double(width),
                       data: PKDrawing(strokes: strokes).dataRepresentation(), strokes: strokes.count, revision: s.revision, updated: 1)
    }

    // MARK: The words an ink belongs to

    @Test func theHashIsStableAcrossLaunchesAndTellsWordsApart() {
        #expect(InkCore.hash("It is cold out there.") == InkCore.hash("It is cold out there."))
        #expect(InkCore.hash("It is cold out there.") != InkCore.hash("It is cold out here."))
        #expect(InkCore.hash("a") == "89be207b544f1e4", "FNV-1a over UTF-16 units: a stored hash must mean the same tomorrow")
    }

    @Test func aRevisionKeepsInkOnALineWhoseWordsAreTheSame() {
        let ink = Self.inkOf(Self.play, line: "L0002", [stroke([.zero, CGPoint(x: 9, y: 9)])], width: 300)
        let next = inkScript(revision: "r2", [said("L0000", "A", "A new first line."), Self.play.lines[0], Self.play.lines[1], Self.play.lines[2]])
        let r = InkCore.place(next, [ink])
        #expect(r.placed.map(\.line) == ["L0002"] && r.lost.isEmpty)
        #expect(r.placed.first?.revision == "r2" && r.changed, "re-stamped with the new revision, to be saved")
        #expect(InkCore.place(Self.play, [ink]).changed == false, "placing again changes nothing")
    }

    @Test func aRevisionThatChangedTheWordsListsTheInkAsNotPlacedNeverOnOtherWords() {
        let ink = Self.inkOf(Self.play, line: "L0002", [stroke([.zero, CGPoint(x: 9, y: 9)])], width: 300)
        let next = inkScript(revision: "r2", [Self.play.lines[0], said("L0002", "B", "It is bitterly cold out there."), Self.play.lines[2]])
        let r = InkCore.place(next, [ink])
        #expect(r.placed.isEmpty)
        #expect(r.lost.map(\.line) == ["L0002"])
        #expect(r.lost.first?.data == ink.data, "kept as stored")
    }

    @Test func inkMovesToTheIdExactlyItsWordsMovedToAndNotWhenTwoLinesShareThem() {
        let ink = Self.inkOf(Self.play, line: "L0002", [stroke([.zero, CGPoint(x: 9, y: 9)])], width: 300)
        let split = inkScript(revision: "r2", [Self.play.lines[0], said("L0002a", "B", "It is cold out there."), Self.play.lines[2]])
        let moved = InkCore.place(split, [ink])
        #expect(moved.placed.map(\.line) == ["L0002a"] && moved.lost.isEmpty && moved.changed)
        let twice = inkScript(revision: "r2", [Self.play.lines[0], said("L0002a", "B", "It is cold out there."), said("L0002b", "B", "It is cold out there.")])
        let both = InkCore.place(twice, [ink])
        #expect(both.placed.isEmpty && both.lost.count == 1, "two candidates, no guess")
    }

    // MARK: Where a line's block stands

    @Test func everyLineOnAPageHasABlockInReadingOrderInsideThePageView() throws {
        let l = try Self.layout(Self.play)
        let blocks = l.inkBlocks(page: 0)
        #expect(blocks.map(\.line) == Array(l.lines(onPage: 0)))
        #expect(blocks.map(\.rect.minY) == blocks.map(\.rect.minY).sorted())
        for b in blocks {
            #expect(b.rect.minX == ReaderLayout.inset && b.rect.width == l.textSize.width)
            #expect(b.rect.minY >= ReaderLayout.headRoom - 1 && b.rect.maxY <= ReaderLayout.headRoom + l.pageSize.height + 1)
            #expect(b.stack == 0)
        }
    }

    @Test func aSpeechRunningOntoTheNextPageIsOneBlockOfStackedPieces() throws {
        let long = String(repeating: "and so it goes on and on until the page is full and then some more ", count: 30)
        let s = inkScript([said("L0001", "A", long), said("L0002", "B", "Short.")])
        let l = try Self.layout(s, height: 300)
        #expect(l.pageCount > 1 && l.starts[0] < l.ends[0], "the long speech spans pages")
        let first = try #require(l.inkBlocks(page: l.starts[0]).first { $0.line == 0 })
        let next = try #require(l.inkBlocks(page: l.starts[0] + 1).first { $0.line == 0 })
        #expect(first.stack == 0)
        #expect(abs(next.stack - first.rect.height) < 0.5, "the second piece starts where the first ends, in block units")
    }

    @Test func aPointOwnsTheLineItIsInElseTheNearestInTheGap() throws {
        let l = try Self.layout(Self.play)
        let blocks = l.inkBlocks(page: 0)
        let mid = { (b: InkBlock) in CGPoint(x: b.rect.midX, y: b.rect.midY) }
        #expect(ReaderLayout.inkOwner(at: mid(blocks[1]), in: blocks)?.line == 1)
        #expect(ReaderLayout.inkOwner(at: CGPoint(x: -20, y: blocks[2].rect.midY), in: blocks)?.line == 2, "a margin note belongs to its line")
        #expect(ReaderLayout.inkOwner(at: CGPoint(x: 100, y: 0), in: blocks)?.line == 0, "above the text, the first line")
    }

    // MARK: Moving, scaling, reflow

    @Test func inkIsStoredInBlockUnitsAndFollowsItsLineThroughANewColumnWidth() throws {
        let s = Self.play
        let a = try Self.layout(s, width: 340)
        let b = try Self.layout(s, width: 440)
        let blockA = try #require(a.inkBlocks(page: 0).first { $0.line == 1 })
        // The Pencil draws in line two's block (page A), 40 points in from the column's left and 5 down.
        let drawn = stroke([CGPoint(x: blockA.rect.minX + 40, y: blockA.rect.minY + 5), CGPoint(x: blockA.rect.minX + 100, y: blockA.rect.minY + 25)])
        let r = InkCompose.commit(canvas: PKDrawing(strokes: [drawn]), previous: ([], []), blocks: a.inkBlocks(page: 0), script: s,
                                  textWidth: a.textSize.width, inks: [:], now: 5)
        let ink = try #require(r.inks["L0002"], "the stroke belongs to the line it starts in")
        #expect(r.changed == ["L0002"] && r.owners == ["L0002"] && !r.needsReset)
        #expect(ink.width == Double(a.textSize.width) && ink.strokes == 1)
        let stored = try PKDrawing(data: ink.data)
        #expect(abs(stored.bounds.minX - 40) < 3 && abs(stored.bounds.minY - 5) < 3, "relative to the block's top-left, \(stored.bounds)")

        let wide = InkCompose.page(inks: ["L0002": ink], blocks: b.inkBlocks(page: 0), ids: s.lines.map(\.id), textWidth: b.textSize.width)
        let blockB = try #require(b.inkBlocks(page: 0).first { $0.line == 1 })
        let k = b.textSize.width / a.textSize.width
        #expect(k > 1.2)
        let got = wide.drawing.bounds
        #expect(abs((got.minX - blockB.rect.minX) - 40 * k) < 4, "scaled with the column: \(got.minX - blockB.rect.minX) vs \(40 * k)")
        #expect(abs((got.minY - blockB.rect.minY) - 5 * k) < 4, "and down the line it was drawn on")
        #expect(abs(got.width - stored.bounds.width * k) < 4)
        #expect(wide.owners == ["L0002"])
        // Back at the first width the ink is where it was drawn.
        let same = InkCompose.page(inks: ["L0002": ink], blocks: a.inkBlocks(page: 0), ids: s.lines.map(\.id), textWidth: a.textSize.width)
        #expect(abs(same.drawing.bounds.minX - drawn.renderBounds.minX) < 3 && abs(same.drawing.bounds.minY - drawn.renderBounds.minY) < 3)
    }

    @Test func inkMovesWhenTheLinesAboveItGrowAtALargerTextSize() throws {
        let s = Self.play
        let small = try Self.layout(s, base: 17)
        let big = try Self.layout(s, base: 26)
        let blockS = try #require(small.inkBlocks(page: 0).first { $0.line == 2 })
        let blockL = try #require(big.inkBlocks(page: 0).first { $0.line == 2 })
        #expect(blockL.rect.minY > blockS.rect.minY + 10, "line three sits lower at the larger size")
        let drawn = stroke([CGPoint(x: blockS.rect.minX + 10, y: blockS.rect.minY + 4), CGPoint(x: blockS.rect.minX + 50, y: blockS.rect.minY + 14)])
        let ink = try #require(InkCompose.commit(canvas: PKDrawing(strokes: [drawn]), previous: ([], []), blocks: small.inkBlocks(page: 0),
                                                 script: s, textWidth: small.textSize.width, inks: [:], now: 1).inks["L0003"])
        let page = InkCompose.page(inks: ["L0003": ink], blocks: big.inkBlocks(page: 0), ids: s.lines.map(\.id), textWidth: big.textSize.width)
        #expect(page.drawing.bounds.minY > blockL.rect.minY - 1 && page.drawing.bounds.minY < blockL.rect.maxY, "still on line three's block")
    }

    @Test func inkDrawnOnASpeechsSecondPageStaysWithItsWordsAndIsOffTheFirstPage() throws {
        let long = String(repeating: "and so it goes on and on until the page is full and then some more ", count: 30)
        let s = inkScript([said("L0001", "A", long), said("L0002", "B", "Short.")])
        let l = try Self.layout(s, height: 300)
        let p1 = l.starts[0] + 1
        let blocks = l.inkBlocks(page: p1)
        let b = try #require(blocks.first { $0.line == 0 })
        let drawn = stroke([CGPoint(x: b.rect.minX + 20, y: b.rect.minY + 3), CGPoint(x: b.rect.minX + 60, y: b.rect.minY + 12)])
        let r = InkCompose.commit(canvas: PKDrawing(strokes: [drawn]), previous: ([], []), blocks: blocks, script: s,
                                  textWidth: l.textSize.width, inks: [:], now: 1)
        let ink = try #require(r.inks["L0001"])
        let stored = try PKDrawing(data: ink.data)
        #expect(stored.bounds.minY > b.stack - 4, "in block units: below the first page's piece (\(stored.bounds.minY) vs \(b.stack))")
        let again = InkCompose.page(inks: ["L0001": ink], blocks: blocks, ids: s.lines.map(\.id), textWidth: l.textSize.width)
        #expect(abs(again.drawing.bounds.minY - drawn.renderBounds.minY) < 3, "back where it was drawn")
        let onFirst = InkCompose.page(inks: ["L0001": ink], blocks: l.inkBlocks(page: l.starts[0]), ids: s.lines.map(\.id), textWidth: l.textSize.width)
        let firstPage = l.inkBlocks(page: l.starts[0]).first { $0.line == 0 }!
        #expect(onFirst.drawing.bounds.minY > firstPage.rect.maxY - 2, "it sits below the first piece, off that page's text")
    }

    @Test func eraseAStrokeAndItsLineLosesIt() throws {
        let s = Self.play
        let l = try Self.layout(s)
        let blocks = l.inkBlocks(page: 0)
        let b = blocks[0]
        let one = stroke([CGPoint(x: b.rect.minX + 5, y: b.rect.minY + 2), CGPoint(x: b.rect.minX + 30, y: b.rect.minY + 8)], at: Date(timeIntervalSince1970: 1))
        let two = stroke([CGPoint(x: b.rect.minX + 60, y: b.rect.minY + 2), CGPoint(x: b.rect.minX + 90, y: b.rect.minY + 8)], at: Date(timeIntervalSince1970: 2))
        let first = InkCompose.commit(canvas: PKDrawing(strokes: [one, two]), previous: ([], []), blocks: blocks, script: s,
                                      textWidth: l.textSize.width, inks: [:], now: 1)
        #expect(first.inks["L0001"]?.strokes == 2)
        let held = PKDrawing(strokes: [one, two]).strokes
        let erased = InkCompose.commit(canvas: PKDrawing(strokes: [two]), previous: (held, first.owners), blocks: blocks, script: s,
                                       textWidth: l.textSize.width, inks: first.inks, now: 2)
        #expect(erased.inks["L0001"]?.strokes == 1 && erased.owners == ["L0001"])
        let none = InkCompose.commit(canvas: PKDrawing(), previous: (PKDrawing(strokes: [two]).strokes, erased.owners), blocks: blocks, script: s,
                                     textWidth: l.textSize.width, inks: erased.inks, now: 3)
        #expect(none.inks["L0001"] == nil, "no strokes, no ink")
    }

    @Test func aNewStrokeLeavesAnotherLinesInkAlone() throws {
        let s = Self.play
        let l = try Self.layout(s)
        let blocks = l.inkBlocks(page: 0)
        let a = stroke([CGPoint(x: blocks[0].rect.minX + 5, y: blocks[0].rect.minY + 2), CGPoint(x: blocks[0].rect.minX + 30, y: blocks[0].rect.minY + 8)], at: Date(timeIntervalSince1970: 1))
        let r1 = InkCompose.commit(canvas: PKDrawing(strokes: [a]), previous: ([], []), blocks: blocks, script: s, textWidth: l.textSize.width, inks: [:], now: 1)
        let held = PKDrawing(strokes: [a]).strokes
        let b = stroke([CGPoint(x: blocks[2].rect.minX + 5, y: blocks[2].rect.minY + 2), CGPoint(x: blocks[2].rect.minX + 30, y: blocks[2].rect.minY + 8)], at: Date(timeIntervalSince1970: 2))
        let r2 = InkCompose.commit(canvas: PKDrawing(strokes: [a, b]), previous: (held, r1.owners), blocks: blocks, script: s, textWidth: l.textSize.width, inks: r1.inks, now: 2)
        #expect(r2.changed == ["L0003"] && r2.owners == ["L0001", "L0003"])
        #expect(r2.inks["L0001"] == r1.inks["L0001"], "the other line's stored ink is untouched, byte for byte")
    }

    // MARK: On the device

    @Test func storageOnePerScriptUnreadableReadsAsNoneAnEmptySetRemovesTheFile() throws {
        let root = tmpRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InkStore(root: root)
        let ink = Self.inkOf(Self.play, line: "L0002", [stroke([.zero, CGPoint(x: 9, y: 9)])], width: 300)
        try store.save(scriptID: "s/1", title: "T", [ink])
        #expect(store.load("s/1") == [ink])
        #expect(store.url("s/1").pathExtension == "ink" && store.url("s/1").deletingLastPathComponent() == root)
        #expect(store.load("other").isEmpty)
        try Data("not json".utf8).write(to: store.url("bad"))
        #expect(store.load("bad").isEmpty, "unreadable reads as none")
        try store.save(scriptID: "s/1", title: "T", [])
        #expect(!FileManager.default.fileExists(atPath: store.url("s/1").path))
    }

    @Test func storageAFailedWriteIsReportedNeverSwallowed() throws {
        let blocker = tmpRoot()
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let ink = Self.inkOf(Self.play, line: "L0002", [stroke([.zero, CGPoint(x: 9, y: 9)])], width: 300)
        #expect(throws: (any Error).self) { try InkStore(root: blocker).save(scriptID: "s", title: nil, [ink]) }
    }

    @Test func inkFilesAreNotMarksAndMarksAreNotInk() throws {
        let root = tmpRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ink = Self.inkOf(Self.play, line: "L0002", [stroke([.zero, CGPoint(x: 9, y: 9)])], width: 300)
        try InkStore(root: root).save(scriptID: "s", title: "T", [ink])
        let mark = try #require(MarksCore.fromSelection(Self.play, [MarkPiece(line: "L0001", start: 0, end: 3)], .highlight).first)
        try MarkStore(root: root).save(scriptID: "s", title: "T", [mark])
        #expect(MarkStore(root: root).load("s") == [mark])
        #expect(MarkStore(root: root).exportRows().count == 1)
        #expect(InkStore(root: root).exportRows().count == 1)
    }

    @Test func theExportCarriesTheStrokeCountAndTheDrawingNeverTheThumbnail() throws {
        let root = tmpRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ink = Self.inkOf(Self.play, line: "L0002", [stroke([.zero, CGPoint(x: 9, y: 9)]), stroke([CGPoint(x: 3, y: 3), CGPoint(x: 5, y: 9)], at: Date(timeIntervalSince1970: 2))], width: 300)
        try InkStore(root: root).save(scriptID: "b", title: "B", [ink])
        try InkStore(root: root).save(scriptID: "a", title: "A", [ink])
        let rows = InkStore(root: root).exportRows()
        #expect(rows.map(\.script) == ["a", "b"])
        let row = try #require(rows.first)
        #expect(row.strokes == 2 && row.width == 300 && row.line == "L0002")
        #expect(Data(base64Encoded: row.drawing) == ink.data, "the drawing is the PKDrawing's own data")
        _ = try PKDrawing(data: try #require(Data(base64Encoded: row.drawing)))
        let export = DataExport(exportedAt: Date(timeIntervalSince1970: 0), history: [], following: [], queue: [], takes: [], ink: rows)
        let json = try #require(try JSONSerialization.jsonObject(with: export.json()) as? [String: Any])
        let list = try #require(json["ink"] as? [[String: Any]])
        #expect(list.count == 2 && (list[0]["strokes"] as? Int) == 2 && (list[0]["drawing"] as? String) == row.drawing)
        #expect(Set(list[0].keys) == ["script", "title", "revision", "line", "strokes", "width", "updated", "drawing"])
    }
}
