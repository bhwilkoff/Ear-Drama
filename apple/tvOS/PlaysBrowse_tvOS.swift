#if os(tvOS)
import SwiftUI

// Browse's Plays scope on the TV (B31 §3.7, tvOS-DESIGN §4.2): the library's data shelves as focus shelves of play
// tiles, each headed by the rule that fills it, with the count. No facets, no scenes, no search by line and no record
// door: the TV records nothing. A tile is a focus stop with no page to open until the reader reaches the TV (B21). The
// index and the collections come through the one APIClient and are kept only in the URL cache (Caches).

struct PlaysBrowse_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var rows: [PlayRow]?
    @State private var collections: PlayCollections?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            if let rows {
                let rails = FindCore.rails(rows, collections, scenes: false, ids: FindCore.tvIDs(collections))
                if rows.isEmpty || rails.isEmpty {
                    EmptyState("No plays yet", systemImage: "theatermasks")
                } else {
                    Text(verbatim: countText(rows.count, "play", "plays"))
                        .font(TypeRamp.bodyStrong)
                        .foregroundStyle(Color.brandText)
                    ForEach(rails) { rail in
                        TVShelf(title: rail.title) {
                            Text(verbatim: rail.count.formatted()).monospacedDigit()
                        } content: {
                            ForEach(rail.plays) { PlayTile_tvOS(row: $0) }
                        }
                        .accessibilityIdentifier("tv-play-shelf-\(rail.id)")
                    }
                }
            } else if failed {
                EmptyState(catalog.isOnline ? "This did not load." : Connectivity.offlineLine, systemImage: "exclamationmark.triangle",
                           action: .init(title: "Try Again") { failed = false; Task { await load() } })
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.s6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task { await load() }
    }

    private func load() async {
        guard rows == nil else { return }
        do {
            guard let data = try await APIClient.shared.playsData("library/index.json") else { rows = []; return }
            let index = try JSONDecoder().decode(PlayRowIndex.self, from: data)
            // An older library has no collections file: the shelves are then absent, never an error.
            if let c = try? await APIClient.shared.playsData("library/collections.json") {
                collections = try? JSONDecoder().decode(PlayCollections.self, from: c)
            }
            rows = index.plays
        } catch {
            failed = true
        }
    }
}

/// A play as the grammar's tile at ten feet: its window (a picture of the play, else its label), the name, the cast
/// fingerprint, "N voices" and "About M min", on the form's board. It lifts under focus and opens nothing yet.
struct PlayTile_tvOS: View {
    let row: PlayRow
    @FocusState private var focused: Bool

    var body: some View {
        // The card style's lift by hand: `.hoverEffect(.highlight)` drew no mark on Ben Bedroom (2026-11-26), so the
        // focused tile could not be told from the rest. Only the focused tile is bright (§3.0).
        ShowTile(series: row.tileRow, facts: [row.voicesText, row.minutesText], cast: row.cast, playLabel: row.labelItem)
            .focusable()
            .focused($focused)
            .scaleEffect(focused ? 1.08 : 1)
            .brightness(focused ? 0 : -0.06)
            .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: focused ? 24 : 0, y: focused ? 14 : 0)
            .animation(.easeOut(duration: 0.15), value: focused)
            .accessibilityIdentifier("tv-play-tile")
    }
}
#endif
