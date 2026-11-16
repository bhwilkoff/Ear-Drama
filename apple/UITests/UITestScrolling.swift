import XCTest

extension XCUIApplication {
    /// The scroll container on screen: the largest collection view, table, scroll view or web view
    /// (a tab strip or a row of chips is a smaller collection view and would scroll sideways).
    var scrollTarget: XCUIElement? {
        let all = [collectionViews, tables, scrollViews, webViews].flatMap { $0.allElementsBoundByIndex }
            .filter { $0.exists && $0.frame.width > 0 && $0.frame.height > 0 }
        return all.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// Scroll by swiping the scroll container itself, never the application element. On an open
    /// iPhone Duo XCUITest reports the app's frame in portrait (669 x 951) while the window is
    /// landscape (951 x 669), so a swipe computed from the app lands sideways and moves nothing;
    /// a swipe on an element uses that element's true frame (DuoScrollProbeUITests, 2026-11-16).
    func scrollUp() { if let el = scrollTarget { el.swipeUp() } else { swipeUp() } }
    func scrollDown() { if let el = scrollTarget { el.swipeDown() } else { swipeDown() } }
}
