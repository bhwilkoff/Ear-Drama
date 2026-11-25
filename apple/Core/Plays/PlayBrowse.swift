import Foundation

// Record's library (iOS-DESIGN §4.14, Decision 075; the web's js/plays-core.js): a play's voices and
// length from its own record, the three facets and the sort, and Today's play. The same rules, in the
// same words, on every platform; `catalog/tests/golden/todays_play.json` holds the pick.

nonisolated enum VoiceBand: String, CaseIterable, Sendable {
    case oneTwo = "1-2", threeFive = "3-5", sixTen = "6-10", elevenPlus = "11+"

    var title: String {
        switch self {
        case .oneTwo: "1 or 2 voices"
        case .threeFive: "3 to 5 voices"
        case .sixTen: "6 to 10 voices"
        case .elevenPlus: "11 or more voices"
        }
    }

    static func of(_ voices: Int) -> VoiceBand? {
        switch voices {
        case 1...2: .oneTwo
        case 3...5: .threeFive
        case 6...10: .sixTen
        case 11...: .elevenPlus
        default: nil
        }
    }
}

nonisolated enum LengthBand: String, CaseIterable, Sendable {
    case short, mid, long

    var title: String {
        switch self {
        case .short: "Under 30 min"
        case .mid: "30 to 60 min"
        case .long: "Over an hour"
        }
    }

    static func of(_ minutes: Int) -> LengthBand? {
        switch minutes {
        case ...29: .short
        case 30...60: .mid
        case 61...: .long
        default: nil
        }
    }
}

nonisolated enum PlayKindFacet: String, CaseIterable, Sendable {
    case radio, stage
    var title: String { self == .radio ? "Radio play" : "Stage play" }
}

nonisolated enum PlaySort: String, CaseIterable, Sendable {
    case voices, short, name

    var title: String {
        switch self {
        case .voices: "Fewest voices first"
        case .short: "Shortest first"
        case .name: "A to Z"
        }
    }

    /// The chip's label, which has to fit a 375 pt phone beside the other chips.
    var chipTitle: String {
        switch self {
        case .voices: "Fewest voices"
        case .short: "Shortest"
        case .name: "A to Z"
        }
    }
}

/// What a list of plays reads: a full script or a row of the published library's index (contract §4.1), so a
/// shelf of 650 plays never fetches a script. The index's own numbers win; a full script computes the same.
nonisolated protocol PlayListing: Sendable {
    var id: String { get }
    var title: String { get }
    var kind: String { get }
    var sortName: String? { get }
    var year: Int? { get }
    /// Speaking parts with at least `PlayScript.castableLines` speeches: the voices a person can cast.
    var voices: Int { get }
    var minutes: Int { get }
    /// Each speaking part's speeches, largest first.
    var castLines: [Int] { get }
    /// The authors as the record names them for reading.
    var authorLine: String { get }
    var lineCount: Int { get }
}

nonisolated extension PlayScript: PlayListing {
    /// Words a minute for a play's length: speech read aloud. A length is "About N min", never exact.
    static let wordsPerMinute = 150
    /// A role a person can cast has at least this many speeches (`script_parse.CASTABLE_LINES`).
    static let castableLines = 5

    /// The voices a person can cast: roles with `castableLines` speeches.
    var voices: Int {
        if !roles.isEmpty { return roles.filter { $0.lines >= Self.castableLines }.count }
        return castParts.filter { $0.id.isSpeaking }.count
    }

    /// Minutes from the words its parts speak, at least 1.
    var minutes: Int {
        let words = roles.reduce(0) { $0 + $1.words }
        return max(1, Int((Double(words) / Double(Self.wordsPerMinute)).rounded()))
    }

    var castLines: [Int] { castParts.filter { $0.id.isSpeaking }.map(\.lineCount) }
    var lineCount: Int { lines.count }

    static func todaysPlay(_ scripts: [PlayScript], dateKey: String) -> PlayScript? {
        PlayBrowse.todaysPlay(scripts, dateKey: dateKey)
    }

    /// The speaking parts the cast window draws: largest first, at most seven, and how many more there are.
    var castWindowBars: (shown: [CastPart], more: Int) {
        let speaking = castParts.filter { $0.id.isSpeaking }
        return (Array(speaking.prefix(7)), max(0, speaking.count - 7))
    }
}

nonisolated extension PlayListing {
    var voiceBand: VoiceBand? { VoiceBand.of(voices) }
    var lengthBand: LengthBand? { LengthBand.of(minutes) }
    var kindFacet: PlayKindFacet? { PlayKindFacet(rawValue: kind) }

    /// "3 voices", "About 30 min": the two facts a play tile says.
    var voicesText: String { voices == 1 ? "1 voice" : "\(voices.formatted()) voices" }
    var minutesText: String { "About \(minutes.formatted()) min" }

    var cast: CastSummary { CastSummary(lines: castLines) }
}

/// A play's cast as the speeches of each speaking part, largest first: all the window and the fingerprint draw.
nonisolated struct CastSummary: Equatable, Sendable {
    let lines: [Int]

    init(lines: [Int]) { self.lines = lines }
    init(script: PlayScript) { self.init(lines: script.castLines) }

    /// The first seven parts' bars and how many more there are.
    var window: (shown: [Int], more: Int) { (Array(lines.prefix(7)), max(0, lines.count - 7)) }

    /// Each part's share of the speaking lines.
    var shares: [Double] {
        let total = Double(lines.reduce(0, +))
        return total > 0 ? lines.map { Double($0) / total } : []
    }

    /// A part's mark color key by its place in the cast (the first seven, in order), or nil.
    static func hue(at index: Int) -> String? { index < PlayScript.partHues.count ? PlayScript.partHues[index] : nil }
}

/// A person's choice on Record: the three facets and the order.
nonisolated struct PlayFilter: Equatable, Sendable {
    var voices: VoiceBand?
    var length: LengthBand?
    var kind: PlayKindFacet?
    var sort: PlaySort = .voices

    var isFiltered: Bool { voices != nil || length != nil || kind != nil }
    var cleared: PlayFilter { PlayFilter(sort: sort) }
}

nonisolated enum PlayBrowse {
    enum Facet: Sendable { case voices, length, kind }

    /// Whether a play passes the filter, leaving out `skip`, so a facet's own counts ignore its own choice.
    static func keeps<S: PlayListing>(_ s: S, _ f: PlayFilter, skip: Facet? = nil) -> Bool {
        (skip == .voices || f.voices == nil || s.voiceBand == f.voices)
            && (skip == .length || f.length == nil || s.lengthBand == f.length)
            && (skip == .kind || f.kind == nil || s.kindFacet == f.kind)
    }

    private static func byName<S: PlayListing>(_ a: S, _ b: S) -> Bool {
        let ka = a.sortName ?? a.title, kb = b.sortName ?? b.title
        let c = ka.compare(kb, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: Locale(identifier: "en"))
        return c == .orderedSame ? a.id < b.id : c == .orderedAscending
    }

    static func list<S: PlayListing>(_ scripts: [S], _ f: PlayFilter) -> [S] {
        let kept = scripts.filter { keeps($0, f) }
        switch f.sort {
        case .voices:
            return kept.sorted { $0.voices != $1.voices ? $0.voices < $1.voices : byName($0, $1) }
        case .short:
            return kept.sorted { $0.minutes != $1.minutes ? $0.minutes < $1.minutes : byName($0, $1) }
        case .name:
            return kept.sorted(by: byName)
        }
    }

    /// How many plays a facet's option would leave, with the other two facets applied.
    static func count<S: PlayListing>(_ scripts: [S], _ f: PlayFilter, facet: Facet, matching: (S) -> Bool) -> Int {
        scripts.filter { keeps($0, f, skip: facet) && matching($0) }.count
    }

    static func fnv1a64(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return h
    }

    /// Today's play (WEB-DESIGN §4.2): the script whose FNV-1a 64 of "play:{YYYY-MM-DD}:{id}" is smallest,
    /// ties by id, on the person's own calendar date. Order-independent, so every platform with the same
    /// library and date picks the same play. Nil for an empty library.
    static func todaysPlay<S: PlayListing>(_ scripts: [S], dateKey: String) -> S? {
        var best: S?
        var bestHash: UInt64 = 0
        for script in scripts {
            let h = fnv1a64("play:\(dateKey):\(script.id)")
            if best == nil || h < bestHash || (h == bestHash && script.id < best!.id) {
                best = script
                bestHash = h
            }
        }
        return best
    }

    /// The scene pools in order (WEB-DESIGN §4.2, Decision 079): two voices and at most 20 minutes, else two or three
    /// voices and at most 30; else every play.
    static let scenePools: [(voices: ClosedRange<Int>, minutes: Int)] = [(2...2, 20), (2...3, 30)]

    /// The plays Today's scene picks from: the first pool with any play in it, else every play.
    static func scenePool<S: PlayListing>(_ scripts: [S]) -> [S] {
        for pool in scenePools {
            let kept = scripts.filter { pool.voices.contains($0.voices) && $0.minutes <= pool.minutes }
            if !kept.isEmpty { return kept }
        }
        return scripts
    }

    /// Today's scene: Today's play's hash over the scene pool, so every platform with the same library and date picks
    /// the same play (`catalog/tests/golden/todays_play.json` `scene`). Nil for an empty library.
    static func todaysScene<S: PlayListing>(_ scripts: [S], dateKey: String) -> S? {
        todaysPlay(scenePool(scripts), dateKey: dateKey)
    }
}

/// A play in a pick list: its id and the words that tell it apart.
nonisolated struct PlayPick: Equatable, Sendable, Identifiable {
    let id: String
    let label: String
}

nonisolated extension PlayBrowse {
    /// The plays as a pick list, by name (the class page; the web's `PlaysCore.pickList`): a title two plays share is
    /// told apart by its author, then by its length.
    static func pickList<S: PlayListing>(_ rows: [S]) -> [PlayPick] {
        let list = rows.sorted { a, b in
            let order = (a.sortName ?? a.title).compare(b.sortName ?? b.title, options: [.caseInsensitive, .diacriticInsensitive],
                                                        range: nil, locale: Locale(identifier: "en"))
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
        func apart(_ labels: [String], _ more: (S) -> String) -> [String] {
            let seen = Dictionary(labels.map { ($0, 1) }, uniquingKeysWith: +)
            return zip(labels, list).map { label, row in
                let extra = more(row)
                return seen[label, default: 0] > 1 && !extra.isEmpty ? "\(label), \(extra)" : label
            }
        }
        let labels = apart(apart(list.map(\.title), \.authorLine)) { "about \($0.minutes) min" }
        return zip(list, labels).map { PlayPick(id: $0.id, label: $1) }
    }
}

/// One of a play's opening speeches: the part, the role as printed, its said words cleaned for the page, and the line
/// (nil when it came from the index row's `opening`).
nonisolated struct OpeningSpeech: Equatable, Sendable, Identifiable {
    let part: PartID
    let name: String
    let text: String
    let lineID: String?
    /// The printed lines of a speech the reader sets as verse (`PlayPage`, the one detection), tidied as the words
    /// are; nil for prose, whose printed breaks are a transcriber's wrapping.
    var verse: [String]?
    var id: String { lineID ?? "\(name)|\(text)" }

    /// Verse lines as a page shows them, or nil when there is nothing to keep apart.
    static func verseLines(_ rows: [String]?) -> [String]? {
        guard let rows else { return nil }
        let kept = rows.enumerated().map { $0.offset == 0 ? clean($0.element) : tidy($0.element) }.filter { !$0.isEmpty }
        return kept.count > 1 ? kept : nil
    }

    private static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "--", with: "\u{2014}")
    }

    /// The words as a page shows them: emphasis marks dropped, whitespace collapsed, a leading stray `.,:;—-` dropped,
    /// and `--` set as an em dash (the web's `openingOf`).
    static func clean(_ text: String) -> String {
        tidy(text).replacingOccurrences(of: #"^[.,:;\x{2014}-]+\s*"#, with: "", options: .regularExpression)
    }
}

nonisolated extension PlayScript {
    /// The first `n` speeches with said words, in script order.
    func opening(n: Int = 4) -> [OpeningSpeech] {
        var out: [OpeningSpeech] = []
        let names = roles.map(\.name)
        for line in lines where line.kind == .speech {
            let text = OpeningSpeech.clean(line.spokenText)
            guard !text.isEmpty else { continue }
            out.append(OpeningSpeech(part: line.part, name: line.role ?? "", text: text, lineID: line.id,
                                     verse: OpeningSpeech.verseLines(PlayPage.verseRows(line, roles: names, emphasis: !isOwn))))
            if out.count >= n { break }
        }
        return out
    }

    static func todaysScene<S: PlayListing>(_ rows: [S], dateKey: String) -> S? {
        PlayBrowse.todaysScene(rows, dateKey: dateKey)
    }

    /// The voice Try a Line gives a person: the one that answers, the second speaker of the opening, else the second
    /// speaking part, else the first.
    func answeringPart(_ opening: [OpeningSpeech]) -> PartID? {
        var speakers: [PartID] = []
        for s in opening where !speakers.contains(s.part) { speakers.append(s.part) }
        let parts = castParts.map(\.id).filter(\.isSpeaking)
        if speakers.count > 1 { return speakers[1] }
        return parts.first { $0 != speakers.first } ?? speakers.first ?? parts.first
    }
}

nonisolated extension PlayRow {
    /// The index row's opening speeches (contract §4.1, already cut short), blanks dropped, at most `n`.
    func opening(n: Int = 4) -> [OpeningSpeech] {
        (openingIndex ?? []).prefix(n).compactMap { o in
            let text = OpeningSpeech.clean(o.text)
            return text.isEmpty ? nil : OpeningSpeech(
                part: .role(o.role), name: o.role, text: text, lineID: nil,
                verse: PlayPage.isVerse([o.text]) ? OpeningSpeech.verseLines(o.text.components(separatedBy: "\n")) : nil)
        }
    }
}

nonisolated extension Production {
    /// Any part still waiting for a performer.
    var hasOpenPart: Bool { parts.values.contains { $0.status == .open } }
}

nonisolated extension PlayBrowse {
    /// Home's Open Parts: this device's productions with a part still open, newest first, at most `limit`.
    static func openProductions(_ productions: [Production], limit: Int = 5) -> [Production] {
        Array(productions.filter { $0.hasOpenPart && !$0.isFinished }.sorted { $0.created > $1.created }.prefix(limit))
    }
}
