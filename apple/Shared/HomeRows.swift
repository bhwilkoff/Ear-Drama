#if os(iOS) || os(macOS)
import SwiftUI

// Home's rows on the iPhone, iPad and Mac (iOS-DESIGN §4.1, macOS-DESIGN §3.1, Decision 075): what is on
// the air with Listen Live, the three doors, then rows each filled by one published rule. Each row is
// its own view with its own states and is absent when its rule yields nothing. The TV draws its own
// (ContentView_tvOS.swift).

// MARK: - On the air

struct HomeOnAirSection: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(LiveRadio.self) private var radio
    @State private var load: OnAirLoad = .loading
    @State private var attempt = 0
    @State private var now = Date()
    @State private var tuning = false

    private struct Key: Hashable { let date: String; let attempt: Int }

    var body: some View {
        Group {
            switch load {
            case .loading:
                PageSection {
                    ProgressView().frame(maxWidth: .infinity).gridRow()
                }
            case .failed:
                PageSection {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Label("Tonight could not load", systemImage: "wifi.slash")
                            .font(TypeRamp.body)
                            .foregroundStyle(Color.brandTextMuted)
                        Button("Try Again") { load = .loading; attempt += 1 }
                            .pageAction()
                    }
                    .gridRow(.words)
                }
            case let .ready(day, stations):
                if let on = OnAirNow.pick(day: day, stations: stations, now: now) { block(on) }
            }
        }
        .task(id: Key(date: RadioClock.localDate(now), attempt: attempt)) {
            load = await OnAirLoad.load(now: now)
        }
        .task {
            while !Task.isCancelled {
                guard (try? await Task.sleep(for: .seconds(15))) != nil else { return }
                now = Date()
            }
        }
    }

    private func block(_ on: OnAirNow) -> some View {
        let listening = on.isLive(radio)
        let episode = on.episode
        return PageSection {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                PushLink(value: Route.episode(episode.id)) {
                    HStack(spacing: Spacing.s3) {
                        SeriesKeyWindow(key: GrammarSlot.seriesKey(episode.id), name: episode.series, side: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: episode.series)
                                .font(TypeRamp.bodyStrong)
                                .foregroundStyle(Color.brandText)
                                .multilineTextAlignment(.leading)
                            EventLine(facts: on.eventFacts(now))
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("on-air-row")
                if let note = on.note {
                    Text(verbatim: note).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
                ActionRow {
                    Button {
                        if listening {
                            on.stopListening(live: radio, player: player)
                        } else {
                            tuning = true
                            Task {
                                await on.tuneIn(catalog: catalog, live: radio, player: player, muted: store.isMuted)
                                tuning = false
                            }
                        }
                    } label: {
                        Label(listening ? "Listening Live" : "Listen Live",
                              systemImage: listening ? "waveform" : "dot.radiowaves.left.and.right")
                    }
                    .pageAction(primary: true)
                    .disabled(tuning)
                    .accessibilityIdentifier("listen-live")
                    .accessibilityAddTraits(listening ? .isSelected : [])
                    Button { store.push(Route.stations) } label: { ActionLabel(title: "All Stations", systemImage: "radio") }
                        .pageAction()
                        .accessibilityIdentifier("all-stations")
                }
            }
            .gridRow(.words)
        } header: {
            PageSectionTitle(title: on.kicker)
        }
    }
}

// MARK: - The three doors

struct HomeDoors: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        PageSection {
            Grid(horizontalSpacing: Spacing.s3) {
                GridRow {
                    door("Listen", "dot.radiowaves.left.and.right") { store.push(Route.stations) }
                    door("Find a Show", AppTab.browse.symbol) { store.selectedTab = .browse }
                    door("Record a Play", AppTab.record.symbol) { store.selectedTab = .record }
                }
            }
            .gridRow()
        }
    }

    private func door(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.s2) {
                Image(systemName: symbol).font(TypeRamp.sectionHeader)
                Text(verbatim: title).font(TypeRamp.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.brandText)
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, Spacing.s2)
            .background(Color.brandSurfaceAlt, in: RoundedRectangle(cornerRadius: Radius.control))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("door-\(title)")
    }
}

// MARK: - Start a show and By length

/// A row of chips over a rail of first episodes: each chip a published shelf. A single shelf is the
/// heading's own suffix and shows no chips.
struct HomeChipSection: View {
    let title: String
    let chips: [HomeChip]
    @State private var picked: String?

    var body: some View {
        if let on = chips.first(where: { $0.id == picked }) ?? chips.first {
            PageSection {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    if chips.count > 1 {
                        ChipBar(chips: chips, picked: on.id) { picked = $0 }
                    }
                    EpisodeRail(episodes: on.episodes)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .pageBleed()
            } header: {
                SectionHead(title: chips.count == 1 ? "\(title): \(on.title)" : title) { EmptyView() }
            }
        }
    }
}

private struct ChipBar: View {
    let chips: [HomeChip]
    let picked: String
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s2) {
                ForEach(chips) { chip in
                    let on = chip.id == picked
                    Button { pick(chip.id) } label: {
                        Text(verbatim: chip.title)
                            .font(TypeRamp.caption)
                            .padding(.horizontal, Spacing.s3)
                            .padding(.vertical, Spacing.s1)
                            .foregroundStyle(on ? Color.brandOnSecondary : Color.brandText)
                            .background(on ? Color.brandSecondary : Color.brandSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .railPadding()
            .padding(.vertical, Spacing.s1)
        }
        .scrollIndicators(.hidden)
    }
}

struct EpisodeRail: View {
    let episodes: [EpisodeRow]
    @Environment(CatalogStore.self) private var catalog
    @State private var series: [String: SeriesRow] = [:]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                ForEach(episodes) { EpisodeTile(episode: $0, series: series[$0.seriesKey]) }
            }
            .sharesNameHeight()
            .railPadding()
            .padding(.vertical, Spacing.s2)
        }
        .scrollIndicators(.hidden)
        .task(id: episodes.map(\.id)) {
            let rows = await catalog.series(Array(Set(episodes.map(\.seriesKey))))
            series = Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
}

/// An episode as its series' show tile with Play on the window's corner: the episode's title and
/// length where the run and the count would be.
struct EpisodeTile: View {
    let episode: EpisodeRow
    let series: SeriesRow?
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store

    private var row: SeriesRow {
        series ?? SeriesRow(key: episode.seriesKey, name: episode.seriesName, genre: episode.seriesGenre, firstDate: nil,
                            lastDate: nil, networks: [], episodeCount: 0, face: episode.seriesFace,
                            picture: episode.seriesPicture)
    }

    var body: some View {
        PushLink(value: Route.episode(episode.id)) {
            ShowTile(series: row, facts: [episode.displayTitle, episode.lengthLabel].compactMap { $0 })
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                PlayEpisodeAction(catalog: catalog, player: player, store: store)(episode.id)
            } label: {
                Image(systemName: "play.fill")
                    .font(TypeRamp.body)
                    .foregroundStyle(Color.brandOnPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.brandPrimary))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(2)
            .accessibilityLabel("Play \(episode.displayTitle), \(episode.seriesName)")
            .accessibilityIdentifier("tile-play")
        }
        .accessibilityIdentifier("episode-tile")
    }
}

// MARK: - Record a play

/// Home's Record a play: Today's Scene (Decision 079), then the shared productions with a part still open.
struct HomeRecordSection: View {
    @Environment(PlaysLibrary.self) private var plays

    var body: some View {
        Group {
            switch plays.state {
            case .loading:
                EmptyView()
            case .unavailable:
                PageSection {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Label("Plays could not load", systemImage: "exclamationmark.triangle")
                            .font(TypeRamp.body)
                            .foregroundStyle(Color.brandTextMuted)
                        Button("Try Again") { Task { await plays.load() } }.pageAction()
                    }
                    .gridRow(.words)
                } header: {
                    SectionHead(title: "Record a play") { EmptyView() }
                }
            case .ready:
                if let row = PlayScript.todaysScene(plays.rows, dateKey: RadioClock.localDate()) {
                    PageSection {
                        TodaysSceneCard(row: row).gridRow()
                    } header: {
                        SectionHead(title: "Record a play") { EmptyView() }
                    }
                    OpenPartsRows()
                }
            }
        }
        .task { await plays.load() }
    }
}

/// Home's Open parts: shared productions someone else directs, signed in, with a speaking part still open.
/// This device's own productions are Record's Yours, never here.
struct OpenPartsRows: View {
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(AccountStore.self) private var account
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Group {
            if account.isSignedIn, !shared.openParts.isEmpty {
                PageRows("Open parts") {
                    ForEach(shared.openParts) { row in
                        VStack(alignment: .leading, spacing: 0) {
                            RemoteProductionRow(remote: row.remote, open: open)
                            Text(verbatim: row.open == 1 ? "1 open part" : "\(row.open.formatted()) open parts")
                                .font(TypeRamp.caption)
                                .foregroundStyle(Color.brandTextMuted)
                        }
                        .pageRow()
                    }
                }
            }
        }
        .task(id: account.isSignedIn) {
            if account.isSignedIn { await shared.loadOpenParts(plays: plays) }
        }
    }

    private func open(_ production: Production) {
        #if os(macOS)
        openWindow(id: ProductionWindow_macOS.id, value: production.id)
        #else
        app.push(PlayRoute.production(production.id))
        #endif
    }
}

// MARK: - Made here

/// The finished ear dramas, newest first (the old "New ear dramas"): absent when there are none. Home draws it twice,
/// `leading` under the three doors and last, and each copy shows only where `FinishedDramas.leadsHome` puts it.
struct MadeHereSection: View {
    var leading: Bool? = nil
    @Environment(AppStore.self) private var store
    @State private var finished = FinishedStore.shared
    private static let count = 6

    var body: some View {
        Group {
            if !finished.plays.isEmpty, leading.map({ $0 == FinishedDramas.leadsHome(count: finished.plays.count) }) ?? true {
                PageSection {
                    ShowGrid(items: Array(finished.plays.prefix(Self.count))) { play, width in
                        FinishedTile(play: play, width: width)
                    }
                    .gridRow()
                } header: {
                    SectionHead(title: "Made here") {
                        Button("All") { store.openBrowseDramas() }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .task { await finished.load() }
    }
}
#endif
