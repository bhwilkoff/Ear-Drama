import XCTest

/// A tile opens its own show, and Back returns to the page it came from (owner, 2026-11-01: a tile
/// opened Wendy Warren for Superman, and Back landed on another show).
final class NavigationUITests: DeviceTestCase {
    private func tiles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "show-tile")
    }

    private func title(_ app: XCUIApplication) -> String {
        app.navigationBars.element(boundBy: 0).identifier
    }

    private func name(_ tile: XCUIElement) -> String {
        tile.label.components(separatedBy: ", ").first ?? tile.label
    }

    private func matches(_ show: String, _ got: String) -> Bool {
        !got.isEmpty && (show.hasPrefix(got) || got.hasPrefix(show))
    }

    private func firstHittable(_ app: XCUIApplication) -> XCUIElement? {
        tiles(app).allElementsBoundByIndex.first(where: { $0.isHittable })
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.element(boundBy: 0).buttons.element(boundBy: 0).tap()
    }

    func testTilesOpenTheirOwnShowAfterScrolling() throws {
        let app = launch(["APP_START_TAB": "browse", "APP_DOOR_SECONDS": "600"])
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 30), "tiles")
        var wrong: [String] = []
        for round in 0..<10 {
            if round > 0 { app.swipeUp(); app.swipeUp() }
            let visible = tiles(app).allElementsBoundByIndex.filter { $0.isHittable }
            guard !visible.isEmpty else { continue }
            let tile = visible[round % visible.count]
            let show = name(tile)
            tile.tap()
            sleep(2)
            let got = title(app)
            if !matches(show, got) { wrong.append("\(show) -> \(got)") }
            back(app)
            XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 10), "Back reaches Browse")
        }
        XCTAssertTrue(wrong.isEmpty, "wrong destinations: \(wrong)")
    }

    func testSupermanTileOpensSuperman() throws {
        let app = launch(["APP_START_TAB": "browse", "APP_DOOR_SECONDS": "600"])
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 30), "tiles")
        let tile = tiles(app).matching(NSPredicate(format: "label BEGINSWITH 'The Adventures of Superman'")).firstMatch
        for _ in 0..<40 where !(tile.exists && tile.isHittable) { app.swipeUp() }
        XCTAssertTrue(tile.isHittable, "Superman tile found")
        tile.tap()
        XCTAssertTrue(app.navigationBars["The Adventures of Superman"].waitForExistence(timeout: 10), "opened \(title(app))")
    }

    func testBackReturnsToTheShowThenTheStart() throws {
        let app = launch(["APP_START_TAB": "browse", "APP_DOOR_SECONDS": "600"])
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 30), "tiles")
        app.swipeUp(); app.swipeUp()
        guard let tile = firstHittable(app) else { return XCTFail("no tile") }
        let show = name(tile)
        tile.tap()
        sleep(2)
        shot(app, "nav-after-tap")
        print("NAVDIAG bars=\(app.navigationBars.allElementsBoundByIndex.map { $0.identifier }) tile=\(tile.label)")
        let showTitle = title(app)
        XCTAssertTrue(matches(show, showTitle), "opened \(showTitle) for \(show)")
        let rows = app.cells.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minY > 300 }
        guard let episode = rows.first else { throw XCTSkip("no episode row visible") }
        episode.tap()
        sleep(2)
        XCTAssertNotEqual(title(app), showTitle, "moved to the episode")
        back(app)
        sleep(1)
        XCTAssertEqual(title(app), showTitle, "Back from the episode lands on the show")
        back(app)
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 10), "Back again reaches Browse")
    }

    func testHomeThenBrowseKeepsEachTabsStack() throws {
        let app = launch(["APP_START_TAB": "home", "APP_DOOR_SECONDS": "600"])
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 30), "home tiles")
        guard let a = firstHittable(app) else { return XCTFail("no home tile") }
        let aName = name(a)
        a.tap()
        sleep(2)
        let aTitle = title(app)
        XCTAssertTrue(matches(aName, aTitle), "Home opened \(aTitle) for \(aName)")
        openTab(app, "Browse")
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 30), "browse tiles")
        app.swipeUp(); app.swipeUp()
        guard let b = firstHittable(app) else { return XCTFail("no browse tile") }
        let bName = name(b)
        b.tap()
        sleep(2)
        let bTitle = title(app)
        XCTAssertTrue(matches(bName, bTitle), "Browse opened \(bTitle) for \(bName)")
        back(app)
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 10), "Back lands on Browse")
        openTab(app, "Home")
        sleep(1)
        XCTAssertEqual(title(app), aTitle, "Home still on its own show")
        back(app)
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10), "Back lands on Home")
    }
}
