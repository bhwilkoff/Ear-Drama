#if os(tvOS)
import SwiftUI

/// Surprise at ten feet (tvOS-DESIGN §4.10; Decision 068): an episode and an
/// evening drawn when it opens, each with Play, then Shuffle. No play: the TV
/// records nothing (PLAYS-DESIGN §6). Play is the default focus, as on Detail.
struct SurpriseScreen_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @State private var episode: EpisodeRow?
    @State private var evening: SurpriseEvening?
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
                } else if episode == nil && evening == nil {
                    EmptyState("Nothing to pick from yet", systemImage: "shuffle")
                }
                if let episode {
                    pick("An episode", lines: [episode.displayTitle, episode.seriesName, AirDate.display(episode.airDate)]) {
                        Button { play(episode.id, presentPlayer: true) } label: { Label("Play", systemImage: "play.fill") }
                            .tint(Color.brandPrimary)
                            .focused($playFocused)
                        NavigationLink(value: Route.episode(episode.id)) { Label("Episode", systemImage: "info.circle") }
                    }
                }
                if let evening {
                    let first = evening.first?.episode
                    pick("An evening", lines: [AirDate.display(evening.day.evening), evening.day.stationLine,
                                               first.map { "\($0.seriesName) · \($0.displayTitle)" }]) {
                        if let first {
                            // From its start, never live, and nothing queued behind it.
                            Button { play(first.id, presentPlayer: true) } label: { Label("Play", systemImage: "play.fill") }
                                .tint(Color.brandPrimary)
                        }
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
            episode = await picked
            evening = await night
            loaded = true
        }
    }

    private func pick<Actions: View>(_ title: String, lines: [String?],
                                     @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text(title).font(TypeRamp.sectionHeader).foregroundStyle(Color.brandText)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                ForEach(Array(lines.compactMap { $0 }.enumerated()), id: \.offset) { index, line in
                    Text(verbatim: line)
                        .font(index == 0 ? TypeRamp.bodyStrong : TypeRamp.body)
                        .foregroundStyle(index == 0 ? Color.brandText : Color.brandTextMuted)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: Spacing.s6) { actions() }
                .focusSection()
        }
    }
}
#endif
