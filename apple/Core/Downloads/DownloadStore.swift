#if os(iOS) || os(macOS)
import CryptoKit
import Foundation
import Observation

/// One downloaded (or downloading) episode. Persisted in the downloads
/// directory's index, so the list survives a relaunch.
nonisolated struct DownloadRecord: Codable, Hashable, Sendable, Identifiable {
    enum State: String, Codable, Sendable {
        case queued, downloading, downloaded, failed
    }

    let episodeID: String
    var title: String
    var seriesName: String
    /// The recording the file came from (the catalog's rank 0 when it began).
    var remoteURL: URL
    var fileName: String
    var state: State
    var receivedBytes: Int64 = 0
    var expectedBytes: Int64 = 0
    var addedAt: Date
    /// Names the transfer. A late callback from a task that was cancelled
    /// before this record was re-created carries a different token and is
    /// ignored, so it can never fill the new record with the old bytes.
    var token: String

    var id: String { episodeID }
    var isActive: Bool { state == .queued || state == .downloading }
    var fraction: Double? {
        expectedBytes > 0 ? min(1, Double(receivedBytes) / Double(expectedBytes)) : nil
    }
}

/// What moves the bytes. Production is a background URLSession; the tests
/// drive the store's callbacks themselves.
protocol DownloadTransport: AnyObject {
    func begin(token: String, url: URL)
    func cancel(token: String)
    func cancelAll()
    /// The transfers the system is still carrying, by token.
    func liveTokens() async -> Set<String>
    /// Holds until the system has delivered every event of a background
    /// relaunch (iOS).
    func finishBackgroundEvents() async
}

/// Downloads an episode's default recording so it plays with no network
/// (research 04 §2.10; Archive Watch Decision 099's design). The files live in
/// Application Support/Downloads, excluded from backup: re-downloadable public
/// files the listener expects offline, never purged the way Caches is. They are
/// the app's own cache and nothing else: no Files exposure (no
/// UIFileSharingEnabled, no LSSupportsOpeningDocumentsInPlace) and no share
/// sheet, because the app must never export an MP3 (research 04 §11, 5.2.3).
///
/// Every create path has its inverse: `download` / `cancel`, a finished file /
/// `remove`, everything / `removeAll`, and `reconnect` sweeps what a dead
/// process left behind.
@Observable
final class DownloadStore {
    nonisolated static let sessionIdentifier = "app.eardrama.downloads"

    private(set) var records: [String: DownloadRecord] = [:]
    /// False until `reconnect` has compared the index with the live transfers.
    private(set) var isReconnected = false

    let directory: URL
    @ObservationIgnored private let transport: DownloadTransport
    @ObservationIgnored private var lastPublish: [String: Date] = [:]
    @ObservationIgnored private let fileManager = FileManager.default

    static let indexName = "index.json"
    static let partialExtension = "partial"

    init(directory: URL, transport: DownloadTransport) {
        self.directory = directory
        self.transport = transport
        Self.prepare(directory)
        records = Self.loadIndex(in: directory)
    }

    /// The app's store: the background session wired to it.
    static func live() -> DownloadStore {
        let transport = BackgroundDownloadTransport()
        let store = DownloadStore(directory: defaultDirectory(), transport: transport)
        transport.store = store
        return store
    }

    /// Application Support/Downloads, created on first use. On iOS Application
    /// Support does not exist until someone makes it.
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Downloads", isDirectory: true)
    }

    private static func prepare(_ directory: URL) {
        var dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }

    // MARK: - Reads

    func record(for episodeID: String) -> DownloadRecord? { records[episodeID] }

    /// Newest first: what the Library lists.
    var sortedRecords: [DownloadRecord] {
        records.values.sorted { $0.addedAt > $1.addedAt }
    }

    /// Bytes the finished downloads hold on this device.
    var totalBytes: Int64 {
        records.values.filter { $0.state == .downloaded }.reduce(0) { $0 + $1.receivedBytes }
    }

    /// The local file to play instead of `recording`, when this episode's
    /// download of that same recording is finished and on disk.
    func localFile(for episodeID: String, recording: URL) -> URL? {
        guard let r = records[episodeID], r.state == .downloaded, r.remoteURL == recording else { return nil }
        let url = fileURL(r.fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Commands

    /// Downloads the episode's default recording. A queued, running, or
    /// finished download is left alone; a failed one starts over.
    func download(_ detail: EpisodeDetail) {
        guard let recording = detail.defaultRecording else { return }
        download(episodeID: detail.episode.id, title: detail.episode.displayTitle,
                 seriesName: detail.episode.seriesName, url: recording.url)
    }

    func download(episodeID: String, title: String, seriesName: String, url: URL, now: Date = Date()) {
        if let existing = records[episodeID], existing.state != .failed { return }
        if let stale = records[episodeID] { deleteFiles(of: stale) }
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension.lowercased()
        let record = DownloadRecord(
            episodeID: episodeID, title: title, seriesName: seriesName, remoteURL: url,
            fileName: "\(Self.fileStem(episodeID)).\(ext)", state: .queued, addedAt: now,
            token: UUID().uuidString)
        records[episodeID] = record
        saveIndex()
        transport.begin(token: record.token, url: url)
    }

    /// Stops a queued or running download and forgets it.
    func cancel(_ episodeID: String) {
        guard let r = records[episodeID], r.isActive else { return }
        remove(episodeID)
    }

    /// Removes a download in any state: the transfer, the file, the record.
    func remove(_ episodeID: String) {
        guard let r = records.removeValue(forKey: episodeID) else { return }
        if r.isActive { transport.cancel(token: r.token) }
        deleteFiles(of: r)
        lastPublish[r.token] = nil
        saveIndex()
    }

    /// Every download, gone. The files go first and unconditionally: they are
    /// what the listener asked to reclaim.
    func removeAll() {
        transport.cancelAll()
        for name in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [] {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        records = [:]
        lastPublish = [:]
        saveIndex()
    }

    // MARK: - Relaunch

    /// Rebuilds the truth after a process death: a record whose transfer the
    /// system no longer carries failed (the listener can try again), a
    /// finished record whose file is gone is dropped, and a file no record
    /// claims (a half-moved partial, a removal cut short) is deleted, because
    /// it is the one kind of leak nobody can find and clear.
    func reconnect() async {
        let live = await transport.liveTokens()
        var claimed: Set<String> = [Self.indexName]
        for (id, var r) in records {
            switch r.state {
            case .downloaded:
                if fileManager.fileExists(atPath: fileURL(r.fileName).path) {
                    claimed.insert(r.fileName)
                } else {
                    records[id] = nil
                }
            case .queued, .downloading:
                if !live.contains(r.token) {
                    r.state = .failed
                    records[id] = r
                }
            case .failed:
                break
            }
        }
        let tokens = Set(records.values.filter(\.isActive).map(\.token))
        for token in live where !tokens.contains(token) { transport.cancel(token: token) }
        for name in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [] where !claimed.contains(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        saveIndex()
        isReconnected = true
    }

    func handleBackgroundEvents() async {
        await transport.finishBackgroundEvents()
    }

    // MARK: - Transport callbacks (main queue)

    func transferProgressed(token: String, received: Int64, expected: Int64, now: Date = Date()) {
        guard var r = record(token: token), r.isActive else { return }
        // Callbacks arrive per chunk; the Library redraws at most 4 times a second.
        if r.state == .downloading, let last = lastPublish[token], now.timeIntervalSince(last) < 0.25 { return }
        lastPublish[token] = now
        let firstBytes = r.state == .queued
        r.state = .downloading
        r.receivedBytes = received
        if expected > 0 { r.expectedBytes = expected }
        records[r.episodeID] = r
        if firstBytes { saveIndex() }
    }

    /// The system's temporary file is deleted the moment the delegate returns,
    /// so the move happens here, synchronously. The file lands as a partial
    /// and takes its real name only once it is known good; a failure deletes
    /// the partial, so a half file can never reach the player or the disk total.
    func transferFinished(token: String, location: URL, httpStatus: Int?) {
        guard var r = record(token: token), r.isActive else { return }
        lastPublish[token] = nil
        let final = fileURL(r.fileName)
        let partial = final.appendingPathExtension(Self.partialExtension)
        try? fileManager.removeItem(at: partial)
        do {
            try fileManager.moveItem(at: location, to: partial)
            let size = Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            guard (200..<300).contains(httpStatus ?? 200), size > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try? fileManager.removeItem(at: final)
            try fileManager.moveItem(at: partial, to: final)
            r.receivedBytes = size
            r.expectedBytes = size
            r.state = .downloaded
        } catch {
            print("[DownloadStore] \(r.episodeID) did not save: status \(httpStatus ?? 0), \(error.localizedDescription)")
            deleteFiles(of: r)
            r.state = .failed
        }
        records[r.episodeID] = r
        saveIndex()
    }

    /// A transfer ended with an error. A deliberate cancel already removed its
    /// record, so this only ever marks a live download failed.
    func transferFailed(token: String, message: String?) {
        guard var r = record(token: token), r.isActive else { return }
        print("[DownloadStore] \(r.episodeID) failed: \(message ?? "unknown")")
        lastPublish[token] = nil
        deleteFiles(of: r)
        r.state = .failed
        records[r.episodeID] = r
        saveIndex()
    }

    // MARK: - Files

    func fileURL(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// Episode ids carry `|` and come from an open upload system: never a path
    /// component as they are. A digest is fixed-length and collision-free in
    /// practice.
    nonisolated static func fileStem(_ episodeID: String) -> String {
        SHA256.hash(data: Data(episodeID.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func record(token: String) -> DownloadRecord? {
        records.values.first { $0.token == token }
    }

    private func deleteFiles(of record: DownloadRecord) {
        let final = fileURL(record.fileName)
        try? fileManager.removeItem(at: final)
        try? fileManager.removeItem(at: final.appendingPathExtension(Self.partialExtension))
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL(Self.indexName), options: .atomic)
    }

    private static func loadIndex(in directory: URL) -> [String: DownloadRecord] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(indexName)),
              let decoded = try? JSONDecoder().decode([String: DownloadRecord].self, from: data)
        else { return [:] }
        return decoded
    }
}
#endif
