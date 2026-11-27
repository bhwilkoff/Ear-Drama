import Foundation

// Plays phase 1, pass the phone (docs/PLAYS-DESIGN.md). A castable script as the
// catalog built it (catalog/tools/build_castable_scripts.py): only scripts whose
// rights state is `castable` and whose parse is clean are in the file, and every
// word is the parser's exact slice of the printed text. Nothing here rewrites,
// summarizes, or fills in a word (§8 rule 2).

/// One part on the cast sheet: a speaking role as the script names it, or one of
/// the two parts "like any other" (§2.2), stage directions and sound (B32 §3.1: effects and music).
nonisolated struct PartID: Hashable, Codable, Sendable, RawRepresentable, CodingKeyRepresentable, Comparable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    static func role(_ name: String) -> PartID { PartID(rawValue: "role:" + name) }
    static let directions = PartID(rawValue: "directions")
    static let sound = PartID(rawValue: "sound")

    /// The role's name as printed, or nil for the two non-speaking parts.
    var roleName: String? { rawValue.hasPrefix("role:") ? String(rawValue.dropFirst(5)) : nil }
    var isSpeaking: Bool { roleName != nil }

    var title: String {
        if let roleName { return roleName }
        return self == .directions ? "Stage directions" : "Sound"
    }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var codingKey: any CodingKey { Key(stringValue: rawValue) }
    init?<T: CodingKey>(codingKey: T) { rawValue = codingKey.stringValue }

    static func < (a: PartID, b: PartID) -> Bool { a.rawValue < b.rawValue }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// A piece of a speech, exactly as printed: what is said, and the directions,
/// mic positions, and sounds printed inside it.
nonisolated enum LinePart: Codable, Hashable, Sendable {
    case say(String)
    case direction(String)
    case mic(String)
    case sound(String)

    var text: String {
        switch self {
        case let .say(t), let .direction(t), let .mic(t), let .sound(t): t
        }
    }

    var isSaid: Bool { if case .say = self { true } else { false } }

    init(from decoder: any Decoder) throws {
        let object = try decoder.singleValueContainer().decode([String: String].self)
        guard let (key, value) = object.first, object.count == 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "one key per part"))
        }
        switch key {
        case "say": self = .say(value)
        case "mic": self = .mic(value)
        case "sound": self = .sound(value)
        default: self = .direction(value)
        }
    }

    func encode(to encoder: any Encoder) throws {
        let key = switch self {
        case .say: "say"
        case .direction: "direction"
        case .mic: "mic"
        case .sound: "sound"
        }
        var container = encoder.singleValueContainer()
        try container.encode([key: text])
    }
}

nonisolated struct ScriptLine: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case speech, sound, music, direction }
    let id: String
    let kind: Kind
    let role: String?
    let parts: [LinePart]?
    let source: String?
    /// Indexes into `parts` of the said parts the source printed in italics (the speaker's stress).
    let em: [Int]?

    init(id: String, kind: Kind, role: String? = nil, parts: [LinePart]? = nil, source: String? = nil, em: [Int]? = nil) {
        self.em = em
        self.id = id
        self.kind = kind
        self.role = role
        self.parts = parts
        self.source = source
    }

    var part: PartID {
        switch kind {
        case .speech: .role(role ?? "")
        case .direction: .directions
        case .sound, .music: .sound
        }
    }

    /// The words a performer (or a stand-in) says: the speech's said parts, or
    /// the whole printed block for a direction or a cue, which a person reads.
    var spokenText: String {
        if kind == .speech {
            return (parts ?? []).filter(\.isSaid).map(\.text).joined(separator: " ")
        }
        return source ?? ""
    }
}

nonisolated struct PlayScript: Codable, Identifiable, Sendable {
    struct Author: Codable, Hashable, Sendable {
        let name: String?
        let born: Int?
        let died: Int?
        /// How the record names the author for reading ("George Melville Baker"); the filed name is turned when absent.
        var display: String? = nil
    }
    struct Source: Codable, Hashable, Sendable {
        let name: String
        let url: String
    }
    struct Evidence: Codable, Hashable, Sendable {
        let claim: String?
        let src: String?
    }
    struct Rights: Codable, Hashable, Sendable {
        let bucket: String
        let evidence: [Evidence]
    }
    struct Role: Codable, Hashable, Sendable {
        let name: String
        let lines: Int
        let words: Int
        /// "high" or "low": the register of the part's stand-in voice, where the play's own print settles it
        /// (catalog DECISIONS 049). Auto-cast reads it; nothing on screen shows it.
        var register: String? = nil
    }

    let id: String
    let revision: String
    let kind: String
    let title: String
    let authors: [Author]
    /// The record's own year, when it has one (Decision 067: a play is marked
    /// only by facts from its record).
    var year: Int? = nil
    let source: Source
    let rights: Rights
    private(set) var roles: [Role]
    private(set) var lines: [ScriptLine]
    /// The key the A to Z order sorts on (`sort_name`), when the record has one.
    var sortName: String? = nil
    /// The printed act and scene headings the parser set aside (contract §4.1), for the reader's contents.
    private(set) var sections: [ScriptSection]? = nil
    /// The range this script is cut to (PLAYS-DESIGN §2.12), nil for the whole play; never stored or sent.
    private(set) var scope: ProductionRange? = nil
    private(set) var wholeBox: WholeScript? = nil
    /// An own script cast by ear: the episode it came from (PLAYS-DESIGN §13 item 10).
    var episode: String? = nil
    /// An own script: what a line with a take said before its words changed, oldest first (§13 item 4).
    var edits: [String: [LineEdit]]? = nil

    struct LineEdit: Codable, Hashable, Sendable {
        let until: Date
        let text: String
    }

    /// A person's own script (PLAYS-DESIGN §13): on this device only, so no Share, Read Together or Publish.
    var isOwn: Bool { kind == "own" }
    static func isOwnID(_ id: String) -> Bool { id.hasPrefix("own-") }

    private enum CodingKeys: String, CodingKey {
        case id, revision, kind, title, authors, year, source, rights, roles, lines, sections, episode, edits
        case sortName = "sort_name"
    }

    /// An author as the record names them for reading: `display`, else the filed name turned.
    static func authorName(_ author: Author) -> String? {
        if let display = author.display?.trimmingCharacters(in: .whitespaces), !display.isEmpty { return display }
        return author.name.map(displayName)
    }

    var authorLine: String {
        authors.compactMap(Self.authorName).joined(separator: ", ")
    }

    /// The authors with their years where the record has them:
    /// "Henry Fisk Carlton (1893–1973)".
    var authorLineWithYears: String {
        authors.compactMap { author in
            Self.authorName(author).map { name in
                let years = switch (author.born, author.died) {
                case let (born?, died?): " (\(born)–\(died))"
                case let (born?, nil): " (b. \(born))"
                case let (nil, died?): " (d. \(died))"
                case (nil, nil): ""
                }
                return name + years
            }
        }
        .joined(separator: ", ")
    }

    /// "12 parts · 840 lines": the speaking parts and every line of the script.
    var lengthLine: String {
        let parts = castParts.filter { $0.id.isSpeaking }.count
        return "\(parts) \(parts == 1 ? "part" : "parts") · \(lines.count.formatted()) \(lines.count == 1 ? "line" : "lines")"
    }

    /// "Carlton, Henry Fisk" as Gutenberg files it reads "Henry Fisk Carlton".
    static func displayName(_ filed: String) -> String {
        let pieces = filed.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard pieces.count == 2, !pieces[1].isEmpty, !pieces[1].first!.isNumber else { return filed }
        return pieces[1] + " " + pieces[0]
    }

    func lines(for part: PartID) -> [ScriptLine] { lines.filter { $0.part == part } }

    /// The parts on the cast sheet: speaking parts largest first (by lines, then
    /// by first appearance), then Sound on every script (its count the cue rows, B32 §3.1 item 1), then stage
    /// directions where the script has them (§2.2).
    var castParts: [CastPart] {
        var counts: [PartID: Int] = [:]
        var first: [PartID: Int] = [:]
        for (index, line) in lines.enumerated() {
            counts[line.part, default: 0] += 1
            if first[line.part] == nil { first[line.part] = index }
        }
        let speaking = counts.keys.filter(\.isSpeaking).sorted {
            counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : first[$0]! < first[$1]!
        }
        counts[.sound] = cueRows.count
        let others = [PartID.sound, .directions].filter { counts[$0] != nil }
        return (speaking + others).map { CastPart(id: $0, lineCount: counts[$0]!) }
    }

    var speechLineIDs: [String] { lines.filter { $0.kind == .speech }.map(\.id) }

    /// One of the script's cue rows, a slot the Sound part may fill (B32 §3.1): a sound or music line (`piece` nil), or
    /// inside a speech a printed sound piece or an aside beginning "sound of", "noise of" or "music" (`piece` its index).
    struct CueRow: Equatable, Sendable {
        let line: String
        let piece: Int?
        let text: String
    }

    /// The cue rows by the reader's rule (`PlayPage.isCueWords`), the mirror of `PlaysCore.cueRows`. Never filled in.
    var cueRows: [CueRow] {
        var out: [CueRow] = []
        for line in lines {
            if line.kind == .sound || line.kind == .music {
                out.append(CueRow(line: line.id, piece: nil, text: line.source ?? ""))
                continue
            }
            guard line.kind == .speech, let parts = line.parts else { continue }
            for (i, piece) in parts.enumerated() {
                switch piece {
                case let .sound(t): out.append(CueRow(line: line.id, piece: i, text: t))
                case let .direction(t) where PlayPage.isCueWords(t): out.append(CueRow(line: line.id, piece: i, text: t))
                default: break
                }
            }
        }
        return out
    }

    /// Each role's published stand-in register by part (catalog DECISIONS 049), only "high" or "low".
    var registers: [PartID: String] {
        var out: [PartID: String] = [:]
        for r in roles { if let g = r.register, g == "high" || g == "low" { out[.role(r.name)] = g } }
        return out
    }
}

/// The script a scoped one was cut from (a box, so a script can hold its own whole).
nonisolated final class WholeScript: Sendable {
    let script: PlayScript
    init(_ script: PlayScript) { self.script = script }
}

/// A scene's production range (B31 §3.4, PLAYS-DESIGN §2.12): two line ids of its script, the scene's first line and its
/// last. Both are in the production record, the Worker's record and the export, and never in the fingerprint.
nonisolated struct ProductionRange: Codable, Hashable, Sendable {
    let from: String
    let to: String

    /// The scene's heading as a range production's title prints it: "Adelphi, Scene II" gives "Scene II".
    static func heading(ofTitle title: String, play: String) -> String? {
        title.hasPrefix(play + ", ") ? String(title.dropFirst(play.count + 2)) : nil
    }

    static func title(_ play: String, heading: String?) -> String {
        guard let heading, !heading.isEmpty else { return play }
        return "\(play), \(heading)"
    }
}

/// A scene's range (PLAYS-DESIGN §2.12): every seam that pairs a production with its script reads `scoped(for:)`.
nonisolated extension PlayScript {
    /// The indexes the range spans, or nil when either bound is gone or they are out of order.
    func span(of range: ProductionRange) -> ClosedRange<Int>? {
        guard let a = lines.firstIndex(where: { $0.id == range.from }),
              let z = lines.firstIndex(where: { $0.id == range.to }), z >= a else { return nil }
        return a...z
    }

    /// The script cut to `range`: its lines, its sections there, and each role speaking there with its lines and words
    /// there, so voices and minutes are the range's. A script already cut, or a range that does not resolve, is returned as is.
    func scoped(to range: ProductionRange?) -> PlayScript {
        guard let range, scope == nil, let span = span(of: range) else { return self }
        let cut = Array(lines[span])
        let ids = Set(cut.map(\.id))
        var said: [String: (lines: Int, words: Int)] = [:]
        for line in cut where line.kind == .speech {
            guard let role = line.role else { continue }
            let words = (line.parts ?? []).filter(\.isSaid).reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            said[role, default: (0, 0)].lines += 1
            said[role, default: (0, 0)].words += words
        }
        var out = self
        out.lines = cut
        out.roles = roles.compactMap { r in said[r.name].map { Role(name: r.name, lines: $0.lines, words: $0.words, register: r.register) } }
        out.sections = sections?.filter { ids.contains($0.line) }
        out.scope = range
        out.wholeBox = WholeScript(self)
        return out
    }

    /// The script a production records: cut to its range, else whole.
    func scoped(for production: Production) -> PlayScript { scoped(to: production.range) }

    /// The whole script behind a scoped one.
    var whole: PlayScript { wholeBox?.script ?? self }

    /// True when the production's range no longer resolves in this script (rule 4).
    func rangeDrifted(_ production: Production) -> Bool {
        guard let range = production.range, scope == nil else { return false }
        return span(of: range) == nil
    }

    /// The parts a range's cast sheet lists; the whole play's when `range` is nil or does not resolve.
    func castParts(for range: ProductionRange?) -> [CastPart] { scoped(to: range).castParts }
}

/// A play stands on the drama board and its parts take the part marks
/// (direction D, D3-6). Scripts carry no genre, so no genre is ever named.
nonisolated extension PlayScript {
    static let boardGenre = "drama"
    /// The first seven speaking parts, largest first, in this order; every other part is neutral.
    static let partHues = ["mystery", "scifi", "western", "serial", "documentary", "comedy", "news"]

    /// A part's mark color key, or nil (directions, sound, and the eighth speaking part on).
    func partHue(_ part: PartID) -> String? {
        guard part.isSpeaking else { return nil }
        let speaking = castParts.filter { $0.id.isSpeaking }
        guard let i = speaking.firstIndex(where: { $0.id == part }), i < Self.partHues.count else { return nil }
        return Self.partHues[i]
    }

    /// Each speaking part's share of the speaking lines, largest first: the cast fingerprint.
    var castShares: [CastShare] {
        let speaking = castParts.filter { $0.id.isSpeaking }
        let total = Double(speaking.reduce(0) { $0 + $1.lineCount })
        guard total > 0 else { return [] }
        return speaking.map { CastShare(part: $0.id, share: Double($0.lineCount) / total) }
    }

    /// Where a part speaks: `bins` equal runs of the script, each the share of its lines the part speaks.
    func presence(of part: PartID, bins: Int = 24) -> [Double] {
        guard bins > 0, !lines.isEmpty else { return [] }
        let n = lines.count
        return (0..<bins).map { i in
            let run = lines[(i * n / bins)..<((i + 1) * n / bins)]
            return run.isEmpty ? 0 : Double(run.filter { $0.part == part }.count) / Double(run.count)
        }
    }
}

nonisolated struct CastShare: Equatable, Sendable {
    let part: PartID
    let share: Double
}

nonisolated struct CastPart: Identifiable, Hashable, Sendable {
    let id: PartID
    let lineCount: Int
    var title: String { id.title }
    /// "12 lines", or for Sound its cue rows: "34 cues", "Add sounds" with none (B32 §3.1 item 1).
    var lengthText: String {
        if id == .sound { return SoundBoard.cuesLength(lineCount) }
        return lineCount == 1 ? "1 line" : "\(lineCount.formatted()) lines"
    }
}

/// The bundled castable scripts (phase 1 bundles the file; PLAYS-DESIGN §3).
nonisolated struct CastableLibrary: Codable, Sendable {
    let format: Int
    let scripts: [PlayScript]

    static let resourceName = "castable-scripts"

    static func load(from bundle: Bundle = .main) -> CastableLibrary? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CastableLibrary.self, from: data)
    }
}
