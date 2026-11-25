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
            case let .series(key): SeriesScreen(key: key).id(route)
            case let .episode(id): EpisodeScreen(id: id).id(route)
            case let .person(id): PersonScreen(id: id).id(route)
            case .account: AccountScreen()
            case .surprise: SurpriseScreen()
            case .stations: RadioScreen()
            case let .drama(pid): FinishedDramaScreen(id: pid)
            case let .invitation(token): InviteScreen(token: token)
            case let .readRoom(code): ReadRoomScreen(code: code, seat: LaunchDoors.current.readSeat)
            case let .readScreen(code): ReadScreenHost(code: code)
            case let .classPage(id): ClassPageScreen(id: id)
            case let .classCasting(classID, pid): CastingBoardScreen(classID: classID, productionID: pid)
            case .parts: PartsScreen()
            }
        }
        .navigationDestination(for: DownloadsRoute.self) { _ in DownloadsScreen() }
        .navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .upNext: UpNextScreen()
            case .history: HistoryScreen()
            case .about: AboutScreen()
            case let .play(key): PlayProductionsScreen(key: key)
            }
        }
        .navigationDestination(for: PlayRoute.self) { route in
            switch route {
            case let .script(id): PlayScriptScreen(id: id)
            case let .production(id): ProductionScreen(id: id)
            case let .recording(production, part, line): PartScreen(productionID: production, part: part, replacing: line)
            case .addScript: AddScriptScreen()
            case let .parts(id): OwnPartsScreen(id: id).id(route)
            case let .cast(id): EarScreen(id: id).id(route)
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
    @State private var day: HomeDay?
    @State private var shelves = HomeShelves()
    @State private var loaded = false
    @State private var continuing: [EpisodeRow] = []
    @State private var year: Int?
    @State private var allNight = false
    @State private var voices: [PersonRow] = []
    @State private var heroKey: String?

    private static let nightFirst = 6
    private static let voiceCount = 12

    private var selectedYear: Int? { year ?? day?.years.peak }

    /// A show at most once per Home (WEB-DESIGN §4.2r rule 5): each row skips the shows drawn above it, in the
    /// order On the air, Start a show, By length, This day in radio. Continue is exempt.
    private var rows: (start: [HomeChip], length: [HomeChip], above: Set<String>) {
        let hero: Set<String> = heroKey.map { [$0] } ?? []
        let start = HomeShows.chips(shelves.start, above: hero)
        let length = HomeShows.chips(shelves.length, above: start.seen)
        return (start.chips, length.chips, length.seen)
    }

    var body: some View {
        let rows = rows
        PageBody {
            HomeOnAirSection(heroKey: $heroKey)
            if !continuing.isEmpty {
                continuingRows
            }
            MadeHereSection(leading: true)
            if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if loaded {
                HomeChipSection(title: "Start a show", chips: rows.start)
                HomeRecordSection()
                HomeChipSection(title: "By length", chips: rows.length)
                if !voices.isEmpty {
                    PageSection {
                        VoicesShelf(voices: voices)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .pageBleed()
                        PictureCredit(arts: voices.map(\.person.art), slot: 84)
                            .gridRow(.words)
                    } header: {
                        SectionHead(title: "Most heard voices") {
                            Button("All") { store.openBrowseVoices() }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                if let day, let selected = selectedYear {
                    PageSection {
                        DayBoard(model: day, selected: Binding(get: { selected }, set: { year = $0; allNight = false }))
                            .gridRow()
                    }
                    nightSection(day, selected, skipping: rows.above)
                }
                MadeHereSection(leading: false)
            } else {
                SkeletonRows(count: 3)
            }
        }
        .navigationTitle("Ear Drama")
        #if os(iOS)
        // The way to Surprise (iOS-DESIGN §3.1, §4.1): a push, never a section.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.push(Route.surprise) } label: { Label("Surprise", systemImage: "shuffle") }
                    .accessibilityIdentifier("surprise")
            }
        }
        #endif
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            let loadedDay = await HomeDay.load(catalog)
            shelves = await catalog.homeShelves()
            day = loadedDay.years.years.isEmpty ? nil : loadedDay
            voices = await catalog.voices(limit: Self.voiceCount)
            year = nil
            loaded = true
        }
        .task(id: history.inProgressIDs.joined(separator: "\n") + "#\(catalog.loadKey)") {
            continuing = await catalog.episodes(Array(history.inProgressIDs.prefix(10)))
        }
    }

    private var continuingRows: some View {
        let rows = ForEach(continuing) { episode in
            NavigationLink(value: Route.episode(episode.id)) {
                EpisodeRowLabel(episode: episode, showSeries: true)
            }
            .playRowLink()
            .pageRow()
            .playContextMenu(episode.id)
        }
        #if os(macOS)
        return PageRows("Continue") { rows }
        #else
        // V8: Home's Continue takes the heading every other Home section wears (SectionHead), not the List's
        // small gray section title, so the first screen reads as one set of sections (open Duo, 2026-11-20).
        return PageSection { rows } header: { SectionHead(title: "Continue") { EmptyView() } }
        #endif
    }

    @ViewBuilder private func nightSection(_ day: HomeDay, _ selected: Int, skipping above: Set<String>) -> some View {
        let night = day.night(selected)
        let shows = night.shows.filter { !above.contains($0.series.key) }
        if !shows.isEmpty {
            PageSection {
                ShowGrid(items: shows, first: allNight ? nil : Self.nightFirst) { show, width in
                    TileLink(value: Route.episode(show.episode.id), series: show.series, width: width, facts: show.facts)
                }
                .gridRow()
                if shows.count > Self.nightFirst {
                    Button(allNight ? "Fewer shows" : "All \(shows.count.formatted()) shows that night") {
                        allNight.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(TypeRamp.caption)
                    .gridRow(.words)
                }
            } header: {
                SectionHead(title: day.nightHeading(selected)) {
                    if night.singles > 0 { Text(verbatim: countText(night.singles, "single recording", "single recordings")) }
                }
            }
        }
    }
}

extension View {
    /// A row that carries its own Play: no chevron beside it, so the title keeps the width (375 pt).
    func playRowLink() -> some View {
        #if os(tvOS)
        self
        #else
        navigationLinkIndicatorVisibility(.hidden)
        #endif
    }

    /// A clear row in a page's List. `.box` is a filled block (a card, a board, a grid of tiles), `.words` an unfilled
    /// one (text, a row of buttons); at regular width they stand on different edges (iOS-DESIGN §3.6b).
    func gridRow(_ line: RowLine = .box, top: CGFloat = Spacing.s2, bottom: CGFloat = Spacing.s2) -> some View {
        modifier(PageRowInsets(line: line, top: top, bottom: bottom))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Browse (iOS-DESIGN §4.2; was Series)

struct SeriesBrowseScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var store
    @State private var series: [SeriesRow]?
    /// The same list with the genre and decade filters off: the field counts over it (R11c).
    @State private var fieldBase: [SeriesRow] = []
    @State private var facets: (genres: [String], networks: [String], decades: [Int]) = ([], [], [])
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
    @State private var fieldHeight: CGFloat = 0
    @State private var sideRowHeight: CGFloat = 0
    @State private var scope: BrowseScope = .shows
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var heightClass
    #endif

    private struct Filter: Hashable {
        let genre: String?, network: String?, decade: Int?, sort: SeriesSort, generation: Int
    }

    private struct PageKey: Hashable {
        let genre: String?, network: String?, decade: Int?, sort: SeriesSort, hasScript: Bool, singles: Bool
    }

    private struct Item: Identifiable {
        let row: SeriesRow
        var id: String { row.key }
    }

    /// Plays live on Record (Decision 075); "Has a script" keeps the series with a linked episode
    /// whose script this device's bundle holds.
    private func shownSeries(_ all: [SeriesRow]) -> [SeriesRow] {
        guard hasScript else { return all }
        return all.filter { scripted[$0.key]?.contains { plays.has($0) } == true }
    }
    private var isFiltered: Bool { hasScript || genre != nil || network != nil || decade != nil }
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
            // A short window (a phone on its side) has no room for a pinned bar: the controls scroll with the tiles
            // (iOS-DESIGN §4.2).
            if controlsScroll {
                Section {
                    controls
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                #if os(iOS)
                .listSectionSpacing(Spacing.s2)
                #endif
            }
            if scope == .dramas {
                FinishedBrowse()
                    .gridRow()
            } else if scope == .voices {
                VoicesBrowse()
                    .gridRow()
            } else if catalog.state == .unavailable {
                CatalogUnavailableView()
            } else if let series {
                results(series, proxy: proxy)
                    .listRowInsets(EdgeInsets(top: Spacing.s2, leading: 0, bottom: Spacing.s2, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                SkeletonRows()
            }
        }
        .pageMargins()
        .overlay {
            if scope == .shows, catalog.state != .unavailable, let series, shownSeries(series).isEmpty {
                EmptyState("Nothing matches", systemImage: "line.3.horizontal.decrease.circle",
                           action: .init(title: "Clear Filters") { clear() })
            }
        }
        #if os(iOS)
        // The pinned controls already stand off the list; the grouped List's own 35 pt on top of them read as a hole.
        .contentMargins(.top, Spacing.s2, for: .scrollContent)
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
        .modifier(TopBar { if !controlsScroll { controls } })
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
        .onChange(of: store.pendingBrowseVoices, initial: true) { _, asked in
            guard asked else { return }
            scope = .voices
            store.pendingBrowseVoices = false
        }
        .task(id: Filter(genre: genre, network: network, decade: decade, sort: sort, generation: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            series = await catalog.seriesBrowse(genre: genre, network: network, decade: decade, sort: sort)
        }
        .task(id: Filter(genre: nil, network: network, decade: nil, sort: sort, generation: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            fieldBase = await catalog.seriesBrowse(genre: nil, network: network, decade: nil, sort: sort)
        }
        .onChange(of: PageKey(genre: genre, network: network, decade: decade, sort: sort,
                              hasScript: hasScript, singles: singles)) { shown = BrowseScreenPage.size }
    }

    private var controlsScroll: Bool {
        #if os(iOS)
        heightClass == .compact
        #else
        false
        #endif
    }

    /// The scope and the filter chips: pinned under the title, or the list's first row in a short window.
    private var controls: some View {
        VStack(spacing: 0) {
            Picker("Browse", selection: $scope) {
                ForEach(BrowseScope.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // In the list the row already stands on the box edge (§3.6b); the chips start on the words edge.
            .modifier(WidthPadding(compact: controlsScroll ? 0 : Spacing.s4, regular: controlsScroll ? 0 : Spacing.s6))
            .padding(.vertical, Spacing.s2)
            .accessibilityIdentifier("browse-scope")
            if scope == .shows { chips }
        }
    }

    private func itemsOf(_ all: [SeriesRow]) -> [Item] {
        let listed = shownSeries(all)
        let shows = listed.filter { ShowLine.isShow($0.episodeCount) }
        let lesser = listed.filter { !ShowLine.isShow($0.episodeCount) }
        return (singles ? lesser : shows).map(Item.init)
    }

    private func azKey(_ item: Item) -> String { item.row.sortName ?? item.row.name }

    private func azLetters(_ items: [Item]) -> [String] { Grammar.azLetters(items.map(azKey)) }

    /// The shown items by A to Z letter, each group in the catalog's order.
    private func azGroups(_ items: [Item]) -> [(letter: String, items: [Item])] {
        var by: [String: [Item]] = [:]
        for item in items { by[Grammar.azLetter(azKey(item)), default: []].append(item) }
        return azLetters(items).map { ($0, by[$0] ?? []) }
    }

    private func tileView(_ item: Item, width: CGFloat) -> some View {
        TileLink(value: Route.series(item.row.key), series: item.row, width: width)
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
        VStack(alignment: .leading, spacing: 0) {
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
                        // Rows beside the field fill its height; the rest take the whole width, so
                        // no empty column is left under a short field.
                        let visible = Array(items.prefix(shown))
                        let cut = BrowseLayout.rowsBeside(fieldHeight: fieldHeight, rowHeight: sideRowHeight) * plan.columns
                        VStack(alignment: .leading, spacing: Spacing.s3) {
                            HStack(alignment: .top, spacing: BrowseLayout.sideGap) {
                                fieldColumn(field).frame(width: plan.fieldWidth, alignment: .topLeading)
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fieldHeight = $0 }
                                VStack(alignment: .leading, spacing: Spacing.s3) {
                                    SectionHead(title: heading) { EmptyView() }
                                    ShowGrid(items: Array(visible.prefix(cut)), fixedWidth: plan.gridWidth,
                                             onRowHeight: { sideRowHeight = $0 }) { tileView($0, width: $1) }
                                }
                            }
                            if visible.count > cut {
                                ShowGrid(items: Array(visible.dropFirst(cut)), fixedWidth: columnWidth) { tileView($0, width: $1) }
                            }
                            moreButton(items.count)
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
            moreButton(items.count)
        }
    }

    @ViewBuilder private func moreButton(_ count: Int) -> some View {
        if count > shown {
            Button("Show more") { shown += BrowseScreenPage.size }
                .buttonStyle(.borderless)
                .font(TypeRamp.caption)
        }
    }

    private func clear() { hasScript = false; genre = nil; network = nil; decade = nil }

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
            .pageBarPadding()
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
            .background(on ? Color.brandSecondary : Color.brandSurfaceAlt, in: Capsule())
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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var page: SeriesPage??

    var body: some View {
        Group {
            switch page {
            case .none:
                List { SkeletonRows(count: 10) }
            case .some(.none):
                EmptyState("Series not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)):
                content(page)
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
        .task(id: PageIdentity.taskID(key, load: catalog.loadKey)) {
            page = nil
            guard catalog.state == .ready else { return }
            page = .some(await catalog.seriesPage(key))
        }
    }

    private func head(_ page: SeriesPage) -> some View {
        let series = page.series
        let kicker = series.genre.map { ItemKicker.genre($0, rest: series.network) }
            ?? series.network.map(ItemKicker.text)
        return ItemHeadBoard(kicker: kicker, name: series.name, genre: series.genre, art: series.lead, label: series.labelItem,
                             facts: SeriesHead.facts(series), first: series.firstDate, last: series.lastDate, years: series.yearCounts)
    }

    private func gallery(_ page: SeriesPage) -> [Artwork] {
        ItemLead.gallery(page.series.gallery, lead: page.series.lead)
    }

    private func actions(_ page: SeriesPage) -> some View {
        ActionRow {
            FollowButton(key: page.series.key).pageAction(primary: true)
            ShareLink(item: SiteLinks.series(page.series.key), subject: Text(page.series.name)) {
                ActionLabel(title: "Share", systemImage: "square.and.arrow.up")
            }
            .pageAction()
            .help("Share")
        }
    }

    #if !os(tvOS)
    private func wide(_ page: SeriesPage) -> some View {
        WidePage {
            head(page)
            actions(page).frame(maxWidth: 480, alignment: .leading)
            if let about = page.about {
                SeriesAboutBlock(about: about)
                    .frame(maxWidth: 720, alignment: .leading)
            }
            if !gallery(page).isEmpty { SeriesGallery(pictures: gallery(page)) }
            ForEach(page.seasons) { season in
                WideSection(title: season.season ?? "Undated") {
                    ForEach(season.episodes) { episode in
                        NavigationLink(value: Route.episode(episode.id)) {
                            EpisodeRowLabel(episode: episode)
                        }
                        .wideRow()
                        .playContextMenu(episode.id)
                    }
                }
            }
        }
    }
    #endif

    @ViewBuilder private func content(_ page: SeriesPage) -> some View {
        #if os(iOS)
        if sizeClass == .regular { wide(page) } else { list(page) }
        #elseif os(macOS)
        wide(page)
        #else
        list(page)
        #endif
    }

    private func list(_ page: SeriesPage) -> some View {
        List {
            Section {
                head(page)
                    .listRowInsets(EdgeInsets(top: Spacing.s2, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                actions(page)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                if let about = page.about {
                    SeriesAboutBlock(about: about)
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if !gallery(page).isEmpty {
                    SeriesGallery(pictures: gallery(page))
                        .padding(.horizontal, Spacing.s4)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Spacing.s2, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(page.seasons) { season in
                Section {
                    ForEach(season.episodes) { episode in
                        NavigationLink(value: Route.episode(episode.id)) {
                            EpisodeRowLabel(episode: episode)
                        }
                        .playRowLink()
                        .playContextMenu(episode.id)
                    }
                } header: {
                    Text(verbatim: season.season ?? "Undated")
                }
            }
        }
        .modifier(ReadableColumn())
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
    @State private var castsByEar = false

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
        .task(id: PageIdentity.taskID(id, load: catalog.loadKey)) {
            detail = nil
            show = nil
            guard catalog.state == .ready else { return }
            let loaded = await catalog.episodeDetail(id)
            if let loaded { show = await catalog.series([loaded.episode.seriesKey]).first }
            detail = .some(loaded)
            castsByEar = false
            if let loaded { castsByEar = await EarDoor.opens(loaded, plays: plays, forwarding: catalog.forwarding) }
        }
        .task { await plays.load() }
    }

    private func content(_ detail: EpisodeDetail) -> some View {
        let episode = detail.episode
        let isCurrent = player.item?.episode.id == episode.id
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        let lead = Grammar.leadPicture(series: show, credits: detail.credits, star: detail.star)
        let showFacts: [String?] = show.map { [$0.yearSpan ?? "Undated", $0.episodeCount == 1 ? "1 episode" : "\($0.episodeCount.formatted()) episodes"] } ?? []
        let genre = show?.genre ?? episode.seriesGenre
        let onAir = Grammar.onAirOf(detail.credits)
        let downloadState = downloads.record(for: episode.id)?.state
        let offline = !catalog.isOnline && downloadState != .downloaded
        #if os(macOS)
        let transcript = false
        #else
        let transcript = episode.transcriptURL != nil
        #endif
        return PageBody(measure: 960) {
            PageSection {
                ItemHeadBoard(kicker: ItemKicker.show(episode.seriesName, key: episode.seriesKey),
                              name: ItemLead.episodeTitle(episode), genre: genre, label: episode.labelItem(series: show),
                              facts: Grammar.episodeFacts(date: episode.airDate.map { AirDate.display($0) }, network: episode.network, sponsor: detail.sponsor,
                                                          length: episode.durationText, season: episode.season,
                                                          title: episode.title, number: episode.number),
                              first: show?.firstDate, last: show?.lastDate, years: show?.yearCounts,
                              markYear: episode.airDate.flatMap { Int($0.prefix(4)) })
                    .gridRow()

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
                    #if os(macOS)
                    if let url = episode.transcriptURL {
                        Button {
                            openWindow(id: TranscriptRef.windowID, value: TranscriptRef(title: episode.displayTitle, url: url))
                        } label: {
                            ActionLabel(title: Transcript.label, systemImage: "text.quote")
                        }
                        .pageAction()
                        .help(Transcript.label)
                    }
                    #endif
                }
                .regularVerticalPadding()
                .gridRow(.words, top: 0)

                // Decision 068: an episode linked to a castable script this bundle holds.
                if let id = detail.script, plays.has(id) {
                    StartEarDramaButton(scriptID: id)
                        .pageAction()
                        .gridRow(.words, top: 0)
                } else if castsByEar {
                    // With no castable script and a shown transcript, Record This casts the episode by ear (Decision 088.3).
                    EarDoor(episodeID: episode.id).gridRow(.words, top: 0)
                }
                if let access = detail.scriptAccess {
                    ReadScriptControl(access: access)
                        .gridRow(.words, top: 0)
                }
            }

            // Filled rows are a section of their own (iOS-DESIGN §3.6h): under clear rows the card has no top corners.
            if downloadState != nil || transcript || offline || (isCurrent && player.errorMessage != nil) {
                PageSection {
                    if downloadState != nil { DownloadControl(detail: detail) }
                    #if !os(macOS)
                    if transcript {
                        Button {
                            transcriptOpen = true
                        } label: {
                            Label(Transcript.label, systemImage: "text.quote")
                        }
                    }
                    #endif
                    if offline { OfflineNotice() }
                    if isCurrent, let message = player.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.semanticError)
                    }
                }
            }

            if lead != nil {
                let showRow = NavigationLink(value: Route.series(episode.seriesKey)) {
                    GrammarRow(visual: .window(lead, name: episode.seriesName, genre: genre), title: episode.seriesName, sub: showFacts)
                }
                .playRowLink()
                .pageRow()
                #if os(macOS)
                PageSection {
                    showRow
                    PictureCredit(arts: [lead], slot: 48)
                }
                #else
                Section { showRow } footer: { PictureCredit(arts: [lead], slot: 48) }
                #endif
            }

            if !onAir.isEmpty {
                PageSection {
                    OnAirFaces(credits: onAir, genre: genre)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    PictureCredit(arts: onAir.map(\.art), slot: 72)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } header: {
                    PageSectionTitle(title: "On the air")
                }
            }

            if !detail.credits.isEmpty {
                PageSection {
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
                                #if os(macOS)
                                .buttonStyle(.plain)
                                #endif
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
                PageSection {
                    DisclosureGroup {
                        ForEach(Array(detail.recordings.enumerated()), id: \.element.id) { index, recording in
                            Button {
                                play(episode.id, recording: recording)
                            } label: {
                                VersionLabel(recording: recording, position: index + 1, isDefault: recording.rank == 0)
                            }
                            .accessibilityHint("Plays this copy")
                            #if os(macOS)
                            .buttonStyle(.plain)
                            .help("Play this copy")
                            #endif
                        }
                    } label: {
                        HStack {
                            Text("Recordings").font(TypeRamp.bodyStrong)
                            Spacer(minLength: 0)
                            Text(verbatim: detail.recordings.count.formatted())
                                .font(TypeRamp.caption)
                                .foregroundStyle(Color.brandTextMuted)
                        }
                    }
                    .accessibilityIdentifier("recordings-disclosure")
                }
            }

            if let rightsLine = detail.rightsLine {
                PageSection {
                    Text(rightsLine)
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                }
            }
        }
        #if os(iOS)
        .modifier(ReadableColumn(width: 960))
        #endif
        .navigationTitle(ItemLead.episodeTitle(episode))
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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var page: PersonPage??
    @State private var shows: [String: SeriesRow] = [:]
    @State private var newestFirst = false

    var body: some View {
        Group {
            switch page {
            case .none:
                List { SkeletonRows(count: 10) }
            case .some(.none):
                EmptyState("Person not found", systemImage: "questionmark.square.dashed")
            case let .some(.some(page)):
                content(page, groups: page.groups(newestFirst: newestFirst))
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
        .navigationBarTitleDisplayMode(.inline)
        #endif
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

    private func head(_ page: PersonPage, groups: [PersonSeriesGroup]) -> some View {
        let run = PersonShows.span(page.episodes)
        return ItemHeadBoard(name: page.person.name, genre: nil, art: page.person.art,
                             label: LabelItem(kind: .person, name: page.person.name, first: run.first, last: run.last), round: true,
                             facts: [page.person.years, PersonRowLabel.count(page.episodes.count),
                                     groups.count > 1 ? countText(groups.count, "show", "shows") : nil],
                             first: run.first, last: run.last, years: PersonShows.yearCounts(page.episodes))
    }

    private func showShelf(_ groups: [PersonSeriesGroup], inset: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Spacing.s3) {
                ForEach(groups) { group in
                    NavigationLink(value: Route.series(group.seriesKey)) {
                        let tile = PersonShows.tile(shows[group.seriesKey], key: group.seriesKey,
                                                    name: group.seriesName, episodes: group.episodes)
                        ShowTile(series: tile, width: 160,
                                 facts: [tile.yearSpan ?? "Undated", countText(group.episodes.count, "episode", "episodes")])
                    }
                    .buttonStyle(.plain)
                }
            }
            .sharesNameHeight()
            .padding(.horizontal, inset)
        }
    }

    #if !os(tvOS)
    private func wide(_ page: PersonPage, groups: [PersonSeriesGroup]) -> some View {
        WidePage {
            head(page, groups: groups)
            if groups.count > 1 { showShelf(groups, inset: Spacing.s6).padding(.horizontal, -Spacing.s6) }
            ForEach(groups) { group in
                WideSection(title: group.seriesName) {
                    ForEach(group.episodes) { item in
                        NavigationLink(value: Route.episode(item.id)) {
                            EpisodeRowLabel(episode: item.episode, note: item.rolesLine)
                        }
                        .wideRow()
                        .playContextMenu(item.id)
                    }
                }
            }
        }
    }
    #endif

    @ViewBuilder private func content(_ page: PersonPage, groups: [PersonSeriesGroup]) -> some View {
        #if os(iOS)
        if sizeClass == .regular { wide(page, groups: groups) } else { list(page, groups: groups) }
        #elseif os(macOS)
        wide(page, groups: groups)
        #else
        list(page, groups: groups)
        #endif
    }

    private func list(_ page: PersonPage, groups: [PersonSeriesGroup]) -> some View {
        List {
            Section {
                head(page, groups: groups)
                    .listRowInsets(EdgeInsets(top: Spacing.s2, leading: Spacing.s4, bottom: Spacing.s2, trailing: Spacing.s4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                if groups.count > 1 {
                    showShelf(groups, inset: Spacing.s4)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.episodes) { item in
                        NavigationLink(value: Route.episode(item.id)) {
                            EpisodeRowLabel(episode: item.episode, note: item.rolesLine)
                        }
                        .playRowLink()
                        .playContextMenu(item.id)
                    }
                } header: {
                    Text(group.seriesName)
                }
            }
        }
        .modifier(ReadableColumn())
    }
}

struct VersionLabel: View {
    let recording: Recording
    let position: Int
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(verbatim: RecordingLabel.title(recording, position: position))
                .font(TypeRamp.body)
                .foregroundStyle(Color.brandText)
            let facts = RecordingLabel.facts(recording, isBest: isDefault)
            if !facts.isEmpty {
                Text(verbatim: facts)
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
    }
}

// MARK: - Search

struct SearchResultsList: View {
    let query: String
    @Environment(CatalogStore.self) private var catalog
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    @State private var results: SearchResults?
    @State private var searchedFor = ""

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                EmptyState("Search titles, people, and spoken words", systemImage: "magnifyingglass")
            } else if let results, searchedFor == query {
                let matchingPlays = Self.plays(plays.rows, matching: query)
                let mine = Self.own(plays.own.rows, matching: query)
                if results.isEmpty && matchingPlays.isEmpty && mine.isEmpty {
                    EmptyState("No matches for “\(query)”", systemImage: "magnifyingglass",
                               action: .init(title: "Add a Script") { app.wantsAddScript = true })
                } else {
                    PageBody {
                        if !mine.isEmpty {
                            PageRows("Your Scripts") { ForEach(mine) { OwnScriptLink(row: $0).pageRow() } }
                        }
                        if !results.series.isEmpty {
                            PageRows("Series") {
                                ForEach(results.series) { row in
                                    NavigationLink(value: Route.series(row.key)) { SeriesRowLabel(series: row) }
                                        .pageRow()
                                }
                            }
                        }
                        if !results.people.isEmpty {
                            PageRows("People") {
                                ForEach(results.people) { row in
                                    NavigationLink(value: Route.person(row.id)) { PersonRowLabel(row: row) }
                                        .pageRow()
                                }
                            }
                        }
                        if !matchingPlays.isEmpty {
                            PageRows("Plays") {
                                ForEach(matchingPlays) { script in
                                    NavigationLink(value: PlayRoute.script(script.id)) { ScriptRow(script: script) }
                                        .pageRow()
                                }
                            }
                        }
                        if let aired = results.aired, !aired.episodes.isEmpty {
                            PageRows(aired.title) {
                                ForEach(aired.episodes) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        EpisodeRowLabel(episode: episode, showSeries: true)
                                    }
                                    .playRowLink()
                                    .pageRow()
                                    .playContextMenu(episode.id)
                                }
                            }
                        }
                        if !results.episodes.isEmpty {
                            PageRows("Episodes") {
                                ForEach(results.episodes) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        EpisodeRowLabel(episode: episode, showSeries: true)
                                    }
                                    .playRowLink()
                                    .pageRow()
                                    .playContextMenu(episode.id)
                                }
                            }
                        }
                        // A search that found no play: the person may have the words themselves.
                        if matchingPlays.isEmpty && mine.isEmpty {
                            PageSection {
                                Button { app.wantsAddScript = true } label: { Label("Add a Script", systemImage: "plus") }
                                    .gridRow(.words)
                            }
                        }
                        if !results.transcript.isEmpty {
                            PageRows(Transcript.label) {
                                let words = Transcript.searchWords(query)
                                ForEach(results.transcript) { episode in
                                    NavigationLink(value: Route.episode(episode.id)) {
                                        TranscriptHitLabel(episode: episode, words: words)
                                    }
                                    .pageRow()
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
    static func plays<Play: PlayListing>(_ scripts: [Play], matching query: String) -> [Play] {
        let words = Self.words(query)
        guard !words.isEmpty else { return [] }
        return Array(scripts.lazy.filter { script in
            let have = Self.words("\(script.title) \(script.authorLine)")
            return words.allSatisfy { w in have.contains { $0.hasPrefix(w) } }
        }.prefix(40))
    }

    /// This device's own scripts by their titles (PLAYS-DESIGN §13).
    static func own(_ rows: [OwnRow], matching query: String) -> [OwnRow] {
        let words = Self.words(query)
        guard !words.isEmpty else { return [] }
        return rows.filter { row in
            let have = Self.words(row.title)
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
    @AppStorage(LibrarySide.storageKey) private var sideName = LibrarySide.listening.rawValue
    /// APP_LIBRARY_SIDE (DEBUG only): the side drawn until the person picks one; the stored choice is not written.
    @State private var doorSide = LaunchDoors.current.librarySide.map(\.capitalized)
    @State private var inProgress: [EpisodeRow]?
    @State private var queued: [EpisodeRow] = []
    @State private var following: [SeriesRow] = []
    @State private var voicesOpen = false

    private var side: LibrarySide { LibrarySide(rawValue: doorSide ?? sideName) ?? .listening }
    private var sideChoice: Binding<String> {
        Binding(get: { side.rawValue }, set: { doorSide = nil; sideName = $0 })
    }

    var body: some View {
        Group {
            if let inProgress {
                ScrollViewReader { proxy in
                List {
                    if catalog.state == .unavailable {
                        CatalogUnavailableView()
                    }
                    Section {
                        Picker("Library", selection: sideChoice) {
                            ForEach(LibrarySide.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .gridRow()
                    }
                    switch side {
                    case .listening: listening(inProgress)
                    case .making: making
                    }
                    foot
                }
                .pageMargins()
                .onChange(of: app.libraryVoicesRequest) {
                    voicesOpen = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        withAnimation { proxy.scrollTo("voices", anchor: .top) }
                    }
                }
                }
            } else {
                List { SkeletonRows() }.pageMargins()
            }
        }
        .navigationTitle("Library")
        #if os(iOS)
        // Edit reorders the queue in Up next; with nothing queued there is nothing to edit.
        .toolbar { if side == .listening && !queued.isEmpty && !Self.emptied { ToolbarItem(placement: .primaryAction) { EditButton() } } }
        #endif
        .task(id: account.isSignedIn) { if account.isSignedIn { await shared.loadRemote() } }
        .task(id: LibraryKey(entries: history.entries, queue: queue.items, load: catalog.loadKey)) {
            guard !Self.emptied else { inProgress = []; return }
            queued = await catalog.episodes(queue.items)
            inProgress = await catalog.episodes(history.inProgressIDs)
        }
        .task(id: follows.followedKeys.joined(separator: "\n") + "#\(catalog.loadKey)") {
            following = await catalog.series(follows.followedKeys)
        }
    }

    // MARK: Listening

    /// Up next (started, then the queue), the shows followed, then History and Downloads as one line each. A part with
    /// nothing in it is absent; a side with nothing says one sentence and Browse.
    @ViewBuilder private func listening(_ started: [EpisodeRow]) -> some View {
        let upNext = LibraryModel.upNext(started: started.map(\.id), queued: queued.map(\.id))
        let finished = Self.emptied ? 0 : history.entries.values.filter(\.finished).count
        let held = Self.emptied ? 0 : downloads.records.count
        let shows = Self.emptied ? [] : following
        if upNext.isEmpty && shows.isEmpty && finished == 0 && held == 0 {
            Section {
                EmptyState("Nothing played yet", systemImage: "books.vertical",
                           action: .init(title: "Browse") { app.selectedTab = .browse })
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        if !upNext.isEmpty {
            Section("Up next") { UpNextRows(started: started, queued: queued, limit: LibraryModel.shownRows) }
        }
        if !shows.isEmpty {
            Section("Shows you follow") { FollowingShelf(series: shows) }
        }
        if finished > 0 || held > 0 {
            Section {
                if finished > 0 {
                    LibraryCountLink(title: "History", systemImage: "clock.arrow.circlepath",
                                     count: finished.formatted(), route: .history)
                }
                if held > 0 { DownloadsRow() }
            }
        }
    }

    // MARK: Making

    /// Your Parts, the productions grouped by play, then one line per class. With none of them: one sentence and
    /// Record a Play.
    @ViewBuilder private var making: some View {
        let groups = LibraryPlayGroup.groups(PlaysShare.libraryRows(plays.store, remote: account.isSignedIn ? shared.remote : []))
        let seats = !HomeSeats.load().isEmpty
        let classes = (shared.classes?.teaching.count ?? 0) + (shared.classes?.memberOf.count ?? 0)
        if groups.isEmpty && !seats && classes == 0 {
            Section {
                EmptyState("Nothing recorded yet", systemImage: "mic",
                           action: .init(title: "Record a Play") { app.selectedTab = .record })
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        if seats {
            Section { PushLink(value: Route.parts) { Label("Your Parts", systemImage: "person.wave.2") } }
        }
        if !groups.isEmpty { ProductionsByPlay(groups: groups) }
        if account.isSignedIn { ClassesSection() }
    }

    // MARK: The foot

    /// Under either side, in this order everywhere: Account, Voices (disclosed in place, no Settings page, owner
    /// 2026-11-22), Export, About.
    @ViewBuilder private var foot: some View {
        Section("Account and preferences") {
            AccountRow()
            VoicesFootRow(open: $voicesOpen)
        }
        if voicesOpen { VoicesSection() }
        Section {
            ExportRow()
            NavigationLink(value: LibraryRoute.about) { Label("About Ear Drama", systemImage: "info.circle") }
        }
    }

    /// The APP_EMPTY_LIBRARY door (DEBUG only): Library drawn as a new listener's.
    static let emptied = LaunchDoors.current.emptyLibrary
}
#endif
