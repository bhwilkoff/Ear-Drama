import XCTest

/// Each section opens and draws text only that screen draws (never a tab-bar
/// label: the bar's own words made Release-build Home frames pass once).
final class TabSmokeUITests: DeviceTestCase {
    private func check(_ tab: String, _ rx: String) {
        let app = launch(["APP_START_TAB": tab, "APP_DOOR_SECONDS": "60"])
        XCTAssertTrue(text(app, matching: rx).waitForExistence(timeout: 25), "\(tab): /\(rx)/")
        shot(app, "tab-\(tab)")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testHome() { check("home", "This day in radio|Continue") }
    func testBrowse() { check("browse", "Kind|Genre|Decade") }
    func testStations() { check("stations", "Tonight in") }
    func testSurprise() { check("surprise", "An episode|An evening") }
    func testSearch() { check("search", "Titles, series, people|Search titles") }
    func testLibrary() { check("library", "Nothing played yet|In progress|Queue|Following|History|Ear dramas|Downloads") }
}
