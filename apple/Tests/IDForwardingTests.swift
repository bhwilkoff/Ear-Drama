import Foundation
import Testing

/// Forwarding ids (docs/CATALOG-CONTRACT.md §3.5): every store that keeps an
/// episode id rewrites the ones the catalog moved, once, keeping each row's own
/// stamp. Fixture ids only; nothing here reads the real catalog.
struct IDForwardingTests {
    private let forwarding = IDForwarding(
        aliases: ["jb|1921-03-11": "jb|1943-11-21", "jb|old-slug": "jb|1944-01-02", "q|old": "q|new"],
        tombstones: ["jb|gone"])

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "forwarding-tests-\(UUID().uuidString)")!
    }

    @Test func aListForwardsDropsTheGoneAndKeepsARepeatOnce() {
        #expect(forwarding.forward(["q|old", "jb|gone", "q|new", "x|unknown"]) == ["q|new", "x|unknown"])
        #expect(forwarding.resolve("x|unknown") == "x|unknown", "an id from a newer catalog is kept")
    }

    @Test func historyMovesOnceByTheNewerStamp() {
        let d = defaults()
        let history = ListeningHistory(defaults: d)
        history.record("jb|1921-03-11", position: 600, duration: 1800, now: Date(millis: 5_000))
        history.record("jb|1944-01-02", position: 300, duration: 1800, now: Date(millis: 9_000))
        history.record("jb|old-slug", position: 50, duration: 1800, now: Date(millis: 1_000))
        history.markSynced("jb|old-slug", at: Date(millis: 1_000))
        history.record("jb|gone", position: 90, duration: 1800, now: Date(millis: 2_000))

        #expect(history.forward(forwarding) == 2)
        #expect(history.entry(for: "jb|1943-11-21")?.position == 600, "the position moved to the new id")
        #expect(history.entry(for: "jb|1943-11-21")?.updatedAt == Date(millis: 5_000), "keeping its own stamp")
        #expect(history.entry(for: "jb|1921-03-11") == nil, "and left the old id")
        #expect(history.pending.contains("jb|1943-11-21"), "a row not yet uploaded stays owed")
        #expect(!history.pending.contains("jb|1921-03-11"))
        #expect(history.entry(for: "jb|1944-01-02")?.position == 300, "the newer row it merged into wins")
        #expect(history.entry(for: "jb|old-slug") == nil)
        #expect(history.entry(for: "jb|gone") != nil, "a tombstoned id stays: it is the person's record")
        #expect(history.forward(forwarding) == 0, "it migrates once")
        #expect(ListeningHistory(defaults: d).entry(for: "jb|1943-11-21")?.position == 600, "and is saved")
    }

    @Test func aNewerRemovalOfTheOldIDRemovesTheNewOne() {
        let history = ListeningHistory(defaults: defaults())
        history.record("jb|1943-11-21", position: 300, duration: 1800, now: Date(millis: 1_000))
        history.apply([HistoryRow(episodeId: "jb|1921-03-11", position: 0, duration: nil, finished: false,
                                  deleted: true, updatedAt: 9_000)])
        history.forward(forwarding)
        #expect(history.entry(for: "jb|1943-11-21") == nil, "another device's later removal wins")
        #expect(history.stamp(for: "jb|1943-11-21") == Date(millis: 9_000))
    }

    @Test func aSyncedRowForTheOldIDLandsOnTheNewOne() {
        let history = ListeningHistory(defaults: defaults())
        history.apply([HistoryRow(episodeId: "jb|1921-03-11", position: 900, duration: 1800, finished: false,
                                  deleted: false, updatedAt: 9_000)])
        history.forward(forwarding)
        #expect(history.entry(for: "jb|1943-11-21")?.position == 900)
        #expect(history.entry(for: "jb|1921-03-11") == nil)
        #expect(history.pending.isEmpty, "a row the Worker sent is not sent back")
    }

    @Test func followsMoveOnceByTheNewerStamp() {
        let d = defaults()
        let follows = FollowedSeries(defaults: d)
        let f = IDForwarding(seriesAliases: ["jbp": "jb", "older": "suspense", "both": "twin"],
                             seriesTombstones: ["folkweave"])
        follows.setFollowing("jbp", true, now: Date(millis: 5_000))
        follows.setFollowing("folkweave", true, now: Date(millis: 5_000))
        follows.setFollowing("suspense", true, now: Date(millis: 9_000))
        follows.setFollowing("older", true, now: Date(millis: 1_000))
        follows.markSynced([FollowRow(seriesId: "older", following: true, updatedAt: 1_000)])
        follows.setFollowing("twin", false, now: Date(millis: 9_000))
        follows.setFollowing("both", true, now: Date(millis: 2_000))

        #expect(follows.forward(f) == 3)
        #expect(follows.isFollowing("jb"), "the follow moved to the new key")
        #expect(follows.states["jb"]?.updatedAt == Date(millis: 5_000), "keeping its own stamp")
        #expect(follows.pending.contains("jb"), "a follow not yet uploaded stays owed")
        #expect(follows.states["jbp"] == nil && !follows.pending.contains("jbp"), "and left the old key")
        #expect(follows.states["suspense"]?.updatedAt == Date(millis: 9_000), "an older follow merges into the newer")
        #expect(!follows.isFollowing("twin"), "a newer unfollow of the new key wins")
        #expect(follows.isFollowing("folkweave"), "a tombstoned key's follow stays: it is the person's choice")
        #expect(follows.forward(f) == 0, "it migrates once")
        #expect(FollowedSeries(defaults: d).isFollowing("jb"), "and is saved")
    }

    @Test func aSyncedFollowForTheOldKeyLandsOnTheNewOne() {
        let follows = FollowedSeries(defaults: defaults())
        follows.setFollowing("jb", true, now: Date(millis: 1_000))
        follows.apply([FollowRow(seriesId: "jbp", following: false, updatedAt: 9_000)])
        follows.forward(IDForwarding(seriesAliases: ["jbp": "jb"]))
        #expect(!follows.isFollowing("jb"), "another device's later unfollow wins")
        #expect(follows.states["jbp"] == nil)
        #expect(follows.pending.isEmpty, "a row the Worker sent is not sent back")
    }

    /// The watch has no catalog: it keeps the forwarding it is handed and
    /// forwards its own history with it, as `EarDramaWatchApp` does on launch.
    @Test func aKeptForwardingRoundTripsAndForwardsAHistory() {
        let d = defaults()
        #expect(IDForwarding.stored(in: d) == IDForwarding(), "nothing kept is no forwarding")
        let f = IDForwarding(aliases: ["jb|1921-03-11": "jb|1943-11-21"], tombstones: ["jb|gone"],
                             seriesAliases: ["jbp": "jb"], seriesTombstones: ["folkweave"])
        f.store(in: d)
        #expect(IDForwarding.stored(in: d) == f)
        let history = ListeningHistory(defaults: d)
        history.record("jb|1921-03-11", position: 600, duration: 1800, now: Date(millis: 5_000))
        #expect(history.forward(IDForwarding.stored(in: d)) == 1)
        #expect(history.entry(for: "jb|1943-11-21")?.position == 600)
    }

    @Test func theQueueForwardsKeepingItsStampAndDirtyFlag() {
        let d = defaults()
        let queue = ListeningQueue(defaults: d)
        queue.set(["q|old", "jb|gone", "q|new"], now: Date(millis: 4_000))
        queue.markSynced(QueueState(items: queue.items, updatedAt: 4_000))
        var changes = 0
        queue.onChange = { changes += 1 }
        #expect(queue.forward(forwarding))
        #expect(queue.items == ["q|new"])
        #expect(queue.updatedAt == Date(millis: 4_000), "a rewrite is not an edit")
        #expect(!queue.dirty, "and is never uploaded as one")
        #expect(changes == 1, "Up next refreshes")
        #expect(!queue.forward(forwarding), "it migrates once")
        #expect(ListeningQueue(defaults: d).items == ["q|new"], "and is saved")
    }
}

#if os(iOS) || os(macOS)
struct DownloadForwardingTests {
    private let url = URL(string: "https://archive.org/download/PDP_JackBenny/Jack%20Benny%20Show,%20The%2043-11-21.mp3")!

    @Test func aDownloadIsReKeyedAndItsFileKeepsItsName() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-fwd-\(UUID().uuidString)")
        let store = DownloadStore(directory: dir, transport: FakeTransport())
        store.download(episodeID: "jb|1921-03-11", title: "No. 4", seriesName: "The Jack Benny Program", url: url)
        store.download(episodeID: "q|old", title: "Old", seriesName: "Q", url: url)
        store.download(episodeID: "q|new", title: "New", seriesName: "Q", url: url)
        let fileName = try #require(store.record(for: "jb|1921-03-11")?.fileName)
        store.forward(IDForwarding(aliases: ["jb|1921-03-11": "jb|1943-11-21", "q|old": "q|new"]))
        #expect(store.record(for: "jb|1921-03-11") == nil)
        #expect(store.record(for: "jb|1943-11-21")?.fileName == fileName, "the file keeps its name")
        #expect(store.record(for: "jb|1943-11-21")?.episodeID == "jb|1943-11-21")
        #expect(store.record(for: "q|new")?.title == "New", "the new id's own download is kept")
        #expect(store.record(for: "q|old") == nil, "the moved second copy goes")
        let reopened = DownloadStore(directory: dir, transport: FakeTransport())
        #expect(reopened.record(for: "jb|1943-11-21") != nil, "the index is saved")
    }
}
#endif
