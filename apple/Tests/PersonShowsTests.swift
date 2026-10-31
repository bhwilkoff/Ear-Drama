import Foundation
import Testing

/// The person page's per-show years and run strip follow the web's `yearsOf` and `stripOf`
/// (js/app.js renderPerson): the person's own episodes in the series, never the series' whole run.
struct PersonShowsTests {
    private func credit(_ date: String?) -> PersonEpisode {
        PersonEpisode(episode: EpisodeRow(id: "s|\(date ?? "x")", seriesKey: "s", seriesName: "S", airDate: date, season: nil,
                                          number: nil, title: nil, lengthSeconds: nil, rights: "unclaimed", rightsBasis: nil,
                                          network: nil),
                      roles: [])
    }

    @Test func theStripCountsTheirEpisodesPerYear() {
        let eps = [credit("1946-02-06"), credit("1946-02-27"), credit("1948-01-01"), credit(nil)]
        #expect(PersonShows.yearCounts(eps) == [1946, 2, 0, 1])
        let run = PersonShows.span(eps)
        #expect(run.first == "1946" && run.last == "1948")
    }

    @Test func undatedEpisodesDrawNoStrip() {
        #expect(PersonShows.yearCounts([credit(nil)]) == nil)
        #expect(PersonShows.span([credit(nil)]).first == nil)
    }

    @Test func theTileTakesThePersonsYearsAndTheSeriesPicture() {
        let art = Artwork(url: URL(string: "https://example.org/a")!, width: 600, height: 800)
        let series = SeriesRow(key: "s", name: "S", genre: "drama", firstDate: "1930-01-01", lastDate: "1960-01-01", networks: [],
                               episodeCount: 500, picture: art)
        let tile = PersonShows.tile(series, key: "s", name: "S", episodes: [credit("1946-02-06"), credit("1948-01-01")])
        #expect(tile.yearSpan == "1946–1948" && tile.episodeCount == 2 && tile.picture == art && tile.genre == "drama")
    }
}
