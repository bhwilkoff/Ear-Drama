import XCTest

/// Shared launch and screenshot helpers. Every launch is muted (APP_MUTE) and
/// skips onboarding; tests that change app state put it back before they end.
@MainActor class DeviceTestCase: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func launch(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["APP_MUTE": "1", "APP_SKIP_ONBOARD": "1"]
            .merging(env) { $1 }
        app.launch()
        return app
    }

    func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func hittable(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let all = app.buttons.matching(identifier: id).allElementsBoundByIndex
        return all.first(where: { $0.isHittable }) ?? all.last ?? app.buttons[id]
    }

    /// First element anywhere whose label matches the regex.
    func text(_ app: XCUIApplication, matching rx: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "(?s).*(\(rx)).*")).firstMatch
    }

    func elapsed(_ app: XCUIApplication) -> Int {
        let v = (app.sliders["Position"].value as? String) ?? ""
        return v.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }
}

/// Catalog ids the tests open. Both are in the live catalog (not the clean-only
/// seed), which the app fetches on first launch.
enum Fixture {
    /// 28 minutes, not a serial: the player and queue tests.
    static let long = "xminusone|1956-04-24"
    static let longTitle = "The Sense of Wonder"
    /// 137 seconds: the download test.
    static let short = "hopalongcassidy|tandyclydebio"
    static let shortTitle = "Andy Clyde Bio"
}
