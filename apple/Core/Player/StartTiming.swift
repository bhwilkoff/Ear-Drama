import Foundation

/// How a network recording opens (2026-11-14). `AVURLAssetPreferPreciseDurationAndTimingKey` makes
/// AVFoundation read a whole MP3 before the first sound: measured on a Mac, 1.2 s to 44 s to first
/// audio (a 70 MB file), with the player "playing" and its clock frozen meanwhile, against 0.6 to
/// 2.2 s without it. Without it, a constant-bitrate file or one with a Xing/Info/VBRI table is still
/// timed exactly; only a variable-bitrate file with no table is misread. The catalog length cannot
/// tell those apart (for such a file it is the same bitrate estimate: Challenge of the Yukon
/// 1949-12-09 is listed at 1956 s and decodes to 1757 s). The frame headers can: the player reads
/// the file's first 64 KB alongside the load, and only a file whose frames vary with no table is
/// reopened with precise timing, at the same place.
nonisolated enum StartTiming {
    /// What a file's first frames say about its timing.
    enum Frames: Equatable, Sendable {
        /// The first frame carries a Xing, Info, or VBRI table: timed exactly from it.
        case table
        /// Every frame read has one bitrate: constant, timed exactly by arithmetic.
        case constant
        /// Bitrates vary and there is no table: only a full read times it.
        case variable
        /// Not readable as MPEG-1/2 layer III (another format, or the bytes did not come).
        case unknown
    }

    /// The bytes read from the head of a file.
    static let headBytes = 65_536
    /// The bytes read past an ID3 tag too big for the head (a tag may carry pictures).
    static let pastTagBytes = 32_768
    /// Fewer frames than this say nothing about the bitrate.
    static let minimumFrames = 8
    /// With no frame verdict: the quick estimate and the catalog length disagree by more than this.
    static let disagreeShare = 0.05

    /// Whether the file opens again with precise timing.
    static func needsPrecise(_ frames: Frames, estimated: Double, catalog: Double?) -> Bool {
        switch frames {
        case .variable: true
        case .table, .constant: false
        case .unknown: disagrees(estimated: estimated, catalog: catalog)
        }
    }

    /// The fallback: AVFoundation's quick duration against the catalog's length.
    static func disagrees(estimated: Double, catalog: Double?) -> Bool {
        guard let catalog, catalog > 0 else { return false }
        guard estimated.isFinite, estimated > 0 else { return true }
        return abs(estimated - catalog) > catalog * disagreeShare
    }

    /// The end of an ID3v2 tag at the start of `bytes`, or nil when there is none.
    static func tagEnd(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else { return nil }
        let size = Int(bytes[6] & 0x7F) << 21 | Int(bytes[7] & 0x7F) << 14 | Int(bytes[8] & 0x7F) << 7 | Int(bytes[9] & 0x7F)
        let footer = bytes[5] & 0x10 != 0 ? 10 : 0
        return 10 + size + footer
    }

    /// Walks the MPEG audio frames from the first sync at or after `start`.
    static func frames(in bytes: [UInt8], from start: Int = 0) -> Frames {
        var offset = start
        var rates: [Int] = []
        var table = false
        while offset + 4 <= bytes.count {
            guard let frame = header(bytes, at: offset) else {
                if rates.isEmpty {
                    offset += 1
                    continue
                }
                break
            }
            if rates.isEmpty {
                let end = min(bytes.count, offset + frame.length)
                table = contains(bytes, "Xing", in: offset..<end) || contains(bytes, "Info", in: offset..<end)
                    || contains(bytes, "VBRI", in: offset..<end)
                if table { return .table }
            }
            guard offset + frame.length <= bytes.count else { break }
            rates.append(frame.kbps)
            offset += frame.length
        }
        guard rates.count >= minimumFrames else { return .unknown }
        return Set(rates).count == 1 ? .constant : .variable
    }

    /// Reads the head of `url` (and past a large tag) and says what its frames are.
    static func sniff(_ url: URL, read: (URL, ClosedRange<Int>) async -> Data?) async -> Frames {
        guard let head = await read(url, 0...(headBytes - 1)) else { return .unknown }
        let bytes = [UInt8](head)
        guard let end = tagEnd(bytes) else { return frames(in: bytes) }
        if end + 4096 <= bytes.count { return frames(in: bytes, from: end) }
        guard let past = await read(url, end...(end + pastTagBytes - 1)) else { return .unknown }
        return frames(in: [UInt8](past))
    }

    private static let layer3Kbps: [[Int]] = [
        [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],   // MPEG-1
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],       // MPEG-2 and 2.5
    ]
    private static let sampleRates: [Int: [Int]] = [3: [44100, 48000, 32000], 2: [22050, 24000, 16000], 0: [11025, 12000, 8000]]

    /// A layer III frame header at `offset`: its bitrate and length, or nil.
    private static func header(_ b: [UInt8], at offset: Int) -> (kbps: Int, length: Int)? {
        guard b[offset] == 0xFF, b[offset + 1] & 0xE0 == 0xE0 else { return nil }
        let version = Int(b[offset + 1] >> 3) & 3
        let layer = Int(b[offset + 1] >> 1) & 3
        let rateIndex = Int(b[offset + 2] >> 4)
        let sampleIndex = Int(b[offset + 2] >> 2) & 3
        let padding = Int(b[offset + 2] >> 1) & 1
        guard version != 1, layer == 1, rateIndex != 0, rateIndex != 15, sampleIndex != 3,
              let rates = sampleRates[version] else { return nil }
        let kbps = layer3Kbps[version == 3 ? 0 : 1][rateIndex]
        let length = (version == 3 ? 144 : 72) * kbps * 1000 / rates[sampleIndex] + padding
        return length > 4 ? (kbps, length) : nil
    }

    private static func contains(_ b: [UInt8], _ word: String, in range: Range<Int>) -> Bool {
        let w = Array(word.utf8)
        guard range.count >= w.count else { return false }
        for i in range.lowerBound...(range.upperBound - w.count) where b[i] == w[0] {
            if Array(b[i..<(i + w.count)]) == w { return true }
        }
        return false
    }
}
