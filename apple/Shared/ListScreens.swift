#if os(iOS) || os(macOS)
import SwiftUI

// The List-based screens the iPhone, iPad, and Mac trees share. Each platform
// wraps them in its own shell (a tab bar, a split view); the TV has its own
// focus-driven screens in tvOS/.

/// The ONE destination registry: every NavigationStack applies it.
struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case let .series(key): SeriesScreen(key: key)
            case let .episode(id): EpisodeScreen(id: id)
            case .account: AccountScreen()
            case .surprise: SurpriseScreen()
            }
        }
        .navigationDestination(for: PlayRoute.self) { route in
            switch route {
            case let .script(id): PlayScriptScreen(id: id)
            case let .production(id): ProductionScreen(id: id)
            case let .recording(production, part): PartScreen(productionID: production, part: part)
            }
        }
    }
}

extension View {
    func routeDestinations() -> some View { modifier(RouteDestinations()) }
}

private struct PlayContextMenu: ViewModifier {
    let episodeID: String
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                PlayEpisodeAction(catalog: catalog, player: player, store: store)(episodeID)
            } label: {
                Label("Play", systemImage: "play")
            }
        }
    }
}

extension View {
    func playContextMenu(_ episodeID: String) -> some View { modifier(PlayContextMenu(episodeID: episodeID)) }
}

// MARK: - Home (iOS-DESIGN §4.1; was Listen)

struct ListenScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
    @Environment(AppStore.self) private var store
    @State private var shelves: [Shelf]?
    @State private var continuing: [EpisodeRow] = []

    var body: some View {
        List {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if let shelves {
                if !continuing.isEmpty {
                    Section("Continue listening") {
                        ForEach(continuing) { episode in
                            NavigationLink(value: Route.episode(episode.id)) {
                                EpisodeRowLabel(episode: episode, showSeries: true)
                            }
                            .playContextMenu(episode.id)
                        }
                    }
                }
                ForEach(shelves) { shelf in
                    Section(shelf.rule.title) {
                        ForEach(shelf.episodes) { episode in
                            NavigationLink(value: Route.episode(episode.id)) {
                                EpisodeRowLabel(episode: episode, showSeries: true)
                            }
                            .playContextMenu(episode.id)
                        }
                    }
                }
                if shelves.isEmpty && continuing.isEmpty {
                    ContentUnavailableView("Nothing to list yet", systemImage: "radio")
                }
            } else {
                SkeletonRows()
            }
        }
        .navigationTitle("Home")
        #if os(iOS)
        // iPhone's way to Surprise (iOS-DESIGN §3.1, Archive Watch §2.6: a push).
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.push(Route.surprise) } label: { Label("Surprise", systemImage: AppTab.surprise.symbol) }
            }
        }
        #endif
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            shelves = await catalog.listenShelves()
        }
        .task(id: history.inProgressIDs.joined(separator: "\n") + "#\(catalog.loadKey)") {
            continuing = await catalog.episodes(Array(history.inProgressIDs.prefix(10)))
        }
    }
}

// MARK: - Browse (iOS-DESIGN §4.2; was Series)

/// What Browse lists: a radio series, or a stage play (Decision 068).
enum BrowseKind: String, CaseIterable, Hashable {
    case series, plays
    var title: String { self == .series ? "Series" : "Plays" }
}

struct SeriesBrowseScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(PlaysLibrary.self) private var plays
    @State private var series: [SeriesRow]?
    @State private var facets: (genres: [String], networks: [String], decades: [Int]) = ([], [], [])
    @State private var kind: BrowseKind?
    @State private var hasScript = false
    @State private var genre: String?
    @State private var network: String?
    @State private var decade: Int?

    private struct Filter: Hashable { let genre: String?, network: String?, decade: Int?, generation: Int }

    /// A play carries no genre, network, or decade, and only plays carry a
    /// script today, so either side of the list can be narrowed away.
    private var showsSeries: Bool { kind != .plays && !hasScript }
    private var showsPlays: Bool { kind != .series && genre == nil && network == nil && decade == nil }
    private var shownPlays: [PlayScript] { showsPlays ? plays.scripts : [] }
    private var isFiltered: Bool { kind != nil || hasScript || genre != nil || network != nil || decade != nil }

    var body: some View {
        Group {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if let series {
                let rows = showsSeries ? series : []
                if rows.isEmpty && shownPlays.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
                    } actions: {
                        Button("Clear Filters") { clear() }
                    }
                } else {
                    List {
                        ForEach(rows) { row in
                            NavigationLink(value: Route.series(row.key)) { SeriesRowLabel(series: row) }
                        }
                        ForEach(shownPlays) { script in
                            NavigationLink(value: PlayRoute.script(script.id)) { ScriptRow(script: script) }
                        }
                    }
                }
            } else {
                List { SkeletonRows() }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { chips }
        .navigationTitle("Browse")
        .task(id: catalog.loadKey) { facets = await catalog.browseFacets() }
        .task { await plays.load() }
        .task(id: Filter(genre: genre, network: network, decade: decade, generation: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            series = await catalog.seriesBrowse(genre: genre, network: network, decade: decade)
        }
    }

    private func clear() { kind = nil; hasScript = false; genre = nil; network = nil; decade = nil }

    /// Archive Watch's iOS-DESIGN §4.2a: the filters are chips you can see,
    /// each a native Menu naming its value; Clear leads once anything is set.
    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s2) {
                if isFiltered {
                    Button("Clear") { clear() }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear filters")
                }
                chip(kind?.title ?? "Kind", on: kind != nil) {
                    Picker("Kind", selection: $kind) {
                        Text("Any kind").tag(BrowseKind?.none)
                        ForEach(BrowseKind.allCases, id: \.self) { Text($0.title).tag(BrowseKind?.some($0)) }
                    }
                }
                chip(genre.map(GenreDisplay.name) ?? "Genre", on: genre != nil) {
                    Picker("Genre", selection: $genre) {
                        Text("Any genre").tag(String?.none)
                        ForEach(facets.genres, id: \.self) { Text(GenreDisplay.name($0)).tag(String?.some($0)) }
                    }
                }
                chip(decade.map { "\($0)s" } ?? "Decade", on: decade != nil) {
                    Picker("Decade", selection: $decade) {
                        Text("Any decade").tag(Int?.none)
                        ForEach(facets.decades, id: \.self) { Text(verbatim: "\($0)s").tag(Int?.some($0)) }
                    }
                }
                chip(network ?? "Network", on: network != nil) {
                    Picker("Network", selection: $network) {
                        Text("Any network").tag(String?.none)
                        ForEach(facets.networks, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }
                Toggle("Has a script", isOn: $hasScript)
                    .toggleStyle(.button)
                    .buttonBorderShape(.capsule)
                    .tint(hasScript ? Color.brandSecondary : Color.brandTextMuted)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }

    private func chip<Content: View>(_ title: String, on: Bool, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Text(verbatim: title)
                .font(TypeRamp.caption)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s1)
                .foregroundStyle(on ? Color.brandOnSecondary : Color.brandText)
                .background(on ? Color.brandSecondary : Color.brandSurface, in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }
}

// MARK: - Series page

struct SeriesScreen: View {
    let key: String
    @Environment(CatalogStore.self) private var catalog
    @State private var page: SeriesPage??

    var body: some View {
        Group {
            switch page {
            case .none:
                List { SkeletonRows(count: 10) }
            case .some(.none):
                ContentUnavailableView("Series not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)):
                List {
                    Section {
                        Text(verbatim: page.series.metaLine)
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                    ForEach(page.seasons) { season in
                        Section {
                            ForEach(season.episodes) { episode in
                                NavigationLink(value: Route.episode(episode.id)) {
                                    EpisodeRowLabel(episode: episode)
                                }
                                .playContextMenu(episode.id)
                            }
                        } header: {
                            Text(verbatim: season.season ?? "Undated")
                        }
                    }
                }
                .navigationTitle(page.series.name)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            page = .some(await catalog.seriesPage(key))
        }
    }
}

// MARK: - Episode detail

struct EpisodeScreen: View {
    let id: String
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(DownloadStore.self) private var downloads
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    @State private var transcriptOpen = false
    #endif
    @State private var detail: EpisodeDetail??

    var body: some View {
        Group {
            switch detail {
            case .none:
                List { SkeletonRows(count: 4) }
            case .some(.none):
                ContentUnavailableView("Episode not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(detail)):
                content(detail)
            }
        }
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            detail = .some(await catalog.episodeDetail(id))
        }
    }

    private func content(_ detail: EpisodeDetail) -> some View {
        let episode = detail.episode
        let isCurrent = player.item?.episode.id == episode.id
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        return List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    NavigationLink(value: Route.series(episode.seriesKey)) {
                        Text(episode.seriesName)
                            .font(TypeRamp.body)
                            .foregroundStyle(Color.brandLink)
                    }
                    Text(episode.displayTitle)
                        .font(TypeRamp.sectionHeader)
                        .foregroundStyle(Color.brandText)
                    Text(verbatim: factsLine(detail))
                        .font(TypeRamp.tabular)
                        .foregroundStyle(Color.brandTextMuted)
                }
                .padding(.vertical, Spacing.s2)

                Button {
                    if isCurrent { player.togglePlayPause() } else { play(episode.id) }
                } label: {
                    Label(isCurrent && player.isPlaying ? "Pause" : "Play",
                          systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(TypeRamp.bodyStrong)
                }
                .tint(Color.brandPrimary)
                .disabled(detail.recordings.isEmpty)
                DownloadControl(detail: detail)
                if let url = episode.transcriptURL {
                    Button {
                        #if os(macOS)
                        openWindow(id: TranscriptRef.windowID,
                                   value: TranscriptRef(title: episode.displayTitle, url: url))
                        #else
                        transcriptOpen = true
                        #endif
                    } label: {
                        Label(Transcript.label, systemImage: "text.quote")
                    }
                }
                if !catalog.isOnline && downloads.record(for: episode.id)?.state != .downloaded { OfflineNotice() }
                if isCurrent, let message = player.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.semanticError)
                }
            }

            ForEach(CreditGroups.grouped(detail.credits), id: \.role) { group in
                Section(group.role) {
                    ForEach(group.credits) { credit in
                        Text(credit.line).font(TypeRamp.body)
                    }
                }
            }

            if detail.recordings.count > 1 {
                Section("Versions") {
                    ForEach(detail.recordings) { recording in
                        Button {
                            play(episode.id, recording: recording)
                        } label: {
                            VersionLabel(recording: recording, isDefault: recording.rank == 0)
                        }
                        .accessibilityHint("Plays this copy")
                    }
                }
            }

            if let rightsLine = detail.rightsLine {
                Section {
                    Text(rightsLine)
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                }
            }
        }
        .navigationTitle(episode.displayTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // The https twin, never the file (iOS-DESIGN §4.4, DEEP_LINKS.md).
                ShareLink(item: SiteLinks.episode(episode.id), subject: Text(episode.displayTitle)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share")
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $transcriptOpen) {
            if let url = episode.transcriptURL { TranscriptSheet_iOS(url: url) }
        }
        #endif
    }

    private func factsLine(_ detail: EpisodeDetail) -> String {
        let e = detail.episode
        return [AirDate.display(e.airDate), e.network, detail.sponsor, e.durationText]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

struct VersionLabel: View {
    let recording: Recording
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(recording.archiveID)
                .font(TypeRamp.body)
                .foregroundStyle(Color.brandText)
            Text(verbatim: facts)
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
        }
    }

    private var facts: String {
        var parts = recording.notes
        if let length = recording.lengthSeconds { parts.append(EpisodeRow.clock(length)) }
        if let kbps = recording.kbps { parts.append("\(kbps) kbps") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Search

struct SearchResultsList: View {
    let query: String
    @Environment(CatalogStore.self) private var catalog
    @Environment(PlaysLibrary.self) private var plays
    @State private var results: SearchResults?
    @State private var searchedFor = ""

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search titles, series, and people", systemImage: "magnifyingglass")
            } else if let results, searchedFor == query {
                let matchingPlays = Self.plays(plays.scripts, matching: query)
                if results.isEmpty && matchingPlays.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        if !results.series.isEmpty {
                            Section("Series") {
                                ForEach(results.series) { row in
                                    NavigationLink(value: Route.series(row.key)) { SeriesRowLabel(series: row) }
                                }
                            }
                        }
                        if !matchingPlays.isEmpty {
                            Section("Plays") {
                                ForEach(matchingPlays) { script in
                                    NavigationLink(value: PlayRoute.script(script.id)) { ScriptRow(script: script) }
                                }
                            }
                        }
                        if !results.episodes.isEmpty {
                            Section("Episodes") {
                                ForEach(results.episodes) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        EpisodeRowLabel(episode: episode, showSeries: true,
                                                        note: results.transcriptOnly.contains(episode.id)
                                                            ? Transcript.searchNote : nil)
                                    }
                                    .playContextMenu(episode.id)
                                }
                            }
                        }
                    }
                }
            } else {
                List { SkeletonRows() }
            }
        }
        .task { await plays.load() }
        .task(id: query) {
            let q = query
            guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            // Debounce typing; a newer query cancels this task.
            guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
            results = await catalog.search(q)
            searchedFor = q
        }
    }
}

extension SearchResultsList {
    /// Word-prefix, as every search here (§3.4): each typed word begins a word
    /// of the play's title or author.
    static func plays(_ scripts: [PlayScript], matching query: String) -> [PlayScript] {
        let words = Self.words(query)
        guard !words.isEmpty else { return [] }
        return scripts.filter { script in
            let have = Self.words("\(script.title) \(script.authorLine)")
            return words.allSatisfy { w in have.contains { $0.hasPrefix(w) } }
        }
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

// MARK: - Library

struct LibraryScreen: View {
    private struct LibraryKey: Equatable { let entries: [String: ListeningHistory.Entry]; let load: Int }
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
    @Environment(DownloadStore.self) private var downloads
    @Environment(PlaysLibrary.self) private var plays
    @State private var inProgress: [EpisodeRow]?
    @State private var played: [EpisodeRow] = []

    var body: some View {
        Group {
            if let inProgress {
                if inProgress.isEmpty && played.isEmpty && downloads.records.isEmpty && plays.store.productions.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing played yet", systemImage: "books.vertical")
                    } actions: {
                        AccountRow().fixedSize()
                    }
                } else {
                    List {
                        if !inProgress.isEmpty {
                            Section("In progress") {
                                ForEach(inProgress) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        EpisodeRowLabel(episode: episode, showSeries: true)
                                    }
                                    .swipeActions { removeButton(episode.id) }
                                    .contextMenu { removeButton(episode.id) }
                                }
                            }
                        }
                        DownloadsSection()
                        EarDramasSection()
                        if !played.isEmpty {
                            Section("Played") {
                                ForEach(played) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        EpisodeRowLabel(episode: episode, showSeries: true)
                                    }
                                    .swipeActions { removeButton(episode.id) }
                                    .contextMenu { removeButton(episode.id) }
                                }
                            }
                        }
                        Section { AccountRow() }
                    }
                }
            } else {
                List { SkeletonRows() }
            }
        }
        .navigationTitle("Library")
        .task(id: LibraryKey(entries: history.entries, load: catalog.loadKey)) {
            let ids = history.inProgressIDs
            let playedIDs = history.entries.filter(\.value.finished)
                .sorted { $0.value.updatedAt > $1.value.updatedAt }.map(\.key).prefix(100)
            inProgress = await catalog.episodes(ids)
            played = await catalog.episodes(Array(playedIDs))
        }
    }

    private func removeButton(_ id: String) -> some View {
        Button(role: .destructive) { history.remove(id) } label: {
            Label("Remove from History", systemImage: "trash")
        }
    }
}
#endif
