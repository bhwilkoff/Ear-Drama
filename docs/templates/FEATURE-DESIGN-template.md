# [APP NAME] [FEATURE]: Feature Design (BINDING)

<!-- SEED TEMPLATE. Author as docs/[FEATURE].md (for example
     CAPTIONS.md, SHAREPLAY.md, LINK-SHARING.md, PULSE.md) when one
     feature cuts across every platform AND what it can do differs by
     OS version or hardware. Platform DESIGN docs say how a platform
     looks; this doc says what one feature IS on every platform. Read
     `binding-design-doc-discipline` (doc-layer parity) and
     `cross-platform-parity-discipline` (capability tiers) first.
     Replace every [BRACKET]; delete these comments as you go. -->

**Binding.** Quote this document before changing any [FEATURE] path on
any platform. Every cell below is measured, not asserted, and the
audit named in §6 re-derives it.

Where a platform DESIGN doc and this doc disagree about [FEATURE], this
doc wins on what the feature does; the platform doc wins on how it
looks.

I want [one sentence: what a person gets from this feature, on any
device they own].

<!-- Anchor: the decision, bug or measurement that made this doc
     necessary. Archive Watch wrote CAPTIONS.md after caption behaviour
     came to differ across six OS versions and four delivery paths, and
     no single platform doc could hold that. -->

---

## §1. What [FEATURE] is

[Two or three sentences. Name the modes if there are several, and give
each a binding name. A surface may not invent a new phrase for one of
them.]

| Mode | Binding name | What the person gets |
|---|---|---|
| [A] | [name] | |
| [B] | [name] | |

---

## §2. The capability matrix (OS × platform)

<!-- Rows = platform and OS version. Columns = modes or tiers. Every
     cell is ✅ / 🚫 / ⏳ with a reason. A capability the device can
     never have is 🚫 here and omitted from the app; one it could have
     and currently lacks is shown in the app with one sentence. -->

| Platform / OS | [Mode A] | [Mode B] | Why |
|---|---|---|---|
| iOS / iPadOS [NN] | | | |
| iOS / iPadOS [NN+1] | | | |
| macOS [NN] | | | |
| tvOS [NN] | | | |
| Android phone | | | |
| Android TV / Fire TV | | | |
| Web | | | |

Measured [YYYY-MM-DD] by `tools/audit_[feature].py` (§6).

---

## §3. Which path a person gets, and when it is decided

<!-- The decision tree: given this device, this OS, this item, which
     path runs. Say WHEN the choice is locked in (at item build, at
     session start), because that decides what can change later. -->

---

## §4. Rules (binding)

4.1 [Rule.] **Why:** [the incident or measurement]. **Owner:**
[dated quote, if the rule came from one].

4.2 [Rule.]

---

## §5. Requirements checklist for a new platform

Run this before [FEATURE] ships on any platform not yet in §2.

1. [ ] Which modes can this hardware and OS ever support? Record the
   🚫 reasons in §2.
2. [ ] Which entitlements, permissions or store declarations does it
   need?
3. [ ] Is the shared logic (Core, the pipeline) already consumed, or
   does this platform need a mirror? If a mirror, add a parity guard.
4. [ ] Which states does a person see when a capability is missing but
   could be granted?
5. [ ] Add the platform's row to §2 and its cell to PARITY.md in the
   same change.
6. [ ] Stamp any new rule into every platform DESIGN doc the same day.

---

## §6. Audit and tests

| Tool | What it proves | Negative control |
|---|---|---|
| `tools/audit_[feature].py` | Re-derives §2 from the real published data or builds | |
| `tools/test_[feature]_parity.py` | Every platform's copy of the rule matches | A one-sided change must fail |

---

## §7. Out of scope

| Idea | Why not | Date |
|---|---|---|

Bring back §2 re-measured whenever a platform or an OS version changes.
