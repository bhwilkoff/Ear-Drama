# Ear Drama: Cross-Platform Feature Parity

> **Single source of truth** for what's shipping where. Updated in
> the SAME change set as any user-facing feature.
>
> Companion to `AGENTS.md` (project context), `SCRATCHPAD.md` (active
> milestone), `DECISIONS.md` (architecture decisions). Per-platform
> design rules live in `iOS-DESIGN.md` (iOS), `macOS-DESIGN.md` (macOS),
> `tvOS-DESIGN.md` (tvOS), `WEB-DESIGN.md` (web), `ANDROID-DESIGN.md`
> (Android) when those binding docs exist. The full workflow
> (including the periodic parity audit) is the
> `cross-platform-parity-discipline` skill.

Base platforms: **web · iOS/iPadOS · macOS · tvOS · Android.** The three
Apple platforms (iOS · macOS · tvOS) are adjacent in every table because
they share one Swift Core. A Core change usually moves all three columns
at once, so verify each still builds.

Extended surfaces, added as COLUMNS when adopted (each is a form factor
of an existing build, not a new codebase; see Decision 028): **Android TV /
Fire TV** (the Android app's TV form factor) and **Web-TV** (webOS /
Tizen / Cast, the web app's additive TV layer). **Windows** (Decision
029) is an optional sixth full platform with its own column and its own
authoritative parity doc (`docs/windows/` pattern: a WINDOWS-PARITY.md
mirroring this file's rows). A feature that ships on phone/desktop but
not its TV form factor gets ⏳ with a reason, never silence. The
recurring audit finding is parity that lands on new platforms without
returning to the platform it started on.

> **Last audit: 2026-10-22 (loop tick 30)**: sections 4 to 13 still held
> the template's sample rows, and 38 cells claimed ✅ for things Ear Drama
> never built (sign-in, account deletion, share links, Liquid Glass, an
> installable PWA, Mac player-as-window). Rewritten from the code: nothing
> has shipped to a store or the live site with data yet, so no cell reads ✅;
> built-but-unplayed work reads 🚧.

---

## 0. Platform set

**1.0 is the core five at one feature set** (Decision 056): web, iOS/iPadOS,
macOS, tvOS, and Android. The **web leads**: it is the landing twin for every
share link and the fastest to see, and the natives mirror it. tvOS earns its
place because listening is lean-back; macOS shares the Apple Core.

**Stubs at 1.0, built out after the core five** (Decision 056): CarPlay,
Android Auto, Android TV / Fire TV, Roku, webOS / Tizen, watchOS, and Wear OS.
Each is a target that builds and launches, ⏳ in every row until then.
Windows is 🔮: not in the owner's set for 1.0.

---

## Legend

- ✅ **Shipped**: live in production on this platform
- 🚧 **In progress**: being built; some parts may already be in main
- ⏳ **Planned**: committed; targeted for an upcoming milestone
- 🔮 **Future**: agreed direction; no timeline yet
- 🚫 **Out of scope**: explicitly not built on this platform (with reason)
- n/a: platform-inapplicable (e.g., lock-screen controls on tvOS)

n/a and 🚫 are different claims. n/a means the verb does not apply to
this platform at all. 🚫 means it could apply and we chose not to build
it, and the Notes say why.

A ⏳ or 🚫 cell carries its reason in Notes. "Deliberately deferred,
because X" is a healthy cell; a silent blank is drift.

---

## Parity rule

When shipping any user-facing feature:

1. **Confirm the verb is identical across platforms.**
   Find = explore, Profile = identify, etc. Don't let one platform
   own a different verb for the same surface.
2. **Pick the native idiom per platform**: `<dialog showModal>` on
   web, `.sheet` on iOS, `NavigationSplitView` + AppKit on macOS,
   focus-driven full-screen on tvOS, `ModalBottomSheet` on Android.
   *Same verb, native idiom.* An inversion of another platform's rule
   (e.g. `.buttonStyle(.plain)` is wrong on tvOS but correct on
   iOS/macOS) is deliberate. Never harmonize it away.
3. **Update this table** in the SAME PR. Drift here is what causes
   "the web has X but iOS doesn't" complaints six months later.
4. **Cross-link to the binding design doc** for each platform that
   has one.

---

## 1. Top-level navigation

| Verb | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Shell: Home · Browse · Stations · Surprise · Search · Library (Decision 068) | 🚧 six in the nav; old `?view=listen/series/radio/plays` rewritten to the new names | 🚧 iPhone five tabs, Surprise from Home's toolbar; iPad sidebar lists Surprise | 🚧 six sidebar sections, ⌘1 to ⌘6 | 🚧 six sidebar entries | 🚧 five tabs, Surprise from Home's top bar | Archive Watch's placement per platform; sections are verbs, never content types. Doors take the new names and still read the old |
| Home (Continue, shelves by rule) | 🚧 Continue, Following, then `listenShelves` | 🚧 `listenShelves` | 🚧 `listenShelves` | 🚧 `listenShelves` | 🚧 `listenShelves` | Was Listen. Decision 058; R13 lists from data. Every client draws the published `listenShelves` in order (contract §5.1). No Most episodes (HUMAN-SHAPED B). Roku still reads `index/listen.json` |
| Browse (series and plays together; kind, genre, decade, network, has a script; Sort, Popular by default) | 🚧 selects incl. Kind and Has a script; plays as rows | 🚧 chip row; plays as rows | 🚧 same | 🚧 series, Genre picker; no plays (TV records nothing) | 🚧 chips incl. Kind and Has a script; plays as rows (not on TV) | Was Series. Plays have no genre, decade, or network, so those narrow to series; Has a script keeps plays and series with an episode whose `script` is set (contract §3.1); no episode is linked yet. Sort: Popular (`series.downloads`, contract §3.3; uncounted rows and plays after the counted, by name), A to Z, Most episodes, Oldest first, on every platform; the TV's is a picker |
| Stations (evenings and genre stations on one clock) | 🚧 stations row (Tonight, then genre stations from `stations.json`), Listen live | 🚧 stations row; Tonight; Listen live; device-checked on iPhone 12, 2026-10-27 | 🚧 stations row; Tonight | 🚧 stations shelf of cards, first focused; Tonight | 🚧 stations row; Tonight; Listen live; TV focus stops | Was Radio. Gaps stated, never filled (R9); floor 0.25 provisional (owner, SCRATCHPAD 4) |
| Surprise (a random episode, evening, and play; one tap) | 🚧 `?view=surprise` | 🚧 push from Home; iPad sidebar; device-checked on iPhone 12, 2026-10-27 | 🚧 sidebar | 🚧 sidebar; no play | 🚧 Home top bar; no play on TV | Platform random, no cross-platform determinism; an evening plays its first surviving slot from the start, never a queue |
| A person's page (`withPerson`): every served episode crediting them, by series, roles on each row, oldest or newest first; credits on Detail link to it; People in Search | 🚧 `?person=`, `/person/{id}` twin, segmented order, `people/` shards and `search/people/` files | 🚧 `PersonScreen`, toolbar order Menu, credit rows push; device-checked on iPhone 12, 2026-10-27 (deep link) | 🚧 same screen in the detail column | 🚧 `PersonScreen_tvOS`, order button, credits a focus section of links | 🚧 `PersonScreen`, segmented order, credit rows open it | Facts only (name, years, episode count, portrait when served); no bio. Web people search reads the projection; Apple and Android scan `people` natively. No device check yet |
| Search (titles, people, plays, transcript text, dates) | 🚧 word-prefix titles, people, plays; no transcripts yet | 🚧 FTS5 word-prefix; plays; device-checked on iPhone 12, 2026-10-27 (search link) | 🚧 FTS5 word-prefix; plays | 🚧 FTS5 word-prefix | 🚧 FTS5 word-prefix; plays (not on TV) | |
| Library (followed series, queue, downloads, history, ear dramas) | 🚧 device-local; Ear dramas; no downloads (Decision 071) | 🚧 Ear dramas | 🚧 Ear dramas | 🚧 no Ear dramas | 🚧 Ear dramas (not on TV) | Device-local until sync (M5) |
| Start an ear drama (any page whose record carries a script) | 🚧 a play's page; an episode whose `script` is set (fixture-verified) | 🚧 a play's page; a linked episode | 🚧 a play's page or a linked episode, opens its window | n/a | 🚧 a play's page; a linked episode (not on TV) | Decision 068: `episodes.script` links only castable bundled scripts (`episode_scripts.py`). 2026-10-24: 0 linked; 616 served episodes match a Generic Radio Workshop script and wait on GRW's permission, and even then each needs its own work-layer evidence |

---

## 2. Listening

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Show art: star portraits, typographic card, lock-screen artwork | 🚧 tiles on mixed rows and series rows, faces on series page and Detail, cast portraits, Now Playing and Media Session | 🚧 same; `MPMediaItemArtwork` | 🚧 same; transport-bar tile | 🚧 card tiles, Detail and series faces, cast grid, 400 pt Now Playing art | 🚧 tiles, faces, cast portraits, sheet art, Media3 `artworkUri` / card PNG | Decision 069, contract §3.3a: dated matches' own P18 portraits only; CC credits shown; no device check yet |
| Episode detail (date, network, sponsor, cast, versions, rights line) | 🚧 no sponsor yet | 🚧 | 🚧 | 🚧 | 🚧 no sponsor | Unclaimed reads "no claim known; removed on request", never public domain |
| Player: background play, system controls, speed, skip | 🚧 Media Session | 🚧 Now Playing, remote commands; skip, seek, speed, pause device-checked on iPhone 12, 2026-10-27 (muted, XCUITest taps) | 🚧 Controls menu, keyboard | 🚧 full-screen Now Playing | 🚧 Media3 session | iPhone web cannot be relied on for background audio. Headerless VBR MP3 (no Xing/Info/VBRI; the first frame's bitrate misreads duration and seeks, found 2026-10-27): Apple uses precise duration and resumes from nothing past the catalog length; Android builds a seek map from the catalog length (`Mp3Seeking`) and applies the same resume rule, unit-tested, not device-checked; web `<audio>` unchanged, exposure unmeasured |
| Sleep timer: "end of this episode" first, fades (R20) | 🚧 fade ignored by iPhone Safari (pauses) | 🚧 15 minutes set and cleared, end of this episode stopped a downloaded file; device-checked on iPhone 12, 2026-10-27 (fade not heard) | 🚧 | 🚧 | 🚧 | Decision 062: 10 s fade, speeds 0.75 to 2, save every 5 s, 3 s rewind after an interruption; on every core platform |
| Serials play to the end of an arc and stop; the next story is offered (R3, Decision 067) | 🚧 `API.arcOf`, `Player.upNext`/`nextStory`, "Next story" in Now Playing | 🚧 `PlaybackQueue.after`, `NextStoryButton` in Now Playing | 🚧 same; transport bar | 🚧 same; action row | 🚧 playlist is the arc's remaining parts then the queue; "Next story" on the sheet | Arcs from titled parts only (catalog DECISIONS 010): 480 on the native build, 198 whole on the clean-only web. A live slot never follows an arc. No device check; nothing heard |
| Commercials chaptered, never skipped (R8) | ⏳ no data | ⏳ no data | ⏳ no data | ⏳ no data | ⏳ no data | Skip is a fixed interval everywhere; no source marks commercial times yet (contract §3.2a) |
| Volume leveled on the device (Decision 067) | 🚧 DynamicsCompressorNode; not on iPhone/iPad web or TV engines ("Not in this browser") | 🚧 MTAudioProcessingTap + DynamicsProcessor | 🚧 same; beside the sleep timer | 🚧 same; Now Playing toggle | 🚧 DynamicsProcessing on the audio session | Decision 070: one set of numbers, on by default, "Level volume" turns it off; no per-file gain; not yet heard on a device |
| What plays next: an arc's next part, else one episode, then the person's queue, then stop (Decision 067) | 🚧 | 🚧 plays a synced queue; add, remove, reorder (Detail button, row menu, Library Queue); device-checked on iPhone 12, 2026-10-27: Detail add, Library Queue order, Move down, swipe to remove, and a serial's next part ahead of the queue | 🚧 same, plus a Controls menu command | 🚧 same, long-press menu, no reorder drag | 🚧 add, remove, reorder built (Detail button, long-press menu, swipe to remove), not device-checked | Arcs: the serial row above |
| Versions picker; domestic copy by default | 🚧 | 🚧 | 🚧 | 🚧 Versions section on Detail | 🚧 | catalog Decision 007 |
| Transcripts, labeled automatic | 🚧 closed section, fetched on open | 🚧 sheet, from Detail and the player | 🚧 window, ⌥⌘T | 🚧 focus-scrolling reader | 🚧 route from Detail and the player | Shown only above the measured quality gate (058) |
| Downloads (an episode, a season, a whole run; a Downloads place by series; storage held; remove a series or all) | n/a: decided, Decision 071 (WEB-DESIGN §7.2a) | 🚧 background session, four at a time; series Download menu asks with count and size; Library row to the place; one episode downloaded, played from the file, removed, device-checked on iPhone 12, 2026-10-27 | 🚧 same; toolbar menu, right-click Remove | n/a; Library says "Downloads are on iPhone, iPad, and Mac." | 🚧 WorkManager, four at a time; top-bar Download menu; `Route.Downloads` | Decision 071. A finished file plays with no network; a queued, failed, or partial one never plays. Lock screen offline: Apple falls back to the typographic card, Android always shows the card for a downloaded file. No real run downloaded by an agent |
| Listen Together | 🚧 Worker rooms; ?room= link; guests follow, never drive; a guest's pause holds, play catches up | 🚧 SharePlay; capability off until the App ID has it | 🚧 SharePlay | 🚧 SharePlay during a call | 🚧 Worker rooms; ?room= link; guests follow; TV joins by code; a guest's pause holds, play catches up | Worker rooms on web and Android (Decision 065); a guest's own pause on every platform (Decision 067); Apple ports room-protocol.js, golden-checked; not run on devices |
| Credits, privacy, and take-down pages | 🚧 /credits/, /privacy/, /takedown/; owner placeholders | ✅ three links at Library's foot (`SiteLinkRows`), system browser; UI-tested (existence only, not tapped) | ✅ Help menu (`SiteLinks`) | 🚧 three rows with the plain address (no browser); built, not seen on a TV | 🚧 three Library rows, Custom Tab (a TV shows the address); built and unit-tested, not seen on a device | One set of pages; apps link to them. Web pages themselves still owner placeholders |
| Works offline (what was already loaded) | 🚧 service worker; network-first data, cached shell; "You are offline." line; `?offline=1` door | 🚧 seed or downloaded catalog, downloads, Library; "You are offline." above the mini player; an undownloaded episode is refused in words; `APP_FORCE_OFFLINE` | 🚧 same; the line above the transport bar | 🚧 same minus downloads; the line heads every tab | 🚧 says "You are offline." above the mini player and on the no-catalog state; `appname_force_offline` door | Audio downloads are their own row. Apple and Android built and unit-tested, not device-checked offline (the iPhone 12 sweep, 2026-10-27, saw Detail's older warning on a build before the line); web screenshot at 375 px with the door |

---

## 3. Making plays

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Pass the phone: record role by role on one device | 🚧 headphones confirmed by the person (a page cannot see the route); IndexedDB; not yet recorded | 🚧 built, tested; not yet recorded on a device | 🚧 own window, Recording menu; not yet recorded | n/a | 🚧 Start an ear drama on a play's page (not on TV), takes as 24-bit WAV; not yet recorded | Web with headphones only; live stand-in voices never stored; 15 scripts bundled (`catalog/plays/castable-scripts.json`): 11 stage plays, 4 radio plays |
| Parts in any order, the largest suggested (C7, Decision 067) | 🚧 every open part has Take part, the largest accented | 🚧 same; the largest prominent | 🚧 same | n/a | 🚧 same; the largest filled | One part records at a time on one device; the Worker allows any open part too (`not_open`) |
| Recording needs an account, always (Decision 067) | 🚧 "Recording needs an account." and Sign in at Start recording | 🚧 same, Sign in with Apple / Google buttons | 🚧 same | n/a | 🚧 same, the account row | Taking a part, reading along, and listening need none; sign-in from this step not yet run on a device |
| Listen through any time, open lines read live (C5, Decision 067) | 🚧 `ListenThrough`, `speechSynthesis` local voices | 🚧 `LiveListenThrough`, `AVSpeechSynthesizer.speak` | 🚧 same | n/a | 🚧 `LiveListen`, `TextToSpeech.speak`, local voices only | Labeled "Device voice"; never stored, mixed, exported, or uploaded; a guard test on each platform, broken once; not yet heard on a device |
| Personal Voice in a listen-through (Decision 067) | n/a: no such browser API | 🚧 "Use my Personal Voice", `speak` only | 🚧 same | n/a | n/a: no such Android API | Live only, never a buffer, a file, or a cue; needs a device to verify |
| Export whenever every speaking line is human (Decision 067) | 🚧 Export beside the mix, renders if stale | 🚧 `ShareLink`, renders on demand | 🚧 same | n/a | 🚧 share sheet, renders if stale | No longer waits for a full listen |
| A play's facts: year, author's years, length (Decision 067) | 🚧 | 🚧 | 🚧 | n/a | 🚧 | "1876 · 16 parts · 657 lines"; the year is the record's own (`year` in the bundle, 3 of 15 have one); no age ratings |
| Commercials as their own parts (C10) | ✅ data plane | ✅ data plane | ✅ data plane | n/a | ✅ data plane | `script_parse` names a speech inside commercial n "ROLE (COMMERCIAL n)"; no bundled script has a commercial yet |
| Invite-link productions (share, invite, join, claim any open part, upload, consent, report, block, publish) | 🚧 `js/plays-share.js`; stub-Worker tests; screenshots at 375 px against a stubbed record; never against a deployed Worker | 🚧 `Core/Plays/PlaysShare.swift`, `SharedPlaysViews.swift`; stub-transport tests; not run on screen | 🚧 same code, Mac idiom; not run on screen | n/a: TVs play back only; invites ignored | 🚧 `plays/PlaysShare.kt`, `SharedPlaysScreens.kt`; JVM tests; not run on a device. The 10 s OkHttp read timeout may cut a large upload (ANDROID-DESIGN §12); manifest link filters stay off | PLAYS-DESIGN §11.7. Sign-in required. Uploads wait on the owner's R2 switch (P1): the record's `uploads` is false and every client says "Uploads are off." Consent words are the owner's placeholder (P2) |
| Teacher classes (consent for under-13s) | 🚧 Classes in Library's Ear dramas: make, join by code | 🚧 make, join; no roster view yet | 🚧 same | n/a | 🚧 make, join | A roster only (P8). An under-13 class takes no student until the privacy policy covers school consent (P5) |
| Play back a finished play | 🚧 Listen through, Export as WAV | 🚧 Listen Through, Export | 🚧 Listen Through, Export | ⏳ AirPlay from a phone meanwhile | 🚧 Listen through, Export via share sheet | |

---

## 3b. Teaching surfaces

Teaching is a parity domain with DELIBERATE asymmetry. Track it so
a future session doesn't "harmonize" a rejection into a port (see
`universal-feature-states`).

| Surface | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| EmptyState (productive next action) | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | Required everywhere from the first list/grid |
| ErrorBanner / OfflinePill | 🚧 offline line; the player's line ("You are offline." or "This recording did not load."), announced; no haptics on the web | 🚧 offline line; error haptic with the player's line ("You are offline." for a network failure) and "Download failed" | 🚧 offline line; the player's line and "Download failed"; haptics n/a on the Mac | 🚧 offline line; the player's line; no downloads, no haptics on the TV | 🚧 offline line; error haptic with "Download failed" and the player's problem line | Required everywhere. Built, not device-checked |
| HintBanner (one-shot tip) | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | Persisted dismissals + a global reset in Settings |
| Multi-step anchored walkthroughs | 🚫 | ⏳ | 🚫 | 🚫 | 🚫 | iOS-only where its idioms are novel; other platforms use EmptyState + hints + a `?` explainer. Record the rejection in each platform's design doc |

---

## 3c. Stubs (Decision 056)

A stub builds in CI and opens to its first screen; it grows from the core's
shared code only after the core five are complete.

| Platform | State | First screen | Notes |
|---|---|---|---|
| CarPlay | 🚧 builds | Continue, Stations, Browse, Downloads tabs (R17); Continue and Downloads play | Runs only once Apple grants the carplay-audio entitlement (Needs Ben) |
| watchOS | 🚧 builds | Continue, "Waiting on the phone" | watchOS 11 floor (pairs with iOS 18); not embedded in the phone app yet |
| Android Auto | 🚧 builds | Continue, Stations, Browse, Downloads (R17); Continue and Downloads play through the phone's queue | Every release with car support waits on Google's car review: internal or closed track only; Assistant voice (VC-1) not done |
| Android TV / Fire TV | 🚧 builds | Home, D-pad focus on the first row; Now Playing card in the background (TV-NP) | Banner art is a placeholder for the owner |
| Wear OS | 🚧 builds | Continue, "Waiting on the phone" | minSdk 30 (Wear OS 3); needs its own versionCode before upload |
| webOS / Tizen | 🚧 builds (.ipk, .wgt) | Listen, D-pad focus on the first card; remote media keys; Back that walks history | Placeholder art; the .wgt was signed with the Archive Watch Samsung profile until Ear Drama has its own |
| Roku | 🚧 builds (sideload zip) | Listen rows of series tiles from the web projection; loading, empty, error, offline | No Series screen yet; placeholder art |

---

## 4. Accounts (Decision 057)

Signing in is optional: every listening verb works signed out. It syncs
history, queue, and follows, and it is required to make a play with others.

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Sign in with Apple | 🚧 Apple JS, nonce; placeholders until the Worker is deployed | 🚧 placeholders; entitlement off until the App ID capability (WORKER.md 4) | 🚧 placeholders; entitlement off until the App ID capability (WORKER.md 4) | 🚧 placeholders; entitlement off until the App ID capability (WORKER.md 4) | 🚧 Custom Tab, auth/apple/ return page; placeholders | M5; verified at the Worker |
| Sign in with Google | 🚧 Google's own button; placeholders | 🚧 ASWebAuthenticationSession + PKCE, no SDK | 🚧 same as iOS | ⏳ no web auth session on tvOS | 🚧 Credential Manager; needs Android OAuth clients | M5; tvOS by a phone hand-off |
| Email and password | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | Decision 057 names Apple and Google only |
| Sync of history, queue, follows | 🚧 LWW per row, markers, ?since=; tested against a stubbed Worker | 🚧 stubbed-Worker tests; no Follow/Queue controls yet | 🚧 stubbed-Worker tests; no Follow/Queue controls yet | 🚧 stubbed-Worker tests; no Follow/Queue controls yet | 🚧 stubbed-Worker tests; queue and follows stored, not shown | One store on the Worker + D1, never two |
| Account deletion | 🚧 in the account sheet, and the public page delete-account/ | 🚧 Account screen, fresh Apple code | 🚧 Account screen, fresh Apple code | 🚧 Account screen, fresh Apple code | 🚧 account sheet; web path delete-account/ | Ships with sign-in (Decision 035) |

---

## 5. Links

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Routes for series, episode, search | 🚧 + 404 forwarder | ⏳ | ⏳ | ⏳ | ⏳ | DEEP_LINKS.md |
| Universal Links / App Links | n/a | ✅ | ✅ | n/a | ✅ | 2026-10-24: AASA + assetlinks.json on eardrama.org; series, episode, person, search, library, invite open the apps (DEEP_LINKS.md). Built and unit-tested; not yet opened on a device from a real link. tvOS takes `eardrama://` only (no Safari) |
| `eardrama://` scheme | n/a | ⏳ | ⏳ | ⏳ | ⏳ | OAuth callbacks and Top Shelf |
| Share an episode | 🚧 Web Share | 🚧 share sheet, https link | 🚧 share menu, https link | ⏳ QR code | 🚧 share sheet, https link (not on TV) | The web page is every share's landing twin |
| Archive Watch film cross-links | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | Out of 1.0 (Decision 058) |

---

## 6. Not in 1.0

| Feature | Why |
|---|---|
| Push notifications | Nothing in 1.0 needs to reach a listener outside the app |
| Payments, subscriptions, in-app purchase | Free, no ads (AGENTS.md); no paid tier |

---

## 7. Oldest hardware served

| Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Evergreen browsers | iOS 18 (iPhone XS / XR) | macOS 26 | tvOS 26 (Apple TV HD) | minSdk 29 (Android 10) | project.yml and android/app/build.gradle.kts; tools/test_ios_floor.py and test_tvos_floor.py hold the Apple floors |

---

## 8. The shared data plane

Every client is a consumer only (`shared-data-plane-contract`); the
contract is `docs/CATALOG-CONTRACT.md`.

| Asset | Purpose | Where | Consumed by |
|---|---|---|---|
| `ear-drama.sqlite.zz` + `manifest.json` | the served projection, queried on disk | Release `catalog-latest` | iOS, macOS, tvOS, Android (validate, then swap) |
| `ear-drama-seed.sqlite` | first launch offline (clean only) | bundled at build time from `catalog/out/publish-clean` | iOS, macOS, tvOS, Android |
| `/data/` (index, series, shards, days) | the web projection | GitHub Pages, deployed by `catalog-publish.yml` | web |
| `loudness-latest` | loudness measurements | Release asset, `catalog-loudness.yml` | the projection build only |
| Worker + D1 | accounts, sync, shared plays | 🚧 built and tested locally (Decision 063); not deployed; no client signs in yet | every client |

---

## 9. Web-specific affordances

| Feature | Web | Why |
|---|---|---|
| URL reflects the view | 🚧 | Shareable links; native apps keep state in memory |
| Web Share with a copy fallback | 🚧 | Native apps use the system share sheet |
| Offline shell (service worker) | 🚧 | Network-first data, cached shell; audio downloads are the apps' |

---

## 10. iOS-specific affordances

| Feature | iOS | Why |
|---|---|---|
| System tab bar (Liquid Glass on iOS 26) | 🚧 | The floor is iOS 18, so the system draws what each version has |
| Lock Screen and Control Center controls | 🚧 | Now Playing and remote commands; device check pending |
| Dark and tinted app icons | 🚧 | The mark in the dark-mode red on a clear ground; a grayscale one for tinting (`tools/render-app-icon.py`); not yet seen on a device |
| Live Activities, widgets | 🔮 | After 1.0 |

---

## 11. macOS-specific affordances

macOS is a pointer, keyboard, menu bar, resizable-window app, never the
iOS app resized (`macos-platform-patterns`).

| Feature | macOS | Why |
|---|---|---|
| Controls menu with keyboard equivalents | 🚧 | Play/Pause, skip, speed, sleep timer, Download Episode |
| `NavigationSplitView` sidebar and detail | 🚧 | iOS uses tabs, tvOS a focus sidebar |
| A transport bar along the window's bottom | 🚧 | Audio has no picture, so the player never replaces the window |

---

## 12. tvOS-specific affordances

| Feature | tvOS | Why |
|---|---|---|
| Focus-driven layout, Play focused on Detail | 🚧 | The ten-foot constraint (`tvos-platform-patterns`) |
| Full-screen Now Playing | 🚧 | Typographic, no artwork required |
| Top Shelf | ⏳ | The listener's Continue items |
| Layered parallax icon | 🚧 | Back (red), ring, microphone layers (`branding/tvos-icon-layers/`); not yet seen on a device |

---

## 13. Android-specific affordances

| Feature | Android | Why |
|---|---|---|
| Predictive back | 🚧 enabled in the manifest | iOS swipe-back is fixed-animation |
| Media3 notification and lock-screen controls | 🚧 | The MediaSession service |
| Adaptive icon with a monochrome layer | 🚧 | The ring microphone on the icon red, with its own monochrome silhouette (`tools/render-app-icon.py`); not yet seen on a device |
| Android Auto library tree | ⏳ | M9 stub |

---

## Maintenance protocol

When you ship a feature:

1. Find the row in this table. Add new rows under the right section
   if needed.
2. Update each platform's status with one of the legend symbols.
3. Link to the relevant section of the platform's binding design doc.
4. Note any platform-specific deltas in the Notes column.
5. A shared-Core change usually moves all THREE Apple columns (iOS ·
   macOS · tvOS). Verify each still builds before you tick them.

When a feature ships on one platform but is meaningfully different
elsewhere, add an entry to §9 / §10 / §11 / §12 / §13.

When a platform explicitly rejects a feature, add an "Out of scope"
row in the relevant design doc and link from this table.

Keep the matrix readable, or it stops being true:

- **A cell is one sentence plus a link.** Put the evidence in the cell
  ("✅ verified on iPhone 12, YYYY-MM-DD"). Put the story in the ledger,
  design doc or DECISIONS entry the cell links to. A matrix that
  becomes a journal stops being read.
- **Name the parity test** in Notes for every row a mechanical guard
  enforces (for example `tools/test_<rule>_parity.py`).
- **One summary row per ported platform** (§7d). Never keep a second
  per-surface copy here once the port has its own ledger.
- **Scripts read columns by header name.** `line.split("|")` returns a
  leading empty element, so a fixed index lands in the wrong column
  and the table still renders. Build the index from the header row.
- **Keep §7b and §7c current** when a floor moves or a capability
  changes.

**Run a parity audit** (the `cross-platform-parity-discipline` skill,
"audit" mode) before any launch wave and roughly once per milestone:
walk the shipped feature list per platform and verify every cell is
honest. Real audits on shipped apps have found both missing rows
(features nobody recorded) AND false cells (a "synced" claim that
never actually synced). The audit is what keeps this file true.
