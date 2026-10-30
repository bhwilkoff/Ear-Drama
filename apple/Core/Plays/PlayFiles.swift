#if os(iOS) || os(macOS)
import AVFoundation
import Foundation

/// What the microphone captured: the only thing a take or room-tone file is
/// ever written from. A stand-in is a different type (`StandInAudio`) with no
/// path to a file (PLAYS-DESIGN §5 rule 1).
nonisolated struct MicrophoneCapture: Sendable {
    let samples: [Float]
    let sampleRate: Double

    func slice(_ range: Range<Int>) -> MicrophoneCapture {
        let r = range.clamped(to: 0..<samples.count)
        return MicrophoneCapture(samples: Array(samples[r]), sampleRate: sampleRate)
    }
}

/// Takes on disk: mono, 48 kHz, FLAC from a 24-bit source (§4.2, §6). FLAC
/// writing was measured on macOS 27 (2026-10-22); the iOS 18 floor is still to
/// measure on a device, and ALAC in CAF is the fallback §6 names.
nonisolated enum TakeAudio {
    static let sampleRate: Double = 48_000
    static let fileExtension = "flac"

    static var format: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    static func write(_ capture: MicrophoneCapture, to url: URL) throws {
        try SyntheticAudio.refuse(capture.samples)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: capture.sampleRate,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 24]
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: capture.sampleRate, channels: 1,
                                interleaved: false)!
        guard let buffer = buffer(capture.samples, format: fmt) else { return }
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        try file.write(from: buffer)
        file.close()
    }

    /// Any audio file, as mono float samples at its own rate.
    static func read(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            return ([], file.processingFormat.sampleRate)
        }
        try file.read(into: buffer)
        let n = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: n))
        return (samples, file.processingFormat.sampleRate)
    }

    static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }
}

/// Productions on the device (§6): `Application Support/Plays/<production>/`
/// holds `script.json` (the script as cast), `production.json`, `takes/`,
/// `roomtone/`, and `mix.m4a`. Nothing is uploaded and no account is needed
/// (§8 rule 4; pending owner: Decision 057's sign-in covers sharing, not this).
@Observable
final class ProductionStore {
    let root: URL
    private(set) var productions: [Production] = []
    /// `share.json` per production id: its link to the Worker (PLAYS-DESIGN §11.7 rule 1).
    private(set) var shares: [String: ProductionShare] = [:]
    private(set) var lastError: String?

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot
        load()
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Plays", directoryHint: .isDirectory)
    }

    func folder(_ id: String) -> URL { root.appending(path: id, directoryHint: .isDirectory) }
    func takesFolder(_ id: String) -> URL { folder(id).appending(path: "takes", directoryHint: .isDirectory) }
    func roomToneFolder(_ id: String) -> URL { folder(id).appending(path: "roomtone", directoryHint: .isDirectory) }
    func mixURL(_ id: String) -> URL { folder(id).appending(path: "mix.m4a") }
    func takeURL(_ production: Production, _ take: Take) -> URL { takesFolder(production.id).appending(path: take.file) }

    func production(_ id: String) -> Production? { productions.first { $0.id == id } }

    func load() {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        productions = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appending(path: "production.json")) else { return nil }
            return try? decoder.decode(Production.self, from: data)
        }
        .sorted { $0.created > $1.created }
        shares = [:]
        for production in productions {
            if let data = try? Data(contentsOf: shareURL(production.id)),
               let share = try? decoder.decode(ProductionShare.self, from: data) {
                shares[production.id] = share
            }
        }
    }

    func shareURL(_ id: String) -> URL { folder(id).appending(path: "share.json") }

    func share(_ id: String) -> ProductionShare? { shares[id] }

    /// The production on this device linked to the Worker's `pid`, if any.
    func findShared(_ pid: String) -> Production? {
        productions.first { shares[$0.id]?.pid == pid }
    }

    func setShare(_ id: String, _ share: ProductionShare) throws {
        try Self.encoder.encode(share).write(to: shareURL(id), options: .atomic)
        shares[id] = share
    }

    func readTake(_ id: String, file: String) throws -> Data {
        try Data(contentsOf: takesFolder(id).appending(path: file))
    }

    /// Another member's take, written once: a file that exists is never
    /// overwritten (takes are immutable, §8 rule 5).
    func importTake(_ id: String, file: String, data: Data) throws {
        let url = takesFolder(id).appending(path: file)
        try FileManager.default.createDirectory(at: takesFolder(id), withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try data.write(to: url, options: .withoutOverwriting)
    }

    func create(_ script: PlayScript) throws -> Production {
        let production = Production(script: script)
        let fm = FileManager.default
        try fm.createDirectory(at: takesFolder(production.id), withIntermediateDirectories: true)
        try fm.createDirectory(at: roomToneFolder(production.id), withIntermediateDirectories: true)
        try Self.encoder.encode(script).write(to: folder(production.id).appending(path: "script.json"),
                                              options: .atomic)
        try save(production)
        return production
    }

    /// The script as cast, read back from the production's own folder, so a
    /// later catalog revision never changes a play halfway through.
    func script(for production: Production) -> PlayScript? {
        guard let data = try? Data(contentsOf: folder(production.id).appending(path: "script.json")) else { return nil }
        return try? JSONDecoder().decode(PlayScript.self, from: data)
    }

    func save(_ production: Production) throws {
        try Self.encoder.encode(production).write(to: folder(production.id).appending(path: "production.json"),
                                                  options: .atomic)
        if let index = productions.firstIndex(where: { $0.id == production.id }) {
            productions[index] = production
        } else {
            productions.insert(production, at: 0)
        }
    }

    /// Saves, keeping the error for the screen rather than throwing into a view.
    func update(_ production: Production) {
        do {
            try save(production)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Deleting a production deletes its folder: takes, room tone, mix, record.
    func delete(_ id: String) throws {
        let folder = folder(id)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        productions.removeAll { $0.id == id }
        shares[id] = nil
    }

    func discardUnusedTakes(_ id: String) throws {
        guard var production = production(id) else { return }
        for take in production.discardUnused() {
            try? FileManager.default.removeItem(at: takeURL(production, take))
        }
        try save(production)
    }

    /// Discard the run (Run through's review): its takes and their files go, each line back to its prior take.
    func discardRun(_ id: String, _ run: [RunNote]) throws {
        guard var production = production(id) else { return }
        for take in production.discardRun(run) {
            try? FileManager.default.removeItem(at: takeURL(production, take))
        }
        try save(production)
    }

    /// Writes a take file that never existed before (takes are never overwritten).
    func writeTake(_ capture: MicrophoneCapture, production: Production, lineID: String) throws -> String {
        let name = "\(lineID)-\(UUID().uuidString.prefix(8)).\(TakeAudio.fileExtension)"
        let url = takesFolder(production.id).appending(path: name)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.createDirectory(at: takesFolder(production.id), withIntermediateDirectories: true)
        try TakeAudio.write(capture, to: url)
        return name
    }

    func writeRoomTone(_ capture: MicrophoneCapture, production: Production) throws -> String {
        let name = "roomtone-\(UUID().uuidString.prefix(8)).\(TakeAudio.fileExtension)"
        try FileManager.default.createDirectory(at: roomToneFolder(production.id), withIntermediateDirectories: true)
        try TakeAudio.write(capture, to: roomToneFolder(production.id).appending(path: name))
        return name
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
#endif
