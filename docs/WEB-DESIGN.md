# Ear Drama web design (binding)

**Binding.** Quote the rule number before proposing any new view, dialog,
route, or data path. If no rule fits, propose a new rule first, then the
feature (`binding-design-doc-discipline`). Companion to `PARITY.md`,
`docs/CATALOG-CONTRACT.md`, and the sibling design docs as they are
written. The platforms share verbs, never idioms; where a rule here
inverts a sibling's, the inversion is deliberate and says so.

Seeded 2026-10-22 from `docs/templates/WEB-DESIGN-template.md` when the
web app passed five views (Listen, Series, a series page, Episode, Search,
Library). The R-numbers are the proposed binding rules of
`docs/research/05-design-research.md` §9; this doc quotes the ones the
web app follows today.

## §1 Principles

- **§1.1 The web feels like the web.** URL-driven state, shareable
  everything, zero install, phone first. Never port iOS or tvOS chrome.
- **§1.2 No framework, no build step.** Vanilla HTML, CSS, and JS served
  raw by GitHub Pages at eardrama.org.
- **§1.3 No backend for listening.** Static hosting and the catalog's
  published projection. A person's own listening stays in this browser
  unless they sign in (Decision 057: signing in is optional, never at
  first launch, and the first launch plays with zero taps); signed in, it
  also syncs through the Worker (§4.11).
- **§1.4 Mobile-first.** Every media query is `min-width`. Look at 375 px
  before 1440 px.
- **§1.5 Only essential words on screen** (AGENTS.md). A caption is a
  refusal, a warning, or a fact a person cannot discover by looking. No
  list or blurb is written by the app: shelves, genres, and names come
  from the catalog (R13).

## §2 Data plane

- **§2.1 One data client.** Every read goes through `js/api.js`; views
  never call `fetch`. The data base is `<meta name="ed-data">` in
  `index.html`, resolved against the page.
- **§2.1a The Worker is reached through the same client.** Sign-in,
  refresh, sync, and deletion are `API.account` in `js/api.js` (§4.11);
  `js/sync.js` and `js/account.js` never call `fetch` for the Worker.
- **§2.2 The projection decides; the client draws.** Rights, copy
  ranking, identity, and the public-web gate are settled by
  `catalog/tools/build_web_projection.py` (contract §4). The client adds
  no filter of its own (contract's one rule).
- **§2.3 Data files are versioned by the build, not the client.** A
  missing field is null; a removed episode is a 404, which the client
  shows as "Not in the catalog."

## §3 Routing and URL state

- **§3.1 Query routes, not hash routes.** `?view=home|browse|stations|surprise|search|library`
  (Decision 068), `?view=browse&kind=&script=1&genre=&decade=&network=&sort=`,
  `?series={key}&season=`, `?item={episode id}`, `?person={person id}&order=newest`
  (§4.14), `?view=search&q=`,
  `?view=library&tab=`, and for an ear drama (§4.10) `?play={script id}`,
  `?production={id}`, `?production={id}&part={part id}`, and `?room={CODE}`
  (§4.12), which opens the Listen Together sheet over the Home view. The
  names before Decision 068 still open: `?view=listen` is Home,
  `?view=series` Browse, `?view=radio` Stations, and `?view=plays` Browse
  narrowed to plays (`kind=plays`), each rewritten in place
  (`history.replaceState`) so the address shows the new name. This inverts the
  template's hash routes on purpose: query routes are what the path twins
  forward into. A production lives only in the browser that made it
  (PLAYS-DESIGN §6), so its routes have no path twin and no app link; a
  shared one is reached by its invite, `/invite#{token}` (§4.10a).
- **§3.2 Every `eardrama://` link has an `https://eardrama.org` path
  twin** (`/series/{key}`, `/episode/{id}`, `/person/{id}`, `/search?q=`, `/library`),
  forwarded by `404.html`. Never change these shapes; shipped apps share
  them (DEEP_LINKS.md).
- **§3.3 One router.** `route()` reads the location and shows one
  `<section hidden>`; focus moves to the view's `<h1>` on every
  navigation after the first.
- **§3.4 Site pages are real paths**: `/credits/`, `/privacy/`,
  `/takedown/`, `/delete-account/`, each its own static page sharing
  `css/styles.css`.

## §4 Surfaces

- **§4.1 Navigation: sections are actions** (Decision 068, owner
  2026-10-24: *"we should focus on actions and not content type ... we
  should mimic the items from Archive Watch"*). Six destinations, **Home,
  Browse, Stations, Surprise, Search, Library**, Archive Watch's web nav
  (its WEB-DESIGN §3.0) with Ear Drama's Stations in Channels' place: a
  bottom tab bar on a phone, six columns at 375 px, and a sidebar from
  768 px. Each owns one verb (the verb test, Archive Watch iOS-DESIGN
  §12.2): Home is chosen for you, Browse is everything by facet, Stations
  is lean back on one clock, Surprise is a random pick, Search finds,
  Library is yours. There is no section for a content type: a stage play
  sits in Browse and Search beside the radio series, and recording is an
  action on its page (§4.10). The phone's six reduce to the car's four
  (Continue, Stations, Browse, Downloads) without a new one (R17). Depth
  is at most two from a section: section, series, episode; Browse, play,
  cast sheet; a season or a Library section is a segmented scope, never a
  push.
  - *Replaced* (2026-10-23): "Six destinations, Listen, Series, Radio,
    Plays, Search, Library (05-design-research §8, plus Plays on
    2026-10-23, as the Apple apps carry a Plays tab, Decision 059)."
- **§4.2 Home** (was Listen, Decision 068) = Continue listening (this device), Following, then the
  manifest's `listenShelves` in its order (contract §5.1; the same list on
  every platform): `onThisDay` is "This day in radio", the contract's query
  on the person's own date; `mostDownloaded` is "Most downloaded", the
  published ids in order (archive.org's own download counts, Decision 067);
  each `genreFirsts` is an episode list headed by the published genre name,
  its ids drawn in order. Each section draws only when it has rows. A catalog
  without the key falls back to `index/listen.json`'s genre shelves of
  series. No "Most episodes" shelf (the owner, Decision 067).
- **§4.3 Browse** (was Series, Decision 068) lists radio series and
  stage plays together. Its filters are visible controls in one row, as
  Archive Watch's chips (its iOS-DESIGN §4.2a): Kind (Any kind, Series,
  Plays), Genre, Decade, Network, "Has a script", and Sort. Sort is Popular (the default), A to Z, Most episodes, and Oldest first. Popular is the published `downloads` (contract §3.3): counted series first, most downloaded first, then every row without a count by `sortName`. A play has no count, so under Popular it sorts after every counted series; a catalog published before the field has no counts, so Popular is A to Z.
  The URL carries `sort=` only when it is not Popular. Each facet's
  counts are computed against the other facets' selection, so no offered
  choice yields zero rows (§10.5). The real count is shown. A play carries
  no genre, decade, or network in its record, so setting one of those
  narrows to series; "Has a script" narrows to the rows whose record
  carries a usable script: the plays, and the series with an episode
  whose Detail row carries a `script` (contract §3.1). A play row reads its title,
  then its author and part count, and opens its page (§4.10).
- **§4.4 A series page** lists its episodes oldest first, every row
  leading with its air date in tabular figures (R1). Seasons are a
  segmented scope; undated episodes are their own scope.
- **§4.5 Episode detail** shows the series, the title, the date, one
  caption line of facts, Play, queue, Share, the cast and credits, the
  recordings, and the rights line. "Start an ear drama" joins the actions
  when the Detail row's `script` names a script in this browser's
  castable file (Decision 068), never on a TV. Every part draws only from
  data, and a part with no data is absent, never a placeholder:
  - No title: the episode's number names it ("No. 90"), else "Untitled";
    an id never reaches the screen.
  - No date: "Undated" opens the facts line, and no date line is drawn.
  - No network, no credits: the facts line and the credits section
    simply omit them.
  - A recording with no archive.org identifier shows its format and no
    Source link.
  - Copies of one broadcast are versions under Recording(s), the first
    being the default (R5).
  - **The transcript (R16, DECISIONS 058)** is a closed `<details>`,
    "Automatic transcript" (the label on every platform), under the
    actions, drawn only when the Detail row's `transcript` is set (the
    gate passed, contract §4). Opening it fetches the text from that
    archive.org URL through `API.transcript`, never a copy of ours; its
    states are `stateBox`'s (§7.1). The text is plain, selectable, one
    sentence a line, at the body size in a 68ch measure. `#transcript` in
    the URL opens it: the player's "Automatic transcript" link, shown
    only for an episode whose Detail carries one, lands there (§3.1's
    route, plus a fragment, never a new route shape). Measured
    2026-10-22 in headless Chrome from `http://127.0.0.1`: the fetch
    followed archive.org's 302 to the storage node, which answered 200,
    `access-control-allow-origin: *`, `text/plain; charset=utf-8`.
- **§4.6 Search** is word-prefix over the projection's term files,
  debounced 180 ms, series first, then people (§4.14, from
  `search/people/`, most episodes first, eight shown with the total), then
  plays (word-prefix on the title and author of `castable-scripts.json`),
  then "Aired {date}" when the query names an air date (contract §3.4,
  `search/dates/`, oldest first, narrowed by the other words), then
  episodes paged 30 at a time, then **Automatic transcript** (`search/said/`,
  every word of three letters or more said in a shown transcript, less the
  episodes above), paged 10 at a time; each of its rows is the episode row
  plus the line where the words are said, italic, verbatim from the text at
  the Detail row's `transcript`, and the row stands alone when that text
  does not load. The query is mirrored to the URL. The client never builds
  an index of its own from fetched transcripts: it would search only what
  this browser happened to open.
- **§4.7 Library** = the account row (§4.11), then one segmented scope, in the order the person
  returns to things: **Continue** (episodes started and not finished), **Queue**, **Following**,
  **History**, and **Ear dramas** (the productions this browser recorded in or joined, newest
  first, each with "N of M lines recorded" or "Finished", "Shared" for a shared one, then the
  shared ones this browser has not opened, and Classes, §4.10a; Decision 068), on this device.
  Every section draws the one grammar (§6.4b): Continue, Queue and History are rows (the series'
  window leads where series mix); **Following is show tiles** in a grid (`.g-grid`, subgrid slots so
  names, strips and facts line up across a row). Queue keeps move up, move down and remove on its
  rows; Clear history asks first. The four states: every section reads this browser's storage, so
  there is no loading or offline state of its own (a tile or window whose picture does not load
  draws its title block); an empty section is one caption that says what it would hold, and the
  Browse button: "Episodes you stop partway through wait here.", "Episodes you add play in this
  order, after the one that is playing.", "Series you follow appear here.", "Episodes you play
  appear here, newest first." An empty Ear dramas says "No ear dramas yet." and nothing more.
  `tools/web_fit_library.py` shoots every section, empty and full, light and dark, at 320, 375,
  390 and 430 px and fails on a wrapped button, a sideways scroll, an overflowing tile name, a full
  section that drew nothing or an empty one with no caption. The tab strip scrolls inside itself
  (`.segmented-scroll`) when five labels do not fit.
- **§4.9 Stations** (was Radio, Decision 068: *"collections of ear dramas
  should be stations"*) = the stations row, then Tonight's schedule.
  **The stations row** (R10, contract §8) lists Tonight in 19xx first, then
  each genre station `stations.json` publishes, one row each: the station's
  name (the genre's name from data), what is on now (series, then title), and
  "Listen live" ("Listening live" while on; pressing it pauses). Outside the
  evening Tonight's row says "Starts at" or "Ended at"; a withheld slot says
  "Not in the catalog" and offers no Listen live. A genre station joins its
  slot on now where the clock stands and plays each later slot at its own
  time, under the evening's live rules (R14), for at most twelve hours from
  tuning in; its episodes are fetched only on tune-in. With no stations file,
  Tonight stands alone. **Tonight's schedule** is the evening `tonight.json` publishes
  for the listener's own calendar date (contract §8), as the night's
  schedule; an evening shows whenever any of its programs survives
  (Decision 067). When the day offers other published years (`years`), a
  native "Year" select beside the heading picks one: that year's whole
  evening on tonight's clock, and picking ends listening live. Each slot shows its local time with the original Eastern time
  beside it as a fact ("7:00 PM ET" alone where the two agree), and the
  slot on the air is marked on the one clock, read from the file's UTC
  instants (R10). A surviving slot links to its episode and plays from
  its start; "Listen live" joins the slot on the air where the clock
  stands, and each later surviving slot starts at its own time. A pause,
  another episode, or the sleep timer ends listening live, and so does
  the last slot: nothing plays after the evening (R14). A gap is drawn as
  a gap (R9): its time, its length, the catalog series name only where the
  file sets `known_series` (the listing matched a series), and "Not
  surviving" (or "Not in the catalog" for a recording this projection does
  not serve). The newspaper's printed text is never drawn (Decision 067); the
  file no longer carries it. The listing is credited in one caption line linking
  the page it was read from. No evening for today is the empty state.
- **§4.10 Ear dramas: pass the phone** (`docs/PLAYS-DESIGN.md` is binding on
  what the feature does; this rule is how it looks on the web). Code:
  `js/plays-core.js` (the script, production, relay, timeline, and audio
  math, mirroring `apple/Core/Plays`), `js/plays-store.js`,
  `js/plays-voice.js`, `js/plays-audio.js`, `js/plays-worklet.js`,
  `js/plays-session.js`, `js/plays-ui.js`; tests `js/plays.test.js`.
  - **Not on a TV**: the smart-TV layer (`html.tv`) hides every way to
    start an ear drama (the plays in Browse, Search, and Surprise, and
    Library's Ear dramas), as Android TV does; TVs play back only
    (research 08 §5).
  - **No list of its own** (Decision 068). The plays are rows in Browse
    and Search (§4.3, §4.6) and a pick on Surprise (§4.13); a person's
    productions are Library's Ear dramas (§4.7). Each play shows its
    title, author, part count, and its rights evidence claims verbatim,
    each linked to its source, and the source's name linked, read
    generically from `data/plays/castable-scripts.json` through
    `API.castableScripts`. Nothing on it is written by the app. The Pages
    deploy copies the file into `data/plays/` (`catalog-publish.yml`);
    locally, copy it into the `data` link's `plays/` folder.
    - *Replaced*: "**The list** (`?view=plays`): "Your plays" ... then
      "Plays you can cast"."
  - **A play** (`?play=`): the author with the years the record carries,
    a facts line (the record's year when it has one, then "N parts · N
    lines"; never an age rating, Decision 067), the rights line, "Start an
    ear drama" (was "Cast this play"), and its parts
    largest first with line counts (directions and sound are parts too).
    Casting replaces this page in the history with the cast sheet, so the
    depth stays two.
  - **The cast sheet** (`?production=`): every part with its state. Every
    open part offers "Take part" while no part records, with an optional
    name field; the largest open part's button is the accent one, the
    others plain (C7, owner 2026-10-23: any order, largest suggested);
    sound and directions may "Leave silent"; a finished part offers "Open
    part" only while no part records. A refusal is one line in the error
    color. Below: Listen through, any time (§2.6, C5): until every
    speaking line is human, one Listen through / Stop button runs
    `ListenThrough` (`js/plays-session.js`), the current line shown as the
    teleprompter draws it, labeled "Device voice" when `speechSynthesis`
    reads it; once complete, the rendered mix in its own `<audio>`, and
    Export beside it at any time (it renders the mix if needed). Then
    Discard unused takes, Delete production (asks first).
    - *Replaced*: "Only the relay's next part offers "Take part" ..." and
      "Listen through (§2.6, C5: offered only when every speaking line has
      a human take), Export once finished".
  - **Recording** (`?production=&part=`): signed out, the page says
    "Recording needs an account." with a Sign in button that opens the
    account sheet (§4.11), and nothing else (owner 2026-10-23: always, even
    a play never shared). Signed in, before anything, the
    headphones refusal. The web cannot see the audio route (Safari lists no
    outputs, and Chrome's labels name devices, not the route in use), so
    the page says "Headphones only. This browser cannot tell whether they
    are on." and Start recording stays disabled until the person checks
    "My headphones are on", every session (PLAYS-DESIGN §4.3). Start
    recording asks for the microphone then, never earlier
    (`getUserMedia`, `echoCancellation: true`, `autoGainControl` and
    `noiseSuppression` off). Then five seconds of room tone with a
    countdown, then the teleprompter: the cue line (labeled "Device voice"
    when the device voice reads it), "Your line" while listening, the line
    large, the next line dim, the line's takes, one record control,
    previous and next, Run-up, Hear it read, the device voice's speed,
    Keep, and Done with this part (enabled when every line of a speaking
    part has a take). Keys: Space records or stops, Return keeps, the
    arrow keys move by line. Leaving the page ends the session and stops
    the microphone.
  - **Capture is an AudioWorklet writing PCM**, not MediaRecorder: the
    line-end detector reads 20 ms frames as they arrive, the kept window
    (onset less 250 ms to end plus 250 ms) is cut from samples, and every
    browser yields the same PCM, where MediaRecorder gives Opus in WebM
    or AAC in MP4 by browser, lossy and needing a decode to trim. Takes
    are resampled to 48 kHz with an `OfflineAudioContext` and kept as
    24-bit mono WAV.
  - **The device voice is `speechSynthesis`, local voices only**
    (`localService`, English), and is never captured: its sound goes to the
    system output, which a page cannot read. With no local voice the cue is
    shown, not spoken. The bleed check is the microphone's level while
    the device voice speaks (PLAYS-DESIGN §4.1), held only as a number.
  - **Storage is IndexedDB** (`ed-plays`, one `files` store keyed by
    path), laid out like Apple's folder: `{id}/script.json`,
    `{id}/production.json` (the same record and field names),
    `{id}/takes/{line}-{8 hex}.wav`, `{id}/roomtone/`, `{id}/mix.wav`. A
    take is written with `add`, which refuses an existing key, so a take is
    never overwritten. Not OPFS: writing a file from the page needs
    `createWritable`, which older Safari lacks.
  - **The mix** is rendered in 30 s `OfflineAudioContext` chunks from the
    timeline and written as 16-bit mono WAV at 48 kHz: the browser has no
    AAC or Opus file encoder short of real-time MediaRecorder, and WAV
    plays everywhere. The listen-through plays it in its own
    `<audio controls>` in the cast sheet, deliberately not the one player
    of §5.1: a mix has no history, queue, resume, or Media Session, and
    the episode player pauses when it starts. Reaching its end without
    seeking forward finishes the play; Export downloads the WAV.
  - `?mute=1` silences the device voice, the cues, and the mix.
- **§4.10a Shared ear dramas** (PLAYS-DESIGN §11.7 is binding on the verbs
  and words; this is the web's idiom). Code: `js/plays-share.js` (no DOM,
  the Worker's record mirrored into this browser's production) and the shared
  views in `js/plays-ui.js`; tests `js/plays-share.test.js` against a stubbed
  Worker. Nothing of it is offered while the Worker's URL is a placeholder
  (`API.plays.available()`), and none of it on a TV.
  - **The cast sheet of an unshared production** ends with **Share** (an
    optional name field); signed out, Share opens the account sheet beside
    "Sharing needs an account."
  - **A shared cast sheet** (`?production=` with a `share.json`): the
    Worker's parts and names; Record and Release on my claim; Take part on
    every open part while none records (the suggested one the accent);
    Leave silent on open sound and directions; Open part on a finished one
    of mine or as director. Below, on my claim, **Upload N takes** (while a take waits) and
    **Done with this part**, with one line under them: "Uploads are off."
    while the record's `uploads` is false (the button disabled), or the
    bleed warning when a chosen take is flagged. Uploading asks no consent
    (Decision 072). Then Listen through (it first fetches the other
    members' chosen takes, then is §4.10's), "N takes are hidden from you."
    when the Worker hides any; Publish (director, complete play) opens a modal
    `<dialog>` with the Worker's consent words and "I agree to publish my
    recording under CC0." / "Not now", and is offered only while `GET
    /consent` says `publishes`, else "Publishing opens when the Ear Drama
    archive account is connected." A performer who is not the director sees the same words and button inline once the play is complete, with "Not now" (back next open); the director sees each performer's name with a mark, and Publish stays disabled until all have agreed (PLAYS-DESIGN §11.7 rule 6). (The archive.org job reads as PLAYS-DESIGN §11.7 rule 9: a quiet line, **On archive.org** as a link, or the Worker's reason with **Publish again**; once published, a details disclosure "Your lines" (the director's "Lines") offers **Replace** (a link to `?production=&part=&line=`, the recorder on that one line) and **Remove** (`confirm()`, the error color) per rule 13.); then
    **People** (Report opens an inline
    form with a reason select and a note; Block asks with `confirm`), Invite
    for the director (the link in a read-only field, Share link through
    `shareTarget`, "Works for N days."), and Delete production (this
    browser's copy only). Showing the tab again (`visibilitychange`)
    redraws a shared production unless a take records or something plays,
    so parts recorded elsewhere arrive (PLAYS-DESIGN §11.7 rule 7).
  - **Another member's part** (`?production=&part=`) is read-along with a
    Take button (plays that take in its own `<audio>`) and Report per line.
  - **An invite** arrives as `/invite#{token}` (forwarded by `404.html` as
    `#invite={token}`); `app.js` holds it in `sessionStorage` for the tab,
    clears it from the address, and opens `?view=library&tab=dramas`, where
    **Invitation** leads the list (§11.7 rule 3).
  - **Library's Ear dramas** (§4.7) lists this browser's productions, then
    the shared ones not yet opened here (a button that makes the production
    here, then opens it); shared rows say "Shared". Signed in, **Classes**
    follows the list: each class with its code (two groups of four, tabular),
    Make a class (name, "Under 13"), Join a class (code, optional name).
- **§4.13 Surprise** (`?view=surprise`, Decision 068; Archive Watch
  WEB-DESIGN §4.9): three random picks drawn from the data on each visit,
  each playable or startable in one tap, and Shuffle to draw again. **An
  episode**: a served, recommendable episode with a recording (a series
  drawn in proportion to its episodes, then one of its episodes), its
  series, title, and date, and Play. **An evening**: one evening from
  `tonight.json` (contract §8), its date, network, and station, and Play,
  which plays its first surviving slot from the start (never live, never
  a queue: what plays next is the owner's call). **A play**: one castable
  script, its title and author, and "Start an ear drama", which makes the
  production and opens its cast sheet (§4.10); not on a TV. The draw is
  `Math.random()`: nothing needs to match another device. No copy is
  written for a pick; a pick with no data is absent.
- **§4.14 A person** (`?person={id}`, `withPerson`, contract §4 and §5):
  every served episode crediting them, grouped by series, each row its date,
  title, and the roles it credits them in ("Cast as Mrs. Stevenson,
  Writer"). Reached from a credited name on Detail (§4.5, each name a link)
  and from Search's People. The head is the portrait when one is served
  (Decision 069, with its credit), the name, and one facts line: the years
  from the people row ("1900–1974", "Born 1915", "Died 1985") and the episode
  count. Facts only from data: no bio, no blurb, no "known for" (R13).
  Order is a segmented Oldest first / Newest first (`&order=newest`), drawn
  only when there is more than one episode; undated episodes are last
  either way, and a series sits where its first episode in that order does.
  A series heading links to the series. The page belongs to Browse's
  section in the nav, as Detail does.
- **§4.8 Site pages live in a quiet footer**, at the end of every view's
  scroll and on each site page: Credits, Privacy, Take-down requests,
  Delete an account (§4.11).
  They are never featured in the main UI (AGENTS.md "side doors").

- **§4.11 The account lives in one row of Library** (Decision 057, 063;
  LOOP-PLAN M5). The web has no Settings page, and an account is a rare
  job, so it gets no tab, no route, and no header chrome: one row under
  Library's heading, above the Queue, History, Following scope, and a
  `<dialog showModal>` it opens (full screen on a phone, a 440 px sheet
  from 768 px, like Now Playing, §5.1). Nothing about it appears at first
  launch or anywhere else in the app.
  - **The row, signed out**: "Sign in". While `js/config.js` holds
    `REPLACE_WITH` placeholders the button is disabled and the caption
    reads "Not available yet" (a refusal, §1.5); no error is drawn. After
    the Worker ended the session: "Your sign-in ended." in the error color.
  - **The row, signed in**: "{Apple|Google} account" (opens the sheet),
    the status caption ("Synced 3:42 PM", "Syncing", "Offline", or "Sync
    failed 3:42 PM" in the error color), and a Sync now icon button.
  - **The sheet, signed out**: Sign in with Apple, then Google's own
    button, and one caption: what this device has played is kept and
    added to the account (the merge, below). **The sheet, signed in**:
    Signed in with, Last sync, Last error (only when there is one), Sync
    now, Sign out, and Delete account, which asks first with `confirm()`.
  - **Sign-in**: Sign in with Apple JS (popup) and Google Identity
    Services (its rendered button), each the provider's own first-party
    script, loaded only when the sheet opens (§8.3). Each attempt sends a
    fresh raw nonce; Apple's `state` is checked. No PKCE redirect: Google
    requires a client secret to redeem a web client's code, and both
    providers' scripts return the identity token the Worker verifies.
  - **Tokens** (`API.account`): the access token is held in memory only;
    the refresh token is kept in IndexedDB (`ed-auth`) encrypted with a
    non-extractable AES-GCM key, so a copy of the browser profile taken
    off the machine cannot be read. That is the most the web allows
    without an HttpOnly cookie, which the Worker does not issue; it does
    not protect against script on the page. Never in localStorage or a
    URL. A refresh happens before any call with under 5 minutes left, one
    at a time per tab and across tabs (Web Locks), because a refresh token
    sent twice ends the sign-in. A 401 refreshes once and retries; a
    second is surfaced. A refused refresh signs out here.
  - **Sync** (`js/sync.js`): history (positions, finished, removal
    markers), the queue (whole), and follows (`following: false` as the
    marker), last write wins per row by `updated_at` (`Store.applyRemote`;
    a tie keeps this device's), read with `?since=` the last
    `server_time`. The first run after sign-in sends everything this
    browser kept signed out to `/v1/sync/merge`, once. It runs on load,
    on visibility change, back online, Sync now, and 10 s after the
    listening changes (at most 2 min while playback keeps changing it).
    Rows from the Worker carry no card, so the client fills them from the
    catalog. Clearing history sends a marker for every row.
  - **Sign out and deletion** leave this browser's listening in place.
    Deletion forgets the tokens and the account state only after the
    Worker answers; for an Apple account it first asks Apple for a fresh
    authorization code so the Worker can revoke Apple's token.
  - **`/delete-account/`** is the public path Google Play requires for
    someone without the app: what is deleted, then sign in and Delete. It
    is linked from the site footer only. Ear Drama keeps no email, so the
    account is found by signing in with it.
  - **Not on a TV** (`html.tv`): a packaged TV app runs from `file://`,
    which the Worker refuses (docs/WORKER.md).
  - Tests: `js/account.test.js` against a stubbed Worker.

- **§4.12 Listen Together lives on the player** (LOOP-PLAN M6, Decisions
  058, 065; docs/WORKER.md "Listen Together rooms"). No tab, no view, no
  header chrome: a room is something the person does with what is playing.
  - **Where**: a "Listen together" button in Now Playing's options row
    (beside Speed and the sleep timer), and a "Join a room" row in Library
    under the account row (§4.11) for someone with nothing playing. Both
    open one `<dialog showModal>` sheet (full screen on a phone, 440 px
    from 768 px, like the account sheet). While `js/config.js` holds the
    Worker placeholder, both buttons are disabled with the caption "Not
    available yet" (a refusal, §1.5); nothing is an error.
  - **The link**: `?room={CODE}` (DEEP_LINKS.md) opens the sheet with the
    code filled in, then drops the parameter from the address. Joining
    takes the person's tap on Join, never the link alone: a room plays
    sound, and the tap is what lets the browser start it.
  - **Out of a room**: "Start a room" (only while an episode from
    archive.org is loaded; the room carries that exact copy), then the
    code field and Join. Codes are normalized as the protocol says (spaces,
    `-` and `_` dropped, I and L read as 1, O as 0). The one line under
    it is a refusal: "That is not a room code.", "No room has that code.",
    "This room has ended.", "This room is full.", "You are no longer in
    this room.", "Too many tries. Try again in a minute.", "You are
    offline.", "Ear Drama could not be reached."
  - **In a room**: the code, large, in tabular figures, split 3 + 3 for
    reading aloud; "{n} listening"; for a guest, "Following the host";
    Share link (the `?room=` link through `shareTarget`), Leave, and for the
    host End room. Everyone, the host included, is one of the n.
  - **The guest's player**: the transport is the host's. Skip, seek, and
    speed are disabled, and the person's own verbs (keys, Media Session,
    `Player.toggle`) do nothing (`Player.setFollowing`); the room's
    corrections go through `Player.follow`. A drift nudge sets the
    element's rate only and is never kept as the person's speed (§5.2).
    Play and pause are the guest's own (Decision 067): pause holds their
    sound while the room plays on, and play catches them up to where the
    host is now (`Together.hold`, through `Player.setGuestHold`); the same
    tap starts the sound when the browser refused to. The mini player's caption reads
    "Listening together · {n}". Picking another episode, or the sleep
    timer ending, leaves the room, as it ends listening live (§4.9).
  - **The rules are the protocol's**, ported in `js/together-core.js` and
    golden-checked against `worker/src/room-protocol.js`
    (`js/together.test.js`): the host writes state when it changes; every
    member reads every 2 s, every 10 s after a still minute; the clock is
    the smallest-round-trip sample; drift under 150 ms is left, 150 ms to
    2 s is closed by 3% of speed, over 2 s is a seek, and a guest that is
    seeking or buffering is left to catch up. A guest plays
    `https://archive.org/download/{archive_id}/{file}` built here,
    percent-encoded as the pipeline does, never a URL from the room.
    When the host leaves or goes quiet, the next read's `role: "host"`
    hands that member the controls.
  - **A reload keeps the room**: the code and member key are in this tab's
    `sessionStorage` (`ed.room`), never localStorage or a URL. Closing the
    tab sends nothing; the Worker drops a quiet member after 2 minutes.
  - **Not on a TV** (`html.tv`): a packaged TV app's `file://` origin is
    refused by the Worker, as for the account (§4.11).
  - Code: `js/together-core.js`, `js/together.js` (the session, no DOM),
    `js/together-ui.js`; every call is `API.rooms` (§2.1a).

## §5 The player

- **§5.1 One `<audio>` element** owned by `js/player.js`; the views draw
  it. The one exception is a play's listen-through (§4.10), which is not an
  episode. The bar is a flex child above the tab bar, never `position: fixed`
  (§6.3). Now Playing is a `<dialog showModal>`, full screen on a phone.
- **§5.2 Speed, the sleep timer, and skip live on the player** (R18):
  back 15 s, forward 30 s, speeds 0.75, 1, 1.25, 1.5, and 2 (`SPEEDS`,
  DECISIONS 062), kept on the device; a rate kept from an older build
  lands on the nearest choice.
- **§5.3 Bedtime is a mode** (R20). The sleep timer offers "End of this
  episode" first, fades the volume over its last 10 s (`FADE_S`), and
  nothing starts again until the person presses play.
- **§5.4 Lean-back is bounded** (R3, R14, Decision 067): a part of a story arc (contract §3.3) is followed by the arc's next part, automatically; at the arc's last part playback stops and the series' next story is offered as a "Next story" action, never started. Anything the person queued plays after an arc's last part, as after any episode. Outside an arc: one episode, then the queue, then stop. A live slot follows its clock, never an arc
  (`Player.load(…, { arc: false })`). Now Playing's caption names what is
  up next ("Next part:" or "Next in queue:"); the last part shows a "Next
  story" button (`#np-story`), hidden for a Listen Together guest.
  `Player.upNext` and `Player.nextStory` are the rule; `API.arcOf` reads it.
- **§5.5 Never skip the commercials** (R8). Skip is a fixed interval,
  never a jump past a segment. No data marks a commercial's start and end
  yet, and the web has no chapter surface (contract §3.2a).
- **§5.6 Media Session** carries the title, series, and date, with play,
  pause, and seek handlers, and the artwork Now Playing draws (§6.4): the
  portrait at 500 px, or the typographic card painted to a 512 px PNG. Keyboard: k or space toggles, j and l skip.
- **§5.7 Progress persists** every 5 s (`SAVE_EVERY_MS`) and on pause;
  resume only inside the 10 s to 95% window. A pause the browser made (a
  call, another tab's sound), not the person, is an interruption: the
  next play starts 3 s back (`REWIND_S`). DECISIONS 062 holds all four
  numbers; `js/player.test.js` checks them.
- **§5.8 Audio is never cached** by the service worker (§7.2).
- **§5.9 Volume is leveled on the device** (Decision 067; DECISIONS 070).
  The element plays through a `DynamicsCompressorNode` (`Player.LEVEL`:
  threshold -24 dB, ratio 4, knee 12 dB, attack 3 ms, release 250 ms; the
  browser's own makeup gain, 10.8 dB), on by default, and "Level volume" in
  Now Playing's options turns it off (kept on the device). The copy is
  fetched with `crossorigin` so Web Audio can hear it; a copy refused that
  way plays again without it, unleveled. The graph is built only once a
  tap or key has started the AudioContext. Not on iPhone or iPad (a page's
  AudioContext stops at the lock screen) or a TV engine: the button is
  disabled with "Not in this browser" (a refusal, §1.5). The sleep fade and
  the mute door ride the graph's output gain. No per-file measurement is
  read.
- **§5.10 Another speaker is the browser's own picker** (the owner,
  2026-10-28: "All apps should be able to make use of native sharing like
  airplay or casting on their platforms."). One button in Now Playing's
  options (`#np-remote`, `js/remote-playback.js`) opens Safari's AirPlay
  picker (`webkitShowPlaybackTargetPicker`) or, in Chrome and Edge, the
  Remote Playback API's Cast picker (`audio.remote.prompt()`). Its label
  is the platform's word, "AirPlay" or "Cast"; it shows only while the
  browser reports a target (`webkitplaybacktargetavailabilitychanged`,
  `remote.watchAvailability`; a browser that cannot watch shows it and lets
  the picker say what it finds), and never on a TV, which is the speaker.
  The receiver fetches the element's own src, the archive.org copy. No
  Cast SDK and no receiver of our own. Listen Together is a separate verb.

## §6 Look

- **§6.1 Every value is a token** from `design-tokens.json`; nothing in
  `styles.css` names a color. Brand chrome and genre accents never mix
  (R12): genres reach the page only through `data-genre` and
  `--genre-accent`, which the generator sets per catalog genre key.
- **§6.1a Color roles (Decision 064, On Air).** Ink (`--color-primary`,
  `.btn-primary`, `.icon-btn-primary`) is the primary action: Play and
  Pause, Listen through, Listen live, the progress line, and the slot on
  the air now. Red (`--color-record`, `.btn-record`) means recording and
  nothing else (owner, 2026-10-29: *"Red means recording."*): Start
  recording, the record button, and "Your line" while the microphone is
  open. Blue
  does the wayfinding: `--color-link` for links and the focus ring;
  `--color-secondary` for the selected tab and sidebar item, a pressed
  toggle, a checked control, the loading spinner, and every filled
  button that is not Play. Genre hues (`--color-genre-*`) are content:
  the series card's and row's genre edge and the series page head, never
  a button, a tab, or a link.
- **§6.2 Density from removing chrome.** Six type levels (page title,
  section header, body strong, body, caption, tabular). The page title
  and section header set Big Shoulders (the display face); every other
  level sets Public Sans (Decision 060). Both are self-hosted from
  `fonts/` (`font-display: swap`, the display face preloaded, both in the
  service worker's shell), built by `tools/build_fonts.py`.
- **§6.3 Safari layout.** `body { height: 100dvh; display: flex;
  flex-direction: column; overflow: hidden }`, `main` is the one scroll
  container. No `viewport-fit=cover`, no `position: fixed` overlays.
- **§6.4 Art is a served portrait, else the typographic card** (R11,
  Decision 069, contract §3.3a). A picture comes only from the catalog: a
  person's portrait the projection serves, or a card drawn from data (the
  name, one meta line, on the genre hue). No stock, placeholder, or
  uploader art. A stage play draws the same card from its own title, year,
  and genre. Where art appears, and only there:
  - **A row that mixes series** (Continue listening, This day, genre
    shelves, search results, the queue and history, series rows and
    cards, Stations' rows and an evening's aired slots) leads with a 56 px
    tile (§6.4a): the series' star, else the series'
    first letter in its genre hue on the surface. Rows on a series page
    carry none: one picture repeated down a list is chrome. On a phone the
    date stacks above the title (still first, R1) so the title keeps its
    width; from 768 px it takes its column.
  - **A series page, Detail, and a person's page** open with the face
    band (§6.4a), captioned with the person's name (who it is cannot be
    seen; a person's page leaves it to the heading) and the credit when
    the license asks for one. Detail uses the episode's star, a person
    credited in it; a series page its star. No face, no picture: the
    heading is the card.
  - **Cast lines** carry a 32 px round portrait where the person has one;
    a role group with any portrait keeps the slot on every line, so names
    align. Credits owed by those portraits follow the list, one caption,
    each linked to its Commons file page.
  - **Now Playing** (D3-4) leads with the grammar's window at its largest
    slot (360 px, no taller than 44 % of the screen): the show's picture,
    else its star's, else the title block, cropped on the face and held to
    the size floor (`API.windowFill`); a credit the picture owes is
    captioned under it. The episode title and the event line (show, date,
    network; the show name links to its page) come next. §5.6 sends the
    same picture to the lock screen. The mini player is the grammar's row
    in small: a 40 px window, the title, the event line (show, date).
    On a phone the options row is speed beside the sleep timer, every
    other verb on its own row, so no pair wraps apart (320 to 430 px).
  - **Small crops center on the published face** (amended 2026-10-28,
    V4; `artwork-presentation-design` rules 4 and 5: a crop only in small
    repeated slots, at a focal point computed once in the pipeline). Only
    the small repeated slots crop: the 56 px row tile, the 32 px cast
    face, and any square the system asks for (the lock screen). Each
    shows the square `API.cropRect` picks around the portrait's `art.face`
    box (contract §3.3a, the one formula): the face about half the
    square, at most 4x zoom, so a wide frame (J. Carrol Naish's trailer
    title card) shows his face, not the card's lettering. Without a face:
    an upright or square picture takes its largest square at 50% across
    and 20% down; a wide one is not cropped, so the tile keeps its letter
    and the cast line its empty slot (a blind center crop of a wide frame
    loses the face); an unknown size (an older catalog) keeps the plain
    fill crop at 50% 20%. No client
    detects faces. A page that is about the picture (§6.4a) never crops.
    A failed image leaves the tile's letter or nothing, never a broken
    image. `API.artURL` is the one helper:
    Commons' standard widths (120, 330, 500, 960), never a re-hosted copy.
- **§6.4a Faces lead** (owner, 2026-10-28: *"Portraits should show wherever they are useful or joyful (overall the visuals are not highlighted yet on the app)."* and *"The visual pass should be for all artwork. We want the app to be as visual as possible."*). The only art the
  projection serves with evidence is a person's portrait (§6.4); every
  other image class waits on the owner's V2 to V5. Where a face is served it is the first
  thing on its page and large enough to know. **The box takes the
  picture's shape, never the picture the box's** (owner, 2026-10-28:
  *"I think you can find better solutions for different aspect ratios of
  images, then just blurring and black bars."*; the method is
  `artwork-presentation-design`). Its aspect `a` is the projection's
  width over height (contract §3.3); `a > 1.15` is wide, anything else
  upright (a square included); an unknown size is drawn upright at 4:5
  until the image decodes (`aspect-ratio: auto 4 / 5`). On a series page,
  Detail, and a person's page an upright face is **the print**: beside
  the heading, 168 px tall on a phone and 240 px from 768 px, as wide as
  its aspect makes it (at most 40 % of the head), with a hairline border,
  the control radius, the genre's 3 px edge under it, and its caption
  (whose face, and the credit when owed) directly under it in its own
  column; the heading and facts sit beside it and the actions run under
  both. A wide face is **the plate**: above the heading at the column's
  full width and its own aspect, at most 320 px tall, set at the start
  (never centered in a filled band) when that cap binds, captioned under
  it. Now Playing's bound is a square, full width and no taller than
  44 % of the screen (`min(100%, 44dvh)`) so Play stays on a phone's
  first screen: a portrait is drawn whole at its own aspect inside it and
  its box shrinks to it, centered on the page; a card fills the square;
  a credit the portrait owes is captioned under it (the art is larger
  than a page's head there). Nothing is drawn behind a picture: no wash,
  no bars, no filter; while it loads the box is the surface color at
  exactly the picture's size, so nothing moves when it lands, and a
  failed image removes its box. A row's tile is 56 px. Sizes come from
  the one helper: the 120 step for tiles, the 330, 500 or 960 step for
  the print, the plate and Now Playing by drawn width at the screen's
  density.
  With no face, a series page's head is drawn as its typographic card
  (the name, the facts, Follow and Share on the surface with the genre's
  8 px edge, at least 200 px tall, 240 px from 768 px): the designed
  fallback, never a gray box. A play's row in Browse and Search leads
  with its tile (the title's letter; plays carry no genre).
- **§6.4b One grammar for every level of content** (owner, 2026-10-29:
  *"the design is still not uniform for all different levels of content
  (some with images, some without, some with more information, some with
  less). We need to a design approach that evens out all of the
  inconsistencies and make the app look like one complete thought."*;
  then *"Yes to both"*, build D everywhere; `catalog-experience-design`
  rule 11, `uniform-imagery-design` §2 to §7; D3-1). The shared text for
  every platform (iOS-, macOS-, tvOS- and ANDROID-DESIGN R11b). Each
  object has one skeleton of fixed slots; richer data fills more slots
  and never adds, moves or resizes one. Where it amends §6.4 and §6.4a,
  this rule wins.
  - **The window** is one square slot (a circle for a person), radius 4
    inside the card's 12, on the print ground (`color.print.ground`) with
    a 1 px hairline (`color.print.edge`). It holds the series' `picture`
    (contract §3.3a: the show's own image, then its star, then the person
    heard most; `pictureKind` is never said on a tile), cropped by
    `cropRect`, or, when the picture is wide with no face, drawn whole
    inside a 6 % inset on the ground. Below the size floor (the crop's
    pixel height under the slot's points; a whole picture whose short
    side is under half the slot) or with no picture, the window holds the
    **title block**: the monogram (the initials of the first two words
    that start with a letter, skipping the, a, an, of, and, in, on, to,
    for, el, la, le, de, der, die; else the first letter or digit) set in
    Big Shoulders as an outline (no fill, a 1.4 px stroke) in the board's
    onBoard color, on the board, its baseline at 93 % and its start at 9 %
    of the window, sized `min(104, floor(86 / sum(w)))` hundredths of
    the window where w is 0.76 for M, 0.78 for W, 0.45 for J, 0.27 for I or 1, else 0.50 (the advances of the bundled Big Shoulders Bold, the widest cut any platform ships, measured 2026-10-30),
    plus 0.02 per letter; the window's hairline is onBoard at 32 %. The
    name is never drawn twice.
  - **The grade** (`uniform-imagery-design` §2): every picture in a
    window is neutral monochrome (Rec. 709 luminance) then the linear
    levels `k * v + o` in sRGB. The projection does not yet publish
    `art.grade` (contract §3.3a follow-up), so every platform applies the
    documented default, the identity levels (`k` 1, `o` 0) after the
    monochrome; a published grade replaces it with no client change in
    shape. Web: one SVG filter (`feColorMatrix saturate 0`, then
    `feComponentTransfer` linear) with `color-interpolation-filters`
    sRGB.
  - **The show tile**: on the genre's board (`color.board`; the neutral
    `surfaceAlt` with the page text for a show with no genre), padding
    6 px (10 px at the foot), and in order: the window; the name (L2 in
    Big Shoulders, upper case, balanced; a name whose longest word passes
    10 letters steps down to L3's size, past 14 to L5's, never a broken
    word); the **run strip** (18 px, 1930 to 1962 on one fixed axis, in
    onBoard: the axis's baseline at 30 %, and the years from the first to
    the last broadcast as a solid bar; an undated show is the baseline
    alone); the facts (the years, else "Undated"; then the count of
    episodes), each on its own line. Tiles in one grid row share their
    slot tracks (CSS `subgrid`), so every mark in a row sits on one line.
    The strip shows the span, not the surviving episodes by year: the
    projection carries no per-year counts yet (contract follow-up).
  - **The row**: 64 px whatever it carries, a 48 px visual, the title
    (L3), the sub line (L5, muted, an event line), the length (L6), and
    Play (36 px). The visual is the date block (the month in small caps
    over the day in Big Shoulders, on the series' board; an undated
    numbered episode says "No." over its number) in a list of one
    series, and the series' window in a list that mixes series or lists
    series. A missing sub line centers the title in the same height. R1
    holds: the date leads, in the visual.
  - **The head board** (series, episode, ear drama): the board with the
    window (96 px, 128 from 600 px, 176 from 1024), the kicker (L5, upper
    case, tracked), the name (L1 in Big Shoulders, stepping down like the
    tile's), the facts, and the run strip full width under both (18 px
    until per-year counts are published, then 56). Built in D3-1; the series
    and episode pages adopt it in §6.4d.
  - **The event line**: facts joined by " · ", each separator kept with
    the fact before it, so a line may end on a dot and never opens with
    one.
  - **Color**: everything on a board takes its one onBoard color; marks
    (the strip on the page, legend keys, a part's face) take the genre
    hue (`color.genre`); no stripe on a card's edge (the 3 px genre edge
    of §6.4a and the 8 px edge of the typographic card retire with the
    head board in D3-3). Red still means recording.
- **§6.4c Home and Browse in direction D** (owner, 2026-10-29: *"Having
  more shows is better, so 5."*; *"I like the bulky blocks and colors of
  The Sleeve and I like the data visualization options of the Almanac."*;
  D3-2; the shared text for iOS-, macOS-, tvOS- and ANDROID-DESIGN R11c).
  Amends §4.3 (Browse's list) and §4.1 (Home's shelves); where it differs,
  this rule wins. **A show is a series of at least 5 episodes**
  (`API.isShow`); a shorter one is a single recording, counted and listed
  behind its own link, never in a shelf. **Home**: Continue listening and
  Following as before; the **day board** (neutral `surfaceAlt`: the kicker
  "This day in radio", the date, the count of surviving broadcasts and
  years, a strip of that date's broadcasts by year, each bar stacked by
  genre in the genre marks in a fixed order, the selected year outlined,
  and a legend of the genres seen); **that night** (the selected year,
  the peak by default, picked by a radio group of bars: tap, or arrow keys
  with one tab stop): show tiles for the shows on the air that night, a
  copy under the same title folded once, each tile's facts the episode and
  its length, six and then "All N shows that night", the single recordings
  counted as a fact; **Most downloaded**: 12 show tiles in a rail, "All N
  shows" to Browse. The catalog's episode shelves (onThisDay rows,
  mostDownloaded rows, genreFirsts) no longer draw on Home; their genre
  work is Browse's field. **Browse**: every filter and sort stays; a count
  line ("2,036 shows", then "8,605 single recordings" as a link); the
  **decade by genre field** (a square per cell in the genre mark, its side
  the square root of the cell's share of the biggest, 6 to 32 px, the
  count beneath, each cell a link applying genre and decade, counts over
  the shows passing the other filters; "N with no genre or date" is a
  fact); the results as a tile grid whose rows share their slot tracks
  (`subgrid`), headed by the sort ("Most downloaded first", "A to Z",
  "Most episodes", "Oldest first"); A to Z is the `shelf` of the
  prototype, the catalog as it is (most of it title blocks). From 1024 px
  the field sits beside the grid. The rules are `API.isShow`, `dayYears`,
  `nightShows`, `decadeField`, `fieldSide`, golden-tested in
  `js/api.test.js` and mirrored on every platform. Fit: no sideways
  scroll, no overflow, no broken word at 320, 375, 390 and 430 px, light
  and dark (checked in headless Chrome with a control that fails on a
  62-letter name). "Has a script" is a bordered control like the selects,
  filled when on (iPad Pro frame, 2026-10-30: it drew as bare text).
- **§6.4d Series and episode pages in direction D** (owner, 2026-10-29:
  *"an item with a picture, without one, rich or sparse, renders in the
  same structure"*; *"a share button that goes to the next line instead of
  being next to the other buttons"*; D3-3; the shared text for iOS-,
  macOS-, tvOS- and ANDROID-DESIGN R11d). Amends §4.4 and §4.5 and retires
  the print, the plate and the typographic-card head of §6.4a on these two
  pages; where it differs, this rule wins. **The series page** is the head
  board (kicker: the genre, then the networks; name; facts: the years or
  "Undated", then the count of episodes; the run strip), then one button
  row (Follow, Share), the picture's credit when its license asks and the
  window shows it, the season scope, and the episode list. **The episode
  page** is the head board of its show (a link to the series; its name a
  paragraph under the page's own h1), led by `API.leadPicture` (the show's
  own image; else the episode's star; else the first cast with a picture;
  else the series' picture; else the title block), then the episode's title
  (the h1), its **event line** (`API.episodeFacts`: the date, else
  "Undated"; the network, sponsor, length, season, and its number when the
  title does not say it), one button row (Play, Add to queue, Share), the
  "Start an ear drama" row only where a castable script exists, **On the
  air** (`API.onAirOf`: the cast in billing order, each once, at most 6,
  each a 72 px round window over the name and the character; a face with
  no picture is the title block), "Cast and credits" folded (the full
  grouped list), then the recordings and the rights line. A section with
  nothing in it is not drawn and the sections after it close up; no slot is
  moved by a rich page or a bare one. **A button row never wraps apart**:
  one flex row without wrap, Play and Follow taking the room, and Add to
  queue and Share folding to their icons (44 px, the label kept as the
  accessible name) when the row is under 480 px; a long action ("Start an
  ear drama") has its own row. The head board's strip is 18 px until the
  projection carries per-year counts (then 56 px, as in the prototype).
  Rules golden-tested in `js/api.test.js`; fit checked at 320, 375, 390 and
  430 px, light and dark, by `tools/web_fit_actions.py` (a control with the
  row allowed to wrap fails it: the share button drops a line).
- **§6.4e Browse's A to Z jump and the D3-fix rules** (owner, 2026-10-30: *"We are building for each specific platform. It has to look good and use native design and apis on the given platform."*; *"Yes, add a letter jump"*). While Browse sorts A to Z a `nav` of letter links (`API.azLetters`: only a letter that has shows, "#" first for numbers and symbols) sits over the grid; a link pages in the tiles up to its letter and scrolls there. The decade headers are short ('20s). Every platform: an undated, unnumbered episode leads its row with the series' window, never an empty date block; the run strip draws one bar per year from `series.year_counts` (web: `years`), its height the count over the show's busiest year, and falls back to the first-to-last span where the catalog has none; the head board's strip is taller than the tile's; the series page's genre is a link that opens Browse at its root filtered to that genre; an episode with a `script` offers Start an ear drama (not on a TV). The head strip is 32 px, 40 from 600 px.

- **§6.5 Icons are inline SVG** (R-ICON-1); emoji are never chrome.

## §7 States, PWA, and offline

- **§7.1 Every list has loading, empty, error, and offline states**
  (`universal-feature-states`), drawn by one function, `stateBox`. Empty
  is a sentence (§7.1a); error and offline carry Try again; "Not in the catalog"
  has no retry because retrying cannot help.
- **§7.1a The empty state is the fact and at most one way on** (P4,
  2026-10-28). The rule it serves (AGENTS.md, owner): "Only essential
  words on screen. A caption must be a refusal, a warning, or a fact the
  person cannot discover by looking." `stateBox('empty', { text,
  action })` draws the sentence and, when one helps, one link
  (`{ label, href }`, a `.btn`). Library's Queue ("Nothing queued."),
  History ("Nothing played yet."), and Following ("Not following any
  series.") link to Browse; Browse with nothing matching links "Clear
  filters" (keeping the sort). No results echo the query, "No matches
  for “{query}”.", and suggest nothing. An empty state never replaces
  navigation: the account row, Listen together, Library's sections, and
  the footer's site pages stay drawn around it.
- **§7.1b No hints** (one-shot tips), as iOS §7.5: each candidate
  repeats a visible control, and Search finding words said in an
  episode belongs in the search placeholder (the owner's copy call). No
  dismissal store, no "Show tips again".
- **§7.2 Service worker** (`sw.js`): the shell is cache-first under a
  versioned name (`ed-shell-vN`); catalog JSON is network-first with the
  last good copy as the fallback (`ed-data-vN`), yielding to the copy
  after 4 s; audio, ranged requests, `/pulse/`, `/cast/`, and other
  origins' pages pass through. Activate deletes every older `ed-` cache.
  An offline navigation to a path twin falls back to the cached
  `404.html`, which forwards it. `tools/test_sw.mjs` checks the routing
  out of the shipped file.
- **§7.2a The web does not download audio** (Decision 071). Episodes
  stream from archive.org and pass the service worker untouched; no
  Download control, no audio in Cache Storage or OPFS. The places where
  offline listening matters, a phone in the car and a phone at bedtime
  with the screen locked, are where a browser is weakest: iPhone web
  stops a page's audio at the lock screen and its storage is
  best-effort, so a file counted on for the trip can be gone without a
  word, and Android has the app. A download the web cannot promise to
  keep is not offered. PARITY's Downloads cell is n/a with this reason.
- **§7.3 Offline is a degraded mode, not a failure.** A status line,
  "You are offline.", sits in the document flow while the browser
  reports no network. Whatever the person opened before still opens; a
  view that was never opened shows the neutral offline state, never the
  error color. `API.isOffline()` is the one test of it; the `?offline=1`
  door holds the state for a screenshot (it never blocks the network).
- **§7.4 On a local server the worker runs only with `?sw=1`**, and is
  unregistered otherwise, so a cache-first shell never hides an edit.
- **§7.5 Every control is labeled**, and the first screen is usable
  without sight (R21): a skip link, one `<h1>` per view, `aria-current`
  on the active tab, live regions for counts and announcements.

## §8 Values

- **§8.1 The rights line is the projection's words** (contract §5.5),
  drawn under the recordings. An unclaimed recording reads "No rights
  claim known. Removed on request." and is never called public domain
  (catalog Decision 001).
- **§8.2 The take-down page** says what to send, where, and that removal
  follows a claim a reader can open; the address is one constant in
  `js/site.js`. The designated agent's details are the owner's to fill
  after registration.
- **§8.3 No analytics, no cookies, no third-party scripts**, with one
  exception: Apple's and Google's sign-in scripts (§4.11), loaded only
  after the person opens the sign-in sheet, never on page load, and only
  when that provider is configured. The privacy page states exactly what
  this browser keeps; change it in the same change that changes what is
  kept (signed in: the account state in `ed.account`, the encrypted
  refresh token in IndexedDB `ed-auth`, per-row sync stamps in
  `ed.stamps`).
- **§8.4 The public-web gate is upstream.** Until the DMCA agent is
  registered, eardrama.org is built without `--include-unclaimed`; the
  client never filters.

## §9 Parity discipline

- **§9.1** Update `PARITY.md` in the same change set as any user-facing
  feature; quote these rule numbers in proposals.
- **§9.2 Not on the web yet**, each arriving with its milestone: the
  Stations' genre stations, downloads. Sign-in and sync (M5, §4.11) and Listen
  Together (M6, §4.12) are built and wait on the owner's Worker URL and
  client ids.

## §10 Traps this codebase has already paid for

- **§10.1 Bump `SHELL_VERSION` in `sw.js` on every web change.** An
  unbumped deploy reaches nobody, and `fetch(url, {cache:'no-store'})`
  does not bypass a service worker.
- **§10.2 An author `display` rule beats `[hidden]`.** Write the display
  on `.thing:not([hidden])`.
- **§10.3 An element turned into `<a>` inherits the bare `a` rule.** A
  link not shaped like a link needs `color: inherit; text-decoration:
  none`, with the affordance on `:hover` and `:focus-visible`.
- **§10.4 A render replaces before it appends.**
- **§10.5 Compute each facet against the other facets' selection.**
- **§10.6 One rule, one function.** An episode's name is `epTitle()`
  everywhere it is drawn or spoken.
- **§10.7 Headless Chrome's `--window-size` has a floor near 500 px.** A
  375 px screenshot taken that way is a crop of a wider layout. Set the
  viewport with DevTools' `Emulation.setDeviceMetricsOverride` instead.
