import Foundation
import Testing

/// The download store as a state machine over a fake transport: queued ->
/// downloading -> downloaded -> removed, cancel, failure, and the relaunch
/// reconnect. The real background URLSession is not exercised here.
final class FakeTransport: DownloadTransport {
    var begun: [(token: String, url: URL)] = []
    var cancelled: [String] = []
    var cancelledAll = 0
    var live: Set<String> = []

    func begin(token: String, url: URL) { begun.append((token, url)); live.insert(token) }
    func cancel(token: String) { cancelled.append(token); live.remove(token) }
    func cancelAll() { cancelledAll += 1; live.removeAll() }
    func liveTokens() async -> Set<String> { live }
    func finishBackgroundEvents() async {}
}

struct DownloadStoreTests {
    private let url = URL(string: "https://archive.org/download/OTRR_Suspense/Suspense_43-05-25_Sorry_Wrong_Number.mp3")!
    private let id = "suspense|1943-05-25"

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("downloads-\(UUID().uuidString)", isDirectory: true)
    }

    /// A stand-in for the system's temporary file, outside the store's directory.
    private func tempFile(bytes: Int) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString).tmp")
        try Data(repeating: 0x55, count: bytes).write(to: file)
        return file
    }

    /// The files in the store's directory other than its index.
    private func filesOnDisk(_ store: DownloadStore) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? [])
            .filter { $0 != DownloadStore.indexName }.sorted()
    }

    private func start(_ store: DownloadStore) {
        store.download(episodeID: id, title: "Sorry, Wrong Number", seriesName: "Suspense", url: url)
    }

    @Test func queuedThenDownloadingThenDownloadedThenRemoved() throws {
        let transport = FakeTransport()
        let store = DownloadStore(directory: makeDirectory(), transport: transport)
        start(store)
        let token = try #require(store.record(for: id)?.token)
        #expect(store.record(for: id)?.state == .queued)
        #expect(transport.begun.map(\.url) == [url])

        store.transferProgressed(token: token, received: 500, expected: 2000)
        #expect(store.record(for: id)?.state == .downloading)
        #expect(store.record(for: id)?.fraction == 0.25)
        #expect(store.localFile(for: id, recording: url) == nil)

        store.transferFinished(token: token, location: try tempFile(bytes: 2048), httpStatus: 200)
        let record = try #require(store.record(for: id))
        #expect(record.state == .downloaded)
        #expect(store.totalBytes == 2048)
        let local = try #require(store.localFile(for: id, recording: url))
        #expect(local.pathExtension == "mp3")
        #expect(local.path.hasPrefix(store.directory.path))
        // Another recording of the same episode is not the downloaded file.
        #expect(store.localFile(for: id, recording: URL(string: "https://archive.org/other.mp3")!) == nil)
        // Starting again on a finished download does nothing.
        start(store)
        #expect(transport.begun.count == 1)

        store.remove(id)
        #expect(store.record(for: id) == nil)
        #expect(filesOnDisk(store).isEmpty)
        #expect(store.totalBytes == 0)
    }

    @Test func cancelStopsTheTransferAndForgetsIt() throws {
        let transport = FakeTransport()
        let store = DownloadStore(directory: makeDirectory(), transport: transport)
        start(store)
        let token = try #require(store.record(for: id)?.token)
        store.transferProgressed(token: token, received: 100, expected: 2000)
        store.cancel(id)
        #expect(transport.cancelled == [token])
        #expect(store.record(for: id) == nil)
        // The cancelled task's late callbacks change nothing.
        store.transferProgressed(token: token, received: 900, expected: 2000)
        store.transferFinished(token: token, location: try tempFile(bytes: 64), httpStatus: 200)
        #expect(store.record(for: id) == nil)
        #expect(filesOnDisk(store).isEmpty)
    }

    @Test func aStaleTokenNeverFillsANewDownload() throws {
        let transport = FakeTransport()
        let store = DownloadStore(directory: makeDirectory(), transport: transport)
        start(store)
        let old = try #require(store.record(for: id)?.token)
        store.cancel(id)
        start(store)
        let new = try #require(store.record(for: id)?.token)
        #expect(old != new)
        store.transferFinished(token: old, location: try tempFile(bytes: 64), httpStatus: 200)
        #expect(store.record(for: id)?.state == .queued)
    }

    /// A server error page, an empty body, and a transport error each leave
    /// the record failed and NOTHING on disk.
    @Test func aFailedDownloadLeavesNoPartialFile() throws {
        for outcome in ["404", "empty", "error"] {
            let store = DownloadStore(directory: makeDirectory(), transport: FakeTransport())
            start(store)
            let token = try #require(store.record(for: id)?.token)
            store.transferProgressed(token: token, received: 100, expected: 2000)
            switch outcome {
            case "404": store.transferFinished(token: token, location: try tempFile(bytes: 512), httpStatus: 404)
            case "empty": store.transferFinished(token: token, location: try tempFile(bytes: 0), httpStatus: 200)
            default: store.transferFailed(token: token, message: "The network connection was lost.")
            }
            #expect(store.record(for: id)?.state == .failed, "\(outcome)")
            #expect(filesOnDisk(store).isEmpty, "\(outcome) left \(filesOnDisk(store))")
            #expect(store.localFile(for: id, recording: url) == nil)
            #expect(store.totalBytes == 0)
        }
    }

    /// Control: the disk check above can see a partial file when one is left.
    @Test func theDiskCheckSeesALeftoverPartial() throws {
        let store = DownloadStore(directory: makeDirectory(), transport: FakeTransport())
        let partial = store.fileURL("abc.mp3").appendingPathExtension(DownloadStore.partialExtension)
        try Data([1, 2, 3]).write(to: partial)
        #expect(filesOnDisk(store) == ["abc.mp3.partial"])
    }

    @Test func aFailedDownloadCanStartOver() throws {
        let transport = FakeTransport()
        let store = DownloadStore(directory: makeDirectory(), transport: transport)
        start(store)
        let token = try #require(store.record(for: id)?.token)
        store.transferFailed(token: token, message: nil)
        start(store)
        #expect(store.record(for: id)?.state == .queued)
        #expect(transport.begun.count == 2)
    }

    @Test func removeAllEmptiesTheDirectory() throws {
        let transport = FakeTransport()
        let store = DownloadStore(directory: makeDirectory(), transport: transport)
        start(store)
        let token = try #require(store.record(for: id)?.token)
        store.transferFinished(token: token, location: try tempFile(bytes: 100), httpStatus: 200)
        store.download(episodeID: "suspense|1942-06-17", title: "The Burning Court", seriesName: "Suspense",
                       url: URL(string: "https://archive.org/download/x/burning.mp3")!)
        store.removeAll()
        #expect(store.records.isEmpty)
        #expect(transport.cancelledAll == 1)
        #expect(filesOnDisk(store).isEmpty)
        // And a relaunch sees none of it.
        #expect(DownloadStore(directory: store.directory, transport: FakeTransport()).records.isEmpty)
    }

    @Test func theDirectoryIsExcludedFromBackup() throws {
        let store = DownloadStore(directory: makeDirectory(), transport: FakeTransport())
        let values = try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    /// After a process death: a transfer the system still carries stays
    /// downloading, one it dropped is failed, a finished file survives, a
    /// finished record whose file vanished is dropped, an unclaimed file is
    /// swept, and a live task nobody claims is cancelled.
    @Test func relaunchReconnectsToTheSystemsTransfers() async throws {
        let directory = makeDirectory()
        let first = FakeTransport()
        let before = DownloadStore(directory: directory, transport: first)
        let ids = ["a|1", "a|2", "a|3", "a|4"]
        for (n, episode) in ids.enumerated() {
            before.download(episodeID: episode, title: "Episode \(n)", seriesName: "A",
                            url: URL(string: "https://archive.org/download/a/\(n).mp3")!)
        }
        let token = { (episode: String) in before.record(for: episode)!.token }
        before.transferProgressed(token: token("a|1"), received: 10, expected: 100)
        before.transferFinished(token: token("a|3"), location: try tempFile(bytes: 300), httpStatus: 200)
        before.transferFinished(token: token("a|4"), location: try tempFile(bytes: 400), httpStatus: 200)
        let vanished = before.fileURL(before.record(for: "a|4")!.fileName)
        try FileManager.default.removeItem(at: vanished)
        let orphan = directory.appendingPathComponent("leftover.mp3.partial")
        try Data([0]).write(to: orphan)

        let second = FakeTransport()
        second.live = [token("a|1"), "unclaimed-task"]
        let after = DownloadStore(directory: directory, transport: second)
        #expect(after.records.count == 4)
        #expect(!after.isReconnected)
        await after.reconnect()
        #expect(after.isReconnected)
        #expect(after.record(for: "a|1")?.state == .downloading)
        #expect(after.record(for: "a|2")?.state == .failed)
        #expect(after.record(for: "a|3")?.state == .downloaded)
        #expect(after.record(for: "a|4") == nil)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(second.cancelled == ["unclaimed-task"])
        #expect(after.totalBytes == 300)
        // The reconnected transfer still completes into the new process's store.
        after.transferFinished(token: token("a|1"), location: try tempFile(bytes: 100), httpStatus: 200)
        #expect(after.record(for: "a|1")?.state == .downloaded)
        #expect(filesOnDisk(after).count == 2)
    }

    @Test func fileNamesNeverCarryTheEpisodeID() {
        let stem = DownloadStore.fileStem("suspense|../../etc")
        #expect(stem.count == 32)
        #expect(stem.allSatisfy { $0.isHexDigit })
        #expect(stem == DownloadStore.fileStem("suspense|../../etc"))
        #expect(stem != DownloadStore.fileStem("suspense|1943-05-25"))
    }
}
