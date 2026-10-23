# Ear Drama Android design (binding)

**Binding.** Quote the rule number before proposing any new screen,
route, sheet, tab, or car or TV surface on Android. If no rule fits,
propose a new rule first, then the feature
(`binding-design-doc-discipline`). Companion to `PARITY.md`,
`docs/CATALOG-CONTRACT.md`, `docs/WEB-DESIGN.md`, `docs/iOS-DESIGN.md`,
`docs/macOS-DESIGN.md`, and `docs/tvOS-DESIGN.md`. Where a rule here
inverts a sibling's, §11 says so.

Seeded 2026-10-22 from `docs/templates/ANDROID-DESIGN-template.md`. It
describes what is built in `android/app/src/main/java/com/example/appname/`
(`ui/`, `playback/`, `navigation/`, `data/`) and `android/wear/`. The
production lessons this doc does not restate live in
`android-production-gotchas`; the TV focus mechanics in
`androidtv-compose-focus`.

## §1 Principles

- **§1.1 Android feels like Material 3.** The web's verbs
  (`docs/WEB-DESIGN.md` §4) in Material's own components:
  `NavigationSuiteScaffold`, `TopAppBar`, `ListItem`, `FilterChip`,
  `DockedSearchBar`, `ModalBottomSheet`, `DropdownMenu`, and system and
  predictive back. Never port iOS chrome.
- **§1.2 Compose only, one Activity.** `MainActivity` hosts `AppRoot`;
  no Fragments, no AppCompat.
- **§1.3 One shared data plane.** Screens read the served projection
  through `CatalogDatabase` via `rememberCatalogQuery` (`ui/Components.kt`)
  and the network through `ApiClient`; a screen never opens SQLite or
  OkHttp itself.
- **§1.4 Depth is at most two from a tab**: tab, series, episode. A
  season is a scope; the player is a sheet. In Plays it is tab, cast
  sheet, part: casting a play replaces the script page with its cast sheet.
- **§1.5 Only essential words on screen** (AGENTS.md); no list or blurb
  written by the app (R13).

### §1.6 The shared rules as they bind Android

The common text is in `docs/WEB-DESIGN.md` §4.5, §5, and §8 and
`docs/research/05-design-research.md` §9. On Android:

- **R1** the date leads every episode row (the `ListItem` overline in
  `EpisodeListItem`) and every card, as the catalog stores it
  (`1943-02-24`, `formatAirDate`) in the tabular `bodySmall`; episodes
  run oldest first.
- **R5** copies are Versions on Detail, each with its own Play, the rank
  0 copy the default.
- **R11** cards are typographic `OutlinedCard`s (date, title, series);
  no node, card, or notification carries invented art.
- **R12** brand colors are chrome; dynamic color is off by default.
- **R13** shelves are the catalog's `meta.listenShelves`, in order
  (contract §5.1; the same list and titles on every platform): This day
  in radio on the person's own date, then each published genre's ids as
  given. An older catalog without the key falls back to the rules run on
  the device (This day in radio, one shelf per genre the catalog names).
- **R15 and Decision 061: loudness by cutting.** `LoudnessLevel.volume`
  (`playback/LoudnessLevel.kt`) gives each queued item `-21 - I` dB,
  peak-clamped at -1 dBTP and never above unity, for the default copy
  only; the sleep fade multiplies it.
- **R16** "Automatic transcript" (`Transcript.LABEL`) on Detail, the
  player, and the transcript screen's title.
- **R17** the car's four roots are the phone's tabs reduced (§9.1).
- **R18** speed, sleep, and skip live on the player sheet.
- **R20** the sleep menu lists "End of this episode" first, then 15, 30,
  45, and 60 minutes (`SleepTimer`); it fades, and once fired the queue
  stops.
- **R21** every icon button has a `contentDescription`; §7.3.
- **The rights line** is the published `meta.rightsLines` words
  (contract §5.5, `CatalogDatabase.rightsLines`), the contract's own
  strings for a catalog that predates the key: "No rights claim known.
  Removed on request." for an unclaimed recording, never public domain;
  a clean basis with no words shows no line (`DisplayVocabulary.rightsLine`).
- **R9, R10, R14 on the Radio tab** (§4.10): a gap is drawn as a gap,
  the slot on the air is read from the file's UTC instants on the one
  clock (`RadioClock.onAir`, `radio/Tonight.kt`, golden against
  `js/api.test.js`), and nothing plays after the evening.
- Not built anywhere yet (data plane first): R2, R3 arc ends, R4, R6,
  R7, R8.

## §2 Data plane

- **§2.1 One read path.** `CatalogDatabase` over the bundled SQLite
  driver; `rememberCatalogQuery` re-runs on `dbVersion`, on its keys,
  and, with `watchUser`, on the listener's own records.
- **§2.2 The projection decides.** Rights, rank, the transcript gate,
  and loudness numbers arrive in the served database; the client adds no
  filter beyond the contract's `recommendAnd` on shelves and the queue.
- **§2.3 A person's listening stays on the device** (`UserStore`,
  `DownloadStore`) unless they sign in (Decision 057). Signed in, history,
  follows, and the queue sync through the Worker (Decision 063,
  `account/SyncEngine.kt`): the first pass sends the signed-out history
  to `/v1/sync/merge` once, later passes `PUT` only rows changed here, and
  every pass then reads `?since=` and applies last write wins per row. A
  removal is a marker (`deleted`, `following = 0`), never a missing row.
  Downloads never sync.
- **§2.4 The Worker rides the one Ktor client** (`ApiClient.client`)
  through `account/WorkerApi.kt`, which refreshes the session before every
  call when under five minutes remain, one refresh at a time, and gives a
  401 one refresh and one retry before it surfaces. The session and the
  account's state are one record, AES-GCM encrypted under an Android
  Keystore key (`KeystoreSessionStore`, `noBackupFilesDir`), never
  SharedPreferences. The Worker's URL and the Google and Apple client ids
  are gradle properties (`EARDRAMA_*`), `REPLACE_WITH` placeholders in
  git; while one is a placeholder its sign-in is not offered.

## §3 Navigation shell

- **§3.1 Six tabs, hard set**: Listen, Series, Radio, Plays, Search,
  Library (`Tab`, `navigation/Routes.kt`), with Material icons
  Headphones, Layers, Radio, TheaterComedy, Search, and Bookmarks (Radio
  takes the radio, as on Apple; Series takes Layers, the nearest to
  Apple's `square.stack`). Radio follows Series, as on the web and Apple.
  Plays records, so a TV shows the other five (`Tab.onTelevision`;
  PLAYS-DESIGN §2: TVs play back only). `NavigationSuiteScaffold` draws a
  bar, a rail, or a drawer by window size; on a phone that is one
  `NavigationBar` of six items, about 57 dp each at 360 dp ("Library",
  the longest label, is about 42 dp in `labelMedium`), every label whole
  at the default font size (measured from the type, not yet on a device). Material's guidance is three to five; the
  six-section question is the owner's (§12, SCRATCHPAD item 12), and no
  destination is dropped meanwhile.
- **§3.2 One route registry.** Every destination is a case of the sealed
  `Route` (Navigation 3 `NavKey`): the five roots, `Series`, `Episode`,
  `Transcript`, and the plays' `Script`, `Production`, and `Recording`,
  resolved in one `entryProvider` in `ui/AppRoot.kt`. Radio's root is
  `Route.Radio`; a slot opens the same `Episode` route.
- **§3.3 One back stack per tab** (`rememberNavBackStack`). System back
  and predictive back pop within the tab
  (`android:enableOnBackInvokedCallback="true"`); tapping the selected
  tab returns it to its root; another tab keeps its stack.
- **§3.4 Deep links and doors land in the inbox** that `MainActivity`
  posts to and `AppRoot` drains in one `LaunchedEffect`. `DeepLink.parse`
  reads DEEP_LINKS.md's shapes, `eardrama://` and its
  `https://eardrama.org` twin alike: `series/{key}`, `episode/{id}`,
  `search?q=`, `library`, and `/?room=` (§4.13); anything else opens nothing. Both manifest
  filters stay off until the store records and Play's fingerprint exist.
  The one filter on is `eardrama://oauth/apple`, Sign in with Apple's
  return, which `MainActivity` hands to the account (§4.11) before the
  inbox and which opens no screen.
- **§3.5 A push never stacks a duplicate** (`navigateTo`,
  `navigation/BackStack.kt`; every push in `AppRoot`, the inbox's
  included). A route already on the tab's stack is popped back to
  (popUpTo, singleTop when it is the top): Detail's series link from a
  series page returns to that page, and the player's Open episode from a
  transcript returns to its Detail. A transcript is Detail read, not a
  level of §1.4, and one opened over another replaces it, so a stack
  ends in at most one.

## §4 Surfaces

- **§4.1 Listen** is a `LazyColumn` of shelves, each a header over a
  `LazyRow` of 220 dp cards: Continue listening, then the published
  shelves in order (R13). A shelf with no rows is not drawn.
- **§4.2 Series browse** is one row of `FilterChip`s over a paged list
  of series (200 at a time), each one line of years and count: the sort
  and the network as dropdown chips (a `DropdownMenu`), then the decades,
  then the genres. The sort is the web's three, "A to Z", "Most
  episodes", and "Oldest first" (`SeriesSort`, undated last). The
  networks are those `series.networks` names, each with the series it
  would list ("CBS (2,781)"), most first, at most 40, after "All
  networks". The decades come from the series' own dates
  (`seriesDecades`). Every facet is counted against the others'
  selection through the one clause the list uses (`facetClause`), so no
  choice offered yields zero rows (web §4.3, §10.5).
- **§4.3 A series page** shows years and count, then Follow (Following
  once followed, a tonal button), then its broadcast seasons as
  `FilterChip`s, a segmented scope and never a push, the oldest selected
  first; the episodes of that season run oldest first. Follow writes the
  store sync carries (`UserStore.setFollowing`, §2.3); an unfollow is a
  marker. Share is the top bar's action (§4.12).
- **§4.4 Episode detail**, the web's order (web §4.5): the series as a
  link, the title as a heading, the date, one facts line ("Undated" when
  there is no date, then network, sponsor, length: `detailFacts`), Play
  (or "Resume at" the saved position), the download control, "Automatic
  transcript" when the gate passed, Cast and credits, Versions (or the
  one copy's notes), and the rights line. A part with no data is absent;
  the sponsor shows only where the catalog carries the contract's
  `sponsor` column (probed, as Apple does). Share is the top bar's action
  (§4.12).
- **§4.5 Search** is a `DockedSearchBar` ("Titles, series, people"),
  debounced, with Clear, series first and then episodes; "In the
  transcript" marks a transcript-only match.
- **§4.6 Library** is the account row (§4.11), then In progress (with "position of length"), Downloads
  (with storage held and Remove All, which asks first), Played
  (Apple's word), and Following (the web's last Library scope, §4.7): the
  followed series, newest follow first, each opening its page. A follow
  the open catalog does not serve is kept for sync and not listed.
- **§4.7 The transcript is a route** (`ui/screens/TranscriptScreen.kt`):
  the episode title, then plain selectable text in `bodyMedium`, a
  sentence a line, at most 680 dp wide, fetched from archive.org when
  opened.
- **§4.8 Episode rows carry two targets**: the row opens Detail ("Open
  episode") and the trailing button plays ("Play" and the title).
- **§4.9 Plays** (`docs/PLAYS-DESIGN.md` binds what it does;
  `ui/screens/PlaysScreens.kt`, `RecordingScreen.kt`, `plays/`). The tab
  is "Your plays" (each with "n of m lines recorded" or "Finished" and a
  Delete that asks first) over "Plays you can cast", each row the
  title, author and part count, and the rights line: the evidence claims
  verbatim, each linked to its source, then the source by name. The
  script page adds "Cast this play" and the parts with line counts. The
  cast sheet is a `ListItem` per part, largest first, with its one verb
  in the trailing slot: Take part (an `AlertDialog` with an optional
  name), Leave silent (sound and directions only), Record, or a `⋮` menu
  with Open part; then Listen, then Discard unused takes and Delete
  production. Recording asks for the microphone at Start recording,
  checks the route (headphones, or a refusal line with "Record without
  headphones", which turns on echo cancellation and marks the takes
  `aec`), counts five seconds of room tone, then shows the cue (labeled
  "Device voice" when the device reads it), "Your line", the line in
  `headlineSmall`, the next line dim, the takes, one 72 dp record
  control, Run-up, Hear it read, the device voice's speed, Keep, and
  Done with this part. Space or the headset key records or stops, Enter
  keeps, and the arrows move by line. Takes are 24-bit WAV (not FLAC:
  MediaMuxer has no FLAC container), the mix is AAC in `mix.m4a`, and
  only a finished play offers Export, through the share sheet.
- **§4.10 Radio** is Tonight in 19xx (`RadioScreen`,
  `ui/screens/RadioScreen.kt`), the web's §4.9 in a `LazyColumn` of
  `ListItem`s: the evening `tonight.json` publishes for the device's own
  calendar date (`RadioClock.localDate`, never the UTC date), fetched
  through `ApiClient.tonight()` from the catalog's Release (contract §2,
  §8) and resolved against the open catalog (`RadioLoad`). A header of
  "Tonight in 1942" (`headlineSmall`, a heading), the evening's date, and
  the network and station; then one row a slot. Each row leads with its
  local time (`bodySmall`, tabular) and the paper's Eastern time beneath
  it ("7:00 PM ET" alone where the two agree). The slot on the air says
  "Now", takes the `surfaceVariant` container and the red edge (§6.1a), and is marked selected
  for TalkBack, repainted every 15 seconds from the file's instants. A
  surviving slot opens its episode ("Open episode") and has a trailing
  Play that plays it from its start (§4.8); a gap is muted, not
  clickable: `known_series` where the file sets it, then "Not surviving"
  (or "Not in the catalog" for a withheld slot or one the open catalog
  lacks), and its length. The paper's printed text is never decoded, so
  no screen can draw it. Before the evening the header says "Starts at",
  after it "Ended at"; during it, "Listen live" (`LiveRadio`,
  `radio/LiveListening.kt`) joins the slot on the air at the clock's
  offset through the one `PlaybackEngine`, with nothing queued behind
  it, and each later surviving slot starts at its own time. A pause (by
  the person, the notification, a headset, or audio focus), another
  episode, the sleep timer, a stop, or the last slot's end stops it, and
  nothing autoplays after the evening (R14). While live the button reads
  "Listening live"; pressing it pauses. No file, or no evening for
  today, is the `EmptyMessage` "No evening is published for today."; an
  unreachable file is "Tonight could not load." with Try again, or "You
  are offline." with Try again when the device has no network. The
  listing's credit is one caption link, "Schedule: {paper}, via
  {source}", opened in the browser (text only on a TV).
- **§4.11 The account is Library's first row** (`ui/AccountRow.kt`).
  Android has no Settings screen and gets none for this: an account is a
  rare job, and Library is where the records it syncs already live
  (`learner-experience-design`: account pages for rare jobs). One
  `ListItem` with the account icon: signed out, "Sign in to sync"; signed
  in, "Signed in with Google" (or Apple) over "Synced 5 minutes ago",
  "Syncing", or "Not synced yet", or the last error in the error color
  with the `error` haptic. A build whose ids are placeholders shows the
  row unclickable with "Sign-in is not set up in this build." and no
  error. The row opens a `ModalBottomSheet`: signed out, "Sign in with
  Google" (Credential Manager, a Google ID token with a raw nonce) and
  "Sign in with Apple" (Apple's web authorization in a Custom Tab, no
  scope, returning through `eardrama.org/auth/apple/` to
  `eardrama://oauth/apple`, DEEP_LINKS.md), each only when configured;
  signed in, the sync line, the last error, Sync now, Sign out, and
  Delete account, which asks first in an `AlertDialog` ("Delete your
  account?") and, for an Apple account, goes back through Apple for the
  code the Worker revokes. Sign-in is never asked for at launch or by any
  other screen (Decision 057). A signed-in app syncs when it comes
  forward and when it leaves (`MainActivity.onStart`/`onStop`); signed
  out, nothing reaches the Worker.
- **§4.12 Share** is a Share icon in the top bar of Detail and a series
  page ("Share" and the title for TalkBack). It sends the https twin
  (`navigation/SiteLinks.kt`, DEEP_LINKS.md, as Apple's `SiteLinks`):
  `https://eardrama.org/episode/{id}` or `/series/{key}`, the id encoded
  exactly as the web's `encodeURIComponent`, through the system share
  sheet (`ACTION_SEND`, text), titled as the web titles it ("Sorry, Wrong
  Number (1943-05-25)", or "(undated)"). A TV has no share sheet to
  another person, so it draws no Share (§9.2).
- **§4.13 Listen together** (LOOP-PLAN M6, Decision 065, docs/WORKER.md
  "Listen Together rooms") is one `ModalBottomSheet`, opened from a
  Listen together icon (Groups) on the player sheet's row of speed,
  transcript, and sleep, and from a "Listen together" row in Library
  under the account row, so a code can be typed with nothing playing.
  Least chrome, no sign-in. Out of a room the sheet shows "Start a
  room" while an episode is loaded (the room carries the host's exact
  copy, the `archive_id` and file of the recording playing, Archive
  Watch Decision 143), then a "Room code" field and Join. In a room it
  shows the code in `displaySmall`, "n listening", then Share (the
  https link, phone only), Leave, and, for the host, End room. A guest
  hears the host: play, pause, seek, and speed follow through the one
  `PlaybackEngine`, and the player sheet's transport is disabled for a
  guest (a code lets someone listen, never drive). When the host leaves
  or goes quiet, the member present longest becomes host and gets the
  controls. One plain line, never the error color, for "No room has
  that code.", "This room has ended.", "This room is full.", "Too many
  tries. Wait a minute.", or "Could not reach the room."; a build whose
  Worker URL is a placeholder shows "Listen together is not available in
  this build." and offers nothing else. The rules are the Worker's,
  ported, not re-derived: `together/RoomProtocol.kt` (pure, no imports)
  carries the code normalization, the clock estimate, drift correction
  by speed before seeking, the poll cadence, and handoff from
  `worker/src/room-protocol.js`, golden-checked against it
  (`android/scripts/room-golden.mjs`, `RoomProtocolTest`);
  `together/RoomsApi.kt` is the thin HTTP adapter on the one Ktor
  client; `together/ListenTogether.kt` runs the room. A link
  `https://eardrama.org/?room=CODE` (DEEP_LINKS.md) opens the sheet with
  the code filled in and joins only when Join is pressed (§5.1: nothing
  plays without a request). On a TV the Library row and the sheet are
  D-pad stops with the ring, the code field takes focus, and Share is
  absent.

## §5 The player

- **§5.1 One engine.** `PlaybackEngine` owns the Media3 player; the
  `PlaybackService` (`MediaLibraryService`, `mediaPlayback`) wraps it so
  the notification, the lock screen, Bluetooth, and the car share one
  session, with back 15 and forward 30 as its media buttons. Nothing
  plays at start: the only path to the player is a request from the
  listener.
- **§5.2 The mini player** sits above the tabs while an episode is
  loaded (`MiniPlayer`, `ui/screens/Player.kt`): a progress line, title,
  series (or the problem, in the error color), and Play or Pause; a tap
  opens the player.
- **§5.3 The player is a `ModalBottomSheet`**: series, title (a link to
  Detail), date, any problem, the position slider with elapsed and
  remaining, back 15, a 72 dp Play, forward 30, then speed, the
  transcript, and the sleep timer as `DropdownMenu`s, and "Up next".
- **§5.4 The player's numbers are DECISIONS 062's** (`PlayerNumbers`):
  the sleep fade is 10 s, speeds are 0.75, 1, 1.25, 1.5, and 2, progress
  saves every 5 s and on pause, and resuming after an interruption (audio
  focus handed back after a call) starts 3 s back. A saved position
  resumes exactly where it was saved (`PlayerNumbers.fromSaved`), as on
  the web. A finished episode starts over. `PlayerNumbersTest` checks the
  web player carries the same numbers.

## §6 Theme

- **§6.1 Brand first; dynamic color is not the default**
  (`ui/theme/Theme.kt`, `dynamicColor = false`). Light and dark come from
  the generated tokens.
- **§6.1a Color roles (Decision 064, On Air).** Material components take
  `colorScheme.primary` by default, so `Theme.kt` puts the brand's blue
  `secondary` in M3's `primary` and `secondary` slots (and a sixth of it
  over the ground in the two container slots): the selected
  `NavigationBar` item, chips, every filled button that is not live,
  spinners, and the download bar follow it with no override. Links and
  the TV focus ring take `OnAir.colors.link`. Red (the brand `primary`)
  is only for what is live, set by hand through `OnAir.colors.live`
  (`liveButtonColors()` on a filled button): Play and Pause on the player
  and the mini player, Play on Detail, the progress line and the
  scrubber (the player's and a play's mix), the slot on the air (a 4 dp
  leading edge), Listen live and Listening live, Start recording, the
  record control, and "Your line" while the microphone is live. M3's
  `tertiary` holds the red too, so no default component reaches it, and
  dynamic color never changes `OnAir`. Genre hues are content: a series
  row's 4 dp leading mark (`OnAir.genre(key)`, the border color for a key
  the palette does not name), never a button, a tab, or a link. Tab icons
  are unchanged. `ColorRolesTest` fails on the red reached any other way,
  on a red M3 `primary`, and on a token genre with no mark.
- **§6.2 Six type levels** (`AppTypography`, `ui/theme/Type.kt`):
  `displaySmall`, `headlineSmall`, `titleMedium`, `bodyMedium`,
  `labelMedium`, `bodySmall` with tabular figures, over the system face.
  Refuse a seventh; `TypeLevelsTest` fails on any other style named.
- **§6.3 Icons are Material Symbols** (R-ICON-1); the skip icons are
  Media3's own.
- **§6.4 Haptics use the one taxonomy**, mapped in one place
  (`ui/Haptics.kt`, `Haptic`): `selection` on a tab, season, or filter
  change, when "Your line" begins, and on the mix's Play and Pause;
  `success` when a download finishes; `error` when "Download failed",
  the player's problem line, a plays refusal line, or "Tonight could not
  load." appears.

## §7 States and accessibility

- **§7.1 Every query has four states** (`Loadable`): Loading (a labeled
  spinner), Ready, NoCatalog ("No catalog on this device yet.", or "You
  are offline." when the device has no network, Try again), and Failed
  ("The catalog could not be read.", Try again). An empty result is an
  `EmptyMessage` sentence; "This episode is not in the catalog." has no
  retry. Offline is a degraded mode, not a failure (web §7.3): while the
  device reports no network, "You are offline." sits in the flow above
  the mini player, in the neutral color (`OfflineLine`).
- **§7.2 The transcript has its own states**: loading, "You are
  offline." or "The transcript did not load." with Try again.
- **§7.3 TalkBack.** Section headers and the Detail title are
  `heading()`; rows carry `onClickLabel`s; the slider has a description
  and a state ("m:ss of m:ss"); speed and the sleep timer announce their
  value; font scaling applies because every style is in `sp`.

## §8 Values

The rights line, the transcript label, and loudness by cutting are as in
§1.6 and are not reworded. A downloaded file is played, never exported:
no share or open-with action (`ui/Downloads.kt`). A finished play's mix
is the one file the app shares, and only when the person presses Export
(`FileProvider`, `Plays/` only). Share (§4.12) sends a link, never a file. A device voice is never written to a
file (`StandInNeverStoredTest`). No analytics.

## §9 Stubs that live in the Android build, and parity

- **§9.1 Android Auto** (`playback/CarLibrary.kt`) is the browse tree the
  service serves: four roots, Continue, Radio, Series, Downloads (R17).
  Continue lists this device's in-progress episodes as playable nodes
  (title, series and date) within an 8 s budget; the other three are
  empty. No artwork. Every release with car support waits on Google's
  car review.
- **§9.2 Android TV and Fire TV** are a runtime branch of the one app
  (`ui/Television.kt`, `isTelevision()`), never a flavor. On a TV the
  focused card wears a ring and a 1.06 scale (`tvFocusMark`), never
  color alone, and each tab's screen claims focus on entry
  (`ClaimTvFocus`): Listen its first card, Series its first filter chip,
  Radio its Listen live button during the evening (else its first slot),
  Search its field, Library its first row. The pushed screens and the
  player sheet claim it too: Detail its Play (tvOS-DESIGN §6.2), a series
  page its first episode (Follow and the seasons are above it), the
  transcript its first sentence (each sentence a stop, since a remote has
  no scroll gesture), and the player sheet its Play or Pause. Every
  control on them wears the ring: episode and series rows, chips,
  buttons, the series link, and the player's controls. Share is absent on
  a TV (DEEP_LINKS.md: a TV shares by QR code, not built). On Radio every slot is a
  D-pad focus stop with the ring, gaps included, and a surviving slot is
  one stop that opens Detail, where Play lives (tvOS-DESIGN §4.8). The session stays on so the home screen can show a
  Now Playing card (TV-NP). The banner is a placeholder. A TV omits
  sign-in: Credential Manager's sheet and a Custom Tab are phone surfaces,
  and a remote is no way to type an Apple ID. The account row is absent on
  a TV signed out; an account signed in on that device still syncs, as
  `android-tv`, with Sync now, Sign out, and Delete account (§4.11).
- **§9.3 Wear OS** (`android/wear/`) is Continue, saying "Waiting on the
  phone" until the phone hands its history over; minSdk 30.
- **§9.4** Update `PARITY.md` in the same change set.

## §10 Traps this codebase has already paid for

- **§10.1 Every query keys on `dbVersion`** (`rememberCatalogQuery`), or
  a screen shows yesterday's catalog after a swap.
- **§10.2 A recreated Activity must not reopen the launch doors**
  (`savedInstanceState == null` in `MainActivity`).
- **§10.3 Fire OS can report a normal UI mode on a TV**, so
  `isTelevision()` also checks the launcher's feature flags.
- **§10.4 A credit's position is its key** on Detail: one person can hold
  two roles on one broadcast.

## §11 Deliberate inversions

- **§11.1 Play never opens the player.** Like iOS, Play on Detail
  starts the audio in place; tvOS focuses Play and opens Now Playing
  (`docs/tvOS-DESIGN.md` §6.2).
- **§11.2 The transcript is a pushed route**, where iOS uses a sheet,
  the Mac a window, tvOS a full-screen reader, and the web a closed
  section. Same label everywhere.
- **§11.3 Predictive back pops the stack**; iOS's swipe back is a fixed
  animation.
- **§11.4 The media session stays on on a TV**, the inverse of Archive
  Watch, a video app that turns its session off there.
- **§11.5 Search is the fifth tab**, after Plays, where Apple's
  `role: .search` lets the system place it last.
- **§11.6 Listen live on a TV starts in place**, as Play does (§11.1);
  tvOS opens Now Playing full screen (tvOS-DESIGN §4.8). Android TV's
  player is still the phone's sheet (§12).

## §12 Open (what the code does not yet meet)

- **Six destinations on the phone's bar** (§3.1): they fit at 360 dp
  at the default font size, but Material's bar guidance is three to five
  and the largest font scales will ellipsize the labels. The owner is
  deciding the six-section question for every platform (SCRATCHPAD item
  12); until then nothing is dropped.
- **Radio has not run on a device.** Listening live, a slot starting at
  its own time, and each event that stops it are proven in
  `RadioTests` on the JVM, not yet heard on the Pixel or a TV.

- **Plays has not run on a device.** The microphone, the route check,
  echo cancellation, the engine voices (and API 29's zero-volume
  collection), the AAC mix, and the share sheet are built from the
  documentation and wait on the Pixel 8a and one Samsung (PLAYS-DESIGN
  §4.4). The bleed threshold is Apple's unmeasured 0.5.

- **The queue is the rest of the season** (`followingInSeason`), where
  Apple plays on through the series and the web only what the person
  queued (`docs/WEB-DESIGN.md` §5.4). R14 needs one rule, and it is the
  owner's to set (DECISIONS 062).
- **No sponsor reaches Detail yet**: the contract names `sponsor`
  (§3.1), but the projection does not publish the column, so §4.4 probes
  for it and shows none (Apple likewise).
- **On a TV the pushed screens and the player sheet are the phone's
  layouts**, with focus claimed and the ring (§9.2), not a ten-foot
  design; none has run on a TV. The player is still the sheet (§11.6).
- **A TV cannot share**: DEEP_LINKS.md's QR code of the https twin is
  not built.
- **Listen has no Following shelf**, which the web draws after Continue
  listening (web §4.2); Android's follows are in Library (§4.6).
- **The `eardrama://` and App Link filters are off** in the manifest
  (§3.4); `DeepLink.parse` routes both once they are on.
- **No Queue verb**, which the web has: what plays next is the owner's
  call (SCRATCHPAD item 9, and the queue item above). Sync stores the
  queue other devices send (`UserStore.queue`) and sends it back
  unchanged; nothing on Android shows it, and no Android verb removes an
  episode from history.
- **Sign-in has not run.** The Worker is not deployed and the ids are
  placeholders (docs/WORKER.md, Needs Ben). Apple on Android also needs
  the return page at `https://eardrama.org/auth/apple/`, which forwards
  its fragment to `eardrama://oauth/apple`; it is not built. Google needs
  an Android OAuth client for `app.eardrama` with the Play signing SHA-1
  (and `app.eardrama.debug` with the debug key) in the project that owns
  the Web client id.
- **Listen together has not run** (§4.13). The Worker is not deployed,
  so every build says it is not available; the room, drift correction,
  and handoff are proven in `ListenTogetherTest` and `RoomProtocolTest`
  on the JVM against a Worker built from `room-protocol.js`, not yet
  heard across the Pixel, an iPhone, and the web (LOOP-PLAN M6's play
  gate). A guest's notification and headset buttons still pause; the
  next read puts the guest back with the host.
- **Tab icons differ from Apple's** (Headphones and Radio against
  `play.circle` and `square.stack`).

Bring the next change back to a rule here, or bring a new rule first.
