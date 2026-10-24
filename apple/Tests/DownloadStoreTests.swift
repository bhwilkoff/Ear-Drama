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

/// Decision 071: a season or a whole run asked for at once, the space it
/// takes, the Downloads place's grouping, a series removed, and the player
/// choosing the file only when it is finished.
struct DownloadRunTests {
    private func makeStore(_ transport: FakeTransport = FakeTransport()) -> DownloadStore {
        DownloadStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("downloads-\(UUID().uuidString)", isDirectory: true), transport: transport)
    }

    private func tempFile(bytes: Int) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString).tmp")
        try Data(repeating: 0x55, count: bytes).write(to: file)
        return file
    }

    private func request(_ id: String, bytes: Int64? = 1_000) -> DownloadRequest {
        DownloadRequest(episodeID: id, title: id, seriesName: DownloadRecord.seriesKey(of: id).capitalized,
                        url: URL(string: "https://archive.org/download/x/\(DownloadStore.fileStem(id)).mp3")!,
                        estimatedBytes: bytes)
    }

    private func finish(_ store: DownloadStore, _ id: String, bytes: Int = 64) throws {
        let token = try #require(store.record(for: id)?.token)
        store.transferFinished(token: token, location: try tempFile(bytes: bytes), httpStatus: 200)
    }

    private func detail(kbps: Int?, seconds: Double?) -> EpisodeDetail {
        let episode = EpisodeRow(id: "suspense|1943-05-25", seriesKey: "suspense", seriesName: "Suspense",
                                 airDate: "1943-05-25", season: "1942-43", number: nil, title: "Sorry, Wrong Number",
                                 lengthSeconds: seconds, rights: "unclaimed", rightsBasis: nil, network: "CBS")
        let recording = Recording(rank: 0, archiveID: "OTRR_Suspense", url: URL(string: "https://archive.org/download/a/b.mp3")!,
                                  format: "VBR MP3", kbps: kbps, lengthSeconds: seconds, variant: nil, partial: false)
        return EpisodeDetail(episode: episode, sponsor: nil, credits: [], recordings: [recording], rightsLine: nil)
    }

    @Test func theSeriesKeyIsTheIDBeforeItsBar() {
        #expect(DownloadRecord.seriesKey(of: "suspense|1943-05-25") == "suspense")
        #expect(DownloadRecord.seriesKey(of: "x|y|z") == "x")
        #expect(DownloadRecord.seriesKey(of: "lonely") == "lonely")
    }

    @Test func aRequestEstimatesBitrateTimesLength() throws {
        // 128 kbps for 30 minutes is 128,000 / 8 bytes a second for 1,800 s.
        let full = try #require(DownloadRequest(detail(kbps: 128, seconds: 1_800)))
        #expect(full.estimatedBytes == 28_800_000)
        #expect(full.title == "Sorry, Wrong Number")
        #expect(DownloadRequest(detail(kbps: nil, seconds: 1_800))?.estimatedBytes == nil)
        #expect(DownloadRequest(detail(kbps: 128, seconds: nil))?.estimatedBytes == nil)
        let none = EpisodeDetail(episode: detail(kbps: 1, seconds: 1).episode, sponsor: nil, credits: [],
                                 recordings: [], rightsLine: nil)
        #expect(DownloadRequest(none) == nil)
    }

    @Test func aPlanSkipsWhatIsDownloadedOrRunningAndRetriesWhatFailed() throws {
        let transport = FakeTransport()
        let store = makeStore(transport)
        store.download(DownloadPlan([request("s|1"), request("s|2"), request("s|3")], records: [:]))
        try finish(store, "s|1")
        let failing = try #require(store.record(for: "s|3")?.token)
        store.transferFailed(token: failing, message: "lost")
        // s|1 finished, s|2 running, s|3 failed, s|4 new, s|4 asked twice.
        let plan = DownloadPlan([request("s|1"), request("s|2"), request("s|3"), request("s|4"), request("s|4", bytes: nil)],
                                records: store.records)
        #expect(plan.requests.map(\.episodeID) == ["s|3", "s|4"])
        #expect(plan.estimatedBytes == 2_000)
        #expect(store.missing(["s|1", "s|2", "s|3", "s|4"]) == ["s|3", "s|4"])
        store.download(plan)
        #expect(transport.begun.count == 5)
        #expect(store.record(for: "s|3")?.state == .queued)
        #expect(DownloadPlan([request("s|9", bytes: nil)], records: [:]).estimatedBytes == nil)
    }

    @Test func thePlaceGroupsBySeriesInTheOrderAsked() throws {
        let store = makeStore()
        store.download(DownloadPlan([request("suspense|3"), request("suspense|1"), request("suspense|2")], records: [:]))
        store.download(DownloadPlan([request("baby|1")], records: [:]))
        let groups = store.seriesGroups
        #expect(groups.map(\.key) == ["baby", "suspense"])
        #expect(groups[1].records.map(\.episodeID) == ["suspense|3", "suspense|1", "suspense|2"])
        #expect(store.hasDownloads(inSeries: "suspense"))
        #expect(!store.hasDownloads(inSeries: "gunsmoke"))
    }

    @Test func removingASeriesLeavesTheOthersAndTheirBytes() throws {
        let transport = FakeTransport()
        let store = makeStore(transport)
        store.download(DownloadPlan([request("suspense|1"), request("suspense|2"), request("baby|1")], records: [:]))
        try finish(store, "suspense|1", bytes: 100)
        try finish(store, "baby|1", bytes: 40)
        #expect(store.totalBytes == 140)
        let running = try #require(store.record(for: "suspense|2")?.token)
        store.removeSeries("suspense")
        #expect(transport.cancelled == [running])
        #expect(store.records.keys.sorted() == ["baby|1"])
        #expect(store.totalBytes == 40)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []
        #expect(files.filter { $0 != DownloadStore.indexName }.count == 1)
    }

    @Test func thePlayerOpensTheFileOnlyOnceItIsFinished() throws {
        let store = makeStore()
        let r = request("suspense|1")
        store.download(DownloadPlan([r], records: [:]))
        let recording = Recording(rank: 0, archiveID: "x", url: r.url, format: nil, kbps: nil,
                                  lengthSeconds: nil, variant: nil, partial: false)
        let hook: (String, Recording) -> URL? = { id, rec in store.localFile(for: id, recording: rec.url) }
        // Queued: the network copy.
        #expect(AudioPlayer.source(episodeID: r.episodeID, recording: recording, localFile: hook) == (r.url, false))
        // Finished: the file on this device.
        try finish(store, r.episodeID)
        let local = AudioPlayer.source(episodeID: r.episodeID, recording: recording, localFile: hook)
        #expect(local.isLocal)
        #expect(local.url.isFileURL)
        #expect(local.url.path.hasPrefix(store.directory.path))
        // Removed: back to the network.
        store.remove(r.episodeID)
        #expect(AudioPlayer.source(episodeID: r.episodeID, recording: recording, localFile: hook) == (r.url, false))
    }
}
