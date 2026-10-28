# Top Shelf extension setup

Ear Drama's Apple TV Home Screen shows the listener's Continue items when
the app is focused in the top row. The design is `docs/tvOS-DESIGN.md` §9.3;
this page is how it is wired and what the owner must do before a device
build carries it.

The extension is a separate process with tight memory limits and no
catalog, so it reads one small JSON file the app wrote. It makes no network
calls.

## Shape

| Piece | Where |
|---|---|
| Extension target | `EarDramaTopShelf` in `project.yml` (`app.eardrama.TopShelf`, tvOS app extension) |
| Content provider | `apple/TopShelf/ContentProvider.swift` (`TVTopShelfContentProvider`, async `loadTopShelfContent()`) |
| Snapshot type, shared by app and extension | `apple/Core/TopShelf/TopShelfSnapshot.swift` |
| Building the snapshot from history | `apple/Core/TopShelf/TopShelfSnapshot+Catalog.swift`, called from `apple/tvOS/ContentView_tvOS.swift` |
| Tests | `apple/Tests/TopShelfTests.swift` |
| App Group | `group.app.eardrama` |
| File | `topshelf.json` in the App Group container |
| Item link | `eardrama://episode/{percent-encoded id}` (HTTPS twin `https://eardrama.org/episode/{id}`, `DEEP_LINKS.md`) |

The shelf is `.sectioned`: one section, "Continue listening", up to ten
items in Home's Continue order (`TopShelfSnapshot.limit`), one line each
(series, then episode), square art. Play and select both open the item's
link. A portrait whose license asks for a credit is left off, since the
shelf cannot show the credit. Nothing in progress returns `nil`, so tvOS
keeps the static Top Shelf image.

## Data flow

1. The tvOS app writes the snapshot whenever listening history changes
   (`TopShelfSnapshot.publish(_:)`, which calls `write(to:)` on
   `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`).
   With no App Group the container is `nil` and the write is skipped, so
   the code is safe before the group exists.
2. The extension reads `topshelf.json`, maps each item to a
   `TVTopShelfSectionedItem` (`playAction` and `displayAction` both the
   item's link), and returns one section.
3. The app routes `eardrama://episode/{id}` through the deep-link inbox,
   like every external entry point.

The App Group container is one of the only places tvOS can write besides
Caches (Decision 017, tvOS-DESIGN §10.1). Everything stays inside it.

## The owner step: App Groups on the App ID

The shelf ships inert. Both entitlement lines are commented out in
`project.yml` because the App Store profiles cannot carry an App Group
until the capability exists on the App IDs, and the tvOS export would
fail:

- the app: `"CODE_SIGN_ENTITLEMENTS[sdk=appletv*]": apple/Resources/EarDrama-tvOS.entitlements`
- the extension: `CODE_SIGN_ENTITLEMENTS: apple/TopShelf/TopShelf.entitlements`

Both entitlement files already hold
`com.apple.security.application-groups = group.app.eardrama`.

To turn it on (the owner, in the Apple Developer portal):

1. Identifiers: create the App Group `group.app.eardrama`.
2. Enable **App Groups** on `app.eardrama` and on `app.eardrama.TopShelf`,
   and add `group.app.eardrama` to each. Regenerate profiles (automatic
   signing does this).
3. Then, together in one change, uncomment the two lines above in
   `project.yml`, run `xcodegen generate`, and build the tvOS Release for a
   device. Restore both or neither: one without the other signs a group the
   other process cannot open.
4. Install on an Apple TV, play an episode part-way, leave the app, focus
   its icon in the top row, and look.

A simulator build proves nothing here: the simulator signs without the
capability and lets Application Support writes through, which a device does
not.

## Keeping it fresh

The app rewrites the snapshot when history changes. The extension asks for
the file each time the system loads the shelf. Nothing in the extension
refreshes on its own.
