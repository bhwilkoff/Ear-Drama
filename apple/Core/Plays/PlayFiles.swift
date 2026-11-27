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
    /// Productions whose scene range a revision moved and this store dropped: the cast sheet says so once (PLAYS-DESIGN §2.12 rule 4).
    private(set) var droppedRanges: Set<String> = []
    /// Take writes in flight per production: a production is never removed while one is pending (Decision 079).
    private var pendingTakes: [String: Int] = [:]

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot
        load()
    }

    static var defaultRoot: URL {
        (LaunchDoors.scratchRoot ?? URL.applicationSupportDirectory).appending(path: "Plays", directoryHint: .isDirectory)
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
            return (try? decoder.decode(Production.self, from: data)).flatMap { $0.isTooNew ? nil : $0.migrated }
        }
        .sorted { $0.created > $1.created }
        for production in productions where production.range != nil {
            guard let whole = wholeScript(for: production), whole.rangeDrifted(production) else { continue }
            try? save(production.droppingRange(whole: whole))
            droppedRanges.insert(production.id)
        }
        shares = [:]
        for production in productions {
            if let data = try? Data(contentsOf: shareURL(production.id)),
               let share = try? decoder.decode(ProductionShare.self, from: data) {
                shares[production.id] = share
            }
        }
        for id in StudioCore.emptyLocal(productions, isShared: { shares[$0] != nil }) where pendingTakes[id] == nil { try? delete(id) }
    }

    /// Leaving the studio with no take: a local, unshared production with no take is deleted (PLAYS-DESIGN §2.3 rule
    /// 3a). True when it went.
    @discardableResult
    func removeIfEmpty(_ id: String) -> Bool {
        guard pendingTakes[id] == nil, let p = production(id), StudioCore.emptyLocal([p], isShared: { shares[$0] != nil }) == [id] else { return false }
        return (try? delete(id)) != nil
    }

    /// Runs a take's write for `id`; the production is not removed until it has finished.
    func withTakeWrite<T>(_ id: String, _ body: () throws -> T) rethrows -> T {
        pendingTakes[id, default: 0] += 1
        defer {
            if let n = pendingTakes[id], n > 1 { pendingTakes[id] = n - 1 } else { pendingTakes[id] = nil }
        }
        return try body()
    }

    func hasPendingTake(_ id: String) -> Bool { pendingTakes[id] != nil }

    /// Leaving the studio: waits for this production's take writes to settle, then removes it if it is still empty
    /// and `isHeld` (a screen showing it) is false. No timer: only the writes decide.
    @discardableResult
    func removeWhenSettled(_ id: String, isHeld: () -> Bool = { false }) async -> Bool {
        while hasPendingTake(id) { try? await Task.sleep(for: .milliseconds(10)) }
        guard !isHeld() else { return false }
        return removeIfEmpty(id)
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

    /// The share undone on this device, after the Worker refused its script for good: the production is private again.
    func unshare(_ id: String) throws {
        let url = shareURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        shares[id] = nil
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

    /// The newest production of `scriptID` on this device with this range that is not shared (the scene card's door, §2.12).
    func newest(of scriptID: String, range: ProductionRange?) -> Production? {
        productions.first { $0.scriptID == scriptID && $0.range == range && shares[$0.id] == nil && $0.room == nil }
    }

    func acknowledgeDroppedRange(_ id: String) { droppedRanges.remove(id) }

    func create(_ script: PlayScript, range: ProductionRange? = nil, heading: String? = nil) throws -> Production {
        let script = script.whole
        let production = Production(script: script, range: range, heading: heading)
        let fm = FileManager.default
        try fm.createDirectory(at: takesFolder(production.id), withIntermediateDirectories: true)
        try fm.createDirectory(at: roomToneFolder(production.id), withIntermediateDirectories: true)
        try Self.encoder.encode(script).write(to: folder(production.id).appending(path: "script.json"),
                                              options: .atomic)
        try save(production)
        return production
    }

    // MARK: Own scripts (PLAYS-DESIGN §13)

    func productions(of scriptID: String) -> [Production] { productions.filter { $0.scriptID == scriptID } }

    /// Every line of `scriptID` with a take in any production, chosen or not: what may not move (§13 item 4).
    func takenLines(of scriptID: String) -> Set<String> { Set(productions(of: scriptID).flatMap { $0.takes.map(\.lineID) }) }

    /// A changed own script reaches its productions here (§13 item 5). A shared one keeps its own text.
    func adopt(_ script: PlayScript) throws {
        for production in productions(of: script.id) where shares[production.id] == nil {
            var next = production
            next.adopt(script, lines: self.wholeScript(for: production)?.lines.map(\.id) != script.lines.map(\.id))
            // The record first: a script that then fails to write is found changed again when this is tried again.
            try save(next)
            try Self.encoder.encode(script).write(to: folder(production.id).appending(path: "script.json"), options: .atomic)
        }
    }

    /// The script as cast, read back from the production's own folder, so a
    /// later catalog revision never changes a play halfway through.
    func script(for production: Production) -> PlayScript? {
        wholeScript(for: production)?.scoped(for: production)
    }

    /// The whole script as cast, whatever the production's range.
    func wholeScript(for production: Production) -> PlayScript? {
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

    /// Deletes the unchosen takes and their files (every line, or only `lines`) and returns how many went.
    @discardableResult
    func discardUnusedTakes(_ id: String, lines: Set<String>? = nil) throws -> Int {
        guard var production = production(id) else { return 0 }
        let gone = production.discardUnused(lines: lines)
        for take in gone {
            try? FileManager.default.removeItem(at: takeURL(production, take))
        }
        try save(production)
        return gone.count
    }

    /// Deletes one unchosen take and its file; false when refused (the chosen take, or no such take).
    @discardableResult
    func deleteTake(_ id: String, takeID: String) throws -> Bool {
        guard var production = production(id) else { return false }
        let gone = production.deleteTake(takeID)
        guard !gone.isEmpty else { return false }
        for take in gone {
            try? FileManager.default.removeItem(at: takeURL(production, take))
        }
        try save(production)
        return true
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
