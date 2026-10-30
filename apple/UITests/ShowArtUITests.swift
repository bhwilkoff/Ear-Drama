import XCTest

/// iOS-DESIGN R11d (D3-3, which retired R11a's FaceHero on these pages): the episode page and the
/// series page lead with the show's `HeadBoard`, its window drawing the picture, and the episode's
/// board is the link to its series. R11c (D3-4): Now Playing's art leaves Play on the first screen.
/// The frames are for the person running the test to look at.
final class ShowArtUITests: DeviceTestCase {
    /// A live-catalog episode whose show has a served picture. Absent means skip, not fail.
    private enum Faced {
        static let id = "gunsmoke|1952-04-26"
        static let series = "Gunsmoke"
    }

    private func board(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "head-board").firstMatch
    }

    /// The board spans the page's column (720 pt at most, ReadableColumn) and is tall enough for
    /// the smallest window (96 pt) and the run strip.
    private func assertLeads(_ app: XCUIApplication, _ element: XCUIElement, _ page: String) {
        let column = min(app.frame.width, 720)
        XCTAssertGreaterThanOrEqual(element.frame.width, column * 0.8, "\(page): the board spans the column")
        XCTAssertGreaterThanOrEqual(element.frame.height, 96 + 40, "\(page): the board holds the window and the strip")
        XCTAssertLessThan(element.frame.minY, app.frame.height * 0.5, "\(page): the board leads the page")
    }

    func testFacesOnDetailSeriesAndNowPlaying() throws {
        let app = launch(["APP_START_ITEM": Faced.id, "APP_DOOR_SECONDS": "600"])
        guard app.buttons["Add to queue"].waitForExistence(timeout: 30) || app.buttons["In queue"].exists else {
            throw XCTSkip("\(Faced.id) is not in this catalog")
        }
        let detailBoard = board(app)
        XCTAssertTrue(detailBoard.waitForExistence(timeout: 10), "the episode page leads with its show's picture, not the title block")
        sleep(4)
        assertLeads(app, detailBoard, "Detail")
        shot(app, "01-detail-board")

        detailBoard.tap()
        XCTAssertTrue(app.navigationBars[Faced.series].waitForExistence(timeout: 15), "the board opens the series page")
        let seriesBoard = board(app)
        XCTAssertTrue(seriesBoard.waitForExistence(timeout: 10), "the series page leads with its picture")
        sleep(4)
        assertLeads(app, seriesBoard, "Series")
        shot(app, "02-series-board")
        app.terminate()

        let playing = launch(["APP_START_ITEM": Faced.id, "APP_AUTOPLAY": "1", "APP_DOOR_SECONDS": "600"])
        XCTAssertTrue(playing.buttons["Forward 30 seconds"].waitForExistence(timeout: 30), "Now Playing opened")
        sleep(6)
        shot(playing, "03-now-playing")
        XCTAssertTrue(hittable(playing, "Play").exists || hittable(playing, "Pause").exists,
                      "Play stays on the first screen under the art")
        let control = hittable(playing, "Pause").exists ? hittable(playing, "Pause") : hittable(playing, "Play")
        XCTAssertTrue(control.isHittable, "Play is on screen, not pushed below by the art")
        XCTAssertTrue(playing.descendants(matching: .any)["RoutePicker"].isHittable, "the verbs row stays on screen under the art")
        if hittable(playing, "Pause").exists { hittable(playing, "Pause").tap() }
        playing.buttons["Close player"].tap()
        XCTAssertEqual(playing.state, .runningForeground)
    }
}
