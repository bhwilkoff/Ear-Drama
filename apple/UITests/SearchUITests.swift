import XCTest

/// Search by air date (2026-10-27): a date narrows by the other words, and the
/// "Aired" section lists what aired then.
final class SearchUITests: DeviceTestCase {
    func testDateFindsWhatAired() throws {
        let app = launch(["APP_DOOR_SECONDS": "60"])
        sleep(3)
        // The search link (DEEP_LINKS.md) reaches the same screen as typing.
        app.open(URL(string: "eardrama://search?q=gangbusters+august+1954")!)
        let aired = text(app, matching: "Aired")
        XCTAssertTrue(aired.waitForExistence(timeout: 15), "an Aired section")
        XCTAssertTrue(text(app, matching: "Kewpie Doll").waitForExistence(timeout: 10),
                      "Gang Busters 1954-08-02 in it")
        shot(app, "search-date")
    }
}
