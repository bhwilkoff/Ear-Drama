# Top Shelf extension setup

I want the Apple TV Home Screen to show something worth opening when
[APP NAME] is focused in the top row: Continue Watching, a curated
shelf, what is new. A Top Shelf extension (`.sectioned` content) does
that. The extension is a separate process with tight memory limits and
no network budget to speak of, so it reads a small JSON file instead of
the catalog.

There are two ways to produce that file. Pick one per section.

- **Device-local snapshot.** The app writes the JSON into the App Group
  container whenever its state changes. This is the only choice for
  personal sections (Continue Watching), because only the device knows
  them.
- **Pipeline-published file.** The data pipeline publishes a tiny JSON
  once a day, keyed by local date, and the extension (or a widget)
  fetches it directly. Nothing depends on the app having launched, and
  nothing loads the big catalog. This is the right choice for shared
  sections (today's pick, editor's shelf, what is new).

Most apps mix them: personal sections from the snapshot, shared sections
from the published file.

## The owner step: the App Group on device builds

The App Group capability must be enabled for this App ID in your Apple
Developer account for **device and TestFlight** builds. With automatic
signing and a team set, Xcode usually registers
`group.com.example.appname` on the first device build. If device signing
complains, toggle App Groups in Signing & Capabilities for both targets.
Simulator builds need nothing extra, so a green simulator build proves
nothing here.

The App Group container is also one of the only places tvOS can write
(Decision 017). Everything in this runbook stays inside it or inside
`Library/Caches`.

## Step 1: the App Group on both targets

1. Apple Developer portal (or Xcode, Signing & Capabilities, **+ App
   Group**), create `group.com.example.appname`.
2. Add the **App Groups** capability to the **main app** target and
   select that group.
3. Repeat for the Top Shelf extension target (Step 2).

## Step 2: the extension target

Xcode, **File, New, Target..., tvOS, TV Top Shelf Extension**. Name it
`AppNameTopShelf`. Xcode wires the embed phase and a stub
`ContentProvider`. Then:

- Add the **App Groups** capability with `group.com.example.appname`.
- Replace the generated `ContentProvider.swift` with the file in Step 5.
- Delete the sample code Xcode generated.

## Step 3: the device-local snapshot

Add this to the main app target (for example
`apple/tvOS/TopShelf/TopShelfSnapshot.swift`, which you create). Call
`TopShelfSnapshot.write(_:)` after the catalog loads and whenever
Continue Watching changes. It no-ops if the App Group is not configured
yet, so it is safe to add before the group exists.

```swift
import Foundation

enum TopShelfSnapshot {
    static let appGroup = "group.com.example.appname"
    static let fileName = "topshelf.json"

    struct Payload: Codable {
        struct Item: Codable {
            let id: String
            let title: String
            let posterURL: String?
            let year: Int?
        }
        struct Section: Codable {
            let title: String
            let items: [Item]
        }
        let sections: [Section]
        let generatedAt: Double   // epoch seconds; stamp at call site
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        )
    }

    static func write(_ payload: Payload) {
        guard let dir = containerURL else { return }   // group not set up yet
        let url = dir.appendingPathComponent(fileName)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func read() -> Payload? {
        guard let dir = containerURL else { return nil }
        let url = dir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
```

Build the payload from `AppStore` (the curated shelf plus the SwiftData
progress rows mapped back to catalog items). Keep it to about 10 items
per section; Top Shelf has tight memory limits.

## Step 4: the pipeline-published file

The data pipeline (Decision 016) publishes one small file per local
date alongside the catalog, for example
`https://<your-data-host>/topshelf/2026-09-30.json`, in the same
`Payload` shape as Step 3. A handful of items per section, a few
kilobytes in total. Publish a few days ahead so a device in any time
zone finds its date.

Key the file by the device's LOCAL date, not UTC. "Today's pick" should
change at the viewer's midnight. If every platform must show the same
pick for the same date (iOS widget, Android widget, web), the pick
itself comes from one algorithm with golden tests
(`cross-platform-determinism`, Decision 025); the pipeline just
publishes its output.

The extension fetches the file for today, caches it in the App Group
container, and falls back to the cached copy (then to the device-local
snapshot, then to `nil`) when the fetch fails.

```swift
import Foundation

enum PublishedShelf {
    static let base = URL(string: "https://<your-data-host>/topshelf/")!

    static func todayURL(now: Date = .now, calendar: Calendar = .current) -> URL {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let key = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        return base.appendingPathComponent("\(key).json")
    }

    static func load() async -> TopShelfSnapshot.Payload? {
        let url = todayURL()
        let cache = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: TopShelfSnapshot.appGroup)?
            .appendingPathComponent("published-latest.json")
        if let (data, response) = try? await URLSession.shared.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let payload = try? JSONDecoder().decode(TopShelfSnapshot.Payload.self, from: data) {
            if let cache { try? data.write(to: cache, options: .atomic) }
            return payload
        }
        guard let cache, let data = try? Data(contentsOf: cache) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.Payload.self, from: data)
    }
}
```

The cost: this variant adds a network dependency to a process with a
small time budget, and a missed publish shows yesterday's shelf (or
nothing). Keep the file tiny, keep the cached fallback, and have the
publishing workflow fail loudly when the file for tomorrow is missing
(`docs/CI-FLEET.md`).

The same file serves WidgetKit timelines on iOS and macOS and the
Android widget, which is where most of its value comes from.

## Step 5: the content provider

Replace the generated `ContentProvider.swift` in the extension target.
This version merges both sources: published sections first, then the
personal snapshot.

```swift
import TVServices

class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task {
            let published = await PublishedShelf.load()?.sections ?? []
            let local = TopShelfSnapshot.read()?.sections ?? []
            let all = local + published
            guard !all.isEmpty else { completionHandler(nil); return }

            let sections = all.map { section -> TVTopShelfItemCollection<TVTopShelfSectionedItem> in
                let items = section.items.map { item -> TVTopShelfSectionedItem in
                    let shelfItem = TVTopShelfSectionedItem(identifier: item.id)
                    shelfItem.title = item.title
                    if let poster = item.posterURL, let url = URL(string: poster) {
                        shelfItem.setImageURL(url, for: [.screenScale1x, .screenScale2x])
                    }
                    shelfItem.imageShape = .poster
                    shelfItem.displayAction = TVTopShelfAction(
                        url: URL(string: "appname://item/\(item.id)")!
                    )
                    return shelfItem
                }
                let collection = TVTopShelfItemCollection(items: items)
                collection.title = section.title
                return collection
            }
            completionHandler(TVTopShelfSectionedContent(sections: sections))
        }
    }
}
```

`TopShelfSnapshot` and `PublishedShelf` must be members of **both**
targets (check Target Membership), or duplicate the small readers into
the extension.

## Step 6: deep links into the app

Top Shelf items open `appname://item/{id}`. Declare the scheme and route
it. The web twin `https://<your-domain>/item/{id}` belongs in
`DEEP_LINKS.md` too.

1. **Info.plist.** With `GENERATE_INFOPLIST_FILE = YES`, set
   `INFOPLIST_FILE` to a small Info.plist containing:

   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array><string>appname</string></array>
     </dict>
   </array>
   <key>NSUserActivityTypes</key>
   <array><string>com.example.appname.viewing</string></array>
   ```

   The `NSUserActivityTypes` entry also completes the Detail screen's
   `NSUserActivity` support.

2. **Route it through the inbox.** External entry points never mutate
   the router directly. `.onOpenURL` drops the link in the deep-link
   inbox, and the root view consumes it once foregrounded:

   ```swift
   .onOpenURL { url in
       guard url.scheme == "appname", url.host == "item" else { return }
       deepLinkInbox.post(.item(id: url.lastPathComponent))
   }
   ```

   The root view then resolves the ID against the catalog, resets the
   Home tab's `NavigationPath`, and pushes the item. The same URL route
   is a sturdier transport for App Intents than a singleton inbox of
   their own (`appname://surprise` and so on).

## Step 7: keeping it fresh

- Call `TopShelfSnapshot.write(...)` when the catalog loads and after
  playback updates progress.
- The published file refreshes itself: the extension asks for today's
  date every time the system loads it.
- For the device-local sections, a `BGAppRefreshTask` can re-write the
  snapshot in the background.

Focus the app on the Home Screen and look.
