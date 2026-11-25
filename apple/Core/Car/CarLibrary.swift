import Foundation

// The car's tree as a pure model (docs/iOS-DESIGN.md §9.1, R17), the Swift twin of Android's `CarLibrary`
// (same ids, same rules, same cases in CarLibraryTests): four tabs, then folders and rows that are a
// folder, something that plays, or a plain message. The CarPlay templates in `iOS/CarPlay_iOS.swift`
// only draw what this answers.

/// A picture a node wears, named by what it is a picture of, never by a URL.
nonisolated enum CarArt: Hashable, Sendable {
    case episode(String)
    case series(String)
}

nonisolated struct CarNode: Hashable, Sendable, Identifiable {
    enum Kind: Sendable { case folder, episode, station, message }

    let id: String
    let title: String
    let subtitle: String?
    let kind: Kind
    var art: CarArt? = nil
    /// The listened fraction, on Continue's rows.
    var progress: Double? = nil

    var isFolder: Bool { kind == .folder }
    var plays: Bool { kind == .episode || kind == .station }
}

/// A station the car can tune: `line` is what is on now, `artEpisodeID` the broadcast whose picture it wears.
nonisolated struct CarStation: Hashable, Sendable {
    let id: String
    let name: String
    let line: String?
    let artEpisodeID: String?
}

nonisolated enum CarTimeout {
    /// `work`'s answer, or nil when it has not answered within `budget` (the work is cancelled).
    static func run<T: Sendable>(_ budget: Duration, _ work: @escaping @MainActor @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: budget)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// The tree. Browse is the driver-safe part of the app's Browse: the shows you follow, the most
/// downloaded shows, the genres, the length bands; a show opens on its episodes (on its seasons first
/// when it has many). A list the app chooses for the listener leaves out `no_recommend` broadcasts. A
/// folder that cannot be built says why in one message row within `budget` (a car loads within 8 s),
/// never an empty screen or a spinner.
final class CarLibrary {
    static let root = "root"
    static let continueTab = "tab:continue"
    static let stationsTab = "tab:radio"
    static let browseTab = "tab:series"
    static let downloadsTab = "tab:downloads"
    static let following = "browse:following"
    static let popular = "browse:popular"
    static let genres = "browse:genres"
    static let lengths = "browse:lengths"
    static let stationPrefix = "station:"

    /// Most rows one folder holds; the template shows fewer when the car says so.
    static let pageMax = 100
    static let searchSeries = 5
    static let searchEpisodes = 25
    private static let showsMax = 50
    /// A show with more episodes than this, across several seasons, opens on its seasons.
    private static let splitAt = 100

    static let tabs: [CarNode] = [
        CarNode(id: continueTab, title: "Continue", subtitle: nil, kind: .folder),
        CarNode(id: stationsTab, title: "Stations", subtitle: nil, kind: .folder),
        CarNode(id: browseTab, title: "Browse", subtitle: nil, kind: .folder),
        CarNode(id: downloadsTab, title: "Downloads", subtitle: nil, kind: .folder),
    ]

    private static let browseFolders: [CarNode] = [
        CarNode(id: following, title: "Shows you follow", subtitle: nil, kind: .folder),
        CarNode(id: popular, title: "Popular shows", subtitle: nil, kind: .folder),
        CarNode(id: genres, title: "Genres", subtitle: nil, kind: .folder),
        CarNode(id: lengths, title: "By length", subtitle: nil, kind: .folder),
    ]

    static let noCatalog = "Open Ear Drama on your phone to download the catalog"
    static let slow = "Taking too long. Try again in a moment"
    static let offlineStations = "Stations need a connection"

    static func isStation(_ id: String) -> Bool { id.hasPrefix(stationPrefix) }
    static func message(_ text: String) -> CarNode { CarNode(id: "msg:\(text)", title: text, subtitle: nil, kind: .message) }

    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
    private static func dec(_ s: String) -> String { s.removingPercentEncoding ?? s }
    static func seriesID(_ key: String) -> String { "series/\(enc(key))" }
    private static func seasonID(_ key: String, _ season: String?) -> String { "season/\(enc(key))/\(season.map(enc) ?? "~")" }

    static func episodeNode(_ row: EpisodeRow) -> CarNode {
        let title = ItemLead.episodeTitle(row)
        let date = row.airDate.map { AirDate.medium($0) }
        let subtitle = [row.seriesName != title ? row.seriesName : nil, date != title ? date : nil]
            .compactMap { $0 }.joined(separator: " \u{00B7} ")
        return CarNode(id: row.id, title: title, subtitle: subtitle.isEmpty ? nil : subtitle, kind: .episode, art: .episode(row.id))
    }

    static func seriesNode(_ row: SeriesRow) -> CarNode {
        let first = row.firstDate.map { String($0.prefix(4)) }
        let last = row.lastDate.map { String($0.prefix(4)) }
        var run: [String] = []
        for year in [first, last].compactMap({ $0 }) where !run.contains(year) { run.append(year) }
        let count = "\(row.episodeCount) episode\(row.episodeCount == 1 ? "" : "s")"
        let subtitle = [run.isEmpty ? nil : run.joined(separator: "\u{2013}"), count].compactMap { $0 }.joined(separator: " \u{00B7} ")
        return CarNode(id: seriesID(row.key), title: row.name, subtitle: subtitle, kind: .folder, art: .series(row.key))
    }

    static func stationNode(_ s: CarStation) -> CarNode {
        CarNode(id: s.id, title: s.name, subtitle: s.line, kind: .station, art: s.artEpisodeID.map(CarArt.episode))
    }

    private enum Built: Sendable {
        case nodes([CarNode])
        case unknown
    }

    private let catalog: CatalogStore
    private let inProgressIDs: () -> [String]
    private let progress: (String) -> Double?
    /// The finished downloads, newest first: what plays with no signal (R17).
    private let downloadedIDs: () -> [String]
    /// The keys of the shows the listener follows, newest follow first.
    private let followed: () -> [String]
    /// The stations on the air now; throws when they cannot be read (offline).
    private let stations: () async throws -> [CarStation]
    private let budget: Duration

    init(catalog: CatalogStore,
         inProgressIDs: @escaping () -> [String] = { [] },
         progress: @escaping (String) -> Double? = { _ in nil },
         downloadedIDs: @escaping () -> [String] = { [] },
         followed: @escaping () -> [String] = { [] },
         stations: @escaping () async throws -> [CarStation] = { [] },
         budget: Duration = .seconds(8)) {
        self.catalog = catalog
        self.inProgressIDs = inProgressIDs
        self.progress = progress
        self.downloadedIDs = downloadedIDs
        self.followed = followed
        self.stations = stations
        self.budget = budget
    }

    let rootNode = CarNode(id: root, title: "Ear Drama", subtitle: nil, kind: .folder)

    /// The children of `parent`, at most `pageMax`; nil when no such folder exists.
    func children(of parent: String) async -> [CarNode]? {
        guard Self.isFolderID(parent) else { return nil }
        let built = await CarTimeout.run(budget) { [self] in await build(parent).map(Built.nodes) ?? .unknown }
        switch built {
        case nil: return [Self.message(Self.slow)]
        case .unknown?: return nil
        case let .nodes(nodes)?: return Array(nodes.prefix(Self.pageMax))
        }
    }

    private static func isFolderID(_ id: String) -> Bool {
        id == root || tabs.contains { $0.id == id } || browseFolders.contains { $0.id == id }
            || ["genre/", "length/", "series/", "season/"].contains { id.hasPrefix($0) }
    }

    /// A node by id (a row the car asks about by its id).
    func item(_ id: String) async -> CarNode? {
        if id == Self.root { return rootNode }
        if Self.isStation(id) { return (try? await stations())?.first { $0.id == id }.map(Self.stationNode) }
        if id.hasPrefix("series/") {
            await catalog.whenReady()
            return await catalog.series([Self.dec(String(id.dropFirst("series/".count)))]).first.map(Self.seriesNode)
        }
        if let known = (Self.tabs + Self.browseFolders).first(where: { $0.id == id }) { return known }
        return await catalog.episodes([id]).first.map(Self.episodeNode)
    }

    /// Where the listener left off: the most recent episode in progress, or nil.
    func resumeTarget() async -> String? {
        await CarTimeout.run(budget) { [self] in await catalog.episodes(Array(inProgressIDs().prefix(1))).first?.id } ?? nil
    }

    /// The car's search: the shows then the episodes the app's own search finds for `query`.
    func search(_ query: String) async -> [CarNode] {
        let q = query.trim
        guard !q.isEmpty else { return [] }
        let found = await CarTimeout.run(budget) { [self] () -> [CarNode] in
            guard await ready() else { return [Self.message(Self.noCatalog)] }
            let results = await catalog.search(q)
            let nodes = results.series.prefix(Self.searchSeries).map(Self.seriesNode)
                + results.episodes.prefix(Self.searchEpisodes).map(Self.episodeNode)
            return nodes.isEmpty ? [Self.message("Nothing found for \(q)")] : nodes
        }
        return found ?? [Self.message(Self.slow)]
    }

    /// What "play X on Ear Drama" plays: a station named, else a show's episode in progress or its first,
    /// else an episode the search finds, else where the listener left off; never nothing while the catalog
    /// has anything.
    func voiceTarget(_ query: String?) async -> String? {
        let q = (query ?? "").trim
        if !q.isEmpty {
            if let list = try? await stations(),
               let hit = list.first(where: { $0.name.localizedCaseInsensitiveContains(q) || q.localizedCaseInsensitiveContains($0.name) }) {
                return hit.id
            }
            if let found = await CarTimeout.run(budget, { [self] in await catalog.search(q) }) {
                if let show = found.series.first, let page = await catalog.seriesPage(show.key) {
                    let rows = await catalog.episodes(inProgressIDs())
                    if let id = rows.first(where: { $0.seriesKey == show.key })?.id ?? page.episodes.first?.id { return id }
                }
                if let episode = found.episodes.first { return episode.id }
            }
        }
        if let resume = await resumeTarget() { return resume }
        return await CarTimeout.run(budget) { [self] in await catalog.randomEpisode()?.id } ?? nil
    }

    // MARK: - Folders

    private func ready() async -> Bool {
        await catalog.whenReady()
        return catalog.state == .ready
    }

    private func build(_ parent: String) async -> [CarNode]? {
        switch parent {
        case Self.root: return Self.tabs
        case Self.continueTab: return await continuing()
        case Self.downloadsTab: return await downloaded()
        case Self.stationsTab: return await onAir()
        case Self.browseTab: return Self.browseFolders
        default: return await browse(parent)
        }
    }

    private func onAir() async -> [CarNode] {
        let list: [CarStation]
        do { list = try await stations() } catch { return [Self.message(Self.offlineStations)] }
        return list.isEmpty ? [Self.message("Nothing is on the air right now")] : list.map(Self.stationNode)
    }

    private func continuing() async -> [CarNode] {
        guard await ready() else { return [Self.message(Self.noCatalog)] }
        var seen = Set<String>()
        let rows = await catalog.episodes(inProgressIDs()).filter { seen.insert($0.id).inserted }
        let nodes = rows.map { row -> CarNode in
            var node = Self.episodeNode(row)
            node.progress = progress(row.id)
            return node
        }
        return nodes.isEmpty ? [Self.message("Nothing in progress")] : nodes
    }

    private func downloaded() async -> [CarNode] {
        let ids = downloadedIDs()
        guard await ready() else { return [Self.message(Self.noCatalog)] }
        let byID = Dictionary(await catalog.episodes(ids).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let nodes = ids.compactMap { byID[$0] }.map(Self.episodeNode)
        return nodes.isEmpty ? [Self.message("No downloads yet")] : nodes
    }

    /// Shows only (a series of at least `ShowLine.showMin`), most downloaded first, never one whose every
    /// broadcast is withheld from recommendations.
    private func shows(genre: String? = nil) async -> [SeriesRow] {
        let rows = await catalog.run {
            $0.seriesBrowse(genre: genre, sort: .popular, forShelf: true, limit: 2_000)
        } ?? []
        return Array(rows.filter { ShowLine.isShow($0.episodeCount) }.prefix(Self.showsMax))
    }

    private func browse(_ id: String) async -> [CarNode]? {
        guard await ready() else { return [Self.message(Self.noCatalog)] }
        if id == Self.following {
            let rows = await catalog.series(followed())
            return rows.isEmpty ? [Self.message("Follow a show on your phone and it appears here")] : rows.map(Self.seriesNode)
        }
        if id == Self.popular { return await shows().map(Self.seriesNode) }
        if id == Self.genres {
            let present = await catalog.run { $0.genres() } ?? []
            var nodes: [CarNode] = []
            for genre in ShowLine.genreOrder where present.contains(genre) {
                guard GenreDisplay.names[genre] != nil else { continue }
                if await shows(genre: genre).isEmpty { continue }
                nodes.append(CarNode(id: "genre/\(Self.enc(genre))", title: GenreDisplay.name(genre), subtitle: nil, kind: .folder))
            }
            return nodes
        }
        if id == Self.lengths {
            return HomeShelves(await catalog.listenShelves()).length.map {
                CarNode(id: "length/\(Self.enc($0.id.replacingOccurrences(of: "length-", with: "")))", title: $0.title,
                        subtitle: nil, kind: .folder)
            }
        }
        if id.hasPrefix("genre/") { return await shows(genre: Self.dec(String(id.dropFirst("genre/".count)))).map(Self.seriesNode) }
        if id.hasPrefix("length/") {
            let band = "length-" + Self.dec(String(id.dropFirst("length/".count)))
            let ids = HomeShelves(await catalog.listenShelves()).length.first { $0.id == band }?.episodes.map(\.id) ?? []
            let capped = Array(ids.prefix(Self.pageMax))
            return (await catalog.run { $0.recommendableEpisodes(ids: capped) } ?? []).map(Self.episodeNode)
        }
        if id.hasPrefix("series/") { return await seriesChildren(Self.dec(String(id.dropFirst("series/".count)))) }
        let parts = String(id.dropFirst("season/".count)).split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let page = await catalog.seriesPage(Self.dec(String(parts[0]))) else { return nil }
        let season = Self.dec(String(parts[1]))
        return page.seasons.first { ($0.season ?? "~") == season }?.episodes.map(Self.episodeNode) ?? []
    }

    /// A show opens on its episodes, oldest first; one with many across several seasons opens on its seasons.
    private func seriesChildren(_ key: String) async -> [CarNode]? {
        guard let page = await catalog.seriesPage(key) else { return nil }
        if page.seasons.count > 1 && page.episodes.count > Self.splitAt {
            return page.seasons.map {
                CarNode(id: Self.seasonID(page.series.key, $0.season), title: $0.season.map { "Season \($0)" } ?? "Undated",
                        subtitle: "\($0.episodes.count) episodes", kind: .folder)
            }
        }
        return page.episodes.map(Self.episodeNode)
    }
}

private extension String {
    var trim: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
