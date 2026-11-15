import Foundation

// Marks in the script reader (PLAYS-DESIGN §2.10, iOS-DESIGN §4.15 "Marks"; Decision 076 S5), with no drawing:
// a port of the web's js/marks-core.js, held to js/marks.test.js and the golden cases every stack runs
// (catalog/tests/golden/marks_anchor.json). A mark is anchored to a line, never a page: (script, revision, line
// id, start, end) with offsets in UTF-16 code units into `ScriptReading.lineText` (the web's string indexes),
// the marked words (`text`) and up to 32 characters either side. A new revision re-anchors each mark by its
// words (`place`); one it cannot place is kept, untouched, and listed as not placed.

nonisolated enum MarkKind: String, Codable, Sendable, CaseIterable {
    case highlight, underline, breath, pause, beat, note

    /// Marks over words; the rest stand between two words.
    var isSpan: Bool { self == .highlight || self == .underline || self == .note }
    /// Marks that never stack: an overlapping or touching one of the same kind merges.
    var merges: Bool { self == .highlight || self == .underline }
}

nonisolated enum MarkHue {
    static let all = ["yellow", "green", "blue", "pink"]
}

/// The web's JSON keys exactly, so an export reads the same and a later sync needs no mapping.
nonisolated struct Mark: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var kind: MarkKind
    var line: String
    var start: Int
    var end: Int
    var text: String
    var prefix: String
    var suffix: String
    var revision: String?
    /// Epoch milliseconds.
    var created: Int64
    var updated: Int64
    var hue: String?
    var label: String?
    var note: String?
    var group: String?

    var isSpan: Bool { kind.isSpan }
}

/// The selection on one line, in raw offsets into its `lineText`.
nonisolated struct MarkPiece: Equatable, Sendable {
    var line: String
    var start: Int
    var end: Int
}

nonisolated struct MarkExtra: Sendable {
    var hue: String?
    var label: String?
    var note: String?
    var group: String?
    init(hue: String? = nil, label: String? = nil, note: String? = nil, group: String? = nil) {
        self.hue = hue
        self.label = label
        self.note = note
        self.group = group
    }
}

nonisolated struct MarkPatch: Sendable {
    var hue: String?
    var label: String?
    var note: String?
    init(hue: String? = nil, label: String? = nil, note: String? = nil) {
        self.hue = hue
        self.label = label
        self.note = note
    }
}

nonisolated enum MarksCore {
    static let context = 32
    /// Away from its own line, a mark moves only on this many characters of evidence (words plus context), or all it has.
    static let evidence = 16
    /// In its own line, a point mark needs this much of its context to match.
    static let pointEvidence = 8
    static let labelMax = 24

    typealias U16 = [UInt16]

    // MARK: Words

    /// A word's characters: letters, digits, apostrophes, hyphens, and the printed `_italic_` marks.
    static func isWord(_ u: UInt16) -> Bool {
        if u == 0x27 || u == 0x2019 || u == 0x5F || u == 0x2D { return true }
        guard let s = Unicode.Scalar(u) else { return false }
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    /// JavaScript's `\s`.
    static func isSpace(_ u: UInt16) -> Bool {
        switch u {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        case 0x2000...0x200A: true
        default: false
        }
    }

    /// A selection grown to whole words and trimmed of space; nil when nothing is left.
    static func snapWords(_ text: String, _ start: Int, _ end: Int) -> (start: Int, end: Int)? {
        snapWords(Array(text.utf16), start, end)
    }

    static func snapWords(_ t: U16, _ start: Int, _ end: Int) -> (start: Int, end: Int)? {
        var s = max(0, min(start, end, t.count))
        var e = min(t.count, max(start, end, 0))
        while s < e, isSpace(t[s]) { s += 1 }
        while e > s, isSpace(t[e - 1]) { e -= 1 }
        if s >= e { return nil }
        while s > 0, isWord(t[s - 1]), isWord(t[s]) { s -= 1 }
        while e < t.count, isWord(t[e]), isWord(t[e - 1]) { e += 1 }
        return (s, e)
    }

    /// Where a point mark goes for a selection ending at `end`: after its word and any punctuation that follows.
    static func pointAfter(_ text: String, _ end: Int) -> Int { pointAfter(Array(text.utf16), end) }

    static func pointAfter(_ t: U16, _ end: Int) -> Int {
        var p = max(0, min(end, t.count))
        while p > 0, isSpace(t[p - 1]) { p -= 1 }
        while p < t.count, isWord(t[p]) { p += 1 }
        while p < t.count, !isSpace(t[p]), !isWord(t[p]) { p += 1 }
        return p
    }

    // MARK: Making

    nonisolated(unsafe) private static var seq = 0
    private static let seqLock = NSLock()

    static func newID(_ now: Int64) -> String {
        seqLock.lock()
        let n = seq
        seq += 1
        seqLock.unlock()
        return "m\(String(now, radix: 36))\(String(n, radix: 36))\(String(Int.random(in: 0..<1296), radix: 36))"
    }

    static func rev(_ script: PlayScript) -> String? { script.revision.isEmpty ? nil : script.revision }

    static func nowMillis() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }

    private static func slice(_ t: U16, _ from: Int, _ to: Int) -> String {
        let a = max(0, min(from, t.count)), b = max(a, min(to, t.count))
        return String(decoding: t[a..<b], as: UTF16.self)
    }

    /// The anchor's quote: the words and their context, read from the line as it is now.
    private static func quote(_ t: U16, _ start: Int, _ end: Int) -> (text: String, prefix: String, suffix: String) {
        (slice(t, start, end), slice(t, max(0, start - context), start), slice(t, end, end + context))
    }

    private static func text(of line: ScriptLine) -> U16 { Array(ScriptReading.lineText(line).utf16) }

    /// One mark on one line. `extra`: hue (a highlight), label (a beat), note (a note), group.
    static func make(_ script: PlayScript, _ lineID: String, _ start: Int, _ end: Int, _ kind: MarkKind,
                     _ extra: MarkExtra = MarkExtra(), now: Int64 = nowMillis()) -> Mark? {
        guard let line = script.lines.first(where: { $0.id == lineID }) else { return nil }
        return make(line: line, revision: Self.rev(script), start, end, kind, extra, now: now)
    }

    static func make(line: ScriptLine, revision: String?, _ start: Int, _ end: Int, _ kind: MarkKind,
                     _ extra: MarkExtra = MarkExtra(), now: Int64 = nowMillis()) -> Mark {
        let lt = text(of: line)
        let s = max(0, min(start, lt.count))
        let e = kind.isSpan ? max(s, min(end, lt.count)) : s
        let q = quote(lt, s, e)
        var m = Mark(id: newID(now), kind: kind, line: line.id, start: s, end: e, text: q.text, prefix: q.prefix, suffix: q.suffix,
                     revision: revision, created: now, updated: now)
        if kind == .highlight { m.hue = extra.hue.flatMap { MarkHue.all.contains($0) ? $0 : nil } ?? MarkHue.all[0] }
        if kind == .beat { m.label = String((extra.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(labelMax)) }
        if kind == .note { m.note = extra.note ?? "" }
        if let g = extra.group, kind.merges { m.group = g }
        return m
    }

    /// The marks a selection makes. `pieces` are the selection per line in reading order, in raw offsets. A span
    /// mark covers each piece grown to whole words (a note: its first line's piece only); highlights and underlines
    /// across lines share a group. A point mark goes after the last piece's last word.
    static func fromSelection(_ script: PlayScript, _ pieces: [MarkPiece], _ kind: MarkKind,
                              _ extra: MarkExtra = MarkExtra(), now: Int64 = nowMillis()) -> [Mark] {
        var byID: [String: ScriptLine] = [:]
        for l in script.lines where byID[l.id] == nil { byID[l.id] = l }
        var snapped: [(line: ScriptLine, lt: U16, start: Int, end: Int)] = []
        for p in pieces {
            guard let line = byID[p.line] else { continue }
            let lt = text(of: line)
            if let w = snapWords(lt, p.start, p.end) { snapped.append((line, lt, w.start, w.end)) }
        }
        guard let last = snapped.last else { return [] }
        if !kind.isSpan {
            let at = pointAfter(last.lt, last.end)
            return [make(line: last.line, revision: Self.rev(script), at, at, kind, extra, now: now)]
        }
        let use = kind == .note ? Array(snapped.prefix(1)) : snapped
        let group = use.count > 1 && kind.merges ? "g\(newID(now))" : nil
        return use.map { p in
            var x = extra
            x.group = group
            return make(line: p.line, revision: Self.rev(script), p.start, p.end, kind, x, now: now)
        }
    }

    /// Adds a mark by the overlap rules: a highlight or underline that overlaps or touches others of its kind in
    /// the line merges with them into one over all their words, taking the new mark's id, hue and group; a note is
    /// always its own; a breath, pause or beat replaces any point mark at its place.
    static func add(_ script: PlayScript, _ marks: [Mark], _ mark: Mark?) -> [Mark] {
        guard var mark else { return marks }
        var out = marks
        if mark.kind.merges {
            var s = mark.start, e = mark.end, grew = true
            var gone = Set<String>()
            while grew {
                grew = false
                for m in out where !gone.contains(m.id) && m.kind == mark.kind && m.line == mark.line {
                    if m.start <= e, s <= m.end {
                        gone.insert(m.id)
                        s = min(s, m.start)
                        e = max(e, m.end)
                        grew = true
                    }
                }
            }
            out = out.filter { !gone.contains($0.id) }
            if s != mark.start || e != mark.end {
                let lt = script.lines.first { $0.id == mark.line }.map(text(of:)) ?? []
                let q = quote(lt, s, e)
                mark.start = s
                mark.end = e
                mark.text = q.text
                mark.prefix = q.prefix
                mark.suffix = q.suffix
            }
        } else if !mark.kind.isSpan {
            out = out.filter { $0.kind.isSpan || $0.line != mark.line || $0.start != mark.start }
        }
        out.append(mark)
        return out
    }

    /// Removes a mark and the rest of its group, returning what went, so the removal can be undone.
    static func remove(_ marks: [Mark], _ id: String) -> (marks: [Mark], removed: [Mark]) {
        guard let m = marks.first(where: { $0.id == id }) else { return (marks, []) }
        func hit(_ x: Mark) -> Bool { x.id == id || (m.group != nil && x.group == m.group) }
        return (marks.filter { !hit($0) }, marks.filter(hit))
    }

    /// Changes a mark: a hue for its whole group, a beat's label, a note's words.
    static func update(_ marks: [Mark], _ id: String, _ patch: MarkPatch, now: Int64 = nowMillis()) -> [Mark] {
        guard let m = marks.first(where: { $0.id == id }) else { return marks }
        return marks.map { x in
            if x.id != id, !(patch.hue != nil && m.group != nil && x.group == m.group) { return x }
            var y = x
            y.updated = now
            if let h = patch.hue, x.kind == .highlight, MarkHue.all.contains(h) { y.hue = h }
            if x.id == id, let l = patch.label, x.kind == .beat {
                y.label = String(l.trimmingCharacters(in: .whitespacesAndNewlines).prefix(labelMax))
            }
            if x.id == id, let n = patch.note, x.kind == .note { y.note = n }
            return y
        }
    }

    // MARK: Re-anchoring a revision (PLAYS-DESIGN §2.10 rule 4)

    private static func commonTail(_ a: U16, _ b: U16) -> Int {
        var n = 0
        while n < a.count, n < b.count, a[a.count - 1 - n] == b[b.count - 1 - n] { n += 1 }
        return n
    }

    private static func commonHead(_ a: U16, _ b: U16) -> Int {
        var n = 0
        while n < a.count, n < b.count, a[n] == b[n] { n += 1 }
        return n
    }

    /// Every index `needle` begins at in `hay`, overlapping ones included, in order.
    private static func occurrences(_ needle: U16, in hay: U16) -> [Int] {
        guard !needle.isEmpty, needle.count <= hay.count else { return [] }
        var out: [Int] = []
        for k in 0...(hay.count - needle.count) where hay[k] == needle[0] {
            var ok = true
            var j = 1
            while j < needle.count { if hay[k + j] != needle[j] { ok = false; break }; j += 1 }
            if ok { out.append(k) }
        }
        return out
    }

    /// The best place for a mark in one line's words: where (context characters matched as `score`), or nil.
    static func bestIn(_ lt: U16, _ mark: Mark) -> (at: Int, score: Int, off: Int)? {
        let text = Array(mark.text.utf16), prefix = Array(mark.prefix.utf16), suffix = Array(mark.suffix.utf16)
        var at: [Int] = []
        func add(_ k: Int) { if !at.contains(k) { at.append(k) } }
        if !text.isEmpty {
            for k in occurrences(text, in: lt) { add(k) }
        } else {
            let tail = Array(prefix.suffix(16)), head = Array(suffix.prefix(16))
            if !tail.isEmpty { for k in occurrences(tail, in: lt) { add(k + tail.count) } }
            if !head.isEmpty { for k in occurrences(head, in: lt) { add(k) } }
            if tail.isEmpty, head.isEmpty { add(0) }
        }
        var best: (at: Int, score: Int, off: Int)?
        for k in at {
            let score = commonTail(prefix, Array(lt[0..<min(k, lt.count)]))
                + commonHead(suffix, Array(lt[min(lt.count, k + text.count)...]))
            let off = abs(k - mark.start)
            if best == nil || score > best!.score || (score == best!.score && off < best!.off) { best = (k, score, off) }
        }
        return best
    }

    /// Where a line id sorts among the script's ids (`L0009a` after `L0009`, before `L0010`), by plain string order.
    private static func sortIndex(_ ids: [U16], _ id: U16) -> Int {
        var i = 0
        while i < ids.count, ids[i].lexicographicallyPrecedes(id) { i += 1 }
        return i
    }

    /// Re-anchors stored marks to `script` as it is now. A placed mark carries its (maybe new) line, offsets, quote
    /// and this revision; a lost mark is returned exactly as stored. `changed` is true when any placed mark moved
    /// or took the new revision.
    static func place(_ script: PlayScript, _ marks: [Mark]) -> (placed: [Mark], lost: [Mark], changed: Bool) {
        let lines = script.lines
        let texts = lines.map(text(of:))
        let ids = lines.map(\.id)
        var index: [String: Int] = [:]
        for (i, id) in ids.enumerated() where index[id] == nil { index[id] = i }
        let idUnits = ids.map { Array($0.utf16) }
        let rev: String? = script.revision.isEmpty ? nil : script.revision
        var placed: [Mark] = [], lost: [Mark] = []
        var changed = false
        func put(_ m: Mark, _ i: Int, _ at: Int) {
            let end = at + m.text.utf16.count
            let q = quote(texts[i], at, end)
            var y = m
            y.line = ids[i]
            y.start = at
            y.end = end
            y.text = q.text
            y.prefix = q.prefix
            y.suffix = q.suffix
            y.revision = rev
            if y.line != m.line || y.start != m.start || y.end != m.end || y.revision != m.revision || y.prefix != m.prefix
                || y.suffix != m.suffix { changed = true }
            placed.append(y)
        }
        for m in marks {
            let text = Array(m.text.utf16)
            let own = index[m.line]
            // 1. The same revision, and the slice still reads the words.
            if let own, let rev, m.revision == rev, m.end <= texts[own].count, m.start <= m.end,
               Array(texts[own][m.start..<m.end]) == text {
                placed.append(m)
                continue
            }
            // 2. The same line: the best place its words (or a point mark's context) stand.
            let avail = m.prefix.utf16.count + m.suffix.utf16.count
            if let own, let b = bestIn(texts[own], m), !text.isEmpty || b.score >= min(pointEvidence, avail) {
                put(m, own, b.at)
                continue
            }
            // 3. Every other line, nearest first, on evidence.
            let from = own ?? sortIndex(idUnits, Array(m.line.utf16))
            var best: (at: Int, score: Int, off: Int, i: Int, dist: Int)?
            for i in lines.indices where i != own {
                guard let b = bestIn(texts[i], m) else { continue }
                let dist = abs(i - from)
                if best == nil || b.score > best!.score
                    || (b.score == best!.score && (dist < best!.dist || (dist == best!.dist && b.off < best!.off))) {
                    best = (b.at, b.score, b.off, i, dist)
                }
            }
            if let best, text.count + best.score >= min(evidence, text.count + avail), !text.isEmpty || best.score > 0 {
                put(m, best.i, best.at)
                continue
            }
            // 4. Not placed: kept as it was.
            lost.append(m)
        }
        return (placed, lost, changed)
    }

    // MARK: Order

    /// The notebook's order: script order (line, then offset), then the kinds' order.
    static func order(_ script: PlayScript, _ marks: [Mark]) -> [Mark] {
        var index: [String: Int] = [:]
        for (i, l) in script.lines.enumerated() where index[l.id] == nil { index[l.id] = i }
        let kinds = MarkKind.allCases
        return marks.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            let ix = index[x.line] ?? Int(1e9), iy = index[y.line] ?? Int(1e9)
            if ix != iy { return ix < iy }
            if x.start != y.start { return x.start < y.start }
            if x.end != y.end { return x.end < y.end }
            let kx = kinds.firstIndex(of: x.kind)!, ky = kinds.firstIndex(of: y.kind)!
            if kx != ky { return kx < ky }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Span marks at an offset in a line, the narrowest first (what a tap on the words opens), a note first.
    static func at(_ marks: [Mark], _ lineID: String, _ offset: Int) -> [Mark] {
        marks.enumerated().filter { $0.element.isSpan && $0.element.line == lineID && $0.element.start <= offset && offset < $0.element.end }
            .sorted { a, b in
                let wa = a.element.end - a.element.start, wb = b.element.end - b.element.start
                if wa != wb { return wa < wb }
                let na = a.element.kind == .note, nb = b.element.kind == .note
                if na != nb { return na }
                return a.offset < b.offset
            }.map(\.element)
    }
}

// MARK: - On the device

/// A play's marks, one JSON file per script in Application Support (`Marks/<script id>.json`, the web's shape
/// `{format: 1, script, title, marks: [...]}`). Never `UserDefaults` (it would grow without bound), never iCloud
/// until the sync phase; private to the device.
nonisolated struct MarkStore: Sendable {
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? URL.applicationSupportDirectory.appending(path: "Marks", directoryHint: .isDirectory)
    }

    struct File: Codable {
        var format: Int
        var script: String
        var title: String?
        var marks: [Lossy]

        /// One element that may not decode (an unknown kind is dropped on read, never the whole file).
        struct Lossy: Codable {
            var mark: Mark?
            init(_ m: Mark) { mark = m }
            init(from decoder: Decoder) throws { mark = try? Mark(from: decoder) }
            func encode(to encoder: Encoder) throws { try mark?.encode(to: encoder) }
        }
    }

    static func valid(_ m: Mark) -> Bool { m.start >= 0 && m.end >= m.start && !m.id.isEmpty }

    func url(_ scriptID: String) -> URL {
        let safe = scriptID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) ?? scriptID
        return root.appending(path: "\(safe).json")
    }

    /// A play's stored marks (`[]` when none or unreadable).
    func load(_ scriptID: String) -> [Mark] {
        guard let data = try? Data(contentsOf: url(scriptID)),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.marks.compactMap(\.mark).filter(Self.valid)
    }

    /// Stores a play's marks; throws when the device would not keep them (a full disk), so it is surfaced.
    func save(scriptID: String, title: String?, _ marks: [Mark]) throws {
        let fm = FileManager.default
        if marks.isEmpty {
            if fm.fileExists(atPath: url(scriptID).path) { try fm.removeItem(at: url(scriptID)) }
            return
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(File(format: 1, script: scriptID, title: title, marks: marks.map(File.Lossy.init)))
            .write(to: url(scriptID), options: .atomic)
    }

    /// Every play's marks on this device, for the person's own export, sorted by script id.
    func exportRows() -> [DataExport.MarkRow] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        var rows: [DataExport.MarkRow] = []
        for name in names {
            guard let data = try? Data(contentsOf: root.appending(path: name)),
                  let file = try? JSONDecoder().decode(File.self, from: data) else { continue }
            for m in file.marks.compactMap(\.mark).filter(Self.valid) {
                rows.append(DataExport.MarkRow(script: file.script, title: file.title, revision: m.revision, line: m.line, start: m.start,
                                               end: m.end, kind: m.kind.rawValue, text: m.text, hue: m.hue, label: m.label,
                                               note: m.note, created: Date(timeIntervalSince1970: Double(m.created) / 1000),
                                               updated: Date(timeIntervalSince1970: Double(m.updated) / 1000)))
            }
        }
        return rows.sorted { $0.script < $1.script }
    }

    // MARK: Prefs (`ed.marks.prefs`: whether marks show, the last highlight hue)

    static let prefsKey = "ed.marks.prefs"

    static func prefs(_ defaults: UserDefaults = .standard) -> (show: Bool, hue: String) {
        guard let raw = defaults.string(forKey: prefsKey), let data = raw.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (true, MarkHue.all[0]) }
        let hue = (o["hue"] as? String).flatMap { MarkHue.all.contains($0) ? $0 : nil } ?? MarkHue.all[0]
        return ((o["show"] as? Bool) ?? true, hue)
    }

    static func savePrefs(show: Bool, hue: String, _ defaults: UserDefaults = .standard) {
        let o: [String: Any] = ["show": show, "hue": hue]
        if let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), let s = String(data: data, encoding: .utf8) {
            defaults.set(s, forKey: prefsKey)
        }
    }
}
