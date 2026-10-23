import Foundation

/// The mix as plain data (PLAYS-DESIGN §4.2): lines in script order, each a
/// chosen human take with its in and out points, a gap before it, and a stored
/// gain. Placement is relative, so a longer re-take ripples every later line.
/// A partial play has no timeline at all: it is never mixed into a file (§5
/// rule 3), and nothing but a take can be placed, so a stand-in cannot be.
nonisolated struct MixTimeline: Equatable, Sendable {
    struct Placement: Equatable, Sendable {
        let lineID: String
        let takeID: String
        let file: String
        let start: Int
        let inFrame: Int
        let outFrame: Int
        let gain: Float
        var frames: Int { outFrame - inFrame }
    }

    enum Failure: Error, Equatable {
        case incomplete(missing: [String])
        case sampleRate(String)
    }

    let sampleRate: Double
    let placements: [Placement]
    let totalFrames: Int

    static let target: Double = -16
    static let peakCeiling: Double = -1
    static let defaultGap = 0.4

    static func build(script: PlayScript, production: Production, sampleRate: Double = 48_000,
                      gap: Double = defaultGap) throws(Failure) -> MixTimeline {
        let missing = Relay.missingSpeech(production, script)
        guard missing.isEmpty else { throw .incomplete(missing: missing) }
        var placements: [Placement] = []
        var cursor = 0
        let gapFrames = Int(gap * sampleRate)
        for line in script.lines {
            guard let take = production.chosenTake(for: line.id) else { continue }
            guard take.sampleRate == sampleRate else { throw .sampleRate(take.id) }
            let start = placements.isEmpty ? 0 : cursor + gapFrames
            placements.append(Placement(lineID: line.id, takeID: take.id, file: take.file, start: start,
                                        inFrame: 0, outFrame: take.frames,
                                        gain: gain(loudness: take.loudness, peak: take.peak)))
            cursor = start + take.frames
        }
        return MixTimeline(sampleRate: sampleRate, placements: placements, totalFrames: cursor)
    }

    /// The linear gain that brings a take to -16 LUFS, held so its peak stays at
    /// or below -1 dBFS (sample peak stands in for true peak) and within +-24 dB.
    /// An unmeasured or silent take plays at unity.
    static func gain(loudness: Double?, peak: Float) -> Float {
        guard let loudness, loudness.isFinite else { return 1 }
        var db = target - loudness
        if peak > 0 { db = min(db, peakCeiling - 20 * log10(Double(peak))) }
        db = min(max(db, -24), 24)
        return Float(pow(10, db / 20))
    }
}
