# Radio catalog — decisions

Append-only, lead-with-WHY (the Archive Watch format). This pipeline will move to
Ear Drama's own repository when it is created; these entries move with it.

## 001 — Unclaimed broadcasts are kept and removed on request; nothing is kept on a paid licence
*Date: 2026-10-17*

A pre-1972 radio recording with no claim a reader can open — no Copyright Office
schedule, no named claimant with a source, no take-down, no renewed script or
adapted film, not post-1972, not of non-US origin — is `keep_unclaimed`: shown,
and hidden the moment a claim appears. No recording is kept on a SoundExchange
statutory licence or any other paid licence.

**Why**: the owner, 2026-10-17: *"I like the idea of moving to a 'take down
request' model for this, but a licensed model at $1000 per year is definitely not
in keeping with our regular process."* Federal law protects nearly every pre-1972
recording until 2067 (17 U.S.C. §1401), so "public domain by age" frees almost no
radio drama; but §1401(f)(5) denies statutory damages and fees to an owner who
filed no schedule, and §1401(f)(3) applies the DMCA safe harbor — the reason
archive.org and RadioEchoes run on notice and takedown
(`docs/research/02-rights.md` §12).

**How to apply**: never label `keep_unclaimed` "public domain" in any client —
its rights line says no claim is known and that it is removed on request
(Archive Watch Decision 153's lesson). A take-down goes in
`editorial/takedowns.json` and takes effect at the next build. Every new claim
source becomes a hide bucket that runs BEFORE the rescues, with a test and a
control. Register a DMCA agent before launch.

## 002 — An uploader's licence tag neither admits nor hides a recording
*Date: 2026-10-17*

The archive.org `licenseurl` on an OTR item is recorded as provenance and plays
no part in the rights state. OTRR's CC BY-NC-ND sets are kept like any unclaimed
recording, and OTRR is credited (the licence's attribution term; the app is
noncommercial and makes no derivative copy — loudness gain is applied at
playback).

**Why**: measured 2026-10-17, ~1,000 OTR items carry CC BY-NC-ND/ND tags and
~1,490 PD marks on 1940s network broadcasts that uploaders could not own
(02-rights §8). As a rescue they are an uploader's word (Archive Watch Decision
140); as a hide they would remove OTRR's sets, the best-dated copies in the
corpus, on a claim over the compilation that the app already honors. This
departs from 02-rights §10's proposed `rec_uploader_cannot_license` hide, which
was written before Decision 001.

## 003 — The radio app is its own app, not a section of Archive Watch
*Date: 2026-10-19*

Ear Drama ships as a separate app with its own repository, bundle ids
and store listings. This catalog pipeline moves there when that repository is
created.

**Why**: the owner, 2026-10-19: *"It is definitely a separate app."* (Answering
RESEARCH.md §7 Q2.) App Store guideline 4.3(a) ("Don't create multiple Bundle
IDs of the same app") is answered by the app's different content and audio-first
design, which the research (`docs/research/04`, `05`) documents.

**How to apply**: nothing here imports Archive Watch code at runtime; the one
file this pipeline reads from Archive Watch (`shared/editorial/cce_renewals.json`)
is copied into the new repository when it moves. Cross-links to Archive Watch
films (RESEARCH §6) are links between two apps, by archive.org id.

## 004 — An unregistered network script follows the recording: kept while unclaimed
*Date: 2026-10-22*

A script with no registration, renewal, or sourced claim does not hide its
episode; the episode takes the recording layer's state. A script registered and
renewed (the CCE drama renewals, 679 of them radio) still hides it as
`work_script_claim`.

**Why**: the owner answered RESEARCH §7 Q4 on 2026-10-22 with the take-down
model rather than "protected: hide". Treating every unregistered script as
protected would remove most network drama on a claim nobody has made, while the
real script risk is the registered and renewed kind (*Lone Ranger*, 1984).

**How to apply**: the CCE renewals must be wired into the audit before any
old-time radio item is published (README: "not yet wired in"), with a test and
a control. A registration found later is a new hide bucket, never a list of ids.

## 005 — A named, sourced claimant hides a series; a sales listing alone does not
*Date: 2026-10-22*

A series hides when a claim a reader can open names it (The Shadow and Condé
Nast, The Lone Ranger, the Lum and Abner takedowns). A licensee selling the
series on CDs is not, by itself, a claim.

**Why**: the owner chose this for Q5 on 2026-10-22 over "hide anything sold" and
"keep until a takedown". It is the rule the audit already applies; a sales
catalog says what someone sells, not what they own.

**How to apply**: `rec_rights_holder_claim` needs a source on every row; a new
claimant enters through `editorial/audio_claims.json` with its evidence link.

## 006 — The remaining buckets, with a stricter rule for music
*Date: 2026-10-22*

These settle Q6-Q9 and 02-rights §11 items 5-10:

| Bucket | Rule |
|---|---|
| Non-US productions | hidden unless licensed |
| Post-1972 series (CBS Radio Mystery Theater) | hidden unless licensed |
| A general takedown naming no episodes | hides the whole series; the letter is kept in `takedowns.json` |
| 10+ live script renewals in a series | a series claim |
| CBS news broadcasts Sony scheduled | hidden; news is out of scope anyway |
| Music and variety shows built on popular songs | **hidden** (stricter than drama) |
| AFRS originals | kept as government work only when no commercial performer is credited |
| WWII and Cold War propaganda | never recommended, always findable (Archive Watch 149; `no_recommend`) |
| Noncommercial-use notices ($50 each) | not filed |

**Why**: the owner accepted the defaults on 2026-10-22, "but stricter music".
Song copyrights are the live risk in a variety hour: the music publishers are
active, and their works are registered, so a hidden variety show costs little
drama and removes the claim most likely to be made.

**How to apply**: music and variety need a `content_kind` from data (archive.org
subjects, log genres, Goldin's program type), never from a model's reading of a
title; a comedy-variety show whose songs are incidental stays with drama only
when its data says so. The AFRS rule reads the credits table. Each row above is
a bucket with a paired test and a broken control in `tests/test_audio_rights.py`.

## 007 — The default copy is the domestic network broadcast, commercials included
*Date: 2026-10-22*

When a domestic network copy and an AFRS disc of one broadcast both survive, the
domestic copy plays by default and the AFRS disc is a version a listener can
pick, even when the disc sounds better.

**Why**: the owner chose R5 for Q9 on 2026-10-22. The sponsor and the pitch are
the era's history (R8), and the domestic copy is what people heard that night.

**How to apply** (amended the same day, tick 8): `build_db.order_recordings` sorts
a complete copy before a partial one (under 60% of the median length), then the
domestic broadcast before an AFRS, AFRTS, or rehearsal variant, then OTRR's copy,
then the measured bitrate; never the format label. Completeness comes before kind
because a seven-minute fragment of the domestic broadcast is not the broadcast as
aired; the first wording here put kind first, which the test's control now refuses.

## 008 — Transcripts: archive.org serves the text; search indexes every one, without positions
*Date: 2026-10-22*

The projection indexes every fetched transcript in `episodes_fts` and sets
`has_transcript` (and `transcript_url`, archive.org's own `.autogenerated.txt`)
only where `transcript_gate.shown` passes; the text itself is never in a file
we publish to clients. `episodes_fts` is `detail=column`.

**Why**: DECISIONS 058 says always searchable, shown only past the gate. A
browser can fetch archive.org's text directly (measured 2026-10-22: `*` CORS on
the 302 and the storage node's 200, preflight allowed), so re-hosting about 181
MB of text would add a copy that can drift and buys nothing. Token positions
would have cost 8.6 KB compressed per transcript (about 78 MB, three times the
projection); `detail=column` costs 2.1 KB and keeps every query the clients
make (quoted prefix terms, column filters); only phrase and NEAR queries lose.

**How to apply**: the gate is re-run on the cached text at build time, so the
cache's stored verdict is evidence, not the decision. A transcript of a copy
that is no longer the default is neither indexed nor shown. A phrase search
feature would need positions back, measured against the size budget first.

## 009 — Genre stations: the genre's broadcasts in the order they aired, one published clock
*Date: 2026-10-24*

A genre station (R10, Decisions 058 and 068) is a published schedule in
`stations.json`: the genre's served, recommendable, complete episodes, 5 to 90
minutes, back to back on one UTC clock, in the order they first aired, each
build keeping every published slot and appending four days ahead. No episode
repeats in the window, and a series waits for six others before it airs again.

**Why**: everyone tuned to a station must hear the same episode at the same
moment (AGENTS.md: publish a computed value, never a seeded shuffle), and the
owner rules out AI-written lists, so the order has to be a fact of the data.
Broadcast order is one: a station walks its genre's surviving radio as it aired,
which mixes series the way a real evening did. Measured 2026-10-24 on the
2026-10-22 projection: eight stations, 1,905 slots for four days, 23 to 73
series per station in a window (drama spans 1936 to 1939 in four days, so a
pass through a genre takes months). With a three-slot wait, drama cycled four
1936 series for hours; six gives 23 series in the same window. A complete
default copy only: a partial one is a broadcast as it was not aired.

**How to apply**: never rebuild a schedule from scratch over a published one;
a change to the order rule applies to the slots appended after the kept ones.
A pass over a series the wait skipped is lost for that cycle, not deferred
(the file carries no cursor). A station that cannot fill three days without a
repeat fails the build rather than repeat.

## 010 — Story arcs come from what titles say, and any doubt leaves the episodes single
*Date: 2026-10-24*

A story arc (contract §3.3, `arcs` and `arc_parts`; `tools/arcs.py`) is the
parts of one serial story, in order. It is derived only from titled parts in
one series ("The Molly K Matter - Ep 3", "Space Station of Danger, Part 2",
"Chapter 4"), and kept only when the parts run 1 to n with no gap and no part
twice, n is at least 2 and no more than a stated "of N", and the dates, where
known, rise with the part, neighbors at most 45 days apart. A bare "Episode 7",
or the series' own name and a number, numbers a series, not a story. Same-titled
dated episodes without a part number are not arcs.

**Why**: Decision 067 plays a serial to its arc's end and stops, so an arc
decides what plays without being asked. A wrong arc plays the wrong thing on
its own; a missing arc only falls back to the rule that stood before (one
episode, then the queue). Measured 2026-10-24 on the 121,907-episode served
build: 1,988 candidate stories, 480 arcs over 3,886 episodes in 238 series
(Johnny Dollar's 1955-56 five-part stories make 49); 330 refused for a lost
part, 23 for a part twice (The Molly K Matter's "Ep 5" and "pt5"), 2 for parts
against the calendar. A gap is refused, not cut short: playing parts 1 and 2 and
then offering the next story would skip a part 4 that survives.

**How to apply**: loosen a rule only with a measurement of what it adds and a
sample read against the episodes. The web serves an arc only whole (a part the
gate holds back would be skipped), so its counts are smaller (198 arcs on the
clean-only web). `next_arc` is the series' following arc whose first part is
recommendable (`recommendAnd`: the offer chooses for the listener); parts inside
an arc play regardless, since the listener chose the story. No source marks a
commercial's start and end yet, so there are no chapters (R8); see contract §3.2a.
