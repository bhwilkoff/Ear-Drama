import Foundation

// One row of the published play library's index (contract §4.1, Decision 075/076): what a list draws without
// fetching the play's script. `cast` is each named speaker's speeches, largest first; `voices` counts the roles
// with a spoken line. A row published before `cast` draws no cast and never throws.

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
    /// Finding a play (contract §4.1, B31 C3), each absent in a library built before it: computed once by the
    /// catalog, never by a client.
    var form: String? = nil
    var hue: String? = nil
    var era: String? = nil
    var life: Life? = nil
    var oneAct = false
    var balance: String? = nil
    var subjects: [String] = []
    var locc: String? = nil
    var attributed = false
    var scenes: [Scene] = []
    /// The play's pictures (contract §4.1 `picture.kind`): `picture` leads a window only when it is of the play itself.
    var picture: PlayArt? = nil
    var titlePage: PlayArt? = nil
    var production: PlayArt? = nil
    var authorArt: PlayArt? = nil

    struct Life: Codable, Hashable, Sendable {
        var born: Int?
        var died: Int?
    }

    /// A scene for N voices (B31 §3.4): its first line, its heading as printed, the voices, the minutes, its parts.
    struct Scene: Codable, Hashable, Sendable {
        let line: String
        var heading: String? = nil
        let voices: Int
        var minutes: Int = 0
        var parts: [String] = []
        /// The scene's last line (contract §4.1), absent in a library built before it: such a scene opens the reader.
        var to: String? = nil

        init(line: String, to: String? = nil, heading: String? = nil, voices: Int, minutes: Int = 0, parts: [String] = []) {
            (self.line, self.to, self.heading, self.voices, self.minutes, self.parts) = (line, to, heading, voices, minutes, parts)
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            line = try c.decode(String.self, forKey: .line)
            to = (try? c.decodeIfPresent(String.self, forKey: .to)) ?? nil
            heading = try? c.decodeIfPresent(String.self, forKey: .heading)
            voices = try c.decode(Int.self, forKey: .voices)
            minutes = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? 0
            parts = (try? c.decodeIfPresent([String].self, forKey: .parts)) ?? []
        }
    }

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
        case form, hue, era, life, oneAct, balance, subjects, locc, attributed, scenes, picture, titlePage, production, authorArt
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
        // Each additive field is read on its own: one the client does not understand never loses the row.
        form = try? c.decodeIfPresent(String.self, forKey: .form)
        hue = try? c.decodeIfPresent(String.self, forKey: .hue)
        era = try? c.decodeIfPresent(String.self, forKey: .era)
        life = try? c.decodeIfPresent(Life.self, forKey: .life)
        oneAct = (try? c.decodeIfPresent(Bool.self, forKey: .oneAct)) ?? false
        balance = try? c.decodeIfPresent(String.self, forKey: .balance)
        subjects = (try? c.decodeIfPresent([String].self, forKey: .subjects)) ?? []
        locc = try? c.decodeIfPresent(String.self, forKey: .locc)
        attributed = (try? c.decodeIfPresent(Bool.self, forKey: .attributed)) ?? false
        scenes = ((try? c.decodeIfPresent([Lenient<Scene>].self, forKey: .scenes)) ?? []).compactMap(\.value)
        picture = try? c.decodeIfPresent(PlayArt.self, forKey: .picture)
        titlePage = try? c.decodeIfPresent(PlayArt.self, forKey: .titlePage)
        production = try? c.decodeIfPresent(PlayArt.self, forKey: .production)
        authorArt = try? c.decodeIfPresent(PlayArt.self, forKey: .authorArt)
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
        openingIndex = script.opening(n: 2).map { Speech(role: $0.name, text: $0.verse?.joined(separator: "\n") ?? $0.text) }
    }

    var voices: Int { indexVoices ?? 0 }
    var minutes: Int { max(1, indexMinutes ?? Int((Double(words ?? 0) / Double(PlayScript.wordsPerMinute)).rounded())) }
    var castLines: [Int] { castIndex ?? [] }
    var authorLine: String { authors.joined(separator: ", ") }
    var lineCount: Int { lines ?? 0 }

    /// Named speaking parts, of any size.
    var partCount: Int { castLines.isEmpty ? (roleCount ?? 0) : castLines.count }

    /// The first author's display name, or "".
    var firstAuthor: String { authors.first ?? "" }

    /// The play's label (B31 2.1): its name, first author, form's board, era, life and cast, all from the row.
    var labelItem: LabelItem {
        LabelItem(kind: .play, name: title, cast: castLines, author: firstAuthor.isEmpty ? nil : firstAuthor, hue: hue, era: era,
                  life: life.map { LabelItem.Life(born: $0.born, died: $0.died) })
    }

    /// What a play's window leads with outside its own page (B31 §1.4): a picture of the play itself (`work`,
    /// `production` or `book`), never its title page or its author's face; nil is the label.
    var windowPicture: Artwork? { picture.flatMap { PlayArt.windowKinds.contains($0.kind ?? "") ? $0.artwork : nil } }

    /// The play as a show tile's row: no run, the form's board (else neutral), and only a picture of the play.
    var tileRow: SeriesRow {
        SeriesRow(key: id, name: title, genre: hue, firstDate: nil, lastDate: nil, networks: [], episodeCount: 0, picture: windowPicture)
    }

    /// What leads the play's own page header: a picture of the play, else its title page, else a photograph of its
    /// production, else its author's portrait; nil is the label.
    var pageLead: Artwork? { windowPicture ?? titlePage?.artwork ?? production?.artwork ?? authorArt?.artwork }
}

/// A picture as the play library publishes it (contract §4.1): the URL, its size, credit, evidence, face box and,
/// on `picture`, what it shows.
nonisolated struct PlayArt: Codable, Hashable, Sendable {
    /// The kinds a tile, row, rail or TV window may lead with (`play_art.WINDOW_KINDS`).
    static let windowKinds: Set<String> = ["work", "production", "book"]

    let url: String
    var width: Int? = nil
    var height: Int? = nil
    var credit: String? = nil
    var evidence: String? = nil
    var face: String? = nil
    var kind: String? = nil

    var artwork: Artwork? {
        guard let u = URL(string: url) else { return nil }
        return Artwork(url: u, width: width, height: height, credit: credit, evidence: evidence.flatMap(URL.init(string:)),
                       face: Artwork.FaceBox(face))
    }
}

/// One element of a list decoded on its own, so a malformed one is dropped and the rest kept.
nonisolated struct Lenient<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

nonisolated struct PlayRowIndex: Codable, Sendable {
    let format: Int?
    let plays: [PlayRow]
    /// The index's facets (contract §4.1, B31 C3); nil in a library built before them.
    var facets: PlayFacets? = nil

    private enum CodingKeys: String, CodingKey { case format, plays, facets }

    init(format: Int?, plays: [PlayRow], facets: PlayFacets? = nil) {
        (self.format, self.plays, self.facets) = (format, plays, facets)
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format)
        plays = try c.decode([PlayRow].self, forKey: .plays)
        facets = try? c.decodeIfPresent(PlayFacets.self, forKey: .facets)
    }
}

/// The facets the catalog counted over the whole library (contract §4.1): the voice and minute bins, the form, era
/// and balance values (`value` null for "Not named" or undated), subjects and LoCC most first, the one-act count.
nonisolated struct PlayFacets: Codable, Hashable, Sendable {
    struct Bin: Codable, Hashable, Sendable {
        let min: Int
        var max: Int?
    }
    struct Value: Codable, Hashable, Sendable {
        var value: String?
        var count: Int = 0

        init(value: String?, count: Int = 0) { (self.value, self.count) = (value, count) }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = try? c.decodeIfPresent(String.self, forKey: .value)
            count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        }
    }

    var voices: [Bin]? = nil
    var minutes: [Bin]? = nil
    var form: [Value]? = nil
    var era: [Value]? = nil
    var balance: [Value]? = nil
    var subjects: [Value]? = nil
    var locc: [Value]? = nil
    var oneAct: Int? = nil

    init(voices: [Bin]? = nil, minutes: [Bin]? = nil, form: [Value]? = nil, era: [Value]? = nil, balance: [Value]? = nil,
         subjects: [Value]? = nil, locc: [Value]? = nil, oneAct: Int? = nil) {
        (self.voices, self.minutes, self.form, self.era, self.balance) = (voices, minutes, form, era, balance)
        (self.subjects, self.locc, self.oneAct) = (subjects, locc, oneAct)
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voices = try? c.decodeIfPresent([Bin].self, forKey: .voices)
        minutes = try? c.decodeIfPresent([Bin].self, forKey: .minutes)
        form = try? c.decodeIfPresent([Value].self, forKey: .form)
        era = try? c.decodeIfPresent([Value].self, forKey: .era)
        balance = try? c.decodeIfPresent([Value].self, forKey: .balance)
        subjects = try? c.decodeIfPresent([Value].self, forKey: .subjects)
        locc = try? c.decodeIfPresent([Value].self, forKey: .locc)
        oneAct = try? c.decodeIfPresent(Int.self, forKey: .oneAct)
    }
}
