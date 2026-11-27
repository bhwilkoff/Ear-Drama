#if os(iOS) || os(macOS)
import SwiftUI

// Record (iOS-DESIGN §4.14, macOS-DESIGN §3.1, Decision 075): the section for making an ear drama. Yours,
// Today's Scene (Decision 079), finding a play (B31 §3: search, facets, the ways in, the grid), then Made here. Not
// compiled for the TV: it has no microphone and records nothing (tvOS-DESIGN §2.1).

struct RecordScreen: View {
    @Environment(PlaysLibrary.self) private var plays
    @Environment(CatalogStore.self) private var catalog
    @Environment(AppStore.self) private var app
    // A launch door may open Record with words in the field or facets chosen (DEBUG; LaunchDoors).
    @State private var find = FindCore.State(picks: LaunchDoors.current.playPicks)
    @State private var query = LaunchDoors.current.playQuery ?? ""
    @State private var playSearch = PlaySearchModel()
    private var searching: Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        PageBody {
            if !searching {
                YoursSection()
                YourScriptsSection()
            }
            switch plays.state {
            case .loading:
                PageSection { ProgressView().frame(maxWidth: .infinity).gridRow() } header: { SectionHead(title: "Plays") { EmptyView() } }
            case .unavailable:
                PageSection {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Label(catalog.isOnline ? "This did not load." : Connectivity.offlineLine,
                              systemImage: catalog.isOnline ? "exclamationmark.triangle" : "wifi.slash")
                            .font(TypeRamp.body)
                            .foregroundStyle(Color.brandTextMuted)
                        Button("Try Again") { Task { await plays.load() } }.pageAction()
                    }
                    .gridRow(.words)
                } header: {
                    SectionHead(title: "Plays") { EmptyView() }
                }
            case .ready:
                if !searching, let row = PlayScript.todaysScene(plays.rows, dateKey: RadioClock.localDate()) {
                    PageSection { TodaysSceneCard(row: row).gridRow() }
                }
                PlayFinderSection(query: query, search: playSearch, state: $find)
            }
            if !searching {
                MadeHereSection()
                ClassDoorsSection()
            }
        }
        .navigationTitle("Record")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(iOS)
        // Always drawn under the title: a field that hides until a pull is a search nobody finds.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Titles, authors, characters, lines")
        #else
        .searchable(text: $query, prompt: "Titles, authors, characters, lines")
        #endif
        .toolbar {
            #if os(macOS)
            // The Mac's facets are toolbar menus (macOS-DESIGN §3.1), so the page under them is the plays alone.
            if plays.state == .ready, !plays.rows.isEmpty, !searching {
                ToolbarItemGroup(placement: .automatic) {
                    PlayFacetMenus(rows: plays.rows, facets: FindCore.facets(plays.facets), state: $find, chips: false)
                }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button { app.push(PlayRoute.addScript) } label: { Label("Add a Script", systemImage: "plus") }
                    .help("Add a Script")
                    .accessibilityIdentifier("add-script")
            }
        }
        // A text file dropped on Record opens the page that reads it.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            app.post(.script(url))
            return true
        }
        .task { await plays.load() }
        .task { await FinishedStore.shared.load() }
        // A choice the library does not offer (a launch door's band, an index that changed under it) is dropped.
        .onChange(of: plays.facets, initial: true) { dropUnoffered() }
        .onChange(of: plays.state) { dropUnoffered() }
        // The play search runs here, on the one page view, never on its sections (PlaySearchSections).
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2, (try? await Task.sleep(for: .milliseconds(180))) != nil else { return }
            await plays.load()
            await playSearch.run(q, plays: plays)
        }
    }
}

extension RecordScreen {
    private func dropUnoffered() {
        guard plays.state == .ready else { return }
        find.picks = FindCore.offered(find.picks, FindCore.facets(plays.facets))
    }
}

/// Make a Class and Join a Class: Record's class door, signed in only.
struct ClassDoorsSection: View {
    @Environment(AccountStore.self) private var account

    var body: some View {
        if account.isSignedIn {
            PageRows("Classes") { ClassDoors().pageRow() }
        }
    }
}

/// This device's productions and the shared ones not opened here, each row "N of M lines recorded",
/// "Finished" or "Shared". Absent when there are none: no sentence says so.
struct YoursSection: View {
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(AccountStore.self) private var account
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        let rows = PlaysShare.libraryRows(plays.store, remote: account.isSignedIn ? shared.remote : [])
        if !rows.isEmpty {
            PageRows("Yours") {
                ForEach(rows) { row in
                    if let production = row.local {
                        ProductionLink(production: production).pageRow()
                    } else if let remote = row.remote {
                        RemoteProductionRow(remote: remote, open: open).pageRow()
                    }
                }
            }
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

/// A play as the show tile (B31 §1.4, §2.1; iOS-DESIGN §4.14): the window holds a picture of the play, else its label;
/// the name; the cast fingerprint where a show's run strip stands; "N voices" with "About M min"; on the form's board,
/// else the neutral one.
struct PlayTile: View {
    let script: PlayRow
    var width: CGFloat = ShowTile.defaultWidth

    var body: some View {
        TileLink(value: PlayRoute.script(script.id), series: Self.row(script), width: width,
                 facts: [script.voicesText, script.minutesText], cast: script.cast, playLabel: script.labelItem)
            .overlay(alignment: .topTrailing) { ReadTileButton(scriptID: script.id, title: script.title) }
            .accessibilityIdentifier("play-tile")
    }

    /// A play has no run: its board is its form's (`hue`), else neutral, and only a picture of the play leads its window.
    static func row(_ script: PlayRow) -> SeriesRow { script.tileRow }

    /// A play known only as a listing (a bundled script): the drama board, as before B31.
    static func row(_ script: some PlayListing) -> SeriesRow {
        SeriesRow(key: script.id, name: script.title, genre: PlayScript.boardGenre, firstDate: nil, lastDate: nil,
                  networks: [], episodeCount: 0)
    }
}

/// The plays as rows of tiles. Each row of tiles is a row of the page's list, so a library of 650 plays builds
/// only the rows on screen; the width is the caller's (measured on a row beside it), as Browse's is.
struct PlayGrid: View {
    let rows: [PlayRow]
    let width: CGFloat

    private struct Chunk: Identifiable {
        let items: [PlayRow]
        var id: String { items[0].id }
    }

    var body: some View {
        let gap = BrowseLayout.gap
        let columns = BrowseLayout.columns(width: width, tileMin: ShowTile.defaultWidth)
        let tileWidth = BrowseLayout.tileWidth(width: width, columns: columns)
        if width > 0 {
            ForEach(stride(from: 0, to: rows.count, by: columns).map { Chunk(items: Array(rows[$0..<min($0 + columns, rows.count)])) }) { chunk in
                HStack(alignment: .top, spacing: gap) {
                    ForEach(chunk.items) { PlayTile(script: $0, width: tileWidth) }
                }
                .frame(width: width, alignment: .leading)
                .sharesNameHeight()
                #if os(macOS)
                .environment(\.tileFillsRow, true)
                .fixedSize(horizontal: false, vertical: true)
                #endif
                .gridRow()
            }
        }
    }
}
#endif
