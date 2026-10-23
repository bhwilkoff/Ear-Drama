#if os(iOS) || os(macOS)
import Accelerate
import AVFoundation
import Foundation

/// Renders a finished play's timeline into `mix.m4a` (PLAYS-DESIGN §4.1): one
/// `AVAudioEngine` in offline manual rendering, a player node scheduled at each
/// placement's sample time with the take's stored gain applied in memory. It
/// reads only take files named by the timeline, and a timeline holds only human
/// takes, so a stand-in cannot reach the mix (§5 rule 3). A take the bleed
/// check flagged is refused, never mixed (§8 rule 3).
nonisolated enum MixRenderer {
    enum Failure: Error { case engine(String), bleed(lineID: String) }

    static let chunk: AVAudioFrameCount = 4096
    static let lookahead = 2.0

    static func render(_ timeline: MixTimeline, takesFolder: URL, to destination: URL) throws {
        if let flagged = timeline.placements.first(where: \.bleed) { throw Failure.bleed(lineID: flagged.lineID) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: timeline.sampleRate, channels: 1,
                                   interleaved: false)!
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk)
        try engine.start()
        player.play()
        defer {
            player.stop()
            engine.stop()
        }

        let partial = destination.deletingLastPathComponent()
            .appending(path: ".mix-\(UUID().uuidString.prefix(8)).m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: timeline.sampleRate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000]
        do {
            let output = try AVAudioFile(forWriting: partial, settings: settings, commonFormat: .pcmFormatFloat32,
                                         interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk) else {
                throw Failure.engine("buffer")
            }
            var next = 0
            let ahead = Int(lookahead * timeline.sampleRate)
            while engine.manualRenderingSampleTime < AVAudioFramePosition(timeline.totalFrames) {
                let now = Int(engine.manualRenderingSampleTime)
                while next < timeline.placements.count, timeline.placements[next].start < now + ahead {
                    try schedule(timeline.placements[next], on: player, folder: takesFolder, format: format)
                    next += 1
                }
                let remaining = AVAudioFrameCount(timeline.totalFrames - now)
                switch try engine.renderOffline(min(chunk, remaining), to: buffer) {
                case .success: try output.write(from: buffer)
                default: throw Failure.engine("render")
                }
            }
            output.close()
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: destination)
        }
    }

    private static func schedule(_ placement: MixTimeline.Placement, on player: AVAudioPlayerNode, folder: URL,
                                 format: AVAudioFormat) throws {
        let audio = try TakeAudio.read(folder.appending(path: placement.file))
        let window = Array(audio.samples[min(placement.inFrame, audio.samples.count)..<min(placement.outFrame,
                                                                                          audio.samples.count)])
        let gained = vDSP.multiply(placement.gain, window)
        guard let buffer = TakeAudio.buffer(gained, format: format) else { return }
        player.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: AVAudioFramePosition(placement.start),
                                                      atRate: format.sampleRate))
    }
}
#endif
