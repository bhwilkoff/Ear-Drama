---
name: ten-foot-detail-design
description: The reusable design of a Detail/hero page and its neighbours (Series, Search) on a ten-foot TV screen, distilled from building the same patterns twice — Roku (SceneGraph) then Android TV (Compose) — where they came out identical because they are platform-agnostic. Covers the ambient-blur backdrop that never crops a poster, the category eyebrow that states the kind once, the meta line (canonical genres, a vote-floored rating), episode-name derivation and monogram placeholders, true-count-not-render-cap, empty/error states as doors, the one-lit-thing focus rule, and the discipline that a binding design doc beats a backlog note. Triggers on TV Detail screen, hero, backdrop, poster crop, series screen, season chips, episode list, ten-foot UI, search count, empty state.
---

# Ten-foot Detail design (platform-agnostic)

These patterns were built on Roku in SceneGraph, then applied to Android TV in
Compose during a "apply what you learned across platforms" pass — and they came
out the same both times, because none of them is about a framework. They are
about a person sitting ten feet from a repertory catalog of archival film with
inconsistent artwork. When you build a Detail, Series, or Search surface on any
TV runtime (Roku, Android TV, tvOS, web-TV), cite these and let the platform
supply the widgets.

Design each surface so it "reads like a first-party app on THIS platform, not a
database browser." That single ship-gate question drove every rule below.

## 1. The backdrop is a scene, and a poster is never cropped into it

The hero band is wide (~2.4–3.2:1). Your art is not: catalog backdrops are 16:9
and, for the large majority of a real archive, there is no backdrop at all —
only a 2:3 poster. Crop-filling a 2:3 poster into a wide band shows a pixelated
horizontal slice of its middle. That is the single most common "the background
looks terrible" report, and it appeared identically on Fire TV, Roku, and phone.

The fix has two layers:

- **A soft ambient base, always.** Draw the source image at a genuinely small
  decode and scale it up to fill the whole band — the bilinear upscale IS the
  blur, so there are no crop edges and no visible pixels; it becomes a wash of
  the film's own colour. On a platform with a real blur (Compose `Modifier.blur`
  on API 31+) add it; the small decode carries the rest. **Key trap:** image
  caches are keyed by URL, so a node asking for a tiny decode of a URL that is
  drawn large elsewhere gets the big cached bitmap — give the blur its own
  smaller URL (tmdb `w92`, commons `?width=120`, amazon `_SX120`), not just a
  small requested size.
- **A sharp layer ONLY when a true 16:9 backdrop exists.** Backdrops are
  composed wide and crop cleanly; show them sharp as the hero. A poster is never
  the sharp background — it is the inset, shown WHOLE at its own aspect (fit,
  not crop), and its colour lives in the blur behind it.

Then a **scrim whose weight is conditional**: light over a vivid backdrop (keep
it cinematic), heavier over a poster blur (push it back so the copy wins). And
draw the fitted poster/copy ABOVE the scrim — these scrims end fully opaque at
the bottom, so anything under one loses its lower third.

With no image at all, show a category-accent field, never a stretched poster or
an empty box.

## 2. The category eyebrow states the kind ONCE

Put the content kind — humanized, never the raw slug (`feature-film` →
"Feature Film", `tv-series` → "Classic TV", `tv-special` → "Television") — as a
small tracked-caps eyebrow in its category accent above the title. Because the
eyebrow says it, the **meta line below never repeats it**. Ship a single
`kindLabel()`/`KindLabel()` table shared by every surface so Home, Detail,
Series and Search read identically.

## 3. The meta line: year, genres, a rating that earned it

Meta = year · runtime · **up to two CANONICAL genres** · a rating star — never
the kind (the eyebrow owns that). Two data traps that produced visible defects:

- **Genre fields mix canonical Title-Case genres with lowercase descriptor
  tags** ("Drama|comedy drama|romantic comedy|comedy of remarriage"). The raw
  first-two read "Drama · comedy drama" — a duplicate in two cases. Keep only
  Title-Case entries; drop the lowercase descriptors.
- **A rating needs a vote floor.** Show the star only past ~100 votes; a 9.8
  from six people is noise. This means carrying the vote count on the model, not
  just the rating — a field that is easy to forget to decode.

## 4. Series is a scene, not the phone screen scaled

A TV series page is the Detail page's shape, not a centered poster card under a
back-arrow app bar (that is a phone surface; do not ship it at ten feet). Same
hero (§1), same eyebrow (§2), a meta line of year range · "N of M episodes" ·
seasons · "Aired on <network>", favorite + share for the whole series (stored
under a stable `series:<id>` key so it agrees across your platforms), the full
overview (focusable so the list can scroll it into view, never cut), then:

- **Season chips that SELECT ON FOCUS** — no extra Select press (the first-party
  TV idiom). "More Episodes" for an unnumbered group beside numbered seasons;
  plain "Episodes" when it is the only group ("Unsorted" is a system word, not a
  shelf word).
- **Episode rows** with a 16:9 still or a **monogram plate** (a single initial —
  never the title repeated in truncated caps, which says the same thing twice
  beside the label), an `S1 · E3` number, the episode name, a two-line blurb,
  and a resume bar.
- A **"N of M episodes available"** footer when you hold only part of a canonical
  run — it sets the expectation that the library grows.

**Episode-name derivation.** Archival episode uploads frequently carry the
SERIES title verbatim, so a season reads as the same line repeated. When the
episode title equals the series title, derive the name from the archive id
(`13_demon_street_fever_1959` → "Fever"): drop the leading tokens the series
title accounts for and a trailing 4-digit year, Title-Case the rest, fall back
to the original title if nothing survives. Diacritics matter — fold them so a
title is not "also known as" its own accented self.

## 5. A count states matches, not the render cap

A results count must be the TRUE match total, not the number of rows you chose
to render. "300 titles match" when the query actually matched 8,990 (the 300
was the render cap) under-sells the catalog, where Browse honestly shows its
full total. Compute the count separately (a cheap `COUNT(*)`), thousands-grouped,
with correct singular/plural agreement — build a small `plural(n, noun)` helper
rather than hand-writing `+ "s"` at each call site (that is where "1 playlists"
comes from). When a facet chip narrows the view, show the narrowed subset count.

## 6. Empty and error states are doors, not dead ends

A search miss shows "Nothing matches X" AND the browse doors (genres, decades,
Surprise) beneath it — one press from a shelf. A film that cannot load shows a
plain banner ("This copy would not play — it may have been moved or restricted")
and returns cleanly. Reserve gold-plating for states a real user can reach: a
fabricated deep-link id that paints a degraded page is not user-reachable, so
note it and move on rather than building for it.

Note a layout trap: a helper that centers a message by filling its whole box
(the common `Message` component) leaves zero height for the doors below it — use
a plain top-aligned line when something must follow it.

## 7. One lit thing, and read the screen adversarially

Exactly one element is focus-lit at a time; a second ring is always a bug (a
list keeping focus on its last item after focus left the list is the usual
cause). Focus is invisible to a screenshot and misleads in both directions — a
rendered control can be unreachable, and a "broken" one can be working — so
verify where a navigation LANDS, by the app's own focus trace, not by pixels.
When you do read a screenshot, list what is WRONG in it before you say anything
is right, and zoom before filing an artwork complaint as a UI defect.

## 8. A binding design doc beats a backlog note

Keep these rules in a binding `TV-DESIGN.md` / `ROKU-DESIGN.md` and cite the
section in each change. When a STATE/NEXT note tells you to build something the
binding doc (or a sourced platform rule) forbids — the classic case is
cross-device sign-in on a platform whose certification prohibits off-device
auth — the doc wins. Re-read the doc BEFORE building from a note, not after.

## See also

- `smart-tv-platform-expansion` — the ten-foot focus contract and the runtime map
- `roku-brightscript-app` / `androidtv-compose-focus` — the platform mechanics
  that render these patterns
- `mobile-first-density-design` — the six-level type scale and no-tinted-boxes
  discipline these inherit
- `binding-design-doc-discipline` — how a TV-DESIGN.md stays load-bearing
- `image-cdn-discipline` — the per-source URL size levers the ambient blur relies on
