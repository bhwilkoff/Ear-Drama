#if os(iOS) || os(macOS)
import AVFoundation
import CryptoKit
import Foundation

/// One of the person's own sounds (B32 §3.4): recorded or brought for the Sound part, kept on this device only, never
/// synced, uploaded, shared or published. A production's `sound` block names it by `id` (`src.own`).
nonisolated struct OwnSound: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    let created: Date
    /// "recorded" or "file".
    let from: String
    let seconds: Double
    let bytes: Int
    /// The file name inside `Sounds/mine/`.
    let file: String
    let loudness: Double?
    let peak: Float
}

/// Own sounds on disk (§3.4 item 1): `Application Support/Sounds/mine/` beside `Plays/`, the take format (mono 48 kHz
/// FLAC) and an `index.json`. Nothing here reaches the network: the share, sync and publish clients never read it.
@Observable
final class OwnSoundStore {
    let root: URL
    private(set) var sounds: [OwnSound] = []

    nonisolated enum Refusal: Error, Equatable { case tooLong, tooLarge, unreadable, empty }

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot
        load()
    }

    static var defaultRoot: URL {
        (LaunchDoors.scratchRoot ?? URL.applicationSupportDirectory)
            .appending(path: "Sounds", directoryHint: .isDirectory).appending(path: "mine", directoryHint: .isDirectory)
    }

    private var indexURL: URL { root.appending(path: "index.json") }

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? Self.decoder.decode([OwnSound].self, from: data) else { sounds = []; return }
        sounds = list.sorted { $0.created > $1.created }
    }

    func sound(_ id: String) -> OwnSound? { sounds.first { $0.id == id } }

    func url(_ id: String) -> URL? { sound(id).map { root.appending(path: $0.file) } }

    /// Samples at the take rate, or nil when this device does not hold the sound ("On another device").
    func samples(_ id: String) -> [Float]? {
        guard let url = url(id), let read = try? TakeAudio.read(url) else { return nil }
        return read.samples
    }

    /// Keeps a sound recorded on the board (up to 30 s) or a decoded file, in the take format.
    @discardableResult
    func save(_ samples: [Float], name: String, from: String) throws -> OwnSound {
        guard !samples.isEmpty else { throw Refusal.empty }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let file = "\(id).\(TakeAudio.fileExtension)"
        let url = root.appending(path: file)
        try TakeAudio.write(MicrophoneCapture(samples: samples, sampleRate: TakeAudio.sampleRate), to: url)
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sound = OwnSound(id: id, name: trimmed.isEmpty ? "My sound" : String(trimmed.prefix(60)), created: .now, from: from,
                             seconds: Double(samples.count) / TakeAudio.sampleRate, bytes: bytes, file: file,
                             loudness: BS1770.integratedLoudness(samples, sampleRate: TakeAudio.sampleRate),
                             peak: BS1770.samplePeak(samples))
        sounds.insert(sound, at: 0)
        try persist()
        return sound
    }

    /// Bring a file (§3.2 item 6): audio up to 10 minutes and 50 MB, decoded to mono at the take rate and kept.
    @discardableResult
    func bring(_ url: URL) throws -> OwnSound {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
        guard bytes <= SoundBoard.ownFileMaxBytes else { throw Refusal.tooLarge }
        let samples = try Self.decode(url, maxSeconds: SoundBoard.ownFileMaxSeconds)
        return try save(samples, name: url.deletingPathExtension().lastPathComponent, from: "file")
    }

    func rename(_ id: String, to name: String) {
        guard let i = sounds.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sounds[i].name = String(trimmed.prefix(60))
        try? persist()
    }

    func delete(_ id: String) {
        guard let s = sound(id) else { return }
        try? FileManager.default.removeItem(at: root.appending(path: s.file))
        sounds.removeAll { $0.id == id }
        try? persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.encoder.encode(sounds).write(to: indexURL, options: .atomic)
    }

    /// Any audio file as mono float at the take rate, refused past `maxSeconds`.
    nonisolated static func decode(_ url: URL, maxSeconds: Double) throws -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { throw Refusal.unreadable }
        let inFormat = file.processingFormat
        guard inFormat.sampleRate > 0, Double(file.length) / inFormat.sampleRate <= maxSeconds + 0.5 else { throw Refusal.tooLong }
        guard let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw Refusal.unreadable }
        try file.read(into: input)
        guard input.frameLength > 0 else { throw Refusal.empty }
        let out = TakeAudio.format
        guard let converter = AVAudioConverter(from: inFormat, to: out) else { throw Refusal.unreadable }
        if inFormat.channelCount > 1 {
            // Every channel at an equal share, the mono mix (the mix stays mono, §3.5).
            let n = Int(inFormat.channelCount)
            converter.channelMap = [0]
            if let data = input.floatChannelData {
                for f in 0..<Int(input.frameLength) {
                    var sum: Float = 0
                    for c in 0..<n { sum += data[c][f] }
                    data[0][f] = sum / Float(n)
                }
            }
        }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * out.sampleRate / inFormat.sampleRate) + 4_096
        guard let output = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: capacity) else { throw Refusal.unreadable }
        nonisolated(unsafe) var given = false
        nonisolated(unsafe) let source = input
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true
            status.pointee = .haveData
            return source
        }
        if let error { throw error }
        let n = Int(output.frameLength)
        guard n > 0, let ch = output.floatChannelData else { throw Refusal.empty }
        return Array(UnsafeBufferPointer(start: ch[0], count: n))
    }

    /// Export my data (docs/EXPORT.md `ownSounds[]`): each sound whole, as a base64 16-bit 48 kHz mono WAV.
    func exportRows() -> [DataExport.OwnSoundRow] {
        sounds.compactMap { s in
            guard let samples = samples(s.id) else { return nil }
            return DataExport.OwnSoundRow(id: s.id, name: s.name, created: s.created, from: s.from, seconds: s.seconds,
                                          bytes: s.bytes, wav: Self.wav16(samples).base64EncodedString())
        }
    }

    /// A 16-bit PCM mono WAV at the take rate.
    nonisolated static func wav16(_ samples: [Float], sampleRate: Int = Int(TakeAudio.sampleRate)) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        for s in samples {
            let v = Int16(max(-32_768, min(32_767, (Double(max(-1, min(1, s))) * 32_767).rounded())))
            u16(UInt16(bitPattern: v))
        }
        return d
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// The sound pack (B32 §5.2), a source that may be absent: `manifestURL` is nil until the owner rules on its archive.org
/// item, and then the board's library shows nothing (WEB-DESIGN §4.16 item 14a, the same rule). Configured, the
/// manifest is read through the shared client, each category downloads on demand into
/// `Application Support/Sounds/<pack>/`, and every file is checked against its sha256 before use.
@Observable
final class SoundPackStore {
    enum State: Equatable { case absent, loading, ready, unreachable, offline }

    /// The manifest, e.g. https://archive.org/download/eardrama-sounds-1/sounds.json. Nil until the owner rules (§10 q2).
    static let manifestURL: URL? = nil

    let manifestURL: URL?
    private(set) var state: State
    private(set) var manifest: SoundBoard.Manifest?
    /// Category ids being downloaded, and the ones that failed.
    private(set) var downloading: Set<String> = []
    private(set) var failed: Set<String> = []
    @ObservationIgnored private let root: URL

    init(manifestURL: URL? = SoundPackStore.manifestURL, root: URL? = nil) {
        self.manifestURL = manifestURL
        self.root = root ?? (LaunchDoors.scratchRoot ?? URL.applicationSupportDirectory).appending(path: "Sounds", directoryHint: .isDirectory)
        state = manifestURL == nil ? .absent : .loading
    }

    var cues: [SoundBoard.PackCue] { manifest?.cues ?? [] }

    func load() async {
        guard let manifestURL, manifest == nil else { return }
        state = .loading
        do {
            let data = try await APIClient.shared.soundPackData(manifestURL)
            manifest = try SoundBoard.readManifest(data)
            state = .ready
        } catch {
            state = (error as? URLError)?.code == .notConnectedToInternet ? .offline : .unreachable
        }
    }

    private func folder(_ pack: String) -> URL { root.appending(path: pack, directoryHint: .isDirectory) }

    func fileURL(_ cue: SoundBoard.PackCue) -> URL? {
        guard let manifest else { return nil }
        return folder(manifest.pack).appending(path: cue.file)
    }

    func isHere(_ cue: SoundBoard.PackCue) -> Bool { fileURL(cue).map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    func categoryHere(_ id: String) -> Bool { cues.filter { $0.category == id }.allSatisfy(isHere) }

    func cue(_ id: String) -> SoundBoard.PackCue? { cues.first { $0.id == id } }

    /// Downloads a category's files, each checked against its sha256 (a mismatch is deleted and fetched once more).
    func download(_ category: String) async {
        guard let manifestURL, let manifest, !downloading.contains(category) else { return }
        downloading.insert(category)
        failed.remove(category)
        defer { downloading.remove(category) }
        for cue in manifest.cues where cue.category == category && !isHere(cue) {
            guard let dest = fileURL(cue), let src = URL(string: cue.file, relativeTo: manifestURL)?.absoluteURL else { continue }
            var ok = false
            for _ in 0..<2 where !ok {
                guard let data = try? await APIClient.shared.soundPackData(src) else { break }
                let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard hex == cue.sha256 else { continue }
                try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                ok = (try? data.write(to: dest, options: .atomic)) != nil
            }
            if !ok { failed.insert(category); return }
        }
    }
}

/// What the mix and the live listen read for a pack or own sound (Decision 091's resolver): its length and kind for the
/// timeline, its samples at the take rate for the renderer, its file for the live listen. A sound this device lacks
/// resolves to nil, so the timeline names it (`missingSounds`), never drops it.
nonisolated struct SoundSources: Sendable {
    let own: @Sendable (String) -> (info: OwnSound, url: URL)?
    let pack: @Sendable (String) -> (cue: SoundBoard.PackCue, url: URL)?

    @MainActor
    init(own store: OwnSoundStore, pack: SoundPackStore) {
        let mine = Dictionary(uniqueKeysWithValues: store.sounds.compactMap { s in store.url(s.id).map { (s.id, (s, $0)) } })
            .filter { FileManager.default.fileExists(atPath: $0.value.1.path) }
        let cues = Dictionary(uniqueKeysWithValues: pack.cues.compactMap { c in pack.fileURL(c).map { (c.id, (c, $0)) } })
            .filter { FileManager.default.fileExists(atPath: $0.value.1.path) }
        self.own = { mine[$0] }
        self.pack = { cues[$0] }
    }

    func url(_ src: SoundSource) -> URL? {
        switch src {
        case let .own(id, _): own(id)?.url
        case let .pack(_, cue): pack(cue)?.url
        case .take: nil
        }
    }

    /// The timeline's view of a source (frames at the take rate), or nil when it is not on this device.
    func info(_ src: SoundSource, _ cue: SoundCue) -> SoundInfo? {
        switch src {
        case let .own(id, _):
            guard let o = own(id) else { return nil }
            return SoundInfo(key: "own:\(id)", frames: Int((o.info.seconds * TakeAudio.sampleRate).rounded()), kind: "effect",
                             loudness: o.info.loudness, peak: Double(o.info.peak))
        case let .pack(_, id):
            guard let p = pack(id) else { return nil }
            return SoundInfo(key: "pack:\(id)", frames: SoundMix.msFrames(p.cue.ms, TakeAudio.sampleRate),
                             kind: p.cue.kind == "effect" ? "effect" : "music", loudness: p.cue.lufs, peak: p.cue.peak ?? 0)
        case .take:
            return nil
        }
    }

    /// The timeline's resolver and the renderer's loader, as `renderMix` takes them.
    var resolver: (SoundSource, SoundCue) -> SoundInfo? { { info($0, $1) } }
    var loader: @Sendable (SoundSource) throws -> [Float] { { try samples($0) } }

    /// A source's samples at the take rate, for the renderer.
    func samples(_ src: SoundSource) throws -> [Float] {
        guard let url = url(src) else { throw MixTimeline.Failure.missingSounds([]) }
        let read = try TakeAudio.read(url)
        if read.sampleRate == TakeAudio.sampleRate { return read.samples }
        return try OwnSoundStore.decode(url, maxSeconds: .infinity)
    }
}
#endif
