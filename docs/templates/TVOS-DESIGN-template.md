# [APP NAME] tvOS Design (BINDING)

<!-- Seed for docs/tvOS-DESIGN.md (you create this). Create once the Apple TV app passes
     ~5 views. Invoke `binding-design-doc-discipline` for the workflow
     and `tvos-platform-patterns` for the mechanics (focus APIs, card
     sizes, image pipeline, animation values) this doc does NOT restate.

     HOW TO USE: the §N structure and the platform-truth rules baked in
     below are tvOS FACTS, true for any Apple TV app, not any one app.
     Keep them. Replace every [BRACKET] with your app's specifics and
     delete the <!-- FILL --> notes. Sections marked "(optional module)"
     only apply if your app has that kind of surface. Delete the whole
     module if it doesn't (e.g. §8 media/player, §9 takeover modes).
     Sibling templates (IOS/MACOS/WEB/ANDROID) share §1's shape; every
     other section diverges into the platform's native idioms. -->

**Binding.** Every new view, tab, row, sheet, overlay, or toolbar item
on the Apple TV app must trace to a rule in this document. When
something feels overwhelming or inconsistent, **fix this document
first, then fix the feature.** Proposals (and commits) cite the rule
they implement, e.g. "per tvOS-DESIGN §2.3."

Division of labor:
- **This doc** is the *binding contract*: information architecture,
  surface taxonomy, the design system, per-feature IA decisions.
- **`tvos-platform-patterns` skill** holds the *implementation
  recipes*: non-binding how-to; cite it for mechanics.
- **The sibling design docs** are the other platforms' contracts. Docs
  share verbs, never idioms (PARITY.md "same verb, native idiom").
  When a rule below deliberately inverts a sibling rule, it says so.
  Do not "harmonize" them.
- **`PARITY.md`** says what ships where, updated in the SAME change set.
- **`DECISIONS.md`** holds the why behind non-obvious rules.

---

## §1: Principles (the why)

1.1 **Ten-foot first.** The app is used from a couch with a remote, not
a pointer. Every surface must be legible and operable at distance;
nothing depends on precision aim or hover.

1.2 **Focus does the work.** The focused element IS the chrome.
Surrounding elements stay quiet. Density comes from removing chrome,
not adding decoration (`mobile-first-density-design`).

1.3 **One verb per top-level surface.** Each tab owns a distinct user
verb. Two surfaces competing for the same verb is a structural bug.
Resolve it before shipping (§12.2).

1.4 **Depth ≤ 2 from any tab root.** Tab → list/grid → detail. A
would-be third push must instead be a scope, a sheet/overlay, or a
different tab (§12.3).

1.5 **Back is sacred.** Never intercept the Menu/Back button outside a
player or a modal (App Store rejection risk). Every full-screen
takeover (§9) has a visible exit and honors Back.

1.6 **[Content-quality posture.]**
<!-- FILL: the app's non-negotiable stance on the quality/fidelity of
     what it presents (source quality, real vs placeholder content,
     accuracy). Delete if your app has no such stance. -->

1.7 **No new state without a home.** Any persisted user state maps to
the data model in §10 and, for synced state, the sync island
(`per-ecosystem-sync-islands`).

1.8 **Voice.** Section labels are plain and scannable; supporting copy
is evocative and short, never internal/pipeline language ("results",
"items", raw counts as the whole subtitle, "tap to…"). Copy lives in
shared config, not in Swift, so it can change without a build.

---

## §2: Information architecture

2.1 **Tab budget = [N], hard ceiling.** The sidebar
(`TabView(.sidebarAdaptable)`) holds [N]. A new surface earns a tab
ONLY if it owns a distinct top-level verb (§1.3) AND would be buried if
nested. Default to nesting. Adding one past the ceiling requires
removing or merging one first.

2.2 **The canonical tab set:** [list]. Settings is [a tab / behind a
gear]. Decide once and bind it.

2.3 **What nests, and where** (binding placement for the backlog):
<!-- FILL: the surfaces that are NOT tabs and where they live, e.g.
     detail-class destinations reached from a detail screen, a category
     as a facet rather than a tab, an action rather than a surface. -->

2.4 **The home surface is the front page, not a junk drawer.** It
composes a bounded set of sections. Each new home section declares a
removal/empty rule (`universal-feature-states`) and respects any
content-visibility gate the app has.

2.5 **Every list/grid/row/sheet declares all states.** loading · loaded
· empty · error, each user-visible. **Empty states must contain a
focusable element**, or focus gets trapped (the classic tvOS
empty-state bug).

---

## §3: Surface taxonomy (the only allowed shapes)

Every UI maps to exactly one. A new shape needs a new rule here first.

3.1 **Tab**: a top-level verb. Sidebar entry + `NavigationStack`.
3.2 **Row**: a horizontal, lazy collection; focus reveals its title.
3.3 **Grid**: paged/lazy browse with facets.
3.4 **Detail**: a focused item view: primary content + metadata +
actions + related. The primary action is auto-focused on appear.
3.5 **Sheet / overlay**: transient, dismissible, focus-restoring.
Never a nav push (§1.4).
3.6 **Takeover** *(optional module, §9)*: a full-screen mode that
replaces the shell while active, with a visible exit + Back.
3.7 **Player** *(optional module, §8)*: media playback.

---

## §4: Typography (binding; mechanics in the skill)

4.1 **Six levels, period.** Three weights × two sizes on the tvOS ramp
(76/57/38/29/23). Body floor **29pt**; never below 23pt (ten-foot
legibility). A seventh level is refused; refactor instead (AGENTS.md density
rule). Use tokens, never hardcode.

4.2 **No long body text on transient surfaces** (hero, row, banner).
Long text lives on Detail and in overlays only.

---

## §5: Color & materials (binding)

5.1 **Brand vs semantic split is absolute.** Brand chrome ([primary],
[accent]) is for CTA/chrome. Any per-category semantic accents carry
*content meaning only*. Never a brand color for meaning, never a
semantic color for chrome.

5.2 **Dark-first.** Reserve brightness for the focused element. Liquid
Glass (`.glassEffect`, tvOS 26) is the material: glass on key
interactive surfaces only, never on everything
(`swiftui-liquid-glass`). No `.ultraThinMaterial` holdouts.

---

## §6: Focus contract (binding; APIs in the skill)

6.1 The unbreakable rules hold everywhere: dark-first / 29pt floor /
90×60 safe area · Back sacred · full reachability · **never
`.buttonStyle(.plain)`** (it destroys focusability; use `.borderless`
or a custom `ButtonStyle`) · preserve focus by stable id, not index.

6.2 Initial-focus surfaces (first landing, a takeover's entry, a
player) claim focus **imperatively on appear**, because default focus alone
is unreliable on tvOS. Every new overlay/takeover declares its default
focus and its focus-restoration target on dismiss.

6.3 A stack of same-position focusables can trap focus. Give lazy rows
stable identity and let focus move by content, not index.

6.4 A held Select is a card's second verb. Select does the one primary
thing; holding it (a `.contextMenu`) offers the card's one secondary
action, such as [Remove from History]. Android TV spells the same verb
as a long press and Roku as `*`, so the verb matches on every TV while
the idiom stays native. A destructive second verb asks first with
Cancel focused. When the question closes, focus goes back on purpose:
the same card on Cancel, its neighbor on Remove. Left to the engine,
focus falls to the sidebar.

---

## §7: Images & artwork (binding)

7.1 **Decode to displayed size via a shared image loader, never raw
`AsyncImage` in grids/rows.** Bare AsyncImage re-decodes/re-downloads
on every focus reveal and bursts connections (remote hosts throttle).

7.2 **Prefer real, designed art; fall back gracefully.** Where an item
has no image, [generate one / show a typographic card] before a generic
placeholder. Any image, title, and description shown together must
agree.

---

## §8: Player surfaces *(optional module; delete if no media)*

<!-- KEEP this section only if the app plays audio/video. The rules are
     genuinely tvOS-specific, not app-specific. -->

8.1 **The native player owns transport.** Add only overlays/sheets,
never a parallel transport. Remote media flows through a resilient
loader (`resilient-media-streaming`), never a raw URL asset.

8.2 **In-player settings are one sheet (§3.5), not nav.** Surface a
control only when it has ≥2 real options (honest affordances).

8.3 **Sharing.** tvOS has no share sheet → hand off via QR + deep link
(`[scheme]://…`) and a canonical URL; AirPlay is native.

8.4 Suppress a media asset's bogus embedded metadata and publish Now
Playing info explicitly (`commonIdentifier…`).

---

## §9: Takeover modes *(optional module; delete if none)*

<!-- KEEP only if the app has full-screen "modes" that replace the
     navigation shell (an ambient/continuous experience, a scoped
     simplified shell, an idle screensaver). -->

9.0 **Definition.** A takeover replaces the navigation shell with a
full-screen experience. Every one: (a) has a visible exit + honors Back
(§1.5); (b) declares default focus (§6.2); (c) offers at least one way
back to normal navigation.

9.1 **One shared engine.** If several takeovers share behavior
(queueing, auto-advance, transitions), they use ONE service, never a
second parallel engine ("fix the document, then the feature").

---

## §10: Personalization & data (binding)

10.1 **One place for saved state.** Favorites/history/preferences live
in one home (one tab with sections, not three tabs) mapped to the data
model.

10.2 **Account & sync.** Sign in with Apple for identity + CloudKit
private DB for cross-device sync; no external auth. Sign-in is optional
and gates ONLY sync; browsing works signed-out
(`per-ecosystem-sync-islands`).

10.3 **Hiding ≠ deleting.** If the app hides consumed/completed items
from the home surface, they remain reachable elsewhere and can be shown
via a setting.

---

## §11: Anti-patterns (never)

11.1 A new tab to avoid nesting (§2.1). 11.2 A third nav push (§1.4).
11.3 `.buttonStyle(.plain)` (kills focus, §6.1). 11.4 A parallel
transport or second shared engine (§8.1, §9.1). 11.5 A control shown
with only one real option (§8.2). 11.6 A takeover/overlay with no exit
or no default focus (§9.0). 11.7 A seventh type level (§4.1). 11.8 An
empty state with no focusable element (§2.5). 11.9 Raw `AsyncImage` in
a grid/row (§7.1).

---

## §12: The three tests (run before any surface ships)

12.1 **Competent-designer test.** Could a peer rebuild this screen
from a one-paragraph description? If no, you added decoration; strip.
12.2 **Verb test.** What verb does this own? Colliding with a sibling?
Structural bug; resolve first.
12.3 **Depth test.** Count pushes from the tab root. >2 →
scope/sheet/tab, not another push.

---

## §13: Out of scope (intentional gaps)

<!-- FILL: the tvOS directions deliberately declined, each with a
     "revisit when", so they aren't re-proposed. -->

---

## §14: Per-feature IA decision table (the backlog, bound)

| # | Feature | Surface (§3) | Placement | Key rule |
|---|---|---|---|---|
| 1 | [feature] | [Tab/Detail/Sheet/…] | [where] | [§ref] |

<!-- One row per backlog feature: the shape it takes, where it lives,
     and the rule that binds it. A new feature adds a row before code. -->
