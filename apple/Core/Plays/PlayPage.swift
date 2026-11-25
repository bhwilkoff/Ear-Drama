import Foundation

// The Ear Drama page (docs/research/design/R2-play-typography.md, PLAYS-DESIGN §2.7 rule 10): how one script line
// is set, as plain data with no drawing. A port of the web's ReaderCore.layoutOf, isVerse and cueTail
// (js/reader-core.js), held to js/reader.test.js case for case. Every run keeps its UTF-16 offset into
// `ScriptReading.lineText`, so marks still anchor; a character the page leaves out (a printed speaker label's
// period, a direction's enclosing bracket) is simply not drawn, and a line break inside prose is drawn as the
// space it stands for.

/// One printed run of a laid-out line (`kind`, `said` and `piece` as `ScriptReading.Run`; `at` into `lineText`).
nonisolated struct PageRun: Equatable, Sendable {
    var kind: ScriptReading.RunKind
    var text: String
    var at: Int
    var piece: Int
    var said: Bool
}

/// A row: one printed verse line, the prose of a speech between cues, or a sound cue (`cue`).
nonisolated struct PageRow: Equatable, Sendable {
    var cue: Bool
    var indent: Bool
    var runs: [PageRun]
}

/// One speaker's turn: the line's own role (`name` nil, drawn from `role`, outside the printed words) or a
/// second speaker run into the line (`name` is the printed name, with its offset).
nonisolated struct PageSpeech: Equatable, Sendable {
    var role: String
    var name: PageRun?
    var rows: [PageRow]
}

nonisolated struct PageLine: Equatable, Sendable {
    /// A speech's printed breaks are verse (kept), else a transcriber's wrapping (reflowed).
    var verse = false
    /// A speech's turns; empty for a block.
    var speeches: [PageSpeech] = []
    /// A block's one row (a direction or a cue); empty for a speech.
    var rows: [PageRow] = []
}

nonisolated enum PlayPage {
    /// A page this many em wide sets the speaker's name in a gutter beside the words; narrower, over them.
    static let gutterMinEm: CGFloat = 30

    // MARK: Verse

    private static let rowSkip: Set<Character> = ["'", "\"", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}", "(", "[", "_",
                                                   "\u{2014}", "\u{2013}", "-"]

    /// The first character of a said row after any quotes, dash, bracket or italic mark.
    private static func rowStart(_ row: String) -> Character? {
        row.first { !$0.isWhitespace && !rowSkip.contains($0) }
    }

    /// Whether a speech's printed line breaks are verse: every row after a break begins with a capital, and its
    /// rows are not mostly as long as a transcriber's wrapped line (60 characters and more).
    static func isVerse(_ texts: [String]) -> Bool {
        var rows: [String] = []
        var after: [String] = []
        for t in texts {
            for (i, p) in t.components(separatedBy: "\n").enumerated() {
                rows.append(p)
                if i > 0 { after.append(p) }
            }
        }
        after = after.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !after.isEmpty else { return false }
        for r in after {
            guard let c = rowStart(r), String(c).lowercased() != String(c), c.isLetter else { return false }
        }
        let full = rows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let body = Array(full.dropLast())
        let long = body.filter { $0.utf16.count >= 60 }.count
        if !body.isEmpty, Double(long) / Double(body.count) >= 0.7 { return false }
        return full.count >= 3 || (full.first?.utf16.count ?? 0) < 50
    }

    // MARK: Cues

    private static let cueWords = try! NSRegularExpression(pattern: "^[\\s(\\[_]*(?:(?:sounds?|noises?) of\\b|music\\b)",
                                                           options: [.caseInsensitive])

    /// An aside whose words begin "sound of", "noise of" or "music" is a cue, whatever the parser called it.
    static func isCueWords(_ text: String) -> Bool {
        cueWords.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static let sentenceBreak = try! NSRegularExpression(pattern: "[.!?;:\u{2014}][\u{27}\"\u{2019}\u{201D})\\]]*\\s+(?=\\S)")

    /// The offset a speech's cue begins at: the last sentence break, or 0 when the whole speech is one sentence.
    static func cueTail(_ text: String) -> Int {
        let ns = text as NSString
        var end = ns.length
        while end > 0, isSpace(ns.character(at: end - 1)) { end -= 1 }
        var at = 0
        for m in sentenceBreak.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let stop = m.range.location + m.range.length
            if stop < end - 2 { at = stop }
        }
        return at
    }

    // MARK: Text helpers (UTF-16, so offsets match the web's)

    private static func isSpace(_ u: unichar) -> Bool {
        guard let s = Unicode.Scalar(u) else { return false }
        return s.properties.isWhitespace
    }

    private static func leadingSpace(_ s: NSString) -> Int {
        var n = 0
        while n < s.length, isSpace(s.character(at: n)) { n += 1 }
        return n
    }

    /// Replaces each break and the space after it with spaces of the same length (the offsets stay put).
    private static func flatten(_ text: String) -> String {
        let ns = text as NSString
        var out = [unichar]()
        out.reserveCapacity(ns.length)
        var inBreak = false
        for i in 0..<ns.length {
            let u = ns.character(at: i)
            if u == 10 { inBreak = true }
            if inBreak, isSpace(u) { out.append(32) } else { inBreak = false; out.append(u) }
        }
        return String(utf16CodeUnits: out, count: out.count)
    }

    /// A run's words as drawn: a transcriber's wrap, kept as spaces so offsets hold, is one space on the page.
    static func drawn(_ text: String) -> String {
        text.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
    }

    private static func slice(_ s: NSString, _ from: Int, _ to: Int? = nil) -> String {
        let end = min(to ?? s.length, s.length)
        return from >= end ? "" : s.substring(with: NSRange(location: from, length: end - from))
    }

    private static func hasLetter(_ s: String) -> Bool { s.contains { $0.isLetter } }

    private static let emphasisEnd = try! NSRegularExpression(pattern: "[.!?][\"\u{2019}\u{201D}]?\\s*$")

    // MARK: Layout

    /// How a line is set. A speech gives `speeches`: one, or more when the printed text runs a second speaker's
    /// speech into the first ("Why not?\nGRACE" then ". Never mind why.", a parser miss the page still
    /// attributes). Verse keeps a row per printed line; prose is one row, broken only by a cue. A block gives one
    /// row, its enclosing brackets left undrawn. `roles` is the script's role names.
    static func layoutOf(_ line: ScriptLine, roles: [String]) -> PageLine {
        var runs = ScriptReading.runsOf(line).map { PageRun(kind: $0.kind, text: $0.text, at: $0.at, piece: $0.piece, said: $0.said) }
        let isSpeech = line.kind == .speech && line.parts != nil
        let parts = line.parts ?? []

        // A word or three printed in italics between said words that run on in lowercase is the speaker's
        // emphasis the parser took for a direction: drawn as said, in italic.
        if isSpeech {
            var stressed = Set<Int>()
            for (i, p) in parts.enumerated() {
                guard case let .direction(text) = p, i > 0, i + 1 < parts.count,
                      case let .say(prev) = parts[i - 1], case let .say(next) = parts[i + 1] else { continue }
                let words = text.replacingOccurrences(of: "_", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: \.isWhitespace)
                let lower = next.drop { $0.isWhitespace }.first.map { String($0).lowercased() == String($0) && $0.isLetter } ?? false
                let ended = emphasisEnd.firstMatch(in: prev, range: NSRange(location: 0, length: (prev as NSString).length)) != nil
                if words.count <= 3, lower, !ended { stressed.insert(i) }
            }
            stressed.formUnion(line.em ?? [])
            for i in runs.indices where stressed.contains(runs[i].piece) { runs[i].said = true; runs[i].kind = .em }
        }
        // A direction printed wholly in italic marks ("[_Exeunt._]") is italic, not turned roman.
        var byPiece: [Int: [Int]] = [:]
        for (i, r) in runs.enumerated() where !r.said { byPiece[r.piece, default: []].append(i) }
        for idx in byPiece.values {
            let lettered = idx.filter { hasLetter(runs[$0].text) }
            let turned: ScriptReading.RunKind = isSpeechKind(line) ? .plain : .em
            if !lettered.isEmpty, lettered.allSatisfy({ runs[$0].kind == turned }) {
                for i in idx { runs[i].kind = isSpeechKind(line) ? .aside : .plain }
            }
        }

        guard isSpeech else {
            var out = runs.map { r -> PageRun in var r = r; r.text = flatten(r.text); return r }
            let src = (line.source ?? "").replacingOccurrences(of: "_", with: "")
            let ns = src as NSString
            let lead = leadingSpace(ns)
            var tail = ns.length
            while tail > 0, isSpace(ns.character(at: tail - 1)) { tail -= 1 }
            let opens = lead < ns.length && "[(".utf16.contains(ns.character(at: lead))
            let closes = tail > 0 && "])".utf16.contains(ns.character(at: tail - 1))
            let anyClose = src.contains("]") || src.contains(")")
            let bracketed = opens && (closes || !anyClose)
            if bracketed, !out.isEmpty {
                let first = out[0].text as NSString
                var n = leadingSpace(first)
                if n < first.length, "[(".utf16.contains(first.character(at: n)) {
                    n += 1
                    while n < first.length, isSpace(first.character(at: n)) { n += 1 }
                    out[0].text = slice(first, n)
                    out[0].at += n
                }
                if closes {
                    let t = out[out.count - 1].text as NSString
                    var e = t.length
                    while e > 0, isSpace(t.character(at: e - 1)) { e -= 1 }
                    if e > 0, "])".utf16.contains(t.character(at: e - 1)) {
                        e -= 1
                        while e > 0, isSpace(t.character(at: e - 1)) { e -= 1 }
                        out[out.count - 1].text = slice(t, 0, e)
                    }
                }
            }
            let cue = line.kind != .direction
            return PageLine(rows: [PageRow(cue: cue, indent: false, runs: out.filter { !$0.text.isEmpty })])
        }

        func key(_ i: Int) -> String {
            switch parts[i] {
            case .say: "say"
            case .direction: "direction"
            case .mic: "mic"
            case .sound: "sound"
            }
        }
        func isCue(_ i: Int) -> Bool {
            let k = key(i)
            return k == "sound" || (k == "direction" && isCueWords(parts[i].text))
        }
        let names = roles.filter { $0.utf16.count >= 2 }.sorted { $0.utf16.count > $1.utf16.count }
        /// The role a second speaker's name at `k + 1` of `text` is, when what follows reads as its label.
        func runIn(_ text: NSString, _ k: Int) -> String? {
            for n in names {
                let len = n.utf16.count
                guard k + 1 + len <= text.length, text.substring(with: NSRange(location: k + 1, length: len)) == n else { continue }
                let rest = slice(text, k + 1 + len) as NSString
                if leadingSpace(rest) == rest.length { return n }
                if rest.length >= 2, [46, 58].contains(rest.character(at: 0)), isSpace(rest.character(at: 1)) { return n }
            }
            return nil
        }
        func newlines(_ text: NSString, from: Int = 0) -> [Int] {
            var out: [Int] = []
            var k = text.range(of: "\n", options: [], range: NSRange(location: from, length: text.length - from)).location
            while k != NSNotFound {
                out.append(k)
                k = text.range(of: "\n", options: [], range: NSRange(location: k + 1, length: text.length - k - 1)).location
            }
            return out
        }
        // A run-in speaker's break is not a verse break.
        let said: [String] = parts.compactMap { p -> String? in
            guard case let .say(raw) = p else { return nil }
            var t = raw
            for k in newlines(raw as NSString) where runIn(t as NSString, k) != nil {
                let ns = t as NSString
                t = slice(ns, 0, k) + " " + slice(ns, k + 1)
            }
            return t
        }
        let verse = isVerse(said)

        var speeches: [PageSpeech] = []
        var rowIndex: Int?
        var rowKey: String?
        var label = false

        func startSpeech(_ role: String, _ name: PageRun?) {
            speeches.append(PageSpeech(role: role, name: name, rows: []))
            rowIndex = nil
        }
        func newRow(_ key: String?) -> Int {
            speeches[speeches.count - 1].rows.append(PageRow(cue: key != nil, indent: false, runs: []))
            rowIndex = speeches[speeches.count - 1].rows.count - 1
            rowKey = key
            return rowIndex!
        }
        func rowNow(_ key: String?) -> Int {
            if let i = rowIndex, rowKey == key { return i }
            return newRow(key)
        }
        func push(_ r: PageRun, _ text: String, _ at: Int) {
            guard !text.isEmpty else { return }
            var run = r
            run.text = text
            run.at = at
            let i = rowNow(nil)
            speeches[speeches.count - 1].rows[i].runs.append(run)
        }
        func emit(_ r: PageRun, _ text: String, _ start: Int) {
            var at = start
            if !verse { push(r, text.replacingOccurrences(of: "\n", with: " "), at); return }
            let segs = text.components(separatedBy: "\n")
            for (i, raw) in segs.enumerated() {
                var seg = raw
                if i > 0 { _ = newRow(nil) }
                let rowEmpty = rowIndex.map { speeches[speeches.count - 1].rows[$0].runs.isEmpty } ?? true
                if i > 0 || rowIndex == nil || rowEmpty {
                    let lead = leadingSpace(seg as NSString)
                    if i > 0, lead >= 2 {
                        let k = rowNow(nil)
                        speeches[speeches.count - 1].rows[k].indent = true
                    }
                    seg = slice(seg as NSString, lead)
                    at += lead
                }
                push(r, seg, at)
                at += seg.utf16.count + 1
            }
        }

        startSpeech(line.role ?? "", nil)
        for r in runs {
            if isCue(r.piece) {
                let i = rowNow("p\(r.piece)")
                var cr = r
                cr.text = flatten(r.text)
                speeches[speeches.count - 1].rows[i].runs.append(cr)
                continue
            }
            if let i = rowIndex, speeches[speeches.count - 1].rows[i].cue { rowIndex = nil }
            if !r.said { push(r, flatten(r.text), r.at); continue }
            var text = r.text
            var at = r.at
            if label {
                let ns = text as NSString
                var n = leadingSpace(ns)
                if n < ns.length, [46, 58].contains(ns.character(at: n)) { n += 1 }
                n += leadingSpace(slice(ns, n) as NSString)
                text = slice(ns, n)
                at += n
                if text.isEmpty { continue }
                label = false
            }
            // A second speaker run in: "\nNAME" at the end of the words, or "\nNAME. " before more.
            while true {
                let ns = text as NSString
                var hit: (k: Int, n: String)?
                for k in newlines(ns) {
                    if let n = runIn(ns, k) { hit = (k, n); break }
                }
                guard let h = hit else { break }
                emit(r, slice(ns, 0, h.k), at)
                startSpeech(h.n, PageRun(kind: .say, text: h.n, at: at + h.k + 1, piece: r.piece, said: false))
                let after = slice(ns, h.k + 1 + h.n.utf16.count) as NSString
                var m = 0
                if after.length > 0, [46, 58].contains(after.character(at: 0)) { m = 1 }
                m += leadingSpace(slice(after, m) as NSString)
                at += h.k + 1 + h.n.utf16.count + m
                text = slice(after, m)
                if text.isEmpty { label = true; break }
            }
            if !text.isEmpty { emit(r, text, at) }
        }
        for i in speeches.indices {
            speeches[i].rows = speeches[i].rows.filter { !$0.runs.isEmpty }
        }
        return PageLine(verse: verse, speeches: speeches)
    }

    /// A verse speech's printed lines, said words only (cues and asides left out); nil for prose or a run-in speaker
    /// (the web's `ReaderCore.verseRows`).
    static func verseRows(_ line: ScriptLine, roles: [String]) -> [String]? {
        let lay = layoutOf(line, roles: roles)
        guard lay.verse, lay.speeches.count == 1 else { return nil }
        return lay.speeches[0].rows.filter { !$0.cue }.map { row in
            row.runs.filter(\.said).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
        }.filter { !$0.isEmpty }
    }

    private static func isSpeechKind(_ line: ScriptLine) -> Bool { line.kind == .speech }
}
