import SwiftUI

// Now Playing's two sections under the controls (direction D, D3-9): "On the air", the episode's
// credited performers as round faces, and "That night on the radio", the other surviving
// broadcasts of the same air date (contract §3.3b, `CatalogDatabase.sameDay`). Each draws only
// when it has something: no credits, or an undated episode, leaves nothing and no heading.

struct NowPlayingPeople: View {
    let episode: EpisodeRow
    /// Opens a page. The player is a sheet or a cover with no navigation stack of its own, so the
    /// caller closes it and pushes the route onto the tab beneath.
    let open: (Route) -> Void
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @State private var onAir: [Credit] = []
    @State private var night: [EpisodeRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            if !onAir.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    SectionHead(title: "On the air") { EmptyView() }
                    OnAirFaces(credits: onAir, genre: episode.seriesGenre, open: open)
                    PictureCredit(arts: onAir.map(\.art), slot: 72)
                }
                .accessibilityIdentifier("now-playing-on-the-air")
            }
            if !night.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    SectionHead(title: "That night on the radio") { EmptyView() }
                    ForEach(night) { row in
                        #if os(tvOS)
                        Button { open(.episode(row.id)) } label: { nightRow(row) }
                            .buttonStyle(.card)
                        #else
                        nightRow(row)
                            .contentShape(Rectangle())
                            .onTapGesture { open(.episode(row.id)) }
                            .accessibilityAddTraits(.isButton)
                        #endif
                    }
                }
                .accessibilityIdentifier("now-playing-that-night")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: episode.id) {
            onAir = []
            night = []
            let id = episode.id
            let detail = await catalog.episodeDetail(id)
            let same = await catalog.sameDay(episode.airDate, excluding: id)
            guard id == episode.id else { return }
            onAir = detail.map { Grammar.onAirOf($0.credits) } ?? []
            night = same
        }
    }

    /// The row the lists use: the show's window, the title, the show and its network (the date is
    /// the section's own), the length, and Play.
    private func nightRow(_ row: EpisodeRow) -> some View {
        GrammarRow(
            visual: .window(row.seriesWindowArt, name: row.seriesName, genre: row.seriesGenre),
            title: row.displayTitle,
            sub: [row.seriesName, row.network],
            length: row.durationText,
            playLabel: "Play \(row.displayTitle)",
            onPlay: { PlayEpisodeAction(catalog: catalog, player: player, store: store)(row.id) })
    }
}
