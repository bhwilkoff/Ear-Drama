import Foundation
import Network
import Observation

/// Owns the open catalog: the bundled seed at first launch, then the full
/// catalog once a refresh has downloaded and validated it. Views ask it for the
/// contract's verbs; queries run off the main actor and return values.
@Observable
final class CatalogStore {
    enum State: Equatable {
        case loading
        case ready
        /// No seed in the bundle and no download yet.
        case unavailable
    }

    private(set) var state: State = .loading
    /// Bumps when a newer catalog is swapped in, so every view re-queries.
    private(set) var generation = 0
    /// True when the open catalog is the bundled seed, not a full download.
    private(set) var isSeed = true
    private(set) var isOnline = true

    /// A view's `.task(id:)` key: changes when the catalog becomes ready and
    /// again on every swap, so a screen loads once the data is there.
    var loadKey: Int { state == .ready ? generation : -1 }

    @ObservationIgnored private var database: CatalogDatabase?
    @ObservationIgnored private let refresher: CatalogRefreshService
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var started = false

    init(refresher: CatalogRefreshService = .shared) {
        self.refresher = refresher
    }

    /// Opens a catalog for testing or previews without the bundle.
    init(path: String) {
        refresher = .shared
        database = CatalogDatabase(path: path)
        state = database == nil ? .unavailable : .ready
        started = true
    }

    func start() async {
        guard !started else { return }
        started = true
        watchNetwork()
        if let cached = await refresher.cachedDatabasePath(), open(cached, seed: false) {
            // the last full download
        } else if let seed = Bundle.main.path(forResource: CatalogSource.seedResource, ofType: "sqlite"),
                  open(seed, seed: true) {
            // first launch: the bundled seed
        } else {
            state = .unavailable
        }
        await refresh()
    }

    /// Foreground re-check, throttled by the refresher's TTL.
    func refresh(force: Bool = false) async {
        guard let path = await refresher.refresh(force: force || database == nil) else { return }
        if open(path, seed: false) { generation += 1 }
    }

    @discardableResult
    private func open(_ path: String, seed: Bool) -> Bool {
        let refresher = self.refresher
        let isDownload = !seed
        guard let db = CatalogDatabase(path: path, onCorruption: {
            guard isDownload else { return }
            Task { await refresher.discardCachedDatabase(reason: "a read came back corrupt") }
        }) else { return false }
        database = db
        isSeed = seed
        state = .ready
        return true
    }

    private func watchNetwork() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "app.eardrama.network"))
    }

    /// Waits while the catalog is still opening (a door or deep link can ask
    /// for an episode before first paint).
    func whenReady() async {
        while state == .loading {
            guard (try? await Task.sleep(for: .milliseconds(100))) != nil else { return }
        }
    }

    // MARK: - Verbs (contract §5), off the main actor

    func run<T: Sendable>(_ body: @escaping @Sendable (CatalogDatabase) -> T) async -> T? {
        guard let db = database else { return nil }
        return await Task.detached(priority: .userInitiated) { body(db) }.value
    }

    func seriesBrowse(genre: String?, network: String?, decade: Int?) async -> [SeriesRow] {
        await run { $0.seriesBrowse(genre: genre, network: network, decade: decade) } ?? []
    }

    func browseFacets() async -> (genres: [String], networks: [String], decades: [Int]) {
        await run { ($0.genres(), $0.networks(), $0.decades()) } ?? ([], [], [])
    }

    func seriesPage(_ key: String) async -> SeriesPage? {
        await run { $0.seriesPage(key: key) } ?? nil
    }

    func episodeDetail(_ id: String) async -> EpisodeDetail? {
        await run { $0.episodeDetail(id: id) } ?? nil
    }

    func scriptedSeries() async -> [String: [String]] {
        await run { $0.scriptedSeries() } ?? [:]
    }

    func search(_ query: String) async -> SearchResults {
        await run { $0.search(query) } ?? SearchResults()
    }

    func episodes(_ ids: [String]) async -> [EpisodeRow] {
        await run { $0.episodes(ids: ids) } ?? []
    }

    func randomEpisode() async -> EpisodeRow? {
        await run { $0.randomEpisode() } ?? nil
    }

    /// The Listen tab: the catalog's published shelves on the person's own
    /// calendar date (`CatalogDatabase.listenShelves`).
    func listenShelves(today: Date = Date(), calendar: Calendar = .current) async -> [Shelf] {
        let parts = calendar.dateComponents([.month, .day], from: today)
        let month = parts.month ?? 1, day = parts.day ?? 1
        return await run { $0.listenShelves(month: month, day: day) } ?? []
    }
}
