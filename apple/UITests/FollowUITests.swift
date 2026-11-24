import XCTest

final class FollowUITests: DeviceTestCase {
    /// Followed shows live in Library's Listening side as "Shows you follow" since Decision 075 took
    /// Following off Home; a List only exposes the rows on screen, so swipe until it appears.
    @discardableResult
    private func scrollTo(_ el: XCUIElement, in app: XCUIApplication, swipes: Int = 10) -> Bool {
        for _ in 0..<swipes where !(el.exists && el.isHittable) { app.scrollUp() }
        return el.exists
    }

    /// The followed show's tile on the shelf: its label carries the series name.
    private func seriesTile(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Fixture.seriesName)).firstMatch
    }

    /// Library has drawn: the Listening | Making switch is there.
    private func libraryLoaded(_ app: XCUIApplication) -> Bool {
        app.buttons["Listening"].waitForExistence(timeout: 30)
    }

    func testFollowShowsInLibraryThenUnfollow() throws {
        let app = launch(["APP_START_ITEM": Fixture.series, "APP_DOOR_SECONDS": "300"])
        let follow = app.buttons["Follow"]
        let following = app.buttons["Following"]
        XCTAssertTrue(follow.waitForExistence(timeout: 30) || following.exists, "Follow on the series page")
        if following.exists { following.tap(); XCTAssertTrue(follow.waitForExistence(timeout: 5)) }
        follow.tap()
        XCTAssertTrue(app.buttons["Following"].waitForExistence(timeout: 5), "followed")
        shot(app, "01-followed")
        app.terminate()

        let library = launch(["APP_START_TAB": "library", "APP_DOOR_SECONDS": "300"])
        XCTAssertTrue(libraryLoaded(library), "Library loaded")
        XCTAssertTrue(scrollTo(library.staticTexts["Shows you follow"], in: library), "Shows you follow in Library")
        let tile = seriesTile(library)
        XCTAssertTrue(scrollTo(tile, in: library, swipes: 3), "the followed series on the shelf")
        shot(library, "02-library-following")
        tile.tap()

        // Restore: unfollow from the series page; Library no longer lists it.
        let again = library.buttons["Following"]
        XCTAssertTrue(again.waitForExistence(timeout: 10), "Following on the series page")
        again.tap()
        XCTAssertTrue(library.buttons["Follow"].waitForExistence(timeout: 5), "unfollowed")
        library.terminate()

        let after = launch(["APP_START_TAB": "library", "APP_DOOR_SECONDS": "300"])
        XCTAssertTrue(libraryLoaded(after), "Library loaded")
        XCTAssertFalse(scrollTo(after.staticTexts["Shows you follow"], in: after, swipes: 3), "Shows you follow gone")
        shot(after, "03-unfollowed")
    }
}
