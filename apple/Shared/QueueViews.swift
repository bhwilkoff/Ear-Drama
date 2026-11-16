import SwiftUI

// The queue verbs (the web's Detail button and Library rows): add to the end,
// remove, reorder. They never change what plays next (Decision 067).

/// A menu item on an episode: "Add to queue", or "Remove from queue" when it is there.
struct QueueMenuItem: View {
    let episodeID: String
    @Environment(ListeningQueue.self) private var queue

    var body: some View {
        let queued = queue.contains(episodeID)
        Button {
            if queued { queue.remove(episodeID) } else { queue.add(episodeID) }
        } label: {
            Label(queued ? "Remove from queue" : "Add to queue",
                  systemImage: queued ? "text.badge.minus" : "text.badge.plus")
        }
    }
}

/// Detail's toggle, the web's "Add to queue" / "In queue" (`aria-pressed`).
struct QueueToggleButton: View {
    let episodeID: String
    @Environment(ListeningQueue.self) private var queue

    var body: some View {
        let queued = queue.contains(episodeID)
        Button {
            if queued { queue.remove(episodeID) } else { queue.add(episodeID) }
        } label: {
            ActionLabel(title: queued ? "In queue" : "Add to queue",
                        systemImage: queued ? "text.badge.checkmark" : "text.badge.plus")
        }
        .pageAction()
        #if !os(tvOS)
        .sensoryFeedback(Haptic.light.feedback, trigger: queued)
        #endif
    }
}

/// The player's own queue verb: the same toggle as Detail's, on the surface where the episode is
/// playing. Its label reads the state; a pressed toggle, as the web's `aria-pressed` button.
struct PlayerQueueButton: View {
    let episodeID: String
    @Environment(ListeningQueue.self) private var queue

    var body: some View {
        let queued = queue.contains(episodeID)
        Button {
            if queued { queue.remove(episodeID) } else { queue.add(episodeID) }
        } label: {
            Label(queued ? "In queue" : "Add to queue", systemImage: queued ? "text.badge.checkmark" : "text.badge.plus")
        }
        .accessibilityIdentifier("player-queue")
        .accessibilityValue(queued ? "On" : "Off")
        .help(queued ? "Remove from queue" : "Add to queue")
        #if !os(tvOS)
        .sensoryFeedback(Haptic.light.feedback, trigger: queued)
        #endif
    }
}

#if !os(tvOS)
/// The player's own Share: the episode's https page, the twin every share lands on.
struct PlayerShareLink: View {
    let episode: EpisodeRow

    var body: some View {
        ShareLink(item: SiteLinks.episode(episode.id), subject: Text(episode.displayTitle)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("player-share")
        .help("Share")
    }
}
#endif

/// A queued episode's menu: one step up or down, or out; the web's three buttons.
struct QueueRowMenu: View {
    let episodeID: String
    @Environment(ListeningQueue.self) private var queue

    var body: some View {
        let index = queue.items.firstIndex(of: episodeID)
        Button { queue.move(episodeID, by: -1) } label: { Label("Move up", systemImage: "arrow.up") }
            .disabled(index == nil || index == 0)
        Button { queue.move(episodeID, by: 1) } label: { Label("Move down", systemImage: "arrow.down") }
            .disabled(index == nil || index == queue.items.count - 1)
        Button(role: .destructive) { queue.remove(episodeID) } label: {
            Label("Remove from queue", systemImage: "trash")
        }
    }
}

#if os(iOS)
/// What plays next, beside the player at regular width (iOS-DESIGN §5.9, Decision 080): the player's own queue,
/// read where it already lives. Up Next is the arc's next part; Queue is the person's queue with its verbs (drag to
/// reorder in place, swipe or the menu to remove, Move up and down); listening live, the lineup from the slot on the
/// air to the end, which the clock plays, so nothing in it plays by a tap.
struct PlayerQueuePane: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(CatalogStore.self) private var catalog
    @Environment(ListeningQueue.self) private var queue
    @Environment(LiveRadio.self) private var live
    @State private var queued: [EpisodeRow] = []
    @State private var now = Date()

    var body: some View {
        List {
            if live.day != nil || live.station != nil {
                lineup
            } else {
                upNext
                queueSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.brandBackground)
        .accessibilityIdentifier("player-queue-pane")
        .task(id: QueueKey(items: queue.items, current: player.item?.episode.id, load: catalog.loadKey)) {
            let current = player.item?.episode.id
            queued = await catalog.episodes(queue.items).filter { $0.id != current }
        }
        .task {
            while (try? await Task.sleep(for: .seconds(30))) != nil { now = Date() }
        }
    }

    @ViewBuilder private var upNext: some View {
        if let arc = player.arc, arc.nextPart != nil, let next = player.upNext.first {
            Section("Up Next") {
                EpisodeRowLabel(episode: next, showSeries: true, note: "Part \(arc.part + 1) of \(arc.parts)")
            }
        }
    }

    private var queueSection: some View {
        Section("Queue") {
            if queued.isEmpty {
                SectionCaption("Episodes you add play in this order, after the one that is playing.")
            }
            ForEach(queued) { episode in
                EpisodeRowLabel(episode: episode, showSeries: true)
                    .swipeActions {
                        Button(role: .destructive) { queue.remove(episode.id) } label: {
                            Label("Remove from queue", systemImage: "trash")
                        }
                    }
                    .contextMenu { QueueRowMenu(episodeID: episode.id) }
            }
            .onMove { source, destination in
                var ids = queued.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                let current = player.item?.episode.id
                // The playing episode may still sit in the queue; it keeps its place at the head.
                queue.reorder(queue.items.filter { $0 == current } + ids)
            }
        }
    }

    private var lineup: some View {
        let slots = live.lineup(at: now)
        return Section("On the Air") {
            ForEach(Array(slots.enumerated()), id: \.element.slot.id) { index, entry in
                let time = RadioClock.clock(entry.slot.utcStart)
                let isNow = index == 0 && entry.slot.utcStart <= now
                if let detail = entry.detail {
                    GrammarRow(visual: .window(detail.episode.seriesWindowArt, name: detail.episode.seriesName,
                                               genre: detail.episode.seriesGenre),
                               title: entry.slot.playableEpisode?.series ?? detail.episode.seriesName,
                               sub: [time, detail.episode.displayTitle], badge: isNow ? "Now" : nil)
                        .listRowBackground(isNow ? Color.brandSurfaceAlt : nil)
                } else {
                    GapLine(time: time, name: entry.slot.knownSeries ?? RadioClock.gapNote(entry.slot), isNow: isNow)
                }
            }
        }
    }

    private struct QueueKey: Equatable {
        let items: [String]
        let current: String?
        let load: Int
    }
}
#endif
