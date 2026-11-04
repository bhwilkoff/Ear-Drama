import XCTest

/// A tile opens its own show, and Back returns to the page it came from (owner, 2026-11-01: a tile
/// opened Wendy Warren for Superman, and Back landed on another show).
final class NavigationUITests: DeviceTestCase {
    private func tiles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "show-tile")
    }

    /// The pushed page's bar: the stack keeps the bars beneath it in the tree, in order.
    private func topBar(_ app: XCUIApplication) -> XCUIElement {
        let bars = app.navigationBars.allElementsBoundByIndex
        return bars.last(where: { $0.isHittable }) ?? bars.last ?? app.navigationBars.element(boundBy: 0)
    }

    private func title(_ app: XCUIApplication) -> String {
        topBar(app).identifier
    }

    private func name(_ tile: XCUIElement) -> String {
        tile.label.components(separatedBy: ", ").first ?? tile.label
    }

    private func matches(_ show: String, _ got: String) -> Bool {
        !got.isEmpty && (show.hasPrefix(got) || got.hasPrefix(show))
    }

    /// Whole on screen: a tile's frame that runs under the tab bar or off the glass has a center nothing receives.
    private func onScreen(_ app: XCUIApplication, _ e: XCUIElement) -> Bool {
        // The frame is read first: on the iPad XCUITest throws, rather than answers false, when it asks
        // a tile scrolled out of the List whether it is hittable (no activation point to test).
        let f = e.frame
        return f.minY > 120 && f.maxY < app.frame.height - 110 && f.minX >= 0 && f.maxX <= app.frame.width && e.isHittable
    }

    private func firstHittable(_ app: XCUIApplication) -> XCUIElement? {
        tiles(app).allElementsBoundByIndex.first(where: { onScreen(app, $0) })
    }

    /// Waits for a pushed page: the root's own bar gone, and a title shown.
    private func settle(_ app: XCUIApplication, from root: String) {
        for _ in 0..<30 {
            let t = title(app)
            if t != root && !t.isEmpty { return }
            usleep(500_000)
        }
    }

    private func back(_ app: XCUIApplication) {
        topBar(app).buttons.element(boundBy: 0).tap()
    }

    func testTilesOpenTheirOwnShowAfterScrolling() throws {
        let app = launch(["APP_START_TAB": "browse", "APP_DOOR_SECONDS": "600"])
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 30), "tiles")
        sleep(3)
        var wrong: [String] = []
        for round in 0..<10 {
            if round > 0 { app.swipeUp(); app.swipeUp() }
            let visible = tiles(app).allElementsBoundByIndex.filter { onScreen(app, $0) }
            guard !visible.isEmpty else { continue }
            let tile = visible[round % visible.count]
            let show = name(tile)
            tile.tap()
            settle(app, from: "Browse")
            let got = title(app)
            if !matches(show, got) { wrong.append("\(show) -> \(got)") }
            if got == "Browse" { continue }
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
        settle(app, from: "Browse")
        let showTitle = title(app)
        XCTAssertTrue(matches(show, showTitle), "opened \(showTitle) for \(show)")
        sleep(3)
        let rows = app.buttons.allElementsBoundByIndex.filter {
            $0.isHittable && $0.frame.minY > 400 && $0.frame.height > 40 && $0.frame.maxY < app.frame.height - 180
                && !["Follow", "Following", "Share", "Back"].contains($0.label) && !$0.label.isEmpty
        }
        guard let episode = rows.first else { throw XCTSkip("no episode row visible") }
        episode.tap()
        settle(app, from: showTitle)
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
        guard let a = firstHittable(app) ?? tiles(app).allElementsBoundByIndex.first(where: { $0.isHittable }) else { return XCTFail("no home tile") }
        let aName = name(a)
        a.tap()
        settle(app, from: "Home")
        let aTitle = title(app)
        XCTAssertNotEqual(aTitle, "Home", "Home's tile opened a page (\(aName))")
        openTab(app, "Browse")
        XCTAssertTrue(tiles(app).firstMatch.waitForExistence(timeout: 30), "browse tiles")
        app.swipeUp(); app.swipeUp()
        guard let b = firstHittable(app) else { return XCTFail("no browse tile") }
        let bName = name(b)
        b.tap()
        settle(app, from: "Browse")
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
