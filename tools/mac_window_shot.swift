import CoreGraphics
import Foundation
// Capture ONE window of ONE application, never a screen region and never the screen.
//
// `screencapture -R x,y,w,h` captures whatever is at those coordinates. Pointed at
// an app window that was not in front, it photographed the owner's personal
// documents in other windows, more than once. A full-screen grab is the same leak with a bigger lens. A window id is
// the only form of capture that cannot pick up somebody else's content, so this
// tool has NO fallback to a region or the full screen: it captures the window or it
// fails and says why.
//
// AND A WINDOW ID IS NOT ENOUGH ON ITS OWN. Matching a window by TITLE SUBSTRING
// alone once captured the owner's terminal, because the tab they were working in
// was titled with the same words as the app window being looked for. So the OWNER
// application is required and matched EXACTLY (or by pid). A title is a thing
// anybody's window can happen to contain; the application that drew it is not.
//
//   winshot <app name | pid:N> <title substring | ""> <out.png> [options]
//     --min-width N     ignore windows narrower than N points (panels, tooltips)
//     --skip-size WxH   ignore windows of exactly this size (repeatable) — e.g. an
//                       app's restored secondary windows that sit over the main one
//     --id-only         print the window id instead of capturing
//
// Pass "" as the title to take that application's frontmost qualifying window.
// Build: swiftc -O tools/mac_window_shot.swift -o build/bin/winshot
let args = CommandLine.arguments
func usage() -> Never {
    print("usage: winshot <app name | pid:N> <title substring | \"\"> <out.png> "
          + "[--min-width N] [--skip-size WxH]... [--id-only]")
    print("  the app name is matched EXACTLY — see the header for why")
    exit(2)
}
guard args.count >= 4 || (args.count >= 3 && args.contains("--id-only")) else { usage() }
let app = args[1], needle = args[2]
var out = args.count >= 4 && !args[3].hasPrefix("--") ? args[3] : ""
var minWidth = 0.0
var skip: [(Double, Double)] = []
var idOnly = false
var i = out.isEmpty ? 3 : 4
while i < args.count {
    switch args[i] {
    case "--min-width":
        guard i + 1 < args.count, let v = Double(args[i + 1]) else { usage() }
        minWidth = v; i += 2
    case "--skip-size":
        let p = (i + 1 < args.count ? args[i + 1] : "").split(separator: "x").compactMap { Double($0) }
        guard p.count == 2 else { usage() }
        skip.append((p[0], p[1])); i += 2
    case "--id-only":
        idOnly = true; i += 1
    default:
        usage()
    }
}
if !idOnly && out.isEmpty { usage() }

let wantPid: Int? = app.hasPrefix("pid:") ? Int(app.dropFirst(4)) : nil
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] else {
    print("no window list (is Screen Recording permission granted?)"); exit(1)
}
var sawApp = false
for w in list {   // front-to-back order: the first match is the frontmost
    let title = (w[kCGWindowName as String] as? String) ?? ""
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
    let pid = (w[kCGWindowOwnerPID as String] as? Int) ?? -1
    if let wp = wantPid { guard pid == wp else { continue } } else { guard owner == app else { continue } }
    sawApp = true
    guard needle.isEmpty || title.contains(needle) else { continue }
    let b = (w[kCGWindowBounds as String] as? [String: Any]) ?? [:]
    let ww = (b["Width"] as? Double) ?? 0, hh = (b["Height"] as? Double) ?? 0
    if ww < minWidth { continue }
    if skip.contains(where: { $0.0 == ww && $0.1 == hh }) { continue }
    guard let id = w[kCGWindowNumber as String] as? Int else { continue }
    if idOnly { print(id); exit(0) }
    try? FileManager.default.removeItem(atPath: out)       // never return a stale file
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l\(id)", out]
    do { try p.run() } catch { print("screencapture failed to start: \(error)"); exit(1) }
    p.waitUntilExit()
    let size = ((try? FileManager.default.attributesOfItem(atPath: out))?[.size] as? Int) ?? 0
    guard p.terminationStatus == 0, size > 0 else {
        print("screencapture wrote nothing for window \(id) (status \(p.terminationStatus))"
              + " — Screen Recording permission?")
        exit(1)
    }
    print("captured \"\(title)\" (\(owner), pid \(pid), \(Int(ww))x\(Int(hh))) -> \(out)")
    exit(0)
}
// SAY WHICH HALF FAILED. "no window matching X" sends a reader looking for a
// missing window when the app is not running at all, and the other way round.
print(sawApp
      ? "\(app) is running but has no qualifying window" + (needle.isEmpty ? "" : " whose title contains \"\(needle)\"")
      : "no application " + (wantPid != nil ? "with \(app)" : "named exactly \"\(app)\"") + " has an on-screen window")
exit(1)
