# [APP NAME] [PLATFORM]: Port Parity Ledger

<!-- SEED TEMPLATE. Author as docs/[PLATFORM]-PARITY.md the day a
     platform becomes a port of another one (a Roku app rebuilt from
     the tvOS app, an Android TV form factor, a Windows twin). Read the
     `cross-platform-parity-discipline` skill first, section "Port
     ledgers at three levels". Replace every [BRACKET]; delete these
     comments as you go.

     The three levels can live in one file (three sections, as below)
     or three files ([PLATFORM]-PARITY.md, [PLATFORM]-FEATURE-PARITY.md,
     [PLATFORM]-FEEDBACK-LEDGER.md) once each grows past a screen.
     PARITY.md keeps ONE summary row pointing here (its §7d). -->

I want someone who switches from [REFERENCE PLATFORM] to [PLATFORM] to
find the same app: the same verbs, finished to the same standard, in
the idiom of the new device.

A screen that exists is not a screen that is finished.

Archive Watch learned this on Roku. Its feature ledger claimed 74
verified rows and "feature parity" on 2026-09-04. The owner used the
build and returned twenty defects the next day: a More Like This row
that did nothing, a Channels view that was not a guide, filters that
cycled instead of letting you pick. Every ✅ had counted a surface that
existed. So this ledger has three levels, and only the last one is the
truth.

The cost is real: three tables to keep, and a device in hand for every
✅. The alternative is a green matrix and a disappointed owner.

**Reference platform:** [e.g. tvOS]. Every row below is enumerated from
its source, not from memory.
**Port:** [PLATFORM]. **Reuse vehicle:** [e.g. same Android app,
branched at runtime on `UiModeManager` / 0% reuse, full rewrite].
**Binding design doc:** `docs/[PLATFORM]-DESIGN.md`.

---

## Verification tiers

Every Evidence cell carries one tier:

- **T1 device.** A screenshot, a log line or a focus-tree dump from
  real hardware.
- **T2 code.** The wiring was read end to end. Nothing ran.
- **T3 owner.** A person judged the feel or the look on the device.

Only T1 or T3 turns a cell ✅. T2 is 🔨 (built, not verified).

Where you can, make the app report what it rendered (a log line that
lists the shelves it drew, the item it opened), so a T1 check reads
evidence instead of squinting at a photo of a television.

Legend: ✅ built and verified (T1/T3) · 🔨 built, not verified (T2) ·
⏳ not built · 🚫 not possible on this platform, with the reason ·
n/a the verb does not apply here, with the reason.

---

## Level 1. Screen matrix: does each surface exist and can you reach it

This level is necessary and never sufficient. Reachable is not parity.

| Surface | Reachable from | Status | Tier | Evidence |
|---|---|---|---|---|
| [Home] | [launch] | | | |
| [Browse] | [nav rail] | | | |
| [Detail] | [any tile] | | | |
| [Search] | | | | |
| [Library] | | | | |
| [Settings] | | | | |
| [Player] | | | | |

---

## Level 2. Feature ledger: the buttons and behaviours inside each surface

<!-- Build this by reading the reference platform's view files (grep
     for Button, .contextMenu, .onTapGesture, menu items, toolbar
     items, keyboard shortcuts) and listing every one. A surface that
     exists and does nothing is worse than a missing one: it promises. -->

Enumerated from `[path/to/reference/Views/*]` on [YYYY-MM-DD].

### [Detail]

| [Reference platform] behaviour | [PLATFORM] | Tier | Note |
|---|---|---|---|
| [Play / Resume with position] | | | |
| [Favorite] | | | |
| [More Like This row opens a title] | | | |
| [Share] | | | |

### [Next surface]

| [Reference platform] behaviour | [PLATFORM] | Tier | Note |
|---|---|---|---|

Deliberate differences go here too, as n/a or 🚫 with the reason, in
both directions: what the port does that the reference does not, and
what it never will.

---

## Level 3. Owner feedback ledger

Each item comes from a person using the build. Number it, keep their
words, and treat it as binding until the row reads ✅ with device
evidence. This level supersedes anything above it that disagrees.

| # | Feedback (their words, abridged) | Status | Evidence |
|---|---|---|---|
| F1 | | | |

---

## Superseded assessments

<!-- When feedback proves an earlier tally wrong, do not delete it.
     Move it here with the date and one sentence on what it counted
     that it should not have. It is the record of the mistake. -->

---

## Fix log

| # | Date | What was wrong | Fix | Rows it closed |
|---|---|---|---|---|

Bring back the Level 3 table after the next time someone uses the build.
