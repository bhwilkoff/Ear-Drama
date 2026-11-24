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
            for el in query.allElementsBoundByIndex where el.exists && el.label.count <= 128 && !bar.buttons[el.label].exists {
                let f = el.frame
                if f.isEmpty || f.minY >= screen { continue }
                // isHittable only for a candidate: asked of a tile half off the screen it fails the test itself.
                if f.minY < top - 4 && f.maxY > top + 4 && f.minY < screen && el.isHittable {
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
    /// Read in ONE snapshot of the tree: element by element it took hundreds of round trips, long enough for a
    /// scroll to still be moving between the first read and the last (N7). The screenshot is no longer compared:
    /// its pixels change with the scroll indicator's fade and Home's live clock, so a page at its end read as
    /// moved and the end check was skipped or run on a page still in motion.
    func contentSignature(_ app: XCUIApplication) -> String {
        guard let root = try? app.snapshot() else { return "" }
        let kinds: Set<XCUIElement.ElementType> = [.cell, .staticText, .button, .image]
        var out: [String] = []
        func walk(_ s: XCUIElementSnapshot) {
            if kinds.contains(s.elementType) {
                out.append("\(s.elementType.rawValue):\(s.label.prefix(24)):\(Int(s.frame.minY)):\(Int(s.frame.minX))")
            }
            s.children.forEach(walk)
        }
        walk(root)
        return out.joined(separator: "|")
    }

    /// Waits until the screen stops changing, the same signature on two reads 0.3 s apart, and returns it. A
    /// fixed 0.7 s sleep after each swipe was the race: under load a fast swipe's deceleration and bounce outlast
    /// it, so the end check read frames still moving (N7).
    @discardableResult
    func settle(_ app: XCUIApplication, _ what: String, timeout: TimeInterval = 10) -> String {
        let t0 = Date()
        var last = contentSignature(app)
        while Date().timeIntervalSince(t0) < timeout {
            usleep(300_000)
            let now = contentSignature(app)
            if now == last {
                stage(String(format: "%@ settled after %.1fs", what, Date().timeIntervalSince(t0)))
                return now
            }
            last = now
        }
        stage(String(format: "%@ NEVER settled in %.0fs", what, timeout))
        return last
    }

    /// One page up by swiping the page's own scroll container, the largest on screen (UITestScrolling). A drag
    /// computed from the app element lands sideways whenever XCUITest reports the app's frame in portrait while
    /// the window is landscape (the iPhone 12 in landscape, the open iPhone Duo: DuoScrollProbeUITests
    /// 2026-11-16); an element's own swipe does not. The first scroll view taller than 100 pt was taken before,
    /// which on Home is the dial or the voices shelf whenever they had loaded: a sideways strip (N7).
    private func scrollPage(_ app: XCUIApplication, far: Bool = false) {
        if let area = app.scrollTarget { area.swipeUp(velocity: far ? .fast : .slow) } else { app.swipeUp() }
    }

    func sweep(_ app: XCUIApplication, _ name: String, pages: Int = 3) {
        var last = settle(app, "\(name) top")
        shot(app, "\(name)-p00")
        for i in 1...pages {
            var moved = false
            for far in [false, true] {
                scrollPage(app, far: far)
                let now = settle(app, "\(name) page \(i)\(far ? " far" : "")")
                if now != last { last = now; moved = true; break }
            }
            if !moved { stage("\(name) end at page \(i)"); assertEndClears(app, name); break }
            shot(app, "\(name)-p\(String(format: "%02d", i))")
        }
    }

    func tab(_ t: String, _ extra: [String: String] = [:]) -> XCUIApplication {
        let app = launch(["APP_START_TAB": t, "APP_DOOR_SECONDS": "300"].merging(extra) { $1 })
        sleep(6)
        return app
    }
}
