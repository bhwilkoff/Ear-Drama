import XCTest

/// The empty state (iOS-DESIGN §7.4): a title and one action, and never in
/// place of the navigation the screen carries.
final class EmptyStateUITests: DeviceTestCase {
    /// An empty Library keeps Account and the site pages, and Browse opens Browse.
    func testEmptyLibraryKeepsAccountAndBrowses() throws {
        let app = launch(["APP_START_TAB": "library", "APP_EMPTY_LIBRARY": "1", "APP_DOOR_SECONDS": "60"])
        XCTAssertTrue(text(app, matching: "Nothing played yet").waitForExistence(timeout: 25), "the empty state")
        XCTAssertTrue(text(app, matching: "^Account").waitForExistence(timeout: 5), "the Account row under it")
        let credits = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Credits")).firstMatch
        var n = 0
        while !credits.waitForExistence(timeout: n == 0 ? 5 : 1) && n < 6 { app.swipeUp(); n += 1 }
        XCTAssertTrue(credits.exists, "the site pages under it")
        shot(app, "empty-library")
        app.swipeDown()
        let browse = hittable(app, "empty-action")
        XCTAssertTrue(browse.waitForExistence(timeout: 5), "the Browse action")
        browse.tap()
        XCTAssertTrue(text(app, matching: "Kind|Genre|Decade").waitForExistence(timeout: 15), "Browse opened")
        shot(app, "empty-library-browse")
    }

    /// No results echo the query and invent nothing.
    func testNoResultsEchoTheQuery() throws {
        let app = launch(["APP_DOOR_SECONDS": "60"])
        sleep(3)
        app.open(URL(string: "eardrama://search?q=zqxjvw")!)
        XCTAssertTrue(text(app, matching: "No matches for “zqxjvw”").waitForExistence(timeout: 15), "the query echoed")
        shot(app, "empty-search")
    }
}
