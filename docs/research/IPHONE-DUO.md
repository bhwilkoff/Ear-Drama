# iPhone Duo: Ear Drama's first pass (2026-11-14)

The owner connected the Duo ("Duo", iPhone19,4, UDID 00008160-001814623AA00036)
for about 45 minutes. This page is what the app did on it, what was fixed, and a
design plan. Apple's device guidance and the SDK table are not repeated here;
they are in Archive Watch's `docs/research/IPHONE-DUO.md` §2 and §2a, and its
iOS-DESIGN §2.8 holds the Duo rules it adopted. Ear Drama follows the same rules.

Frames are in `build/qa/duo-2026-11-14/` (gitignored, local to this Mac).

## 1. How it was seen

- Debug build, Xcode 27.1 (iOS 27.1 SDK), `xcodegen` then `xcodebuild` for the
  device id, installed with `devicectl`, every launch muted (`APP_MUTE=1`) and
  driven to a screen by the launch doors (`APP_START_TAB`, `APP_START_ITEM`,
  `APP_AUTOPLAY`).
- **The phone was open the whole session, in landscape.** `devicectl device info
  displays` reports two displays: `LCD` (primary, 1398×2034 px, the OUTER
  display) and `LCD-1` (1878×2670 px native, the INNER display). Only one is
  active at a time.
- **Trap, now solved:** `devicectl device capture screenshot` with no display
  id captures the *primary* display, which is the outer one. With the phone open,
  the outer display is off and the frame is pure black, though the device is
  neither locked nor asleep (`lockState`: passcodeRequired false). The first
  capture (`01-home.png`, first version) was that black frame. Pass
  `--display-unique-id` of the display whose `active` is true; the inner one's id
  was `123-456-789`. An inner landscape capture is **2853×2007 px**; an outer
  capture would be 1398×2034 (portrait) or the reverse.
- **The outer display was never seen.** The owner did not close the phone
  during the session, so every frame below is the inner display in landscape.
  Nothing here describes the closed Duo or the inner display in portrait.

## 2. What each surface does today (inner display, landscape, regular width)

Every screen fills the display edge to edge, and the system's vertical strip
(status, toolbar items, tab bar) runs down the right edge. No surface is boxed,
and no content is clipped by the strip. Ear Drama gets this for free because it
has one `TabView` (`.sidebarAdaptable`) and `.toolbar` on each `NavigationStack`,
and no custom bar.

| Surface | Frame | What it does |
|---|---|---|
| Home | `01-home.png` (before), `10-home-fixed.png` (after) | Continue listening as full-width grouped rows; the Surprise `Label` sits in the strip's toolbar group. Before the fix, the strip ALSO held a Surprise tab (defect 1). |
| Browse | `02-browse.png` | Shows / Voices / Ear dramas picker, facet chips, the genre × decade matrix beside the tile wall: the regular-width layout. |
| Stations | `03-stations.png` | Station rows, full width. |
| Surprise | `04-surprise.png` (as a tab, before), `11-surprise-door-fixed.png` (as Home's push, after) | Head boards at a reading width with Play under each. |
| Search | `05-search.png` | The search field moves to the top right; the empty state is centered. |
| Library | `06-library.png` | Continue rows, full width. |
| A series (Tarzan) | `07-series.png` | Two-column header (picture, then name, years, the run chart, Follow, Share) and two columns of date-block episode rows. The strip collapsed to Back + the download menu with the tab button at the bottom: the system's own scroll-collapse. |
| An episode | `08-episode.png` | The series board, then the episode's name, Play / Add to queue / Download / Share in one row. |
| Now Playing | `09-nowplaying.png` | A page sheet centered over the episode (about 750 pt wide); close, queue and share in its own horizontal toolbar. The sheet does not use the display's width. |
| Script, cast, recorder | none | Not seen (§2a). |

### 2a. The script page and the recorder

**Not seen.** The recorder has no launch door; it is reached by taps (Browse →
Kind → Plays → a script → Start an ear drama → a part), which is what
`LayoutSweepUITests/testCreate` does without ever pressing Record. The run failed
with "Timed out while enabling automation mode": the Duo put up **"Enable UI
Automation — Touch ID to continue with XCTest"** (`12-after-uitest.png`). That is
the owner's step, once per device, in person. Until then, nothing on the Duo can
be tapped by a test, and the script page, cast sheet and recorder are unverified
on this device. To run it after the Touch ID step:
`xcodebuild test -scheme EarDramaUITests -destination id=00008160-001814623AA00036
-only-testing:EarDramaUITests/LayoutSweepUITests/testCreate` (with
`DEVELOPER_DIR` set to Xcode 27.1, and `DEVELOPMENT_TEAM`), then
`xcresulttool export attachments`. The Duo is not in the bench file, so
`tools/ios_uitest.py --device` does not know it yet.

## 3. Code audited against Apple's Duo checklist

Clean on the hard rules: no `UIScreen.main`, no `UIWindow(frame:)`, no device
orientation reads, no `UIRequiresFullScreen`, no layout computed once at launch,
all three iPhone orientations declared (`project.yml:118`). One idiom check,
`AccountStore.swift:221` (`deviceName` reports "ipad" or "iphone" to the account
service), labels a device and does not lay anything out, so it is not a Duo
defect; a Duo reports "iphone".

| # | Finding | Where | Status |
|---|---|---|---|
| 1 | **Surprise stood in the strip as a tab** beside Home's own Surprise button (two shuffle icons). The strip shows every tab whatever its `defaultVisibility(.hidden, for: .tabBar)`, and the tab was added on `hSize == .regular` alone. Archive Watch hit the same trap 2026-11-10. | `apple/iOS/ContentView_iOS.swift:33` (before) | **Fixed, seen on the Duo** (`10-home-fixed.png`: five tabs; `11-surprise-door-fixed.png`: the Surprise door hands Surprise to Home's push, Back + Shuffle in the strip). |
| 2 | **Two player toolbar items were bare `Image`s** (close `chevron.down`, transcript `text.quote`) with an accessibility label. The strip and its overflow need a `Label` (title + symbol). | `apple/iOS/PlayerViews_iOS.swift:74,89` (before) | **Fixed in code; NOT seen in the strip.** The player is a sheet at regular width, and its toolbar stayed horizontal in `09-nowplaying.png`. The close button still draws as a chevron. |
| 3 | Text-only toolbar items: Done / Cancel / Not Now / Make / Report in sheets (`TranscriptViews.swift:147`, `SharedPlaysViews.swift:369,432,440,548,554,611`, `InviteScreen.swift:71,300`) and `EditButton` on the queue (`ListScreens.swift:1448`). | as listed | Left alone. These are confirmation/cancellation actions in sheets, which keep a horizontal bar, and Apple's text-only rule applies to items that should move into the strip. |
| 4 | Full-bleed fills on the wide outer display. | `ArtViews.swift:34,62` | No defect. Every picture is a box of its own shape (`ShapedArt`, R11a); nothing fills a full-width hero, so the outer display's width cannot crop harder. |
| 5 | Fold-aware overlays (`reservedRegions(kind: .division/.occlusion)`). | none | Nothing to do yet: Ear Drama has no custom full-screen overlay. The future reader and studio (§5) are where it applies. |
| 6 | Multi-window. The scene manifest is generated (`project.yml:117`) with the CarPlay scene delegate (`CarPlay_iOS.swift:25`); no `UIApplicationSupportsMultipleScenes`. | `project.yml` | Owner call (Q3), not a defect. |
| 7 | Size-class branches keyed on "regular" (Series wide `ListScreens.swift:801`, Drama `:1162`, print bound `ArtViews.swift:105`, Plays `PlaysScreens.swift:262`, Radio `RadioScreen.swift:256`). | as listed | Correct behavior for the open Duo; `02-browse.png` and `07-series.png` show the regular-width layouts turned on. |
| 8 | **App Store builds use the iOS 26 SDK.** `appstore-build.yml:66,76` runs on `macos-26` and picks Xcode 26.6. Per Apple's table, an app built with the iOS 26 SDK runs **boxed** on the Duo. Everything above was seen in a Debug build from Xcode 27.1; TestFlight and App Store users see the boxed app until CI builds with Xcode 27.1. | `.github/workflows/appstore-build.yml` | Owner call (Q1). Not changed: editing that workflow got runs held as "malicious" before (memory, 2026-11-09). |

## 4. What was fixed

- `apple/iOS/ContentView_iOS.swift`: the Surprise tab is added only when
  `hSize == .regular` AND iOS 27's `isTabViewSidebarAvailable` is not false,
  read by a probe inside each tab's stack (the environment value means nothing
  outside a tab's content). The compact-width hand-back to Home keys on the same
  condition. iOS-DESIGN §3.1 was amended first.
- `apple/iOS/PlayerViews_iOS.swift`: the close and transcript toolbar items are
  `Label`s.

## 5. Design plan for the Duo

Apple's rule holds: no layout per pose. The outer display is compact width, the
inner is regular width, and each surface already measures its container. What
the Duo adds is room for a **primary + secondary pair** on the inner display, and
Apple's own example of that is a player with its Up Next list.

### 5.1 Now Playing + queue as an ArrangementView

Today Now Playing is a page sheet at regular width (`09-nowplaying.png`): about a
third of the inner display, the queue a further sheet away. On the open Duo:

- **Inner display (regular width):** Now Playing becomes the primary of an
  `ArrangementView` (SwiftUI wrapper over `UIArrangementViewController`), with the
  **queue** (`QueueViews.swift`) as the secondary: split side by side in
  landscape, stacked in portrait. Partly folded, Apple's tabletop rule applies:
  the picture and title on the top half, the transport (skip, play, sleep, speed)
  on the stable bottom half, the same controls as every other pose. The overlay
  arrangement separates the two across the fold for us; nothing reads the hinge.
- **Outer display (compact):** unchanged, the sheet as on every iPhone, the queue
  one tap away.
- **Folding keeps the person's place** (Archive Watch §2.8): closing the phone
  with the queue showing leaves the player open and the queue a tap away; it
  never dismisses the player or loses the queue's scroll position.
- iPad gets the same split for free, since the rule is regular width, not Duo.

### 5.2 The script reader and the recording studio

The read-along reader (owner, 2026-11-09: reading a script as the voices say it)
and the recorder (`RecordingScreen.swift`, `RecorderView`) are the Duo's best
fit, because a performer needs two things at once: the words, and the controls.

- **Open (inner display): script on one side, recording controls on the other.**
  The primary is the script, scrolled to the current line with the cue above and
  the performer's line marked; the secondary is the studio: record / stop / keep,
  the take list, the level, the mode control (Run through / Line by line / Step),
  the scene's cast. An `ArrangementView` split in landscape (script left, controls
  right, toward the thumb and the vertical strip); stacked in portrait (script on
  top, controls below). Partly folded and set down like a laptop, the script
  stands up on the top half and the controls lie on the bottom half, which is
  exactly how a person holds a script and a recorder.
- **Closed (outer display): the script alone**, the current line large, with the
  one control the performer cannot do without (record/stop) and everything else
  one tap away. A person reading along to a broadcast sees only the reader.
- **Today's recorder is a step toward this, not this.** `RecorderView` turns on
  three columns at a measured 840 pt (`RecordingScreen.swift:208`: scene rail,
  scene, aids rail) inside a 720 pt-wide dock. In the open Duo's landscape the
  content width moves between about 867 and 951 pt as the strip collapses and
  expands (Archive Watch §2.8), so it stays wide, but a threshold that close to
  the strip's range must never rebuild the controls while a take is recording.
  Inner portrait (about 626 pt) gives the narrow recorder.
- **The fold.** The reader is a custom scrolling view; its current line must stay
  out of `reservedRegions(kind: .division)` when partly folded, and the record
  button out of `.occlusion` (the inner camera while it is active). This is the
  first place Ear Drama needs those regions.
- **One seam.** The reader and the studio open the same script id through the
  one client seam the read-along memory calls for, so Now Playing's "read along"
  and the studio's script are the same view in a different arrangement.

## 6. What was not seen

- The **script page, cast sheet and recorder** (the UI Automation Touch ID
  prompt, §2a).
- The **outer display** (closed Duo), in any orientation.
- The **inner display in portrait**, partly folded, or tabletop.
- The player's toolbar items inside the vertical strip (fix 2): the player is a
  sheet at regular width, so its bar stayed horizontal.
- Playback audio (every launch muted), Split View, a second window.
- A Release or TestFlight build. Store builds are boxed today (§3, finding 8).

## 7. Owner questions

**Q1. Build App Store releases with Xcode 27.1 so the Duo gets the full-screen app?**
- **A (recommended).** Move `appstore-build.yml` to the newest released Xcode on
  GitHub's `macos-27` / `xcode-27` image, as Archive Watch did 2026-10-08. A
  27.0 build already fills most of the inner display; 27.1 is edge to edge. Done
  as its own change, with the last green copy kept to revert to if GitHub holds
  the run.
- B. Wait for Apple's April 2027 SDK floor to force it.

**Q2. Now Playing on the open Duo (and iPad).**
- **A (recommended).** Player + queue as an `ArrangementView` at regular width (§5.1).
- B. Keep the sheet everywhere.
- **Answered 2026-11-16: A, "Two panes."** At regular width the player and what
  plays next (the arc's next part, the queue reordered in place, a station's lineup
  when listening live) side by side; the phone keeps the sheet. Decision 080,
  iOS-DESIGN §5.3 and §5.9; built, §10.

**Q3. A second window on the open Duo and iPad** (two series side by side, or a
script beside a recording)?
- A. Yes, turn on multiple scenes. CarPlay's scene delegate already routes by role.
- **B (recommended for now).** Not until the reader and studio exist; then
  revisit, since the split in §5.2 covers the main two-things-at-once case
  inside one window.

**Q4. The studio closed.** When the Duo closes during a take:
- **A (recommended).** Keep recording; the outer display shows the script with
  record/stop, and nothing is lost.
- B. Pause the take on the fold.
- **Answered 2026-11-16: A, "Keep recording."** Decision 080, iOS-DESIGN §4.15
  "Folding during a take", PLAYS-DESIGN §2.9 rule 11; built, §10. The fold itself
  was not performed (no remote fold).

## 8. Outer display, seen 2026-11-14 (closed phone)

Frames: `build/qa/duo-2026-11-14/outer/` (1398x2034, display `987-654-321`), captured by
launch door with `devicectl device capture screenshot --display-unique-id <active display>`.
Home, Browse, Stations, Search and Library all fill the outer display; the status bar and
the five tabs sit in the right-edge strip, with Home's Surprise button in it. Nothing is
boxed or clipped on the left. Browse's chip row runs under the strip on the right (a scroll
peek, by the left/right rule). Library on a new device is five empty-state cards (the R2
audit's finding). The recorder was not seen: XCUITest screenshots capture the primary
(outer) display, which is black while the phone is open, and `ios_uitest.py` reported the
run PASS with two all-black frames: a harness defect (its blind-frame check missed them).

## 9. The fit-and-finish pass, 2026-11-16 (open display, landscape)

Owner, holding the first App Store submission: *"let's fix all of the interface
elements for the duo."* Frames: `build/qa/duo-audit/before/`, `after/` (local),
inner display `123-456-789`, Debug build from Xcode 27.1, every launch muted. The
rules this pass wrote are iOS-DESIGN §3.6; each defect below names its rule.

| # | Before (measured on the 951 pt landscape frame) | Rule | After |
|---|---|---|---|
| 1 | Record: the Yours card 20 pt from the left and 0 pt from the safe area (13 pt from the strip); Today's Scene 16 pt inside it on both sides | §3.6a, §3.6b | both 24 pt from each edge, one edge |
| 2 | Home: three left edges (the Continue card 20 pt, On the air 36 pt, its heading 40 pt) | §3.6b | boxes on the card edge, words on the heading's |
| 3 | Browse: scope and chips 16 pt, count and field 20 pt, tiles to 13 pt from the strip | §3.6a | all 24 pt |
| 4 | Library, Stations, Account, Downloads: cards 20 pt / 13 pt from the strip | §3.6a | 24 pt / 24 pt from the safe area |
| 5 | Episode: four left edges (board 36, title 36, transcript card 20, On the air 40) | §3.6b | board on the card edge, title and buttons on the heading's |
| 6 | Account: Sign in buttons 820 pt wide; Google's a 58 pt capsule beside Apple's 44 pt rectangle | §3.6d | 375 pt, both 44 pt, `Radius.control` |
| 7 | Cast sheet column (340 pt): board 16 pt in, rows 20 pt in, the switch, sign-in and book buttons touching the divider | §3.6e | 375 pt, every row 16 pt from both edges |
| 8 | Studio beside the script: the panel's cards flush against the reader | §3.6a | 24 pt |
| 9 | Reader Text: a 650 pt medium sheet, three controls, two-thirds empty | §3.6c | a popover on the Text button (a sheet on a phone) |
| 10 | Confirmations on whole views: Downloads Remove / Remove All, Remove a published line, Delete Unused Takes (code; not drawable signed out with no downloads) | §3.6c | each on its button |
| 11 | (found while fixing) a chip row on the card edge was clipped by the section's rounded corner | §3.6b | rails start on the words edge |
| 12 | (found while fixing) a modifier wrapped outside the row traits turned Record's chip row into a card | — | measured inside the traits |

Judged right as they were: the series and person pages (`WidePage`, already 24 pt;
the person's shelf peeks under the strip by the left/right rule), Search, Surprise
(a centered 720 pt reading column), the sleep timer (on its button), the series
Download menu, Contents / Search / Voices / Marks and the voice picker (long
lists, medium sheets). Now Playing stays a page sheet: the player and queue side
by side (§5.1, Q2) needs iOS-DESIGN §5.3 amended first. Seen in passing, not a Duo
defect: Surprise's evening board reads "CBS · WTOP ·" with a trailing separator.

Not seen this pass: anything signed in (the Duo is signed out; Block, Delete
Account and a shared play's lines), the outer display (the phone stayed open), the
inner display in portrait or partly folded, and Downloads with a download in it.
XCUITest refused the Duo ("Timed out while enabling automation mode": UI
Automation wants a person's Touch ID), so frames below the first screen came from
the DEBUG door `APP_SCROLL_Y`.

## 10. Two panes and the fold, 2026-11-16 (Decision 080)

- **Now Playing (Q2)**: at regular width a `fullScreenCover` holding an
  `ArrangementView` split (`PlayerSheet_iOS(panes:)`, `PlayerQueuePane`); the
  presentation is latched when the player opens (`PlayerPresenter`), so a fold never
  dismisses it. Seen on the open Duo (inner display, landscape: the player on the left,
  Queue on the right, Close, queue, share and transcript in the strip), on the iPad Pro
  12.9 (the same two panes) and on the iPhone 12 (the sheet, unchanged). Frames local.
  Not seen: a queue with items, an arc's next part, the live lineup, portrait, folded.
- **The fold mid-take (Q4)**: `EngineLiveAudio` restarts on
  `AVAudioEngineConfigurationChange` and an interruption's end and puts its tap back on the
  same `CaptureSink`, which retargets to the new format and keeps every sample; a cast
  reading stops with the reader's loader, not on the 860 pt switch. `FoldContinuityTests`
  (2 tests, the mutant that drops a changed-format buffer seen to fail both). The studio
  pane was seen on the open Duo (stub engine, Recording 0:19). **Not physically tested:**
  closing the Duo during a real take, the outer display's dock in that moment, and whether
  a fold reconfigures the audio hardware at all.
