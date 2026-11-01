import XCTest

/// Layout audit on the real phone: each screen at its top, then scrolled page by page to its end,
/// every page attached. The last page of a screen must end above the tab bar and mini player.
final class LayoutSweepUITests: DeviceTestCase {
    /// At the end of a screen's scroll nothing may straddle the top of the bar (the mini player, else
    /// the tab bar), and no list row may sit wholly behind it: the last element is fully visible.
    private func assertEndClears(_ app: XCUIApplication, _ name: String) {
        let bar = app.tabBars.firstMatch
        guard bar.exists else { return }
        var top = bar.frame.minY
        let mini = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Now playing'")).firstMatch
        if mini.exists { top = min(top, mini.frame.minY) }
        let screen = app.frame.height
        let kinds: [XCUIElementQuery] = [app.cells, app.staticTexts, app.buttons, app.images]
        for query in kinds {
            for el in query.allElementsBoundByIndex where el.exists && el.isHittable && !bar.buttons[el.label].exists {
                let f = el.frame
                if f.isEmpty || f.minY >= screen { continue }
                if f.minY < top - 4 && f.maxY > top + 4 {
                    XCTFail("\(name): \(el.elementType.rawValue) '\(el.label.prefix(40))' straddles the bar top \(Int(top)): \(Int(f.minY))-\(Int(f.maxY))")
                }
            }
        }
        for cell in app.cells.allElementsBoundByIndex where cell.exists && cell.frame.minY >= top && cell.frame.minY < screen {
            XCTFail("\(name): row '\(cell.label.prefix(40))' is wholly behind the bar at the end of the scroll")
        }
    }

    private func sweep(_ app: XCUIApplication, _ name: String, pages: Int = 3) {
        shot(app, "\(name)-p00")
        var last = app.screenshot().pngRepresentation
        for i in 1...pages {
            app.swipeUp()
            usleep(600_000)
            let now = app.screenshot().pngRepresentation
            if now == last { assertEndClears(app, name); break }
            last = now
            shot(app, "\(name)-p\(String(format: "%02d", i))")
        }
    }

    private func tab(_ t: String, _ extra: [String: String] = [:]) -> XCUIApplication {
        let app = launch(["APP_START_TAB": t, "APP_DOOR_SECONDS": "300"].merging(extra) { $1 })
        sleep(6)
        return app
    }

    func testHome() { sweep(tab("home"), "home") }
    func testStations() { sweep(tab("stations"), "stations", pages: 9) }
    func testLibrary() { sweep(tab("library"), "library", pages: 9) }
    func testSurprise() { sweep(tab("surprise"), "surprise") }

    func testBrowse() {
        let app = tab("browse")
        sweep(app, "browse-shows")
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        app.buttons["Voices"].tap(); sleep(3)
        sweep(app, "browse-voices", pages: 3)
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        app.buttons["Ear dramas"].tap(); sleep(3)
        sweep(app, "browse-plays", pages: 6)
    }

    /// With an episode loaded the mini player stands above the tab bar; the end of each screen must clear both.
    private func withMini(_ tab: String, _ name: String, tapBar: Bool = true) {
        let app = launch(["APP_START_ITEM": Fixture.long, "APP_AUTOPLAY": "1", "APP_DOOR_SECONDS": "300"])
        sleep(8)
        let close = app.buttons["Close player"]
        if close.waitForExistence(timeout: 5) { close.tap(); sleep(2) }
        openTab(app, tab)
        sleep(3)
        sweep(app, name, pages: 9)
    }

    func testMiniStations() { withMini("Stations", "mini-stations") }
    func testMiniLibrary() { withMini("Library", "mini-library") }
    func testMiniHome() { withMini("Home", "mini-home") }
    func testMiniBrowse() { withMini("Browse", "mini-browse") }
    func testMiniSearch() { withMini("Search", "mini-search") }

    /// A 71-character title: the head board holds it to three lines and its facts stay on screen.
    func testLongTitleSeries() { sweep(tab("browse", ["APP_START_ITEM": "librivox2469"]), "series-long-title") }

    /// A script's page, the cast sheet and the recorder in its three modes. Nothing is recorded: the
    /// Record button is never pressed. The production made here is deleted again.
    func testCreate() {
        let app = tab("browse")
        app.buttons["Kind"].tap()
        app.buttons["Plays"].tap(); sleep(3)
        let tile = app.buttons.matching(identifier: "show-tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "a script tile")
        tile.tap(); sleep(3)
        sweep(app, "create-script", pages: 4)
        for _ in 0..<4 { app.swipeDown() }
        let start = app.buttons["Start an ear drama"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Start an ear drama")
        start.tap(); sleep(3)
        sweep(app, "create-cast", pages: 6)
        for _ in 0..<6 { app.swipeDown() }
        let record = app.buttons["Record"].firstMatch
        if record.waitForExistence(timeout: 3) {
            record.tap(); sleep(3)
            shot(app, "create-recorder-run")
            for mode in ["Line by line", "Step", "Run through"] where app.buttons[mode].exists {
                app.buttons[mode].tap(); sleep(2)
                shot(app, "create-recorder-\(mode)")
            }
            app.navigationBars.buttons.firstMatch.tap(); sleep(2)
        }
        for _ in 0..<12 where !app.buttons["Delete Production"].isHittable { app.swipeUp() }
        if app.buttons["Delete Production"].isHittable {
            app.buttons["Delete Production"].tap()
            let confirm = app.buttons["Delete Production and Its Recordings"]
            if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        }
        sleep(2)
    }

    func testSearch() {
        let app = tab("search")
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) { field.tap(); field.typeText("Dragnet\n") }
        sleep(4)
        sweep(app, "search", pages: 5)
    }

    func testPerson() {
        let app = tab("browse")
        app.buttons["Voices"].tap(); sleep(3)
        let face = app.buttons.matching(identifier: "voice-face").firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 20), "a voice")
        shot(app, "person-before-tap")
        XCTAssertTrue(face.isHittable, "face \(face.label) frame \(face.frame) hittable")
        print("PERSON-TAP label=\(face.label) frame=\(face.frame)")
        face.tap(); sleep(4)
        XCTAssertEqual(app.state, .runningForeground, "the app stays in front after tapping a voice")
        sweep(app, "person", pages: 6)
    }

    func testInvite() {
        let app = launch(["APP_DOOR_SECONDS": "300"])
        sleep(3)
        app.open(URL(string: "eardrama://invite#\(String(repeating: "A", count: 43))")!)
        sleep(6)
        sweep(app, "invite", pages: 3)
        app.buttons["Not Now"].tap()
    }

    /// The ink of a button's picture, as a box in points inside the button, measured against its own
    /// corner color with the 1 pt border and a 3 pt edge left out.
    private func inkBox(_ button: XCUIElement) -> CGRect? {
        let shot = button.screenshot().image
        guard let cg = shot.cgImage else { return nil }
        let scale = shot.scale
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let edge = Int(4 * scale)
        let c = ((h / 2) * w + edge) * 4
        let base = (Int(data[c]), Int(data[c + 1]), Int(data[c + 2]))
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in edge..<(h - edge) {
            for x in edge..<(w - edge) {
                let i = (y * w + x) * 4
                let d = abs(Int(data[i]) - base.0) + abs(Int(data[i + 1]) - base.1) + abs(Int(data[i + 2]) - base.2)
                if d > 120 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX >= 0 else { return nil }
        let box = CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                         width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        // A landscape iPad hands back the screenshot's pixels in portrait order, so its axes are
        // the button's turned 90 degrees: every glyph read as off center on both axes at once.
        let frame = button.frame
        let turned = (w > h) != (frame.width > frame.height) && abs(frame.width - frame.height) > 1
        return turned ? CGRect(x: box.minY, y: box.minX, width: box.height, height: box.width) : box
    }

    /// Every button in a page's action row draws its picture and title centered: a folded button's glyph
    /// in the middle, and nothing clipped at the trailing edge.
    private func assertCentered(_ app: XCUIApplication, _ names: [String], _ page: String) {
        for name in names {
            let b = app.buttons[name].firstMatch
            guard b.waitForExistence(timeout: 5) else { XCTFail("\(page): no '\(name)' button"); continue }
            guard let ink = inkBox(b) else { XCTFail("\(page): '\(name)' drew nothing"); continue }
            let f = b.frame
            XCTAssertEqual(ink.midX, f.width / 2, accuracy: 4, "\(page): '\(name)' content off center (ink \(ink), button \(f))")
            XCTAssertEqual(ink.midY, f.height / 2, accuracy: 4, "\(page): '\(name)' content off center vertically (ink \(ink), button \(f))")
            XCTAssertGreaterThanOrEqual(f.width, 44, "\(page): '\(name)' narrower than 44 pt")
        }
    }

    func testActionRowsAreCentered() {
        let ep = launch(["APP_START_ITEM": Fixture.long, "APP_DOOR_SECONDS": "300"])
        sleep(8)
        shot(ep, "actions-episode")
        assertCentered(ep, ["Play", "Add to queue", "Download", "Share"], "episode")
        ep.buttons["Add to queue"].tap()
        XCTAssertTrue(ep.buttons["In queue"].waitForExistence(timeout: 5), "queued")
        shot(ep, "actions-episode-queued")
        assertCentered(ep, ["Play", "In queue", "Download", "Share"], "episode, queued")
        ep.buttons["In queue"].tap()
        XCTAssertTrue(ep.buttons["Add to queue"].waitForExistence(timeout: 5), "unqueued again")
        ep.terminate()
        let series = launch(["APP_START_ITEM": Fixture.series, "APP_DOOR_SECONDS": "300"])
        sleep(8)
        shot(series, "actions-series")
        assertCentered(series, ["Follow", "Share"], "series")
        series.buttons["Follow"].tap()
        XCTAssertTrue(series.buttons["Following"].waitForExistence(timeout: 5), "followed")
        shot(series, "actions-series-following")
        assertCentered(series, ["Following", "Share"], "series, following")
        series.buttons["Following"].tap()
        XCTAssertTrue(series.buttons["Follow"].waitForExistence(timeout: 5), "unfollowed again")
    }

    func testSeries() {
        let app = tab("browse", ["APP_START_ITEM": "tarzan"])
        sweep(app, "series")
    }

    func testEpisode() {
        let app = launch(["APP_START_ITEM": Fixture.long, "APP_DOOR_SECONDS": "300"])
        sleep(8)
        sweep(app, "episode")
    }
}
