import Foundation
import Testing

/// Finding a play (B31 §3), FindCore held to js/find.test.js's own fixture: an index shaped as contract §4.1 publishes
/// it (never the real catalog's contents), the facets and their counts against each other, rails that never repeat a
/// play, search by title, character and spoken line (the words in order before scattered ones), a library built before
/// B31 decoding with none of it, and negative controls.
struct FindCoreTests {
    private static func row(_ id: String, _ title: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var r: [String: Any] = ["id": id, "revision": "r", "title": title,
                                "sort_name": title.replacingOccurrences(of: #"^(The|A) "#, with: "", options: .regularExpression),
                                "authors": [extra["author"] as? String ?? "Ann Writer"], "voices": 2, "minutes": 10, "cast": [10, 8]]
        for (k, v) in extra where k != "author" { r[k] = v }
        return r
    }

    private static let indexJSON: [String: Any] = [
        "format": 1,
        "plays": [
            row("a", "Alpha", ["voices": 2, "minutes": 8, "form": "comedy", "era": "1900-1930", "balance": "ensemble", "oneAct": true,
                               "subjects": ["Ireland"], "locc": "PR",
                               "scenes": [["line": "L0003", "heading": "Scene I", "voices": 2, "minutes": 4, "parts": ["JACK", "JILL"]]]]),
            row("b", "Beta", ["voices": 4, "minutes": 35, "form": "tragedy", "era": "1800s", "balance": "lead", "locc": "PT"]),
            row("c", "The Gamma", ["voices": 2, "minutes": 15, "era": "1800s", "balance": "mixed", "locc": "PR",
                                   "scenes": [["line": "L0010", "heading": "Act II", "voices": 2, "minutes": 6, "parts": ["ANN", "BOB"]],
                                              ["line": "L0090", "heading": "Act III", "voices": 3, "minutes": 3, "parts": ["A", "B", "C"]],
                                              ["line": 7, "voices": "two"]]]),
            row("d", "Delta", ["voices": 12, "minutes": 120, "form": "melodrama", "balance": "ensemble", "locc": "PS"]),
            row("e", "Epsilon", ["voices": 6, "minutes": 50, "form": "comedy", "era": "1600s", "balance": "mixed", "author": "Ben Bard", "locc": "PR"]),
            row("f", "Zeta", ["voices": 3, "minutes": 9, "form": "comedy", "era": "1600s", "balance": "mixed", "author": "Ben Bard", "locc": "PR",
                              "picture": ["url": "https://example.org/w.jpg", "width": 800, "height": 600, "kind": "work"],
                              "titlePage": ["url": "https://example.org/t.jpg", "width": 800, "height": 1200]]),
        ],
        "facets": [
            "voices": [["min": 1, "max": 2, "count": 2], ["min": 3, "max": 4, "count": 2], ["min": 5, "max": 6, "count": 1],
                       ["min": 7, "max": 10, "count": 0], ["min": 11, "max": NSNull(), "count": 1]],
            "minutes": [["min": 1, "max": 10, "count": 2], ["min": 11, "max": 20, "count": 1], ["min": 21, "max": 40, "count": 1],
                        ["min": 41, "max": 90, "count": 1], ["min": 91, "max": NSNull(), "count": 1]],
            // melodrama is on one play, under foldUnder: the index counts it under "Not named" (value null).
            "form": [["value": "comedy", "count": 3], ["value": "tragedy", "count": 1], ["value": NSNull(), "count": 2]],
            "era": [["value": "1600s", "count": 2], ["value": "1800s", "count": 2], ["value": "1900-1930", "count": 1], ["value": NSNull(), "count": 1]],
            "balance": [["value": "ensemble", "count": 2], ["value": "mixed", "count": 3], ["value": "lead", "count": 1]],
            "subjects": [["value": "Ireland", "count": 1]],
            "locc": [["value": "PR", "count": 4], ["value": "PT", "count": 1], ["value": "PS", "count": 1]],
            "oneAct": 1,
        ],
    ]

    private static let index: PlayRowIndex = {
        let data = try! JSONSerialization.data(withJSONObject: indexJSON)
        return try! JSONDecoder().decode(PlayRowIndex.self, from: data)
    }()
    private static var rows: [PlayRow] { index.plays }

    private static let collections = PlayCollections(data: [
        .init(id: "two-voices", title: "Plays for two voices", count: 2, plays: ["a", "c"]),
        .init(id: "ten-minutes", title: "Ten minutes or less", count: 2, plays: ["a", "f"]),
        .init(id: "one-act", title: "One Act Plays", count: 1, plays: ["a"]),
        .init(id: "author-bard", title: "Ben Bard", kind: "author", count: 2, plays: ["e", "f"]),
    ])

    @Test func theFacetsAreTheIndexs() throws {
        let facets = FindCore.facets(Self.index.facets)
        #expect(facets.map(\.key) == ["voices", "length", "balance", "form", "era", "subject", "locc", "oneact"])
        let form = try #require(facets.first { $0.key == "form" })
        #expect(form.values.map(\.label) == ["Comedy", "Tragedy", "Not named"])
        #expect(form.of(Self.rows[3]) == ["none"], "a folded form (melodrama, under five) counts as Not named")
        #expect(FindCore.offered(["voices": "3-5", "form": "comedy", "nope": "x"], facets) == ["form": "comedy"], "an old band is dropped")
        #expect(facets.first { $0.key == "length" }?.values.map(\.label) == ["Up to 10 min", "10-20 min", "20-40 min", "40-90 min", "Longer"])
        #expect(facets.first { $0.key == "voices" }?.values.map(\.label) == ["1-2", "3-4", "5-6", "7-10", "11+"])
    }

    @Test func countsRunAgainstTheOtherPicks() throws {
        let facets = FindCore.facets(Self.index.facets)
        let c = FindCore.counts(Self.rows, facets, ["form": "comedy"])
        #expect(c.first { $0.key == "voices" }?.values.map { "\($0.value):\($0.count)" } == ["1-2:1", "3-4:1", "5-6:1"])
        let form = try #require(c.first { $0.key == "form" }?.values)
        #expect(form.first { $0.value == "comedy" }?.count == 3 && form.first { $0.value == "tragedy" }?.count == 1)
        let chosen = FindCore.counts(Self.rows, facets, ["voices": "7-10"]).first { $0.key == "voices" }?.values ?? []
        #expect(chosen.contains { $0.value == "7-10" && $0.count == 0 }, "a chosen empty value stays")
        for f in FindCore.counts(Self.rows, facets, ["era": "1600s"]) {
            for x in f.values {
                var picks = ["era": "1600s"]
                picks[f.key] = x.value
                #expect(FindCore.filter(Self.rows, facets, picks).count == x.count, "\(f.key)=\(x.value)")
            }
        }
    }

    @Test func theWaysInNeverRepeatAPlay() {
        let rs = FindCore.rails(Self.rows, Self.collections)
        #expect(rs.map(\.id) == ["scenes-2", "ten-minutes"])
        #expect(rs.last?.plays.map(\.id) == ["f"], "Ten minutes drops Alpha, which the scenes rail holds")
        var seen = Set<String>()
        for r in rs {
            for id in (r.plays.map(\.id) + r.scenes.map(\.row.id)) { #expect(seen.insert(id).inserted, "\(id) twice") }
        }
        #expect(rs.first?.count == 2, "the scenes rail counts every play with a scene for two")
        #expect(!rs.contains { $0.kind == .editor }, "no editor rail from an empty file")
        var ed = Self.collections
        ed.editor = [.init(id: "ed1", title: "For a pair", by: "Ben", plays: ["c", "a", "gone"])]
        let first = FindCore.rails(Self.rows, ed).first
        #expect(first?.kind == .editor && first?.by == "Ben" && first?.plays.map(\.id) == ["c", "a"], "the editor's rail leads, ids that do not resolve dropped")
        #expect(FindCore.rails(Self.rows, nil).map(\.id) == ["scenes-2"], "no collections file: the scenes rail alone")
    }

    @Test func aCollectionKeepsItsOrderAndThePlaysNeighbors() {
        #expect(FindCore.collection(Self.rows, Self.collections, id: "ten-minutes")?.plays.map(\.id) == ["a", "f"])
        #expect(FindCore.collection(Self.rows, Self.collections, id: "nope") == nil)
        #expect(FindCore.sameShape(Self.rows, Self.rows[0]).map(\.id) == ["c", "f"])
        let by = FindCore.byAuthor(Self.rows, Self.collections, Self.rows[4])
        #expect(by.id == "author-bard" && by.plays.map(\.id) == ["f"])
    }

    @Test func searchByTitleAuthorAndCharacter() {
        #expect(FindCore.titleHits(Self.rows, "gam").map(\.id) == ["c"])
        #expect(FindCore.titleHits(Self.rows, "ben").map(\.id) == ["e", "f"])
        let names = ["CANDIDA": [[0, 141], [3, 77]], "LADY CANDIDA": [[1, 5]], "BOB": [[2, 9]], "OUT OF RANGE": [[99, 4]]]
        #expect(FindCore.characterHits(Self.rows, names, "candida").map { "\($0.row.id):\($0.lines)" } == ["a:141", "d:77", "b:5"])
        #expect(FindCore.titleCase("LADY BRACKNELL") == "Lady Bracknell" && FindCore.titleCase("1 AVOC") == "1 Avoc")
    }

    @Test func saidShardsIntersectEveryWord() async throws {
        let shards: [String: FindCore.Shard] = ["qu": ["quality": [0, 2], "qualityless": [1]], "me": ["mercy": [2, 1], "mercyful": [1], "merry": [0]]]
        let got = try await FindCore.saidPlays("quality of mercy") { shards[$0] ?? [:] }
        #expect(got.exact == [2] && got.all == [1, 2])
        #expect(try await FindCore.saidPlays("the quality") { shards[$0] ?? [:] }.all.isEmpty)
        #expect(try await FindCore.saidPlays("of") { _ in [:] }.all.isEmpty)
    }

    @Test func lineShardsIntersectAtTheLine() async throws {
        let shards: [String: FindCore.Shard] = ["qu": ["quality": [0, 2, 3, 4, 2, 1, 1]], "me": ["mercy": [0, 1, 7, 2, 1, 4, 3, 1, 0]]]
        #expect(FindCore.decodeLines(shards["me"]!["mercy"]!).map { "\($0.play):\($0.lines)" } == ["0:[7]", "2:[4]", "5:[0]"])
        let got = try #require(try await FindCore.lineCandidates("quality of mercy") { shards[$0] ?? [:] })
        #expect(got.cands == [FindCore.Candidate(play: 0, lines: [7])])
        #expect(try await FindCore.lineCandidates("quality") { _ in nil } == nil, "no line shards: nil, and the caller falls back")
        let pre = try #require(try await FindCore.lineCandidates("qual") { shards[$0] ?? [:] })
        #expect(pre.prefix.contains("qual") && pre.cands.count == 2)
        #expect(FindCore.termFile("quality") == "qu" && FindCore.termFile("élan") == "xe96c")
    }

    private static func script(_ lines: [ScriptLine]) -> PlayScript {
        PlayScript(id: "s", revision: "r", kind: "stage", title: "S", authors: [], source: .init(name: "S", url: ""),
                   rights: .init(bucket: "script_source_cleared", evidence: []), roles: [], lines: lines)
    }
    private static func say(_ id: String, _ role: String, _ text: String, kind: ScriptLine.Kind = .speech) -> ScriptLine {
        kind == .speech ? ScriptLine(id: id, kind: .speech, role: role, parts: [.say(text)]) : ScriptLine(id: id, kind: kind, source: text)
    }

    /// The two lines the web's first build showed for "quality of mercy" (Landor's Citation, The Two Noble Kinsmen), and Portia.
    @Test func aLineHoldsEveryWordAndThePhraseLeads() throws {
        let row = Self.rows[0], q = "quality of mercy"
        let citation = Self.script([Self.say("L1", "SIR THOMAS", "on another of very different quality; that the plain sense"),
                                    Self.say("L2", "SIR THOMAS", "Have mercy upon us.")])
        let kinsmen = Self.script([Self.say("L1", "EMILIA", "alters to The quality of his thoughts, and mercy follows")])
        let merchant = Self.script([Self.say("L9", "PORTIA", "The quality of mercy is not strain\u{2019}d, It droppeth as the gentle rain")])
        #expect(FindCore.lineHit(citation, row: row, q, places: nil) == nil, "the words in different lines are no hit")
        let k = try #require(FindCore.lineHit(kinsmen, row: row, q, places: nil))
        #expect(!k.phrase)
        let m = try #require(FindCore.lineHit(merchant, row: row, q, places: nil))
        #expect(m.phrase && m.line == "L9" && m.role == "Portia")
        #expect(FindCore.shownHits([k, m]) == [m] && FindCore.shownHits([k]) == [k])
        #expect(FindCore.lineHit(Self.script([Self.say("L1", "A", "QUALITY -- of... Mercy!")]), row: row, q, places: nil)?.phrase == true)
        let candidate = Self.script([Self.say("L1", "A", "He is a candidate.")])
        #expect(FindCore.lineHit(candidate, row: row, "candida", places: nil) == nil, "a whole word, not a prefix")
        #expect(FindCore.lineHit(candidate, row: row, "candida", places: nil, prefix: ["candida"]) != nil)
        #expect(FindCore.lineHit(Self.script([Self.say("L1", "", q, kind: .direction)]), row: row, q, places: nil) == nil, "never a direction")
        #expect(FindCore.lineHit(Self.script([Self.say("L0", "A", q), Self.say("L1", "A", "x")]), row: row, q, places: [1]) == nil,
                "only the line places the shards name")
        #expect(FindCore.snippet(String(repeating: "word ", count: 60) + "mercy " + String(repeating: "tail ", count: 40), "mercy", max: 60).hasPrefix("…"))
        #expect(FindCore.snippet("beside _Geltrude_ and _Candida_", "candida") == "beside Geltrude and Candida")
    }

    @Test func theBudgetAndTheReadingOrder() throws {
        func r(_ id: String, _ title: String, _ words: Int) throws -> PlayRow {
            try JSONDecoder().decode(PlayRow.self, from: JSONSerialization.data(withJSONObject: ["id": id, "title": title, "words": words]))
        }
        let rs = [try r("x", "Mercy Me", 20000), try r("y", "Y", 300000), try r("z", "Z", 10000)]
        let o = FindCore.orderCandidates([.init(play: 1, lines: [1, 2, 3]), .init(play: 2, lines: [1]), .init(play: 0, lines: [5])], rs, "mercy")
        #expect(o.map(\.row.id) == ["x", "y", "z"])
        #expect(FindCore.nextBatch(o, from: 0, budget: 200000) == 1)
        #expect(FindCore.nextBatch(o, from: 1, budget: 200000) == 2, "one script over the budget is still read alone")
    }

    /// An old library: rows and an index with none of the new fields decode, and the facets fall back to voices and length.
    @Test func aLibraryBuiltBeforeB31StillReads() throws {
        let old = try JSONDecoder().decode(PlayRowIndex.self, from: Data(#"{"format":1,"plays":[{"id":"o","title":"Old","voices":3,"minutes":20,"cast":[5,4,1]}]}"#.utf8))
        #expect(old.facets == nil && old.plays.first?.form == nil && old.plays.first?.scenes.isEmpty == true)
        let fs0 = FindCore.facets(nil)
        #expect(fs0.map(\.key) == ["voices", "length"])
        #expect(FindCore.counts(Self.rows, fs0, [:]).first { $0.key == "voices" }?.values.reduce(0) { $0 + $1.count } == Self.rows.count)
        // A malformed scene is dropped, the rest kept; a picture of the play leads the window, a title page only the page.
        #expect(Self.rows[2].scenes.map(\.line) == ["L0010", "L0090"])
        #expect(Self.rows[5].windowPicture?.url.lastPathComponent == "w.jpg" && Self.rows[0].windowPicture == nil)
        let titleOnly = try JSONDecoder().decode(PlayRow.self, from: Data(#"{"id":"t","title":"T","picture":{"url":"https://e.org/t.jpg","kind":"titlePage"},"titlePage":{"url":"https://e.org/t.jpg"}}"#.utf8))
        #expect(titleOnly.windowPicture == nil && titleOnly.pageLead?.url.lastPathComponent == "t.jpg", "a title page never leads a window")
        let junk = try JSONDecoder().decode(PlayRowIndex.self, from: Data(#"{"plays":[{"id":"j","title":"J","form":7,"life":"x","picture":3}],"facets":"x"}"#.utf8))
        #expect(junk.plays.count == 1 && junk.facets == nil, "a field the client does not understand never loses the row")
    }

    /// Negative control: a rail builder that forgets what it has shown repeats a play the test above would catch.
    @Test func theRepeatCheckSeesARepeat() {
        let shown = FindCore.rails(Self.rows, Self.collections).flatMap { $0.plays.map(\.id) + $0.scenes.map(\.row.id) }
        let naive = ["a", "c"] + Self.collections.data.first { $0.id == "ten-minutes" }!.plays
        #expect(Set(shown).count == shown.count && Set(naive).count != naive.count)
    }
}

struct FindDoorTests {
    @Test func theFindDoorsParse() {
        let d = LaunchDoors.from(environment: ["APP_PLAY_QUERY": "quality of mercy", "APP_PLAY_PICKS": "form=comedy, voices=1-2,bad",
                                               "APP_BROWSE_SCOPE": "plays"], arguments: [])
        #expect(d.playQuery == "quality of mercy" && d.playPicks == ["form": "comedy", "voices": "1-2"] && d.browseScope == "plays")
        #expect(LaunchDoors.from(environment: [:], arguments: []).isEmpty)
    }
}
