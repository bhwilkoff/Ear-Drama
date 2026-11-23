import XCTest

/// Every wait is on the state that matters (N7): the control is driven to "Download" first whatever an earlier run
/// left, the Library row is tapped only once it is on screen clear of the bars, and the row is swiped by its cell.
final class DownloadsPlaceUITests: DeviceTestCase {
    func testDownloadsPlaceByEpisodeThenRemove() throws {
        stage("fixture short=\(Fixture.short) title=\(Fixture.shortTitle)")
        let item = launch(["APP_START_ITEM": Fixture.short, "APP_DOOR_SECONDS": "600"])
        XCTAssertTrue(downloadControlReady(item), "the download control reached Download")
        item.buttons["Download"].tap()
        stage("Download tapped")
        let done = item.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Downloaded'")).firstMatch
        XCTAssertTrue(wait(done, "exists == true", timeout: 120, "Downloaded"), "download finished")
        item.terminate()

        let app = launch(["APP_START_TAB": "library", "APP_DOOR_SECONDS": "300"])
        XCTAssertTrue(wait(app.navigationBars["Library"], "exists == true", timeout: 30, "Library"), "Library opened")
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS 'Downloads'")).firstMatch
        XCTAssertTrue(reveal(row, in: app), "Downloads row in Library, clear of the bars")
        shot(app, "01-library-downloads-row")
        row.tap()

        XCTAssertTrue(wait(app.navigationBars["Downloads"], "exists == true", timeout: 10, "the place"), "the place opened")
        let episode = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", Fixture.shortTitle)).firstMatch
        let cell = app.cells.containing(NSPredicate(format: "label CONTAINS %@", Fixture.shortTitle)).firstMatch
        XCTAssertTrue(wait(cell, "exists == true", timeout: 10, "the episode's row"), "the episode is listed")
        XCTAssertTrue(reveal(cell, in: app), "the episode's row clear of the bars")
        shot(app, "02-downloads-place")

        // The whole row, not its title text: a swipe that starts on the text can read as a tap and push the episode.
        cell.swipeLeft()
        let rm = app.buttons["Remove Download"]
        XCTAssertTrue(wait(rm, "exists == true AND hittable == true", timeout: 5, "the swipe action"), "swipe action")
        rm.tap()
        // Another test's downloads may still be listed (2026-10-30: a series download's two
        // episodes), so the check is that this episode left, not that the place is empty.
        XCTAssertTrue(wait(episode, "exists == false", timeout: 10, "the episode left"), "removed; the episode left the place")
        shot(app, "03-removed")
    }
}
