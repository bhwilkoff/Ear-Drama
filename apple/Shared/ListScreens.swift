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

// MARK: - Listen

struct ListenScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
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
                    ContentUnavailableView("Nothing to list yet", systemImage: "radio",
                                           description: Text("Browse Series to start."))
                }
            } else {
                SkeletonRows()
            }
        }
        .navigationTitle("Listen")
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            shelves = await catalog.listenShelves()
        }
        .task(id: history.inProgressIDs.joined(separator: "\n") + "#\(catalog.loadKey)") {
            continuing = await catalog.episodes(Array(history.inProgressIDs.prefix(10)))
        }
    }
}

// MARK: - Series browse

struct SeriesBrowseScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var series: [SeriesRow]?
    @State private var facets: (genres: [String], networks: [String], decades: [Int]) = ([], [], [])
    @State private var genre: String?
    @State private var network: String?
    @State private var decade: Int?

    private struct Filter: Hashable { let genre: String?, network: String?, decade: Int?, generation: Int }

    var body: some View {
        Group {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if let series {
                if series.isEmpty {
                    ContentUnavailableView {
                        Label("No series match", systemImage: "line.3.horizontal.decrease.circle")
                    } actions: {
                        Button("Clear Filters") { genre = nil; network = nil; decade = nil }
                    }
                } else {
                    List(series) { row in
                        NavigationLink(value: Route.series(row.key)) { SeriesRowLabel(series: row) }
                    }
                }
            } else {
                List { SkeletonRows() }
            }
        }
        .navigationTitle("Series")
        .toolbar { ToolbarItem(placement: .primaryAction) { filterMenu } }
        .task(id: catalog.loadKey) { facets = await catalog.browseFacets() }
        .task(id: Filter(genre: genre, network: network, decade: decade, generation: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            series = await catalog.seriesBrowse(genre: genre, network: network, decade: decade)
        }
    }

    private var isFiltered: Bool { genre != nil || network != nil || decade != nil }

    private var filterMenu: some View {
        Menu {
            Picker("Genre", selection: $genre) {
                Text("Any genre").tag(String?.none)
                ForEach(facets.genres, id: \.self) { Text(GenreDisplay.name($0)).tag(String?.some($0)) }
            }
            .pickerStyle(.menu)
            Picker("Network", selection: $network) {
                Text("Any network").tag(String?.none)
                ForEach(facets.networks, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .pickerStyle(.menu)
            Picker("Decade", selection: $decade) {
                Text("Any decade").tag(Int?.none)
                ForEach(facets.decades, id: \.self) { Text(verbatim: "\($0)s").tag(Int?.some($0)) }
            }
            .pickerStyle(.menu)
            if isFiltered {
                Button("Clear Filters", role: .destructive) { genre = nil; network = nil; decade = nil }
            }
        } label: {
            Label("Filter", systemImage: isFiltered
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter series")
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
                            .foregroundStyle(Color.brandPrimary)
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
    @State private var results: SearchResults?
    @State private var searchedFor = ""

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search titles, series, and people", systemImage: "magnifyingglass")
            } else if let results, searchedFor == query {
                if results.isEmpty {
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

// MARK: - Library

struct LibraryScreen: View {
    private struct LibraryKey: Equatable { let entries: [String: ListeningHistory.Entry]; let load: Int }
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
    @Environment(DownloadStore.self) private var downloads
    @State private var inProgress: [EpisodeRow]?
    @State private var played: [EpisodeRow] = []

    var body: some View {
        Group {
            if let inProgress {
                if inProgress.isEmpty && played.isEmpty && downloads.records.isEmpty {
                    ContentUnavailableView("Nothing played yet", systemImage: "books.vertical",
                                           description: Text("Episodes you start are kept here."))
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
