import XCTest

final class FollowUITests: DeviceTestCase {
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
        XCTAssertTrue(home.staticTexts["Following"].waitForExistence(timeout: 30), "Following on Home")
        let row = home.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", Fixture.seriesName)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the followed series on Home")
        shot(home, "02-home-following")
        row.tap()

        // Restore: unfollow from the series page; Home no longer lists it.
        let again = home.buttons["Following"]
        XCTAssertTrue(again.waitForExistence(timeout: 10), "Following on the series page")
        again.tap()
        XCTAssertTrue(home.buttons["Follow"].waitForExistence(timeout: 5), "unfollowed")
        home.terminate()

        let after = launch(["APP_START_TAB": "home", "APP_DOOR_SECONDS": "300"])
        XCTAssertTrue(after.staticTexts["Continue listening"].waitForExistence(timeout: 30)
                      || after.cells.firstMatch.waitForExistence(timeout: 30), "Home loaded")
        XCTAssertFalse(after.staticTexts["Following"].exists, "Following row gone")
        shot(after, "03-unfollowed")
    }
}
