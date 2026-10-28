import XCTest

/// Credits, Privacy, and Take-down requests are links to the website (iOS-DESIGN
/// §4.10a). The test asserts they exist and taps none, so Safari never opens.
final class SiteLinksUITests: DeviceTestCase {
    func testLibraryCarriesTheThreePages() throws {
        let app = launch(["APP_START_TAB": "library", "APP_DOOR_SECONDS": "60"])
        for name in ["Credits", "Privacy", "Take-down requests"] {
            let link = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
            var n = 0
            while !link.waitForExistence(timeout: n == 0 ? 25 : 1) && n < 6 { app.swipeUp(); n += 1 }
            XCTAssertTrue(link.exists, "\(name) link in Library")
        }
        shot(app, "01-library-links")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
