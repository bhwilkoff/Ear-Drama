import XCTest

final class PlayerUITests: DeviceTestCase {
    func testPlayerVerbs() throws {
        let app = launch(["APP_START_ITEM": Fixture.long, "APP_AUTOPLAY": "1",
                          "APP_DOOR_SECONDS": "600", "APP_PLAYBACK_DIAG": "1"])
        XCTAssertTrue(app.buttons["Forward 30 seconds"].waitForExistence(timeout: 30))
        // The clock shows the resume point before the item is ready (an open mid-file took 3 to 45 s
        // on 2026-10-31), so measure only once it moves.
        let started = Date()
        let first = elapsed(app)
        while elapsed(app) <= first, Date().timeIntervalSince(started) < 60 { usleep(250_000) }
        sleep(4)
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

        // The slider's adjust lands as several seeks over seconds, so t3 can be a transient read:
        // judge "still playing" against the clock as it stands once the verbs are done.
        let settled = elapsed(app)
        sleep(15)
        XCTAssertGreaterThan(elapsed(app), settled, "still playing after the verbs")
        app.buttons["Close player"].tap(); sleep(2)
        shot(app, "08-closed-mini")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Another speaker (owner, 2026-10-28): AirPlay's own picker is on the player.
    func testRoutePickerOnPlayer() throws {
        let app = launch(["APP_START_ITEM": Fixture.short, "APP_AUTOPLAY": "1",
                          "APP_DOOR_SECONDS": "120"])
        XCTAssertTrue(app.buttons["Forward 30 seconds"].waitForExistence(timeout: 30))
        let picker = app.descendants(matching: .any)["RoutePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "the AirPlay route picker is on the player")
        XCTAssertTrue(picker.isHittable, "the route picker can be pressed")
        shot(app, "09-route-picker")
        app.buttons["Close player"].tap(); sleep(2)
    }
}
