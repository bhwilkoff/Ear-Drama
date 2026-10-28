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
            case let .person(id): PersonScreen(id: id)
            case .account: AccountScreen()
            case .surprise: SurpriseScreen()
            }
        }
        .navigationDestination(for: DownloadsRoute.self) { _ in DownloadsScreen() }
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
            QueueMenuItem(episodeID: episodeID)
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
    /// Series key -> the castable script ids its episodes link (contract §3.1).
    @State private var scripted: [String: [String]] = [:]
    @State private var genre: String?
    @State private var network: String?
    @State private var decade: Int?
    @State private var sort: SeriesSort = .popular

    private struct Filter: Hashable {
        let genre: String?, network: String?, decade: Int?, sort: SeriesSort, generation: Int
    }

    /// A play carries no genre, network, or decade, so those narrow to series;
    /// "Has a script" keeps the plays and the series with a linked episode
    /// whose script this device's bundle holds.
    private var showsSeries: Bool { kind != .plays }
    private func shownSeries(_ all: [SeriesRow]) -> [SeriesRow] {
        guard showsSeries else { return [] }
        guard hasScript else { return all }
        return all.filter { scripted[$0.key]?.contains { plays.script($0) != nil } == true }
    }
    private var showsPlays: Bool { kind != .series && genre == nil && network == nil && decade == nil }
    private var shownPlays: [PlayScript] { showsPlays ? plays.scripts : [] }
    private var isFiltered: Bool { kind != nil || hasScript || genre != nil || network != nil || decade != nil }

    /// One List for every state, as Home and Library: swapping scroll views
    /// under the bar lost the large title (seen on an iPhone 12, 2026-10-24).
    var body: some View {
        List {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if let series {
                ForEach(shownSeries(series)) { row in
                    NavigationLink(value: Route.series(row.key)) { SeriesRowLabel(series: row) }
                }
                ForEach(shownPlays) { script in
                    NavigationLink(value: PlayRoute.script(script.id)) { ScriptRow(script: script) }
                }
            } else {
                SkeletonRows()
            }
        }
        .overlay {
            if catalog.state != .unavailable, let series, shownSeries(series).isEmpty, shownPlays.isEmpty {
                ContentUnavailableView {
                    Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Clear Filters") { clear() }
                }
            }
        }
        .modifier(TopBar { chips })
        .navigationTitle("Browse")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task(id: catalog.loadKey) {
            facets = await catalog.browseFacets()
            scripted = await catalog.scriptedSeries()
        }
        .task { await plays.load() }
        .task(id: Filter(genre: genre, network: network, decade: decade, sort: sort, generation: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            series = await catalog.seriesBrowse(genre: genre, network: network, decade: decade, sort: sort)
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
                // An order, not a filter: never filled, never cleared (Archive Watch §4.2a).
                chip("Sort: \(sort.title)", on: false) {
                    Picker("Sort", selection: $sort) {
                        ForEach(SeriesSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
        }
        .scrollIndicators(.hidden)
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

/// A bar of controls pinned under the navigation bar. On 26 it is the
/// system's `safeAreaBar`, which keeps the large title and the scroll edge
/// effect; before, an inset whose material stops at the safe area, so it never
/// paints over the title.
private struct TopBar<Bar: View>: ViewModifier {
    @ViewBuilder let bar: () -> Bar

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content.safeAreaBar(edge: .top, spacing: 0) { bar() }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                bar().background(.bar, ignoresSafeAreaEdges: [])
            }
        }
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
                        HStack(alignment: .top, spacing: Spacing.s3) {
                            if let face = page.series.face { FaceFigure(face: face) }
                            Text(verbatim: page.series.metaLine)
                                .font(TypeRamp.caption)
                                .foregroundStyle(Color.brandTextMuted)
                        }
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
                .toolbar { SeriesDownloadMenu(page: page) }
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
    @Environment(PlaysLibrary.self) private var plays
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
        .task { await plays.load() }
    }

    private func content(_ detail: EpisodeDetail) -> some View {
        let episode = detail.episode
        let isCurrent = player.item?.episode.id == episode.id
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        return List {
            Section {
                HStack(alignment: .top, spacing: Spacing.s3) {
                    if let face = detail.starFace { FaceFigure(face: face) }
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
                }
                .padding(.vertical, Spacing.s2)

                Button {
                    if isCurrent { player.togglePlayPause() } else { play(episode.id) }
                } label: {
                    Label(isCurrent && player.isPlaying ? "Pause" : "Play",
                          systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(TypeRamp.bodyStrong)
                        // A List row draws a Label's icon in the app tint, not the button's.
                        .foregroundStyle(detail.recordings.isEmpty ? Color.brandTextMuted : Color.brandPrimary)
                }
                .tint(Color.brandPrimary)
                .disabled(detail.recordings.isEmpty)
                QueueToggleButton(episodeID: episode.id)
                DownloadControl(detail: detail)
                // Decision 068: an episode linked to a castable script this bundle holds.
                if let id = detail.script, let script = plays.script(id) {
                    StartEarDramaButton(script: script)
                }
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
                let faces = group.credits.contains { $0.art != nil }
                Section(group.role) {
                    ForEach(group.credits) { credit in
                        // withPerson (§4.13): a credited name pushes the person's page.
                        NavigationLink(value: Route.person(credit.personID)) {
                            HStack(spacing: Spacing.s2) {
                                if faces { CreditFace(art: credit.art) }
                                Text(credit.line).font(TypeRamp.body)
                            }
                        }
                        .disabled(credit.personID.isEmpty)
                    }
                }
            }
            // CC BY / BY-SA portraits carry their credit (Decision 069); the heading's face already does.
            let owed = detail.owedCredits
            if !owed.isEmpty {
                Section {
                    ForEach(owed, id: \.personID) { credit in
                        if let art = credit.art, let line = art.credit {
                            LabeledContent(credit.name) { ArtCredit(credit: line, evidence: art.evidence) }
                                .font(TypeRamp.caption)
                        }
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

// MARK: - A person (withPerson, iOS-DESIGN §4.13)

struct PersonScreen: View {
    let id: String
    @Environment(CatalogStore.self) private var catalog
    @State private var page: PersonPage??
    @State private var newestFirst = false

    var body: some View {
        Group {
            switch page {
            case .none:
                List { SkeletonRows(count: 10) }
            case .some(.none):
                ContentUnavailableView("Person not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)):
                List {
                    Section {
                        HStack(alignment: .top, spacing: Spacing.s3) {
                            if let face = page.person.face { FaceFigure(face: face) }
                            Text(verbatim: Self.facts(page))
                                .font(TypeRamp.caption)
                                .foregroundStyle(Color.brandTextMuted)
                        }
                    }
                    ForEach(page.groups(newestFirst: newestFirst)) { group in
                        Section {
                            ForEach(group.episodes) { item in
                                NavigationLink(value: Route.episode(item.id)) {
                                    EpisodeRowLabel(episode: item.episode, note: item.rolesLine)
                                }
                                .playContextMenu(item.id)
                            }
                        } header: {
                            Text(group.seriesName)
                        }
                    }
                }
                .navigationTitle(page.person.name)
                .toolbar {
                    if page.episodes.count > 1 {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Picker("Order", selection: $newestFirst) {
                                    Text("Oldest first").tag(false)
                                    Text("Newest first").tag(true)
                                }
                            } label: {
                                Label("Order", systemImage: "arrow.up.arrow.down")
                            }
                            .help("Order")
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            page = .some(await catalog.personPage(id))
        }
    }

    /// The years and the count, facts from the data only (no bio is written).
    static func facts(_ page: PersonPage) -> String {
        [page.person.years, PersonRowLabel.count(page.episodes.count)].compactMap { $0 }.joined(separator: " · ")
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
                        if !results.people.isEmpty {
                            Section("People") {
                                ForEach(results.people) { row in
                                    NavigationLink(value: Route.person(row.id)) { PersonRowLabel(row: row) }
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
                        if let aired = results.aired, !aired.episodes.isEmpty {
                            Section(aired.title) {
                                ForEach(aired.episodes) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        EpisodeRowLabel(episode: episode, showSeries: true)
                                    }
                                    .playContextMenu(episode.id)
                                }
                            }
                        }
                        if !results.episodes.isEmpty {
                            Section("Episodes") {
                                ForEach(results.episodes) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        EpisodeRowLabel(episode: episode, showSeries: true)
                                    }
                                    .playContextMenu(episode.id)
                                }
                            }
                        }
                        if !results.transcript.isEmpty {
                            Section(Transcript.label) {
                                let words = Transcript.searchWords(query)
                                ForEach(results.transcript) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        TranscriptHitLabel(episode: episode, words: words)
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
    private struct LibraryKey: Equatable {
        let entries: [String: ListeningHistory.Entry]; let queue: [String]; let load: Int
    }
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
    @Environment(ListeningQueue.self) private var queue
    @Environment(DownloadStore.self) private var downloads
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(AccountStore.self) private var account
    @Environment(AppStore.self) private var app
    @State private var inProgress: [EpisodeRow]?
    @State private var played: [EpisodeRow] = []
    @State private var queued: [EpisodeRow] = []

    var body: some View {
        Group {
            if let inProgress {
                if inProgress.isEmpty && played.isEmpty && queue.items.isEmpty && downloads.records.isEmpty && plays.store.productions.isEmpty
                    && app.pendingInvite == nil && !account.isSignedIn {
                    ContentUnavailableView {
                        Label("Nothing played yet", systemImage: "books.vertical")
                    } actions: {
                        VStack(spacing: 12) {
                            AccountRow().fixedSize()
                            SiteLinkInline()
                        }
                    }
                } else {
                    List {
                        if !queued.isEmpty {
                            Section("Queue") {
                                ForEach(queued) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        EpisodeRowLabel(episode: episode, showSeries: true)
                                    }
                                    .swipeActions {
                                        Button(role: .destructive) { queue.remove(episode.id) } label: {
                                            Label("Remove from queue", systemImage: "trash")
                                        }
                                    }
                                    .contextMenu { QueueRowMenu(episodeID: episode.id) }
                                }
                                .onMove { source, destination in
                                    var ids = queued.map(\.id)
                                    ids.move(fromOffsets: source, toOffset: destination)
                                    queue.reorder(ids)
                                }
                            }
                        }
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
                        #if os(iOS)
                        Section { SiteLinkRows() }
                        #endif
                    }
                }
            } else {
                List { SkeletonRows() }
            }
        }
        .navigationTitle("Library")
        #if os(iOS)
        .toolbar { if !queued.isEmpty { ToolbarItem(placement: .primaryAction) { EditButton() } } }
        #endif
        .task(id: account.isSignedIn) { if account.isSignedIn { await shared.loadRemote() } }
        .task(id: LibraryKey(entries: history.entries, queue: queue.items, load: catalog.loadKey)) {
            let ids = history.inProgressIDs
            let playedIDs = history.entries.filter(\.value.finished)
                .sorted { $0.value.updatedAt > $1.value.updatedAt }.map(\.key).prefix(100)
            queued = await catalog.episodes(queue.items)
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
