import XCTest

/// Layout audit on the real phone: each screen at its top, then scrolled page by page to its end,
/// every page attached. The last page of a screen must end above the tab bar and mini player.
final class LayoutSweepUITests: DeviceTestCase {
    func testHome() { sweep(tab("home"), "home") }
    func testRecord() { sweep(tab("record"), "record", pages: 9) }
    /// Stations is Home's push (Decision 075); its door opens Home, then the screen.
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
    /// Each step waits on the state it needs, never a fixed sleep (N7). The episode is paused as soon as the mini
    /// player shows it: playing, it crossed ListeningHistory's 30-second "started" mark at a moment set by the
    /// network and the load, and Home then inserted its Continue section at the top mid-sweep, moving every row
    /// under the end check (testMiniHome failed 3 of 4 under load, 2026-10-31). Paused, the page holds still.
    private func withMini(_ tab: String, _ name: String, root: String? = nil) {
        stage("fixture long=\(Fixture.long)")
        let app = launch(["APP_START_ITEM": Fixture.long, "APP_AUTOPLAY": "1", "APP_DOOR_SECONDS": "900"])
        let close = app.buttons["Close player"]
        XCTAssertTrue(wait(close, "exists == true AND hittable == true", timeout: 30, "the player sheet"), "the player opened")
        close.tap()
        wait(close, "exists == false", timeout: 10, "the sheet closed")
        let mini = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Now playing'")).firstMatch
        XCTAssertTrue(wait(mini, "exists == true AND hittable == true", timeout: 60, "the mini player"), "the mini player stands")
        let pause = app.buttons.matching(NSPredicate(format: "label == 'Pause'")).firstMatch
        if wait(pause, "exists == true AND hittable == true", timeout: 30, "the mini's Pause") {
            pause.tap()
            wait(app.buttons.matching(NSPredicate(format: "label == 'Play'")).firstMatch, "exists == true", timeout: 10, "paused")
        }
        openTab(app, tab)
        let title = root ?? tab
        if !wait(app.navigationBars[title], "exists == true", timeout: 10, "\(title) at its root") {
            // A reselected tab may keep its pushed page (the door pushed the episode on Home): go back to the root.
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            XCTAssertTrue(wait(app.navigationBars[title], "exists == true", timeout: 10, "\(title) after Back"), "\(title) at its root")
        }
        wait(app.progressIndicators.firstMatch, "exists == false", timeout: 30, "\(title) loaded")
        sweep(app, name, pages: 9)
    }

    func testMiniRecord() { withMini("Record", "mini-record") }
    func testMiniLibrary() { withMini("Library", "mini-library") }
    func testMiniHome() { withMini("Home", "mini-home", root: "Ear Drama") }
    func testMiniBrowse() { withMini("Browse", "mini-browse") }
    func testMiniSearch() { withMini("Search", "mini-search") }

    /// A name of 60 characters or more (Fixture.longName): the head board holds it to three lines and its facts stay on screen.
    func testLongTitleSeries() { sweep(tab("browse", ["APP_START_ITEM": Fixture.longName]), "series-long-title") }

    /// Record (Decision 075: the plays are tiles on the Record tab), a play, Record This, the cast sheet and
    /// a taken part's studio gate. Nothing is recorded: Start Recording is never pressed. The production
    /// made here is deleted again.
    func testCreate() {
        let app = tab("record")
        sweep(app, "create-record", pages: 3)
        for _ in 0..<3 { app.swipeDown(velocity: .fast) }
        let tile = app.buttons.matching(identifier: "play-tile").firstMatch
        for _ in 0..<8 where !(tile.exists && tile.isHittable) { app.scrollUp() }
        XCTAssertTrue(tile.waitForExistence(timeout: 20) && tile.isHittable, "a play tile on Record")
        tile.tap(); sleep(3)
        sweep(app, "create-script", pages: 4)
        for _ in 0..<4 { app.scrollDown() }
        let start = app.buttons["Record This"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Record This")
        start.tap(); sleep(3)
        sweep(app, "create-cast", pages: 6)
        // A part is taken from its card ("Take part", then a name in the alert), which opens the script reader
        // with the studio dock at its gate ("Start Recording", or the account a second production needs). Start
        // is never pressed: the microphone is asked for there, and nothing is recorded. Close returns to the
        // production. (A bare "Record" query matched the Record tab and left the production, 2026-11-23.)
        let take = app.buttons["Take part"].firstMatch
        for _ in 0..<6 where !(take.exists && take.isHittable) { app.scrollUp() }
        XCTAssertTrue(take.waitForExistence(timeout: 5) && take.isHittable, "Take part on a part's card")
        take.tap()
        let name = app.alerts.textFields.firstMatch
        if name.waitForExistence(timeout: 3) { name.tap(); name.typeText("Sweep") }
        let confirm = app.alerts.buttons["Take Part"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "the Take this part alert")
        confirm.tap(); sleep(3)
        XCTAssertTrue(app.descendants(matching: .any)["studio-gate"].waitForExistence(timeout: 15),
                      "the studio opens at its gate")
        shot(app, "create-studio-gate")
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), "Close on the reader")
        close.tap(); sleep(2)
        for _ in 0..<12 where !app.buttons["Delete Production"].isHittable { app.scrollUp() }
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

    /// A series page of each shape (Fixture: picked per run from the catalog): rich, bare, words without a picture.
    func testSeries() { sweep(tab("browse", ["APP_START_ITEM": Fixture.rich]), "series") }
    func testBareSeries() { sweep(tab("browse", ["APP_START_ITEM": Fixture.bare]), "series-bare") }
    func testNoPictureSeries() { sweep(tab("browse", ["APP_START_ITEM": Fixture.noPicture]), "series-no-picture") }

    func testEpisode() {
        let app = launch(["APP_START_ITEM": Fixture.long, "APP_DOOR_SECONDS": "300"])
        sleep(8)
        sweep(app, "episode")
    }
}
