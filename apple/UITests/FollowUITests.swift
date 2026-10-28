import XCTest

final class FollowUITests: DeviceTestCase {
    /// Home's Following section sits under up to ten Continue rows, and a List only
    /// exposes the rows on screen: swipe until it appears (seen 2026-10-28).
    @discardableResult
    private func scrollTo(_ el: XCUIElement, in app: XCUIApplication, swipes: Int = 10) -> Bool {
        for _ in 0..<swipes where !(el.exists && el.isHittable) { app.swipeUp() }
        return el.exists
    }

    /// The series row under Following, not an episode of it in Continue: a series
    /// row's label starts with the series name, an episode row's with its date.
    private func seriesRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Fixture.seriesName)).firstMatch
    }

    func testFollowShowsOnHomeThenUnfollow() throws {
        let app = launch(["APP_START_ITEM": Fixture.series, "APP_DOOR_SECONDS": "300"])
        let follow = app.buttons["Follow"]
        let following = app.buttons["Following"]
        XCTAssertTrue(follow.waitForExistence(timeout: 30) || following.exists, "Follow on the series page")
        if following.exists { following.tap(); XCTAssertTrue(follow.waitForExistence(timeout: 5)) }
        follow.tap()
        XCTAssertTrue(app.buttons["Following"].waitForExistence(timeout: 5), "followed")
        shot(app, "01-followed")
        app.terminate()

        let home = launch(["APP_START_TAB": "home", "APP_DOOR_SECONDS": "300"])
        XCTAssertTrue(home.staticTexts["Continue listening"].waitForExistence(timeout: 30), "Home loaded")
        XCTAssertTrue(scrollTo(home.staticTexts["Following"], in: home), "Following on Home")
        let row = seriesRow(home)
        XCTAssertTrue(scrollTo(row, in: home, swipes: 3), "the followed series under Following")
        shot(home, "02-home-following")
        row.tap()

        // Restore: unfollow from the series page; Home no longer lists it.
        let again = home.buttons["Following"]
        XCTAssertTrue(again.waitForExistence(timeout: 10), "Following on the series page")
        again.tap()
        XCTAssertTrue(home.buttons["Follow"].waitForExistence(timeout: 5), "unfollowed")
        home.terminate()

        let after = launch(["APP_START_TAB": "home", "APP_DOOR_SECONDS": "300"])
        XCTAssertTrue(after.staticTexts["Continue listening"].waitForExistence(timeout: 30), "Home loaded")
        XCTAssertFalse(scrollTo(after.staticTexts["Following"], in: after), "Following section gone")
        shot(after, "03-unfollowed")
    }
}
