import CoreGraphics
import CoreText
import Foundation
#if canImport(UIKit)
import UIKit
typealias ReaderFont = UIFont
#elseif canImport(AppKit)
import AppKit
typealias ReaderFont = NSFont
#endif

// Pages for the script reader (PLAYS-DESIGN §2.7, iOS-DESIGN §4.15, macOS-DESIGN §4.7). One attributed string
// holds the whole script; Core Text cuts it into pages of the reader's size (a frame per page, chained by the
// range the last one showed) and the same frame draws the page, so what is drawn is what was measured. The
// brief names TextKit 2; an `NSTextLayoutManager` holds one container, so a chain of pages is Core Text's.
// Never SwiftUI `Text`: its line breaking differs and pages would overflow.

nonisolated extension NSAttributedString.Key {
    /// The script line's index (an `Int` into `script.lines`) a run belongs to; its id is `script.lines[i].id`.
    static let edLine = NSAttributedString.Key("ed.line")
    /// A `ReaderInk` raw value: which color the run is drawn in.
    static let edInk = NSAttributedString.Key("ed.ink")
    /// The part's place in the cast (the hue's index), or -1.
    static let edHue = NSAttributedString.Key("ed.hue")
    /// The run's offset into `ScriptReading.lineText(line)`, or -1 for a heading drawn from a set-aside block.
    static let edOffset = NSAttributedString.Key("ed.offset")
}

nonisolated enum ReaderInk: Int, Sendable {
    case speaker, said, aside, direction, cue, heading
}

/// A script's structure, computed once: the sections, the contents, and what draws before each line.
nonisolated struct ScriptStructure: Sendable {
    let sections: [ScriptHeading]
    let contents: [ContentsEntry]
    let indexByID: [String: Int]
    /// Set-aside headings drawn before the line at this index.
    let setAside: [Int: [ScriptHeading]]
    /// Lines that are themselves headings.
    let headLines: [Int: ScriptHeading]
    /// Each line's speaking part's place in the cast (the hue's index), or -1.
    let hueOfLine: [Int]
    let speaking: [PartID]

    init(_ script: PlayScript) {
        sections = ScriptReading.sectionsOf(script)
        contents = ScriptReading.contents(from: sections)
        indexByID = Dictionary(script.lines.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        var before: [Int: [ScriptHeading]] = [:]
        var heads: [Int: ScriptHeading] = [:]
        for s in sections {
            if s.isLine { heads[s.index] = s } else { before[s.index, default: []].append(s) }
        }
        setAside = before
        headLines = heads
        let order = script.castParts.filter { $0.id.isSpeaking }.map(\.id)
        speaking = order
        let place = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        hueOfLine = script.lines.map { line in
            guard line.kind == .speech, let at = place[line.part], at < PlayScript.partHues.count else { return -1 }
            return at
        }
    }

    func place(of lineIndex: Int) -> (act: ScriptHeading?, scene: ScriptHeading?) {
        ScriptReading.placeOf(contents, lineIndex: lineIndex)
    }
}

nonisolated struct ReaderStyle: Equatable, Sendable {
    /// The reading body's point size: Dynamic Type's body on a phone, a book size on the Mac.
    var base: CGFloat
    /// The reader's size step (`ReaderMath.sizes`).
    var scale: Double
    /// Line height as a multiple of the type size.
    var leading: Double

    var size: CGFloat { (base * CGFloat(scale)).rounded(.toNearestOrEven) }
}

nonisolated enum ReaderFonts {
    static func serif(_ size: CGFloat, italic: Bool = false, weight: ReaderFont.Weight = .regular) -> ReaderFont {
        #if canImport(UIKit)
        var d = ReaderFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if let s = d.withDesign(.serif) { d = s }
        if italic, let i = d.withSymbolicTraits(d.symbolicTraits.union(.traitItalic)) { d = i }
        return ReaderFont(descriptor: d, size: size)
        #else
        var d = ReaderFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if let s = d.withDesign(.serif) { d = s }
        if italic { d = d.withSymbolicTraits(d.symbolicTraits.union(.italic)) }
        return ReaderFont(descriptor: d, size: size) ?? ReaderFont.systemFont(ofSize: size, weight: weight)
        #endif
    }

    static func sans(_ size: CGFloat, weight: ReaderFont.Weight = .semibold) -> ReaderFont {
        ReaderFont.systemFont(ofSize: size, weight: weight)
    }

    /// The section-header face (`TypeRamp.displayFontName`), the system bold where it is not installed.
    static func display(_ size: CGFloat) -> ReaderFont {
        ReaderFont(name: TypeRamp.displayFontName, size: size) ?? sans(size, weight: .bold)
    }
}

/// A cut script: the pages, and for every script line the first and last page it shows.
nonisolated final class ReaderLayout: @unchecked Sendable {
    let string: NSAttributedString
    let pageSize: CGSize
    let style: ReaderStyle
    let pages: [NSRange]
    let lineRanges: [NSRange]
    let starts: [Int]
    let ends: [Int]
    let hueOfLine: [Int]
    private let framesetter: CTFramesetter
    private let frames = NSCache<NSNumber, FrameBox>()

    private final class FrameBox { let frame: CTFrame; init(_ f: CTFrame) { frame = f } }

    var pageCount: Int { max(1, pages.count) }

    private init(string: NSAttributedString, framesetter: CTFramesetter, pageSize: CGSize, style: ReaderStyle, pages: [NSRange],
                 lineRanges: [NSRange], hueOfLine: [Int]) {
        self.string = string
        self.framesetter = framesetter
        self.pageSize = pageSize
        self.style = style
        self.pages = pages
        self.lineRanges = lineRanges
        self.hueOfLine = hueOfLine
        func pageOf(_ offset: Int) -> Int {
            var lo = 0, hi = pages.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if pages[mid].location <= offset { lo = mid } else { hi = mid - 1 }
            }
            return max(0, lo)
        }
        var s: [Int] = [], e: [Int] = []
        s.reserveCapacity(lineRanges.count)
        e.reserveCapacity(lineRanges.count)
        for r in lineRanges {
            s.append(pageOf(r.location))
            e.append(pageOf(max(r.location, r.location + r.length - 1)))
        }
        starts = s
        ends = e
    }

    /// Cuts `script` into pages of `pageSize` at `style`. Throws when its task is cancelled (a newer layout is wanted).
    static func build(_ script: PlayScript, structure: ScriptStructure, style: ReaderStyle, pageSize: CGSize) throws -> ReaderLayout {
        let size = style.size
        let lineHeight = (size * CGFloat(style.leading)).rounded()
        let out = NSMutableAttributedString()
        var ranges: [NSRange] = []
        ranges.reserveCapacity(script.lines.count)

        func paragraph(height: CGFloat, before: CGFloat = 0, after: CGFloat, indent: CGFloat = 0,
                       align: NSTextAlignment = .natural) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.minimumLineHeight = height
            p.maximumLineHeight = height
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            p.firstLineHeadIndent = indent
            p.headIndent = indent
            p.alignment = align
            p.lineBreakMode = .byWordWrapping
            return p
        }

        func append(_ text: String, font: ReaderFont, ink: ReaderInk, line: Int, hue: Int, at: Int) {
            out.append(NSAttributedString(string: text, attributes: [
                .font: font, .edInk: ink.rawValue, .edLine: line, .edHue: hue, .edOffset: at,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ]))
        }

        func heading(_ text: String, level: SectionLevel, line: Int) {
            let big = level == .scene ? size * 1.15 : size * 1.4
            let start = out.length
            append(text, font: ReaderFonts.display(big), ink: .heading, line: line, hue: -1, at: -1)
            append("\n", font: ReaderFonts.display(big), ink: .heading, line: line, hue: -1, at: -1)
            out.addAttribute(.paragraphStyle, value: paragraph(height: (big * CGFloat(style.leading)).rounded(), before: size * 1.2,
                                                               after: size * 0.8, align: .center),
                             range: NSRange(location: start, length: out.length - start))
        }

        for (i, line) in script.lines.enumerated() {
            if i % 256 == 0 { try Task.checkCancellation() }
            let lo = out.length
            for h in structure.setAside[i] ?? [] { heading(h.title, level: h.level, line: i) }
            let runs = ScriptReading.runsOf(line)
            let hue = structure.hueOfLine[i]
            if let head = structure.headLines[i] {
                let start = out.length
                let big = head.level == .scene ? size * 1.15 : size * 1.4
                let font = ReaderFonts.display(big)
                for r in runs { append(r.text, font: font, ink: .heading, line: i, hue: -1, at: r.at) }
                append("\n", font: font, ink: .heading, line: i, hue: -1, at: -1)
                out.addAttribute(.paragraphStyle, value: paragraph(height: (big * CGFloat(style.leading)).rounded(), before: size * 1.2,
                                                                   after: size * 0.8, align: .center),
                                 range: NSRange(location: start, length: out.length - start))
            } else if line.kind == .speech {
                let start = out.length
                append(line.role ?? "", font: ReaderFonts.sans(size * 0.8125), ink: .speaker, line: i, hue: hue, at: -1)
                append(" ", font: ReaderFonts.serif(size), ink: .said, line: i, hue: -1, at: -1)
                var previous: ScriptReading.Run?
                for r in runs {
                    if let p = previous, p.piece != r.piece, ScriptReading.spaceBetween(p.text, r.text) {
                        append(" ", font: ReaderFonts.serif(size), ink: .said, line: i, hue: -1, at: -1)
                    }
                    switch r.kind {
                    case .say: append(r.text, font: ReaderFonts.serif(size), ink: .said, line: i, hue: -1, at: r.at)
                    case .em: append(r.text, font: ReaderFonts.serif(size, italic: true), ink: .said, line: i, hue: -1, at: r.at)
                    case .aside: append(r.text, font: ReaderFonts.serif(size, italic: true), ink: .aside, line: i, hue: -1, at: r.at)
                    case .plain: append(r.text, font: ReaderFonts.serif(size), ink: .aside, line: i, hue: -1, at: r.at)
                    }
                    previous = r
                }
                append("\n", font: ReaderFonts.serif(size), ink: .said, line: i, hue: -1, at: -1)
                out.addAttribute(.paragraphStyle, value: paragraph(height: lineHeight, after: size * 0.55),
                                 range: NSRange(location: start, length: out.length - start))
            } else {
                let start = out.length
                let cue = line.kind != .direction
                for r in runs {
                    let italic = cue ? false : r.kind == .plain
                    let font = cue ? ReaderFonts.sans(size * 0.8125) : ReaderFonts.serif(size * 0.95, italic: italic)
                    append(r.text, font: font, ink: cue ? .cue : .direction, line: i, hue: -1, at: r.at)
                }
                append("\n", font: ReaderFonts.serif(size), ink: .direction, line: i, hue: -1, at: -1)
                out.addAttribute(.paragraphStyle, value: paragraph(height: lineHeight, after: size * 0.55, indent: size * 1.25),
                                 range: NSRange(location: start, length: out.length - start))
            }
            ranges.append(NSRange(location: lo, length: out.length - lo))
        }

        let framesetter = CTFramesetterCreateWithAttributedString(out)
        let path = CGPath(rect: CGRect(origin: .zero, size: pageSize), transform: nil)
        var pages: [NSRange] = []
        var location = 0
        let total = out.length
        while location < total {
            if pages.count % 16 == 0 { try Task.checkCancellation() }
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame).length
            let length = max(1, min(visible, total - location))
            pages.append(NSRange(location: location, length: length))
            location += length
        }
        if pages.isEmpty { pages = [NSRange(location: 0, length: 0)] }
        return ReaderLayout(string: out, framesetter: framesetter, pageSize: pageSize, style: style, pages: pages,
                            lineRanges: ranges, hueOfLine: structure.hueOfLine)
    }

    // MARK: Where things are

    /// The script line whose text holds this offset into the string.
    func lineIndex(at offset: Int) -> Int {
        var lo = 0, hi = lineRanges.count - 1
        guard hi >= 0 else { return 0 }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineRanges[mid].location <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// The script lines that show on a page, first to last.
    func lines(onPage page: Int) -> Range<Int> {
        guard pages.indices.contains(page), !lineRanges.isEmpty else { return 0..<0 }
        let r = pages[page]
        return lineIndex(at: r.location)..<(lineIndex(at: max(r.location, r.location + r.length - 1)) + 1)
    }

    func frame(_ page: Int) -> CTFrame {
        let key = NSNumber(value: page)
        if let box = frames.object(forKey: key) { return box.frame }
        let r = pages.indices.contains(page) ? pages[page] : NSRange(location: 0, length: 0)
        let path = CGPath(rect: CGRect(origin: .zero, size: pageSize), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: r.location, length: r.length), path, nil)
        frames.setObject(FrameBox(frame), forKey: key)
        return frame
    }

    /// The script line under a point of a page (top-left origin), or nil in the gap between lines.
    func line(at point: CGPoint, page: Int) -> Int? {
        let frame = self.frame(page)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let y = pageSize.height - point.y
        for (i, line) in lines.enumerated() {
            var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &asc, &desc, &lead)
            let band = ReaderLayout.band(origin: origins[i], asc: asc, desc: desc, style: style)
            guard y >= band.minY, y <= band.maxY else { continue }
            let at = CTLineGetStringIndexForPosition(line, CGPoint(x: point.x - origins[i].x, y: 0))
            return lineIndex(at: at == kCFNotFound ? CTLineGetStringRange(line).location : at)
        }
        return nil
    }

    /// The vertical extent a line occupies: its line height, the baseline's descent below it.
    fileprivate static func band(origin: CGPoint, asc: CGFloat, desc: CGFloat, style: ReaderStyle) -> CGRect {
        let height = max(asc + desc, (style.size * CGFloat(style.leading)).rounded())
        return CGRect(x: 0, y: origin.y - desc, width: 0, height: height)
    }

    // MARK: Drawing

    struct Theme {
        var ink: CGColor
        var muted: CGColor
        var hues: [CGColor]
        var background: CGColor
    }

    struct Marks {
        /// The lines of the part being played, or nil.
        var mine: Set<Int>? = nil
        var hide = false
        /// Hidden lines the person has tapped open.
        var peeked: Set<Int> = []
    }

    /// Draws one page into a context whose origin is the page's top-left, y down (a SwiftUI `Canvas`).
    func draw(page: Int, in cg: CGContext, theme: Theme, marks: Marks = Marks()) {
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.translateBy(x: 0, y: pageSize.height)
        cg.scaleBy(x: 1, y: -1)
        cg.textMatrix = .identity
        let frame = self.frame(page)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        func hue(_ line: Int) -> CGColor {
            let h = hueOfLine.indices.contains(line) ? hueOfLine[line] : -1
            return h >= 0 && h < theme.hues.count ? theme.hues[h] : theme.muted
        }
        for (i, line) in lines.enumerated() {
            let origin = origins[i]
            var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &asc, &desc, &lead)
            let range = CTLineGetStringRange(line)
            let index = lineIndex(at: range.location)
            let band = ReaderLayout.band(origin: origin, asc: asc, desc: desc, style: style)
            let mine = marks.mine?.contains(index) == true
            if mine {
                cg.setFillColor(hue(index).copy(alpha: 0.09) ?? hue(index))
                cg.fill(CGRect(x: -10, y: band.minY, width: pageSize.width + 20, height: band.height))
                cg.setFillColor(hue(index))
                cg.fill(CGRect(x: -10, y: band.minY, width: 3, height: band.height))
            }
            var hidden: [(CGFloat, CGFloat)] = []
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                let inkValue = (attrs[NSAttributedString.Key.edInk] as? Int).flatMap(ReaderInk.init(rawValue:)) ?? .said
                let runLine = (attrs[NSAttributedString.Key.edLine] as? Int) ?? index
                let rr = CTRunGetStringRange(run)
                if marks.hide, mine, marks.mine?.contains(runLine) == true, inkValue == .said, !marks.peeked.contains(runLine) {
                    let x0 = CTLineGetOffsetForStringIndex(line, rr.location, nil)
                    let x1 = CTLineGetOffsetForStringIndex(line, rr.location + rr.length, nil)
                    if let last = hidden.last, abs(last.1 - x0) < 6 { hidden[hidden.count - 1].1 = x1 } else { hidden.append((x0, x1)) }
                    continue
                }
                switch inkValue {
                case .said, .heading: cg.setFillColor(theme.ink)
                case .speaker: cg.setFillColor(hue(runLine))
                case .aside, .direction, .cue: cg.setFillColor(theme.muted)
                }
                cg.textPosition = origin
                CTRunDraw(run, cg, CFRange(location: 0, length: 0))
            }
            for span in hidden {
                let rect = CGRect(x: origin.x + span.0 - 2, y: origin.y - desc * 0.5, width: span.1 - span.0 + 4, height: (asc + desc) * 0.8)
                cg.setFillColor(hue(index).copy(alpha: 0.30) ?? hue(index))
                cg.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2.8, cornerHeight: rect.height / 2.8, transform: nil))
                cg.fillPath()
            }
        }
    }
}
