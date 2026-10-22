---
name: cross-platform-parity-discipline
description: "Use when shipping ANY user-facing feature in a multi-platform repo, when asked to check parity or audit features, or before a launch wave on any platform. Carries the PARITY.md workflow (same verb / native idiom, same-change-set updates, deliberate-defer cells with reasons, capability tiers not effort tiers), the periodic parity AUDIT that catches missing rows and silently-false cells, mechanical parity guards (extract constants/ORDER BY/refusal sentences from each platform and diff, with a negative control), port ledgers at three levels, the PARITY.md maintenance protocol, and doc-layer parity. Triggers on PARITY.md, feature parity, parity matrix, ship on all platforms, does Android have, parity audit, parity test, parity guard, port ledger, platform port audit, cross-platform feature, launch readiness, degenerate state, capability tier."
---

# Cross-Platform Parity Discipline

The single source of truth for "what ships where" is `PARITY.md`.
This skill is the workflow that keeps it true. It was battle-tested
shipping one app on five platforms (tvOS, iOS/iPadOS, macOS, web,
Android) through simultaneous store submissions — every rule below
earns its place from a real drift incident.

## The rule

**Same verb, native idiom.** The feature (the verb: search, save,
share, browse) is identical across platforms. The expression is
whatever is native — `.searchable` on iOS, `SearchBar` on Android,
`<input type=search>` + URL params on web, the focus-driven keyboard
on tvOS, `NavigationSplitView` + AppKit on macOS (e.g. player
metadata rides the window title bar, since macOS has no
`externalMetadata`). Never let one platform own a different verb for
the same surface; never port one platform's layout to another.

The three Apple platforms (iOS/iPadOS, macOS, tvOS) share one Swift
Core, so keep their columns grouped/adjacent in the matrix. A
shared-Core change usually moves ALL THREE Apple cells at once — but
"moves" is not "verified": re-build each of the three and confirm the
feature on each idiom before flipping the cells to ✅.

## When you ship a feature

In the SAME change set (not a follow-up):

1. **Find or add the row** in PARITY.md under the right verb section.
2. **Update every platform's cell** — including the ones you didn't
   touch. A platform you can't reach right now gets ⏳ plus a Notes
   reason, never a blank. Blanks are drift.
3. **Mirror where feasible.** If the change is small on the other
   platforms, ship them together. If not, the ⏳ note says why and
   what wave it lands in.
4. **Cross-link the binding design doc section** that governs the
   feature on each platform that has one.
5. **Don't wait to be asked.** "Ship on one and see" is how a matrix
   rots.

## Cell honesty rules

- ✅ means *live and verified on that platform* — not "code merged."
  If you haven't seen it work (sim screenshot, emulator run, browser
  check), it's 🚧.
- A **deliberate defer is a healthy cell**: "⏳ Google Cast — needs
  Cast SDK + device-tested receiver, deferred to player wave" is
  good engineering. The reason in Notes is mandatory; it's what lets
  a future session pick the work up without re-deriving the blocker.
- **Owner-blocked is its own state**: when a cell waits on something
  only the human can do (an OAuth client, a store setting, a domain),
  say "OWNER:" in the note. Don't let owner-blocked items
  masquerade as engineering backlog.
- **n/a and 🚫 carry reasons.** "n/a — TV apps suspend in
  background" teaches; a bare n/a invites re-litigating.
- Platform-exclusive features go in the per-platform affordance
  sections (§9–§12), with the cross-platform equivalent named:
  "Top Shelf (tvOS) ↔ WidgetKit (iOS) ↔ Glance widgets (Android) ↔
  PWA shortcuts (web)."

## Capability tiers, not effort tiers

What a platform offers is decided by what its hardware and OS CAN do,
never by how much of the port has been written. Legacy or weak devices
never set the ceiling: gate the affordance, keep the implementation
whole.

- **Gate on a hardware predicate, not a form factor.** "Host can be in
  the show" = camera AND microphone present (`FEATURE_CAMERA_ANY` +
  mic), not `isTelevision()`. A TV that has a camera passes; a
  cameraless tablet fails. Apply the predicate at EVERY entry point in
  the same change (phone overflow row and TV button are one decision;
  fixing one is how the defect survives in the other).
- **Never have vs currently lack.** A capability the device can NEVER
  have is omitted outright, with the reason in PARITY.md (a permanent
  apology on screen is clutter). One it COULD have and currently lacks
  (unconfigured sign-in, camera not yet permitted) stays visible with
  one sentence saying why and what unlocks it. Never a silently
  missing button.
- **Publish a capability definition table** in PARITY.md when one
  feature name covers several modes: rows = platforms, columns = the
  named modes (and separate HOST vs JOIN columns when those differ),
  each cell ✅/🚫 with the OS or hardware reason. It is the canonical
  answer to "what does X mean on this device"; the rows below carry
  the engineering detail.

Source: Archive Watch Decisions 131/132 (Watch Together's three named
modes; Android TV and Fire TV entries removed because no camera or
mic, while tvOS keeps it by borrowing an iPhone via Continuity Camera).

## The parity audit (run before launch waves + once per milestone)

Day-to-day updates miss two failure classes that only an audit
catches. Real audits on a shipped 4-platform app found **5 missing
rows and 4 false cells** in a matrix that was being maintained
conscientiously.

**Protocol:**

1. **Inventory sweep**: walk each platform's actual surfaces (tab by
   tab, screen by screen — from the code, not from memory) and list
   every user-facing capability. Diff that list against the matrix.
   Missing rows get added. Typical finds: share buttons, media/lock-
   screen controls, result filters, tappable metadata (cast → person
   browse) — small verbs nobody recorded.
2. **Cell verification**: for every ✅, ask "have we observed this
   working on this platform, recently?" Suspicious cells get tested,
   not trusted. The canonical false cell: a "(synced)" claim where
   the sync payload never actually carried that record type — code
   existed, data never flowed.
3. **Degenerate-outcome pass**: for the marquee features, drive each
   to its tie / zero / empty / cold-quit outcome, not just the happy
   path — a game that ends in a tie, a list with zero results, a
   session killed mid-flow and relaunched. Happy-path audits miss
   whole bug classes; a real pass found the tie screen, the
   empty-history dashboard, and the resume-after-force-quit path all
   broken on platforms whose happy paths were ✅.
4. **Stale-blocker check — in BOTH directions**: for every ⏳/🚫, is
   the recorded reason still true? Blockers expire (an API ships, a
   domain gets bought, a measurement gets re-run and contradicts the
   old one). And **audit the claim against the code before building
   the "missing" feature** — a documented-backlog sweep found four ⏳
   items that were wrong docs: the features already existed and the
   matrix was stale in the pessimistic direction. Building from a
   false ⏳ duplicates shipped work.
5. **Fix in the same pass**: small gaps (a missing toggle, a missing
   row) get closed during the audit; large ones get ⏳ cells with
   reasons and land in the milestone queue ordered by size.

## Auditing a whole-platform port

When one platform is a PORT of another (a new desktop twin, a TV form
factor), organize the audit doc **by failure class, not surface by
surface**: missing entirely · present-but-wrong (logic diverges from the
source platform) · present-but-unwired (renders, does nothing) ·
degenerate-state-only bugs. Surface-by-surface walks re-find the same
class N times and miss the classes that cut across surfaces; a
failure-class organization turns each class into one fix applied
everywhere. Give the port its own per-item tracker doc
(`docs/<PLATFORM>-PARITY.md`) mirroring the main matrix's rows.

### Port ledgers at three levels

A screen matrix alone lies. Archive Watch's Roku feature ledger
reported 74 ✅ rows and "feature parity"; the owner used the build the
next day and returned 20 defects (non-functional More Like This, a
Channels view that was not an EPG, filters that cycled instead of
picked). The ✅ rows counted surfaces that EXISTED, not surfaces
FINISHED to the reference platform's standard. Likewise an Android TV
"12/12 D-pad-verified" claim measured reachability, not parity.
Reachable is not parity.

Keep three levels, seeded from `docs/templates/PORT-PARITY-LEDGER-template.md`:

1. **Screen matrix** (`<PLATFORM>-PARITY.md`): does each surface exist
   and is it reachable. Necessary, never sufficient.
2. **Feature ledger** (`<PLATFORM>-FEATURE-PARITY.md`): the reference
   platform's buttons and behaviours INSIDE each screen, enumerated
   from its SOURCE files (grep the views), not from memory. A surface
   that exists and does nothing is worse than a missing one: it
   promises.
3. **Owner feedback ledger** (`<PLATFORM>-FEEDBACK-LEDGER.md`): each
   item from a human using the build, numbered, in their words, binding
   until its row reads ✅ with on-device evidence. It supersedes any
   earlier self-assessment; keep the superseded tally in the doc as a
   record of the mistake.

Tag every cell with its verification tier: **T1 device** (screenshot,
log, focus tree on real hardware) · **T2 code** (wiring read end to
end) · **T3 owner** (feel, visual judgment). Only T1 or T3 flips a cell
to ✅. Where possible the app self-reports what it rendered (a log line
listing the shelves it drew), so a T1 check reads evidence instead of
eyeballing. Record deliberate platform differences as n/a WITH the
reason, in both directions.

## Working the gap queue

When closing parity gaps in bulk (a "parity wave"):

- **Order by shared-logic leverage**: a feature whose logic already
  lives in shared code (a deterministic scheduler, a query verb, a
  flag baked into the data plane) ports cheapest — do those first.
- **Port the logic, rebuild the layout.** A deterministic core
  (same constants, same seeds, same query) gives identical behavior
  across platforms; the layout around it is rebuilt in each
  platform's idiom. Never screenshot-match layouts across platforms.
- **Re-verify the platforms you didn't touch.** Shared-file changes
  must re-build every consumer (the tvOS build going green after an
  iOS-motivated Core change is part of done).
- Update PARITY.md per change set within the wave, not once at the
  end — a wave that dies mid-way must leave a true matrix.

## The dead-API audit: a declaration nothing calls is an unshipped feature

A parity matrix is built from what each platform's UI *offers*. It cannot see
a capability that exists in shared code and is **wired on zero platforms** —
every cell looks consistent, because they are all consistently wrong.

Found in production: a `beginStallSuspension` on a shared SharePlay service,
public, documented, and **called by nothing on any platform**. Every player
received a playback coordinator and none of them ever suspended it, so a
buffering participant silently drifted out of sync instead of the group
waiting. The matrix had no row for it; the code review had nothing to catch,
because the method was correct.

Run this whenever you audit a shared layer:

```bash
# every public/internal method on the shared service, minus its own definition
grep -rn --include="*.swift" "func " Shared/Services/Thing.swift |
  sed -E 's/.*func ([a-zA-Z0-9_]+).*/\1/' |
  while read f; do
    n=$(grep -rn --include="*.swift" "\.$f(" . | grep -vc "Services/Thing.swift")
    [ "$n" -eq 0 ] && echo "NEVER CALLED: $f"
  done
```

Two rules follow:

- **Prefer driving cross-cutting behaviour from the shared entry point** rather
  than exposing it for each platform to remember. The stall suspension moved
  into the shared `attach(player:)`; three platforms then cannot diverge on it
  again, and there is no per-platform call site to forget.
- **A capability with no row is a capability with no owner.** If shared code
  can do something a user would notice, it earns a matrix row even when the
  answer is identical everywhere — that row is what makes "wired nowhere"
  visible.

## Mechanical parity guards

When one rule is implemented in several languages (a hero-eligibility
bar, a search ORDER BY, a room-code alphabet, a refusal sentence),
reading diffs will not catch drift: each copy is correct where it
lives. A test that reads the SHIPPED source of every platform and
diffs the rule will.

- **Regex-extract, don't re-implement.** Pull the constant set, the
  year, the `ORDER BY` clause, or the user-facing sentence out of the
  real Swift, Kotlin, JS and pipeline files, and assert they are equal
  (sentences character for character). Where possible also EXECUTE the
  extracted rule against a small fixture (the ORDER BY against an
  in-memory FTS table) with cases the rule exists for.
- **One run asks every surface the same gate question.** For a flow
  with several entry points (every "go live" / "purchase" / "share"
  surface), grep each surface for each gate its siblings have. Archive
  Watch had one gate-added-on-one-platform-only defect recur four
  times, each found by eye, late, before
  `test_studio_surface_parity.sh` existed. It is a source check: it
  proves no surface lacks a gate its siblings have, not that the screen
  behaves.
- **Check the pipeline against the clients too.** Every value the
  producer can emit must have a client sentence, or it falls to a
  default that leaks an internal name to a user.
- **Web: every `API.x` the JS calls must be exported.** Plain JS has no
  compiler; a call to a non-existent `API.summary` shipped from
  v1.42.469 to v1.42.584 and left every browser guest with no player. Parse the
  export block of `js/api.js`, grep callers for `API\.(\w+)`, diff.
- **Every guard has a negative control.** Mutate one side (add a bucket
  to one set, run the old `ORDER BY rank`) and assert the guard FAILS.
  A guard that cannot fail is decoration; one Archive Watch text-wrap
  test passed with the defect reinstated and was thrown away.
- **Cite the guard in the PARITY row's Notes** (`test_hero_rule_parity.py`)
  so the next editor knows the rule is enforced and where.
- Run the guards in CI on every push; they cost milliseconds.

Why it matters: Archive Watch's web and Roku copied only half of the
hero rights bar (the year, not the buckets) and admitted 46% and 67%
more titles than the apps until a guard compared all four copies.

Prefer removing the copies (compute once in the pipeline, publish the
result: `cross-platform-determinism` Rule 0) over guarding them. Guard
what must stay mirrored.

## PARITY.md maintenance protocol

A matrix that grows into a journal stops being readable, then stops
being true. Archive Watch's PARITY.md reached 830 lines with single
rows over 13,000 characters.

- **Cap a cell at one sentence plus a link.** Evidence goes in the cell
  ("✅ verified iPhone 12, 2026-09-20"), the story goes in the ledger,
  design doc or DECISIONS entry the cell links to.
- **One summary row per ledgered port.** Once a platform has its own
  ledger, PARITY holds one line pointing at it; do not keep a second
  per-surface copy (it drifts false the moment the ledger moves on).
- **n/a is not 🚫.** n/a = the verb does not apply to this platform
  (lock-screen controls on tvOS). 🚫 = could apply, deliberately not
  built, with the reason.
- **Name the parity test in Notes** for any row a guard enforces.
- **Carry an "Oldest hardware served" row** (the floor per platform
  and the device it reaches) and a **capability definition table** for
  any multi-mode feature (see Capability tiers).
- **Per-section verification-gate tables** are fine where a section's
  cells share a gate (device run, owner review).
- **Scripts read columns by HEADER name, never by index.**
  `line.split("|")` returns a LEADING EMPTY element, so `parts[4]` is
  not the fourth platform. Archive Watch silently overwrote the macOS
  column four times this way; the table still rendered and the wrong
  cell read as fact. Build the index from the header row
  (`cols = [c.strip() for c in header.strip().strip("|").split("|")]`).

## Doc-layer parity

A cross-platform rule lives in EVERY platform design doc, not only the
one where it was first written. When the owner says "yes, all
platforms", stamp the rule into each DESIGN doc the SAME day, each copy
citing the origin rule number and the owner's dated words (Archive
Watch's "New to Archive Watch" shelf landed in all seven platform
design docs on 2026-09-25, each quoting "Yes, all platforms"). A doc that lacks the
rule will be "harmonized" by a future session.

Features that cut across every platform (captions, SharePlay/watch
party, link sharing, analytics) get a feature-scoped binding doc beside
the platform docs, seeded from `docs/templates/FEATURE-DESIGN-template.md`:
an OS × platform capability matrix that an audit script re-derives
from the real data, and a new-platform checklist. See
`binding-design-doc-discipline`.

## Verbs that deserve a row people forget

Share (and what a share URL opens on each platform) · lock-screen /
media-key controls · search-result filters · tappable secondary
metadata · account deletion (a store-review requirement, not a
feature) · error/empty/offline states for marquee surfaces ·
settings toggles that gate behavior shipped elsewhere · deep-link
routes (every emitted URL shape must be openable everywhere it
lands — including the manifest/intent-filter on Android).
