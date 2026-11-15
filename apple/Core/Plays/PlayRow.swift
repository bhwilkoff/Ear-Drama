import Foundation

// One row of the published play library's index (contract §4.1, Decision 075/076): what a list draws without
// fetching the play's script. `cast` is each named speaker's speeches, largest first; `voices` counts the roles
// with at least `PlayScript.castableLines`. A row published before `cast` draws no cast and never throws.

nonisolated struct PlayRow: Codable, Hashable, Sendable, Identifiable, PlayListing {
    struct Rights: Codable, Hashable, Sendable {
        let bucket: String
        let evidence: [PlayScript.Evidence]
    }

    let id: String
    let revision: String
    let title: String
    var sortName: String? = nil
    var kind: String = "stage"
    var authors: [String] = []
    var year: Int? = nil
    var collection: String? = nil
    var indexVoices: Int? = nil
    var roleCount: Int? = nil
    var castIndex: [Int]? = nil
    var lines: Int? = nil
    var words: Int? = nil
    var indexMinutes: Int? = nil
    var rights: Rights? = nil
    var source: PlayScript.Source? = nil
    /// `scripts/<id>.json`, relative to the index.
    var path: String? = nil
    /// The first speeches with said words, each the role as printed and its words (contract §4.1).
    var openingIndex: [Speech]? = nil

    struct Speech: Codable, Hashable, Sendable {
        let role: String
        let text: String
    }

    private enum CodingKeys: String, CodingKey {
        case id, revision, title, kind, authors, year, collection, lines, words, rights, source, path
        case openingIndex = "opening"
        case sortName = "sort_name"
        case indexVoices = "voices"
        case roleCount = "roles"
        case indexMinutes = "minutes"
        case castIndex = "cast"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        revision = try c.decodeIfPresent(String.self, forKey: .revision) ?? ""
        title = try c.decode(String.self, forKey: .title)
        sortName = try c.decodeIfPresent(String.self, forKey: .sortName)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "stage"
        authors = try c.decodeIfPresent([String].self, forKey: .authors) ?? []
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        collection = try c.decodeIfPresent(String.self, forKey: .collection)
        indexVoices = try c.decodeIfPresent(Int.self, forKey: .indexVoices)
        roleCount = try c.decodeIfPresent(Int.self, forKey: .roleCount)
        castIndex = try c.decodeIfPresent([Int].self, forKey: .castIndex)
        lines = try c.decodeIfPresent(Int.self, forKey: .lines)
        words = try c.decodeIfPresent(Int.self, forKey: .words)
        indexMinutes = try c.decodeIfPresent(Int.self, forKey: .indexMinutes)
        rights = try c.decodeIfPresent(Rights.self, forKey: .rights)
        source = try c.decodeIfPresent(PlayScript.Source.self, forKey: .source)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        openingIndex = try? c.decodeIfPresent([Speech].self, forKey: .openingIndex)
    }

    /// A bundled script as a row, for the library that has not loaded: the same numbers the index would carry.
    init(script: PlayScript) {
        id = script.id
        revision = script.revision
        title = script.title
        sortName = script.sortName
        kind = script.kind
        authors = script.authors.compactMap(PlayScript.authorName)
        year = script.year
        indexVoices = script.voices
        roleCount = script.roles.count
        castIndex = script.castLines
        lines = script.lines.count
        words = script.roles.reduce(0) { $0 + $1.words }
        indexMinutes = script.minutes
        rights = Rights(bucket: script.rights.bucket, evidence: script.rights.evidence)
        source = script.source
        openingIndex = script.opening(n: 2).map { Speech(role: $0.name, text: $0.text) }
    }

    var voices: Int { indexVoices ?? 0 }
    var minutes: Int { max(1, indexMinutes ?? Int((Double(words ?? 0) / Double(PlayScript.wordsPerMinute)).rounded())) }
    var castLines: [Int] { castIndex ?? [] }
    var authorLine: String { authors.joined(separator: ", ") }
    var lineCount: Int { lines ?? 0 }

    /// Named speaking parts, of any size.
    var partCount: Int { castLines.isEmpty ? (roleCount ?? 0) : castLines.count }
}

nonisolated struct PlayRowIndex: Codable, Sendable {
    let format: Int?
    let plays: [PlayRow]
}
