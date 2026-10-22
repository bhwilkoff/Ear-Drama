# Binding platform design docs: the index and the shared shape

<!-- START HERE, then copy the per-platform template you need. -->

A binding design doc is the contract for ONE platform's UI: every new
view, tab, sheet, grid, route, or toolbar item must trace to a rule in
it. When something feels overwhelming or inconsistent, **fix the doc
first, then fix the feature.** Proposals and commits cite the rule they
implement (e.g. "per §2.3"). Invoke `binding-design-doc-discipline` for
the workflow.

Create a platform's doc once that platform passes **~5 views**. Before
that, the skills carry enough. Seed it from the matching per-platform
template in this folder, which preserves the structure AND the
hard-won, platform-specific rules (not just section headings):

| Platform | Seed template | Author as | Mechanics skill |
|---|---|---|---|
| Apple TV | `TVOS-DESIGN-template.md` | `docs/tvOS-DESIGN.md` | `tvos-platform-patterns` |
| iPhone / iPad | `IOS-DESIGN-template.md` | `docs/iOS-DESIGN.md` | `ios-production-gotchas` |
| iPad at regular width (extends iOS) | `IPAD-DESIGN-template.md` | `docs/IPAD-DESIGN.md` | `ios-production-gotchas` |
| macOS | `MACOS-DESIGN-template.md` | `docs/macOS-DESIGN.md` | `macos-platform-patterns` |
| Web viewer | `WEB-DESIGN-template.md` | `docs/WEB-DESIGN.md` | `web-platform-patterns` |
| Android | `ANDROID-DESIGN-template.md` | `docs/ANDROID-DESIGN.md` | `android-production-gotchas` |
| Smart TV (Google TV, Fire TV, LG, Samsung, Roku) | `TV-DESIGN-template.md` | `docs/TV-DESIGN.md` | `smart-tv-platform-expansion` |
| Windows | `WINDOWS-DESIGN-template.md` | `docs/WINDOWS-DESIGN.md` | `windows-production-gotchas` |

Data shared across clients gets `docs/DATA-CONTRACT.md` (seed:
`DATA-CONTRACT-template.md`, skill: `shared-data-plane-contract`). The
design docs consume it; they don't restate it.

A feature whose capability differs by OS version or hardware (captions,
a watch party, link sharing) gets a feature-scoped binding doc beside
these: seed `FEATURE-DESIGN-template.md`, author as `docs/<FEATURE>.md`.
A platform that is a port of another gets a three-level ledger: seed
`PORT-PARITY-LEDGER-template.md`, author as `docs/<PLATFORM>-PARITY.md`.
A rule the owner approves for all platforms is stamped into every doc
here the same day (`binding-design-doc-discipline`, doc-layer parity).

---

## The shared shape (why the templates rhyme)

Every per-platform doc follows the same skeleton. **§1 is nearly
identical across platforms** (the principles below); **everything after
§1 diverges into the platform's native idioms**. That divergence is
the point, not a defect to harmonize away.

- **§1 Principles (the why):** same verb, native idiom · the
  platform's defining interaction (focus / touch / pointer+keyboard /
  URL / Material) · one shared data plane · depth ≤ 2 from any root ·
  density from removal · voice/copy in shared config.
- **§2 Navigation shell:** the hard-set destination list, one adaptive
  shell across form factors, one destination registry, an inbox for
  external entry points (deep links / voice / widgets).
- **§3 Surface taxonomy:** the only allowed screen shapes; a new shape
  needs a new rule first.
- **§4 Idiom rules:** which native components are mandatory for which
  verbs, and the anti-patterns this platform rejects (each with the
  incident that earned it).
- **§5 State, persistence, sync:** local-first vs synced
  (`per-ecosystem-sync-islands`), resume semantics, settings storage.
- **Anti-patterns · the tests · out-of-scope table:** rejected
  directions live in the doc so they aren't re-proposed.

---

## The three cross-cutting laws (all platforms)

1. **Same verb, native idiom** (PARITY.md). The feature set matches
   across platforms; the expression is whatever that platform's users
   already know. When one doc's rule deliberately INVERTS a sibling's
   (e.g. `.buttonStyle(.plain)` is fatal on tvOS but correct on iOS),
   it says so. Never "harmonize" them.
2. **PARITY.md is updated in the SAME change set** as any user-facing
   feature (`cross-platform-parity-discipline`).
3. **Density from removal**, six type levels max, brand-vs-semantic
   color split is absolute (`mobile-first-density-design`).

Keep each doc APPEND-ONLY in spirit: amend a rule with a dated note and
a reason; never silently contradict it.
