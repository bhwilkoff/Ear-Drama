import Accelerate
import Foundation

/// ITU-R BS.1770 integrated loudness of a mono signal: K-weighting (the
/// libebur128 filter design, valid at any sample rate), 400 ms blocks every
/// 100 ms, the -70 LUFS absolute gate and the -10 LU relative gate.
nonisolated enum BS1770 {
    static func integratedLoudness(_ samples: [Float], sampleRate: Double) -> Double? {
        let weighted = kWeighted(samples, sampleRate: sampleRate)
        let block = Int(sampleRate * 0.4), hop = Int(sampleRate * 0.1)
        guard weighted.count >= block, block > 0 else { return nil }
        var powers: [Double] = []
        var start = 0
        while start + block <= weighted.count {
            var sum = 0.0
            for i in start..<(start + block) { sum += weighted[i] * weighted[i] }
            powers.append(sum / Double(block))
            start += hop
        }
        let loud = { (z: Double) in -0.691 + 10 * log10(z) }
        let absolute = powers.filter { $0 > 0 && loud($0) > -70 }
        guard !absolute.isEmpty else { return nil }
        let relative = loud(absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = absolute.filter { loud($0) > relative }
        guard !gated.isEmpty else { return nil }
        return loud(gated.reduce(0, +) / Double(gated.count))
    }

    static func samplePeak(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return vDSP.maximumMagnitude(samples)
    }

    private static func kWeighted(_ x: [Float], sampleRate fs: Double) -> [Double] {
        // Stage 1: the head's high shelf.
        var k = tan(.pi * 1681.974450955533 / fs)
        let vh = pow(10, 3.999843853973347 / 20), vb = pow(vh, 0.4996667741545416)
        var q = 0.7071752369554196
        var a0 = 1 + k / q + k * k
        let s1b = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0]
        let s1a = [2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
        // Stage 2: the RLB high-pass.
        k = tan(.pi * 38.13547087602444 / fs)
        q = 0.5003270373238773
        a0 = 1 + k / q + k * k
        let s2b = [1.0, -2.0, 1.0]
        let s2a = [2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
        return biquad(biquad(x.map(Double.init), s1b, s1a), s2b, s2a)
    }

    private static func biquad(_ x: [Double], _ b: [Double], _ a: [Double]) -> [Double] {
        var y = [Double](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in x.indices {
            let out = b[0] * x[i] + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = out
            y[i] = out
        }
        return y
    }
}

/// The bleed check (PLAYS-DESIGN §5 rule 2): how strongly a known signal (the
/// stand-in that played) appears inside another (a microphone window). The
/// peak normalized cross-correlation over every lag, on an 8 kHz copy of both.
/// 1 is the reference itself; unrelated audio stays near 0.
nonisolated enum BleedCheck {
    /// UNVERIFIED: research 08a "To measure" 4 sets the real threshold on devices.
    static let threshold: Float = 0.5

    static func score(signal: [Float], reference: [Float], sampleRate: Double) -> Float {
        let factor = max(1, Int(sampleRate / 8000))
        let s = decimate(signal, by: factor), r = decimate(reference, by: factor)
        guard !r.isEmpty, !s.isEmpty else { return 0 }
        // Slide the shorter across the longer, zero-padded so a partial overlap counts.
        let (long, short) = s.count >= r.count ? (s, r) : (r, s)
        let shortNorm = sqrt(vDSP.sumOfSquares(short))
        guard shortNorm > 1e-6 else { return 0 }
        let pad = [Float](repeating: 0, count: short.count - 1)
        let padded = pad + long + pad
        let lags = padded.count - short.count + 1
        var products = [Float](repeating: 0, count: lags)
        padded.withUnsafeBufferPointer { p in
            short.withUnsafeBufferPointer { k in
                vDSP_conv(p.baseAddress!, 1, k.baseAddress!, 1, &products, 1, vDSP_Length(lags), vDSP_Length(short.count))
            }
        }
        // The energy of each window of the long signal, by a running sum.
        let squares = padded.map { $0 * $0 }
        var window = squares[0..<short.count].reduce(0, +)
        var best: Float = 0
        for lag in 0..<lags {
            if lag > 0 { window += squares[lag + short.count - 1] - squares[lag - 1] }
            // A window that holds a sliver of the signal cannot vouch for a match.
            guard window > shortNorm * shortNorm * 0.05 else { continue }
            best = max(best, abs(products[lag]) / (shortNorm * sqrt(max(window, 1e-12))))
        }
        return min(best, 1)
    }

    private static func decimate(_ x: [Float], by factor: Int) -> [Float] {
        guard factor > 1 else { return x }
        let n = x.count / factor
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var sum: Float = 0
            for j in 0..<factor { sum += x[i * factor + j] }
            out[i] = sum / Float(factor)
        }
        return out
    }
}

/// Voice detection that ends a take (PLAYS-DESIGN §2.4, research 08a §5.1): an
/// energy detector on 20 ms frames, its floor from the session's room tone.
/// "Wait for me": it waits for the performer however long they take to begin.
nonisolated struct LineEndDetector {
    enum Event: Equatable { case onset(frame: Int), end(frame: Int) }

    let sampleRate: Double
    let threshold: Float
    let trailingSilence: Double
    private(set) var onset: Int?
    private(set) var end: Int?
    private var position = 0
    private var loudRun = 0
    private var lastLoud = 0
    private var pending: [Float] = []

    static let minimumThreshold: Float = 0.003  // about -50 dBFS RMS

    init(sampleRate: Double, roomToneRMS: Float, trailingSilence: Double = 1.0) {
        self.sampleRate = sampleRate
        threshold = max(Self.minimumThreshold, roomToneRMS * 4)
        self.trailingSilence = trailingSilence
    }

    private var frameLength: Int { Int(sampleRate * 0.02) }

    mutating func feed(_ samples: [Float]) -> Event? {
        pending += samples
        var event: Event?
        while pending.count >= frameLength, end == nil {
            let frame = Array(pending.prefix(frameLength))
            pending.removeFirst(frameLength)
            let rms = sqrt(vDSP.meanSquare(frame))
            if rms >= threshold {
                loudRun += 1
                lastLoud = position + frameLength
                if onset == nil, loudRun >= 3 {
                    onset = position - 2 * frameLength
                    event = .onset(frame: onset!)
                }
            } else {
                loudRun = 0
            }
            position += frameLength
            if onset != nil, Double(position - lastLoud) >= trailingSilence * sampleRate {
                end = lastLoud
                event = .end(frame: lastLoud)
            }
        }
        return event
    }

    /// The kept window: from onset less 250 ms to the end plus 250 ms (§4.2).
    /// Without a detected onset the whole capture is kept.
    static func window(onset: Int?, end: Int?, total: Int, sampleRate: Double) -> Range<Int> {
        guard let onset else { return 0..<total }
        let handle = Int(sampleRate * 0.25)
        let lower = max(0, onset - handle)
        let upper = min(total, (end ?? total) + handle)
        return lower..<max(lower, upper)
    }

    static func rms(_ samples: [Float]) -> Float {
        samples.isEmpty ? 0 : sqrt(vDSP.meanSquare(samples))
    }
}
