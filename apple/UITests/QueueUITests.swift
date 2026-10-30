import XCTest

final class QueueUITests: DeviceTestCase {
    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// Opens Detail for `id` and leaves the episode in the queue, starting clean.
    private func enqueue(_ id: String) {
        let app = launch(["APP_START_ITEM": id, "APP_DOOR_SECONDS": "300"])
        let inQueue = app.buttons["In queue"]
        let add = app.buttons["Add to queue"]
        XCTAssertTrue(add.waitForExistence(timeout: 30) || inQueue.exists, "queue verb on Detail")
        if inQueue.exists { inQueue.tap(); XCTAssertTrue(add.waitForExistence(timeout: 5)) }
        add.tap()
        XCTAssertTrue(app.buttons["In queue"].waitForExistence(timeout: 5), "added")
        shot(app, "queued-\(id.prefix(8))")
        app.terminate()
    }

    func testAddReorderRemove() throws {
        enqueue(Fixture.long)
        enqueue(Fixture.short)

        let app = launch(["APP_START_TAB": "library", "APP_DOOR_SECONDS": "300"])
        XCTAssertTrue(app.staticTexts["Queue"].waitForExistence(timeout: 20), "Queue section in Library")
        let first = row(app, Fixture.longTitle)
        XCTAssertTrue(first.waitForExistence(timeout: 10), "queued row")
        XCTAssertTrue(row(app, Fixture.shortTitle).exists, "second queued row")
        shot(app, "02-library-queue")
        XCTAssertLessThan(first.frame.minY, row(app, Fixture.shortTitle).frame.minY, "added order")

        // Reorder: Move down on the head puts it below the second item.
        let before = first.frame.minY
        first.press(forDuration: 1.2)
        let down = app.buttons["Move down"]
        XCTAssertTrue(down.waitForExistence(timeout: 3), "Move down verb")
        down.tap(); sleep(1)
        XCTAssertGreaterThan(row(app, Fixture.longTitle).frame.minY, before, "row moved down")
        shot(app, "03-moved-down")

        // Restore: remove both; the section's caption takes the last one's place.
        for title in [Fixture.longTitle, Fixture.shortTitle] {
            row(app, title).swipeLeft()
            let remove = app.buttons["Remove from queue"]
            XCTAssertTrue(remove.waitForExistence(timeout: 3), "swipe action on \(title)")
            remove.tap(); sleep(1)
        }
        shot(app, "04-removed")
        XCTAssertTrue(app.staticTexts["Episodes you add play in this order, after the one that is playing."]
            .waitForExistence(timeout: 5), "queue emptied: the section says what it would hold")
    }
}
