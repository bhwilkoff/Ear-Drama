import XCTest

/// The layout sweep's helpers, shared by LayoutSweepUITests and IPadAuditUITests.
extension DeviceTestCase {
    /// At the end of a screen's scroll nothing may straddle the top of the bar (the mini player, else
    /// the tab bar), and no list row may sit wholly behind it: the last element is fully visible.
    func assertEndClears(_ app: XCUIApplication, _ name: String) {
        let bar = app.tabBars.firstMatch
        guard bar.exists else { return }
        var top = bar.frame.minY
        let mini = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Now playing'")).firstMatch
        if mini.exists { top = min(top, mini.frame.minY) }
        let screen = app.frame.height
        let kinds: [XCUIElementQuery] = [app.cells, app.staticTexts, app.buttons, app.images]
        for query in kinds {
            for el in query.allElementsBoundByIndex where el.exists && el.isHittable && el.label.count <= 128 && !bar.buttons[el.label].exists {
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

    func sweep(_ app: XCUIApplication, _ name: String, pages: Int = 3) {
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

    func tab(_ t: String, _ extra: [String: String] = [:]) -> XCUIApplication {
        let app = launch(["APP_START_TAB": t, "APP_DOOR_SECONDS": "300"].merging(extra) { $1 })
        sleep(6)
        return app
    }
}
