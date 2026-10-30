import Foundation
import Testing

// resilient-media-streaming: a failed load is retried once with jitter, then the next recording in
// rank order, then the error. (An iPad seek test saw NSURLErrorDomain -1008 four times on one
// episode and the player stayed failed.)

struct LoadRecoveryTests {
    private func recording(_ rank: Int) -> Recording {
        Recording(rank: rank, archiveID: "a\(rank)", url: URL(string: "https://archive.org/download/a\(rank)/x.mp3")!,
                  format: "MP3", kbps: 64, lengthSeconds: 1800, variant: nil, partial: false)
    }

    /// The loop the player runs on each failed item, driven by a loader that fails the way a fake says.
    private func run(chosen: Int, among ranks: [Int], failures: Set<String>) -> (loaded: Recording?, attempts: [String], waits: [Double]) {
        let all = ranks.map(recording)
        var plan = LoadRecovery(chosen: all.first { $0.rank == chosen }!, among: all)
        var attempts: [String] = []
        var waits: [Double] = []
        var next = plan.current
        var attempt = 0
        while true {
            attempt += 1
            attempts.append("\(next.rank)")
            // A failure is keyed by "rank#attempt-of-that-rank".
            let nth = attempts.filter { $0 == "\(next.rank)" }.count
            if !failures.contains("\(next.rank)#\(nth)") { return (next, attempts, waits) }
            switch plan.failed(jitter: 1.25) {
            case .retry(let delay): waits.append(delay)
            case .fallback(let other): next = other
            case .giveUp: return (nil, attempts, waits)
            }
        }
    }

    @Test func aLoadThatFailsOnceIsRetriedOnceWithJitterAndPlays() {
        let result = run(chosen: 0, among: [0, 1], failures: ["0#1"])
        #expect(result.loaded?.rank == 0, "the same recording loads on the retry")
        #expect(result.attempts == ["0", "0"])
        #expect(result.waits == [LoadRecovery.retryDelay * 1.25], "the wait carries the jitter")
    }

    @Test func aRecordingThatKeepsFailingGivesWayToTheNextInRankOrder() {
        let result = run(chosen: 0, among: [2, 0, 1], failures: ["0#1", "0#2"])
        #expect(result.loaded?.rank == 1, "rank order, not list order")
        #expect(result.attempts == ["0", "0", "1"])
    }

    @Test func whenEveryRecordingFailsTheErrorIsSurfaced() {
        let result = run(chosen: 0, among: [0, 1], failures: ["0#1", "0#2", "1#1", "1#2"])
        #expect(result.loaded == nil)
        #expect(result.attempts == ["0", "0", "1", "1"], "each recording gets one retry, none more")
    }

    @Test func aLoadThatSucceededEarnsItsNextFailureARetry() {
        let all = [recording(0), recording(1)]
        var plan = LoadRecovery(chosen: all[0], among: all)
        #expect(plan.failed(jitter: 1) == .retry(after: LoadRecovery.retryDelay))
        plan.loaded()
        #expect(plan.failed(jitter: 1) == .retry(after: LoadRecovery.retryDelay), "a seek that fails after playback began is retried too")
    }

    /// iPad 2026-10-30: an item failed (-1008) after a seek to 0.8; a failed item reads 0 s, the
    /// half-second tick took that as the clock, and the retry opened the recording from the start.
    @Test func aFailedItemsZeroClockIsNotWhereTheRetryResumes() {
        var shown = 0.0
        // The fake item: plays from the resume point, the person seeks, then it fails.
        let ticks: [(reading: Double, failed: Bool)] = [(820, false), (821, false), (1400, false), (0, true), (0, true)]
        for tick in ticks { shown = LoadRecovery.clock(reading: tick.reading, itemFailed: tick.failed, shown: shown) }
        #expect(shown == 1400, "the retry opens where the person was")
        // A stall is not a failure: the clock holds and nothing asks the plan for a step.
        shown = LoadRecovery.clock(reading: 1400, itemFailed: false, shown: shown)
        #expect(shown == 1400)
        #expect(LoadRecovery.clock(reading: .nan, itemFailed: false, shown: 1400) == 1400)
    }

    @Test func aLoneRecordingIsRetriedOnceThenGivenUp() {
        let all = [recording(0)]
        var plan = LoadRecovery(chosen: all[0], among: all)
        _ = plan.failed(jitter: 1)
        #expect(plan.failed(jitter: 1) == .giveUp)
    }
}
