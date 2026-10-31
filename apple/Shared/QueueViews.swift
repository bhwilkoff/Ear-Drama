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
