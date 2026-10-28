import XCTest

/// The bedtime rule (research 05, R20): "End of this episode" stops the player
/// at the end and nothing starts the next episode. The timer is in-memory, so
/// terminating the app puts it back.
final class SleepTimerUITests: DeviceTestCase {
    func testEndOfEpisodeStopsAndStartsNothing() throws {
        let app = launch(["APP_START_ITEM": Fixture.short, "APP_AUTOPLAY": "1", "APP_DOOR_SECONDS": "300"])
        XCTAssertTrue(app.sliders["Position"].waitForExistence(timeout: 30), "player open")
        let started = Date()
        while elapsed(app) == 0, Date().timeIntervalSince(started) < 30 { usleep(250_000) }

        app.buttons["Sleep timer"].tap()
        let end = app.buttons["End of this episode"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "End of this episode is offered")
        end.tap(); sleep(1)
        XCTAssertNotEqual(app.buttons["Sleep timer"].value as? String, "Off", "timer set")
        shot(app, "01-timer-set")

        app.sliders["Position"].adjust(toNormalizedSliderPosition: 0.97)
        let seeked = Date()
        let play = app.buttons.matching(identifier: "Play").firstMatch
        while !play.exists, Date().timeIntervalSince(seeked) < 40 { usleep(500_000) }
        XCTAssertTrue(play.exists, "playback stopped at the end (Play offered, not Pause)")
        shot(app, "02-stopped-at-end")

        let at = elapsed(app)
        sleep(8)
        XCTAssertTrue(app.buttons.matching(identifier: "Play").firstMatch.exists, "still stopped 8 s later")
        XCTAssertFalse(app.buttons.matching(identifier: "Pause").firstMatch.exists, "nothing started")
        XCTAssertLessThanOrEqual(abs(elapsed(app) - at), 1, "the clock holds")
        XCTAssertTrue(text(app, matching: Fixture.shortTitle).exists, "still the same episode, not the next")
        shot(app, "03-nothing-next")
        app.terminate()
    }
}
