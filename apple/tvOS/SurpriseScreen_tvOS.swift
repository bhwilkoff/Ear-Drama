#if os(tvOS)
import SwiftUI

/// Surprise at ten feet (tvOS-DESIGN §4.10; Decision 068): an episode, an evening, and a play drawn
/// when it opens, each in the grammar, then Shuffle. The episode's and the evening's boards carry
/// Play, the default focus, as on Detail. The play is a tile only: the TV records nothing
/// (PLAYS-DESIGN §6), so it takes no focus.
struct SurpriseScreen_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @State private var episode: EpisodeRow?
    @State private var series: SeriesRow?
    @State private var evening: SurpriseEvening?
    @State private var script: PlayScript?
    @State private var loaded = false
    @State private var draw = 0
    @FocusState private var playFocused: Bool

    private struct Key: Hashable { let draw: Int; let load: Int }

    var body: some View {
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                if !loaded {
                    ProgressView()
                } else if episode == nil && evening == nil && script == nil {
                    EmptyState("Nothing to pick from yet", systemImage: "shuffle")
                }
                if let episode {
                    pick("An episode") {
                        HeadBoard(kicker: nil, name: episode.seriesName, genre: episode.seriesGenre,
                                  art: episode.seriesWindowArt, first: series?.firstDate, last: series?.lastDate,
                                  years: series?.yearCounts,
                                  facts: [episode.displayTitle, AirDate.display(episode.airDate)],
                                  link: .episode(episode.id))
                        Button { play(episode.id, presentPlayer: true) } label: { Label("Play", systemImage: "play.fill") }
                            .tint(Color.brandPrimary)
                            .focused($playFocused)
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
                            Button { play(first.id, presentPlayer: true) } label: { Label("Play", systemImage: "play.fill") }
                                .tint(Color.brandPrimary)
                        }
                    }
                }
                if let script {
                    pick("A play") {
                        ShowTile(series: SeriesRow(key: script.id, name: script.title, genre: PlayScript.boardGenre, firstDate: nil,
                                                   lastDate: nil, networks: [], episodeCount: 0),
                                 facts: [script.authorLine, countText(script.castParts.filter { $0.id.isSpeaking }.count, "part", "parts")]
                                     .filter { !$0.isEmpty },
                                 castScript: script)
                    }
                }
                if loaded {
                    Button { draw += 1 } label: { Label("Shuffle", systemImage: "shuffle") }
                        .focusSection()
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultFocus($playFocused, true)
        .task(id: Key(draw: draw, load: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            async let picked = catalog.randomEpisode()
            async let night = SurprisePicks.evening(catalog: catalog)
            script = await Task.detached { CastableLibrary.load()?.scripts.randomElement() }.value
            episode = await picked
            evening = await night
            if let key = episode?.seriesKey { series = await catalog.series([key]).first } else { series = nil }
            loaded = true
        }
    }

    private func pick<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text(title).font(TypeRamp.sectionHeader).foregroundStyle(Color.brandText).accessibilityAddTraits(.isHeader)
            content()
        }
        .focusSection()
    }
}
#endif
