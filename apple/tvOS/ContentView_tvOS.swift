#if os(tvOS)
import SwiftUI

// The ten-foot app (tvos-platform-patterns, ten-foot-detail-design): a
// sidebar of the top-level verbs, one NavigationStack per tab reset when the
// sidebar leaves it, focus doing the work (only the focused card is bright),
// cards with .card style (never .plain), and Now Playing as a full-screen
// typographic view: in radio the people are the picture.

struct ContentView_tvOS: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: Binding(get: { store.selectedTab }, set: { store.selectResettingPrevious($0) })) {
            // tvOS-DESIGN §2.1 (Decision 068): Archive Watch's sidebar, Surprise listed.
            Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: AppTab.home) {
                stack(.home) { ListenScreen_tvOS() }
            }
            Tab(AppTab.browse.title, systemImage: AppTab.browse.symbol, value: AppTab.browse) {
                stack(.browse) { SeriesBrowseScreen_tvOS() }
            }
            Tab(AppTab.stations.title, systemImage: AppTab.stations.symbol, value: AppTab.stations) {
                stack(.stations) { RadioScreen_tvOS() }
            }
            Tab(AppTab.search.title, systemImage: AppTab.search.symbol, value: AppTab.search, role: .search) {
                stack(.search) { SearchScreen_tvOS() }
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.symbol, value: AppTab.library) {
                stack(.library) { LibraryScreen_tvOS() }
            }
            Tab(AppTab.surprise.title, systemImage: AppTab.surprise.symbol, value: AppTab.surprise) {
                stack(.surprise) { SurpriseScreen_tvOS() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .fullScreenCover(isPresented: $store.isPlayerPresented) {
            NowPlaying_tvOS()
        }
    }

    private func stack<Root: View>(_ tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: store.path(for: tab)) {
            root()
                .safeAreaInset(edge: .top, spacing: 0) {
                    // The offline line heads every tab's root (tvOS-DESIGN §7.3).
                    VStack(spacing: 0) {
                        OfflineLine()
                        NowPlayingEntry_tvOS()
                    }
                }
                .routeDestinations_tvOS()
        }
    }
}

/// The way back to Now Playing (tvOS-DESIGN §5.4): heads every tab's root
/// while an episode is loaded and opens the player on it as it is.
private struct NowPlayingEntry_tvOS: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store

    var body: some View {
        if let item = player.item {
            HStack {
                Button {
                    store.isPlayerPresented = true
                } label: {
                    Label {
                        Text(verbatim: "Now Playing · \(item.episode.displayTitle) · \(item.episode.seriesName)")
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                    }
                    .font(TypeRamp.bodyStrong)
                }
                .accessibilityLabel("Now playing: \(item.episode.displayTitle), \(item.episode.seriesName)")
                .accessibilityHint("Opens the player")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 90)
            .padding(.vertical, Spacing.s4)
            .focusSection()
        }
    }
}

private struct RouteDestinations_tvOS: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case let .series(key): SeriesScreen_tvOS(key: key)
            case let .episode(id): EpisodeScreen_tvOS(id: id)
            case let .person(id): PersonScreen_tvOS(id: id)
            case .account: AccountScreen_tvOS()
            case .surprise: SurpriseScreen_tvOS()
            }
        }
    }
}

extension View {
    fileprivate func routeDestinations_tvOS() -> some View { modifier(RouteDestinations_tvOS()) }
}

// MARK: - Cards and rows

/// A typographic episode card: date, title, series. No art, no placeholder.
private struct EpisodeCard_tvOS: View {
    let episode: EpisodeRow

    var body: some View {
        NavigationLink(value: Route.episode(episode.id)) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(verbatim: AirDate.display(episode.airDate))
                    .font(TypeRamp.tabular)
                    .foregroundStyle(Color.brandTextMuted)
                Text(episode.displayTitle)
                    .font(TypeRamp.bodyStrong)
                    .foregroundStyle(Color.brandText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                HStack(spacing: Spacing.s3) {
                    ArtTile(name: episode.seriesName, genre: episode.seriesGenre, face: episode.seriesFace, size: 64)
                    Text(episode.seriesName)
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                        .lineLimit(1)
                }
            }
            .padding(Spacing.s6)
            .frame(width: 420, height: 236, alignment: .topLeading)
            .background(Color.brandSurface)
        }
        .buttonStyle(.card)
        .accessibilityElement(children: .combine)
        .contextMenu { QueueMenuItem(episodeID: episode.id) }
    }
}

/// A followed series as a typographic card, the episode card's size.
private struct SeriesCard_tvOS: View {
    let series: SeriesRow

    var body: some View {
        NavigationLink(value: Route.series(series.key)) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                ArtTile(name: series.name, genre: series.genre, face: series.face, size: 64)
                Spacer(minLength: 0)
                Text(series.name)
                    .font(TypeRamp.bodyStrong)
                    .foregroundStyle(Color.brandText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(verbatim: series.metaLine)
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
                    .lineLimit(1)
            }
            .padding(Spacing.s6)
            .frame(width: 420, height: 236, alignment: .topLeading)
            .background(Color.brandSurface)
        }
        .buttonStyle(.card)
        .accessibilityElement(children: .combine)
    }
}

private struct SeriesShelf_tvOS: View {
    let title: String
    let series: [SeriesRow]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(title)
                .font(TypeRamp.sectionHeader)
                .foregroundStyle(Color.brandText)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(series) { SeriesCard_tvOS(series: $0) }
                }
                .padding(.vertical, Spacing.s6)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

private struct ShelfRow_tvOS: View {
    let title: String
    let episodes: [EpisodeRow]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(title)
                .font(TypeRamp.sectionHeader)
                .foregroundStyle(Color.brandText)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(episodes) { EpisodeCard_tvOS(episode: $0) }
                }
                .padding(.vertical, Spacing.s6)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

// MARK: - Home (was Listen)

private struct ListenScreen_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
    @Environment(FollowedSeries.self) private var follows
    @State private var shelves: [Shelf]?
    @State private var continuing: [EpisodeRow] = []
    @State private var following: [SeriesRow] = []

    var body: some View {
        Group {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if let shelves {
                if shelves.isEmpty && continuing.isEmpty && following.isEmpty {
                    ContentUnavailableView("Nothing to list yet", systemImage: "radio")
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 80) {
                            if !continuing.isEmpty {
                                ShelfRow_tvOS(title: "Continue listening", episodes: continuing)
                            }
                            if !following.isEmpty {
                                SeriesShelf_tvOS(title: "Following", series: following)
                            }
                            ForEach(shelves) { ShelfRow_tvOS(title: $0.rule.title, episodes: $0.episodes) }
                        }
                        .padding(.vertical, 60)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            shelves = await catalog.listenShelves()
        }
        .task(id: history.inProgressIDs.joined(separator: "\n") + "#\(catalog.loadKey)") {
            continuing = await catalog.episodes(Array(history.inProgressIDs.prefix(10)))
        }
        .task(id: follows.followedKeys.joined(separator: "\n") + "#\(catalog.loadKey)") {
            following = await catalog.series(follows.followedKeys)
        }
    }
}

// MARK: - Browse (was Series; the TV lists no plays, PLAYS-DESIGN §6)

private struct SeriesBrowseScreen_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var series: [SeriesRow]?
    @State private var genres: [String] = []
    @State private var genre: String?
    @State private var sort: SeriesSort = .popular

    private struct Key: Hashable { let genre: String?; let sort: SeriesSort; let load: Int }

    var body: some View {
        Group {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if let series {
                List {
                    if !genres.isEmpty {
                        Picker("Genre", selection: $genre) {
                            Text("Any genre").tag(String?.none)
                            ForEach(genres, id: \.self) { Text(GenreDisplay.name($0)).tag(String?.some($0)) }
                        }
                    }
                    Picker("Sort", selection: $sort) {
                        ForEach(SeriesSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    ForEach(series) { row in
                        NavigationLink(value: Route.series(row.key)) { SeriesRowLabel(series: row) }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: catalog.loadKey) { genres = await catalog.browseFacets().genres }
        .task(id: Key(genre: genre, sort: sort, load: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            series = await catalog.seriesBrowse(genre: genre, network: nil, decade: nil, sort: sort)
        }
    }
}

private struct SeriesScreen_tvOS: View {
    let key: String
    @Environment(CatalogStore.self) private var catalog
    @Environment(FollowedSeries.self) private var follows
    @State private var page: SeriesPage??

    var body: some View {
        Group {
            switch page {
            case .none: ProgressView()
            case .some(.none): ContentUnavailableView("Series not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)):
                List {
                    Section {
                        HStack(alignment: .top, spacing: Spacing.s6) {
                            if let face = page.series.face { FaceFigure(face: face, width: 200) }
                            VStack(alignment: .leading, spacing: Spacing.s2) {
                                Text(page.series.name).font(TypeRamp.pageTitle)
                                Text(verbatim: page.series.metaLine)
                                    .font(TypeRamp.caption)
                                    .foregroundStyle(Color.brandTextMuted)
                            }
                        }
                        .focusable(false)
                        let on = follows.isFollowing(key)
                        Button { follows.toggle(key) } label: {
                            Label(on ? "Following" : "Follow", systemImage: on ? "checkmark" : "plus")
                        }
                    }
                    ForEach(page.seasons) { season in
                        Section(season.season ?? "Undated") {
                            ForEach(season.episodes) { episode in
                                NavigationLink(value: Route.episode(episode.id)) {
                                    EpisodeRowLabel(episode: episode)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            page = .some(await catalog.seriesPage(key))
        }
    }
}

// MARK: - A person (withPerson, tvOS-DESIGN §4.11)

private struct PersonScreen_tvOS: View {
    let id: String
    @Environment(CatalogStore.self) private var catalog
    @State private var page: PersonPage??
    @State private var newestFirst = false

    var body: some View {
        Group {
            switch page {
            case .none: ProgressView()
            case .some(.none): ContentUnavailableView("Person not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)):
                List {
                    Section {
                        HStack(alignment: .top, spacing: Spacing.s6) {
                            if let face = page.person.face { FaceFigure(face: face, width: 200) }
                            VStack(alignment: .leading, spacing: Spacing.s2) {
                                Text(page.person.name).font(TypeRamp.pageTitle)
                                Text(verbatim: PersonScreen_tvOS.facts(page))
                                    .font(TypeRamp.caption)
                                    .foregroundStyle(Color.brandTextMuted)
                            }
                        }
                        .focusable(false)
                        if page.episodes.count > 1 {
                            Button {
                                newestFirst.toggle()
                            } label: {
                                Label(newestFirst ? "Newest first" : "Oldest first", systemImage: "arrow.up.arrow.down")
                            }
                        }
                    }
                    ForEach(page.groups(newestFirst: newestFirst)) { group in
                        Section(group.seriesName) {
                            ForEach(group.episodes) { item in
                                NavigationLink(value: Route.episode(item.id)) {
                                    EpisodeRowLabel(episode: item.episode, note: item.rolesLine)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            page = .some(await catalog.personPage(id))
        }
    }

    static func facts(_ page: PersonPage) -> String {
        [page.person.years, PersonRowLabel.count(page.episodes.count)].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Episode detail

private struct EpisodeScreen_tvOS: View {
    let id: String
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @State private var detail: EpisodeDetail??
    @State private var transcriptOpen = false
    @FocusState private var playFocused: Bool

    var body: some View {
        Group {
            switch detail {
            case .none: ProgressView()
            case .some(.none): ContentUnavailableView("Episode not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(detail)): content(detail)
            }
        }
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            detail = .some(await catalog.episodeDetail(id))
        }
    }

    private func content(_ detail: EpisodeDetail) -> some View {
        let episode = detail.episode
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                HStack(alignment: .top, spacing: Spacing.s8) {
                    if let face = detail.starFace { FaceFigure(face: face, width: 240) }
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        Text(episode.seriesName)
                            .font(TypeRamp.bodyStrong)
                            .foregroundStyle(Color.brandTextMuted)
                        Text(episode.displayTitle)
                            .font(TypeRamp.pageTitle)
                            .foregroundStyle(Color.brandText)
                        Text(verbatim: [AirDate.display(episode.airDate), episode.network, detail.sponsor,
                                        episode.durationText].compactMap { $0 }.joined(separator: " · "))
                            .font(TypeRamp.tabular)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: Spacing.s6) {
                    // tvOS auto-focuses Play on Detail (an inversion of the
                    // iOS rule, which never steals focus).
                    Button {
                        // The episode already loaded opens where it is (§4.4).
                        if player.item?.episode.id == episode.id {
                            store.isPlayerPresented = true
                        } else {
                            play(episode.id, presentPlayer: true)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .tint(Color.brandPrimary)
                    .focused($playFocused)
                    .disabled(detail.recordings.isEmpty)
                    QueueToggleButton(episodeID: episode.id)
                    NavigationLink(value: Route.series(episode.seriesKey)) {
                        Label("Series", systemImage: "square.stack")
                    }
                    if episode.transcriptURL != nil {
                        Button {
                            transcriptOpen = true
                        } label: {
                            Label(Transcript.label, systemImage: "text.quote")
                        }
                    }
                }
                .focusSection()

                if !catalog.isOnline { OfflineNotice() }

                // withPerson (§4.11): every credited name is a focus stop that pushes the person.
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    ForEach(CreditGroups.grouped(detail.credits), id: \.role) { group in
                        let faces = group.credits.contains { $0.art != nil }
                        VStack(alignment: .leading, spacing: Spacing.s2) {
                            Text(group.role).font(TypeRamp.bodyStrong)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 520), alignment: .leading)],
                                      alignment: .leading, spacing: Spacing.s3) {
                                ForEach(group.credits) { credit in
                                    NavigationLink(value: Route.person(credit.personID)) {
                                        HStack(spacing: Spacing.s3) {
                                            // Decision 069: portraits on cast lines; the slot stays so names align.
                                            if faces { CreditFace(art: credit.art, size: 64) }
                                            Text(credit.line).font(TypeRamp.body)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .disabled(credit.personID.isEmpty)
                                }
                            }
                        }
                    }
                }
                .focusSection()
                ForEach(detail.owedCredits, id: \.personID) { credit in
                    if let line = credit.art?.credit {
                        Text(verbatim: "\(credit.name): \(line)")
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                }

                if detail.recordings.count > 1 {
                    VersionsSection_tvOS(detail: detail)
                }

                if let rightsLine = detail.rightsLine {
                    Text(rightsLine)
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultFocus($playFocused, true)
        .fullScreenCover(isPresented: $transcriptOpen) {
            if let url = episode.transcriptURL {
                TranscriptScreen_tvOS(title: episode.displayTitle, url: url)
            }
        }
    }
}

/// R5 on the TV (§4.4): every copy of the broadcast, the default first; each
/// plays that copy in Now Playing.
private struct VersionsSection_tvOS: View {
    let detail: EpisodeDetail
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store

    var body: some View {
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text("Versions").font(TypeRamp.sectionHeader)
            ForEach(detail.recordings.sorted { $0.rank < $1.rank }) { recording in
                Button {
                    play(detail.episode.id, recording: recording, presentPlayer: true)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text(verbatim: recording.archiveID)
                            .font(TypeRamp.body)
                        Text(verbatim: Self.facts(recording))
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityHint("Plays this copy")
            }
        }
        .focusSection()
    }

    private static func facts(_ recording: Recording) -> String {
        var parts = recording.notes
        if let length = recording.lengthSeconds { parts.append(EpisodeRow.clock(length)) }
        if let kbps = recording.kbps { parts.append("\(kbps) kbps") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Search and Library

private struct SearchScreen_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var results = SearchResults()

    var body: some View {
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
            if let aired = results.aired, !aired.episodes.isEmpty {
                Section(aired.title) {
                    ForEach(aired.episodes) { episode in
                        NavigationLink(value: Route.episode(episode.id)) {
                            EpisodeRowLabel(episode: episode, showSeries: true)
                        }
                    }
                }
            }
            if !results.episodes.isEmpty {
                Section("Episodes") {
                    ForEach(results.episodes) { episode in
                        NavigationLink(value: Route.episode(episode.id)) {
                            EpisodeRowLabel(episode: episode, showSeries: true)
                        }
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
                    }
                }
            }
        }
        .overlay {
            if !query.isEmpty, results.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, prompt: "Titles, series, people")
        .onChange(of: store.pendingSearch, initial: true) { _, q in
            guard let q else { return }
            query = q
            store.pendingSearch = nil
        }
        .task(id: query) {
            let q = query
            guard (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
            results = q.isEmpty ? SearchResults() : await catalog.search(q)
        }
    }
}

private struct LibraryScreen_tvOS: View {
    /// The TV keeps no media files (tvOS-DESIGN: downloads are n/a), and says so.
    static let noDownloads: LocalizedStringKey = "Downloads are on iPhone, iPad, and Mac."
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
    @Environment(ListeningQueue.self) private var queue
    @Environment(FollowedSeries.self) private var follows
    @State private var inProgress: [EpisodeRow]?
    @State private var queued: [EpisodeRow] = []
    @State private var following: [SeriesRow] = []

    private struct Key: Equatable { let ids: [String]; let queue: [String]; let load: Int }

    var body: some View {
        Group {
            if let inProgress {
                if inProgress.isEmpty && queued.isEmpty && following.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing played yet", systemImage: "books.vertical")
                    } description: {
                        Text(Self.noDownloads)
                    } actions: {
                        AccountRow().fixedSize()
                    }
                } else {
                    List {
                        if !queued.isEmpty {
                            Section("Queue") {
                                ForEach(queued) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        EpisodeRowLabel(episode: episode, showSeries: true)
                                    }
                                    .contextMenu { QueueRowMenu(episodeID: episode.id) }
                                }
                            }
                        }
                        if !following.isEmpty {
                            Section("Following") {
                                ForEach(following) { row in
                                    NavigationLink(value: Route.series(row.key)) { SeriesRowLabel(series: row) }
                                }
                            }
                        }
                        ForEach(inProgress) { episode in
                            NavigationLink(value: Route.episode(episode.id)) {
                                EpisodeRowLabel(episode: episode, showSeries: true)
                            }
                            .contextMenu {
                                Button(role: .destructive) { history.remove(episode.id) } label: {
                                    Label("Remove from History", systemImage: "trash")
                                }
                            }
                        }
                        Section {
                            AccountRow()
                            SiteLinkRows()
                        } footer: {
                            Text(Self.noDownloads)
                                .foregroundStyle(Color.brandTextMuted)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: Key(ids: history.inProgressIDs, queue: queue.items, load: catalog.loadKey)) {
            queued = await catalog.episodes(queue.items)
            inProgress = await catalog.episodes(history.inProgressIDs)
        }
        .task(id: follows.followedKeys.joined(separator: "\n") + "#\(catalog.loadKey)") {
            following = await catalog.series(follows.followedKeys)
        }
    }
}

// MARK: - Now Playing

/// Full-screen and typographic: series, episode, date, network, the people.
/// Speed, sleep, and skip are on this screen (R18). Menu dismisses (Back).
private struct NowPlaying_tvOS: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(CatalogStore.self) private var catalog
    @State private var transcriptOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Spacer(minLength: 0)
            if let item = player.item {
                HStack(alignment: .bottom, spacing: Spacing.s8) {
                    NowPlayingArt(episode: item.episode, face: item.face, line: item.episode.network, side: 400)
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        Text(item.episode.seriesName)
                            .font(TypeRamp.sectionHeader)
                            .foregroundStyle(Color.brandTextMuted)
                        Text(item.episode.displayTitle)
                            .font(TypeRamp.pageTitle)
                            .foregroundStyle(Color.brandText)
                        Text(verbatim: [AirDate.display(item.episode.airDate), item.episode.network]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(TypeRamp.tabular)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Spacing.s3) {
                ProgressView(value: min(player.elapsed, player.duration ?? 1), total: max(player.duration ?? 1, 1))
                    .tint(Color.brandPrimary)
                    .accessibilityLabel("Position")
                TimeLabels()
            }
            HStack(spacing: Spacing.s8) {
                TransportControls(large: true)
                Spacer()
                SpeedMenu()
                SleepButton()
                LevelToggle()
                ListenTogetherButton()
                NextStoryButton()
                if player.item?.episode.transcriptURL != nil {
                    Button {
                        transcriptOpen = true
                    } label: {
                        Label(Transcript.label, systemImage: "text.quote")
                    }
                }
            }
            .focusSection()
            FollowingHostNotice()
            if let message = player.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.semanticError)
            } else if !catalog.isOnline {
                OfflineNotice()
            }
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 60)
        .background(Color.brandBackground.ignoresSafeArea())
        .onPlayPauseCommand { player.togglePlayPause() }
        .fullScreenCover(isPresented: $transcriptOpen) {
            if let item = player.item, let url = item.episode.transcriptURL {
                TranscriptScreen_tvOS(title: item.episode.displayTitle, url: url)
            }
        }
    }
}
#endif
