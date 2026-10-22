---
name: values-based-feed-ranking
description: Use when building any algorithmic content surface — a feed, a discovery tab, a "for you" ranking, a multi-source merge — especially over a third-party social/content API. Carries the hybrid multi-source merge pattern (parallel fetch, silent-fail secondaries, dedup, trending score), the values-based ranking rebuild (honor the user's OWN moderation settings, personalize only from the user's own visible signals, weight conversation over virality, penalize reposts, show "why you're seeing this"), seen-item dedup with a session bypass, the flat-tabs IA lesson, and the never-recommended-always-findable data flag. Triggers on feed ranking, discovery feed, for-you, algorithm, multi-source merge, trending score, engagement ranking, recommendation surface, seen posts, moderation preferences, filter bubble.
---

# Values-Based Feed Ranking

Lessons from rebuilding a production discovery feed twice. The first
build merged three engagement-ranked global sources and sorted by
likes-per-hour — and produced a feed that was identical for every
user, dominated by whatever was viral network-wide, and structurally
aligned with rage-bait dynamics. The rebuild passes the
`learning-orientation-design` four-question check *as a ranking
function*, not just as a feature proposal. That is this skill's core
move: **the values check applies to algorithms, not only to UI.**

## 1. The hybrid multi-source merge (the mechanical layer)

- **Fetch N sources in parallel; the primary is load-bearing,
  secondaries fail silently** (`try?` on Swift, `.catch(() => null)`
  on web). One flaky third-party feed must never blank the surface.
- **Dedup by canonical item id** across sources before ranking.
- Wall-clock latency equals the slowest single source, not the sum —
  always fire concurrently.
- A serviceable default trending score is HN-style:
  `(likes − 1) / (hours + 2)^1.8`. Treat it as a starting point the
  values pass will then reshape — not the destination.
- **Content filtering happens at the merge step**, because
  third-party sources do not apply the moderation the platform's own
  personalized feed does. Filter label-carrying adult/graphic content
  during merge on every ambient surface; leave user-toggleable
  surfaces (search) to their toggle.

## 2. The values pass (what made the rebuild different)

Run the four questions against the *ranking function*:

1. **Honor the user's OWN moderation — never invent your own.** Fetch
   the user's existing preferences from the platform (muted words,
   per-label visibility, adult-content toggle, mutes/blocks) and
   apply them client-side. A hardcoded blocklist is your judgment;
   their settings are their agency. (This also surfaced a model bug:
   a viewer field named subtly differently from the API's — decode
   what the API actually sends, verified live.)
2. **Personalize only from the user's own visible signals** — their
   follow graph, who their follows know, hashtags from their own
   recent posts. No opaque model, nothing they can't inspect or
   change by acting in the app.
3. **Weight conversation over virality.** Replies and
   reply-to-like ratio dominate; questions get boosted; originals
   beat amplification; **reposts are penalized (×0.5)**; raw likes
   are de-emphasized. Ranking is an editorial act — decide what
   behavior you're rewarding, because you're rewarding something
   either way.
4. **Every ranked item explains itself.** A "why you're seeing this"
   chip ("From someone you follow", "Followed by N you know",
   "Matches your interest in #X", "Active conversation · N replies").
   If a reason can't be stated in one chip, the signal is too opaque
   to use.

Anti-pattern named plainly: **the generic firehose** — merging global
engagement-ranked sources and calling it "discover". Two accounts
seeing the same feed is the tell; no per-account blocking can outrun
a globally-ranked pool.

## 3. Seen-item dedup with a session bypass

- Filter already-seen items by simple id membership (a rolling
  window, e.g. 7 days, pruned on save) — not an engagement threshold;
  the clever version was specced and never missed.
- **Always offer the escape hatch**: "N posts already seen — show
  anyway" sets a session-level bypass flag. Filtering without a
  bypass reads as the app hiding things.
- Mark items seen from EVERY surface that displays them (feed,
  gallery, reader), and sync the seen set across devices through
  user-owned storage (the platform's own repo/record store or the
  per-ecosystem sync island) — ids only, union merge, debounced
  writes plus a flush on background.

## 4. IA lesson: flat tabs, not nested toggles

Ship the feed surface as **flat top-level tabs** (e.g. Following ·
Conversations · Trending), where Following is the user's follows in
plain chronological order — a distinct "catch up on your people" feed
that still honors their moderation — and the discovery tabs share one
pipeline differing only in base signal. A tab-inside-tab design
(Following/Discover + a sub-toggle) was built and then flattened:
the nested level was redundant the moment network-awareness became an
always-on ranking input.

## 5. Never recommended, always findable

Some items belong in the catalog but should never be CHOSEN for the
person (propaganda, a rights caveat, material that needs context a
one-line caption cannot give). Hiding them outright guts the archive;
promoting them is a recommendation you cannot stand behind. The answer
is a data flag, not a ranking weight:

- The pipeline sets it every build from sourced evidence (`noRecommend`
  plus a reason); never widen it on a bare keyword. Archive Watch
  Decision 149 narrowed "propaganda" from 200 tagged titles (Potemkin,
  Why We Fight) to 60 with evidence a reader can open.
- **Machine-chosen surfaces skip it**: feeds, heroes, shelves, related,
  channels, widgets, surprise picks, social posts.
- **Viewer-driven surfaces keep it**: search, browse filters,
  collections, Detail.
- Outbound broadcast (social, partner feeds) keeps its own stricter
  do-not-promote list on top (see `shared-data-plane-contract`).
- Rank in the pipeline once and store the why, so every platform shows
  the same order and the same reason (Decision 139).

## Cost honesty

The values pass costs a per-session preferences fetch and an
author-feed fetch to build the personal context, and the candidate
pool is smaller than a firehose (paginate to compensate). Pay it —
the alternative optimizes for exactly the dynamics the "why we build"
note exists to reject.
