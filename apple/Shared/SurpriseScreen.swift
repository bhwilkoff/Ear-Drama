#if os(iOS) || os(macOS)
import SwiftUI

/// Surprise (iOS-DESIGN §4.11; Decision 068): an episode, an evening, and a
/// play, drawn from the data when the screen opens and again on Shuffle. Each
/// is a head board in the grammar with one tap to play or start. No copy is
/// written; a pick with no data is absent.
struct SurpriseScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(PlaysLibrary.self) private var plays
    @State private var episode: EpisodeRow?
    @State private var series: SeriesRow?
    @State private var evening: SurpriseEvening?
    @State private var script: PlayScript?
    @State private var loaded = false
    @State private var draw = 0

    private struct Key: Hashable { let draw: Int; let load: Int }

    var body: some View {
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        ScrollView {
            picks {
                if !loaded {
                    SkeletonRows(count: 3)
                } else if episode == nil && evening == nil && script == nil {
                    EmptyState("Nothing to pick from yet", systemImage: "shuffle")
                }
                if let episode {
                    pick("An episode") {
                        NavigationLink(value: Route.episode(episode.id)) {
                            HeadBoard(kicker: nil, name: episode.seriesName, genre: episode.seriesGenre,
                                      art: episode.seriesWindowArt, first: series?.firstDate, last: series?.lastDate,
                                      years: series?.yearCounts,
                                      facts: [episode.displayTitle, AirDate.medium(episode.airDate)])
                        }
                        .buttonStyle(.plain)
                        playButton { play(episode.id) }
                    }
                }
                if let evening {
                    let first = evening.first?.episode
                    pick("An evening") {
                        HeadBoard(kicker: nil, name: AirDate.display(evening.day.evening), genre: first?.seriesGenre,
                                  art: first?.seriesWindowArt, first: nil, last: nil,
                                  facts: [evening.day.stationLine, first?.seriesName])
                        if let first {
                            // From its start, never live, and nothing queued behind it.
                            playButton { play(first.id) }
                        }
                    }
                }
                if let script {
                    pick("A play") {
                        NavigationLink(value: PlayRoute.script(script.id)) {
                            HeadBoard(kicker: nil, name: script.title, genre: PlayScript.boardGenre, art: nil,
                                      first: nil, last: nil, facts: PlayHead.facts(script),
                                      credits: script.authorLineWithYears, castScript: script)
                        }
                        .buttonStyle(.plain)
                        StartEarDramaButton(script: script)
                    }
                }
            }
            .padding(Spacing.s4)
            #if !os(macOS)
            .modifier(ReadableColumn())
            #endif
        }
        .navigationTitle("Surprise")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { draw += 1 } label: { Label("Shuffle", systemImage: "shuffle") }
                    .help("Shuffle")
            }
        }
        .task(id: Key(draw: draw, load: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            async let picked = catalog.randomEpisode()
            async let night = SurprisePicks.evening(catalog: catalog)
            await plays.load()
            script = plays.scripts.randomElement()
            episode = await picked
            evening = await night
            if let key = episode?.seriesKey { series = await catalog.series([key]).first } else { series = nil }
            loaded = true
        }
    }

    /// The three picks: a column, or side by side as far as a Mac window allows.
    @ViewBuilder private func picks<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if os(macOS)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 400), spacing: Spacing.s6, alignment: .top)],
                  alignment: .leading, spacing: Spacing.s6, content: content)
        #else
        VStack(alignment: .leading, spacing: Spacing.s6, content: content)
        #endif
    }

    private func pick<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(title).font(TypeRamp.sectionHeader).foregroundStyle(Color.brandText).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func playButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Play", systemImage: "play.fill")
        }
        .pageAction(primary: true)
    }
}
#endif
