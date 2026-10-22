# Deep links: the cross-platform contract

A URL is a string that has to mean the same thing on every platform.
This doc is the contract. Pick the routes ONCE at project start;
every web view, Apple `View`, and Android `composable(...)` reads
from the same table.

## URL shapes

Pick path-prefix scoping (one path per resource type). Android
`autoVerify="true"` and iOS `appID...paths` both need explicit
prefix lists, and a flat structure makes the lists short.

| Resource | URL shape | Owner |
|---|---|---|
| Public profile | `https://app.example.com/u/{username}` | Web renders; iOS + Android open the in-app view |
| Single item detail | `https://app.example.com/item/{id}` | All platforms render in-app; web is the landing twin |
| Settings deep entry | `https://app.example.com/settings/{section}` | All; web routes via `?view=settings&section=...` |
| OAuth callback | `appname://oauth/callback?...` | Custom scheme only, never HTTPS (provider redirects break otherwise) |

**Add a row to this table BEFORE adding a deep link in code.** New
routes that aren't documented here become orphans the next time a
platform adds support. Discovery cost compounds.

**The canonical-twin rule**: every custom-scheme link a native app
emits (`appname://item/x`) has an HTTPS twin
(`https://app.example.com/item/x`) that the WEB app renders, so a
share always lands somewhere meaningful, even for recipients
without the app. On a static host, a `404.html` forwarder that maps
`/item/{id}` into the web app's router makes the twins real before
server-side routes exist.

## Per-platform wiring

| Platform | Where to register | Where to dispatch |
|---|---|---|
| **Web** | Nowhere; URLs are the routing (+ `404.html` forwarder on static hosts) | `js/app.js::init()` reads `location.search` + `pathname` |
| **iOS / iPadOS** | `Info.plist` `CFBundleURLTypes` (custom scheme) + Associated Domains entitlement (Universal Links) | `App.scene.onOpenURL`: fires for BOTH custom and Universal Links on iOS 17+ → post to the intent inbox |
| **tvOS** | `Info.plist` `CFBundleURLTypes`, custom scheme ONLY (no Safari on tvOS → no Universal Links; the scheme is what Top Shelf + Siri use) | same `.onOpenURL` → same inbox (universal target) |
| **Android** | `AndroidManifest.xml` `<intent-filter android:autoVerify="true">` per scheme + path-prefix | `MainActivity.onCreate` + `onNewIntent` → `handleDeepLink(intent)` switches by `uri.scheme` |

**Android manifest audit**: EVERY host/path the app emits anywhere
(share sheets, QR codes, widgets) must be declared in an
intent-filter. An undeclared route fails silently for external
opens while in-app navigation works, which is why it ships broken.
Test each route with
`adb shell am start -a android.intent.action.VIEW -d <url>`.

**Sharing from a TV**: a tvOS app can't invoke a share sheet to
another person. Render the HTTPS twin as an on-screen **QR code**.

## State in the link

Archive Watch has no backend and no accounts, and folks still wanted
to hand a playlist to a friend. The answer was to put the playlist in
the link itself. There is no server to run, nothing to bill, and
nothing that learns what anyone shared.

The link carries the state. Nothing stores it.

I want a shared list to open on every platform, preview when it is
posted, and keep working years after it was sent. These rules are
what that took (source: Archive Watch `docs/PLAYLIST-SHARING.md`).

1. **Deflate the payload, then base64url it.** A playlist is a name
   plus ordered ids. Measured over 300 random draws per size against
   the live catalog: 50 titles came to a median of 1,368 characters
   (p95 1,542), 100 titles to 2,535. About 2,000 characters is the
   practical ceiling, because chat apps, email clients and QR codes
   start mangling links past it. So a self-contained link holds
   about 50 items. Past the cap, share the first N and say so on
   screen ("Sharing the first 50 of 70"). Never truncate silently.
2. **Keep an uncompressed variant for platforms that cannot
   deflate.** Mark it with a version prefix so every decoder knows
   which one it is reading. Roku's BrightScript has no deflate, and
   its links run about 2.5 times longer.
3. **Put the route in the path and the payload in the fragment:**
   `https://app.example.com/list/#<blob>`. A browser never sends a
   fragment to the server, so the list stays on the device. And an
   Android intent filter matches the path and cannot see a fragment
   at all, so `/#/list/<blob>` could never open the Android app.
   Apple's AASA can match fragments, but one link has to serve both.
4. **Make the route a real static page.** GitHub Pages serves
   `404.html` with an HTTP 404 status, and several link-preview
   crawlers refuse to preview a 404. Generate `/list/index.html`
   with generic preview copy and a script that hands the fragment to
   the router. The copy is generic on purpose: the contents are in a
   fragment the generator never sees. Keep a `404.html` fallback for
   the window before the page deploys, and have the deploy refuse to
   ship without the static page.
5. **Old link shapes decode forever.** Links are permanent and some
   are already out in the world. Every earlier shape keeps a decoder
   and a route on every platform.
6. **Declare an AASA path only after the app that handles it is
   live.** We serve the AASA file, so it takes effect the moment it
   deploys. Declared early, it sends a shared link into an installed
   app that does not know the route and drops the person on Home
   with their link gone. That is worse than the web page. The order
   is: teach the apps the route, ship them, confirm the release is
   live (approved is not live), then declare the path. Android is
   different: its intent filter ships inside the app, so the path
   can be declared in the same release that handles it.
7. **Televisions share by QR code.** A TV draws the same link as a
   QR code for a phone to scan. Prove the encoder by decoding a
   photograph of the screen back to the exact string, because a
   broken QR code looks just like a working one.

The cost is honest: a link is not a directory. You can only open one
if somebody sent it to you, so discovery still needs a published list
(Archive Watch bakes submitted lists into the static site through an
editorial step). And a long list does not fit. We chose that over
running a server.

## Verification files

Both iOS and Android verify HTTPS deep-links via files at
`/.well-known/` **at the domain root**. A project-pages subpath
(`user.github.io/repo/.well-known/`) does NOT work for iOS; you
need a user site or a custom (apex) domain. See
`.well-known/README.md` for the JSON shapes:

- iOS: `apple-app-site-association` (no extension)
- Android: `assetlinks.json`

Common failures, all production-verified:

- **File missing from the published build.** GitHub Pages runs
  Jekyll by default, which silently drops dot-directories. Add a
  `.nojekyll` file at the root (or `include: [.well-known]` in
  `_config.yml`).
- **Android: only the upload-key fingerprint listed.** Production
  installs are PLAY-signed: add the Play App Signing SHA-256
  (Console → Setup → App signing) immediately after enrollment, or
  App Links break only in production.
- **iOS: entitlement flipped mid-review.** Adding Associated
  Domains re-signs the app, so don't change it while a build is in
  flight.
- Symptoms (disambiguation chooser on Android; URL opens Safari on
  iOS) look like OS bugs; the bug is always the verification file.

## Path-prefix discipline

Each new resource type needs a path prefix added to ALL surfaces in
one PR:

1. `.well-known/apple-app-site-association`: `applinks.details[].paths`
2. `.well-known/assetlinks.json` (the manifest below gates prefixes)
3. `android/app/src/main/AndroidManifest.xml`: `<data android:pathPrefix="/newresource"/>`
4. The Apple `.onOpenURL` dispatcher / intent inbox: add the case
   (one dispatcher serves iOS + macOS + tvOS in the universal target)
5. `MainActivity.kt` `handleDeepLink`: add the case + route
6. `js/app.js` URL parser (+ `404.html` forwarder map): handle the
   new route

For a **companion-app** deep link (opening a different app), the
per-platform install-probe + open differs: iOS uses
`UIApplication.canOpenURL`/`open` (+ the scheme in
`LSApplicationQueriesSchemes`); **macOS uses
`NSWorkspace.urlForApplication(toOpen:)` / `open`, with NO
`LSApplicationQueriesSchemes` entry** (that array is iOS-only);
Android uses an `Intent`. Fall back to the companion's store page
when it isn't installed.

The dispatcher logic switches by SCHEME (`https` vs custom), THEN by
path, never by URL shape alone. The hard-won lesson:
`url.scheme == "myapp"` silently drops every HTTPS Universal Link
because the scheme check excludes the wrong half.

## OAuth callbacks specifically

OAuth providers require a redirect URI. On mobile, that's ALWAYS a
custom scheme. HTTPS redirects go through the system browser and
break the back-to-app hop:

- Android: `appname://oauth/callback` in the manifest; Custom Tabs
  handles the round trip.
- iOS: same shape in `Info.plist` `CFBundleURLTypes`.
- Web: `https://app.example.com/oauth/callback`, no special
  handling.
- tvOS: avoid OAuth-in-browser entirely (there is no browser).
  Use Sign in with Apple natively, or a device-code flow if a
  third-party provider is unavoidable.

When a provider lets you choose, use the bundle identifier as the
redirect scheme (`com.example.appname://oauth/callback`). Prefer PKCE
where the provider offers it and a Device Code flow where it does not,
which also covers the TV. The `authentication` skill carries the rest
("Installed-app OAuth to third-party providers").

Don't try to unify the mobile and web callback URLs. The OAuth
spec doesn't, and the providers don't.
