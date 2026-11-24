import XCTest

/// App Review screen recording (2.1 Information Needed, 2026-11-14): the typical flow at a human pace.
/// Not part of the suite; recorded once with devicectl screen-record.
final class AppReviewTourUITests: DeviceTestCase {
    private func mark(_ s: String) { print("TOUR-MARK \(Date().timeIntervalSince1970) \(s)") }

    private func dump(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(string: app.debugDescription)
        a.name = "tree-\(name)"
        a.lifetime = .keepAlways
        add(a)
    }

    private func pause(_ s: Double = 1.5) { usleep(UInt32(s * 1_000_000)) }

    @discardableResult
    private func tap(_ e: XCUIElement, wait: Double = 8) -> Bool {
        guard e.waitForExistence(timeout: wait) else { return false }
        if !e.isHittable { pause(0.5) }
        guard e.isHittable else { return false }
        e.tap()
        return true
    }

    private func firstHittable(_ q: XCUIElementQuery, minY: CGFloat = 100, app: XCUIApplication) -> XCUIElement? {
        q.allElementsBoundByIndex.first { e in
            let f = e.frame
            return f.minY > minY && f.maxY < app.frame.height - 90 && e.isHittable
        }
    }

    private func closePlayerIfOpen(_ app: XCUIApplication) {
        let close = app.buttons["Close player"]
        if close.exists && close.isHittable { close.tap(); pause() }
    }

    func testTour() throws {
        // Warm launch: the recorder starts once the app runs; the recorded launch is the cold one below.
        var app = launch(["APP_DOOR_SECONDS": "900", "APP_RESET_PRODUCTIONS": "1"])
        sleep(14)
        app.terminate()
        sleep(3)
        mark("launch")
        app = XCUIApplication()
        app.launchEnvironment = ["APP_MUTE": "1", "APP_SKIP_ONBOARD": "1", "APP_DOOR_SECONDS": "900", "APP_UITEST_SESSION": "1"]
        app.launch()
        sleep(5)
        dump(app, "home")

        // Home: On the air, then Listen Live.
        mark("home")
        app.scrollUp(); pause(2)
        app.scrollDown(); pause(1.5)
        if tap(app.buttons["listen-live"], wait: 10) {
            mark("listen-live")
            sleep(5)
            dump(app, "live")
            closePlayerIfOpen(app)
            let live = app.buttons["listen-live"]
            if live.exists && live.isHittable { live.tap(); pause(2) }
        }

        // Browse, a series, an episode.
        mark("browse")
        openTab(app, "Browse")
        sleep(3)
        app.scrollUp(); pause(2)
        dump(app, "browse")
        if let tile = firstHittable(app.buttons.matching(identifier: "show-tile"), app: app) {
            tile.tap()
            mark("series")
            sleep(3)
            dump(app, "series")
            app.scrollUp(); pause(2)
            let rows = app.buttons.allElementsBoundByIndex.filter {
                $0.isHittable && $0.frame.minY > 200 && $0.frame.height > 40 && $0.frame.maxY < app.frame.height - 120
                    && !["Follow", "Following", "Share", "Back", "Play", "Add to queue", "In queue"].contains($0.label)
                    && !$0.label.isEmpty && !$0.label.hasPrefix("Now playing")
            }
            if let episode = rows.first {
                episode.tap()
                mark("episode")
                sleep(3)
                dump(app, "episode")
            }
        }

        // Play, then Now Playing: pause and resume.
        let play = app.buttons.matching(NSPredicate(format: "label == 'Play' OR label BEGINSWITH 'Play '")).allElementsBoundByIndex
            .first { $0.isHittable && !($0.label.hasPrefix("Play ") && $0.frame.minY > app.frame.height - 140) }
        if let play {
            play.tap()
            mark("play")
            sleep(3)
            if !app.buttons["Close player"].exists {
                let mini = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Now playing'")).firstMatch
                tap(mini, wait: 6)
            }
            sleep(3)
            dump(app, "player")
            mark("pause")
            if tap(hittable(app, "Pause"), wait: 5) { sleep(2) }
            mark("resume")
            if tap(hittable(app, "Play"), wait: 5) { sleep(3) }
            if tap(hittable(app, "Pause"), wait: 3) { pause() }
            closePlayerIfOpen(app)
        }

        // Search.
        mark("search")
        openTab(app, "Search")
        sleep(2)
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 10) {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 4) {
                field.typeText("Gang Busters\n")
            }
        }
        sleep(4)
        dump(app, "search")

        // Record: a play, Read, two pages, Contents, I'm playing, the studio (Sign in with Apple, then the dock).
        mark("record")
        openTab(app, "Record")
        sleep(3)
        dump(app, "record")
        // Today's play carries its own Read button on the Record tab.
        let todaysRead = app.buttons.matching(NSPredicate(format: "identifier == 'todays-play' AND label == 'Read'")).firstMatch
        let anyRead = app.buttons.matching(NSPredicate(format: "label == 'Read' OR label BEGINSWITH 'Read '")).firstMatch
        let readButton = todaysRead.waitForExistence(timeout: 8) ? todaysRead : anyRead
        if readButton.exists {
            mark("play-page")
            dump(app, "play-page")
            readButton.tap()
            if true {
                mark("reader")
                sleep(4)
                dump(app, "reader")
                let pager = app.descendants(matching: .any)["reader-pager"]
                let target = pager.exists ? pager : app
                target.swipeLeft(); sleep(2)
                target.swipeLeft(); sleep(2)
                mark("contents")
                if tap(app.buttons["Contents"], wait: 5) {
                    sleep(3)
                    dump(app, "contents")
                    let done = app.buttons.matching(NSPredicate(format: "label IN {'Done', 'Close'}")).allElementsBoundByIndex.last { $0.isHittable }
                    if let done { done.tap() } else { app.swipeDown(velocity: .fast) }
                    pause(2)
                }
                mark("part")
                if tap(app.buttons["reader-part"], wait: 5) {
                    pause(2)
                    dump(app, "part-menu")
                    let parts = app.buttons.allElementsBoundByIndex.filter { $0.label.contains("(") && $0.label.hasSuffix(")") && $0.isHittable }
                    if let part = parts.first { part.tap() } else { app.scrollDown() }
                    sleep(3)
                }
                mark("studio")
                if tap(app.buttons["reader-record"], wait: 5) {
                    sleep(5)
                    dump(app, "studio")
                    let signIn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sign in with Apple'")).firstMatch
                    if tap(signIn, wait: 6) {
                        mark("apple-sheet")
                        // The owner rests a finger on Touch ID. Signed in, the gate offers Start Recording
                        // (never pressed: no microphone take is made).
                        var signedIn = false
                        for _ in 0..<45 {
                            sleep(2)
                            if app.buttons["studio-start"].exists || app.buttons["studio-takes"].exists { signedIn = true; break }
                        }
                        if signedIn {
                            mark("signed-in")
                            sleep(3)
                            dump(app, "studio-signed-in")
                            if tap(app.buttons["studio-takes"], wait: 2) { sleep(3); app.scrollDown(); pause() }
                            pause(2)
                        } else {
                            mark("apple-sheet-cancel")
                            let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                            let cancel = sb.buttons.matching(NSPredicate(format: "label IN {'Cancel', 'Close'}")).firstMatch
                            if cancel.exists { cancel.tap() } else { app.swipeDown(velocity: .fast) }
                            pause(2)
                        }
                    }
                }
                mark("close-reader")
                let closeStudio = app.buttons["Close"]
                if tap(closeStudio, wait: 3) { pause(2) }
                if app.buttons["Close"].exists { tap(app.buttons["Close"], wait: 2); pause(2) }
                dump(app, "after-reader")
            }
        }

        // The production the studio made stays on the device: delete it, as a listener would.
        mark("delete-production")
        openTab(app, "Record")
        sleep(2)
        let back = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if !app.navigationBars["Record"].exists, back.exists { back.tap(); pause(1.5) }
        if !app.navigationBars["Record"].exists, back.exists { back.tap(); pause(1.5) }
        app.scrollDown(); pause()
        dump(app, "yours")
        let yours = app.staticTexts["Yours"]
        if yours.exists {
            let row = app.cells.allElementsBoundByIndex.first { $0.frame.minY > yours.frame.maxY && $0.isHittable }
                ?? app.buttons.allElementsBoundByIndex.first { $0.frame.minY > yours.frame.maxY && $0.isHittable && $0.frame.height > 40 }
            if let row {
                row.swipeLeft(); pause(1.5)
                if tap(app.buttons["Delete"], wait: 3) {
                    pause(1.5)
                    dump(app, "delete-dialog")
                    tap(app.buttons["Delete Production and Its Recordings"], wait: 4)
                    sleep(2)
                }
            }
        }

        // Library, then Account (signed out: Sign in with Apple).
        mark("library")
        openTab(app, "Library")
        sleep(3)
        for _ in 0..<4 { app.scrollUp(); pause(0.8) }
        dump(app, "library")
        let account = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Account'")).firstMatch
        let cell = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'Account'")).firstMatch
        mark("account")
        if !tap(account, wait: 4) { tap(cell, wait: 4) }
        sleep(4)
        dump(app, "account")
        let deleteAccount = app.buttons["Delete Account"]
        if deleteAccount.waitForExistence(timeout: 3) {
            // Signed in: delete the account, as a person may.
            pause(2)
            mark("delete-account")
            if tap(deleteAccount, wait: 3) {
                pause(2)
                let confirm = app.buttons.matching(identifier: "Delete Account").allElementsBoundByIndex.last { $0.isHittable }
                confirm?.tap()
                mark("delete-confirm")
                // Apple may ask for Touch ID once more: wait for the signed-out account.
                let again = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sign in with Apple'")).firstMatch
                for _ in 0..<45 {
                    if again.exists { break }
                    sleep(2)
                }
            }
        }
        sleep(3)
        mark("end")
        sleep(3)
    }
}
