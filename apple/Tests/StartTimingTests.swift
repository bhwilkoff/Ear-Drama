import Foundation
import Testing

/// A network recording opens without precise timing (which reads the whole file before the first
/// sound) and is reopened with it only when its first frames vary with no Xing/Info/VBRI table.
/// Frame shapes measured 2026-11-14 on real archive.org files.
struct StartTimingTests {
    /// One MPEG-1 layer III frame at 44.1 kHz with bitrate index `index` (5 = 64 kbps, 9 = 128).
    private func frame(_ index: UInt8, tag: String? = nil) -> [UInt8] {
        let kbps = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320][Int(index)]
        var bytes = [UInt8](repeating: 0, count: 144 * kbps * 1000 / 44100)
        bytes[0] = 0xFF
        bytes[1] = 0xFB
        bytes[2] = index << 4
        bytes[3] = 0x44
        if let tag { bytes.replaceSubrange(36..<40, with: Array(tag.utf8)) }
        return bytes
    }

    private func id3(size: Int) -> [UInt8] {
        let s = [UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F), UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F)]
        return [0x49, 0x44, 0x33, 4, 0, 0] + s + [UInt8](repeating: 0, count: size)
    }

    @Test func aConstantBitrateFileIsConstant() {
        // Gunsmoke 1960-12-11: 309 frames, every one 64 kbps, no table.
        let bytes = (0..<40).flatMap { _ in frame(5) }
        #expect(StartTiming.frames(in: bytes) == .constant)
    }

    @Test func varyingFramesWithNoTableAreVariable() {
        // Challenge of the Yukon 1949-12-09: 64, 80, 56, 96 and 48 kbps frames, no table.
        let bytes = (0..<40).flatMap { i in frame([5, 6, 4, 7, 3][i % 5]) }
        #expect(StartTiming.frames(in: bytes) == .variable)
    }

    @Test func aTableInTheFirstFrameIsATable() {
        // Breakfast Club 1960-09-06: a Xing table, then varying frames; Family Theater: LAME's Info.
        #expect(StartTiming.frames(in: frame(5, tag: "Xing") + (0..<40).flatMap { i in frame([5, 6][i % 2]) }) == .table)
        #expect(StartTiming.frames(in: frame(7, tag: "Info") + (0..<40).flatMap { _ in frame(7) }) == .table)
        #expect(StartTiming.frames(in: frame(7, tag: "VBRI") + (0..<40).flatMap { _ in frame(7) }) == .table)
    }

    @Test func tooFewFramesOrNotMP3IsUnknown() {
        #expect(StartTiming.frames(in: (0..<3).flatMap { _ in frame(5) }) == .unknown)
        #expect(StartTiming.frames(in: [UInt8](repeating: 0x20, count: 4000)) == .unknown)
        #expect(StartTiming.frames(in: []) == .unknown)
    }

    @Test func framesAreFoundPastAnID3Tag() {
        let tagged = id3(size: 1000) + (0..<40).flatMap { i in frame([5, 6][i % 2]) }
        #expect(StartTiming.tagEnd(tagged) == 1010)
        #expect(StartTiming.frames(in: tagged, from: 1010) == .variable)
        #expect(StartTiming.tagEnd(frame(5)) == nil)
    }

    @Test func onlyAVariableFileWithNoTableNeedsPrecise() {
        #expect(StartTiming.needsPrecise(.variable, estimated: 1956, catalog: 1956), "the catalog length is the same estimate")
        #expect(!StartTiming.needsPrecise(.constant, estimated: 1423, catalog: 1422.54))
        #expect(!StartTiming.needsPrecise(.table, estimated: 1755, catalog: 1755.27))
        #expect(!StartTiming.needsPrecise(.unknown, estimated: 1049, catalog: 1000), "unknown: within 5% stands")
        #expect(StartTiming.needsPrecise(.unknown, estimated: 1051, catalog: 1000), "unknown: past 5% is a misread")
        #expect(StartTiming.needsPrecise(.unknown, estimated: .nan, catalog: 1000))
        #expect(!StartTiming.needsPrecise(.unknown, estimated: 3600, catalog: nil), "nothing to check against")
    }

    @Test func theSniffReadsPastATagTooBigForTheHead() async {
        // Stolen Symphony: a 284 KB tag (pictures) before the first frame.
        let tagSize = 284_000
        let file = id3(size: tagSize) + (0..<80).flatMap { i in frame([9, 10][i % 2]) }
        let reads = Reads()
        let frames = await StartTiming.sniff(URL(string: "https://archive.org/download/a/b.mp3")!) { _, range in
            await reads.add(range)
            let upper = min(range.upperBound, file.count - 1)
            return range.lowerBound <= upper ? Data(file[range.lowerBound...upper]) : Data()
        }
        #expect(frames == .variable)
        let seen = await reads.ranges
        #expect(seen == [0...65_535, (tagSize + 10)...(tagSize + 10 + 32_767)])
        let failed = await StartTiming.sniff(URL(string: "https://archive.org/download/a/b.mp3")!) { _, _ in nil }
        #expect(failed == .unknown, "no bytes: unknown, so the catalog length decides")
    }

    private actor Reads {
        var ranges: [ClosedRange<Int>] = []
        func add(_ r: ClosedRange<Int>) { ranges.append(r) }
    }
}
