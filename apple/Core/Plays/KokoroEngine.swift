#if os(iOS) || os(macOS)
import CoreML
import Foundation

/// Renders one piece of tokens in one voice: 24 kHz mono samples, in memory.
nonisolated protocol KokoroRenderer: AnyObject, Sendable {
    func render(_ tokens: [Int32], voice: Int, speed: Float) throws -> [Float]
    /// The samples and the duration model's frames for each token (nil when the renderer cannot say).
    func renderTimed(_ tokens: [Int32], voice: Int, speed: Float) throws -> (samples: [Float], frames: [Int]?)
}

nonisolated extension KokoroRenderer {
    func renderTimed(_ tokens: [Int32], voice: Int, speed: Float) throws -> (samples: [Float], frames: [Int]?) {
        (try render(tokens, voice: voice, speed: speed), nil)
    }
}

nonisolated enum KokoroRenderError: Error, Equatable {
    /// More tokens or frames than the largest bucket: the piece is split and tried again.
    case tooLong
    case badOutput
}

/// Kokoro on Core ML (our own conversion, tools/convert_kokoro_coreml.py; no third-party package): the duration model,
/// the alignment as a gather, then the decoder, each a fixed-shape function per bucket. It runs on the CPU
/// (`defaultUnits`): measured on an M3 (the Mac bench, 2026-11-16) the CPU reads at RTF 0.07 in a 350 MB footprint, the
/// GPU at 0.07 with a 977 MB footprint (its buffers count against the app), and the Neural Engine's compiler refuses the
/// decoder (ANECCompile FAILED), after which `.all` fails every render. Each model is compiled once per manifest version into the model folder (Application Support) and its
/// functions are loaded as lines need them, at most two decoder buckets at a time. Holds no audio past a call.
nonisolated final class CoreMLKokoroRenderer: KokoroRenderer, @unchecked Sendable {
    private let duration: URL
    private let decoder: URL
    private let table: [Float]
    private let tokenBuckets: [Int]
    private let frameBuckets: [Int]
    private let units: MLComputeUnits
    private let keepDecoders: Int
    private let lock = NSLock()
    private var models: [String: MLModel] = [:]
    private var recent: [String] = []
    private var rng = Xorshift(seed: UInt64(UInt32.random(in: 1...UInt32.max)))

    private init(duration: URL, decoder: URL, table: [Float], manifest: KokoroManifest, units: MLComputeUnits, keepDecoders: Int) {
        self.duration = duration
        self.decoder = decoder
        self.table = table
        self.tokenBuckets = manifest.tokenBuckets.sorted()
        self.frameBuckets = manifest.frameBuckets.sorted()
        self.units = units
        self.keepDecoders = max(1, keepDecoders)
    }

    /// Compiles the two packages if this version has not been compiled yet, and reads the voice table.
    static let defaultUnits: MLComputeUnits = .cpuOnly

    /// Decoder buckets kept loaded: each loaded function holds its own plan, and loading one costs a line's wait.
    static let defaultKeepDecoders = 2

    static func load(root: URL, manifest: KokoroManifest, units: MLComputeUnits = defaultUnits,
                     keepDecoders: Int = defaultKeepDecoders) async throws -> CoreMLKokoroRenderer {
        let fm = FileManager.default
        let compiled = root.appending(path: "compiled-v\(manifest.version)", directoryHint: .isDirectory)
        try fm.createDirectory(at: compiled, withIntermediateDirectories: true)
        func ready(_ name: String) async throws -> URL {
            let dest = compiled.appending(path: "\(name).mlmodelc", directoryHint: .isDirectory)
            if fm.fileExists(atPath: dest.appending(path: "coremldata.bin").path) { return dest }
            let built = try await MLModel.compileModel(at: root.appending(path: "\(name).mlpackage", directoryHint: .isDirectory))
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: built, to: dest)
            return dest
        }
        let d = try await ready("KokoroDuration")
        let e = try await ready("KokoroDecoder")
        guard let voices = manifest.files("voices").first else { throw KokoroRenderError.badOutput }
        let bytes = try Data(contentsOf: root.appending(path: voices.place), options: .alwaysMapped)
        let table = bytes.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
        guard table.count == Kokoro.voices.count * Kokoro.rows * Kokoro.style else { throw KokoroRenderError.badOutput }
        return CoreMLKokoroRenderer(duration: d, decoder: e, table: table, manifest: manifest, units: units,
                                    keepDecoders: keepDecoders)
    }

    private func model(_ url: URL, _ function: String) throws -> MLModel {
        lock.lock()
        defer { lock.unlock() }
        let key = url.lastPathComponent + "/" + function
        recent.removeAll { $0 == key }
        recent.append(key)
        if let m = models[key] { return m }
        let config = MLModelConfiguration()
        config.computeUnits = units
        config.functionName = function
        let m = try MLModel(contentsOf: url, configuration: config)
        models[key] = m
        // Keep the duration model and the decoder buckets used last.
        let decoders = recent.filter { $0.hasPrefix(decoder.lastPathComponent) }
        for old in decoders.dropLast(keepDecoders) {
            models[old] = nil
            recent.removeAll { $0 == old }
        }
        return m
    }

    func render(_ tokens: [Int32], voice: Int, speed: Float) throws -> [Float] {
        try renderTimed(tokens, voice: voice, speed: speed).samples
    }

    func renderTimed(_ tokens: [Int32], voice: Int, speed: Float) throws -> (samples: [Float], frames: [Int]?) {
        let n = tokens.count
        guard let tb = Kokoro.bucket(n, in: tokenBuckets) else { throw KokoroRenderError.tooLong }
        var ids = [Int32](repeating: 0, count: tb)
        ids.replaceSubrange(0..<n, with: tokens)
        let ref = Kokoro.style(table, voice: voice, tokenCount: n)
        let first = try model(duration, "t\(tb)").prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLMultiArray(MLShapedArray<Int32>(scalars: ids, shape: [1, tb])),
            "ref_s": MLMultiArray(MLShapedArray<Float>(scalars: ref, shape: [1, Kokoro.style])),
            "speed": MLMultiArray(MLShapedArray<Float>(scalars: [speed], shape: [1])),
            "length": MLMultiArray(MLShapedArray<Float>(scalars: [Float(n)], shape: [1])),
        ]))
        guard let du = first.featureValue(for: "duration")?.multiArrayValue,
              let dd = first.featureValue(for: "d")?.multiArrayValue,
              let te = first.featureValue(for: "t_en")?.multiArrayValue else { throw KokoroRenderError.badOutput }
        let frames = Kokoro.frames(Array(MLShapedArray<Float>(converting: du).scalars.prefix(n)))
        let total = frames.reduce(0, +)
        guard let fb = Kokoro.bucket(total, in: frameBuckets) else { throw KokoroRenderError.tooLong }
        let align = Kokoro.alignment(frames)
        let d = MLShapedArray<Float>(converting: dd).scalars  // 1, tb, 640
        let t = MLShapedArray<Float>(converting: te).scalars  // 1, 512, tb
        let dw = d.count / tb, tw = t.count / tb
        var en = [Float](repeating: 0, count: dw * fb)
        var asr = [Float](repeating: 0, count: tw * fb)
        for (f, token) in align.enumerated() {
            let k = Int(token)
            for c in 0..<dw { en[c * fb + f] = d[k * dw + c] }
            for c in 0..<tw { asr[c * fb + f] = t[c * tb + k] }
        }
        let noise = gaussian(Kokoro.samplesPerFrame * fb)
        let second = try model(decoder, "f\(fb)").prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "en": MLMultiArray(MLShapedArray<Float>(scalars: en, shape: [1, dw, fb])),
            "asr": MLMultiArray(MLShapedArray<Float>(scalars: asr, shape: [1, tw, fb])),
            "ref_s": MLMultiArray(MLShapedArray<Float>(scalars: ref, shape: [1, Kokoro.style])),
            "noise": MLMultiArray(MLShapedArray<Float>(scalars: noise, shape: [1, noise.count, 1])),
            "length": MLMultiArray(MLShapedArray<Float>(scalars: [Float(total)], shape: [1])),
        ]))
        guard let audio = second.featureValue(for: "audio")?.multiArrayValue else { throw KokoroRenderError.badOutput }
        return (Array(MLShapedArray<Float>(converting: audio).scalars.prefix(Kokoro.samplesPerFrame * total)), frames)
    }

    /// Standard normal noise for the excitation (the model takes it as an input, so no random operator is in a graph).
    private func gaussian(_ count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        var out = [Float](repeating: 0, count: count)
        var i = 0
        while i < count {
            let u1 = max(Float(rng.next() >> 40) / Float(1 << 24), 1e-7)
            let u2 = Float(rng.next() >> 40) / Float(1 << 24)
            let r = (-2 * log(u1)).squareRoot()
            out[i] = r * cos(2 * .pi * u2)
            if i + 1 < count { out[i + 1] = r * sin(2 * .pi * u2) }
            i += 2
        }
        return out
    }
}

/// A fast generator for noise (never for anything that must be unpredictable).
nonisolated struct Xorshift {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// The downloaded voices reading a play's lines (PLAYS-DESIGN §2.8 engine `kokoro`, rule 10; Decision 078): a line's
/// published phonemes (`phonemes/<id>.json`, through the one `APIClient`, kept in memory for the last two plays, never
/// on disk) are tokenized and rendered into memory, and each render is marked synthetic so no writer in the app accepts
/// it (`SyntheticAudio`). Nothing here writes a file or plays a sound: `KokoroLive` plays a render once and
/// `KokoroStandInVoice` hands one to the recorder's cue. A nil or false result means Kokoro cannot read the line (no
/// model, no phonemes, a non-finite or silent render), and the part's system voice reads it.
actor KokoroReader {
    typealias Phonemes = @Sendable (String) async throws -> Data?
    typealias Loader = @Sendable (URL, KokoroManifest) async throws -> KokoroRenderer

    static let shared = KokoroReader()
    static let keepPlays = 2

    private let root: URL
    private let phonemes: Phonemes
    private let loader: Loader
    private let maxSymbols: Int
    private var renderer: KokoroRenderer?
    private var vocab: [String: Int32] = [:]
    private var plays: [(id: String, lines: [String: PhonemeLine]?)] = []
    /// Why the last refused render was refused (the bench and the logs say it; the person hears the system voice).
    private(set) var lastRefusal: String?

    init(root: URL = KokoroInstall.defaultRoot,
         phonemes: @escaping Phonemes = { try await APIClient.shared.playsData("library/phonemes/\($0).json") },
         loader: @escaping Loader = { try await CoreMLKokoroRenderer.load(root: $0, manifest: $1) },
         maxSymbols: Int = Kokoro.pieceSymbols) {
        self.root = root
        self.phonemes = phonemes
        self.loader = loader
        self.maxSymbols = maxSymbols
    }

    nonisolated func ready() -> Bool { KokoroFlag.enabled && KokoroInstall.manifest(at: root) != nil }

    /// Whether the play has published phonemes: nil until `prepare` has asked.
    func hasPhonemes(_ playID: String) -> Bool? { plays.first { $0.id == playID }.map { $0.lines != nil } }

    /// Fetches a play's phonemes once. A play the catalog held for review has none (the file is absent).
    @discardableResult
    func prepare(_ playID: String) async -> Bool {
        if let known = hasPhonemes(playID) { return known }
        let lines: [String: PhonemeLine]?
        do {
            lines = try await phonemes(playID).map { try JSONDecoder().decode(PhonemeFile.self, from: $0).byWords() }
        } catch {
            return false  // unreachable now: asked again next time
        }
        plays.removeAll { $0.id == playID }
        plays.append((playID, lines))
        if plays.count > Self.keepPlays { plays.removeFirst(plays.count - Self.keepPlays) }
        return lines != nil
    }

    private func row(_ playID: String, _ text: String) -> PhonemeLine? {
        plays.first { $0.id == playID }?.lines?[Kokoro.keyOf(text)]
    }

    /// Whether Kokoro can read this line now (the model is here and the line has phonemes).
    func canRead(_ playID: String, _ text: String) -> Bool { ready() && row(playID, text) != nil }

    private func engine() async throws -> KokoroRenderer? {
        if let renderer { return renderer }
        guard let m = KokoroInstall.manifest(at: root), let vocabFile = m.files("vocab").first else { return nil }
        vocab = try Kokoro.parseVocab(Data(contentsOf: root.appending(path: vocabFile.place)))
        let r = try await loader(root, m)
        renderer = r
        return r
    }

    /// Loads the model now (the bench measures it; a first line otherwise loads it).
    func warm() async -> Bool {
        do { return try await engine() != nil } catch {
            lastRefusal = "load threw \(error)"
            return false
        }
    }

    /// The line's renders, one per piece of at most `maxSymbols` symbols, handed to `onPiece` as each is made. False
    /// when Kokoro cannot read the line or its FIRST piece is refused (nothing was handed over, so the system voice
    /// can read it); a later refused piece ends the line there.
    /// `onTiming`, when given, hears each piece's phoneme symbols and frames just before its samples, with the line's
    /// whole phoneme string (the read-along's word clock, PLAYS-DESIGN §2.11 rule 3); nil when the renderer could not say.
    func renderPieces(_ playID: String, _ text: String, voice voiceID: String, speed: Float,
                      onTiming: (@Sendable (ReadAlong.KokoroPiece?, _ line: String) async -> Void)? = nil,
                      onPiece: @Sendable ([Float]) async -> Void) async -> Bool {
        guard let voice = Kokoro.voice(voiceID), ready() else { return false }
        await prepare(playID)
        guard let r = row(playID, text), let e = try? await engine() else { return false }
        let whole = Kokoro.phonemes(r, voice: voice)
        var queue = Kokoro.chunks(whole, max: maxSymbols)
        var handed = 0
        while !queue.isEmpty {
            let piece = queue.removeFirst()
            let tokens = Kokoro.tokenize(piece, vocab: vocab)
            guard tokens.count > 2 else { continue }
            let samples: [Float]
            let frames: [Int]?
            do {
                (samples, frames) = try e.renderTimed(tokens, voice: voice.index, speed: speed)
            } catch KokoroRenderError.tooLong where piece.count > 8 {
                queue.insert(contentsOf: Kokoro.chunks(piece, max: max(8, piece.count / 2)), at: 0)
                continue
            } catch {
                lastRefusal = "render threw \(error)"
                return handed > 0
            }
            guard Kokoro.audible(samples) else {
                lastRefusal = "refused \(samples.count) samples, \(samples.filter { !$0.isFinite }.count) non-finite"
                return handed > 0
            }
            SyntheticAudio.mark(samples)
            if let onTiming {
                let symbols = piece.unicodeScalars.filter { vocab[String($0)] != nil }.map { Character($0) }
                await onTiming(frames.map { ReadAlong.KokoroPiece(symbols: symbols, frames: $0) }, whole)
            }
            await onPiece(samples)
            handed += 1
        }
        return handed > 0
    }

    /// The whole line in one buffer (the recorder's cue), marked synthetic; nil when Kokoro cannot read it.
    func render(_ playID: String, _ text: String, voice: String, speed: Float) async -> [Float]? {
        let parts = Parts()
        guard await renderPieces(playID, text, voice: voice, speed: speed, onPiece: { await parts.add($0) }) else { return nil }
        let all = await parts.all
        SyntheticAudio.mark(all)
        return all
    }

    /// Lets the model go (before Delete).
    func unload() {
        renderer = nil
        vocab = [:]
    }

    private actor Parts {
        var all: [Float] = []
        func add(_ p: [Float]) { all += p }
    }
}
#endif
