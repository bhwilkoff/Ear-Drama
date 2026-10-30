import Foundation

/// Watches progress, not elapsed time (resilient-media-streaming): a load that wants data and has
/// received no new bytes and not moved its position for `limit` seconds never fails by itself, so
/// it is called failed and goes through `LoadRecovery`. A healthy slow load (the precise-timing
/// scan of a headerless VBR MP3 takes 23 s) keeps receiving bytes and is never touched.
nonisolated struct StallWatchdog: Sendable {
    static let limit = 30.0

    enum Verdict: Equatable, Sendable {
        case ok
        case stalled
    }

    private struct Mark: Equatable {
        let bytes: Double
        let position: Double
    }

    private var mark: Mark?
    private var since = 0.0

    /// One look at the player. `wantsData`: playing, or waiting to play, from the network.
    /// `bytes`: anything that only grows as data arrives (loaded seconds, bytes transferred).
    mutating func observe(now: Double, wantsData: Bool, bytes: Double, position: Double) -> Verdict {
        let seen = Mark(bytes: bytes, position: position)
        guard wantsData, seen == mark else {
            mark = wantsData ? seen : nil
            since = now
            return .ok
        }
        return now - since >= Self.limit ? .stalled : .ok
    }

    /// A new item was opened, or the stall was handled: start counting again.
    mutating func reset() {
        mark = nil
        since = 0
    }
}
