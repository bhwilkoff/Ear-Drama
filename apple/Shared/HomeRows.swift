#if os(iOS) || os(macOS)
import SwiftUI

// Home's rows on the iPhone, iPad and Mac (iOS-DESIGN §4.1, macOS-DESIGN §3.1, Decision 075, 081): On the air and the
// dial (HomeOnAir.swift), the two doors, then rows each filled by one published rule. Each row is
// its own view with its own states and is absent when its rule yields nothing. The TV draws its own
// (ContentView_tvOS.swift).

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
                        TodaysSceneCard(row: row, wide: true).gridRow(.words)
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
