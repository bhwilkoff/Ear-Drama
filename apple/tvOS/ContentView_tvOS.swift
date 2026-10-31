#if os(tvOS)
import AVKit
import SwiftUI

// The ten-foot app (tvos-platform-patterns, ten-foot-detail-design): a
// sidebar of the top-level verbs, one NavigationStack per tab reset when the
// sidebar leaves it, focus doing the work (only the focused card is bright),
// cards with .card style (never .plain), and Now Playing as a full-screen
// typographic view: in radio the people are the picture.

struct ContentView_tvOS: View {
    @Environment(AppStore.self) private var store
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history

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
        // The Top Shelf's Continue items follow the history from any tab.
        .task(id: history.inProgressIDs.joined(separator: "\n") + "#\(catalog.loadKey)") {
            guard catalog.state == .ready else { return }
            let episodes = await catalog.episodes(Array(history.inProgressIDs.prefix(TopShelfSnapshot.limit)))
            var pageFaces: [String: Face] = [:]
            for episode in episodes {
                if let face = await catalog.episodeDetail(episode.id)?.starFace { pageFaces[episode.id] = face }
            }
            TopShelfSnapshot.publish(episodes, pageFaces: pageFaces)
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
            case let .drama(pid): FinishedDramaScreen(id: pid)
            case .invitation: EmptyView()
            }
        }
        .navigationDestination(for: SharedPlayRoute.self) { SharedPlayScreen_tvOS(route: $0) }
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
                Text(verbatim: AirDate.stored(episode.airDate))
                    .font(TypeRamp.tabular)
                    .foregroundStyle(Color.brandTextMuted)
                Text(episode.displayTitle)
                    .font(TypeRamp.bodyStrong)
                    .foregroundStyle(Color.brandText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                HStack(spacing: Spacing.s3) {
                    PictureWindow(art: episode.seriesWindowArt, name: episode.seriesName, genre: episode.seriesGenre, side: 64)
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

/// A followed series as the grammar's tile (R11b): focus scales the whole tile through the card style.
private struct SeriesCard_tvOS: View {
    let series: SeriesRow

    var body: some View {
        NavigationLink(value: Route.series(series.key)) {
            ShowTile(series: series)
        }
        .buttonStyle(.card)
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
                HStack(alignment: .top, spacing: 40) {
                    ForEach(series) { SeriesCard_tvOS(series: $0) }
                }
                .sharesNameHeight()
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
    @Environment(AppStore.self) private var app
    @State private var day: HomeDay?
    @State private var top: [SeriesRow] = []
    @State private var loaded = false
    @State private var continuing: [EpisodeRow] = []
    @State private var following: [SeriesRow] = []
    @State private var allNight = false
    @State private var finished = FinishedStore.shared

    private static let nightFirst = 6
    private static let topCount = 12

    var body: some View {
        Group {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if loaded {
                if continuing.isEmpty && following.isEmpty && day == nil && top.isEmpty && finished.plays.isEmpty {
                    EmptyState("Nothing to list yet", systemImage: "radio")
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 80) {
                            if !continuing.isEmpty {
                                ShelfRow_tvOS(title: "Continue listening", episodes: continuing)
                            }
                            if !following.isEmpty {
                                SeriesShelf_tvOS(title: "Following", series: following)
                            }
                            if let day, let peak = day.years.peak {
                                DayBoard(model: day, selected: .constant(peak), interactive: false)
                                    .padding(.horizontal, 60)
                                night(day, peak)
                            }
                            if !top.isEmpty {
                                VStack(alignment: .leading, spacing: Spacing.s4) {
                                    SectionHead(title: "Most downloaded") {
                                        Button("All \(top.count.formatted()) shows") { app.selectResettingPrevious(.browse) }
                                    }
                                    .padding(.horizontal, 60)
                                    TileShelf_tvOS(items: Array(top.prefix(Self.topCount))) { row in
                                        TileLink(value: Route.series(row.key), series: row)
                                    }
                                }
                                .focusSection()
                            }
                            if !finished.plays.isEmpty {
                                VStack(alignment: .leading, spacing: Spacing.s4) {
                                    SectionHead(title: "New ear dramas") {
                                        Button("All") { app.openBrowseDramas() }
                                    }
                                    .padding(.horizontal, 60)
                                    TileShelf_tvOS(items: Array(finished.plays.prefix(6))) { play in
                                        FinishedTile(play: play)
                                    }
                                }
                                .focusSection()
                            }
                        }
                        .padding(.vertical, 60)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task { await finished.load() }
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            let loadedDay = await HomeDay.load(catalog)
            top = await catalog.seriesBrowse(genre: nil, network: nil, decade: nil, sort: .popular)
                .filter { ShowLine.isShow($0.episodeCount) }
            day = loadedDay.years.years.isEmpty ? nil : loadedDay
            loaded = true
        }
        .task(id: history.inProgressIDs.joined(separator: "\n") + "#\(catalog.loadKey)") {
            continuing = await catalog.episodes(Array(history.inProgressIDs.prefix(10)))
        }
        .task(id: follows.followedKeys.joined(separator: "\n") + "#\(catalog.loadKey)") {
            following = await catalog.series(follows.followedKeys)
        }
    }

    @ViewBuilder private func night(_ day: HomeDay, _ year: Int) -> some View {
        let night = day.night(year)
        if !night.shows.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                SectionHead(title: day.nightHeading(year)) {
                    if night.singles > 0 { Text(verbatim: countText(night.singles, "single recording", "single recordings")) }
                }
                .padding(.horizontal, 60)
                TileShelf_tvOS(items: allNight ? night.shows : Array(night.shows.prefix(Self.nightFirst))) { show in
                    TileLink(value: Route.episode(show.episode.id), series: show.series, facts: show.facts)
                }
                if night.shows.count > Self.nightFirst {
                    Button(allNight ? "Fewer shows" : "All \(night.shows.count.formatted()) shows that night") {
                        allNight.toggle()
                    }
                    .padding(.horizontal, 60)
                }
            }
            .focusSection()
        }
    }
}

/// A shelf of show tiles in one row, each sharing the shelf's name height.
private struct TileShelf_tvOS<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 40) {
                ForEach(items) { tile($0) }
            }
            .sharesNameHeight()
            .padding(.horizontal, 60)
            .padding(.vertical, Spacing.s6)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Browse (was Series; the TV lists no plays, PLAYS-DESIGN §6)

private struct SeriesBrowseScreen_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var series: [SeriesRow]?
    @State private var fieldBase: [SeriesRow] = []
    @State private var genres: [String] = []
    @State private var genre: String?
    @State private var decade: Int?
    @State private var sort: SeriesSort = .popular
    @State private var singles = false
    @State private var shown = BrowseScreenPage.size
    @State private var scope: BrowseScope = .shows
    @Environment(AppStore.self) private var store

    private struct Key: Hashable { let genre: String?; let decade: Int?; let sort: SeriesSort; let load: Int }

    private var heading: String {
        switch sort {
        case .popular: "Most downloaded first"
        case .name: "A to Z"
        case .episodes: "Most episodes"
        case .firstAired: "Oldest first"
        }
    }

    var body: some View {
        Group {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if let series {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: Spacing.s6) {
                            Picker("Browse", selection: $scope) {
                                ForEach(BrowseScope.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if scope == .dramas {
                                FinishedBrowse()
                            } else {
                                filters
                                results(series, proxy: proxy)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 60)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: catalog.loadKey) { genres = await catalog.browseFacets().genres }
        .task(id: Key(genre: genre, decade: decade, sort: sort, load: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            series = await catalog.seriesBrowse(genre: genre, network: nil, decade: decade, sort: sort)
        }
        .task(id: Key(genre: nil, decade: nil, sort: sort, load: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            fieldBase = await catalog.seriesBrowse(genre: nil, network: nil, decade: nil, sort: sort)
        }
        .onChange(of: Key(genre: genre, decade: decade, sort: sort, load: singles ? 1 : 0)) { shown = BrowseScreenPage.size }
        .onChange(of: store.pendingBrowseGenre, initial: true) { _, g in
            guard let g else { return }
            genre = g; decade = nil; scope = .shows
            store.pendingBrowseGenre = nil
        }
        .onChange(of: store.pendingBrowseDramas, initial: true) { _, asked in
            guard asked else { return }
            scope = .dramas
            store.pendingBrowseDramas = false
        }
    }

    private var filters: some View {
        HStack(spacing: Spacing.s6) {
            if !genres.isEmpty {
                Picker("Genre", selection: $genre) {
                    Text("Any genre").tag(String?.none)
                    ForEach(genres, id: \.self) { Text(GenreDisplay.name($0)).tag(String?.some($0)) }
                }
            }
            Picker("Sort", selection: $sort) {
                ForEach(SeriesSort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if genre != nil || decade != nil {
                Button("Clear") { genre = nil; decade = nil }
            }
        }
    }

    @ViewBuilder private func results(_ all: [SeriesRow], proxy: ScrollViewProxy) -> some View {
        let shows = all.filter { ShowLine.isShow($0.episodeCount) }
        let lesser = all.filter { !ShowLine.isShow($0.episodeCount) }
        let listed = singles ? lesser : shows
        let field = ShowLine.decadeField(fieldBase.filter { ShowLine.isShow($0.episodeCount) }
            .map { (genre: $0.genre, first: $0.firstDate) })
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: singles ? countText(lesser.count, "single recording", "single recordings")
                 : countText(shows.count, "show", "shows"))
                .font(TypeRamp.bodyStrong)
            Spacer()
            if singles || !lesser.isEmpty {
                Button(singles ? countText(shows.count, "show", "shows")
                       : countText(lesser.count, "single recording", "single recordings")) { singles.toggle() }
            }
        }
        if !field.genres.isEmpty {
            GenreField(field: field, genre: genre, decade: decade) { g, d in genre = g; decade = d }
                .focusSection()
        }
        if field.none > 0 {
            Text(verbatim: "\(field.none.formatted()) with no genre")
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
        }
        SectionHead(title: heading) { EmptyView() }
        if listed.isEmpty {
            EmptyState("Nothing matches", systemImage: "line.3.horizontal.decrease.circle",
                       action: .init(title: "Clear Filters") { genre = nil; decade = nil })
        } else if sort == .name {
            // A to Z: a row of letters focus can reach, then each letter's tiles, drawn as they scroll in.
            let letters = Grammar.azLetters(listed.map { $0.sortName ?? $0.name })
            let groups = Dictionary(grouping: listed) { Grammar.azLetter($0.sortName ?? $0.name) }
            LetterRow(letters: letters) { proxy.scrollTo("az-\($0)", anchor: .top) }
            LazyVStack(alignment: .leading, spacing: Spacing.s6) {
                ForEach(letters, id: \.self) { l in
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        Text(verbatim: l).font(TypeRamp.sectionHeader).foregroundStyle(Color.brandText).id("az-\(l)")
                        ShowGrid(items: groups[l] ?? []) { row, width in
                            TileLink(value: Route.series(row.key), series: row, width: width)
                        }
                    }
                }
            }
        } else {
            ShowGrid(items: Array(listed.prefix(shown))) { row, width in
                TileLink(value: Route.series(row.key), series: row, width: width)
            }
            if listed.count > shown {
                Button("Show more") { shown += BrowseScreenPage.size }
            }
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
            case .some(.none): EmptyState("Series not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)):
                List {
                    Section {
                        HeadBoard(kicker: SeriesHead.kicker(page.series), name: page.series.name, genre: page.series.genre,
                                  art: page.series.windowArt, first: page.series.firstDate, last: page.series.lastDate,
                                  years: page.series.yearCounts,
                                  facts: SeriesHead.facts(page.series), genreKey: page.series.genre,
                                  kickerRest: page.series.networks.joined(separator: " \u{00B7} "), showsCredit: true)
                            .listRowBackground(Color.clear)
                        // Follow is the first focus stop; only the focused control is bright.
                        let on = follows.isFollowing(page.series.key)
                        ActionRow {
                            Button { follows.toggle(page.series.key) } label: {
                                Label(on ? "Following" : "Follow", systemImage: on ? "checkmark" : "plus")
                            }
                            .pageAction(primary: true)
                        }
                        .listRowBackground(Color.clear)
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
    @State private var shows: [String: SeriesRow] = [:]
    @State private var newestFirst = false

    var body: some View {
        Group {
            switch page {
            case .none: ProgressView()
            case .some(.none): EmptyState("Person not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)):
                let groups = page.groups(newestFirst: newestFirst)
                let run = PersonShows.span(page.episodes)
                List {
                    Section {
                        HeadBoard(kicker: nil, name: page.person.name, genre: nil, art: page.person.art,
                                  first: run.first, last: run.last, years: PersonShows.yearCounts(page.episodes),
                                  facts: [page.person.years, PersonRowLabel.count(page.episodes.count),
                                          groups.count > 1 ? countText(groups.count, "show", "shows") : nil],
                                  showsCredit: true)
                            .listRowBackground(Color.clear)
                        if groups.count > 1 {
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 40) {
                                    ForEach(groups) { group in
                                        let tile = PersonShows.tile(shows[group.seriesKey], key: group.seriesKey,
                                                                    name: group.seriesName, episodes: group.episodes)
                                        NavigationLink(value: Route.series(group.seriesKey)) {
                                            ShowTile(series: tile,
                                                     facts: [tile.yearSpan ?? "Undated", countText(group.episodes.count, "episode", "episodes")])
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                                .sharesNameHeight()
                                .padding(.vertical, Spacing.s6)
                            }
                            .scrollClipDisabled()
                            .listRowBackground(Color.clear)
                        }
                        if page.episodes.count > 1 {
                            Button {
                                newestFirst.toggle()
                            } label: {
                                Label(newestFirst ? "Newest first" : "Oldest first", systemImage: "arrow.up.arrow.down")
                            }
                        }
                    }
                    ForEach(groups) { group in
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
            let loaded = await catalog.personPage(id)
            page = .some(loaded)
            if let loaded {
                let keys = Array(Set(loaded.episodes.map(\.episode.seriesKey)))
                shows = Dictionary(uniqueKeysWithValues: await catalog.series(keys).map { ($0.key, $0) })
            }
        }
    }
}

// MARK: - Episode detail

private struct EpisodeScreen_tvOS: View {
    let id: String
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @State private var detail: EpisodeDetail??
    @State private var show: SeriesRow?
    @State private var creditsOpen = false
    @State private var transcriptOpen = false
    @FocusState private var playFocused: Bool

    var body: some View {
        Group {
            switch detail {
            case .none: ProgressView()
            case .some(.none): EmptyState("Episode not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(detail)): content(detail)
            }
        }
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            let loaded = await catalog.episodeDetail(id)
            if let loaded { show = await catalog.series([loaded.episode.seriesKey]).first }
            detail = .some(loaded)
        }
    }

    private func content(_ detail: EpisodeDetail) -> some View {
        let episode = detail.episode
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        let lead = Grammar.leadPicture(series: show, credits: detail.credits, star: detail.star)
        let genre = show?.genre ?? episode.seriesGenre
        let onAir = Grammar.onAirOf(detail.credits)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                HeadBoard(kicker: show?.genre.map(GenreDisplay.name) ?? "Show", name: episode.seriesName, genre: genre, art: lead,
                          first: show?.firstDate, last: show?.lastDate, years: show?.yearCounts,
                          facts: show.map { [$0.yearSpan ?? "Undated", $0.episodeCount == 1 ? "1 episode" : "\($0.episodeCount.formatted()) episodes"] } ?? ["Undated"],
                          link: .series(episode.seriesKey), showsCredit: true)

                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(episode.displayTitle)
                        .font(TypeRamp.pageTitle)
                        .foregroundStyle(Color.brandText)
                    EventLine(facts: Grammar.episodeFacts(date: episode.airDate.map { AirDate.display($0) }, network: episode.network, sponsor: detail.sponsor,
                                                          length: episode.durationText, season: episode.season,
                                                          title: episode.title, number: episode.number))
                }
                .accessibilityElement(children: .combine)

                ActionRow {
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
                    .pageAction(primary: true)
                    .focused($playFocused)
                    .disabled(detail.recordings.isEmpty)
                    QueueToggleButton(episodeID: episode.id)
                    if episode.transcriptURL != nil {
                        Button {
                            transcriptOpen = true
                        } label: {
                            Label(Transcript.label, systemImage: "text.quote")
                        }
                    }
                }

                if !catalog.isOnline { OfflineNotice() }

                if !onAir.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        Text("On the air").font(TypeRamp.sectionHeader)
                        OnAirFaces(credits: onAir, genre: genre)
                        PictureCredit(arts: onAir.map(\.art), slot: 72)
                    }
                    .focusSection()
                }

                // withPerson (§4.11): every credited name is a focus stop that pushes the person.
                if !detail.credits.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s6) {
                        Button {
                            creditsOpen.toggle()
                        } label: {
                            HStack {
                                Text("Cast and credits").font(TypeRamp.bodyStrong)
                                Spacer(minLength: 0)
                                Text(verbatim: detail.credits.count.formatted())
                                    .font(TypeRamp.caption)
                                    .foregroundStyle(Color.brandTextMuted)
                                Image(systemName: creditsOpen ? "chevron.up" : "chevron.down")
                            }
                        }
                        if creditsOpen {
                            ForEach(CreditGroups.grouped(detail.credits), id: \.role) { group in
                                VStack(alignment: .leading, spacing: Spacing.s2) {
                                    Text(group.role).font(TypeRamp.bodyStrong)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 520), alignment: .leading)],
                                              alignment: .leading, spacing: Spacing.s3) {
                                        ForEach(group.credits) { credit in
                                            NavigationLink(value: Route.person(credit.personID)) {
                                                Text(credit.line).font(TypeRamp.body)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .disabled(credit.personID.isEmpty)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .focusSection()
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
            Text("Recordings").font(TypeRamp.sectionHeader)
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
            if !query.isEmpty, results.isEmpty { EmptyState("No matches for “\(query)”", systemImage: "magnifyingglass") }
        }
        .searchable(text: $query, prompt: "Titles, people, spoken words")
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
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
    @Environment(ListeningQueue.self) private var queue
    @Environment(FollowedSeries.self) private var follows
    @Environment(AppStore.self) private var app
    @State private var inProgress: [EpisodeRow]?
    @State private var queued: [EpisodeRow] = []
    @State private var following: [SeriesRow] = []

    private struct Key: Equatable { let ids: [String]; let queue: [String]; let load: Int }

    var body: some View {
        Group {
            if let inProgress {
                // The empty state heads the list and takes the focus; the
                // account and the site pages stay under it (tvOS-DESIGN §7.3a).
                List {
                    if inProgress.isEmpty && queued.isEmpty && following.isEmpty {
                        EmptyState("Nothing played yet", systemImage: "books.vertical",
                                   action: .init(title: "Browse") { app.selectResettingPrevious(.browse) })
                    }
                    Section("Continue") {
                        if inProgress.isEmpty {
                            SectionCaption("Episodes you stop partway through wait here.")
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
                    }
                    Section("Queue") {
                        if queued.isEmpty {
                            SectionCaption("Episodes you add play in this order, after the one that is playing.")
                        }
                        ForEach(queued) { episode in
                            NavigationLink(value: Route.episode(episode.id)) {
                                EpisodeRowLabel(episode: episode, showSeries: true)
                            }
                            .contextMenu { QueueRowMenu(episodeID: episode.id) }
                        }
                    }
                    if following.isEmpty {
                        Section("Following") { SectionCaption("Series you follow appear here.") }
                    } else {
                        SeriesShelf_tvOS(title: "Following", series: following)
                            .listRowBackground(Color.clear)
                    }
                    SharedEarDramasSection_tvOS()
                    Section {
                        AccountRow()
                        SiteLinkRows()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: Key(ids: history.inProgressIDs, queue: queue.items, load: catalog.loadKey)) {
            guard !LaunchDoors.current.emptyLibrary else { inProgress = []; return }
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
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        NowPlayingArt(episode: item.episode, face: item.face, side: 400)
                        // Shown larger than a page's head, so a credited portrait carries its credit (Decision 069).
                        if let art = NowPlayingArt.art(item.episode, item.face), let credit = art.credit {
                            ArtCredit(credit: credit, evidence: art.evidence)
                        }
                    }
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        Text(item.episode.displayTitle)
                            .font(TypeRamp.pageTitle)
                            .foregroundStyle(Color.brandText)
                        EventLine(facts: [item.episode.seriesName, AirDate.display(item.episode.airDate), item.episode.network])
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
                RoutePicker_tvOS()
                    .frame(width: 80, height: 80)
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

/// The system's audio output picker (AVKit): the Apple TV's own speakers, a
/// HomePod, or another AirPlay speaker, never a custom device list.
private struct RoutePicker_tvOS: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.routePickerButtonStyle = .system
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
