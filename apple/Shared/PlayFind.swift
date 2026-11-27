#if os(iOS) || os(macOS)
import SwiftUI

// Finding a play (B31 §3.1-3.6; iOS-DESIGN §4.14, §4.5; macOS-DESIGN §3.1): Record's Plays with its search field, the
// facets as native menus counted against each other, Filters, the ways in as rails whose heading is their rule, the
// grid under the sort's name, the four states; the search's Plays, Characters and Lines; a collection and the scenes
// for N voices as pushed pages. The rules are FindCore's (the web's js/find-core.js); this file only draws them.

// MARK: - The facets

enum FindText {
    /// A facet value in its menu: "1-2 voices (27)", "Comedy (214)".
    static func option(_ f: FindCore.Facet, _ o: FindCore.Option) -> String {
        let label = f.key == "voices" ? "\(o.label) \(o.label == "1" ? "voice" : "voices")" : o.label
        return "\(label) (\(o.count.formatted()))"
    }

    /// The chip's title: the chosen value's words, else the facet's name.
    static func chip(_ f: FindCore.Facet, picked: String?) -> String {
        guard let picked, let o = f.values.first(where: { $0.value == picked }) else { return f.label }
        return f.key == "voices" ? "\(o.label) \(o.label == "1" ? "voice" : "voices")" : o.label
    }

    static func plays(_ n: Int) -> String { n == 1 ? "1 play" : "\(n.formatted()) plays" }
}

/// The four facets a performer asks first (B31 §3.1), the order, and Filters for the rest; each a native `Menu` whose
/// values carry their counts against the other picks, so no choice yields nothing.
struct PlayFacetMenus: View {
    let rows: [PlayRow]
    let facets: [FindCore.Facet]
    @Binding var state: FindCore.State
    var chips = true
    @State private var filtersOpen = false

    static let chipKeys = ["voices", "length", "form", "era"]

    var body: some View {
        let counted = FindCore.counts(rows, facets, state.picks)
        if state.isActive {
            Button("Clear") { state = state.cleared }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear filters")
        }
        ForEach(counted.filter { Self.chipKeys.contains($0.key) }, id: \.key) { f in
            chip(FindText.chip(f, picked: state.picks[f.key]), on: state.picks[f.key] != nil) {
                Picker(f.label, selection: pick(f.key)) {
                    Text(verbatim: f.key == "voices" ? "Any number" : f.key == "length" ? "Any length" : "Any").tag("")
                    ForEach(f.values, id: \.value) { Text(verbatim: FindText.option(f, $0)).tag($0.value) }
                }
                .pickerStyle(.inline)
            }
            .accessibilityIdentifier("facet-\(f.key)")
        }
        // An order, not a filter: never filled, never cleared.
        chip("Sort: \(FindCore.sortTitle(state.sort))", on: false) {
            Picker("Sort", selection: $state.sort) {
                ForEach(FindCore.sorts, id: \.key) { Text(verbatim: $0.title).tag($0.key) }
            }
            .pickerStyle(.inline)
        }
        if facets.contains(where: \.filter) {
            let n = facets.filter { $0.filter && state.picks[$0.key] != nil }.count
            Button { filtersOpen = true } label: { chipLabel(n > 0 ? "Filters \u{00B7} \(n)" : "Filters", on: n > 0) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("play-filters")
                .sheet(isPresented: $filtersOpen) { PlayFiltersSheet(rows: rows, facets: facets, state: $state) }
        }
    }

    private func pick(_ key: String) -> Binding<String> {
        Binding(get: { state.picks[key] ?? "" }, set: { state.picks[key] = $0.isEmpty ? nil : $0 })
    }

    @ViewBuilder private func chip<Content: View>(_ title: String, on: Bool, @ViewBuilder content: () -> Content) -> some View {
        if chips {
            Menu { content() } label: { chipLabel(title, on: on) }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
        } else {
            Menu { content() } label: { Text(verbatim: title) }
        }
    }

    private func chipLabel(_ title: String, on: Bool) -> some View {
        Text(verbatim: title)
            .font(TypeRamp.caption)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .foregroundStyle(on ? Color.brandOnSecondary : Color.brandText)
            .background(on ? Color.brandSecondary : Color.brandSurfaceAlt, in: Capsule())
    }
}

/// Filters (B31 §3.1): every facet, each value with its count against the others, applied with "Show N plays".
struct PlayFiltersSheet: View {
    let rows: [PlayRow]
    let facets: [FindCore.Facet]
    @Binding var state: FindCore.State
    @State private var pending: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let counted = FindCore.counts(rows, facets, pending)
        let n = FindCore.filter(rows, facets, pending).count
        NavigationStack {
            Form {
                ForEach(counted.filter { !$0.values.isEmpty }, id: \.key) { f in
                    Section(f.key == "era" ? "Era of the playwright" : f.label) {
                        ForEach(f.values, id: \.value) { o in
                            Button {
                                pending[f.key] = pending[f.key] == o.value ? nil : o.value
                            } label: {
                                HStack {
                                    Text(verbatim: o.label).foregroundStyle(Color.brandText)
                                    Spacer()
                                    Text(verbatim: o.count.formatted()).monospacedDigit().foregroundStyle(Color.brandTextMuted)
                                    Image(systemName: "checkmark").opacity(pending[f.key] == o.value ? 1 : 0)
                                        .accessibilityHidden(pending[f.key] != o.value)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(pending[f.key] == o.value ? .isSelected : [])
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear Filters") { pending = [:] }.disabled(pending.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show \(FindText.plays(n))") {
                        state.picks = pending
                        dismiss()
                    }
                    .accessibilityIdentifier("filters-show")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
        .onAppear { pending = state.picks }
    }
}

// MARK: - Record > Plays

/// Record's Plays (iOS-DESIGN §4.14 item 3): with a search of two letters or more, the search's sections; else the
/// facet chips (the Mac's are in the toolbar), the ways in while nothing is chosen, then the grid under the sort's name.
struct PlayFinderSection: View {
    let query: String
    let search: PlaySearchModel
    @Binding var state: FindCore.State
    @Environment(PlaysLibrary.self) private var plays
    @Environment(CatalogStore.self) private var catalog
    @State private var measured: CGFloat = 0
    @State private var shown = Self.page
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// The Mac draws a page of plays at a time; a phone's list builds its rows as they scroll.
    private static let page = 60

    var body: some View {
        let rows = plays.rows
        let facets = FindCore.facets(plays.facets)
        if query.trimmingCharacters(in: .whitespaces).count >= 2 {
            PlaySearchSections(query: query, search: search, offersAdd: true)
        } else if rows.isEmpty {
            PageSection {
                Text("No plays yet.").font(TypeRamp.body).foregroundStyle(Color.brandTextMuted).gridRow(.words)
            } header: {
                SectionHead(title: "Plays") { EmptyView() }
            }
        } else {
            #if os(iOS)
            PageSection {
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.s2) { PlayFacetMenus(rows: rows, facets: facets, state: $state) }
                        .railPadding()
                        .padding(.vertical, Spacing.s2)
                }
                .scrollIndicators(.hidden)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    measured = max(0, $0 - (sizeClass == .regular ? 0 : 2 * Spacing.s4))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                SectionHead(title: "Plays") { EmptyView() }
            }
            #endif
            if !state.isActive {
                ForEach(FindCore.rails(rows, plays.collections)) { PlayRailSection(rail: $0) }
            }
            grid(rows, facets)
        }
    }

    @ViewBuilder private func grid(_ rows: [PlayRow], _ facets: [FindCore.Facet]) -> some View {
        let list = FindCore.sorted(FindCore.filter(rows, facets, state.picks), state.sort)
        PageSection {
            #if os(macOS)
            Color.clear.frame(height: 1).onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured = $0 }
            #endif
            if list.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("Nothing matches these filters.").font(TypeRamp.body).foregroundStyle(Color.brandTextMuted)
                    Button("Clear Filters") { state = state.cleared }.pageAction()
                }
                .gridRow(.words)
            } else {
                #if os(macOS)
                PlayGrid(rows: Array(list.prefix(shown)), width: measured)
                if list.count > shown {
                    Button("Show more") { shown += Self.page }.buttonStyle(.borderless).font(TypeRamp.caption)
                }
                #else
                PlayGrid(rows: list, width: measured)
                #endif
            }
        } header: {
            SectionHead(title: FindCore.sortTitle(state.sort)) { Text(verbatim: list.count.formatted()).monospacedDigit() }
                .accessibilityIdentifier("plays-count")
        }
        .onChange(of: state) { shown = Self.page }
    }
}

/// A way in (B31 §3.2): its rule as the heading, its count beside it, All when it holds more, and its plays or scenes
/// as a rail that scrolls sideways.
struct PlayRailSection: View {
    let rail: FindCore.Rail

    var body: some View {
        PageSection {
            if let by = rail.by {
                Text(verbatim: by).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).gridRow(.words, top: 0, bottom: 0)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Spacing.s3) {
                    if rail.kind == .scenes {
                        ForEach(rail.scenes) { SceneCard(hit: $0) }
                    } else {
                        ForEach(rail.plays) { PlayTile(script: $0) }
                    }
                }
                .sharesNameHeight()
                .railPadding()
                .padding(.vertical, Spacing.s2)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .pageBleed()
        } header: {
            SectionHead(title: rail.title) {
                HStack(spacing: Spacing.s3) {
                    Text(verbatim: rail.count.formatted()).monospacedDigit()
                    PushLink(value: rail.kind == .scenes ? PlayRoute.scenes(rail.voices) : PlayRoute.collection(rail.id)) { Text("All") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("All \(rail.title)")
                }
            }
        }
        .accessibilityIdentifier("play-rail-\(rail.id)")
    }
}

/// Opens the reader at a line: a full-screen cover on iPhone and iPad, its own window on the Mac.
struct ReaderOpener {
    let app: AppStore
    #if os(macOS)
    let openWindow: OpenWindowAction
    #endif

    func callAsFunction(_ scriptID: String, line: String?) {
        #if os(macOS)
        openWindow(id: ReaderWindow_macOS.id, value: ReaderWindow_macOS.value(scriptID, line: line))
        #else
        app.reading = ReaderTarget(scriptID: scriptID, line: line)
        #endif
    }
}

/// A scene for N voices (B31 §3.4): its heading as printed and its minutes, the play (not on the play's own page), the
/// parts' names, on the play's board. It opens this scene's production (PLAYS-DESIGN §2.12), making it on the first tap;
/// Read on its corner opens the reader at the scene's first line, and a scene with no end (a library built before it)
/// opens the reader. Not on a TV.
struct SceneCard: View {
    let hit: FindCore.SceneHit
    var inPlay = false
    @Environment(AppStore.self) private var app
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AccountStore.self) private var account
    @State private var asking = false
    @State private var failure: String?
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    private func door() async {
        let s = hit.scene
        guard let to = s.to else { opener(hit.row.id, line: s.line); return }
        let range = ProductionRange(from: s.line, to: to)
        let store = plays.store
        if let have = store.newest(of: hit.row.id, range: range) { open(have.id); return }
        if StudioCore.needsAccount(productions: store.productions, signedIn: account.status != .signedOut, makingNew: true) {
            asking = true
            return
        }
        do {
            guard let whole = try await plays.script(id: hit.row.id) else { failure = "This play could not be found."; return }
            open(try store.create(whole, range: range, heading: s.heading).id)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func open(_ id: String) {
        #if os(macOS)
        openWindow(id: ProductionWindow_macOS.id, value: id)
        #else
        app.push(PlayRoute.production(id))
        #endif
    }

    private var opener: ReaderOpener {
        #if os(macOS)
        ReaderOpener(app: app, openWindow: openWindow)
        #else
        ReaderOpener(app: app)
        #endif
    }

    var body: some View {
        let s = hit.scene, ink = Color.onBoard(hit.row.hue)
        let kick = [s.heading, s.minutes > 0 ? "\(s.minutes) min" : nil].compactMap { $0 }.joined(separator: " \u{00B7} ")
        ZStack(alignment: .topTrailing) {
        Button { Task { await door() } } label: {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(verbatim: kick).font(TypeRamp.caption).foregroundStyle(ink.opacity(0.8)).padding(.trailing, s.to == nil ? 0 : 36)
                if !inPlay {
                    Text(verbatim: hit.row.title).font(TypeRamp.bodyStrong).foregroundStyle(ink).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: failure ?? FindCore.names(s.parts)).font(TypeRamp.caption).foregroundStyle(ink).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(Spacing.s3)
            .frame(width: Self.width, alignment: .topLeading)
            .frame(minHeight: inPlay ? 72 : 104, alignment: .topLeading)
            .background(Color.board(hit.row.hue), in: RoundedRectangle(cornerRadius: Radius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([inPlay ? nil : hit.row.title, s.heading, s.minutes > 0 ? "\(s.minutes) min" : nil, FindCore.names(s.parts)]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(s.to == nil ? "Opens the reader at this scene" : "Records this scene")
        .accessibilityIdentifier("scene-card")
        if s.to != nil { ReadTileButton(scriptID: hit.row.id, title: s.heading ?? hit.row.title, line: s.line) }
        }
        .sheet(isPresented: $asking) { SecondProductionSheet() }
    }

    #if os(macOS)
    static let width: CGFloat = 220
    #else
    static let width: CGFloat = 200
    #endif
}

// MARK: - A collection, the scenes for N voices

/// A collection whole (B31 §3.2): its title, the editor's credit and note when it has them, its plays in its own order.
struct PlayCollectionScreen: View {
    let id: String
    @Environment(PlaysLibrary.self) private var plays

    var body: some View {
        let found = FindCore.collection(plays.rows, plays.collections, id: id)
        Group {
            if let found {
                ShowGridPage(title: found.collection.title, by: found.collection.by, note: found.collection.note, rows: found.plays)
            } else if plays.state == .loading || (plays.fromLibrary && plays.collections == nil) {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState("This collection is not in the library.", systemImage: "questionmark.square.dashed")
            }
        }
        .navigationTitle(found?.collection.title ?? "Plays")
        .task { await plays.load() }
    }
}

/// Every scene for N voices (B31 §3.4), one per play, plays A to Z.
struct PlayScenesScreen: View {
    let voices: Int
    @Environment(PlaysLibrary.self) private var plays

    private var title: String { "Scenes for \(["", "", "two", "three", "four"][min(4, max(0, voices))]) voices" }

    var body: some View {
        let all = FindCore.sceneRows(plays.rows, voices: voices)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: SceneCard.width, maximum: SceneCard.width + 80), spacing: Spacing.s3, alignment: .top)],
                      alignment: .leading, spacing: Spacing.s3) {
                ForEach(all) { SceneCard(hit: $0) }
            }
            .padding(Spacing.s4)
            .overlay {
                if all.isEmpty, plays.state != .loading { EmptyState("No scenes for \(voices) voices yet.", systemImage: "theatermasks") }
            }
        }
        .navigationTitle(title)
        .task { await plays.load() }
    }
}

/// A grid of plays as a page: the heading's credit and note, then the tiles.
private struct ShowGridPage: View {
    let title: String
    let by: String?
    let note: String?
    let rows: [PlayRow]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                if let by { Text(verbatim: by).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted) }
                if let note { Text(verbatim: note).font(TypeRamp.body) }
                Text(verbatim: FindText.plays(rows.count)).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                ShowGrid(items: rows) { row, width in PlayTile(script: row, width: width) }
            }
            .padding(Spacing.s4)
        }
    }
}

// MARK: - Search (B31 §3.3)

/// The search's play sections (B31 §3.3, iOS-DESIGN §4.5): Plays (title and author), Characters, Lines (the words in
/// order before scattered words), each absent when empty; More lines reads the next scripts.
///
/// The caller runs the search (`PlaySearchModel.run`) from one view above the List: a `.task` here would sit on a group
/// of sections, and a group hands its modifiers to every child, so each section that appeared started the search again
/// and the first one's results never showed (iPhone 12, 2026-11-26: "quality of mercy" spun forever).
struct PlaySearchSections: View {
    let query: String
    let search: PlaySearchModel
    /// Record's search offers Add a Script when nothing matches; the Search tab says so once for every kind.
    var offersAdd = false
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app

    var body: some View {
        let s = search
        Group {
            if s.query != query.trimmingCharacters(in: .whitespaces) || s.phase == .loading {
                PageSection { ProgressView().frame(maxWidth: .infinity).gridRow() }
            } else {
                if !s.titled.isEmpty {
                    PageRows("Plays") {
                        ForEach(s.titled.prefix(30)) { PlayListRow(row: $0).pageRow() }
                    }
                }
                if !s.characters.isEmpty {
                    PageRows("Characters") {
                        ForEach(s.characters) { h in
                            PlayListRow(row: h.row, sub: [FindCore.titleCase(h.role), h.lines == 1 ? "1 line" : "\(h.lines.formatted()) lines",
                                                          h.row.firstAuthor]).pageRow()
                        }
                    }
                }
                if !s.shown.isEmpty || (s.reading && !s.foundAny) {
                    PageRows("Lines") {
                        ForEach(s.shown) { h in
                            PlayListRow(row: h.row, sub: [h.role, h.row.firstAuthor], said: FindCore.snippet(h.text, query), line: h.line).pageRow()
                        }
                        if s.reading {
                            ProgressView().frame(maxWidth: .infinity).pageRow()
                        } else if s.left > 0 {
                            Button("More lines (\(FindText.plays(s.left)))") { Task { await s.more(plays: plays) } }
                                .accessibilityIdentifier("more-lines")
                                .pageRow()
                        }
                    }
                } else if s.left > 0, !s.reading {
                    PageSection {
                        Button("More lines (\(FindText.plays(s.left)))") { Task { await s.more(plays: plays) } }.gridRow(.words)
                    }
                }
                if !s.foundAny, !s.reading, offersAdd {
                    PageSection {
                        VStack(alignment: .leading, spacing: Spacing.s2) {
                            Text("No plays match \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}.")
                                .font(TypeRamp.body).foregroundStyle(Color.brandTextMuted)
                            Button { app.wantsAddScript = true } label: { Label("Add a Script", systemImage: "plus") }.pageAction()
                        }
                        .gridRow(.words)
                    }
                }
            }
        }
    }
}

/// A play in a list (Search's Plays, Characters, Lines): its window (a picture of the play, else its label), the title,
/// a sub line, and a found line in italic, verbatim. It opens the play's page, or the reader at `line`.
struct PlayListRow: View {
    let row: PlayRow
    var sub: [String]? = nil
    var said: String? = nil
    var line: String? = nil
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Button {
            if let line {
                #if os(macOS)
                ReaderOpener(app: app, openWindow: openWindow)(row.id, line: line)
                #else
                ReaderOpener(app: app)(row.id, line: line)
                #endif
            } else {
                app.push(PlayRoute.script(row.id))
            }
        } label: {
            HStack(alignment: .top, spacing: Spacing.s3) {
                PictureWindow(art: row.windowPicture, name: row.title, genre: row.hue, side: 48, label: row.labelItem)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.title).font(TypeRamp.bodyStrong).foregroundStyle(Color.brandText).lineLimit(2)
                    EventLine(facts: sub ?? [row.firstAuthor, row.voicesText, row.minutesText])
                    if let said {
                        Text(verbatim: said).font(TypeRamp.caption).italic().foregroundStyle(Color.brandText).lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(line == nil ? "play-row" : "line-row")
    }
}
#endif
