import XCTest

final class BrowseUITests: DeviceTestCase {
    /// The first show tile's name. Not `cells.firstMatch`: on the iPad that is the sidebar's Home,
    /// and in design D the first List row is the count line, the same under every sort.
    private func firstRow(_ app: XCUIApplication) -> String {
        app.buttons.matching(identifier: "show-tile").firstMatch.label
    }

    func testFilterChipAndSort() throws {
        let app = launch(["APP_START_TAB": "browse", "APP_DOOR_SECONDS": "120"])
        let kind = app.buttons["Kind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 30), "Kind chip")
        XCTAssertTrue(app.buttons.matching(identifier: "show-tile").firstMatch.waitForExistence(timeout: 30), "show tiles")
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
        XCTAssertTrue(app.buttons.matching(identifier: "show-tile").firstMatch.waitForExistence(timeout: 30), "show tiles after Clear")
        let before = firstRow(app)
        if popular.frame.maxX > app.frame.width { app.buttons["Decade"].swipeLeft() }
        popular.tap()
        let az = app.buttons["A to Z"]
        XCTAssertTrue(az.waitForExistence(timeout: 5), "Sort menu offers A to Z")
        az.tap()
        XCTAssertTrue(app.buttons["Sort: A to Z"].waitForExistence(timeout: 5), "sort chip names the order")
        sleep(2)
        shot(app, "03a-az-top")
        // A to Z is sections of lazy rows under the genre field: the first tile exists once scrolled to.
        let tiles = app.buttons.matching(identifier: "show-tile")
        for _ in 0..<8 where !tiles.firstMatch.exists { app.swipeUp() }
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10), "tiles under A to Z")
        XCTAssertNotEqual(firstRow(app), before, "the list reordered")
        shot(app, "03-sort-az")
        for _ in 0..<12 where !app.buttons["Sort: A to Z"].isHittable { app.swipeDown(velocity: .fast) }

        if app.buttons["Sort: A to Z"].frame.maxX > app.frame.width { app.buttons["Decade"].swipeLeft() }
        app.buttons["Sort: A to Z"].tap()
        app.buttons["Popular"].tap()
        XCTAssertTrue(app.buttons["Sort: Popular"].waitForExistence(timeout: 5), "default restored")
    }
}
