# The web app

Read this before any web work: views, routing, CSS, data, offline,
images, or deploys.

These rules lived in `AGENTS.md` until October 3, 2026, when it was cut
below 24,000 bytes so that Antigravity, which stops reading a rule file
at that size, would read all of it. They moved here word for word, and
`AGENTS.md` links to this page with one line saying when to read it. The
rules that hold on every platform stayed in `AGENTS.md`.

## Which skill

`web-platform-patterns` is the umbrella: view system,
  URL state, service worker, IndexedDB, image fallback chains, CSS
  gotchas, headless verification. Third-party page content (reader
  mode, link previews): `web-content-extraction`. Design skills
  under `KUI:<name>`; `frontend-design` for component-level work.

## Web app

**Stack**: Vanilla HTML/JS. No framework, no build step. Custom
CSS, mobile-first. <!-- FILL IN: API / auth / hosting choices -->.
GitHub Pages static hosting, branch `main`, root `/`.

**Key directories**:
- `/`: root; index.html, AGENTS.md (CLAUDE.md imports it), SCRATCHPAD.md, DECISIONS.md, design-tokens.json (the look, for every platform)
- `/css/styles.css`: single main stylesheet
- `/js/api.js`, `/js/app.js`: API abstraction + view system
- `/assets/`: static assets (shared with iOS + tvOS + Android)

**Run locally**: `python3 -m http.server 8080` → visit
http://localhost:8080. Deploy: push to `main`; GitHub Pages serves
automatically.

**Conventions** (the load-bearing ones; see skills for the rest):
- All API calls through `js/api.js`, never `fetch` directly
  elsewhere
- CSS custom properties in `:root` in `styles.css`, written from `design-tokens.json` (never edit the generated block by hand)
- Mobile-first; all media queries use `min-width`
- No inline styles
- Error states must be user-visible (not just console logs)
- **URL-driven state is the web's superpower.** Every surface gets
  a shareable canonical URL; filters live in query params. The web
  app doubles as the canonical link target for shares from every
  native platform: every `appname://item/x` has an `https://…/item/x`
  twin (see DEEP_LINKS.md).
  User-made lists travel in the link itself (`/list/#<deflated blob>`;
  DEEP_LINKS.md, "State in the link").
- **`cache:'no-store'` does not bypass a service worker**, and an
  author `display` rule beats `[hidden]` (write `.x:not([hidden])`).
- **Every `API.x` the JS calls must be exported by `js/api.js`**,
  checked by a test.

**Safari layout pitfall** (codified in the bundled CSS):
`body { height: 100dvh; display: flex; flex-direction: column;
overflow: hidden; }` with `main { flex: 1; overflow-y: auto;
min-height: 0; }`. NO `viewport-fit=cover`. NO `position: fixed`
overlays; they break Safari's compositor at the Dynamic Island.

**Modern web APIs to reach for first** (skip the npm dep / custom
fallback):
- `<dialog showModal>` for all modals (native focus trap + ESC)
- Popover API (`popover="auto"`) for dropdowns + tooltips
- View Transitions API for cross-view animations
- Container Queries (`@container`) for component-level responsiveness
- CSS `:has()` to kill JS class-toggle patterns
- Web Share API with `clipboard.writeText` fallback
- MediaSession API for lock-screen / media-key controls on any
  playing media
- `prefers-reduced-transparency` / `prefers-reduced-motion`
  overrides for every blur / animation
