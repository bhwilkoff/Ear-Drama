import Foundation
import Testing

/// The car's tree over a fixture catalog: the cases of Android's CarLibraryTest. `problems` states the
/// tree's rules (four tabs, every node titled, a message neither a folder nor playing, no folder past the
/// page cap, no folder deeper than the audio stack allows); the control proves it sees a tree that breaks them.
struct CarLibraryTests {
    typealias Ep = Fixture.Ep
    private typealias Show = (key: String, name: String, genre: String?, first: String?, last: String?, networks: String?)

    private static let shows: [Show] = [
        ("suspense", "Suspense", "mystery", "1942-06-17", "1943-05-25", #"["CBS"]"#),
        ("jackbenny", "The Jack Benny Program", "comedy", "1941-01-05", "1941-01-30", nil),
        ("wartime", "Wartime Speeches", "news", "1944-01-01", "1944-01-05", nil),
        ("bigshow", "A Long Running Show", "drama", "1941-01-01", "1942-12-01", nil),
        ("tiny", "Two Recordings", "western", "1950-01-01", "1950-01-02", nil),
    ]

    private static var episodes: [Ep] {
        var out: [Ep] = []
        for i in 0..<6 {
            out.append(Ep(id: "suspense|1942-\(String(format: "%02d", i + 1))-17", series: "suspense", date: "1942-\(String(format: "%02d", i + 1))-17",
                          season: "1941-42", num: i + 1, title: i == 0 ? "The Hitch-Hiker" : "Broadcast \(i + 1)"))
        }
        out.append(Ep(id: "suspense|1943-05-25", series: "suspense", date: "1943-05-25", season: "1942-43", num: 7, title: "Sorry, Wrong Number"))
        for i in 0..<5 {
            out.append(Ep(id: "jackbenny|1941-01-0\(i + 1)", series: "jackbenny", date: "1941-01-0\(i + 1)", season: "1940-41", num: i + 1,
                          title: "Jell-O \(i + 1)"))
        }
        for i in 0..<5 {
            out.append(Ep(id: "wartime|1944-01-0\(i + 1)", series: "wartime", date: "1944-01-0\(i + 1)", season: "1943-44", num: nil,
                          title: "Bulletin \(i + 1)", rights: "clean", basis: "rec_gov_work", noRecommend: "Nazi-state speech or broadcast"))
        }
        for i in 0..<105 {
            let month = String(format: "%02d", i % 12 + 1), day = String(format: "%02d", i / 12 + 1)
            out.append(Ep(id: "bigshow|\(i)", series: "bigshow", date: "\(i < 60 ? 1941 : 1942)-\(month)-\(day)",
                          season: i < 60 ? "1941-42" : "1942-43", num: i + 1, title: "Chapter \(i + 1)"))
        }
        out.append(Ep(id: "tiny|1950-01-01", series: "tiny", date: "1950-01-01", season: nil, num: nil, title: "One"))
        out.append(Ep(id: "tiny|1950-01-02", series: "tiny", date: "1950-01-02", season: nil, num: nil, title: "Two"))
        return out
    }

    private static let shelves = """
        [{"rule":"byLength","band":"about30","episodes":["suspense|1942-02-17","wartime|1944-01-01","suspense|1942-03-17","gone|1900-01-01"]}]
        """

    private static func store(shelves: String? = CarLibraryTests.shelves) throws -> CatalogStore {
        CatalogStore(path: try Fixture.make(listenShelves: shelves, episodeRows: episodes, seriesRows: Self.shows).path)
    }

    private func library(
        _ catalog: CatalogStore,
        inProgress: [String] = [],
        downloaded: [String] = [],
        followed: [String] = [],
        budget: Duration = .seconds(8),
        stations: @escaping () async throws -> [CarStation] = { [] }
    ) -> CarLibrary {
        CarLibrary(catalog: catalog, inProgressIDs: { inProgress }, progress: { inProgress.contains($0) ? 0.25 : nil },
                   downloadedIDs: { downloaded }, followed: { followed }, stations: stations, budget: budget)
    }

    private static let tabs = ["Continue", "Stations", "Browse", "Downloads"]

    /// What is wrong with `nodes` under `parent`, walking every folder under them to `depth` more levels.
    private func problems(_ lib: CarLibrary, of parent: String = CarLibrary.root, depth: Int = 5) async -> [String] {
        guard let children = await lib.children(of: parent) else { return ["\(parent) lists nothing"] }
        var out = Self.nodeProblems(children, parent: parent)
        if parent == CarLibrary.root, children.map(\.title) != Self.tabs { out.append("top level is \(children.map(\.title))") }
        for node in children where node.isFolder {
            if depth == 0 { out.append("\(node.id) is deeper than the audio stack"); continue }
            out += await problems(lib, of: node.id, depth: depth - 1)
        }
        return out
    }

    private static func nodeProblems(_ nodes: [CarNode], parent: String) -> [String] {
        var out: [String] = []
        if nodes.count > CarLibrary.pageMax { out.append("\(parent) holds \(nodes.count)") }
        for node in nodes {
            if node.title.trimmingCharacters(in: .whitespaces).isEmpty { out.append("\(node.id) has no title") }
            if node.id.isEmpty { out.append("a node under \(parent) has no id") }
            if node.kind == .message && (node.isFolder || node.plays || node.art != nil) { out.append("\(node.id) is a message that acts") }
        }
        return out
    }

    @Test func theWholeTreeKeepsItsRules() async throws {
        let lib = library(try Self.store(), inProgress: ["suspense|1942-02-17"], downloaded: ["suspense|1943-05-25"],
                          followed: ["suspense"],
                          stations: { [CarStation(id: "station:mystery", name: "Mystery", line: "Suspense · The Hitch-Hiker", artEpisodeID: "suspense|1942-01-17")] })
        #expect(await problems(lib) == [])
    }

    @Test func controlATreeThatBreaksTheRulesIsCaught() {
        let bad = [
            CarNode(id: "x|1", title: "", subtitle: nil, kind: .episode),
            CarNode(id: "m", title: "Oops", subtitle: nil, kind: .message, art: .episode("x")),
        ]
        let found = Self.nodeProblems(bad, parent: "p")
        #expect(found.contains { $0.contains("has no title") } && found.contains { $0.contains("message that acts") })
        let many = (0..<(CarLibrary.pageMax + 1)).map { CarNode(id: "e\($0)", title: "T", subtitle: nil, kind: .episode) }
        #expect(Self.nodeProblems(many, parent: "p").contains { $0.contains("holds") })
    }

    @Test func theFourTabsAreTheRoot() async throws {
        let lib = library(try Self.store())
        let tabs = try #require(await lib.children(of: CarLibrary.root))
        #expect(tabs.map(\.title) == Self.tabs)
        #expect(tabs.allSatisfy { $0.isFolder })
    }

    @Test func continueListsOnlyWhatIsInProgressAndInTheCatalog() async throws {
        let lib = library(try Self.store(), inProgress: ["suspense|1942-02-17", "gone|1950-01-01", "jackbenny|1941-01-01", "suspense|1942-02-17"])
        let nodes = try #require(await lib.children(of: CarLibrary.continueTab))
        #expect(nodes.map(\.id) == ["suspense|1942-02-17", "jackbenny|1941-01-01"])
        #expect(nodes.first?.progress == 0.25)
    }

    @Test func anEpisodeCarriesTitleSubtitleAndItsArt() async throws {
        let lib = library(try Self.store(), inProgress: ["suspense|1942-01-17"])
        let node = try #require(await lib.children(of: CarLibrary.continueTab)?.first)
        #expect(node.title == "The Hitch-Hiker")
        #expect(node.subtitle == "Suspense \u{00B7} Jan 17, 1942")
        #expect(node.art == .episode("suspense|1942-01-17"))
        #expect(!node.subtitle!.contains("1942-01"), "an ISO date never shows")
    }

    @Test func emptyFoldersSayWhyInAMessageRow() async throws {
        let lib = library(try Self.store(), stations: { [] })
        for (tab, words) in [(CarLibrary.continueTab, "Nothing in progress"), (CarLibrary.downloadsTab, "No downloads yet"),
                             (CarLibrary.stationsTab, "Nothing is on the air right now"),
                             (CarLibrary.following, "Follow a show on your phone and it appears here")] {
            let only = try #require(await lib.children(of: tab)?.first)
            #expect(only.kind == .message && only.title == words, "\(tab)")
        }
    }

    @Test func downloadsListTheFinishedOnesInOrder() async throws {
        let lib = library(try Self.store(), downloaded: ["suspense|1943-05-25", "gone|1950-01-01", "suspense|1942-01-17"])
        #expect(await lib.children(of: CarLibrary.downloadsTab)?.map(\.id) == ["suspense|1943-05-25", "suspense|1942-01-17"])
    }

    @Test func anUnknownFolderIsAnErrorNotAnEmptyList() async throws {
        let lib = library(try Self.store())
        #expect(await lib.children(of: "tab:nowhere") == nil)
        #expect(await lib.children(of: "series/nope") == nil)
        #expect(await lib.children(of: "season/nope/~") == nil)
    }

    @Test func followedShowsKeepTheirOrderAndSkipTheMissing() async throws {
        let lib = library(try Self.store(), followed: ["jackbenny", "ghost", "suspense"])
        let nodes = try #require(await lib.children(of: CarLibrary.following))
        #expect(nodes.map(\.title) == ["The Jack Benny Program", "Suspense"])
        #expect(nodes.last?.subtitle == "1942\u{2013}1943 \u{00B7} 7 episodes")
        #expect(nodes.last?.art == .series("suspense"))
    }

    @Test func popularAreShowsOnlyAndNeverOneWithNothingToRecommend() async throws {
        let nodes = try #require(await library(try Self.store()).children(of: CarLibrary.popular))
        let names = nodes.map(\.title)
        #expect(names.contains("Suspense") && names.contains("A Long Running Show"))
        #expect(!names.contains("Two Recordings"), "fewer than five episodes is no show")
        #expect(!names.contains("Wartime Speeches"), "every broadcast is never-recommend")
    }

    @Test func genresNameOnlyTheOnesWithAShow() async throws {
        let lib = library(try Self.store())
        let genres = try #require(await lib.children(of: CarLibrary.genres))
        #expect(genres.map(\.title) == ["Drama", "Mystery", "Comedy"], "published order; western has no show, news only withheld ones")
        let mysteryID = try #require(genres.first { $0.title == "Mystery" }).id
        let mystery = try #require(await lib.children(of: mysteryID))
        #expect(mystery.map(\.title) == ["Suspense"])
    }

    @Test func lengthBandsAreThePublishedOnesAndLeaveOutWhatIsNeverRecommended() async throws {
        let lib = library(try Self.store())
        let bands = try #require(await lib.children(of: CarLibrary.lengths))
        #expect(bands.map(\.title) == ["About 30 min"])
        let episodes = try #require(await lib.children(of: bands[0].id))
        #expect(episodes.map(\.id) == ["suspense|1942-02-17", "suspense|1942-03-17"])
        let none = library(try Self.store(shelves: nil))
        #expect(await none.children(of: CarLibrary.lengths)?.isEmpty == true)
    }

    @Test func aShowOpensOnItsEpisodesOldestFirst() async throws {
        let lib = library(try Self.store())
        let nodes = try #require(await lib.children(of: CarLibrary.seriesID("suspense")))
        #expect(nodes.count == 7 && nodes.allSatisfy { $0.kind == .episode })
        #expect(nodes.first?.id == "suspense|1942-01-17" && nodes.last?.id == "suspense|1943-05-25")
    }

    @Test func aLongShowAcrossSeasonsOpensOnItsSeasons() async throws {
        let lib = library(try Self.store())
        let seasons = try #require(await lib.children(of: CarLibrary.seriesID("bigshow")))
        #expect(seasons.map(\.title) == ["Season 1941-42", "Season 1942-43"])
        #expect(seasons.allSatisfy { $0.isFolder })
        #expect(seasons.map(\.subtitle) == ["60 episodes", "45 episodes"])
        let second = try #require(await lib.children(of: seasons[1].id))
        #expect(second.count == 45 && second.allSatisfy { $0.kind == .episode })
        #expect(second.first?.title == "Chapter 61")
    }

    @Test func aSlowFolderSaysSoWithinItsBudgetInsteadOfSpinning() async throws {
        let lib = library(try Self.store(), budget: .milliseconds(80), stations: { try await Task.sleep(for: .seconds(30)); return [] })
        let started = ContinuousClock.now
        let only = try #require(await lib.children(of: CarLibrary.stationsTab)?.first)
        #expect(only.title == CarLibrary.slow && only.kind == .message)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func stationsOfflineSayStationsNeedAConnection() async throws {
        let lib = library(try Self.store(), stations: { throw URLError(.notConnectedToInternet) })
        #expect(await lib.children(of: CarLibrary.stationsTab)?.map(\.title) == [CarLibrary.offlineStations])
    }

    @Test func stationsShowWhatIsOnWithItsPicture() async throws {
        let on = CarStation(id: "station:mystery", name: "Mystery", line: "Suspense \u{00B7} Broadcast 2", artEpisodeID: "suspense|1942-02-17")
        let nodes = try #require(await library(try Self.store(), stations: { [on] }).children(of: CarLibrary.stationsTab))
        #expect(nodes == [CarNode(id: "station:mystery", title: "Mystery", subtitle: "Suspense \u{00B7} Broadcast 2", kind: .station,
                                  art: .episode("suspense|1942-02-17"))])
        #expect(nodes[0].plays)
    }

    @Test func noCatalogSaysToOpenThePhone() async {
        let lib = library(CatalogStore(path: "/nonexistent/catalog.sqlite"))
        #expect(await lib.children(of: CarLibrary.popular)?.map(\.title) == [CarLibrary.noCatalog])
        #expect(await lib.children(of: CarLibrary.continueTab)?.map(\.title) == [CarLibrary.noCatalog])
        #expect(await lib.search("suspense").map(\.title) == [CarLibrary.noCatalog])
    }

    @Test func searchGivesShowsThenEpisodesOrSaysNothingFound() async throws {
        let lib = library(try Self.store())
        let found = await lib.search("suspense")
        #expect(found.first?.kind == .folder && found.first?.title == "Suspense")
        #expect(found.dropFirst().allSatisfy { $0.kind == .episode })
        #expect(await lib.search("zzzzqqq").map(\.title) == ["Nothing found for zzzzqqq"])
        #expect(await lib.search("   ").isEmpty)
    }

    @Test func voiceTargetPrefersAStationThenTheShowsEpisodeInProgress() async throws {
        let on = CarStation(id: "station:mystery", name: "Mystery", line: nil, artEpisodeID: nil)
        let catalog = try Self.store()
        #expect(await library(catalog, stations: { [on] }).voiceTarget("the mystery station") == "station:mystery")
        #expect(await library(catalog, inProgress: ["suspense|1942-03-17"]).voiceTarget("Suspense") == "suspense|1942-03-17")
        #expect(await library(catalog).voiceTarget("Suspense") == "suspense|1942-01-17", "no episode in progress: the first")
        #expect(await library(catalog, inProgress: ["jackbenny|1941-01-02"]).voiceTarget("something unheard of") == "jackbenny|1941-01-02",
                "nothing matches: where the listener left off")
        #expect(await library(catalog).voiceTarget(nil) != nil, "never nothing while the catalog has anything")
    }
}
