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
    /// The role (as printed) of the speech a run belongs to: names, words, directions inside it.
    static let edRole = NSAttributedString.Key("ed.role")
    /// A running number per speech, so a speech's lines tint as one block.
    static let edSpeech = NSAttributedString.Key("ed.speech")
    /// A run drawn on the sound lane's quiet block.
    static let edBlock = NSAttributedString.Key("ed.block")
    /// The speaker glyph's placeholder (drawn as an SF Symbol, not as text).
    static let edGlyph = NSAttributedString.Key("ed.glyph")
    /// The role whose speech comes in on this run (the cue), and its hue; underlined when that part is being played.
    static let edCueRole = NSAttributedString.Key("ed.cue.role")
    static let edCueHue = NSAttributedString.Key("ed.cue.hue")
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

/// A page that opens inside a speech is headed, above the text, with its speaker and "(cont'd)".
nonisolated struct ReaderContd: Equatable, Sendable {
    let role: String
    let hue: Int
}

/// What pagination knows of one paragraph: where a page may not break (a name stays with its words, an act opens
/// a page, verse keeps two rows at either side).
nonisolated private struct ReaderPara {
    var start: Int
    var end: Int
    var keepNext = false
    var breakBefore = false
    var group = -1
    var speechStart = -1
    var role: String?
    var hue = -1
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
    let hueByRole: [String: Int]
    let contd: [Int: ReaderContd]
    /// Whether the speaker's name stands in a gutter beside the words (a page of 30 em or more).
    let gutter: Bool
    /// The studio's part (its role name): its speeches never split across pages (PLAYS-DESIGN §2.9), and the page
    /// keeps `footRoom` below the text so the current line's outline is never clipped.
    let keepRole: String?
    private let framesetter: CTFramesetter
    private let frames = NSCache<NSNumber, FrameBox>()

    /// The page's inner margin: a part's tint and its rule are drawn inside it, so no page edge clips them.
    static let inset: CGFloat = 14
    /// Room above the text for a carried-over speech's head.
    static let headRoom: CGFloat = 22
    /// Room below the text in the studio, for the current line's outline.
    static let footRoom: CGFloat = 8

    private final class FrameBox { let frame: CTFrame; init(_ f: CTFrame) { frame = f } }

    var pageCount: Int { max(1, pages.count) }

    /// The text column: the page without its inner margins.
    var textSize: CGSize { CGSize(width: pageSize.width - 2 * Self.inset, height: pageSize.height) }

    private init(string: NSAttributedString, framesetter: CTFramesetter, pageSize: CGSize, style: ReaderStyle, pages: [NSRange],
                 lineRanges: [NSRange], hueOfLine: [Int], hueByRole: [String: Int], contd: [Int: ReaderContd], gutter: Bool,
                 keepRole: String?) {
        self.string = string
        self.framesetter = framesetter
        self.pageSize = pageSize
        self.style = style
        self.pages = pages
        self.lineRanges = lineRanges
        self.hueOfLine = hueOfLine
        self.hueByRole = hueByRole
        self.contd = contd
        self.gutter = gutter
        self.keepRole = keepRole
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
    static func build(_ script: PlayScript, structure: ScriptStructure, style: ReaderStyle, pageSize: CGSize,
                      keepRole: String? = nil) throws -> ReaderLayout {
        let size = style.size
        let lineHeight = (size * CGFloat(style.leading)).rounded()
        let textWidth = pageSize.width - 2 * inset
        let gutterOn = pageSize.width / size >= PlayPage.gutterMinEm
        let gutterW = size * 8.5
        let col = size * 9.5
        let gap = size * 0.7
        let roles = script.roles.map(\.name)
        var hueByRole: [String: Int] = [:]
        for (i, p) in structure.speaking.enumerated() where i < PlayScript.partHues.count {
            if let n = p.roleName { hueByRole[n] = i }
        }
        let names = DirectionNames(roles: roles)

        let out = NSMutableAttributedString()
        var ranges: [NSRange] = []
        ranges.reserveCapacity(script.lines.count)
        var paras: [ReaderPara] = []
        var pendingBreak = true
        var groupCount = 0
        var speechCount = 0

        // Context every appended run carries.
        var ctxLine = -1
        var ctxRole: String?
        var ctxSpeech = -1

        func paragraph(before: CGFloat = 0, after: CGFloat, first: CGFloat = 0, head: CGFloat = 0, height: CGFloat? = nil,
                       align: NSTextAlignment = .natural, tabs: [CGFloat] = []) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            let h = height ?? lineHeight
            p.minimumLineHeight = h
            p.maximumLineHeight = h
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            p.firstLineHeadIndent = first
            p.headIndent = head
            p.alignment = align
            p.lineBreakMode = .byWordWrapping
            if !tabs.isEmpty { p.tabStops = tabs.map { NSTextTab(textAlignment: .left, location: $0, options: [:]) } }
            return p
        }

        func append(_ text: String, font: ReaderFont, ink: ReaderInk, hue: Int = -1, at: Int, extra: [NSAttributedString.Key: Any] = [:]) {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font, .edInk: ink.rawValue, .edLine: ctxLine, .edHue: hue, .edOffset: at,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ]
            if let r = ctxRole { attrs[.edRole] = r; attrs[.edSpeech] = ctxSpeech }
            for (k, v) in extra { attrs[k] = v }
            out.append(NSAttributedString(string: text, attributes: attrs))
        }

        /// Ends the paragraph that began at `start`: its break, its style, and what pagination needs to know.
        func endPara(_ start: Int, style: NSParagraphStyle, keepNext: Bool = false, breakBefore: Bool = false, group: Int = -1,
                 speechStart: Int = -1, role: String? = nil, hue: Int = -1) {
            append("\n", font: ReaderFonts.serif(size), ink: .said, at: -1)
            out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: out.length - start))
            paras.append(ReaderPara(start: start, end: out.length, keepNext: keepNext, breakBefore: breakBefore || pendingBreak,
                                    group: group, speechStart: speechStart, role: role, hue: hue))
            pendingBreak = false
        }

        func headingFont(_ level: SectionLevel) -> ReaderFont {
            ReaderFonts.display(level == .scene ? size * 1.25 : size * 1.75)
        }

        func heading(_ text: String, level: SectionLevel, runs: [ScriptReading.Run]? = nil) {
            let start = out.length
            let font = headingFont(level)
            let big = level == .scene ? size * 1.25 : size * 1.75
            if let runs {
                for r in runs { append(r.text, font: font, ink: .heading, at: r.at) }
            } else {
                append(text, font: font, ink: .heading, at: -1)
            }
            let opens = level != .scene
            endPara(start, style: paragraph(before: opens ? 0 : size * 1.2, after: size * 0.6, height: (big * 1.2).rounded()),
                keepNext: true, breakBefore: opens)
        }

        // Caption: the speaker glyph and cue lane, a part's printed name.
        let caption = size * 0.8125
        func nameFont() -> ReaderFont { ReaderFonts.sans(size * 0.9, weight: .semibold) }
        let glyphWidth = caption * 1.7

        /// A cue's words on the sound lane; the first character carries the glyph mark (the glyph is drawn in the
        /// indent before it, an SF Symbol Core Text cannot set in a line).
        func appendCue(_ r: PageRun, first: Bool) {
            let up = r.text.uppercased()
            let text = up.utf16.count == r.text.utf16.count ? up : r.text
            let font = ReaderFonts.sans(caption, weight: .semibold)
            let extra: [NSAttributedString.Key: Any] = [.edBlock: 1, .kern: caption * 0.06]
            var at = r.at
            var body = text
            if first, let head = text.first {
                var mark = extra
                mark[.edGlyph] = true
                append(String(head), font: font, ink: .cue, at: at, extra: mark)
                at += String(head).utf16.count
                body = String(text.dropFirst())
            }
            if !body.isEmpty { append(body, font: font, ink: .cue, at: at, extra: extra) }
        }

        /// A direction's words, each part it names (in capitals) in that part's hue, upright and strong.
        func appendDirection(_ text: String, at: Int, italic: Bool, ink: ReaderInk, scale: CGFloat = 1) {
            var last = 0
            let ns = text as NSString
            func plain(_ from: Int, _ to: Int) {
                guard to > from else { return }
                append(ns.substring(with: NSRange(location: from, length: to - from)),
                       font: ReaderFonts.serif(size * scale, italic: italic), ink: ink, at: at + from)
            }
            for m in names.matches(in: text) {
                plain(last, m.range.location)
                let n = ns.substring(with: m.range)
                if let h = hueByRole[n] {
                    append(n, font: ReaderFonts.serif(size * scale, weight: .semibold), ink: .speaker, hue: h, at: at + m.range.location)
                } else {
                    append(n, font: ReaderFonts.serif(size * scale, italic: italic), ink: ink, at: at + m.range.location)
                }
                last = m.range.location + m.range.length
            }
            plain(last, ns.length)
        }

        let asideOpen = try! NSRegularExpression(pattern: "^\\s*[(\\[]")
        let asideClose = try! NSRegularExpression(pattern: "[)\\]][.,;:!?]*\\s*$")
        func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
            re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
        }

        // The last said run of the speech being drawn, and the speech before it, for the cue underline.
        var lastSaid: (loc: Int, text: String)?
        var previousSpeech: (role: String, tail: NSRange?)?

        /// One row's words, cue pieces and asides, as printed runs in order.
        func appendRow(_ row: PageRow) {
            var previous: PageRun?
            for (k, r) in row.runs.enumerated() {
                if let p = previous, p.piece != r.piece, ScriptReading.spaceBetween(p.text, r.text) {
                    append(" ", font: ReaderFonts.serif(size), ink: .said, at: -1)
                }
                previous = r
                if r.said {
                    lastSaid = (out.length, r.text)
                    switch r.kind {
                    case .em: append(r.text, font: ReaderFonts.serif(size, italic: true), ink: .said, at: r.at)
                    default: append(r.text, font: ReaderFonts.serif(size), ink: .said, at: r.at)
                    }
                    continue
                }
                let whole = row.runs.filter { $0.piece == r.piece && !$0.said }.map(\.text).joined()
                let open = (k == 0 || row.runs[k - 1].piece != r.piece) && !matches(asideOpen, whole)
                let close = (k == row.runs.count - 1 || row.runs[k + 1].piece != r.piece) && !matches(asideClose, whole)
                if open { append("(", font: ReaderFonts.serif(size), ink: .aside, at: -1) }
                appendDirection(r.text, at: r.at, italic: r.kind != .plain, ink: .aside)
                if close { append(")", font: ReaderFonts.serif(size), ink: .aside, at: -1) }
            }
        }

        // The front of the play: its title, its authors, and its speaking parts in their hues.
        if !script.lines.isEmpty {
            var s = out.length
            append(script.title, font: ReaderFonts.display(size * 1.75), ink: .heading, at: -1)
            endPara(s, style: paragraph(after: size * 0.3, height: (size * 2.1).rounded()), keepNext: true)
            let by = script.authorLine
            if !by.isEmpty {
                s = out.length
                append(by, font: ReaderFonts.serif(size), ink: .direction, at: -1)
                endPara(s, style: paragraph(after: size * 1.2), keepNext: true)
            }
            if !structure.speaking.isEmpty {
                s = out.length
                append("Parts", font: ReaderFonts.sans(caption, weight: .regular), ink: .direction, at: -1)
                endPara(s, style: paragraph(after: size * 0.3), keepNext: true)
                s = out.length
                for (i, p) in structure.speaking.enumerated() {
                    if i > 0 { append("   ", font: ReaderFonts.serif(size), ink: .said, at: -1) }
                    append(p.title, font: nameFont(), ink: .speaker, hue: i < PlayScript.partHues.count ? i : -1, at: -1,
                           extra: [.kern: size * 0.02])
                }
                endPara(s, style: paragraph(after: size * 0.7))
            }
        }

        pendingBreak = !script.lines.isEmpty
        for (i, line) in script.lines.enumerated() {
            if i % 256 == 0 { try Task.checkCancellation() }
            let lo = i == 0 ? 0 : out.length
            ctxLine = i
            ctxRole = nil
            for h in structure.setAside[i] ?? [] { heading(h.title, level: h.level) }
            if let head = structure.headLines[i] {
                heading("", level: head.level, runs: ScriptReading.runsOf(line))
            } else if line.kind == .speech, line.parts != nil {
                let layout = PlayPage.layoutOf(line, roles: roles)
                for sp in layout.speeches {
                    let hue = hueByRole[sp.role] ?? -1
                    speechCount += 1
                    ctxRole = sp.role
                    ctxSpeech = speechCount
                    if let p = previousSpeech, let tail = p.tail, p.role != sp.role {
                        out.addAttributes([.edCueRole: sp.role, .edCueHue: hue], range: tail)
                    }
                    lastSaid = nil
                    let speechStart = out.length
                    let name = sp.name?.text ?? sp.role
                    let nameAt = sp.name?.at ?? -1
                    let nameWidth = (name as NSString).size(withAttributes: [.font: nameFont()]).width
                        + CGFloat(name.count) * size * 0.02
                    let firstIsCue = sp.rows.first?.cue ?? false
                    let beside = gutterOn && !name.isEmpty && !sp.rows.isEmpty && !firstIsCue && nameWidth <= gutterW
                    let base: CGFloat = beside ? col : 0
                    func appendName() {
                        append(name, font: nameFont(), ink: .speaker, hue: hue, at: nameAt, extra: [.kern: size * 0.02])
                    }

                    if !beside, !name.isEmpty {
                        let s = out.length
                        appendName()
                        endPara(s, style: paragraph(after: 0), keepNext: !sp.rows.isEmpty, speechStart: speechStart, role: sp.role, hue: hue)
                    }
                    let group: Int
                    if layout.verse { groupCount += 1; group = groupCount } else { group = -1 }
                    for (k, row) in sp.rows.enumerated() {
                        let last = k == sp.rows.count - 1
                        let after = last ? gap : (row.cue || sp.rows[k + 1].cue ? size * 0.2 : 0)
                        let s = out.length
                        if row.cue {
                            for (n, r) in row.runs.enumerated() {
                                if n > 0, row.runs[n - 1].piece != r.piece { append(" ", font: ReaderFonts.sans(caption), ink: .cue, at: -1, extra: [.edBlock: 1]) }
                                appendCue(r, first: n == 0)
                            }
                            endPara(s, style: paragraph(before: size * 0.2, after: max(after, size * 0.2), first: base + glyphWidth, head: base + glyphWidth),
                                speechStart: speechStart, role: sp.role, hue: hue)
                            continue
                        }
                        let first = k == 0 && beside
                        var tabs: [CGFloat] = []
                        var firstIndent = base
                        var headIndent = base
                        if layout.verse {
                            let half = row.indent
                            if !first { firstIndent = base + (half ? size * 2.5 : 0) }
                            headIndent = base + (half ? size * 4 : size * 1.5)
                        }
                        if first {
                            appendName()
                            append("\t", font: ReaderFonts.serif(size), ink: .said, at: -1)
                            firstIndent = max(0, gutterW - nameWidth)
                            tabs = [col]
                        }
                        appendRow(row)
                        endPara(s, style: paragraph(after: after, first: firstIndent, head: headIndent, tabs: tabs),
                            group: group, speechStart: speechStart, role: sp.role, hue: hue)
                    }
                    var tail: NSRange?
                    if let l = lastSaid {
                        let k = PlayPage.cueTail(l.text)
                        let length = l.text.utf16.count
                        tail = NSRange(location: l.loc + k, length: max(0, length - k))
                    }
                    previousSpeech = (sp.role, tail)
                }
                ctxRole = nil
            } else {
                let layout = PlayPage.layoutOf(line, roles: roles)
                let row = layout.rows.first ?? PageRow(cue: false, indent: false, runs: [])
                let s = out.length
                let indent = gutterOn ? col : size * 1.5
                if row.cue {
                    for (n, r) in row.runs.enumerated() { appendCue(r, first: n == 0) }
                    endPara(s, style: paragraph(before: size * 0.2, after: gap, first: indent + glyphWidth, head: indent + glyphWidth))
                } else {
                    for r in row.runs {
                        appendDirection(r.text, at: r.at, italic: r.kind == .plain, ink: .direction)
                    }
                    endPara(s, style: paragraph(after: gap, first: indent, head: indent))
                }
            }
            ranges.append(NSRange(location: lo, length: out.length - lo))
        }

        // MARK: Pages

        let framesetter = CTFramesetterCreateWithAttributedString(out)
        let path = CGPath(rect: CGRect(origin: .zero, size: CGSize(width: textWidth, height: pageSize.height)), transform: nil)
        let total = out.length
        let breaks = paras.filter(\.breakBefore).map(\.start)
        var groupFirst: [Int: Int] = [:]
        var groupLast: [Int: Int] = [:]
        for (i, p) in paras.enumerated() where p.group >= 0 {
            if groupFirst[p.group] == nil { groupFirst[p.group] = i }
            groupLast[p.group] = i
        }
        var speechEnd: [Int: Int] = [:]
        for p in paras where p.speechStart >= 0 { speechEnd[p.speechStart] = max(speechEnd[p.speechStart] ?? 0, p.end) }
        func paraIndex(_ loc: Int) -> Int {
            var lo = 0, hi = paras.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if paras[mid].start <= loc { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }

        /// Moves a page's end so a name is never alone at its foot, an act opens a page, and a speech keeps two lines
        /// (verse, two rows) at either side of a break.
        func adjust(start: Int, visibleEnd: Int, frame: CTFrame) -> Int {
            var end = visibleEnd
            if let b = breaks.first(where: { $0 > start && $0 < end }) { end = b }
            let lines = CTFrameGetLines(frame) as! [CTLine]
            let lineStarts = lines.map { CTLineGetStringRange($0).location }
            for _ in 0..<12 {
                guard end < total, end > start else { break }
                let pi = paraIndex(end - 1)
                let p = paras[pi]
                // In the studio my speech is one block: it goes whole to the next page (one longer than a page breaks).
                if let keep = keepRole, p.role == keep, p.speechStart > start, (speechEnd[p.speechStart] ?? 0) > end {
                    end = p.speechStart
                    continue
                }
                if end < p.end {
                    if p.group >= 0 {
                        if p.start > start { end = p.start; continue }
                        break
                    }
                    let n1 = lineStarts.filter { $0 >= p.start && $0 < end }.count
                    if p.start > start, n1 < 2 { end = p.start; continue }
                    let next = CTFramesetterCreateFrame(framesetter, CFRange(location: end, length: 0), path, nil)
                    let n2 = (CTFrameGetLines(next) as! [CTLine]).filter { CTLineGetStringRange($0).location < p.end }.count
                    if n2 < 2 {
                        if n1 >= 3, let at = lineStarts.last(where: { $0 >= p.start && $0 < end }) { end = at; continue }
                        if p.start > start { end = p.start; continue }
                    }
                    // A name set inside a direction ("(Extends arms; BIJAH") is not left at the foot either.
                    if end >= 2, out.attribute(.edInk, at: end - 2, effectiveRange: nil) as? Int == ReaderInk.speaker.rawValue {
                        let n1 = lineStarts.filter { $0 >= p.start && $0 < end }.count
                        if n1 >= 3, let at = lineStarts.last(where: { $0 >= p.start && $0 < end }) { end = at; continue }
                        if p.start > start { end = p.start; continue }
                    }
                    break
                }
                if p.keepNext, p.start > start { end = p.start; continue }
                if p.group >= 0, pi + 1 < paras.count, paras[pi + 1].group == p.group, let gf = groupFirst[p.group], let gl = groupLast[p.group] {
                    let before = pi - max(gf, paraIndex(start)) + 1
                    let after = gl - pi
                    if before < 2 || after < 2 {
                        if after < 2, before >= 3 { end = p.start; continue }
                        if paras[gf].start > start { end = paras[gf].start; continue }
                    }
                }
                break
            }
            return end > start ? end : visibleEnd
        }

        var pages: [NSRange] = []
        var contd: [Int: ReaderContd] = [:]
        var location = 0
        while location < total {
            if pages.count % 16 == 0 { try Task.checkCancellation() }
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame).length
            var stop = min(total, location + max(1, visible))
            if stop < total { stop = adjust(start: location, visibleEnd: stop, frame: frame) }
            pages.append(NSRange(location: location, length: stop - location))
            if !paras.isEmpty {
                let p = paras[paraIndex(location)]
                if p.speechStart >= 0, p.speechStart < location, let role = p.role, !role.isEmpty {
                    contd[pages.count - 1] = ReaderContd(role: role, hue: p.hue)
                }
            }
            location = stop
        }
        if pages.isEmpty { pages = [NSRange(location: 0, length: 0)] }
        return ReaderLayout(string: out, framesetter: framesetter, pageSize: pageSize, style: style, pages: pages,
                            lineRanges: ranges, hueOfLine: structure.hueOfLine, hueByRole: hueByRole, contd: contd, gutter: gutterOn,
                            keepRole: keepRole)
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
        let path = CGPath(rect: CGRect(origin: .zero, size: textSize), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: r.location, length: r.length), path, nil)
        frames.setObject(FrameBox(frame), forKey: key)
        return frame
    }

    /// The script line under a point of a page (top-left origin, the text column's), or nil in the gap between lines.
    func line(at point: CGPoint, page: Int) -> Int? {
        let frame = self.frame(page)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let y = pageSize.height - point.y
        let x = point.x - Self.inset
        for (i, line) in lines.enumerated() {
            var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &asc, &desc, &lead)
            let band = ReaderLayout.band(origin: origins[i], asc: asc, desc: desc, style: style)
            guard y >= band.minY, y <= band.maxY else { continue }
            let at = CTLineGetStringIndexForPosition(line, CGPoint(x: x - origins[i].x, y: 0))
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
        /// The quiet block behind a sound cue.
        var block: CGColor
        /// The record red (the studio's outline while a cue plays or the microphone is open) and the warning color.
        var record: CGColor? = nil
        var warning: CGColor? = nil
    }

    /// How the studio outlines the current line (§2.9 rule 2).
    enum Outline: Sendable { case ink, armed, recording }

    struct Marks {
        /// The role of the part being played, or nil.
        var role: String? = nil
        var hide = false
        /// Hidden lines the person has tapped open.
        var peeked: Set<Int> = []
        /// The studio's current line (a script line index) and how it is outlined.
        var current: Int? = nil
        var outline: Outline = .ink
        /// The take state of each of my lines on the page (the studio).
        var takes: [Int: StudioCore.LineState] = [:]
    }

    /// Where a take-state mark sits after a speaker's name, in the text's own coordinates (y up from the text foot).
    struct TakeMarkSpot {
        let line: Int
        let state: StudioCore.LineState
        let glyph: CGRect
        let count: CGPoint?
        /// The name and the mark together: the button's area.
        let hit: CGRect
    }

    private var markFont: ReaderFont { ReaderFonts.sans(style.size * 0.8125, weight: .semibold) }

    /// One mark per line of mine on the page, after the speaker's name; in the gutter the name is right-aligned, so the
    /// mark sits under it when the speech goes on, else before it.
    func takeMarkSpots(page: Int, role: String, takes: [Int: StudioCore.LineState]) -> [TakeMarkSpot] {
        guard !takes.isEmpty else { return [] }
        let frame = self.frame(page)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let g = style.size * 0.8125
        var seen = Set<Int>()
        var out: [TakeMarkSpot] = []
        for (i, line) in lines.enumerated() {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                guard (attrs[NSAttributedString.Key.edInk] as? Int) == ReaderInk.speaker.rawValue,
                      (attrs[NSAttributedString.Key.edRole] as? String) == role,
                      let at = attrs[NSAttributedString.Key.edLine] as? Int, let state = takes[at], !seen.contains(at) else { continue }
                seen.insert(at)
                var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &asc, &desc, &lead)
                let rr = CTRunGetStringRange(run)
                let o = origins[i]
                let x0 = CTLineGetOffsetForStringIndex(line, rr.location, nil)
                let x1 = CTLineGetOffsetForStringIndex(line, rr.location + rr.length, nil)
                let lineEnd = CTLineGetStringRange(line).location + CTLineGetStringRange(line).length
                let beside = gutter && rr.location + rr.length + 1 < lineEnd
                let countText = state.state == .chosen ? "\(state.takes)" : nil
                let countW = countText.map { ($0 as NSString).size(withAttributes: [.font: markFont]).width + 3 } ?? 0
                let width = g + countW
                var x: CGFloat, y: CGFloat
                if !beside {
                    x = o.x + x1 + g * 0.5
                    y = o.y
                } else if i + 1 < lines.count, sameSpeech(lines[i + 1], attrs[NSAttributedString.Key.edSpeech] as? Int) {
                    x = o.x + x1 - width
                    y = origins[i + 1].y
                } else {
                    x = max(-Self.inset + 2, o.x + x0 - width - g * 0.4)
                    y = o.y
                }
                let glyph = CGRect(x: x, y: y - 1, width: g, height: g)
                let count = countText.map { _ in CGPoint(x: x + g + 3, y: y) }
                let name = CGRect(x: o.x + x0, y: o.y - desc, width: x1 - x0, height: asc + desc)
                out.append(TakeMarkSpot(line: at, state: state, glyph: glyph, count: count,
                                        hit: name.union(CGRect(x: x, y: y - desc, width: width, height: asc + desc)).insetBy(dx: -6, dy: -6)))
            }
        }
        return out
    }

    /// Whether a frame line opens inside the given speech (the mark may sit under the name only then).
    private func sameSpeech(_ line: CTLine, _ speech: Int?) -> Bool {
        guard let speech else { return false }
        let loc = CTLineGetStringRange(line).location
        guard loc < string.length else { return false }
        return (string.attributes(at: loc, effectiveRange: nil)[.edSpeech] as? Int) == speech
    }

    /// A rectangle in the text's coordinates as the page's view draws it (top-left origin, the head room above).
    func viewRect(_ r: CGRect) -> CGRect {
        CGRect(x: Self.inset + r.minX, y: Self.headRoom + pageSize.height - r.maxY, width: r.width, height: r.height)
    }

    /// Draws one page into a context whose origin is the top-left of the page's view, y down (a SwiftUI `Canvas`
    /// `Self.headRoom` tall above the text).
    func draw(page: Int, in cg: CGContext, theme: Theme, marks: Marks = Marks()) {
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.translateBy(x: Self.inset, y: Self.headRoom + pageSize.height)
        cg.scaleBy(x: 1, y: -1)
        cg.textMatrix = .identity
        let frame = self.frame(page)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        func hueColor(_ h: Int) -> CGColor { h >= 0 && h < theme.hues.count ? theme.hues[h] : theme.muted }
        let textWidth = textSize.width
        let glyphWidth = style.size * 0.8125 * 1.7

        if let head = contd[page] {
            let s = NSMutableAttributedString(string: head.role, attributes: [
                .font: ReaderFonts.sans(style.size * 0.8125, weight: .semibold),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): hueColor(head.hue),
            ])
            s.append(NSAttributedString(string: " (cont\u{2019}d)", attributes: [
                .font: ReaderFonts.sans(style.size * 0.8125, weight: .regular),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): theme.muted,
            ]))
            let ctLine = CTLineCreateWithAttributedString(s)
            cg.textPosition = CGPoint(x: gutter ? style.size * 9.5 : 0, y: pageSize.height + 8)
            CTLineDraw(ctLine, cg)
        }

        // The part's speeches: a tint across the page with a rule in its hue, one block per speech.
        struct Tint { var lo: CGFloat; var hi: CGFloat; var hue: Int; var speech: Int }
        var tints: [Tint] = []
        var info: [(asc: CGFloat, desc: CGFloat, band: CGRect)] = []
        for (i, line) in lines.enumerated() {
            var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &asc, &desc, &lead)
            let band = ReaderLayout.band(origin: origins[i], asc: asc, desc: desc, style: style)
            info.append((asc, desc, band))
            guard let me = marks.role else { continue }
            let loc = CTLineGetStringRange(line).location
            guard loc < string.length else { continue }
            let attrs = string.attributes(at: loc, effectiveRange: nil)
            guard (attrs[.edRole] as? String) == me, let speech = attrs[.edSpeech] as? Int else { continue }
            if let last = tints.last, last.speech == speech {
                tints[tints.count - 1].lo = min(last.lo, band.minY)
                tints[tints.count - 1].hi = max(last.hi, band.maxY)
            } else {
                tints.append(Tint(lo: band.minY, hi: band.maxY, hue: hueByRole[me] ?? -1, speech: speech))
            }
        }
        for t in tints {
            let c = hueColor(t.hue)
            let rect = CGRect(x: -Self.inset, y: t.lo - 3, width: textWidth + 2 * Self.inset, height: t.hi - t.lo + 6)
            cg.setFillColor(c.copy(alpha: 0.10) ?? c)
            cg.fill(rect)
            cg.setFillColor(c)
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: 3, height: rect.height))
        }

        // The studio's current line: outlined in ink, dashed record red while its cue plays, solid while the microphone is open.
        if let current = marks.current, let me = marks.role {
            var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
            for (i, line) in lines.enumerated() {
                let loc = CTLineGetStringRange(line).location
                guard loc < string.length else { continue }
                let attrs = string.attributes(at: loc, effectiveRange: nil)
                guard (attrs[.edLine] as? Int) == current, (attrs[.edRole] as? String) == me else { continue }
                lo = min(lo, info[i].band.minY)
                hi = max(hi, info[i].band.maxY)
            }
            if lo < hi {
                let rect = CGRect(x: -Self.inset + 5, y: lo - 5, width: textWidth + 2 * Self.inset - 10, height: hi - lo + 10)
                let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                cg.saveGState()
                switch marks.outline {
                case .ink:
                    cg.setStrokeColor(theme.ink)
                    cg.setLineWidth(1.5)
                case .armed:
                    cg.setStrokeColor(theme.record ?? theme.ink)
                    cg.setLineWidth(2)
                    cg.setLineDash(phase: 0, lengths: [6, 4])
                case .recording:
                    cg.setStrokeColor(theme.record ?? theme.ink)
                    cg.setLineWidth(2.5)
                }
                cg.addPath(path)
                cg.strokePath()
                cg.restoreGState()
            }
        }

        var glyph: CGImage?
        for (i, line) in lines.enumerated() {
            let origin = origins[i]
            let (asc, desc, _) = info[i]
            var hidden: [(CGFloat, CGFloat)] = []
            var block: (CGFloat, CGFloat)?
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            for run in runs {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                let rr = CTRunGetStringRange(run)
                guard attrs[NSAttributedString.Key.edBlock] != nil else { continue }
                let lead = attrs[NSAttributedString.Key.edGlyph] != nil ? glyphWidth : 0
                let x0 = CTLineGetOffsetForStringIndex(line, rr.location, nil) - lead
                let x1 = CTLineGetOffsetForStringIndex(line, rr.location + rr.length, nil)
                block = (min(block?.0 ?? x0, x0), max(block?.1 ?? x1, x1))
            }
            if let b = block {
                let rect = CGRect(x: origin.x + b.0 - 3, y: origin.y - desc - 1, width: b.1 - b.0 + 7, height: asc + desc + 2)
                cg.setFillColor(theme.block)
                cg.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
                cg.fillPath()
            }
            for run in runs {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                let inkValue = (attrs[NSAttributedString.Key.edInk] as? Int).flatMap(ReaderInk.init(rawValue:)) ?? .said
                let runLine = (attrs[NSAttributedString.Key.edLine] as? Int) ?? 0
                let role = attrs[NSAttributedString.Key.edRole] as? String
                let rr = CTRunGetStringRange(run)
                if attrs[NSAttributedString.Key.edGlyph] != nil {
                    if glyph == nil { glyph = ReaderGlyph.speaker(size: style.size * 0.8125, color: theme.muted) }
                    if let g = glyph {
                        let x0 = CTLineGetOffsetForStringIndex(line, rr.location, nil)
                        let h = style.size * 0.8125 * 0.95
                        let w = h * CGFloat(g.width) / CGFloat(g.height)
                        cg.draw(g, in: CGRect(x: origin.x + x0 - glyphWidth + 1, y: origin.y - 1, width: w, height: h))
                    }
                }
                if marks.hide, let me = marks.role, role == me, inkValue == .said, ((attrs[NSAttributedString.Key.edOffset] as? Int) ?? -1) >= 0, !marks.peeked.contains(runLine) {
                    let x0 = CTLineGetOffsetForStringIndex(line, rr.location, nil)
                    let x1 = CTLineGetOffsetForStringIndex(line, rr.location + rr.length, nil)
                    if let last = hidden.last, abs(last.1 - x0) < 6 { hidden[hidden.count - 1].1 = x1 } else { hidden.append((x0, x1)) }
                    continue
                }
                switch inkValue {
                case .said, .heading: cg.setFillColor(theme.ink)
                case .speaker: cg.setFillColor(hueColor((attrs[NSAttributedString.Key.edHue] as? Int) ?? -1))
                case .cue: cg.setFillColor(theme.ink)
                case .aside, .direction: cg.setFillColor(theme.muted)
                }
                cg.textPosition = origin
                CTRunDraw(run, cg, CFRange(location: 0, length: 0))
                if let me = marks.role, (attrs[NSAttributedString.Key.edCueRole] as? String) == me {
                    let x0 = CTLineGetOffsetForStringIndex(line, rr.location, nil)
                    let x1 = CTLineGetOffsetForStringIndex(line, rr.location + rr.length, nil)
                    cg.setFillColor(hueColor((attrs[NSAttributedString.Key.edCueHue] as? Int) ?? -1))
                    cg.fill(CGRect(x: origin.x + x0, y: origin.y - desc * 0.55, width: max(0, x1 - x0), height: 2))
                }
            }
            for span in hidden {
                let rect = CGRect(x: origin.x + span.0 - 2, y: origin.y - desc * 0.5, width: span.1 - span.0 + 4, height: (asc + desc) * 0.8)
                let h = marks.role.flatMap { hueByRole[$0] } ?? -1
                cg.setFillColor(hueColor(h).copy(alpha: 0.30) ?? hueColor(h))
                cg.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2.8, cornerHeight: rect.height / 2.8, transform: nil))
                cg.fillPath()
            }
        }

        // Each of my lines' take state after the speaker's name (§2.9 rule 3).
        if let me = marks.role {
            let hue = hueColor(hueByRole[me] ?? -1)
            for spot in takeMarkSpots(page: page, role: me, takes: marks.takes) {
                let color: CGColor
                let symbol: String
                switch spot.state.state {
                case .none: color = theme.muted; symbol = "circle"
                case .chosen: color = hue; symbol = "circle.fill"
                case .flagged: color = theme.warning ?? theme.muted; symbol = "exclamationmark.triangle.fill"
                }
                if let image = ReaderGlyph.symbol(symbol, size: style.size * 0.8125, color: color) {
                    let h = spot.glyph.height * 0.95
                    let w = h * CGFloat(image.width) / CGFloat(image.height)
                    cg.draw(image, in: CGRect(x: spot.glyph.minX, y: spot.glyph.minY, width: w, height: h))
                }
                if let at = spot.count {
                    let s = NSAttributedString(string: "\(spot.state.takes)", attributes: [
                        .font: markFont, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                    ])
                    cg.textPosition = at
                    CTLineDraw(CTLineCreateWithAttributedString(s), cg)
                }
            }
        }
    }
}

/// The parts a direction names in capitals (as the printed text sets them), longest first.
nonisolated struct DirectionNames: Sendable {
    private let regex: NSRegularExpression?

    init(roles: [String]) {
        let caps = roles.filter { $0.count >= 3 && $0 == $0.uppercased() && $0.contains { ("A"..."Z").contains($0) } }
            .sorted { $0.count > $1.count }
        if caps.isEmpty {
            regex = nil
        } else {
            let alt = caps.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            regex = try? NSRegularExpression(pattern: "(?<![\\p{L}])(?:\(alt))(?![\\p{L}])")
        }
    }

    func matches(in text: String) -> [NSTextCheckingResult] {
        regex?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? []
    }
}

/// The sound lane's speaker, an SF Symbol drawn to an image in the cue's color (the page is Core Text, which draws no symbols).
nonisolated enum ReaderGlyph {
    static let scale: CGFloat = 3

    static func speaker(size: CGFloat, color: CGColor) -> CGImage? { symbol("speaker.wave.2", size: size, color: color) }

    static func symbol(_ name: String, size: CGFloat, color: CGColor) -> CGImage? {
        #if canImport(UIKit)
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        guard let base = UIImage(systemName: name, withConfiguration: config) else { return nil }
        let tinted = base.withTintColor(UIColor(cgColor: color), renderingMode: .alwaysOriginal)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: tinted.size, format: format).image { _ in tinted.draw(at: .zero) }.cgImage
        #else
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config),
              let tint = NSColor(cgColor: color) else { return nil }
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        var rect = CGRect(origin: .zero, size: CGSize(width: base.size.width * scale, height: base.size.height * scale))
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }
}
