import Foundation

/// Library direction B's pure rules (owner 2026-11-23): Up next is the started episodes, then the queue in its
/// order, each once; five rows show before "All N". Display only: the history and queue stores are unchanged.
nonisolated enum LibraryModel {
    static let shownRows = 5

    static func upNext(started: [String], queued: [String]) -> [String] {
        var seen = Set<String>()
        return (started + queued).filter { seen.insert($0).inserted }
    }

    /// The queue after dragging within the rows shown: the shown rows in their new order, then the queue's rest.
    static func queueAfterMove(queue: [String], shown: [String]) -> [String] {
        shown + queue.filter { !shown.contains($0) }
    }
}
