import XCTest

final class DownloadsPlaceUITests: DeviceTestCase {
    func testDownloadsPlaceByEpisodeThenRemove() throws {
        let item = launch(["APP_START_ITEM": Fixture.short, "APP_DOOR_SECONDS": "600"])
        let remove = item.buttons["Remove Download"]
        let download = item.buttons["Download"]
        XCTAssertTrue(download.waitForExistence(timeout: 30) || remove.exists, "Download verb")
        if download.exists { download.tap() }
        let done = item.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Downloaded'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 120), "download finished")
        item.terminate()

        let app = launch(["APP_START_TAB": "library", "APP_DOOR_SECONDS": "300"])
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS 'Downloads'")).firstMatch
        var n = 0
        while !row.waitForExistence(timeout: n == 0 ? 25 : 1) && n < 8 { app.swipeUp(); n += 1 }
        XCTAssertTrue(row.exists, "Downloads row in Library")
        shot(app, "01-library-downloads-row")
        row.tap()

        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 10), "the place opened")
        let episode = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", Fixture.shortTitle)).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 10), "the episode is listed")
        shot(app, "02-downloads-place")

        episode.swipeLeft()
        let rm = app.buttons["Remove Download"]
        XCTAssertTrue(rm.waitForExistence(timeout: 3), "swipe action")
        rm.tap()
        XCTAssertTrue(app.staticTexts["No downloads"].waitForExistence(timeout: 10), "removed; the place is empty")
        shot(app, "03-removed")
    }
}
