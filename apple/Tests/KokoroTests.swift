import Foundation
import Testing

// The downloadable voices on Apple (Decision 078, S6e; PLAYS-DESIGN §2.8 rule 10), the Swift mirror of
// android/.../KokoroCoreTest, KokoroModelStoreTest, KokoroReaderTest and KokoroCastTest: the voices, the tokenizer over
// published phonemes, the alignment, the render guard, the manifest's acceptance, the download (resume, checksum,
// Delete), the reader over a fake renderer, and the cast. Nothing here runs the model or plays a sound.
//
// Seen to fail, 2026-11-15 (each against a mutated copy of Core/Plays):
//   KokoroManifest.accept without the license check: "a GPL file" is accepted.
//   KokoroModelStore keeping a file whose SHA-256 differs: the checksum test finds it kept and the state ready.
//   KokoroModelStore downloading a partial file from byte 0: the resume test sees a request from 0.
//   KokoroReader playing a render with a NaN: the NaN test hears a line instead of the fallback.
//   KokoroReader without SyntheticAudio.mark: "every piece is marked synthetic" fails.
//   VoiceCasting.resolve finding a Kokoro voice without the download: the deleted-model test reads Heart.
//   Kokoro.frames rounding half up: the half-to-even golden fails.

// MARK: - Fixtures

/// Kokoro's symbols for the fixture lines: lower-case letters, space and punctuation (all in Kokoro's vocabulary).
nonisolated let kokoroFixtureVocab: [String: Int32] = {
    var v: [String: Int32] = [" ": 16, ".": 4, ",": 3, "?": 6, "!": 5, "ˈ": 156, "ˌ": 157]
    for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() where c != "g" { v[String(c)] = Int32(43 + i) }  // Kokoro's ids
    return v
}()

nonisolated func kokoroVocabJSON(_ vocab: [String: Int32] = kokoroFixtureVocab) -> Data {
    try! JSONSerialization.data(withJSONObject: ["model": ["vocab": vocab]], options: [.sortedKeys])
}

/// A play's phoneme file whose "phonemes" are the lines' own words, lower-cased (what the fake renderer reads).
func kokoroPhonemeFile(_ script: PlayScript) -> Data {
    let lines = script.lines.filter { $0.kind == .speech }.map { l -> [String: String] in
        let t = Kokoro.keyOf(l.spokenText)
        return ["id": l.id, "t": t, "us": t.lowercased(), "gb": t.lowercased() + " "]
    }
    return try! JSONSerialization.data(withJSONObject: ["format": 1, "id": script.id, "revision": script.revision, "lines": lines])
}

nonisolated func kokoroManifestJSON(files: [[String: Any]], precision: String = "fp16-int8w", runtime: String = "coreml",
                                    voices: [String] = Kokoro.voices.map(\.id), frameBuckets: [Int] = [64, 128],
                                    tokenBuckets: [Int] = [32], version: Int = KokoroModelStore.version) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "format": 1, "version": version, "name": "Kokoro-82M v1.0", "attribution": "x", "voices": voices,
        "voiceShape": [510, 256], "sampleRate": 24_000, "precision": precision, "runtime": runtime,
        "frameBuckets": frameBuckets, "tokenBuckets": tokenBuckets, "files": files,
    ], options: [.sortedKeys])
}

nonisolated func kokoroSHA(_ d: Data) -> String {
    let url = FileManager.default.temporaryDirectory.appending(path: "sha-\(UUID().uuidString)")
    try! d.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    return try! KokoroModelStore.sha256(url)
}

/// The files a fixture manifest names, with their bytes: two tiny "models", the voice table and the vocabulary.
nonisolated func kokoroFixtureFiles(license: String = "Apache-2.0") -> [(entry: [String: Any], bytes: Data)] {
    let parts: [(String, String, String, Data)] = [
        ("kokoro-v3-KokoroDuration.mlpackage-Manifest.json", "duration", "KokoroDuration.mlpackage/Manifest.json", Data("{\"d\":1}".utf8)),
        ("kokoro-v3-KokoroDecoder.mlpackage-Manifest.json", "decoder", "KokoroDecoder.mlpackage/Manifest.json", Data("{\"e\":2}".utf8)),
        ("kokoro-v3-voices-en.bin", "voices", "voices-en.bin", Data(count: Kokoro.voiceTableBytes)),
        ("kokoro-v3-tokenizer.json", "vocab", "tokenizer.json", kokoroVocabJSON()),
    ]
    return parts.map { name, role, dest, bytes in
        (["path": name, "role": role, "dest": dest, "bytes": bytes.count, "sha256": kokoroSHA(bytes), "license": license], bytes)
    }
}

/// A model folder as a finished download leaves it.
func kokoroDownloadedRoot(version: Int = KokoroModelStore.version) -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "kokoro-\(UUID().uuidString)", directoryHint: .isDirectory)
    let files = kokoroFixtureFiles()
    for f in files {
        let url = root.appending(path: f.entry["dest"] as! String)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! f.bytes.write(to: url)
    }
    try! kokoroManifestJSON(files: files.map(\.entry), version: version).write(to: root.appending(path: KokoroInstall.keptName))
    KokoroInstall.invalidate()
    return root
}

/// Renders a chirp per piece (its pitch from the tokens), so a stand-in can be looked for in files; or NaN, silence, or
/// "too long" past `maxTokens`, to test the guards.
nonisolated final class ChirpRenderer: KokoroRenderer, @unchecked Sendable {
    enum Mode { case chirp, nan, silent }
    let mode: Mode
    let maxTokens: Int
    private let lock = NSLock()
    private var calls: [[Int32]] = []
    var rendered: [[Int32]] { lock.lock(); defer { lock.unlock() }; return calls }

    init(_ mode: Mode = .chirp, maxTokens: Int = 512) {
        self.mode = mode
        self.maxTokens = maxTokens
    }

    func render(_ tokens: [Int32], voice: Int, speed: Float) throws -> [Float] {
        guard tokens.count <= maxTokens else { throw KokoroRenderError.tooLong }
        lock.lock()
        calls.append(tokens)
        lock.unlock()
        let n = 12_000
        switch mode {
        case .nan: return [Float](repeating: 0.2, count: n - 1) + [.nan]
        case .silent: return [Float](repeating: 0, count: n)
        case .chirp:
            let f0 = 300.0 + Double(tokens.reduce(0) { ($0 &* 31 &+ Int($1)) % 997 }) / 3 + Double(voice * 7)
            return (0..<n).map { i in
                let t = Double(i) / 24_000
                return 0.3 * Float(sin(2 * .pi * (f0 * t + 1_800 * t * t)))
            }
        }
    }
}

func kokoroReader(_ script: PlayScript?, renderer: ChirpRenderer = ChirpRenderer(), root: URL = kokoroDownloadedRoot(),
                  maxSymbols: Int = Kokoro.pieceSymbols) -> KokoroReader {
    let phonemes = script.map(kokoroPhonemeFile)
    return KokoroReader(root: root, phonemes: { _ in phonemes }, loader: { _, _ in renderer }, maxSymbols: maxSymbols)
}

private func line(_ id: String, _ role: String?, _ kind: ScriptLine.Kind, _ text: String) -> ScriptLine {
    kind == .speech ? ScriptLine(id: id, kind: .speech, role: role, parts: [.say(text)]) : ScriptLine(id: id, kind: kind, source: text)
}

private func script() -> PlayScript {
    let lines = [
        line("L0001", nil, .direction, "(A kitchen.)"),
        line("L0002", "FIBBER", .speech, "Well, _Molly_."),
        line("L0003", "MOLLY", .speech, "Yes, dearie?"),
        line("L0004", "MOLLY", .speech, "Come in."),
        line("L0005", "FIBBER", .speech, "Good night."),
    ]
    return PlayScript(id: "gut-0", revision: "r1", kind: "radio", title: "Good Grammar", authors: [],
                      source: .init(name: "Fixture", url: "https://example.org"),
                      rights: .init(bucket: "script_source_cleared", evidence: []),
                      roles: ["MOLLY", "FIBBER"].map { n in .init(name: n, lines: 2, words: 2) }, lines: lines)
}

private let molly = PartID.role("MOLLY"), fibber = PartID.role("FIBBER")
private nonisolated let systemVoices = [CastVoice(id: "com.ava", name: "Ava", language: "en-US", tier: 2, gender: .female),
                                        CastVoice(id: "com.tom", name: "Tom", language: "en-US", tier: 1, gender: .male)]

// MARK: - The pure parts

struct KokoroCoreTests {
    @Test func noVoicesUntilDownloadedThenAll28BestGradeFirstNamedAsKokoro() {
        #expect(Kokoro.castable(ready: false).isEmpty)
        let v = Kokoro.castable(ready: true)
        #expect(v.count == 28)
        #expect(v.prefix(4).map(\.id) == ["af_heart", "af_bella", "af_nicole", "bf_emma"])
        #expect(v.allSatisfy { $0.engine == .kokoro && $0.name.hasSuffix(" (Kokoro)") && $0.displayName == $0.name })
        #expect(v[0].name == "Heart (Kokoro)")
        #expect(v.first { $0.id == "af_sky" }?.gender == .female)
        #expect(v.first { $0.id == "bm_george" }?.gender == .male)
        #expect(v.first { $0.id == "bm_george" }?.language == "en-GB")
        #expect(Kokoro.voiceTableBytes == 14_622_720)
    }

    @Test func tokenizePadsWithZeroBothEndsAndDropsSymbolsTheVocabularyLacks() throws {
        #expect(Kokoro.tokenize("hˌa ¤.", vocab: kokoroFixtureVocab) == [0, 50, 157, 43, 16, 4, 0])
        #expect(Kokoro.tokenize("", vocab: kokoroFixtureVocab) == [0, 0])
        #expect(try Kokoro.parseVocab(kokoroVocabJSON(["a": 43, "ˈ": 156])) == ["a": 43, "ˈ": 156])
    }

    @Test func chunksNeverPassTheLimitCutAtPunctuationAndJoinBack() {
        let ps = String(repeating: "ðə kˈæt sˈæt ˌɔn ðə mˈæt. ", count: 40)
        let parts = Kokoro.chunks(ps, max: 100)
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.count <= 100 })
        #expect(parts.joined() == ps)
        #expect(parts.dropLast().allSatisfy { $0.hasSuffix(". ") || $0.hasSuffix(".") })
        #expect(Kokoro.chunks("short") == ["short"])
        let noBreak = String(repeating: "a", count: 250)
        #expect(Kokoro.chunks(noBreak, max: 100).joined() == noBreak)
    }

    @Test func theStyleRowIsTheVoicesRowForTheUnpaddedLengthCappedAtTheLastRow() {
        #expect(Kokoro.styleOffset(voice: 3, tokenCount: 7) == (3 * 510 + 5) * 256)
        #expect(Kokoro.styleOffset(voice: 0, tokenCount: 2_000) == 509 * 256)
        #expect(Kokoro.styleOffset(voice: 0, tokenCount: 2) == 0)
        let table = (0..<(28 * 510 * 256)).map(Float.init)
        let s = Kokoro.style(table, voice: 1, tokenCount: 12)
        #expect(s.count == 256 && s[0] == Float((510 + 10) * 256))
    }

    @Test func framesRoundHalfToEvenAtLeastOneAndTheAlignmentRepeatsEachToken() {
        #expect(Kokoro.frames([0.2, 0.5, 1.5, 2.5, 3.49, .nan]) == [1, 1, 2, 2, 3, 1], "kokoro's torch.round, then clamp(min=1)")
        #expect(Kokoro.alignment([1, 3, 2]) == [0, 1, 1, 1, 2, 2])
        #expect(Kokoro.bucket(65, in: [128, 64, 256]) == 128)
        #expect(Kokoro.bucket(300, in: [64, 128, 256]) == nil)
    }

    @Test func aRenderWithAnyNonFiniteSampleOrOnlyNearSilenceIsNeverPlayed() {
        #expect(Kokoro.audible([0, 0.2, -0.3]))
        #expect(!Kokoro.audible([0.2, .nan, 0.1]))
        #expect(!Kokoro.audible([0.2, .infinity]))
        #expect(!Kokoro.audible([Float](repeating: 0, count: 24_000)))
        #expect(!Kokoro.audible([]))
    }

    @Test func speedCarriesTheTempoAndPitchThePlaybackRateClamped() {
        #expect(Kokoro.speedFor(rate: 1, pitch: 1) == 1)
        #expect(abs(Kokoro.speedFor(rate: 1, pitch: 0.8) - 1.25) < 1e-6)
        #expect(Kokoro.speedFor(rate: 2, pitch: 0.5) == 2)
        #expect(Kokoro.speedFor(rate: 0.5, pitch: 1.5) == 0.5)
    }

    @Test func aBritishVoiceReadsTheGBPhonemesWhereTheFileHasThem() throws {
        let row = PhonemeLine(id: "L1", t: "Tea?", us: "tˈi?", gb: "tˈiː?")
        #expect(Kokoro.phonemes(row, voice: try #require(Kokoro.voice("bf_emma"))) == "tˈiː?")
        #expect(Kokoro.phonemes(row, voice: try #require(Kokoro.voice("af_heart"))) == "tˈi?")
        #expect(Kokoro.phonemes(PhonemeLine(id: "L1", t: "Tea?", us: "tˈi?"), voice: try #require(Kokoro.voice("bm_lewis"))) == "tˈi?")
        #expect(Kokoro.keyOf("  Well,\n _Molly_. ") == "Well, Molly.")
        // Hear in Library > Voices reads the opening through OpeningSpeech.clean; it must find the script's row.
        let printed = "--Ah--this is the place--very quiet, retired, romantic--et cetera"
        #expect(Kokoro.keyOf(OpeningSpeech.clean(printed)) == Kokoro.keyOf(printed))
    }

    @Test func theManifestIsAcceptedOnlyWithPermissiveCoreMLFilesTheAppsVoicesAndNeverFP16() throws {
        let files = kokoroFixtureFiles().map(\.entry)
        let m = try KokoroManifest.accept(kokoroManifestJSON(files: files))
        #expect(Set(m.files.map(\.role)) == ["duration", "decoder", "voices", "vocab"])
        #expect(m.files("duration").first?.place == "KokoroDuration.mlpackage/Manifest.json")
        func refused(_ label: String, _ data: Data) {
            #expect(throws: KokoroManifest.Refusal.self, "\(label) was accepted") { try KokoroManifest.accept(data) }
        }
        func with(_ role: String, _ key: String, _ value: Any) -> [[String: Any]] {
            files.map { f in
                var f = f
                if f["role"] as? String == role { f[key] = value }
                return f
            }
        }
        refused("a GPL file", kokoroManifestJSON(files: kokoroFixtureFiles(license: "GPL-3.0").map(\.entry)))
        refused("no license", kokoroManifestJSON(files: kokoroFixtureFiles(license: "").map(\.entry)))
        refused("fp16", kokoroManifestJSON(files: files, precision: "fp16"))
        refused("an ONNX manifest", kokoroManifestJSON(files: files, runtime: "onnx"))
        refused("other voices", kokoroManifestJSON(files: files, voices: ["af_heart"]))
        refused("no decoder", kokoroManifestJSON(files: files.filter { $0["role"] as? String != "decoder" }))
        refused("a place outside the folder", kokoroManifestJSON(files: with("decoder", "dest", "../x/Manifest.json")))
        refused("an absolute place", kokoroManifestJSON(files: with("decoder", "dest", "/etc/x")))
        refused("an asset name with a slash", kokoroManifestJSON(files: with("vocab", "path", "a/b.json")))
        refused("a short voice table", kokoroManifestJSON(files: with("voices", "bytes", 10)))
        refused("no buckets", kokoroManifestJSON(files: files, frameBuckets: []))
        refused("not JSON", Data("<html>".utf8))
    }
}

// MARK: - The download

/// A Release asset host: serves the fixture files with Range, counts requests, can cut a body short or corrupt one.
private nonisolated final class FakeRelease: @unchecked Sendable {
    private let lock = NSLock()
    var assets: [String: Data]
    private(set) var requests: [(name: String, from: Int)] = []
    var cutAt: [String: Int] = [:]

    init(manifest: Data, files: [(entry: [String: Any], bytes: Data)]) {
        var a = [KokoroModelStore.manifestName: manifest]
        for f in files { a[f.entry["path"] as! String] = f.bytes }
        assets = a
    }

    var fetch: KokoroModelStore.Fetch {
        { [self] url, file, progress in
            let name = url.lastPathComponent
            let fm = FileManager.default
            if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil) }
            let have = (try fm.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            let (body, cut) = lock.withLock { () -> (Data?, Int?) in
                requests.append((name, have))
                return (assets[name], cutAt.removeValue(forKey: name))
            }
            guard let body else { throw URLError(.fileDoesNotExist) }
            let end = min(body.count, cut ?? body.count)
            let h = try FileHandle(forWritingTo: file)
            try h.seekToEnd()
            if have < end { try h.write(contentsOf: body[have..<end]) }
            try h.close()
            progress(Int64(end))
            if cut != nil { throw URLError(.networkConnectionLost) }
        }
    }

    func requested(_ name: String) -> [Int] { lock.lock(); defer { lock.unlock() }; return requests.filter { $0.name == name }.map(\.from) }
}

@MainActor
struct KokoroModelStoreTests {
    private func host() -> (FakeRelease, URL) {
        let files = kokoroFixtureFiles()
        let release = FakeRelease(manifest: kokoroManifestJSON(files: files.map(\.entry)), files: files)
        let root = FileManager.default.temporaryDirectory.appending(path: "kokoro-dl-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (release, root)
    }

    @Test func aDownloadFetchesEveryFileChecksItAndKeepsTheManifestLast() async throws {
        let (release, root) = host()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KokoroModelStore(root: root, fetch: release.fetch)
        #expect(store.state == .absent && !store.ready)
        store.download()
        await store.wait()
        #expect(store.state == .ready)
        let m = try #require(KokoroInstall.manifest(at: root))
        #expect(m.files.count == 4)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "KokoroDecoder.mlpackage/Manifest.json").path))
        #expect(KokoroInstall.castable(at: root).count == 28, "the 28 voices appear once the model is here")
        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true, "a re-downloadable model stays out of backups")
        await store.delete()
        #expect(store.state == .absent)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(KokoroInstall.castable(at: root).isEmpty, "Delete takes the voices away")
    }

    @Test func aStoppedDownloadResumesWhereItStopped() async throws {
        let (release, root) = host()
        defer { try? FileManager.default.removeItem(at: root) }
        release.cutAt["kokoro-v3-voices-en.bin"] = 5_000_000
        let store = KokoroModelStore(root: root, fetch: release.fetch)
        store.download()
        await store.wait()
        #expect(store.state == .failed)
        #expect(KokoroInstall.manifest(at: root) == nil, "no manifest is kept until every file is whole")
        store.clearFailure()
        store.download()
        await store.wait()
        #expect(store.state == .ready)
        #expect(release.requested("kokoro-v3-voices-en.bin") == [0, 5_000_000], "the second request starts where the first stopped")
        #expect(release.requested("kokoro-v3-KokoroDuration.mlpackage-Manifest.json") == [0], "a whole, checked file is not fetched again")
    }

    @Test func aFileWhoseChecksumDiffersIsDeletedAndTheDownloadFails() async throws {
        let (release, root) = host()
        defer { try? FileManager.default.removeItem(at: root) }
        release.assets["kokoro-v3-tokenizer.json"] = Data(count: kokoroVocabJSON().count)
        let store = KokoroModelStore(root: root, fetch: release.fetch)
        store.download()
        await store.wait()
        #expect(store.state == .failed)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "tokenizer.json").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "next/tokenizer.json.part").path))
        #expect(KokoroInstall.manifest(at: root) == nil)
    }

    @Test func anOlderModelKeepsWorkingUntilTheNewOneIsWhole() async throws {
        let (release, _) = host()
        let root = kokoroDownloadedRoot(version: KokoroModelStore.version - 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KokoroModelStore(root: root, fetch: release.fetch)
        #expect(store.ready && store.outdated, "the older model counts as downloaded")
        release.cutAt["kokoro-v3-voices-en.bin"] = 5_000_000
        store.download()
        await store.wait()
        #expect(store.ready && store.outdated, "a stopped fetch leaves the older model in use")
        #expect(KokoroInstall.manifest(at: root)?.version == KokoroModelStore.version - 1)
        #expect(KokoroInstall.castable(at: root).count == 28)
        release.cutAt.removeAll()
        store.download()
        await store.wait()
        #expect(store.ready && !store.outdated)
        #expect(KokoroInstall.manifest(at: root)?.version == KokoroModelStore.version)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "next").path))
    }
}

// MARK: - The reader

struct KokoroReaderTests {
    @Test func aLineIsReadFromItsPublishedPhonemesInPiecesEachMarkedSynthetic() async throws {
        let renderer = ChirpRenderer()
        let reader = kokoroReader(script(), renderer: renderer, maxSymbols: 7)
        #expect(await reader.prepare("gut-0"))
        #expect(await reader.canRead("gut-0", "Well, _Molly_."), "keyed by the words, italic marks dropped")
        let pieces = PiecesBox()
        let ok = await reader.renderPieces("gut-0", "Well, Molly.", voice: "af_heart", speed: 1) { pieces.add($0) }
        #expect(ok)
        #expect(pieces.all.count == 2, "\"well, molly.\" in pieces of at most 7 symbols, cut at the comma")
        #expect(pieces.all.allSatisfy(SyntheticAudio.isSynthetic), "every piece is marked synthetic")
        #expect(renderer.rendered.first == Kokoro.tokenize("well,", vocab: kokoroFixtureVocab))
        let whole = try #require(await reader.render("gut-0", "Come in.", voice: "bm_george", speed: 1))
        #expect(SyntheticAudio.isSynthetic(whole))
        #expect(renderer.rendered.last == Kokoro.tokenize("in. ", vocab: kokoroFixtureVocab), "a British voice reads gb")
    }

    @Test func aLineWithoutPhonemesOrAPlayWithoutThemIsNotReadByKokoro() async {
        let reader = kokoroReader(script())
        #expect(await reader.render("gut-0", "A line the file lacks.", voice: "af_heart", speed: 1) == nil)
        let held = kokoroReader(nil)
        #expect(await held.prepare("gut-9") == false, "a play held for review has no phoneme file")
        #expect(await held.render("gut-9", "Come in.", voice: "af_heart", speed: 1) == nil)
        #expect(await reader.render("gut-0", "Come in.", voice: "xx_none", speed: 1) == nil, "an unknown voice")
    }

    @Test func aNonFiniteOrSilentRenderFallsBackToTheSystemVoice() async {
        #expect(await kokoroReader(script(), renderer: ChirpRenderer(.nan)).render("gut-0", "Come in.", voice: "af_heart", speed: 1) == nil)
        #expect(await kokoroReader(script(), renderer: ChirpRenderer(.silent)).render("gut-0", "Come in.", voice: "af_heart", speed: 1) == nil)
    }

    @Test func aPieceTooLongForTheBucketsIsSplitAndRead() async throws {
        let renderer = ChirpRenderer(maxTokens: 10)
        let reader = kokoroReader(script(), renderer: renderer, maxSymbols: 100)
        _ = try #require(await reader.render("gut-0", "Yes, dearie?", voice: "af_heart", speed: 1))
        #expect(renderer.rendered.count >= 2 && renderer.rendered.allSatisfy { $0.count <= 10 })
    }

    @Test func noModelNoKokoro() async {
        let empty = FileManager.default.temporaryDirectory.appending(path: "kokoro-none-\(UUID().uuidString)")
        let reader = kokoroReader(script(), root: empty)
        #expect(!reader.ready())
        #expect(await reader.render("gut-0", "Come in.", voice: "af_heart", speed: 1) == nil)
    }
}

nonisolated final class PiecesBox: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [[Float]] = []
    var all: [[Float]] { lock.lock(); defer { lock.unlock() }; return list }
    func add(_ p: [Float]) { lock.lock(); list.append(p); lock.unlock() }
}

// MARK: - The cast

struct KokoroCastTests {
    private func cast(downloaded: [CastVoice]) -> VoiceCast {
        let box = DownloadedBox(downloaded)
        return VoiceCast(key: "p:k-\(UUID().uuidString)", playID: "gut-0", parts: script().castParts.map(\.id),
                         voices: { systemVoices }, downloaded: { box.now }, defaults: { .empty }, storage: .memory())
    }

    @Test func theDefaultCastsKokoroFirstWhereItIsDownloadedAndNothingIsStored() {
        let without = cast(downloaded: [])
        #expect(script().castParts.map(\.id).filter(\.isSpeaking).allSatisfy { without.resolve($0).voice?.engine == .system },
                "no download: the device's own voices")
        let storage = CastStorage.memory()
        let c = VoiceCast(key: "p:k-default", playID: "gut-0", parts: script().castParts.map(\.id), voices: { systemVoices },
                          downloaded: { Kokoro.castable(ready: true) }, defaults: { .empty }, storage: storage)
        let speaking = script().castParts.map(\.id).filter(\.isSpeaking)
        #expect(speaking.allSatisfy { c.resolve($0).voice?.engine == .kokoro && c.resolve($0).isDefault }, "downloaded: Kokoro leads every Default")
        #expect(storage.read() == nil, "and a download is never written into the cast")
        #expect(c.resolve(speaking[0]).voice?.id == "af_heart", "the best grade reads the largest part")
    }

    @Test func aPartCastToAKokoroVoiceReadsItAndItsSystemFallbackIsTheAutoCastVoice() throws {
        let c = cast(downloaded: Kokoro.castable(ready: true))
        let heart = try #require(Kokoro.castable(ready: true).first { $0.id == "af_heart" })
        c.set(molly) { $0 = VoiceCastEntry(engine: .kokoro, voice: heart.id, name: heart.displayName) }
        let r = c.resolve(molly)
        #expect(r.read && r.voice?.engine == .kokoro && r.voice?.id == "af_heart" && r.missing == nil)
        let fb = c.systemFallback(molly)
        #expect(fb.voice?.engine == .system && fb.voice?.id == VoiceCasting.autoCast(c.parts, systemVoices)[molly]?.voice,
                "MOLLY's auto-cast system voice")
        c.set(fibber) { $0 = VoiceCastEntry(engine: .system, voice: "com.tom", name: "Tom") }
        #expect(c.systemFallback(fibber) == c.resolve(fibber), "a system part reads as resolved")
    }

    @Test func afterDeleteAKokoroPartFallsBackVisiblyAndItsChoiceReturnsWithTheDownload() {
        let box = DownloadedBox(Kokoro.castable(ready: true))
        let c = VoiceCast(key: "p:k-\(UUID().uuidString)", playID: "gut-0", parts: script().castParts.map(\.id),
                          voices: { systemVoices }, downloaded: { box.now }, storage: .memory())
        c.set(molly) { $0 = VoiceCastEntry(engine: .kokoro, voice: "af_heart", name: "Heart (Kokoro)") }
        box.now = []
        let gone = c.resolve(molly)
        #expect(gone.read && gone.voice?.engine == .system && gone.missing == "Heart (Kokoro)")
        box.now = Kokoro.castable(ready: true)
        #expect(c.resolve(molly).voice?.id == "af_heart")
    }
}

private nonisolated final class DownloadedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [CastVoice]
    init(_ l: [CastVoice]) { list = l }
    var now: [CastVoice] {
        get { lock.lock(); defer { lock.unlock() }; return list }
        set { lock.lock(); list = newValue; lock.unlock() }
    }
}
