#if os(iOS) && DEBUG
import UIKit

/// DEBUG door for frames of a page below its first screen, where no test can scroll: the open iPhone Duo refuses
/// XCUITest until a person confirms UI Automation on it, and `devicectl` can launch and capture but not touch.
/// APP_SCROLL_Y=<points> scrolls the largest vertical scroll view on screen to that offset (clamped to its end)
/// APP_SCROLL_DELAY seconds after launch (default 6). Never compiled into a Release build.
enum ScrollDoor {
    static func openIfAsked() {
        let env = ProcessInfo.processInfo.environment
        if LaunchDoors.current.landscape { turn() }
        guard let y = env["APP_SCROLL_Y"].flatMap(Double.init) else { return }
        let delay = env["APP_SCROLL_DELAY"].flatMap(Double.init) ?? 6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { step(CGFloat(y)) }
    }

    /// APP_LANDSCAPE=1: the scene turned, for a phone on the bench that no test can turn (compact-height frames).
    private static func turn() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { print("APP_LANDSCAPE: \($0)") }
        }
    }

    /// A screen at a time: a lazy List only knows its height as far as it has laid out, so one jump stops at its
    /// estimate of the end.
    @MainActor private static func step(_ remaining: CGFloat) {
        guard remaining > 0, let s = target() else { return }
        let move = min(remaining, s.bounds.height * 0.8)
        let before = s.contentOffset.y
        scroll(s, to: before + s.adjustedContentInset.top + move)
        let moved = s.contentOffset.y - before
        guard moved > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { step(remaining - moved) }
    }

    @MainActor private static func target() -> UIScrollView? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        var best: UIScrollView?
        func walk(_ v: UIView) {
            if let s = v as? UIScrollView, !s.isHidden, s.window != nil,
               s.contentSize.height + s.adjustedContentInset.top + s.adjustedContentInset.bottom > s.bounds.height + 1,
               s.bounds.width * s.bounds.height > (best.map { $0.bounds.width * $0.bounds.height } ?? 0) {
                best = s
            }
            v.subviews.forEach(walk)
        }
        windows.filter { !$0.isHidden }.forEach(walk)
        return best
    }

    @MainActor private static func scroll(_ s: UIScrollView, to y: CGFloat) {
        let top = -s.adjustedContentInset.top
        let end = max(top, s.contentSize.height - s.bounds.height + s.adjustedContentInset.bottom)
        s.setContentOffset(CGPoint(x: s.contentOffset.x, y: min(end, top + y)), animated: false)
    }
}
#endif
