import XCTest

// V8 (2026-11-20): the series head's kicker and the label's rim name `series.network`, the one primary network,
// never the `networks` list ("CBS · NBC · AFRS · NBC RED" sat over Lux Radio Theater on every platform).
nonisolated final class SeriesHeadNetworkTests: XCTestCase {
    @MainActor func testTheHeadAndTheRimNameThePrimaryNetworkOnly() {
        let lux = SeriesRow(key: "lux", name: "Lux", genre: "drama", firstDate: "1935-06-01", lastDate: "1955-06-01",
                            networks: ["NBC Blue", "CBS", "AFRS"], episodeCount: 9, network: "CBS")
        XCTAssertEqual(SeriesHead.kicker(lux), "Drama \u{00B7} CBS")
        XCTAssertEqual(lux.labelItem.network, "CBS")
        let none = SeriesRow(key: "x", name: "X", genre: "drama", firstDate: nil, lastDate: nil,
                             networks: ["Syndicated"], episodeCount: 1)
        XCTAssertEqual(SeriesHead.kicker(none), "Drama")
        XCTAssertNil(none.labelItem.network)
    }
}
