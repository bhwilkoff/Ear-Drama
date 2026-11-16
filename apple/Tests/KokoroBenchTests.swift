import Foundation
import Testing

// The S6a gate on the Mac (R2-kokoro-feasibility §6, S6e): the shipping reader and Core ML engine over the real model,
// muted, from the test runner (not sandboxed, so it reads a model folder anywhere). Skipped unless a folder is given:
//
//     TEST_RUNNER_KOKORO_BENCH_ROOT=/path/to/model TEST_RUNNER_KOKORO_BENCH_MINUTES=3 \
//         xcodebuild test -scheme EarDrama -destination platform=macOS -only-testing:EarDramaTests/KokoroModelBenchTests
//
// The folder is what a finished download leaves (manifest.json beside each file at its `dest`). The bench writes its JSON
// to the temporary directory, never audio. The quality door (docs/research/design/kokoro-spike/coreml_asr_check.py) is the
// one place a Kokoro render reaches a file: raw float32 renders of the measurement's lines in the folder the harness
// names (TEST_RUNNER_KOKORO_QUALITY_OUT, a scratch folder), for a local Whisper to transcribe; never in the app.
@MainActor
struct KokoroModelBenchTests {
    nonisolated static let env = ProcessInfo.processInfo.environment

    @Test(.enabled(if: env["KOKORO_BENCH_ROOT"] != nil), .timeLimit(.minutes(60)))
    func theRealModelReadsEveryLineWithinTheGate() async throws {
        var o = KokoroBench.Options(Self.env.reduce(into: [:]) { out, kv in
            if kv.key.hasPrefix("KOKORO_BENCH_") { out["APP_" + kv.key] = kv.value }
        })
        o.resultFile = FileManager.default.temporaryDirectory.appending(path: "kokoro-bench.json")
        let result = try #require(await KokoroBench.run(o))
        print("KOKORO_BENCH_FILE \(o.resultFile.path)")
        #expect(result["refused"] as? Int == 0)
        let rtf = try #require(result["rtf"] as? Double)
        #expect(rtf > 0 && rtf <= 0.7)
    }

    struct QualityLines: Decodable {
        struct Line: Decodable { let us: String }
        let voices: [String: Int]
        let lines: [Line]
    }

    @Test(.enabled(if: env["KOKORO_BENCH_ROOT"] != nil && env["KOKORO_QUALITY_LINES"] != nil && env["KOKORO_QUALITY_OUT"] != nil),
          .timeLimit(.minutes(30)))
    func theRealModelRendersTheQualityLines() async throws {
        let root = URL(filePath: try #require(Self.env["KOKORO_BENCH_ROOT"]), directoryHint: .isDirectory)
        let out = URL(filePath: try #require(Self.env["KOKORO_QUALITY_OUT"]), directoryHint: .isDirectory)
        let spec = try JSONDecoder().decode(QualityLines.self, from: Data(contentsOf: URL(filePath: try #require(Self.env["KOKORO_QUALITY_LINES"]))))
        KokoroInstall.invalidate()
        let m = try #require(KokoroInstall.manifest(at: root))
        let vocab = try Kokoro.parseVocab(Data(contentsOf: root.appending(path: try #require(m.files("vocab").first).place)))
        let engine = try await CoreMLKokoroRenderer.load(root: root, manifest: m)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (name, index) in spec.voices {
            for (i, line) in spec.lines.enumerated() {
                var all: [Float] = []
                for piece in Kokoro.chunks(line.us, max: Kokoro.pieceSymbols) {
                    let tokens = Kokoro.tokenize(piece, vocab: vocab)
                    guard tokens.count > 2 else { continue }
                    all += try engine.render(tokens, voice: index, speed: 1)
                }
                #expect(Kokoro.audible(all), "\(name) line \(i)")
                try all.withUnsafeBytes { try Data($0).write(to: out.appending(path: "coreml_\(name)_\(i).f32")) }
            }
        }
    }
}
