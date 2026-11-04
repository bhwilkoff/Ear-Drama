#if os(tvOS)
import SwiftUI

/// Surprise at ten feet (tvOS-DESIGN §4.10; Decision 068): an episode, an evening, and a play drawn
/// when it opens. The episode is the hero, Play the default focus, as on Detail, Shuffle beside it.
/// The evening is a wide card that plays; the play is a card only: the TV records nothing
/// (PLAYS-DESIGN §6), so it takes no focus.
struct SurpriseScreen_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @State private var episode: EpisodeRow?
    @State private var series: SeriesRow?
    @State private var evening: SurpriseEvening?
    @State private var script: PlayScript?
    @State private var more: [EpisodeRow] = []
    @State private var loaded = false
    @State private var draw = 0
    @FocusState private var playFocused: Bool

    private struct Key: Hashable { let draw: Int; let load: Int }
    private static let moreCount = 3

    var body: some View {
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: TV.rowGap) {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 200)
                } else if episode == nil && evening == nil && script == nil {
                    EmptyState("Nothing to pick from yet", systemImage: "shuffle")
                }
                if let episode {
                    TVHero(kicker: episode.seriesName, title: episode.displayTitle,
                           facts: [AirDate.display(episode.airDate), episode.durationText], genre: episode.seriesGenre,
                           art: episode.seriesWindowArt, pictureName: episode.seriesName, years: series?.yearCounts,
                           clearance: TV.rootClearance) {
                        Button { play(episode.id, presentPlayer: true) } label: { Label("Play", systemImage: "play.fill") }
                            .focused($playFocused)
                        NavigationLink(value: Route.episode(episode.id)) { Text("Details") }
                        Button { draw += 1 } label: { Label("Shuffle", systemImage: "shuffle") }
                    }
                } else if loaded {
                    Button { draw += 1 } label: { Label("Shuffle", systemImage: "shuffle") }
                        .focusSection()
                }
                if evening != nil || script != nil || !more.isEmpty {
                    TVShelf {
                        if let evening, let first = evening.first?.episode {
                            // From its start, never live, and nothing queued behind it.
                            Button { play(first.id, presentPlayer: true) } label: {
                                TVWideCard(art: first.seriesWindowArt, name: first.seriesName, genre: first.seriesGenre,
                                           top: "An evening", title: AirDate.display(evening.day.evening), display: true,
                                           sub: first.seriesName, foot: evening.day.stationLine)
                            }
                            .buttonStyle(.card)
                        }
                        if let script {
                            TVWideCard(art: nil, name: script.title, genre: PlayScript.boardGenre, top: "A play", title: script.title,
                                       sub: script.authorLine.isEmpty ? nil : script.authorLine,
                                       foot: countText(script.castParts.filter { $0.id.isSpeaking }.count, "part", "parts"))
                                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        }
                        ForEach(more) { TVEpisodeLink(episode: $0) }
                    }
                }
            }
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultFocus($playFocused, true)
        .task(id: Key(draw: draw, load: catalog.loadKey)) {
            guard catalog.state == .ready else { return }
            async let picked = catalog.randomEpisode()
            async let night = SurprisePicks.evening(catalog: catalog)
            script = await Task.detached { CastableLibrary.load()?.scripts.randomElement() }.value
            episode = await picked
            var drawn: [EpisodeRow] = []
            for _ in 0..<Self.moreCount {
                if let row = await catalog.randomEpisode(), row.id != episode?.id, !drawn.contains(where: { $0.id == row.id }) {
                    drawn.append(row)
                }
            }
            more = drawn
            evening = await night
            if let key = episode?.seriesKey { series = await catalog.series([key]).first } else { series = nil }
            loaded = true
        }
    }
}
#endif
