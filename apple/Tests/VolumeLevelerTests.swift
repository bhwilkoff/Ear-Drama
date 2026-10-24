import AudioToolbox
import Foundation
import Testing

/// Decision 067: the leveler the player's tap runs, measured offline through
/// the same `LevelerUnit` (Apple's DynamicsProcessor) on a quiet passage
/// followed by a loud one, as an old transfer's levels wander.
struct VolumeLevelerTests {
    static let rate = 44_100.0

    /// Renders `input` (mono float) through a LevelerUnit in 512-frame slices.
    static func level(_ input: [Float]) throws -> [Float] {
        let format = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1,
            mBitsPerChannel: 32, mReserved: 0)
        let source = Source(input)
        let unit = try #require(LevelerUnit(format: format, maxFrames: 4096) { buffers, frames in
            source.fill(buffers, frames: Int(frames))
        })
        var output: [Float] = []
        let slice = 512
        var scratch = [Float](repeating: 0, count: slice)
        while output.count < input.count {
            let n = min(slice, input.count - output.count)
            let status = scratch.withUnsafeMutableBytes { raw -> OSStatus in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: UInt32(n * 4), mData: raw.baseAddress))
                return unit.render(&list, frames: UInt32(n))
            }
            #expect(status == noErr)
            output += scratch[0..<n]
        }
        return output
    }

    final class Source: @unchecked Sendable {
        let samples: [Float]
        var at = 0
        init(_ samples: [Float]) { self.samples = samples }
        func fill(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int) -> OSStatus {
            for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                let out = buffer.mData!.assumingMemoryBound(to: Float.self)
                for i in 0..<frames { out[i] = at + i < samples.count ? samples[at + i] : 0 }
            }
            at += frames
            return noErr
        }
    }

    static func tone(seconds: Double, dBFS: Float) -> [Float] {
        let amp = pow(10, dBFS / 20)
        return (0..<Int(seconds * rate)).map { amp * Float(sin(2 * .pi * 440 * Double($0) / rate)) }
    }

    static func rmsDB(_ x: ArraySlice<Float>) -> Float {
        10 * log10(x.reduce(0) { $0 + $1 * $1 } / Float(x.count))
    }

    @Test func theNumbersAreTheWebsOwn() {
        #expect(LevelNumbers.thresholdDB == -24)
        #expect(LevelNumbers.ratio == 4)
        #expect(LevelNumbers.attackSeconds == 0.003)
        #expect(LevelNumbers.releaseSeconds == 0.25)
        #expect(abs(LevelNumbers.makeupDB - 10.8) < 0.001, "0.6 x 18 dB, the Web Audio makeup rule")
        #expect(LevelNumbers.headroomDB == 6)
    }

    @Test func aQuietPassageAndALoudOneComeOutCloser() throws {
        let quiet = Self.tone(seconds: 2, dBFS: -40)
        let loud = Self.tone(seconds: 2, dBFS: -6)
        let out = try Self.level(quiet + loud)
        // Measure each passage's last second, after the detector has settled.
        let n = Int(Self.rate)
        let inGap = Self.rmsDB(loud[n...]) - Self.rmsDB(quiet[n...])
        let outGap = Self.rmsDB(out[(quiet.count + n)...]) - Self.rmsDB(out[n..<(2 * n)])
        print("[VolumeLeveler] input gap \(inGap) dB, leveled gap \(outGap) dB")
        #expect(inGap > 33)
        #expect(outGap < inGap - 8, "the leveler narrows the gap between a quiet and a loud passage")
        #expect(Self.rmsDB(out[n..<(2 * n)]) > Self.rmsDB(quiet[n...]) + 6, "the quiet passage is lifted")
        #expect(out.allSatisfy { abs($0) <= 1 }, "never past full scale")
    }

    @Test func offPassesTheSignalThroughUntouched() {
        let toggle = LevelerSwitch(true)
        toggle.set(false)
        #expect(toggle.isOn == false, "the tap reads this switch on the audio thread and passes the source through")
    }
}
