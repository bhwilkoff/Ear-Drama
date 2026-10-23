#if os(iOS) || os(macOS)
import AVFoundation
import Foundation
#if os(macOS)
import CoreAudio
#endif

/// Where the device's sound goes (PLAYS-DESIGN §4.1 route check).
nonisolated enum AudioRoute: Equatable, Sendable {
    /// Wired, Bluetooth A2DP, or USB headphones.
    case headphones
    case speaker
    /// AirPlay is refused for recording: its delay can reach two seconds.
    case airPlay
}

/// What plays to the performer before their line.
nonisolated enum CueAudio: Sendable {
    case standIn(StandInAudio)
    case take(URL)
}

/// The recording device seam: the app's is one `AVAudioEngine`; the tests'
/// is a fake that plays nothing aloud and records nothing.
protocol LiveAudio: AnyObject {
    func outputRoute() -> AudioRoute
    func start(echoCancelled: Bool) throws
    func play(_ cue: CueAudio) async
    /// Microphone chunks, mono at the take rate, delivered on the main actor.
    func beginCapture(_ onChunk: @escaping @MainActor @Sendable ([Float]) -> Void)
    func endCapture() -> MicrophoneCapture
    func stop()
}

/// One engine, one clock (research 08a §4.2): a player node for human takes
/// and stand-in buffers, and a tap on the microphone. The output reaches the
/// performer's ears only; only the tap is ever written, and only as a take.
final class EngineLiveAudio: LiveAudio {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var sink: CaptureSink?
    private var running = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: TakeAudio.format)
    }

    func outputRoute() -> AudioRoute {
        #if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
        if outputs.contains(.airPlay) { return .airPlay }
        if outputs.contains(where: { [.headphones, .bluetoothA2DP, .usbAudio].contains($0) }) { return .headphones }
        return .speaker
        #else
        return MacOutputRoute.current()
        #endif
    }

    func start(echoCancelled: Bool) throws {
        guard !running else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // A2DP for headphone output, never HFP: a hands-free microphone is
        // narrowband, and HFP would win the route if both were allowed (§4.3).
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP, .defaultToSpeaker])
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
        #endif
        if echoCancelled { try engine.inputNode.setVoiceProcessingEnabled(true) }
        engine.prepare()
        try engine.start()
        running = true
    }

    func play(_ cue: CueAudio) async {
        let buffer: AVAudioPCMBuffer?
        switch cue {
        case let .standIn(audio):
            buffer = TakeAudio.buffer(audio.samples, format: TakeAudio.format)
        case let .take(url):
            buffer = (try? TakeAudio.read(url)).flatMap { TakeAudio.buffer($0.samples, format: TakeAudio.format) }
        }
        guard running, let buffer else { return }
        if !player.isPlaying { player.play() }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { @Sendable _ in
                done.resume()
            }
        }
    }

    func beginCapture(_ onChunk: @escaping @MainActor @Sendable ([Float]) -> Void) {
        guard running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sink = CaptureSink(from: format, onChunk: onChunk)
        self.sink = sink
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: sink.block)
    }

    func endCapture() -> MicrophoneCapture {
        engine.inputNode.removeTap(onBus: 0)
        let samples = sink?.drain() ?? []
        sink = nil
        return MicrophoneCapture(samples: samples, sampleRate: TakeAudio.sampleRate)
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        running = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

/// The microphone tap's buffer, filled on the audio thread and drained on the
/// main actor. It converts the hardware format to mono at the take rate.
private nonisolated final class CaptureSink: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private let converter: AVAudioConverter?
    private let inFormat: AVAudioFormat
    private let onChunk: @MainActor @Sendable ([Float]) -> Void

    init(from format: AVAudioFormat, onChunk: @escaping @MainActor @Sendable ([Float]) -> Void) {
        inFormat = format
        converter = AVAudioConverter(from: format, to: TakeAudio.format)
        self.onChunk = onChunk
    }

    var block: AVAudioNodeTapBlock {
        { @Sendable [self] buffer, _ in self.receive(buffer) }
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * TakeAudio.sampleRate / inFormat.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: TakeAudio.format, frameCapacity: capacity) else { return }
        let feed = TapInput(buffer)
        var error: NSError?
        converter.convert(to: out, error: &error, withInputFrom: feed.block)
        guard error == nil, out.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
        lock.lock()
        samples += chunk
        lock.unlock()
        let deliver = onChunk
        Task { @MainActor in deliver(chunk) }
    }

    func drain() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let out = samples
        samples = []
        return out
    }
}

/// One tap buffer for the converter, then "no data for now" (the stream goes on).
private nonisolated final class TapInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    var block: AVAudioConverterInputBlock {
        { @Sendable [self] _, status in
            if let buffer = self.buffer {
                self.buffer = nil
                status.pointee = .haveData
                return buffer
            }
            status.pointee = .noDataNow
            return nil
        }
    }
}

#if os(macOS)
/// The Mac's default output device, read from Core Audio: built-in headphones
/// (the data source reads 'hdpn'), USB or Bluetooth count as headphones.
nonisolated enum MacOutputRoute {
    static func current() -> AudioRoute {
        var device = AudioDeviceID(0)
        guard get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                  kAudioObjectPropertyScopeGlobal, &device) else { return .speaker }
        var transport: UInt32 = 0
        guard get(device, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, &transport) else {
            return .speaker
        }
        switch transport {
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .headphones
        case kAudioDeviceTransportTypeBuiltIn:
            var source: UInt32 = 0
            let headphones: UInt32 = 0x6864_706E  // 'hdpn'
            return get(device, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput, &source)
                && source == headphones ? .headphones : .speaker
        default: return .speaker
        }
    }

    /// Every property read here is a UInt32 (an AudioDeviceID is one too).
    private static func get(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                            _ scope: AudioObjectPropertyScope, _ value: inout UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}
#endif
#endif
