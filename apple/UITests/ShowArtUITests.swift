import XCTest

/// iOS-DESIGN R11a: a served face is the first thing on Detail and the series
/// page, full width, and Now Playing's art is full width. The frames are for
/// the person running the test to look at; the asserts check the band's size.
final class ShowArtUITests: DeviceTestCase {
    /// A live-catalog episode whose star has a served portrait. Absent means skip, not fail.
    private enum Faced {
        static let id = "gunsmoke|1952-04-26"
        static let series = "Gunsmoke"
    }

    private func band(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["face-hero"].firstMatch
    }

    private func assertFullWidth(_ app: XCUIApplication, _ element: XCUIElement, _ page: String) {
        XCTAssertGreaterThanOrEqual(element.frame.width, app.frame.width * 0.8, "\(page): the face band is full width")
        XCTAssertGreaterThanOrEqual(element.frame.height, 200, "\(page): the face band is tall enough to know the face")
    }

    func testFacesOnDetailSeriesAndNowPlaying() throws {
        let app = launch(["APP_START_ITEM": Faced.id, "APP_DOOR_SECONDS": "600"])
        guard app.buttons["Add to queue"].waitForExistence(timeout: 30) || app.buttons["In queue"].exists else {
            throw XCTSkip("\(Faced.id) is not in this catalog")
        }
        let detailBand = band(app)
        guard detailBand.waitForExistence(timeout: 10) else { throw XCTSkip("\(Faced.id) has no served face") }
        sleep(4)
        assertFullWidth(app, detailBand, "Detail")
        shot(app, "01-detail-face")

        let seriesLink = app.buttons.matching(NSPredicate(format: "label == %@", Faced.series)).firstMatch
        XCTAssertTrue(seriesLink.waitForExistence(timeout: 10), "Detail links its series")
        seriesLink.tap()
        XCTAssertTrue(app.navigationBars[Faced.series].waitForExistence(timeout: 15), "the series page opened")
        let seriesBand = band(app)
        XCTAssertTrue(seriesBand.waitForExistence(timeout: 10), "the series page opens with its face")
        sleep(4)
        assertFullWidth(app, seriesBand, "Series")
        shot(app, "02-series-face")
        app.terminate()

        let playing = launch(["APP_START_ITEM": Faced.id, "APP_AUTOPLAY": "1", "APP_DOOR_SECONDS": "600"])
        XCTAssertTrue(playing.buttons["Forward 30 seconds"].waitForExistence(timeout: 30), "Now Playing opened")
        sleep(6)
        shot(playing, "03-now-playing")
        XCTAssertTrue(hittable(playing, "Play").exists || hittable(playing, "Pause").exists,
                      "Play stays on the first screen under the art")
        let control = hittable(playing, "Pause").exists ? hittable(playing, "Pause") : hittable(playing, "Play")
        XCTAssertLessThan(control.frame.maxY, playing.frame.height, "Play is on screen, not pushed below by the art")
        if hittable(playing, "Pause").exists { hittable(playing, "Pause").tap() }
        playing.buttons["Close player"].tap()
        XCTAssertEqual(playing.state, .runningForeground)
    }
}
