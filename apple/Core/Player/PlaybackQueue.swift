import Foundation

/// What may play after an episode ends (Decision 067, the owner's rule until
/// serial arcs exist): one episode, then whatever the person queued, whatever
/// its series, then stop. Nothing the person did not choose starts by itself.
/// The same rule as the web's `Player.nextInQueue` and Android's `PlaybackQueue`.
nonisolated enum PlaybackQueue {
    /// The queue's head, skipping the episode that just played.
    static func next(after episodeID: String, queued: [String]) -> String? {
        queued.first { $0 != episodeID }
    }
}
