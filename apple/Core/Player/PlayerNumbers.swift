import Foundation

/// Decision 062: one set of player numbers on every platform, named once.
/// Android and the web carry the same values under the same names; the
/// design docs quote these (iOS-DESIGN §5.7).
nonisolated enum PlayerNumbers {
    /// The sleep timer fades the volume over its last this-many seconds.
    static let sleepFadeSeconds: TimeInterval = 10
    /// The speed choices, slowest first.
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 2]
    /// The listening position saves this often while playing (and on pause).
    static let saveEverySeconds: TimeInterval = 5
    /// Resuming after an interruption backs up this far, so the last line is heard again.
    static let interruptionRewindSeconds: Double = 3

    static func isSaveDue(lastSaved: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastSaved) >= saveEverySeconds
    }
}
