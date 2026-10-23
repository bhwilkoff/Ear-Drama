import Foundation

/// DECISIONS 061: play at -21 LUFS, reached by cutting. A volume factor in
/// (0, 1]: the gain is -21 - I, clamped so the true peak stays at or below
/// -1 dBTP, and never above 0 dB (AVPlayer cannot boost). Unmeasured plays at 1.
/// The same numbers as the web's `API.playbackVolume` (js/api.js).
nonisolated enum LoudnessLevel {
    static let target: Double = -21

    static func volume(i: Double?, tp: Double?) -> Float {
        guard let i, i.isFinite else { return 1 }
        var gain = target - i
        if let tp, tp.isFinite { gain = min(gain, -1 - tp) }
        gain = min(gain, 0)
        return Float(pow(10, gain / 20))
    }

    /// The measurement belongs to the default (rank 0) copy only; any other
    /// version plays at unity.
    static func volume(for episode: EpisodeRow, recording: Recording) -> Float {
        recording.rank == 0 ? volume(i: episode.loudnessI, tp: episode.loudnessTP) : 1
    }
}
