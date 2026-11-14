import Foundation

// The script reader's rules (PLAYS-DESIGN §2.7, Decision 076 S0 + S1), in Core with no SwiftUI: which
// printed block opens a section, the contents, the place a line is in, search, the printed runs of a
// line, and the arithmetic of pages. The web's js/plays-core.js and js/reader-core.js are the reference;
// catalog/tests/golden/script_sections.json is run by every stack.

/// A printed heading the parser set aside (contract §4.1): verbatim, at the id of the line it opens.
nonisolated struct ScriptSection: Codable, Hashable, Sendable {
    let line: String
    let source: String
}

nonisolated enum SectionLevel: String, Sendable { case act, scene, part }

/// One section of a script in reading order. `isLine` is true when the heading is itself a stage-direction
/// line (drawn as that line); false when it is a printed heading the parser set aside (drawn before `line`).
nonisolated struct ScriptHeading: Hashable, Sendable, Identifiable {
    let line: String
    let index: Int
    var level: SectionLevel
    let title: String
    let act: String?
    let isLine: Bool
    var id: String { "\(line)/\(isLine)/\(level.rawValue)" }
}

/// A contents entry: an act or part (or a scene standing alone) with the scenes under it.
nonisolated struct ContentsEntry: Hashable, Sendable, Identifiable {
    let heading: ScriptHeading
    var scenes: [ScriptHeading]
    var id: String { heading.id }
}

nonisolated enum ScriptReading {
    // MARK: Sections

    private static let number = "(?:[IVXLC]+|\\d+|ONE|TWO|THREE|FOUR|FIVE|SIX|SEVEN|EIGHT|NINE|TEN|FIRST|SECOND|THIRD|FOURTH|"
        + "FIFTH|SIXTH|SEVENTH|EIGHTH|NINTH|TENTH|LAST|PRIMUS|SECUNDUS|TERTIUS|QUARTUS|QUINTUS)"
    private static let ordinal = "(?:FIRST|SECOND|THIRD|FOURTH|FIFTH|SIXTH|SEVENTH|EIGHTH|NINTH|TENTH|LAST)"
    private static let actPattern = try! NSRegularExpression(
        pattern: "^[\\W_]*(?:ACT(?:US)?\\.?\\s+(\(number))\\b|(?:THE\\s+)?(\(ordinal))\\s+ACT\\b)", options: [.caseInsensitive])
    private static let scenePattern = try! NSRegularExpression(
        pattern: "^[\\W_]*(?:SC(?:ENE|ENA|OENA)\\.?\\s+\(number)\\b|(?:THE\\s+)?\(ordinal)\\s+SCENE\\b)", options: [.caseInsensitive])
    private static let partPattern = try! NSRegularExpression(
        pattern: "^[\\W_]*(?:PROLOGUE|EPILOGUE|INDUCTION)[\\W_]*$", options: [.caseInsensitive])

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }

    private static func firstLine(_ text: String?) -> String {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `act`, `scene`, `part` (a prologue, epilogue or induction), or nil: the first line of the block, tested in that order.
    static func sectionLevel(_ text: String?) -> SectionLevel? {
        let f = firstLine(text)
        if matches(actPattern, f) != nil { return .act }
        if matches(scenePattern, f) != nil { return .scene }
        if matches(partPattern, f) != nil { return .part }
        return nil
    }

    /// A heading as the reader names it: its first printed line, italic marks and runs of spaces dropped.
    static func sectionTitle(_ text: String?) -> String {
        let f = firstLine(text).replacingOccurrences(of: "_", with: "")
        return f.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The act's number as printed, upper-cased ("ACT I. SCENE II." gives "I"), or nil.
    static func actKey(_ text: String?) -> String? {
        let f = firstLine(text)
        guard let m = matches(actPattern, f) else { return nil }
        for group in [1, 2] where m.range(at: group).location != NSNotFound {
            return (f as NSString).substring(with: m.range(at: group)).uppercased()
        }
        return nil
    }

    /// Every section of a script in reading order. An act heading that repeats the act in hand is a scene;
    /// a heading with no speech under it before the next one of its rank or higher is a printed list of
    /// the acts, not a place in the play, and is left out.
    static func sectionsOf(_ script: PlayScript) -> [ScriptHeading] {
        var at: [String: Int] = [:]
        for (i, line) in script.lines.enumerated() { at[line.id] = i }
        struct Draft { var heading: ScriptHeading; let order: Int }
        var drafts: [Draft] = []
        var order = 0
        for s in script.sections ?? [] {
            guard let level = sectionLevel(s.source), let index = at[s.line] else { continue }
            drafts.append(Draft(heading: ScriptHeading(line: s.line, index: index, level: level, title: sectionTitle(s.source),
                                                       act: actKey(s.source), isLine: false), order: order))
            order += 1
        }
        for (index, l) in script.lines.enumerated() where l.kind != .speech {
            guard let level = sectionLevel(l.source) else { continue }
            drafts.append(Draft(heading: ScriptHeading(line: l.id, index: index, level: level, title: sectionTitle(l.source),
                                                       act: actKey(l.source), isLine: true), order: order))
            order += 1
        }
        drafts.sort { a, b in
            if a.heading.index != b.heading.index { return a.heading.index < b.heading.index }
            if a.heading.isLine != b.heading.isLine { return !a.heading.isLine }
            return a.order < b.order
        }
        var out = drafts.map(\.heading)
        var act: String?
        for i in out.indices {
            switch out[i].level {
            case .act:
                if let current = act, let key = out[i].act, key == current { out[i].level = .scene } else { act = out[i].act }
            case .part: act = nil
            case .scene: break
            }
        }
        var speechBefore = [0]
        speechBefore.reserveCapacity(script.lines.count + 1)
        for l in script.lines { speechBefore.append(speechBefore.last! + (l.kind == .speech ? 1 : 0)) }
        func rank(_ s: ScriptHeading) -> Int { s.level == .scene ? 1 : 0 }
        var kept: [ScriptHeading] = []
        for (i, s) in out.enumerated() {
            let next = out[(i + 1)...].first { rank($0) <= rank(s) }
            let end = next?.index ?? script.lines.count
            if speechBefore[end] - speechBefore[s.index] > 0 { kept.append(s) }
        }
        return kept
    }

    /// The contents: acts (and prologues, epilogues) with their scenes; a scene before any act, or after an
    /// epilogue, stands alone.
    static func contentsOf(_ script: PlayScript) -> [ContentsEntry] { contents(from: sectionsOf(script)) }

    static func contents(from sections: [ScriptHeading]) -> [ContentsEntry] {
        var out: [ContentsEntry] = []
        var actAt: Int?
        for s in sections {
            if s.level == .act {
                out.append(ContentsEntry(heading: s, scenes: []))
                actAt = out.count - 1
            } else if s.level == .scene, let a = actAt {
                out[a].scenes.append(s)
            } else {
                out.append(ContentsEntry(heading: s, scenes: []))
                if s.level == .part { actAt = nil }
            }
        }
        return out
    }

    /// The act and the scene a line falls in, each a heading or nil.
    static func placeOf(_ contents: [ContentsEntry], lineIndex: Int) -> (act: ScriptHeading?, scene: ScriptHeading?) {
        var act: ScriptHeading?
        var scene: ScriptHeading?
        for top in contents {
            if top.heading.index > lineIndex { break }
            act = top.heading
            scene = nil
            for s in top.scenes {
                if s.index > lineIndex { break }
                scene = s
            }
        }
        return (act, scene)
    }

    // MARK: Text, search

    /// The printed words of a line as one string: a speech's pieces joined by one space, else its block.
    /// This is the string a mark anchors to (S5); never change its definition.
    static func lineText(_ line: ScriptLine) -> String {
        if line.kind == .speech, let parts = line.parts { return parts.map(\.text).joined(separator: " ") }
        return line.source ?? ""
    }

    /// Folds case, accents, curly quotes and runs of space, keeping the UTF-16 offset each folded character came from.
    static func fold(_ text: String) -> (out: [Character], from: [Int]) {
        var out: [Character] = []
        var from: [Int] = []
        var space = false
        var offset = 0
        for ch in text {
            let length = ch.utf16.count
            defer { offset += length }
            if ch.isWhitespace {
                if space { continue }
                space = true
                out.append(" ")
                from.append(offset)
                continue
            }
            space = false
            var f = String(ch).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            f = f.replacingOccurrences(of: "\u{2018}", with: "'").replacingOccurrences(of: "\u{2019}", with: "'")
                .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
            for c in f {
                out.append(c)
                from.append(offset)
            }
        }
        return (out, from)
    }

    struct Hit: Hashable, Sendable, Identifiable {
        let line: String
        let index: Int
        let role: String?
        let before: String
        let match: String
        let after: String
        var id: String { line }
    }

    /// A script's lines folded once, so each keystroke of a query only searches.
    final class SearchIndex: Sendable {
        private let lines: [(id: String, role: String?, text: String, out: [Character], from: [Int])]

        init(_ script: PlayScript) {
            lines = script.lines.map { l in
                let t = ScriptReading.lineText(l)
                let f = ScriptReading.fold(t)
                return (l.id, l.kind == .speech ? l.role : nil, t, f.out, f.from)
            }
        }

        /// Every line whose printed words hold the query; the total counts past `limit`.
        func search(_ query: String, limit: Int = 100, span: Int = 40) -> (total: Int, hits: [Hit]) {
            let q = ScriptReading.fold(query.trimmingCharacters(in: .whitespacesAndNewlines)).out
            guard q.count >= 2 else { return (0, []) }
            var hits: [Hit] = []
            var total = 0
            for (index, f) in lines.enumerated() {
                guard let at = Self.find(q, in: f.out) else { continue }
                total += 1
                if hits.count >= limit { continue }
                let start = f.from[at]
                let end = f.from[at + q.count - 1] + (f.text as NSString).rangeOfComposedCharacterSequence(at: f.from[at + q.count - 1]).length
                let ns = f.text as NSString
                let b = max(0, start - span)
                let tail = min(ns.length, end + span)
                func collapse(_ s: String) -> String {
                    var out = ""
                    var space = false
                    for c in s {
                        if c.isWhitespace {
                            if !space { out.append(" ") }
                            space = true
                        } else {
                            out.append(c)
                            space = false
                        }
                    }
                    return out
                }
                let before = collapse(ns.substring(with: NSRange(location: b, length: start - b)))
                let after = collapse(ns.substring(with: NSRange(location: end, length: tail - end)))
                hits.append(Hit(line: f.id, index: index, role: f.role,
                                before: (b > 0 ? "\u{2026}" : "") + String(before.drop(while: { $0 == " " })),
                                match: collapse(ns.substring(with: NSRange(location: start, length: end - start))),
                                after: String(after.reversed().drop(while: { $0 == " " }).reversed()) + (end + span < ns.length ? "\u{2026}" : "")))
            }
            return (total, hits)
        }

        private static func find(_ needle: [Character], in hay: [Character]) -> Int? {
            guard !needle.isEmpty, hay.count >= needle.count else { return nil }
            let first = needle[0]
            var i = 0
            let last = hay.count - needle.count
            while i <= last {
                if hay[i] == first {
                    var k = 1
                    while k < needle.count, hay[i + k] == needle[k] { k += 1 }
                    if k == needle.count { return i }
                }
                i += 1
            }
            return nil
        }
    }

    static func searchScript(_ script: PlayScript, _ query: String, limit: Int = 100, span: Int = 40) -> (total: Int, hits: [Hit]) {
        SearchIndex(script).search(query, limit: limit, span: span)
    }

    // MARK: A part's lines, open parts

    /// A part's lines in reading order, as indexes into `script.lines`.
    static func lineIndexes(of part: PartID, in script: PlayScript) -> [Int] {
        script.lines.indices.filter { script.lines[$0].part == part }
    }

    /// The first of `part`'s lines after `index` (direction 1) or before it (-1), or nil when none.
    static func nextLine(of part: PartID, after index: Int, direction: Int = 1, in script: PlayScript) -> Int? {
        let mine = lineIndexes(of: part, in: script)
        if direction > 0 { return mine.first { $0 > index } }
        return mine.last { $0 < index }
    }

    /// The speaking parts of a production still open (never sound effects or stage directions).
    static func openSpeakingParts(_ p: Production, script: PlayScript? = nil) -> [PartID] {
        let ids = script.map { $0.castParts.map(\.id) } ?? p.parts.keys.sorted()
        return ids.filter { $0.isSpeaking && p.state(of: $0).status == .open }
    }

    /// The same, for a shared production's record; a part the record does not list is open.
    static func openSpeakingParts(_ r: SharedRecord, script: PlayScript? = nil) -> [PartID] {
        let ids = script.map { $0.castParts.map(\.id) } ?? r.parts.keys.sorted().map { PartID(rawValue: $0) }
        return ids.filter { $0.isSpeaking && r.part($0).status == .open }
    }

    // MARK: Runs

    enum RunKind: Int, Sendable { case say, em, aside, plain }

    /// One printed run of a line: `at` is its offset into `lineText` (UTF-16, the string a mark anchors to).
    struct Run: Equatable, Sendable {
        let kind: RunKind
        let text: String
        let at: Int
        let piece: Int
        let said: Bool
    }

    /// A line as printed runs. A speech's pieces are `say` (the words) or `aside` (a printed direction inside
    /// it); a block's text is `plain`, its `_italic_` marks drawn as `em` and never shown.
    static func runsOf(_ line: ScriptLine) -> [Run] {
        var runs: [Run] = []
        func split(_ text: String, _ start: Int, _ piece: Int, said: Bool, base: RunKind, flipped: RunKind) {
            var at = start
            var on = false
            for seg in text.components(separatedBy: "_") {
                if !seg.isEmpty { runs.append(Run(kind: on ? flipped : base, text: seg, at: at, piece: piece, said: said)) }
                at += seg.utf16.count + 1
                on.toggle()
            }
        }
        if line.kind == .speech, let parts = line.parts {
            var at = 0
            for (i, piece) in parts.enumerated() {
                if i > 0 { at += 1 }
                switch piece {
                case let .say(t): split(t, at, i, said: true, base: .say, flipped: .em)
                default: split(piece.text, at, i, said: false, base: .aside, flipped: .plain)
                }
                at += piece.text.utf16.count
            }
            return runs
        }
        split(line.source ?? "", 0, 0, said: false, base: .plain, flipped: .em)
        return runs
    }

    private static let noSpaceBefore = Set(".,;:!?)]\u{2019}\u{201D}\u{2026}\u{2014}-")
    private static let noSpaceAfter = Set("([\u{201C}\u{2018}\u{2014}-")

    /// Whether a space is drawn between two printed pieces: not before closing punctuation, not after an opening one.
    static func spaceBetween(_ before: String, _ after: String) -> Bool {
        if let f = after.first, noSpaceBefore.contains(f) { return false }
        if let l = before.last, noSpaceAfter.contains(l) { return false }
        return true
    }
}

// MARK: - The reader's settings and arithmetic

nonisolated struct ReaderPrefs: Codable, Equatable, Sendable {
    enum Layout: String, Codable, Sendable, CaseIterable { case pages, scroll }
    enum Spacing: String, Codable, Sendable, CaseIterable { case tight, normal, loose }

    var layout: Layout = .pages
    var size: Int = ReaderMath.defaultSize
    var spacing: Spacing = .normal

    /// Settings as stored (or not): anything unknown falls back to the default. Pages by default (owner, Decision 076).
    static func normalized(_ raw: Any?) -> ReaderPrefs {
        guard let p = raw as? [String: Any] else { return ReaderPrefs() }
        var out = ReaderPrefs()
        if let s = p["layout"] as? String, let l = Layout(rawValue: s) { out.layout = l }
        if let n = p["size"] as? Int, n >= 0, n < ReaderMath.sizes.count { out.size = n }
        if let s = p["spacing"] as? String, let sp = Spacing(rawValue: s) { out.spacing = sp }
        return out
    }

    static func decode(_ json: String?) -> ReaderPrefs {
        guard let data = json?.data(using: .utf8), let raw = try? JSONSerialization.jsonObject(with: data) else { return ReaderPrefs() }
        return normalized(raw)
    }

    var json: String { (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "{}" }

    var scale: Double { ReaderMath.sizes[size] }
    var lineHeight: Double { ReaderMath.spacing[spacing]! }
}

nonisolated enum ReaderMath {
    /// Text size steps, as a share of the reading body size; the third is the default.
    static let sizes: [Double] = [0.875, 0.9375, 1, 1.125, 1.25, 1.5, 1.75]
    static let defaultSize = 2
    /// Line spacing as a line height, in multiples of the type size.
    static let spacing: [ReaderPrefs.Spacing: Double] = [.tight: 1.35, .normal: 1.55, .loose: 1.8]
    /// Two facing pages once the reading area is this wide (points).
    static let spreadMin: CGFloat = 900

    /// How many pages one screen shows: two from `spreadMin`, else one.
    static func perSpread(_ width: CGFloat) -> Int { width >= spreadMin ? 2 : 1 }

    /// The reading position on a page: the first line still showing on it, which is the line carried over
    /// from the page before when there is one (so a restore never skips words). -1 when none.
    static func lineAtPage(starts: [Int], ends: [Int], page: Int) -> Int {
        for i in ends.indices {
            if ends[i] >= page && starts[i] <= page { return i }
            if starts[i] > page { return i }
        }
        return ends.isEmpty ? -1 : ends.count - 1
    }

    /// The first page of the screen that shows `page`: spreads begin on even pages.
    static func spreadStart(_ page: Int, per: Int) -> Int { page / per * per }

    /// Where a turn lands: one screen on or back, never past the first or the last.
    static func turn(_ page: Int, delta: Int, per: Int, count: Int) -> Int {
        let last = spreadStart(max(0, count - 1), per: per)
        return min(last, max(0, spreadStart(page, per: per) + delta * per))
    }

    /// A finished drag: -1 back, 1 on, 0 stay. Past a fifth of the width, or a flick (30 pt at 0.4 pt/ms).
    static func swipeTurn(dx: Double, ms: Double, width: Double) -> Int {
        let fast = abs(dx) >= 30 && abs(dx) / max(1, ms) >= 0.4
        if abs(dx) < width / 5 && !fast { return 0 }
        return dx < 0 ? 1 : -1
    }

    enum Zone: Equatable, Sendable { case prev, middle, next }

    /// A tap on the page: the outer fifth of either edge turns, the middle does not.
    static func tapZone(x: Double, width: Double) -> Zone {
        if x < width / 5 { return .prev }
        if x > width * 4 / 5 { return .next }
        return .middle
    }

    enum KeyTurn: Equatable, Sendable { case by(Int), first, last, none }

    /// The keys that turn a page (pedals send arrows or Page Up/Down).
    static func keyTurn(_ key: String, shift: Bool = false) -> KeyTurn {
        switch key {
        case "ArrowRight", "ArrowDown", "PageDown": return .by(1)
        case "ArrowLeft", "ArrowUp", "PageUp": return .by(-1)
        case " ": return .by(shift ? -1 : 1)
        case "Home": return .first
        case "End": return .last
        default: return .none
        }
    }

    /// "12 of 140", or "12\u{2013}13 of 140" for a spread.
    static func pageLabel(page: Int, per: Int, count: Int) -> String {
        let a = page + 1
        let b = min(count, page + per)
        return b > a ? "\(a)\u{2013}\(b) of \(count)" : "\(a) of \(count)"
    }

    /// Positions kept per script: newest first, at most `keep`; an update keeps the fields it does not carry.
    static func remember(_ store: [ReaderPosition], _ entry: ReaderPosition, keep: Int = 60) -> [ReaderPosition] {
        var merged = store.first { $0.id == entry.id } ?? ReaderPosition(id: entry.id)
        if let line = entry.line { merged.line = line }
        if let part = entry.part { merged.part = part }
        return [merged] + store.filter { $0.id != entry.id }.prefix(keep - 1)
    }
}

/// Where a person was in a script and which part they were playing, kept per script on this device.
nonisolated struct ReaderPosition: Codable, Equatable, Sendable {
    let id: String
    var line: String?
    var part: String?
}
