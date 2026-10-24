import Foundation

/// Where an episode stands in its story arc (contract §3.3, `arcs` and
/// `arc_parts`): the next part's id, nil on the last part, and on the last
/// part only, the series' next story's first part, offered and never started.
nonisolated struct ArcPosition: Equatable, Sendable {
    let arcID: String
    let part: Int
    let parts: Int
    let nextPart: String?
    let nextStory: String?
}

/// What may play after an episode ends (Decision 067): a part of a story arc
/// is followed by the arc's next part; at the arc's last part playback stops
/// and the next story is offered, never started. Outside an arc, and after an
/// arc's last part, whatever the person queued, whatever its series, then
/// stop. Nothing the person did not choose starts by itself. The same rule as
/// the web's `Player.upNext` and Android's `PlaybackQueue`.
nonisolated enum PlaybackQueue {
    enum Next: Equatable, Sendable {
        /// The arc's next part.
        case part(String)
        /// The queue's head.
        case queue(String)

        var episodeID: String {
            switch self {
            case let .part(id), let .queue(id): id
            }
        }
    }

    /// The queue's head, skipping the episode that just played.
    static func next(after episodeID: String, queued: [String]) -> String? {
        queued.first { $0 != episodeID }
    }

    /// The arc's next part, else the queue's head.
    static func after(_ episodeID: String, arc: ArcPosition?, queued: [String]) -> Next? {
        if let part = arc?.nextPart { return .part(part) }
        return next(after: episodeID, queued: queued).map(Next.queue)
    }

    /// The next story to offer: only on an arc's last part.
    static func offer(_ arc: ArcPosition?) -> String? {
        guard let arc, arc.nextPart == nil else { return nil }
        return arc.nextStory
    }
}
