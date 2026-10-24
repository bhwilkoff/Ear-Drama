import AVFoundation
import AudioToolbox
import MediaToolbox
import Synchronization

/// Decision 067: volume is leveled on the device as it plays, never from a
/// per-file measurement. One set of numbers on every platform (the web's
/// `Player.LEVEL`, Android's `LevelNumbers`), so a listener moving between
/// them hears the same evenness.
nonisolated enum LevelNumbers {
    static let thresholdDB: Float = -24
    static let ratio: Float = 4
    static let attackSeconds: Float = 0.003
    static let releaseSeconds: Float = 0.25
    /// The Web Audio rule the browser applies on its own: 0.6 x the
    /// compression at 0 dBFS, here 0.6 x 18 = 10.8 dB.
    static var makeupDB: Float { 0.6 * -thresholdDB * (1 - 1 / ratio) }
    /// Apple's DynamicsProcessor states compression as headroom, the room
    /// left above the threshold for a full-scale input: 24 dB / 4 = 6 dB.
    static var headroomDB: Float { -thresholdDB / ratio }
}

/// The person's switch, read on the audio thread by every tap.
nonisolated final class LevelerSwitch: Sendable {
    private let on: Atomic<Bool>
    init(_ value: Bool) { on = Atomic(value) }
    var isOn: Bool { on.load(ordering: .relaxed) }
    func set(_ value: Bool) { on.store(value, ordering: .relaxed) }
}

/// Apple's DynamicsProcessor audio unit set to `LevelNumbers`, pulling its
/// input through `pull`. The player's tap and the offline test share it, so
/// the test measures the unit the listener hears.
nonisolated final class LevelerUnit: @unchecked Sendable {
    typealias Pull = (UnsafeMutablePointer<AudioBufferList>, UInt32) -> OSStatus

    private(set) var unit: AudioUnit?
    private let pull: Pull
    private var sampleTime: Float64 = 0

    init?(format: AudioStreamBasicDescription, maxFrames: UInt32, pull: @escaping Pull) {
        self.pull = pull
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: kAudioUnitSubType_DynamicsProcessor,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &desc) else { return nil }
        var made: AudioUnit?
        guard AudioComponentInstanceNew(component, &made) == noErr, let unit = made else { return nil }
        self.unit = unit
        var asbd = format
        let size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var frames = maxFrames
        var callback = AURenderCallbackStruct(inputProc: { refCon, _, _, _, frames, data in
            guard let data else { return kAudio_ParamError }
            let me = Unmanaged<LevelerUnit>.fromOpaque(refCon).takeUnretainedValue()
            return me.pull(data, frames)
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        let ok = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd, size) == noErr
            && AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &asbd, size) == noErr
            && AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                                    &frames, UInt32(MemoryLayout<UInt32>.size)) == noErr
            && AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                                    &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr
            && AudioUnitInitialize(unit) == noErr
        guard ok else {
            AudioComponentInstanceDispose(unit)
            self.unit = nil
            return nil
        }
        let set = { (id: AudioUnitParameterID, value: Float) in
            AudioUnitSetParameter(unit, id, kAudioUnitScope_Global, 0, value, 0)
        }
        _ = set(kDynamicsProcessorParam_Threshold, LevelNumbers.thresholdDB)
        _ = set(kDynamicsProcessorParam_HeadRoom, LevelNumbers.headroomDB)
        _ = set(kDynamicsProcessorParam_AttackTime, LevelNumbers.attackSeconds)
        _ = set(kDynamicsProcessorParam_ReleaseTime, LevelNumbers.releaseSeconds)
        _ = set(kDynamicsProcessorParam_OverallGain, LevelNumbers.makeupDB)
    }

    /// Renders `frames` into `buffers`, then holds every float sample inside
    /// full scale: an onset the attack has not yet caught is clipped by the
    /// makeup gain only for those few milliseconds.
    func render(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: UInt32) -> OSStatus {
        guard let unit else { return kAudioUnitErr_Uninitialized }
        var flags = AudioUnitRenderActionFlags()
        var stamp = AudioTimeStamp()
        stamp.mFlags = .sampleTimeValid
        stamp.mSampleTime = sampleTime
        sampleTime += Float64(frames)
        let status = AudioUnitRender(unit, &flags, &stamp, 0, frames, buffers)
        guard status == noErr else { return status }
        for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            for i in 0..<Int(buffer.mDataByteSize) / MemoryLayout<Float>.size {
                samples[i] = min(1, max(-1, samples[i]))
            }
        }
        return noErr
    }

    deinit {
        if let unit {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
    }
}

/// The player's tap: an `MTAudioProcessingTap` on the item's audio track runs
/// each buffer through a `LevelerUnit` while the switch is on, and passes it
/// through untouched while it is off (research 04 §2.11). Streamed
/// progressive MP3, local downloads, and AirPlay audio all pass the tap.
nonisolated enum VolumeLeveler {
    private final class Context: @unchecked Sendable {
        let toggle: LevelerSwitch
        var unit: LevelerUnit?
        init(toggle: LevelerSwitch) { self.toggle = toggle }
    }

    /// An audio mix that levels `track`, or nil when the tap cannot be made
    /// (the item then plays unleveled, as before).
    static func mix(for track: AVAssetTrack, toggle: LevelerSwitch) -> AVAudioMix? {
        let context = Context(toggle: toggle)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque()),
            init: nil, finalize: nil, prepare: nil, unprepare: nil, process: { _, _, _, _, _, _ in })
        callbacks.`init` = { _, clientInfo, storageOut in
            storageOut.pointee = clientInfo
        }
        callbacks.finalize = { tap in
            Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
        }
        callbacks.prepare = { tap, maxFrames, format in
            let context = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            let floats = format.pointee.mFormatID == kAudioFormatLinearPCM
                && format.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
                && format.pointee.mBitsPerChannel == 32
            guard floats else {
                print("[VolumeLeveler] not float PCM; this item plays unleveled")
                return
            }
            context.unit = LevelerUnit(format: format.pointee, maxFrames: UInt32(maxFrames)) { buffers, frames in
                var got: CMItemCount = 0
                return MTAudioProcessingTapGetSourceAudio(tap, CMItemCount(frames), buffers, nil, nil, &got)
            }
            if context.unit == nil { print("[VolumeLeveler] the dynamics unit did not start; unleveled") }
        }
        callbacks.unprepare = { tap in
            Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().unit = nil
        }
        callbacks.process = { tap, frames, _, buffers, framesOut, flagsOut in
            let context = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            if context.toggle.isOn, let unit = context.unit,
               unit.render(buffers, frames: UInt32(frames)) == noErr {
                framesOut.pointee = frames
                return
            }
            _ = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut)
        }
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                         kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
              let tap else {
            Unmanaged<Context>.fromOpaque(callbacks.clientInfo!).release()
            return nil
        }
        let input = AVMutableAudioMixInputParameters(track: track)
        input.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [input]
        return mix
    }
}
