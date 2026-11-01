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
    private var endedEarly: Set<Int> = []

    init(chosen: Recording, among recordings: [Recording]) {
        current = chosen
        ranked = recordings.sorted { $0.rank < $1.rank }
    }

    /// The recording loaded: a later failure (a seek, a dropped connection) gets its own retry.
    mutating func loaded() {
        retried = false
        tried = []
    }

    /// The clock the player keeps while it reads `reading` off the item. A failed item reads 0 s,
    /// which is not where the person was, so the retry would open the recording from the start
    /// (iPad seek test, 2026-10-30).
    static func clock(reading: Double, itemFailed: Bool, shown: Double) -> Double {
        guard reading.isFinite, !itemFailed else { return shown }
        return reading
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

    /// Whether an item that played to its end stopped far short of the recording's known length.
    /// A slow archive.org response can hand AVFoundation a few seconds of file; with precise timing
    /// it reads that as the whole item and "ends" it at 5 s of 30 minutes (iPad, 2026-10-31).
    static func endedTooSoon(position: Double, expected: Double?) -> Bool {
        guard let expected, expected.isFinite, position.isFinite else { return false }
        return expected - position > max(120, expected * 0.5)
    }

    /// The item ended too soon. Unlike `failed`, a recording that became ready first gets no fresh
    /// retry: each recording is retried once, then replaced by one that has not ended early.
    mutating func endedTooSoon(jitter: Double) -> Step {
        if endedEarly.insert(current.rank).inserted { return .retry(after: Self.retryDelay * jitter) }
        guard let next = ranked.first(where: { !endedEarly.contains($0.rank) }) else { return .giveUp }
        current = next
        retried = false
        return .fallback(next)
    }
}
