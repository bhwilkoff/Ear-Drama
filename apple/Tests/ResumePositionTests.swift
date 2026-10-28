import Foundation
import Testing

/// Before 1.0.73 a VBR MP3 with no Xing/VBRI table had its length misread
/// (Gang Busters 1954-08-02 as about an hour for 23:42), so places were saved
/// past the real end. Resuming at one would land on silence.
@MainActor struct ResumePositionTests {
    private func history() -> ListeningHistory {
        let defaults = UserDefaults(suiteName: "ResumePositionTests-\(UUID().uuidString)")!
        return ListeningHistory(defaults: defaults)
    }

    @Test func aPlaceInsideTheRecordingResumes() {
        let h = history()
        h.record("g|1", position: 600, duration: nil)
        #expect(h.resumePosition(for: "g|1", length: 1421.6) == 600)
    }

    @Test func aPlacePastTheRecordingStartsOver() {
        let h = history()
        h.record("g|1", position: 2069, duration: nil)
        #expect(h.resumePosition(for: "g|1", length: 1421.6) == nil)
    }

    @Test func withNoKnownLengthTheSavedPlaceStands() {
        let h = history()
        h.record("g|1", position: 2069, duration: nil)
        #expect(h.resumePosition(for: "g|1") == 2069)
    }
}
