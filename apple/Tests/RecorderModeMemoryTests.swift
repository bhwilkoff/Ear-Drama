import Foundation
import Testing

// The recorder opens in Run through, then remembers the last mode on this device.

struct RecorderModeMemoryTests {
    private func fresh() -> UserDefaults {
        let name = "RecorderModeMemoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func runThroughFirstThenTheLastModePicked() {
        let defaults = fresh()
        #expect(RecordingSession.Mode.remembered(in: defaults) == .run)
        RecordingSession.Mode.lines.remember(in: defaults)
        #expect(RecordingSession.Mode.remembered(in: defaults) == .lines)
        RecordingSession.Mode.step.remember(in: defaults)
        #expect(RecordingSession.Mode.remembered(in: defaults) == .step)
    }

    @Test func aWordThatIsNoModeFallsBackToRunThrough() {
        let defaults = fresh()
        defaults.set("nonsense", forKey: RecordingSession.Mode.key)
        #expect(RecordingSession.Mode.remembered(in: defaults) == .run)
    }
}
