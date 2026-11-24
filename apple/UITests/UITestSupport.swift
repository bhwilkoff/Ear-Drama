import XCTest

/// Shared launch and screenshot helpers. Every launch is muted (APP_MUTE) and
/// skips onboarding; tests that change app state put it back before they end.
@MainActor class DeviceTestCase: XCTestCase {
    override func setUp() { continueAfterFailure = true; started = Date() }

    nonisolated(unsafe) var started = Date()

    /// One line per stage, seconds since the test began, so two runs of a test can be laid side by side and the
    /// stage whose time moves is the race (N7, owner: "instrument the stages and compare").
    func stage(_ what: String) {
        print(String(format: "STAGE %@ +%.1fs %@", name, Date().timeIntervalSince(started), what))
    }

    /// Waits for `predicate` on `element`, reporting how long it took or that it never held.
    @discardableResult
    func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval, _ what: String) -> Bool {
        let t0 = Date()
        let ok = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)],
                                  timeout: timeout) == .completed
        stage(String(format: "%@ %@ after %.1fs", what, ok ? "held" : "NEVER held", Date().timeIntervalSince(t0)))
        return ok
    }

    /// The first launch of each test starts from a new listener's lists (APP_RESET_USER_STATE); a
    /// relaunch inside the test keeps them, because tests that terminate and reopen the app check
    /// that a queue or a follow survives.
    private var launchedOnce = false

    func launch(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["APP_MUTE": "1", "APP_SKIP_ONBOARD": "1", "APP_UITEST_SESSION": "1"]
            .merging(launchedOnce ? [:] : ["APP_RESET_USER_STATE": "1"]) { $1 }
            .merging(env) { $1 }
        launchedOnce = true
        app.launch()
        return app
    }

    /// The episode page's download control, driven to "Download" from whatever an earlier test or run left on the
    /// device: APP_RESET_USER_STATE sets aside lists, not downloads, and a background transfer outlives the app, so
    /// the same episode can open downloaded, still downloading, or failed (DownloadsPlaceUITests waited only for
    /// "Download" or "Remove Download": N7). Returns false when the control never reached "Download".
    @discardableResult
    func downloadControlReady(_ app: XCUIApplication) -> Bool {
        let states = ["Download", "Remove Download", "Cancel Download", "Try Again"]
        let any = app.buttons.matching(NSPredicate(format: "label IN %@", states)).firstMatch
        guard wait(any, "exists == true", timeout: 30, "a download control") else { return false }
        for _ in 0..<4 {
            if app.buttons["Download"].exists { stage("download control: Download"); return true }
            for verb in ["Remove Download", "Cancel Download", "Try Again"] where app.buttons[verb].exists {
                stage("download control: \(verb), clearing it")
                app.buttons[verb].tap()
                break
            }
            let next = app.buttons.matching(NSPredicate(format: "label IN %@", ["Download", "Remove Download", "Cancel Download"])).firstMatch
            wait(next, "exists == true", timeout: 15, "the control's next state")
        }
        return app.buttons["Download"].exists
    }

    /// Scrolls until `element` can take a tap clear of the bars: on screen, hittable, and wholly above the tab
    /// bar and the mini player, with its frame the same on two reads (the scroll has stopped). An element that
    /// merely exists may be a lazy row rendered just off screen or under the tab bar, where a tap lands on the
    /// bar instead (DownloadsPlaceUITests' Library row: N7).
    @discardableResult
    func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 10) -> Bool {
        func clear() -> Bool {
            guard element.exists, element.isHittable else { return false }
            var floor = app.frame.maxY
            let bar = app.tabBars.firstMatch
            if bar.exists { floor = min(floor, bar.frame.minY) }
            let mini = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Now playing'")).firstMatch
            if mini.exists { floor = min(floor, mini.frame.minY) }
            let f1 = element.frame
            usleep(300_000)
            return element.frame == f1 && f1.maxY <= floor && f1.minY >= 0
        }
        for n in 0...swipes {
            if clear() { stage("revealed after \(n) swipes"); return true }
            if n < swipes { app.scrollUp() }
        }
        stage("NOT revealed after \(swipes) swipes")
        return false
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

/// The shows the tests open, picked per run from the published catalog by tools/uitest_fixture.py (DESIGN-LOOP
/// N12, owner 2026-11-04: "It seems to me that it is running the same things over and over"). The runner passes
/// them as TEST_RUNNER_UITEST_FIXTURE, which arrives here as UITEST_FIXTURE; each id is chosen by shape (length,
/// picture, about text, name length), never by name. A run started from Xcode without the runner gets the
/// fallback set and says so in the log.
enum Fixture {
    private static let picked: [String: String] = {
        let raw = ProcessInfo.processInfo.environment["UITEST_FIXTURE"] ?? ""
        let json = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
        let fields = json.compactMapValues { $0 as? String }
        if fields.isEmpty {
            print("FIXTURE fallback (no UITEST_FIXTURE: run tools/ios_uitest.py to pick from the catalog)")
        } else {
            print("FIXTURE \(fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        }
        return fields
    }()

    private static func value(_ key: String, _ fallback: String) -> String { picked[key] ?? fallback }

    /// 25 to 35 minutes, a unique title: the player, seek and queue tests.
    static var long: String { value("long", "xminusone|1956-04-24") }
    static var longTitle: String { value("longTitle", "The Sense of Wonder") }
    /// The series of `long`: the follow test and the series action row.
    static var series: String { value("series", "xminusone") }
    static var seriesName: String { value("seriesName", "X Minus One") }
    /// One to four minutes, a unique title: the download, search and sleep timer tests.
    static var short: String { value("short", "hopalongcassidy|tandyclydebio") }
    static var shortTitle: String { value("shortTitle", "Andy Clyde Bio") }
    /// Series pages of each shape the grammar must hold: a picture, about text and a long run; none of those and a
    /// handful of episodes; about text without a picture; a name of 60 characters or more.
    static var rich: String { value("rich", "gunsmoke") }
    static var bare: String { value("bare", "nelliestuart") }
    static var noPicture: String { value("noPicture", "xminusone") }
    static var longName: String { value("longName", "librivox2469") }
    /// An episode of 25 to 35 minutes whose show has a served picture, and that show's name: the show-art test.
    static var faced: String { value("faced", "gunsmoke|1952-04-26") }
    static var facedSeries: String { value("facedSeries", "Gunsmoke") }
}
