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
  season is a scope; the player is a sheet. For an ear drama it is
  Browse, cast sheet, part: starting one replaces the play's page with
  its cast sheet. A person (§4.15) stands where a series does: Search,
  person, episode is two; from Detail a credit pushes the person, as
  Detail's series link does, and a person already on the stack is popped
  back to (§3.5), so person, episode, person never stacks.
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
  no node, card, or notification carries invented art. As amended by
  Decision 069 (2026-10-24): a served portrait or the typographic card
  drawn from data is the art. A row that mixes series leads with a 40 dp
  tile (the series' star, else its first letter in its genre hue); the
  series page and Detail put the face beside the heading with the name
  and any owed CC credit; cast lines carry 32 dp round portraits; Now
  Playing and the Media3 session's `artworkUri` carry the same picture.
  One helper builds every image URL (Commons' 120 / 330 / 500 / 960 steps).
- **R11a Faces lead** (owner, 2026-10-28: *"Portraits should show wherever they are useful or joyful (overall the visuals are not highlighted yet on the app)."* and *"The visual pass should be for all artwork. We want the app to be as visual as possible."*) (WEB-DESIGN §6.4a is the shared text). The
  only art served with evidence is a person's portrait; other classes wait
  on the owner's V2 to V5. **The box takes the picture's shape, never the
  picture the box's** (owner, 2026-10-28: *"I think you can find better solutions for different aspect ratios of images, then just blurring and black bars."*; `artwork-presentation-design`). `Artwork.isWide` is width over height
  past `Artwork.WIDE_ASPECT` (1.15, the web's and Apple's number); an
  unknown size is upright, drawn at 4:5. The series page, Detail, and a
  person's page open with `FaceHero`. Upright (a square included) is the
  print: `ShapedArt` at its own aspect inside 150 x 168 dp (276 x 240 dp
  from 600 dp wide), beside its label (the name, which a person's page
  leaves to the title; the credit when owed; and the series' or person's
  facts line, which then has no row of its own). Wide is the plate: the
  column's width at its own aspect, at most 320 dp tall, at the start, the
  label under it. `ShapedArt` draws a hairline (`outlineVariant`), the 8 dp
  radius, and the genre's 3 dp edge, and nothing behind the picture: no
  wash, bars, or filter; while it loads the box is `surfaceVariant` at
  exactly the picture's size. Now Playing's bound is a square, full width
  and no taller than 44 % of the screen: a portrait is drawn whole at its
  own aspect and its box shrinks to it, centered; a card fills the
  square; an owed credit is under it. A row's `ArtTile` is 56 dp and a cast
  line's `CreditFace` 32 dp; an evening's aired slot leads with its series'
  tile. **Now Playing (D3-4)** draws the grammar's `PictureWindow` at the
  44 % bound (the show's picture, else its star's, else the title block), then the title
  and an `EventLine`; the mini player is a `GrammarRow`; the media session's artwork is the same picture. **Small crops center on the published face** (V4, WEB-DESIGN §6.4
  is the shared text): the tile and `CreditFace` show the square
  `Artwork.cropRect` picks around `Artwork.face` (the contract §3.3a
  formula: the face about half the square, at most 4x zoom), drawn as
  Coil's image at `ContentScale.FillBounds`, sized and offset inside a
  clipped box. Without a face an upright or square picture takes its
  largest square at 50 % across, 20 % down; a wide one is not cropped: the
  tile keeps its letter, the cast line its empty slot. No client detects
  faces. The Media3 session hands the system a URL
  (`artworkUri`), which it crops itself. Every box is sized from the published
  aspect, so nothing shifts when an image lands.
- **R11b One grammar** (owner, 2026-10-29: *"the design is still not uniform for all different levels of content (some with images, some without, some with more information, some with less). We need to a design approach that evens out all of the inconsistencies and make the app look like one complete thought."*; `catalog-experience-design` rule 11; D3-1); WEB-DESIGN §6.4b is the shared text, and
  where it amends R11 and R11a it wins. `ui/Grammar.kt` holds one
  composable per object, phone and TV alike: `PictureWindow` (the square
  slot on `PrintGround` with the `PrintEdge` hairline; the series'
  `picture` cropped by `Art.cropRect`, graded by a `ColorMatrix`
  (saturation 0, then scale `k` and offset `o * 255`) as Coil's color
  filter, the identity levels until the projection publishes
  `art.grade`; else `TitleBlock`, the monogram drawn with
  `TextStyle(drawStyle = Stroke)` in onBoard), `ShowTile` (window, name,
  `RunStrip`, facts, on `boardColor`; the names in one shelf take the
  tallest name's height, so every strip sits on one line), `GrammarRow`
  (64 dp, a 48 dp visual: `DateBlock` in a series' own list, the
  series' window where series mix; title, sub, length, Play),
  `HeadBoard` and `EventLine` (a `FlowRow` that keeps each " ·" with the
  fact before it). Home's shelves draw `ShowTile`; Browse and every
  series list draw `GrammarRow`; on TV the focused tile scales whole.
- **R11c Home and Browse** (owner, 2026-10-29: *"Having more shows is better, so 5."* and *"I like the bulky blocks and colors of The Sleeve and I like the data visualization options of the Almanac."*; D3-2; WEB-DESIGN §6.4c is the shared text). A show is a series of at least 5 episodes (`isShow`, `SHOW_MIN`); tiles in shelves and grids are shows only, and the rest are single recordings, counted and reachable by a link that lists them in the same tile grid. The rules are pure functions in `data/GrammarRules.kt` with the web's golden cases in `GrammarTest` (`isShow`, `dayYears`, `nightShows`, `decadeField`, `fieldSide`, `GENRE_ORDER`). Home, top to bottom, each section only with data: Continue listening and Following (kept), the day board (`DayBoard` in `ui/HomeBrowse.kt`: kicker "This day in radio", the big date, "N surviving broadcasts · N years", a bar per year stacked by genre in the genre mark colors on a fixed axis from 1930 to the last year, the selected year outlined with its label, a tap selects a year, peak year by default, a legend of the genres seen; every broadcast of the day, no limit of 20), the selected night as show tiles (first 6, then "All N shows that night" in place; each tile's facts are the episode title and length and it opens the episode; "N single recordings" at the heading's right as a plain fact), and Most downloaded (12 show tiles, then "All N shows" to Browse). Most heard voices and New ear dramas are not built (the data and the Worker are missing). Browse keeps every filter and sort as they were, then shows a count line ("2,036 shows" and, as a plain link, "7,189 single recordings"), the decade by genre field (`DecadeFieldView`: a square per cell in the genre's mark color sized by `fieldSide`, the count under it, "N with no genre" only when above 0, each non-empty cell applies its genre and decade; the other filters count, genre and decade do not), then a `LazyVerticalGrid` of show tiles (a play is a title-block tile with author and parts). The section heading names the sort, "A to Z" for A to Z. From 840 dp wide the field sits beside the grid; on phones it sits above. The field cells and the year bars carry TalkBack labels.
- **R11e Browse's A to Z jump and the D3-fix rules** (owner, 2026-10-30: *"We are building for each specific platform. It has to look good and use native design and apis on the given platform."*; *"Yes, add a letter jump"*). Sorted A to Z, Browse loads every series and a fast-scroll letter rail (`LetterRail`) sits on the trailing edge: a touch or drag jumps with the selection haptic, and TalkBack gets one custom action per letter; on a TV the letters are chips in the filter row. The decade headers read '20s. The episode page writes a full day in the device's long date format (`formatAirDateLong`); a year-only or month-only date stays as precise as the catalog is (R1). an undated, unnumbered episode leads its row with the series' window, never an empty date block; the run strip draws one bar per year from `series.year_counts` (web: `years`), its height the count over the show's busiest year, and falls back to the first-to-last span where the catalog has none; the head board's strip is taller than the tile's; the series page's genre is a link that opens Browse at its root filtered to that genre; an episode with a `script` offers Start an ear drama (not on a TV). The head strip is 40 dp on a phone, 56 from 600 dp.
- **R11f The three recording modes and D's recorder** (owner ruling 4, 2026-10-29: *"One option should let you record and have the other parts play (either human voices or generated voices for parts that haven't been taken yet) and it should play right through with your opportunity to record your part as it shows up naturally within the Ear Drama script. Another option should allow you to record each line individually or re-record any lines again by tapping them and re-recording. Another option could be a 'wait for tap' to advance through the script as you are describing."*; owner, 2026-10-30: *"It has to look good and use native design and apis on the given platform. There is no reason to degrade one platform in order to make sure everything is uniform across all platforms."*; D3-6; WEB-DESIGN and PLAYS-DESIGN carry the shared text). The recorder (`ui/screens/Recorder.kt`, stateless: `RecorderView` reads a `RecorderUi` and calls a `RecorderActions`; `RecordingScreen` feeds it from `RecordingSession`) has fixed slots that never move between modes or states: the top (close, the part name in the display face over the play title, "K of N" lines kept), the strip (one cell per line of the part: kept in the part's hue, the current one outlined, red while it records; TalkBack says "K of N lines kept"), the mode control, the scene, the dock. The mode control is Material 3's `SingleChoiceSegmentedButtonRow` with "Run through", "Line by line", "Step", the selected segment blue, disabled (and still showing its choice) while the microphone is armed or open and during a run; `RecordingSession.setMode` refuses the same. **Run through**: the play runs from the current line's cue to the part's last line (`Relay.runPlan`), other parts in their human takes or the device voice live, the microphone opening on each of your lines as it comes (the box armed: a dashed red edge and a "Next" pill while the cue plays) and the line-end detector closing it; the dock is the round red "From here", then ink Pause (red Stop while the microphone is open; both pause) with "N taken" beside it; Pause or the last line opens the run's review ("This run · N takes", each take with its cue, its length and Again; Discard the run, blue, deletes the run's takes and files and puts each line back on the take it had; "Keep N takes", ink). **Line by line**: every line of the part in order, with "Take k" and a check or "Not yet"; a tap opens that line in place (its cue above, your line box, then Record, red, and Cue, blue; Stop while recording); no dock. **Step**: each cue waits for a tap: the round red Record (Cancel while the cue plays, Stop while listening), then the take in the box with its take count; Again (a red dot), With cue (blue), Keep (ink), and Keep lands on the next line's Ready without playing its cue. Red means recording only (the round control, the box's recording edge and pill, Again's dot, the strip's current cell while recording); blue is wayfinding (Cue, With cue, Discard the run, Take part, the aids); ink is the action (Keep, Pause, Keep N takes, Record on the cast sheet). Your line box is your part's board (`board.<hue>`, the neutral board when the part has no hue) with its one onBoard color; a part's face is a filled circle in its mark color (`partHue`: the seven largest speaking parts take mystery, scifi, western, serial, documentary, comedy, news in that order, the rest and directions and sound stand on neutral) with the performer's initial, a dashed ring and waveform for the device voice, and a check when recorded. From 840 dp a left rail "In this scene" (the faces of the parts near the line and who holds each) and a right rail "This line" (the aids) flank the scene. The aids row is Step's and Line by line's; every state is a render in `PlaysRenderTest`. The strip, the faces and the take controls carry TalkBack descriptions, "Your line" is spoken before the microphone opens (§4.9), and no cue plays while the microphone is open (`RecordingSession.cancel` and `pause` stop a cue at once).
- **R11f Now Playing's people and Voices** (D3-9; owner, 2026-10-30: *"It has to look good and use native design and apis on the given platform."*; the shared text, WEB-DESIGN §6.4f). Now Playing draws **On the air** (the credited performers as round faces, portrait else monogram, each opening the person) and **That night on the radio** (`CatalogDatabase.sameDay`, contract §3.3b: at most 12 other surviving broadcasts of the same air date, by network with unknown last, then series, then id; each a grammar row of show and network, Play, and a tap to the episode), each hidden when it has nothing. **Voices** is Browse's second scope (Shows, Voices, Ear dramas) and Home's "Most heard voices" rail with All: `CatalogDatabase.voices` behind a column-exists guard, round faces over the name and the episodes, each opening the person's page; a catalog without the table draws neither. The sheet scrolls under its controls; `EpisodeRow.network` is read from `episodes.network`, so Now Playing's event line reads show, date, network. No Voices scope bar on a TV.

- **R11d Series and episode pages in direction D** (owner, 2026-10-29:
  *"an item with a picture, without one, rich or sparse, renders in the
  same structure"*; *"a share button that goes to the next line instead of
  being next to the other buttons"*; D3-3); WEB-DESIGN §6.4d is the shared
  text and where it differs this wins. It amends §4.3 and §4.4 and retires
  `FaceHero` on these two pages. **Series:** `HeadBoard` (kicker: the genre
  name, then the one primary network, `series.network` (V8, 2026-11-20: never the `networks` list, which put "CBS · NBC · AFRS · NBC RED" over Lux Radio Theater and "CBS, NBC" over Gunsmoke; none when the catalog names none); the name as the page's
  heading; facts: the years or "Undated", then the episode count; the run
  strip), then one button row (Follow, Share), the picture's credit when
  its license asks and the window shows it (`PictureCredit`), the season
  scope, the episodes. **Episode:** the head board of its show (the board
  is the link to the series; its name is not a heading), led by
  `leadPicture`; the episode's title as the heading; the event line
  (`episodeFacts`); one button row (Play, Add to queue, Share, Download);
  "Start an ear drama" on its own row where a castable script exists;
  Automatic transcript; On the air (`onAirOf`: round 72 dp windows of up to
  six cast, name and character beneath, a tap opens the person, the title
  block where there is no picture); Cast and credits folded; recordings;
  the rights line. A section with nothing in it is not drawn. **A button
  row never wraps apart:** `ActionRow` is a `Row`, never a `FlowRow`;
  Play and Follow take the room (`weight`), and the secondary buttons fold
  to 48 dp icons (`FoldButton`, the label kept as the content description)
  under 480 dp (600 dp on the episode row, which carries four), the Resume
  label shortens under 360 dp. The pages sit in a 720 dp column on a
  tablet. On a TV Play takes the default focus and Share is absent.
  Rules golden-tested in `GrammarTest`; the row's fit at 320 to 599 dp by
  `PageActionsFitTest` (its control, a `FlowRow`, must fail); renders by
  `GrammarRenderTest` with `GRAMMAR_RENDER_DIR`.
- **R12** brand colors are chrome; dynamic color is off by default.
- **R13** shelves are the catalog's `meta.listenShelves`, in order
  (contract §5.1; the same list and titles on every platform): This day
  in radio on the person's own date, "Most downloaded" (archive.org's own
  counts, Decision 067), then each published genre's ids as given. An older catalog without the key falls back to the rules run on
  the device (This day in radio, one shelf per genre the catalog names).
- **R15 and Decisions 067, 070: volume leveled on the device.** No
  per-file measurement is read. `VolumeLeveler` (`playback/VolumeLeveler.kt`)
  puts Android's `DynamicsProcessing` effect on the player's audio session:
  one full-band compressor at the numbers every platform shares
  (`LevelNumbers`: threshold -24 dB, ratio 4, knee 12 dB, attack 3 ms,
  release 250 ms, makeup 10.8 dB) and a limiter at -1 dBFS. On by default;
  "Level volume" (an icon toggle on the player sheet, the selected state in
  blue) turns it off, kept on the device. A device that cannot make the
  effect plays unleveled. The sleep fade is the player's volume.
- **R16** "Automatic transcript" (`Transcript.LABEL`) on Detail, the
  player, and the transcript screen's title.
- **R17** the car's four roots are the phone's tabs reduced (§9.1).
- **R18a Player sheet opens whole** (N4, 2026-11-04): `skipPartiallyExpanded = true`, so Play and the option row are on the first screen, never below a half-height peek; the sheet and the page share the 16 dp margin; the option row's controls sit in equal-weight cells. A trailing button on a row ends 12 dp from the edge, where Play's circle does; a text button that opens a menu or a run starts on the page margin (zero content padding).
- **R18** speed, sleep, and skip live on the player sheet.
- **R18a** Another speaker (the owner, 2026-10-28: "All apps should be
  able to make use of native sharing like airplay or casting on their
  platforms."): Google's own Cast button (Media3 `MediaRouteButton`) ends
  the player sheet's option row, shown only while a Cast receiver is on
  the network (`CastRoute.available`), and never on a TV or a device
  without Play services (Fire TV), which offer no button. Android 13+
  opens the system output switcher from it. Media3's `CastPlayer` wraps
  the one ExoPlayer, so the queue and the place move to the receiver and
  back; Google's Default Media Receiver plays the catalog copy, never a
  downloaded file (`CastRoute.Items`). The volume keys move the speaker
  while it plays, and the sleep fade and leveling act on the phone's own
  output only. Listen Together is a separate verb.
- **R20** the sleep menu lists "End of this episode" first, then 15, 30,
  45, and 60 minutes (`SleepTimer`); it fades, and once fired the queue
  stops. What plays next is the owner's rule (Decision 067): a part of a story arc (contract §3.3) is followed by the arc's next part, automatically; at the arc's last part playback stops and the series' next story is offered as a "Next story" action, never started. Anything the person queued plays after an arc's last part, as after any episode. Outside an arc: one episode, then the queue, then stop. A live slot follows its clock, never an arc
  (`queue = false`). The player's playlist is the episode, the arc's
  remaining parts (`CatalogDatabase.arcAhead`), then the synced queue
  (`PlaybackQueue.after`); a queued episode leaves the queue as it starts.
  The sheet's "Next story" button (`NowPlaying.nextStory`) shows on the
  last part only, never for a Listen Together guest.
- **R21** every icon button has a `contentDescription`; §7.3.
- **The rights line** is the published `meta.rightsLines` words
  (contract §5.5, `CatalogDatabase.rightsLines`), the contract's own
  strings for a catalog that predates the key: "No rights claim known.
  Removed on request." for an unclaimed recording, never public domain;
  a clean basis with no words shows no line (`DisplayVocabulary.rightsLine`).
  **The unclaimed line is not drawn** (owner, 2026-11-09: *"the 'No rights
  claim known. Removed on request.' on each ear drama is unnecessary as that
  is the default for every show on the app"*): `displayedRightsLine` returns
  null for `unclaimed`, the vocabulary string stays for the cross-language
  parity test, and every other rights phrase still shows.
- **R22 A show is one tap from any of its episodes, and says what it is**
  (owner, 2026-11-09: *"the dramas seem totally disconnected from any
  recurring show that they are a part of ... Most people will have no idea
  what the shows are about and they will need an entry point to know whether
  or not they should listen."*). The episode page's head board is the show's
  control (its facts line ends "All N episodes ›"; click label "Open series");
  Now Playing names the show as a link (`onOpenSeries`); every episode row
  and Home's night tile name the show. The series page draws an About under
  its facts when the catalog has `series.about_text` (column-exists guard,
  `AboutBlock`): paragraphs collapsed to four lines with Read more, then
  "From [about_source]" opening `about_url` in a Custom Tab (the CC BY-SA
  attribution; a TV names the source without a link). Nothing is drawn when
  the columns or the value are absent. An episode with `episodes.script_url`
  offers "Read the script · [script_source]" in a Custom Tab, beside the
  ear drama and transcript rows. A recording with no clean label is named by
  its kbps and length, never "Recording N" (`RecordingLabel.title`).
- **R9, R10, R14 on the Radio tab** (§4.10): a gap is drawn as a gap,
  the slot on the air is read from the file's UTC instants on the one
  clock (`RadioClock.onAir`, `radio/Tonight.kt`, golden against
  `js/api.test.js`), and nothing plays after the evening.
- Not built anywhere yet (data plane first): R2, R4, R6, R7. R8: no data
  marks a commercial's start and end yet (contract §3.2a); Media3's chapter
  metadata will carry them when it does.

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

- **§3.1 Five sections, Record among them** (Decision 075, owner
  2026-11-14: *"It is entirely unclear what the app is or how to use it
  easily"*; *"The ability/functionality for recording new Ear Dramas is
  significantly buried"*). **Five tabs, hard set: Home, Browse, Record,
  Search, Library** (`Tab`, `navigation/Routes.kt`), with Material icons
  Home, Explore, Mic, Search, and Bookmarks. **Stations** is pushed from
  Home (`Route.Radio`, from On the air's "All stations" and the Listen
  door) and **Surprise** is the Home top bar's one action (Shuffle),
  pushing `Route.Surprise`; neither is a tab. `NavigationSuiteScaffold`
  draws a bar, a rail, or a drawer by window size; five items is inside
  Material's three to five. Each tab owns one verb: Home what is on now
  and where to start, Browse every show by facet, Record making an ear
  drama (your productions, then the plays), Search find, Library yours.
  "Record this" sits beside Play on any page with a castable script.
  **On a TV** (Android TV, Fire TV) there is no Record tab: a TV records
  nothing (PLAYS-DESIGN §2), so the rail shows Home, Browse, Search,
  Library, Home has no Record a play door or row, and the plays, the
  Surprise play, and Ear dramas are not shown.
  - *Replaced* (2026-11-14, Decision 075): "**Five tabs, hard set: Home,
    Browse, Stations, Search, Library** ... No tab is named for a content
    type: plays sit in Browse and Search beside the series".
  - *Replaced*: "Six tabs, hard set: Listen, Series, Radio, Plays,
    Search, Library ... Plays records, so a TV shows the other five."
- **§3.2 One route registry.** Every destination is a case of the sealed
  `Route` (Navigation 3 `NavKey`): the five roots, `Series`, `Episode`,
  `Transcript`, `Surprise`, and the ear drama's `Script`, `Production`,
  and `Recording`,
  resolved in one `entryProvider` in `ui/AppRoot.kt`. Stations' root is
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

- **§4.1 Home** (Decision 075; the web's §4.2 holds the shared sections
  and data rules) is a `LazyColumn`, the top bar's action Surprise
  (§4.14). Top to bottom: **On the air** (an `ElevatedCard` on the board:
  tonight's slot on now, else the first genre station with a playable
  slot, as a `GrammarRow`, then **Listen live**, a filled `Button` in
  ink, and **All stations**, an `OutlinedButton` pushing `Route.Radio`;
  absent when nothing is on); **Continue** (only with history); **three
  doors**, one `Row` of three equal `OutlinedCard`s, a Material icon over
  a verb (Listen `Radio`, Find a show `Explore`, Record a play `Mic`);
  **Start a show** (`FilterChip`s, "Most downloaded" then each published
  genre, over a `LazyRow` of 220 dp tiles with a Play `IconButton`);
  **By length** (Under 15 min, About 30 min, An hour, from `byLength`;
  absent while unpublished); **Record a play** (Today's scene, below,
  then Open parts); **This day in radio**; **Most heard voices**; **Made
  here**. Each section has its own loading, error (Try again) and offline
  state; a section whose rule yields nothing is not drawn.
  - **Today's scene** (Decision 079, owner 2026-11-15; WEB-DESIGN §4.2 item 7
    is the shared rule; port brief `docs/research/design/R2-design-review.md`
    §6): `todaysScene(rows, date)` in `plays/`, the `todaysPlay` hash over
    the scene pool (two voices and at most 20 min; else 2-3 voices and at
    most 30; else every play), golden `catalog/tests/golden/todays_play.json`
    `scene`. One card on the drama board: the kicker "Today's scene", the
    title, an event line (author · N voices · About M min) opening the play
    page; the opening as a page on the print ground (the first four
    speeches, each its role name in `labelMedium` over its said words, three
    lines at most, a 3 dp rule in the part's hue; `openingOf`, else the index
    row's `opening`); then one `Row` that never wraps: **Try a line**
    (filled `Button` in ink, `Mic`: the reader's Record path for the
    answering voice, the second speaker of the opening, else the second
    part, opening the studio on that part's first line with its cue
    underlined), **Hear it** (`OutlinedButton`: the opening read live by the
    play's one cast in device voices through `TextToSpeech`, lighting the
    speech being read; it becomes Stop, pauses the player first, stops when
    the screen leaves, keeps nothing; absent with no voice) and **Read**.
    Record a play moves up between Start a show and By length. Not on a TV.
  - **Made here, leading** (Decision 079; WEB-DESIGN §4.2 item 7a): while
    there are one to five finished ear dramas, Made here is drawn directly
    under the three doors instead of last; at six or more it returns to the
    end.
  - *Replaced* (2026-11-15, Decision 079): "**Record a play** (Today's play,
    `todaysPlay` in `plays/`, as `PlayHeadBoard` with Record this and
    Parts, ...) drawn after By length".
  - *Pending port* (2026-11-15 design review, `docs/research/design/R2-design-review.md`
    §6; WEB-DESIGN §4.2 items 1, 2 and 7, §4.15): the top app bar title on Home
    is **Ear Drama** (built 2026-11-15; the Home tab keeps its label); On the air's kicker reads "On the air · {source}" after
    an ink dot (Today's scene and the move are built, above, Decision 079),
    and the rest of this note: `todaysScene` (the
    `todaysPlay` hash over two voices and at most 20 min, else 2-3 voices and
    at most 30), the title block on the drama board, the first four speeches
    as a page (role name over said words, three lines at most, a rule in the
    part's hue), then **Try a line** (filled `Button`, `Mic`: the studio on
    the answering voice's first line), **Hear it** (the opening read live by
    the cast's device voices, never kept) and **Read**. Record's second block
    is the same card. Play tiles show the index row's `opening` as a page in
    the window when it is present. Not on a TV.
  - *Replaced* (2026-11-14): "a `LazyColumn` of shelves ... Continue
    listening, then Following ..., then the published shelves in order".
- **§4.1r Home reads as one thing** (Decision 081, owner 2026-11-19: *"the home screen ... still reads like a long list of items that feel unrelated ... The goal is to have the home view feel more cohesive and inviting from the moment that you open the app."*; rulings: "Home: all of R3a §4.1", "label art C on every platform"). Binding over §4.1 wherever they differ; the shared
  rules are WEB-DESIGN §4.2r 1-8 (one lead object, the dial of genre stations under it, two quiet
  doors, one art system and one window size in every rail, a show at most once per Home, two inks
  per screen, rhythm L S M L M S, framing from data only). Android's idiom: the hero is the On the air board
  at full width, its window at tier L, **Listen live** a filled ink button; the dial is a `LazyRow`
  of S-tier labels; the doors are two `TextButton`s with Material Symbols in one row. On Google TV
  the hero and the dial follow tvOS-DESIGN §4.1r (focus does the work; the label never adds focus
  chrome a picture would not). Built in Round 3 V6.
- **§4.2 Browse** (was Series) lists radio series; the plays moved to
  Record (§4.9a, Decision 075), so the Kind chip and every clause below
  about plays in Browse are replaced. A Kind chip (Any kind, Series, Plays) and a "Has a script"
  chip lead its row of `FilterChip`s; a play carries no genre, decade, or
  network, so setting one narrows to series, and "Has a script" keeps the
  rows whose record carries a usable script: the plays, and the series
  with an episode whose `script` is set (contract §3.1). A play row
  is its title, then author and part count, and opens the play's page.
  Below the chips, a paged list
  of series (200 at a time), each one line of years and count: the sort
  and the network as dropdown chips (a `DropdownMenu`), then the decades,
  then the genres. The sort is the web's four, "Popular" (the default,
  filled once another is chosen), "A to Z", "Most episodes", and "Oldest
  first" (`SeriesSort`, undated last). Sort is Popular (the default), A to Z, Most episodes, and Oldest first. Popular is the published `downloads` (contract §3.3): counted series first, most downloaded first, then every row without a count by `sortName`. A play has no count, so under Popular it sorts after every counted series; a catalog published before the field has no counts, so Popular is A to Z. Plays follow
  the series under every order. The
  networks are those `series.networks` names, each with the series it
  would list ("CBS (2,781)"), most first, at most 40, after "All
  networks". The decades come from the series' own dates
  (`seriesDecades`). Every facet is counted against the others'
  selection through the one clause the list uses (`facetClause`), so no
  choice offered yields zero rows (web §4.3, §10.5).
- **§4.3g Item pages wear Home's hero** (Decision 081, Round 3 V7; owner, 2026-11-19: *"We need to continue making the app more visually appealing, both from the home screen perspective ... and the individual item perspective."* Shared rules: WEB-DESIGN §6.4g 1-7). `ItemHeadBoard`
  heads the series, episode, person, play and ear drama pages: the window at tier L across the board's top on a phone and 320 dp
  beside the words from 560 dp (a tablet, a TV), a picture at its own shape through `ItemLead.window` (wide a plate, upright
  beside the words), never cropped, graded; the label (round for a person) otherwise; an episode's head is its dated label with its
  year at full ink on the show's strip and the show's picture a row under the actions; the copies are one collapsed
  **Recordings** row; `series.gallery` is a `LazyRow` of whole pictures, ungraded, drawn only from two evidenced ones.
  **TV: focus does the work.** The head and its buttons are one list item wrapped in `revealWhole()`, so a D-pad move to a button
  asks the list to reveal the whole board, never only the button (Google TV Home scrolled the hero's top off screen, 2026-11-19);
  Home's hero draws its photo through the same window, at its own shape, where a wide photo had sat small inside a square window.
  V8 (2026-11-20): this holds on the episode page too (its Play row had been a separate item, and Play's first focus scrolled the
  board's top under the bar), and on a TV a wide plate is at most 30% of the screen's height (`ItemLead.window(plateMax)`), so the
  name and the buttons stay on the first screen (Lux Radio Theater's 2:1 hero had filled it).
  A plate so capped (under 70% of the board's width, `ItemLead.cappedPlate`) stands left of the words, as an upright picture
  does, never alone at the top with an empty band beside it (V8 follow-up, 2026-11-20).
- **§4.3 A series page** shows years and count, then Follow (Following
  once followed, a tonal button), then its broadcast seasons as
  `FilterChip`s, a segmented scope and never a push, the oldest selected
  first; the episodes of that season run oldest first. Follow writes the
  store sync carries (`UserStore.setFollowing`, §2.3); an unfollow is a
  marker. Share is the top bar's action (§4.12). The top bar's Download
  action (as Detail's download control, on a TV too) opens a menu: Download all
  episodes, Download this season (the selected chip's, when there is
  more than one season), and Remove downloads once any of the series is
  on the device. A download asks first in an `AlertDialog` naming the
  count and about how much space it takes, from each copy's bitrate and
  length ("Download 52 episodes?", "About 640 MB."); an item whose
  episodes are all downloaded or downloading is disabled; removing a
  series' downloads asks first (iOS-DESIGN §4.3, R17).
- **§4.4 Episode detail**, the web's order (web §4.5): the series as a
  link, the title as a heading, the date, one facts line ("Undated" when
  there is no date, then network, sponsor, length: `detailFacts`), Play
  (or "Resume at" the saved position), the download control, "Start an
  ear drama" when the episode's `script` names a bundled script
  (Decision 068; never on a TV), "Automatic transcript" when the gate
  passed, Cast and credits (each a row that opens its person, §4.15), Versions (or the
  one copy's notes), and the rights line. A part with no data is absent;
  the sponsor shows only where the catalog carries the contract's
  `sponsor` column (probed, as Apple does; the pipeline computes it). Share is the top bar's action
  (§4.12).
- **§4.5 Search** is a `DockedSearchBar` ("Titles, series, people"),
  debounced, with Clear, series first, then People (§4.15), then plays (title and author,
  word-prefix), then "Aired {date}" when the query names an air date
  (`DateQuery`, contract §3.4), then episodes, then **Automatic
  transcript** (`Transcript.LABEL`): each row the episode row with the
  line where the words are said as an italic second supporting line,
  verbatim (`Transcript.snippet`), read from the transcript's own URL.
- **§4.6 Library** (direction B, owner 2026-11-23: "Most people we exclusively use this app for listening, so
  let's do option B to make it easier for them to use the app that way.") is a two-way `SingleChoiceSegmentedButtonRow`,
  **Listening** | **Making**, over one `LazyColumn`, and the foot. Listening is the default for a new person; the last
  side is remembered per device (`ed.library.side` in the `ed.library` prefs). A TV has no Making side and no control.
  *Replaced* (2026-11-23): "every section keeps its header and caption", and the separate Continue, Queue and
  Following sections. **An empty section is absent: no header, no caption.** A side with nothing at all shows one
  sentence and one button (Listening: "Nothing played yet." with Browse; Making: "No ear dramas yet." with Record a
  play, which selects the Record tab).
  - **Listening**: **Up next** merges the episodes started (with "position of length") and then the queue in the
    person's order (a queued row swipes away and long-presses for Move up, Move down, Remove: `QueueRow`); an episode
    in both shows once. Five rows, then "All N" opens `Route.LibraryList("upnext")`, the whole list. **Shows you
    follow** is the shelf of the grammar's show tiles (`ShowShelf`, newest follow first; a long press offers Unfollow,
    which asks; a follow the open catalog does not serve is kept for sync and not listed). **History** is one line with
    its count, opening `Route.LibraryList("history")`. **Downloads** is one line with the count and storage held,
    opening `Route.Downloads`: downloads grouped by series, each removable, a series' Remove and Remove All asking first, the storage held at the foot.
  - **Making** (not on a TV): **Waiting on you** (shared productions someone else directs with a speaking part open, as
    Home's Open parts), **Productions** grouped by play (`LibraryModel.groups`: one row per play, "9 productions ·
    newest finished", opening `Route.PlayProductions(scriptId)`; a play with one production is that production's row,
    with its Delete that asks first), **Marks** as one line ("In 3 scripts"), **Classes** one line per class opening its
    class page. Make a class and Join a class left Library: they are two buttons under Record's top (`ClassDoors`,
    signed in).
  - **The foot**, under either side, headed "Account and preferences", in this order: **Account** (§4.11),
    **Voices** (a disclosure row whose state reads "Kokoro · 1.0x"; tapping opens the full controls in place, no Settings
    screen; Better voices opens it and scrolls to it), **Listen together**, **Export my data**, and **About Ear Drama**
    (a disclosure row that opens the site pages, §4.11a). A TV's foot is Account, Show a reading and About.
  The four states: loading and the retry message are `LoadableContent`'s; offline is the app-wide "You are offline."
  line; empty is the absent section above. `LibraryModelTest` pins the side default, the Up next merge and the
  grouping.
- **§4.7 The transcript is a route** (`ui/screens/TranscriptScreen.kt`):
  the episode title, then plain selectable text in `bodyMedium`, a
  sentence a line, at most 680 dp wide, fetched from archive.org when
  opened.
- **§4.8 Episode rows carry two targets**: the row opens Detail ("Open
  episode") and the trailing button plays ("Play" and the title).
- **§4.9 Ear dramas** (`docs/PLAYS-DESIGN.md` binds what it does;
  `ui/screens/PlaysScreens.kt`, `RecordingScreen.kt`, `plays/`). Record
  is their tab (§4.9a, Decision 075); a play is also a row in Search, and
  a person's productions lead Record and stay in Library's Ear dramas
  (§4.6). *Replaced* (2026-11-14): "No tab of their own (Decision 068)". A play stands
  on the drama board (`PLAY_BOARD`, `board.drama`; the genre is never
  named on screen), in Browse's tiles and Search's and Surprise's rows
  as well as its own page (D3-6). The play's page (`playPage`) is
  `PlayHeadBoard`, the head board with the kicker "Radio play" or "Stage
  play", the name, the author (with born and died years when the record
  has them) as the credits, the year when it has one, "N parts" and "N
  lines", nothing invented, and the cast fingerprint in the mark slot
  (`CastFingerprint`: one bar, a segment per speaking part by its share
  of the lines, largest first, 1 px apart, in the board's one onBoard
  color); then "Record this" (was "Start an ear drama", Decision 075,
  and before that "Cast this play"; ink, the
  primary action), the parts as `PartCard`s in a grid (`PartGrid`: two
  across, three from 840 dp; a face, the name in the display face, "N
  lines", the 24-bar `PresenceStrip` in the part's hue), then the rights
  line (the evidence claims verbatim, each linked to its source, then
  the source by name). The cast sheet is the same head board (kicker
  "Ear drama"), Listen through and the share and invite verbs, then the
  same part cards with their state as the who line ("You · 5 of 76",
  "Pat · recorded", "Open", "Left silent") and the verbs in the card
  (Decision 067, batch 0b): every open part shows Take part (an
  `AlertDialog` with an optional name) while no part records, in any
  order; the part `Relay.next` suggests (the first open one) gets the
  ink button, the others the blue outlined one (`wayColors()`). Also
  Leave silent (any open sound or directions part), Record (ink), and
  Open part; the part recording is outlined in ink; then Discard unused
  takes and Delete production. Listen runs at any
  time: a finished-or-complete play plays the mix; otherwise
  `Relay.listenPlan` runs live, each take from its file and each
  speech line without one read by `TextToSpeech.speak` on a local voice
  only (never `synthesizeToFile`, never stored), with the speaker and
  words on screen and "Device voice" on those lines, and a Stop; a live
  listen writes nothing and never marks the play listened through.
  Export shows whenever the play is complete, rendering the mix if it
  is missing or stale, with no caption. Recording needs no account
  (Decision 079; *replaced* 2026-11-15: "signed out, the Start recording
  step shows "Recording needs an account." and the Library account row's
  sign-in sheet instead of the button"), and no account line stands
  beside the record control (F11). Signed out, beginning a
  production while another on this device holds a take shows "A second
  production needs an account." and the account row's sign-in sheet
  instead of the studio (PLAYS-DESIGN §2.3). Recording asks for the microphone at Start recording,
  checks the route (headphones, or a refusal line with "Record without
  headphones", which turns on echo cancellation and marks the takes
  `aec`), counts five seconds of room tone, then opens the recorder in
  direction D (R11f): the cue card (labeled "Device voice" when the
  device reads it), your line on your part's board in `displaySmall`,
  the lines around it dim, the takes, one 80 dp round control,
  Run-up, Hear it read, the device voice's speed, and Done with this
  part. Space or the headset key records, stops or pauses, Enter keeps
  (a Step review), and the arrows move by line. Takes are 24-bit WAV (not FLAC:
  MediaMuxer has no FLAC container), the mix is AAC in `mix.m4a`, and
  a complete play offers Export, through the share sheet. A device
  voice's PCM is tagged `synthetic`; every writer (`TakeAudio.write`,
  the mix renderer, an upload) refuses it, and a listen plan's voice
  entries hold text only (`StandInNeverStoredTest`).
- **D3-8 Stations, Surprise, People, a person** (D3-8, 2026-10-30) Stations, Surprise, Search's people and a person's page follow WEB-DESIGN §6.4f in this platform's idiom: `GrammarRow` gained `badge` ("Now" in the play color), `trailing` (Listen live) and `opens = false` (a row that only states); Surprise's picks are `HeadBoard`s (the play's is `PlayHeadBoard`); `PersonListItem` is a round-window row; `PersonScreen` is a head board, a `LazyRow` of `ShowTile`s, then the rows. `PersonShows` (data/GrammarRules.kt) holds the per-show years rule.
- **§4.10 Stations** (was Radio) opens with the stations row, the web's
  §4.9 as the list's first items (`stationRows`): Tonight in 19xx first,
  then each genre station from `stations.json` (`ApiClient.stations()`,
  `radio/Stations.kt`), one `ListItem` each with the station's name
  (`titleMedium`), what is on now (series, then title), and a trailing
  "Listen live" (the ink play button; "Listening live" outlined in ink
  while on, which pauses). Tonight's row carries "Starts at" / "Ended at"
  outside the evening, so the evening's header no longer does. A genre
  station tunes in through the same `LiveRadio` with the next twelve
  hours' slots, resolved in the open catalog on tap. On a TV the first
  Listen live takes focus on entry. Then Tonight in 19xx (`RadioScreen`,
  `ui/screens/RadioScreen.kt`), the web's §4.9 in a `LazyColumn` of
  `ListItem`s: the evening `tonight.json` publishes for the device's own
  calendar date (`RadioClock.localDate`, never the UTC date), fetched
  through `ApiClient.tonight()` from the catalog's Release (contract §2,
  §8) and resolved against the open catalog (`RadioLoad`). A header of
  "Tonight in 1942" (`headlineSmall`, a heading), the evening's date, and
  the network and station; when the date offers other published years
  (Decision 067), a "Year 1947" text button opens a menu of them, and
  picking one loads that year's whole evening on tonight's clock (and ends
  listening live); then one row a slot. An evening shows whenever any of
  its programs survives. Each row leads with its
  local time (`bodySmall`, tabular) and the paper's Eastern time beneath
  it ("7:00 PM ET" alone where the two agree). The slot on the air says
  "Now", takes the `surfaceVariant` container and the ink edge (§6.1a), and is marked selected
  for TalkBack, repainted every 15 seconds from the file's instants. A
  surviving slot opens its episode ("Open episode") and has a trailing
  Play that plays it from its start (§4.8); a gap is muted, not
  clickable: `known_series` where the file sets it, then "Not surviving"
  (or "Not in the catalog" for a withheld slot or one the open catalog
  lacks), and its length. The newspaper's printed text is never drawn
  (Decision 067); the file no longer carries it. Before the evening Tonight's row says "Starts at",
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
- **§4.11a The site pages** close Library: three `ListItem`s, "Credits",
  "Privacy", "Take-down requests", each opened in a Custom Tab
  (`SiteLinks.CREDITS`, `PRIVACY`, `TAKEDOWN`). An empty Library keeps
  them in the foot (§4.6, §7.1a). A TV shows the address as supporting text
  and opens nothing.
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
  `PlaybackEngine`, and the player sheet's skip, seek, and speed are
  disabled for a guest (a code lets someone listen, never drive). Play and
  Pause stay the guest's own (Decision 067): pausing, from the sheet, the
  notification, or a headset, holds their sound while the room plays on;
  playing catches them up to where the host is now (`ListenTogether.hold`,
  reported by `PlaybackEngine.onGuestHold`); a held guest handed the room
  takes it from where the room is. When the host leaves
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

- **§4.9b The voices on the cast sheet** (Decision 076 S2; PLAYS-DESIGN §2.8 is
  binding; owner 2026-11-14: *"The virtual voices who play the different parts should
  also be intuitive."*; WEB-DESIGN §4.10 for the shared words; port spec
  `docs/research/design/R2-voices-port-brief.md`). Built 2026-11-14 (PARITY 🚧). Every part no
  person holds shows an `AssistChip` with the voice's name (and a warning icon when its
  cast voice is gone and the auto-cast one reads), "Not read" for directions and sound.
  The chip opens a `ModalBottomSheet` picker: Speed and Pitch as − value + steppers,
  then "On this device": `TextToSpeech.getVoices()` filtered to English and
  `!isNetworkConnectionRequired` and without `KEY_FEATURE_NOT_INSTALLED`, sorted by
  `quality` (500 down to 100), then the person's locale, then name, leaving out the
  locale stand-in (`en-US-language`, feature `legacySetLanguageVoice`, the same speaker
  as `en-us-x-iog-local` on the Pixel 8a); a voice's label is what it sounds like and
  its accent (PLAYS-DESIGN §2.8 rule 12; *replaced* 2026-11-23: "its locale's display
  name, numbered in sort order when two share a locale ("English (United States) 2")",
  which the owner could not choose by): "Low, warm · US", from `VoiceLabels.SEED` for
  Google's voices, else measured once on the device (`VoiceTraitStore`, four numbers in
  `ed.voicetraits`, about 0.7 s a voice, the sound never kept), with "High quality"
  under it when the engine reports quality 400 or more. A chip drops the accent when
  every voice here shares it ("Low, warm") and ellipsizes at the end, so the words that
  tell voices apart lead. The sheet is full height on a phone
  (`skipPartiallyExpanded = true`). Recast all sits with the cast sheet's manage actions;
  on a TV the chips and picker are absent and the listen-through reads the cast. The
  reader's top bar has Voices (`RecordVoiceOver`: every part with its chip, Recast all)
  and its bottom bar Hear the cast / Stop (icon only below 600 dp), a one-line "Device
  voice · PART" above the bar while it reads. Voices are re-read when the engine is up
  and on every resume. Each row is a `RadioButton` row with a play
  `IconButton` that reads the part's first line. **Get more voices** sends
  `TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA` to the engine's installer. Android
  reports no voice gender, so auto-cast alternates by voice only. The cast is a
  `VoiceCast` in `plays/` read by `SystemStandInVoice`, the live listen-through and the
  reader's Hear the cast; kept in `SharedPreferences` (`ed.cast`), never synced.
  **Downloaded** (Kokoro, Decision 078, S6d; PLAYS-DESIGN §2.8 rule 10; built
  2026-11-15, PARITY 🚧): below "On this device" and Get more voices, the picker's
  "Downloaded" heading, then an `OutlinedButton` with the download icon, "Download voices
  (126 MB)" (the engine module and the model); while downloading a `LinearProgressIndicator`
  with "34 MB of 126 MB" and a
  Cancel `TextButton`; once here the 28 Kokoro voices as the same radio rows with play
  buttons ("Heart (Kokoro)", best grade first), a "Delete downloaded voices (107 MB)"
  `TextButton`, and the attribution line in `labelMedium`. The model (`kokoro-v2-manifest.json`'s
  three files from the Release `kokoro-model`: the q8 model, since v1's q8f16 renders NaN on
  ONNX Runtime Android) is fetched by `kokoro/KokoroModelStore.kt`
  on the one Ktor client in the app's scope (leaving the sheet does not stop it), resumed
  with `Range`, checked by SHA-256, kept under `filesDir/kokoro/v2`. `kokoro/KokoroReader.kt`
  reads the play's `phonemes/<id>.json` through the library transport, renders on ONNX
  Runtime (`OrtKokoroRenderer`, CPU, in 100-symbol pieces with an arena that shrinks after every
  render) on one background thread, refuses NaN or silent
  renders, and marks every buffer synthetic; `KokoroLive` plays a line once through an
  `AudioTrack` (nothing at all when muted) for Hear the cast, the listen-through and the
  preview, and `plays/KokoroStandIn.kt` hands the recorder's cue path a `StandInAudio`.
  DEBUG only: `KokoroBenchActivity` (the S6a bench, `src/debug/`). **Download on demand** (owner 2026-11-15): ONNX Runtime and
  `OrtKokoroRenderer` are the on-demand Play Feature Delivery module `:kokoro`, never in the
  base install. Download voices first asks Play for the module (`kokoro/KokoroModule.kt`,
  `SplitInstallManager`), then fetches the model; the button's size and the one progress line
  count both. The states: "Waiting" (pending), the bytes (downloading), "Installing", Play's own
  sheet behind **Continue download** when it asks first, "The download failed." with Try again,
  and the voices once both are here. The base reaches the engine only through `KokoroEngines`
  (by reflection, `SplitCompat` in the Application); Delete removes the model and asks Play to
  uninstall the module. A build not from Play (a sideloaded APK, Fire TV) cannot install it and
  says the download failed. The bench and local runs use `bundletool build-apks --local-testing`.
  The whole group and the cue path sit behind `BuildConfig.KOKORO_VOICES` (on; the S6a gate
  passed on the Pixel 8a 2026-11-15, R2-kokoro-feasibility "S6a on the Pixel 8a").


- **§4.9a Record** (Decision 075; the web's §4.15 is the shared rule;
  not on a TV). The tab's root is a `LazyColumn`: **Yours** (this device's
  productions and the shared ones not yet opened, each "n of m lines
  recorded", "Finished" or "Shared"; a production with no take is never a
  row and is deleted when the studio closes without one and whenever the
  store loads, PLAYS-DESIGN §2.3 rule 3a; absent when empty), **Today's
  scene** (§4.1's card; *replaced* 2026-11-15: "Today's play
  (`PlayHeadBoard` with Record this and Parts)"), **Plays** under a row of
  `FilterChip`s with menus (Voices 1-2 / 3-5 / 6-10 / 11+; Length Under
  30 min / 30-60 min / Over an hour, `minutesOf` at 150 words a minute;
  Kind Radio play / Stage play; Sort Fewest voices, Shortest, A to Z),
  each play a tile whose window draws its cast (one bar per speaking
  part, largest first, up to seven, in the board's one color, "+N" for the rest; the Today's play board wears the same window)
  with "N voices · About M min", then **Made here**. Author lines use
  each author's `display` name.

- **§4.14 Surprise** (`ui/screens/SurpriseScreen.kt`; Archive Watch
  PARITY §5) is a `LazyColumn` of three picks drawn when it opens, and a
  Shuffle action in its top bar: **an episode** (a served, recommendable
  episode with a recording, at random, `CatalogDatabase.randomEpisode`)
  with Play; **an evening** (one of `tonight.json`'s evenings), its date
  and network, with Play, which plays its first surviving slot from the
  start, never live and never a queue; **a play** (one castable script)
  with "Record this", not on a TV. Each plays or starts in one
  tap. `kotlin.random.Random`: nothing needs to match another device. No
  copy is written; a pick with no data is absent.
- **§4.15 A person** (`ui/screens/PersonScreen.kt`, `Route.Person`;
  `withPerson`) is a push from a Detail credit or Search's People, at the
  depth of a series (§1.4): a top bar with the name and Back, the
  portrait when one is served (`FaceFigure`), one Meta line of the years
  from the people row and the episode count, a
  `SingleChoiceSegmentedButtonRow` of Oldest first and Newest first (only
  with more than one episode; selection haptic on change), then a
  `SectionHeader` per series and `EpisodeListItem` rows whose supporting
  line names the roles ("Cast as Mrs. Stevenson, Writer"), each with
  Play. Undated last either way. On a TV the D-pad starts on the first
  episode. No bio is written (R13).

- **§4.16 Shared ear dramas, phase 2** (binding rule: `docs/PLAYS-DESIGN.md`
  §11.7, "The same verbs on the web, iPhone, iPad, Mac, and Android (§8
  rule 7); Apple TV and the other TVs play back only and offer none of it.
  ... Every call goes through the platform's one API client, refreshed
  first. Words on screen are these, on every platform."). Android's idiom
  (`ui/screens/SharedPlaysScreens.kt`; logic in `plays/PlaysShare.kt`, pure
  Kotlin, ported from `js/plays-share.js`; calls in `plays/PlaysApi.kt`
  on `WorkerApi`, which refreshes before each one):
  - The cast sheet (§4.9) gains, for a signed-in person, **Share** (a
    dialog with an optional name; signed out: "Sharing needs an account."
    over the account row). `share.json` (`{ pid, consented }`) sits beside
    `production.json` in `filesDir/Plays/<id>/`. A shared sheet shows each
    part's Worker state and performer; Record for mine, **Take part** for an
    open part while none records (the `next` part filled, the rest
    outlined), **Leave silent** for sound and directions, **Open part** in
    the `⋮` menu for a finished part while none records, **Release** for
    mine. The director's **Invite** puts the link
    (`https://eardrama.org/invite#{token}`) in the system share sheet and
    shows "Works for N days.". **Upload N takes** is a `Button`; while the
    Worker's `uploads` is false it is replaced by "Uploads are off.".
    Uploading asks no consent (Decision 072); no consent dialog until the
    consent screen ships. **Done with this part** finishes a part
    once its takes are up. **People** lists members with "You" and
    "Director" tags, and Report (reason list and an optional note) and
    Block (confirm: "You will no longer hear their takes.") for the rest.
    **Publish** (rule 9) opens an `AlertDialog` with the Worker's consent
    words and "I agree to publish my recording under CC0." / "Not now", and
    is offered only while `GET /consent` says `publishes`, else "Publishing
    opens when the Ear Drama archive account is connected."; the archive.org job reads as PLAYS-DESIGN rule 9 (a quiet line, **On archive.org** opened with `LocalUriHandler`, or the reason with **Publish again**); once published, "Your lines" (director: "Lines") rows with **Replace** (the recorder route with a `line`) and **Remove** (an `AlertDialog`, error color, rule 13). The record is re-read every
    20 s while the screen is started and at once on every return to it
    (`repeatOnLifecycle(STARTED)`), never in the background. "N takes are hidden from you." stands under Listen.
  - Listen through fetches the other members' chosen takes into the
    production's `takes/` as files that are never overwritten, then runs
    §4.9's listen-through; another member's line shows **Report**.
  - An invite link is parsed by `DeepLink.parse` into the inbox
    (`InboxRequest.Invite`), which holds the token for the session and
    selects Library. Library's Ear dramas then lists an **Invitation**
    (title and parts; signed out: "Sign in to join"; signed in: **Take
    part** per open part with an optional name, **Open** for a member,
    **Not now**), this device's productions, the shared ones this person is
    in that the device has not opened, and, signed in, **Classes** (**Make a
    class** with Under 13, the code in two groups of four, **Join a
    class**). The manifest's https filters stay as §3.4 has them. A TV draws
    none of it.

- **§4.17 The script reader** (Decision 076 S1; PLAYS-DESIGN §2.7 binding on
  the verbs; WEB-DESIGN §4.16 the sibling; port spec
  `docs/research/design/R2-reader-port-brief.md`). **Read** (a `TextButton`
  beside Record this, and a book `IconButton` on each Record tile) opens
  `Route.Reader(scriptId, lineId?)`, full screen over the bottom bar, no
  account. A `TopAppBar` (Close, the title over the act and scene, then
  Contents, Search and Text icons with content descriptions); a bottom bar
  with **I'm playing** (an `ExposedDropdownMenuBox`), Next line, Hide my
  lines (an `IconToggleButton`) and the page count.
  - **Pages by default**: the script paginated with `TextMeasurer` at the
    current font scale into pages, shown in a `HorizontalPager` (a slide,
    never a curl; `beyondViewportPageCount = 1`). Two facing pages when the
    reader holds 860 dp or more (a tablet, an open foldable in book
    posture; the same rule as Apple and web, `ReaderMath.SPREAD_MIN`),
    one otherwise. Turns: swipe; a tap on the outer fifth; hardware keys and
    pedals (DPAD left/right/up/down, PAGE_UP/PAGE_DOWN, SPACE) through
    `onPreviewKeyEvent`; and an opt-in **Volume keys turn pages** in Text.
    **Scroll** (a setting): a `LazyColumn` keyed by line id.
  - **Position** is a line id per script in `SharedPreferences` with the
    part; a font-scale, text size, spacing, rotation or fold change
    re-paginates and `scrollToPage` the page holding that line
    (`rememberSaveable` survives the configuration change).
  - **Text**, **Contents**, **Search** are `ModalBottomSheet`s (size over
    seven steps on top of the system font scale, spacing, Pages / Scroll;
    acts with scenes; a search field over `PlaysCore.search`).
  - **I'm playing**: the part's lines carry a start rule and tint in its
    hue; Hide my lines draws its words as rounded bars in the hue (still
    measured, so pages stay put); a tap peeks one.
  - **The Ear Drama page** (PLAYS-DESIGN §2.7 rule 10, binding; frames in
    `docs/research/design/R2-play-typography.md`). `PlayPage.layoutOf`, `isVerse` and `cueTail` (`plays/PlayPage.kt`) carry
    the web's fixtures as tests; blocks are measured with `TextMeasurer`
    and cut by `ReaderPagination` (keep-with-next, widow and orphan, verse rows). Per speech: the name in `titleMedium` in the part's hue over the
    words (`bodyMedium`), never the last item measured on a page; when a page
    is 30 em or wider (expanded width) the name sits in a right-aligned
    8.5 em column in a `Row`. Verse is one `Text` per printed line with a
    hanging turnover indent (`ParagraphStyle(textIndent = TextIndent(0.sp,
    rest = 1.5.em))`); a direction inside a speech an italic
    `onSurfaceVariant` span with the parentheses added in the
    `AnnotatedString` (never stored); a stage direction an indented italic
    paragraph with a part named in capitals in its hue; a cue a row with
    the Material `volume_up` symbol and the cue in `labelMedium` capitals on
    a `surfaceContainerHigh` shape. The front page (title, authors, Parts in
    their hues); an act opens a page; "NAME (cont'd)" heads a page that opens
    inside a speech; the cue before each of my speeches underlined in my hue.
    TalkBack reads each speech as one node: the name, then the words.
  - Not on a TV: Android TV and Fire TV get the read-along panel of
    tvOS-DESIGN §4.13 (PLAYS-DESIGN §2.11 rule 10), a listen-through panel of
    the line heard with one before and one after, 28 sp body, no focus.
    **A read room's shared screen** (Decision 082, PLAYS-DESIGN §12.2 and §12.10 item 9; built 2026-11-19, Round 3 T5): **Show a reading** is a row in the
    TV's Library (`Route.ReadPair`; also `eardrama://read/pair` and the DEBUG door `appname_start_read_pair`). `ReadPairScreen` asks `POST /v1/read/pair` and shows the
    pairing code at `displayLarge`, split 3 + 3, with one line ("On the leader's device: Reading, then Add a screen."); it asks `GET /v1/read/pair/{code}` every
    2 seconds, replaces an expired code without a word (`ReadPairing`), and when a leader types the code under Reading, Add a screen, the answer is the room as the TV's
    screen: the same panel follows the **room's cursor** (the current line, one before and one after, part names, the room code and how many are here in a corner). The TV never
    asks for typing. It speaks an unheld line only while the leader's Read open parts is on, never during a take; it records nothing, holds no part, never leads;
    one **Leave** button holds focus. Fire TV the same (no Play services needed: the room is the Worker's). Not rendered on a real TV yet (Roborazzi at 1920x1080 only).
  - **Read along** (PLAYS-DESIGN §2.11, rewritten 2026-11-23; port from iOS-DESIGN §4.15a): a production's
    Read along opens the reader and starts reading at once; the listen plan's line id drives `follow`; a touch
    stops the turning and **Back to the line** returns. Built 2026-11-23: `AlongModel` plays the plan (takes from
    file, other lines live in the part's cast voice) and holds the line heard; the word comes from
    `UtteranceProgressListener.onRangeStart` through `CastSpeaker.onRange` and `ReadAlong.spoken`/`word`
    (a hue fill and a 2 dp rule on the TextMeasurer page, drawn over the layout so a word never re-measures);
    a **Kokoro** line lights the line only, because the ONNX export has no duration output (never estimated);
    the pager turns on the word when a speech runs onto a page not in view (`animateScrollToPage`, a cut under
    Remove animations; Scroll scrolls the block into view); Hear the cast is the same model; the transport
    replaces the reader's bottom bar (speaker in hue, previous, play or pause, next, a speed `DropdownMenu` of
    0.5x to 2x, stop; the page count from 600 dp); `ed.along.speed` in the `ed.reader` prefs; takes at
    `MediaPlayer` speed with the pitch kept, a finished drama's files at `PlaybackEngine.setSpeed`. A muted
    door speaks at volume 0 so the engine's callbacks still run. Code comments cite rules 10 and 11. A **finished ear drama's** page
    plays the item's per-line MP3s as one playlist (`PlaybackEngine.playFiles`, rows
    `drama:{id}:{n}`) and offers **Read along** beside Listen when the files map onto the
    script (PLAYS-DESIGN §2.11 rule 11): `Route.Reader(along, drama)`, the row playing being
    the line heard. On a TV the drama page shows `ReadAlongPanel` under Listen.
  - **The studio** (Decision 076 S3; PLAYS-DESIGN §2.9 binding; web sibling
    WEB-DESIGN §4.16 item 14; port spec `docs/research/design/R2-studio-port-brief.md`).
    `Route.Reader(scriptId, lineId?, productionId?, part?)`: the cast sheet's
    Take part / Record / Open part and the reader's **Record** (bottom bar,
    once a part is chosen) open the reader with the studio attached; the
    `RecordingSession` engine and take model stay, plus `deleteTake` (refused for
    the chosen take) and a part-scoped `discardUnused`. Each of my lines shows
    its take state after the name (`radio_button_unchecked`, a filled circle
    with the count in the hue, `warning`), a click target that makes the line
    current and opens its take list. Every other part's line a device voice
    reads carries, after the name, a dashed ring in the part's hue with
    `GraphicEq` and the voice's short name ("Zoe"), a click target that opens
    that part's voice picker; none on a line with a usable human take
    (PLAYS-DESIGN §2.9 rule 3a, 2026-11-15). The transport ends with Listen from
    here (`PlayArrow`, Stop while it plays); in Run through with no run on, a
    line holding a take shows **Again** in the status line and that single
    take's round control reads Cancel / Stop (rules 5, 6). **Compact**: a bottom dock in the
    `Scaffold` (the `SingleChoiceSegmentedButtonRow`, the status line with the
    level meter, Previous / record / Next / Hide my lines), the take list, cast,
    Listen through from here, Delete unused takes and Done with this part in a
    `ModalBottomSheet`. **Expanded** (the reader holds 860 dp or more: a
    tablet, an open foldable): a `SupportingPaneScaffold` with the reader as
    the main pane and the studio as the supporting pane; in tabletop posture
    the dock sits below the hinge (`currentWindowAdaptiveInfo().windowPosture`).
    Hardware keys and pedals: SPACE record / stop, J / K my lines, R again,
    ENTER keep.
    The studio reads in Pages even when Scroll is set (a line is whole only
    on a page); Scroll returns when the studio is left. The DEBUG doors
    `appname_start_studio` (a role name, with `appname_start_read`),
    `appname_studio_stub` (an engine that opens no microphone and plays
    nothing; a heard line is a synthetic tone, never room audio) and
    `appname_studio_phase` (`idle`, `listening`, `takes`) exist for frames; the
    mute door silences take playback and cue voices too. A voice chip names a
    voice by its distinguishing part (a region in initials, the number kept).
  - **Marks** (Decision 076 S5; PLAYS-DESIGN §2.10 binding; web sibling WEB-DESIGN
    §4.16 item 15; port spec `docs/research/design/R2-marks-port-brief.md`).
    `plays/MarksCore.kt` mirrors `js/marks-core.js` (anchor, `snapWords`,
    `pointAfter`, overlap, `place` over `catalog/tests/golden/marks_anchor.json`,
    notebook order); marks live in Room (`MarkEntity`, keyed by script id and mark
    id; never in the backup's cloud rules until the sync phase).
    - **Selecting**: each measured page takes Compose's own text selection
      (`SelectionContainer` around the page's blocks, or the measured
      `TextLayoutResult` hit-tested for a long-press and drag with the system's
      handles, whichever keeps the page's measured layout); the selection maps to (line id, offset)
      through each drawn run's offset. The floating text toolbar (`TextToolbar`,
      the system's own) gains **Highlight, Underline, Breath, Pause, Beat, Note**
      after Copy, as the Android text-processing menu does; a tap on a mark opens
      a small `DropdownMenu` anchored to it (the four hues and Delete, Edit and
      Delete for a beat or note), a delete answered by a `Snackbar` with Undo.
    - **As built (2026-11-15)**: the page is canvas-drawn, so selection is the measured
      `TextLayoutResult` hit-tested (long press selects a word, a drag or a handle extends it;
      a long press that selects nothing is swallowed, never a page turn) and the system's floating
      toolbar is an `ActionMode` (`TYPE_FLOATING`) with Copy and the six actions. Each block keeps a
      map of its drawn runs to the line's words; a breath, pause, beat or note's end takes room as
      page-drawn text in the block (the page re-measures), never in `lineText`. Scroll mode selects
      within one block.
    - **Drawing**: highlights as a `drawBehind` fill over the run's boxes
      (`markColor(key, dark)`, the generated token), underlines as a 2 dp
      `onSurface` rule, a note's dotted rule with the `sticky_note_2` glyph;
      breath, pause and beat drawn by the page in the gap after their word (the
      beat's label in `labelSmall` capitals in an outline), never added to the
      text; a point mark re-measures the page.
    - **Notebook**: **Marks** (a `bookmark` `IconButton` in the top app bar)
      opens a `ModalBottomSheet`: a Show marks `Switch`, then a `LazyColumn` in
      script order (glyph, speaker in `labelMedium`, the words, a beat's label, a
      note), a tap going to the line; **Not placed** after, each with Delete.
      Empty: "Select words on the page to mark them."
    - **Stylus ink** (the Ink API, `androidx.ink`) is a later phase, not parity
      blocking: an iPad's ink draws nowhere on Android until then (PARITY ⏳).
    - Hardware keys with a selection: H, U, /, P, B, N; Esc lets go. TalkBack:
      each mark is a custom accessibility action on its speech.
    - Export: `DataExport` adds `marks[]` (docs/EXPORT.md).

- **§4.19 Reading together** (T4 2026-11-19, T5 2026-11-19; `ui/screens/ReadScreens.kt`, `ui/screens/ReaderRoom.kt`, `plays/ReadSession.kt`, `plays/ReadRecord.kt`, `plays/ReadPairing.kt`). Binding rule: PLAYS-DESIGN §12 (§12.10 is T5's) and Decision 082. The verbs are the web's (WEB-DESIGN §4.17 to §4.19). **The room drives the existing reader** (T5 closes T4's defect: T4 had drawn a separate plain list): `ReadRoomScreen` joins, then renders `ReaderScreen(room = RoomSeam)`, so the page turns on its own measured layout. The seam, like the studio's, follows the room's cursor with `ReadAlong.Follow` (the page turns to the cursor and lights it; a touch on the page stops the turning and shows **Back to the line**); the lines this device holds are tinted from the room (a part's claims, or a class seat's assignment ranges: `Mine`, a set of line indexes beside the studio's single role); **Hide my lines** is the room bar's, only in Rehearse, the cursor's line never hidden; one fact above the buttons ("Next: you, in N lines", "Ann is reading", "Waiting for Ann"); the part menu, the studio's Record and Hear the cast are not drawn in a room (no sound from a reader device). Join: a code by link or typed opens a join screen with the code and an optional name (40 characters; the last typed is kept in `ed.read`, the app has no chosen name to start from; a class room asks for the seat instead); `no_such_room` reads "No reading with that code." and `room_ended` "This reading has ended.", kept from the Worker's code by the shared client (`WorkerReadWire` maps the body's `error`; a test holds a 404 and a 410 to their words). **The room bar** (`RoomBar`): the fact, "N here", Parts (an adult room), and for the leader Back, Next, Again (Rehearse) and the **Reading** menu: mode (Table read, Rehearse, Record), Record every line here (Record mode), Lock joining, Read open parts, Open the screen, **Add a screen** (type the code a TV shows; "No screen shows that code.", "That code has expired."), End the reading. **Record in the room** (`ReadRecord`, the Kotlin mirror of js/read-record.js; the engine is `RecordingSession.recordInRoom`: no cue, `room` capture, the line's own part): in Record mode the **Record row** shows **Start recording** (the microphone permission, five seconds of room tone, once per room), **Recording** with **Stop** (red, the one place red appears), "Quiet while others record", "N takes on this device"; the take is written on the device first (a per-room local production, `Production.room`, with its outbox persisted), then sent to the receiver with `PUT /v1/read/{code}/takes/{id}`; `nobody_receiving`, offline, a timeout or a 5xx keeps it in the outbox and it is sent again every 5 seconds and on every snapshot. The receiver (`you.receives`) holds the pickup and imports each arrival as the line's chosen take; it records only in One microphone, which credits the line's part, keeps the take as the director's own and moves the cursor on. **Takes** (the receiver's sheet): counts per reader, each speaking line with Recorded / On <name>'s device / Waiting / Open, Play, Again, and in a class production Approve and Again, which offers an optional note; the class page lists takes that reached this app under Review (Play, Approve, Again, an optional note); **Listen through** and **Export** are the production page's own (`ListenThrough`); **Publish under my name** only in a class marked 13 and over with every line taken (credit name, the CC0 consent, `publish { credit_name }`, then `RoomPublish` sends each chosen take to `archive/files` one at a time, `not_ready` waits a minute and tries again, `already_sent` is skipped); an under-13 class shows "An under-13 class never publishes.". The teacher's class page and casting board are as in T4. Refusals and warnings use `ReadCore.refusal`'s words, one line. **NOT built**: the leader's arrow keys; dragging a part onto a seat; the receiver's takes are not synced to a second device; none of the microphone path has run on a real device (tests use fakes and the `appname_studio_stub` door). **TV panel rule**: a Google TV opens every room as the shared screen (`ReadScreenScreen`, or `ReadPairScreen` for Show a reading below): the line large with one before and one after, the code, who is here, one **Leave** button holding focus; it holds no part, leads nothing and records nothing (rule 12). While the leader's Read open parts is on, the screen's live device voice reads a line nobody holds and stops the moment the cursor moves (`openVoiceLine`); nothing is stored.
- **§4.21 Your parts and Relay across time** (T6, 2026-11-19; `ui/screens/PartsScreen.kt`, `plays/RelayAcrossTime.kt`). Binding rule: PLAYS-DESIGN §12.11 and Decision 083. **Your parts** is a text button on the room's join screen (`Route.Parts`; not on a TV): the class code, then the names; the key is sealed under an Android Keystore key in `noBackupFilesDir/seats`, the class and name in `home-seats.json`. Each class production shows a part's name and line count with **Record** (the reader's studio on a production kept on this device) and every line with its take's state, as on the web (WEB-DESIGN §4.20 item 2). `RelayHub` holds one `RelaySender` per linked production; the ask, the back-off (5, 10, 20, 40, then 60 s) and the states are RelayCore's. The class page holds each production's pickup while it is open (`ClassInbox`). Roborazzi `android-relay-*` draws the waiting and sent states (`RelayRenderTest`). NOT built: a WorkManager job to send while the app is closed (the sender runs while the app is open, as the ruling says). Free plan (2026-11-23, PLAYS-DESIGN §12.11 item 4): the class page's pickup runs only while the screen is STARTED, stops after 30 minutes with no take and shows **Keep receiving takes** (a `Button` above the page); a backgrounded app makes no retry ask.

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
  `NavigationBar` item, chips, every filled button that is not the
  primary action, spinners, and the download bar follow it with no
  override. Links and the TV focus ring take `OnAir.colors.link`. Ink
  (the brand `primary`) is the primary action, set by hand through
  `OnAir.colors.play` (`playButtonColors()` on a filled button): Play
  and Pause on the player and the mini player, Play on Detail, Listen
  through, the progress line and the scrubber (the player's and a play's
  mix), the slot on the air (a 4 dp leading edge), and Listen live and
  Listening live. Red (the brand `record`) means recording and nothing
  else (owner, 2026-10-29: *"Red means recording."*), through
  `OnAir.colors.record` (`recordButtonColors()`): Start recording, the
  record control, and "Your line" while the microphone is open. M3's
  `tertiary` holds the red, so no default component reaches it, and
  dynamic color never changes `OnAir`. Genre hues are content: a series
  row's 4 dp leading mark (`OnAir.genre(key)`, the border color for a key
  the palette does not name), never a button, a tab, or a link. Tab icons
  are unchanged. `ColorRolesTest` fails on the red reached any other way
  or outside `RecordingScreen.kt` and `Recorder.kt`, on a non-blue M3 `primary`, and on a
  token genre with no mark.
- **§6.2 Six type levels** (`AppTypography`, `ui/theme/Type.kt`):
  `displaySmall`, `headlineSmall`, `titleMedium`, `bodyMedium`,
  `labelMedium`, `bodySmall` with tabular figures. `displaySmall` and
  `headlineSmall` set the bundled Big Shoulders Bold (`res/font`,
  Decision 060); the rest set the system face.
  Refuse a seventh; `TypeLevelsTest` fails on any other style named.
- **§6.3 Icons are Material Symbols** (R-ICON-1); the skip icons are
  Media3's own.
- **§6.4 Haptics use the one taxonomy**, mapped in one place
  (`ui/Haptics.kt`, `Haptic`): `selection` on a tab, season, or filter
  change, when "Your line" begins, and on the mix's Play and Pause;
  `success` when a download finishes; `error` when "Download failed",
  the player's problem line, a plays refusal line, or "Tonight could not
  load." appears.

- **§6.r The label is the default art** (Decision 081; the shared rule is WEB-DESIGN §6.4r, R3a
  §3.4). Wherever this doc names the typographic card, the title block or the initial as the art
  of something without a picture, that art is now **the label**: a flat transcription disc drawn
  natively (Compose `Canvas`) from the same `labelSpec` goldens as the web (`cross-platform-determinism`):
  genre board, a run arc on the 1930-1962 dial, the monogram or the episode's date on the label,
  network · decade on the rim at tier L from `series.network`; a finished ear drama's part-hue rim;
  a person's groove ring; a play's script page with voice-band rules. A picture that passes the
  size floor always wins, and the two never share an object's slot. Networks and sponsors are names
  in our type, never logos; user-made ear dramas never take an uploaded picture. The media notification and Android Auto show the episode's label as the session art. Built in
  Round 3 V4.

## §7 States and accessibility

- **§7.1 Every query has four states** (`Loadable`): Loading (a labeled
  spinner), Ready, NoCatalog ("No catalog on this device yet.", or "You
  are offline." when the device has no network, Try again), and Failed
  ("The catalog could not be read.", Try again). An empty result is an
  `EmptyMessage` sentence; "This episode is not in the catalog." has no
  retry. Offline is a degraded mode, not a failure (web §7.3): while the
  device reports no network, "You are offline." sits in the flow above
  the mini player, in the neutral color (`OfflineLine`); the
  `appname_force_offline` door holds it for a screenshot.
- **§7.1a One empty state: the fact and at most one action** (P4,
  2026-10-28). The rule it serves (AGENTS.md, owner): "Only essential
  words on screen. A caption must be a refusal, a warning, or a fact the
  person cannot discover by looking." `EmptyMessage(text, action =
  EmptyAction(label) { })` (`ui/Components.kt`) is every empty state: the
  sentence and, when one helps, one tonal button. It never replaces
  navigation: an empty Library side shows "Nothing played yet." with Browse
  (it selects the Browse tab, with the `selection` haptic) under the side
  control, and the foot (Account and preferences) below, signed
  in or out. Browse with nothing matching offers "Clear filters". No
  results echo the query, "No matches for “{query}”.". On a TV the
  action takes the D-pad focus (`ClaimTvFocus`), except Browse's, which
  leaves the focus on the chip just pressed (`claimTvFocus = false`).
- **§7.1b No hints**, as iOS §7.5: each candidate repeats a visible
  control (Detail's "Add to queue"), and Search finding words
  said in an episode belongs in the search placeholder (the owner's copy
  call). No dismissal store, no "Show tips again"; Android has no
  Settings screen to hold one (§4.11).
- **§7.2 The transcript has its own states**: loading, "You are
  offline." or "The transcript did not load." with Try again.
- **§7.3 TalkBack.** Section headers and the Detail title are
  `heading()`; rows carry `onClickLabel`s; the slider has a description
  and a state ("m:ss of m:ss"); speed and the sleep timer announce their
  value; font scaling applies because every style is in `sp`.

## §8 Values

The rights line, the transcript label, and volume leveling are as in
§1.6 and are not reworded. A downloaded file is played, never exported:
no share or open-with action (`ui/Downloads.kt`). Playback prefers the
finished file (`DownloadStore.localFile`); a queued, running, failed, or
partial download never plays. WorkManager runs at most four downloads at
once, and OkHttp follows archive.org's redirect to its storage node. A finished play's mix
is the one file the app shares, and only when the person presses Export
(`FileProvider`, `Plays/` only). Share (§4.12) sends a link, never a file. A device voice is never written to a
file (`StandInNeverStoredTest`). No analytics.

## §9 Stubs that live in the Android build, and parity

- **§9.1 Android Auto** (`playback/CarLibrary.kt`) is the browse tree the
  service serves: four roots, Continue, Stations, Browse, Downloads (R17).
  Continue lists this device's in-progress episodes as playable nodes
  (title, series and date) within an 8 s budget; Downloads lists the
  finished downloads, newest first, each playing its file; Stations and
  Browse are empty. No artwork. Every release with car support waits on Google's
  car review.
- **§9.2 Android TV and Fire TV** are a runtime branch of the one app
  (`ui/Television.kt`, `isTelevision()`), never a flavor. On a TV the
  focused card wears a ring and a 1.06 scale (`tvFocusMark`), never
  color alone, and each tab's screen claims focus on entry
  (`ClaimTvFocus`): Home its first card, Browse its first filter chip,
  Stations its Listen live button during the evening (else its first slot),
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
- **§9.2a The TV safe area and the focus claim** (2026-11-14, from the
  Google TV Streamer check; owner: *"The android tv should be available
  too. Are you testing features on everything?"*). On a TV the whole app
  sits inside a safe area of 48 dp at each side and 27 dp at the top and
  bottom (Google's TV layout guidance: 5% of the 960 x 540 dp screen, so
  96 x 54 px at 1080p), applied once around the tab surface
  (`TvSafeHorizontal`, `TvSafeVertical`): the rail, every top bar, the
  rows and chips, and the mini player are inside it, and the background
  still fills the screen. A focused control at least 400 dp wide wears
  the ring without the 1.06 scale, so a wide row never grows under the
  rail or into the cut. Initial focus (`ClaimTvFocus`) is requested where
  the target is drawn, once its content has loaded, every frame until it
  takes, and never after the listener has pressed a key since the screen
  opened (`TvFocusClock`): a claim that waits on data must not pull focus
  back from the rail. Surprise claims its first Play. Down from Home's
  On the air row lands on Listen live, not All stations. Home keeps its
  rows across navigation (`ScreenMemo`), so Back draws it at once.
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

**R14 Dates and recordings never show raw archive text** (owner, 2026-10-31: *"We want to be both unambiguous and well designed. Spelling out the month (or abbreviating it for space) is far better."*; AGENTS.md: raw upload text never shows). `formatAirDate` is the one formatter for rows, event lines, the media session and Android Auto ("Sep 17, 1949" in the device's medium format, "Sep 1949", "1949"); `formatAirDateLong` is the long form for Detail. Recordings (the section is now named Recordings, not Versions) are named by `RecordingLabel` (`recordings.label` behind a column-exists guard, else its kbps and length, best copy marked); the archive.org identifier never renders. `AirDateTest` and `RecordingLabelTest` fail on an ISO shape or an identifier-shaped label.

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
- **§11.5 Search is the fourth tab**, before Library, as the web's order;
  Apple's `role: .search` lets the system place it.
- **§11.6 Listen live on a TV starts in place**, as Play does (§11.1);
  tvOS opens Now Playing full screen (tvOS-DESIGN §4.8). Android TV's
  player is still the phone's sheet (§12).

## §12 Open (what the code does not yet meet)

- **Stations has not run on a device.** Listening live, a slot starting at
  its own time, and each event that stops it are proven in
  `RadioTests` on the JVM, not yet heard on the Pixel or a TV.

- **Plays has not run on a device.** The microphone, the route check,
  echo cancellation, the engine voices (and API 29's zero-volume
  collection), the AAC mix, and the share sheet are built from the
  documentation and wait on the Pixel 8a and one Samsung (PLAYS-DESIGN
  §4.4). The bleed threshold is Apple's unmeasured 0.5.

- **Shared ear dramas (§4.16) have not run on a device or against a
  deployed Worker.** `PlaysShare` is proven on the JVM against a fake
  transport (`PlaysShareTest`); `PlaysApi` and the Compose screens are
  built from the Worker's documentation. The app's one OkHttp client keeps
  its 10 second read timeout, which a 45 MB take upload may outlast on a
  slow link; nothing measured it yet. The manifest's `eardrama://` and
  https filters stay off (§3.4), so an invite link opens the app only once
  they are on.
- **The sponsor reaches Detail from the next published catalog**: the
  projection now computes `sponsor` per episode (§3.1,
  `catalog/tools/sponsors.py`); §4.4 still probes for the column, so an
  older catalog shows none (Apple likewise).
- **On a TV the pushed screens and the player sheet are the phone's
  layouts**, with focus claimed and the ring (§9.2), not a ten-foot
  design; none has run on a TV. The player is still the sheet (§11.6).
- **A TV cannot share**: DEEP_LINKS.md's QR code of the https twin is
  not built.
- **The `eardrama://` and App Link filters are off** in the manifest
  (§3.4); `DeepLink.parse` routes both once they are on.
- **The queue verbs are the web's** (`WEB-DESIGN` §4.5, §4.7): add to the
  end (an episode already queued moves to the end), remove, move up or
  down (`QueueEdit`, written through `UserStore.enqueue` and the like).
  Detail carries an "Add to queue" / "In queue" button under Play; a
  long-press on any episode row opens a menu with "Add to queue" or
  "Remove from queue"; Library's Up next swipes a queued row away to
  remove and its long-press menu adds Move up and Move down.
  `PlaybackEngine.queueChanged()` rebuilds what follows the playing
  episode by the same `PlaybackQueue.after`, so "Up next" matches. The
  verbs only order what the person chose; what plays next is Decision
  067's, untouched. No Android verb removes an episode from history.
- **Sign-in has not run.** The Worker is deployed (`/v1/health`, 2026-10-30)
  but the ids are placeholders (docs/WORKER.md, Needs Ben). Apple on Android also needs
  the return page at `https://eardrama.org/auth/apple/`, which forwards
  its fragment to `eardrama://oauth/apple`; it is not built. Google needs
  an Android OAuth client for `app.eardrama` with the Play signing SHA-1
  (and `app.eardrama.debug` with the debug key) in the project that owns
  the Web client id.
- **Listen together has not run** (§4.13). Sign-in is not set up,
  so every build says it is not available; the room, drift correction,
  and handoff are proven in `ListenTogetherTest` and `RoomProtocolTest`
  on the JVM against a Worker built from `room-protocol.js`, not yet
  heard across the Pixel, an iPhone, and the web (LOOP-PLAN M6's play
  gate). A guest's notification and headset buttons still pause; the
  next read puts the guest back with the host.
- **Tab icons differ from Apple's** (Headphones and Radio against
  `play.circle` and `square.stack`).

**E1 rules (2026-10-30, D4 review).** The player sheet carries one nowrap row of Add to queue and Share under the controls (the Detail page's `QueueToggle` and `ShareButton`; Share is not offered on a TV). Stations after the evening ends: Tonight's button reads Replay. Library carries an "Export my data" row (absent on a TV) that opens a sheet of Save everything (JSON) and Save history (CSV), written through the system save sheet (docs/EXPORT.md). The rights fallback computes its year from the calendar.

Bring the next change back to a rule here, or bring a new rule first.

- **§4.22 Student privacy** (Decision 084, PLAYS-DESIGN §12.12; `ui/screens/PrivacyUi.kt`, `plays/AgeGate.kt`). The teacher's class page ends with **Class** (Ends {date}, **Change date** in the Material date picker bounded today to 400 days ahead, **Export class** through `CreateDocument("application/json")` as "{class name} export.json", **Delete class** in an `AlertDialog` whose confirm is in the error role) and an under-13 class without approval is headed by **School approval**. The class list shows "Deleted {date} unless opened". A class publish adds the two confirmations. The age question ("What year were you born?", a year list with no default) comes before Share, Invite, Take part and Publish / I agree, outside a class; only the Boolean is kept in preferences `ed.over13`. A director's **Delete for everyone** is offered only while the production has no archive job. Roborazzi `android-*` frames in `docs/research/design/img/privacy/` (`PrivacyRenderTest`).
