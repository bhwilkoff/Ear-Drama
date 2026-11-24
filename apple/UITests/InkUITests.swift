import UIKit
import XCTest

/// Pencil ink in the script reader (Decision 076 S5), on an iPad. A Pencil cannot be driven, so the DEBUG door
/// APP_READER_INK_FINGER=1 lets a finger draw in Ink mode (APP_READER_INK=1 opens the reader in it). The run draws on
/// two lines, turns Ink off (the same strokes, read-only), changes the text size, and turns a page and back. Every
/// frame is attached for a person to read.
final class InkUITests: DeviceTestCase {
    private let play = "gut-5071"

    private func open(_ extra: [String: String] = [:]) -> XCUIApplication {
        launch(["APP_READER": play, "APP_READER_LINE": "L0009"].merging(extra) { $1 })
    }

    private func pager(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["reader-pager"] }

    private func draw(_ app: XCUIApplication, from a: CGVector, to b: CGVector, via m: CGVector) {
        let p = pager(app)
        let start = p.coordinate(withNormalizedOffset: a)
        let mid = p.coordinate(withNormalizedOffset: m)
        let end = p.coordinate(withNormalizedOffset: b)
        start.press(forDuration: 0.05, thenDragTo: mid)
        mid.press(forDuration: 0.05, thenDragTo: end)
    }

    func testInkFollowsItsLine() throws {
        // Ink is the Pencil's, and the Pencil is an iPad's: an iPhone's reader has no Ink button.
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Ink is iPad and Pencil only") }
        let app = open(["APP_READER_RESET_MARKS": "1", "APP_READER_INK": "1", "APP_READER_INK_FINGER": "1"])
        XCTAssertTrue(pager(app).waitForExistence(timeout: 20), "the reader opened")
        sleep(3)
        shot(app, "ink-0-ready")

        draw(app, from: CGVector(dx: 0.30, dy: 0.20), to: CGVector(dx: 0.62, dy: 0.20), via: CGVector(dx: 0.46, dy: 0.225))
        sleep(1)
        draw(app, from: CGVector(dx: 0.18, dy: 0.36), to: CGVector(dx: 0.24, dy: 0.46), via: CGVector(dx: 0.14, dy: 0.42))
        sleep(2)
        shot(app, "ink-1-drawn")

        let toggle = app.buttons["ink-toggle"].exists ? app.buttons["ink-toggle"] : app.buttons["Ink"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 4), "the Ink button is in the toolbar")
        toggle.tap()
        sleep(2)
        shot(app, "ink-2-read-only")

        // A page turn and back: the ink is still on its lines.
        pager(app).swipeLeft()
        sleep(2)
        shot(app, "ink-3-next-page")
        pager(app).swipeRight()
        sleep(2)
        shot(app, "ink-4-back")
        app.terminate()

        let again = open(["APP_READER_PREFS": "{\"size\":5}", "APP_READER_RESET_MARKS": "0"])
        XCTAssertTrue(pager(again).waitForExistence(timeout: 20))
        sleep(3)
        shot(again, "ink-5-larger")

        if again.buttons["Marks"].waitForExistence(timeout: 4) {
            again.buttons["Marks"].tap()
            sleep(2)
            shot(again, "ink-6-notebook")
        }
    }
}
