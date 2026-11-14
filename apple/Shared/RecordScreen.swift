#if os(iOS) || os(macOS)
import SwiftUI

// Record (iOS-DESIGN §4.14, macOS-DESIGN §3.1, Decision 075): the section for making an ear drama. Yours,
// Today's play, the plays by voices, length and kind, then Made here. Not compiled for the TV: it has no
// microphone and records nothing (tvOS-DESIGN §2.1).

struct RecordScreen: View {
    @Environment(PlaysLibrary.self) private var plays
    @State private var filter = PlayFilter()

    var body: some View {
        PageBody {
            YoursSection()
            switch plays.state {
            case .loading:
                PageSection { ProgressView().frame(maxWidth: .infinity).gridRow() }
            case .unavailable:
                PageSection {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Label("Plays could not load", systemImage: "exclamationmark.triangle")
                            .font(TypeRamp.body)
                            .foregroundStyle(Color.brandTextMuted)
                        Button("Try Again") { Task { await plays.load() } }.pageAction()
                    }
                    .gridRow()
                }
            case .ready:
                if let row = PlayBrowse.todaysPlay(plays.rows, dateKey: RadioClock.localDate()) {
                    PageSection { TodaysPlayBoard(row: row).gridRow() }
                }
                PlaysLibrarySection(scripts: plays.rows, filter: $filter)
            }
            MadeHereSection()
        }
        .navigationTitle("Record")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await plays.load() }
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

/// The castable library under its facets: three chips that count what each choice leaves, and the order.
struct PlaysLibrarySection: View {
    let scripts: [PlayRow]
    @Binding var filter: PlayFilter
    @State private var shown = Self.page
    @State private var measured: CGFloat = 0

    /// The Mac draws a page of plays at a time; a phone's list builds its rows as they scroll.
    private static let page = 60

    var body: some View {
        let list = PlayBrowse.list(scripts, filter)
        PageSection {
            if scripts.isEmpty {
                Text("No plays yet.")
                    .font(TypeRamp.body)
                    .foregroundStyle(Color.brandTextMuted)
                    .gridRow()
            } else {
                chips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .pageBleed()
                Text(verbatim: "\(countText(list.count, "play", "plays")) \u{00B7} \(filter.sort.title)")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured = $0 }
                    .gridRow()
                    .accessibilityIdentifier("plays-count")
                if list.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Nothing matches these filters.")
                            .font(TypeRamp.body)
                            .foregroundStyle(Color.brandTextMuted)
                        Button("Clear Filters") { filter = filter.cleared }.pageAction()
                    }
                    .gridRow()
                } else {
                    #if os(macOS)
                    PlayGrid(rows: Array(list.prefix(shown)), width: measured)
                    if list.count > shown {
                        Button("Show more") { shown += Self.page }
                            .buttonStyle(.borderless)
                            .font(TypeRamp.caption)
                    }
                    #else
                    PlayGrid(rows: list, width: measured)
                    #endif
                }
            }
        } header: {
            SectionHead(title: "Plays") { EmptyView() }
        }
        .onChange(of: filter) { shown = Self.page }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s2) {
                if filter.isFiltered {
                    Button("Clear") { filter = filter.cleared }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear filters")
                }
                chip(filter.voices?.title ?? "Voices", on: filter.voices != nil) {
                    Picker("Voices", selection: $filter.voices) {
                        Text("Any number").tag(VoiceBand?.none)
                        ForEach(VoiceBand.allCases, id: \.self) { band in
                            let n = PlayBrowse.count(scripts, filter, facet: .voices) { $0.voiceBand == band }
                            if n > 0 || filter.voices == band {
                                Text(verbatim: "\(band.title) (\(n.formatted()))").tag(VoiceBand?.some(band))
                            }
                        }
                    }
                }
                chip(filter.length?.title ?? "Length", on: filter.length != nil) {
                    Picker("Length", selection: $filter.length) {
                        Text("Any length").tag(LengthBand?.none)
                        ForEach(LengthBand.allCases, id: \.self) { band in
                            let n = PlayBrowse.count(scripts, filter, facet: .length) { $0.lengthBand == band }
                            if n > 0 || filter.length == band {
                                Text(verbatim: "\(band.title) (\(n.formatted()))").tag(LengthBand?.some(band))
                            }
                        }
                    }
                }
                chip(filter.kind?.title ?? "Kind", on: filter.kind != nil) {
                    Picker("Kind", selection: $filter.kind) {
                        Text("Any kind").tag(PlayKindFacet?.none)
                        ForEach(PlayKindFacet.allCases, id: \.self) { kind in
                            let n = PlayBrowse.count(scripts, filter, facet: .kind) { $0.kindFacet == kind }
                            if n > 0 || filter.kind == kind {
                                Text(verbatim: "\(kind.title) (\(n.formatted()))").tag(PlayKindFacet?.some(kind))
                            }
                        }
                    }
                }
                // An order, not a filter: never filled, never cleared.
                chip("Sort: \(filter.sort.chipTitle)", on: false) {
                    Picker("Sort", selection: $filter.sort) {
                        ForEach(PlaySort.allCases, id: \.self) { Text($0.chipTitle).tag($0) }
                    }
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip<Content: View>(_ title: String, on: Bool, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Text(verbatim: title)
                .font(TypeRamp.caption)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s1)
                .foregroundStyle(on ? Color.brandOnSecondary : Color.brandText)
                .background(on ? Color.brandSecondary : Color.brandSurface, in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// A play as the show tile: the cast drawn in the window, the name, the cast fingerprint where a show's
/// run strip stands, and "N voices" with "About M min".
struct PlayTile: View {
    let script: PlayRow
    var width: CGFloat = ShowTile.defaultWidth

    var body: some View {
        TileLink(value: PlayRoute.script(script.id), series: Self.row(script), width: width,
                 facts: [script.voicesText, script.minutesText], cast: script.cast)
            .overlay(alignment: .topTrailing) { ReadTileButton(scriptID: script.id, title: script.title) }
            .accessibilityIdentifier("play-tile")
    }

    /// A play carries no genre, picture or run: it stands on the drama board and its cast is its mark.
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
