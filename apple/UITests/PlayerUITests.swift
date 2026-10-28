import XCTest

final class PlayerUITests: DeviceTestCase {
    func testPlayerVerbs() throws {
        let app = launch(["APP_START_ITEM": Fixture.long, "APP_AUTOPLAY": "1",
                          "APP_DOOR_SECONDS": "600"])
        XCTAssertTrue(app.buttons["Forward 30 seconds"].waitForExistence(timeout: 30))
        sleep(12)
        shot(app, "01-playing")
        let t0 = elapsed(app)
        app.buttons["Forward 30 seconds"].tap(); sleep(2)
        let t1 = elapsed(app)
        XCTAssertGreaterThanOrEqual(t1 - t0, 28, "forward 30")
        app.buttons["Back 15 seconds"].tap(); sleep(2)
        XCTAssertLessThan(elapsed(app), t1, "back 15")
        shot(app, "02-after-skips")

        app.buttons["Playback speed"].tap(); sleep(1)
        shot(app, "03-speed-menu")
        let fast = app.buttons["1.5×"].exists ? app.buttons["1.5×"]
            : app.buttons.matching(NSPredicate(format: "label CONTAINS '1.5'")).firstMatch
        fast.tap(); sleep(1)
        XCTAssertEqual(app.buttons["Playback speed"].value as? String, "1.5×")

        app.sliders["Position"].adjust(toNormalizedSliderPosition: 0.5); sleep(3)
        let t3 = elapsed(app)
        XCTAssertGreaterThan(t3, 400, "seek moved well past the skips (slider adjust lands within a few percent of the target)")
        shot(app, "04-seeked")

        hittable(app, "Pause").tap(); sleep(3)
        let p0 = elapsed(app); sleep(3)
        XCTAssertEqual(p0, elapsed(app), "paused clock holds")
        shot(app, "05-paused")
        hittable(app, "Play").tap(); sleep(4)
        XCTAssertGreaterThan(elapsed(app), p0, "resumed clock advances")

        app.buttons["Sleep timer"].tap(); sleep(1)
        shot(app, "06-sleep-menu")
        app.buttons["15 minutes"].tap(); sleep(1)
        XCTAssertNotEqual(app.buttons["Sleep timer"].value as? String, "Off")
        shot(app, "07-sleep-set")
        app.buttons["Sleep timer"].tap(); sleep(1)
        app.buttons["Turn Off Timer"].tap(); sleep(1)
        XCTAssertEqual(app.buttons["Sleep timer"].value as? String, "Off")

        let level = app.buttons["Level volume"].exists ? app.buttons["Level volume"]
            : app.switches["Level volume"]
        level.tap(); sleep(1); level.tap(); sleep(1)

        sleep(15)
        XCTAssertGreaterThan(elapsed(app), t3, "still playing after the verbs")
        app.buttons["Close player"].tap(); sleep(2)
        shot(app, "08-closed-mini")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
