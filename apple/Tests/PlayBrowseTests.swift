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
