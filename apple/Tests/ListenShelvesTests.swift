import Foundation
import Testing

// The Listen tab draws `meta.listenShelves` (docs/CATALOG-CONTRACT.md §5.1):
// the published order, each genre's ids as published, onThisDay held to the
// golden cases every client shares, and the older-catalog fallback.

nonisolated private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

struct ListenShelvesTests {
    static let published = """
        [{"rule": "genreFirsts", "genre": "drama", "episodes": ["librivox1|s2", "librivox1|s1"]},
         {"rule": "onThisDay"},
         {"rule": "genreFirsts", "genre": "mystery", "episodes": ["suspense|1943-05-25", "gone|1900-01-01", "suspense|1942-06-17"]},
         {"rule": "mostEpisodes"},
         {"rule": "genreFirsts", "genre": "western", "episodes": []}]
        """

    @Test func onThisDayMatchesTheGoldenCases() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("catalog/tests/golden/on_this_day.json"))
        let golden = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(golden["episodes"] as? [[Any]])
        let eps = rows.map { r in
            Fixture.Ep(id: r[0] as? String ?? "", series: r[1] as? String ?? "", date: r[2] as? String, season: nil,
                       num: r[3] as? Int, title: r[0] as? String, noRecommend: r[4] as? String)
        }
        let series = Set(eps.map(\.series)).sorted().map {
            (key: $0, name: $0.uppercased(), genre: String?.none, first: String?.none, last: String?.none,
             networks: String?.none)
        }
        let db = try #require(CatalogDatabase(path: try Fixture.make(episodeRows: eps, seriesRows: series).path))
        let cases = try #require(golden["cases"] as? [[String: Any]])
        #expect(cases.count >= 7)
        for c in cases {
            let month = try #require(c["month"] as? Int), day = try #require(c["day"] as? Int)
            let want = try #require(c["want"] as? [String])
            let got = db.shelf(.onThisDay(month: month, day: day), limit: c["limit"] as? Int ?? 20).map(\.id)
            #expect(got == want, "\(month)/\(day)")
        }
    }

    @Test func publishedOrderAndIdsAreDrawnAsGiven() throws {
        let db = try Fixture.open(listenShelves: Self.published)
        let shelves = db.listenShelves(month: 5, day: 25)
        // An unknown rule is ignored and an empty shelf dropped.
        #expect(shelves.map(\.rule) == [.genreFirsts("drama"), .onThisDay(month: 5, day: 25), .genreFirsts("mystery")])
        #expect(shelves.map(\.rule.title) == ["Drama", "This day in radio", "Mystery"])
        // Ids in published order, not broadcast order; an unserved id dropped.
        #expect(shelves[0].episodes.map(\.id) == ["librivox1|s2", "librivox1|s1"])
        #expect(shelves[2].episodes.map(\.id) == ["suspense|1943-05-25", "suspense|1942-06-17"])
        #expect(shelves[1].episodes.map(\.id) == ["suspense|1943-05-25", "mrsorrowful|1950-05-25"])
    }

    @Test func anOlderCatalogFallsBackToTheRulesRunHere() throws {
        let db = try Fixture.open()
        #expect(db.publishedShelves == nil)
        let shelves = db.listenShelves(month: 5, day: 25)
        #expect(shelves.first?.rule == .onThisDay(month: 5, day: 25))
        let genres = shelves.dropFirst().map(\.rule)
        #expect(Set(genres) == Set(db.genres().map { ShelfRule.genreFirsts($0) }))
        #expect(shelves.allSatisfy { !$0.episodes.isEmpty })
        // Control: the fallback draws the genre's own first, where the published list said otherwise.
        #expect(shelves.first { $0.rule == .genreFirsts("drama") }?.episodes.map(\.id) == ["librivox1|s1"])
        // A value that is not a list is an older catalog too.
        #expect(try Fixture.open(listenShelves: "{}").publishedShelves == nil)
    }

    @Test func parseKeepsOnlyKnownRules() {
        #expect(PublishedShelf.parse(Self.published) == [
            .genreFirsts(genre: "drama", episodes: ["librivox1|s2", "librivox1|s1"]), .onThisDay,
            .genreFirsts(genre: "mystery", episodes: ["suspense|1943-05-25", "gone|1900-01-01", "suspense|1942-06-17"]),
            .genreFirsts(genre: "western", episodes: []),
        ])
        #expect(PublishedShelf.parse("not json") == nil)
        #expect(PublishedShelf.parse("[]") == [])
    }
}
