import Foundation

/// What may play after an episode ends. The queue is the rest of the SAME
/// series in broadcast order (R1, research 05 §2.4), so playback never runs
/// into unrelated content. A serial's arc end (R3) needs the `runs` table the
/// served projection does not carry yet; until it does, a series ends the queue.
nonisolated enum PlaybackQueue {
    static let maximum = 50

    /// The episodes after `episodeID` in its series page's order.
    static func following(_ episodeID: String, in page: SeriesPage) -> [EpisodeRow] {
        let all = page.episodes
        guard let index = all.firstIndex(where: { $0.id == episodeID }) else { return [] }
        return Array(all[(index + 1)...].prefix(maximum)).filter { $0.seriesKey == page.series.key }
    }
}
