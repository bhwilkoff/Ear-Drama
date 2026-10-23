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

- **§3.1 Query routes, not hash routes.** `?view=listen|series|radio|plays|search|library`,
  `?series={key}&season=`, `?item={episode id}`, `?view=search&q=`,
  `?view=library&tab=`, and for plays (§4.10) `?play={script id}`,
  `?production={id}`, `?production={id}&part={part id}`, and `?room={CODE}`
  (§4.12), which opens the Listen Together sheet over the Listen view. This inverts the
  template's hash routes on purpose: query routes are what the path twins
  forward into. A production lives only in the browser that made it
  (PLAYS-DESIGN §6), so its routes have no path twin and no app link.
- **§3.2 Every `eardrama://` link has an `https://eardrama.org` path
  twin** (`/series/{key}`, `/episode/{id}`, `/search?q=`, `/library`),
  forwarded by `404.html`. Never change these shapes; shipped apps share
  them (DEEP_LINKS.md).
- **§3.3 One router.** `route()` reads the location and shows one
  `<section hidden>`; focus moves to the view's `<h1>` on every
  navigation after the first.
- **§3.4 Site pages are real paths**: `/credits/`, `/privacy/`,
  `/takedown/`, `/delete-account/`, each its own static page sharing
  `css/styles.css`.

## §4 Surfaces

- **§4.1 Navigation.** Six destinations, Listen, Series, Radio, Plays,
  Search, Library (05-design-research §8, plus Plays on 2026-10-23, as the
  Apple apps carry a Plays tab, Decision 059): a bottom tab bar on a phone,
  six columns at 375 px, and a sidebar from 768 px. The phone's six reduce to the car's four
  (Continue, Radio, Series, Downloads) without a new one (R17). Depth is
  at most two from a tab: tab, series, episode; Plays, cast sheet, part;
  a season or a Library section is a segmented scope, never a push.
- **§4.2 Listen** = Continue listening (this device), Following, This day
  in radio, then shelves by rule from `index/listen.json`. Each section
  draws only when it has rows.
- **§4.3 Series browse** = genre, decade, and network selects plus sort.
  Each facet's counts are computed against the other facets' selection,
  so no offered choice yields zero rows (§10.5). The real count is shown.
- **§4.4 A series page** lists its episodes oldest first, every row
  leading with its air date in tabular figures (R1). Seasons are a
  segmented scope; undated episodes are their own scope.
- **§4.5 Episode detail** shows the series, the title, the date, one
  caption line of facts, Play, queue, Share, the cast and credits, the
  recordings, and the rights line. Every part draws only from data, and
  a part with no data is absent, never a placeholder:
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
  debounced 180 ms, series first, then episodes paged 30 at a time, the
  query mirrored to the URL.
  - **Gap: web search does not find transcript words.** The apps match
    them through the served projection's `episodes_fts` (contract §3.4),
    but that index is contentless, so the web builder has no text to cut
    term files from, and adding about 9,000 transcripts' vocabulary to
    the two-character term files is a size to measure before it is
    built (contract §4). The client never builds an index of its own
    from fetched transcripts: it would search only what this browser
    happened to open. Until the projection carries transcript terms,
    transcript search is native only (PARITY).
- **§4.7 Library** = the account row (§4.11), then Queue, History, Following, on this device. Clear
  history asks first.
- **§4.9 Radio** = Tonight in 19xx: the evening `tonight.json` publishes
  for the listener's own calendar date (contract §8), as the night's
  schedule. Each slot shows its local time with the original Eastern time
  beside it as a fact ("7:00 PM ET" alone where the two agree), and the
  slot on the air is marked on the one clock, read from the file's UTC
  instants (R10). A surviving slot links to its episode and plays from
  its start; "Listen live" joins the slot on the air where the clock
  stands, and each later surviving slot starts at its own time. A pause,
  another episode, or the sleep timer ends listening live, and so does
  the last slot: nothing plays after the evening (R14). A gap is drawn as
  a gap (R9): its time, its length, the catalog series name only where the
  file sets `known_series`, and "Not surviving" (or "Not in the catalog"
  for a recording this projection does not serve). The paper's OCR text
  (`printed`) stays in the file as witness and is **not drawn** until the
  owner rules on it. The listing is credited in one caption line linking
  the page it was read from. No evening for today is the empty state.
- **§4.10 Plays: pass the phone** (`docs/PLAYS-DESIGN.md` is binding on
  what the feature does; this rule is how it looks on the web). Code:
  `js/plays-core.js` (the script, production, relay, timeline, and audio
  math, mirroring `apple/Core/Plays`), `js/plays-store.js`,
  `js/plays-voice.js`, `js/plays-audio.js`, `js/plays-worklet.js`,
  `js/plays-session.js`, `js/plays-ui.js`; tests `js/plays.test.js`.
  - **Not on a TV**: the smart-TV layer (`html.tv`) hides the Plays tab, as
    Android TV does; TVs play back only (research 08 §5).
  - **The list** (`?view=plays`): "Your plays" (this browser's
    productions, newest first, each with "N of M lines recorded" or
    "Finished"), then "Plays you can cast" from
    `data/plays/castable-scripts.json`, read generically through
    `API.castableScripts`. Each play shows its title, author, part count,
    and its rights evidence claims verbatim, each linked to its source,
    and the source's name linked. Nothing on it is written by the app.
    The Pages deploy copies the file into `data/plays/`
    (`catalog-publish.yml`); locally, copy it into the `data` link's
    `plays/` folder.
  - **A play** (`?play=`): the same lines, "Cast this play", and its parts
    largest first with line counts (directions and sound are parts too).
    Casting replaces this page in the history with the cast sheet, so the
    depth stays two.
  - **The cast sheet** (`?production=`): every part with its state. Only
    the relay's next part offers "Take part", with an optional name field;
    sound and directions may "Leave silent"; a finished part offers "Open
    part" only while no part records (C7). A refusal is one line in the
    error color. Below: Listen through (§2.6, C5: offered only when every
    speaking line has a human take), Export once finished, Discard unused
    takes, Delete production (asks first).
  - **Recording** (`?production=&part=`): before anything, the
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
    Play is enabled only when the browser refused to start the sound,
    and that one tap starts it. The mini player's caption reads
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
- **§5.4 Lean-back is bounded** (R3, R14). At an episode's end the next
  one plays only when the person queued it and it is from the same
  series.
- **§5.5 Never skip the commercials** (R8). Skip is a fixed interval,
  never a jump past a segment.
- **§5.6 Media Session** carries the title, series, and date, with play,
  pause, and seek handlers. Keyboard: k or space toggles, j and l skip.
- **§5.7 Progress persists** every 5 s (`SAVE_EVERY_MS`) and on pause;
  resume only inside the 10 s to 95% window. A pause the browser made (a
  call, another tab's sound), not the person, is an interruption: the
  next play starts 3 s back (`REWIND_S`). DECISIONS 062 holds all four
  numbers; `js/player.test.js` checks them.
- **§5.8 Audio is never cached** by the service worker (§7.2).

## §6 Look

- **§6.1 Every value is a token** from `design-tokens.json`; nothing in
  `styles.css` names a color. Brand chrome and genre accents never mix
  (R12): genres reach the page only through `data-genre` and
  `--genre-accent`, which the generator sets per catalog genre key.
- **§6.1a Color roles (Decision 064, On Air).** Red (`--color-primary`)
  is only for what is live: Play, the progress line, the slot on the air
  now, Listen live, and Start recording (the microphone is live). Blue
  does the wayfinding: `--color-link` for links and the focus ring;
  `--color-secondary` for the selected tab and sidebar item, a pressed
  toggle, a checked control, the loading spinner, and every filled
  button that is not Play. Genre hues (`--color-genre-*`) are content:
  the series card's and row's genre edge and the series page head, never
  a button, a tab, or a link.
- **§6.2 Density from removing chrome.** Six type levels (page title,
  section header, body strong, body, caption, tabular), system fonts.
- **§6.3 Safari layout.** `body { height: 100dvh; display: flex;
  flex-direction: column; overflow: hidden }`, `main` is the one scroll
  container. No `viewport-fit=cover`, no `position: fixed` overlays.
- **§6.4 Cards are typographic** (R11): the name, one meta line, the
  genre edge. No placeholder art.
- **§6.5 Icons are inline SVG** (R-ICON-1); emoji are never chrome.

## §7 States, PWA, and offline

- **§7.1 Every list has loading, empty, error, and offline states**
  (`universal-feature-states`), drawn by one function, `stateBox`. Empty
  is a sentence; error and offline carry Try again; "Not in the catalog"
  has no retry because retrying cannot help.
- **§7.2 Service worker** (`sw.js`): the shell is cache-first under a
  versioned name (`ed-shell-vN`); catalog JSON is network-first with the
  last good copy as the fallback (`ed-data-vN`), yielding to the copy
  after 4 s; audio, ranged requests, `/pulse/`, `/cast/`, and other
  origins' pages pass through. Activate deletes every older `ed-` cache.
  An offline navigation to a path twin falls back to the cached
  `404.html`, which forwards it. `tools/test_sw.mjs` checks the routing
  out of the shipped file.
- **§7.3 Offline is a degraded mode, not a failure.** A status line,
  "You are offline.", sits in the document flow while the browser
  reports no network. Whatever the person opened before still opens; a
  view that was never opened shows the neutral offline state, never the
  error color.
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
  Radio tab's genre channels, transcript search (§4.6; reading a transcript
  is on Detail, §4.5), downloads. Sign-in and sync (M5, §4.11) and Listen
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
