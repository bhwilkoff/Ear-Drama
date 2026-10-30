import Foundation

// Plays phase 1, pass the phone (docs/PLAYS-DESIGN.md). A castable script as the
// catalog built it (catalog/tools/build_castable_scripts.py): only scripts whose
// rights state is `castable` and whose parse is clean are in the file, and every
// word is the parser's exact slice of the printed text. Nothing here rewrites,
// summarizes, or fills in a word (§8 rule 2).

/// One part on the cast sheet: a speaking role as the script names it, or one of
/// the two parts "like any other" (§2.2), stage directions and sound effects.
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
        return self == .directions ? "Stage directions" : "Sound effects"
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

    init(id: String, kind: Kind, role: String? = nil, parts: [LinePart]? = nil, source: String? = nil) {
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
    let roles: [Role]
    let lines: [ScriptLine]

    var authorLine: String {
        authors.compactMap(\.name).map(Self.displayName).joined(separator: ", ")
    }

    /// The authors with their years where the record has them:
    /// "Henry Fisk Carlton (1893–1973)".
    var authorLineWithYears: String {
        authors.compactMap { author in
            author.name.map { name in
                let years = switch (author.born, author.died) {
                case let (born?, died?): " (\(born)–\(died))"
                case let (born?, nil): " (b. \(born))"
                case let (nil, died?): " (d. \(died))"
                case (nil, nil): ""
                }
                return Self.displayName(name) + years
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
    /// by first appearance), then sound effects and stage directions where the
    /// script has them (§2.2).
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
        let others = [PartID.sound, .directions].filter { counts[$0] != nil }
        return (speaking + others).map { CastPart(id: $0, lineCount: counts[$0]!) }
    }

    var speechLineIDs: [String] { lines.filter { $0.kind == .speech }.map(\.id) }
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
