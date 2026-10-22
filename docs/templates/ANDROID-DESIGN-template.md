# [APP NAME] Android design (binding)

<!-- Seed for docs/ANDROID-DESIGN.md. Invoke
     `binding-design-doc-discipline` for the workflow and
     `android-production-gotchas` for the mechanics this doc does NOT
     restate (dbVersion invalidation keying, BundledSQLiteDriver, the
     staged atomic DB swap, the contradictory-WHERE silent-empty bug,
     sealed-Route nav + deep-link inbox, Media3 queue flags, emulator
     verification).

     The §N structure and the rules baked in below are ANDROID platform
     facts, true for any Compose app on this template's shared data
     plane. Keep them. Replace every [BRACKET]; delete the <!-- FILL -->
     notes. Sections marked "(optional module)" apply only if the app
     has that surface. When a rule inverts an iOS/tvOS rule, that
     inversion is deliberate (the Material idiom of the same verb). -->

**Binding.** Quote the rule number before proposing any new screen,
route, sheet, or data path in the Android app (`android/`). If no rule
fits, propose a NEW rule first. Companion to `PARITY.md`,
`docs/DATA-CONTRACT.md`, and the sibling design docs. The platforms
share verbs, never idioms (PARITY "same verb, native idiom").

## §1 Principles

- **§1.1 Android feels like Material.** The feature set matches the
  other platforms; the expression is Material 3: bottom bar/rail,
  `FilterChip`, `DropdownMenu`, `Switch`, `TabRow`. Never port iOS or
  tvOS chrome; never invent a custom control where an M3 one exists
  (`native-platform-first`).
- **§1.2 Compose-only, single Activity.** No Fragments, no AppCompat,
  no XML layouts beyond the splash/launcher theme. `minSdk [29]`,
  edge-to-edge.
- **§1.3 One shared data plane.** The phone consumes the same published
  data as every other client. No Android-only reads, hosts, or
  pipelines, and never re-derive policy flags client-side (the
  contract's one rule, `shared-data-plane-contract`).
- **§1.4 Hilt for dependencies, one navigation root.** The starter uses
  Hilt and a single `AppRoot` that owns the back stack; deep links and
  launch doors land in an inbox the root drains (`navigation/LaunchDoors.kt`).
  `BackHandler` only confirms unsaved changes. Split into modules only
  when build times or ownership demand it. Propose a rule change first.
- **§1.5 Depth ≤ 2 from any tab root.** Tab → grid/list → detail. A
  would-be third push must be a scope chip, dropdown, or sheet. Player
  and Settings are pushed routes; only an immersive surface is full-screen.

## §2 Data plane (contract compliance)

<!-- These rules assume the template's shared read-only SQLite data
     plane. If your Android app reads a different source, keep the
     invalidation + refresh discipline (§2.4/§2.3) and adapt the rest. -->

- **§2.1 One data read path.** A single repository layer implements the
  contract's query verbs with the standard filter clauses (visibility
  gates). Screens never touch SQLite, OkHttp, or asset files directly;
  they go through `AppContainer`'s repositories.
- **§2.2 BundledSQLiteDriver, read paths only.** The bundled driver
  **guarantees FTS5**; never fall back to framework SQLite for the
  dataset (framework SQLite may lack FTS5). Decode only the rows a
  screen shows, with no in-memory copy of the whole dataset.
- **§2.3 The refresh ritual is fixed:** ETag-conditional GET of the
  compressed DB → stream-inflate raw DEFLATE (`Inflater(nowrap = true)`,
  64 KB chunks) to a STAGING file → size floor → open-probe row count →
  **atomic rename** → store ETag → bump `dbVersion`. Any failure keeps
  the cached DB; the bundled seed is the floor.
- **§2.4 Screens re-query on `dbVersion`.** Every screen that holds query
  results keys its `produceState`/`LaunchedEffect` on the data layer's
  `dbVersion` (and the user-state change signal where user records
  matter) so the
  seed→full-DB swap and filter changes propagate everywhere. **Forgetting
  this key is the classic "screen shows zero items" bug.**
- **§2.5 Editorial config is fetched, not re-hosted** (bundled copy as
  offline fallback). Composed sections resolve through a curated map,
  never by re-running a broad query (the duplicate-section bug).
- **§2.6 User state is local-first**: a tiny `user.sqlite` (same bundled
  driver); scalar settings in DataStore with the shared key names. A
  [sync island: Google Drive App Data] is a later wave (§7) and gates
  ONLY sync. Browse always works signed-out (`per-ecosystem-sync-islands`).

## §3 Navigation shell

- **§3.1 [N] content tabs, hard set: [list]** via `NavigationSuiteScaffold`
  (bottom bar → rail → drawer by window size: one hierarchy, never
  forked per form factor). Settings is NOT a tab; it lives behind the
  gear. A new tab requires amending this rule.
- **§3.2 One route registry.** Every pushable destination is a case of
  the sealed `Route` handled in `AppRoot`. New destinations extend
  `Route`, never a per-screen ad-hoc overlay.
- **§3.3 System back pops the stack** (`BackHandler`); tab taps clear it.
- **§3.4 Deep links land in a pending-item inbox.** `[scheme]://item/{id}`
  (same scheme as the other platforms) is parsed in `MainActivity` and
  consumed once by `AppRoot`. New entry points (App Links, App Shortcuts)
  extend this inbox, never push routes from outside the composition. **App
  Links require the Play App Signing cert SHA-256 in `assetlinks.json`**
  (`store-submission-playbook`).

## §4 Surfaces

- **§4.1 Home order is fixed** and documented here (deduped downward,
  sections dropped under [N] items: the stub rule). Inserting a section
  means amending this rule. A visibility toggle (Settings) filters
  consumed items where applicable.
- **§4.2 Browse** = scope `FilterChip`s + facet dropdowns + adaptive
  `LazyVerticalGrid` with paging-on-scroll ([N]/page) and the REAL total
  from the count query. **Beware the contradictory-WHERE silent-empty
  bug: a clause that both EXCLUDES a type AND filters FOR it returns zero
  rows.** Branch explicitly (`android-production-gotchas`).
- **§4.3 Search** = debounced (~[180] ms) full-text over the FTS5 index,
  grid results, explicit empty states.
- **§4.4 Detail** = header → title/meta → primary action → body →
  [rich-metadata rows, each shown only when present] → related. A
  parent/children variant (if content nests) uses a selector + a child
  list.
- **§4.5 Library / saved state** over `user.sqlite`. Empty states are
  explicit sentences, never blank space (`universal-feature-states`).
- **§4.6 Tiles are content + two text lines, nothing else** (density from
  removing chrome). Stable `key`s on every `LazyGrid`/`LazyRow`.

## §5 Player *(optional module; delete if no media)*

<!-- KEEP only if the app plays audio/video. -->

- **§5.1 Media3 `PlayerView` owns transport.** `keepScreenOn`, OkHttp
  `DataSource`, and a patient custom `LoadErrorHandlingPolicy` (more
  retries, modest capped backoff) so idle-connection resets resume from
  the byte offset instead of failing (the Android analog of a resilient
  loader, `resilient-media-streaming`). Overlays only; never a parallel
  transport.
- **§5.2 Never a runtime quality/bitrate ceiling** if the source URL is
  chosen at build time.
- **§5.3 Progress persists every [10] s and on dispose**; resume seeks
  within bounds. Ephemeral/live playback must NOT persist progress.

## §6 Theme

- **§6.1 [Brand theme]; dynamic color is NOT the default.** Material You
  dynamic color may become a Settings opt-in later; it never becomes the
  default (the brand identity is the product).
- **§6.2 Brand vs semantic split is absolute:** primary + accent are
  chrome/CTA only; any per-category accents carry content meaning only.
  Never a brand color for meaning, never a semantic accent for chrome.
- **§6.3 M3 typography styles only:** `headlineSmall`, `titleMedium`,
  `bodyMedium/Small`, `labelMedium/Small` with weight modifiers; six
  hierarchy levels, refuse a seventh (AGENTS.md density rule).

## §7 Out of scope on Android v1 (intentional, next wave)

<!-- FILL: what ships later, not never, each with the reason, so it
     isn't partially implemented without a rule. Common items: Glance
     widgets + App Shortcuts, the Google Drive App Data sync island
     (needs the shared OAuth client; never a custom backend, never
     CloudKit), Google Cast, category-visibility toggles. -->

## §8 Parity discipline

- **§8.1** Update `PARITY.md` in the same change set as any user-facing
  feature; proposals/commits quote these rule numbers.
- **§8.2** A feature that lands differently from tvOS/iOS must be the
  *native Material idiom* of the same verb. Name the rule it mirrors or
  deliberately inverts. Emulator-verify (release build) before claiming
  done (`android-production-gotchas`).
