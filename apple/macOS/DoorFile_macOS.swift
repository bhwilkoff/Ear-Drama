#if os(macOS) && DEBUG
import AppKit

/// APP_DOOR_FILE: a harness drives one running app from a file, so a pass over every
/// screen, size, and appearance takes no pointer, no relaunch, and never the owner's
/// focus. Each line of the file is a command; the app deletes the file when done.
///
///     tab browse | item <key> | play <id> | person <name> | search <text>
///     size 1600x1000 | look dark|light | scroll 900 | back
enum DoorFile_macOS {
    static func watch(_ store: AppStore) async {
        guard let path = ProcessInfo.processInfo.environment["APP_DOOR_FILE"] else { return }
        while !Task.isCancelled {
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                try? FileManager.default.removeItem(atPath: path)
                for line in text.split(separator: "\n") { run(String(line), store) }
            }
            guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
        }
    }

    private static var window: NSWindow? {
        NSApp.windows.filter(\.isVisible).max { $0.frame.width < $1.frame.width }
    }

    private static func run(_ line: String, _ store: AppStore) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = parts.first else { return }
        let arg = parts.count > 1 ? parts[1] : ""
        switch verb {
        case "tab": store.post(.tab(arg))
        case "item": store.post(.item(arg))
        case "play": store.post(.play(arg))
        case "person": store.post(.person(arg))
        case "search": store.post(.search(arg))
        case "back": store.goBack()
        case "look": NSApp.appearance = NSAppearance(named: arg == "dark" ? .darkAqua : .aqua)
        case "size":
            let wh = arg.split(separator: "x").compactMap { Double($0) }
            guard wh.count == 2, let window else { return }
            var frame = window.frame
            frame.origin.y += frame.height - wh[1]
            frame.size = NSSize(width: wh[0], height: wh[1])
            window.setFrame(frame, display: true)
        case "scroll":
            guard let view = window?.contentView, let scroller = pageScroller(in: view) else { return }
            // Clamped to the page: an unclamped offset scrolls the clip view past the document's end and
            // the frame shows an empty pane that reads as content gone (2026-11-09).
            let bottom = max(0, (scroller.documentView?.frame.height ?? 0) - scroller.contentView.bounds.height)
            scroller.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, Double(arg) ?? 0), bottom)))
            scroller.reflectScrolledClipView(scroller.contentView)
        default: break
        }
    }

    /// The largest scroll view that can scroll: the detail column's page, not the sidebar.
    private static func pageScroller(in view: NSView) -> NSScrollView? {
        var found: [NSScrollView] = []
        func walk(_ v: NSView) {
            if let s = v as? NSScrollView, (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 1 { found.append(s) }
            v.subviews.forEach(walk)
        }
        walk(view)
        return found.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}
#endif
