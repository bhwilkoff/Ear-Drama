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
        while !element.exists && n < 12 { app.scrollUp(); n += 1 }
    }

    func testVersionsListsEveryCopy() throws {
        let app = try open(Multi.id)
        // The copies are one "Recordings  N  >" row that opens the list in place (a DisclosureGroup).
        let row = app.descendants(matching: .any).matching(identifier: "recordings-disclosure").firstMatch
        scrollTo(app, row)
        guard row.exists else { throw XCTSkip("\(Multi.id) has one recording in this catalog") }
        shot(app, "01-recordings-row")
        row.tap()
        sleep(1)
        for _ in 0..<3 where row.exists && row.frame.minY > app.frame.height * 0.35 { app.scrollUp() }
        XCTAssertTrue(row.exists, "the Recordings row stays on screen while its list is open")
        shot(app, "02-recordings-open")
        let floor = app.frame.height - 140
        let copies = app.buttons.allElementsBoundByIndex.filter {
            $0.frame.minY >= row.frame.maxY - 1 && $0.frame.maxY < floor && $0.frame.height > 30
        }
        XCTAssertGreaterThanOrEqual(copies.count, 2, "two or more copies listed once Recordings opens")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testCreditOpensPersonPage() throws {
        let app = try open(Multi.id)
        // R11d (D3-3): the credits are folded under "Cast and credits"; unfold it first. Each
        // credited name is a link, so it reads as a button, not a static text.
        let fold = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cast and credits'")).firstMatch
        scrollTo(app, fold)
        guard fold.exists else { throw XCTSkip("\(Multi.id) has no credits in this catalog") }
        fold.tap()
        let credit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Multi.person)).firstMatch
        scrollTo(app, credit)
        guard credit.exists else { throw XCTSkip("\(Multi.person) is not credited in this catalog") }
        shot(app, "01-credit")
        credit.tap()
        XCTAssertTrue(app.navigationBars[Multi.person].waitForExistence(timeout: 15), "person page titled with the name")
        // Under the head board their shows stand as tiles (one per show, its episode count as the value),
        // then each show's episodes as rows with their own Play, below the fold on a phone.
        let tile = app.buttons.matching(NSPredicate(format: "value CONTAINS 'episode'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "their shows as tiles")
        shot(app, "02-person")
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play '")).firstMatch
        scrollTo(app, play)
        XCTAssertTrue(play.exists, "their episodes listed under the tiles")
        shot(app, "03-person-episodes")
    }
}
