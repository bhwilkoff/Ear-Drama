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
        // §3.0: no tint on the TV. A tint colors a focused button's label too, so any light one
        // is white on the system's white plate.
        .tint(nil)
        .fullScreenCover(isPresented: $store.isPlayerPresented) {
            NowPlaying_tvOS().tint(nil)
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
                // At the trailing edge: the tab bar's pill holds the leading one.
                Spacer(minLength: 300)
                Button {
                    store.isPlayerPresented = true
                } label: {
                    Label {
                        Text(verbatim: item.episode.displayTitle).lineLimit(1)
                    } icon: {
                        Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                    }
                    .font(TypeRamp.bodyStrong)
                }
                .accessibilityLabel("Now playing: \(item.episode.displayTitle), \(item.episode.seriesName)")
                .accessibilityHint("Opens the player")
            }
            .padding(.bottom, Spacing.s3)
            .focusSection()
        }
    }
}

private struct RouteDestinations_tvOS: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case let .series(key): SeriesScreen_tvOS(key: key).id(route)
            case let .episode(id): EpisodeScreen_tvOS(id: id).id(route)
            case let .person(id): PersonScreen_tvOS(id: id).id(route)
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

// MARK: - Home (was Listen)

private struct ListenScreen_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
    @Environment(FollowedSeries.self) private var follows
    @Environment(AppStore.self) private var app
    @Environment(AudioPlayer.self) private var player
    @State private var day: HomeDay?
    @State private var top: [SeriesRow] = []
    @State private var loaded = false
    @State private var continuing: [EpisodeRow] = []
    @State private var following: [SeriesRow] = []
    @State private var finished = FinishedStore.shared
    @State private var voices: [PersonRow] = []
    @FocusState private var heroFocused: Bool

    private static let topCount = 12
    private static let voiceCount = 12

    var body: some View {
        Group {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if loaded {
                if continuing.isEmpty && following.isEmpty && day == nil && top.isEmpty && voices.isEmpty && finished.plays.isEmpty {
                    EmptyState("Nothing to list yet", systemImage: "radio")
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: TV.rowGap) {
                            hero
                            firstRow
                            if !following.isEmpty {
                                TVShelf(title: "Following") {
                                    ForEach(following) { TileLink(value: Route.series($0.key), series: $0) }
                                }
                            }
                            if let day, let peak = day.years.peak {
                                DayStrip_tvOS(model: day, year: peak)
                            }
                            if !top.isEmpty {
                                TVShelf(title: "Most downloaded") {
                                    Button("All \(top.count.formatted()) shows") { app.selectResettingPrevious(.browse) }
                                } content: {
                                    ForEach(top.prefix(Self.topCount)) { TileLink(value: Route.series($0.key), series: $0) }
                                }
                            }
                            if !voices.isEmpty {
                                TVShelf(title: "Most heard voices") {
                                    Button("All") { app.openBrowseVoices() }
                                } content: {
                                    ForEach(voices) { VoiceLink(row: $0) }
                                }
                            }
                            if !finished.plays.isEmpty {
                                TVShelf(title: "New ear dramas") {
                                    Button("All") { app.openBrowseDramas() }
                                } content: {
                                    ForEach(finished.plays.prefix(6)) { FinishedTile(play: $0) }
                                }
                            }
                        }
                        .padding(.bottom, 60)
                    }
                    .defaultFocus($heroFocused, true)
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
            voices = await catalog.voices(limit: Self.voiceCount)
            loaded = true
        }
        .task(id: history.inProgressIDs.joined(separator: "\n") + "#\(catalog.loadKey)") {
            continuing = await catalog.episodes(Array(history.inProgressIDs.prefix(10)))
        }
        .task(id: follows.followedKeys.joined(separator: "\n") + "#\(catalog.loadKey)") {
            following = await catalog.series(follows.followedKeys)
        }
    }

    /// §4.1: the episode in progress, else this day's busiest year, its first show with a picture.
    private func lead(_ day: HomeDay?) -> HomeDay.Show? {
        guard let day, let peak = day.years.peak else { return nil }
        let shows = day.night(peak).shows
        return shows.first { $0.series.windowArt != nil } ?? shows.first
    }

    @ViewBuilder private var hero: some View {
        if let episode = continuing.first {
            TVHero(kicker: "Continue listening", title: episode.seriesName, subtitle: episode.displayTitle,
                   facts: [AirDate.medium(episode.airDate), episode.durationText], genre: episode.seriesGenre,
                   art: episode.seriesWindowArt, progress: history.progress(for: episode.id), clearance: TV.rootClearance) {
                heroActions(episode, verb: "Resume")
            }
        } else if let show = lead(day), let day, let peak = day.years.peak {
            TVHero(kicker: "This day in radio", title: show.series.name, subtitle: show.episode.displayTitle,
                   facts: [day.nightHeading(peak), show.episode.durationText], genre: show.series.genre,
                   art: show.series.windowArt, clearance: TV.rootClearance) {
                heroActions(show.episode, verb: "Play")
            }
        }
    }

    @ViewBuilder private func heroActions(_ episode: EpisodeRow, verb: String) -> some View {
        Button {
            if player.item?.episode.id == episode.id {
                app.isPlayerPresented = true
            } else {
                PlayEpisodeAction(catalog: catalog, player: player, store: app)(episode.id, presentPlayer: true)
            }
        } label: {
            Label(verb, systemImage: "play.fill")
        }
        .focused($heroFocused)
        NavigationLink(value: Route.episode(episode.id)) { Text("Details") }
    }

    /// §4.1: the rest of Continue listening and that night's shows are one row of wide cards, each
    /// group under its own heading, so a single episode in progress never stands beside an empty screen.
    @ViewBuilder private var firstRow: some View {
        let rest = Array(continuing.dropFirst())
        let peak = day?.years.peak
        let night = peak.flatMap { day?.night($0) }
        let leadID = continuing.isEmpty ? lead(day)?.id : nil
        let others = night?.shows.filter { $0.id != leadID } ?? []
        // §3.0: pictures lead.
        let shows = others.filter { $0.series.windowArt != nil } + others.filter { $0.series.windowArt == nil }
        if !rest.isEmpty || !shows.isEmpty {
            TVShelf {
                if !rest.isEmpty {
                    group("Continue listening", fact: nil) {
                        ForEach(rest) { TVEpisodeLink(episode: $0) }
                    }
                }
                if !shows.isEmpty, let day, let peak, let night {
                    group(day.nightHeading(peak),
                          fact: night.singles > 0 ? countText(night.singles, "single recording", "single recordings") : nil) {
                        ForEach(shows) { show in
                            NavigationLink(value: Route.episode(show.episode.id)) {
                                TVWideCard(art: show.series.windowArt, name: show.series.name, genre: show.series.genre,
                                           title: show.series.name, sub: show.episode.displayTitle, foot: show.episode.durationText)
                            }
                            .buttonStyle(.card)
                            .contextMenu { QueueMenuItem(episodeID: show.episode.id) }
                        }
                    }
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, fact: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
                Text(verbatim: title).font(TypeRamp.sectionHeader).foregroundStyle(Color.brandText).lineLimit(1).fixedSize()
                if let fact {
                    Text(verbatim: fact).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).lineLimit(1).fixedSize()
                }
            }
            .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: TV.cardGap) { content() }
        }
    }
}

/// The day across the years (R11c): the strip and its legend, under the shows it counts.
private struct DayStrip_tvOS: View {
    let model: HomeDay
    let year: Int

    var body: some View {
        let day = model.years
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHead(title: "This day in radio") {
                Text(verbatim: "\(countText(day.count, "surviving broadcast", "surviving broadcasts")) \u{00B7} \(countText(day.years.count, "year", "years"))").foregroundStyle(Color.brandTextMuted)
            }
            YearStrip(day: day, selected: year, height: DayBoard.stripHeight)
            HStack(spacing: TV.cardGap) {
                ForEach(day.genres.filter { !$0.isEmpty }, id: \.self) { genre in
                    HStack(spacing: Spacing.s1) {
                        Rectangle().fill(Color.genre(genre) ?? Color.brandTextMuted).frame(width: 20, height: 20)
                        Text(verbatim: GenreDisplay.name(genre)).lineLimit(1).fixedSize()
                    }
                }
                Spacer(minLength: 0)
            }
            .font(TypeRamp.caption)
            .foregroundStyle(Color.brandTextMuted)
            .accessibilityHidden(true)
        }
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
    @State private var fieldOpen = false
    @Environment(AppStore.self) private var store

    private struct Key: Hashable { let genre: String?; let decade: Int?; let sort: SeriesSort; let load: Int }

    var body: some View {
        Group {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if let series {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: Spacing.s4) {
                            Picker("Browse", selection: $scope) {
                                ForEach(BrowseScope.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                            if scope == .dramas {
                                FinishedBrowse()
                            } else if scope == .voices {
                                VoicesBrowse()
                            } else {
                                results(series, proxy: proxy)
                            }
                        }
                        .padding(.top, TV.rootClearance)
                        .padding(.bottom, 60)
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
        .onChange(of: store.pendingBrowseVoices, initial: true) { _, asked in
            guard asked else { return }
            scope = .voices
            store.pendingBrowseVoices = false
        }
    }

    private var filters: some View {
        HStack(spacing: Spacing.s6) {
            if !genres.isEmpty {
                Picker("Genre", selection: $genre) {
                    Text("Any genre").tag(String?.none)
                    ForEach(genres, id: \.self) { Text(GenreDisplay.name($0)).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
            }
            Picker("Sort", selection: $sort) {
                ForEach(SeriesSort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
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
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            Text(verbatim: singles ? countText(lesser.count, "single recording", "single recordings")
                 : countText(shows.count, "show", "shows"))
                .font(TypeRamp.bodyStrong)
            Spacer()
            filters
            if !field.genres.isEmpty {
                Button { fieldOpen.toggle() } label: {
                    Label("By decade", systemImage: fieldOpen ? "chevron.up" : "chevron.down")
                }
            }
            if singles || !lesser.isEmpty {
                Button(singles ? countText(shows.count, "show", "shows")
                       : countText(lesser.count, "single recording", "single recordings")) { singles.toggle() }
            }
        }
        .focusSection()
        if fieldOpen, !field.genres.isEmpty {
            GenreField(field: field, genre: genre, decade: decade) { g, d in genre = g; decade = d }
                .focusSection()
            if field.none > 0 {
                Text(verbatim: "\(field.none.formatted()) with no genre")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
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
    @Environment(ListeningHistory.self) private var history
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @State private var page: SeriesPage??
    @FocusState private var playFocused: Bool

    var body: some View {
        Group {
            switch page {
            case .none: ProgressView()
            case .some(.none): EmptyState("Series not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)): content(page)
            }
        }
        .task(id: PageIdentity.taskID(key, load: catalog.loadKey)) {
            page = nil
            guard catalog.state == .ready else { return }
            page = .some(await catalog.seriesPage(key))
        }
    }

    private func content(_ page: SeriesPage) -> some View {
        let series = page.series
        let on = follows.isFollowing(series.key)
        let episodes = page.seasons.flatMap(\.episodes)
        let ids = Set(episodes.map(\.id))
        let resume = history.inProgressIDs.first(where: ids.contains)
        let kicker = ([series.genre.map(GenreDisplay.name)].compactMap { $0 } + series.networks.prefix(2))
            .joined(separator: " \u{00B7} ")
        return ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: TV.rowGap) {
                TVHero(kicker: kicker, title: series.name, facts: SeriesHead.facts(series), genre: series.genre,
                       art: series.windowArt, years: series.yearCounts) {
                    // §4.3: Play is the first focus stop; only the focused control is bright.
                    if let first = resume ?? episodes.first?.id {
                        Button {
                            if player.item?.episode.id == first {
                                store.isPlayerPresented = true
                            } else {
                                PlayEpisodeAction(catalog: catalog, player: player, store: store)(first, presentPlayer: true)
                            }
                        } label: {
                            Label(resume == nil ? "Play" : "Resume", systemImage: "play.fill")
                        }
                        .focused($playFocused)
                    }
                    Button { follows.toggle(series.key) } label: {
                        Label(on ? "Following" : "Follow", systemImage: on ? "checkmark" : "plus")
                    }
                    if let genre = series.genre {
                        Button(GenreDisplay.name(genre)) { store.openBrowse(genre: genre) }
                            .accessibilityLabel("Browse \(GenreDisplay.name(genre))")
                    }
                }
                ForEach(page.seasons) { season in
                    TVShelf(title: season.season ?? "Undated", lazy: true) {
                        Text(verbatim: countText(season.episodes.count, "episode", "episodes")).foregroundStyle(Color.brandTextMuted)
                    } content: {
                        ForEach(season.episodes) { episode in
                            NavigationLink(value: Route.episode(episode.id)) { TVDateCard(episode: episode) }
                                .buttonStyle(.card)
                                .contextMenu { QueueMenuItem(episodeID: episode.id) }
                        }
                    }
                }
            }
            .padding(.bottom, 60)
        }
        .defaultFocus($playFocused, true)
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
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: TV.rowGap) {
                        TVHero(title: page.person.name,
                               facts: [page.person.years, PersonRowLabel.count(page.episodes.count),
                                       groups.count > 1 ? countText(groups.count, "show", "shows") : nil],
                               genre: nil, art: page.person.art, round: true,
                               years: PersonShows.yearCounts(page.episodes)) {
                            if page.episodes.count > 1 {
                                Button {
                                    newestFirst.toggle()
                                } label: {
                                    Label(newestFirst ? "Newest first" : "Oldest first", systemImage: "arrow.up.arrow.down")
                                }
                            }
                        }
                        if groups.count > 1 {
                            TVShelf(title: "Shows") {
                                ForEach(groups.sorted { $0.episodes.count > $1.episodes.count }) { group in
                                    let tile = PersonShows.tile(shows[group.seriesKey], key: group.seriesKey,
                                                                name: group.seriesName, episodes: group.episodes)
                                    TileLink(value: Route.series(group.seriesKey), series: tile,
                                             facts: [tile.yearSpan ?? "Undated", countText(group.episodes.count, "episode", "episodes")])
                                }
                            }
                        }
                        ForEach(groups) { group in
                            TVShelf(title: group.seriesName, lazy: true) {
                                Text(verbatim: countText(group.episodes.count, "episode", "episodes")).foregroundStyle(Color.brandTextMuted)
                            } content: {
                                ForEach(group.episodes) { item in
                                    NavigationLink(value: Route.episode(item.id)) {
                                        TVDateCard(episode: item.episode, note: item.rolesLine)
                                    }
                                    .buttonStyle(.card)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .task(id: PageIdentity.taskID(id, load: catalog.loadKey)) {
            page = nil
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
        .task(id: PageIdentity.taskID(id, load: catalog.loadKey)) {
            detail = nil
            show = nil
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
            VStack(alignment: .leading, spacing: TV.rowGap) {
                TVHero(kicker: episode.seriesName, title: episode.displayTitle,
                       facts: Grammar.episodeFacts(date: episode.airDate.map { AirDate.display($0) }, network: episode.network,
                                                   sponsor: detail.sponsor, length: nil, season: episode.season,
                                                   title: episode.title, number: episode.number),
                       genre: genre, art: lead, pictureName: episode.seriesName) {
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
                        Label(episode.durationText.map { "Play \u{00B7} \($0)" } ?? "Play", systemImage: "play.fill")
                    }
                    .focused($playFocused)
                    .disabled(detail.recordings.isEmpty)
                    NavigationLink(value: Route.series(episode.seriesKey)) { Text("Show") }
                    QueueToggleButton(episodeID: episode.id)
                    if episode.transcriptURL != nil {
                        Button {
                            transcriptOpen = true
                        } label: {
                            Label("Transcript", systemImage: "text.quote")
                        }
                        .accessibilityLabel(Transcript.label)
                    }
                }

                if !catalog.isOnline { OfflineNotice() }

                if !onAir.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        SectionHead(title: "On the air") { EmptyView() }
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
                            Label("Cast and credits \u{00B7} \(detail.credits.count.formatted())",
                                  systemImage: creditsOpen ? "chevron.up" : "chevron.down")
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
            .padding(.bottom, 60)
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

/// R5 on the TV (§4.4): every copy of the broadcast as a card, the default first; each plays that
/// copy in Now Playing.
private struct VersionsSection_tvOS: View {
    let detail: EpisodeDetail
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store

    var body: some View {
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        TVShelf(title: "Recordings", lazy: true) {
            ForEach(Array(detail.recordings.sorted { $0.rank < $1.rank }.enumerated()), id: \.element.id) { index, recording in
                Button {
                    play(detail.episode.id, recording: recording, presentPlayer: true)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text(verbatim: RecordingLabel.title(recording, position: index + 1))
                            .font(TypeRamp.bodyStrong)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Text(verbatim: RecordingLabel.facts(recording, isBest: index == 0))
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                            .lineLimit(2)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(Spacing.s4)
                    .frame(width: TV.dateCard.width, height: 180, alignment: .topLeading)
                    .background(Color.brandSurface)
                }
                .buttonStyle(.card)
                .accessibilityHint("Plays this copy")
            }
        }
    }
}

// MARK: - Search and Library

private struct SearchScreen_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var results = SearchResults()

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: TV.rowGap) {
                if !results.series.isEmpty {
                    TVShelf(title: "Shows") {
                        ForEach(results.series) { TileLink(value: Route.series($0.key), series: $0) }
                    }
                }
                if !results.people.isEmpty {
                    TVShelf(title: "People") {
                        ForEach(results.people) { row in
                            NavigationLink(value: Route.person(row.id)) {
                                TVFace(art: row.person.art, name: row.person.name, line: PersonRowLabel.count(row.episodes))
                            }
                            .buttonStyle(TVBareButtonStyle())
                        }
                    }
                }
                if let aired = results.aired, !aired.episodes.isEmpty {
                    TVShelf(title: aired.title, lazy: true) {
                        ForEach(aired.episodes) { TVEpisodeLink(episode: $0) }
                    }
                }
                if !results.episodes.isEmpty {
                    TVShelf(title: "Episodes", lazy: true) {
                        ForEach(results.episodes) { TVEpisodeLink(episode: $0) }
                    }
                }
                if !results.transcript.isEmpty {
                    TVShelf(title: Transcript.label, lazy: true) {
                        let words = Transcript.searchWords(query)
                        ForEach(results.transcript) { TranscriptHitCard_tvOS(episode: $0, words: words) }
                    }
                }
            }
            .padding(.vertical, Spacing.s6)
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

/// §4.5: the episode's card with the line where the words are said, verbatim.
private struct TranscriptHitCard_tvOS: View {
    let episode: EpisodeRow
    let words: [String]
    @State private var quote: String?

    var body: some View {
        TVEpisodeLink(episode: episode, quote: quote)
            .task(id: episode.id) {
                guard let url = episode.transcriptURL else { return }
                quote = await Transcript.snippet(from: url, words: words)
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
    @FocusState private var emptyFocused: Bool

    private struct Key: Equatable { let ids: [String]; let queue: [String]; let load: Int }

    var body: some View {
        Group {
            if let inProgress {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: TV.rowGap) {
                        // The empty state heads the page and takes the focus; the account and the
                        // site pages stay under it (tvOS-DESIGN §7.3a).
                        if inProgress.isEmpty && queued.isEmpty && following.isEmpty {
                            EmptyState("Nothing played yet", systemImage: "books.vertical",
                                       action: .init(title: "Browse") { app.selectResettingPrevious(.browse) },
                                       focus: $emptyFocused)
                                .frame(height: 360)
                                .frame(maxWidth: .infinity)
                        }
                        section("Continue", caption: "Episodes you stop partway through wait here.", empty: inProgress.isEmpty) {
                            ForEach(inProgress) { episode in
                                TVEpisodeLink(episode: episode) {
                                    Button(role: .destructive) { history.remove(episode.id) } label: {
                                        Label("Remove from History", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        section("Queue", caption: "Episodes you add play in this order, after the one that is playing.", empty: queued.isEmpty) {
                            ForEach(queued) { episode in
                                TVEpisodeLink(episode: episode) { QueueRowMenu(episodeID: episode.id) }
                            }
                        }
                        if following.isEmpty {
                            section("Following", caption: "Series you follow appear here.", empty: true) { EmptyView() }
                        } else {
                            TVShelf(title: "Following") {
                                ForEach(following) { TileLink(value: Route.series($0.key), series: $0) }
                            }
                        }
                        SharedEarDramasSection_tvOS()
                        VStack(alignment: .leading, spacing: Spacing.s4) {
                            AccountRow()
                                .frame(maxWidth: 640)
                                .focusSection()
                            HStack(spacing: 64) { SiteLinkRows() }
                                .font(TypeRamp.caption)
                                .foregroundStyle(Color.brandTextMuted)
                        }
                    }
                    .padding(.top, TV.rootClearance)
                    .padding(.bottom, 60)
                }
                .defaultFocus($emptyFocused, true)
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

    /// §4.6: an empty section keeps its header and its one caption.
    @ViewBuilder private func section<Content: View>(_ title: String, caption: String, empty: Bool,
                                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        if empty {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                SectionHead(title: title) { EmptyView() }
                SectionCaption(caption)
            }
        } else {
            TVShelf(title: title, lazy: true, content: content)
        }
    }
}

// MARK: - Now Playing

/// Full-screen (§5.2a): the hero, the progress line, one row of controls, the people below it.
/// Speed, sleep, and skip are on this screen (R18). Menu dismisses (Back).
private struct NowPlaying_tvOS: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(CatalogStore.self) private var catalog
    @Environment(AppStore.self) private var store
    @State private var transcriptOpen = false
    @FocusState private var pauseFocused: Bool

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                controlsPage
                    .containerRelativeFrame(.vertical)
                if let item = player.item {
                    NowPlayingPeople(episode: item.episode) { route in
                        store.isPlayerPresented = false
                        store.push(route)
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .background(Color.brandBackground.ignoresSafeArea())
        .defaultFocus($pauseFocused, true)
        .onPlayPauseCommand { player.togglePlayPause() }
        .fullScreenCover(isPresented: $transcriptOpen) {
            if let item = player.item, let url = item.episode.transcriptURL {
                TranscriptScreen_tvOS(title: item.episode.displayTitle, url: url)
            }
        }
    }

    /// The first screen: the hero and the controls. The people sit below it.
    private var controlsPage: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            if let item = player.item {
                TVHero(kicker: item.episode.seriesName, title: item.episode.displayTitle,
                       facts: [AirDate.display(item.episode.airDate), item.episode.network],
                       genre: item.episode.seriesGenre, art: NowPlayingArt.art(item.episode, item.face),
                       pictureName: item.episode.seriesName) { EmptyView() }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                ProgressView(value: min(player.elapsed, player.duration ?? 1), total: max(player.duration ?? 1, 1))
                    .tint(Color.brandPrimary)
                    .accessibilityLabel("Position")
                TimeLabels()
            }
            HStack(spacing: Spacing.s4) {
                transport("gobackward.15", label: "Back 15 seconds") { player.skip(by: -AudioPlayer.Skip.back) }
                    .disabled(player.isFollowing)
                transport(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Play") {
                    player.togglePlayPause()
                }
                .focused($pauseFocused)
                transport("goforward.30", label: "Forward 30 seconds") { player.skip(by: AudioPlayer.Skip.forward) }
                    .disabled(player.isFollowing)
                Spacer(minLength: Spacing.s6)
                HStack(spacing: Spacing.s3) {
                    SpeedMenu()
                    SleepButton()
                    LevelToggle()
                    if let item = player.item {
                        PlayerQueueButton(episodeID: item.episode.id)
                    }
                    ListenTogetherButton()
                    NextStoryButton()
                    if player.item?.episode.transcriptURL != nil {
                        Button {
                            transcriptOpen = true
                        } label: {
                            Label("Transcript", systemImage: "text.quote")
                        }
                        .accessibilityLabel(Transcript.label)
                    }
                    RoutePicker_tvOS()
                        .frame(width: 88, height: 88)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .lineLimit(1)
            .focusSection()
            FollowingHostNotice()
            if let message = player.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.semanticError)
            } else if !catalog.isOnline {
                OfflineNotice()
            }
            Spacer(minLength: 0)
        }
        .disabled(player.item == nil)
    }

    /// One size for all three (§5.2a): the circle is the system's, the glyph sits in one frame.
    private func transport(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 88, height: 88)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }
}

/// The system's audio output picker (AVKit): the Apple TV's own speakers, a
/// HomePod, or another AirPlay speaker, never a custom device list.
private struct RoutePicker_tvOS: UIViewRepresentable {
    /// Focus puts a white plate behind the glyph, which `tintColor` alone leaves white on white.
    final class InkedPicker: AVRoutePickerView {
        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            let ink: UIColor = context.nextFocusedView?.isDescendant(of: self) == true ? .black : .white
            tintColor = ink
            activeTintColor = ink
        }
    }

    func makeUIView(context: Context) -> InkedPicker {
        let view = InkedPicker()
        view.routePickerButtonStyle = .plain
        view.prioritizesVideoDevices = false
        // §5.2a: the system style draws its glyph black on this page.
        view.tintColor = .white
        view.activeTintColor = .white
        return view
    }

    func updateUIView(_ uiView: InkedPicker, context: Context) {}
}
#endif
