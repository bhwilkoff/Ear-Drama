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
