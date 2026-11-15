import CoreGraphics
import CoreText
import Foundation
#if canImport(PencilKit)
import PencilKit
#endif

// Pencil ink in the script reader (PLAYS-DESIGN §2.10 rule 1, iOS-DESIGN §4.15 "Marks"; Decision 076 S5). Ink is
// anchored to a script line, never a page: a line's strokes are stored in the line block's own coordinates (the
// origin the block's top-left corner, units of points at the text column's width when the ink was drawn), so the
// ink moves with its line through a reflow, a new text size and a page turn, and scales with the column. A line
// that continues on the next page is one block of stacked pieces, so ink on either part stays with its words.
// A revision keeps a line's ink only while the line's text is the same (it may move to the id exactly its text
// moved to); otherwise the ink is kept, untouched, and listed as not placed, never drawn over other words.

/// One line's ink as stored: a `PKDrawing` (its data) in the line block's coordinates.
nonisolated struct LineInk: Codable, Equatable, Sendable, Identifiable {
    var line: String
    /// `InkCore.hash` of the line's printed words when the ink was drawn.
    var hash: String
    /// The first words of the line, for the notebook only.
    var text: String
    /// The text column's width, in points, that the strokes' units are measured in.
    var width: Double
    var data: Data
    var strokes: Int
    var revision: String?
    /// Epoch milliseconds.
    var updated: Int64

    var id: String { "\(line)#\(hash)" }
}

nonisolated enum InkCore {
    static let previewLength = 60

    /// FNV-1a over the line's UTF-16 units: the same on every launch (Swift's `Hasher` is seeded per process).
    static func hash(_ text: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for u in text.utf16 {
            h = (h ^ UInt64(u & 0xFF)) &* 0x0000_0100_0000_01B3
            h = (h ^ UInt64(u >> 8)) &* 0x0000_0100_0000_01B3
        }
        return String(h, radix: 16)
    }

    static func lineText(_ line: ScriptLine) -> String { ScriptReading.lineText(line) }

    static func preview(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(previewLength))
    }

    /// The ink a revision keeps: a line with the same id and the same words keeps its own; ink whose words now stand
    /// under exactly one other id (a split or renumbered line, not already inked) moves there; the rest is lost.
    static func place(_ script: PlayScript, _ inks: [LineInk]) -> (placed: [LineInk], lost: [LineInk], changed: Bool) {
        var hashes: [String: String] = [:]
        var byHash: [String: [String]] = [:]
        for l in script.lines {
            let text = lineText(l)
            let h = hash(text)
            hashes[l.id] = h
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { byHash[h, default: []].append(l.id) }
        }
        let rev = MarksCore.rev(script)
        var changed = false
        var placed: [LineInk] = []
        var claimed = Set<String>()
        var rest: [LineInk] = []
        for ink in inks {
            if hashes[ink.line] == ink.hash, !claimed.contains(ink.line) {
                claimed.insert(ink.line)
                var k = ink
                if k.revision != rev { k.revision = rev; changed = true }
                placed.append(k)
            } else {
                rest.append(ink)
            }
        }
        var lost: [LineInk] = []
        for ink in rest {
            let free = (byHash[ink.hash] ?? []).filter { !claimed.contains($0) }
            if free.count == 1, let id = free.first {
                claimed.insert(id)
                var k = ink
                k.line = id
                k.revision = rev
                placed.append(k)
                changed = true
            } else {
                lost.append(ink)
            }
        }
        return (placed, lost, changed)
    }

    /// The units-to-points factor of a block now: the column's width over the width the ink was drawn at.
    static func factor(width now: CGFloat, drawnAt ref: Double) -> CGFloat {
        ref > 0 && now > 0 ? now / CGFloat(ref) : 1
    }
}

// MARK: - Where a line's block stands on a page

/// A line's piece on one page, in the page view's coordinates (top-left origin): the text column's full width and
/// the height of the line's frame lines. `stack` is the height of the line's pieces on earlier pages.
nonisolated struct InkBlock: Equatable, Sendable {
    let line: Int
    let rect: CGRect
    let stack: CGFloat

    /// Block units to the page view, for ink drawn at `ref` points of column width and a column of `textWidth` now.
    func transform(textWidth: CGFloat, drawnAt ref: Double) -> CGAffineTransform {
        let s = InkCore.factor(width: textWidth, drawnAt: ref)
        return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: rect.minX, ty: rect.minY - stack)
    }
}

nonisolated extension ReaderLayout {
    private func pieces(page: Int) -> [(line: Int, rect: CGRect)] {
        guard pages.indices.contains(page) else { return [] }
        let (lines, origins) = frameLines(page)
        var out: [(line: Int, rect: CGRect)] = []
        var cur: (line: Int, lo: CGFloat, hi: CGFloat)?
        func flush() {
            guard let c = cur else { return }
            out.append((c.line, viewRect(CGRect(x: 0, y: c.lo, width: textSize.width, height: c.hi - c.lo))))
            cur = nil
        }
        for (i, line) in lines.enumerated() {
            let li = lineIndex(at: CTLineGetStringRange(line).location)
            let m = metrics(line)
            let band = ReaderLayout.band(origin: origins[i], asc: m.asc, desc: m.desc, style: style)
            if var c = cur, c.line == li {
                c.lo = min(c.lo, band.minY)
                c.hi = max(c.hi, band.maxY)
                cur = c
            } else {
                flush()
                cur = (li, band.minY, band.maxY)
            }
        }
        flush()
        return out
    }

    /// Every line with a piece on `page`, in reading order.
    func inkBlocks(page: Int) -> [InkBlock] {
        pieces(page: page).map { p in
            var stack: CGFloat = 0
            if p.line < starts.count, starts[p.line] < page {
                for q in starts[p.line]..<page {
                    stack += pieces(page: q).first(where: { $0.line == p.line })?.rect.height ?? 0
                }
            }
            return InkBlock(line: p.line, rect: p.rect, stack: stack)
        }
    }

    /// The block a point of the page view belongs to: the one it is in, else the nearest above or below (a stroke
    /// that starts in the margin or the gap between lines belongs to the closest line).
    static func inkOwner(at point: CGPoint, in blocks: [InkBlock]) -> InkBlock? {
        var best: (b: InkBlock, d: CGFloat)?
        for b in blocks {
            let d = point.y < b.rect.minY ? b.rect.minY - point.y : (point.y > b.rect.maxY ? point.y - b.rect.maxY : 0)
            if best == nil || d < best!.d { best = (b, d) }
        }
        return best?.b
    }
}

// MARK: - Composing a page's ink and taking an edit back to its lines

#if canImport(PencilKit)
nonisolated struct InkPage {
    var drawing: PKDrawing
    /// The line id each stroke of `drawing` belongs to.
    var owners: [String]
}

nonisolated extension PKStroke {
    func moved(by t: CGAffineTransform) -> PKStroke {
        var s = self
        s.transform = s.transform.concatenating(t)
        return s
    }
}

nonisolated enum InkCompose {
    /// The page's ink as one drawing in the page view's coordinates: every line's strokes through its block's
    /// transform. `show` says whether a line's ink is drawn (Hide My Lines hides a hidden line's).
    static func page(inks: [String: LineInk], blocks: [InkBlock], ids: [String], textWidth: CGFloat,
                     show: (Int) -> Bool = { _ in true }) -> InkPage {
        var strokes: [PKStroke] = []
        var owners: [String] = []
        for b in blocks where b.line < ids.count && show(b.line) {
            let id = ids[b.line]
            guard let ink = inks[id], let stored = try? PKDrawing(data: ink.data) else { continue }
            let t = b.transform(textWidth: textWidth, drawnAt: ink.width)
            let moved = stored.strokes.map { $0.moved(by: t) }
            strokes += moved
            owners += Array(repeating: id, count: moved.count)
        }
        return InkPage(drawing: PKDrawing(strokes: strokes), owners: owners)
    }

    private static func same(_ a: PKStroke, _ b: PKStroke) -> Bool {
        let x = a.renderBounds, y = b.renderBounds
        return a.path.creationDate == b.path.creationDate
            && abs(x.minX - y.minX) < 0.5 && abs(x.minY - y.minY) < 0.5 && abs(x.width - y.width) < 0.5 && abs(x.height - y.height) < 0.5
    }

    struct Result {
        var inks: [String: LineInk]
        /// Owners for the canvas's strokes as they now stand, parallel to its strokes.
        var owners: [String]
        var changed: Set<String>
        /// A stroke had no line to belong to (a page with no text): the canvas should be put back.
        var needsReset: Bool
    }

    /// An edit on the page's canvas, taken back to the lines: a stroke added belongs to the line its first point is
    /// nearest; a stroke erased leaves its line. Only the lines that changed are rewritten (their strokes brought
    /// back through the inverse of the block's transform).
    static func commit(canvas: PKDrawing, previous: (strokes: [PKStroke], owners: [String]), blocks: [InkBlock],
                       script: PlayScript, textWidth: CGFloat, inks: [String: LineInk], now: Int64) -> Result {
        let new = canvas.strokes
        var owners: [String] = []
        var changed = Set<String>()
        var needsReset = false
        var i = 0
        var matched = Set<Int>()
        for stroke in new {
            var found: Int?
            var j = i
            while j < previous.strokes.count {
                if same(previous.strokes[j], stroke) { found = j; break }
                j += 1
            }
            if let j = found {
                matched.insert(j)
                owners.append(previous.owners[j])
                i = j + 1
            } else if let first = stroke.path.first?.location.applying(stroke.transform),
                      let b = ReaderLayout.inkOwner(at: first, in: blocks), b.line < script.lines.count {
                let id = script.lines[b.line].id
                owners.append(id)
                changed.insert(id)
            } else {
                owners.append("")
                needsReset = true
            }
        }
        for (k, o) in previous.owners.enumerated() where !matched.contains(k) { changed.insert(o) }
        var out = inks
        var byID: [String: InkBlock] = [:]
        for b in blocks where b.line < script.lines.count { byID[script.lines[b.line].id] = byID[script.lines[b.line].id] ?? b }
        for id in changed {
            guard let b = byID[id] else { continue }
            let ref = inks[id]?.width ?? Double(textWidth)
            let back = b.transform(textWidth: textWidth, drawnAt: ref).inverted()
            let mine = new.enumerated().filter { owners[$0.offset] == id }.map { $0.element.moved(by: back) }
            if mine.isEmpty { out[id] = nil; continue }
            let text = script.lines.first(where: { $0.id == id }).map(InkCore.lineText) ?? ""
            out[id] = LineInk(line: id, hash: InkCore.hash(text), text: InkCore.preview(text), width: ref,
                              data: PKDrawing(strokes: mine).dataRepresentation(), strokes: mine.count,
                              revision: MarksCore.rev(script), updated: now)
        }
        return Result(inks: out, owners: owners, changed: changed, needsReset: needsReset)
    }
}
#endif

// MARK: - On the device

/// A play's ink, one file per script beside its marks (`Marks/<script id>.ink`: `{format, script, title, ink: [...]}`,
/// each line's `PKDrawing` as base64 data). Private to the device, like the marks.
nonisolated struct InkStore: Sendable {
    let root: URL

    init(root: URL? = nil) { self.root = root ?? MarkStore().root }

    struct File: Codable {
        var format: Int
        var script: String
        var title: String?
        var ink: [LineInk]
    }

    func url(_ scriptID: String) -> URL {
        MarkStore(root: root).url(scriptID).deletingPathExtension().appendingPathExtension("ink")
    }

    static func valid(_ i: LineInk) -> Bool { !i.line.isEmpty && !i.data.isEmpty && i.strokes > 0 }

    func load(_ scriptID: String) -> [LineInk] {
        guard let data = try? Data(contentsOf: url(scriptID)), let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.ink.filter(Self.valid)
    }

    func save(scriptID: String, title: String?, _ ink: [LineInk]) throws {
        let fm = FileManager.default
        if ink.isEmpty {
            if fm.fileExists(atPath: url(scriptID).path) { try fm.removeItem(at: url(scriptID)) }
            return
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(File(format: 1, script: scriptID, title: title, ink: ink)).write(to: url(scriptID), options: .atomic)
    }

    /// Every play's ink on this device, one row a line, for the person's own export (docs/EXPORT.md `ink[]`).
    func exportRows() -> [DataExport.InkRow] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasSuffix(".ink") }.sorted()
        var rows: [DataExport.InkRow] = []
        for name in names {
            guard let data = try? Data(contentsOf: root.appending(path: name)), let file = try? JSONDecoder().decode(File.self, from: data) else { continue }
            for i in file.ink.filter(Self.valid) {
                rows.append(DataExport.InkRow(script: file.script, title: file.title, revision: i.revision, line: i.line, strokes: i.strokes,
                                              width: i.width, updated: Date(timeIntervalSince1970: Double(i.updated) / 1000),
                                              drawing: i.data.base64EncodedString()))
            }
        }
        return rows.sorted { ($0.script, $0.line) < ($1.script, $1.line) }
    }
}
