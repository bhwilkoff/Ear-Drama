#if DEBUG && (os(iOS) || os(macOS))
import CoreML
import Darwin
import Foundation

/// The S6a gate for Apple (R2-kokoro-feasibility §6, S6e), the mirror of Android's KokoroBenchActivity: a DEBUG-only
/// door that renders real lines muted (nothing reaches an output) through the shipping reader and engine, in a loop
/// for some minutes, the 28 voices in turn, and logs the real-time factor, the wait for a line's first audio, peak
/// memory (phys_footprint, what jetsam counts, sampled every 20 ms) and the thermal state. The gate: RTF at most 0.7
/// and memory under 600 MB on the iPhone 12.
///
///     APP_KOKORO_BENCH=1              run at launch (downloads the model first if it is not here)
///     APP_KOKORO_BENCH_PLAYS=a,b,c    the plays whose published phonemes are read (Android's three by default)
///     APP_KOKORO_BENCH_LINES=50       how many speech lines, shared across the plays, spread through each
///     APP_KOKORO_BENCH_MINUTES=10     how long the loop runs (at least one pass over the lines)
///     APP_KOKORO_BENCH_UNITS=cpu      Core ML compute units: cpu (the shipping engine's) | gpu | ane | all
///     APP_KOKORO_BENCH_KEEP=2         decoder buckets kept loaded (the engine's default)
///     APP_KOKORO_BENCH_ROOT=/path     a model folder already holding the files (the Mac test runner; skips the store)
///
/// Prints one `KOKORO_BENCH` line per line read and a final `KOKORO_BENCH_RESULT {json}`, and writes the same JSON to
/// Documents/kokoro-bench.json. Writes no audio.
enum KokoroBench {
    struct Options {
        var plays = ["gut-1782", "gut-44302-3", "gut-70684-2"]
        var lines = 50
        var minutes = 10.0
        var unitsName = "cpu"
        var keep = CoreMLKokoroRenderer.defaultKeepDecoders
        var root: URL?
        var resultFile = URL.documentsDirectory.appending(path: "kokoro-bench.json")

        init() {}

        init(_ env: [String: String]) {
            if let p = env["APP_KOKORO_BENCH_PLAYS"] { plays = p.split(separator: ",").map(String.init) }
            lines = Int(env["APP_KOKORO_BENCH_LINES"] ?? "") ?? lines
            minutes = Double(env["APP_KOKORO_BENCH_MINUTES"] ?? "") ?? minutes
            unitsName = env["APP_KOKORO_BENCH_UNITS"] ?? unitsName
            keep = Int(env["APP_KOKORO_BENCH_KEEP"] ?? "") ?? keep
            root = env["APP_KOKORO_BENCH_ROOT"].map { URL(filePath: $0, directoryHint: .isDirectory) }
        }

        var units: MLComputeUnits {
            switch unitsName {
            case "cpu": .cpuOnly
            case "gpu": .cpuAndGPU
            case "ane": .cpuAndNeuralEngine
            default: .all
            }
        }
    }

    static func runIfAsked(_ env: [String: String] = ProcessInfo.processInfo.environment) async {
        guard env["APP_KOKORO_BENCH"] == "1" else { return }
        await run(Options(env))
    }

    /// Runs the bench and returns its summary (nil when it could not run; the reason is logged and written).
    @discardableResult
    static func run(_ o: Options) async -> [String: Any]? {
        let resultFile = o.resultFile
        try? FileManager.default.removeItem(at: resultFile)  // a harness never reads an earlier run's result
        let peak = PeakMemory()
        peak.start()
        defer { peak.stop() }
        log("start device=\(device()) plays=\(o.plays.joined(separator: ",")) lines=\(o.lines) minutes=\(o.minutes) "
            + "units=\(o.unitsName) keep=\(o.keep) footprint=\(mb(Memory.footprint())) thermal=\(thermal())")
        let root: URL
        if let given = o.root {
            KokoroInstall.invalidate()
            guard KokoroInstall.manifest(at: given) != nil else { return fail("no model in \(given.path)", to: resultFile) }
            root = given
        } else {
            let store = KokoroModelStore.shared
            if !store.ready {
                log("downloading the model")
                let t0 = Date()
                store.download()
                await store.wait()
                guard store.ready else { return fail("the download did not finish (\(store.state))", to: resultFile) }
                log("downloaded \(Kokoro.megabytes(store.downloadBytes)) in \(String(format: "%.0f", Date().timeIntervalSince(t0))) s")
            }
            root = store.root
        }
        let units = o.units, keep = o.keep
        let reader = KokoroReader(root: root, loader: {
            try await CoreMLKokoroRenderer.load(root: $0, manifest: $1, units: units, keepDecoders: keep)
        })
        var lines: [(play: String, line: PhonemeLine)] = []
        for (k, play) in o.plays.enumerated() {
            guard let data = try? await APIClient.shared.playsData("library/phonemes/\(play).json"),
                  let file = try? JSONDecoder().decode(PhonemeFile.self, from: data) else { return fail("no phonemes for \(play)", to: resultFile) }
            await reader.prepare(play)
            let readable = file.lines.filter { $0.t.count >= 12 }
            let want = o.lines / o.plays.count + (k < o.lines % o.plays.count ? 1 : 0)
            let step = max(1, readable.count / max(1, want))
            lines += stride(from: 0, to: readable.count, by: step).prefix(want).map { (play, readable[$0]) }
            log("play \(play): \(readable.count) readable lines")
        }
        guard !lines.isEmpty else { return fail("no lines", to: resultFile) }
        log("lines \(lines.count), characters mean \(lines.map(\.line.t.count).reduce(0, +) / lines.count)")
        let before = Memory.footprint()
        let loadStart = Date()
        guard await reader.warm() else {
            let why = await reader.lastRefusal
            return fail("load (\(why ?? "?"))", to: resultFile)
        }
        let load = Date().timeIntervalSince(loadStart)
        let loaded = Memory.footprint()
        log("loaded in \(String(format: "%.2f", load)) s footprint before=\(mb(before)) after=\(mb(loaded))")
        var rows: [[String: Any]] = []
        var synth = 0.0, audio = 0.0, firsts: [Double] = [], rtfs: [Double] = [], refused = 0
        var worstThermal = ProcessInfo.processInfo.thermalState
        let started = Date()
        let end = started.addingTimeInterval(o.minutes * 60)
        var i = 0
        while i < lines.count || Date() < end {
            let (play, line) = lines[i % lines.count]
            let voice = Kokoro.voices[i % Kokoro.voices.count].id
            let clock = Clock()
            let t0 = Date()
            let ok = await reader.renderPieces(play, line.t, voice: voice, speed: 1) { piece in
                clock.add(samples: piece.count)
            }
            let secs = Date().timeIntervalSince(t0)
            let heard = Double(clock.samples) / Kokoro.sampleRate
            if ok {
                synth += secs
                audio += heard
                if heard > 0 { rtfs.append(secs / heard) }
                if let f = clock.first { firsts.append(f.timeIntervalSince(t0)) }
            } else {
                refused += 1
            }
            let refusal = ok ? nil : await reader.lastRefusal
            let state = ProcessInfo.processInfo.thermalState
            if state.rawValue > worstThermal.rawValue { worstThermal = state }
            let row: [String: Any] = [
                "i": i, "play": play, "id": line.id, "voice": voice, "characters": line.t.count, "ok": ok,
                "seconds": round3(secs), "audio": round3(heard), "rtf": heard > 0 ? round3(secs / heard) : -1,
                "first": round3(clock.first.map { $0.timeIntervalSince(t0) } ?? -1),
                "footprint_mb": Memory.footprint() / 1_000_000, "thermal": thermal(state),
            ]
            rows.append(row)
            log("line \(i) \(play)/\(line.id) \(voice) characters=\(line.t.count) ok=\(ok) rtf=\(row["rtf"]!) first=\(row["first"]!)s "
                + "audio=\(row["audio"]!)s footprint=\(mb(Memory.footprint())) peak=\(mb(peak.peak)) thermal=\(thermal(state))"
                + (refusal.map { " refusal=\($0)" } ?? ""))
            i += 1
        }
        let sortedFirst = firsts.sorted(), sortedRTF = rtfs.sorted()
        func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? -1 : a[min(a.count - 1, Int(Double(a.count) * p))] }
        let rtf = audio > 0 ? synth / audio : -1
        let peakMB = peak.peak / 1_000_000
        let passes = rtf >= 0 && rtf <= 0.7 && peakMB < 600 && refused == 0
        let result: [String: Any] = [
            "device": device(), "os": ProcessInfo.processInfo.operatingSystemVersionString, "units": o.unitsName, "keep": o.keep,
            "plays": o.plays, "lines": lines.count, "renders": i, "refused": refused, "load_seconds": round3(load),
            "footprint_before_load_mb": before / 1_000_000, "footprint_loaded_mb": loaded / 1_000_000,
            "rtf": round3(rtf), "rtf_p95": round3(pct(sortedRTF, 0.95)), "rtf_max": round3(sortedRTF.last ?? -1),
            "audio_seconds": round3(audio), "synth_seconds": round3(synth),
            "wall_seconds": round3(Date().timeIntervalSince(started)),
            "first_audio_median": round3(pct(sortedFirst, 0.5)), "first_audio_p95": round3(pct(sortedFirst, 0.95)),
            "first_audio_max": round3(sortedFirst.last ?? -1),
            "peak_footprint_mb": peakMB, "thermal_end": thermal(), "thermal_worst": thermal(worstThermal),
            "gate": ["rtf_max": 0.7, "memory_max_mb": 600, "passes": passes],
        ]
        if let s = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            log("RESULT " + String(decoding: s, as: UTF8.self), tag: "KOKORO_BENCH_RESULT")
        }
        var full = result
        full["per_line"] = rows
        if let json = try? JSONSerialization.data(withJSONObject: full, options: [.sortedKeys]) { try? json.write(to: resultFile) }
        return result
    }

    private static func log(_ s: String, tag: String = "KOKORO_BENCH") { print("\(tag) \(s)") }

    private static func fail(_ why: String, to file: URL) -> [String: Any]? {
        log("FAILED: \(why)")
        if let d = try? JSONSerialization.data(withJSONObject: ["failed": why, "device": device()]) { try? d.write(to: file) }
        return nil
    }
    private static func mb(_ b: UInt64) -> String { "\(b / 1_000_000)MB" }
    private static func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }

    private static func thermal(_ s: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) -> String {
        switch s {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func device() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &name, &size, nil, 0)
        return String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// When a line's first audio arrived and how much there was.
    nonisolated private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var first: Date?
        private(set) var samples = 0
        func add(samples n: Int) {
            lock.lock()
            if first == nil { first = Date() }
            samples += n
            lock.unlock()
        }
    }
}

/// The process's physical footprint (what the system counts against an app's memory limit).
nonisolated enum Memory {
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let task = mach_task_self_
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(task, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

/// Samples the footprint every 20 ms on its own thread, keeping the highest.
nonisolated final class PeakMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var highest: UInt64 = 0
    private var running = false

    var peak: UInt64 { lock.lock(); defer { lock.unlock() }; return highest }

    func start() {
        lock.lock()
        running = true
        lock.unlock()
        Thread.detachNewThread { [self] in
            while true {
                let now = Memory.footprint()
                lock.lock()
                highest = max(highest, now)
                let go = running
                lock.unlock()
                if !go { break }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
    }
}
#endif
