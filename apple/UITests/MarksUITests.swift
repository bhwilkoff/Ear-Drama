import XCTest

/// Marks in the script reader (Decision 076 S5): press words, the edit menu's six verbs, a tap on a mark, the
/// notebook, a new text size. Every frame is attached for a person to read. Launches the play through the reader
/// door (APP_READER) and erases its marks first (APP_READER_RESET_MARKS), so the run starts from nothing.
final class MarksUITests: DeviceTestCase {
    private let play = "gut-5071"

    private func open(_ extra: [String: String] = [:]) -> XCUIApplication {
        launch(["APP_READER": play, "APP_READER_LINE": "L0009", "APP_READER_RESET_MARKS": "1"].merging(extra) { $1 })
    }

    private func pager(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["reader-pager"] }

    /// Presses a word and drags to the right, as a reader's finger does, then lets go: the edit menu opens.
    private func select(_ app: XCUIApplication, x: CGFloat, y: CGFloat, dx: CGFloat) {
        let p = pager(app)
        let a = p.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        let b = p.coordinate(withNormalizedOffset: CGVector(dx: x + dx, dy: y))
        a.press(forDuration: 0.8, thenDragTo: b)
    }

    private func choose(_ app: XCUIApplication, _ title: String) {
        let item = app.menuItems[title]
        if item.waitForExistence(timeout: 4) { item.tap(); return }
        let button = app.buttons[title].firstMatch
        if button.waitForExistence(timeout: 2) { button.tap() }
    }

    private func write(_ app: XCUIApplication, _ words: String) {
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        if field.waitForExistence(timeout: 4) { field.tap(); field.typeText(words) }
        shot(app, "marks-compose-\(words.prefix(4))")
        let save = app.buttons["Save"]
        if save.waitForExistence(timeout: 2) { save.tap() }
    }

    func testSixMarksTheNotebookAndANewSize() {
        let app = open()
        XCTAssertTrue(pager(app).waitForExistence(timeout: 20), "the reader opened")
        sleep(3)
        shot(app, "marks-0-page")

        select(app, x: 0.3, y: 0.18, dx: 0.35)
        sleep(1)
        shot(app, "marks-1-bar")
        choose(app, "Highlight")
        sleep(1)
        select(app, x: 0.3, y: 0.30, dx: 0.35)
        choose(app, "Underline")
        sleep(1)
        select(app, x: 0.3, y: 0.42, dx: 0.12)
        choose(app, "Breath")
        sleep(1)
        select(app, x: 0.3, y: 0.52, dx: 0.12)
        choose(app, "Pause")
        sleep(1)
        select(app, x: 0.3, y: 0.62, dx: 0.12)
        choose(app, "Beat")
        write(app, "the turn")
        sleep(1)
        select(app, x: 0.3, y: 0.72, dx: 0.3)
        choose(app, "Note")
        write(app, "say it warm")
        sleep(2)
        shot(app, "marks-2-all-six")

        pager(app).coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.18)).tap()
        sleep(1)
        shot(app, "marks-3-opened")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)

        if app.buttons["Marks"].waitForExistence(timeout: 4) {
            app.buttons["Marks"].tap()
            sleep(2)
            shot(app, "marks-4-notebook")
            let done = app.buttons["Done"]
            if done.exists { done.tap() }
        }
        sleep(1)
        app.terminate()

        let again = open(["APP_READER_PREFS": "{\"size\":5}", "APP_READER_RESET_MARKS": "0"])
        XCTAssertTrue(pager(again).waitForExistence(timeout: 20))
        sleep(3)
        shot(again, "marks-5-larger")
    }
}
