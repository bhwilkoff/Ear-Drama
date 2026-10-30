import Foundation
import Testing

struct PagesRulesTests {
    private func art(_ name: String) -> Artwork {
        Artwork(url: URL(string: "https://example.org/\(name)")!, width: 600, height: 800)
    }

    private func series(_ picture: String?, kind: String?) -> SeriesRow {
        SeriesRow(key: "s", name: "S", genre: "drama", firstDate: nil, lastDate: nil, networks: [], episodeCount: 1,
                  picture: picture.map(art), pictureKind: kind)
    }

    private var credits: [Credit] {
        [Credit(personID: "a", name: "A", role: "cast", character: nil, art: nil),
         Credit(personID: "b", name: "B", role: "cast", character: nil, art: art("b")),
         Credit(personID: "c", name: "C", role: "cast", character: nil, art: art("c")),
         Credit(personID: "d", name: "D", role: "writer", character: nil, art: art("d")),
         Credit(personID: "b", name: "B", role: "cast", character: nil, art: art("b"))]
    }

    @Test func leadPictureFollowsTheWebCases() {
        #expect(Grammar.leadPicture(series: series("show", kind: "show"), credits: credits, star: "c")?.url.lastPathComponent == "show")
        #expect(Grammar.leadPicture(series: series("s", kind: "star"), credits: credits, star: "c")?.url.lastPathComponent == "c")
        #expect(Grammar.leadPicture(series: series("s", kind: "star"), credits: credits, star: nil)?.url.lastPathComponent == "b")
        let writer = [Credit(personID: "w", name: "W", role: "writer", character: nil, art: art("w"))]
        #expect(Grammar.leadPicture(series: series("s", kind: "star"), credits: writer, star: nil)?.url.lastPathComponent == "s")
        #expect(Grammar.leadPicture(series: series(nil, kind: nil), credits: [], star: nil) == nil)
    }

    @Test func onAirIsTheCastOnceEachInBillingOrder() {
        #expect(Grammar.onAirOf(credits).map(\.personID) == ["a", "b", "c"])
        #expect(Grammar.onAirOf(credits, limit: 2).count == 2)
    }

    @Test func episodeFactsFollowTheWebCases() {
        #expect(Grammar.episodeFacts(date: "Jun 17, 1943", network: "CBS", sponsor: nil, length: "30 min", season: "1943-44",
                                     title: "T", number: 4)
                == ["Jun 17, 1943", "CBS", "30 min", "Season 1943-44", "No. 4"])
        #expect(Grammar.episodeFacts(date: nil, network: nil, sponsor: nil, length: nil, season: nil, title: nil, number: 4)
                == ["Undated"])
    }
}
