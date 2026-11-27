import Foundation

// Finding a play (B31 §3; iOS-DESIGN §4.14, §4.5; the web's js/find-core.js, the same rules in the same words): the
// facets, the ways in and the search over the play library's index, as pure functions with no views. Every value and
// bound comes from the catalog (contract §4.1 "Finding a play": the rows' `form`, `era`, `balance`, `subjects`,
// `locc`, `oneAct`, `scenes`; the index's `facets`; `collections.json`; `characters.json`; `search/lines/` and
// `search/said/`); this file only counts and filters what the catalog computed. Nothing ranks by attention.

/// The library's collections (contract §4.1 `collections.json`): the editor's, then the data's.
nonisolated struct PlayCollections: Codable, Hashable, Sendable {
    struct Collection: Codable, Hashable, Sendable, Identifiable {
        let id: String
        let title: String
        var by: String? = nil
        var note: String? = nil
        var rule: String? = nil
        var kind: String? = nil
        var count: Int? = nil
        var plays: [String] = []

        init(id: String, title: String, by: String? = nil, note: String? = nil, kind: String? = nil, count: Int? = nil, plays: [String] = []) {
            (self.id, self.title, self.by, self.note, self.kind, self.count, self.plays) = (id, title, by, note, kind, count, plays)
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            by = try? c.decodeIfPresent(String.self, forKey: .by)
            note = try? c.decodeIfPresent(String.self, forKey: .note)
            rule = try? c.decodeIfPresent(String.self, forKey: .rule)
            kind = try? c.decodeIfPresent(String.self, forKey: .kind)
            count = try? c.decodeIfPresent(Int.self, forKey: .count)
            plays = (try? c.decodeIfPresent([String].self, forKey: .plays)) ?? []
        }
    }

    var editor: [Collection] = []
    var data: [Collection] = []

    init(editor: [Collection] = [], data: [Collection] = []) { (self.editor, self.data) = (editor, data) }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        editor = ((try? c.decodeIfPresent([Lenient<Collection>].self, forKey: .editor)) ?? []).compactMap(\.value)
        data = ((try? c.decodeIfPresent([Lenient<Collection>].self, forKey: .data)) ?? []).compactMap(\.value)
    }
}

/// `characters.json`: every speaking part's printed name, each with `[play number, lines]` pairs, a play number being
/// the play's place in the index the file was built with.
nonisolated struct PlayCharacters: Decodable, Sendable {
    let names: [String: [[Int]]]
}

nonisolated enum FindCore {
    struct Option: Hashable, Sendable {
        let value: String
        let label: String
        var count = 0
    }

    struct Facet: Sendable {
        let key: String
        let label: String
        /// True for the ones that live in Filters, not the chips.
        var filter = false
        var values: [Option]
        let of: @Sendable (PlayRow) -> [String]
    }

    /// What a person chose: the facets' values by key, the sort, a collection or a scene count to show whole.
    struct State: Equatable, Sendable {
        var picks: [String: String] = [:]
        var sort = "voices"
        var collection: String? = nil
        var scenes = 0

        var isActive: Bool { !picks.isEmpty }
        var cleared: State { State(sort: sort) }
    }

    // The bins the catalog publishes (index.facets.voices / .minutes); these stand in only for a library built before
    // B31 C3 or the bundled scripts, and are the same numbers (B31 §3.1).
    static let voiceBins: [PlayFacets.Bin] = [.init(min: 1, max: 2), .init(min: 3, max: 4), .init(min: 5, max: 6), .init(min: 7, max: 10), .init(min: 11, max: nil)]
    static let minuteBins: [PlayFacets.Bin] = [.init(min: 1, max: 10), .init(min: 11, max: 20), .init(min: 21, max: 40), .init(min: 41, max: 90), .init(min: 91, max: nil)]

    static let formLabel = ["comedy": "Comedy", "farce": "Farce", "tragedy": "Tragedy", "tragicomedy": "Tragicomedy", "history": "History",
                            "fantasy": "Fairy and fantasy", "religious": "Religious", "melodrama": "Melodrama", "libretto": "Libretto"]
    static let balanceLabel = ["ensemble": "Ensemble", "mixed": "Mixed", "lead": "A star part"]
    // The Library of Congress's own class names for its P subclasses (the record's LoCC), shortened to the language.
    static let loccLabel = ["PA": "Greek and Latin", "PB": "Celtic", "PC": "Romance", "PD": "Germanic", "PE": "English language",
                            "PF": "Dutch and Frisian", "PG": "Slavic", "PH": "Finnish and Hungarian", "PJ": "Middle Eastern",
                            "PK": "Indian and Iranian", "PL": "East Asian", "PM": "Indigenous American", "PN": "General",
                            "PQ": "French, Italian, Spanish", "PR": "English", "PS": "American", "PT": "German, Dutch, Scandinavian",
                            "PZ": "Children\u{2019}s"]
    static let sorts: [(key: String, title: String)] = [("voices", "Fewest voices"), ("short", "Shortest"), ("name", "A to Z")]
    static func sortTitle(_ key: String) -> String { sorts.first { $0.key == key }?.title ?? sorts[0].title }

    /// The data collections that lead, in this order, after the editor's (§3.1); the rest stay reachable by their id.
    static let railIDs = ["ten-minutes", "two-voices", "star-part", "one-act"]

    private static func binKey(_ b: PlayFacets.Bin) -> String { b.max.map { "\(b.min)-\($0)" } ?? "\(b.min)+" }
    private static func inBin(_ b: PlayFacets.Bin, _ n: Int) -> Bool { n >= b.min && (b.max.map { n <= $0 } ?? true) }

    /// The facets this library offers, in the web's order: Voices, Length, then the ones the index carries.
    static func facets(_ index: PlayFacets?) -> [Facet] {
        let F = index ?? PlayFacets()
        let vb = (F.voices?.isEmpty == false ? F.voices : nil) ?? voiceBins
        let mb = (F.minutes?.isEmpty == false ? F.minutes : nil) ?? minuteBins
        func vLabel(_ b: PlayFacets.Bin) -> String { b.max.map { $0 == b.min ? "\(b.min)" : "\(b.min)-\($0)" } ?? "\(b.min)+" }
        func mLabel(_ b: PlayFacets.Bin, _ i: Int) -> String {
            guard let max = b.max else { return "Longer" }
            return i == 0 ? "Up to \(max) min" : "\(b.min - 1)-\(max) min"
        }
        var out = [
            Facet(key: "voices", label: "Voices", values: vb.map { Option(value: binKey($0), label: vLabel($0)) },
                  of: { r in vb.filter { inBin($0, r.voices) }.map(binKey) }),
            Facet(key: "length", label: "Length", values: mb.enumerated().map { Option(value: binKey($1), label: mLabel($1, $0)) },
                  of: { r in mb.filter { inBin($0, r.indexMinutes ?? r.minutes) }.map(binKey) }),
        ]
        if let balance = F.balance {
            out.append(Facet(key: "balance", label: "How the lines are shared", filter: true,
                             values: balance.compactMap { v in v.value.flatMap { balanceLabel[$0] }.map { Option(value: v.value!, label: $0) } },
                             of: { r in r.balance.flatMap { balanceLabel[$0] != nil ? [$0] : nil } ?? [] }))
        }
        if let form = F.form {
            let named = Set(form.compactMap(\.value))
            out.append(Facet(key: "form", label: "Form",
                             values: form.compactMap { v in v.value.flatMap { formLabel[$0] }.map { Option(value: v.value!, label: $0) } }
                                 + [Option(value: "none", label: "Not named")],
                             // A form on fewer plays than the catalog's foldUnder is counted with Not named, as the index counts it.
                             of: { r in [r.form.flatMap { named.contains($0) ? $0 : nil } ?? "none"] }))
        }
        if let era = F.era {
            let named = Set(era.compactMap(\.value))
            out.append(Facet(key: "era", label: "Era",
                             values: era.compactMap { v in v.value.map { Option(value: $0, label: $0) } } + [Option(value: "none", label: "Undated")],
                             of: { r in [r.era.flatMap { named.contains($0) ? $0 : nil } ?? "none"] }))
        }
        if let subjects = F.subjects, !subjects.isEmpty {
            out.append(Facet(key: "subject", label: "Subject", filter: true,
                             values: subjects.compactMap { v in v.value.map { Option(value: $0, label: $0) } }, of: { $0.subjects }))
        }
        if let locc = F.locc, !locc.isEmpty {
            out.append(Facet(key: "locc", label: "Literature of the original", filter: true,
                             values: locc.compactMap { v in v.value.flatMap { loccLabel[String($0.prefix(2))] }.map { Option(value: v.value!, label: $0) } },
                             of: { r in r.locc.map { [$0] } ?? [] }))
        }
        if let n = F.oneAct, n > 0 {
            out.append(Facet(key: "oneact", label: "One act", filter: true, values: [Option(value: "1", label: "One act")],
                             of: { $0.oneAct ? ["1"] : [] }))
        }
        return out
    }

    /// The picks this library offers: a value its facets do not hold (an older choice, another library's band) is dropped,
    /// as the web drops an old link's.
    static func offered(_ picks: [String: String], _ facets: [Facet]) -> [String: String] {
        picks.filter { key, value in facets.first { $0.key == key }?.values.contains { $0.value == value } ?? false }
    }

    /// The rows that pass every pick but `skip`'s.
    static func filter(_ rows: [PlayRow], _ facets: [Facet], _ picks: [String: String], skip: String? = nil) -> [PlayRow] {
        let fs = facets.filter { $0.key != skip && picks[$0.key] != nil }
        if fs.isEmpty { return rows }
        return rows.filter { r in fs.allSatisfy { $0.of(r).contains(picks[$0.key]!) } }
    }

    /// Each facet's values with their counts against the other picks (WEB-DESIGN §10.5: no choice yields nothing); a
    /// value with no plays is left out unless it is the one chosen.
    static func counts(_ rows: [PlayRow], _ facets: [Facet], _ picks: [String: String]) -> [Facet] {
        facets.map { f in
            var c: [String: Int] = [:]
            for r in filter(rows, facets, picks, skip: f.key) { for v in f.of(r) { c[v, default: 0] += 1 } }
            var out = f
            out.values = f.values.map { var o = $0; o.count = c[$0.value] ?? 0; return o }.filter { $0.count > 0 || picks[f.key] == $0.value }
            return out
        }
    }

    /// A row's minutes for sorting and the facet (the index's own number when it has one).
    private static func minutesOf(_ r: PlayRow) -> Int { r.indexMinutes ?? r.minutes }

    static func byName(_ a: PlayRow, _ b: PlayRow) -> Bool {
        (a.sortName ?? a.title).compare(b.sortName ?? b.title, options: [.caseInsensitive, .diacriticInsensitive], range: nil,
                                        locale: Locale(identifier: "en")) == .orderedAscending
    }

    static func sorted(_ rows: [PlayRow], _ sort: String) -> [PlayRow] {
        switch sort {
        case "short": rows.sorted { minutesOf($0) != minutesOf($1) ? minutesOf($0) < minutesOf($1) : byName($0, $1) }
        case "name": rows.sorted(by: byName)
        default: rows.sorted {
            $0.voices != $1.voices ? $0.voices < $1.voices : minutesOf($0) != minutesOf($1) ? minutesOf($0) < minutesOf($1) : byName($0, $1)
        }
        }
    }

    // MARK: The ways in (B31 §3.1, §3.2)

    struct SceneHit: Hashable, Sendable, Identifiable {
        let row: PlayRow
        let scene: PlayRow.Scene
        var id: String { "\(row.id)|\(scene.line)" }
    }

    struct Rail: Sendable, Identifiable {
        enum Kind: Sendable { case editor, scenes, data }
        let kind: Kind
        let id: String
        let title: String
        var by: String? = nil
        var note: String? = nil
        let count: Int
        var plays: [PlayRow] = []
        var scenes: [SceneHit] = []
        var voices = 0
    }

    /// The rails: the editor's collections, then Scenes for two voices, then the data rails `railIDs` names. A play
    /// appears once on the screen: a rail drops a play a rail above it holds (Decision 081 rule 5), and a rail left with
    /// nothing is absent. `per` is how many a rail shows. The TV, which has no scenes and no grid, passes `scenes: false`
    /// and every data collection but the authors' (`tvIDs`).
    static func rails(_ rows: [PlayRow], _ collections: PlayCollections?, per: Int = 12, scenes withScenes: Bool = true,
                      ids: [String] = railIDs) -> [Rail] {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>(), out: [Rail] = []
        func take(_ ids: [String]) -> [PlayRow] {
            var got: [PlayRow] = []
            for id in ids {
                if got.count >= per { break }
                if let r = byID[id], !seen.contains(id) { got.append(r); seen.insert(id) }
            }
            return got
        }
        let C = collections ?? PlayCollections()
        for c in C.editor {
            let plays = take(c.plays)
            if !plays.isEmpty {
                out.append(Rail(kind: .editor, id: c.id, title: c.title, by: c.by, note: c.note, count: c.plays.filter { byID[$0] != nil }.count, plays: plays))
            }
        }
        let scenes = withScenes ? sceneRows(rows, voices: 2) : []
        var shown: [SceneHit] = []
        for s in scenes {
            if shown.count >= per { break }
            if !seen.contains(s.row.id) { shown.append(s); seen.insert(s.row.id) }
        }
        if !shown.isEmpty {
            out.append(Rail(kind: .scenes, id: "scenes-2", title: "Scenes for two voices", count: Set(scenes.map(\.row.id)).count, scenes: shown, voices: 2))
        }
        let data = Dictionary(C.data.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in ids {
            guard let c = data[id] else { continue }
            let plays = take(c.plays)
            if !plays.isEmpty { out.append(Rail(kind: .data, id: c.id, title: c.title, count: c.count ?? c.plays.count, plays: plays)) }
        }
        return out
    }

    /// The TV's data shelves: `railIDs` first, then every other data collection but an author's, in the file's order.
    static func tvIDs(_ collections: PlayCollections?) -> [String] {
        railIDs + (collections?.data ?? []).filter { $0.kind != "author" && !railIDs.contains($0.id) }.map(\.id)
    }

    /// One collection by id, editor's or data's, its plays in the collection's own order.
    static func collection(_ rows: [PlayRow], _ collections: PlayCollections?, id: String) -> (collection: PlayCollections.Collection, plays: [PlayRow])? {
        let C = collections ?? PlayCollections()
        guard let c = (C.editor + C.data).first(where: { $0.id == id }) else { return nil }
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return (c, c.plays.compactMap { byID[$0] })
    }

    /// Every scene for `voices` voices, a play's first one per play (text order), plays A to Z.
    static func sceneRows(_ rows: [PlayRow], voices: Int) -> [SceneHit] {
        rows.compactMap { r in r.scenes.first { $0.voices == voices && !$0.line.isEmpty }.map { SceneHit(row: r, scene: $0) } }
            .sorted { byName($0.row, $1.row) }
    }

    /// Same voices and length (B31 §3.5): within one voice and 15 minutes of the play, closest first, the play left out.
    static func sameShape(_ rows: [PlayRow], _ play: PlayRow, n: Int = 12) -> [PlayRow] {
        let v = play.voices, m = minutesOf(play)
        func d(_ r: PlayRow) -> Double { Double(abs(r.voices - v)) + Double(abs(minutesOf(r) - m)) / 15 }
        return Array(rows.filter { $0.id != play.id && abs($0.voices - v) <= 1 && abs(minutesOf($0) - m) <= 15 }
            .sorted { d($0) != d($1) ? d($0) < d($1) : byName($0, $1) }
            .prefix(n))
    }

    /// More by the author: the author's collection when the catalog published one, else the rows that name them first.
    static func byAuthor(_ rows: [PlayRow], _ collections: PlayCollections?, _ play: PlayRow, n: Int = 12) -> (plays: [PlayRow], id: String?, total: Int) {
        let name = play.firstAuthor
        guard !name.isEmpty else { return ([], nil, 0) }
        let c = (collections?.data ?? []).first { $0.kind == "author" && $0.title.hasSuffix(name) }
        let list = c.flatMap { collection(rows, collections, id: $0.id)?.plays } ?? rows.filter { $0.firstAuthor == name }.sorted(by: byName)
        let others = list.filter { $0.id != play.id }
        return (Array(others.prefix(n)), c?.id, others.count)
    }

    // MARK: Search (B31 §3.3): titles and authors, characters, spoken lines

    static func tokens(_ text: String) -> [String] { Transcript.tokens(text) }

    private static func authorText(_ r: PlayRow) -> String { r.authors.joined(separator: " ") }
    private static func prefixed(_ words: [String], _ text: String) -> Bool {
        let have = tokens(text)
        return words.allSatisfy { w in have.contains { $0.hasPrefix(w) } }
    }

    /// Plays whose title or author has every query word as a word prefix, A to Z.
    static func titleHits(_ rows: [PlayRow], _ q: String) -> [PlayRow] {
        let words = tokens(q)
        guard !words.isEmpty else { return [] }
        return rows.filter { prefixed(words, "\($0.title) \(authorText($0))") }.sorted(by: byName)
    }

    struct CharacterHit: Hashable, Sendable, Identifiable {
        let row: PlayRow
        let role: String
        let lines: Int
        var id: String { "\(row.id)|\(role)" }
    }

    /// Characters: a role whose printed name has every query word as a word prefix, most lines first. `rows` is the index
    /// the file was built with (play numbers are places in it).
    static func characterHits(_ rows: [PlayRow], _ names: [String: [[Int]]]?, _ q: String, n: Int = 20) -> [CharacterHit] {
        let words = tokens(q)
        guard !words.isEmpty, let names else { return [] }
        var out: [CharacterHit] = []
        for (name, plays) in names where prefixed(words, name) {
            for pair in plays where pair.count >= 2 && pair[0] >= 0 && pair[0] < rows.count {
                out.append(CharacterHit(row: rows[pair[0]], role: name, lines: pair[1]))
            }
        }
        return Array(out.sorted { a, b in
            if a.lines != b.lines { return a.lines > b.lines }
            if byName(a.row, b.row) != byName(b.row, a.row) { return byName(a.row, b.row) }
            return a.role < b.role
        }.prefix(n))
    }

    /// The words a line search reads: three letters or more, as the shards file them, each once.
    static func saidWords(_ q: String) -> [String] {
        var seen = Set<String>()
        return tokens(q).filter { $0.count >= 3 && seen.insert($0).inserted }
    }

    /// The shard a word is filed in (contract §4.1, the web projection's `term_file`): its first two letters, or "x" and
    /// their code points in hex when either is not a-z or 0-9.
    static func termFile(_ word: String) -> String {
        let p = String(word.unicodeScalars.prefix(2).map(Character.init))
        if p.count == 2, p.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) }) { return p }
        return "x" + word.unicodeScalars.prefix(2).map { String($0.value, radix: 16) }.joined()
    }

    typealias Shard = [String: [Int]]
    /// Reads one shard by its file name: nil when the library has no such directory (an older library), [:] when the
    /// shard holds no word.
    typealias ShardRead = @Sendable (String) async throws -> Shard?

    /// Play numbers whose spoken words hold every query word (search/said, delta-coded); `exact` where every word is whole.
    static func saidPlays(_ q: String, get: ShardRead) async throws -> (all: [Int], exact: [Int]) {
        let words = saidWords(q)
        guard !words.isEmpty else { return ([], []) }
        var all: Set<Int>?, exact: Set<Int>?
        for w in words {
            let terms = try await get(termFile(w)) ?? [:]
            var pre = Set<Int>(), ex = Set<Int>()
            for (t, deltas) in terms where t.hasPrefix(w) {
                var n = 0
                for d in deltas { n += d; pre.insert(n); if t == w { ex.insert(n) } }
            }
            all = all.map { $0.intersection(pre) } ?? pre
            exact = exact.map { $0.intersection(ex) } ?? ex
            if all?.isEmpty ?? true { return ([], []) }
        }
        return ((all ?? []).sorted(), (exact ?? []).sorted())
    }

    /// A word's line postings (search/lines) as play number to its line places, in play order.
    static func decodeLines(_ flat: [Int]) -> [(play: Int, lines: [Int])] {
        var out: [(Int, [Int])] = [], i = 0, play = 0
        while i + 1 < flat.count {
            play += flat[i]
            let n = flat[i + 1]
            var lines: [Int] = [], line = 0
            for k in 0..<n where i + 2 + k < flat.count { line += flat[i + 2 + k]; lines.append(line) }
            out.append((play, lines))
            i += 2 + n
        }
        return out
    }

    struct Candidate: Hashable, Sendable {
        let play: Int
        /// The line places to check; nil checks every speech (the search/said fallback).
        let lines: [Int]?
    }

    /// The plays with one speech line holding every query word, from the line shards, the rarest word intersected first.
    /// A word the shards hold whole is matched whole, else as a prefix (`prefix` names those). Nil when the library has
    /// no line shards.
    static func lineCandidates(_ q: String, get: ShardRead) async throws -> (cands: [Candidate], prefix: Set<String>)? {
        let words = saidWords(q)
        guard !words.isEmpty else { return ([], []) }
        var sets: [(m: [Int: Set<Int>], size: Int)] = [], prefix = Set<String>()
        for w in words {
            guard let terms = try await get(termFile(w)) else { return nil }
            let whole = terms[w] != nil
            if !whole { prefix.insert(w) }
            let keys = whole ? [w] : terms.keys.filter { $0.hasPrefix(w) }
            var m: [Int: Set<Int>] = [:], size = 0
            for k in keys {
                for (play, lines) in decodeLines(terms[k] ?? []) { m[play, default: []].formUnion(lines); size += lines.count }
            }
            sets.append((m, size))
        }
        sets.sort { $0.size < $1.size }
        var cur = sets[0].m
        for s in sets.dropFirst() {
            var next: [Int: Set<Int>] = [:]
            for (play, lines) in cur {
                guard let other = s.m[play] else { continue }
                let both = lines.intersection(other)
                if !both.isEmpty { next[play] = both }
            }
            cur = next
            if cur.isEmpty { break }
        }
        return (cur.map { Candidate(play: $0.key, lines: $0.value.sorted()) }.sorted { $0.play < $1.play }, prefix)
    }

    /// About how many bytes a script costs over the wire, from its spoken words (measured 2026-11-26: 3.3 gzipped bytes
    /// a word on average over a tenth of the library).
    static func scriptBytes(_ row: PlayRow) -> Int { Int((3.3 * Double(row.words ?? 3000) + 2000).rounded()) }

    struct Ordered: Sendable {
        let row: PlayRow
        let lines: [Int]?
        let named: Bool
        let play: Int
    }

    /// The order scripts are read in: a play whose title or author holds the words first, then the plays with the most
    /// lines holding them, then the index's order.
    static func orderCandidates(_ cands: [Candidate], _ rows: [PlayRow], _ q: String) -> [Ordered] {
        let words = tokens(q)
        return cands.filter { $0.play >= 0 && $0.play < rows.count }.map { c in
            let r = rows[c.play]
            return Ordered(row: r, lines: c.lines, named: prefixed(words, "\(r.title) \(authorText(r))"), play: c.play)
        }.sorted { a, b in
            if a.named != b.named { return a.named }
            let la = a.lines?.count ?? 0, lb = b.lines?.count ?? 0
            return la != lb ? la > lb : a.play < b.play
        }
    }

    /// The end of the next batch to read within `budget` bytes (at least one script).
    static func nextBatch(_ ordered: [Ordered], from: Int, budget: Int) -> Int {
        var i = from, used = 0
        while i < ordered.count, i == from || used + scriptBytes(ordered[i].row) <= budget {
            used += scriptBytes(ordered[i].row)
            i += 1
        }
        return i
    }

    struct LineHit: Hashable, Sendable, Identifiable {
        let row: PlayRow
        let line: String
        let role: String
        let text: String
        let phrase: Bool
        var id: String { "\(row.id)|\(line)" }
    }

    /// A play's best line for a query: one holding the exact phrase (every word in order, case and punctuation aside),
    /// else one holding every word. `places` limits the check to those line places (from the line shards); nil checks
    /// every speech. A word in `prefix` matches as a word prefix.
    static func lineHit(_ script: PlayScript, row: PlayRow, _ q: String, places: [Int]?, prefix: Set<String> = []) -> LineHit? {
        let words = tokens(q)
        guard !words.isEmpty else { return nil }
        func matches(_ w: String, _ h: String) -> Bool { h == w || (prefix.contains(w) && h.hasPrefix(w)) }
        let at = places.map { $0.compactMap { $0 >= 0 && $0 < script.lines.count ? script.lines[$0] : nil } } ?? script.lines
        var any: LineHit?
        for l in at where l.kind == .speech {
            let text = l.spokenText
            if text.isEmpty { continue }
            let have = tokens(text)
            guard words.allSatisfy({ w in have.contains { matches(w, $0) } }) else { continue }
            let role = titleCase(l.role ?? "")
            if have.count >= words.count {
                for i in 0...(have.count - words.count) where words.enumerated().allSatisfy({ matches($1, have[i + $0]) }) {
                    return LineHit(row: row, line: l.id, role: role, text: text, phrase: true)
                }
            }
            if any == nil { any = LineHit(row: row, line: l.id, role: role, text: text, phrase: false) }
        }
        return any
    }

    /// What the Lines section shows: only the exact-phrase hits when there is one, else every hit.
    static func shownHits(_ hits: [LineHit]) -> [LineHit] { hits.contains(where: \.phrase) ? hits.filter(\.phrase) : hits }

    /// The matched line cut near `max` characters around the words, with "…" where it was cut, emphasis marks dropped.
    static func snippet(_ text: String, _ q: String, max: Int = 120) -> String {
        let t = text.replacingOccurrences(of: "_", with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let chars = Array(t)
        if chars.count <= max { return t }
        let w = tokens(q).max { $0.count < $1.count } ?? ""
        var at = 0
        let folded = Array(t.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
        if !w.isEmpty, folded.count == chars.count {
            let wa = Array(w)
            if wa.count <= folded.count {
                for i in 0...(folded.count - wa.count) where Array(folded[i..<(i + wa.count)]) == wa
                    && (i == 0 || !(folded[i - 1].isLetter || folded[i - 1].isNumber)) {
                    at = i
                    break
                }
            }
        }
        var from = Swift.max(0, at - max / 4)
        if from > 0, let sp = chars[from...].firstIndex(of: " "), sp < at { from = sp + 1 }
        var to = min(chars.count, from + max)
        if to < chars.count, let sp = chars[...to].lastIndex(of: " "), sp > from + max / 2 { to = sp }
        return (from > 0 ? "…" : "") + String(chars[from..<to]) + (to < chars.count ? "…" : "")
    }

    /// A role's printed name in capitals read as a name: "LADY BRACKNELL" is "Lady Bracknell".
    static func titleCase(_ name: String) -> String {
        guard name == name.uppercased() else { return name }
        var out = "", up = true
        for ch in name.lowercased() {
            out.append(up && ch.isLetter ? Character(ch.uppercased()) : ch)
            up = ch.isWhitespace || "-'\u{2019}(".contains(ch)
        }
        return out
    }

    /// "Jack and Jill", "A, B and C".
    static func names(_ parts: [String]) -> String {
        let p = parts.map(titleCase)
        return p.count > 1 ? p.dropLast().joined(separator: ", ") + " and " + p.last! : p.joined()
    }

    /// A play's kicker (B31 §3.5): its kind, then its form and One act, each only when the record says it.
    static func kicker(kind: String, form: String?, oneAct: Bool) -> String {
        [kind == "radio" ? "Radio play" : "Stage play", form.flatMap { formLabel[$0] }, oneAct ? "One act" : nil]
            .compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}
