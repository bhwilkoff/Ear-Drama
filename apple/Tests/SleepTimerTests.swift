import Foundation
import Testing

/// R20 as a state machine: End of this episode first, a fade over the last
/// seconds, and never the next episode once it has fired.
struct SleepTimerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// True when the timer lowers the volume in its final seconds and is at
    /// full volume before them. Used on the real timer and on a broken one.
    private func fadeHolds(_ timer: SleepTimer) -> Bool {
        var early = timer, late = timer
        let full = early.tick(now: t0, remainingInEpisode: 60).volume
        let fading = late.tick(now: t0, remainingInEpisode: 5).volume
        return full == 1 && fading > 0 && fading < 1
    }

    @Test func endOfEpisodeIsOfferedFirst() {
        #expect(SleepTimer.options.first == .endOfEpisode)
        #expect(SleepTimer.options.first?.title == "End of this episode")
        #expect(SleepTimer.options.dropFirst().allSatisfy { if case .minutes = $0 { true } else { false } })
    }

    @Test func offNeverTouchesPlayback() {
        var timer = SleepTimer()
        let r1 = timer.tick(now: t0, remainingInEpisode: 2)
        #expect(r1 == .init(volume: 1, shouldPause: false))
        let r2 = timer.episodeDidEnd()
        #expect(r2)
        #expect(!timer.isActive)
    }

    @Test func endOfEpisodeFadesThenRefusesTheNextEpisode() {
        var timer = SleepTimer()
        timer.set(.endOfEpisode, now: t0)
        #expect(timer.isActive)
        let r3 = timer.tick(now: t0, remainingInEpisode: 600)
        #expect(r3.volume == 1)
        let r4 = timer.tick(now: t0, remainingInEpisode: 5)
        #expect(r4.volume == 0.5)
        let r5 = timer.tick(now: t0, remainingInEpisode: 0)
        #expect(r5.volume == 0)
        #expect(fadeHolds(timer))
        // The episode ends: the queue must NOT advance, now or later.
        let r6 = timer.episodeDidEnd()
        #expect(r6 == false)
        #expect(timer.mode == .fired)
        let r7 = timer.episodeDidEnd()
        #expect(r7 == false)
        let r8 = timer.tick(now: t0, remainingInEpisode: 1800)
        #expect(r8.shouldPause == false)
    }

    @Test func durationFadesPausesOnceAndRefusesTheNextEpisode() {
        var timer = SleepTimer()
        timer.set(.minutes(15), now: t0)
        let r9 = timer.tick(now: t0.addingTimeInterval(60), remainingInEpisode: 30)
        #expect(r9 == .init(volume: 1, shouldPause: false))
        // An episode that ends BEFORE the deadline may hand on to the next.
        let r10 = timer.episodeDidEnd()
        #expect(r10)
        #expect(timer.isActive)
        let fading = timer.tick(now: t0.addingTimeInterval(15 * 60 - 5), remainingInEpisode: 900)
        #expect(fading.volume == 0.5 && !fading.shouldPause)
        let fired = timer.tick(now: t0.addingTimeInterval(15 * 60), remainingInEpisode: 895)
        #expect(fired.shouldPause && fired.volume == 0)
        #expect(timer.mode == .fired)
        // Fired: it pauses exactly once, and nothing starts afterward.
        let r11 = timer.tick(now: t0.addingTimeInterval(15 * 60 + 1), remainingInEpisode: 894)
        #expect(r11.shouldPause == false)
        let r12 = timer.episodeDidEnd()
        #expect(r12 == false)
    }

    @Test func cancelRestoresNormalPlayback() {
        var timer = SleepTimer()
        timer.set(.endOfEpisode, now: t0)
        _ = timer.episodeDidEnd()
        timer.cancel()
        #expect(timer.mode == .off)
        let r13 = timer.episodeDidEnd()
        #expect(r13)
        let r14 = timer.tick(now: t0, remainingInEpisode: 3)
        #expect(r14.volume == 1)
    }

    @Test func labelsCountDown() {
        var timer = SleepTimer()
        #expect(timer.label(now: t0) == nil)
        timer.set(.minutes(30), now: t0)
        #expect(timer.label(now: t0.addingTimeInterval(60)) == "29:00")
        timer.set(.endOfEpisode, now: t0)
        #expect(timer.label(now: t0) == "End of episode")
    }

    /// Negative control: the fade check must be able to fail. A timer with no
    /// fade window stops dead, and `fadeHolds` has to say so.
    @Test func controlFadeCheckCatchesAMissingFade() {
        var broken = SleepTimer()
        broken.fadeSeconds = 0
        broken.set(.endOfEpisode, now: t0)
        #expect(fadeHolds(broken) == false)
        var real = SleepTimer()
        real.set(.endOfEpisode, now: t0)
        #expect(fadeHolds(real))
    }
}

struct ListeningHistoryTests {
    private func makeDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func resumesWithARewindAndForgetsFinished() {
        let defaults = makeDefaults()
        let history = ListeningHistory(defaults: defaults)
        history.record("a|1", position: 10, duration: 1800)
        #expect(history.resumePosition(for: "a|1") == nil)          // under the threshold
        history.record("a|1", position: 600, duration: 1800)
        #expect(history.resumePosition(for: "a|1") == 597)
        #expect(history.inProgressIDs == ["a|1"])
        history.record("a|1", position: 1790, duration: 1800)
        #expect(history.entry(for: "a|1")?.finished == true)
        #expect(history.resumePosition(for: "a|1") == nil)
        #expect(history.inProgressIDs.isEmpty)
        // Persisted across launches.
        history.record("b|2", position: 300, duration: 1800)
        #expect(ListeningHistory(defaults: defaults).resumePosition(for: "b|2") == 297)
    }
}
