import Foundation

// Kokoro-82M, the downloadable voices (Decisions 076, 078; R2-kokoro-feasibility §6 S6e), the parts that need no
// runtime: the 28 voices, the tokenizer over the catalog's published phonemes, the voice table's style rows, the
// alignment the decoder reads, the render guard, and the Apple manifest's acceptance. The Swift mirror of
// android/.../kokoro/KokoroCore.kt and js/kokoro-voice.js. No phonemizer: a line arrives as phonemes (contract §4.1
// `phonemes/<id>.json`); a line without them is read by the part's system voice. Plain data, so tvOS (which reads
// the cast only, n/a) compiles it without using it.

nonisolated enum Kokoro {
    struct Voice: Equatable, Sendable {
        let id: String
        let name: String
        let grade: String
        let index: Int

        var language: String { british ? "en-GB" : "en-US" }
        /// The voice's own reported gender (its id says it), never a part's.
        var gender: VoiceGender { id.dropFirst().first == "f" ? .female : .male }
        var british: Bool { id.first == "b" }
    }

    /// The 28 English voices of Kokoro-82M v1.0 (VOICES.md), in the voice table's order. The grade is Kokoro's own.
    static let voices: [Voice] = [
        ("af_heart", "Heart", "A"), ("af_alloy", "Alloy", "C"), ("af_aoede", "Aoede", "C+"), ("af_bella", "Bella", "A-"),
        ("af_jessica", "Jessica", "D"), ("af_kore", "Kore", "C+"), ("af_nicole", "Nicole", "B-"), ("af_nova", "Nova", "C"),
        ("af_river", "River", "D"), ("af_sarah", "Sarah", "C+"), ("af_sky", "Sky", "C-"),
        ("am_adam", "Adam", "F+"), ("am_echo", "Echo", "D"), ("am_eric", "Eric", "D"), ("am_fenrir", "Fenrir", "C+"),
        ("am_liam", "Liam", "D"), ("am_michael", "Michael", "C+"), ("am_onyx", "Onyx", "D"), ("am_puck", "Puck", "C+"),
        ("am_santa", "Santa", "D-"),
        ("bf_alice", "Alice", "D"), ("bf_emma", "Emma", "B-"), ("bf_isabella", "Isabella", "C"), ("bf_lily", "Lily", "D"),
        ("bm_daniel", "Daniel", "D"), ("bm_fable", "Fable", "C"), ("bm_george", "George", "C"), ("bm_lewis", "Lewis", "D+"),
    ].enumerated().map { Voice(id: $1.0, name: $1.1, grade: $1.2, index: $0) }

    /// Kokoro's grades, best first (VOICES.md); the ones under C- start unticked in the defaults.
    static let grades = ["A", "A-", "B-", "C+", "C", "C-", "D+", "D", "D-", "F+"]
    static func offByDefault(_ grade: String) -> Bool { (grades.firstIndex(of: grade) ?? grades.count) > grades.firstIndex(of: "C-")! }

    /// Symbols per render: Kokoro rushes past ~400 (VOICES.md) and stops at 510.
    static let maxTokens = 400
    /// Symbols per render on a phone: a render's working memory and its wait grow with its length (the S6a bench).
    static let pieceSymbols = 100
    static let style = 256
    static let rows = 510
    static let sampleRate = 24_000.0
    /// Samples per predicted frame (the decoder's upsampling: 2 × 10 × 6 × 5).
    static let samplesPerFrame = 600

    /// The voice table's size for `voices`: voices × 510 rows × 256 floats, little-endian float32.
    static var voiceTableBytes: Int { voices.count * rows * style * 4 }

    static func voice(_ id: String?) -> Voice? { voices.first { $0.id == id } }

    /// The castable Kokoro voices: none until the model is downloaded; best grade first, then the table's order.
    static func castable(ready: Bool) -> [CastVoice] {
        guard ready else { return [] }
        func rank(_ v: Voice) -> Int { grades.firstIndex(of: v.grade) ?? grades.count }
        return voices.sorted { (rank($0), $0.index) < (rank($1), $1.index) }
            .map { CastVoice(id: $0.id, name: "\($0.name) (Kokoro)", language: $0.language, tier: 0, gender: $0.gender, engine: .kokoro,
                             grade: $0.grade, offByDefault: offByDefault($0.grade)) }
    }

    /// A phoneme string split into renders of at most `max` symbols, at the last sentence punctuation, else the last
    /// comma, else the last space before the limit. Joined, they are the input (js/kokoro-voice.js `chunks`).
    static func chunks(_ ps: String, max: Int = maxTokens) -> [String] {
        var out: [String] = []
        var rest = Array(ps)
        func last(_ head: [Character], _ s: String) -> Int {
            let pat = Array(s)
            guard head.count >= pat.count else { return -1 }
            for i in stride(from: head.count - pat.count, through: 0, by: -1) where Array(head[i..<i + pat.count]) == pat { return i }
            return -1
        }
        while rest.count > max {
            let head = Array(rest[0..<max])
            var cut = [". ", "! ", "? ", "; "].map { last(head, $0) }.max() ?? -1
            if cut < max / 4 { cut = last(head, ", ") }
            if cut < max / 4 { cut = head.lastIndex(of: " ") ?? -1 }
            if cut <= 0 { cut = max - 1 }
            out.append(String(rest[0...cut]))
            rest = Array(rest[(cut + 1)...])
        }
        if !rest.isEmpty { out.append(String(rest)) }
        return out
    }

    /// Phonemes to Kokoro's token ids (tokenizer.json's vocabulary), padded with 0 at both ends; unknown symbols dropped.
    static func tokenize(_ ps: String, vocab: [String: Int32]) -> [Int32] {
        var ids: [Int32] = [0]
        ids.reserveCapacity(ps.unicodeScalars.count + 2)
        for scalar in ps.unicodeScalars {
            if let id = vocab[String(scalar)] { ids.append(id) }
        }
        ids.append(0)
        return ids
    }

    /// tokenizer.json's `model.vocab`.
    static func parseVocab(_ data: Data) throws -> [String: Int32] {
        struct File: Decodable {
            struct Model: Decodable { let vocab: [String: Int32] }
            let model: Model
        }
        return try JSONDecoder().decode(File.self, from: data).model.vocab
    }

    /// The words as the phoneme file keys them: printed italic marks dropped, whitespace folded.
    static func keyOf(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: "")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Where a voice's style row for `tokenCount` padded tokens starts in the table (the row is the unpadded length).
    static func styleOffset(voice: Int, tokenCount: Int) -> Int {
        let n = min(rows - 1, max(0, tokenCount - 2))
        return (voice * rows + n) * style
    }

    static func style(_ table: [Float], voice: Int, tokenCount: Int) -> [Float] {
        let at = styleOffset(voice: voice, tokenCount: tokenCount)
        return Array(table[at..<at + style])
    }

    /// The model's speed for a part's rate and pitch: pitch is played back by sample rate, so the tempo is rate.
    static func speedFor(rate: Double, pitch: Double) -> Float { Float(min(2, max(0.5, rate / pitch))) }

    /// Each token's frames, as kokoro rounds its predicted durations: to the nearest (half to even), at least one.
    static func frames(_ durations: [Float]) -> [Int] {
        durations.map { d in Swift.max(1, Int(d.isFinite ? d.rounded(.toNearestOrEven) : 1)) }
    }

    /// The token each frame repeats: kokoro's alignment matrix as a gather (token i for each of its frames).
    static func alignment(_ frames: [Int]) -> [Int32] {
        var out: [Int32] = []
        out.reserveCapacity(frames.reduce(0, +))
        for (i, n) in frames.enumerated() { out.append(contentsOf: repeatElement(Int32(i), count: n)) }
        return out
    }

    /// The smallest of `buckets` that holds `n`, or nil when none does.
    static func bucket(_ n: Int, in buckets: [Int]) -> Int? { buckets.sorted().first { $0 >= n } }

    /// A render is played only when every sample is finite and something is louder than near-silence (fp16 renders
    /// NaN; R2-kokoro-feasibility §3). Otherwise the part's system voice reads the line.
    static func audible(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        var peak: Float = 0
        for s in samples {
            guard s.isFinite else { return false }
            peak = Swift.max(peak, abs(s))
        }
        return peak >= silence
    }

    static let silence: Float = 1e-3

    /// The phonemes a voice reads for one line: a British voice reads `gb` where the file has it.
    static func phonemes(_ row: PhonemeLine, voice: Voice) -> String { voice.british ? (row.gb ?? row.us) : row.us }

    /// "107 MB": decimal megabytes, as the stores and the Files app count.
    static func megabytes(_ bytes: Int64) -> String { "\(Int((Double(bytes) / 1_000_000).rounded())) MB" }
}

/// One line of `phonemes/<id>.json` (contract §4.1).
nonisolated struct PhonemeLine: Codable, Equatable, Sendable {
    let id: String
    var t: String = ""
    let us: String
    var gb: String? = nil
}

nonisolated struct PhonemeFile: Codable, Sendable {
    var format: Int = 1
    var id: String = ""
    var revision: String = ""
    var lines: [PhonemeLine] = []

    /// The lines keyed as the reader looks them up: by their words (`Kokoro.keyOf`).
    func byWords() -> [String: PhonemeLine] {
        var out: [String: PhonemeLine] = [:]
        for l in lines where out[Kokoro.keyOf(l.t)] == nil { out[Kokoro.keyOf(l.t)] = l }
        return out
    }
}

/// The Apple model manifest (`kokoro-vN-apple-manifest.json`, tools/publish_kokoro_model.py --coreml): our own Core
/// ML conversion (tools/convert_kokoro_coreml.py), two `.mlpackage`s published file by file, the voice table and the
/// vocabulary. Each file is a Release asset (`path`) placed at `dest` under the model folder.
nonisolated struct KokoroManifest: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        let path: String
        let role: String
        let bytes: Int64
        let sha256: String
        let license: String
        var dest: String? = nil

        /// Where the file lives under the model folder.
        var place: String { dest ?? path }
    }

    let format: Int
    var version: Int = 1
    var name: String = ""
    var attribution: String = ""
    var voices: [String] = []
    var voiceShape: [Int] = []
    var sampleRate: Int = 24_000
    var precision: String = ""
    var runtime: String = ""
    /// The decoder's frame buckets and the duration model's token buckets, one Core ML function each.
    var frameBuckets: [Int] = []
    var tokenBuckets: [Int] = []
    var files: [File] = []

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    func files(_ role: String) -> [File] { files.filter { $0.role == role } }

    enum Refusal: Error, Equatable { case refused(String) }

    /// Licenses a model file may carry (tools/fetch_kokoro_model.py LICENSES): permissive only.
    static let licenses: Set<String> = ["Apache-2.0", "MIT", "BSD-2-Clause", "BSD-3-Clause"]

    /// The manifest when the app can use it: format 1, the Core ML runtime, both models, a voice table and a
    /// vocabulary, each file with a plain asset name, a relative place, a size, a SHA-256 and a permissive license,
    /// the voices this app knows in its order, buckets, never fp16 alone. Throws naming what is wrong.
    static func accept(_ data: Data) throws(Refusal) -> KokoroManifest {
        guard let m = try? JSONDecoder().decode(KokoroManifest.self, from: data) else { throw .refused("not a model manifest") }
        func need(_ ok: Bool, _ why: @autoclosure () -> String) throws(Refusal) { if !ok { throw .refused(why()) } }
        try need(m.format == 1, "format \(m.format)")
        try need(m.runtime == "coreml", "runtime \(m.runtime)")
        try need(m.precision != "fp16", "fp16 renders NaN")
        for role in ["duration", "decoder", "voices", "vocab"] { try need(!m.files(role).isEmpty, "no \(role) file") }
        let plain = /^[A-Za-z0-9_.-]+$/
        for f in m.files {
            try need(f.path.wholeMatch(of: plain) != nil, "path \(f.path)")
            let parts = f.place.split(separator: "/", omittingEmptySubsequences: false)
            try need(!f.place.hasPrefix("/") && !parts.isEmpty
                     && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && String($0).wholeMatch(of: plain) != nil },
                     "place \(f.place)")
            try need(licenses.contains(f.license), "\(f.path): license \(f.license) is not permissive")
            try need(f.sha256.wholeMatch(of: /^[0-9a-f]{64}$/) != nil, "\(f.path): sha256")
            try need(f.bytes > 0, "\(f.path): size")
        }
        try need(Set(m.files.map(\.place)).count == m.files.count, "two files in one place")
        try need(m.voices == Kokoro.voices.map(\.id), "voices differ from the app's")
        try need(m.voiceShape == [Kokoro.rows, Kokoro.style], "voice shape \(m.voiceShape)")
        try need(m.files("voices").first?.bytes == Int64(Kokoro.voiceTableBytes), "voice table size")
        try need(!m.frameBuckets.isEmpty && !m.tokenBuckets.isEmpty && (m.frameBuckets + m.tokenBuckets).allSatisfy { $0 > 0 },
                 "buckets")
        return m
    }
}

/// Whether the downloadable voices are offered: always in a DEBUG build (the bench, the doors), and in a release build
/// since the S6a gate passed on the open iPhone Duo, 2026-11-22: RTF 0.116, peak 539 MB against 0.7 and 600 MB, over
/// 623 renders in 10 minutes with kokoro-v3-apple (R2-kokoro-feasibility, S6e).
nonisolated enum KokoroFlag {
    static let inRelease = true

    static var enabled: Bool {
        #if DEBUG
        true
        #else
        inRelease
        #endif
    }
}
