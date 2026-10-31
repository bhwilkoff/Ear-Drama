import Foundation

/// A person's shows as the page draws them: the years and run strip are the person's own episodes in
/// each series (the same rule as the web's `stripOf`), never the series' whole run.
nonisolated enum PersonShows {
    static func yearCounts(_ episodes: [PersonEpisode]) -> [Int]? {
        let years = episodes.compactMap { $0.episode.airDate.flatMap { Int($0.prefix(4)) } }
        guard let lo = years.min(), let hi = years.max() else { return nil }
        var counts = [Int](repeating: 0, count: hi - lo + 1)
        for y in years { counts[y - lo] += 1 }
        return [lo] + counts
    }

    static func span(_ episodes: [PersonEpisode]) -> (first: String?, last: String?) {
        let years = episodes.compactMap { $0.episode.airDate.flatMap { Int($0.prefix(4)) } }
        return (years.min().map(String.init), years.max().map(String.init))
    }

    /// The series as a tile: the catalog's picture and genre, the person's years and count.
    static func tile(_ series: SeriesRow?, key: String, name: String, episodes: [PersonEpisode]) -> SeriesRow {
        let run = span(episodes)
        return SeriesRow(key: key, name: series?.name ?? name, genre: series?.genre, firstDate: run.first, lastDate: run.last,
                         networks: [], episodeCount: episodes.count, face: series?.face, picture: series?.picture,
                         pictureKind: series?.pictureKind, yearCounts: yearCounts(episodes), sortName: nil)
    }
}
