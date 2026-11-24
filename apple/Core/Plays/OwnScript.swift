// Own scripts (Decision 088.3; docs/research/design/R4-record-anything.md, R4-core-port-brief.md): a port of
// js/own-core.js and its Kotlin twin OwnScript.kt, function for function and rule for rule, held to
// catalog/tests/golden/own_script_{parse,ops}.json and ear_cast_lines.json (OwnScriptTests).
//
// PURE: no screen, no storage, no network, no clock. Offsets are UTF-16 code units of a line's text, so every
// rule reads a [UInt16] and never a Character or a String.Index (Swift `==` on strings is canonical equivalence
// and would hide an un-normalized text; sets and comparisons here are over unit arrays). No regular expression
// decides a rule: a row is read by the character, and the only classes are single scalars
// (Unicode.Scalar.Properties.generalCategory). A name's cap while reading is 30 code points, a part's stored
// name 40 UTF-16 units, bytes are UTF-8. Never edit a golden by hand: change the rule in js/own-core.js, all three
// ports and the golden in one change set.

import CryptoKit
import Foundation

nonisolated struct OwnSpan: Equatable, Sendable {
    var start: Int64
    var end: Int64
}

/// Who a line is cast to by ear: a part, or left out.
nonisolated enum OwnWho: Equatable, Sendable {
    case role(String)
    case out
}

/// One line of a doc being corrected. `k` is its key while it is edited, `id` nil until `OwnScript.done`.
nonisolated struct OwnLine: Equatable, Sendable {
    var k: Int = 0
    var id: String?
    var kind: String
    var role: String?
    var text: String
    var label: String?
    var at: OwnSpan?
    var mark: OwnWho?
}

/// A doc is plain data, never changed in place: `OwnScript.apply` returns a new one. `undo` holds the earlier
/// `lines` arrays themselves (copy on write), not copies.
nonisolated struct OwnDoc: Equatable, Sendable {
    var lines: [OwnLine]
    var nextKey: Int
    var letters: [String: Int] = [:]
    var heard: [Int] = []
    var undo: [[OwnLine]] = []
}

nonisolated enum OwnPiece: Equatable, Sendable {
    case say(String)
    case direction(String)

    var text: String {
        switch self {
        case .say(let t), .direction(let t): return t
        }
    }
}

nonisolated enum OwnOpKind: String, Sendable {
    case assign, split, join, words, leaveOut, add, rename, notPart, undo, unknown
}

nonisolated enum OwnTarget: Equatable, Sendable {
    case role(String)
    case kind(String)
}

/// One change on the parts page; see `OwnScript.apply`.
nonisolated struct OwnOp: Sendable {
    var op: OwnOpKind
    var line: Int?
    var at: Int?
    var text: String = ""
    var to: OwnTarget?
    var after: Int?
    var kind: String = ""
    var role: String = ""
    var part: String = ""
    var rename: String = ""
}

nonisolated struct OwnEnv: Sendable {
    var takes: Set<String> = []
    var shared = false
}

nonisolated enum OwnRefusal: String, Sendable {
    case shared, nothing_to_undo, no_such_part, part_has_take, no_such_line, too_many_lines, empty, too_long
    case bad_name, line_has_take, bad_kind, no_line_above, no_such_op
    case bad_id, no_title, title_too_long, no_lines, bad_line_id, bad_part, bad_line, no_parts
}

nonisolated struct OwnResult: Sendable {
    var doc: OwnDoc
    var refusal: OwnRefusal?
}

nonisolated struct OwnParsed: Equatable, Sendable {
    var text: String
    var lines: [OwnLine]
    var parts: [OwnPart]
}

nonisolated struct OwnPart: Equatable, Sendable {
    var name: String
    var lines: Int
}

nonisolated struct OwnLabel: Equatable, Sendable {
    var form: String
    var name: String
    var key: String
    var label: String
    var text: String
    var bare: Bool
}

nonisolated struct OwnCue: Equatable, Sendable {
    var text: String
    var at: OwnSpan?
}

nonisolated struct OwnMeta: Sendable {
    var id: String
    var title: String
    var episodeId: String?
    var episodeUrl: String?
}

/// Plain JSON data: what a castable script is, and what is hashed. Keys sort by UTF-16 unit when written.
nonisolated indirect enum OwnJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case string(String)
    case array([OwnJSON])
    case object([String: OwnJSON])

    subscript(key: String) -> OwnJSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

nonisolated enum OwnScript {
    static let maxBytes = 400_000
    static let maxLines = 6000
    static let maxPartName = 40
    static let maxTitle = 300
    private static let maxNamePoints = 30

    typealias U = [UInt16]

    // MARK: Units

    @inline(__always) private static func u(_ s: String) -> U { Array(s.utf16) }
    @inline(__always) private static func str(_ a: U) -> String { String(decoding: a, as: UTF16.self) }
    private static func words(_ s: String) -> Set<U> { Set(s.split(separator: " ").map { u(String($0)) }) }

    /// JavaScript's slice for non-negative bounds: clamped, empty when backwards.
    private static func sl(_ s: U, _ a: Int, _ b: Int? = nil) -> U {
        let x = min(max(a, 0), s.count)
        let y = min(max(b ?? s.count, 0), s.count)
        return x >= y ? [] : Array(s[x..<y])
    }

    private static func cpAt(_ s: U, _ i: Int) -> Int {
        if i < 0 || i >= s.count { return -1 }
        let a = Int(s[i])
        if a >= 0xd800 && a <= 0xdbff && i + 1 < s.count {
            let b = Int(s[i + 1])
            if b >= 0xdc00 && b <= 0xdfff { return 0x10000 + ((a - 0xd800) << 10) + (b - 0xdc00) }
        }
        return a
    }

    private static func codePointBefore(_ s: U, _ i: Int) -> Int {
        if i <= 0 { return -1 }
        let b = Int(s[i - 1])
        if b >= 0xdc00 && b <= 0xdfff && i >= 2 {
            let a = Int(s[i - 2])
            if a >= 0xd800 && a <= 0xdbff { return 0x10000 + ((a - 0xd800) << 10) + (b - 0xdc00) }
        }
        return b
    }

    @inline(__always) private static func width(_ cp: Int) -> Int { cp > 0xffff ? 2 : 1 }
    @inline(__always) private static func at(_ s: U, _ p: Int, _ c: UInt16) -> Bool { p >= 0 && p < s.count && s[p] == c }
    private static func eq(_ a: String?, _ b: String?) -> Bool { a.map(u) == b.map(u) }

    private static func startsWith(_ s: U, _ prefix: U, _ p: Int = 0) -> Bool {
        if p < 0 || p + prefix.count > s.count { return false }
        for i in 0..<prefix.count where s[p + i] != prefix[i] { return false }
        return true
    }

    private static func endsWith(_ s: U, _ c: UInt16) -> Bool { s.last == c }

    private static func contains(_ s: U, _ c: UInt16) -> Bool { s.contains(c) }

    private static func cpCount(_ s: U) -> Int {
        var n = 0
        var i = 0
        while i < s.count { i += width(cpAt(s, i)); n += 1 }
        return n
    }

    private static func cps(_ s: U) -> [Int] {
        var out: [Int] = []
        var i = 0
        while i < s.count { let c = cpAt(s, i); out.append(c); i += width(c) }
        return out
    }

    private static func utf8Count(_ s: U) -> Int {
        var n = 0
        var i = 0
        while i < s.count {
            let c = Int(s[i])
            if c < 0x80 { n += 1 } else if c < 0x800 { n += 2 } else if c >= 0xd800 && c <= 0xdbff && i + 1 < s.count { n += 4; i += 1 } else { n += 3 }
            i += 1
        }
        return n
    }

    // MARK: Characters, one code point at a time

    private static let UPPER = 1
    private static let LOWER = 2
    private static let LETTER = 4
    private static let MARK = 8
    private static let DIGIT = 16

    private static func classOf(_ cp: Int) -> Int {
        guard cp >= 0, let sc = Unicode.Scalar(UInt32(cp)) else { return 0 }
        switch sc.properties.generalCategory {
        case .uppercaseLetter, .titlecaseLetter: return UPPER | LETTER
        case .lowercaseLetter: return LOWER | LETTER
        case .modifierLetter, .otherLetter: return LETTER
        case .nonspacingMark, .spacingMark, .enclosingMark: return MARK
        case .decimalNumber: return DIGIT
        default: return 0
        }
    }

    private static func isC(_ cp: Int, _ mask: Int) -> Bool { cp >= 0 && (classOf(cp) & mask) != 0 }

    private static let SPACE: UInt16 = 32
    private static let TAB: UInt16 = 9
    private static let NL: UInt16 = 10
    @inline(__always) private static func isGap(_ u: UInt16) -> Bool { u == SPACE || u == TAB }
    @inline(__always) private static func isBlankUnit(_ u: UInt16) -> Bool { u == SPACE || u == TAB || u == NL }

    static func trim(_ s: U) -> U {
        var a = 0
        var b = s.count
        while a < b && isBlankUnit(s[a]) { a += 1 }
        while b > a && isBlankUnit(s[b - 1]) { b -= 1 }
        return (a == 0 && b == s.count) ? s : Array(s[a..<b])
    }

    /// Space, tab and line breaks only: never a locale's idea of white space.
    static func trim(_ s: String) -> String { str(trim(u(s))) }

    private static func skipGap(_ s: U, _ p0: Int) -> Int {
        var p = p0
        while p < s.count && isGap(s[p]) { p += 1 }
        return p
    }

    /// Words between runs of spaces, tabs and line breaks.
    private static func wordsOf(_ s: U) -> [U] {
        var out: [U] = []
        var from = -1
        for i in 0...s.count {
            let gap = i == s.count || isBlankUnit(s[i])
            if !gap && from < 0 { from = i } else if gap && from >= 0 { out.append(Array(s[from..<i])); from = -1 }
        }
        return out
    }

    static func wordsOf(_ s: String) -> [String] { wordsOf(u(s)).map(str) }

    static func utf8Length(_ s: String) -> Int { s.utf8.count }

    private static func splitRows(_ s: U) -> [U] {
        var out: [U] = []
        var from = 0
        for i in 0..<s.count where s[i] == NL { out.append(Array(s[from..<i])); from = i + 1 }
        out.append(Array(s[from...]))
        return out
    }

    private static func joinRows(_ rows: ArraySlice<U>) -> U {
        var out = U()
        for (i, r) in rows.enumerated() { if i > 0 { out.append(NL) }; out.append(contentsOf: r) }
        return out
    }

    // MARK: Normalizing a text

    private static func dropped(_ u: Int) -> Bool {
        u < 9 || u == 14 || u == 15 || (u >= 16 && u <= 31) || (u >= 0x7f && u <= 0x9f && u != 0x85) || u == 0xad || u == 0x200b ||
            u == 0x200e || u == 0x200f || u == 0x2060 || u == 0xfeff || (u >= 0x202a && u <= 0x202e) || (u >= 0x2066 && u <= 0x2069)
    }

    private static func newline(_ u: Int) -> Bool { u == 10 || u == 11 || u == 12 || u == 13 || u == 0x85 || u == 0x2028 || u == 0x2029 }
    private static func wideSpace(_ u: Int) -> Bool { u == 0xa0 || u == 0x1680 || (u >= 0x2000 && u <= 0x200a) || u == 0x202f || u == 0x205f || u == 0x3000 }

    /// The text every rule reads and every line slices: line ends one `\n`, every other space one U+0020 (a tab stays),
    /// unseen characters dropped, a lone surrogate U+FFFD, NFC, then the pairs that mark italics and bold dropped.
    static func normalize(units t: U) -> U {
        var out = U()
        out.reserveCapacity(t.count)
        let n = t.count
        var i = 0
        while i < n {
            let c = Int(t[i])
            if c >= 32 && c < 0x7f { out.append(t[i]); i += 1; continue }
            if c >= 0xd800 && c <= 0xdbff {
                let v = i + 1 < n ? Int(t[i + 1]) : 0
                if v >= 0xdc00 && v <= 0xdfff { out.append(t[i]); out.append(t[i + 1]); i += 2; continue }
                out.append(0xfffd)
            } else if c >= 0xdc00 && c <= 0xdfff { out.append(0xfffd) }
            else if newline(c) { if !(c == 13 && i + 1 < n && t[i + 1] == 10) { out.append(NL) } }
            else if wideSpace(c) { out.append(SPACE) }
            else if dropped(c) { }
            else { out.append(t[i]) }
            i += 1
        }
        if out.contains(where: { $0 >= 0x300 }) {
            out = u(str(out).precomposedStringWithCanonicalMapping)
        }
        return unmark(out)
    }

    static func normalize(_ raw: String?) -> String { str(normalize(units: u(raw ?? ""))) }

    @inline(__always) private static func asciiWord(_ u: Int) -> Bool { (u >= 48 && u <= 57) || (u >= 65 && u <= 90) || (u >= 97 && u <= 122) }

    /// Drops one `_` that does not join two ASCII letters or digits, and `**`. A run of any other length is the writer's own.
    private static func unmark(_ t: U) -> U {
        if !t.contains(where: { $0 == 95 || $0 == 42 }) { return t }
        var out = U()
        out.reserveCapacity(t.count)
        var from = 0
        var i = 0
        while i < t.count {
            let c = t[i]
            if c != 95 && c != 42 { i += 1; continue }
            var j = i + 1
            while j < t.count && t[j] == c { j += 1 }
            let n = j - i
            let inner = i > 0 && j < t.count && asciiWord(Int(t[i - 1])) && asciiWord(Int(t[j]))
            if (c == 95 && n == 1 && !inner) || (c == 42 && n == 2) { out.append(contentsOf: t[from..<i]); from = j }
            i = j
        }
        out.append(contentsOf: t[from...])
        return out
    }

    // MARK: Names

    private static let NOT_NAME = words(
        "ACT SCENE SCENES NOTE NOTES CAST DATE TITLE BY AUTHOR WRITTEN SETTING TIME PLACE CHARACTERS COPYRIGHT END " +
            "FINIS DRAMATIS PERSONS SYNOPSIS COSTUMES PROPERTIES SCENERY CURTAIN FADE CUT TRANSCRIBED SOURCE SERIES PROGRAM PRODUCTION " +
            "HTTP HTTPS AT FOOTNOTE FOOTNOTES APPENDIX INDEX CONTENTS CHAPTER ILLUSTRATION TABLEAU ENTER EXIT EXEUNT")
    private static let COMMON = words(
        "NO YES OH AH O WELL AY AYE NAY YEA INDEED TRUE NEVER GOOD HUSH COME STOP WHY WHAT NOW SO THEN THERE HERE THIS " +
            "THAT HOW WHERE WHEN WHO AGAIN NOTHING EVERYTHING PERHAPS EXACTLY CERTAINLY SURELY THANKS PLEASE SILENCE PAUSE")
    private static let COMMON_MIXED = words("I IT HE SHE WE YOU THEY SIR MADAM PEACE MANET FLOURISH SENNET ALARUM ALARUMS")
    private static let TITLES = words("MR MRS MS DR ST LT CAPT COL GEN SGT REV PROF MME MLLE M MM MESSRS")
    private static let SMALL = words("of the and in with on at to a an de la le von van der du del")
    private static let WORD_NUMBERS = words(
        "ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN FIRST SECOND THIRD FOURTH FIFTH SIXTH SEVENTH EIGHTH " +
            "NINTH TENTH LAST PRIMUS SECUNDUS TERTIUS QUARTUS QUINTUS PRIMA SECUNDA TERTIA QUARTA QUINTA SEXTA SEPTIMA OCTAVA NONA DECIMA")
    private static let ROMAN: Set<U> = {
        var s = Set<U>()
        for tens in ["", "X", "XX", "XXX"] {
            for ones in ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"] where !(tens + ones).isEmpty { s.insert(u(tens + ones)) }
        }
        return s
    }()
    private static let ABBREVIATIONS = words("Mr Mrs Ms Dr St Col Capt Lt Gen Sgt Prof Rev")

    /// ASCII letters to capitals, every other character as it is, so offsets never move.
    private static func asciiUpper(_ s: U) -> U { s.map { $0 >= 97 && $0 <= 122 ? $0 - 32 : $0 } }

    /// A part's name as stored: one space between words, straight apostrophes, capitals, no label punctuation at its ends.
    private static func partName(_ raw: U) -> U {
        var s0 = U()
        for (i, w) in wordsOf(raw).enumerated() { if i > 0 { s0.append(SPACE) }; s0.append(contentsOf: w) }
        s0 = s0.map { $0 == 0x2018 || $0 == 0x2019 ? 39 : $0 }
        func edge(_ c: UInt16) -> Bool { c == 32 || c == 46 || c == 58 || c == 64 || c == 95 || c == 94 || c == 0xff1a }
        var a = 0
        var b = s0.count
        while a < b && edge(s0[a]) { a += 1 }
        while b > a && edge(s0[b - 1]) { b -= 1 }
        return u(str(Array(s0[a..<b])).uppercased())
    }

    static func partName(_ raw: String) -> String { str(partName(u(raw))) }

    /// nil when a part may be called this (already through `partName`), or why not: empty, too_long, bad_name.
    static func partNameRefusal(_ name: String?) -> OwnRefusal? {
        guard let name, !name.isEmpty else { return .empty }
        let a = u(name)
        if a.count > maxPartName { return .too_long }
        for c in a where c < 32 || c == 127 || (c >= 0x200b && c <= 0x200f) || (c >= 0x2028 && c <= 0x202e) { return .bad_name }
        return nil
    }

    private static func isCaps(_ name: U) -> Bool {
        var upper = false
        for w in wordsOf(name) {
            var s = w
            for p in [u("Mac"), u("Mc")] where startsWith(s, p) && s.count > p.count && isC(cpAt(s, p.count), UPPER) {
                s = Array(s[p.count...])
                break
            }
            for cp in cps(s) {
                if isC(cp, LOWER) { return false }
                if isC(cp, UPPER) { upper = true }
            }
        }
        return upper
    }

    private static func isTitled(_ name: U) -> Bool {
        let ws = wordsOf(name)
        if ws.isEmpty { return false }
        for (i, w) in ws.enumerated() {
            let cp = cpAt(w, 0)
            let ok: Bool
            if isC(cp, UPPER) || (isC(cp, LETTER) && !isC(cp, LOWER)) { ok = true }
            else if i == 0 { ok = ws.count > 1 && isC(cp, DIGIT) }
            else { ok = isC(cp, DIGIT) || w[0] == 35 || w[0] == 38 || SMALL.contains(w) }
            if !ok { return false }
        }
        return true
    }

    private static func hasLower(_ s: U) -> Bool { cps(s).contains { isC($0, LOWER) } }

    private static func nameOK(_ name: U, _ maxWords: Int = 4) -> Bool {
        let key = partName(name)
        let ws = wordsOf(key)
        if ws.isEmpty || ws.count > maxWords || key.count > maxPartName { return false }
        for i in 0..<(ws.count - 1) {
            let w = ws[i]
            if endsWith(w, 46) && !TITLES.contains(Array(w.dropLast())) && cpCount(w) != 2 && ws[i + 1] != u("OF") && !isC(cpAt(ws[i + 1], 0), DIGIT) { return false }
        }
        var head = ws[0]
        while endsWith(head, 46) || endsWith(head, 39) { head.removeLast() }
        if NOT_NAME.contains(head) || key == u("THE END") { return false }
        if ws[0] == u("PAGE") && ws.count > 1 && isC(cpAt(ws[1], 0), DIGIT) { return false }
        return cps(key).contains { isC($0, LETTER) }
    }

    /// The end (exclusive) of the bracket opening at `p`, counting nested ones of its kind, or -1.
    private static func bracketEnd(_ s: U, _ p: Int) -> Int {
        let open = s[p]
        let close: UInt16 = open == 40 ? 41 : 93
        var depth = 0
        for i in p..<s.count {
            let c = s[i]
            if c == open { depth += 1 } else if c == close { depth -= 1; if depth == 0 { return i + 1 } }
        }
        return -1
    }

    private static func opensBracket(_ s: U, _ p: Int) -> Bool { p < s.count && (s[p] == 40 || s[p] == 91) }

    private enum Form: String, CaseIterable { case colon, dot, gap, alone, mixed }

    private struct Lab {
        var form: Form
        var name: U
        var key: U
        var label: U
        var text: U
        var bare: Bool
    }

    private static func nameChar(_ cp: Int) -> Bool {
        isC(cp, LETTER | MARK | DIGIT) || cp == 46 || cp == 39 || cp == 0x2019 || cp == 0x2018 || cp == 38 || cp == 35 || cp == 45 || cp == 47 || cp == 32 || cp == 0xfffd
    }

    private static func skipDash(_ s: U, _ p0: Int) -> Int {
        var p = p0
        if startsWith(s, [45, 45], p) { while at(s, p, 45) { p += 1 }; return p }
        return (at(s, p, 0x2014) || at(s, p, 0x2013)) ? p + 1 : p
    }

    /// The label a row opens with, read every way a label is printed, best first. `s` is trimmed.
    private static func labels(_ s: U) -> [Lab] {
        var i = 0
        if at(s, 0, 64) { i = 1 }
        let first = cpAt(s, i)
        if first < 0 || !(isC(first, LETTER | DIGIT) && !isC(first, LOWER)) { return [] }
        var found: [Form: Lab] = [:]
        var held: [Form: Lab] = [:]
        var points = 0
        var e = i
        while e < s.count && points < maxNamePoints {
            let cp = cpAt(s, e)
            if !nameChar(cp) { break }
            e += width(cp)
            points += 1
            if cp == 32 { continue }
            ends(s, i, e, &found, &held)
        }
        var out: [Lab] = []
        for store in [found, held] { for f in Form.allCases { if let l = store[f] { out.append(l) } } }
        return out
    }

    static func labels(_ row: String) -> [OwnLabel] {
        labels(u(row)).map { OwnLabel(form: $0.form.rawValue, name: str($0.name), key: str($0.key), label: str($0.label), text: str($0.text), bare: $0.bare) }
    }

    private static func couldEnd(_ s: U, _ e: Int) -> Bool {
        let r = skipGap(s, e)
        if r >= s.count { return true }
        let c = s[r]
        return c == 58 || c == 0xff1a || c == 40 || c == 91 || c == 94 || at(s, e, 46) || at(s, e, 44) || (c == 46 && r > e) || r - e >= 3 ||
            s[e..<r].contains(TAB)
    }

    private static func ends(_ s: U, _ i: Int, _ e: Int, _ found: inout [Form: Lab], _ held: inout [Form: Lab]) {
        if !couldEnd(s, e) { return }
        let name = sl(s, i, e)
        if !nameOK(name) { return }
        let key = partName(name)
        let ws = wordsOf(key)
        let caps = isCaps(name)
        let titled = !caps && isTitled(name)
        let numeral = ROMAN.contains(key)
        let last = ws[ws.count - 1]
        let maybe = TITLES.contains(last) || cpCount(last) == 1
        var d = U()
        var p = e
        let q = skipGap(s, at(s, e, 44) ? e + 1 : e)
        if opensBracket(s, q) {
            let end = bracketEnd(s, q)
            if end > 0 { d = sl(s, q, end); p = end }
        }
        func put(_ isFound: Bool, _ form: Form, _ atIdx: Int, _ rest: U, _ found: inout [Form: Lab], _ held: inout [Form: Lab]) {
            if isFound && found[form] != nil { return }
            let said = trim(rest)
            var text = said
            if !d.isEmpty { text = said.isEmpty ? d : d + [SPACE] + said }
            let lab = Lab(form: form, name: name, key: key, label: d.isEmpty ? trim(sl(s, 0, atIdx)) : name, text: text, bare: said.isEmpty)
            if isFound { found[form] = lab } else { held[form] = lab }
        }
        let r = skipGap(s, p)

        if at(s, r, 58) || at(s, r, 0xff1a) {
            let rest = sl(s, r + 1)
            let ratio = r == e && isC(cpAt(s, e - 1), DIGIT) && isC(cpAt(rest, 0), DIGIT)
            if !startsWith(rest, [47, 47]) && !ratio { put(true, .colon, r + 1, rest, &found, &held) }
        }
        if numeral || COMMON.contains(key) { return }

        if caps || (titled && ws.count <= 3 && !COMMON_MIXED.contains(key)) {
            let form: Form = caps ? .dot : .mixed
            if at(s, p, 46) {
                let g = skipGap(s, p + 1)
                let t = skipDash(s, g)
                if t < s.count && (t > p + 1 || opensBracket(s, t)) {
                    if !maybe || !d.isEmpty { put(true, form, p + 1, sl(s, t), &found, &held) }
                    else if caps || !TITLES.contains(last) { put(false, form, p + 1, sl(s, t), &found, &held) }
                }
            } else if !d.isEmpty && caps {
                let t = skipDash(s, r)
                if t < s.count && !at(s, t, 58) && !at(s, t, 0xff1a) && !at(s, t, 46) { put(true, form, p, sl(s, t), &found, &held) }
            }
        }
        if r > p && r < s.count && !at(s, r, 58) && !at(s, r, 0xff1a) {
            let gap = s[p..<r]
            if (caps || titled) && gap.contains(TAB) { put(true, .gap, r, sl(s, r), &found, &held) }
            else if caps && gap.count >= 3 { put(true, .gap, r, sl(s, r), &found, &held) }
        }
        if caps {
            var z = r
            if at(s, z, 46) || at(s, z, 58) || at(s, z, 0xff1a) || at(s, z, 94) { z = skipGap(s, z + 1) }
            if z == s.count { put(true, .alone, z, [], &found, &held) }
        }
    }

    // MARK: Rows

    private static let CUE_SOUND = ["SOUND EFFECTS", "SOUND EFFECT", "SOUND", "SFX"].map(u)
    private static let CUE_MUSIC = ["MUSIC", "THEME", "ORCHESTRA"].map(u)
    private static let OPENERS: Set<UInt16> = Set(u("([*#\"\u{201C}>- \t"))

    private static func skipOpeners(_ s: U) -> Int {
        var p = 0
        while p < s.count && OPENERS.contains(s[p]) { p += 1 }
        return p
    }

    /// "sound", "music" or nil: rule 1.
    private static func cueKind(_ s: U) -> String? {
        let p = skipOpeners(s)
        let up = asciiUpper(s)
        for (kind, ws) in [("sound", CUE_SOUND), ("music", CUE_MUSIC)] {
            for w in ws {
                if !startsWith(up, w, p) { continue }
                let caps = startsWith(s, w, p)
                let r = skipGap(s, p + w.count)
                let none = r >= s.count
                let c: UInt16 = none ? 32 : s[r]
                if !none && (c == 58 || c == 0xff1a) { return kind }
                if caps && (none || c == 46 || c == 40 || c == 91 || c == 45 || c == 0x2014 || c == 0x2013) { return kind }
                if caps && !none && (c == 41 || c == 93) && p > 0 { return kind }
                if caps && r > p + w.count && !contains(s, 58) && isCaps(s) && wordsOf(s).count >= 3 { return kind }
            }
        }
        return nil
    }

    static func cueKind(_ row: String) -> String? { cueKind(u(row)) }

    private static let HEADS = ["ACT", "SCENE", "PROLOGUE", "EPILOGUE", "INDUCTION", "CURTAIN", "TABLEAU", "THE END", "END OF", "FINIS", "FADE IN", "FADE OUT",
                                "FADE TO", "CUT TO", "INT.", "EXT.", "INT/EXT", "DISSOLVE TO"].map(u)
    private static let HEADS_NUMBERED = ["ACT", "SCENE", "ACTUS", "SCENA", "SCOENA"].map(u)

    private static func wordEnds(_ s: U, _ p: Int) -> Bool {
        p >= s.count || !(isC(cpAt(s, p), LETTER | MARK | DIGIT) || s[p] == 39 || s[p] == 0x2019)
    }

    /// Rule 2: a heading of the play or its staging.
    private static func isHeading(_ s: U) -> Bool {
        let p = skipOpeners(s)
        for h in HEADS where startsWith(s, h, p) && (endsWith(h, 46) || wordEnds(s, p + h.count)) { return true }
        let up = asciiUpper(s)
        if startsWith(up, u("END OF "), p) {
            for w in wordsOf(up) where startsWith(w, u("ACT")) || startsWith(w, u("SCENE")) || startsWith(w, u("PLAY")) { return true }
        }
        for h in HEADS_NUMBERED {
            if !startsWith(up, h, p) || !wordEnds(s, p + h.count) { continue }
            var q = p + h.count
            if at(s, q, 46) { q += 1 }
            let a = skipGap(s, q)
            if a == q { continue }
            var b = a
            while b < s.count && isC(cpAt(s, b), LETTER | DIGIT) { b += width(cpAt(s, b)) }
            let n = sl(up, a, b)
            if !n.isEmpty && (ROMAN.contains(n) || WORD_NUMBERS.contains(n) || n.allSatisfy { $0 >= 48 && $0 <= 57 }) { return true }
        }
        return false
    }

    static func isHeading(_ row: String) -> Bool { isHeading(u(row)) }

    /// A paragraph that opens with a printed entrance or exit.
    private static func isEntrance(_ s: U) -> Bool {
        for w in ["Enter", "Re-enter", "Reenter"].map(u) where startsWith(s, w + [SPACE]) && isC(cpAt(s, w.count + 1), LETTER) { return true }
        for w in ["Exit", "Exeunt", "Manet", "Manent"].map(u) where startsWith(s, w) && (s.count == w.count || s[w.count] == 46 || s[w.count] == 32) { return true }
        return false
    }

    static func isEntrance(_ row: String) -> Bool { isEntrance(u(row)) }

    private static func isExit(_ s: U) -> Bool { s == u("Exit") || s == u("Exit.") || s == u("Exeunt") || s == u("Exeunt.") }

    /// The last row of a bracketed direction that opens row `i`'s paragraph (-1 if it does not close with the row), and whether it closes.
    private static func bracketRows(_ rows: [U], _ i: Int) -> (Int, Bool) {
        let open = rows[i][0]
        let close: UInt16 = open == 40 ? 41 : 93
        var depth = 0
        var j = i
        while j < rows.count && !rows[j].isEmpty {
            let s = rows[j]
            for p in 0..<s.count {
                let c = s[p]
                if c == open { depth += 1 }
                else if c == close {
                    depth -= 1
                    if depth == 0 {
                        let whole = p == s.count - 1 || (p == s.count - 2 && s[p + 1] == 46)
                        return (whole ? j : -1, true)
                    }
                }
            }
            j += 1
        }
        return (-1, false)
    }

    private final class Building {
        let kind: String
        let role: U?
        var text: U
        let label: U?
        init(_ kind: String, _ role: U?, _ text: U, _ label: U?) { self.kind = kind; self.role = role; self.text = text; self.label = label }
    }

    /// The ten rules (R4 section 2.2): the normalized text, lines as a doc holds them, and each part's count of lines.
    static func parse(_ raw: String?) -> OwnParsed { parse(units: u(raw ?? "")) }

    static func parse(units raw: U) -> OwnParsed {
        let text = normalize(units: raw)
        let rows = splitRows(text).map { trim($0) }
        var read = [[Lab]?](repeating: nil, count: rows.count)
        var seen: [U: Int] = [:]
        var starting: [U: Int] = [:]
        var printed: [Form: [U: Int]] = [.colon: [:], .dot: [:], .alone: [:]]
        func row(_ i: Int) -> U { i >= 0 && i < rows.count ? rows[i] : [] }
        func opensParagraph(_ i: Int) -> Bool { i == 0 || rows[i - 1].isEmpty }

        for i in 0..<rows.count {
            let s = rows[i]
            if s.isEmpty || cueKind(s) != nil || isHeading(s) { continue }
            let ls = labels(s)
            read[i] = ls
            guard let m = ls.first else { continue }
            if printed[m.form] != nil { printed[m.form]![m.key, default: 0] += 1 }
            if m.form == .mixed { starting[m.key, default: 0] += 1 }
            else if m.form != .alone || !row(i + 1).isEmpty || !row(i + 2).isEmpty { seen[m.key, default: 0] += 1 }
        }
        var established: [Form: Bool] = [:]
        for (form, counts) in printed { established[form] = counts.values.filter { $0 >= 2 }.count >= 2 }
        func afterLabel(_ i: Int) -> Bool { i >= 1 && read[i - 1]?.first?.form == .colon }
        func known(_ m: Lab, _ i: Int) -> Bool {
            let n = seen[m.key] ?? 0
            if m.form == .mixed { return (n >= 2 && opensParagraph(i)) || (starting[m.key] ?? 0) >= 5 }
            if n >= 2 { return true }
            if established[m.form] != true { return false }
            if m.form == .dot { return opensParagraph(i) && hasLower(m.text) }
            if m.form == .alone { return opensParagraph(i) && !row(i + 1).isEmpty && hasLower(row(i + 1)) }
            if isCaps(m.name) { return opensParagraph(i) || afterLabel(i) || cueKind(rows[i - 1]) != nil }
            return opensParagraph(i) && isTitled(m.name) && wordsOf(m.name).count <= 2
        }

        var out: [Building] = []
        var cur: Building?
        var blank = true
        var awaiting = false
        var resume: U?
        func push(_ kind: String, _ role: U?, _ t: U, _ label: U? = nil) {
            let b = Building(kind, role, t, (label?.isEmpty ?? true) ? nil : label)
            cur = b
            out.append(b)
            awaiting = false
            resume = nil
        }
        func more(_ s: U) { let b = cur!; if !b.text.isEmpty { b.text.append(NL) }; b.text.append(contentsOf: s) }
        var i = 0
        while i < rows.count {
            let s = rows[i]
            if s.isEmpty { blank = true; i += 1; continue }
            if let cue = cueKind(s) { push(cue, nil, s) }
            else if isHeading(s) { push("direction", nil, s) }
            else {
                let aw = awaiting
                let m = (read[i] ?? []).first { x in known(x, i) && !(aw && !blank && !isCaps(x.name)) }
                if let m {
                    push("speech", m.key, m.text, m.label)
                    awaiting = m.bare
                } else if awaiting {
                    more(s)
                    awaiting = opensBracket(s, 0) && bracketEnd(s, 0) == s.count
                } else if blank && opensBracket(s, 0) {
                    let (last, closes) = bracketRows(rows, i)
                    if last >= 0 { push("direction", nil, joinRows(rows[i...last])); i = last }
                    else { push(s[0] == 91 && !closes ? "direction" : "open", nil, s) }
                } else if blank && isEntrance(s) { push("direction", nil, s) }
                else if !blank, let c = cur, c.kind == "speech", isExit(s) {
                    let role = c.role
                    push("direction", nil, s)
                    resume = role
                } else if !blank, let r = resume { push("speech", r, s) }
                else if !blank && cur != nil { more(s) }
                else { push("open", nil, s) }
            }
            blank = false
            i += 1
        }
        let lines: [OwnLine] = out.map { l in
            if l.kind == "speech" && l.text.isEmpty { return OwnLine(kind: "open", text: l.label.map(str) ?? "") }
            return OwnLine(kind: l.kind, role: l.role.map(str), text: str(l.text), label: l.label.map(str))
        }
        return OwnParsed(text: str(text), lines: lines, parts: partsOf(lines))
    }

    /// Each part's name and its count of lines, in order of first appearance.
    static func partsOf(_ lines: [OwnLine]) -> [OwnPart] {
        var order: [U] = []
        var count: [U: Int] = [:]
        for l in lines where l.kind == "speech" {
            let r = u(l.role ?? "")
            if count[r] == nil { order.append(r) }
            count[r, default: 0] += 1
        }
        return order.map { OwnPart(name: str($0), lines: count[$0]!) }
    }

    // MARK: A line's printed pieces

    /// Every bracket's partner: opening index to the index after the closing one, `( )` and `[ ]` each nested on their own, one pass.
    private static func matched(_ s: U) -> [Int: Int] {
        var out: [Int: Int] = [:]
        var round: [Int] = []
        var square: [Int] = []
        for i in 0..<s.count {
            let c = s[i]
            if c == 40 { round.append(i) }
            else if c == 91 { square.append(i) }
            else if c == 41, let o = round.popLast() { out[o] = i + 1 }
            else if c == 93, let o = square.popLast() { out[o] = i + 1 }
        }
        return out
    }

    private static func spans(_ s: U) -> [(Int, Int)] {
        let m = matched(s)
        var out: [(Int, Int)] = []
        if m.isEmpty { return out }
        var i = 0
        while i < s.count {
            guard let end = m[i] else { i += 1; continue }
            let c = i > 0 ? Int(s[i - 1]) : 0
            if asciiWord(c) || (c > 0x7f && isC(codePointBefore(s, i), LETTER | MARK | DIGIT)) { i += 1; continue }
            if trim(sl(s, i + 1, end - 1)).isEmpty { i += 1; continue }
            out.append((i, end))
            i = end
        }
        return out
    }

    /// A speech's text as the castable shape's parts, each a slice of it.
    private static func pieces(_ text: U) -> [OwnPiece] {
        var out: [OwnPiece] = []
        var from = 0
        func say(_ t: U) { let w = trim(t); if !w.isEmpty { out.append(.say(str(w))) } }
        for (a, b) in spans(text) {
            say(sl(text, from, a))
            out.append(.direction(str(trim(sl(text, a + 1, b - 1)))))
            from = b
        }
        say(sl(text, from))
        return out
    }

    static func pieces(_ text: String) -> [OwnPiece] { pieces(u(text)) }

    private static func evenRound(_ s: U) -> Bool {
        var depth = 0
        for c in s {
            if c == 40 { depth += 1 } else if c == 41 { depth -= 1; if depth < 0 { return false } }
        }
        return depth == 0
    }

    /// The text a speech's parts read from again.
    static func textOf(_ parts: [OwnPiece]) -> String {
        var out = U()
        for (i, p) in parts.enumerated() {
            if i > 0 { out.append(SPACE) }
            switch p {
            case .say(let t): out.append(contentsOf: u(t))
            case .direction(let t):
                let a = u(t)
                let even = evenRound(a)
                out.append(even ? 40 : 91)
                out.append(contentsOf: a)
                out.append(even ? 41 : 93)
            }
        }
        return str(out)
    }

    // MARK: Cutting a line

    private static func regional(_ cp: Int) -> Bool { cp >= 0x1f1e6 && cp <= 0x1f1ff }

    private static func insideCharacter(_ s: U, _ at: Int) -> Bool {
        let c = Int(s[at])
        if c >= 0xdc00 && c <= 0xdfff { let b = Int(s[at - 1]); if b >= 0xd800 && b <= 0xdbff { return true } }
        let cp = cpAt(s, at)
        if isC(cp, MARK) || cp == 0x200d || (cp >= 0x1f3fb && cp <= 0x1f3ff) { return true }
        let before = codePointBefore(s, at)
        if before == 0x200d { return true }
        if regional(cp) && regional(before) {
            var n = 0
            var i = at
            while i >= 2 && regional(codePointBefore(s, i)) { n += 1; i -= 2 }
            return n % 2 == 1
        }
        return false
    }

    /// Where a cut asked for at `at` goes: off a character it would break, out of a direction's brackets. -1 when one side would have nothing.
    static func cutAt(_ text: String, _ at: Int?) -> Int { cutAt(u(text), at) }

    private static func cutAt(_ text: U, _ at: Int?) -> Int {
        guard let at, at > 0, at < text.count else { return -1 }
        var p = at
        while p > 0 && insideCharacter(text, p) { p -= 1 }
        for (a, b) in spans(text) where p > a && p < b { p = !trim(sl(text, 0, a)).isEmpty ? a : b }
        return (!trim(sl(text, 0, p)).isEmpty && !trim(sl(text, p)).isEmpty) ? p : -1
    }

    // MARK: Ids

    private static func pad(_ n: Int) -> String { let s = String(n); return String(repeating: "0", count: max(0, 4 - s.count)) + s }

    private static func letters(_ n0: Int) -> String {
        var n = n0
        var out: [UInt8] = []
        while n > 0 { let r = (n - 1) % 26; out.append(UInt8(97 + r)); n = (n - 1 - r) / 26 }
        return String(decoding: out.reversed(), as: UTF8.self)
    }

    private static func lettersValue(_ w: U) -> Int {
        var n = 0
        for c in w { n = n * 26 + (Int(c) - 96) }
        return n
    }

    private static func baseOf(_ id: String?) -> String { id.map { str(sl(u($0), 0, 5)) } ?? "L0000" }

    // MARK: A script being corrected

    /// A doc from parse()'s lines, or fromCues()'s.
    static func newDoc(_ lines: [OwnLine]) -> OwnDoc {
        OwnDoc(lines: lines.enumerated().map { i, l in
            OwnLine(k: i + 1, id: nil, kind: l.kind, role: (l.role?.isEmpty ?? true) ? nil : l.role, text: l.text, label: (l.label?.isEmpty ?? true) ? nil : l.label, at: l.at)
        }, nextKey: lines.count + 1)
    }

    private static func refuse(_ doc: OwnDoc, _ why: OwnRefusal) -> OwnResult { OwnResult(doc: doc, refusal: why) }

    private static func accept(_ doc: OwnDoc, _ lines: [OwnLine], nextKey: Int? = nil, letters: [String: Int]? = nil, heard: [Int]? = nil) -> OwnResult {
        var d = doc
        d.lines = lines
        if let nextKey { d.nextKey = nextKey }
        if let letters { d.letters = letters }
        if let heard { d.heard = heard }
        d.undo = doc.undo + [doc.lines]
        return OwnResult(doc: d, refusal: nil)
    }

    private static func nextID(_ doc: OwnDoc, _ above: OwnLine?, _ given: Bool) -> (String?, [String: Int]) {
        if !given { return (nil, doc.letters) }
        let base = baseOf(above?.id)
        let n = (doc.letters[base] ?? 0) + 1
        var l = doc.letters
        l[base] = n
        return (base + letters(n), l)
    }

    /// The words of a text, letters and digits only: what tells a changed word from a changed comma.
    private static func spoken(_ text: String) -> U {
        var out = U()
        var gap = false
        var said = U()
        var first = true
        for p in pieces(u(text)) {
            guard case .say(let t) = p else { continue }
            if !first { said.append(SPACE) }
            first = false
            said.append(contentsOf: u(t))
        }
        var i = 0
        while i < said.count {
            let cp = cpAt(said, i)
            let w = width(cp)
            if isC(cp, LETTER | MARK | DIGIT) {
                if gap && !out.isEmpty { out.append(SPACE) }
                gap = false
                out.append(contentsOf: said[i..<(i + w)])
            } else if cp != 39 && cp != 0x2019 { gap = true }
            i += w
        }
        return u(str(out).lowercased())
    }

    /// Whether more than punctuation and capitals changed between two versions of a line.
    static func wordsChanged(_ before: String, _ after: String) -> Bool { spoken(before) != spoken(after) }

    private static func holdCast(_ doc: OwnDoc, _ lines: [OwnLine], _ i: Int) -> [OwnLine] {
        guard i >= 0, i < lines.count else { return lines }
        let l = lines[i]
        if l.kind != "open" || l.mark != nil || doc.heard.isEmpty { return lines }
        guard let who = castOf(doc)[l.k], let who else { return lines }
        var out = lines
        out[i].mark = who
        return out
    }

    private static let KINDS = ["direction", "sound", "music", "open"]

    /// One change on the parts page: assign, split, join, words, leaveOut, add, rename, notPart, undo. Refused, the doc is the one given.
    static func apply(_ doc: OwnDoc, _ op: OwnOp, _ env: OwnEnv = OwnEnv()) -> OwnResult {
        func taken(_ l: OwnLine) -> Bool { l.id.map(env.takes.contains) ?? false }
        if env.shared { return refuse(doc, .shared) }
        let lines = doc.lines
        if op.op == .undo {
            guard let last = doc.undo.last else { return refuse(doc, .nothing_to_undo) }
            var d = doc
            d.lines = last
            d.undo.removeLast()
            return OwnResult(doc: d, refusal: nil)
        }
        if op.op == .rename || op.op == .notPart {
            let part = op.part
            let mine = lines.filter { $0.kind == "speech" && eq($0.role, part) }
            if mine.isEmpty { return refuse(doc, .no_such_part) }
            let to: String? = op.op == .rename ? partName(normalize(op.rename)) : nil
            if op.op == .rename {
                if let why = partNameRefusal(to) { return refuse(doc, why) }
                if eq(to, part) { return OwnResult(doc: doc, refusal: nil) }
            }
            if mine.contains(where: taken) { return refuse(doc, .part_has_take) }
            return accept(doc, lines.map { l in
                var l = l
                if l.kind != "speech" || !eq(l.role, part) { return l }
                if op.op == .rename { l.role = to }
                else {
                    l.kind = "open"
                    l.role = nil
                    l.text = l.label != nil ? l.label! + " " + l.text : l.text
                    l.label = nil
                }
                return l
            })
        }

        let given = lines.contains { $0.id != nil }
        if op.op == .add {
            let i = op.after == 0 ? 0 : (lines.firstIndex { $0.k == op.after }.map { $0 + 1 } ?? 0)
            if op.after != 0 && i == 0 { return refuse(doc, .no_such_line) }
            if lines.count >= maxLines { return refuse(doc, .too_many_lines) }
            let text = trim(normalize(op.text))
            if text.isEmpty { return refuse(doc, .empty) }
            let speech = op.kind == "speech"
            let role: String? = speech ? partName(normalize(op.role)) : nil
            if speech, let why = partNameRefusal(role) { return refuse(doc, why) }
            let n = nextID(doc, i > 0 ? lines[i - 1] : nil, given)
            let line = OwnLine(k: doc.nextKey, id: n.0, kind: (speech || KINDS.contains(op.kind)) ? op.kind : "open", role: role, text: text)
            var next = Array(lines[0..<i])
            next.append(line)
            next.append(contentsOf: lines[i...])
            return accept(doc, next, nextKey: doc.nextKey + 1, letters: n.1)
        }

        guard let i = lines.firstIndex(where: { $0.k == op.line }) else { return refuse(doc, .no_such_line) }
        let l = lines[i]
        func put(_ now: [OwnLine]) -> [OwnLine] { Array(lines[0..<i]) + now + Array(lines[(i + 1)...]) }

        if op.op == .words {
            let text = trim(normalize(op.text))
            if text.isEmpty { return refuse(doc, .empty) }
            if u(text) == u(l.text) { return OwnResult(doc: doc, refusal: nil) }
            var n = l
            n.text = text
            return accept(doc, put([n]))
        }
        if op.op == .assign {
            var role: String?
            var kind = ""
            switch op.to {
            case .role(let r)?: role = partName(normalize(r)); kind = "speech"
            case .kind(let k)?: kind = k
            case nil: break
            }
            if kind != "speech" && !KINDS.contains(kind) { return refuse(doc, .bad_kind) }
            if kind == "speech", let why = partNameRefusal(role) { return refuse(doc, why) }
            if l.kind == kind && eq(l.role, role) { return OwnResult(doc: doc, refusal: nil) }
            if taken(l) { return refuse(doc, .line_has_take) }
            var n = l
            n.kind = kind
            n.role = role
            n.mark = nil
            return accept(doc, holdCast(doc, put([n]), i + 1))
        }
        if taken(l) { return refuse(doc, .line_has_take) }
        if op.op == .leaveOut { return accept(doc, holdCast(doc, put([]), i)) }
        if op.op == .split {
            let t = u(l.text)
            let p = cutAt(t, op.at)
            if p < 0 { return refuse(doc, .empty) }
            if lines.count >= maxLines { return refuse(doc, .too_many_lines) }
            let n = nextID(doc, l, given)
            var a = l
            a.text = str(trim(sl(t, 0, p)))
            var b = l
            b.k = doc.nextKey
            b.id = n.0
            b.text = str(trim(sl(t, p)))
            b.label = nil
            b.mark = nil
            if let span = l.at {
                let cut = timeAt(span, t.count, p)
                a.at = OwnSpan(start: span.start, end: cut)
                b.at = OwnSpan(start: cut, end: span.end)
            }
            let heard = doc.heard.contains(l.k) ? doc.heard + [b.k] : doc.heard
            return accept(doc, put([a, b]), nextKey: doc.nextKey + 1, letters: n.1, heard: heard)
        }
        if op.op == .join {
            if i == 0 { return refuse(doc, .no_line_above) }
            let above = lines[i - 1]
            if taken(above) { return refuse(doc, .line_has_take) }
            let verse = above.text.utf16.contains(10) || l.text.utf16.contains(10)
            var one = above
            one.text = above.text + (verse ? "\n" : " ") + l.text
            if let a = above.at, let b = l.at { one.at = OwnSpan(start: a.start, end: b.end) }
            let next = Array(lines[0..<(i - 1)]) + [one] + Array(lines[(i + 1)...])
            return accept(doc, holdCast(doc, next, i))
        }
        return refuse(doc, .no_such_op)
    }

    /// The two nearest speakers above and below, no name twice: the one-tap answers for a line with no part.
    static func nearestParts(_ lines: [OwnLine], _ i: Int) -> [String] {
        var out: [String] = []
        var d = 1
        while d < lines.count && out.count < 2 {
            for j in [i - d, i + d] where j >= 0 && j < lines.count {
                let l = lines[j]
                if l.kind == "speech", let r = l.role, !out.contains(r), out.count < 2 { out.append(r) }
            }
            d += 1
        }
        return out
    }

    /// Done: each line gets its id, once, and the steps before it can no longer be taken back.
    static func done(_ doc: OwnDoc, keepOpen: Bool = false) -> OwnDoc {
        var lines = doc.lines
        if !lines.contains(where: { $0.id != nil }) {
            for i in lines.indices { lines[i].id = "L" + pad(i + 1) }
        }
        if !keepOpen {
            for i in lines.indices where lines[i].kind == "open" && lines[i].mark == nil { lines[i].kind = "direction" }
        }
        var d = doc
        d.lines = lines
        d.undo = []
        return d
    }

    // MARK: The castable shape

    /// A done doc as a castable script (plain data, as the catalog's JSON reads), its revision still to be sealed. Lines marked by ear
    /// are theirs; left-out lines are not in it; a line with no part is a direction.
    static func toScript(_ doc: OwnDoc, _ meta: OwnMeta) -> OwnJSON {
        struct Shaped { var id: String?; var kind: String; var role: String?; var parts: [OwnPiece]; var source: String }
        let shaped: [Shaped] = settle(doc).lines.map { l in
            if l.kind == "speech" { return Shaped(id: l.id, kind: "speech", role: l.role, parts: pieces(l.text), source: "") }
            return Shaped(id: l.id, kind: l.kind == "open" ? "direction" : l.kind, role: nil, parts: [], source: l.text)
        }
        var order: [String] = []
        var counts: [String: (Int, Int)] = [:]
        for l in shaped where l.kind == "speech" {
            let r = l.role ?? ""
            if counts[r] == nil { order.append(r); counts[r] = (0, 0) }
            counts[r]!.0 += 1
            for p in l.parts { if case .say(let t) = p { counts[r]!.1 += wordsOf(u(t)).count } }
        }
        let episode = meta.episodeId != nil
        var script: [String: OwnJSON] = [
            "id": .string(meta.id), "revision": .string(""), "kind": .string("own"),
            "title": .string(trim(normalize(meta.title))), "authors": .array([]),
            "source": episode ? .object(["name": .string("Automatic transcript"), "url": meta.episodeUrl.map { .string($0) } ?? .null])
                : .object(["name": .string("Added by you"), "url": .string("")]),
            "rights": .object(["bucket": .string("own"), "evidence": .array([])]),
            "roles": .array(order.map { .object(["name": .string($0), "lines": .int(counts[$0]!.0), "words": .int(counts[$0]!.1)]) }),
            "lines": .array(shaped.map { l in
                if l.kind == "speech" {
                    return .object([
                        "id": l.id.map { .string($0) } ?? .null, "kind": .string("speech"), "role": l.role.map { .string($0) } ?? .null,
                        "parts": .array(l.parts.map { p in
                            switch p {
                            case .say(let t): return .object(["say": .string(t)])
                            case .direction(let t): return .object(["direction": .string(t)])
                            }
                        }),
                    ])
                }
                return .object(["id": l.id.map { .string($0) } ?? .null, "kind": .string(l.kind), "source": .string(l.source)])
            }),
        ]
        if let e = meta.episodeId { script["episode"] = .string(e) }
        return .object(script)
    }

    /// A doc over a script as it stands, for Edit a copy (new script id, same line ids).
    static func fromScript(_ script: OwnJSON) -> OwnDoc {
        var given: [String: Int] = [:]
        var lines: [OwnLine] = []
        if case .array(let src)? = script["lines"] {
            for (i, l) in src.enumerated() {
                guard case .string(let id)? = l["id"], case .string(let kind)? = l["kind"] else { continue }
                let base = baseOf(id)
                given[base] = max(given[base] ?? 0, lettersValue(sl(u(id), 5)))
                let speech = kind == "speech"
                var text = ""
                var role: String?
                if speech {
                    var parts: [OwnPiece] = []
                    if case .array(let ps)? = l["parts"] {
                        for p in ps {
                            if case .string(let t)? = p["say"] { parts.append(.say(t)) }
                            else if case .string(let t)? = p["direction"] { parts.append(.direction(t)) }
                        }
                    }
                    text = textOf(parts)
                    if case .string(let r)? = l["role"] { role = r }
                } else if case .string(let t)? = l["source"] { text = t }
                lines.append(OwnLine(k: i + 1, id: id, kind: kind, role: role, text: text))
            }
        }
        return OwnDoc(lines: lines, nextKey: lines.count + 1, letters: given.filter { $0.value != 0 })
    }

    /// A doc as it is kept: everything but the steps that can be taken back.
    static func kept(_ doc: OwnDoc) -> OwnDoc { var d = doc; d.undo = []; return d }

    // MARK: The revision

    private static let HEX = Array("0123456789abcdef".utf8)

    private static func jsonString(_ s: String, _ out: inout [UInt8]) {
        out.append(34)
        for b in s.utf8 {
            switch b {
            case 34: out.append(contentsOf: [92, 34])
            case 92: out.append(contentsOf: [92, 92])
            case 10: out.append(contentsOf: [92, 110])
            case 13: out.append(contentsOf: [92, 114])
            case 9: out.append(contentsOf: [92, 116])
            case 8: out.append(contentsOf: [92, 98])
            case 12: out.append(contentsOf: [92, 102])
            case 0..<32: out.append(contentsOf: [92, 117, 48, 48, HEX[Int(b >> 4)], HEX[Int(b & 15)]])
            default: out.append(b)
            }
        }
        out.append(34)
    }

    private static func canonical(_ v: OwnJSON, _ out: inout [UInt8]) {
        switch v {
        case .null: out.append(contentsOf: Array("null".utf8))
        case .bool(let b): out.append(contentsOf: Array((b ? "true" : "false").utf8))
        case .int(let n): out.append(contentsOf: Array(String(n).utf8))
        case .string(let s): jsonString(s, &out)
        case .array(let a):
            out.append(91)
            for (i, x) in a.enumerated() { if i > 0 { out.append(44) }; canonical(x, &out) }
            out.append(93)
        case .object(let o):
            out.append(123)
            let keys = o.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
            for (i, k) in keys.enumerated() {
                if i > 0 { out.append(44) }
                jsonString(k, &out)
                out.append(58)
                canonical(o[k]!, &out)
            }
            out.append(125)
        }
    }

    /// The bytes that are hashed, and sent when a script is shared: keys sorted, no spaces, nothing escaped that need not be.
    static func canonicalBytes(_ v: OwnJSON) -> [UInt8] { var out: [UInt8] = []; canonical(v, &out); return out }

    static func canonicalLines(_ v: OwnJSON) -> String { String(decoding: canonicalBytes(v), as: UTF8.self) }

    /// The catalog's revision: the first 12 hex digits of the SHA-256 of the canonical lines, UTF-8.
    static func revisionOf(_ lines: OwnJSON) -> String {
        let digest = SHA256.hash(data: canonicalBytes(lines))
        var out: [UInt8] = []
        for b in digest.prefix(6) { out.append(HEX[Int(b >> 4)]); out.append(HEX[Int(b & 15)]) }
        return String(decoding: out, as: UTF8.self)
    }

    static func seal(_ script: OwnJSON) -> OwnJSON {
        guard case .object(var o) = script else { return script }
        o["revision"] = .string(revisionOf(o["lines"] ?? .null))
        return .object(o)
    }

    private static func isOwnID(_ s: U) -> Bool {
        let groups = [8, 4, 4, 4, 12]
        var p = 4
        guard startsWith(s, u("own-")) else { return false }
        for (gi, g) in groups.enumerated() {
            if gi > 0 { if !at(s, p, 45) { return false }; p += 1 }
            for _ in 0..<g {
                guard p < s.count, (s[p] >= 48 && s[p] <= 57) || (s[p] >= 97 && s[p] <= 102) else { return false }
                p += 1
            }
        }
        return p == s.count
    }

    private static func isLineID(_ s: U) -> Bool {
        guard s.count >= 5, s[0] == 76 else { return false }
        for i in 1...4 where !(s[i] >= 48 && s[i] <= 57) { return false }
        for i in 5..<s.count where !(s[i] >= 97 && s[i] <= 122) { return false }
        return true
    }

    /// nil when `script` may be kept and shared, or the first thing wrong with it.
    static func refusalOf(_ script: OwnJSON?) -> OwnRefusal? {
        guard let script, case .object = script else { return .bad_id }
        guard case .string(let id)? = script["id"], isOwnID(u(id)) else { return .bad_id }
        guard case .string(let title)? = script["title"], !trim(u(title)).isEmpty else { return .no_title }
        if title.utf16.count > maxTitle { return .title_too_long }
        guard case .array(let lines)? = script["lines"], !lines.isEmpty else { return .no_lines }
        if lines.count > maxLines { return .too_many_lines }
        var seen = Set<String>()
        var speeches = 0
        for l in lines {
            guard case .object = l, case .string(let lid)? = l["id"], isLineID(u(lid)), seen.insert(lid).inserted else { return .bad_line_id }
            if case .string("speech")? = l["kind"] {
                speeches += 1
                guard case .string(let role)? = l["role"], u(role) == partName(u(role)), partNameRefusal(role) == nil else { return .bad_part }
                guard case .array(let parts)? = l["parts"], !parts.isEmpty else { return .bad_line }
                for p in parts {
                    guard case .object(let pm) = p, pm.count == 1, let (k, v) = pm.first, k == "say" || k == "direction",
                          case .string(let t) = v, !t.isEmpty else { return .bad_line }
                }
            } else if case .string(let k)? = l["kind"], k == "direction" || k == "sound" || k == "music" {
                guard case .string(let src)? = l["source"], !src.isEmpty else { return .bad_line }
            } else { return .bad_line }
        }
        if speeches == 0 { return .no_parts }
        if canonicalBytes(.array(lines)).count > maxBytes { return .too_long }
        return nil
    }

    /// nil when a text may be read, or why not: empty, too_long. Asked before `parse`.
    static func textRefusal(_ raw: String?) -> OwnRefusal? {
        let t = raw ?? ""
        if t.utf16.count > maxBytes || t.utf8.count > maxBytes { return .too_long }
        return trim(normalize(units: u(t))).isEmpty ? .empty : nil
    }

    // MARK: A transcript, cast by ear

    /// `start + (end - start) * at / length`, whole milliseconds, rounded down.
    private static func timeAt(_ span: OwnSpan, _ length: Int, _ at: Int) -> Int64 {
        span.start + ((span.end - span.start) * Int64(at)) / Int64(length)
    }

    private static func digitsAt(_ s: U, _ p: Int, _ max: Int) -> Int {
        var n = 0
        while n < max && p + n < s.count && s[p + n] >= 48 && s[p + n] <= 57 { n += 1 }
        return n
    }

    private static func clock(_ s: U, _ p: Int) -> (ms: Int64, end: Int)? {
        var nums: [Int64] = []
        var i = p
        while true {
            let n = digitsAt(s, i, 4)
            if n == 0 { return nil }
            nums.append(Int64(str(Array(s[i..<(i + n)])))!)
            i += n
            if at(s, i, 58) && nums.count < 3 { i += 1; continue }
            break
        }
        if nums.count < 2 || (!at(s, i, 46) && !at(s, i, 44)) { return nil }
        if digitsAt(s, i + 1, 3) != 3 { return nil }
        let ms = Int64(str(Array(s[(i + 1)..<(i + 4)])))!
        let sec = nums[nums.count - 1]
        let min = nums[nums.count - 2]
        let hour: Int64 = nums.count == 3 ? nums[0] : 0
        if sec > 59 || min > 59 { return nil }
        return ((((hour * 60) + min) * 60 + sec) * 1000 + ms, i + 4)
    }

    private static func replacing(_ t: U, _ a: String, _ b: String) -> U {
        let pa = u(a), pb = u(b)
        var out = U()
        var i = 0
        while i < t.count {
            if startsWith(t, pa, i) { out.append(contentsOf: pb); i += pa.count } else { out.append(t[i]); i += 1 }
        }
        return out
    }

    private static func indexOf(_ s: U, _ sub: U, _ from: Int = 0) -> Int {
        if sub.isEmpty { return min(from, s.count) }
        if s.count < sub.count { return -1 }
        var i = max(from, 0)
        while i + sub.count <= s.count { if startsWith(s, sub, i) { return i }; i += 1 }
        return -1
    }

    private static func cueText(_ s: U) -> U {
        var out = U()
        let last = s.lastIndex(of: 62) ?? -1
        var i = 0
        while i < s.count {
            if s[i] == 60 && i < last { i = s[i...].firstIndex(of: 62)! + 1; continue }
            out.append(s[i])
            i += 1
        }
        var t = out
        for (a, b) in [("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] { t = replacing(t, a, b) }
        var r = U()
        for (i, w) in wordsOf(t).enumerated() { if i > 0 { r.append(SPACE) }; r.append(contentsOf: w) }
        return r
    }

    /// A transcript's cues: WebVTT (or SRT) by its times; any other text, one cue a row with no times.
    static func parseCues(_ raw: String?) -> [OwnCue] {
        let rows = splitRows(normalize(units: u(raw ?? ""))).map { trim($0) }
        var out: [OwnCue] = []
        let arrow = u("-->")
        if !rows.contains(where: { indexOf($0, arrow) >= 0 }) {
            for r in rows {
                let t = cueText(r)
                if !t.isEmpty && r != u("WEBVTT") { out.append(OwnCue(text: str(t), at: nil)) }
            }
            return out
        }
        var i = 0
        while i < rows.count {
            let a0 = indexOf(rows[i], arrow)
            if a0 < 0 { i += 1; continue }
            let a = clock(rows[i], 0)
            let b = clock(rows[i], skipGap(rows[i], a0 + 3))
            var j = i + 1
            var said: [U] = []
            while j < rows.count && !rows[j].isEmpty && indexOf(rows[j], arrow) < 0 { said.append(rows[j]); j += 1 }
            var joined = U()
            for (n, w) in said.enumerated() { if n > 0 { joined.append(SPACE) }; joined.append(contentsOf: w) }
            let t = cueText(joined)
            if let a, let b, b.ms >= a.ms, !t.isEmpty { out.append(OwnCue(text: str(t), at: OwnSpan(start: a.ms, end: b.ms))) }
            i = j
        }
        return out
    }

    private static func closesQuote(_ c: UInt16) -> Bool { c == 34 || c == 39 || c == 0x201d || c == 0x2019 }
    private static func opensQuote(_ c: UInt16) -> Bool { c == 34 || c == 39 || c == 0x201c || c == 0x2018 }

    /// Where a cue's text is cut into lines: the index after each sentence's end, when a space and a capital follow.
    private static func sentenceCuts(_ t: U) -> [Int] {
        var out: [Int] = []
        for i in 0..<t.count {
            let c = t[i]
            if c != 46 && c != 63 && c != 33 { continue }
            var j = i + 1
            while j < t.count && closesQuote(t[j]) { j += 1 }
            if !at(t, j, 32) { continue }
            var n = j + 1
            if n < t.count && opensQuote(t[n]) { n += 1 }
            if !isC(cpAt(t, n), UPPER) { continue }
            if c == 46 {
                var w = i
                while w > 0 && asciiWord(Int(t[w - 1])) { w -= 1 }
                let before = w > 0 ? codePointBefore(t, w) : -1
                if ABBREVIATIONS.contains(sl(t, w, i)) && !isC(before, LETTER | MARK) { continue }
            }
            out.append(j)
        }
        return out
    }

    static func sentenceCuts(_ t: String) -> [Int] { sentenceCuts(u(t)) }

    /// Cues as lines to cast, each a sentence of one cue with its share of the cue's time by UTF-16 units.
    static func fromCues(_ cues: [OwnCue]) -> OwnDoc {
        var lines: [OwnLine] = []
        for cue in cues {
            let t = u(cue.text)
            var from = 0
            let n = t.count
            for cut in sentenceCuts(t) + [n] {
                let text = trim(sl(t, from, cut))
                var at: OwnSpan?
                if let span = cue.at { at = OwnSpan(start: timeAt(span, n, from), end: timeAt(span, n, cut == n ? n : cut + 1)) }
                if !text.isEmpty { lines.append(OwnLine(kind: "open", text: str(text), at: at)) }
                from = cut + 1
            }
        }
        return newDoc(lines)
    }

    /// The line being said at `ms` (its key), or the last one begun; 0 before the first.
    static func lineAt(_ doc: OwnDoc, _ ms: Int64) -> Int {
        var k = 0
        for l in doc.lines { guard let a = l.at else { continue }; if a.start > ms { break }; k = l.k }
        return k
    }

    /// Who each line is cast to, by key: a part, `.out`, or nil. A mark carries to the lines heard in a row after it.
    static func castOf(_ doc: OwnDoc) -> [Int: OwnWho?] {
        let heard = Set(doc.heard)
        var out: [Int: OwnWho?] = [:]
        var carry: OwnWho?
        for l in doc.lines {
            if l.kind != "open" { out[l.k] = .some(l.kind == "speech" ? .role(l.role ?? "") : nil); carry = nil; continue }
            if let m = l.mark { carry = m } else if !heard.contains(l.k) { carry = nil }
            out[l.k] = .some(carry)
        }
        return out
    }

    /// The audio reached line `k`, coming from line `from` (0 after a seek): it and those between are heard. Never undone.
    static func hear(_ doc: OwnDoc, _ k: Int, from: Int = 0) -> OwnDoc {
        guard let b = doc.lines.firstIndex(where: { $0.k == k }) else { return doc }
        let a0 = from != 0 ? (doc.lines.firstIndex { $0.k == from } ?? -1) : -1
        let a = (a0 >= 0 && a0 <= b) ? a0 : b
        var heard = doc.heard
        var have = Set(heard)
        for i in a...b where have.insert(doc.lines[i].k).inserted { heard.append(doc.lines[i].k) }
        if heard.count == doc.heard.count { return doc }
        var d = doc
        d.heard = heard
        return d
    }

    /// A tap on a part (or Leave out) while line `k` is lit.
    static func tap(_ doc: OwnDoc, _ k: Int, _ who: OwnWho, _ env: OwnEnv = OwnEnv()) -> OwnResult {
        if env.shared { return refuse(doc, .shared) }
        guard let i = doc.lines.firstIndex(where: { $0.k == k }) else { return refuse(doc, .no_such_line) }
        var mark = OwnWho.out
        if case .role(let name) = who {
            let role = partName(normalize(name))
            if let why = partNameRefusal(role) { return refuse(doc, why) }
            mark = .role(role)
        }
        var lines = doc.lines
        lines[i].kind = "open"
        lines[i].role = nil
        lines[i].mark = mark
        return marked(doc, lines, env, [k])
    }

    /// Leaves out one line and no other: the next keeps the cast it had.
    static func leaveOutHeard(_ doc: OwnDoc, _ k: Int, _ env: OwnEnv = OwnEnv()) -> OwnResult {
        if env.shared { return refuse(doc, .shared) }
        guard let i = doc.lines.firstIndex(where: { $0.k == k }) else { return refuse(doc, .no_such_line) }
        var lines = doc.lines
        lines[i].kind = "open"
        lines[i].role = nil
        lines[i].mark = .out
        return marked(doc, holdCast(doc, lines, i + 1), env, [k])
    }

    private static func marked(_ doc: OwnDoc, _ lines: [OwnLine], _ env: OwnEnv, _ heardNow: [Int]) -> OwnResult {
        var heard = doc.heard
        var have = Set(heard)
        for k in heardNow where have.insert(k).inserted { heard.append(k) }
        let next = accept(doc, lines, heard: heard)
        if !env.takes.isEmpty {
            let was = castOf(doc)
            let now = castOf(next.doc)
            if doc.lines.contains(where: { l in (l.id.map(env.takes.contains) ?? false) && was[l.k] != now[l.k] }) { return refuse(doc, .line_has_take) }
        }
        return next
    }

    /// "37 of 149 lines cast": lines given to a part or left out, of all of them.
    static func castCount(_ doc: OwnDoc) -> (cast: Int, lines: Int) {
        let cast = castOf(doc)
        var n = 0
        for l in doc.lines where l.kind != "open" || (cast[l.k] ?? nil) != nil { n += 1 }
        return (n, doc.lines.count)
    }

    /// The marks made into the lines' own parts, left-out lines gone.
    static func settle(_ doc: OwnDoc) -> OwnDoc {
        let cast = castOf(doc)
        var lines: [OwnLine] = []
        for l in doc.lines {
            if l.kind != "open" { lines.append(l); continue }
            let who = cast[l.k] ?? nil
            if who == .out { continue }
            var rest = l
            rest.mark = nil
            if case .role(let name)? = who { rest.kind = "speech"; rest.role = name }
            lines.append(rest)
        }
        var d = doc
        d.lines = lines
        return d
    }
}
