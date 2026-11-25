import Foundation
import Testing

/// The car's picture path: a served picture kept, the label when it cannot be fetched, a bounded
/// directory, and the recipe a node's picture is made from (the cases of Android's CarArtTest).
struct CarArtTests {
    private static func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "carart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private final class Counter: @unchecked Sendable {
        nonisolated(unsafe) var n = 0
    }

    private static let label = Data("LABEL".utf8)
    private static let url = URL(string: "https://x/y.jpg?width=330")!

    @Test func aServedPictureIsFetchedOnceAndKept() async throws {
        let fetches = Counter()
        let store = CarArtStore(dir: try Self.folder()) { _ in fetches.n += 1; return Data("JPEG".utf8) }
        let first = await store.data(key: "e:1", served: Self.url) { Self.label }
        let second = await store.data(key: "e:1", served: Self.url) { Self.label }
        #expect(first == Data("JPEG".utf8) && second == first)
        #expect(fetches.n == 1)
    }

    @Test func offlineTheLabelTakesItsPlaceAndIsKept() async throws {
        let drawn = Counter()
        let store = CarArtStore(dir: try Self.folder()) { _ in nil }
        let first = await store.data(key: "e:1", served: Self.url) { drawn.n += 1; return Self.label }
        _ = await store.data(key: "e:1", served: Self.url) { drawn.n += 1; return Self.label }
        #expect(first == Self.label)
        #expect(drawn.n == 1)
    }

    @Test func noServedPictureDrawsTheLabelWithNoFetchAtAll() async throws {
        let store = CarArtStore(dir: try Self.folder()) { _ in
            Issue.record("must not fetch")
            return nil
        }
        #expect(await store.data(key: "e:2", served: nil) { Self.label } == Self.label)
        #expect(await store.data(key: "e:3", served: nil) { nil } == nil, "no label and no picture is no picture")
    }

    @Test func theDirectoryIsBounded() async throws {
        let dir = try Self.folder()
        let store = CarArtStore(dir: dir) { _ in nil }
        for i in 0..<(CarArtStore.maxFiles + 25) { _ = await store.data(key: "e:\(i)", served: nil) { Self.label } }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count <= CarArtStore.maxFiles)
    }

    @Test func aNodesPictureIsMadeFromTheRecordsOwnArtOrItsLabel() async throws {
        let catalog = CatalogStore(path: try Fixture.make().path)
        let episode = try #require(await catalog.carArt(.episode("suspense|1942-06-17")))
        #expect(episode.key == "e:suspense|1942-06-17")
        guard case let .episode(row, series) = episode.subject else { Issue.record("not an episode recipe"); return }
        #expect(row.seriesKey == "suspense" && series?.key == "suspense")
        let show = try #require(await catalog.carArt(.series("suspense")))
        #expect(show.key == "s:suspense")
        #expect(await catalog.carArt(.series("nope")) == nil)
        #expect(await catalog.carArt(.episode("nope|1")) == nil)
    }
}
