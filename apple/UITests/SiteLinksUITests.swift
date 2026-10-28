import XCTest

/// Credits, Privacy, and Take-down requests are links to the website (iOS-DESIGN
/// §4.10a). The first test asserts they exist and taps none; the second taps
/// Credits and follows it to Safari and back.
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

    /// SiteLinkRows uses a SwiftUI Link, which hands the address to the system:
    /// Safari comes forward and the app leaves the foreground.
    func testCreditsOpensTheSiteAndComesBack() throws {
        let app = launch(["APP_START_TAB": "library", "APP_DOOR_SECONDS": "120"])
        let link = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Credits")).firstMatch
        var n = 0
        while !link.waitForExistence(timeout: n == 0 ? 25 : 1) && n < 6 { app.swipeUp(); n += 1 }
        XCTAssertTrue(link.exists, "Credits link in Library")
        link.tap()

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15), "Safari came forward")
        XCTAssertNotEqual(app.state, .runningForeground, "the app left the foreground")
        shot(safari, "01-safari")

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "back in the app")
        XCTAssertTrue(link.waitForExistence(timeout: 10), "Library is back")
        shot(app, "02-library-again")
        safari.terminate()
    }
}
