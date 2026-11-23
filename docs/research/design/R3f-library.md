# R3f: Library, organized (proposal, 2026-11-23)

A proposal, not a build: the owner chooses. Nothing in the product changed.

**The ask**, owner, 2026-11-23, verbatim: *"the library tab on all of the apps has become a kichen sink aproach to putting everything into an undesigned list of items. Let's do some serious design work on the library page to make sure it is well organized and easy to understand. Multiple of the fields at the top can be collapsed (Continue, Queue, and Following all seem to be the same thing and empty fields don't do anything for a user except to make them scroll through more material before they get to what they want to use)."*

**The standing rule it has to keep** (owner, 2026-11-22; Decision 086 amendment; WEB-DESIGN §4.11a): *"I don't think we need a settings page, but we should continue to iterate upon the library page to make it serve all of the given purposes we need."* Library stays the app's settings home. And positioning (owner, 2026-11-16): listen AND make, equal weight.

Skills applied: `learning-orientation-design`, `learner-experience-design` (rules 2, 4, 5, 6), `mobile-first-density-design` (rules 5, 6; the settings-dump and tab-inside-tab anti-patterns), `universal-feature-states`, `native-platform-first`, `catalog-experience-design` (rules 3, 5, 11), `binding-design-doc-discipline`.

Frames: `docs/research/design/img/library/`. The mock that drew the directions: `docs/research/design/library-mock/mock.html` (`?d=A|B|C&u=new|heavy&wide=1&theme=dark&scope=listen|make`), using the app's own `css/styles.css` tokens and fonts. Presentation for the owner: `docs/research/design/library-directions.html`.

---

## 1. Audit: what Library is today

### 1.1 Frames captured

| Frame | What it shows |
|---|---|
| `now-web-375-new.png` | Web, 375 px, a new listener, whole page (3,297 px tall). Headless Chrome on this Mac. |
| `now-web-375-heavy.png` | Web, 375 px, the fit tool's heavy fixture (`tools/web_fit_library.py` FULL), Continue tab. |
| `now-web-1440-heavy.png` | Web, 1440 px, same fixture (half scale). |
| `now-android-pixel8a.png` | Android, the real Pixel 8a (debug 1.0.161, lease `pixel`, muted door), five frames scrolling top to bottom. |

Not captured: **iPhone Duo, iPad, Mac, Apple TV and the TVs.** No device lease was held by anyone, but the iOS capture path needs the UI-test tier (`tools/ios_uitest.py`) and a build; this proposal step did not run it. The Apple and tvOS rows below come from the code (`apple/Shared/ListScreens.swift` `LibraryScreen`, `apple/tvOS/ContentView_tvOS.swift` `LibraryScreen_tvOS`), not from a frame.

### 1.2 Inventory, every platform, top to bottom

| # | Web (`js/app.js` `renderLibrary`, `index.html`) | iOS / iPadOS / macOS (`LibraryScreen`) | Android (`LibraryScreen.kt`) | tvOS (`LibraryScreen_tvOS`) |
|---|---|---|---|---|
| 1 | Five tabs: Continue, Queue, Following, History, Ear dramas (one shows at a time; opens on Continue even when empty) | "Nothing played yet" + Browse, only when everything is empty | **Account row** | "Nothing played yet" + Browse when empty |
| 2 | The chosen tab's rows, or its caption + Browse | **Continue** (header always; caption when empty) | **Voices, whole**: Kokoro download, Speed, every device voice with tick, up, down, Hear | **Continue** (header + caption when empty) |
| 3 | Account row (Sign in) | **Queue** (header always) | Export my data | **Queue** (header + caption) |
| 4 | Listen together ("Join a room") | **Following** shelf (header always) | Listen together | **Following** shelf or header + caption |
| 5 | Export my data · History (CSV) | **History**, up to 100 rows inline (header always) | Show a reading (TV only) | Shared ear dramas |
| 6 | **Voices, whole** (same parts as Android) | **Downloads** (one row, or header + caption) | "Nothing played yet" when empty | Show a Reading |
| 7 | Site footer (Credits, Privacy, For schools, Security, Take-down, Delete) | **Ear dramas** (header always) | **Continue** (header always) | Account |
| 8 | | **Classes** (signed in: rows, Make a Class, Join a Class) | **Queue** (header always) | Site pages (Credits, Privacy, Take-down) |
| 9 | | Account (one row; Export lives inside its screen) | **Following** (header always) | |
| 10 | | **Voices, whole** (iOS, macOS) | **History** (header always, every finished row) | |
| 11 | | Site pages (iOS) | **Downloads** (one row, or header + caption) | |
| 12 | | | **Ear dramas** (every production, one row each) + Classes | |
| 13 | | | Site pages | |

### 1.3 What backs Continue, Queue and Following

They are three different stores, but one question to the person: *what do I listen to next?*

| Section | Data | Web | Apple | Android | Also shown |
|---|---|---|---|---|---|
| **Continue** | Episodes with a saved position, not finished (history entries) | `Store.inProgress(100)` | `ListeningHistory.inProgressIDs` | `user.inProgress(limit = 100)` | **Home's Continue** on every platform (WEB §4.2 item 3, iOS Home `continuingRows`): Library repeats it in full |
| **Queue** | An ordered list the person built (add, move, remove) | `Store.queue()` | `ListeningQueue.items` | `user.queue()` | The player's "Next in queue" line (Decision 067 decides what plays next) |
| **Following** | Followed series keys, drawn as show tiles | `Store.follows()` | `FollowedSeries.followedKeys` | `user.followed()` | A series page's Follow button; nothing else reads it. Following never produces an episode: the catalog is archival, so there is no "new episodes" feed, and a followed show is today only a bookmark |

So the owner is right in the sense that matters: to a listener, Continue and Queue are both "what's next" (one is started, one is chosen), and Following is the shows that "what's next" would come from. Continue also duplicates Home.

### 1.4 Findings

1. **Empty sections are kept on purpose, by rule.** iOS-DESIGN §4.6, tvOS §4.6 and ANDROID §4.6 say "every section keeps its header, so a section with rows and one without read as one set", with a caption each. A new listener on iOS scrolls past six headers and six captions, plus "Nothing played yet", before Account. This is the rule the owner is now rejecting; the rule changes first.
2. **Voices swamps Library.** On the web in a Mac browser, Voices lists every installed system voice (about fifty on this Mac): it is about 2,600 of the page's 3,297 px, roughly 80% of Library, for a person who has never opened a play (`now-web-375-new.png`). On the Pixel, Voices is **the first thing on screen**, above Continue (`now-android-pixel8a.png`), which breaks Decision 086's own amendment ("an app-wide preference is a rare job and sits at its foot").
3. **The made-by-me side is a flat dump.** On the Pixel, Ear dramas is ten rows and **nine of them are "The Albany Depot"** (separate productions of one play, "7 of 166", "18 of 166"...), with nothing to tell them apart. Classes sit beside them on Apple and Android, with Make a Class and Join a Class buttons always drawn. Library's Ear dramas also repeats Record's Yours (WEB §4.15 item 1).
4. **History is rare but heavy.** Apple and Android draw up to 100 finished episodes inline, above Downloads, Ear dramas, Account and Voices. People open history to find one thing, occasionally; it does not need to be the body of the page.
5. **The rare jobs are scattered differently on each platform.** Export is a Library row on web and Android but inside the Account screen on Apple; Listen together is a Library row on web and Android only; the site pages are in Library on iOS, Android and tvOS, in the footer on web, in the menu bar on Mac; Voices is at the foot on web and Apple and at the top on Android. Same verbs, no common order.
6. **The web hides the person's things behind five tabs.** One tab at a time means a heavy user cannot see that they have an ear drama waiting while looking at Continue, and a new user lands on an empty Continue tab with four more empty tabs to discover. Five equal tabs inside a tab is the `mobile-first-density-design` tab-inside-tab anti-pattern.

### 1.5 Each section: purpose, when empty, how often, duplicates

| Section | For | Empty when | How often needed | Duplicates |
|---|---|---|---|---|
| Continue | resume a started episode | nothing started | daily for a listener | Home's Continue; same question as Queue |
| Queue | play my chosen order | nothing queued (most people) | some listeners, often | the player's Up next line |
| Following | get back to shows I like | nothing followed | weekly | a bookmark list; feeds nothing |
| History | find something I finished | nothing finished | rarely | Export CSV carries the same rows |
| Downloads (Apple, Android) | manage storage, offline | nothing downloaded | rarely | none |
| Ear dramas | open my productions | nothing recorded or joined | often for a maker | Record's Yours |
| Classes | open a class I teach or am in | not signed in, or none | weekly for a teacher | none |
| Your parts | parts waiting on me | none waiting | when asked | today reached from the Reading menu, not Library |
| Account | sign in, sync, delete | always present | rarely | none |
| Voices | default voices for plays | always present | once, then rarely | the cast sheet's Better voices points here |
| Listen together | join a room | always present | rarely | the player's own Listen together |
| Export | take my data | always present | rarely | Apple keeps it in Account |
| Site pages | credits, privacy, take-down | always present | rarely | web footer, Mac menu |

---

## 2. Research: how listening and reading apps organize a personal library

| App | How "in progress / up next / subscribed" is handled | Empty states | Where account, downloads and preferences live |
|---|---|---|---|
| **Apple Podcasts** | iOS 27.2 splits the old Up Next into **New Episodes** ("only ever show you the latest episodes for each show you follow") and **Continue Playing** ("a central hub for all episodes you've started, but haven't yet completed") ([9to5Mac, 2026-10-02](https://9to5mac.com/2026/10/02/ios-27-2-gives-apple-podcasts-the-big-fix-ive-wanted-for-years/)). The change came after complaints that followed shows crowded out the hand-built queue ([Apple Community](https://discussions.apple.com/thread/256155269); [MacRumors forum](https://forums.macrumors.com/threads/ios-26-2-adds-three-new-features-to-podcasts-app.2470478)). | Library rows (Shows, Saved, Downloaded) are links; an empty one is still a row, never a block. | Account behind the profile picture; downloads a Library row; no settings tab in the app. |
| **Spotify Your Library** | One list with filter chips (Playlists, Podcasts, Albums, Artists, Downloaded) and up to four pins ([Spotify newsroom](https://newsroom.spotify.com/2021-04-29/listeners-can-explore-their-spotify-collections-faster-and-easier-with-a-new-your-library-2/); [community moderator on pins](https://community.spotify.com/t5/Your-Library/New-Your-Library-view-iOS-amp-Android/m-p/5212772/highlight/true)). Users complained it "muddled my music and podcasts all together into a big list" ([MacRumors](https://www.macrumors.com/2021/04/29/spotify-updated-your-library-filters-grid-view/)). | A chip only appears for a kind you have. | Settings behind the profile picture, out of the Library list. |
| **Pocket Casts** | Up Next is the player's queue; Filters (New Releases, In Progress) are separate ([support: queue](https://support.pocketcasts.com/article/playing-episodes-and-managing-your-queue-ios)). | Hidden until used. | A **Profile** tab holds Downloads, Files, Starred, History and the Settings gear ([Downloads](https://support.pocketcasts.com/knowledge-base/manage-episode-downloads/), [Files](https://support.pocketcasts.com/article/files-ios)). |
| **Overcast** | One main screen: Playlists (Queue, All Episodes, In Progress, Downloaded, Starred) above the subscribed shows ([MacStories](https://www.macstories.net/reviews/overcast-redesign-enhances-podcast-navigation-with-an-emphasis-on-playlists-and-recent-episodes/); [Podfeet, 2024](https://www.podfeet.com/blog/2024/07/overcast-new-version/)). In progress and queue are views of one list. | Built-in playlists only show when they have episodes. | Settings one button from the main screen; per-show settings on the show. |
| **Audible** | Library filters: All, Not started, **In progress**, Downloaded, Finished ([Audible help](https://help.audible.com/s/article/manage-your-library)). | A filter with nothing just shows nothing. | Profile tab, settings behind its gear ([player settings](https://help.audible.ca/s/article/view-player-settings)). |
| **Apple Books** | Home has Continue; Library has collections: All, Want to Read, Finished, plus the person's own ([Apple support](https://support.apple.com/guide/books/ibks33867842/mac)). Finished is filled automatically and dated. | A collection is a row with a count. | Account and settings behind the profile picture. |
| **Libby** | **Shelf** holds loans, holds, magazines and notices, with **Timeline** as borrowing history inside it; tags are separate ([Libby help: navigating](https://help.libbyapp.com/6011.htm)). | Each shelf section only when it has items. | A separate **Menu** for settings, cards and help (same page). |

**What carries over**:

- Everyone with both separates *started* from *chosen*, and Apple just re-learned that *followed* should not silently fill *chosen*. The merge that works is one list where each row says **why** it is there (resumed, queued, next in a followed show), with the person's own order on top of anything automatic.
- Nobody draws an empty section as a block. A kind with nothing is either absent (Spotify chips, Overcast, Libby) or a single row with a count (Apple Podcasts, Apple Books).
- Every one keeps preferences **out of the collection list**: behind the profile picture, a Profile tab or a Menu. Ear Drama's owner has ruled out a Settings page, so the equivalent here is **one compact group of rows at Library's foot**, each opening its own place, instead of Voices drawn in full.
- History is a rare drawer (Libby's Timeline, Pocket Casts' History in Profile, Apple Books' Finished), never the body of the page.

---

## 3. The directions

All three keep: the one row grammar (window, title, sub, length, action; `catalog-experience-design` §11), a show tile shelf, no counts of anyone's attention, no streaks, nothing ranked by engagement (`learner-experience-design` §5, `values-based-feed-ranking`), and the same **preferences group** at the foot.

**The shared foot (all directions)**: one group of rows, each a single line with its current state, each opening its own place: **Account** (Sign in / Synced 3:42 PM), **Voices** (Kokoro · 1.0×, or Device · 1.0×), **Listen together**, **Export my data**, **About Ear Drama** (Credits, Privacy, For schools, Security, Take-down, Delete an account). Voices stops being drawn in full on Library: its row opens Library's own Voices place (`?view=library&section=voices` keeps working and lands there). On a TV: Account, Show a Reading, About; no Voices, no Export.

### Direction A (recommended): Up next, Made by you, then the back pages

One page, no tabs, sections only when they have something:

1. **Up next**: one list, merging Continue and Queue, and taking Following's job. In order: started episodes (the progress bar under the title, "18 min left"), then the person's queue in their order (drag to reorder, "Queued" in the sub line), then one row per followed show for its **next episode** ("Next in Lux Radio Theater"), by a published rule: the earliest-aired episode of that show after the last one the person finished (the show's first episode if none). At most five rows, then "All 14". The row says why it is there, so the rule is visible and the person's order always comes before the automatic rows.
2. **Made by you**: productions **grouped by play** ("The Albany Depot · 8 productions · newest 18 of 166 lines", opening the play's productions), then **Your parts** ("2 waiting on you") and each **class** ("Room 12 Readers · 3 takes to hear") as single lines. "Record" in the heading. Absent when there is nothing.
3. **Shows you follow**: the show tile shelf, "All 5". Absent when there is nothing.
4. **History** and **Downloads**: one line each with a count, opening their own place. Absent when empty.
5. **Account and preferences**: the shared foot.

**Brand-new user**: the heading, one sentence ("What you play, queue, follow or record gathers here."), **Browse** and **Record a play** side by side (listen and make, equal weight), then the five foot rows. The whole page fits one phone screen (`A-375-new.png`: 594 px at 375 px wide, against today's 3,297 px web page).
**Heavy user**: Up next (5 + All), Made by you, the shelf, two lines, the foot (`A-375-heavy.png`, dark `A-375-heavy-dark.png`). Wide (1440 px, iPad, Mac): two columns, Up next and Made by you on the left, the shelf, the lines and the foot on the right (`A-1440-heavy.png`, `A-1440-heavy-dark.png`).

**Why recommended**: it answers both of the owner's points directly (one "what's next" list; empty sections gone), gives making its own named section of equal standing instead of a tab or a flat dump, and is the plainest page a designer could redraw from one paragraph (the Gruber test). It turns Following from a bookmark into something that does work, without inventing a feed: one row per show the person chose, by a rule they can read.

**Risks**: the "next episode of a followed show" rule needs a published order per show (air date, else log number); undated shows would fall back to log order or contribute nothing (open question 1). Home's Continue then repeats the top of Up next (open question 3).

### Direction B: Listening | Making, two scopes over one foot

A two-way segmented control at the top, **Listening** and **Making**, equal weight, remembered per device:

- **Listening**: Up next (started, then queued; Following is not merged in), the Shows you follow shelf, History and Downloads lines.
- **Making**: **Waiting on you** (parts someone else's production needs from you, with the part and its lines), **Productions** grouped by play, **Marks** ("In 3 scripts"), **Classes**.
- The shared foot under either scope.

**Brand-new user**: the control, one sentence and one button for the chosen scope (Browse, or Record a play), then the foot (`B-375-new.png`). **Heavy user**: `B-375-heavy-listen.png`, `B-375-heavy-make.png`.

**For**: the clearest statement of the dual purpose; a maker never scrolls past listening. **Against**: a segmented control inside a tab is the tab-inside-tab pattern this audit just faulted on the web (two scopes is gentler than five, but still hides half the person's things), and it keeps Following as a separate thing rather than merging it.

### Direction C: one timeline, newest first

Libby's Timeline as the whole page: a **Resume** card for the most recent started episode, then **Queued** (the person's order), then **Recent**: one chronological list of everything the person did, grouped by day, each row tagged with its verb (Heard, Finished, Recorded, Followed, Queued).

**Brand-new user**: one sentence, Browse and Record a play, the foot (`C-375-new.png`). **Heavy user**: `C-375-heavy.png`.

**For**: no sections to understand at all; listening and making interleave as they happened. **Against**: to find a production you scroll through what you heard; Following has no home other than a day it happened; the same episode appears twice (queued, then heard). It is a history with a resume button, and history was the rarest need in the audit.

---

## 4. What moves where (Direction A)

| Today | Under A |
|---|---|
| Continue (section or tab) | Up next, first rows (progress bar) |
| Queue (section or tab) | Up next, after started rows (drag handle) |
| Following (section or tab) | Shows you follow shelf, plus one "Next in {show}" row per show in Up next |
| History (inline, up to 100 rows) | One line with a count, opening History |
| Downloads (row or header + caption) | One line, absent when empty (Apple, Android) |
| Ear dramas (flat, one row per production) | Made by you, grouped by play |
| Classes (with Make and Join always drawn) | One line per class in Made by you; Make a class and Join a class move into Record's class door and the class page (open question 5) |
| Your parts (Reading menu only) | Also a line in Made by you, only when something waits |
| Account row (top on Android, foot elsewhere) | Foot, first row |
| Voices (drawn in full; top on Android) | Foot row with its state, opening Library's Voices place |
| Listen together (web, Android) | Foot row on every platform that has rooms |
| Export (Library on web and Android; Account screen on Apple) | Foot row everywhere (Apple also keeps it in Account) |
| Site pages (Library or footer or menu) | Foot row "About Ear Drama" in Library (web keeps its footer; Mac keeps its menu) |
| Show a Reading (TV) | Foot on a TV |
| "Nothing played yet" + Browse | One sentence with Browse and Record a play, only when Up next, Made by you and the shelf are all empty |
| Every empty section's header + caption | **Removed** |
| The web's five tabs | **Removed** |

**Removed outright**: the empty-section captions ("Episodes you stop partway through wait here." and the five others), the web's Library tabs, Classes' always-drawn Make and Join buttons in Library, and Voices drawn in full on Library.

**States** (`universal-feature-states`): loading draws skeleton rows in Up next's place only; offline keeps everything on the device listing and dims Account's Sync now; a section that fails to read (shared productions) shows its one problem line with Try again in its own place, never blanking the page; an empty section is absent, and an entirely empty Library is the one sentence with two buttons.

**Per platform, same verbs, native idiom**:

- **Web**: one scroll, `<section>` per part with an `h2`; the foot as a list of links; Voices as its own place under `?view=library&section=voices`; queue reorder keeps move up and move down buttons.
- **iOS / iPadOS**: a `List` with sections present only when non-empty; Up next rows `onMove` for queued ones; the foot as an inset-grouped `Section` of `NavigationLink`s (Voices pushes a `List` in Library's stack); iPad uses two columns as the wide frame.
- **macOS**: the same `List`; Voices pushes in Library's stack; About stays in the menu bar too.
- **tvOS**: Up next and Shows you follow as focus shelves; Made by you shows only shared ear dramas (a TV records nothing); foot: Account, Show a Reading, About.
- **Android**: a `LazyColumn` with the same order; the foot as `ListItem`s; Voices as a pushed screen in Library's back stack. On a TV the same, without Voices and Export.

## 5. Learning-orientation check (Direction A)

1. **Deepen understanding**: each Up next row names why it is there (started, queued, next in a show you follow), so the person learns how the list is made; nothing is "for you".
2. **Invite participation**: the person's queue order always leads the automatic rows; following a show is the person's choice and the only thing that adds rows.
3. **Support agency**: preferences are one tap away by name, and Voices keeps every control the person has today.
4. **Clarity over cleverness**: five parts in a fixed order, each absent when empty; one rule for "next episode" stated in the docs and computed the same everywhere.

A count on a line ("42 episodes") is a size, not a score: it tells you what opening the line will show. No streaks, no totals of listening time.

## 6. Open questions for the owner

1. **Followed shows in Up next**: should each followed show add one "Next in {show}" row (A), or should Following stay only as the shelf (A without that row, or B)?
2. **Voices as its own place under Library**: is a Voices page reached from Library's foot acceptable, given "no Settings page"? The alternative is an inline disclosure on Library that opens Voices in place.
3. **Home's Continue**: keep it (it would repeat Up next's first rows), shorten it to the one episode you were last playing, or drop it now that Library leads with Up next?
4. **Made by you vs Record's Yours**: should Library hold everything you made (unfinished, finished, parts, classes) while Record keeps only unfinished productions, or should one of them point to the other?
5. **Classes' Make and Join**: move them out of Library (Record's class door and the class page), or keep them as one "Classes" line in Made by you?
6. **The foot's heading**: "Account and preferences", "You", or no heading?
7. **Up next's length before "All"**: five rows, or as many as there are?

## 7. If the owner chooses A: docs that change first

Per `binding-design-doc-discipline`, the docs change before any code: WEB-DESIGN §4.7, §4.11, §4.11a and §7.1a; iOS-DESIGN §4.6, §4.10, §4.10a and §7.4; macOS-DESIGN §4.3 and §4.4; tvOS-DESIGN §4.6, §4.9 and §4.9a; ANDROID-DESIGN §4.6, §4.11 and §4.11a; PLAYS-DESIGN §2.8 rule 11 (Voices' place); a new DECISIONS entry (Library's order, the empty-section rule, the next-episode rule) amending 086's amendment; then PARITY.md. The fit tools (`tools/web_fit_library.py`, `GrammarRenderTest`) change their checks from "an empty section has a caption" to "an empty section draws nothing".
