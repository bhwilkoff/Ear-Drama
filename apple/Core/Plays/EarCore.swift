import Foundation

// Casting an episode by ear (PLAYS-DESIGN §13 item 10, iOS-DESIGN §4.22; Decision 088.3), as plain functions over
// OwnScript: which line is lit, what has been heard, what a tap does, what a key means. The port of js/ear-core.js,
// held to js/ear.test.js case for case (EarTests). No view, no audio, no storage.
//
// NOTHING HERE PROPOSES A SPEAKER. A line is somebody's only by a tap, or by coming after one while the episode played
// (OwnScript.castOf). It is told where the audio is, and never hears it.

nonisolated enum EarCore {
    /// A first listen starts slow (R4 §2.4 rule 2); Back goes this far.
    static let speed: Float = 0.75
    static let backSeconds: Double = 5
    /// The shortest a line plays for on Hear It: a cue's share can be a tenth of a second.
    static let leastMs: Int64 = 700

    /// What tells this transcript from another: its words and its times.
    static func signature(_ cues: [OwnCue]) -> String {
        String(PlayBrowse.fnv1a64(cues.map { "\($0.at?.start ?? 0)-\($0.at?.end ?? 0) \($0.text)" }.joined(separator: "\n")), radix: 16)
    }

    /// Nil when these cues can be cast, or why not.
    static func refusal(_ doc: OwnDoc) -> OwnRefusal? {
        if doc.lines.isEmpty { return .no_lines }
        return doc.lines.count > OwnScript.maxLines ? .too_many_lines : nil
    }

    /// A part's hue key by the one rule every surface shares (`PlayScript.partHue`): the first seven speaking parts, largest first,
    /// ties by who came first. A part with no line yet has none. `parts` is in the order they were named.
    static func hue(_ name: String?, in parts: [OwnPart]) -> String? {
        guard let name else { return nil }
        let ranked = parts.enumerated().filter { $0.element.lines > 0 }
            .sorted { $0.element.lines != $1.element.lines ? $0.element.lines > $1.element.lines : $0.offset < $1.offset }
        guard let i = ranked.firstIndex(where: { $0.element.name == name }), i < PlayScript.partHues.count else { return nil }
        return PlayScript.partHues[i]
    }

    /// The parts in the order they were named, which is their number and their hue: `names`, then any the lines hold.
    static func parts(_ doc: OwnDoc, names: [String]) -> [OwnPart] {
        let cast = OwnScript.castOf(doc)
        var order = names
        var count: [String: Int] = [:]
        for l in doc.lines {
            guard case let .role(name)?? = cast[l.k] else { continue }
            if count[name] == nil, !order.contains(name) { order.append(name) }
            count[name, default: 0] += 1
        }
        return order.map { OwnPart(name: $0, lines: count[$0] ?? 0) }
    }

    /// A line as it is drawn. `named` says the speaker (or Left out) is not the line above's, so it is printed.
    struct Row: Equatable, Sendable, Identifiable {
        let k: Int
        let text: String
        let kind: String
        let who: OwnWho?
        let named: Bool
        var id: Int { k }
    }

    static func rows(_ doc: OwnDoc) -> [Row] {
        let cast = OwnScript.castOf(doc)
        var before: OwnWho?
        return doc.lines.map { l in
            let who: OwnWho? = l.kind == "open" || l.kind == "speech" ? (cast[l.k] ?? nil) : nil
            defer { before = who }
            return Row(k: l.k, text: l.text, kind: l.kind, who: who, named: who != nil && who != before)
        }
    }

    /// How long a line is played for on its own, in milliseconds.
    static func span(_ at: OwnSpan) -> (from: Int64, until: Int64) { (at.start, max(at.end, at.start + leastMs)) }

    /// Where casting is taken up again, in milliseconds: the place it was left, never past the last line.
    static func place(_ ear: OwnRecord.Ear?, _ doc: OwnDoc) -> Int64 {
        let last = doc.lines.compactMap(\.at).reduce(Int64(0)) { max($0, $1.end) }
        guard let p = ear?.place, p > 0, p < last else { return 0 }
        return p
    }

    // MARK: Keys

    enum Key: Equatable, Sendable { case part(Int), toggle, back, undo }

    enum Press: Equatable, Sendable { case character(Character), left }

    /// What a key does here, or nil. Keys held with another are the system's, but Undo's own.
    static func key(_ press: Press, command: Bool = false, control: Bool = false, option: Bool = false, shift: Bool = false) -> Key? {
        if command || control {
            if !shift, !option, case let .character(c) = press, c == "z" || c == "Z" { return .undo }
            return nil
        }
        if option || shift { return nil }
        switch press {
        case .left: return .back
        case let .character(c):
            if let n = c.wholeNumberValue, c.isASCII, n >= 1 { return .part(n - 1) }
            if c == " " { return .toggle }
            return c == "u" || c == "U" ? .undo : nil
        }
    }
}

/// One sitting. `doc` is OwnScript's; every change makes a new one. `lit` is the line being said (0 before the first).
/// `tick` is told the audio's place as it plays; `jumped` that the place was moved by hand, so the lines between are
/// not heard.
nonisolated struct EarSession: Sendable {
    private(set) var doc: OwnDoc
    private(set) var names: [String]
    var takes: Set<String>
    private(set) var lit = 0
    /// The last line the audio reached without a jump.
    private var from = 0
    private var sampled: [String: Int] = [:]
    /// The order of the names before each rename, with the undo depth it made, for its Undo.
    private var renames: [(depth: Int, names: [String])] = []

    init(doc: OwnDoc, names: [String] = [], takes: Set<String> = []) {
        self.doc = doc
        self.names = names
        self.takes = takes
    }

    private var env: OwnEnv { OwnEnv(takes: takes) }

    private mutating func take(_ r: OwnResult) -> OwnRefusal? {
        if r.refusal == nil { doc = r.doc }
        return r.refusal
    }

    /// Where the audio is now. While `playing`, the line and those since the last tick are heard. Answers what changed.
    mutating func tick(_ ms: Int64, playing: Bool) -> (moved: Bool, heard: Bool) {
        let k = OwnScript.lineAt(doc, ms)
        let moved = k != lit
        lit = k
        guard playing, k != 0 else { return (moved, false) }
        // Already heard by the tick before: nothing new can be.
        if from == k { return (moved, false) }
        let next = OwnScript.hear(doc, k, from: from)
        from = k
        if next.heard.count == doc.heard.count { return (moved, false) }
        // A carried part never reaches a line that was recorded as something else.
        if !takes.isEmpty {
            let was = OwnScript.castOf(doc), now = OwnScript.castOf(next)
            if doc.lines.contains(where: { l in (l.id.map(takes.contains) ?? false) && was[l.k] != now[l.k] }) {
                from = 0
                return (moved, false)
            }
        }
        doc = next
        return (moved, true)
    }

    mutating func jumped() { from = 0 }

    /// The lit line, and those after it as they are heard, are `name`'s. A refusal, or nil.
    mutating func give(_ name: String) -> OwnRefusal? { lit == 0 ? .no_such_line : take(OwnScript.tap(doc, lit, .role(name), env)) }
    mutating func leaveOut() -> OwnRefusal? { lit == 0 ? .no_such_line : take(OwnScript.tap(doc, lit, .out, env)) }

    /// Names a voice. With a line lit it is theirs, as a tap is.
    mutating func add(_ raw: String) -> (name: String, refusal: OwnRefusal?) {
        let name = OwnScript.partName(OwnScript.normalize(raw))
        if let why = OwnScript.partNameRefusal(name) { return (name, why) }
        let known = parts.contains { $0.name == name }
        let refusal = lit != 0 ? give(name) : nil
        if refusal == nil, !known { names.append(name) }
        return (name, refusal)
    }

    mutating func undo() -> OwnRefusal? {
        let why = take(OwnScript.apply(doc, OwnOp(op: .undo)))
        while why == nil, let last = renames.last, last.depth > doc.undo.count { names = last.names; renames.removeLast() }
        return why
    }

    /// A part's name on every line of theirs, and in its place in the order; a name another part has joins the two. One step.
    mutating func rename(_ from: String, _ raw: String) -> (name: String, refusal: OwnRefusal?) {
        let name = OwnScript.partName(OwnScript.normalize(raw))
        let all = parts
        let held = all.first { $0.name == from }
        if let why = OwnScript.partNameRefusal(name) { return (name, why) }
        guard let held else { return (name, .no_such_part) }
        if name == from { return (name, nil) }
        let before = names
        if held.lines > 0 {
            if let refusal = take(OwnScript.apply(doc, OwnOp(op: .rename, part: from, rename: name), env)) { return (name, refusal) }
            renames.append((doc.undo.count, before))
        }
        let order = all.map(\.name)
        names = order.contains(name) ? order.filter { $0 != from } : order.map { $0 == from ? name : $0 }
        return (name, nil)
    }
    /// One line alone, from its sheet: a part, Direction or Sound. The line after it keeps the cast it had.
    mutating func assign(_ k: Int, _ to: OwnTarget) -> OwnRefusal? { take(OwnScript.apply(doc, OwnOp(op: .assign, line: k, to: to), env)) }
    mutating func leaveOutLine(_ k: Int) -> OwnRefusal? { take(OwnScript.leaveOutHeard(doc, k, env)) }
    mutating func apply(_ op: OwnOp) -> OwnRefusal? { take(OwnScript.apply(doc, op, env)) }
    /// Done gives each line its id, once.
    mutating func replace(_ next: OwnDoc) { doc = next }

    func line(_ k: Int) -> OwnLine? { doc.lines.first { $0.k == k } }
    var parts: [OwnPart] { EarCore.parts(doc, names: names) }
    func who(_ k: Int) -> OwnWho? { OwnScript.castOf(doc)[k] ?? nil }
    var count: (cast: Int, lines: Int) { OwnScript.castCount(doc) }
    var canUndo: Bool { !doc.undo.isEmpty }
    var cast: [OwnWho?] { let m = OwnScript.castOf(doc); return doc.lines.map { m[$0.k] ?? nil } }

    /// The next of a part's lines to play, after the one played last: how a person checks whether two voices are one.
    mutating func sample(_ name: String) -> OwnLine? {
        let cast = OwnScript.castOf(doc)
        let mine = doc.lines.filter { $0.at != nil && (cast[$0.k] ?? nil) == .role(name) }
        guard !mine.isEmpty else { return nil }
        let i = mine.firstIndex { $0.k == sampled[name] } ?? -1
        let l = mine[(i + 1) % mine.count]
        sampled[name] = l.k
        return l
    }
}

// MARK: - The transcript's times

/// archive.org's `.vtt` beside a shown transcript's `.txt` (R4 §1.3): the apps read it at `/download/`, where a
/// transcript is (CORS is a browser's rule).
nonisolated enum EarCues {
    enum Failure: Error, Equatable, Sendable {
        /// No transcript with times is there: no door.
        case missing
        case failed
    }

    /// The times' address, and only a transcript we show has one.
    static func url(_ transcript: URL?) -> URL? {
        guard let transcript, transcript.scheme == "https", transcript.host() == "archive.org" else { return nil }
        let path = transcript.path(percentEncoded: true)
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "download", path.hasSuffix(".autogenerated.txt") else { return nil }
        return URL(string: "https://archive.org" + path.dropLast(4) + ".vtt")
    }

    /// What was served, read: cues with times, or why not.
    static func cues(status: Int, text: String) throws -> [OwnCue] {
        if status == 404 || status == 403 { throw Failure.missing }
        guard 200...299 ~= status else { throw Failure.failed }
        let cues = OwnScript.parseCues(text).filter { $0.at != nil }
        guard !cues.isEmpty else { throw Failure.missing }
        return cues
    }
}

/// The cues read this session, so an episode's page and its casting ask once; a failure is asked for again.
actor EarCueCache {
    static let shared = EarCueCache()
    private var kept: [URL: [OwnCue]] = [:]
    private let fetch: @Sendable (URL) async throws -> (String, Int)

    init(fetch: @escaping @Sendable (URL) async throws -> (String, Int) = { try await APIClient.shared.transcriptCues($0) }) {
        self.fetch = fetch
    }

    func cues(_ transcript: URL?) async throws -> [OwnCue] {
        guard let url = EarCues.url(transcript) else { throw EarCues.Failure.missing }
        if let have = kept[url] { return have }
        let (text, status): (String, Int)
        do { (text, status) = try await fetch(url) } catch { throw EarCues.Failure.failed }
        let cues = try EarCues.cues(status: status, text: text)
        kept[url] = cues
        return cues
    }
}
