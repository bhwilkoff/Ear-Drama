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
| Series | `https://eardrama.org/series/{key}` | All; web routes via `?series={key}` (`&season=`) |
| Episode | `https://eardrama.org/episode/{percent-encoded id}` | All; web routes via `?item={id}`; an aliased id forwards |
| Person | `https://eardrama.org/person/{percent-encoded person id}` | All; web routes via `?person={id}` (`&order=newest`), forwarded by `404.html` (WEB-DESIGN §4.14); `eardrama://person/{id}` is its twin. The apps open it on the person's page; they emit no person link yet |
| Search | `https://eardrama.org/search?q=` | All; web routes via `?view=search&q=`; the apps open Search with the query filled in (`+` reads as a space, as `URLSearchParams` reads it) |
| Library | `https://eardrama.org/library` | All; web routes via `?view=library`; the apps open the Library tab |
| Listen Together room | `https://eardrama.org/?room={CODE}` | Web (WEB-DESIGN §4.12) and Android (ANDROID-DESIGN §4.13), Worker rooms (Decision 065); `eardrama://?room={CODE}` is its twin. The code is six Crockford Base32 characters, normalized as `normalizeCode` in `worker/src/room-protocol.js`. Opening it fills in the code; joining takes a tap on Join. The query form is the https twin because the site root is a real page (no `404.html` forwarding needed). Android opens `eardrama://?room=` from its scheme filter; the https form stays in the browser, because claiming the site root would pull every link to eardrama.org's home page into the app. Apple joins through SharePlay, not a code |
| Ear drama invite | `https://eardrama.org/invite#{TOKEN}` | Web, Apple (iOS, iPadOS, macOS), Android (PLAYS-DESIGN §11.7, Decision 066); `eardrama://invite#{TOKEN}` is its twin. The token is 43 base64url characters and rides the fragment so no server log holds it. `404.html` forwards `/invite` to `/?view=library&tab=dramas#invite={TOKEN}`; the web takes it from either shape, holds it for the tab, and clears it from the address. The apps post it to the inbox, which opens Library's Ear dramas with the invitation. Not on a TV |
| OAuth callback | `eardrama://oauth/callback?...` | Custom scheme only, never HTTPS (provider redirects break otherwise) |
| Sign in with Apple return (Android) | `eardrama://oauth/apple#state=&code=&id_token=` | Android. Apple returns to the Services ID's https return URL, `https://eardrama.org/auth/apple/` (fragment response, no scope); that static page (`auth/apple/index.html`) forwards its fragment unchanged to this link and clears it from the address bar; the link opens no screen (ANDROID-DESIGN §4.11). No HTTPS twin: it is a callback, not a share |

**Add a row to this table BEFORE adding a deep link in code.** New
routes that aren't documented here become orphans the next time a
platform adds support. Discovery cost compounds.

**The canonical-twin rule**: every custom-scheme link a native app
emits (`eardrama://episode/x`) has an HTTPS twin
(`https://eardrama.org/episode/x`) that the WEB app renders, so a
share always lands somewhere meaningful, even for recipients
without the app. On a static host, a `404.html` forwarder that maps
`/item/{id}` into the web app's router makes the twins real before
server-side routes exist. The Android and Apple link filters are on
(2026-10-24): `.well-known/assetlinks.json` and
`.well-known/apple-app-site-association` are written, the Android App
Links filter and `eardrama://` filter are live in the manifest, and the
Apple app carries `applinks:eardrama.org` (the Associated Domains
capability was enabled on the `app.eardrama` App ID the same day).
`tools/test_deep_links.mjs` (in `tools/test_web.sh`) holds the AASA paths,
the Android filter's paths, and the 404 forwarder equal, and checks
assetlinks against the Play key below.

The records: Play's app signing key for
`app.eardrama` has SHA-256
`F0:A8:CF:0F:A7:99:7F:EA:06:DB:98:2D:87:47:1A:EE:04:DB:D2:21:60:0B:71:48:C3:AC:27:FA:CB:90:16:1E`
(SHA-1 `20:2E:10:A0:1F:EB:58:43:50:FA:74:8C:AE:DB:65:D1:2F:19:C6:B1`); the
upload key's fingerprint joins it once an upload keystore exists. The
Apple team is `L2G756LY8N`.

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
   `https://eardrama.org/list/#<blob>`. A browser never sends a
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

**Content type on GitHub Pages (measured 2026-10-24).** Pages serves
`assetlinks.json` as `application/json`, and the extensionless
`apple-app-site-association` as `application/octet-stream`; Pages cannot
set headers. Apple accepts it: archivewatch.org (the same host, the same
team) serves its AASA as `application/octet-stream`, and Apple's CDN
holds it (`curl https://app-site-association.cdn-apple.com/a/v1/archivewatch.org`
returns the file). Apple fetches through that CDN, not from the device, so
the CDN's copy is the check after a deploy:
`curl -s https://app-site-association.cdn-apple.com/a/v1/eardrama.org`.
The CDN refreshes on its own schedule (hours to a day), so a path added
today may not open the app until it does.

**Why declaring the paths now is safe (rule 6 below).** A Universal Link
opens only an installed build whose entitlements carry
`applinks:eardrama.org`, and the first such build is the one that parses
every declared path. Builds already installed have no entitlement and keep
opening the site.

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

- Android: `eardrama://oauth/callback` in the manifest; Custom Tabs
  handles the round trip.
- iOS: same shape in `Info.plist` `CFBundleURLTypes`.
- Web: `https://eardrama.org/oauth/callback`, no special
  handling.
- tvOS: avoid OAuth-in-browser entirely (there is no browser).
  Use Sign in with Apple natively, or a device-code flow if a
  third-party provider is unavoidable.

When a provider lets you choose, use the bundle identifier as the
redirect scheme (`app.eardrama://oauth/callback`). Prefer PKCE
where the provider offers it and a Device Code flow where it does not,
which also covers the TV. The `authentication` skill carries the rest
("Installed-app OAuth to third-party providers").

Don't try to unify the mobile and web callback URLs. The OAuth
spec doesn't, and the providers don't.
