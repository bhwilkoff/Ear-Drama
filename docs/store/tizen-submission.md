# The Samsung Tizen submission pack

Companion to `docs/store/webos-submission.md`. The **app is identical**: same web
build, same TV layer, differing only in key codes, lifecycle events and
packaging (Decision 028). What differs is Samsung's process, and one
business decision that is genuinely yours.

Backlog: `docs/templates/TV-PLATFORM-BACKLOG-template.md` S1–S6.

---

## ⚠️ 1. Read this before creating the account

**Samsung's default "Public Seller" tier can only launch apps in the United
States.** Publishing anywhere else requires **Partner Seller**, which requires
signing an offline contract with Samsung HQ or a local subsidiary, i.e. a
business entity.

That is why the recommended order is **LG first, Samsung second**: LG lets an
individual publish globally with no equivalent gate, so it buys real reach while
this decision stays open.

Your options:

| Option | Reach | Cost |
|---|---|---|
| **Public Seller** | US only | Free, immediate |
| **Partner Seller** | Global | Free, but needs a signed contract + a business entity |

Neither blocks engineering. The `.wgt` is the same either way. This only
decides where it can be listed.

---

## 2. Samsung's review is a manual QA pass

Unlike LG's document-driven review, Samsung runs the app against their Launch
and Development checklists by hand. The items that matter for this app:

| Area | Status | Notes |
|---|---|---|
| Launch time (10 s required, 5 s ideal) | Measure it | Cold launch to the first real content, timed on a real set. Archive Watch measured 6.9 s (first paint 1.6 s, its 2 MB index in by 2.3 s): inside the requirement, short of the ideal |
| Launches without error | Pass | Cold launch to Home |
| Full D-pad operability | Pass | 9 surfaces verified by automated focus trace |
| Focus always visible | Pass | Ring + scale + elevation, never colour alone |
| **Back / Return behavior** | Pass | Layered: an open player closes before any navigation, and everywhere else Return steps back one layer. **At the root, Return asks "Exit <app>?" (Exit / Stay), drawn by the app**, because Samsung's Terminating Applications policy requires it; Exit calls `tizen.application…exit()`. Return arrives as BOTH a keydown and a `tizenhwkey` event: handle it once |
| Screensaver during playback | Pass | `webapis.appcommon.setScreenSaver` off while media plays, back on at pause and end |
| Playback resumes after the app returns (CO-MT-01) | Pass | Media the app paused on going to the background resumes when it returns |
| Network lost (CO-CN-02) | Pass | An offline notice, shown inside the player too |
| Long playback | Pass | Play several minutes continuously. Tizen can report the end of a file as `PIPELINE_ERROR_NETWORK` with no `ended` event, so treat an error at the end as the end; and offer no Speed control, because Tizen's player breaks (readyState 0) on a `playbackRate` change |
| Media keys | Pass | Registered through `tizen.tvinputdevice.registerKey()`; **Tizen does not deliver them otherwise** |
| Playback | Pass | Progressive H.264 MP4 over HTTPS; no DRM needed |
| Subtitles | Pass | WebVTT, user-selectable, with the track set `hidden` and the cues drawn by the app at ten-foot size: Tizen's own renderer draws huge text in a narrow box and its size cannot be set |
| Suspend / resume | Pass | `visibilitychange` pauses; focus re-claimed on return |
| Overscan | Pass | 5% safe insets; no text at the panel edge |
| Ten-foot legibility | Pass | 24px body minimum at 1080p |
| No account / payment | Pass | No sign-in, advertising, or purchases |
| Content rights | Pass | Public-domain / CC only; see `docs/store/webos-submission.md` §4 |

The remote-driven walkthrough Samsung may ask for is the same as
`docs/store/webos-submission.md` §1; the app behaves identically.

---

## 2b. Older Samsung TVs: the floor is 2022 (Tizen 6.5, Chromium 85)

Archive Watch's owner, 2026-10-03: *"I'd like to be able to support
everything from 2022 onward."* Samsung's browser engine by model year: 2022
Tizen 6.5 = Chromium 85, 2023 Tizen 7.0 = 94, 2024 Tizen 8.0 = 108, 2025 Tizen
9.0 = 120. A test set that has been updated says nothing about a 2022 set.

Rendered in a real Chromium 85 build before it was fixed, Archive Watch's Home
was EMPTY: `replaceChildren` (86) threw while drawing it, and
`AbortSignal.timeout` (103) threw on every bounded fetch. Behind those, the CSS:
`inset` and the `padding-inline`/`margin-inline` shorthands (87) dropped the
overscan padding and un-centered every sheet; a rule list holding
`:focus-visible` (86) is dropped whole; `color-mix()` (111) with `var()` inside
passes the parser and fails at compute time, voiding the fallback above it.

This template already carries the fix: `js/compat.js` loads before every other
script and fills only what Chromium 85 lacks; `tools/test_tv_compat.py` holds
the CSS rules with planted controls; `tv/build-tv-packages.sh` refuses to
package when it fails; `config.xml` declares `required_version="6.5"`. Never
raise `required_version` to dodge a fix: that drops a model year from the store
silently.

**To check a change on a 2022 engine** without a 2022 TV: Google's Chromium 85
snapshot (`chromium-browser-snapshots/Mac/782078`, Intel, runs under Rosetta),
headless at 1920x1080 against `?tv=1` with a FRESH profile each run (a reused
one serves the old stylesheet from the service worker), reading
`Runtime.exceptionThrown`. Every route should draw with no exceptions.

---

## 3. Packaging

```bash
./tv/build-tv-packages.sh tizen     # stages the shared app + config.xml + icon
# then, with Tizen Studio CLI installed:
tizen build-web   -- tv/tizen/app
tizen package -t wgt -o tv/dist -- tv/tizen/app/.buildResult
```

**⚠️ Keep the signing certificate.** Samsung requires every future update to be
signed with the *same* certificate. Losing it means the app cannot be updated,
so back it up somewhere durable, outside the repo.

`tv/tizen/config.xml` already declares the TV profile, landscape orientation,
`hwkey-event` handling, and the `tv.inputdevice` privilege the media keys need.

---

## 4. Store listing

Same copy as `docs/store/webos-submission.md` §3. Samsung's screenshot dimensions
differ from LG's. Check the current requirement in Seller Office at upload
time rather than trusting a cached number.

---

## 5. Owner steps

| # | Step |
|---|---|
| 1 | **Decide: US-only Public Seller, or pursue Partner for global** (§1) |
| 2 | Create a free **TV Seller Office** account |
| 3 | Install Tizen Studio CLI and create a signing certificate, and **back it up** |
| 4 | `./tv/build-tv-packages.sh tizen`, then build + package (§3) |
| 5 | Enable Developer Mode on a Samsung TV (it is keyed to the TV's IP) and side-load |
| 5b | **Confirm the side-loaded app actually shows films before submitting.** A packaged app runs from `file://`, where a relative data URL resolves inside the package instead of to the server. That was fixed 2026-08-05, but it is invisible in the browser build. An empty Home means the data plane regressed; `node tools/test_packaged_origin.mjs` guards it |
| 6 | Submit through Seller Office; expect ~1–2 weeks and possibly several cycles. Choose the model groups on purpose (2022 onward matches the 6.5 floor, including the licensed `_LIC` groups) |

**Seller Office traps met on a first submission** (Archive Watch,
2026-10-03): the pre-test refuses a `config.xml` that names no screen size
(declare `screen.size.normal.1080.1920`); tags take single words only; every
section's Save must be left to finish, because navigating away mid-upload
silently dropped the screenshots; the screenshot slots share ONE file input,
chosen by the slot's edit icon; the App Description File is Samsung's
PowerPoint template, which you fill and regenerate for each version.

**What a TV package must not carry**: links to other app stores ("Get the app
on ..."). Every TV store's guidelines object to an app linking to a competing
store, and a packaged TV app has no browser to hand off to. Hide them on TV only.
