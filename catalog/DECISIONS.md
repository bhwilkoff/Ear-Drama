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
`editorial/takedowns.json` (date and case number only, Decision 029) and takes effect at the next build; a complete notice removes without a record to open (Decision 029). Every new claim
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
| A general takedown naming no episodes | hides the whole series; the case is listed in `takedowns.json` (date and case number; the letter stays private, Decision 029) |
| 10+ live script renewals in a series | a series claim |
| CBS news broadcasts Sony scheduled | hidden; news is out of scope anyway |
| Music and variety shows built on popular songs | **hidden** (stricter than drama) |
| AFRS originals | kept as government work only when no commercial performer is credited |
| WWII and Cold War propaganda | never recommended, always findable (Archive Watch 149; `no_recommend`) |
| Racist caricature (Amos 'n' Andy, minstrel shows, Fu Manchu) | never recommended, always findable, on a source (013) |
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

## 010. A semicolon list of artists is credits, never one person

**Rule**: `enrich_db.parse_artists` splits Goldin's Artists string on top-level
semicolons first (when 2+ non-empty segments), then parses each segment as
before; the person id is the normal one for the name (`People.goldin`).

**Why**: Goldin types some cast lists with semicolons, and the comma-only
split made the whole list one person: 1,247 people rows with ';' in the name
(a whole cast under one name, shown in Search and as a person page).

**How to apply**: measured 2026-10-24 on the real database: people rows with
';' 1,247 to 7 (two are OTRR names, five are strings with an unbalanced quote
that cannot be split safely; counted as `goldin_compound_names_unparsed`),
people 53,925 to 53,101, episode credits 334,592 to 340,487. A ';' inside a
parenthesis is not a separator. Comma-only variants were measured (9 names)
and left alone.

## 011 — Story arcs come from what titles say, and any doubt leaves the episodes single
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

## 012 — Search finds only what Detail can show: transcripts past the gate, words without text
*Date: 2026-10-27*

Only a transcript that passes `transcript_gate.shown` is indexed: in the served
projection's `episodes_fts.transcript` column, and in the web projection's
`search/said/` files, which hold each transcript word's doc numbers and never
the text. A snippet is cut on the device from archive.org's own text at
`transcript_url`, verbatim. This narrows 008, which indexed every fetched
transcript.

**Why**: the 2026-10-27 brief asked that only transcripts above the gate be searchable
(Search by what is said and by air date). A search hit on a looped transcript would show a row whose text
Detail refuses, and a snippet from that text is exactly the garble the gate
exists to keep off screen. Shipping snippets instead of cutting them on the
device was measured and refused: one 80-character snippet per word per
transcript is 11 MB gzipped for the rarest words alone (those in at most 20 of
5,657 transcripts) and 30 MB for those in at most 110, against 4.7 MB for every
word's doc numbers.

**How to apply**: measured 2026-10-27 on the 2026-10-22 research database with
the transcripts-latest cache (5,657 shown of 5,889 fetched): the served
projection fell 59 KB compressed (32.55 to 32.49 MB) and the clean-only seed 3
KB (1.266 to 1.264 MB); the gate-open web projection gained `search/said/`
(91,535 words in 796 files, 12.8 MB raw, 4.7 MB gzip, the largest `co.json` at
387 KB raw, 144 KB gzip) and `search/dates/` (53 year files, the doc rows by air
date, for Search's dates). A word under three letters is not filed.

## 013 — Racist caricature is never recommended and always findable, on a source a reader can open
*Date: 2026-10-28*

`build_db.no_recommend_reason` sets `no_recommend` (the 006 mechanism) for three
kinds of evidence, in this order. A Nazi-state recording: the speech words now
include German compounds (Wahlkampfrede, Rundfunkansprache, Kundgebung), and a
title that opens with the speaker's full name in the German archive's form
("Adolf Hitler - Kulturtagung", "Adolf Hitler vor dem Reichstag"). A recording
whose archive.org item is in archive.org's own `deemphasize` collection. And
racist caricature, from `catalog/editorial/racist_caricature.json`: a series or
title pattern, each with a source that documents it as racial caricature
(Amos 'n' Andy, Beulah, Aunt Jemima, the minstrel show, the Mitchell Minstrels,
Fu Manchu); `not` exempts a program about the act with its reason. The reason
text names the source. Every surface that chooses for the listener already
skips the flag (contract §5 `recommendAnd`); Search, Browse and Detail keep
the episodes.

**Why**: the owner, 2026-10-28: *"If we don't yet have flags for offensive
materials we need to implement them. Archive watch has multiple different flags
for racist materials that allow them to be searched for but never recommended
on the surfaces we want users to leverage for discovery."* The flag existed
for Nazi speeches only, and that rule missed 87 of the regime's own recordings
because their titles name the speaker and the occasion, not a speech word.
archive.org's subject tags were measured and refused as evidence here: the 18
items tagged racism (11), stereotyping (4) or minstrels (3) are mostly programs ABOUT racism
(Pacifica reels, anti-apartheid journalism), and one "minstrels" tag sits on a
107-show variety collection. A guest spot where the Amos 'n' Andy act performs
in character is flagged with the show; an interview or history program about
it is not.

**How to apply**: measured 2026-10-28 on the local research database: 1,016
episodes flagged racist caricature (786 Amos and Andy Show, 89 The Shadow of
Fu Manchu, 59 Beulah, 20 Aunt Jemima, the rest guest spots and minstrel
episodes across 30 series), Nazi-state 97 to 184, 5 more on archive.org's
deemphasize alone; none lost its flag. Add a program with a source a reader can
open, never on a hunch or a bare keyword; exempt one in `not` with its reason.
Left for the owner: Charlie Chan; Frank Watanabe and the Honorable Archie (no
source found); The Goon Show's Fu Manchu parody (exempted); Jungle Jim's
wartime slurs in titles; coon songs and "darkies" in record titles; Blue Coal
Minstrels; Al Jolson's "Mammy".

## 014 — An id that leaves the catalog forwards, permanently: an alias by its recording, else a tombstone
*Date: 2026-10-28*

Every publish compares the new served projection with the one live on
`catalog-latest` (`catalog/tools/forwarding.py`, `build_projection.py
--previous`). Each id the live one served and the new one does not gets an
alias to the served episode now holding its default copy, matched by
archive.org item and file name, or a tombstone when no served episode holds
it. Aliases and tombstones are cumulative, chains collapse, an id served again
sheds both, and the build, the diff, and the publish lock each refuse what
breaks that (contract §3.5). Every client resolves through them in one place
and rewrites what it stored once.

**Why**: an episode id is the person's data, not ours: it sits in their
history, their place in an episode, their queue, their downloads, the rows
their other devices sync, and every link they shared. A parse fix changes ids
(C1, 2026-10-28: 984 served ids left when "43-11-21" stopped reading as
1921-03-11), and the `episode_aliases` table that was meant to catch this had
never been filled, so each fix would have silently broken those records. The
owner, 2026-10-28: *"Let's just get everything set up the way that we want it
to be. We don't have to worry about current users, but we do have to worry
about building for the future."* So this is the permanent mechanism, run on
every publish, not a one-off migration. The recording is the identity because
it is the one thing a parse fix does not change: a title guess would forward a
listener to a different broadcast, which is worse than a dead link. A
tombstone, unlike a missing id, tells a client the id is gone for good, so it
can drop it from a queue; an id a client merely does not know may come from a
newer catalog than the one it holds and is kept.

**How to apply**: measured on the C1 rebuild against the pre-fix rebuild (same
cache, PYTHONHASHSEED=0): 984 ids left, 899 aliased onto 895 episodes, 85
tombstoned (all now hidden under their corrected ids). A pipeline change that
moves ids needs nothing more: the next publish forwards them. Never hand-write
an alias; fix the parse and let the recording decide. Never reuse an id for a
different broadcast. A client rewrite keeps each row's own stamp and is never
uploaded as new, so a device on an older catalog is not overwritten by one on
a newer catalog. Series keys forward too (015).

## 015 — A series key that leaves forwards to the series holding more than half of its recordings, else a tombstone
*Date: 2026-10-28*

Every publish forwards series keys the way 014 forwards episode ids
(`forwarding.forward_series`, tables `series_key_aliases` and
`series_key_tombstones`, contract §3.5): a key the live projection served and
this one does not gets an alias to the served series now holding more than half
of the distinct recordings (archive.org item plus file) of every episode it
served, or a tombstone. Cumulative, chains collapse, a key served again sheds
both, the clean-only projection inherits them, the builder refuses a broken
forwarding, and `publish_diff.py` refuses a key that left with neither. Every
client resolves a key in the same one place as an episode id and rewrites the
follows it kept, once, by the newer stamp.

**Why**: a series key is the person's data too: their follows, the Worker's
follow rows, every series link they shared. 237 of the C1 rebuild's 899 episode
aliases changed series key, and 46 served keys left outright; without this,
each one is a follow that silently stops and a link that opens nothing. The
owner, 2026-10-28: *"Let's just get everything set up the way that we want it
to be. We don't have to worry about current users, but we do have to worry
about building for the future."* More than half, not a plurality: a follow is a
choice of one program, and a series that leaves by splitting ("Tube Talk" into
one series per month) has no single successor; forwarding it to the biggest
fragment would name a different program, which is worse than a dead follow.
The denominator is every recording the series served, so a series mostly taken
down is not forwarded on its remainder.

**How to apply**: measured on the same pair of builds as 014: 46 keys left, 20
aliased (each onto a series holding all of its recordings, the largest 139 of
139 onto Information Please), 26 tombstoned (24 with no recording served
anywhere; "Tube Talk" at most 4 of 26 in one series, "The Big Broadcast" 1 of
20). Any threshold above 15 % gives the same rows today; if a future parse
produces a borderline split, the rule stays at more than half and the split is
a tombstone. Downloads need no series rewrite: their series is read from the
episode id, which 014 forwards.

## 016 — A fact the source contradicts itself on is not shown; a name's digits are not a broadcast date

Q1 audit fixes (2026-10-29), each a builder rule with a fixture test.
(1) A date in a file name that is the item's own upload day (`otrt-9-25-21` on an item
uploaded 2021-09-25) is dropped, never read as 1921 (`otr_parse.is_upload_stamp`); a date
glued to more digits (`004-24-1-1437`, a Hijri year) is not a date. (2) `series - YYMMDD -
NNN - title` is its own family (F2d): F5 had read the YYMMDD as part of the series name and
dated the file by its number. (3) Two ids matched to one Wikidata person on a birth or death
date are one person in the served catalog (`build_projection.same_person`); a name-and-
occupation match alone never merges (Walter Brennan Jr.). (4) A length the file's size cannot
hold (under 8 kbps) is unmeasured: the same recording's derivative gives it, else it is
empty. (5) A copy over 2.5 times the median of three or more is a several-episode file and
is not listed as a copy. (6) A title naming another sponsor of its series shows no sponsor.
(7) A Goldin cast string with an unclosed parenthesis, a trailing `;` or a hedge
("possibly") is split per person, and an OTRR role that is the character the same person's
cast row names is dropped.

**Why**: each was a fact a listener can see and a reader can check: Escape's earliest
episode read 1921; Space Patrol ran 29 hr 46 min (archive.org's own record says 107,185.94 s
for a 4.1 MB file and 451.71 s for its Ogg); Jack Benny's "First show for Jell-O" named
General Tire; Johnny Dollar 1955-10-03 listed a 73-minute five-part file and two copies of
the 1955-08-29 episode; Bud Collyer was credited twice on 1,099 episodes. None is a rights
call and nothing is hidden: it is no longer asserted. Left as the source has them, reported
and not corrected: OTRRpedia's own names with a nickname in parentheses ("Richard (Dick)
Aurandt", 563 episodes; "Alan Reed (aka Teddy Bergman)", 481) are 980 of the 1,043 episodes
D1b counted as Goldin fragments; OTRRpedia's General Tire run (1934-04-06 to 1934-10-28)
overlaps Jell-O's start.

**How to apply**: measured against the main checkout's caches, served episodes 107,369 to
107,190 (179 fewer, 0.17 %; MAX_SHRINK is 2 %): 191 ids left, 12 appeared, 166 of the
departures are Johnny Dollar number-only episodes now filed under the date their file names
carry. 1,311 copies dropped as overlong, 21 impossible lengths removed, 11 upload-day dates
dropped, 51 fewer people, 63 episodes with a Goldin fragment credit down to 6.

## 017 — The picture that leads a show is the show's own, then its star, then who is heard most

*Date: 2026-10-29*

A series' picture (`series.picture`, `picture_kind`, `picture_source`; contract §3.3a) is,
in order: **show**, a file from the show's own record (its Wikidata item's image, logo, poster,
collage or related image; a Commons file whose Structured Data depicts the item; a file whose
own page lists the item's Commons category); **star**, a person the program's OTRRpedia record
marks (title role, Star, Host) heard on at least 3 and a tenth of its credited episodes, else
a regular whom a Wikipedia covers, scored share of credited episodes x `1 + ln(1 + Wikipedias)`;
**person**, the heard-most rule; else the typographic board. A show image needs a match on more
than the title (the item's years, or its description's, overlap ours ±2, or its broadcaster is
our network), an item its own description does not call a television program, a license class
a portrait is served under, a shorter side of 160 px, no television in its name or categories,
and no date of its own outside the run (±2 years of the earliest logged broadcast and our last
episode).

**Why**: the owner, 2026-10-29: *"images/graphics that show the full 'show' are better than
individual contributors. Images that show the star(s) are better than those that show folks that
are less recognizable."* An image is used when its own record carries the evidence (DECISIONS
055/069), and a title alone is no identity (`evidence-gated-catalog-curation` §7). archive.org
cover art is not a source: a sample of 60 shows found uploaded art on 26 items, whose only rights
statement is the uploader's license for the item (DECISIONS 002).

**How to apply**: `art_policy.show_served`, `series_identity`, `series_face`; harvest
`harvest_series_art.py` (`.cache/series_art/`); evidence tables from `enrich_series_art.py`, run
by `enrich_people_art.py`; guard `tests/test_projection_art.py`. MEASURED on the 2026-10-28
caches, 2,036 shows of 5+ episodes: before, 263 wore a person and 1,773 the board; after, 37
show, 261 star, 1 person, 1,737 board (all 10,641: 49 / 309 / 1 / 10,282). Of 251 identity-
checked matches a random 40 checked by eye held 1 wrong item (Twenty Questions, the TV program),
which the television rule now refuses; of the 55 show pictures first served, 1 was wrong (Hilltop House:
a Commons depicts statement on a 1914 photograph of the hotel), and the date rule now refuses it
with 5 more dated before their program (Pal as Lassie 1942, a 1928 Strange as It Seems strip,
George Raft's 1939 trailer, William Gargan 1933, Leon Janney as a child): 49 served. On 42 shows whose title-role
holder has a portrait, the heard-most rule and share x recognizability each pick the title role
32 times (raw sitelink counts: 28); the marks make the title role win, and the 25 shows that
gained a face had none before. Coverage is bounded by Wikidata: 268 of the 2,036 shows match an
item at all.


## 018 — A person is the picture of at most one show

*Date: 2026-10-29*

Of the shows that would be led by the same person's portrait (017's star and person kinds), they
keep one, by this order: a show whose title holds their full name (the Jack Benny Program); then a
marked role (the title role, Star, Host) in a show holding at least half as many of their credited
episodes as their biggest show; then the show with the most of their episodes; then the highest share;
then the series key. Every other show is decided again without
them (its next candidate, else the typographic card), and `series.star` follows. A show's own image is
never affected and never counts.

**Why**: the owner, 2026-10-29, to "one face per star": "Yes". William Conrad led both Gunsmoke
and Escape; 51 people led more than one show. The floor is there because a mark is a title role:
Jack Webb is the title role of Pete Kelly's Blues (7 episodes) and not marked in Dragnet (474), and
the plain "marked first" rule gave Webb to the 7.

**How to apply**: `art_policy.assign_faces`; guard: the contract query "a person's portrait leads at
most one show" (seen failing on the pre-rule projection: 51) and the unit cases in
`tests/test_projection_art.py`. MEASURED on the 2026-10-28 caches (10,641 shows): 82 shows changed their
star, 53 lost their picture to the card; by kind before and after: star 309 to 255 (with 019), person 1 to 1, show
49 to 49, none 10,282 to 10,336 (floor and own-work only). Webb leads Dragnet, Conrad Gunsmoke (Escape falls to Paul Frees),
Superman keeps Bud Collyer, The Whistler Marvin Miller, Perry Mason John Larkin. The named-show rule was
added after the first measure gave Jack Benny to The Grape Nuts Program (735 episodes, Host marked) and left the
Jack Benny Program (950) to Eddie Anderson; with it the star counts are star 258, person 1, show 49, none
10,333, Benny leads the Jack Benny Program, and The Grape Nuts Program falls to Eddie "Rochester" Anderson.
It also gives Mel Blanc the Mel Blanc Show, Dinah Shore her show, Walter Winchell, Frances Langford and
Charlie Ruggles theirs, and Boris Karloff the Karloff Collection (16 shows changed against the floor-only rule).


## 019 — An own-work license the picture's own date contradicts is not served

*Date: 2026-10-29*

A portrait (or a show image) whose file page gives the uploader's own license (`{{self|...}}`, PD-self,
PD-user, or a Creative Commons license with `source={{own}}`) is refused when the file's own date is
after the death of the person it is of (Wikidata's death; for a show image, the earliest death among
the people the program's record marks). A public-domain template on a scan the uploader calls their own
is not an own-work license and is unaffected.

**Why**: File:Kollmar.jpg led Boston Blackie: "a photograph I took of Richard Kollmar and his
fiancee", `{{self|cc-by-sa-4.0}}`, dated 2019; Kollmar died in 1971. An uploader's word is not
evidence (`evidence-gated-catalog-curation`), and here the word contradicts itself.

**How to apply**: `art_policy.implausible_own_work`, `enrich_people_art.own_work` (the `own_work`
column of `people_art` and `series_art`); guard: `retrace` in `tests/test_projection_art.py` (seen failing
on a projection built before the rule: it lists the removed files) and the unit cases. MEASURED: 177 of
3,875 person files and 39 of 288 show files are own work; 19 served portraits removed, none replaced, no
show image (2,174 to 2,155 portraits). Of five checked by eye, all five were period photographs no
uploader could have taken (Kollmar, Madge Evans and Billy Halop studio portraits, a Dick Elliott television
still, and Oliver Wakefield's file, a theatre programme page, not a portrait at all). Removed: Audrey Call,
Billy Halop, Dick Elliott, Don Albert, Eddie Arcaro, Gaylord Carter, Hugo Weisgall, Irve Tunick, Jack
Wilson, Joan Barton, Ken Carson, Madge Evans, Max Miller, Nathan Van Cleave, Norman Rose, Oliver Wakefield,
Richard Kollmar, Samson Raphaelson, Yoichi Hiraoka.


## 020 — A build's output never depends on the hash seed

*Date: 2026-10-30*

Two builds of one cache under different `PYTHONHASHSEED` values publish the same projection. Wherever
a set or a count's ties set an order a row can depend on (which spelling names a series alias, which
series key a Goldin record links through, the order of a series' networks), the order is sorted.

**Why**: CI pins `PYTHONHASHSEED=0`, which hid it; two local builds differed by about 400 credit rows
and 74 network rows (first run of `tools/check_build_determinism.py`, before the fix: 172 credit
rows, 49 episodes, 3 people and 4 series differed).

**How to apply**: `tools/check_build_determinism.py [seedA seedB]` runs the whole chain twice and compares
every table (about 20 minutes, so not in `run_all.sh`); run it after touching `build_db.py` or
`enrich_db.py`. Sorted: `build_db.build_registry` (names), `enrich_db.SeriesMap.by_dates`, the OTRR
program loop, a series' networks.


## 021 — A portrait under the size floor gives way to a larger file of the same person showing one face

*Date: 2026-10-30*

A person's portrait is still their own image (Wikidata P18) of the most permissive class, unless it fills
less than the largest window a client draws (`art_policy.LARGEST_SLOT`, 300: tvOS's show tile; `fill_px` is
the crop height every client's `windowFill` compares). Then a file of the same person that shows one face
and fills more is served, the one that fills most, an own image before a stand-in. A stand-in may be a file
whose Structured Data depicts the person, only when the detector read exactly one confident face on it, it
passes every other check `served` makes, and the person has a served own image. A group never replaces a
portrait, and nobody gains a face this way.

**Why**: the size floor (uniform-imagery-design §4) draws the title block under it, so the Jack Benny Program,
led by Jack Benny, drew "JB" on every tile: his own image, JackBenny1958Cropped.jpg, is 174 x 333 and its crop
147 px. NBC's 1938 photograph of him alone (1139 x 1479, a depicts file) fills 513. A depicts file was refused
because it is often a group (DECISIONS 069 in the app log); one face is the evidence that this one is not,
and the depicts statement is on the image's own record (owner 2026-10-21). Ranking by size alone was tried and
refused: it gave David Rose a photograph of him with three soldiers and Rod Cameron a theater program.

**How to apply**: `art_policy.pick`, `alternate`, `crop_rect`, `fill_px`, `face_count`; `people_art.faces`
(`enrich_people_art.py`); guard: `floor_misses` in `tests/test_projection_art.py` (seen failing on the
projection built before the rule: 12 people) and the fixture's controls. MEASURED on the 2026-10-29 caches:
12 of 2,155 portraits change, every one checked by eye a single, right person (Jack Benny, Gracie Allen,
Marian Jordan, Parkyakarkus, Jan Miner, Ona Munson, Charles Winninger, Bennett Cerf, Fay Wray, Ben Hecht,
George du Maurier, Gene Roddenberry). Led shows drawing the title block: at a 200 window 22 to 21, at 300
50 to 48 (the Jack Benny Program and Hilltop House). The rest have no larger file: 17 of the 22 at 200 would
fill if the clients' crop widened toward the largest square instead of the title block, a client rule.


## 022 — Display titles and names are derived from the data, and never reorder a series

*Date: 2026-10-30*

`episodes.title` and `series.name` are the display forms (`titles.display_title`, `display_name`); the
source's are kept in `raw_title` and `raw_name` where they differ, and search indexes both. Beyond the
2026-10-22 rules: a leading episode code (EP001, #257), a leading zero-padded number or run of numbers,
a duration (14m42s), a " - " part that is a code (32-22, xxxx) or a first part that is a lone number,
and the series' own name (two words or more, at the start before a separator or as a part) are stripped
where words remain. An all-capitals title takes the case the catalog's own mixed-case titles write each
word in (articles and short joining words lower), and a run-together word of ten letters or more is split
only when every piece is a word at least three titles spell on their own (three letters or more, a listed
two-letter word, never an acronym, never two short words in a row) and exactly one fewest-piece split exists.
A series whose order would change with a leading number dropped keeps the 2026-10-22 rules: with no date and
no number, "03 - Mrs. Hudson" is what lists it third. `sort_name` is the display name's key.

**Why**: the owner's catalog rule, no AI-written copy: a title is the source's words, so the rules only remove
and recase, and every word out is a word the raw title spelled. Upload habits put "EP001 TARZANSFIRSTBIRTHDAY",
"0005 - The Babe Ruth Collection - Harry The Hat - 32-22 - 14m42s" and "01 The Hobbit" on screen and at the
top of A to Z. A larger dictionary split real words ("BEAUTIES" to "Beau Ties", "CORSICAN" to "COR sic an",
"POSTTOASTIES" to "Post to as Ties"); each limit above is one of those refusals.

**How to apply**: `titles.py` (`Words` is built once per build from every title and name; no client
re-derives); `build_projection.py`; guards `tests/test_titles.py` (fixture vocabulary; four mutations seen
failing) and the contract checks in `tests/test_projection.py`. MEASURED on the 2026-10-29 caches: 3,125 of
107,190 served titles change beyond the 2026-10-22 rules (45 by a split), 902 of 10,641 series names, 41
series (794 episodes) keep the older rules for their order, and 116 all-capitals titles keep a long word
whole. Arcs: 451 to 455, the four new ones parts whose leading numbers had hidden a shared name ("Epilogue
Chapter 1, 2"). Known residue: a brand split on proven words ("MAYFIELD" to "May Field"), and a series named
for its work drops that name ("The Magic Flute - Mozart" to "Mozart").


## 023 — A display rule never deletes a letter, splits a spelled name, or drops a name said once

*Date: 2026-10-30*

Amends 022. On the iPad two Barbershop Quartet episodes read "ArbershopQuartet barbershopQuartet" and "Ouvenir
barbershopQuartet". The rules did not strip those letters: the archive.org files are named
`ArbershopQuartet_barbershopQuartet.mp3` and `Ouvenir_barbershopQuartet.mp3` (the item's own metadata title
reads "arbershop Quartet"), so the missing "B" and "S" are the source's and `raw_title` equals `title`. What the
rules owe the reader is only what the dictionary proves. Three changes: (1) a token with one lower-to-capital
hump is split when both halves (four letters or more) are words at least three titles spell on their own and
the whole is not spelled twice ("barbershopQuartet" waits for a third title to spell "barbershop"; "MacArthur"
stays whole); (2) a run-together split keeps joined any pieces a mixed-case title spells joined ("MAYFIELDCIGARETTES"
to "Mayfield Cigarettes", not "May Field Cigarettes"); (3) a series name is stripped from a title only when two
or more of that series' episodes carry it, so "The Magic Flute - Mozart" under the one-episode series "Magic
Flute" keeps its words.

**Why**: the owner's catalog rule, no invented words: a rule may remove and recase, and every word out is a word
the raw title spelled. "Mozart" lost the work; "May Field" split a name a title spells whole.

**How to apply**: `titles.py` (`Words.hump`, `Words._whole`, `Words.spelled`, `series_titles`); guard
`tests/test_titles.py` (five cases seen failing on the 022 code). MEASURED on the 2026-10-29 caches: 676 of
121,907 episode titles change from the 022 build (570 humps split, 106 series names kept) and 64 series names
(humps); no schema change, so no client change, and the apps see it with the next cache Release and catalog publish.


## 024 — Direction D's data: a genre from the records' own keywords, ranked voices, picture grades, and same-day as a query

*Date: 2026-10-30*

Four things direction D's design asked of the pipeline (`docs/research/design/directions/d/direction.md`, "Pipeline
work D needs"). (1) **A genre for a series no OTRRpedia label, RadioEchoes tag or LibriVox listing places**, only from
a word its own records carry: Wikidata's `genre` on an item matched on the years or the network, else the one genre
that more than half of the series' archive.org items name in their subject keywords or the genre tag of their default
copy's file (`genres.KEYWORD`, exact whole words; "drama" yields to a specific genre that also passes; two specific
genres, or none, leave it NULL). An item counts only when every served default copy in it belongs to the one series:
a day's broadcasts and a collector's compilation carry keywords for the item, not for any program in it (found by
looking: "NBC, WEAF, NY" read as a soap opera because its day-long item said so). A collection never counts
("audio_news" is where an uploader files everything that is not music: it put a Thanksgiving record show under
News). The source is stored: `series.genre_source` is `archive.org` or `wikidata:genre`. (2) **`voices`**, the 300 most
heard people, ranked by served episodes they are heard on (`art_policy.VOICE_ROLES`: on-air credits plus announcers
and commercial spokespeople; a writer or conductor is not a voice). (3) **`art.grade`**, `"k,o"` per picture, from
the luminance range of the picture inside the crop a slot shows (uniform-imagery-design section 2),
measured once (`measure_art_grade.py`, `.cache/art_grade.json`). (4) **`sameDay`** is not published: it is a
documented query (contract 3.3b).

**Why**: the owner's catalog rules (evidence or nothing; never a guess from a title) and the owner's picture rule
(2026-10-29: the pictures must read as one set). A genre only from the record, held to one program per item, loses
coverage and keeps the rule; a table of the other broadcasts that night costs 0.68 MB deflated for what an index
returns in 15 microseconds.

**How to apply**: `tools/enrich_genres.py` runs after `enrich_photo_archives.py` (the publish workflow does);
`build_projection.py` reads `series_genre`, `.cache/art_grade.json` (absent: no grades, every client takes the
identity) and writes `voices`; `build_web_projection.py` writes `index/voices.json` and the art arrays end with the
grade. Guards: `tests/test_genre_evidence.py`, `tests/test_projection.py` (voices, grade limits, same-day plan, each
with a broken control), `tests/test_web_projection.py`. MEASURED 2026-10-30 on the 2026-10-29 caches: of 8,519
served series with no genre, 1,543 get one (all `archive.org`; no unplaced series has a Wikidata genre) and 6,976
stay unassigned; of the 834 shows (five episodes or more) with none, 89 get one (47 drama, 14 science fiction, 13
mystery, 6 documentary, 5 comedy, 3 news, 1 serial), 745 stay on the neutral board; a version that let multi-series
items speak assigned 220 of the 834 and misread the day compilations, so the 131 it added are held back, not
guessed. Voices: 300 rows. Grades: 2,184 pictures measured, 1,461 graded (51 at the 1.6 cap), 723 the identity,
none unreadable. Size on the 2026-10-29 build: the app database 125,087,744 to 125,161,472 bytes (+74 KB) and its
download 25,433,689 to 25,463,104 (+29 KB, 0.12%); the web's `index/voices.json` 19.4 KB, 5.1 KB gzipped. A new
cache Release is needed for the grades (`art_grade.json` is a new harvest file); the genres and voices need none.


## 025 — Raw uploader text never reaches a display field: clean it from its source, compose it from data, or withhold it

*Date: 2026-10-31*

Audit: `audits/2026-10-31-display-text.md`. Owner, 2026-10-31: "I don't want raw text uploads to show at all. There is
no benefit to having raw text that is meaningless within the app ... Titles without context don't belong in the app ...
If it means writing with AI, based upon data, that is okay. The goal is to avoid AI writing titles that it doesn't know
(making them up)." Amends 022 and 023 (their protections stand: a rule removes and recases, never cuts a word) and the
"no AI-written copy" line (a title may be composed from the episode's own fields, never invented).

For every episode, in order: (1) the source's title, cleaned (`titles.py`, which now also drops rip tags, shelf and
track codes and doubled punctuation, and sets a title with no capital in the catalog's case); (2) a title composed from
data, "Series, April 26, 1952" (series name + air date) or "Series, episode 112" (series name + number), recorded with
the fields it used; (3) otherwise the episode is withheld from the apps. A series still named by an upload habit (a date,
an identifier, a file name, an uploader's grab bag, an item titled by an upload code) is withheld with its episodes.
Withheld rows stay in the research database untouched, with a reason code (`tools/display_text.py`; the build writes
`display_text.json` beside the projection and the counts into the projection's `meta.displayText`). Upstream, three
evidence rules (`tools/reattribute.py`, `build_db.improve_attribution`) put more of the catalog under a real name: a file
whose name BEGINS with a known program moves to it when the rest is a title that program has, or its own date is inside
the program's run (recorded in the episode's `identity.reattributed`); an unregistered series takes its name from the
item's own title when that spells the same letters, or from the ID3 album written on 80% of its files; a file's own ID3
title beats a title that only restates the file name. The parser also reads `YYYY MM DD` (spaces) as a date: it had read
"1959 10" as a series.

**Why**: the owner's catalog rule is no invented words, and her reading of it is that a meaningless raw string is worse
than a composed or absent one. The measured defects were uploader habits (297 series named for a date, 3,840 empty or
placeholder titles, 3,322 rip tags), not facts about the programs.

**How to apply**: a new display rule goes in `titles.py` with a fixture and a case seen failing; a new withhold reason in
`display_text.py` with a control; never read a file name, identifier or folder date into a display field. Guard:
`tests/test_display_text.py` (fixtures, and over `PROJECTION` the live artifact fails it: 297 date-named series).
`tests/test_reattribute.py`, `tests/test_titles.py`, `tests/test_otr_parse.py`. MEASURED on the 2026-10-29 caches, see the
audit for the table: series 10,641 to 8,740, episodes 107,190 to 103,027 (3.9%, so the publish needs a `shrink_reason`);
episode ids that changed are forwarded by recording (`forwarding.py`), no client change. A cache Release is not needed.


## 026 — Scope is drama and spoken story; a misspelled or numbered series is the program it spells, by evidence

*Date: 2026-10-31*

Amends 025 (P-7). Owner, 2026-10-31: "Drama and spoken story only." Keep radio drama, comedy, audio plays, readings,
serials, and the variety and news shows of radio's golden age; withhold university concerts, music sets and lecture
series, kept in the research database with a reason code. And: "Titles without context don't belong in the app ...
Never invent." Five rules, each only on evidence a reader can open:

1. **A title that is one word and a number** ("TopSecret15", "Hunting300") is a file name: composed from the series
   name and date or number, else the episode is withheld (`display_text.readable_title`).
2. **A series within two letters of one program** ("Top Sercet", "Yours Truly Johny Dollar") joins it
   (`reattribute.near_program`, `build_db.merge_near_names`) only when exactly one program is that near, the names are
   spelled with the same words (one joining word may differ: "Murder At Midnight"; "Lux Radio Theater - AU" is another
   production and stays), and the episodes agree: a title the program has, or every dated episode inside its run, a year
   either side. Recorded in the episode's `identity.reattributed`. "ABC Radio Workshop" is one letter from "CBS Radio
   Workshop" and stays: 1953 is outside its 1956-57 run.
3. **Numbered volumes** ("CBS Mystery Theater Fantasy Selection 1 to 8", "Reel 1, 2") that share a base name become one
   series (`reattribute.disc_groups`, `build_db.merge_disc_series`; LibriVox projects excluded, each is a work). A base
   that names a distribution service ("American Armed Forces Radio No 62", "AFRS V Disc 4") is no program and never
   becomes one: each file moves to the program its own name begins with (`stem_program(loose)`: the program's name leads
   the file name, hyphenated or behind a shelf code), and the rest of the disc is held back (`series_is_a_numbered_disc`).
   An undated volume file loses its bare number as identity (two volumes both have a number 1).
4. **An apostrophe** is restored only from a name a registry spells with it ("The Witch's Tale" for "The Witchs Tale",
   from the series' recorded names): `display_text.repair_apostrophe`; the same letters, one such spelling, never a guess.
   Also: an item title whose trailing parenthetical the series name carries on past ("Ray Bradbury: Bradbury Reads
   Bradbury (Listening Library, 1975)") names the series with the parenthetical dropped (62 series).
5. **Scope.** `tools/enrich_scope.py` (after `enrich_genres.py`) writes `series_scope(series_key, kind, reason, evidence,
   items)`; the build withholds the series as `out_of_scope_concert|lecture|music_set`. Never classified: a program a
   registry names (OTRR, RadioEchoes, the spine), a LibriVox project, a series with a genre label, a series half of whose
   items' own keywords name a spoken genre, a name with a dramatic word (reading, play, story ...), a series on
   `editorial/scope_review.json` (a reviewed keep list, each with a reason; none yet). Evidence: *concert*: concert or
   recital in the name; one performer on every file's ID3 artist with "live" in the name. *lecture*: lecture, symposium,
   colloquium or convocation in the name; or `content_kind = lecture` on 60% of the episodes (build_db's finding-aid
   speaker rule). *music set*: archive.org subject keywords (jazz, big band, bluegrass, opera ...) on 60% of the series'
   own items, or a band, orchestra or choir name with a music collection (`audio_music`, `78rpm`, `etree`); an item that
   feeds several series is a compilation and is never read. An episode whose own title is a V-Disc is a music record
   (`out_of_scope_music_record`).

**Why**: the owner's scope and no-invention rules. Every merge is a fact a reader can check in the dates or titles; none
is a likeness of a name. The 2026-10-31 live sample showed the same upload habit in four more shapes (a file name that
survived, a typo that made a second show, a disc number that made 93 shows, a garbled uploader name).

**How to apply**: a new scope word goes in `enrich_scope.py` with a fixture in `tests/test_scope.py` and a control; a
program wrongly caught goes on `editorial/scope_review.json` with its reason, never a looser rule. Guards:
`tests/test_scope.py`, `tests/test_reattribute.py`, `tests/test_display_text.py` (each seen failing on the 62e7d02 tools;
the projection guard fails on the live artifact with 37 one-word-and-number titles). MEASURED on the 2026-10-29 caches:
series 8,763 to 6,980 and episodes 103,077 to 96,397 (6.5%, so the publish needs a `shrink_reason`). Withheld, in
episodes: lecture 2,017, music set 667, concert 95, V-Disc records 487, numbered discs 3,404 (93 series, about 2,350
of them V-Discs), uploader grab bags 1,076 to 1,469. Merged: 34 misspelled series (452 files), 21 volume series
(274 files); 247 disc files moved to their programs by the loose rule (more by the dated rule once hyphenated stems parse); one-word-and-number titles 37 to 0; apostrophes restored on 40
names. Forwarding against the live projection: 7,670 episode ids left, 744 aliased, 6,926 tombstoned, none neither;
1,802 series keys left, 50 aliased, 1,752 tombstoned. Station slots: 0 changed against the live `stations.json`.
Known residue: "Science Fiction 1968" (OTRR names it, so the build does not call it a grab bag) keeps its name;
"Poetry and Modern Man" (a talk about poetry, kind lecture) and a DJ show that is unlisted music stay or go on the
data alone.


## 027 — Every string the apps render is audited, not every column we chose; the last pass undoes upload habits and adds no word

*Date: 2026-10-31*

Amends 025 and 026 (P-8). Owner, 2026-10-31: "I don't want raw text uploads to show at all ... Titles without context
don't belong in the app. If it means writing with AI, based upon data, that is okay." Never invent.

1. **The audit starts from the clients' rendering code**, not from the columns the pipeline picked: 31 fields in
   `audits/2026-10-31-display-fields.md`. P-6 and P-7 audited series names and episode titles only, so roles with broken
   encodings (202), recording identifiers shown as names, wiki markup in picture credits and 10,523 titles in uploader
   casing went unseen.
2. **`tools/polish.py` is the one last pass** (series names, titles, `aka`, sponsors, roles, characters, person names,
   recording labels), and `tools/field_defects.py` is the one classifier the build, the guard and the audit share.
   A text still carrying a hard defect after the pass is composed from data or withheld (`display_text.readable_title`,
   `series_withheld`), never shown.
3. **Apostrophes** are restored from a dictionary of unambiguous contractions (`Dont`, `Isnt`; `Lets` only as the first
   word, because it is a verb elsewhere) or from exactly one independent witness spelling (`episode_witnesses`), never
   from a guess ("Witchs" needs a source).
4. **`recordings.label`** (additive column, contract 3.2): an `OTRR_` identifier is the Old Time Radio Researchers; else
   the item's own title cleaned (organization before " - ", count and rip tags dropped, run-together words split, a
   shouted word set in case); NULL for an item that is a single broadcast or whose title restates one. Clients show the
   label, else "Recording N", never the identifier.
5. **Scope additions** (`enrich_scope.py`): a band remote ("Remote-HarryJames", "Band Remotes") is music; a run-together
   music-group name ("ArbershopQuartet barbershopQuartet") is music without keywords because a broken name has none to
   read. **Speeches stay.** The first P-8 pass withheld speeches and addresses (28 series); the owner ruled the same day
   "Keep them": historical speeches and wartime addresses (Churchill, FDR, Truman, Lindbergh, Nimitz, the Hitler
   speeches) are the spoken word of radio's golden age and are in scope. The rule was removed whole; no pass may
   withhold a series or episode for being a speech (stated in `enrich_scope.py`'s docstring). Nazi-state recordings keep
   `no_recommend` (never recommended, always findable).
6. **Pictures and plays**: credit lines lose wiki markup and links (`art_policy.clean_author`); a play's title loses
   cataloguer boilerplate and each author gets a `display` name.

**Why**: the owner's no-raw-uploads and no-invention rules; an audit that starts from the schema finds only what the
schema's author already looked at.

**How to apply**: a new displayed field goes in the inventory and in `field_defects.FIELDS`; a new habit gets a rule in
`polish.py` with a fixture and a control in `tests/test_display_fields.py`. The guard fails on the 2026-10-31 live
projection (about 30 classes of defect) and passes on the rebuild. MEASURED on the 2026-10-30 caches against the live
projection: episode titles changed 13,111 of 95,641, series names 1,496, series 6,980 to 6,767 (band
remotes 28, file-name and date fragments, run-together names), episodes 96,397 to 95,641 (-0.8%, inside the 2% floor, so
no `shrink_reason` is needed; if the merge guard is run against a fresher live count, use "P-8 scope: band
remotes, upload fragments, 2026-10-31"). Arcs 335 to 455 (`Ep01of18` now parses as a part). Station slots changed:
0 (`build_stations.py kept`). Two builds under different hash seeds publish identical tables. Episode ids are unchanged
by display text; forwarding is recomputed by the publish as usual. The publish workflow should also run
`PROJECTION=out/publish/ear-drama.sqlite python3 tests/test_display_fields.py` beside the other real-artifact tests
(a workflow edit, outside this change).

## 028 — A name an upload cut, numbered or strung together is its source's own words or withheld; one show under several names is folded only on evidence (P-9)

*Date: 2026-11-04*

Amends 025 to 027. Owner rulings stand: raw upload text never shows; a name comes from a source, cleaned residue or the
record's own data, never invented; no context means withheld, counted, kept in the research database; speeches stay.

1. **One pass, `display_text.clean_series_name`**, run in `build_projection.py` after `polish_name`. Classes: page or side
   fragment ("Superman page01", "Side 2"), cut-off tail (an unclosed bracket, a bare Part or Side; "On the Sunny Side" is
   whole), episode code ("- s01e01", "Deel18"), uploader initials, a glued count or month ("Jukebox31", "Dec18"), reel
   compilations (a reel word and dot-joined programs: one program keeps its name, several are withheld). Each removes words the
   uploader added and adds none. A residue under four letters or a numbered stub ("Vintage No 2") is withheld
   (`series_name_has_no_context`); the others carry `series_name_is_a_fragment`, `series_is_a_reel_compilation`,
   `series_name_joins_programs`.
2. **A leading number goes only as a track number** (`track_numbered`): the series is upload-named (a registry program may be
   really numbered: 33 Half Moon Street, 2000 Plus), three upload-named names within two of its number write the number the
   same way, and the next word is not a quantity ("100 Years").
3. **Same show, several names** (`merge_into`) folds series only on data: names differing by quotes or "&" for "and", keys
   differing by a leading track number, the same single air date, or fragments whose cleaned name is another fragment's or a
   registry program's name or alias. A LibriVox reading and a broadcast are different productions and are never folded. Episodes
   are read under the surviving key (a TEMP view over `episodes`), so the departed key forwards through `series_key_aliases`
   (forwarding.py) with no second mechanism.
4. **Left for the owner:** pairs with the same name and different key stems or dates (The Hobbit 01thehobbit and hobbit,
   Noel Coward Hay Fever 09a/09), and Christopher Marlowe's Faustus (1964 and 1970 productions, kept apart).
5. **Guards** in `tests/test_display_text.py`: fixtures for each class with its control, and over the real projection no name
   the pass would change, no run of track-numbered names, no show split by quotes, "&" or a track number, no title cut off
   mid-bracket.


## 029 — A complete notice removes on its own; the bar of "a claim a reader can open" is for what we hide unprompted
*Date: 2026-11-04*

A take-down notice with every element of 17 U.S.C. section 512(c)(3) removes the
recording without a record to open. `takedown/index.html` no longer asks for one.
"A claim a reader can open" (Decision 001, `evidence-gated-catalog-curation` rule 1)
stays the bar for what the pipeline hides on its own initiative.

**Why**: the owner, 2026-11-04, on Archive Watch's seven proposals: *"All of these
proposals seem incredibly reasonable."* and *"Let's keep personal details out of the
public repo."* Refusing a complete notice for want of extra evidence may cost the
safe harbor Decision 001 relies on.

**How to apply**:
- The public `editorial/takedowns.json` holds `{date, case, scope, key}` and never a
  claimant or a letter link. The requester's details sit in the Worker's D1 table
  `takedown_cases` (`worker/src/takedown.js`), erased three years after a case closes
  (hourly cron; privacy page says so). Old `claimant` / `letter_url` fields are not read.
- `.github/workflows/takedown-check.yml` runs `tools/takedown_cases.py judge` every six
  hours, then lists, records, and dispatches `catalog-publish.yml`. A complete notice
  removes unless the evidence contradicts it. Contradictions go to the owner as an issue
  to answer `remove` or `keep`: a claim naming only a word of a longer title; a recording
  old enough to have no recording right (pre-1926 in 2026) whose archive.org record shows
  no modern layer; a privacy request or incomplete notice. A record that could not be
  read contradicts nothing. A modern layer (a restoration or remaster, new narration, a
  music bed, a re-recording, a post-1971 date, read from archive.org's own record) removes
  even a word-only claim. No audio is decoded: the film-only signals were not ported.
- At most 5 automatic removals a run; the rest wait as holds, so a false sworn form
  cannot do much.
- One footer link, no highlight. The page also says what happens after a mistake and
  that repeat infringers lose the service.
- Nothing a requester wrote reaches a log, issue or the public list, links and the
  work's name included. `tests/test_takedown_check.py` plants a requester and fails if
  it appears; the same run with a leak in place is part of the test.

## 030 — A show's "about" is its Wikipedia article's lead, attributed; a matched script is a link out
*Date: 2026-11-09*

A series carries an `about` only when its English Wikipedia article is the one its
Wikidata match names and that article is about the radio program; the text is the
article's own lead, unchanged but for residue, with "Wikipedia", the article URL and
CC BY-SA 4.0 beside it. An episode whose broadcast matches a script carries a link to
that script's page at its host (`script_url`, `script_source`), whatever the script's
rights: we link out and neither host nor cast it (rights item 16 and Decision 068's
castable rule are unchanged).

**Why**: the owner, 2026-11-09: *"we need to significantly upgrade the individual show
pages with actual info for the show if possible. Most people will have no idea what the
shows are about and they will need an entry point to know whether or not they should
listen. ... ear dramas that have a recording and a script should allow for accessing the
script easily."* No AI copy and no raw upload text may show (AGENTS.md; display-text
ruling 2026-10-31), so the words must come from a human source a reader can open.
Wikipedia's leads are human-written, licensed for reuse with attribution, and already
reached through the Wikidata match the art and witnesses rely on. A wrong "about" is
worse than none: it tells a listener what a show is not.

**How to apply**:
- `tools/harvest_ext_wikipedia_about.py` (after `enrich_external.py`) reads the intro,
  page Wikidata id, short description and canonical URL of every matched article into
  `.cache/wikipedia/about.json`; it stores what Wikipedia said, never a verdict.
  `--report` prints each series' verdict with its evidence; spot-check it after a harvest.
- `tools/series_about.py` decides: the page's `wikibase_item` is the matched qid; the
  short description says radio and names no person, station, character, film, novel or
  franchise (with none, the first sentence names a radio program); the first two
  sentences say "radio". Prefer skipping: The Shadow's article (a fictional character)
  gives that series nothing. `enrich_external.py` writes the rows to `series_about`.
- Trim to whole paragraphs up to 900 characters, else whole sentences of the first;
  never mid-sentence. Strip only template residue (empty parentheses, IPA, citation
  marks). The projection copies `about_text`, `about_source`, `about_url`; the web series
  page carries `about: {text, source, url, license}`. Clients show the source and license
  with a link to the article wherever the text shows.
- Scripts: `episode_scripts.link_outs` uses Decision 068's match rules 1-3 (the research
  database's series + date match, the same date and series, agreeing titles) and drops
  only rule 4 (castable). A source needs a name in `SOURCE_NAME`; today that is the
  Generic Radio Workshop.
- One script id everywhere: `<source>:<the source's own id>` (`grw:<GRW id>`), published as
  `episodes.script_id` / web `scriptId` beside the link; a castable bundle id is the same id
  with a hyphen (`grw-A1` is `grw:A1`, `gut-49295` is `gut:49295`), so a reader resolves a
  GRW broadcast script and a stage play the same way (`episode_scripts.scheme_id`).
- Read-along groundwork (owner, 2026-11-09: *"We will be building a feature for plays,
  radio dramas, and ear dramas that will allow reading the script as the voice actors are
  saying those words ... anything we are building for the ability to read the scripts
  should be with this in mind."*): `build_db.py` keeps each matched script's parsed cues in
  the research database's `script_cues` (script id, order, line id, kind, speaker, spoken
  words), never published. Read-along then needs two things: a rights basis to SHOW the
  text (GRW's permission, or a script whose own record frees it; rights items 15/16
  unchanged until then), and cue-to-audio alignment. archive.org's automatic transcripts
  carry segment timings only: `{stem}.autogenerated.vtt` beside each `.autogenerated.txt`
  holds WebVTT cues of a line or two (measured 2026-11-09 on Cavalcade of America
  1951-12-11: 538 cues over 28 minutes, about 3 s each, no word times, no speakers). The
  pipeline caches only the `.txt` today, so alignment starts by caching the `.vtt` and
  matching cue words to transcript segments (fuzzy, in order), interpolating within a
  segment.
- A new `about.json` reaches the apps only through a new cache Release (README).

## 031 — One broadcast in one place, one show under one name, every copy labeled (P-10)
*Date: 2026-11-09*

Owner, 2026-11-09: *"we need to do significant audits on the database, as I see lots of things in recordings that
still are called 'Recording 2'. Also, I see a lot of things that seem disconnected from their shows."* Extends 028's
`merge_same_shows` (same TEMP-view mechanism, same forwarding; no second mechanism). Every fold is read from the data
and listed in `display_text.json` under `folded` (series with their rule, episodes) for review.

1. **A broadcast filed under two series is one episode** (`display_text.same_broadcasts`): the same full air date and
   the same title (six letters or more, not the series' own name, not composed from the date), when a series is
   upload-named, the two share an archive.org item, or the two series repeat each other at least 3 times. One
   coincidence between two registry programs ("A Christmas Carol" on December 24) is two productions. The survivor
   is the episode of the series with fewer partner series (a compilation repeats many shows), then a registry
   program, then the larger. The folded episode's copies become the survivor's further copies (after its own, the
   same file once) and its id forwards by recording (014). A copy the audit served as unclaimed never joins an
   episode served as clean (the clean-only public web would carry it under the clean line); the reverse is allowed,
   the stricter line holds. The rights vocabulary is untouched.
2. **A series that is one program joins it** (`display_text.same_program`, then `dissolve`), each rule needing every
   dated episode inside the program's run (a year either side) and the program to be the larger: *alias* (its name
   spells a registry alias: "FM&M"), *variant* (names differ by the, show, program, radio or hour: "Red Skelton"),
   *item* (half its episodes come from items titled with one registry program's name and collection words only,
   feeding no third series, three dated episodes, no production qualifier like "(South Africa)", and a season name or
   a shared broadcast: "Grape Nuts Program" is "Jack Benny - Single Episodes - 1932-1934"), *initials* ("GG Season
   05", with a shared broadcast and one program with those initials), *prefix* ("Escape the Birds", dated, the rest an
   episode's own title or a number), *shared* (an upload-named series more than half of whose dated broadcasts are
   one larger series'). A LibriVox project never folds. A moved episode on a date its new series holds, with a title
   one contains, is that broadcast. 028's fragment rule now also finds a registry program of the same cleaned name
   ("The Whistler reel" beside "The Whistler"). An arc whose first part was folded in keeps that part's whole id.
3. **Every copy of an episode with several has a label** (`polish.copy_labels`; contract 3.2): the source name when
   no other copy shares it, else the name or nothing and the first fact that differs, read from the copy's own row
   (variant, partial, clearly longer or shorter, a bitrate 25% apart, the item's upload year, the length in minutes),
   and "Best copy" / "Another copy" only when the rows hold nothing that differs. Never the identifier, never a word
   the row does not support; NULL stays a client fallback only.
4. **Raw title classes** (`display_text.episode_text`, `decide_episode`, `polish.polish_title`): a reel track tail
   (".t01": the reel's name is no title, unless it names the series and one title), "1942-xx-xx" (the year kept at
   the end), the series' initials with a date, date code, "#" or zero-padded number or SxxEyy ("OMB #001", "CGS #055";
   a bare number and a network stay), a trailing code a series' titles carry three times or more ("(DM)", "(JR)"; a
   network's stays), "xx" in front, "Production N" / "Tape N", recording-condition notes ("clipped"), "(Combines all
   dates)", a glued small word ("WithThe"), a series' one-word name plus s before a word ("Tarzans First Birthday": the
   series name is the witness), and a title that only repeats its series' name, composed from the date or number when
   the record has one (else the name is the work's title).

**Why**: the owner's two reports, measured on the live data (manifest 2026-11-08): the 1947-11-09 Home row showed
"Corner Drug Store" under Jack Benny and under "Grape Nuts Program" (735 OTRR Jack Benny singles named for a sponsor),
the same Chase and Sanborn broadcast in two series, a season-named series, and 21,974 copies that read "Recording N".
A person who taps a broadcast should land in its show; a fold on a likeness of names alone would be a guess, so each
rule names its evidence and a control proves its refusal.

**How to apply**: a new fold rule goes in `display_text.py` with a fixture and a control in
`tests/test_same_broadcast.py`; a wrong fold is fixed by tightening its evidence, never by a hand-written alias.
Guards over the real projection: no two series repeat each other's broadcasts 3 times or share an item, no multi-copy
episode has an unlabeled copy, no reel track tail, xx-date or recurring shelf code (seen failing on the unchanged
tools' dry-run projection: 21,974 bare copies, the Michael Fisher / baseball pairs, 271 reel tails, 5+ coded series).
MEASURED on the 2026-10-30 cache Release against the live projection (PYTHONHASHSEED 0 and 7 publish identical
tables): series 6,745 to 6,640, one-episode series 3,952 to 3,906 (two or fewer 4,542 to 4,496); episodes 95,587 to
91,301 (-4.5%, so the publish needs a `shrink_reason`, e.g. "P-10: duplicate broadcasts folded into their shows,
2026-11-09"): 4,042 duplicate broadcasts folded (every one aliased to the episode now holding its copy), 245 reel
tracks whose only title was the reel's name withheld (tombstoned); 97 series folded (66 by these rules: alias 3,
variant 32, item 3, initials 13, prefix 1, shared 14; merge_into 31), series keys 76 aliased, 29 tombstoned (series
of withheld reel tracks only). Copies with no label 21,974 to 0; copies sharing a label within an episode 14,771 to
1,701. Titles changed on episodes served before and after: 2,906 ("(DM)" 837 to 0, ".tNN" 271 to 0, xx-dates 132 to
4, series-initials prefixes 728 to 128 (the rest are networks and stations), titles that only repeat the series'
name 1,315 to 918 (no date or number), "clipped"/"xx"/"WithThe" 344 to 35).
**Left for the owner**: "The Shadow" is hidden by its series renewals, but its season uploads ("Season 11
(9-7-47 to 5-30-48)", 27 episodes) are served as their own series and "Season 17" joined "The Shadow Recreations" by
shared broadcasts: a rights question, not a display one. Two registry programs that are one show on air (The Chase
and Sanborn Hour and Edgar Bergen and Charlie McCarthy; The Fred Allen Show and Town Hall Tonight) keep both series;
their shared broadcasts fold.

## 032 — A rights hide follows the work; a grab bag is not a series; forwarding starts at launch (P-11)
*Date: 2026-11-09*

Owner, 2026-11-09: *"Obviously The Shadow is still under copyright. All seasons should be hidden if the copyright is
still active. Obviously, a grab bag of uploads isn't a series. ... These are incredibly easy questions to answer using
our own rules for how we build."* and *"I'm really not sure what you are saying is 'passing' when we are attempting to
find issues in the database."* And on forwarding: *"the app has not launched yet. Forwarding content only matters if
folks are going to look for it at the old location ... We are trying to get everything set up correctly the first time
and not create a bunch of cruft for things that were set up incorrectly the first time and had to be fixed before
launch."* A data audit: each rule below was found in the real build and is measured there.

1. **A rights hide follows the work** (`tools/same_work.py`, `build_db.follow_work`). The audit judged an episode by
   its series key, so a work hidden on a claim (005's named claimant, a series takedown, 10+ live script renewals, a
   renewed script) stayed served wherever an upload named it otherwise. After the first pass, an episode it served is
   the work's when: *broadcast*, it has the same full air date and title (six letters or more, a trailing
   parenthetical note dropped) as an episode hidden on such a claim, and its series is upload-named, shares the item,
   carries an item whose own name names the work, or repeats the work's broadcasts 3 times (031's test); it takes that
   episode's verdict. *series*, an upload-named series more than half of whose dated episodes (3 at least) are the
   work's broadcasts goes whole ("Season 11 (9-7-47 to 5-30-48)"). *named*, an upload-named series carrying the work's
   name as whole words, not followed by "of"/"'s" ("The Shadow of a Gunman" is another work), with one of the work's
   titles, a date inside its run, or the "Work - Title" form, goes whole ("20 best The Shadow", "The Shadow
   Recreations": a re-performance of a claimed script is the claimed work). Those are judged by the same audit under
   the work's key, the same claims file, no second list; the evidence leads with `same_work`. A post-1972 date or a
   foreign producer describes one production and is not followed. LibriVox never.
2. **A grab bag is not a series** (`reattribute.grab_bag`, `build_db.merge_grab_bags`). A series is an uploader's or
   collection's mixed bag when (*item*) it is named for an archive.org item whose files the build filed under 5+
   series and two registry programs lead its file names or it holds under half the item; (*programs*) three registry
   programs lead a quarter of its file names; (*collection*) its name is a collection's ("Christmas Shows",
   "Singles and Doubles", "Golden Age", "... Radio News", "Weekend", "Audition Recordings", a year or decades of news,
   an uploader's news files) with two programs leading its files or a mixed item. A registry program whose logs span 40
   years at most is judged by its name only; LibriVox never; "Mixed Doubles", "The Wizard of Odds" and "NBC News" are
   programs. Each bag file moves to the program its name begins with when the program has its title or its date is in
   the run (stem_program, gated); an undated piece of a bag that made its own series by its file name ("Richard Nixon"
   from "Grandpa's Old Time Radio Stories") and an undated bag file a registry program took by its name alone with no
   title it has ("Bob Hope #3") go back to the bag. The projection passes the bag through P-10 as a donor only (it
   never survives a fold, never receives one, never joins or is joined by same_program, dissolve or merge_into), then
   withholds what is left (`series_is_a_grab_bag`; the old `series_is_an_uploaders_grab_bag` now donates the same way).
   A dated piece with its own name stays a single (display-text ruling: a name and a date are context).
3. **Rights, two holes the audit sample found** (`audit_audio_rights.foreign_series`, `modern_date`). A one-recording
   series whose item title or file name names a non-US broadcaster is non-US (006): the old two-recording floor let
   every single BBC upload through. A BBC programme id in brackets ("[b007k108]") names a BBC broadcast; a series whose
   files mostly carry one is a BBC programme (Jack Benny's one Radio 4 Extra copy is not most of Jack Benny). An
   undated episode whose own file name or title carries a full date after 1972-02-15 outside brackets is post-1972
   ("BBC R4 SD - A Slow Air ... 20121201", "The-Big-Broadcast-2003-05-04"); a bracketed or parenthesized date is a note
   on the copy ("[Rpt 2019-01-07]", "(Recreation 4-22-2016)") and is never read.
4. **Forwarding starts at launch** (`forwarding.LAUNCHED`). Until it holds the launch date, every build publishes the
   alias and tombstone tables empty and carries nothing from the live projection; pre-launch fixes leave no trail, and
   `publish_diff.py` reports ids that left instead of refusing them. The mechanism and its fixtures stay (its tests run
   it as it will run after launch); set `LAUNCHED` in the commit that launches.

**Why**: the owner's own rules already answered each case: a claim a reader can open hides the work (005), not a
series key; a series is a program, and an uploader's bag is an upload habit (025-028); no context means withheld
(display-text ruling 2026-10-31); non-US and post-1972 productions are hidden (006). The guards that passed before
checked shapes; none asked whether a hidden work was served under another name.

**How to apply**: a new follow rule goes in `same_work.py` with a fixture and a control in `tests/test_same_work.py`; a
bag rule in `reattribute.grab_bag` with both in `tests/test_grab_bag.py`; a program wrongly caught is fixed by
tightening the evidence, never by a list of keys. Guards over the real build (in the publish's contract step): no
served episode is the broadcast of an episode hidden on a claim that follows the work; no served upload-named series
carries a hidden work's name with its titles or dates; no served series is a grab bag by the same test run on what is
served. Each failed on the unchanged tools' dry-run artifacts (94 broadcast leaks, 5+ named series, 57 bags).
MEASURED on the catalog-2026-11-09 Release against the live projection (PYTHONHASHSEED 0, `catalog_dryrun.sh
--with-suites` green): series 6,640 to 5,594, one-episode series 3,906 to 3,393, episodes 91,301 to 82,177 (-10.0%, so
the publish needs a `shrink_reason`, e.g. "P-11: rights follow the work, grab bags withheld, BBC and post-1972 holes
closed, 2026-11-09"). Of the 9,350 ids that left (226 appeared): 5,325 withheld with their bag and 2,489 more that were bag pieces or
name-only bag files returned to it (204 bags: item 149, collection 50, programs 5; 389 bag files moved to the program
their name begins with), 519 bag broadcasts folded into the show that holds them, 709 non-US (BBC 963 of the 1,128
newly flagged series, CBC 122, a BBC programme id 25), 175 post-1972 by a date in their own name, 131 the hidden work's
(research database: 139 episodes, broadcast 102, series 16, named 21; The Shadow's three season uploads, "The Shadow
Recreations", "20 best The Shadow", "Types of The Shadow Radio", the Ghost of Radio singles, "House of Horror"; a Vic
and Sade, a Fibber McGee renewed script, a Free Company renewed script, a Nick Carter). Forwarding: 0 aliases and 0
tombstones published (the live projection carried 9,059 aliases, 13,234 tombstones, 334 series aliases and 3,740 series
tombstones). Home day files for ten dates: 1,290 rows to 1,183, every bag row gone. **Left** (each a class the next
pass can take by rule): undated episodes of real shows in mixed uploads with no date or known title go with the bag
("W B Hickok", 240 Wild Bill Hickok files; "Deadline - Have Gun Will Travel", whose program name trails); Dutch, Japanese
and other non-English productions with no broadcaster named (archive.org's `language` field is on few of them, and
006's non-US rule would also take the Hitler speeches 027 keeps: an owner question); Australian "(AU)"/"Aus NN" uploads;
baseball-game collections ("Classic Baseball on the Radio"), which hold games, not programs; one show under two names
where the spelling differs and nothing is dated ("Big Jon and Sparky"/"Sparkie", "Tarzan"/"Tarzan (all runs)");
fragments of one broadcast filed as singles ("Orson Welles War of the Worlds 10 30" beside the Mercury Theatre);
modern recordings whose date is not a full date ("Oct 2019"); raw titles inside real shows ("Blackstonethe Magic
Detective48 10 03 01The Ghost...").

## 033 — What P-11 left open, each decided by a rule we already had (P-12)
*Date: 2026-11-09*

Owner, 2026-11-09: *"These are incredibly easy questions to answer using our own rules for how we build."* and *"I'm
really not sure what you are saying is 'passing' when we are attempting to find issues in the database."* Nothing here
is a new policy: each class is a case of 006 (non-US and post-1972 productions hidden; music shows hidden), 026 (scope
is drama and spoken story; a misspelled or abbreviated series is the program it spells, by evidence), 027 (speeches
stay), 025 (raw upload text never shows: clean it from its source, compose it from data, or withhold it) or 031 (one
broadcast in one place, one show under one name). The app has not launched, so nothing changed here forwards (032).

1. **A show under its initials or another spelling is that show** (026; `reattribute.renamed_program`,
   `build_db.merge_renamed`, before the grab-bag pass). An upload-named series whose words are a registry program's
   with some written as initials ("W B Hickok" for Wild Bill Hickok) or spelled another way (each word the same or two
   letters apart with the same first letter, one extra word inside the name at most: "Big Jon And Sparky", "Big John
   and Little Sparky" for Big Jon and Sparkie) joins it when exactly one program is that near and its episodes agree:
   three of its titles the program has (all, when it has fewer), read as `stem_program` reads a file's rest, or every
   date inside the run. Undated is fine: an episode needs no date. The renamed key then resolves to the program, so a
   file named "W B Hickok 051 - The Treasure of Old Number" moves too. A name with a production label ("Lux Radio
   Theater - AU") or an extra word at an edge ("Suspense AFRS") is another production; two programs that near
   ("Bill Stern Colgate Sports Newsreel": two registry spellings) leave it where it is.
2. **Non-US productions** (006), three new readings of the record: a production label the series' name, most of its
   items' titles, or the episode's own title or file name carries ("- AU", "(Aus)", "Aus 62", "[SA]", "(South
   Africa)", "(UK)", "Sth African"); "Aussie" or an Australian station and city in item metadata; OTRRpedia's own
   broadcast history when every run is outside the USA. **Language**: archive.org's `language` field (now kept in the
   research database's `items.language`), else the title's script or two function words of another language and none
   of English, else a Dutch or German genre word on the item ("hoorspel", "luisterboek", "Hörspiel"). Exempt exactly
   what 027 keeps, a speech or address (speech, address, Rede, Ansprache, Kundgebung, Aufruf, Parteitag, Kongress,
   discours, discurso ... in the title, file or item record), plus a US government service broadcasting abroad and
   any program OTRRpedia gives a US run (an item's language field does not outweigh a registry's broadcast history:
   Hello Americans, the Newly Discovered Casebook). LibriVox is not read: its recordings are PD-dedicated readings,
   not another country's broadcasts, and 006's concern is a claim regime, not a language.
3. **Out of scope** (026; `enrich_scope.py`, kind `sports`, reason `out_of_scope_sports`): a series whose name names a
   game broadcast (a sport and a broadcast word, a sporting event's own name, a sport alone), whoever names it; a sports
   talk or story show ("Bill Stern Sports Newsreel", "Red Grange Football Show") names no game and stays. A series
   named for V-Discs is music records. A registry program with no story label (OTRRpedia or RadioEchoes) whose own
   items' subject keywords name music on 60% of its episodes is a music show (006's stricter music rule, from data).
4. **One show under two names** (026, 031). Spelling variants are rule 1. A collection's note on a program's name is
   the program ("Tarzan (all runs)", "(Combines all dates)": `display_text.COLLECTION_NOTE`, then 028's fragment fold).
   Two registry programs that are one star's show under a sponsor- or title-era name fold (`display_text.same_show`)
   when both map to the same OTRRpedia programs and nothing else (`registry_alias`), or they share an OTRRpedia program
   and more than half of the smaller one's dated episodes aired on nights the larger holds (`same_nights`); every date
   inside the larger's run. The nights are the stronger evidence. Their same-night episodes are one broadcast (the
   catalog's identity for a dated episode is the series and the night).
5. **A piece of one broadcast filed as a single** (031; `display_text.contained_broadcasts`): an upload-named series'
   episode on the same full date as exactly one registry program's episode, one title's letters (eight or more)
   inside the other's, folds in as a copy. A title composed from the series' name is read as that name. Rights as in
   031: an unclaimed copy never joins a clean episode ("AFRS Thanksgiving Special" stays apart from Command
   Performance's).
6. **A year after 1972 dates a production after 1972** (006; `audit_audio_rights.modern_date(partial=True)`): a month
   and year ("Oct 2019"), a day, month and year with a four-digit year ("14.03.1988"), a year on its own ("Upstate
   Radio Theatre 2004"), a bracket holding only a date ("(2015)", "[2013]"), in the episode's own title or file name,
   folders included ("Bob & Ray - 1973 - WOR, NY - Skits/..."); an upload-named series' own name ("WKBW 1973 Halloween
   Show"). Not read: a bracket with words ("[Rpt BBC7 3 Oct 2003]", "(Recreation 4-22-2016)"), a bracketed date beside
   the copy's own date (032's rebroadcast note), a year the series' own name carries ("2000 Plus"), a title that is
   only a year ("1984"); a dated episode reads only a bracketed year or a month-year. A two-digit year read as 1920-26
   in an item uploaded within three years after the 20YY reading is this century's ("The Glowing Dial" 2020).
7. **Raw titles** (025): lower-to-capital humps split when every piece is a word the catalog spells (two letters at
   least: "Meta Tells Ted Off", "No Leg To Stand On"); markup ("<strong>"); a leading shelf or date code, alone or
   behind the series' name ("67073A-", "460507 249.5", "Crime Does Not Pay-500529-34-"); a collector's credit ("Tom C.
   Miller Collection"), a bracketed note ("(Radio Comedy)"), a network or station alone ("NBC", "WOR, NY") or "Xx"
   where a title should be; the uploader's signature ("D.D.Teoli Jr. A.C") on a title as on a name; a series name's sort
   letter ("zSherlock Holmes"), trailing date code ("Big City Nights 30 10 13") or leading two-letter code ("Rc
   Superman": no context, withheld). A title an upload cut off is restored from a witness of the same episode already
   harvested (OTRR, GOLDINdex, Haendiges, Wikipedia) that begins with every letter of it; with none, a title ending on
   a dangling small word is composed or withheld. "The Silver Clippe" is rule 5: the same day's "Menace to the Silver
   Clipper".
8. **Grab bags are judged on what is served** (032; `build_projection.served_bags`): a series left a bag once rules
   above withhold its other files is withheld as a bag, by the same test the publish's guard runs.

**Why**: the owner's rules already decided each case; P-11 listed them as open. A guard that passes only proves the
shapes it checks, so each new guard asks whether the build serves something a rule withholds.

**How to apply**: a new reading goes beside its rule (`audit_audio_rights.py`, `enrich_scope.py`, `reattribute.py`,
`display_text.py`) with a fixture and a control in `tests/test_p12_audit.py`. A wrong catch is fixed by tightening the
evidence, never by a list of keys. Guards over the real build (`tests/test_p12_audit.py`, in the publish's contract
step): no served episode in another language (speeches and US-run programs kept); no served episode or series with a
production label; no served undated episode with a year after 1972; no served series naming a game broadcast or
V-Discs; no served upload-named series that is one program under its initials or spelling; no two served registry
series that are one show; no piece of one broadcast served as a single. Each failed on the P-11 dry-run artifacts of
the unchanged tools (1,334 other-language episodes, 418 labeled series and episodes, 577 modern undated episodes, 14
game or V-Disc series, 2 spelled series, 4 same-show pairs, 98 broadcast pieces).
MEASURED on the catalog-2026-11-09 Release against the P-11 build (PYTHONHASHSEED 0, `catalog_dryrun.sh --with-suites`
green): series 5,594 to 4,954, one-episode series 3,393 to 2,986, episodes 82,177 to 75,057 (-8.7%, so the publish
needs a `shrink_reason`, e.g. "P-12: non-US and modern productions, game broadcasts and music shows withheld; shows
under other names joined, 2026-11-09"). Newly hidden by source, in research-database episodes: OTRRpedia runs only
outside the USA 952, archive.org language 569, the title's words 755, a Dutch or German genre word 1,163, a label on
the series or its items 415, a label on the episode 105, a year after 1972 in the episode's own name 532 to 2,235, in
an upload-named series' name 31; non-US broadcasters named in item metadata 8,228 to 9,833. Scope: 20 game-broadcast
series (1,705 episodes withheld), 8 music shows and 7 V-Disc series (music withheld 733 to 1,227). Joined to their
program: by initials 338 episodes (W B Hickok 220 into Wild Bill Hickok, V Point 98, AFRS P 20), by spelling 330
(Great Gildersleeves 102, Big Jon And Sparky 96, Martin Lewis Show 34, Grand Old Opry 31, Top Sercet 15, Dick Tracey 12,
Big John and Little Sparky 11 ...). One show under two names: Chase and Sanborn Program into Edgar Bergen and Charlie
McCarthy, Hour of Smiles and Town Hall Tonight into The Fred Allen Show, The New Adventures of Sherlock Holmes into
The Newly Discovered Casebook of Sherlock Holmes (the larger keeps its name), Stars in the Air into Screen Guild
Theater, Adventures of Babe Ruth into Babe Ruth Collection; name folds (merge_into, "Tarzan (all runs)") 23 to 65;
the 1947-11-09 Home row now lists Bergen once. Titles restored from witnesses 91. Home day files for ten dates: 1,175
rows to 1,147. **Left, each by a rule**: undated parts ("War of the Worlds Part 1-4") have no night to fold on (031);
"Bill Stern Colgate Sports Newsreel" is near two registry spellings (026: exactly one); humps whose pieces the catalog
never spells ("JrsSecret") stay (023); a production no record dates or labels (NPR's 1981 Star Wars) is not knowable
from the record (001: not knowing is not a claim); "AFRS Thanksgiving Special" stays beside Command Performance's
episode (031: an unclaimed copy never joins a clean one); speeches in other languages (027) and LibriVox readings in
other languages (PD-dedicated, not another country's broadcast) stay.

## 034 — A fold keeps the program's own title, and the key follows the name; a dry run checks only its own build
*Date: 2026-11-09*

Amends 028, 031 and 033's folds. Nothing here is a new policy: 025 (a display name is the source's own words) and 026
(a series is the program it spells), applied to the one choice every fold makes.

1. **The surviving name is the program's own title, by evidence** (`display_text.name_survivors`, run on every fold
   path: `merge_into`, `same_program`, `same_show`, `dissolve`, after the folds are decided and before composed titles
   are written). In each group (a survivor and every series folded into it) the name kept is, in order: the one the
   most program sources write, OTRRpedia, RadioGOLDINdex, and Wikipedia/Wikidata counted as one encyclopedia
   (`program_witnesses`: `series_map`, `goldin_records`, `series_wikidata`; the group's witnesses pooled, since it is
   one show); then the one that is not upload-shaped (`upload_shaped`: Collection, Singles, a trailing Project, Reel,
   Season/Volume/Part N, an episode count; or a sponsor's name when another is not); then a registry program's over an
   upload-named series'; then the larger. The same name either way keeps the survivor's key ("Tarzan (all runs)"). The
   key follows the chosen name; episode ids do not change. `display_text.json` lists each change under
   `folded.named` with its reason.
2. **A show still under an upload-shaped name takes the one program name its sources write**
   (`display_text.witness_name`): exactly one name that is not upload-shaped, among the witnesses for it and every
   series folded into it; two names, or none, and the name stands. Listed under `folded.titled`.
3. **A dry run starts from an empty workdir** (`tools/catalog_dryrun.py`): a reused `--workdir` is emptied first, and
   each step prints the build it checks (the restored Release, the projection's hash, write time, whether this run
   wrote it, and its `generatedAt`). A reused workdir let the suites step (which runs before the build) read the
   previous run's `out/publish`, so its guards checked stale data.

**Why**: P-12 folded The New Adventures of Sherlock Holmes (the Rathbone/Bruce program's title, written by OTRRpedia,
GOLDINdex and Wikipedia) into "The Newly Discovered Casebook of Sherlock Holmes" and Adventures of Babe Ruth into
"Babe Ruth Collection" because the larger series' key and name survived. Size says which upload held more files, not
what the program was called. A guard that checks stale artifacts proves nothing about the build it reports on.

**How to apply**: a new fold path returns its {old: new} map and goes through `name_survivors`; never pick a survivor
by size alone. A wrong name is fixed by the evidence (a witness, an upload-shaped word), never by a list of keys.
Guard over the real build (`tests/test_p12_audit.py`, in the publish's contract step): no served series' name is
upload-shaped where a program source names its show (seen failing on the unchanged tools' dry-run artifacts of
catalog-2026-11-09: "Babe Ruth Collection" with "Adventures of Babe Ruth"/"Babe Ruth", "Boris Karloff Collection" with
"Boris Karloff Show"). 032's grab-bag guard reads a file led by a program the build folded into a series as that
series' own (`display_text.json` `merged`): renamed, the Sherlock group's "Sherlock Holmes ..." files had read as
another program's and flagged it a bag. MEASURED on the catalog-2026-11-09 Release (PYTHONHASHSEED 0): series 4,954 and episodes
75,057 unchanged, no episode id changed; names changed: The Newly Discovered Casebook of Sherlock Holmes (449 episodes)
is The New Adventures of Sherlock Holmes, Babe Ruth Collection (19) is Adventures of Babe Ruth, Beyond Teaching
Series (14) is Beyond Teaching, Commercials (126) is Radio Commercials (each by witness), Boris Karloff Collection (10)
is Boris Karloff Show; 9 composed titles follow their series' new name. The Fred Allen Show, Edgar Bergen and Charlie
McCarthy and Screen Guild Theater keep their names (the most witnessed). **Left**: the Casebook series is the build's
home for OTRRpedia's umbrella program "Sherlock Holmes" (8101), so the New Adventures group still carries every
Sherlock Holmes production it held (a 1934 Richard Gordon broadcast among them): which production an episode is
belongs to the fold rules (031, 033), not to the name.
