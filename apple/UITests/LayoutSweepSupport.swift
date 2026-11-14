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

    /// What is on screen, as the frames and labels of its elements: it changes when the content scrolled and
    /// is the same when it did not, whatever the scroll indicator or a running animation paints.
    private func contentSignature(_ app: XCUIApplication) -> String {
        let kinds: [XCUIElementQuery] = [app.cells, app.staticTexts, app.buttons, app.images]
        return kinds.flatMap { $0.allElementsBoundByIndex.prefix(60) }.filter { $0.exists }
            .map { "\($0.elementType.rawValue):\($0.label.prefix(24)):\(Int($0.frame.minY)):\(Int($0.frame.minX))" }
            .joined(separator: "|")
    }

    /// One page up by a drag inside the scroll view's own frame, above the floating bar; `swipeUp` on the
    /// app did not scroll in landscape on the iPhone 12.
    private func scrollPage(_ app: XCUIApplication, far: Bool = false) {
        let area = [app.scrollViews, app.collectionViews, app.tables].map { $0.firstMatch }.first { $0.exists && $0.frame.height > 100 }
        let frame = area?.frame ?? app.frame
        let top = frame.minY + frame.height * (far ? 0.12 : 0.3)
        let bottom = frame.minY + frame.height * (far ? 0.7 : 0.6)
        let x = frame.midX
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let from = origin.withOffset(CGVector(dx: x, dy: bottom))
        let to = origin.withOffset(CGVector(dx: x, dy: top))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    func sweep(_ app: XCUIApplication, _ name: String, pages: Int = 3) {
        shot(app, "\(name)-p00")
        var last = (XCUIScreen.main.screenshot().pngRepresentation, contentSignature(app))
        for i in 1...pages {
            var moved = false
            for far in [false, true] {
                scrollPage(app, far: far)
                usleep(700_000)
                let now = (XCUIScreen.main.screenshot().pngRepresentation, contentSignature(app))
                if now.0 != last.0 || now.1 != last.1 { last = now; moved = true; break }
            }
            if !moved { assertEndClears(app, name); break }
            shot(app, "\(name)-p\(String(format: "%02d", i))")
        }
    }

    func tab(_ t: String, _ extra: [String: String] = [:]) -> XCUIApplication {
        let app = launch(["APP_START_TAB": t, "APP_DOOR_SECONDS": "300"].merging(extra) { $1 })
        sleep(6)
        return app
    }
}
