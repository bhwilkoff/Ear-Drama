import XCTest

final class DownloadUITests: DeviceTestCase {
    func testDownloadPlayFromFileRemove() throws {
        let app = launch(["APP_START_ITEM": Fixture.short, "APP_DOOR_SECONDS": "600"])
        XCTAssertTrue(downloadControlReady(app), "the download control reached Download")
        app.buttons["Download"].tap()
        shot(app, "01-downloading")
        let done = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Downloaded'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 120), "download finished")
        shot(app, "02-downloaded")

        hittable(app, "Play").tap()
        XCTAssertTrue(app.buttons["Forward 30 seconds"].waitForExistence(timeout: 15)
                      || app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Now playing'")).firstMatch.exists,
                      "player opened")
        sleep(6)
        shot(app, "03-playing-file")
        XCTAssertEqual(app.state, .runningForeground)
        if app.buttons["Close player"].exists { app.buttons["Close player"].tap(); sleep(2) }

        let rm = app.buttons["Remove Download"]
        XCTAssertTrue(rm.waitForExistence(timeout: 10), "Remove Download")
        rm.tap()
        XCTAssertTrue(app.buttons["Download"].waitForExistence(timeout: 10), "download removed")
        shot(app, "04-removed")
    }
}
