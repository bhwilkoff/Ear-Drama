import XCTest

/// App Review screen recording, second clip (2.1, 2026-11-16): a shared production's People with Report and Block
/// for the other member, then Delete Account. Not part of the suite. `testJoin` (not recorded) takes a part by the
/// invite link in APPREVIEW_INVITE (pass TEST_RUNNER_APPREVIEW_INVITE to xcodebuild); `testModeration` is the clip,
/// recorded from the Mac with devicectl captures of the open display while it runs.
final class AppReviewModerationUITests: DeviceTestCase {
    private func mark(_ s: String) { print("TOUR-MARK \(Date().timeIntervalSince1970) \(s)") }
    private func pause(_ s: Double = 1.5) { usleep(UInt32(s * 1_000_000)) }

    private func dump(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(string: app.debugDescription)
        a.name = "tree-\(name)"
        a.lifetime = .keepAlways
        add(a)
    }

    @discardableResult
    private func tap(_ e: XCUIElement, wait: Double = 8) -> Bool {
        guard e.waitForExistence(timeout: wait) else { return false }
        if !e.isHittable { pause(0.5) }
        guard e.isHittable else { return false }
        e.tap()
        return true
    }

    private func plainLaunch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["APP_MUTE": "1", "APP_SKIP_ONBOARD": "1", "APP_DOOR_SECONDS": "900"]
        app.launch()
        return app
    }

    /// Record tab, back to its root, then the shared production's row under Yours.
    private func openProduction(_ app: XCUIApplication, _ title: String) -> Bool {
        openTab(app, "Record")
        sleep(2)
        let back = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        for _ in 0..<2 where !app.navigationBars["Record"].exists && back.exists { back.tap(); pause(1) }
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        for _ in 0..<4 where !(row.exists && row.isHittable) { app.swipeUp(); pause(0.8) }
        return tap(row, wait: 4)
    }

    private func openPeople(_ app: XCUIApplication) -> Bool {
        let people = app.buttons["People"]
        guard people.waitForExistence(timeout: 6) else { return false }
        // The cast column is narrower than the window: drag that column, not the window's middle, until the row
        // sits well clear of the bottom edge (a tap at the edge lands on nothing).
        for _ in 0..<8 where people.frame.maxY > app.frame.height * 0.6 {
            let x = people.frame.midX / app.frame.width
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.75))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.35)))
            pause(0.8)
        }
        guard tap(people, wait: 4) else { return false }
        if app.buttons["Done"].waitForExistence(timeout: 4) { return true }
        people.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        return app.buttons["Done"].waitForExistence(timeout: 4)
    }

    func testJoin() throws {
        let link = ProcessInfo.processInfo.environment["APPREVIEW_INVITE"] ?? ""
        XCTAssertFalse(link.isEmpty, "APPREVIEW_INVITE")
        let app = plainLaunch()
        sleep(4)
        app.open(URL(string: link)!)
        XCTAssertTrue(text(app, matching: "^Invitation").waitForExistence(timeout: 20), "the Invitation page")
        sleep(4)
        dump(app, "invitation")
        let take = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Take '")).allElementsBoundByIndex
        let first = take.first { $0.label == "Take URIAH" } ?? take.first
        XCTAssertNotNil(first, "a Take button")
        if let first {
            for _ in 0..<6 where !first.isHittable { app.swipeUp(); pause(0.6) }
            first.tap()
            let field = app.textFields["Your name"]
            let signIn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sign in with Apple'")).firstMatch
            if !field.waitForExistence(timeout: 5), tap(signIn, wait: 10) {
                mark("apple-sheet")
                // The owner confirms with Touch ID; signed in, the name alert opens.
                _ = field.waitForExistence(timeout: 180)
                mark(field.exists ? "signed-in" : "sign-in-timeout")
            }
            if field.waitForExistence(timeout: 10) {
                field.tap()
                field.typeText("Demo Reader")
                tap(app.alerts.buttons["Take Part"], wait: 4)
            }
            sleep(6)
            dump(app, "after-join")
        }
        XCTAssertTrue(openProduction(app, "Caesar Rodney"), "the production under Record")
        sleep(3)
        dump(app, "cast")
        XCTAssertTrue(openPeople(app), "People")
        sleep(3)
        dump(app, "people")
        XCTAssertTrue(app.buttons["Report"].waitForExistence(timeout: 5), "Report")
        XCTAssertTrue(app.buttons["Block"].exists, "Block")
        tap(app.buttons["Done"], wait: 3)
    }

    func testPeople() throws {
        let app = plainLaunch()
        sleep(5)
        XCTAssertTrue(openProduction(app, "Caesar Rodney"), "the production")
        sleep(3)
        XCTAssertTrue(openPeople(app), "People")
        sleep(3)
        dump(app, "people")
        XCTAssertTrue(app.buttons["Report"].waitForExistence(timeout: 8), "Report")
        XCTAssertTrue(app.buttons["Block"].exists, "Block")
        tap(app.buttons["Done"], wait: 3)
    }

    func testModeration() throws {
        var app = plainLaunch()
        sleep(10)
        app.terminate()
        sleep(3)
        mark("launch")
        app = plainLaunch()
        sleep(5)

        mark("record")
        XCTAssertTrue(openProduction(app, "Caesar Rodney"), "the production")
        sleep(3)
        mark("people")
        guard openPeople(app), app.buttons["Report"].waitForExistence(timeout: 8) else {
            XCTFail("People with Report: stopping before Delete Account")
            mark("end")
            return
        }
        sleep(6)
        dump(app, "people")

        mark("report")
        if tap(app.buttons["Report"], wait: 5) {
            sleep(5)
            let reason = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reason'")).firstMatch
            if tap(reason, wait: 4) {
                mark("reasons")
                sleep(6)
                dump(app, "reasons")
                // Close the menu by choosing the reason already selected.
                let chosen = app.buttons.matching(NSPredicate(format: "selected == true")).firstMatch
                if chosen.exists && chosen.isHittable { chosen.tap() } else { app.navigationBars.firstMatch.tap() }
                pause(2)
            }
            mark("report-cancel")
            tap(app.buttons["Cancel"], wait: 4)
            sleep(2)
        }

        mark("block")
        if tap(app.buttons["Block"], wait: 5) {
            sleep(6)
            dump(app, "block-dialog")
            mark("block-cancel")
            // A regular-width confirmation is a popover with no Cancel: tap a quiet spot in the
            // sheet (the "You" row's name), away from the popover at the Block button.
            let cancel = app.buttons["Cancel"]
            if cancel.exists && cancel.isHittable { cancel.tap() } else {
                let me = app.staticTexts["You"].firstMatch
                if me.exists { me.tap() } else { app.navigationBars["People"].tap() }
            }
            sleep(2)
        }
        let done = app.navigationBars["People"].buttons["Done"]
        for _ in 0..<4 where app.navigationBars["People"].exists {
            if done.waitForExistence(timeout: 3) && done.isHittable { done.tap() } else {
                app.navigationBars["People"].swipeDown(velocity: .fast)
            }
            pause(1.5)
        }
        pause(1)

        mark("library")
        openTab(app, "Library")
        sleep(3)
        // Synthesized drags do not scroll on the open iPhone Duo's inner display, and Account is
        // Library's last row: reopen the app on Library > Account through the DEBUG door.
        app.terminate()
        app.launchEnvironment["APP_START_TAB"] = "account"
        app.launch()
        mark("account")
        sleep(6)
        dump(app, "account")
        let deleteAccount = app.buttons["Delete Account"]
        XCTAssertTrue(deleteAccount.waitForExistence(timeout: 5), "signed in: Delete Account")
        mark("delete-account")
        if tap(deleteAccount, wait: 3) {
            sleep(5)
            dump(app, "delete-dialog")
            let confirm = app.buttons.matching(identifier: "Delete Account").allElementsBoundByIndex.last { $0.isHittable }
            confirm?.tap()
            mark("delete-confirm")
        }
        let again = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sign in with Apple'")).firstMatch
        for _ in 0..<240 where !again.exists { sleep(2) }
        mark(again.exists ? "signed-out" : "signed-out-timeout")
        XCTAssertTrue(again.exists, "Account signed out")
        sleep(8)
        dump(app, "end")
        mark("end")
    }
}
