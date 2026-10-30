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
            case let .drama(pid): FinishedDramaScreen(id: pid)
            case let .invitation(token): InviteScreen(token: token)
            }
        }
        .navigationDestination(for: DownloadsRoute.self) { _ in DownloadsScreen() }
        .navigationDestination(for: PlayRoute.self) { route in
            switch route {
            case let .script(id): PlayScriptScreen(id: id)
            case let .production(id): ProductionScreen(id: id)
            case let .recording(production, part, line): PartScreen(productionID: production, part: part, replacing: line)
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
    @Environment(FollowedSeries.self) private var follows
    @State private var day: HomeDay?
    @State private var top: [SeriesRow] = []
    @State private var loaded = false
    @State private var continuing: [EpisodeRow] = []
    @State private var following: [SeriesRow] = []
    @State private var year: Int?
    @State private var allNight = false
    @State private var finished = FinishedStore.shared

    private static let nightFirst = 6
    private static let topCount = 12
    private static let dramaCount = 6

    private var selectedYear: Int? { year ?? day?.years.peak }

    var body: some View {
        List {
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if loaded {
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
                if !following.isEmpty {
                    Section("Following") {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: Spacing.s3) {
                                ForEach(following) { row in
                                    NavigationLink(value: Route.series(row.key)) { ShowTile(series: row) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .sharesNameHeight()
                            .padding(.horizontal, Spacing.s4)
                            .padding(.vertical, Spacing.s2)
                        }
                        .scrollIndicators(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
                if let day, let selected = selectedYear {
                    Section {
                        DayBoard(model: day, selected: Binding(get: { selected }, set: { year = $0; allNight = false }))
                            .gridRow()
                    }
                    nightSection(day, selected)
                }
                if !top.isEmpty {
                    Section {
                        ShowGrid(items: Array(top.prefix(Self.topCount))) { row, width in
                            TileLink(value: Route.series(row.key), series: row, width: width)
                        }
                        .gridRow()
                    } header: {
                        SectionHead(title: "Most downloaded") {
                            Button("All \(top.count.formatted()) shows") { store.selectResettingPrevious(.browse) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                if !finished.plays.isEmpty {
                    Section {
                        ShowGrid(items: Array(finished.plays.prefix(Self.dramaCount))) { play, width in
                            FinishedTile(play: play, width: width)
                        }
                        .gridRow()
                    } header: {
                        SectionHead(title: "New ear dramas") {
                            Button("All") { store.openBrowseDramas() }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                if continuing.isEmpty && following.isEmpty && day == nil && top.isEmpty && finished.plays.isEmpty {
                    EmptyState("Nothing to list yet", systemImage: "radio")
                }
            } else {
                SkeletonRows()
            }
        }
        .task { await finished.load() }
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
            let loadedDay = await HomeDay.load(catalog)
            let shows = await catalog.seriesBrowse(genre: nil, network: nil, decade: nil, sort: .popular)
                .filter { ShowLine.isShow($0.episodeCount) }
            day = loadedDay.years.years.isEmpty ? nil : loadedDay
            top = shows
            year = nil
            loaded = true
        }
        .task(id: history.inProgressIDs.joined(separator: "\n") + "#\(catalog.loadKey)") {
            continuing = await catalog.episodes(Array(history.inProgressIDs.prefix(10)))
        }
        .task(id: follows.followedKeys.joined(separator: "\n") + "#\(catalog.loadKey)") {
            following = await catalog.series(follows.followedKeys)
        }
    }

    @ViewBuilder private func nightSection(_ day: HomeDay, _ selected: Int) -> some View {
        let night = day.night(selected)
        if !night.shows.isEmpty {
            let shown = allNight ? night.shows : Array(night.shows.prefix(Self.nightFirst))
            Section {
                ShowGrid(items: shown) { show, width in
                    TileLink(value: Route.episode(show.episode.id), series: show.series, width: width, facts: show.facts)
                }
                .gridRow()
                if night.shows.count > Self.nightFirst {
                    Button(allNight ? "Fewer shows" : "All \(night.shows.count.formatted()) shows that night") {
                        allNight.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(TypeRamp.caption)
                }
            } header: {
                SectionHead(title: day.nightHeading(selected)) {
                    if night.singles > 0 { Text(verbatim: countText(night.singles, "single recording", "single recordings")) }
                }
            }
        }
    }
}

private extension View {
    func gridRow() -> some View {
        listRowInsets(EdgeInsets(top: Spacing.s2, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
    @Environment(AppStore.self) private var store
    @State private var series: [SeriesRow]?
    /// The same list with the genre and decade filters off: the field counts over it (R11c).
    @State private var fieldBase: [SeriesRow] = []
    @State private var facets: (genres: [String], networks: [String], decades: [Int]) = ([], [], [])
    @State private var kind: BrowseKind?
    @State private var hasScript = false
    /// Series key -> the castable script ids its episodes link (contract §3.1).
    @State private var scripted: [String: [String]] = [:]
    @State private var genre: String?
    @State private var network: String?
    @State private var decade: Int?
    @State private var sort: SeriesSort = .popular
    @State private var singles = false
    @State private var shown = BrowseScreenPage.size
    @State private var columnWidth: CGFloat = 0
    @State private var scope: BrowseScope = .shows

    private struct Filter: Hashable {
        let genre: String?, network: String?, decade: Int?, sort: SeriesSort, generation: Int
    }

    private struct PageKey: Hashable {
        let genre: String?, network: String?, decade: Int?, sort: SeriesSort, kind: BrowseKind?, hasScript: Bool, singles: Bool
    }

    private enum Item: Identifiable {
        case show(SeriesRow), play(PlayScript)
        var id: String {
            switch self {
            case let .show(row): "s|" + row.key
            case let .play(script): "p|" + script.id
            }
        }
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
    private var heading: String {
        switch sort {
        case .popular: "Most downloaded first"
        case .name: "A to Z"
        case .episodes: "Most episodes"
        case .firstAired: "Oldest first"
        }
    }

    /// One List for every state, as Home and Library: swapping scroll views
    /// under the bar lost the large title (seen on an iPhone 12, 2026-10-24).
    var body: some View {
        ScrollViewReader { proxy in
            browseList(proxy)
        }
    }

    private func browseList(_ proxy: ScrollViewProxy) -> some View {
        List {
            if scope == .dramas {
                FinishedBrowse()
                    .listRowInsets(EdgeInsets(top: Spacing.s2, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if let series {
                results(series, proxy: proxy)
                    .listRowInsets(EdgeInsets(top: Spacing.s2, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                SkeletonRows()
            }
        }
        .overlay {
            if scope == .shows, catalog.state != .unavailable, let series, shownSeries(series).isEmpty, shownPlays.isEmpty {
                EmptyState("Nothing matches", systemImage: "line.3.horizontal.decrease.circle",
                           action: .init(title: "Clear Filters") { clear() })
            }
        }
        #if os(iOS)
        .modifier(SectionIndex(visible: sort == .name))
        .overlay(alignment: .trailing) {
            if #unavailable(iOS 26), sort == .name, let series {
                let letters = azLetters(itemsOf(series))
                if letters.count > 1 {
                    LetterRail(letters: letters) { proxy.scrollTo("az-\($0)", anchor: .top) }
                        .padding(.trailing, 2)
                }
            }
        }
        #endif
        .modifier(TopBar {
            VStack(spacing: 0) {
                Picker("Browse", selection: $scope) {
                    ForEach(BrowseScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s2)
                .accessibilityIdentifier("browse-scope")
                if scope == .shows { chips }
            }
        })
        .navigationTitle("Browse")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task(id: catalog.loadKey) {
            facets = await catalog.browseFacets()
            scripted = await catalog.scriptedSeries()
        }
        .task { await plays.load() }
        .onChange(of: store.pendingBrowseGenre, initial: true) { _, g in
            guard let g else { return }
            clear(); genre = g; scope = .shows
            store.pendingBrowseGenre = nil
        }
        .onChange(of: store.pendingBrowseDramas, initial: true) { _, asked in
            guard asked else { return }
            scope = .dramas
            store.pendingBrowseDramas = false
        }
        .task(id: Filter(genre: genre, network: network, decade: decade, sort: sort, generation: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            series = await catalog.seriesBrowse(genre: genre, network: network, decade: decade, sort: sort)
        }
        .task(id: Filter(genre: nil, network: network, decade: nil, sort: sort, generation: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            fieldBase = await catalog.seriesBrowse(genre: nil, network: network, decade: nil, sort: sort)
        }
        .onChange(of: PageKey(genre: genre, network: network, decade: decade, sort: sort, kind: kind,
                              hasScript: hasScript, singles: singles)) { shown = BrowseScreenPage.size }
    }

    private func itemsOf(_ all: [SeriesRow]) -> [Item] {
        let listed = shownSeries(all)
        let shows = listed.filter { ShowLine.isShow($0.episodeCount) }
        let lesser = listed.filter { !ShowLine.isShow($0.episodeCount) }
        return (singles ? lesser : shows).map(Item.show) + (singles ? [] : shownPlays.map(Item.play))
    }

    private func azKey(_ item: Item) -> String {
        switch item {
        case let .show(row): row.sortName ?? row.name
        case let .play(script): script.title
        }
    }

    private func azLetters(_ items: [Item]) -> [String] { Grammar.azLetters(items.map(azKey)) }

    /// The shown items by A to Z letter, each group in the catalog's order; a play joins its letter by title.
    private func azGroups(_ items: [Item]) -> [(letter: String, items: [Item])] {
        var by: [String: [Item]] = [:]
        for item in items { by[Grammar.azLetter(azKey(item)), default: []].append(item) }
        return azLetters(items).map { l in
            var group = by[l] ?? []
            if group.contains(where: { if case .play = $0 { true } else { false } }) {
                group.sort { azKey($0).localizedCaseInsensitiveCompare(azKey($1)) == .orderedAscending }
            }
            return (l, group)
        }
    }

    @ViewBuilder private func tileView(_ item: Item, width: CGFloat) -> some View {
        switch item {
        case let .show(row):
            TileLink(value: Route.series(row.key), series: row, width: width)
        case let .play(script):
            TileLink(value: PlayRoute.script(script.id), series: Self.tileRow(script), width: width,
                     facts: [script.authorLine, countText(script.castParts.filter { $0.id.isSpeaking }.count, "part", "parts")]
                         .filter { !$0.isEmpty },
                     castScript: script)
        }
    }

    /// A to Z: one List section per letter, each tile row its own lazy row, so the system's index
    /// (or the rail) can scroll to a letter's first row.
    @ViewBuilder private func azSections(_ items: [Item]) -> some View {
        let columns = BrowseLayout.columns(width: columnWidth, tileMin: ShowTile.defaultWidth)
        let tileWidth = BrowseLayout.tileWidth(width: columnWidth, columns: columns)
        ForEach(azGroups(items), id: \.letter) { group in
            let rows = stride(from: 0, to: group.items.count, by: columns).map { Array(group.items[$0..<min($0 + columns, group.items.count)]) }
            Section {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack(alignment: .top, spacing: BrowseLayout.gap) {
                        ForEach(row) { tileView($0, width: tileWidth) }
                    }
                    .frame(width: columnWidth, alignment: .leading)
                    .sharesNameHeight()
                    .id(i == 0 ? "az-\(group.letter)" : "az-\(group.letter)-\(i)")
                }
            } header: {
                Text(verbatim: group.letter)
                    .font(TypeRamp.sectionHeader)
                    .foregroundStyle(Color.brandText)
                    .accessibilityAddTraits(.isHeader)
            }
            .sectionIndexLabelIfAvailable(group.letter)
        }
    }

    @ViewBuilder private func results(_ all: [SeriesRow], proxy: ScrollViewProxy) -> some View {
        let listed = shownSeries(all)
        let shows = listed.filter { ShowLine.isShow($0.episodeCount) }
        let lesser = listed.filter { !ShowLine.isShow($0.episodeCount) }
        let items = itemsOf(all)
        let field = ShowLine.decadeField(shownSeries(fieldBase).filter { ShowLine.isShow($0.episodeCount) }
            .map { (genre: $0.genre, first: $0.firstDate) })
        let plan = BrowseLayout.plan(width: columnWidth, decades: field.decades.count, tileMin: ShowTile.defaultWidth)
        VStack(alignment: .leading, spacing: Spacing.s4) {
            // The column's width is read from a view that holds no content and every part below is
            // sized from it, so nothing drawn can make the body wider than the column.
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
            if columnWidth > 0 {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                        Text(verbatim: singles ? countText(lesser.count, "single recording", "single recordings")
                             : countText(shows.count, "show", "shows"))
                            .font(TypeRamp.bodyStrong)
                            .foregroundStyle(Color.brandText)
                        Spacer(minLength: 0)
                        if singles || !lesser.isEmpty {
                            Button(singles ? countText(shows.count, "show", "shows")
                                   : countText(lesser.count, "single recording", "single recordings")) { singles.toggle() }
                                .buttonStyle(.borderless)
                                .font(TypeRamp.caption)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if sort == .name && !items.isEmpty {
                        fieldColumn(field)
                        #if os(macOS)
                        LetterRow(letters: azLetters(items)) { proxy.scrollTo("az-\($0)", anchor: .top) }
                        #endif
                    } else if plan.sideBySide {
                        HStack(alignment: .top, spacing: BrowseLayout.sideGap) {
                            fieldColumn(field).frame(width: plan.fieldWidth, alignment: .topLeading)
                            grid(items, width: plan.gridWidth)
                        }
                    } else {
                        fieldColumn(field)
                        grid(items, width: plan.gridWidth)
                    }
                }
                .frame(width: columnWidth, alignment: .topLeading)
            }
        }
        if sort == .name, columnWidth > 0, !items.isEmpty { azSections(items) }
    }

    @ViewBuilder private func fieldColumn(_ field: ShowLine.DecadeField) -> some View {
        if !field.genres.isEmpty || field.none > 0 {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                if !field.genres.isEmpty {
                    GenreField(field: field, genre: genre, decade: decade) { g, d in genre = g; decade = d }
                }
                if field.none > 0 {
                    Text(verbatim: "\(field.none.formatted()) with no genre")
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                }
            }
        }
    }

    private func grid(_ items: [Item], width gridWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHead(title: heading) { EmptyView() }
            ShowGrid(items: Array(items.prefix(shown)), fixedWidth: gridWidth) { item, width in
                tileView(item, width: width)
            }
            if items.count > shown {
                Button("Show more") { shown += BrowseScreenPage.size }
                    .buttonStyle(.borderless)
                    .font(TypeRamp.caption)
            }
        }
    }

    /// A play on the show tile: no picture and no run (plays carry none); it stands on the drama
    /// board, whose name is never said, and its cast fingerprint is its mark.
    private static func tileRow(_ script: PlayScript) -> SeriesRow {
        SeriesRow(key: script.id, name: script.title, genre: PlayScript.boardGenre, firstDate: nil, lastDate: nil, networks: [], episodeCount: 0)
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
                Button { hasScript.toggle() } label: { chipLabel("Has a script", on: hasScript) }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityAddTraits(hasScript ? .isSelected : [])
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
            chipLabel(title, on: on)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func chipLabel(_ title: String, on: Bool) -> some View {
        Text(verbatim: title)
            .font(TypeRamp.caption)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .foregroundStyle(on ? Color.brandOnSecondary : Color.brandText)
            .background(on ? Color.brandSecondary : Color.brandSurface, in: Capsule())
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

#if os(iOS)
/// The system's section index on iOS 26 and later (iPhone and iPad), shown while Browse sorts A to Z;
/// before 26 the rail takes its place.
private struct SectionIndex: ViewModifier {
    let visible: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.listSectionIndexVisibility(visible ? .visible : .hidden)
        } else {
            content
        }
    }
}
#endif

private extension View {
    @ViewBuilder func sectionIndexLabelIfAvailable(_ letter: String) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) { sectionIndexLabel(Text(verbatim: letter)) } else { self }
        #else
        self
        #endif
    }
}

// MARK: - Series page

/// The web's Follow / Following toggle (iOS-DESIGN §4.3). Its state is the
/// store the account sync carries; the screen plays the selection haptic.
struct FollowButton: View {
    let key: String
    @Environment(FollowedSeries.self) private var follows

    var body: some View {
        let on = follows.isFollowing(key)
        Button { follows.toggle(key) } label: {
            Label(on ? "Following" : "Follow", systemImage: on ? "checkmark" : "plus")
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct SeriesScreen: View {
    let key: String
    @Environment(CatalogStore.self) private var catalog
    @Environment(FollowedSeries.self) private var follows
    @State private var page: SeriesPage??

    var body: some View {
        Group {
            switch page {
            case .none:
                List { SkeletonRows(count: 10) }
            case .some(.none):
                EmptyState("Series not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)):
                List {
                    Section {
                        HeadBoard(kicker: SeriesHead.kicker(page.series), name: page.series.name, genre: page.series.genre,
                                  art: page.series.windowArt, first: page.series.firstDate, last: page.series.lastDate,
                                  years: page.series.yearCounts,
                                  facts: SeriesHead.facts(page.series), genreKey: page.series.genre,
                                  kickerRest: page.series.networks.joined(separator: " \u{00B7} "), showsCredit: true)
                            .listRowInsets(EdgeInsets(top: Spacing.s2, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        ActionRow {
                            FollowButton(key: page.series.key).pageAction(primary: true)
                            ShareLink(item: SiteLinks.series(page.series.key), subject: Text(page.series.name)) {
                                ActionLabel(title: "Share", systemImage: "square.and.arrow.up")
                            }
                            .pageAction()
                            .help("Share")
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
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
                .modifier(ReadableColumn())
                .navigationTitle(page.series.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        SeriesDownloadMenu(page: page)
                    }
                }
                .sensoryFeedback(Haptic.selection.feedback, trigger: follows.isFollowing(page.series.key))
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
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
    @State private var show: SeriesRow?

    var body: some View {
        Group {
            switch detail {
            case .none:
                List { SkeletonRows(count: 4) }
            case .some(.none):
                EmptyState("Episode not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(detail)):
                content(detail)
            }
        }
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            let loaded = await catalog.episodeDetail(id)
            if let loaded { show = await catalog.series([loaded.episode.seriesKey]).first }
            detail = .some(loaded)
        }
        .task { await plays.load() }
    }

    private func content(_ detail: EpisodeDetail) -> some View {
        let episode = detail.episode
        let isCurrent = player.item?.episode.id == episode.id
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        let lead = Grammar.leadPicture(series: show, credits: detail.credits, star: detail.star)
        let genre = show?.genre ?? episode.seriesGenre
        let onAir = Grammar.onAirOf(detail.credits)
        let downloadState = downloads.record(for: episode.id)?.state
        let rowInsets = EdgeInsets(top: 0, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4)
        return List {
            Section {
                HeadBoard(kicker: show?.genre.map(GenreDisplay.name) ?? "Show", name: episode.seriesName, genre: genre, art: lead,
                          first: show?.firstDate, last: show?.lastDate, years: show?.yearCounts,
                          facts: show.map { [$0.yearSpan ?? "Undated", $0.episodeCount == 1 ? "1 episode" : "\($0.episodeCount.formatted()) episodes"] } ?? ["Undated"],
                          link: .series(episode.seriesKey), showsCredit: true)
                    .listRowInsets(EdgeInsets(top: Spacing.s2, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(episode.displayTitle)
                        .font(TypeRamp.pageTitle)
                        .foregroundStyle(Color.brandText)
                        .accessibilityAddTraits(.isHeader)
                    EventLine(facts: Grammar.episodeFacts(date: episode.airDate.map { AirDate.display($0) }, network: episode.network, sponsor: detail.sponsor,
                                                          length: episode.durationText, season: episode.season,
                                                          title: episode.title, number: episode.number))
                }
                .listRowInsets(rowInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                ActionRow {
                    Button {
                        if isCurrent { player.togglePlayPause() } else { play(episode.id) }
                    } label: {
                        Label(isCurrent && player.isPlaying ? "Pause" : "Play",
                              systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .pageAction(primary: true)
                    .disabled(detail.recordings.isEmpty)
                    QueueToggleButton(episodeID: episode.id)
                    if downloadState == nil { DownloadControl(detail: detail) }
                    ShareLink(item: SiteLinks.episode(episode.id), subject: Text(episode.displayTitle)) {
                        ActionLabel(title: "Share", systemImage: "square.and.arrow.up")
                    }
                    .pageAction()
                    .help("Share")
                }
                .listRowInsets(rowInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                // Decision 068: an episode linked to a castable script this bundle holds.
                if let id = detail.script, let script = plays.script(id) {
                    StartEarDramaButton(script: script)
                        .pageAction()
                        .listRowInsets(rowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if downloadState != nil { DownloadControl(detail: detail) }
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

            if !onAir.isEmpty {
                Section {
                    OnAirFaces(credits: onAir, genre: genre)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    PictureCredit(arts: onAir.map(\.art), slot: 72)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("On the air")
                }
            }

            if !detail.credits.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(CreditGroups.grouped(detail.credits), id: \.role) { group in
                            Text(group.role)
                                .font(TypeRamp.caption)
                                .foregroundStyle(Color.brandTextMuted)
                            ForEach(group.credits) { credit in
                                // withPerson (§4.13): a credited name pushes the person's page.
                                NavigationLink(value: Route.person(credit.personID)) {
                                    Text(credit.line).font(TypeRamp.body)
                                }
                                .disabled(credit.personID.isEmpty)
                            }
                        }
                    } label: {
                        HStack {
                            Text("Cast and credits").font(TypeRamp.bodyStrong)
                            Spacer(minLength: 0)
                            Text(verbatim: detail.credits.count.formatted())
                                .font(TypeRamp.caption)
                                .foregroundStyle(Color.brandTextMuted)
                        }
                    }
                }
            }

            if detail.recordings.count > 1 {
                Section("Recordings") {
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
        .modifier(ReadableColumn())
        .navigationTitle(episode.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $transcriptOpen) {
            if let url = episode.transcriptURL { TranscriptSheet_iOS(url: url) }
        }
        #endif
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
                EmptyState("Person not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)):
                List {
                    if let face = page.person.face {
                        Section {
                            FaceHero(face: face, genre: nil, showsName: false, facts: Self.facts(page))
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Spacing.s2, trailing: 0))
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        Section {
                            Text(verbatim: Self.facts(page))
                                .font(TypeRamp.caption)
                                .foregroundStyle(Color.brandTextMuted)
                        }
                    }
                    ForEach(page.groups(newestFirst: newestFirst)) { group in
                        Section {
                            ForEach(group.episodes) { item in
                                NavigationLink(value: Route.episode(item.id)) {
                                    EpisodeRowLabel(episode: item.episode, showSeries: true, note: item.rolesLine)
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
                EmptyState("Search titles, people, and spoken words", systemImage: "magnifyingglass")
            } else if let results, searchedFor == query {
                let matchingPlays = Self.plays(plays.scripts, matching: query)
                if results.isEmpty && matchingPlays.isEmpty {
                    EmptyState("No matches for “\(query)”", systemImage: "magnifyingglass")
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
    @Environment(FollowedSeries.self) private var follows
    @State private var inProgress: [EpisodeRow]?
    @State private var played: [EpisodeRow] = []
    @State private var queued: [EpisodeRow] = []
    @State private var following: [SeriesRow] = []

    var body: some View {
        Group {
            if let inProgress {
                // The empty state heads the list; the account and the site
                // pages stay under it, signed in or out (iOS-DESIGN §7.4).
                let empty = Self.emptied || (inProgress.isEmpty && played.isEmpty && queued.isEmpty && following.isEmpty
                    && downloads.records.isEmpty && plays.store.productions.isEmpty
                    && (!account.isSignedIn || shared.remote.isEmpty))
                List {
                    if catalog.state == .unavailable {
                        CatalogUnavailableView()
                    }
                    if empty {
                        Section {
                            EmptyState("Nothing played yet", systemImage: "books.vertical",
                                       action: .init(title: "Browse") { app.selectedTab = .browse })
                                .listRowBackground(Color.clear)
                        }
                    }
                    Section("Continue") {
                        if inProgress.isEmpty {
                            SectionCaption("Episodes you stop partway through wait here.")
                        }
                        ForEach(inProgress) { episode in
                            NavigationLink(value: Route.episode(episode.id)) {
                                EpisodeRowLabel(episode: episode, showSeries: true)
                            }
                            .swipeActions { removeButton(episode.id) }
                            .contextMenu { removeButton(episode.id) }
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
                    Section("Following") {
                        if following.isEmpty || Self.emptied {
                            SectionCaption("Series you follow appear here.")
                        } else {
                            FollowingShelf(series: following)
                        }
                    }
                    Section("History") {
                        if played.isEmpty {
                            SectionCaption("Episodes you finish appear here, newest first.")
                        }
                        ForEach(played) { episode in
                            NavigationLink(value: Route.episode(episode.id)) {
                                EpisodeRowLabel(episode: episode, showSeries: true)
                            }
                            .swipeActions { removeButton(episode.id) }
                            .contextMenu { removeButton(episode.id) }
                        }
                    }
                    if !Self.emptied {
                        DownloadsSection()
                        EarDramasSection()
                    }
                    Section { AccountRow() }
                    #if os(iOS)
                    Section { SiteLinkRows() }
                    #endif
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
            guard !Self.emptied else { inProgress = []; return }
            let ids = history.inProgressIDs
            let playedIDs = history.entries.filter(\.value.finished)
                .sorted { $0.value.updatedAt > $1.value.updatedAt }.map(\.key).prefix(100)
            queued = await catalog.episodes(queue.items)
            inProgress = await catalog.episodes(ids)
            played = await catalog.episodes(Array(playedIDs))
        }
        .task(id: follows.followedKeys.joined(separator: "\n") + "#\(catalog.loadKey)") {
            following = await catalog.series(follows.followedKeys)
        }
    }

    /// The APP_EMPTY_LIBRARY door (DEBUG only): Library drawn as a new listener's.
    static let emptied = LaunchDoors.current.emptyLibrary

    private func removeButton(_ id: String) -> some View {
        Button(role: .destructive) { history.remove(id) } label: {
            Label("Remove from History", systemImage: "trash")
        }
    }
}
#endif
