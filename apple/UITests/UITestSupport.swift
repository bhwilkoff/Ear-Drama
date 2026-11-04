import XCTest

/// Shared launch and screenshot helpers. Every launch is muted (APP_MUTE) and
/// skips onboarding; tests that change app state put it back before they end.
@MainActor class DeviceTestCase: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    /// The first launch of each test starts from a new listener's lists (APP_RESET_USER_STATE); a
    /// relaunch inside the test keeps them, because tests that terminate and reopen the app check
    /// that a queue or a follow survives.
    private var launchedOnce = false

    func launch(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["APP_MUTE": "1", "APP_SKIP_ONBOARD": "1"]
            .merging(launchedOnce ? [:] : ["APP_RESET_USER_STATE": "1"]) { $1 }
            .merging(env) { $1 }
        launchedOnce = true
        app.launch()
        return app
    }

    func shot(_ app: XCUIApplication, _ name: String) {
        // The screen, not the app: a rotated app's own screenshot keeps the portrait canvas and
        // cuts the landscape page off at both edges (iPad, 2026-11-04).
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func hittable(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let all = app.buttons.matching(identifier: id).allElementsBoundByIndex
        return all.first(where: { $0.isHittable }) ?? all.last ?? app.buttons[id]
    }

    /// A section by name: the tab bar on an iPhone, the sidebar on an iPad, where there is no tab
    /// bar and each section is a cell labeled with its name (iPad Pro, 2026-10-30).
    func openTab(_ app: XCUIApplication, _ name: String) {
        let bar = app.tabBars.buttons[name]
        if bar.exists { bar.tap(); return }
        let cell = app.cells.matching(NSPredicate(format: "label == %@", name)).firstMatch
        if !cell.exists {
            let button = app.buttons[name].firstMatch
            if button.exists { button.tap(); return }
            let toggle = app.buttons["Show Sidebar"].firstMatch
            if toggle.exists { toggle.tap(); sleep(1) }
        }
        app.cells.matching(NSPredicate(format: "label == %@", name)).firstMatch.tap()
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
    /// The series of `long`: the follow test.
    static let series = "xminusone"
    static let seriesName = "X Minus One"
    /// 137 seconds: the download test.
    static let short = "hopalongcassidy|tandyclydebio"
    static let shortTitle = "Andy Clyde Bio"
}
