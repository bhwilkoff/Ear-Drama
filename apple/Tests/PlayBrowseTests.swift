import Foundation
import Testing

// Record's library and Home's rows (Decision 075): the pick of Today's play is held to the golden file every
// platform shares, a play's voices and length to the web's test values, the author line to the record's own
// `display`, Open Parts to the productions' own part states, and On the air to the clock.

nonisolated private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func play(_ id: String, title: String = "T", kind: String = "radio", roles: [(String, Int)],
                  sortName: String? = nil, authors: [PlayScript.Author] = []) -> PlayScript {
    PlayScript(id: id, revision: "r1", kind: kind, title: title, authors: authors,
               source: .init(name: "S", url: "https://example.org"),
               rights: .init(bucket: "script_source_cleared", evidence: []),
               roles: roles.map { PlayScript.Role(name: $0.0, lines: PlayScript.castableLines, words: $0.1) },
               lines: roles.map { ScriptLine(id: "\(id)-\($0.0)", kind: .speech, role: $0.0, parts: [.say("x")]) },
               sortName: sortName)
}

struct PlayBrowseTests {
    @Test func todaysPlayMatchesTheGoldenFile() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("catalog/tests/golden/todays_play.json"))
        let golden = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hashes = try #require(golden["hashes"] as? [[String: String]])
        #expect(hashes.count >= 4)
        for h in hashes {
            let want = try #require(h["fnv1a64"]), text = try #require(h["text"])
            #expect(String(format: "%016llx", PlayBrowse.fnv1a64(text)) == want, "\(text)")
        }
        let allIDs = try #require(golden["ids"] as? [String])
        let cases = try #require(golden["cases"] as? [[String: Any]])
        #expect(cases.count >= 10)
        for c in cases {
            let date = try #require(c["date"] as? String)
            let ids = c["ids"] as? [String] ?? allIDs
            let scripts = ids.map { play($0, roles: [("A", 10)]) }
            #expect(PlayScript.todaysPlay(scripts, dateKey: date)?.id == c["want"] as? String, "\(date) \(ids)")
        }
    }

    @Test func todaysSceneMatchesTheGoldenFile() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("catalog/tests/golden/todays_play.json"))
        let golden = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let scene = try #require(golden["scene"] as? [String: Any])
        let rows = try #require(scene["rows"] as? [[String: Any]]).map { r in
            try JSONDecoder().decode(PlayRow.self, from: JSONSerialization.data(withJSONObject: r.merging(["title": "T"]) { a, _ in a }))
        }
        let cases = try #require(scene["cases"] as? [[String: Any]])
        #expect(cases.count >= 10)
        var differs = false
        for c in cases {
            let date = try #require(c["date"] as? String)
            let pool = (c["ids"] as? [String]).map { ids in rows.filter { ids.contains($0.id) } } ?? rows
            #expect(PlayScript.todaysScene(pool, dateKey: date)?.id == c["want"] as? String, "\(date) over \(pool.count)")
            if c["ids"] == nil, PlayBrowse.todaysPlay(rows, dateKey: date)?.id != c["want"] as? String { differs = true }
        }
        #expect(differs, "control: the scene is not today's play over every row")
    }

    @Test func sceneFallsBackThroughThePools() throws {
        func row(_ id: String, _ voices: Int, _ minutes: Int) throws -> PlayRow {
            try JSONDecoder().decode(PlayRow.self, from: Data(#"{"id":"\#(id)","title":"T","voices":\#(voices),"minutes":\#(minutes)}"#.utf8))
        }
        let lib = [try row("long2", 2, 255), try row("a", 2, 12), try row("b", 2, 17), try row("c", 3, 25), try row("big", 12, 175)]
        #expect(PlayBrowse.scenePool(lib).map(\.id) == ["a", "b"])
        #expect(PlayBrowse.scenePool([lib[0], lib[3], lib[4]]).map(\.id) == ["c"])
        #expect(PlayBrowse.scenePool([lib[0], lib[4]]).count == 2)
        #expect(PlayScript.todaysScene([PlayRow](), dateKey: "2026-11-15") == nil)
    }

    @Test func theOpeningIsSaidWordsCleaned() throws {
        let script = PlayScript(id: "o", revision: "r1", kind: "stage", title: "T", authors: [],
                                source: .init(name: "S", url: "https://example.org"),
                                rights: .init(bucket: "script_source_cleared", evidence: []), roles: [],
                                lines: [ScriptLine(id: "L1", kind: .direction, source: "_Night._"),
                                        ScriptLine(id: "L2", kind: .speech, role: "JIM", parts: [.direction("low"), .say("That's  a _full_ one.")]),
                                        ScriptLine(id: "L3", kind: .speech, role: "BILL", parts: [.direction("enters")]),
                                        ScriptLine(id: "L4", kind: .speech, role: "BILL", parts: [.say(". Why--hullo.")]),
                                        ScriptLine(id: "L5", kind: .speech, role: "JIM", parts: [.say("-- Well.")])])
        let o = script.opening(n: 4)
        #expect(o.map { "\($0.name)|\($0.text)|\($0.lineID ?? "")" } == ["JIM|That's a full one.|L2", "BILL|Why\u{2014}hullo.|L4", "JIM|Well.|L5"])
        #expect(o.first?.part == .role("JIM"))
        #expect(script.opening(n: 1).count == 1)
        let json = #"{"id":"x","title":"T","opening":[{"role":"A","text":"One."},{"role":"B","text":" "},{"role":"B","text":"Two."}]}"#
        let row = try JSONDecoder().decode(PlayRow.self, from: Data(json.utf8))
        #expect(row.opening(n: 4).map { $0.name + $0.text } == ["AOne.", "BTwo."])
        #expect(row.opening(n: 4).allSatisfy { $0.lineID == nil })
        let bare = try JSONDecoder().decode(PlayRow.self, from: Data(#"{"id":"y","title":"T","voices":2}"#.utf8))
        #expect(bare.opening(n: 4).isEmpty, "a row published before `opening` has none")
    }

    @Test func voicesMinutesAndBandsMatchTheWebValues() {
        let three = play("a", roles: [("A", 3000), ("B", 1500), ("C", 10)])
        #expect(three.voices == 3 && three.minutes == 30)
        #expect(three.voiceBand == .threeFive && three.lengthBand == .mid)
        #expect(play("b", roles: [("A", 100)]).minutes == 1)
        #expect(play("b", roles: [("A", 100)]).lengthBand == .short)
        let many = play("c", roles: (1...11).map { ("R\($0)", 10) })
        #expect(many.voiceBand == .elevenPlus)
        #expect(VoiceBand.of(2) == .oneTwo && VoiceBand.of(10) == .sixTen && VoiceBand.of(0) == nil)
        #expect(LengthBand.of(29) == .short && LengthBand.of(60) == .mid && LengthBand.of(61) == .long)
        #expect(three.voicesText == "3 voices" && play("d", roles: [("A", 1)]).voicesText == "1 voice")
        #expect(three.minutesText == "About 30 min")
    }

    @Test func castWindowDrawsSevenBarsAndCountsTheRest() {
        let ten = play("c", roles: (1...10).map { ("R\($0)", 10) })
        let cast = ten.castWindowBars
        #expect(cast.shown.count == 7 && cast.more == 3)
    }

    @Test func facetsCountWithTheOtherTwoAppliedAndSortsBreakTiesByName() {
        let scripts = [
            play("a", title: "Zebra", kind: "stage", roles: [("A", 100), ("B", 100)]),
            play("b", title: "apple", kind: "radio", roles: [("A", 100), ("B", 100)], sortName: "Apple"),
            play("c", title: "Mango", kind: "radio", roles: [("A", 9000), ("B", 100), ("C", 100)]),
        ]
        var filter = PlayFilter()
        #expect(PlayBrowse.list(scripts, filter).map(\.id) == ["b", "a", "c"], "fewest voices first, ties A to Z")
        filter.sort = .short
        #expect(PlayBrowse.list(scripts, filter).map(\.id) == ["b", "a", "c"])
        filter.sort = .name
        #expect(PlayBrowse.list(scripts, filter).map(\.id) == ["b", "c", "a"])
        filter.kind = .radio
        #expect(PlayBrowse.list(scripts, filter).map(\.id) == ["b", "c"])
        // Voices counts apply the kind but not the voices choice itself.
        #expect(PlayBrowse.count(scripts, filter, facet: .voices) { $0.voiceBand == .oneTwo } == 1)
        #expect(PlayBrowse.count(scripts, filter, facet: .voices) { $0.voiceBand == .threeFive } == 1)
        filter.length = .long
        #expect(PlayBrowse.list(scripts, filter).isEmpty == false)
        #expect(filter.isFiltered && !filter.cleared.isFiltered && filter.cleared.sort == .name)
    }

    @Test func authorsReadByTheirDisplayName() throws {
        let json = #"{"name":"Baker, George M. (George Melville)","display":"George Melville Baker","born":1832,"died":1890}"#
        let author = try JSONDecoder().decode(PlayScript.Author.self, from: Data(json.utf8))
        let filed = PlayScript.Author(name: "Carlton, Henry Fisk", born: nil, died: nil)
        let script = play("a", roles: [("A", 1)], authors: [author, filed])
        #expect(script.authorLine == "George Melville Baker, Henry Fisk Carlton")
        #expect(script.authorLineWithYears == "George Melville Baker (1832\u{2013}1890), Henry Fisk Carlton")
    }

    @Test func theBundledLibraryDecodesItsSortNames() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("catalog/plays/castable-scripts.json"))
        let library = try JSONDecoder().decode(CastableLibrary.self, from: data)
        #expect(library.scripts.count >= 15)
        #expect(library.scripts.allSatisfy { $0.sortName != nil })
        #expect(library.scripts.flatMap(\.authors).contains { $0.display != nil })
        #expect(PlayScript.todaysPlay(library.scripts, dateKey: "2026-11-14") != nil)
    }

    @Test func openPartsAreThisDevicesUnfinishedProductionsNewestFirst() {
        let script = play("a", roles: [("A", 1), ("B", 1)])
        func production(_ minutes: Double, open: Bool) -> Production {
            var p = Production(id: "p\(minutes)", script: script, created: Date(timeIntervalSince1970: minutes * 60))
            if !open { for key in p.parts.keys { p.parts[key]?.status = .done } }
            return p
        }
        let list = [production(1, open: true), production(3, open: false), production(2, open: true)]
        #expect(PlayBrowse.openProductions(list).map(\.id) == ["p2.0", "p1.0"])
        let many = (1...9).map { production(Double($0), open: true) }
        #expect(PlayBrowse.openProductions(many).count == 5)
    }
}

struct OnAirTests {
    private static func slot(_ start: Double, _ end: Double, episode: String?, withheld: Bool = false) -> RadioSlot {
        RadioSlot(etStart: "8:00", etEnd: "8:30", lengthMin: 30, utcStart: Date(timeIntervalSince1970: start),
                  utcEnd: Date(timeIntervalSince1970: end),
                  episode: episode.map { RadioSlot.Episode(id: "\($0)|1", series: $0.uppercased(), title: "Ep \($0)", lengthS: 1800) },
                  withheld: withheld)
    }

    private static let evening = TonightDay(evening: "1942-05-25", network: nil, station: nil, witness: nil,
                                            slots: [slot(1000, 2800, episode: "a"), slot(2800, 4600, episode: "b", withheld: true)])
    private static let station = Station(genre: "mystery", name: "Mystery",
                                         slots: [slot(0, 5000, episode: "m")])

    @Test func theEveningWinsWhenAnEpisodeIsOnNow() throws {
        let on = try #require(OnAirNow.pick(day: Self.evening, stations: [Self.station], now: Date(timeIntervalSince1970: 1500)))
        #expect(on.kicker == "Tonight in 1942" && on.episode.id == "a|1" && on.note == nil)
        #expect(on.minutesIn(Date(timeIntervalSince1970: 1000 + 600)) == 10)
    }

    @Test func aWithheldSlotFallsThroughToTheFirstStationWithOne() throws {
        let on = try #require(OnAirNow.pick(day: Self.evening, stations: [Self.station], now: Date(timeIntervalSince1970: 3000)))
        #expect(on.kicker == "Mystery" && on.episode.id == "m|1")
    }

    @Test func beforeTheEveningAStationStandsInWithTheStartTime() throws {
        let on = try #require(OnAirNow.pick(day: Self.evening, stations: [Self.station], now: Date(timeIntervalSince1970: 500)))
        #expect(on.kicker == "Mystery")
        #expect(on.note?.hasPrefix("Tonight in 1942 \u{00B7} Starts at ") == true)
    }

    @Test func nothingOnIsNoBlock() {
        #expect(OnAirNow.pick(day: nil, stations: [], now: Date(timeIntervalSince1970: 500)) == nil)
        #expect(OnAirNow.pick(day: Self.evening, stations: [Self.station], now: Date(timeIntervalSince1970: 9000)) == nil)
    }
}

// A first take needs no account; a production with no take stays out of sight (Decision 079, PLAYS-DESIGN §2.3 rule 3a).
struct FirstTakeTests {
    private static func script() -> PlayScript {
        PlayScript(id: "s", revision: "r1", kind: "radio", title: "T", authors: [], source: .init(name: "S", url: "https://example.org"),
                   rights: .init(bucket: "script_source_cleared", evidence: []),
                   roles: [.init(name: "A", lines: 5, words: 10), .init(name: "B", lines: 5, words: 10)],
                   lines: [ScriptLine(id: "L1", kind: .speech, role: "A", parts: [.say("Hello.")]),
                           ScriptLine(id: "L2", kind: .speech, role: "B", parts: [.say("Hi.")])])
    }

    private static func take(_ id: String) -> Take {
        Take(id: id, lineID: "L1", part: .role("A"), file: "\(id).wav", created: .now, frames: 10, sampleRate: 48_000,
             capture: .direct, heard: [:], loudness: nil, peak: 0.1, bleed: false)
    }

    private static func root() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "first-take-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func aSecondProductionAsksForAnAccountSignedOutOnly() {
        let empty = Production(script: Self.script())
        var taken = Production(script: Self.script())
        taken.add(Self.take("t"))
        #expect(!StudioCore.needsAccount(productions: [], signedIn: false, makingNew: true), "the first production needs none")
        #expect(!StudioCore.needsAccount(productions: [empty], signedIn: false, makingNew: true), "an empty one does not count")
        #expect(StudioCore.needsAccount(productions: [empty, taken], signedIn: false, makingNew: true))
        #expect(!StudioCore.needsAccount(productions: [taken], signedIn: true, makingNew: true), "signed in, nothing is asked")
        #expect(!StudioCore.needsAccount(productions: [taken], signedIn: false, makingNew: false), "continuing one asks nothing")
        #expect(!empty.hasTake && taken.hasTake)
    }

    @Test func anEmptyProductionOfThePlayIsReused() {
        let other = Production(id: "o", script: Self.script(), created: Date(timeIntervalSince1970: 3))
        let old = Production(id: "e1", script: Self.script(), created: Date(timeIntervalSince1970: 1))
        let new = Production(id: "e2", script: Self.script(), created: Date(timeIntervalSince1970: 2))
        var taken = Production(id: "t", script: Self.script(), created: Date(timeIntervalSince1970: 4))
        taken.add(Self.take("t"))
        #expect(StudioCore.reusableEmpty([old, new, taken, other], isShared: { $0 == "o" }, scriptID: "s")?.id == "e2")
        #expect(StudioCore.reusableEmpty([taken], isShared: { _ in false }, scriptID: "s") == nil)
        #expect(StudioCore.reusableEmpty([new], isShared: { _ in false }, scriptID: "other") == nil)
    }

    @Test func theStoreDeletesEmptyUnsharedProductionsWhenItLoads() throws {
        let store = ProductionStore(root: Self.root())
        defer { try? FileManager.default.removeItem(at: store.root) }
        let empty = try store.create(Self.script())
        let shared = try store.create(Self.script())
        try store.setShare(shared.id, ProductionShare(pid: "pid-x"))
        var taken = try store.create(Self.script())
        taken.add(Self.take("t"))
        try store.save(taken)
        #expect(store.productions.count == 3, "a store already loaded keeps what it made")
        let rows = PlaysShare.libraryRows(store, remote: [])
        #expect(Set(rows.map(\.id)) == [shared.id, taken.id], "Yours lists a local production once it holds a take")
        let next = ProductionStore(root: store.root)
        #expect(Set(next.productions.map(\.id)) == [shared.id, taken.id], "the empty one is gone on the next load")
        #expect(!FileManager.default.fileExists(atPath: next.folder(empty.id).path), "with its folder")
    }

    @Test func leavingTheStudioWithNoTakeDeletesOnlyAnEmptyUnsharedProduction() throws {
        let store = ProductionStore(root: Self.root())
        defer { try? FileManager.default.removeItem(at: store.root) }
        let empty = try store.create(Self.script())
        let shared = try store.create(Self.script())
        try store.setShare(shared.id, ProductionShare(pid: "pid-y"))
        var taken = try store.create(Self.script())
        taken.add(Self.take("t"))
        try store.save(taken)
        #expect(store.removeIfEmpty(empty.id))
        #expect(!store.removeIfEmpty(shared.id))
        #expect(!store.removeIfEmpty(taken.id))
        #expect(Set(store.productions.map(\.id)) == [shared.id, taken.id])
        #expect(!FileManager.default.fileExists(atPath: store.folder(empty.id).path))
    }

    @Test func aTakeWrittenAfterTheOldTwoSecondWindowSurvivesWithItsProduction() async throws {
        let store = ProductionStore(root: Self.root())
        defer { try? FileManager.default.removeItem(at: store.root) }
        let made = try store.create(Self.script())
        let id = made.id
        let leaving = Task { await store.removeWhenSettled(id) }
        try store.withTakeWrite(id) {
            Thread.sleep(forTimeInterval: 2.5)
            #expect(!store.removeIfEmpty(id), "a pending write is never removed under")
            var p = try #require(store.production(id))
            p.add(Self.take("late"))
            try store.save(p)
        }
        #expect(!(await leaving.value), "not removed")
        #expect(store.production(id)?.hasTake == true)
    }

    @Test func anEmptyProductionWithNoPendingWritesIsRemovedOnLeave() async throws {
        let store = ProductionStore(root: Self.root())
        defer { try? FileManager.default.removeItem(at: store.root) }
        let made = try store.create(Self.script())
        #expect(await store.removeWhenSettled(made.id))
        #expect(store.production(made.id) == nil)
    }

    @Test func aHeldProductionIsNeverPrunedOnLeave() async throws {
        let store = ProductionStore(root: Self.root())
        defer { try? FileManager.default.removeItem(at: store.root) }
        let made = try store.create(Self.script())
        #expect(!(await store.removeWhenSettled(made.id, isHeld: { true })))
        #expect(store.production(made.id) != nil)
    }

    @Test func madeHereLeadsUnderTheDoorsWhileThereAreOneToFive() {
        #expect(!FinishedDramas.leadsHome(count: 0))
        #expect(FinishedDramas.leadsHome(count: 1) && FinishedDramas.leadsHome(count: 5))
        #expect(!FinishedDramas.leadsHome(count: 6))
    }
}
