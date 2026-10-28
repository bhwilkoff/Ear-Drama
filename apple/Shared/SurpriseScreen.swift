#if os(iOS) || os(macOS)
import SwiftUI

/// Surprise (iOS-DESIGN §4.11; Decision 068): an episode, an evening, and a
/// play, drawn from the data when the screen opens and again on Shuffle. Each
/// plays or starts in one tap. No copy is written; a pick with no data is absent.
struct SurpriseScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(PlaysLibrary.self) private var plays
    @State private var episode: EpisodeRow?
    @State private var evening: SurpriseEvening?
    @State private var script: PlayScript?
    @State private var loaded = false
    @State private var draw = 0

    private struct Key: Hashable { let draw: Int; let load: Int }

    var body: some View {
        let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
        List {
            if !loaded {
                SkeletonRows(count: 3)
            } else if episode == nil && evening == nil && script == nil {
                EmptyState("Nothing to pick from yet", systemImage: "shuffle")
            }
            if let episode {
                Section("An episode") {
                    NavigationLink(value: Route.episode(episode.id)) {
                        EpisodeRowLabel(episode: episode, showSeries: true)
                    }
                    Button { play(episode.id) } label: { Label("Play", systemImage: "play.fill").foregroundStyle(Color.brandPrimary) }
                        .tint(Color.brandPrimary)
                }
            }
            if let evening {
                Section("An evening") {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text(verbatim: AirDate.display(evening.day.evening)).font(TypeRamp.bodyStrong)
                        if let line = evening.day.stationLine {
                            Text(verbatim: line).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if let first = evening.first {
                        NavigationLink(value: Route.episode(first.episode.id)) {
                            EpisodeRowLabel(episode: first.episode, showSeries: true)
                        }
                        // From its start, never live, and nothing queued behind it.
                        Button { play(first.episode.id) } label: { Label("Play", systemImage: "play.fill").foregroundStyle(Color.brandPrimary) }
                            .tint(Color.brandPrimary)
                    }
                }
            }
            if let script {
                Section("A play") {
                    NavigationLink(value: PlayRoute.script(script.id)) { ScriptRow(script: script) }
                    StartEarDramaButton(script: script)
                }
            }
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
            loaded = true
        }
    }
}
#endif
