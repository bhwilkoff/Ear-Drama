import Foundation
import Testing

// resilient-media-streaming: a load that wants data, receives no new bytes, and does not move for
// 30 s is a failed load. An iPad sat at AVPlayerItem status 0 for minutes, with no error. A slow
// load that is still receiving bytes (23 s for a headerless VBR MP3) is never killed.

struct StallWatchdogTests {
    /// A fake loader: bytes and position as a function of the fake clock; the watch looks every 0.5 s.
    private func firstStall(until end: Double, wantsData: (Double) -> Bool = { _ in true },
                            bytes: (Double) -> Double, position: (Double) -> Double = { _ in 0 }) -> Double? {
        var watch = StallWatchdog()
        var t = 0.0
        while t <= end {
            if watch.observe(now: t, wantsData: wantsData(t), bytes: bytes(t), position: position(t)) == .stalled { return t }
            t += 0.5
        }
        return nil
    }

    @Test func noBytesFor30SecondsWhileWaitingIsAStall() {
        let at = firstStall(until: 60, bytes: { _ in 0 })
        #expect(at == 30)
    }

    @Test func aSlowTrickleOfBytesIsNeverAStall() {
        #expect(firstStall(until: 3600, bytes: { floor($0 / 20) * 1024 }) == nil)
    }

    @Test func aMovingPositionIsNeverAStall() {
        #expect(firstStall(until: 600, bytes: { _ in 5 }, position: { $0 }) == nil)
    }

    @Test func aPauseIsNeverAStall() {
        #expect(firstStall(until: 3600, wantsData: { _ in false }, bytes: { _ in 0 }) == nil)
    }

    @Test func aPauseThenPlayStartsTheCountAgain() {
        // Paused for 100 s, then waiting with no bytes: 30 s after the play, not after the load.
        let at = firstStall(until: 200, wantsData: { $0 >= 100 }, bytes: { _ in 0 })
        #expect(at == 130)
    }

    @Test func resetStartsTheCountAgain() {
        var watch = StallWatchdog()
        _ = watch.observe(now: 0, wantsData: true, bytes: 0, position: 0)
        watch.reset()
        #expect(watch.observe(now: 40, wantsData: true, bytes: 0, position: 0) == .ok)
        #expect(watch.observe(now: 70, wantsData: true, bytes: 0, position: 0) == .stalled)
    }
}
