import XCTest

/// Seeking a streamed episode must keep it playing (2026-10-27: an X Minus One
/// item failed after a seek to the middle). APP_PLAYBACK_DIAG puts a failure's
/// errors on screen, so the frame says why.
final class SeekUITests: DeviceTestCase {
    func testSeeksKeepPlaying() throws { try seeks(at: nil) }

    /// The 2026-10-27 failure came after the speed went to 1.5x.
    func testSeeksKeepPlayingFaster() throws { try seeks(at: "1.5×") }

    private func seeks(at speed: String?) throws {
        for id in [Fixture.long, "escape|1947-02-28", "gangbusters|1954-08-02"] {
            let app = launch(["APP_START_ITEM": id, "APP_AUTOPLAY": "1",
                              "APP_DOOR_SECONDS": "300", "APP_PLAYBACK_DIAG": "1"])
            guard app.sliders["Position"].waitForExistence(timeout: 30) else {
                XCTFail("no player for \(id)"); continue
            }
            // The clock shows the resume point before the item is ready, so wait for it to move.
            let started = Date()
            let first = elapsed(app)
            while elapsed(app) <= first, Date().timeIntervalSince(started) < 45 { usleep(250_000) }
            print("SEEK START \(id) clock moving after \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            let remaining = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '-'")).firstMatch
            print("SEEK DURATION \(id) remaining label \(remaining.exists ? remaining.label : "none") at clock \(elapsed(app))")
            sleep(4)
            if let speed {
                app.buttons["Playback speed"].tap(); sleep(1)
                app.buttons[speed].tap(); sleep(2)
            }
            for target in [0.5, 0.8, 0.2, 0.65] {
                app.sliders["Position"].adjust(toNormalizedSliderPosition: target)
                sleep(6)
                let a = elapsed(app); sleep(3); let b = elapsed(app)
                let diag = app.staticTexts["PlaybackDiag"]
                print("SEEK DIAG \(id) at \(target) clock \(a)->\(b): \(diag.exists ? diag.label : "no diag")")
                if b <= a {
                    print("SEEK STALL \(id) at \(target): \(diag.exists ? diag.label : "no diag")")
                    shot(app, "stall-\(id.prefix(10))-\(target)")
                    sleep(10)
                    print("SEEK STALL+10s \(id) at \(target): \(diag.exists ? diag.label : "no diag") clock \(elapsed(app))")
                }
                let failure = text(app, matching: "would not play|You are offline")
                if failure.exists {
                    print("SEEK FAIL \(id) at \(target): \(failure.label)")
                    shot(app, "fail-\(id.prefix(10))-\(target)")
                }
                XCTAssertFalse(failure.exists, "\(id) seek \(target): \(failure.exists ? failure.label : "")")
                XCTAssertGreaterThan(b, a, "\(id) clock advances after seek \(target) (\(a) -> \(b))")
            }
            app.terminate()
        }
    }
}
