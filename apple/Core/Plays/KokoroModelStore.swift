#if os(iOS) || os(macOS)
import CryptoKit
import Foundation
import Observation
import os

/// The downloaded Kokoro model on this device (Decision 078; PLAYS-DESIGN §2.8 rule 10): the Apple manifest's files from
/// the GitHub Release `kokoro-model`, under Application Support (never Caches: the system may purge Caches and the
/// voices would vanish mid-play), fetched only when the person asks (Download Voices), resumed with HTTP Range through
/// the one `APIClient`, each file checked against the manifest's SHA-256 before it counts, and removed by Delete. The
/// manifest is written last: its presence beside whole files is what "downloaded" means. Model bytes only: no audio is
/// ever written here.
@MainActor @Observable
final class KokoroModelStore {
    enum State: Equatable {
        case absent
        case downloading(done: Int64, total: Int64)
        case ready
        case failed
    }

    /// Appends a URL's bytes to a file from its current length on (`APIClient.download`).
    typealias Fetch = @Sendable (URL, URL, @escaping @Sendable (Int64) -> Void) async throws -> Void

    static let shared = KokoroModelStore()
    nonisolated static let release = URL(string: "https://github.com/bhwilkoff/Ear-Drama/releases/download/kokoro-model/")!
    nonisolated static let manifestName = "kokoro-v3-apple-manifest.json"
    /// What the picker says before the manifest is read: kokoro-v3-apple-manifest.json's files as published 2026-11-22
    /// (fp32, uncompressed: the compressed conversions failed the check against PyTorch; R2-kokoro-feasibility S6e).
    nonisolated static let knownBytes: Int64 = 532_310_241

    private(set) var state: State = .absent
    let root: URL
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let base: URL
    @ObservationIgnored private let manifestName: String
    @ObservationIgnored private var task: Task<Void, Never>?

    init(root: URL = KokoroInstall.defaultRoot, base: URL = KokoroModelStore.release,
         manifestName: String = KokoroModelStore.manifestName,
         fetch: @escaping Fetch = { try await APIClient.shared.download($0, appendingTo: $1, progress: $2) }) {
        self.root = root
        self.base = base
        self.manifestName = manifestName
        self.fetch = fetch
        state = KokoroInstall.manifest(at: root) != nil ? .ready : .absent
    }

    var ready: Bool { state == .ready }

    /// The bytes a download moves (or moved), as the picker says it.
    var downloadBytes: Int64 { KokoroInstall.manifest(at: root)?.totalBytes ?? Self.knownBytes }

    /// Starts the download (a person's tap; never started for them). A second tap while it runs does nothing.
    func download() {
        guard task == nil, state != .ready else { return }
        state = .downloading(done: 0, total: Self.knownBytes)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run()
                self.state = .ready
            } catch is CancellationError {
                self.state = KokoroInstall.manifest(at: self.root) != nil ? .ready : .absent
            } catch {
                self.state = .failed
            }
            self.task = nil
        }
    }

    /// Waits for a running download (tests, the bench).
    func wait() async { await task?.value }

    /// Stops the download; what is on disk stays, so the next tap resumes it.
    func cancel() { task?.cancel() }

    private func run() async throws {
        let root = root, base = base, fetch = fetch, name = manifestName
        let progress: @Sendable (Int64, Int64) -> Void = { done, total in
            Task { @MainActor in
                guard case .downloading = self.state else { return }
                self.state = .downloading(done: done, total: total)
            }
        }
        try await Task.detached(priority: .utility) {
            try await Self.fetchAll(root: root, base: base, manifestName: name, fetch: fetch, progress: progress)
        }.value
        KokoroInstall.invalidate()
    }

    nonisolated private static func fetchAll(root: URL, base: URL, manifestName: String, fetch: Fetch,
                                             progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var r = root
        try? r.setResourceValues(values)
        let fresh = root.appending(path: "manifest.json.part")
        try? fm.removeItem(at: fresh)
        try await fetch(base.appending(path: manifestName), fresh) { _ in }
        let text = try Data(contentsOf: fresh)
        guard text.count < 1 << 20 else { throw KokoroManifest.Refusal.refused("manifest too large") }
        let m = try KokoroManifest.accept(text)
        let total = m.totalBytes
        var before: Int64 = 0
        for f in m.files {
            try Task.checkCancellation()
            let done = root.appending(path: f.place)
            if (try? done.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == f.bytes,
               (try? sha256(done)) == f.sha256 {
                before += f.bytes
                progress(before, total)
                continue
            }
            try? fm.removeItem(at: done)
            try fm.createDirectory(at: done.deletingLastPathComponent(), withIntermediateDirectories: true)
            let part = root.appending(path: f.place + ".part")
            if size(part) > f.bytes { try? fm.removeItem(at: part) }
            if size(part) < f.bytes {
                let start = before
                try await fetch(base.appending(path: f.path), part) { at in progress(start + at, total) }
            }
            // A body that ended early is kept for the next try to resume from.
            guard size(part) == f.bytes else { throw URLError(.networkConnectionLost) }
            guard try sha256(part) == f.sha256 else {
                try? fm.removeItem(at: part)
                throw KokoroManifest.Refusal.refused("\(f.path): SHA-256 differs from the manifest")
            }
            try fm.moveItem(at: part, to: done)
            before += f.bytes
            progress(before, total)
        }
        let kept = root.appending(path: KokoroInstall.keptName)
        try? fm.removeItem(at: kept)
        try fm.moveItem(at: fresh, to: kept)
    }

    nonisolated private static func size(_ url: URL) -> Int64 {
        Int64((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
    }

    nonisolated static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Removes every downloaded file; the Kokoro voices leave the picker and parts cast to them fall back visibly.
    func delete() async {
        task?.cancel()
        await task?.value
        await KokoroReader.shared.unload()
        let root = root
        await Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: root) }.value
        KokoroInstall.invalidate()
        state = .absent
    }

    /// A failed download's message is cleared when the person tries again.
    func clearFailure() { if state == .failed { state = .absent } }
}

/// What is installed, read without the main actor (the cast resolves parts on any thread): the kept manifest when
/// every file it names is on disk at its size. Cached until a download or Delete says otherwise.
nonisolated enum KokoroInstall {
    static let defaultRoot = URL.applicationSupportDirectory.appending(path: "Kokoro", directoryHint: .isDirectory)
    static let keptName = "manifest.json"

    private static let cache = OSAllocatedUnfairLock<[String: KokoroManifest?]>(initialState: [:])

    static func manifest(at root: URL = defaultRoot) -> KokoroManifest? {
        if let hit = cache.withLock({ $0[root.path] }) { return hit }
        let found = read(root)
        cache.withLock { $0[root.path] = .some(found) }
        return found
    }

    static func invalidate() { cache.withLock { $0.removeAll() } }

    private static func read(_ root: URL) -> KokoroManifest? {
        guard let data = try? Data(contentsOf: root.appending(path: keptName)),
              let m = try? KokoroManifest.accept(data) else { return nil }
        let fm = FileManager.default
        for f in m.files {
            let size = (try? fm.attributesOfItem(atPath: root.appending(path: f.place).path)[.size] as? Int) ?? -1
            if Int64(size) != f.bytes { return nil }
        }
        return m
    }

    /// The Kokoro voices a part may be cast to now: none until the model is here and the engine is on.
    static func castable(at root: URL = defaultRoot) -> [CastVoice] {
        Kokoro.castable(ready: KokoroFlag.enabled && manifest(at: root) != nil)
    }
}

/// The states Settings shows of the Kokoro download.
nonisolated enum KokoroDownloadState: Equatable, Sendable {
    case unsupported
    case absent
    case downloading
    case failed
    case ready

    /// "Better voices" is offered while Kokoro could run here and is not downloaded.
    static func offersBetterVoices(ready: Bool, flag: Bool) -> Bool { flag && !ready }

    static func of(_ s: KokoroModelStore.State, supported: Bool) -> KokoroDownloadState {
        guard supported else { return .unsupported }
        switch s {
        case .absent: return .absent
        case .downloading: return .downloading
        case .failed: return .failed
        case .ready: return .ready
        }
    }
}
#endif
