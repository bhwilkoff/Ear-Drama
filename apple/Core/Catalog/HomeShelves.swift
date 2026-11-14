import Foundation

// Home's two chip rows (iOS-DESIGN §4.1, Decision 075; js/api.js `homeShelves`): Start a Show and By
// Length, each chip a published shelf of first episodes. The pipeline publishes the ids; this only
// orders and names them.

nonisolated struct HomeChip: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let episodes: [EpisodeRow]
}

nonisolated struct HomeShelves: Equatable, Sendable {
    /// "Most downloaded" first, then each genre's firsts in the published order.
    var start: [HomeChip] = []
    /// Under 15 min, About 30 min, An hour: only the bands the catalog publishes.
    var length: [HomeChip] = []

    init() {}

    init(_ shelves: [Shelf]) {
        let popular = shelves.filter { $0.rule == .mostDownloaded }
        let genres = shelves.filter { if case .genreFirsts = $0.rule { true } else { false } }
        start = (popular + genres).map { HomeChip(id: $0.id, title: $0.rule.title, episodes: $0.episodes) }
        length = ShelfRule.lengthBands.compactMap { band in
            shelves.first { $0.rule == .byLength(band.band) }
                .map { HomeChip(id: $0.id, title: band.title, episodes: $0.episodes) }
        }
    }
}

nonisolated extension EpisodeRow {
    /// "29 min", "1 hr 5 min": the length a Home tile says.
    var lengthLabel: String? {
        guard let lengthSeconds, lengthSeconds >= 30 else { return nil }
        let minutes = Int((lengthSeconds / 60).rounded())
        guard minutes >= 60 else { return "\(max(1, minutes)) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }
}

extension CatalogStore {
    func homeShelves(today: Date = Date()) async -> HomeShelves {
        HomeShelves(await listenShelves(today: today))
    }
}
