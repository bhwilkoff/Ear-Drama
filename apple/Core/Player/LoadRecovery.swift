import Foundation

/// What to do when a recording fails to load (resilient-media-streaming): one retry of the same
/// recording after a jittered wait, then the next recording in rank order (each given the same
/// single retry), then the error. A seek test on the iPad saw `NSURLErrorDomain -1008` on every
/// seek of one episode and the player stayed failed.
nonisolated struct LoadRecovery: Sendable {
    enum Step: Equatable, Sendable {
        /// Load the same recording again after this many seconds.
        case retry(after: Double)
        /// This recording is spent; load this one.
        case fallback(Recording)
        /// Nothing left to try: surface the error.
        case giveUp
    }

    static let retryDelay = 1.0

    private(set) var current: Recording
    private let ranked: [Recording]
    private var tried: Set<Int> = []
    private var retried = false

    init(chosen: Recording, among recordings: [Recording]) {
        current = chosen
        ranked = recordings.sorted { $0.rank < $1.rank }
    }

    /// The recording loaded: a later failure (a seek, a dropped connection) gets its own retry.
    mutating func loaded() {
        retried = false
        tried = []
    }

    /// The current recording failed. `jitter` is a factor around 1 (0.5...1.5 in the player).
    mutating func failed(jitter: Double) -> Step {
        if !retried {
            retried = true
            return .retry(after: Self.retryDelay * jitter)
        }
        tried.insert(current.rank)
        guard let next = ranked.first(where: { !tried.contains($0.rank) && $0.rank != current.rank }) else {
            return .giveUp
        }
        current = next
        retried = false
        return .fallback(next)
    }
}
