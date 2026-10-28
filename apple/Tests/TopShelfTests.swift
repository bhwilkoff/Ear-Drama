import Foundation
import Testing

/// The Apple TV Top Shelf's hand-off (tvOS-DESIGN §9.2): the app writes the
/// Continue items, the extension reads them, and nothing in progress means
/// nil so tvOS keeps its static image.
struct TopShelfTests {
    private func episode(_ id: String, series: String = "Suspense", title: String? = "Cabin B-13",
                         art: Artwork? = nil) -> EpisodeRow {
        EpisodeRow(id: id, seriesKey: "suspense", seriesName: series, airDate: "1950-01-01", season: nil,
                   number: nil, title: title, lengthSeconds: 1800, rights: "unclaimed", rightsBasis: nil,
                   network: "CBS", seriesFace: art.map { Face(name: "A. Person", art: $0) })
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TopShelfTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func keepsTheOrderItIsGiven() {
        let snapshot = TopShelfSnapshot.make(from: [episode("a|3"), episode("b|2"), episode("c|1")])
        #expect(snapshot.items.map(\.id) == ["a|3", "b|2", "c|1"])
    }

    @Test func stopsAtTheLimit() {
        let many = (0..<25).map { episode("s|\($0)") }
        #expect(TopShelfSnapshot.make(from: many).items.count == TopShelfSnapshot.limit)
        #expect(TopShelfSnapshot.make(from: many, limit: 3).items.map(\.id) == ["s|0", "s|1", "s|2"])
    }

    @Test func roundTripsThroughTheFile() throws {
        let dir = try tempDirectory()
        let art = Artwork(url: URL(string: "https://upload.example/face.jpg")!)
        let snapshot = TopShelfSnapshot.make(from: [episode("a|1", art: art), episode("b|2")])
        try snapshot.write(to: dir)
        #expect(TopShelfSnapshot.read(from: dir) == snapshot)
    }

    @Test func nothingWrittenReadsAsNil() throws {
        #expect(TopShelfSnapshot.read(from: try tempDirectory()) == nil)
    }

    @Test func nothingInProgressMeansNoContent() throws {
        let dir = try tempDirectory()
        try TopShelfSnapshot.make(from: []).write(to: dir)
        #expect(TopShelfSnapshot.shelf(from: TopShelfSnapshot.read(from: dir)) == nil)
        #expect(TopShelfSnapshot.shelf(from: nil) == nil)
        #expect(TopShelfSnapshot.shelf(from: TopShelfSnapshot.make(from: [episode("a|1")]))?.count == 1)
    }

    @Test func aCreditedPortraitIsLeftOffTheShelf() {
        let free = Artwork(url: URL(string: "https://upload.example/a.jpg")!)
        let credited = Artwork(url: URL(string: "https://upload.example/b.jpg")!, credit: "Author, CC BY-SA 3.0")
        let items = TopShelfSnapshot.make(from: [episode("a|1", art: free), episode("b|2", art: credited), episode("c|3")]).items
        #expect(items[0].artURL != nil)
        #expect(items[1].artURL == nil)
        #expect(items[2].artURL == nil)
    }

    @Test func theLinkOpensTheEpisode() {
        let ids = ["gangbusters|1954-08-02", "a/b|c d"]
        for id in ids {
            let link = TopShelfSnapshot.link(forEpisode: id)
            #expect(link.scheme == "eardrama")
            #expect(DeepLink.parse(link) == .episode(id))
        }
    }

    @Test func theLabelNamesSeriesThenEpisode() {
        let items = TopShelfSnapshot.make(from: [episode("a|1"), episode("b|2", series: "Dragnet", title: nil)]).items
        #expect(items[0].label == "Suspense: Cabin B-13")
        #expect(items[1].label == "Dragnet: 1950-01-01")
    }
}
