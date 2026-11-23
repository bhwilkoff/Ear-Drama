#if os(iOS) || os(macOS)
import SwiftUI

// Library direction B's pieces (owner 2026-11-23, iOS-DESIGN §4.6): the side control's values, the pushed places behind
// Up next, History, a play's productions and About, and the foot's Voices row.

/// The side Library opens on, kept per device. Listening is the default: most people only listen.
enum LibrarySide: String, CaseIterable, Identifiable {
    case listening = "Listening", making = "Making"
    var id: String { rawValue }
    static let storageKey = "ed.library.side"
}

/// Library's pushed places: the full Up next and History lists, a play's productions, About.
enum LibraryRoute: Hashable {
    case upNext, history, about
    case play(String)
}

/// One play's productions as one Library row: how many, and the newest one's state.
struct LibraryPlayGroup: Identifiable, Equatable {
    let key: String
    let title: String
    let rows: [PlaysShare.LibraryRow]
    var id: String { key }

    /// Rows come newest first; a play keeps the place its newest production holds.
    static func groups(_ rows: [PlaysShare.LibraryRow]) -> [LibraryPlayGroup] {
        var order: [String] = []
        var bucket: [String: [PlaysShare.LibraryRow]] = [:]
        for r in rows {
            let k = r.title.lowercased()
            if bucket[k] == nil { order.append(k) }
            bucket[k, default: []].append(r)
        }
        return order.map { k in LibraryPlayGroup(key: k, title: bucket[k]![0].title, rows: bucket[k]!) }
    }
}

/// A row that opens the full list behind it, with its count.
struct LibraryCountLink: View {
    let title: String
    let systemImage: String
    let count: String
    let route: LibraryRoute

    var body: some View {
        NavigationLink(value: route) {
            LabeledContent {
                Text(verbatim: count).monospacedDigit()
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

/// The foot's Voices row: its state, and the full controls disclosed in place under it.
struct VoicesFootRow: View {
    @Binding var open: Bool
    @State private var kokoro = KokoroModelStore.shared

    var body: some View {
        let engine = kokoro.ready && KokoroFlag.enabled ? "Kokoro" : "Device"
        let state = "\(engine) \u{00B7} \(VoiceChipText.rate(VoiceDefaultsStore.load().rate))"
        Button { withAnimation { open.toggle() } } label: {
            HStack {
                Label("Voices", systemImage: "waveform").foregroundStyle(Color.brandText)
                Spacer(minLength: Spacing.s3)
                Text(verbatim: state).foregroundStyle(Color.brandTextMuted)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.brandTextMuted)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "Expanded" : "Collapsed")
    }
}

/// About Ear Drama: the site's pages.
struct AboutScreen: View {
    var body: some View {
        List { Section { SiteLinkRows() } }
            .pageMargins()
            .navigationTitle("About Ear Drama")
    }
}

/// The full Up next list: started episodes with the queue after them; the queued rows drag and swipe to remove.
struct UpNextScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
    @Environment(ListeningQueue.self) private var queue
    @State private var started: [EpisodeRow]?
    @State private var queued: [EpisodeRow] = []

    private struct Key: Equatable { let ids: [String]; let queue: [String]; let load: Int }

    var body: some View {
        Group {
            if let started {
                List { UpNextRows(started: started, queued: queued, limit: nil) }
                    .pageMargins()
            } else {
                List { SkeletonRows() }.pageMargins()
            }
        }
        .navigationTitle("Up next")
        #if os(iOS)
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton() } }
        #endif
        .task(id: Key(ids: history.inProgressIDs, queue: queue.items, load: catalog.loadKey)) {
            queued = await catalog.episodes(queue.items)
            started = await catalog.episodes(history.inProgressIDs)
        }
    }
}

/// Up next's rows: started episodes (swipe removes from History), then the queue in the person's order.
struct UpNextRows: View {
    let started: [EpisodeRow]
    let queued: [EpisodeRow]
    let limit: Int?
    @Environment(ListeningHistory.self) private var history
    @Environment(ListeningQueue.self) private var queue

    var body: some View {
        let startedShown = limit.map { Array(started.prefix($0)) } ?? started
        let startedIDs = Set(started.map(\.id))
        let queuedOnly = queued.filter { !startedIDs.contains($0.id) }
        let queuedShown = limit.map { Array(queuedOnly.prefix(max(0, $0 - startedShown.count))) } ?? queuedOnly
        let total = started.count + queuedOnly.count
        ForEach(startedShown) { episode in
            NavigationLink(value: Route.episode(episode.id)) {
                EpisodeRowLabel(episode: episode, showSeries: true)
            }
            .playRowLink()
            .swipeActions { removeFromHistory(episode.id) }
            .contextMenu { removeFromHistory(episode.id) }
        }
        ForEach(queuedShown) { episode in
            NavigationLink(value: Route.episode(episode.id)) {
                EpisodeRowLabel(episode: episode, showSeries: true)
            }
            .playRowLink()
            .swipeActions {
                Button(role: .destructive) { queue.remove(episode.id) } label: {
                    Label("Remove from queue", systemImage: "trash")
                }
            }
            .contextMenu { QueueRowMenu(episodeID: episode.id) }
        }
        .onMove { source, destination in
            var ids = queuedShown.map(\.id)
            ids.move(fromOffsets: source, toOffset: destination)
            queue.reorder(LibraryModel.queueAfterMove(queue: queue.items, shown: ids))
        }
        if let limit, total > limit {
            NavigationLink(value: LibraryRoute.upNext) {
                Text(verbatim: "All \(total.formatted())")
            }
        }
    }

    private func removeFromHistory(_ id: String) -> some View {
        Button(role: .destructive) { history.remove(id) } label: {
            Label("Remove from History", systemImage: "trash")
        }
    }
}

/// Every finished episode, newest first, each removable.
struct HistoryScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningHistory.self) private var history
    @State private var played: [EpisodeRow]?

    var body: some View {
        Group {
            if let played {
                List {
                    ForEach(played) { episode in
                        NavigationLink(value: Route.episode(episode.id)) {
                            EpisodeRowLabel(episode: episode, showSeries: true)
                        }
                        .playRowLink()
                        .swipeActions { remove(episode.id) }
                        .contextMenu { remove(episode.id) }
                    }
                }
                .pageMargins()
            } else {
                List { SkeletonRows() }.pageMargins()
            }
        }
        .navigationTitle("History")
        .task(id: "\(history.entries.count)#\(catalog.loadKey)") {
            let ids = history.entries.filter(\.value.finished)
                .sorted { $0.value.updatedAt > $1.value.updatedAt }.map(\.key)
            played = await catalog.episodes(ids)
        }
    }

    private func remove(_ id: String) -> some View {
        Button(role: .destructive) { history.remove(id) } label: {
            Label("Remove from History", systemImage: "trash")
        }
    }
}

/// One play's productions, a Library place (a play with several keeps one row in Making).
struct PlayProductionsScreen: View {
    let key: String
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(AccountStore.self) private var account
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        let group = LibraryPlayGroup.groups(PlaysShare.libraryRows(plays.store, remote: account.isSignedIn ? shared.remote : []))
            .first { $0.key == key }
        List {
            ForEach(group?.rows ?? []) { row in
                if let production = row.local {
                    ProductionLink(production: production)
                } else if let remote = row.remote {
                    RemoteProductionRow(remote: remote, open: open)
                }
            }
        }
        .pageMargins()
        .navigationTitle(group?.title ?? "")
    }

    private func open(_ production: Production) {
        #if os(macOS)
        openWindow(id: ProductionWindow_macOS.id, value: production.id)
        #else
        app.push(PlayRoute.production(production.id))
        #endif
    }
}

/// Making's Productions: one row per play, its count and the newest one's state. A play with one production opens it.
struct ProductionsByPlay: View {
    let groups: [LibraryPlayGroup]
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Section("Productions") {
            ForEach(groups) { group in
                if group.rows.count == 1, let production = group.rows[0].local {
                    ProductionLink(production: production)
                } else if group.rows.count == 1, let remote = group.rows[0].remote {
                    RemoteProductionRow(remote: remote, open: open)
                } else {
                    NavigationLink(value: LibraryRoute.play(group.key)) { label(group) }
                }
            }
        }
    }

    private func label(_ group: LibraryPlayGroup) -> some View {
        let newest = group.rows[0].local.map { ProductionProgress.line($0, script: plays.castScript(for: $0)) } ?? ""
        return HStack(alignment: .top, spacing: Spacing.s3) {
            ArtTile(name: group.title, genre: nil, face: nil)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(verbatim: group.title).font(TypeRamp.bodyStrong)
                Text(verbatim: ["\(group.rows.count) productions", newest].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func open(_ production: Production) {
        #if os(macOS)
        openWindow(id: ProductionWindow_macOS.id, value: production.id)
        #else
        app.selectedTab = .library
        app.push(PlayRoute.production(production.id))
        #endif
    }
}
#endif
