import XCTest

final class BrowseUITests: DeviceTestCase {
    private func firstRow(_ app: XCUIApplication) -> String {
        app.cells.firstMatch.staticTexts.firstMatch.label
    }

    func testFilterChipAndSort() throws {
        let app = launch(["APP_START_TAB": "browse", "APP_DOOR_SECONDS": "120"])
        let kind = app.buttons["Kind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 30), "Kind chip")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 30), "series rows")
        shot(app, "01-browse")

        kind.tap()
        let plays = app.buttons["Plays"]
        XCTAssertTrue(plays.waitForExistence(timeout: 5), "Kind menu offers Plays")
        plays.tap()
        XCTAssertTrue(app.buttons["Plays"].waitForExistence(timeout: 5), "chip shows the selection")
        XCTAssertTrue(app.buttons["Clear filters"].waitForExistence(timeout: 5), "Clear appears once a filter is set")
        shot(app, "02-kind-plays")

        app.buttons["Clear filters"].tap()
        XCTAssertTrue(app.buttons["Kind"].waitForExistence(timeout: 5), "cleared")
        XCTAssertFalse(app.buttons["Clear filters"].exists, "Clear leaves with the last filter")

        let popular = app.buttons["Sort: Popular"]
        XCTAssertTrue(popular.waitForExistence(timeout: 5), "Sort chip")
        let before = firstRow(app)
        if popular.frame.maxX > app.frame.width { app.buttons["Decade"].swipeLeft() }
        popular.tap()
        let az = app.buttons["A to Z"]
        XCTAssertTrue(az.waitForExistence(timeout: 5), "Sort menu offers A to Z")
        az.tap()
        XCTAssertTrue(app.buttons["Sort: A to Z"].waitForExistence(timeout: 5), "sort chip names the order")
        sleep(2)
        XCTAssertNotEqual(firstRow(app), before, "the list reordered")
        shot(app, "03-sort-az")

        if app.buttons["Sort: A to Z"].frame.maxX > app.frame.width { app.buttons["Decade"].swipeLeft() }
        app.buttons["Sort: A to Z"].tap()
        app.buttons["Popular"].tap()
        XCTAssertTrue(app.buttons["Sort: Popular"].waitForExistence(timeout: 5), "default restored")
    }
}
