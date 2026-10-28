import XCTest

final class DetailUITests: DeviceTestCase {
    /// A live-catalog episode with several recordings and credits. Absent means skip, not fail.
    private enum Multi {
        static let id = "suspense|1942-06-17"
        static let person = "Bernard Herrmann"
    }

    private func open(_ id: String) throws -> XCUIApplication {
        let app = launch(["APP_START_ITEM": id, "APP_DOOR_SECONDS": "300"])
        guard app.buttons["Add to queue"].waitForExistence(timeout: 30) || app.buttons["In queue"].exists else {
            throw XCTSkip("\(id) is not in this catalog")
        }
        return app
    }

    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        var n = 0
        while !element.exists && n < 12 { app.swipeUp(); n += 1 }
    }

    func testVersionsListsEveryCopy() throws {
        let app = try open(Multi.id)
        let header = app.staticTexts["Versions"]
        scrollTo(app, header)
        guard header.exists else { throw XCTSkip("\(Multi.id) has one recording in this catalog") }
        app.swipeUp()
        XCTAssertTrue(header.exists, "Versions header still on screen")
        shot(app, "01-versions")
        let floor = app.frame.height - 140
        let copies = app.buttons.allElementsBoundByIndex.filter {
            $0.frame.minY > header.frame.maxY && $0.frame.maxY < floor
        }
        XCTAssertGreaterThanOrEqual(copies.count, 2, "two or more copies listed under Versions")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testCreditOpensPersonPage() throws {
        let app = try open(Multi.id)
        let credit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", Multi.person)).firstMatch
        scrollTo(app, credit)
        guard credit.exists else { throw XCTSkip("\(Multi.person) is not credited in this catalog") }
        shot(app, "01-credit")
        credit.tap()
        XCTAssertTrue(app.navigationBars[Multi.person].waitForExistence(timeout: 15), "person page titled with the name")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10), "their episodes listed")
        shot(app, "02-person")
    }
}
