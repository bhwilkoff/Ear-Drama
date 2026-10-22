# [APP NAME]: Non-Apple TV Design (BINDING)

> **Template.** Copy to `docs/TV-DESIGN.md` (you create this) when the app
> adds Android TV / Fire TV or a web-TV build. Replace every `[FILL IN]`.
> The focus contract, the layout floors, the player rules and the
> per-platform mechanics are the load-bearing lessons from shipping
> Archive Watch to Android TV, Fire TV, webOS and Tizen. Keep them unless a
> decision in `DECISIONS.md` says otherwise.

**Binding.** Every view, row, overlay, key handler, or focus behavior in the
**Android TV / Google TV / Fire TV** build and the **web-TV (webOS, Tizen,
VIDAA, aggregator)** build must trace to a rule here. When something feels
wrong, **fix this document first, then fix the feature.** Commits cite the rule,
e.g. "per TV-DESIGN §3.2."

Division of labor:
- **This doc** is the binding contract for the two *non-Apple* 10-foot builds.
- **`docs/tvOS-DESIGN.md`** (you create this from
  `docs/templates/TVOS-DESIGN-template.md`) is the binding contract for Apple
  TV. **This doc inherits its information architecture wholesale** (§2 below).
  [APP NAME] is one product, and the IA is not re-litigated per platform.
- **`docs/TVOS-PLAYBOOK.md`** holds Apple-specific mechanics. Its *principles*
  (ten-foot type, focus does the work, dark-first) transfer; its *APIs* do not.
- **`docs/TV-PLATFORMS.md`** covers platform viability, fees, and the store
  process; `docs/store/tizen-submission.md` and `docs/store/webos-submission.md`
  carry the submission steps.
- **`docs/TV-PLATFORM-BACKLOG.md`** (you create this from
  `docs/templates/TV-PLATFORM-BACKLOG-template.md`) is the ordered work list.
- **`DECISIONS.md` 028** records why smart TVs are two builds, not six apps.

---

## §1. Principles (the why)

**1.1 One product, many remotes.** A TV build is not a port of the phone app and
not a reskin of the Apple TV app. It is the same product expressed in the native
idiom of its platform: Material focus on Android TV, DOM focus on web-TV. The
*verb* is identical (PARITY.md rule); the *idiom* is local.

**1.2 Focus does the work.** Inherited from tvOS-DESIGN. The focused element
is the chrome; everything around it stays quiet. Density comes from removing
chrome, not adding decoration. On a 10-foot screen this is not taste. An
unfocusable or ambiguously focused element is *unusable*, and it fails Google's
TV-DP and LG's and Samsung's function tests outright.

**1.3 D-pad reachability is agency, not a checkbox.** AGENTS.md's "Why we build"
asks whether a design invites the user to engage more fully. On a TV, the remote
*is* the entire vocabulary of engagement. Any function reachable only by pointer,
gesture, or text entry is a function that platform's users do not have. This is
the learning-orientation gate expressed as an engineering rule.

**1.4 No opaque "for you" feed.** Every TV platform offers a home-screen
recommendation surface (Google TV channels, Roku Continue Watching, Fire TV
integration). We may publish to them, but **what we publish is our own editorial
shelves and the user's own Continue Watching**, never a model's opinion the user
cannot inspect. Expose the structure of the catalog ([FILL IN: categories,
decades, collections, community signals]) so a viewer learns how it is
organized. A black-box row teaches nothing. *(Learning-orientation guardrail 1;
see `values-based-feed-ranking`.)*

**1.5 No lean-back-only degraded build.** It is tempting to ship TV as "hero +
autoplay + nothing else." [FILL IN: the participatory surfaces, e.g. Browse,
Search, Favorites, Playlists] are what make the catalog explorable rather than
consumable. A TV build that drops the participatory surfaces is a *smaller
product*, not a simpler one. Deferrals are allowed and must be recorded as
deliberate-defer cells in PARITY.md with a reason. *(Learning-orientation
guardrail 2.)*

**1.6 Lean-back, then lean-in.** Inherited from tvOS-DESIGN. Every surface
must work as pure browse but should offer one door to curiosity: a synopsis, a
connection, a "part of this collection" link. *(Learning-orientation
guardrail 3.)*

**1.7 Back is sacred.** Back never gets swallowed. On Android TV, Back from the
root returns to the launcher (TV-DB). On webOS, Back is keyCode **461**; on
Tizen it is the `tizenhwkey` event (and, on some firmware, a keydown 10009 for
the SAME press: handle it once). Both must navigate back. At the root, webOS and
Android TV exit; Samsung's Terminating Applications policy requires the app to
ask first ("Exit <app>?" with Exit and Stay, drawn by the app, `tv.js`
`askToExit`). Intercepting Back is a certification failure on all three.

**1.8 Faithful presentation.** [FILL IN: the media format and why it plays
natively everywhere.] In Archive Watch, progressive H.264 MP4 over HTTPS played
natively on every one of these platforms, with no DRM, no transcode and no
bitrate ceiling. Prefer a format every platform player already speaks.

---

## §2. Information architecture (inherited, not re-derived)

The top-level surfaces are **exactly** those of `docs/tvOS-DESIGN.md` §2:
[FILL IN: e.g. Home, Browse, Search, Library, Settings]. Adding, removing, or
renaming a top-level surface on a TV build is a change to tvOS-DESIGN, not a
local decision.

**Depth of 2 or less from any root** binds here too and binds *harder*:
a third push on a D-pad is a maze. Tab, then row or grid, then detail. A
would-be third level becomes a scope, an overlay, or a different root.

**Per-platform launch scope.** A platform may ship a subset, in this order, and
must record the rest as deliberate-defer in PARITY.md:

| Wave | Surfaces | Rationale |
|---|---|---|
| **v1 (required to ship)** | [FILL IN: e.g. Home, Browse, Search, Detail, Player, Library, Settings] | The spine. Below this it is not [APP NAME]. |
| **v1.1** | [FILL IN] | The participatory surfaces (§1.5). Defer only for a launch date, never permanently. |
| **v2** | [FILL IN] + platform home-screen integration | Depth. |

**Never on a TV build:** [FILL IN: any creation or editing surface that needs
text entry or direct manipulation. A remote has neither.]

---

## §3. The focus contract (binding)

This is the section that separates a TV app from a resized app. It binds both
builds; §6 and §7 give the per-platform mechanics.

**3.1 Something is always focused.** There is no state in which the user presses
a direction key and nothing is highlighted. On view entry, focus is claimed
imperatively, never left to a default. (This is the same lesson as the Apple
build's initial-focus rule; it is universal to focus engines.)

**3.2 Focus is visible from ten feet.** The focused item is distinguished by
**at least two** of: scale (1.06 to 1.10x), a border or ring, and an elevation
or shadow lift. Color alone is never sufficient. It fails for color-blind
viewers and washes out on a bright living-room panel. The unfocused state
carries no competing decoration.

**3.3 Focus never leaves the screen.** Focusing an item scrolls it into view with
its row header and neighbors visible. A focused element under an overscan margin
or behind a sticky header is a bug.

**3.4 No focus traps and no dead ends.** From every focusable element there is a
path back to the root by pressing Back and a path to a neighbor in at least one
direction. Rows wrap or stop deliberately; they never strand.

**3.5 Directional intent is preserved.** Up/Down moves between rows, Left/Right
within a row. A grid moves in both axes. Never remap an axis for cleverness. The
mental model is a physical grid.

**3.6 Text entry is the last resort.** On-screen keyboards are slow. Search must
be reachable and usable, but every *browse* path must be complete without typing.
[FILL IN: the browse rows that let a viewer find something without a keyboard.]

---

## §4. Layout, type, and color (binding)

**4.1 Canvas.** 1920x1080 is the design baseline for both builds. Android TV
scales by density; web-TV uses a fixed 1920x1080 viewport with CSS scaling.

**4.2 Overscan-safe margins.** **5% inset on every edge** (96px horizontal, 54px
vertical at 1080p). Nothing meaningful (text, focus rings at rest, controls)
crosses that line. Full-bleed artwork may, and must be designed to be cropped.

**4.3 Type scale.** Six levels, per `mobile-first-density-design`: three weights
by two sizes. Minimum **body size 24px at 1080p** (the ten-foot floor); row
headers 32px; hero title 48 to 64px. A seventh level is refused. Refactor
instead.

**4.4 Dark-first.** The canvas is near-black. Living rooms are dark and a bright
UI is fatiguing at 10 feet. Light mode is not offered on TV.

**4.5 Color follows the shared system.** Brand chrome (`--color-primary`,
`--color-accent`) and any semantic accents are **exactly** those in AGENTS.md
and Decision 012. The split is binding: never a brand color for content
meaning, never a semantic color for chrome.

**4.6 Rows over grids at the root.** Home is horizontal rows (the 10-foot idiom).
Grids are for a *chosen* scope (a category, a filter, search results) where the
user has already narrowed and wants density.

---

## §5. Player surfaces (binding)

**5.1 The native transport is the transport.** Per `native-platform-first` and
Decision 022: never build a custom scrubber over a platform player. Android TV
uses the Media3 `PlayerView` TV controls; web-TV uses the platform `<video>`
element's controls plus our key handler.

**5.2 Key contract (both builds).** D-pad **center** toggles play/pause; **left/
right** seek (rewind/fast-forward); dedicated media keys (`KEYCODE_MEDIA_PLAY_PAUSE`
on Android; the registered Tizen and webOS media keys) toggle during playback.
Back exits the player to the previous surface, never to the launcher
mid-playback.

**5.3 Title and description overlay** appears and disappears **with** the
transport controls, per Decision 022. It is non-interactive and never blocks the
controls.

**5.4 Video pauses on switch-away; no background media controls.** Android's
TV-NP is explicit: a *video* app must not surface Now Playing or system media
controls and must pause when the user switches out. If the phone build runs a
`media3-session` `MediaSession`, it **must be gated off on TV.** This is a rule,
not a preference. It is a quality-review failure otherwise.

**5.5 Subtitles side-load, never burn in.** Captions ship as side-loaded tracks:
Media3 `SubtitleConfiguration` on Android TV, a `<track kind="subtitles">` on
web-TV. If captions exist they must be user-selectable, a rule on every
platform. Have the data pipeline emit WebVTT so client-side conversion is a
fallback, not the main path (see `docs/MEDIA-PLAYBACK.md`).

**On web-TV the track MUST be fetched into a same-origin blob.** A
cross-origin `<track>` fails silently. The usual fix (`crossorigin` on the
media element) is unavailable whenever the video host redirects to a node that
sends no CORS header, because `crossorigin` on `<video>` then breaks PLAYBACK.
This bites the PACKAGED apps hardest: a webOS `.ipk` or Tizen `.wgt` serves the
page from a local app origin, so a remote VTT is always cross-origin. On the
public web origin the VTT may be same-origin, which is exactly why the bug hides.
(Learned in Archive Watch.)

**5.6 Playback resilience is per-platform, and it is not optional.** Hosts you do
not control reset idle connections (`resilient-media-streaming`). Android TV
inherits the phone build's Media3 `LoadErrorHandlingPolicy`; web-TV inherits the
web viewer's nudge-reconnect. A platform whose player owns networking and cannot
be made resilient (Roku) must have that regression recorded before work starts.

---

## §6. Android TV mechanics (binding where marked)

**6.1 Dependency (binding).** `androidx.tv:tv-material` **only**. `tv-foundation`
and every `TvLazy*` composable were removed once their behavior merged into
`compose-foundation`. Use standard `LazyRow` / `LazyColumn` /
`LazyVerticalGrid`. Any code or tutorial using `TvLazy*` is stale.

**6.2 One app, two form factors (binding).** The TV build is the **same
`applicationId` and the same AAB** as the phone build, with
`android.software.leanback` and `android.hardware.touchscreen` both declared
`required="false"`. TV is a form factor of one Play listing, not a second app.
Never fork the app.

**6.3 Manifest contract (binding).** `LEANBACK_LAUNCHER` intent filter (TV-ML);
touchscreen and all TV-absent hardware `required="false"` (TV-MT); 320x180 banner
containing the app name, localized per supported language (TV-LB / TV-BN);
160x160 or larger xhdpi icon; landscape without letterboxing (TV-LO).

**6.4 Platform floors (binding).** `minSdk` 31 or lower (TV-PS). If the app
also targets Fire TV, `minSdk` must be **28 or lower** (Fire OS 7 is API 28);
the template's AGENTS.md default of 29 must drop. **64-bit plus 16 KB page-size
compliance across every bundled native library (TV-G6)**. Verify each native
dependency ([FILL IN: e.g. `sqlite-bundled`, Media3, Coil]); do not assume.
AAB is mandatory (TV-G1).

**6.5 Device branching, not device forking.** TV layouts are selected at runtime
by `UiModeManager` type (`UI_MODE_TYPE_TELEVISION`), not by a build flavor. The
data layer, repositories, player engine, and navigation routes are **shared
verbatim** with the phone build. Only the composables differ.

**6.6 Fire TV divergence.** Fire OS is the same build with **no GMS**. Keep the
dependency set GMS-free. The standing rule: **anything GMS-dependent (Cast first
and foremost) is excluded from the Fire variant.** Media3 (not the stale `amzn`
ExoPlayer port) is the player, validated on real Fire hardware.

---

## §7. Web-TV mechanics (binding where marked)

**7.1 Vanilla, no build step (binding).** Inherited from AGENTS.md and
`docs/WEB-DESIGN.md` (you create this from
`docs/templates/WEB-DESIGN-template.md`). The TV build is the **same** web app
plus a TV layer (`tv.js` / `tv.css`, per `smarttv-web-app`), not a fork, not a
framework rewrite. **Norigin Spatial Navigation and every other React-based
focus library are therefore out**; the focus engine is about 200 lines of our
own vanilla JS.

**7.2 The focus engine (binding shape).** A single module owning: a registry of
focusable elements, a spatial "nearest in direction" resolver over
`getBoundingClientRect()`, roving `tabindex`, `scrollIntoView` on focus change,
and one `keydown` listener. Views register and unregister their focusables when
the view system shows a view, the same lifecycle discipline that governs
IntersectionObservers.

**7.3 Per-platform shims only (binding).** The differences between webOS, Tizen
and VIDAA are **key codes, lifecycle events, and packaging**. Nothing else. Each
lives in a small adapter; no view code may branch on platform.

| Concern | webOS | Tizen |
|---|---|---|
| Back | `keydown` keyCode **461** | `tizenhwkey` event |
| Media keys | standard `keydown` | `tizen.tvinputdevice.registerKey()` first |
| Lifecycle | `webOSLaunch` / `webOSRelaunch` | `visibilitychange` |
| Pointer | Magic Remote cursor, which **must coexist** with D-pad focus | none |
| Package | `.ipk` via `ares-package` | signed `.wgt` via `tizen package` |

**7.4 Magic Remote coexistence (binding).** LG's pointer mode is not optional to
support. Hovering moves focus; the D-pad continues to work from wherever the
pointer left focus. Two input models, one focus state.

**7.5 TV breakpoint, not TV fork.** The mobile-first CSS gains a TV media query.
Existing `min-width` discipline (AGENTS.md) is preserved. The TV layer is
additive.

**7.6 Service-worker discipline.** The TV build ships through the same versioned
service worker as the web app. Bump the shell version on every TV change, or TVs
serve a stale app for days (`web-platform-patterns`).

---

## §8. Anti-patterns (never)

- Shipping the phone/tablet layout with bigger fonts and calling it a TV app.
- A focusable element with no visible focus state, or a screen with no initial
  focus.
- Intercepting Back, or exiting to the launcher from mid-playback.
- A custom scrubber or custom transport over a platform player (§5.1).
- Background media controls or Now Playing on a TV video app (TV-NP, §5.4).
- `TvLazyRow` and friends (§6.1), which were removed from the platform.
- A React or framework dependency in the web-TV build (§7.1).
- Any browse path that requires typing (§3.6).
- An opaque "recommended for you" row (§1.4).
- Forking the Android app for TV, or forking the web app for TV.

---

## §9. The three tests (run before any TV surface ships)

1. **The remote test.** Unplug every input but the D-pad. Can you reach and
   operate *every* function of the surface, and get back out? (§1.3, §3.4)
2. **The ten-foot test.** Sit back, or shrink the screenshot to 25%. Can you
   tell what is focused, and read the primary text? (§3.2, §4.3)
3. **The parity test.** Is this verb already defined for another platform in
   PARITY.md? If yes, implement *that verb* in this idiom. If no, it needs an IA
   rule in tvOS-DESIGN §2 first. A TV build never invents a top-level surface.

---

## §10. Out of scope (deliberate, for the first TV wave)

- [FILL IN: creation surfaces that are permanently out (§2).]
- **Sign-in and cross-device sync.** No CloudKit off Apple; the Android-family
  path is Google Drive App Data sync (Decision 015,
  `per-ecosystem-sync-islands`). It may be deferred past the first TV wave. TV
  state is local until then.
- **Platform home-screen integration.** Google TV channels, Fire TV catalog
  integration, Roku Continue Watching. All are v2, all constrained by §1.4.
- **Roku.** A separate funded decision (see `docs/TV-PLATFORMS.md` and the
  `roku-brightscript-app` skill); no code here applies.
