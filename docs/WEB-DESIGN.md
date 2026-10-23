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
  until accounts (Decision 057: signing in is optional, never at first
  launch, and the first launch plays with zero taps).
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
- **§2.2 The projection decides; the client draws.** Rights, copy
  ranking, identity, and the public-web gate are settled by
  `catalog/tools/build_web_projection.py` (contract §4). The client adds
  no filter of its own (contract's one rule).
- **§2.3 Data files are versioned by the build, not the client.** A
  missing field is null; a removed episode is a 404, which the client
  shows as "Not in the catalog."

## §3 Routing and URL state

- **§3.1 Query routes, not hash routes.** `?view=listen|series|search|library`,
  `?series={key}&season=`, `?item={episode id}`, `?view=search&q=`,
  `?view=library&tab=`. This inverts the template's hash routes on
  purpose: query routes are what the path twins forward into.
- **§3.2 Every `eardrama://` link has an `https://eardrama.org` path
  twin** (`/series/{key}`, `/episode/{id}`, `/search?q=`, `/library`),
  forwarded by `404.html`. Never change these shapes; shipped apps share
  them (DEEP_LINKS.md).
- **§3.3 One router.** `route()` reads the location and shows one
  `<section hidden>`; focus moves to the view's `<h1>` on every
  navigation after the first.
- **§3.4 Site pages are real paths**: `/credits/`, `/privacy/`,
  `/takedown/`, each its own static page sharing `css/styles.css`.

## §4 Surfaces

- **§4.1 Navigation.** Four destinations, Listen, Series, Search,
  Library: a bottom tab bar on a phone, a sidebar from 768 px. The car
  reduces to four tabs, so the phone has four (R17). Depth is at most
  two from a tab: tab, series, episode; a season or a Library section is
  a segmented scope, never a push.
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
- **§4.6 Search** is word-prefix over the projection's term files,
  debounced 180 ms, series first, then episodes paged 30 at a time, the
  query mirrored to the URL.
- **§4.7 Library** = Queue, History, Following, on this device. Clear
  history asks first.
- **§4.8 Site pages live in a quiet footer**, at the end of every view's
  scroll and on each site page: Credits, Privacy, Take-down requests.
  They are never featured in the main UI (AGENTS.md "side doors").

## §5 The player

- **§5.1 One `<audio>` element** owned by `js/player.js`; the views draw
  it. The bar is a flex child above the tab bar, never `position: fixed`
  (§6.3). Now Playing is a `<dialog showModal>`, full screen on a phone.
- **§5.2 Speed, the sleep timer, and skip live on the player** (R18):
  back 15 s, forward 30 s, speed 0.8× to 2×, kept on the device.
- **§5.3 Bedtime is a mode** (R20). The sleep timer offers "End of this
  episode" first, fades the volume over its last 20 s, and nothing
  starts again until the person presses play.
- **§5.4 Lean-back is bounded** (R3, R14). At an episode's end the next
  one plays only when the person queued it and it is from the same
  series.
- **§5.5 Never skip the commercials** (R8). Skip is a fixed interval,
  never a jump past a segment.
- **§5.6 Media Session** carries the title, series, and date, with play,
  pause, and seek handlers. Keyboard: k or space toggles, j and l skip.
- **§5.7 Progress persists** every 10 s and on pause; resume only inside
  the 10 s to 95% window.
- **§5.8 Audio is never cached** by the service worker (§7.2).

## §6 Look

- **§6.1 Every value is a token** from `design-tokens.json`; nothing in
  `styles.css` names a color. Brand chrome and genre accents never mix
  (R12): genres reach the page only through `data-genre` and
  `--genre-accent`, neutral until the owner picks the hues (Decision 060).
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
- **§8.3 No analytics, no cookies, no third-party scripts.** The privacy
  page states exactly what this browser keeps; change it in the same
  change that changes what is kept.
- **§8.4 The public-web gate is upstream.** Until the DMCA agent is
  registered, eardrama.org is built without `--include-unclaimed`; the
  client never filters.

## §9 Parity discipline

- **§9.1** Update `PARITY.md` in the same change set as any user-facing
  feature; quote these rule numbers in proposals.
- **§9.2 Not on the web yet**, each arriving with its milestone: the
  Radio tab (R9, R10), transcripts (R16), downloads, sign-in and sync
  (M5), Listen Together (M6).

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
