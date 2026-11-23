import CoreGraphics
import CoreText
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Where a mark stands on the Core Text page, both ways (PLAYS-DESIGN §2.10 rule 4, R2-marks-port-brief §2): every
// drawn run keeps its UTF-16 offset into `ScriptReading.lineText` (`ed.offset`), so a mark's (line, start, end)
// maps to a range of the page string, and a selection of the page string maps back to (line, start, end) pieces.
// Drawing never changes the text: a span mark is a fill or a rule over the run boxes; a point mark stands in a
// gap the page makes with a kern on its word's last character (so a point mark re-paginates, a span mark does not).

nonisolated enum MarkGeometry {
    /// One drawn run of a line's printed words: where it begins in the line's text (`at`) and in the page string.
    struct Run: Equatable {
        let at: Int
        let loc: Int
        let len: Int
    }

    /// The runs of `range` (one script line) that carry the line's own words; a speaker's printed name, a heading's
    /// absent text and every glyph the page adds (offset -1) are not words.
    static func runs(_ s: NSAttributedString, in range: NSRange) -> [Run] {
        var out: [Run] = []
        guard range.length > 0 else { return out }
        s.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            guard let at = attrs[.edOffset] as? Int, at >= 0, attrs[.edName] == nil else { return }
            let base = (attrs[.edBase] as? Int) ?? r.location
            out.append(Run(at: at + (r.location - base), loc: r.location, len: r.length))
        }
        return out
    }

    /// The page-string location of the first character at or after line offset `off`.
    static func start(_ runs: [Run], _ off: Int) -> Int? {
        for r in runs where off < r.at + r.len { return r.loc + max(0, off - r.at) }
        return nil
    }

    /// The page-string location just after the last character before line offset `off`.
    static func end(_ runs: [Run], _ off: Int) -> Int? {
        for r in runs.reversed() where off > r.at { return r.loc + min(r.len, off - r.at) }
        return nil
    }

    /// The location of the character a point mark at `offset` follows (nil at the head of a line).
    static func charBefore(_ s: NSAttributedString, range: NSRange, offset: Int) -> Int? {
        guard offset > 0, let e = end(runs(s, in: range), offset), e > range.location else { return nil }
        return e - 1
    }

    // MARK: Point marks

    static func labelFont(_ size: CGFloat) -> ReaderFont { ReaderFonts.sans(size * 0.6, weight: .semibold) }
    static func labelKern(_ size: CGFloat) -> CGFloat { size * 0.05 }

    static func labelWidth(_ label: String, size: CGFloat) -> CGFloat {
        let up = label.uppercased()
        return (up as NSString).size(withAttributes: [.font: labelFont(size)]).width + CGFloat(up.utf16.count) * labelKern(size)
    }

    /// The room a point mark takes after its word.
    static func pointWidth(_ m: Mark, size: CGFloat) -> CGFloat {
        let label = m.label ?? ""
        switch m.kind {
        case .breath: return size * 0.6
        case .pause: return size * 0.95
        case .beat: return size * 0.95 + (label.isEmpty ? 0 : labelWidth(label, size: size) + size * 0.7)
        default: return 0
        }
    }
}

/// A run of one mark or selection on one frame line, in the text's coordinates (y up from the text foot).
nonisolated struct MarkSpan {
    var x0: CGFloat
    var x1: CGFloat
    var origin: CGPoint
    var asc: CGFloat
    var desc: CGFloat

    var rect: CGRect { CGRect(x: origin.x + x0 - 2, y: origin.y - desc * 0.6, width: x1 - x0 + 4, height: (asc + desc) * 0.85) }
}

nonisolated extension ReaderLayout {
    func frameLines(_ page: Int) -> (lines: [CTLine], origins: [CGPoint]) {
        let frame = self.frame(page)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        return (lines, origins)
    }

    func metrics(_ line: CTLine) -> (asc: CGFloat, desc: CGFloat) {
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &asc, &desc, &lead)
        return (asc, desc)
    }

    /// The page showing string location `loc`.
    func page(containing loc: Int) -> Int {
        var lo = 0, hi = pages.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if pages[mid].location <= loc { lo = mid } else { hi = mid - 1 }
        }
        return max(0, lo)
    }

    // MARK: Marks to the page

    /// The page-string range of a span mark, or nil when its line has no such words.
    func range(of m: Mark, index: [String: Int]) -> NSRange? {
        guard m.isSpan, let li = index[m.line], li < lineRanges.count else { return nil }
        let runs = MarkGeometry.runs(string, in: lineRanges[li])
        guard let s = MarkGeometry.start(runs, m.start), let e = MarkGeometry.end(runs, m.end), e > s else { return nil }
        return NSRange(location: s, length: e - s)
    }

    /// The pieces of the frame lines a page-string range covers on `page`.
    func spans(of range: NSRange, page: Int) -> [MarkSpan] {
        let (lines, origins) = frameLines(page)
        var out: [MarkSpan] = []
        for (i, line) in lines.enumerated() {
            let lr = CTLineGetStringRange(line)
            let lo = max(lr.location, range.location), hi = min(lr.location + lr.length, range.location + range.length)
            guard lo < hi else { continue }
            let x0 = CTLineGetOffsetForStringIndex(line, lo, nil), x1 = CTLineGetOffsetForStringIndex(line, hi, nil)
            let m = metrics(line)
            out.append(MarkSpan(x0: x0, x1: x1, origin: origins[i], asc: m.asc, desc: m.desc))
        }
        return out
    }

    /// Where a mark stands on `page`: a span's pieces, or a point mark's gap (one piece).
    func spans(of m: Mark, page: Int, index: [String: Int]) -> [MarkSpan] {
        if m.isSpan {
            guard let r = range(of: m, index: index) else { return [] }
            return spans(of: r, page: page)
        }
        guard let li = index[m.line], li < lineRanges.count, let gap = gapRange(of: m, line: li) else { return [] }
        let (lines, origins) = frameLines(page)
        for (i, line) in lines.enumerated() {
            let lr = CTLineGetStringRange(line)
            guard gap.location >= lr.location, gap.location < lr.location + lr.length else { continue }
            let x0 = CTLineGetOffsetForStringIndex(line, gap.location, nil)
            let x1 = CTLineGetOffsetForStringIndex(line, min(gap.location + gap.length, lr.location + lr.length), nil)
            let mt = metrics(line)
            return [MarkSpan(x0: x0, x1: max(x1, x0 + 1), origin: origins[i], asc: mt.asc, desc: mt.desc)]
        }
        return []
    }

    /// The figure spaces the page made for a point mark.
    func gapRange(of m: Mark, line li: Int) -> NSRange? {
        var found: NSRange?
        string.enumerateAttribute(.edGap, in: lineRanges[li], options: []) { v, r, stop in
            if (v as? String) == m.id { found = r; stop.pointee = true }
        }
        return found
    }

    /// The marks whose lines show on `page`, with their pieces there.
    func placed(_ marks: [Mark], page: Int, index: [String: Int]) -> [(mark: Mark, spans: [MarkSpan])] {
        let shown = lines(onPage: page)
        return marks.compactMap { m in
            guard let li = index[m.line], shown.contains(li) else { return nil }
            let s = spans(of: m, page: page, index: index)
            return s.isEmpty ? nil : (m, s)
        }
    }

    /// The mark under a point of a page's text (y up), the point marks first, then the narrowest span, a note before an equal width.
    func mark(at up: CGPoint, page: Int, in marks: [Mark], index: [String: Int]) -> Mark? {
        var hits: [(m: Mark, width: CGFloat)] = []
        for (m, spans) in placed(marks, page: page, index: index) {
            let reach: CGFloat = m.isSpan ? 0 : 6
            for s in spans where s.rect.insetBy(dx: -reach, dy: -2).contains(up) {
                hits.append((m, m.isSpan ? Double(m.end - m.start) : -1))
                break
            }
        }
        return hits.sorted { a, b in
            if a.width != b.width { return a.width < b.width }
            return a.m.kind == .note && b.m.kind != .note
        }.first?.m
    }

    // MARK: Selecting

    /// The character boundary nearest a point of `page` (y up); `strict` wants the point inside a line's band.
    func stringIndex(at up: CGPoint, page: Int, strict: Bool = false) -> Int? {
        let (lines, origins) = frameLines(page)
        var best: (i: Int, dy: CGFloat)?
        for (i, line) in lines.enumerated() {
            let m = metrics(line)
            let band = ReaderLayout.band(origin: origins[i], asc: m.asc, desc: m.desc, style: style)
            let dy = up.y < band.minY ? band.minY - up.y : (up.y > band.maxY ? up.y - band.maxY : 0)
            if best == nil || dy < best!.dy { best = (i, dy) }
        }
        guard let best, !strict || best.dy == 0 else { return nil }
        let line = lines[best.i], lr = CTLineGetStringRange(line)
        let at = CTLineGetStringIndexForPosition(line, CGPoint(x: up.x - origins[best.i].x, y: 0))
        return min(max(at == kCFNotFound ? lr.location : at, lr.location), lr.location + lr.length)
    }

    private func isMarkable(_ loc: Int) -> Bool {
        guard loc >= 0, loc < string.length else { return false }
        let a = string.attributes(at: loc, effectiveRange: nil)
        return ((a[.edOffset] as? Int) ?? -1) >= 0 && a[.edName] == nil
    }

    /// The word under a character boundary of the page string (the character after it, else the one before), or nil.
    func wordRange(at index: Int) -> NSRange? {
        let ns = string.string as NSString
        var c = index
        func word(_ k: Int) -> Bool { k >= 0 && k < ns.length && MarksCore.isWord(ns.character(at: k)) && isMarkable(k) }
        if !word(c) { c = index - 1 }
        guard word(c) else { return nil }
        var s = c, e = c + 1
        while word(s - 1) { s -= 1 }
        while word(e) { e += 1 }
        return NSRange(location: s, length: e - s)
    }

    /// The selection as marks see it: one piece a line, in reading order, in raw offsets into each line's words.
    func pieces(for range: NSRange, ids: [String]) -> [MarkPiece] {
        guard range.length > 0, !lineRanges.isEmpty else { return [] }
        let first = lineIndex(at: range.location), last = lineIndex(at: range.location + range.length - 1)
        var out: [MarkPiece] = []
        for li in first...last where li < ids.count {
            var lo = Int.max, hi = Int.min
            for r in MarkGeometry.runs(string, in: lineRanges[li]) {
                let a = max(range.location, r.loc), b = min(range.location + range.length, r.loc + r.len)
                guard a < b else { continue }
                lo = min(lo, r.at + (a - r.loc))
                hi = max(hi, r.at + (b - r.loc))
            }
            if lo < hi { out.append(MarkPiece(line: ids[li], start: lo, end: hi)) }
        }
        return out
    }

    // MARK: Drawing (inside `draw`'s context: the text's coordinates, y up)

    func drawMarkFills(page: Int, in cg: CGContext, theme: Theme, marks: Marks) {
        guard !marks.marks.isEmpty || marks.selection != nil else { return }
        for (m, spans) in placed(marks.marks, page: page, index: marks.lineIndex) where m.kind == .highlight {
            let c = theme.markHues[m.hue ?? "yellow"] ?? theme.markHues["yellow"] ?? theme.block
            cg.setFillColor(c)
            for s in spans {
                cg.addPath(CGPath(roundedRect: s.rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
                cg.fillPath()
            }
        }
        if let sel = marks.selection, sel.length > 0, let c = theme.selection {
            cg.setFillColor(c)
            for s in spans(of: sel, page: page) {
                cg.addPath(CGPath(roundedRect: s.rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
                cg.fillPath()
            }
        }
    }

    // MARK: The word heard (PLAYS-DESIGN §2.11 rule 2)

    /// The page-string range of a word of line `li` (offsets into its `lineText`), or nil when it draws nothing.
    func range(ofWord w: ReadAlong.Word, line li: Int) -> NSRange? {
        guard li >= 0, li < lineRanges.count, w.end > w.start else { return nil }
        let runs = MarkGeometry.runs(string, in: lineRanges[li])
        guard let s = MarkGeometry.start(runs, w.start), let e = MarkGeometry.end(runs, w.end), e > s else { return nil }
        return NSRange(location: s, length: e - s)
    }

    /// The page a word of line `li` is drawn on.
    func page(ofWord w: ReadAlong.Word, line li: Int) -> Int? {
        range(ofWord: w, line: li).map { page(containing: $0.location) }
    }

    /// The word heard: a fill in the speaker's hue with a rule under it (ink for a direction or a cue).
    func drawWord(page: Int, in cg: CGContext, theme: Theme, marks: Marks, hue: (Int) -> CGColor) {
        guard let li = marks.along, let w = marks.alongWord, let r = range(ofWord: w, line: li) else { return }
        let h = li < hueOfLine.count ? hueOfLine[li] : -1
        let c = h >= 0 ? hue(h) : theme.ink
        for s in spans(of: r, page: page) {
            cg.setFillColor(c.copy(alpha: 0.26) ?? c)
            cg.addPath(CGPath(roundedRect: s.rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
            cg.fillPath()
            cg.setFillColor(c)
            cg.fill(CGRect(x: s.origin.x + s.x0 - 1, y: s.origin.y - s.desc * 0.6, width: s.x1 - s.x0 + 2, height: 2))
        }
    }

    private func drawText(_ text: String, font: ReaderFont, color: CGColor, kern: CGFloat = 0, at p: CGPoint, in cg: CGContext) {
        let a = NSAttributedString(string: text, attributes: [
            .font: font, .kern: kern, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        cg.textPosition = p
        CTLineDraw(CTLineCreateWithAttributedString(a), cg)
    }

    func drawMarkRules(page: Int, in cg: CGContext, theme: Theme, marks: Marks) {
        guard !marks.marks.isEmpty else { return }
        let size = style.size
        for (m, spans) in placed(marks.marks, page: page, index: marks.lineIndex) {
            switch m.kind {
            case .highlight: continue
            case .underline:
                cg.setFillColor(theme.ink)
                for s in spans { cg.fill(CGRect(x: s.origin.x + s.x0, y: s.origin.y - 3.5, width: s.x1 - s.x0, height: 2)) }
            case .note:
                cg.saveGState()
                cg.setStrokeColor(theme.ink)
                cg.setLineWidth(2)
                cg.setLineCap(.round)
                cg.setLineDash(phase: 0, lengths: [0.1, 4])
                for s in spans {
                    cg.move(to: CGPoint(x: s.origin.x + s.x0 + 1, y: s.origin.y - 2.5))
                    cg.addLine(to: CGPoint(x: s.origin.x + s.x1 - 1, y: s.origin.y - 2.5))
                    cg.strokePath()
                }
                cg.restoreGState()
                if let last = spans.last, let g = ReaderGlyph.symbol("note.text", size: size * 0.6, color: theme.ink) {
                    let h = size * 0.6 * 0.95
                    let w = h * CGFloat(g.width) / CGFloat(g.height)
                    cg.draw(g, in: CGRect(x: last.origin.x + last.x1 + 1, y: last.origin.y + last.asc * 0.5, width: w, height: h))
                }
            case .breath, .pause, .beat:
                guard let s = spans.first else { continue }
                let font = ReaderFonts.sans(size * 0.85, weight: .semibold)
                let slashes = m.kind == .breath ? "/" : "//"
                drawText(slashes, font: font, color: theme.ink, at: CGPoint(x: s.origin.x + s.x0 + size * 0.1, y: s.origin.y), in: cg)
                if m.kind == .beat, let label = m.label, !label.isEmpty {
                    let lw = MarkGeometry.labelWidth(label, size: size)
                    let pill = CGRect(x: s.origin.x + s.x0 + size * 0.95, y: s.origin.y - 2, width: lw + size * 0.7, height: size * 0.6 * 1.4 + 4)
                    cg.setStrokeColor(theme.ink)
                    cg.setLineWidth(1)
                    cg.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
                    cg.strokePath()
                    drawText(label.uppercased(), font: MarkGeometry.labelFont(size), color: theme.ink, kern: MarkGeometry.labelKern(size),
                             at: CGPoint(x: pill.minX + size * 0.35, y: pill.minY + 4 + size * 0.04), in: cg)
                }
            }
        }
    }
}
