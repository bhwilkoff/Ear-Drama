# [APP NAME] iOS and iPadOS design (binding)

<!-- Seed for docs/iOS-DESIGN.md. Create once the iPhone/iPad app
     passes ~5 views. Invoke `binding-design-doc-discipline` for the
     workflow and `ios-production-gotchas` for the mechanics this doc
     does NOT restate (presentation races, layout traps, size-class
     adaptivity, simulator verification).

     HOW TO USE: the §N structure and the platform-truth rules baked in
     below are iOS FACTS, true for any iPhone/iPad app. Keep them.
     Replace every [BRACKET]; delete the <!-- FILL --> notes. Sections
     marked "(optional module)" only apply if your app has that kind of
     surface; delete the module if it doesn't. §4.1 is the exact
     inverse of the tvOS focus rule. Keep the inversion and the note. -->

**Binding.** Every new view, tab, sheet, grid, route, or toolbar item
in the iPhone/iPad app must trace to a rule in this document. When
something feels overwhelming or inconsistent, **fix this document
first, then fix the feature.** Proposals (and commits) cite the rule
they implement, e.g. "per iOS-DESIGN §2.3."

Division of labor:
- **This doc** = the *binding contract* for the iOS/iPadOS surface:
  navigation shell, touch idioms, screen composition, state rules.
- **`docs/tvOS-DESIGN.md`** = the tvOS contract. The two share verbs,
  never idioms (PARITY "same verb, native idiom"). When a rule below
  inverts a tvOS rule, that inversion is deliberate. Do not
  "harmonize" them.
- **`ios-production-gotchas` skill** = the mechanics + failure modes.
- **`PARITY.md`** = what ships where; updated in the SAME change set.
- **`DECISIONS.md`** = the why behind non-obvious rules.

<!-- If iOS shares a universal target with tvOS/macOS, say so: all iOS
     UI lives in `[…]/iOS/*_iOS.swift` inside `#if os(iOS)` guards;
     shared logic (data, networking, sync) is consumed from Core, never
     duplicated. The few deliberate copies carry a "don't let them
     drift" comment as unification debt, not a pattern. -->

---

## §1 Principles (the why)

1.1 **Same verb, native idiom.** The feature set matches the other
platforms; the expression is whatever iOS users already know: tab bar,
`.searchable`, segmented pickers, swipe-to-delete, `ShareLink`, sheets
with detents. Never port a 10-foot layout to the phone; never invent a
custom control where a native one exists (`native-platform-first`).

1.2 **Touch replaces focus.** There is no focus engine. The tap is the
verb; the element is the chrome. Density comes from removing decoration
(`mobile-first-density-design`). Design for iPhone portrait first, then
let iPad adapt (§2.2, §5).

1.3 **One shared data plane.** The phone consumes the same published
data + sync database as every other client. No iOS-only data reads,
hosts, or pipelines (`shared-data-plane-contract`).

1.4 **[Posture: what this platform is FOR relative to the others.]**
<!-- FILL: e.g. the primary create/capture surface, the on-the-go
     companion, etc., and which idioms therefore don't belong here
     (a 10-foot idle screensaver has no place on a phone). -->

1.5 **Depth ≤ 2 from any tab root.** Tab → list/grid → detail. A
would-be third push must be a scope (segmented picker, Menu facet), a
sheet, or a different tab. Modal presentations don't count as pushes.

1.6 **[Content-quality posture]:** mirror tvOS §1.6 if the app has one.

1.7 **Voice:** plain labels, evocative supporting copy, no
internal/pipeline language. Copy lives in shared config, not Swift.

---

## §2 Navigation shell

2.1 **[N] content tabs, hard set: [list].** Settings is [NOT a tab;
it sits behind the gear, presented as a sheet]. The tab bar is reserved for
content verbs; adding a tab requires amending this rule first. A search
tab uses `role: .search` so the system places it natively.

2.2 **One shell, both form factors.** Root is `TabView(selection:)` +
`.tabViewStyle(.sidebarAdaptable)`: bottom tab bar on iPhone, sidebar
on iPad/regular width. Do NOT add a parallel `NavigationSplitView` code
path; adaptivity comes from the one control. Views adapt to regular
width via `@Environment(\.horizontalSizeClass)`, **never via `UIDevice`
checks**.

2.3 **One destination registry.** Every tab's `NavigationStack` applies
a single shared destination registry. **A new pushable destination MUST
be a `Hashable` route registered there, never a per-view
`navigationDestination`.** This is what lets any surface push the same
screens from any tab.

2.4 **Router owns navigation state.** A `Router` (@Observable) holds the
selected tab and one `NavigationPath` per tab. Views navigate via
`router.push(_:)`, appending to the *active* tab's path. Never
construct a `NavigationLink(destination:)` to a shared screen and never
mutate another tab's path directly.

2.5 **Deep links, intents, and widgets land in an inbox.** The intent
or `onOpenURL` drops a request; the root consumes it once foregrounded.
New entry points extend the inbox + the root's handler; they never
touch `Router` directly from outside the view tree.

2.6 **Full-screen "modes" from tvOS become ordinary pushes on iOS.**
Reached from a toolbar button; back-swipe always works. Only [a player]
goes full-screen (§4.4). This deliberately inverts tvOS-DESIGN §9 ("a
mode replaces the shell"): on the phone the nav bar IS the exit.

---

## §3 Surface taxonomy (the only allowed shapes)

Every iOS screen maps to exactly one. A new shape needs a new rule.

3.1 **Tab:** one of the §2.1 verbs. `NavigationStack` + the registry.
3.2 **Row:** a horizontal `ScrollView` + `LazyHStack` of tiles.
3.3 **Grid:** `LazyVGrid(columns: [GridItem(.adaptive(minimum:…))])`,
paged where the set is large. The adaptive minimum is what makes one
grid serve iPhone and iPad.
3.4 **List:** native `List`/rows for textual/row-shaped content; swipe
actions for destructive verbs (§4.3).
3.5 **Detail:** a scroll view of primary content → title/meta → action
row (primary prominent) → body → related.
3.6 **Sheet:** transient pickers and forms; `presentationDetents`.
On iPad, `.presentationCompactAdaptation(.popover)` is for LEAF
surfaces only (filter panel, single-action picker): **a modal
presented from inside a popover silently no-ops.** A surface that
re-presents (sign-in, sub-flows) stays a plain `.sheet` on every
size class. This exact trap earned an App Store 2.1(a) rejection
("tapping Sign In does nothing on iPad").
3.7 **Full-screen cover:** reserved for [the player / an immersive
surface] only (§4.4).
3.8 **Tile:** [content tile] for content; gradient-on-accent compact
tiles for navigation chips. New tile shapes extend these two.

---

## §4 Touch idiom (binding)

4.1 **`.buttonStyle(.plain)` on tiles is CORRECT on iOS.** Tiles wrap in
`Button { router… } label: { tile }.buttonStyle(.plain)`. This is the
exact inverse of the tvOS guardrail (tvOS-DESIGN §6.1). There is no
focus engine to destroy, and `.plain` keeps content from being tinted
as a button. Rows with two tap targets use `.borderless` so both
hit-test. **Never apply the tvOS rule to iOS files or vice versa.**

4.2 **Native controls only.** Scopes = segmented `Picker`. Facets/sort =
a toolbar `Menu` of Pickers. Forms = `Form`/`Section`. Search =
`.searchable` + a ~180 ms debounced `.task(id: query)`. Sharing =
`ShareLink`. Empty/error = `ContentUnavailableView`. Every
list/grid/sheet declares loading · loaded · empty · error
(`universal-feature-states`).

4.3 **Destructive verbs are swipe actions** (`onDelete`). Deletion of
synced models goes through a tombstone recorder, never a bare
`ctx.delete` (§9.4).

4.4 **`fullScreenCover` is for the one immersive surface only.**
Everything else transient is a `.sheet`. Cover presentation binds to an
**item, not a Bool**, whenever the content is data-dependent:
`fullScreenCover(item:)` (the `isPresented:` race ships a blank screen;
`ios-production-gotchas`). Immersive cover content applies
`.ignoresSafeArea()`.

4.5 **Pickers open at medium detent** so context stays visible behind.

4.6 **Content is never silently cropped where it is the subject.** A
fixed-frame tile may `.fill`; a hero/detail image shows the real
content `.fit` (over a blurred fill of itself, so letterboxing reads as
intentional). Use `Text(verbatim:)` for numbers that must not localize
(the "1,960" locale-comma bug).

4.7 **Image loading** rides `AsyncImage` over the launch-configured
`URLCache` (e.g. 64 MB / 400 MB) with a quiet placeholder. Don't add
per-view caches or third-party loaders. **Exception: high-churn
`Lazy*` surfaces** (feed, gallery, image grids): `AsyncImage` shows
the wrong image in recycled cells and decodes full-res on the main
thread; those surfaces use the ONE shared cached loader
(URL re-check after await + off-main downsample;
see `ios-production-gotchas` §Image loading), still never a per-view
cache or a third-party package.

4.8 **Haptics use the app's semantic taxonomy only:** `selection` /
`light`·`medium`·`heavy` / `success`·`warning`·`error`, never a
bare `UIImpactFeedbackGenerator` at a call site. `error` always
pairs with a surfaced error banner; `selection` always pairs with a
page/segment change (AGENTS.md §Shared design system).

---

## §5 Home / primary-surface composition (binding)

<!-- If your app has a composed home surface. Delete if the first tab is
     a plain list/grid. -->

5.1 **The section order is fixed** and documented here. Inserting a
section means amending this rule, not appending wherever.

5.2 **Sections resolve by a prebuilt id/map, not by re-running a broad
query per section.** Resolving several sections from the same broad
query is how they all end up showing the same items.

5.3 **Dedup downward.** An item shown in an earlier section is excluded
from later ones. The home surface must never be several aliases of the
same list.

5.4 **Min [N] per row (the stub rule).** Below the floor a row reads as
a ragged stub. Drop it rather than show it thin.

5.5 **Shuffles/randomization are seeded once per surface lifetime** so
the layout is stable across body recomputes and re-rolls only on a
fresh appearance.

5.6 **Adapt by size class**, not device. The compact hero becomes a
width-capped centered card at regular width so a wide screen never
stretches it into an extreme crop.

5.7 **[Widgets]** *(optional):* whenever the home surface rebuilds,
write the App Group snapshot via ONE writer; the widget target
duplicates the Codable shape, so both sides change together.

---

## §6 Typography & density (binding)

6.1 **Native Dynamic Type styles only:** `.title`, `.headline`,
`.subheadline`, `.body`, `.caption`, with weight modifiers. The only
sanctioned custom sizes are inside compact navigation tiles (where the
tile is an illustration). A `font(.system(size:))` outside a tile is a
violation; refactor to a style.

6.2 **Six hierarchy levels, period** (AGENTS.md density rule).

6.3 **Body/long text lives on Detail.** Rows and tiles carry title +
one meta line at most.

6.4 **One section-header pattern everywhere** (title `.title3.semibold`
+ optional secondary `.subheadline`).

6.5 **Every redesigned surface holds at the accessibility text sizes.**
Check it at `accessibility2` or larger before it ships. A DEBUG launch
hook that sets the size (`.dynamicTypeSize(...)` from an env var)
renders the app there without touching the phone's settings. The usual
repairs: a row of tiles becomes a grid when
`dynamicTypeSize.isAccessibilitySize` is true, an icon square becomes a
`@ScaledMetric`, and a row moves its secondary text underneath with
`ViewThatFits`. A truncated label ("Downl…") is a failure, not a
compromise.

---

## §7 Color & materials (binding)

7.1 **Brand vs semantic split is absolute.** Chrome/CTAs use
`Brand.primary` / `Brand.accent`; any per-category semantic accents
carry *content meaning only*. Never a brand color for meaning, never a
semantic color for chrome.

7.2 **[Appearance stance.]** If the app pins `preferredColorScheme`,
say so and why. **Watch the dark-mode accent trap: a global
`AccentColor` under forced dark mode draws bordered buttons/links
dark-on-dark.** Ship a dark-appearance accent variant
(`ios-production-gotchas`). Prefer system semantic styles over
hand-rolled grays.

7.3 **Accent tiles use the gradient-to-black pattern** with legible text,
the one decorative device for navigation chips. Content tiles get no
decoration; the content is the design.

---

## §8 Player *(optional module; delete if no media)*

<!-- KEEP only if the app plays audio/video. These are iOS platform
     facts, not app-specific ones. -->

8.1 **`AVPlayerViewController` owns transport; assets ALWAYS come from a
resilient loader,** never `AVPlayerItem(url:)` for remote media. Retain
the loader on the Coordinator, enable PiP (`resilient-media-streaming`).

8.2 **Activate the audio session before playing.** iOS requires
`AVAudioSession` category `.playback` set + activated before `play()`,
or AVPlayer stalls / plays silently behind the ringer switch (the
documented iOS-vs-tvOS gap). Every entry point goes through ONE player
surface that does this.

8.3 **One queue family.** Continuous play is ONE shared engine behind a
`PlaybackQueue` protocol; advancing swaps items on the SAME `AVPlayer`
(`replaceCurrentItem`), never re-presents.

8.4 **Resume is per-item, persisted every ~10 s and on dismantle.**
Ephemeral/live playback must NOT persist resume state.

---

## §9 State, persistence & sync (binding)

9.1 **One data read path.** Views call the store's pass-throughs;
nothing touches the DB, SQLite, or URLSession directly. If the app
swaps a bundled seed → cached → downloaded dataset, each swap bumps a
`dataVersion`, and any view that caches query results re-queries via
`.task(id: store.dataVersion)`.

9.2 **Filters are baked into the data layer once** (visibility gates,
hidden categories) at load/change time. Never re-filter per-view.

9.3 **SwiftData models are shared with the other Apple platforms
verbatim,** in the App Group container, `cloudKitDatabase: .none` with
MANUAL sync, on the same CloudKit container, so devices sync with each
other. Sign-in is optional and gates ONLY sync; never call CloudKit on
a signed-out install (`per-ecosystem-sync-islands`).

9.4 **Every synced mutation goes through the sync nudge.** Insert/update
→ save + nudge (debounced push/pull). Delete → record a **tombstone**
instead of a bare `ctx.delete`, because a bare delete resurrects on the next
pull.

9.5 **UserDefaults keys are shared with the other platforms by name** so
a preference means the same thing everywhere, never a platform-suffixed
twin.

9.6 **No new state without a home** (tvOS-DESIGN §1.7).

---

## §10 Out of scope on iPhone/iPad (intentional)

<!-- FILL: the idioms that do not port to the phone, with the "revisit
     when" note (10-foot/lean-back idioms, a second sync island, custom
     transport chrome). -->

---

## §11 Anti-patterns (never)

11.1 An extra content tab, or Settings as a tab (§2.1). 11.2 A per-view
`navigationDestination` for a shared route (§2.3). 11.3 `NavigationLink`
to a shared screen instead of `router.push` (§2.4). 11.4
`fullScreenCover` for anything but the one immersive surface, or
`fullScreenCover(isPresented:)` around data-dependent content (§4.4).
11.5 `AVPlayerItem(url:)` for remote media, or playback without the
audio-session activation (§8.1–8.2). 11.6 A second queue engine (§8.3).
11.7 Resolving several home sections from one broad query (§5.2). 11.8 A
row under the floor (§5.4). 11.9 A bare `ctx.delete` on a synced model
(§9.4). 11.10 Direct DB/URLSession access from a view (§9.1). 11.11 A
brand color for meaning or a semantic accent for chrome (§7.1). 11.12
Custom font sizes outside navigation tiles (§6.1). 11.13 Porting a tvOS
focus rule into iOS files or this doc's inversions back into tvOS
(§4.1). 11.14 A grid/list/sheet without all four states (§4.2).

---

## §12 The tests (run before any surface ships)

12.1 **Competent-designer test:** rebuildable from one paragraph?
12.2 **Verb test:** what verb does this own? Colliding with a tab's
verb? Structural bug; resolve first.
12.3 **Depth test:** >2 pushes → scope/sheet/tab (§1.5).
12.4 **Parity discipline:** `PARITY.md` updated in the SAME change set;
the proposal quotes this doc's rule numbers. A feature that lands
differently from tvOS must be the *native idiom* of the same verb. Name
the tvOS rule it mirrors or deliberately inverts.
